import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../domain/job.dart';
import '../domain/job_filters.dart';
import '../domain/job_geography.dart';

class JobsException implements Exception {
  const JobsException(
    this.message, {
    this.statusCode,
    this.uncertainOutcome = false,
  });
  final String message;
  final int? statusCode;
  final bool uncertainOutcome;
  @override
  String toString() => message;
}

/// Live SND API at `https://admin.jobsnad.com`.
///
/// Reads are cached by the store and retried. Non-idempotent writes are sent
/// once: a connection failure or server error can happen after a commit.
class SndApi {
  SndApi({
    required this.base,
    required http.Client client,
    required this.deviceId,
  }) : _client = client;

  final String base;
  final String deviceId;
  final http.Client _client;
  final _random = Random();

  Future<List<JobField>> jobFields() async {
    final payload = await _send('GET', '/api/job-fields');
    return [
      for (final row in _rows(payload))
        if (row['is_active'] != false)
          JobField(
            id: (row['id'] as num).toInt(),
            nameAr: (row['name_ar'] as String? ?? row['name'] as String? ?? '')
                .trim(),
            nameEn: (row['name_en'] as String? ?? row['name'] as String? ?? '')
                .trim(),
            slug: (row['slug'] as String? ?? '').trim(),
            icon: (row['icon'] as String? ?? '').trim(),
          ),
    ].where((field) => field.nameAr.isNotEmpty).toList();
  }

  /// The live service caps `/api/jobs` at 30 rows per page even when 50 is
  /// requested, so the catalog spans several pages.
  Future<List<Job>> jobs() => _publicPages('/api/jobs', const {
    'per_page': '50',
  }, 'تعذّر تحميل قائمة الفرص كاملة. حاول التحديث.');

  /// Reads page 1 for `last_page`, then the rest a few pages at a time and
  /// merges them in page order. One request per page in sequence made the
  /// first load wait for every round trip.
  Future<List<Job>> _publicPages(
    String path,
    Map<String, String> query,
    String incomplete,
  ) async {
    Future<Map<String, dynamic>> read(int page) =>
        _send('GET', path, query: {...query, 'page': '$page'});
    final first = await read(1);
    final lastPage = _lastPage(first);
    if (lastPage > 40) throw JobsException(incomplete);
    final pages = [first];
    for (var start = 2; start <= lastPage; start += 4) {
      pages.addAll(
        await Future.wait([
          for (var page = start; page <= min(start + 3, lastPage); page++)
            read(page),
        ]),
      );
    }
    final collected = <String, Job>{};
    for (final (index, payload) in pages.indexed) {
      final rows = _publicJobRows(payload);
      if (rows.isEmpty && index + 1 < lastPage) {
        throw JobsException(incomplete);
      }
      for (final row in rows) {
        final job = Job.fromApi(row, fromCatalog: true);
        if (!job.isDemo && job.isAvailable) collected[job.id] = job;
      }
    }
    return collected.values.toList();
  }

  /// Fetches every page matching the public collection's filter contract.
  /// The store also applies its local filters to the complete catalog so a
  /// server-side filter can add fresh results without hiding local matches.
  Future<List<Job>> filteredJobs({
    required String search,
    required JobFilters filters,
    required int? categoryId,
  }) => _publicPages(
    '/api/filterjob',
    _discoveryQuery(search, filters, categoryId),
    'تعذّر تحميل نتائج البحث كاملة. حاول تعديل البحث.',
  );

  /// One page of the public catalog, filtered and sorted on the server.
  Future<JobsPage> jobsPage({
    required String search,
    required JobFilters filters,
    required int? categoryId,
    required int page,
    int perPage = 24,
  }) async {
    final payload = await _send(
      'GET',
      '/api/filterjob',
      query: {
        ..._discoveryQuery(search, filters, categoryId),
        'per_page': '$perPage',
        'page': '$page',
        if (filters.salaryOnly) 'has_salary': '1',
        if (filters.sort == 'salary' &&
            filters.currency != null &&
            filters.salaryPeriod != null)
          'sort': 'salary',
      },
    );
    final meta = payload['meta'];
    final rows = _publicJobRows(payload);
    final jobs = [
      for (final row in rows)
        if (Job.fromApi(row, fromCatalog: true) case final job
            when !job.isDemo && job.isAvailable)
          job,
    ];
    if (filters.country != null &&
        jobs.any(
          (job) =>
              countryFor(job.country)?.code !=
              countryFor(filters.country)?.code,
        )) {
      throw const JobsException(
        'تعذّر تأكيد نتائج البلد المحدد. يرجى المحاولة لاحقاً.',
      );
    }
    return JobsPage(
      jobs: jobs,
      page: meta is Map && meta['current_page'] is num
          ? (meta['current_page'] as num).toInt()
          : page,
      lastPage: _lastPage(payload),
      total: meta is Map && meta['total'] is num
          ? (meta['total'] as num).toInt()
          : rows.length,
    );
  }

