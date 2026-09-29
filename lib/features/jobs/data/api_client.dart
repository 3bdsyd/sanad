import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../domain/job.dart';

class JobsException implements Exception {
  const JobsException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;
  @override
  String toString() => message;
}

/// Live SND API at `https://snd.avorix.io`.
///
/// Reads are cached by the store and retried. Writes retry only when the
/// server clearly did not accept the request, so a slow timeout cannot
/// publish the same ad twice.
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
            nameEn: (row['name_en'] as String? ?? '').trim(),
          ),
    ].where((field) => field.nameAr.isNotEmpty).toList();
  }

  Future<List<Job>> jobs() async {
    final collected = <String, Job>{};
    var page = 1;
    var lastPage = 1;
    while (page <= lastPage && page <= 40) {
      final payload = await _send(
        'GET',
        '/api/jobs',
        query: {'page': '$page', 'per_page': '50'},
      );
      final before = collected.length;
      for (final row in _rows(payload)) {
        final job = Job.fromApi(row, fromCatalog: true);
        if (!job.isDemo && job.isAvailable) collected[job.id] = job;
      }
      lastPage = _lastPage(payload);
      if (collected.length == before && page < lastPage) {
        throw const JobsException(
          'تعذّر تحميل قائمة الفرص كاملة. حاول التحديث.',
        );
      }
      page++;
    }
    return collected.values.toList();
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
    final payload = await _send('GET', '/api/my-jobs', device: true);
    return [for (final row in _rows(payload)) Job.fromApi(row)];
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
      body: {'job_id': int.tryParse(id) ?? id},
      device: true,
      idempotent: false,
    );
    final added = payload['is_added'];
    if (added is bool) return added;
    throw const JobsException('تعذّر تحديث المحفوظة. حاول مرة تانية.');
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
      throw const JobsException('وصل رد غير متوقع بعد إرسال الإعلان.');
    }
    return Job.fromApi(Map<String, dynamic>.from(data));
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

  Future<List<RemoteNotice>> notices() async {
    final payload = await _send('GET', '/api/notifications', device: true);
    final bucket = payload['data'];
    final rows = bucket is Map && bucket['data'] is List
        ? bucket['data'] as List
        : _rows(payload);
    return [
          for (final row in rows)
            if (row is Map)
              RemoteNotice.fromJson(Map<String, dynamic>.from(row)),
        ]
        .where((notice) => notice.id.isNotEmpty && notice.text.isNotEmpty)
        .toList();
  }

  Future<void> markNoticeRead(String id) async {
    await _send(
      'POST',
      '/api/notifications/${Uri.encodeComponent(id)}/read',
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
          : 'التطبيق في صيانة قصيرة. جرّب بعد شوي.';
    } on JobsException catch (error) {
      if (error.statusCode == 404) return null;
      return null;
    }
  }

  Future<void> visit(String platform) async {
    try {
      await _send(
        'POST',
        '/api/app/visit',
        body: {'device_id': deviceId, 'platform': platform},
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
    final attempts = idempotent ? 3 : 2;
    Object? last;
    for (var attempt = 0; attempt < attempts; attempt++) {
      try {
        final response = await _once(method, path, query, body, device);
        if (_retryStatus(response.statusCode) && attempt < attempts - 1) {
          await _pause(attempt, response);
          continue;
        }
        return _decode(response);
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
      last is TimeoutException
          ? 'الاتصال بطيء. منكمّل بالمحفوظ، وجرّب التحديث بعد شوي.'
          : 'ما في اتصال مستقر. تأكد من الإنترنت وحاول مرة تانية.',
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
      401 || 403 => 'ما في صلاحية لهالإجراء من هذا الجهاز.',
      404 => 'هالطلب مو موجود أو انتهت صلاحيته.',
      408 => 'الاتصال تأخر. حاول مرة تانية.',
      413 => 'الإعلان أكبر من الحد المسموح.',
      422 => 'في معلومات ناقصة أو غير مقبولة. راجع الحقول وحاول.',
      429 => 'وصلت لحد المحاولات. انتظر شوي وحاول.',
      >= 500 => 'الخدمة مشغولة هلق. منحاول لحالا لما يرجع الاتصال.',
      _ => 'تعذّر إتمام الطلب. حاول مرة تانية.',
    };
  }

  String _arabicField(String field, String fallback) {
    if (_arabic(fallback) && !fallback.contains('Exception')) return fallback;
    return switch (field) {
      'title' => 'اكتب مسمّى الوظيفة بشكل أوضح.',
      'company_name' => 'اكتب اسم جهة العمل.',
      'state' => 'اختَر المحافظة أو المدينة.',
      'country' => 'اختَر البلد.',
      'job_field_id' => 'اختَر مجال الشغل.',
      'job_type' => 'اختَر نوع الدوام.',
      'work_type' => 'اختَر طريقة العمل.',
      'experience' => 'اختَر مستوى الخبرة.',
      'description' => 'الوصف قصير أو طويل زيادة عن المسموح.',
      'phone' => 'رقم واتساب غير مقبول.',
      'email' => 'البريد الإلكتروني غير مقبول.',
      'currency' => 'اختَر عملة الراتب.',
      'salary_period' => 'اختَر فترة الراتب.',
      'salary_min' || 'salary_max' => 'راجع حدود الراتب.',
      'listing_duration_days' => 'اختَر مدة الإعلان: 7 أو 14 أو 30 يوماً.',
      'reason' => 'اكتب سبب البلاغ بوضوح.',
      'job_id' => 'هالفرصة ما عادت متاحة.',
      _ => 'في معلومات ناقصة أو غير مقبولة. راجع الحقول وحاول.',
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

  List<Map<String, dynamic>> _rows(Map<String, dynamic> payload) {
    final data = payload['data'];
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
      return (meta['last_page'] as num).toInt().clamp(1, 40);
    }
    return 1;
  }
}

class JobField {
  const JobField({
    required this.id,
    required this.nameAr,
    required this.nameEn,
  });
  final int id;
  final String nameAr;
  final String nameEn;

  Map<String, dynamic> toJson() => {
    'id': id,
    'nameAr': nameAr,
    'nameEn': nameEn,
  };

  factory JobField.fromJson(Map<String, dynamic> json) => JobField(
    id: (json['id'] as num).toInt(),
    nameAr: json['nameAr'] as String? ?? '',
    nameEn: json['nameEn'] as String? ?? '',
  );
}

class RemoteNotice {
  const RemoteNotice({
    required this.id,
    required this.text,
    required this.read,
    this.createdAt,
    this.jobId,
  });

  final String id;
  final String text;
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
    );
  }
}
