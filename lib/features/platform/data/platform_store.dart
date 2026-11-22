import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../../jobs/domain/job.dart';
import '../domain/platform_models.dart';
import 'social_identity.dart';

typedef SecretRead = Future<String?> Function(String key);
typedef SecretWrite = Future<void> Function(String key, String? value);

/// One account/API namespace, single-flight reads/refresh, encrypted bounded
/// snapshots and a durable message outbox. Mutations always use idempotency keys.
class PlatformStore extends ChangeNotifier {
  PlatformStore({
    required this.base,
    required http.Client client,
    SecretRead? readSecret,
    SecretWrite? writeSecret,
    this.requiresAccount = true,
  }) : _client = client,
       _read =
           readSecret ?? ((key) => const FlutterSecureStorage().read(key: key)),
       _write =
           writeSecret ??
           ((key, value) => value == null
               ? const FlutterSecureStorage().delete(key: key)
               : const FlutterSecureStorage().write(key: key, value: value));

  final String base;
  final bool requiresAccount;
  final http.Client _client;
  final SecretRead _read;
  final SecretWrite _write;
  Member? user;
  String? _access, _refresh;
  String _refreshKey = newId();
  Json capabilities = {};
  Json notificationPreferences = {};
  final Map<String, Json> _snapshots = {};
  final Map<String, Future<Json>> _reads = {};
  final Map<String, (Json, List<Job>)> _jobCache = {};
  Set<String>? _favoriteIdsCache;
  final Map<String, String?> _historyCursors = {};
  final Map<String, int> _pathVersions = {};
  void _changedPath(String path) =>
      _pathVersions[path] = (_pathVersions[path] ?? 0) + 1;
  final List<DateTime> _starts = [];
  final List<Json> _outbox = [];
  final Map<String, String> _operationKeys = {};
  Future<void>? _refreshing;
  Future<void>? _initializing;
  Future<void> _writes = Future.value();
  bool ready = false, disposed = false, stale = false;
  String? storageError;
  int _epoch = 0;
  DateTime? _cooldown;
  String? activeConversation;
  bool get signedIn => user != null && _refresh != null;
  bool get demo => base == 'demo';
  String get _sessionKey =>
      'snad.platform.${Uri.encodeComponent(base)}.session';
  String get _cacheKey =>
      'snad.platform.${Uri.encodeComponent(base)}.${user?.id}.private';