  /// Number of public jobs matching [filters], without loading them.
  Future<int> countJobs({
    required String search,
    required JobFilters filters,
    required int? categoryId,
  }) async => (await jobsPage(
    search: search,
    filters: filters,
    categoryId: categoryId,
    page: 1,
    perPage: 1,
  )).total;

  Future<List<String>> jobLocations(String country) async {
    final payload = await _send(
      'GET',
      '/api/job-locations',
      query: {'country': countryLabel(country)},
    );
    final data = payload['data'];
    if (data is! Map || data['cities'] is! List) {
      throw const JobsException(
        'تعذّر قراءة المدن. يمكنك كتابة المدينة يدوياً.',
      );
    }
    return (data['cities'] as List)
        .whereType<String>()
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty && s.length <= 100)
        .toSet()
        .toList()
      ..sort();
  }

  Map<String, String> _discoveryQuery(
    String search,
    JobFilters filters,
    int? categoryId,
  ) {
    return <String, String>{
      if (filters.country != null) 'country': countryLabel(filters.country),
      // `/api/filterjob` honours 50 per page (unlike `/api/jobs`), which keeps
      // a broad filter to a few requests.
      'per_page': '50',
      'sort': 'latest',
      if (search.trim().isNotEmpty) 'search': search.trim(),
      if (filters.category != null && categoryId != null)
        'job_field_id': '$categoryId',
      if (filters.city != null) 'state': filters.city!,
      if (filters.workType != null) 'job_type': filters.workType!,
      if (filters.workMode != null)
        'work_type': workModeApiValue(filters.workMode),
      if (filters.experience != null)
        'experience': experienceApiValue(filters.experience!),
      if (filters.currency != null) 'currency': filters.currency!,
      if (filters.salaryPeriod != null)
        'salary_period': salaryPeriodApiValue(filters.salaryPeriod!),
      if (filters.minSalary != null &&
          filters.currency != null &&
          filters.salaryPeriod != null)
        'salary_min': '${filters.minSalary}',
    };
  }

  Future<Job> job(String id) async {
    final payload = await _send('GET', '/api/jobs/${Uri.encodeComponent(id)}');
    final data = payload['data'];
    if (data is! Map) {
      throw const JobsException('وصل رد غير متوقع من الخدمة.');
    }
    return Job.fromApi(Map<String, dynamic>.from(data), fromCatalog: true);
  }

  Future<List<Job>> myJobs() async {
    final collected = <String, Job>{};
    var page = 1;
    var lastPage = 1;
    while (page <= lastPage) {
      final payload = await _send(
        'GET',
        '/api/my-jobs',
        query: {'page': '$page', 'per_page': '50'},
        device: true,
      );
      final before = collected.length;
      for (final row in _rows(payload)) {
        final job = Job.fromApi(row);
        collected[job.id] = job;
      }
      lastPage = _lastPage(payload);
      if (lastPage > 40 || (before == collected.length && page < lastPage)) {
        throw const JobsException(
          'تعذّر التحقق من إعلاناتك كاملة. لا تعاود الإرسال قبل اكتمال التحديث.',
        );
      }
      page++;
    }
    return collected.values.toList();
  }

  /// Saved jobs with their public data, for pages that don't hold the catalog.
  Future<List<Job>> favoriteJobs() async {
    final payload = await _send('GET', '/api/favorites', device: true);
    return [
      for (final row in _rows(payload))
        if (row['job'] is Map)
          if (Job.fromApi(Map<String, dynamic>.from(row['job'] as Map))
              case final job when job.isAvailable)
            job,
    ];
  }

  Future<Set<String>> favoriteIds() async {
    final payload = await _send('GET', '/api/favorites', device: true);
    final ids = <String>{};
    for (final row in _rows(payload)) {
      final job = row['job'];
      final id = row['job_id'] ?? (job is Map ? job['id'] : null);
      if (id != null) ids.add('$id');
    }
    return ids;
  }

  /// Returns whether the job is saved after the toggle.
  Future<bool> toggleFavorite(String id) async {
    final payload = await _send(
      'POST',
      '/api/favorites',
      body: {'device_id': deviceId, 'job_id': int.tryParse(id) ?? id},
      device: true,
      idempotent: false,
    );
    final added = payload['is_added'];
    if (added is bool) return added;
    throw const JobsException('تعذّر تحديث المحفوظات. حاول مرة أخرى.');
  }

  Future<Job> createJob(Map<String, dynamic> body) async {
    final payload = await _send(
      'POST',
      '/api/jobs',
      body: {...body, 'device_id': deviceId},
      device: true,
      idempotent: false,
    );
    final data = payload['data'];
    if (data is! Map) {
      throw const JobsException(
        'لم يتأكد إرسال الإعلان. تحقق من إعلاناتك قبل إعادة المحاولة.',
        uncertainOutcome: true,
      );
    }
    try {
      return Job.fromApi(Map<String, dynamic>.from(data));
    } catch (_) {
      throw const JobsException(
        'لم يتأكد إرسال الإعلان. تحقق من إعلاناتك قبل إعادة المحاولة.',
        uncertainOutcome: true,
      );
    }
  }

  Future<void> deleteJob(String id) async {
    await _send('DELETE', '/api/jobs/${Uri.encodeComponent(id)}', device: true);
  }

  Future<void> report(String id, String reason) async {
    await _send(
      'POST',
      '/api/job-reports',
      body: {
        'device_id': deviceId,
        'job_id': int.tryParse(id) ?? id,
        'reason': reason,
      },
      device: true,
      idempotent: false,
    );
  }

  Future<({List<RemoteNotice> items, int unread})> notices() async {
    final payload = await _send('GET', '/api/notifications', device: true);
    final bucket = payload['data'];
    final rows = bucket is Map && bucket['data'] is List
        ? bucket['data'] as List
        : _rows(payload);
    final items =
        [
              for (final row in rows)
                if (row is Map)
                  RemoteNotice.fromJson(Map<String, dynamic>.from(row)),
            ]
            .where((notice) => notice.id.isNotEmpty && notice.text.isNotEmpty)
            .toList();
    final unreadRaw = payload['unread_count'];
    final unread = unreadRaw is num
        ? unreadRaw.toInt()
        : items.where((notice) => !notice.read).length;
    return (items: items, unread: unread);
  }

  Future<void> markNoticeRead(String id) async {
    await _send(
      'POST',
      '/api/notifications/${Uri.encodeComponent(id)}/read',
      body: const {},
      device: true,
      idempotent: true,
    );
  }

  /// Optional routes from the collection. A missing route is ignored.
  Future<String?> maintenanceMessage() async {
    try {
      final payload = await _send('GET', '/api/app/maintenance');
      final data = payload['data'];
      final enabled =
          payload['maintenance'] == true ||
          payload['is_maintenance'] == true ||
          (data is Map &&
              (data['maintenance'] == true || data['enabled'] == true));
      if (!enabled) return null;
      final message =
          payload['message'] ?? (data is Map ? data['message'] : null);
      return message is String && message.trim().isNotEmpty
          ? message.trim()
          : 'التطبيق في صيانة قصيرة. حاول بعد قليل.';
    } on JobsException catch (error) {
      if (error.statusCode == 404) return null;
      return null;
    }
  }

  Future<void> registerPushToken(String platform, String token) async {
    final response = await _send(
      'POST',
      '/api/app/visit',
      body: {'device_id': deviceId, 'platform': platform, 'fcm_token': token},
      device: true,
      idempotent: true,
    );
    if (response['success'] != true) {
      throw const JobsException('تعذّر تسجيل إشعارات الجهاز. حاول مجدداً.');
    }
  }

  Future<void> visit(String platform, {String? fcmToken}) async {
    try {
      await _send(
        'POST',
        '/api/app/visit',
        body: {
          'device_id': deviceId,
          'platform': platform,
          'fcm_token': ?fcmToken,
        },
        idempotent: true,
      );
    } on JobsException {
      // Visit tracking must never block browsing.
    }
  }

  Future<Map<String, dynamic>> _send(
    String method,
    String path, {
    Map<String, String>? query,
    Map<String, dynamic>? body,
    bool device = false,
    bool idempotent = true,
  }) async {
    // Live API validates `device_id` in the JSON body for writes; the header
    // alone is not enough for favorites and similar POSTs.
    final effectiveBody = body == null
        ? null
        : device
        ? {...body, 'device_id': deviceId}
        : Map<String, dynamic>.from(body);
    final attempts = idempotent ? 3 : 1;
    Object? last;
    for (var attempt = 0; attempt < attempts; attempt++) {
      try {
        final response = await _once(
          method,
          path,
          query,
          effectiveBody,
          device,
        );
        if (_retryStatus(response.statusCode) && attempt < attempts - 1) {
          await _pause(attempt, response);
          continue;
        }
        try {
          return _decode(response);
        } on JobsException {
          if (!idempotent &&
              (response.statusCode >= 500 || response.statusCode < 300)) {
            throw JobsException(
              'لم يتأكد تنفيذ الطلب. حدّث بياناتك وتحقق من النتيجة قبل إعادة المحاولة.',
              statusCode: response.statusCode,
              uncertainOutcome: true,
            );
          }
          rethrow;
        }
      } on JobsException {
        rethrow;
      } catch (error) {
        last = error;
        final timedOut = error is TimeoutException;
        if ((!_transient(error) && !timedOut) || attempt == attempts - 1) break;
        if (timedOut && !idempotent) break;
      }
      await _pause(attempt, null);
    }
    throw JobsException(
      !idempotent
          ? 'لم يتأكد تنفيذ الطلب. حدّث بياناتك وتحقق من النتيجة قبل إعادة المحاولة.'
          : last is TimeoutException
          ? 'الاتصال بطيء. ستظهر النتائج المحفوظة؛ حاول التحديث بعد قليل.'
          : 'الاتصال غير مستقر. تحقق من اتصال الإنترنت وحاول مرة أخرى.',
      uncertainOutcome: !idempotent,
    );
  }

  Future<http.Response> _once(
    String method,
    String path,
    Map<String, String>? query,
    Map<String, dynamic>? body,
    bool device,
  ) async {
    final request = http.Request(method, _uri(path, query));
    request.followRedirects = false;
    request.headers['Accept'] = 'application/json';
    if (device) request.headers['X-Device-ID'] = deviceId;
    if (body != null) {
      request.headers['Content-Type'] = 'application/json; charset=utf-8';
      request.body = jsonEncode(body);
    }
    final streamed = await _client
        .send(request)
        .timeout(const Duration(seconds: 20));
    if (streamed.statusCode >= 300 && streamed.statusCode < 400) {
      throw const JobsException('تعذّر الوصول للخدمة من عنوانها الآمن.');
    }
    return http.Response.fromStream(
      streamed,
    ).timeout(const Duration(seconds: 20));
  }

  Map<String, dynamic> _decode(http.Response response) {
    Map<String, dynamic>? payload;
    if (response.bodyBytes.isNotEmpty) {
      try {
        final decoded = jsonDecode(utf8.decode(response.bodyBytes));
        if (decoded is Map) payload = Map<String, dynamic>.from(decoded);
      } catch (_) {
        if (response.statusCode >= 200 && response.statusCode < 300) {
          throw const JobsException('وصل رد غير متوقع من الخدمة. حاول مجدداً.');
        }
      }
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw JobsException(
        _message(response.statusCode, payload),
        statusCode: response.statusCode,
      );
    }
    return payload ?? const {};
  }

  String _message(int code, Map<String, dynamic>? payload) {
    final leaked = payload != null && payload['exception'] != null;
    if (!leaked && payload != null) {
      final errors = payload['errors'];
      if (errors is Map && errors.isNotEmpty) {
        final entry = errors.entries.first;
        final value = entry.value;
        final text = value is List && value.isNotEmpty
            ? value.first.toString()
            : value.toString();
        return _arabicField(entry.key.toString(), text);
      }
      final message = payload['message'];
      if (message is String &&
          message.trim().isNotEmpty &&
          _arabic(message) &&
          !message.contains('Exception')) {
        return message.trim();
      }
    }
    return switch (code) {
      401 || 403 => 'لا تتوفر لهذا الجهاز صلاحية تنفيذ هذا الإجراء.',
      404 => 'الطلب غير موجود أو انتهت صلاحيته.',
      408 => 'انتهت مهلة الاتصال. حاول مرة أخرى.',
      413 => 'الإعلان أكبر من الحد المسموح.',
      422 => 'بعض البيانات ناقصة أو غير مقبولة. راجع الحقول ثم أعد المحاولة.',
      429 => 'تم بلوغ الحد المسموح من المحاولات. انتظر قليلاً ثم حاول مجدداً.',
      >= 500 => 'الخدمة غير متاحة مؤقتاً. حاول مجدداً بعد قليل.',
      _ => 'تعذّر إتمام الطلب. حاول مرة أخرى.',
    };
  }

  String _arabicField(String field, String fallback) {
    if (_arabic(fallback) && !fallback.contains('Exception')) return fallback;
    return switch (field) {
      'title' => 'أدخل مسمّى وظيفياً أوضح.',
      'company_name' => 'أدخل اسم جهة العمل.',
      'state' => 'اختر المحافظة أو المدينة.',
      'country' => 'اختر البلد.',
      'job_field_id' => 'اختر مجال العمل.',
      'job_type' => 'اختر نوع الدوام.',
      'work_type' => 'اختر طريقة العمل.',
      'experience' => 'اختر مستوى الخبرة.',
      'description' => 'يجب أن يتراوح طول الوصف ضمن الحدود المسموح بها.',
      'phone' => 'رقم واتساب غير مقبول.',
      'email' => 'البريد الإلكتروني غير مقبول.',
      'currency' => 'اختر عملة الراتب.',
      'salary_period' => 'اختر فترة الراتب.',
      'salary_min' || 'salary_max' => 'راجع حدود الراتب.',
      'listing_duration_days' => 'اختر مدة الإعلان: 7 أو 14 أو 30 يوماً.',
      'reason' => 'اكتب سبب البلاغ بوضوح.',
      'job_id' => 'لم تعد هذه الفرصة متاحة.',
      'device_id' => 'تعذّر تمييز هذا الجهاز. حدّث الصفحة وحاول مجدداً.',
      _ => 'بعض البيانات ناقصة أو غير مقبولة. راجع الحقول ثم أعد المحاولة.',
    };
  }

  bool _arabic(String value) => RegExp(r'[\u0600-\u06FF]').hasMatch(value);

  bool _transient(Object error) {
    if (error is http.ClientException || error is TimeoutException) return true;
    final name = error.runtimeType.toString();
    return name.contains('Socket') ||
        name.contains('Handshake') ||
        name.contains('Tls') ||
        name.contains('HttpException');
  }

  bool _retryStatus(int code) =>
      code == 408 ||
      code == 429 ||
      code == 500 ||
      code == 502 ||
      code == 503 ||
      code == 504;

  Future<void> _pause(int attempt, http.Response? response) async {
    final retryAfter = int.tryParse(response?.headers['retry-after'] ?? '');
    final seconds = retryAfter?.clamp(1, 8);
    final base = seconds != null ? seconds * 1000 : 350 * (1 << attempt);
    await Future<void>.delayed(
      Duration(milliseconds: base + _random.nextInt(250)),
    );
  }

  Uri _uri(String path, Map<String, String>? query) {
    final parsed = Uri.tryParse(base.trim());
    final localDebug =
        kDebugMode &&
        parsed != null &&
        ['localhost', '127.0.0.1', '::1', '[::1]'].contains(parsed.host);
    if (parsed == null ||
        parsed.host.isEmpty ||
        parsed.hasQuery ||
        parsed.hasFragment ||
        parsed.userInfo.isNotEmpty ||
        (parsed.scheme != 'https' &&
            !(localDebug && parsed.scheme == 'http'))) {
      throw const JobsException('عنوان الخدمة غير صالح. يلزم اتصال HTTPS آمن.');
    }
    final prefix = parsed.path.replaceAll(RegExp(r'/+$'), '');
    return parsed.replace(
      path: '$prefix$path',
      queryParameters: query == null || query.isEmpty ? null : query,
    );
  }

  List<Map<String, dynamic>> _publicJobRows(Map<String, dynamic> payload) {
    if (payload['success'] == false) {
      throw JobsException(_message(200, payload));
    }
    final data = payload['data'];
    final meta = payload['meta'];
    final total = meta is Map
        ? meta['total']
        : data is Map
        ? data['total']
        : null;
    final nullRows =
        payload.containsKey('data') &&
        (data == null ||
            (data is Map && data.containsKey('data') && data['data'] == null));
    // Some legacy empty paginators return null rather than []. Only an
    // explicit zero total can establish that this is a successful empty page.
    if (nullRows && total is num && total == 0) return const [];
    return _rows(payload);
  }

  List<Map<String, dynamic>> _rows(Map<String, dynamic> payload) {
    final data = payload['data'];
    if (data is! List && !(data is Map && data['data'] is List)) {
      throw const JobsException(
        'وصل رد غير مكتمل من الخدمة. حاول التحديث مجدداً.',
      );
    }
    final list = data is List
        ? data
        : data is Map && data['data'] is List
        ? data['data'] as List
        : const [];
    return [
      for (final row in list)
        if (row is Map) Map<String, dynamic>.from(row),
    ];
  }

  int _lastPage(Map<String, dynamic> payload) {
    final meta = payload['meta'];
    if (meta is Map && meta['last_page'] is num) {
      return (meta['last_page'] as num).toInt().clamp(1, 1000000);
    }
    final data = payload['data'];
    final value =
        payload['last_page'] ?? (data is Map ? data['last_page'] : null);
    if (value is num) return value.toInt().clamp(1, 1000000);
    return 1;
  }
}

