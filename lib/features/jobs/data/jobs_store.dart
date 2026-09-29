import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/job.dart';
import '../domain/job_filters.dart';
import 'api_client.dart';
import 'demo_jobs.dart';

export 'api_client.dart' show JobField, JobsException, RemoteNotice;

class JobsStore extends ChangeNotifier {
  JobsStore._(this._preferences, this._client);

  static const _configuredBase = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://snd.avorix.io',
  );
  static const _liveBase = 'https://snd.avorix.io';
  static const _secureStorage = FlutterSecureStorage();
  final SharedPreferences _preferences;
  final http.Client _client;
  final List<Job> _jobs = [];
  final Set<String> _savedIds = {};
  final Set<String> _hiddenEmployers = {};
  final List<Submission> _submissions = [];
  JobFilters filters = const JobFilters();
  String query = '';
  final List<Map<String, dynamic>> savedSearches = [];
  final Set<String> _readUpdates = {};
  Future<void> _discoveryWrite = Future.value();
  bool isUpdateRead(String id) => _readUpdates.contains(id);
  Future<void> markUpdateRead(String id) async {
    _readUpdates.add(id);
    _notify();
    await _persistDiscovery();
  }

  Future<void> saveSearch() async {
    final encoded = jsonEncode({'query': query, 'filters': filters.toJson()});
    if (savedSearches.any((s) => s['key'] == encoded)) return;
    final name = [
      if (query.trim().isNotEmpty) query.trim(),
      filters.category,
      filters.city,
      filters.workMode,
    ].whereType<String>().join(' · ');
    savedSearches.insert(0, {
      'key': encoded,
      'name': name.isEmpty ? 'كل الفرص' : name,
      'query': query,
      'filters': filters.toJson(),
    });
    if (savedSearches.length > 20) savedSearches.removeLast();
    _notify();
    await _persistDiscovery();
  }

  Future<void> removeSearch(Map<String, dynamic> search) async {
    savedSearches.remove(search);
    _notify();
    await _persistDiscovery();
  }

  void applySearch(Map<String, dynamic> search) {
    query = search['query'] as String;
    filters = JobFilters.fromJson(
      Map<String, dynamic>.from(search['filters'] as Map),
    );
    _notify();
    unawaited(_persistDiscovery());
  }

  Future<void> _persistDiscovery() {
    final snapshot = jsonEncode({
      'query': query,
      'filters': filters.toJson(),
      'searches': savedSearches,
      'read': _readUpdates.toList(),
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
  String? error;
  String? maintenance;
  String? _deviceId;
  List<JobField> fields = [];
  List<RemoteNotice> notices = [];
  Future<void>? _refreshing;
  Future<void> _favoriteWrite = Future<void>.value();
  DateTime? lastUpdated;
  int totalCount = 0;
  bool _disposed = false;
  Future<void> _savedWrite = Future<void>.value();

  String get apiBase {
    final value = _configuredBase.trim();
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

  List<String> get placeOptions => _withSeen(jobCities, (job) => job.city);
  List<String> get workTypeOptions =>
      _withSeen(jobWorkTypes, (job) => job.workType);
  List<String> get workModeOptions =>
      _withSeen(jobWorkModes, (job) => job.workMode);
  List<String> get experienceOptions =>
      _withSeen(jobExperienceLevels, (job) => job.experience);
  List<Job> get jobs => List.unmodifiable(_jobs);
  List<Job> get discoverableJobs => _jobs
      .where(
        (job) =>
            job.isAvailable &&
            !_hiddenEmployers.contains(_employerIdentity(job)),
      )
      .toList();
  Set<String> get savedIds => Set.unmodifiable(_savedIds);
  List<Submission> get submissions => List.unmodifiable(_submissions);
  int get hiddenEmployerCount => _hiddenEmployers.length;
  List<Job> get visibleJobs => filters.apply(
    _jobs.where((job) => !_hiddenEmployers.contains(_employerIdentity(job))),
    query,
  );
  List<Job> get savedJobs =>
      _jobs
          .where(
            (job) =>
                _savedIds.contains(job.id) &&
                job.isAvailable &&
                !_hiddenEmployers.contains(_employerIdentity(job)),
          )
          .toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  String get _namespace => isDemo
      ? 'fursa.demo.v1'
      : 'fursa.live.v1.${base64Url.encode(utf8.encode(apiBase))}';
  String _key(String name) => '$_namespace.$name';

  static Future<JobsStore> create() async {
    final preferences = await SharedPreferences.getInstance();
    final store = JobsStore._(preferences, http.Client());
    await store._ensureDevice();
    store._readLocal();
    if (store.isDemo) {
      store._jobs.addAll(buildDemoJobs());
      store.totalCount = store._jobs.length;
      store.lastUpdated = DateTime.now();
    } else {
      unawaited(store.refresh());
    }
    return store;
  }

  void _readLocal() {
    try {
      final raw = _preferences.getString(_key('discovery'));
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
          savedSearches.add({...entry, 'filters': decoded.toJson()});
        }
        _readUpdates.addAll((data['read'] as List).whereType<String>());
      }
    } catch (_) {
      error = 'تعذّر استرجاع إعدادات البحث. فيك تختارها من جديد.';
    }

    _savedIds.addAll(_preferences.getStringList(_key('saved')) ?? []);
    _hiddenEmployers.addAll(_preferences.getStringList(_key('hidden')) ?? []);
    try {
      final encoded = _preferences.getString(_key('submissions'));
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
    if (isDemo) return;
    try {
      final encoded = _preferences.getString(_key('cache'));
      if (encoded != null) {
        final cache = jsonDecode(encoded) as Map<String, dynamic>;
        _jobs.addAll(
          (cache['jobs'] as List<dynamic>).map(
            (value) => Job.fromJson(Map<String, dynamic>.from(value as Map)),
          ),
        );
        lastUpdated = DateTime.tryParse(cache['updatedAt'] as String? ?? '');
        totalCount = (cache['total'] as num?)?.toInt() ?? _jobs.length;
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
      SndApi(base: apiBase, client: _client, deviceId: _deviceId!);

  Future<void> _ensureDevice() async {
    if (isDemo) return;
    if (kIsWeb) {
      final saved = _preferences.getString('fursa.device.v1');
      if (saved != null && saved.length >= 16) {
        _deviceId = saved;
        return;
      }
      final id = _newDeviceId();
      await _preferences.setString('fursa.device.v1', id);
      _deviceId = id;
      return;
    }
    try {
      final existing = await _secureStorage.read(key: 'fursa.device.v1');
      if (existing != null && existing.length >= 16) {
        _deviceId = existing;
        return;
      }
    } catch (_) {
      // A fresh id is written below when the keychain is readable.
    }
    final id = _newDeviceId();
    try {
      await _secureStorage.write(key: 'fursa.device.v1', value: id);
    } catch (_) {
      error = 'تعذّر تجهيز هذا الجهاز للنشر. التصفح يبقى متاحاً.';
    }
    _deviceId = id;
  }

  String _newDeviceId() {
    final random = _secureRandom();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  Random _secureRandom() {
    try {
      return Random.secure();
    } catch (_) {
      return Random();
    }
  }

  Future<void> refresh() {
    final current = _refreshing;
    if (current != null) return current;
    final run = _refreshBody();
    _refreshing = run.whenComplete(() {
      if (identical(_refreshing, run)) _refreshing = null;
    });
    return _refreshing!;
  }

  Future<void> _refreshBody() async {
    final quiet = _jobs.isNotEmpty;
    if (!quiet) {
      loading = true;
      error = null;
      _notify();
    }
    try {
      if (isDemo) {
        _jobs
          ..clear()
          ..addAll(buildDemoJobs());
        totalCount = _jobs.length;
      } else {
        final catalog = await _api.jobs();
        _jobs
          ..clear()
          ..addAll(catalog);
        totalCount = catalog.length;
        await _syncSideData();
      }
      lastUpdated = DateTime.now();
      isOffline = false;
      error = null;
      if (!isDemo) await _writeCache();
    } catch (exception) {
      isOffline = !isDemo;
      error = _message(
        exception,
        _jobs.isEmpty
            ? 'تعذّر الاتصال. تأكد من الإنترنت وحاول مجدداً.'
            : 'عم تشوف آخر نسخة محفوظة. التحديث ما مشي هلق.',
      );
    } finally {
      loading = false;
      _notify();
    }
  }

  Future<void> _syncSideData() async {
    try {
      fields = await _api.jobFields();
    } catch (_) {
      // Cached fields keep the publish form usable.
    }
    try {
      final remote = await _api.myJobs();
      _submissions
        ..removeWhere((submission) => !submission.isDemo)
        ..insertAll(
          0,
          remote.map((job) => Submission(job: job, createdAt: job.createdAt)),
        );
      await _persistSubmissions();
    } catch (_) {}
    try {
      final ids = await _api.favoriteIds();
      _savedIds
        ..clear()
        ..addAll(ids);
      await _persistSaved();
    } catch (_) {}
    try {
      notices = await _api.notices();
    } catch (_) {}
    try {
      maintenance = await _api.maintenanceMessage();
    } catch (_) {}
    final platform = kIsWeb
        ? 'web'
        : switch (defaultTargetPlatform) {
            TargetPlatform.iOS => 'ios',
            TargetPlatform.android => 'android',
            _ => 'web',
          };
    unawaited(_api.visit(platform));
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
  }

  void updateFilters(JobFilters value) {
    filters = value;
    _notify();
    unawaited(_persistDiscovery());
  }

  void showError(String message) {
    error = message;
    _notify();
  }

  void clearError() {
    error = null;
    _notify();
  }

  Future<void> toggleSaved(String id) async {
    final added = !_savedIds.remove(id);
    if (added) _savedIds.add(id);
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
      error = _message(exception, 'تعذّر تحديث المحفوظة. حاول مرة تانية.');
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
    _hiddenEmployers.add(_employerIdentity(job));
    await _preferences.setStringList(_key('hidden'), _hiddenEmployers.toList());
    _notify();
  }

  Future<void> unhideAllEmployers() async {
    _hiddenEmployers.clear();
    await _preferences.remove(_key('hidden'));
    _notify();
  }

  Future<void> _persistSubmissions() async {
    await _preferences.setString(
      _key('submissions'),
      jsonEncode(
        _submissions.map((submission) => submission.toJson()).toList(),
      ),
    );
  }

  Future<Submission> submit(Job draft, {bool contactConsent = false}) async {
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
      throw const JobsException('اختر مدة إعلان من 7 أو 14 أو 30 يوماً.');
    }
    busy = true;
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
      } else {
        if (fields.isEmpty) {
          try {
            fields = await _api.jobFields();
          } catch (_) {}
        }
        final fieldId = draft.jobFieldId ?? fieldIdFor(draft.category);
        if (fieldId == null) {
          throw const JobsException('اختَر مجال الشغل من القائمة.');
        }
        stored = await _api.createJob({
          'title': draft.title,
          'company_name': draft.company,
          'country': draft.country.trim().isEmpty ? 'سوريا' : draft.country,
          'state': draft.city,
          'job_field_id': fieldId,
          'job_type': draft.workType,
          'work_type': draft.workMode,
          'experience': draft.experience,
          'description': draft.description,
          if (draft.requirements.isNotEmpty)
            'requirements': draft.requirements.join('\n'),
          if (draft.phone.trim().isNotEmpty) 'phone': draft.phone.trim(),
          if (draft.email.trim().isNotEmpty) 'email': draft.email.trim(),
          'currency': draft.currency,
          'salary_period': draft.salaryPeriod,
          if (draft.salaryMin != null) 'salary_min': draft.salaryMin,
          if (draft.salaryMax != null) 'salary_max': draft.salaryMax,
          'listing_duration_days': expiresInDays,
        });
      }
      final submission = Submission(job: stored, createdAt: DateTime.now());
      _submissions.insert(0, submission);
      try {
        await _persistSubmissions();
      } catch (_) {
        throw JobsException(
          isDemo
              ? 'تعذّر حفظ الإعلان التجريبي على الجهاز.'
              : 'تم إرسال الإعلان، لكن تعذّر حفظ بياناته على الجهاز. لا تعاود إرساله.',
        );
      }
      return submission;
    } catch (exception) {
      final message = _message(
        exception,
        'لم يتم تأكيد إرسال الإعلان. تحقق من الاتصال قبل إعادة المحاولة.',
      );
      error = message;
      throw JobsException(message);
    } finally {
      busy = false;
      _notify();
    }
  }

  Future<Submission> refreshSubmission(Submission submission) async {
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
          'ما لقينا الإعلان على هذا الجهاز.',
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
    if (busy) throw const JobsException('انتظر انتهاء الطلب الحالي.');
    busy = true;
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
    final index = notices.indexWhere((notice) => notice.id == id);
    if (index == -1 || notices[index].read) return;
    final current = notices[index];
    notices[index] = RemoteNotice(
      id: current.id,
      text: current.text,
      read: true,
      createdAt: current.createdAt,
      jobId: current.jobId,
    );
    _notify();
    if (isDemo) return;
    try {
      await _api.markNoticeRead(id);
    } catch (_) {
      notices[index] = current;
      error = 'تعذّر تثبيت القراءة. حاول مرة تانية.';
      _notify();
    }
  }

  Future<void> report(Job job, String reason) async {
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
      exception is JobsException ? exception.message : fallback;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _client.close();
    super.dispose();
  }
}
