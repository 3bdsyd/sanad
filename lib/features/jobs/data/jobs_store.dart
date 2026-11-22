import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/job.dart';
import '../domain/job_filters.dart';
import '../domain/job_geography.dart';
import 'api_client.dart';
import '../../../core/push_notifications.dart';
import '../../../core/network_client.dart';
import 'demo_jobs.dart';
import '../../platform/data/platform_store.dart';
import '../../platform/data/review_moments.dart';
import '../../platform/domain/platform_models.dart'
    show object, objects, textOf, PlatformFailure;

export 'api_client.dart' show JobField, JobsException, RemoteNotice;

class JobsStore extends ChangeNotifier {
  JobsStore._(this._preferences, this._client, this._baseOverride);
  final String? _baseOverride;
  // Product scope: browsing, local saves and anonymous publishing only.
  // Account workflows are excluded from this release, including when a stale
  // build configuration supplies ACCOUNT_PLATFORM=true.
  static const _accountFeatures = false;
  @visibleForTesting
  static bool? accountFeaturesOverride;
  bool get accountsEnabled => accountFeaturesOverride ?? _accountFeatures;
  late final platform = PlatformStore(
    base: apiBase,
    client: _client,
    requiresAccount: accountsEnabled,
  );
  String? _loadedMember;
  void _accountChanged() {
    final id = platform.user?.id;
    if (id != _loadedMember) {
      _loadedMember = id;
      if (id != null) {
        unawaited(
          Future.wait([
            platform.load('/me/favorites'),
            platform.load('/me'),
            platform.load('/me/favorite-ids'),
            platform.load('/me/jobs'),
            platform.load('/me/saved-searches'),
            platform.load('/me/notifications'),
            platform.load('/me/saved-search-matches'),
          ]).catchError((Object _) => <Map<String, dynamic>>[]),
        );
      }
      if (_pushToken != null && id != null) {
        unawaited(
          platform
              .registerPush(
                _pushToken!,
                defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android',
              )
              .catchError((Object _) {}),
        );
      }
    }
    if (accountsEnabled) _readAccountSnapshots();
    _notify();
  }

  void _readAccountSnapshots() {
    savedSearches.clear();
    _matchedJobs.clear();
    _newMatchIds.clear();
    for (final row in objects(
      platform.snapshot('/me/saved-searches')['data'],
    )) {
      final f = object(row['filters']);
      savedSearches.add({
        ...row,
        'query': textOf(row['query']),
        'filters': f,
        'key': jsonEncode({'query': textOf(row['query']), 'filters': f}),
      });
    }
    for (final row in objects(
      platform.snapshot('/me/saved-search-matches')['data'],
    )) {
      final job = Job.fromApi(row);
      _matchedJobs[job.id] = job;
      if (row['is_new'] == true) _newMatchIds.add(job.id);
      if (row['announced'] == true) _announcedMatchIds.add(job.id);
    }
    notices = objects(
      platform.snapshot('/me/notifications')['data'],
    ).map(RemoteNotice.fromJson).toList();
    noticesUnread =
        (object(platform.snapshot('/me/notifications')['meta'])['unread_count']
                as num?)
            ?.toInt() ??
        notices.where((n) => !n.read).length;
    if (!platform.signedIn) {
      _readUpdates.clear();
      _announcedMatchIds.clear();
      _matchWatermarks.clear();
      _matchKnown.clear();
    }
  }