class JobsPage {
  const JobsPage({
    required this.jobs,
    required this.page,
    required this.lastPage,
    required this.total,
  });

  final List<Job> jobs;
  final int page;
  final int lastPage;
  final int total;
}

class JobField {
  const JobField({
    required this.id,
    required this.nameAr,
    required this.nameEn,
    this.slug = '',
    this.icon = '',
  });
  final int id;
  final String nameAr;
  final String nameEn;
  final String slug;
  final String icon;

  Map<String, dynamic> toJson() => {
    'id': id,
    'nameAr': nameAr,
    'nameEn': nameEn,
    'slug': slug,
    'icon': icon,
  };

  factory JobField.fromJson(Map<String, dynamic> json) => JobField(
    id: (json['id'] as num).toInt(),
    nameAr: json['nameAr'] as String? ?? '',
    nameEn: json['nameEn'] as String? ?? '',
    slug: json['slug'] as String? ?? '',
    icon: json['icon'] as String? ?? '',
  );
}

class RemoteNotice {
  const RemoteNotice({
    this.payload = const {},
    required this.id,
    required this.text,
    required this.read,
    this.createdAt,
    this.jobId,
  });

  final String id;
  final String text;
  final Map<String, dynamic> payload;
  final bool read;
  final DateTime? createdAt;
  final String? jobId;

  factory RemoteNotice.fromJson(Map<String, dynamic> json) {
    final title = json['title'] ?? json['subject'];
    final body = json['body'] ?? json['message'] ?? json['content'];
    final text = [
      if (title is String && title.trim().isNotEmpty) title.trim(),
      if (body is String && body.trim().isNotEmpty) body.trim(),
    ].join('\n');
    final readAt = json['read_at'];
    return RemoteNotice(
      id: '${json['id'] ?? ''}',
      text: text,
      read: json['is_read'] == true || json['read'] == true || readAt != null,
      createdAt: DateTime.tryParse('${json['created_at'] ?? ''}'),
      jobId: json['job_id']?.toString(),
      payload: json['payload'] is Map
          ? Map<String, dynamic>.from(json['payload'] as Map)
          : {},
    );
  }
}