  static String newId() => List.generate(
    24,
    (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
  String operationKey(String operation) =>
      _operationKeys.putIfAbsent(operation, newId);
  void completed(String operation) => _operationKeys.remove(operation);

  Future<void> initialize() => _initializing ??= _restore();
  Future<void> _restore() async {
    final epoch = _epoch;
    try {
      final raw = await _read(_sessionKey);
      if (epoch != _epoch || disposed) return;
      if (raw != null) {
        final session = object(jsonDecode(raw));
        _access = session['access_token'] as String?;
        _refresh = session['refresh_token'] as String?;
        _refreshKey = textOf(session['refresh_request_id']).isEmpty
            ? newId()
            : textOf(session['refresh_request_id']);
        user = Member(object(session['user']));
        if (user!.id.isEmpty || _refresh == null || _access == null) {
          user = null;
          _access = null;
          _refresh = null;
        } else {
          final cached = await _read(_cacheKey);
          if (epoch != _epoch || disposed) return;
          if (cached != null) {
            final data = object(jsonDecode(cached));
            final at = DateTime.tryParse(textOf(data['cached_at']));
            if (at == null || DateTime.now().difference(at).inDays > 7) {
              ready = true;
              _notify();
              return;
            }
            _snapshots.addAll(
              object(data['snapshots']).map((k, v) => MapEntry(k, object(v))),
            );
            _favoriteIdsCache = null;
            _jobCache.clear();
            _outbox.addAll(
              objects(data['outbox'])
                  .take(50)
                  .map(
                    (r) => {...r, 'local_state': 'failed'}..remove('sending'),
                  ),
            );
            _operationKeys.addAll(
              object(data['operations']).map((k, v) => MapEntry(k, textOf(v))),
            );
            stale = true;
          }
        }
      }
    } catch (_) {
      user = null;
      _access = null;
      _refresh = null;
      storageError =
          'تعذّر فتح بيانات الحساب الآمنة. أعد فتح التطبيق؛ التصفح متاح.';
    }
    ready = true;
    _notify();
  }

  Future<Json> loadCapabilities() async {
    if (demo) {
      return capabilities = {
        'platform_enabled': true,
        'email_login': true,
        'google_login': true,
        'apple_login': true,
      };
    }
    try {
      capabilities = object(
        (await request('GET', '/capabilities', auth: false))['data'],
      );
      if (capabilities['platform_enabled'] != true) {
        throw const PlatformFailure(
          'خدمات الحسابات قيد التجهيز. يمكنك التصفح والمحاولة لاحقاً.',
        );
      }
      _notify();
      return capabilities;
    } on PlatformFailure catch (error) {
      if (error.status == 404 || error.status == 503) {
        throw const PlatformFailure(
          'خدمات الحسابات قيد التجهيز. يمكنك تصفح الفرص الآن والمحاولة لاحقاً.',
          code: 'platform_unavailable',
        );
      }
      rethrow;
    }
  }

  Future<Json> requestCode(String email) async {
    await loadCapabilities();
    if (demo) return {'challenge_id': 'demo', 'retry_after': 60};
    return object(
      (await request(
        'POST',
        '/auth/email/challenge',
        auth: false,
        body: {'email': email, 'locale': 'ar'},
        key: newId(),
      ))['data'],
    );
  }

  Future<void> verifyCode(String challenge, String code, String name) async {
    if (demo) {
      await demoLogin(name: name);
      return;
    }
    final result = await request(
      'POST',
      '/auth/email/verify',
      auth: false,
      body: {
        'challenge_id': challenge,
        'code': code,
        if (name.isNotEmpty) 'name': name,
        'terms_version': '2026-11-03',
      },
      key: newId(),
    );
    await _establish(object(result['data']));
  }

  Future<void> socialLogin(String provider) async {
    await loadCapabilities();
    if (capabilities['${provider}_login'] != true) {
      throw const PlatformFailure(
        'هذه الطريقة غير متاحة حالياً. استخدم البريد الإلكتروني.',
      );
    }
    if (demo) {
      await demoLogin();
      return;
    }
    final identity = await SocialIdentity.token(provider);
    final result = await request(
      'POST',
      '/auth/social',
      auth: false,
      body: {
        'firebase_id_token': identity,
        'provider': provider,
        'terms_version': '2026-11-03',
      },
      key: newId(),
    );
    await _establish(object(result['data']));
    await SocialIdentity.clear(); // Backend owns the long-lived session.
  }

  Future<void> _establish(Json session) async {
    await initialize();
    if (textOf(session['access_token']).isEmpty ||
        textOf(session['refresh_token']).isEmpty ||
        textOf(object(session['user'])['id']).isEmpty) {
      throw const PlatformFailure(
        'استجابة الدخول غير مكتملة. لم يتم فتح جلسة.',
      );
    }
    // Persist before exposing success. Never store tokens in SharedPreferences.
    _refreshKey = newId();
    try {
      await _storeSecret(
        _sessionKey,
        jsonEncode({...session, 'refresh_request_id': _refreshKey}),
      );
    } catch (_) {
      throw const PlatformFailure(
        'تعذّر حفظ جلسة الحساب بشكل آمن. تحقق من تخزين الجهاز ثم أعد المحاولة.',
      );
    }
    storageError = null;
    _epoch++;
    _cooldown = null;
    _snapshots.clear();
    _jobCache.clear();
    _favoriteIdsCache = null;
    _outbox.clear();
    _operationKeys.clear();
    _reads.clear();
    _historyCursors.clear();
    _access = textOf(session['access_token']);
    _refresh = textOf(session['refresh_token']);
    user = Member(object(session['user']));
    stale = false;
    _notify();
  }

  @visibleForTesting
  Future<void> demoLogin({String name = 'مستخدم العرض'}) async {
    if (!demo) throw StateError('Demo accounts cannot authenticate a live API');
    await _establish({
      'access_token': 'demo',
      'refresh_token': 'demo',
      'user': {
        'id': 'demo-member',
        'name': name.isEmpty ? 'مستخدم العرض' : name,
        'email': 'preview@example.test',
      },
    });
  }

  Future<void> logout() async {
    final refresh = _refresh;
    if (!demo && signedIn) {
      // If revocation cannot reach the API, keep the account visible so the
      // user can retry; never leave a push registration silently linked.
      await request(
        'POST',
        '/auth/logout',
        body: {'refresh_token': refresh},
        key: newId(),
      );
    }
    await _clear();
    await SocialIdentity.clear();
  }

  Future<void> _clear() async {
    final cache = _cacheKey;
    _epoch++;
    _cooldown = null;
    _access = null;
    _refresh = null;
    user = null;
    _snapshots.clear();
    _jobCache.clear();
    _favoriteIdsCache = null;
    _reads.clear();
    _historyCursors.clear();
    _pathVersions.clear();
    _outbox.clear();
    _operationKeys.clear();
    notificationPreferences = {};
    activeConversation = null;
    _notify();
    await _writes.catchError((Object _) {});
    await _storeSecret(cache, null);
    await _storeSecret(_sessionKey, null);
  }

  Future<void> deleteAccount(String reauthTicket) async {
    if (!demo) {
      await request(
        'DELETE',
        '/me',
        body: {'reauth_ticket': reauthTicket},
        key: operationKey('delete-account'),
      );
    }
    await _clear();
    await SocialIdentity.clear();
  }

  Future<void> refreshSession() =>
      _refreshing ??= _rotate().whenComplete(() => _refreshing = null);
  Future<void> _rotate() async {
    final epoch = _epoch, refresh = _refresh;
    if (refresh == null) {
      throw const PlatformFailure('يرجى تسجيل الدخول للمتابعة.', status: 401);
    }
    try {
      final response = await request(
        'POST',
        '/auth/refresh',
        auth: false,
        body: {'refresh_token': refresh},
        key: _refreshKey,
      );
      if (epoch != _epoch) {
        throw const PlatformFailure('تغيّر الحساب. أعد المحاولة.');
      }
      final data = object(response['data']);
      if (textOf(data['access_token']).isEmpty ||
          textOf(data['refresh_token']).isEmpty) {
        throw const PlatformFailure('تعذّر تجديد الجلسة.');
      }
      final nextRefreshKey = newId();
      await _storeSecret(
        _sessionKey,
        jsonEncode({
          ...data,
          'user': user!.data,
          'refresh_request_id': nextRefreshKey,
        }),
      );
      if (epoch != _epoch) return;
      _refreshKey = nextRefreshKey;
      _access = textOf(data['access_token']);
      _refresh = textOf(data['refresh_token']);
      completed('refresh');
    } on PlatformFailure catch (error) {
      if ((error.status == 401 || error.status == 403) && epoch == _epoch) {
        await _clear();
      }
      rethrow;
    }
  }

  Future<Json> request(
    String method,
    String path, {
    Json? body,
    String? key,
    bool auth = true,
    bool retry401 = true,
  }) async {
    if (!path.startsWith('/') ||
        path.startsWith('//') ||
        path.contains('..') ||
        path.contains('\\')) {
      throw ArgumentError('Invalid API path');
    }
    if (auth && !signedIn) {
      throw const PlatformFailure('يرجى تسجيل الدخول للمتابعة.', status: 401);
    }
    if (_cooldown != null && DateTime.now().isBefore(_cooldown!)) {
      throw const PlatformFailure(
        'طلبات كثيرة. انتظر قليلاً ثم أعد المحاولة.',
        status: 429,
      );
    }
    final now = DateTime.now();
    _starts.removeWhere((started) => now.difference(started).inSeconds >= 60);
    if (_starts.length >= 50) {
      throw const PlatformFailure(
        'يرجى الانتظار قليلاً قبل متابعة الطلبات.',
        status: 429,
      );
    }
    _starts.add(now);
    final root = Uri.parse(base);
    if (root.scheme != 'https' &&
        !(kDebugMode &&
            root.scheme == 'http' &&
            ['localhost', '127.0.0.1', '10.0.2.2'].contains(root.host))) {
      throw const PlatformFailure('عنوان الخدمة غير آمن.');
    }
    final epoch = _epoch;
    if (auth && method != 'GET' && key != null) await _persist();
    if (auth && epoch != _epoch) {
      throw const PlatformFailure('تغيّر الحساب. أعد المحاولة.');
    }
    final uri = Uri.parse('$base/api/v2$path');
    final outgoing = http.Request(method, uri)
      ..followRedirects = false
      ..headers.addAll({
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        if (auth) 'Authorization': 'Bearer $_access',
        'Idempotency-Key': ?key,
      });
    if (body != null) outgoing.body = jsonEncode(body);
    try {
      final streamed = await _client
          .send(outgoing)
          .timeout(const Duration(seconds: 25));
      final builder = BytesBuilder(copy: false);
      await for (final chunk in streamed.stream.timeout(
        const Duration(seconds: 25),
      )) {
        if (builder.length + chunk.length > 2 * 1024 * 1024) {
          throw const PlatformFailure('حجم الاستجابة أكبر من المسموح.');
        }
        builder.add(chunk);
      }
      final response = http.Response.bytes(
        builder.takeBytes(),
        streamed.statusCode,
        headers: streamed.headers,
      );
      if (auth && epoch != _epoch) {
        throw const PlatformFailure('تغيّر الحساب. أعد فتح الصفحة.');
      }
      if (response.statusCode == 401 && auth && retry401) {
        await refreshSession();
        if (epoch != _epoch) {
          throw const PlatformFailure(
            'انتهت الجلسة. يرجى تسجيل الدخول.',
            status: 401,
          );
        }
        return request(
          method,
          path,
          body: body,
          key: key,
          auth: auth,
          retry401: false,
        );
      }
      if (response.statusCode == 401 && auth && !retry401) {
        await _clear();
        throw const PlatformFailure(
          'انتهت جلسة الحساب. يرجى تسجيل الدخول.',
          status: 401,
        );
      }
      Json data = {};
      try {
        data = object(jsonDecode(response.body));
      } catch (_) {
        /* HTML errors are not shown to users. */
      }
      if (response.statusCode == 429) {
        final seconds =
            int.tryParse(response.headers['retry-after'] ?? '') ?? 30;
        _cooldown = DateTime.now().add(
          Duration(seconds: seconds.clamp(1, 300)),
        );
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final error = object(data['error']);
        throw PlatformFailure(
          textOf(error['message']).isEmpty
              ? 'تعذّر إتمام الطلب. حاول مجدداً.'
              : textOf(error['message']),
          status: response.statusCode,
          code: textOf(error['code']),
          uncertain: method != 'GET' && response.statusCode >= 500,
        );
      }
      if (!data.containsKey('data')) {
        throw PlatformFailure(
          'وصلت استجابة غير مكتملة من الخدمة. أعد المحاولة أو حدّث بياناتك قبل تكرار الإرسال.',
          status: 502,
          code: 'invalid_response',
          uncertain: method != 'GET',
        );
      }
      return data;
    } on PlatformFailure {
      rethrow;
    } catch (_) {
      throw PlatformFailure(
        'تعذّر الاتصال. تحقق من الشبكة ثم أعد المحاولة.',
        uncertain: method != 'GET',
      );
    }
  }

  Json snapshot(String path) => _snapshots[path] ?? {};
  Future<void> loadMore(String path) async {
    final cursor = object(snapshot(path)['meta'])['next_cursor'];
    if (cursor == null) return;
    final epoch = _epoch;
    final version = _pathVersions[path] ?? 0;
    final next = await request(
      'GET',
      '$path${path.contains('?') ? '&' : '?'}cursor=${Uri.encodeComponent(textOf(cursor))}',
    );
    if (epoch != _epoch || version != (_pathVersions[path] ?? 0)) return;
    if (path.endsWith('/messages')) {
      _historyCursors[path] = object(next['meta'])['next_cursor'] as String?;
    }
    final rows = {
      for (final row in [
        ...objects(snapshot(path)['data']),
        ...objects(next['data']),
      ])
        textOf(row['id']): row,
    };
    _snapshots[path] = {...next, 'data': rows.values.toList()};
    await _persist();
    _notify();
  }

  Future<Json> load(String path) {
    final pending = _reads[path];
    if (pending != null) return pending;
    late final Future<Json> run;
    run = _load(path).whenComplete(() {
      if (identical(_reads[path], run)) _reads.remove(path);
    });
    _reads[path] = run;
    return run;
  }

  Future<Json> _load(String path) async {
    final epoch = _epoch;
    final version = _pathVersions[path] ?? 0;
    try {
      Json data;
      try {
        data = demo ? _demoRead(path) : await request('GET', path);
      } on PlatformFailure catch (error) {
        if (error.status != null || demo) rethrow;
        await Future<void>.delayed(const Duration(milliseconds: 600));
        if (epoch != _epoch || disposed) return {};
        data = await request('GET', path);
      }
      if (epoch != _epoch || version != (_pathVersions[path] ?? 0)) return {};
      if (data['data'] is! Map && data['data'] is! List) {
        throw const PlatformFailure(
          'تعذّر قراءة بيانات الصفحة من الخدمة.',
          status: 502,
          code: 'invalid_response',
        );
      }
      if (path == '/me' && data['data'] is Map) {
        final member = Member(object(data['data']));
        if (member.id != user?.id) {
          throw const PlatformFailure(
            'تعذّر التحقق من صاحب الحساب. أعد تسجيل الدخول.',
            status: 401,
          );
        }
        user = member;
      }
      if (path.endsWith('/messages')) {
        final combined = {
          for (final row in [
            ...objects(snapshot(path)['data']),
            ...objects(data['data']),
          ])
            textOf(row['id']): row,
        };
        final sorted = combined.values.toList()
          ..sort(
            (a, b) =>
                textOf(a['created_at']).compareTo(textOf(b['created_at'])),
          );
        data = {
          ...data,
          'data': sorted,
          if (_historyCursors.containsKey(path))
            'meta': {
              ...object(data['meta']),
              'next_cursor': _historyCursors[path],
            },
        };
      }
      _snapshots[path] = data;
      if (path == '/me/favorite-ids') _favoriteIdsCache = null;
      stale = false;
      // Keep only five threads and the main account lists in the private cache.
      final threads = _snapshots.keys
          .where((k) => k.contains('/messages'))
          .toList();
      while (threads.length > 5) {
        _snapshots.remove(threads.removeAt(0));
      }
      while (_snapshots.length > 24) {
        _snapshots.remove(_snapshots.keys.first);
      }
      await _cacheBestEffort();
      _notify();
      return data;
    } catch (e) {
      if (epoch != _epoch || version != (_pathVersions[path] ?? 0)) return {};
      if (e is PlatformFailure && [403, 404, 410].contains(e.status)) {
        _snapshots.remove(path);
      }
      stale = true;
      _notify();
      rethrow;
    }
  }

  Future<void> _persist() {
    if (!signedIn) return Future.value();
    final cacheKey = _cacheKey;
    final bounded = <String, Json>{};
    for (final entry in _snapshots.entries) {
      final rows = entry.value['data'];
      if (rows is List) {
        final limit = entry.key.endsWith('/messages')
            ? 50
            : entry.key == '/me/favorite-ids'
            ? 10000
            : 20;
        final kept = entry.key.endsWith('/messages')
            ? rows.skip((rows.length - limit).clamp(0, rows.length)).toList()
            : rows.take(limit).toList();
        bounded[entry.key] = {
          ...entry.value,
          'data': kept,
          if (rows.length > limit || entry.key.endsWith('/messages'))
            'meta': {...object(entry.value['meta']), 'next_cursor': null},
        };
      } else {
        bounded[entry.key] = entry.value;
      }
    }
    final at = DateTime.now().toUtc().toIso8601String();
    var encoded = jsonEncode({
      'snapshots': bounded,
      'outbox': _outbox,
      'operations': _operationKeys,
      'cached_at': at,
    });
    while (utf8.encode(encoded).length > 768 * 1024 && bounded.isNotEmpty) {
      bounded.remove(bounded.keys.first);
      encoded = jsonEncode({
        'snapshots': bounded,
        'outbox': _outbox,
        'operations': _operationKeys,
        'cached_at': at,
      });
    }
    final next = _writes
        .catchError((Object _) {})
        .then((_) => _write(cacheKey, encoded));
    _writes = next;
    return next;
  }

  Future<void> _storeSecret(String key, String? value) {
    final next = _writes
        .catchError((Object _) {})
        .then((_) => _write(key, value));
    _writes = next;
    return next;
  }

  Future<void> _cacheBestEffort() async {
    try {
      await _persist();
      storageError = null;
    } catch (_) {
      storageError =
          'تم تحديث البيانات على الخادم، لكن تعذّر حفظ نسخة على هذا الجهاز.';
    }
  }

  Set<String> get favoriteIds => _favoriteIdsCache ??= Set<String>.unmodifiable(
    (snapshot('/me/favorite-ids')['data'] as List? ?? []).map(textOf),
  );

  List<Job> _parsedJobs(String path) {
    if (!_snapshots.containsKey(path)) return const [];
    final data = snapshot(path), cached = _jobCache[path];
    if (cached != null && identical(cached.$1, data)) return cached.$2;
    final jobs = List<Job>.unmodifiable(objects(data['data']).map(Job.fromApi));
    _jobCache[path] = (data, jobs);
    return jobs;
  }

  List<Job> get favorites => _parsedJobs('/me/favorites');
  List<Job> get postings => _parsedJobs('/me/jobs');
  Future<void> rememberDemoJob(Job job) async {
    if (!demo) throw StateError('Not a demo');
    _snapshots['/me/jobs'] = {
      'data': [_jobJson(job), ...objects(snapshot('/me/jobs')['data'])],
    };
    await _cacheBestEffort();
    _notify();
  }

  final Map<String, Job> demoJobs = {};
  Future<void> setFavorite(String id, bool saved) async {
    final result = demo
        ? {
            'data': demoJobs.containsKey(id)
                ? _jobJson(demoJobs[id]!)
                : <String, dynamic>{},
          }
        : await request(
            saved ? 'PUT' : 'DELETE',
            '/me/favorites/${Uri.encodeComponent(id)}',
            key: operationKey('favorite-$id-$saved'),
          );
    completed('favorite-$id-$saved');
    _changedPath('/me/favorites');
    _changedPath('/me/favorite-ids');
    final ids = Set<String>.of(favoriteIds);
    if (saved) {
      ids.add(id);
    } else {
      ids.remove(id);
    }
    _snapshots['/me/favorite-ids'] = {'data': ids.toList()};
    _favoriteIdsCache = Set<String>.unmodifiable(ids);
    final rows = objects(snapshot('/me/favorites')['data'])
      ..removeWhere((row) => textOf(row['id']) == id);
    final job = object(result['data']);
    if (saved && job.isNotEmpty) rows.insert(0, job);
    _snapshots['/me/favorites'] = {...snapshot('/me/favorites'), 'data': rows};
    await _cacheBestEffort();
    _notify();
  }

  Future<Job> createJob(Json body) async {
    final response = await request(
      'POST',
      '/jobs',
      body: body,
      key: operationKey(
        'create-job-${sha256.convert(utf8.encode(jsonEncode(body)))}',
      ),
    );

    final raw = object(response['data']);
    if (textOf(raw['id']).isEmpty ||
        DateTime.tryParse(textOf(raw['created_at'])) == null) {
      throw const PlatformFailure(
        'لم يتم تأكيد تفاصيل الإعلان. حدّث إعلاناتك قبل إعادة الإرسال.',
        uncertain: true,
      );
    }
    final job = Job.fromApi(raw);
    completed('create-job-${sha256.convert(utf8.encode(jsonEncode(body)))}');
    _changedPath('/me/jobs');
    _snapshots['/me/jobs'] = {
      'data': [
        object(response['data']),
        ...objects(
          snapshot('/me/jobs')['data'],
        ).where((row) => textOf(row['id']) != job.id),
      ],
    };
    await _cacheBestEffort();
    _notify();
    return job;
  }

  Future<void> withdrawJob(String id) async {
    if (demo) {
      _snapshots['/me/jobs'] = {
        'data': objects(snapshot('/me/jobs')['data'])
            .map(
              (r) => textOf(r['id']) == id ? {...r, 'status': 'withdrawn'} : r,
            )
            .toList(),
      };
      await _cacheBestEffort();
      _notify();
      return;
    }
    await request(
      'POST',
      '/jobs/${Uri.encodeComponent(id)}/withdraw',
      body: {},
      key: operationKey('withdraw-job-$id'),
    );
    completed('withdraw-job-$id');
    await load('/me/jobs');
  }

  Future<ApplicationRecord> apply(Job job, String note) async {
    if (demo) {
      final data = {
        'id': 'demo-application',
        'job': _jobJson(job),
        'applicant': user!.data,
        'status': 'submitted',
        'note': note,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
        'history': [
          {
            'status': 'submitted',
            'at': DateTime.now().toUtc().toIso8601String(),
          },
        ],
      };
      _snapshots['/me/applications'] = {
        'data': [data, ...objects(snapshot('/me/applications')['data'])],
      };
      await _cacheBestEffort();
      _notify();
      return ApplicationRecord(data);
    }
    final result = await request(
      'POST',
      '/jobs/${Uri.encodeComponent(job.id)}/applications',
      body: {'note': note},
      key: operationKey('apply-${job.id}-${sha256.convert(utf8.encode(note))}'),
    );

    final data = object(result['data']);
    if (textOf(data['id']).isEmpty || object(data['job']).isEmpty) {
      throw const PlatformFailure(
        'لم يتم تأكيد تفاصيل الطلب. راجع طلباتك قبل إعادة التقديم.',
        uncertain: true,
      );
    }
    completed('apply-${job.id}-${sha256.convert(utf8.encode(note))}');
    _changedPath('/me/applications');
    _snapshots['/me/applications'] = {
      'data': [
        data,
        ...objects(
          snapshot('/me/applications')['data'],
        ).where((v) => v['id'] != data['id']),
      ],
    };
    await _cacheBestEffort();
    _notify();
    return ApplicationRecord(data);
  }

  Future<void> applicationAction(
    String id,
    String status, {
    String note = '',
    required int expectedVersion,
  }) async {
    if (!applicationLabels.containsKey(status)) {
      throw ArgumentError('Unknown status');
    }
    if (!demo) {
      await request(
        'PATCH',
        '/applications/${Uri.encodeComponent(id)}',
        body: {
          'status': status,
          'note': note,
          'expected_version': expectedVersion,
        },
        key: operationKey('application-$id-$status-$expectedVersion'),
      );
    }
    completed('application-$id-$status-$expectedVersion');
    for (final path in {..._snapshots.keys, ..._reads.keys}) {
      final entry = MapEntry(path, snapshot(path));
      final uri = Uri.parse(entry.key);
      if (uri.path == '/me/applications' ||
          RegExp(r'^/jobs/[^/]+/applications$').hasMatch(uri.path)) {
        _changedPath(entry.key);
        // A read started before the mutation must not restore the old status.
        _reads.remove(entry.key);
        final selectedStatus = uri.queryParameters['status'];
        _snapshots[entry.key] = {
          ...entry.value,
          'data': objects(entry.value['data'])
              .map(
                (row) => textOf(row['id']) == id
                    ? {...row, 'status': status, 'version': expectedVersion + 1}
                    : row,
              )
              .where(
                (row) =>
                    selectedStatus == null || selectedStatus == row['status'],
              )
              .toList(),
        };
        if (!demo) {
          unawaited(load(entry.key).catchError((_) => <String, dynamic>{}));
        }
      }
    }
    await _cacheBestEffort();
    _notify();
  }

  Future<Conversation> startConversation(String applicationId) async {
    final result = demo
        ? {
            'data': {
              'id': 'demo-chat',
              'peer': {'id': 'demo-peer', 'name': 'جهة عمل توضيحية'},
              'job_title': 'فرصة توضيحية',
              'can_send': true,
            },
          }
        : await request(
            'POST',
            '/applications/${Uri.encodeComponent(applicationId)}/conversation',
            body: {},
            key: operationKey('conversation-$applicationId'),
          );
    final conversation = Conversation(object(result['data']));
    if (conversation.id.isEmpty) {
      throw const PlatformFailure(
        'تعذّر تأكيد المحادثة. حاول مجدداً.',
        uncertain: true,
      );
    }
    completed('conversation-$applicationId');
    _snapshots['/conversations'] = {
      'data': [
        conversation.data,
        ...objects(
          snapshot('/conversations')['data'],
        ).where((r) => r['id'] != conversation.id),
      ],
    };
    _notify();
    return conversation;
  }

  List<ChatMessage> messages(String id) {
    final rows = objects(snapshot('/conversations/$id/messages')['data']);
    final clientIds = rows.map((r) => textOf(r['client_id'])).toSet();
    return [
      ...rows.map(ChatMessage.new),
      ..._outbox
          .where(
            (r) =>
                r['conversation_id'] == id &&
                !clientIds.contains(r['client_id']),
          )
          .map(ChatMessage.new),
    ];
  }

  Future<void> sendMessage(String id, String text) async {
    if (_outbox.length >= 50) {
      throw const PlatformFailure(
        'أكمل إرسال الرسائل المعلّقة قبل إضافة رسائل جديدة.',
      );
    }
    final value = text.trim();
    if (value.isEmpty || value.length > 4000) {
      throw const PlatformFailure('اكتب رسالة من 1 إلى 4000 محرف.');
    }
    final Json local = {
      'conversation_id': id,
      'client_id': newId(),
      'sender_id': user!.id,
      'text': value,
      'local_state': 'pending',
      'created_at': DateTime.now().toUtc().toIso8601String(),
    };
    _outbox.add(local);
    try {
      await _persist();
    } catch (_) {
      _outbox.remove(local);
      rethrow;
    }
    _notify();
    await retryMessage(local['client_id']!);
  }

  Future<void> discardMessage(String clientId) async {
    _outbox.removeWhere(
      (row) => row['client_id'] == clientId && row['sending'] != true,
    );
    await _cacheBestEffort();
    _notify();
  }

  Future<void> retryMessage(String clientId) async {
    final matches = _outbox.where((r) => r['client_id'] == clientId).toList();
    if (matches.isEmpty) return;
    final row = matches.first;
    if (row['sending'] == true) return;
    final epoch = _epoch;
    row['sending'] = true;
    row['local_state'] = 'pending';
    _notify();
    try {
      final id = textOf(row['conversation_id']);
      final response = demo
          ? {
              'data': {...row, 'id': newId(), 'delivery_state': 'sent'},
            }
          : await request(
              'POST',
              '/conversations/$id/messages',
              body: {'client_id': clientId, 'text': row['text']},
              key: clientId,
            );
      if (epoch != _epoch) return;
      final message = object(response['data'])
        ..remove('local_state')
        ..remove('sending');
      if (textOf(message['id']).isEmpty ||
          message['client_id'] != clientId ||
          message['sender_id'] != user?.id) {
        throw const PlatformFailure(
          'تعذّر تأكيد الرسالة من الخادم. أعد المحاولة بنفس الرسالة.',
          uncertain: true,
        );
      }
      final existing = objects(snapshot('/conversations/$id/messages')['data']);
      existing.removeWhere(
        (m) => m['client_id'] == clientId || m['id'] == message['id'],
      );
      _snapshots['/conversations/$id/messages'] = {
        'data': [...existing, message],
      };
      _outbox.remove(row);
    } catch (_) {
      if (epoch == _epoch) row['local_state'] = 'failed';
      rethrow;
    } finally {
      row.remove('sending');
      if (epoch == _epoch) {
        await _cacheBestEffort();
        _notify();
      }
    }
  }

  Future<void> markRead(String id, String messageId) async {
    if (messageId.isEmpty || demo) return;
    await request(
      'PUT',
      '/conversations/$id/read',
      body: {'message_id': messageId},
      key: newId(),
    );
  }

  Future<void> block(String peerId, bool blocked) async {
    if (!demo) {
      await request(
        blocked ? 'PUT' : 'DELETE',
        '/me/blocks/${Uri.encodeComponent(peerId)}',
        key: operationKey('block-$peerId-$blocked'),
      );
    }
    completed('block-$peerId-$blocked');
    _changedPath('/conversations');
    _snapshots['/conversations'] = {
      ...snapshot('/conversations'),
      'data': objects(snapshot('/conversations')['data'])
          .map(
            (row) => textOf(object(row['peer'])['id']) == peerId
                ? {...row, 'blocked_by_me': blocked, 'can_send': !blocked}
                : row,
          )
          .toList(),
    };
    await _cacheBestEffort();
    _notify();
  }

  Future<void> updateProfile(Json profile) async {
    final result = demo
        ? {
            'data': {...user!.data, ...profile},
          }
        : await request(
            'PATCH',
            '/me',
            body: profile,
            key: operationKey('profile'),
          );
    final updated = Member(object(result['data']));
    if (updated.id.isEmpty || updated.id != user?.id) {
      throw const PlatformFailure(
        'تعذّر تأكيد بيانات الملف. حاول مجدداً.',
        uncertain: true,
      );
    }
    user = updated;
    completed('profile');
    await _storeSecret(
      _sessionKey,
      jsonEncode({
        'access_token': _access,
        'refresh_token': _refresh,
        'refresh_request_id': _refreshKey,
        'user': user!.data,
      }),
    );
    _notify();
  }

  Future<void> linkIdentity(String provider) async {
    if (demo) return;
    final token = await SocialIdentity.token(provider);
    try {
      final result = await request(
        'POST',
        '/me/identities',
        body: {'provider': provider, 'firebase_id_token': token},
        key: newId(),
      );
      final linked = Member(object(result['data']));
      if (linked.id.isEmpty || linked.id != user?.id) {
        throw const PlatformFailure(
          'تعذّر تأكيد ربط الحساب. حاول مجدداً.',
          uncertain: true,
        );
      }
      user = linked;
      await _storeSecret(
        _sessionKey,
        jsonEncode({
          'access_token': _access,
          'refresh_token': _refresh,
          'refresh_request_id': _refreshKey,
          'user': user!.data,
        }),
      );
      _notify();
    } finally {
      await SocialIdentity.clear();
    }
  }

  Future<void> savePreferences(Json value) async {
    final result = demo
        ? {'data': value}
        : await request(
            'PUT',
            '/me/notification-preferences',
            body: value,
            key: operationKey('preferences'),
          );
    completed('preferences');
    notificationPreferences = object(result['data']);
    _snapshots['/me/notification-preferences'] = result;
    await _cacheBestEffort();
    _notify();
  }

  Future<void> saveSearch(Json search) async {
    final response = demo
        ? {
            'data': {...search, 'id': newId()},
          }
        : await request(
            'POST',
            '/me/saved-searches',
            body: search,
            key: operationKey('saved-search-${jsonEncode(search)}'),
          );
    completed('saved-search-${jsonEncode(search)}');
    _changedPath('/me/saved-searches');
    _snapshots['/me/saved-searches'] = {
      'data': [
        object(response['data']),
        ...objects(snapshot('/me/saved-searches')['data']),
      ],
    };
    await _cacheBestEffort();
    _notify();
  }

  Future<void> removeSearch(String id) async {
    if (!demo) {
      await request(
        'DELETE',
        '/me/saved-searches/${Uri.encodeComponent(id)}',
        key: operationKey('remove-search-$id'),
      );
    }
    completed('remove-search-$id');
    _changedPath('/me/saved-searches');
    _snapshots['/me/saved-searches'] = {
      'data': objects(
        snapshot('/me/saved-searches')['data'],
      ).where((row) => textOf(row['id']) != id).toList(),
    };
    await _cacheBestEffort();
    _notify();
  }

  Future<String> uploadComplaintImage(Uint8List bytes, String mime) async {
    if (bytes.length > 5 * 1024 * 1024 ||
        !['image/jpeg', 'image/png', 'image/webp'].contains(mime)) {
      throw const PlatformFailure(
        'اختر صورة JPG أو PNG أو WebP بحجم لا يتجاوز 5 ميغابايت.',
      );
    }
    if (demo) return 'demo-image';
    final operation = 'upload-${sha256.convert(bytes)}';
    final response = await request(
      'POST',
      '/uploads',
      body: {
        'purpose': 'complaint',
        'mime_type': mime,
        'content_base64': base64Encode(bytes),
      },
      key: operationKey(operation),
    );
    final id = textOf(object(response['data'])['id']);
    if (id.isEmpty) {
      throw const PlatformFailure(
        'تعذّر تأكيد رفع الصورة. حاول مجدداً.',
        uncertain: true,
      );
    }
    completed(operation);
    return id;
  }

  Future<Json> complaint(
    String text,
    String? imageId, {
    String? conversationId,
  }) async {
    final response = demo
        ? {
            'data': {'id': newId(), 'status': 'open', 'text': text},
          }
        : await request(
            'POST',
            '/complaints',
            body: {
              'text': text,
              'image_id': ?imageId,
              'conversation_id': ?conversationId,
            },
            key: operationKey('complaint'),
          );
    final data = object(response['data']);
    if (textOf(data['id']).isEmpty) {
      throw const PlatformFailure(
        'تعذّر تأكيد إرسال الشكوى. حاول مجدداً.',
        uncertain: true,
      );
    }
    completed('complaint');
    _snapshots['/me/complaints'] = {
      'data': [data, ...objects(snapshot('/me/complaints')['data'])],
    };
    await _cacheBestEffort();
    _notify();
    return data;
  }

  Future<void> registerPush(String token, String platform) async {
    if (!signedIn || demo) return;
    await request(
      'PUT',
      '/me/push-device',
      body: {'fcm_token': token, 'platform': platform},
      key: newId(),
    );
  }

  Future<void> markNoticeRead(String id) async {
    if (!demo) {
      await request(
        'PUT',
        '/me/notifications/${Uri.encodeComponent(id)}/read',
        key: newId(),
      );
    }
    _changedPath('/me/notifications');
    final current = snapshot('/me/notifications');
    final rows = objects(current['data'])
        .map(
          (row) => textOf(row['id']) == id
              ? {
                  ...row,
                  'is_read': true,
                  'read_at': DateTime.now().toUtc().toIso8601String(),
                }
              : row,
        )
        .toList();
    _snapshots['/me/notifications'] = {
      ...current,
      'data': rows,
      'meta': {
        ...object(current['meta']),
        'unread_count': rows.where((row) => row['is_read'] != true).length,
      },
    };
    await _cacheBestEffort();
    _notify();
  }

  Future<void> matchAction(Iterable<String> ids, {required bool read}) async {
    final chosen = ids.toSet();
    if (!demo) {
      await request(
        'PUT',
        '/me/saved-search-matches/${read ? 'read' : 'acknowledge'}',
        body: {'job_ids': chosen.toList()},
        key: newId(),
      );
    }
    _changedPath('/me/saved-search-matches');
    final current = snapshot('/me/saved-search-matches');
    _snapshots['/me/saved-search-matches'] = {
      ...current,
      'data': objects(current['data'])
          .map(
            (row) => chosen.contains(textOf(row['id']))
                ? {...row, if (read) 'is_new': false else 'announced': true}
                : row,
          )
          .toList(),
    };
    await _cacheBestEffort();
    _notify();
  }

  Json _demoRead(String path) => _snapshots[path] ?? {'data': <Json>[]};
  static Json _jobJson(Job j) => {
    'id': j.id,
    'title': j.title,
    'company_name': j.company,
    'country': j.country,
    'state': j.city,
    'description': j.description,
    'status': j.status,
    'created_at': j.createdAt.toUtc().toIso8601String(),
    'expires_at': j.expiresAt.toUtc().toIso8601String(),
    'job_type': j.workType,
    'work_type': j.workMode,
    'currency': j.currency,
    'phone': j.phone,
    'email': j.email,
    'requirements': j.requirements,
    'salary_min': j.salaryMin,
    'salary_max': j.salaryMax,
    'salary_period': j.salaryPeriod,
    'accepts_applications': j.acceptsApplications,
  };
  void _notify() {
    if (!disposed) notifyListeners();
  }

  @override
  void dispose() {
    disposed = true;
    super.dispose();
  }
}