  static const _configuredBase = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://admin.jobsnad.com',
  );
  static const _liveBase = 'https://admin.jobsnad.com';
  static const _secureStorage = FlutterSecureStorage();
  final SharedPreferences _preferences;
  final http.Client _client;
  String? _pushToken;
  late final push = PushNotifications(
    registerToken: (token) async {
      if (isDemo) return;
      await _ensureDevice();
      if (_deviceId == null) throw StateError('device-unavailable');
      await _api.registerPushToken(
        defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android',
        token,
      );
      if (accountsEnabled && platform.signedIn) {
        await platform.registerPush(
          token,
          defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android',
        );
      }
      _pushToken = token;
    },
    onMessage: () async {
      await refreshNotices();
      if (accountsEnabled && platform.activeConversation != null) {
        await platform.load(
          '/conversations/${platform.activeConversation}/messages',
        );
      }
    },
    shouldPresent: (data) =>
        !(accountsEnabled &&
            data['recipient_id'] != null &&
            data['recipient_id'] != platform.user?.id) &&
        !(accountsEnabled &&
            data['destination'] == 'conversation' &&
            data['entity_id'] == platform.activeConversation),
  );
  final List<Job> _jobs = [];
  final Set<String> _savedIds = {};
  final Set<String> _hiddenEmployers = {};
  final List<Submission> _submissions = [];
  JobFilters filters = const JobFilters();
  String query = '';
  bool get needsCountryChoice => false;

  Future<void> confirmCountry(String code) async {
    if (!supportedJobCountryCodes.contains(code)) {
      throw const JobsException('اختر بلداً من القائمة.');
    }
    if (!await _preferences.setBool(_key('country.confirmed'), true)) {
      throw const JobsException('تعذّر حفظ البلد. يرجى المحاولة مجدداً.');
    }
    updateFilters(filters.copyWith(country: code, city: null));
    _notify();
  }

  final List<Map<String, dynamic>> savedSearches = [];
  final Set<String> _readUpdates = {};
  final Map<String, DateTime?> _matchWatermarks = {};
  final Map<String, Set<String>> _matchKnown = {};
  final Map<String, Job> _matchedJobs = {};
  final Set<String> _newMatchIds = {}, _announcedMatchIds = {};
  bool savedMatchesLoading = false;
  String? savedMatchesError;
  DateTime? _lastMatchCheck;

  bool _matchesSaved(Job job) => savedSearches.any(
    (search) => JobFilters.fromJson(
      Map<String, dynamic>.from(search['filters'] as Map),
    ).matches(job, search['query'] as String),
  );

  List<Job> get savedSearchMatches {
    final matches = <String, Job>{
      for (final job in [...discoverableJobs, ..._matchedJobs.values])
        if (job.isAvailable &&
            !_hiddenEmployers.contains(_employerIdentity(job)) &&
            _matchesSaved(job))
          job.id: job,
    }.values.toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return matches;
  }

  bool isNewSavedMatch(String id) =>
      _newMatchIds.contains(id) && !isUpdateRead('job-$id');
  List<Job> get newMatchAlertJobs => savedSearchMatches
      .where(
        (job) =>
            isNewSavedMatch(job.id) && !_announcedMatchIds.contains(job.id),
      )
      .toList();

  Future<void> acknowledgeMatchAlert(Iterable<String> ids) async {
    if (accountsEnabled && platform.signedIn && !isDemo) {
      await platform.matchAction(ids, read: false);
    }
    _announcedMatchIds.addAll(ids);
    _notify();
    await _persistDiscovery();
  }

  /// Watch the latest 50 results of each saved search independently of the
  /// current feed. The first successful check establishes a silent baseline.
  Future<void> refreshSavedSearchMatches({bool force = false}) async {
    if (accountsEnabled) {
      if (platform.signedIn) {
        try {
          await platform.load('/me/saved-search-matches');
          savedMatchesError = null;
        } catch (e) {
          savedMatchesError = e.toString();
        }
      }
      return;
    }
    if (_disposed || savedMatchesLoading || savedSearches.isEmpty) return;
    if (!force &&
        _lastMatchCheck != null &&
        DateTime.now().difference(_lastMatchCheck!) <
            const Duration(minutes: 1)) {
      return;
    }
    savedMatchesLoading = true;
    savedMatchesError = null;
    _lastMatchCheck = DateTime.now();
    _notify();
    try {
      if (!isDemo &&
          fields.isEmpty &&
          savedSearches.any(
            (search) => (search['filters'] as Map)['category'] != null,
          )) {
        try {
          fields = await _api.jobFields();
        } catch (_) {
          savedMatchesError =
              'تعذّر تحميل مجالات البحث المحفوظ. يرجى إعادة المحاولة.';
          return;
        }
      }
      final snapshots = savedSearches
          .map((search) => Map<String, dynamic>.from(search))
          .toList();
      final results = await Future.wait(
        snapshots.map((search) async {
          final filters = JobFilters.fromJson(
            Map<String, dynamic>.from(search['filters'] as Map),
          );
          try {
            final jobs = isDemo
                ? discoverableJobs
                : (await _api.jobsPage(
                    search: search['query'] as String,
                    filters: filters.copyWith(sort: 'newest'),
                    categoryId: filters.category == null
                        ? null
                        : fieldIdFor(filters.category!),
                    page: 1,
                    perPage: 50,
                  )).jobs;
            return (
              search: search,
              jobs: jobs
                  .where(
                    (job) => filters.matches(job, search['query'] as String),
                  )
                  .toList(),
            );
          } catch (_) {
            return (search: search, jobs: null);
          }
        }),
      );
      if (_disposed) return;
      final collected = <String, Job>{};
      for (final result in results) {
        final key = result.search['key'] as String;
        if (!savedSearches.any((search) => search['key'] == key)) continue;
        final jobs = result.jobs;
        if (jobs == null) {
          savedMatchesError =
              'تعذّر تحديث بعض عمليات البحث المحفوظة. يرجى إعادة المحاولة.';
          continue;
        }
        final initialized = _matchWatermarks.containsKey(key);
        final watermark = _matchWatermarks[key];
        final known = _matchKnown[key] ?? <String>{};
        for (final job in jobs) {
          collected[job.id] = job;
          if (initialized &&
              !known.contains(job.id) &&
              (watermark == null || !job.createdAt.isBefore(watermark))) {
            _newMatchIds.add(job.id);
          }
        }
        final dates = [?watermark, ...jobs.map((job) => job.createdAt)]..sort();
        _matchWatermarks[key] = dates.isEmpty ? null : dates.last;
        _matchKnown[key] = jobs.map((job) => job.id).toSet();
      }
      _matchedJobs
        ..clear()
        ..addAll(collected);
      _newMatchIds.removeWhere((id) => isUpdateRead('job-$id'));
      await _persistDiscovery();
    } finally {
      savedMatchesLoading = false;
      _notify();
    }
  }

  Future<void> _discoveryWrite = Future.value();
  Timer? _discoveryDebounce;
  int _discoveryGeneration = 0;
  int? _discoveryErrorRevision;
  bool discoveryLoading = false;

  /// Live clients load the catalog page by page with server-side search and
  /// filters. Demo data stays local and does not need pagination.
  bool get pagedCatalog => (pagedCatalogOverride ?? true) && !isDemo;
  @visibleForTesting
  static bool? pagedCatalogOverride;
  static const _pageSize = 24;
  int _page = 0;
  int _lastPage = 0;
  bool loadingMore = false;
  String? loadMoreError;
  bool get hasMore => pagedCatalog && _page < _lastPage;

  /// Saved or linked jobs fetched outside the current result pages.
  final Map<String, Job> _pinned = {};
  bool isUpdateRead(String id) => _readUpdates.contains(id);
  Future<void> markUpdateRead(String id) async {
    if (accountsEnabled &&
        platform.signedIn &&
        !isDemo &&
        id.startsWith('job-')) {
      await platform.matchAction([id.substring(4)], read: true);
    }
    _readUpdates.add(id);
    _notify();
    await _persistDiscovery();
  }

  Future<void> saveSearch() async {
    if (accountsEnabled) {
      if (!platform.signedIn) {
        throw const JobsException('يرجى تسجيل الدخول لحفظ البحث.');
      }
      await platform.saveSearch({
        'name': query.trim().isEmpty ? 'بحث محفوظ' : query.trim(),
        'query': query,
        'filters': filters.toJson(),
      });
      return;
    }
    final encoded = jsonEncode({'query': query, 'filters': filters.toJson()});
    if (savedSearches.any((s) => s['key'] == encoded)) return;
    final name = [
      if (query.trim().isNotEmpty) query.trim(),
      filters.category,
      if (filters.country != null) countryLabel(filters.country),
      filters.city,
      filters.workMode,
    ].whereType<String>().join(' · ');
    savedSearches.insert(0, {
      'key': encoded,
      'name': name.isEmpty ? 'كل الفرص' : name,
      'query': query,
      'filters': filters.toJson(),
    });
    if (savedSearches.length > 20) {
      final removed = savedSearches.removeLast();
      _matchWatermarks.remove(removed['key']);
      _matchKnown.remove(removed['key']);
    }
    _notify();
    await _persistDiscovery();
    unawaited(refreshSavedSearchMatches(force: true));
  }

  Future<void> removeSearch(Map<String, dynamic> search) async {
    if (accountsEnabled) {
      await platform.removeSearch(textOf(search['id']));
      return;
    }
    savedSearches.remove(search);
    _matchWatermarks.remove(search['key']);
    _matchKnown.remove(search['key']);
    _notify();
    await _persistDiscovery();
  }

  void applySearch(Map<String, dynamic> search) {
    query = search['query'] as String;
    final next = JobFilters.fromJson(
      Map<String, dynamic>.from(search['filters'] as Map),
    );
    updateFilters(next);
  }

  Future<void> _persistDiscovery() {
    final snapshot = jsonEncode({
      'query': query,
      'filters': filters.toJson(),
      'searches': accountsEnabled ? [] : savedSearches,
      'read': _readUpdates.toList(),
      'matchWatermarks': {
        for (final entry in _matchWatermarks.entries)
          entry.key: entry.value?.toUtc().toIso8601String(),
      },
      'matchKnown': {
        for (final entry in _matchKnown.entries)
          entry.key: entry.value.toList(),
      },
      'newMatchIds': _newMatchIds.take(1000).toList(),
      'announcedMatchIds': _announcedMatchIds.take(1000).toList(),
    });
    final next = _discoveryWrite.then((_) async {
      try {
        if (!await _preferences.setString(_key('discovery'), snapshot)) {
          throw StateError('storage');
        }
      } catch (_) {
        error = 'تعذّر حفظ تفضيلات البحث على الجهاز.';
        _notify();
      }
    });
    _discoveryWrite = next;
    return next;
  }

  bool loading = false;
  bool busy = false;
  bool isOffline = false;
  String? _error;
  int _errorRevision = 0;
  String? get error => _error;
  set error(String? value) {
    _error = value;
    _errorRevision++;
  }

  String? _deviceId;
  String? _deviceError;
  Future<void>? _deviceInitialization;
  List<JobField> fields = [];
  List<RemoteNotice> notices = [];
  int noticesUnread = 0;
  Future<void>? _refreshing;
  Future<void> _favoriteWrite = Future<void>.value();
  DateTime? lastUpdated;
  int totalCount = 0;
  bool _disposed = false;
  Future<void> _savedWrite = Future<void>.value();
  int _submissionGeneration = 0;

  String get apiBase {
    final value = (_baseOverride ?? _configuredBase).trim();
    return value.isEmpty ? _liveBase : value;
  }

  bool get isDemo => apiBase == 'demo';
  List<String> get categoryOptions => fields.isEmpty
      ? jobCategories
      : fields.map((field) => field.nameAr).toList();
  int? fieldIdFor(String label) {
    for (final field in fields) {
      if (field.nameAr == label || field.nameEn == label) return field.id;
    }
    return null;
  }

  List<String> _withSeen(List<String> base, String Function(Job job) read) {
    final values = <String>{...base};
    for (final job in _jobs) {
      final value = read(job).trim();
      if (value.isNotEmpty) values.add(value);
    }
    return values.toList();
  }

  /// Governorates only: API places such as «دمشق، المزة» or «.» are free
  /// text and match their governorate through [governorateOf].
  List<String> get placeOptions => placesFor(filters.country);

  List<String> placesFor(String? country) {
    if (country == null) return const [];
    final code = countryFor(country)?.code;
    return <String>{
      if (code == 'SY') ...jobCities,
      for (final job in _allJobs)
        if (countryFor(job.country)?.code == code)
          (code == 'SY' ? governorateOf(job.city) ?? job.city : job.city),
    }.toList()..sort();
  }

  Future<List<String>> availablePlaces(String country) =>
      _api.jobLocations(country);
  List<String> get workTypeOptions =>
      _withSeen(jobWorkTypes, (job) => job.workType);
  List<String> get workModeOptions =>
      _withSeen(jobWorkModes, (job) => job.workMode);
  List<String> get experienceOptions => jobExperienceLevels;
  List<Job> get jobs => List.unmodifiable(_allJobs);
  Iterable<Job> get _allJobs {
    if (_pinned.isEmpty) return _jobs;
    final ids = {for (final job in _jobs) job.id};
    return [..._jobs, ..._pinned.values.where((job) => !ids.contains(job.id))];
  }

  List<Job> get discoverableJobs => _jobs
      .where(
        (job) =>
            job.isAvailable &&
            !_hiddenEmployers.contains(_employerIdentity(job)),
      )
      .toList();

  /// A read-only view: card builds query it per job, so it must not copy.
  Set<String> get savedIds =>
      accountsEnabled ? platform.favoriteIds : UnmodifiableSetView(_savedIds);
  List<Submission> get submissions => accountsEnabled
      ? platform.postings
            .map((j) => Submission(job: j, createdAt: j.createdAt))
            .toList()
      : List.unmodifiable(_submissions);
  int get hiddenEmployerCount => _hiddenEmployers.length;
  // Paged results are already searched on the server; the local pass keeps
  // hidden employers out and the same filter rules as the app.
  List<Job> get visibleJobs => filters.apply(
    _jobs.where((job) => !_hiddenEmployers.contains(_employerIdentity(job))),
    pagedCatalog ? '' : query,
  );
  List<Job> get savedJobs =>
      (accountsEnabled ? platform.favorites : _allJobs)
          .where(
            (job) =>
                savedIds.contains(job.id) &&
                job.isAvailable &&
                !_hiddenEmployers.contains(_employerIdentity(job)),
          )
          .toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  String get _namespace => isDemo
      ? 'snad.demo.v1'
      : 'snad.live.v1.${base64Url.encode(utf8.encode(apiBase))}';
  String _key(String name) => '$_namespace.$name';
  String? _readString(String name) => _preferences.getString(_key(name));

  List<String> _readStringList(String name) =>
      _preferences.getStringList(_key(name)) ?? const [];

  static Future<JobsStore> create({http.Client? client, String? base}) async {
    final preferences = await SharedPreferences.getInstance();
    final store = JobsStore._(
      preferences,
      client ?? createNetworkClient(),
      base,
    );
    store._readLocal();
    if (store.accountsEnabled) {
      store.platform.addListener(store._accountChanged);
      unawaited(store.platform.initialize());
      unawaited(ReviewMoments.recordUse());
    }
    if (store.isDemo) {
      store._jobs.addAll(
        buildDemoJobs().map(
          (j) => j.copyWith(acceptsApplications: store.accountsEnabled),
        ),
      );
      if (store.accountsEnabled) {
        store.platform.demoJobs.addEntries(
          store._jobs.map((j) => MapEntry(j.id, j)),
        );
      }
      store.totalCount = store._jobs.length;
      store.lastUpdated = DateTime.now();
    } else {
      // The public catalog and cached page do not need the private device
      // credential. Initialize it alongside the feed request so secure
      // storage cannot hold the first useful screen hostage.
      unawaited(store._ensureDevice());
      unawaited(store.refresh());
    }
    return store;
  }

  void _readLocal() {
    try {
      final raw = _readString('discovery');
      if (raw != null) {
        final data = jsonDecode(raw) as Map<String, dynamic>;
        filters = JobFilters.fromJson(
          Map<String, dynamic>.from(data['filters'] as Map),
        );
        query = data['query'] as String? ?? '';
        for (final raw in (data['searches'] as List).take(20)) {
          final entry = Map<String, dynamic>.from(raw as Map);
          if (entry['query'] is! String ||
              entry['name'] is! String ||
              entry['key'] is! String ||
              entry['filters'] is! Map) {
            continue;
          }
          final decoded = JobFilters.fromJson(
            Map<String, dynamic>.from(entry['filters'] as Map),
          );
          savedSearches.add({
            ...entry,
            'key': jsonEncode({
              'query': entry['query'],
              'filters': decoded.toJson(),
            }),
            'filters': decoded.toJson(),
          });
        }
        _readUpdates.addAll((data['read'] as List).whereType<String>());
        for (final entry in (data['matchWatermarks'] as Map? ?? {}).entries) {
          _matchWatermarks[entry.key as String] = entry.value is String
              ? DateTime.tryParse(entry.value as String)
              : null;
        }
        for (final entry in (data['matchKnown'] as Map? ?? {}).entries) {
          if (entry.value is List) {
            _matchKnown[entry.key as String] = (entry.value as List)
                .whereType<String>()
                .toSet();
          }
        }
        _newMatchIds.addAll(
          (data['newMatchIds'] as List? ?? []).whereType<String>(),
        );
        _announcedMatchIds.addAll(
          (data['announcedMatchIds'] as List? ?? []).whereType<String>(),
        );
      }
    } catch (_) {
      error = 'تعذّر استرجاع إعدادات البحث. يمكنك ضبطها من جديد.';
    }

    _savedIds.addAll(_readStringList('saved'));
    _hiddenEmployers.addAll(_readStringList('hidden'));
    try {
      final encoded = _readString('submissions');
      if (encoded != null) {
        _submissions.addAll(
          (jsonDecode(encoded) as List<dynamic>).map(
            (value) =>
                Submission.fromJson(Map<String, dynamic>.from(value as Map)),
          ),
        );
      }
    } catch (_) {
      error = 'تعذّر قراءة إعلاناتك المحفوظة على هذا الجهاز.';
    }
    if (accountsEnabled) {
      savedSearches.clear();
      _readUpdates.clear();
      _newMatchIds.clear();
      _announcedMatchIds.clear();
      _matchWatermarks.clear();
      _matchKnown.clear();
      _submissions.clear();
      _savedIds.clear();
    }
    if (isDemo) return;
    try {
      final encoded = _readString('cache');
      if (encoded != null) {
        final cache = jsonDecode(encoded) as Map<String, dynamic>;
        if (!cache.containsKey('filters') && _readString('discovery') == null) {
          filters = const JobFilters(country: 'SY');
        }
        final cacheScope = cache['filters'] is Map
            ? JobFilters.fromJson(
                Map<String, dynamic>.from(cache['filters'] as Map),
              )
            : const JobFilters(country: 'SY');
        final sameScope =
            cacheScope.toJson().toString() == filters.toJson().toString() &&
            (cache['query'] ?? '') == query;
        if (sameScope) {
          _jobs.addAll(
            (cache['jobs'] as List<dynamic>).map(
              (value) => Job.fromJson(Map<String, dynamic>.from(value as Map)),
            ),
          );
        }
        if (sameScope) {
          lastUpdated = DateTime.tryParse(cache['updatedAt'] as String? ?? '');
          totalCount = (cache['total'] as num?)?.toInt() ?? _jobs.length;
        }
        final rawFields = cache['fields'];
        if (rawFields is List) {
          fields = [
            for (final row in rawFields)
              if (row is Map) JobField.fromJson(Map<String, dynamic>.from(row)),
          ];
        }
      }
    } catch (_) {
      error = 'تعذّر قراءة الفرص المحفوظة. حدّث الصفحة للمحاولة مجدداً.';
    }
  }

  SndApi get _api =>
      SndApi(base: apiBase, client: _client, deviceId: _deviceId ?? '');

  Future<void> _ensureDevice() {
    if (isDemo) return Future<void>.value();
    return _deviceInitialization ??= _initializeDevice();
  }

  Future<void> _initializeDevice() async {
    try {
      final key = _key('device');
      final existing = await _secureStorage.read(key: key);
      if (existing != null && existing.length >= 16) {
        _deviceId = existing;
        return;
      }
      final id = _newDeviceId();
      await _secureStorage.write(key: key, value: id);
      if (await _secureStorage.read(key: key) != id) {
        throw StateError('Device credential was not persisted');
      }
      _deviceId = id;
    } catch (_) {
      // Never replace an unreadable credential or publish with a temporary one.
      _deviceError =
          'تعذّر فتح التخزين الآمن. أعد فتح التطبيق للمحاولة؛ يظل التصفح متاحاً.';
      error = _deviceError;
      _notify();
    }
  }

  void _requireDevice() {
    if (!isDemo && (_deviceId == null || _deviceError != null)) {
      throw JobsException(_deviceError ?? 'تعذّر تجهيز هوية هذا الجهاز.');
    }
  }

  String _newDeviceId() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  Future<void> refresh() {
    final current = _refreshing;
    if (current != null) return current;
    late final Future<void> run;
    run = _refreshBody().whenComplete(() {
      if (identical(_refreshing, run)) _refreshing = null;
    });
    _refreshing = run;
    return run;
  }

  Future<void> _refreshBody() async {
    final quiet = _jobs.isNotEmpty;
    int? pageGeneration;
    error = _deviceError;
    _discoveryErrorRevision = null;
    if (!quiet) {
      loading = true;
      _notify();
    }
    try {
      if (isDemo) {
        _jobs
          ..clear()
          ..addAll(buildDemoJobs());
        totalCount = _jobs.length;
      } else if (pagedCatalog) {
        _discoveryGeneration++;
        _discoveryDebounce?.cancel();
        final generation = _discoveryGeneration;
        pageGeneration = generation;
        final first = await _firstPage();
        if (generation == _discoveryGeneration) {
          _showFirstPage(first);
        }
        loading = false;
        _notify();
        await _syncSideData();
        // A remembered category filter needs the field IDs loaded above.
        if (filters.category != null) _scheduleFilteredRequest();
      } else {
        final catalog = await _api.jobs();
        _jobs
          ..clear()
          ..addAll(catalog);
        totalCount = catalog.length;
        // Render public results immediately; owner/notice routes may be slow.
        loading = false;
        _notify();
        await _syncSideData();
        if (_hasServerDiscoveryCriteria) _scheduleFilteredRequest();
      }
      if (pageGeneration != null && pageGeneration != _discoveryGeneration) {
        return;
      }
      lastUpdated = DateTime.now();
      isOffline = false;
      if (!isDemo) await _writeCache();
    } catch (exception) {
      if (pageGeneration != null && pageGeneration != _discoveryGeneration) {
        return;
      }
      isOffline = !isDemo;
      error = _message(
        exception,
        _jobs.isEmpty
            ? 'تعذّر الاتصال. تأكد من الإنترنت وحاول مجدداً.'
            : 'تعرض أحدث نسخة محفوظة. تعذّر التحديث الآن.',
      );
    } finally {
      loading = false;
      _notify();
    }
  }

  Future<void> refreshNotices() async {
    if (accountsEnabled) {
      if (platform.signedIn) {
        try {
          await platform.load('/me/notifications');
        } catch (e) {
          error = e.toString();
          _notify();
        }
      }
      return;
    }
    if (isDemo) return;
    await _ensureDevice();
    if (_deviceId == null) return;
    try {
      final page = await _api.notices();
      notices = page.items;
      noticesUnread = page.unread;
      _notify();
    } catch (exception) {
      error = _message(exception, 'تعذّر تحديث الإشعارات. حاول مجدداً.');
      _notify();
    }
  }

  Future<void> _syncSideData() async {
    await _ensureDevice();
    Future<void> attempt(
      Future<void> Function() action, {
      String? failure,
    }) async {
      try {
        await action();
      } catch (exception) {
        if (failure != null) error ??= _message(exception, failure);
      }
    }

    await Future.wait([
      attempt(() async {
        fields = await _api.jobFields();
      }),
      if (_deviceId != null) ...[
        attempt(
          refreshMySubmissions,
          failure: 'تحدّثت الفرص، لكن تعذّر تحديث إعلاناتك. حاول مجدداً.',
        ),
        attempt(() async {
          if (accountsEnabled) {
            if (platform.signedIn) await platform.load('/me/favorites');
            return;
          }
          // A catalog refresh must not race a pending favorite toggle.
          await _favoriteWrite.catchError((Object _) {});
          final pending = _favoriteWrite;
          final Set<String> ids;
          if (pagedCatalog) {
            final saved = await _api.favoriteJobs();
            ids = {for (final job in saved) job.id};
            if (!identical(pending, _favoriteWrite)) return;
            _pinned
              ..clear()
              ..addEntries(saved.map((job) => MapEntry(job.id, job)));
          } else {
            ids = await _api.favoriteIds();
          }
          if (!identical(pending, _favoriteWrite)) return;
          _savedIds
            ..clear()
            ..addAll(ids);
          await _persistSaved();
        }, failure: 'تحدّثت الفرص، لكن تعذّر تحديث المحفوظة. حاول مجدداً.'),
        attempt(() async {
          if (accountsEnabled) {
            await refreshNotices();
            return;
          }
          final page = await _api.notices();
          notices = page.items;
          noticesUnread = page.unread;
        }, failure: 'تحدّثت الفرص، لكن تعذّر تحديث الإشعارات. حاول مجدداً.'),
      ],
    ]);
    final platformName = kIsWeb
        ? 'web'
        : switch (defaultTargetPlatform) {
            TargetPlatform.iOS => 'ios',
            TargetPlatform.android => 'android',
            _ => 'web',
          };
    if (_deviceId != null) {
      unawaited(_api.visit(platformName, fcmToken: _pushToken));
    }
  }

  Future<void> _writeCache() async {
    try {
      final saved = await _preferences.setString(
        _key('cache'),
        jsonEncode({
          'jobs': _jobs.map((job) => job.toJson()).toList(),
          'fields': fields.map((field) => field.toJson()).toList(),
          'updatedAt': lastUpdated!.toUtc().toIso8601String(),
          'total': totalCount,
          'filters': filters.toJson(),
          'query': query,
        }),
      );
      if (!saved && error == null) {
        error = 'الفرص محدّثة، لكن تعذّر حفظ نسخة للاستخدام دون اتصال.';
      }
    } catch (_) {
      error ??= 'الفرص محدّثة، لكن تعذّر حفظ نسخة للاستخدام دون اتصال.';
    }
  }

  void setQuery(String value) {
    query = value;
    _notify();
    unawaited(_persistDiscovery());
    _scheduleFilteredRequest();
  }

  void updateFilters(JobFilters value) {
    if (filters.country != value.country && pagedCatalog) {
      _jobs.clear();
      _page = _lastPage = totalCount = 0;
      lastUpdated = null;
      error = null;
      _discoveryErrorRevision = null;
    }
    filters = value;
    _notify();
    unawaited(_persistDiscovery());
    _scheduleFilteredRequest();
  }

  bool get _hasDiscoveryCriteria =>
      query.trim().isNotEmpty || filters.activeCount > 0;

  bool get _hasServerDiscoveryCriteria =>
      filters.country != null ||
      query.trim().isNotEmpty ||
      (filters.category != null && fieldIdFor(filters.category!) != null) ||
      filters.city != null ||
      filters.workType != null ||
      filters.workMode != null ||
      filters.experience != null ||
      filters.currency != null ||
      filters.salaryPeriod != null ||
      (filters.minSalary != null &&
          filters.currency != null &&
          filters.salaryPeriod != null);

  void _scheduleFilteredRequest() {
    _discoveryGeneration++;
    _discoveryDebounce?.cancel();
    if (pagedCatalog) {
      // A selected category needs its API ID before the server can filter it.
      if (filters.category != null && fieldIdFor(filters.category!) == null) {
        discoveryLoading = false;
        _notify();
        return;
      }
      discoveryLoading = true;
      loadMoreError = null;
      _notify();
      final generation = _discoveryGeneration;
      _discoveryDebounce = Timer(
        query.trim().isNotEmpty
            ? const Duration(milliseconds: 400)
            : Duration.zero,
        () => unawaited(_reloadFirstPage(generation)),
      );
      return;
    }
    if (isDemo || !_hasDiscoveryCriteria || !_hasServerDiscoveryCriteria) {
      discoveryLoading = false;
      _notify();
      return;
    }
    // The full catalog remains visible while the server request is pending.
    // A selected category needs its API ID; if the field list failed, the
    // local filter still works against the complete catalog.
    if (filters.category != null && fieldIdFor(filters.category!) == null) {
      discoveryLoading = false;
      _notify();
      return;
    }
    discoveryLoading = true;
    _notify();
    final generation = _discoveryGeneration;
    final delay = query.trim().isNotEmpty
        ? const Duration(milliseconds: 400)
        : Duration.zero;
    _discoveryDebounce = Timer(delay, () {
      unawaited(_fetchFiltered(generation));
    });
  }

  Future<JobsPage> _firstPage() => _api.jobsPage(
    search: query,
    filters: filters,
    categoryId: filters.category == null ? null : fieldIdFor(filters.category!),
    page: 1,
    perPage: _pageSize,
  );

  void _showFirstPage(JobsPage first) {
    _jobs
      ..clear()
      ..addAll(first.jobs);
    _page = first.page;
    _lastPage = first.lastPage;
    totalCount = first.total;
    loadMoreError = null;
  }

  Future<void> _reloadFirstPage(int generation) async {
    try {
      final first = await _firstPage();
      if (generation != _discoveryGeneration) return;
      _showFirstPage(first);
      lastUpdated = DateTime.now();
      isOffline = false;
      _clearDiscoveryError();
      await _writeCache();
    } catch (exception) {
      if (generation != _discoveryGeneration) return;
      error = _message(
        exception,
        'تعذّر تحديث نتائج البحث من الخدمة. تأكد من الاتصال وحاول مجدداً.',
      );
      _discoveryErrorRevision = _errorRevision;
    } finally {
      if (generation == _discoveryGeneration) {
        discoveryLoading = false;
        _notify();
      }
    }
  }

  /// Appends the next result page when a client approaches the list's end.
  Future<void> loadMore() async {
    if (!hasMore || loadingMore || loading || discoveryLoading) return;
    loadingMore = true;
    loadMoreError = null;
    _notify();
    final generation = _discoveryGeneration;
    try {
      final next = await _api.jobsPage(
        search: query,
        filters: filters,
        categoryId: filters.category == null
            ? null
            : fieldIdFor(filters.category!),
        page: _page + 1,
        perPage: _pageSize,
      );
      if (generation != _discoveryGeneration) return;
      final ids = {for (final job in _jobs) job.id};
      _jobs.addAll(next.jobs.where((job) => ids.add(job.id)));
      _page = next.page;
      _lastPage = next.lastPage;
      totalCount = next.total;
    } catch (exception) {
      if (generation != _discoveryGeneration) return;
      loadMoreError = _message(exception, 'تعذّر تحميل المزيد من الفرص.');
    } finally {
      loadingMore = false;
      _notify();
    }
  }

  /// Server count for a filter preview; null when it can't be checked now.
  Future<int?> countFor(JobFilters preview) async {
    if (!pagedCatalog) return null;
    if (preview.category != null && fieldIdFor(preview.category!) == null) {
      return null;
    }
    try {
      return await _api.countJobs(
        search: query,
        filters: preview,
        categoryId: preview.category == null
            ? null
            : fieldIdFor(preview.category!),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _fetchFiltered(int generation) async {
    if (isDemo || !_hasServerDiscoveryCriteria) return;
    try {
      final matching = await _api.filteredJobs(
        search: query,
        filters: filters,
        categoryId: filters.category == null
            ? null
            : fieldIdFor(filters.category!),
      );
      if (generation != _discoveryGeneration) return;
      final byId = {for (final job in _jobs) job.id: job};
      for (final job in matching) {
        byId[job.id] = job;
      }
      _jobs
        ..clear()
        ..addAll(byId.values);
      totalCount = _jobs.length;
      _clearDiscoveryError();
      if (lastUpdated != null) await _writeCache();
    } catch (exception) {
      if (generation != _discoveryGeneration) return;
      error = _message(
        exception,
        'تعذّر تحديث نتائج البحث من الخدمة. تظهر النتائج المحمّلة على الجهاز.',
      );
      _discoveryErrorRevision = _errorRevision;
    } finally {
      if (generation == _discoveryGeneration) {
        discoveryLoading = false;
        _notify();
      }
    }
  }

  void showError(String message) {
    error = message;
    _notify();
  }

  void _clearDiscoveryError() {
    if (_discoveryErrorRevision == _errorRevision) error = null;
    _discoveryErrorRevision = null;
  }

  void clearError() {
    _discoveryErrorRevision = null;
    error = null;
    _notify();
  }

  Future<void> toggleSaved(String id, {bool? desired}) async {
    if (accountsEnabled) {
      if (!platform.signedIn) {
        throw const JobsException('يرجى تسجيل الدخول لحفظ الفرصة.');
      }
      await platform.setFavorite(id, desired ?? !savedIds.contains(id));
      await ReviewMoments.completedAction(demo: isDemo);
      return;
    }
    try {
      await _ensureDevice();
      _requireDevice();
    } on JobsException catch (exception) {
      showError(exception.message);
      return;
    }
    final added = !_savedIds.remove(id);
    if (added) _savedIds.add(id);
    if (pagedCatalog && added) {
      // Keep a saved job in «المحفوظة» after the result page changes.
      for (final job in _jobs) {
        if (job.id == id) _pinned[id] = job;
      }
    }
    _notify();
    final next = _favoriteWrite.catchError((Object _) {}).then((_) async {
      await _persistSaved();
      if (isDemo) return;
      final saved = await _api.toggleFavorite(id);
      if (saved == _savedIds.contains(id)) return;
      if (saved) {
        _savedIds.add(id);
      } else {
        _savedIds.remove(id);
      }
      await _persistSaved();
      _notify();
    });
    _favoriteWrite = next;
    try {
      await next;
    } catch (exception) {
      if (added) {
        _savedIds.remove(id);
      } else {
        _savedIds.add(id);
      }
      error = _message(exception, 'تعذّر تحديث المحفوظات. حاول مرة أخرى.');
      try {
        await _persistSaved();
      } catch (_) {}
      _notify();
    }
  }

  Future<void> _persistSaved() {
    final snapshot = _savedIds.toList();
    // Ordered writes keep rapid repeated taps from restoring an older snapshot.
    final next = _savedWrite.catchError((Object _) {}).then((_) async {
      final saved = await _preferences.setStringList(_key('saved'), snapshot);
      if (!saved) throw const JobsException('تعذّر حفظ المفضلة على الجهاز.');
    });
    _savedWrite = next;
    return next;
  }

  String _employerIdentity(Job job) =>
      job.employerKey ??
      jsonEncode([
        job.company.trim(),
        job.phone.trim(),
        job.email.trim().toLowerCase(),
      ]);

  Future<void> hideEmployer(Job job) async {
    final identity = _employerIdentity(job);
    final previous = Set<String>.of(_hiddenEmployers);
    _hiddenEmployers.add(identity);
    try {
      if (!await _preferences.setStringList(
        _key('hidden'),
        _hiddenEmployers.toList(),
      )) {
        throw StateError('storage');
      }
    } catch (_) {
      _hiddenEmployers
        ..clear()
        ..addAll(previous);
      throw const JobsException(
        'تعذّر حفظ إخفاء الجهة على الجهاز. حاول مجدداً.',
      );
    }
    _notify();
  }

  Future<void> unhideAllEmployers() async {
    if (!await _preferences.remove(_key('hidden'))) {
      throw const JobsException('تعذّر حفظ التغيير على الجهاز. حاول مجدداً.');
    }
    _hiddenEmployers.clear();
    _notify();
  }

  Future<void> _persistSubmissions() async {
    if (accountsEnabled) return;
    final saved = await _preferences.setString(
      _key('submissions'),
      jsonEncode(
        _submissions.map((submission) => submission.toJson()).toList(),
      ),
    );
    if (!saved) {
      error = 'تعذّر حفظ إعلاناتك على الجهاز.';
      throw JobsException(error!);
    }
  }

  Future<Submission> submit(Job draft, {bool contactConsent = false}) async {
    if (countryFor(draft.country)?.code != 'SY' ||
        !jobCities.contains(draft.city)) {
      throw const JobsException('اختر محافظة سورية لإضافة فرصة.');
    }
    if (accountsEnabled) {
      if (!platform.signedIn) {
        throw const JobsException('يرجى تسجيل الدخول لإضافة فرصة.');
      }
    } else {
      await _ensureDevice();
      _requireDevice();
    }
    if (!contactConsent) {
      throw const JobsException(
        'يلزم الموافقة على إظهار وسيلة التواصل ضمن الإعلان.',
      );
    }
    if (busy) throw const JobsException('انتظر انتهاء الطلب الحالي.');
    // The form captures its dates separately; round away sub-second clock drift.
    final expiresInDays =
        (draft.expiresAt.difference(draft.createdAt).inMicroseconds /
                Duration.microsecondsPerDay)
            .round();
    if (![7, 14, 30].contains(expiresInDays)) {
      throw const JobsException('اختر مدة للإعلان: 7 أو 14 أو 30 يوماً.');
    }
    busy = true;
    _submissionGeneration++;
    error = null;
    _notify();
    try {
      final Job stored;
      if (isDemo) {
        stored = draft.copyWith(
          id: 'demo-submission-${DateTime.now().microsecondsSinceEpoch}',
          status: 'pending',
          isDemo: true,
        );
        if (accountsEnabled) await platform.rememberDemoJob(stored);
      } else {
        if (fields.isEmpty) {
          try {
            fields = await _api.jobFields();
          } catch (_) {}
        }
        final fieldId = draft.jobFieldId ?? fieldIdFor(draft.category);
        if (fieldId == null) {
          throw const JobsException('اختر مجال العمل من القائمة.');
        }
        final body = <String, dynamic>{
          'title': draft.title,
          'company_name': draft.company,
          'country': draft.country.trim().isEmpty ? 'سوريا' : draft.country,
          'state': draft.city,
          'job_field_id': fieldId,
          'job_type': draft.workType,
          'work_type': workModeApiValue(draft.workMode),
          'experience': experienceApiValue(draft.experience),
          'description': draft.description,
          if (draft.requirements.isNotEmpty)
            'requirements': draft.requirements.join('\n'),
          if (draft.phone.trim().isNotEmpty) 'phone': draft.phone.trim(),
          if (draft.email.trim().isNotEmpty) 'email': draft.email.trim(),
          if (draft.companyWebsite.trim().isNotEmpty)
            'url': draft.companyWebsite.trim(),
          'currency': draft.currency,
          'salary_period': draft.salaryPeriod,
          if (draft.salaryMin != null) 'salary_min': draft.salaryMin,
          if (draft.salaryMax != null) 'salary_max': draft.salaryMax,
          'listing_duration_days': expiresInDays,
          if (accountsEnabled) 'contact_consent': contactConsent,
          if (accountsEnabled) 'accepts_applications': true,
        };
        stored = accountsEnabled
            ? await platform.createJob(body)
            : await _api.createJob(body);
      }
      final submission = Submission(job: stored, createdAt: DateTime.now());
      _submissionGeneration++;
      _submissions.insert(0, submission);
      try {
        await _persistSubmissions();
      } catch (_) {
        throw JobsException(
          isDemo
              ? 'تعذّر حفظ الإعلان التجريبي على الجهاز.'
              : 'تم إرسال الإعلان، لكن تعذّر حفظ بياناته على الجهاز. لا تعاود إرساله.',
          uncertainOutcome: !isDemo,
        );
      }
      return submission;
    } catch (exception) {
      final message = _message(
        exception,
        'لم يتم تأكيد إرسال الإعلان. تحقق من الاتصال قبل إعادة المحاولة.',
      );
      error = message;
      throw JobsException(
        message,
        uncertainOutcome:
            exception is JobsException && exception.uncertainOutcome ||
            exception is PlatformFailure && exception.uncertain,
      );
    } finally {
      busy = false;
      _notify();
    }
  }

  Future<Submission> refreshSubmission(Submission submission) async {
    if (accountsEnabled) {
      await platform.load('/me/jobs');
      return submissions.firstWhere(
        (s) => s.id == submission.id,
        orElse: () => submission,
      );
    }
    await _ensureDevice();
    _requireDevice();
    if (submission.isDemo || submission.status == 'withdrawn') {
      return submission;
    }
    if (busy) throw const JobsException('انتظر انتهاء الطلب الحالي.');
    busy = true;
    _notify();
    try {
      final mine = await _api.myJobs();
      Job? match;
      for (final job in mine) {
        if (job.id == submission.id) match = job;
      }
      if (match == null) {
        throw const JobsException(
          'لم نعثر على الإعلان على هذا الجهاز.',
          statusCode: 404,
        );
      }
      final updated = Submission(job: match, createdAt: submission.createdAt);
      if (!updated.job.isAvailable) {
        _jobs.removeWhere((job) => job.id == updated.id);
        await _preferences.remove(_key('cache'));
      }
      await _replaceSubmission(updated);
      return updated;
    } catch (exception) {
      throw JobsException(
        _message(exception, 'تعذّر تحديث حالة الإعلان. حاول مجدداً.'),
      );
    } finally {
      busy = false;
      _notify();
    }
  }

  /// Recover server-owned submissions even when a create response was lost.
  Future<void> refreshMySubmissions() async {
    if (accountsEnabled) {
      if (platform.signedIn) await platform.load('/me/jobs');
      return;
    }
    if (isDemo) return;
    await _ensureDevice();
    _requireDevice();
    final generation = _submissionGeneration;
    final remote = await _api.myJobs();
    if (generation != _submissionGeneration) {
      throw const JobsException('تغيّرت إعلاناتك أثناء التحديث. حاول مجدداً.');
    }
    _submissions
      ..removeWhere((submission) => !submission.isDemo)
      ..insertAll(
        0,
        remote.map((job) => Submission(job: job, createdAt: job.createdAt)),
      );
    await _persistSubmissions();
    _notify();
  }

  /// Loads one job by id (also registers a server-side view).
  Future<Job?> fetchJob(String id) async {
    if (isDemo) {
      for (final job in _jobs) {
        if (job.id == id) return job;
      }
      return null;
    }
    try {
      final current = await _api.job(id);
      final index = _jobs.indexWhere((existing) => existing.id == current.id);
      if (index != -1) {
        _jobs[index] = current;
      } else if (pagedCatalog) {
        // Linked jobs open without joining the current result page.
        if (current.isAvailable) _pinned[current.id] = current;
      } else if (current.isAvailable) {
        _jobs.insert(0, current);
      }
      _notify();
      return current;
    } catch (_) {
      return null;
    }
  }

  /// Loads the live job (registers a view on the server) and updates the cache.
  Future<Job> trackJobView(Job job) async {
    final fresh = await fetchJob(job.id);
    return fresh ?? job;
  }

  /// Contact always uses the current public record, never an offline snapshot.
  Future<Job> verifyAvailableJob(Job job) async {
    if (!job.isAvailable) {
      throw const JobsException('هذه الفرصة لم تعد متاحة.');
    }
    if (isDemo || job.isDemo) return job;
    try {
      final current = await _api.job(job.id);
      if (!current.isAvailable || current.id != job.id || current.isDemo) {
        throw const JobsException('هذه الفرصة لم تعد متاحة.', statusCode: 410);
      }
      final index = _jobs.indexWhere((existing) => existing.id == current.id);
      if (index != -1) _jobs[index] = current;
      _notify();
      return current;
    } catch (exception) {
      if (exception is JobsException &&
          [404, 410].contains(exception.statusCode)) {
        _jobs.removeWhere((existing) => existing.id == job.id);
        await _preferences.remove(_key('cache'));
        _notify();
        throw const JobsException('هذه الفرصة لم تعد متاحة.');
      }
      throw JobsException(
        _message(
          exception,
          'تعذّر التأكد من توفر الفرصة. اتصل بالإنترنت وحاول مجدداً.',
        ),
      );
    }
  }

  Future<Submission> withdraw(Submission submission) async {
    if (accountsEnabled) {
      await platform.withdrawJob(submission.id);
      return Submission(
        job: submission.job.copyWith(status: 'withdrawn'),
        createdAt: submission.createdAt,
      );
    }
    await _ensureDevice();
    _requireDevice();
    if (busy) throw const JobsException('انتظر انتهاء الطلب الحالي.');
    busy = true;
    _submissionGeneration++;
    _notify();
    try {
      if (!submission.isDemo && submission.status != 'withdrawn') {
        try {
          await _api.deleteJob(submission.id);
        } on JobsException catch (exception) {
          if (exception.statusCode != 404) rethrow;
        }
      }
      final updated = Submission(
        job: submission.job.copyWith(status: 'withdrawn'),
        createdAt: submission.createdAt,
      );
      _submissionGeneration++;
      _jobs.removeWhere((job) => job.id == submission.id);
      _submissions.removeWhere((existing) => existing.id == submission.id);
      _savedIds.remove(submission.id);
      await _persistSubmissions();
      await _persistSaved();
      if (!submission.isDemo) {
        await _preferences.remove(_key('cache'));
      }
      return updated;
    } catch (exception) {
      throw JobsException(
        _message(exception, 'تعذّر سحب الإعلان. حاول مجدداً.'),
      );
    } finally {
      busy = false;
      _notify();
    }
  }

  Future<void> _replaceSubmission(Submission submission) async {
    final index = _submissions.indexWhere(
      (existing) => existing.id == submission.id,
    );
    if (index == -1) {
      _submissions.insert(0, submission);
    } else {
      _submissions[index] = submission;
    }
    await _persistSubmissions();
    _notify();
  }

  Future<void> markNoticeRead(String id) async {
    if (!accountsEnabled && !isDemo) await _ensureDevice();
    if (!accountsEnabled && !isDemo && _deviceId == null) return;
    final index = notices.indexWhere((notice) => notice.id == id);
    if (index == -1 || notices[index].read) return;
    final current = notices[index];
    notices[index] = RemoteNotice(
      id: current.id,
      payload: current.payload,
      text: current.text,
      read: true,
      createdAt: current.createdAt,
      jobId: current.jobId,
    );
    if (noticesUnread > 0) noticesUnread -= 1;
    _notify();
    if (isDemo) return;
    try {
      if (accountsEnabled) {
        await platform.markNoticeRead(id);
      } else {
        await _api.markNoticeRead(id);
      }
    } catch (_) {
      final currentIndex = notices.indexWhere((notice) => notice.id == id);
      if (currentIndex != -1 && notices[currentIndex].read) {
        notices[currentIndex] = current;
        noticesUnread += 1;
      }
      error = 'تعذّر تسجيل حالة القراءة. حاول مرة أخرى.';
      _notify();
    }
  }

  Future<void> report(Job job, String reason) async {
    await _ensureDevice();
    _requireDevice();
    if (reason.trim().length < 5) {
      throw const JobsException('اكتب سبباً واضحاً للبلاغ.');
    }
    if (isDemo || job.isDemo) return;
    try {
      await _api.report(job.id, reason.trim());
    } catch (exception) {
      throw JobsException(
        _message(exception, 'لم يُرسل البلاغ. تحقق من الاتصال وحاول مجدداً.'),
      );
    }
  }

  String _message(Object exception, String fallback) =>
      exception is JobsException
      ? exception.message
      : exception is PlatformFailure
      ? exception.message
      : fallback;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    if (accountsEnabled) platform.removeListener(_accountChanged);
    platform.dispose();
    push.dispose();
    _discoveryDebounce?.cancel();
    _client.close();
    super.dispose();
  }
}
