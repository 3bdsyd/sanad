// Exercises every SndApi use case with scripted JSON responses and verifies
// the outgoing HTTP methods, paths, headers, queries, and request bodies.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:snad/features/jobs/data/api_client.dart';
import 'package:snad/features/jobs/domain/job_filters.dart';

const _deviceId = 'smoke-device-123';
const _job = <String, dynamic>{
  'id': 7,
  'title': 'مطور تطبيقات',
  'device_id': 'server-private-device-id',
  'company_name': 'شركة اختبار',
  'country': 'سوريا',
  'state': 'دمشق',
  'job_field': {'id': 1, 'name_ar': 'تقنية'},
  'job_type': 'دوام كامل',
  'work_type': 'عن بُعد',
  'experience': 'متوسط',
  'description': 'وصف اختبار صالح يتضمن تفاصيل الوظيفة ومسؤولياتها.',
  'requirements': 'خبرة عملية',
  'contact': {'phone': '+963944000000', 'email': null},
  'salary': {'currency': 'USD', 'period': 'شهري', 'min': 700, 'max': 900},
  'listing_duration_days': 30,
  'expires_at': '2035-01-31T00:00:00Z',
  'is_active': true,
  'created_at': '2035-01-01T00:00:00Z',
};

class _RecordedRequest {
  const _RecordedRequest(this.method, this.uri, this.headers, this.body);
  final String method;
  final Uri uri;
  final Map<String, String> headers;
  final String body;
}

class _ScriptedClient extends http.BaseClient {
  final requests = <_RecordedRequest>[];
  var favoritePosts = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final body = request is http.Request ? request.body : '';
    requests.add(
      _RecordedRequest(request.method, request.url, request.headers, body),
    );
    final path = request.url.path;
    final method = request.method;
    final result = switch ((method, path)) {
      ('GET', '/api/job-fields') => {
        'data': [
          {
            'id': 1,
            'name_ar': 'تقنية',
            'name_en': 'Technology',
            'slug': 'technology',
            'icon': 'code',
            'is_active': true,
          },
        ],
      },
      ('GET', '/api/jobs') => {
        'data': [_job],
        'meta': {'last_page': 1},
      },
      ('GET', '/api/jobs/7') => {'data': _job},
      ('GET', '/api/my-jobs') => {
        'data': [_job],
        'meta': {'last_page': 1},
      },
      ('GET', '/api/favorites') => {
        'data': [
          {'job_id': 7},
        ],
      },
      ('POST', '/api/favorites') => {'is_added': favoritePosts++ == 0},
      ('POST', '/api/jobs') => {'data': _job},
      ('DELETE', '/api/jobs/7') => {'success': true},
      ('POST', '/api/job-reports') => {'success': true},
      ('GET', '/api/notifications') => {
        'unread_count': 1,
        'data': {
          'data': [
            {
              'id': 9,
              'title': 'تحديث الإعلان',
              'body': 'تم نشر الإعلان.',
              'is_read': false,
              'created_at': '2035-01-02T00:00:00Z',
              'job_id': 7,
            },
          ],
        },
      },
      ('POST', '/api/notifications/9/read') => {'success': true},
      ('GET', '/api/app/maintenance') => {'maintenance': false},
      ('POST', '/api/app/visit') => {'success': true},
      _ => throw StateError('Unexpected request: $method ${request.url}'),
    };
    final encoded = method == 'DELETE' ? '' : jsonEncode(result);
    return http.StreamedResponse(
      Stream.value(utf8.encode(encoded)),
      method == 'DELETE' ? 204 : 200,
      request: request,
      headers: {'content-type': 'application/json'},
    );
  }
}

class _PagedCatalogClient extends http.BaseClient {
  final requests = <_RecordedRequest>[];

  Map<String, dynamic> _row({required int id, String? status, bool? active}) =>
      {..._job, 'id': id, 'status': ?status, 'is_active': ?active};

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final recorded = _RecordedRequest(
      request.method,
      request.url,
      request.headers,
      request is http.Request ? request.body : '',
    );
    requests.add(recorded);
    final payload = switch (request.url.queryParameters['page']) {
      '1' => {
        'data': [_row(id: 7), _row(id: 8, status: 'pending')],
        'meta': {'last_page': 3, 'total': 6},
      },
      '2' => {
        'data': {
          'data': [_row(id: 9, active: false), _row(id: 10)],
          'last_page': 3,
        },
      },
      '3' => {
        'data': [
          _row(id: 11, status: 'expired'),
          _row(id: 12, status: 'approved'),
        ],
        'meta': {'last_page': 3, 'total': 6},
      },
      _ => throw StateError('Unexpected page: ${request.url}'),
    };
    return http.StreamedResponse(
      Stream.value(utf8.encode(jsonEncode(payload))),
      200,
      request: request,
      headers: {'content-type': 'application/json'},
    );
  }
}

class _FilteredSearchClient extends http.BaseClient {
  final requests = <_RecordedRequest>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(
      _RecordedRequest(
        request.method,
        request.url,
        request.headers,
        request is http.Request ? request.body : '',
      ),
    );
    final payload = switch (request.url.queryParameters['page']) {
      '1' => {
        'data': [_job],
        'meta': {'last_page': 2, 'total': 2},
      },
      '2' => {
        'data': [
          {..._job, 'id': 8},
        ],
        'meta': {'last_page': 2, 'total': 2},
      },
      _ => throw StateError('Unexpected filtered page: ${request.url}'),
    };
    return http.StreamedResponse(
      Stream.value(utf8.encode(jsonEncode(payload))),
      200,
      request: request,
      headers: {'content-type': 'application/json'},
    );
  }
}

class _UnavailableMutationClient extends http.BaseClient {
  var requests = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests++;
    return http.StreamedResponse(
      Stream.value(utf8.encode(jsonEncode({'message': 'temporary failure'}))),
      503,
      request: request,
      headers: {'content-type': 'application/json'},
    );
  }
}

void _expect(bool condition, String message) {
  if (!condition) throw StateError(message);
}

void main() {
  test('SndApi request and response use cases', () async {
    final client = _ScriptedClient();
    final api = SndApi(
      base: 'https://api.example.test',
      client: client,
      deviceId: _deviceId,
    );

    final fields = await api.jobFields();
    _expect(fields.single.nameAr == 'تقنية', 'job-field response parsing');
    final jobs = await api.jobs();
    _expect(jobs.single.title == 'مطور تطبيقات', 'catalog response parsing');
    _expect(
      jobs.single.employerKey == null,
      'public device id is never retained',
    );
    _expect(jobs.single.salaryMin == 700, 'salary response parsing');
    _expect(
      jobs.single.requirements.single == 'خبرة عملية',
      'requirements parsing',
    );
    final detail = await api.job('7');
    _expect(detail.company == 'شركة اختبار', 'detail response parsing');
    _expect(
      (await api.myJobs()).single.status == 'published',
      'my-jobs parsing',
    );
    _expect(
      (await api.favoriteIds()).contains('7'),
      'favorites response parsing',
    );
    _expect(await api.toggleFavorite('7'), 'favorite toggle response parsing');
    _expect(
      !await api.toggleFavorite('7'),
      'favorite removal response parsing',
    );
    const createInput = {
      'title': 'مطور تطبيقات',
      'company_name': 'شركة اختبار',
      'country': 'سوريا',
      'state': 'دمشق',
      'job_field_id': 1,
      'job_type': 'دوام كامل',
      'work_type': 'عن بُعد',
      'experience': 'متوسط',
      'description': 'وصف اختبار صالح يتضمن تفاصيل الوظيفة ومسؤولياتها.',
      'requirements': 'خبرة عملية',
      'phone': '+963944000000',
      'email': '',
      'url': 'https://example.test/jobs',
      'currency': 'USD',
      'salary_period': 'شهري',
      'salary_min': 700,
      'salary_max': 900,
      'listing_duration_days': 30,
    };
    final created = await api.createJob(createInput);
    _expect(created.id == '7', 'create response parsing');
    await api.deleteJob('7');
    await api.report('7', 'سبب واضح للاختبار');
    final notices = await api.notices();
    _expect(
      notices.unread == 1 && notices.items.single.id == '9',
      'notices parsing',
    );
    _expect(
      notices.items.single.text == 'تحديث الإعلان\nتم نشر الإعلان.',
      'notice text',
    );
    await api.markNoticeRead('9');
    _expect(
      await api.maintenanceMessage() == null,
      'maintenance disabled response',
    );
    await api.visit('ios');

    _expect(
      client.requests.length == 14,
      'all 14 API use-case requests recorded',
    );
    _RecordedRequest recorded(String method, String path) =>
        client.requests.firstWhere(
          (request) => request.method == method && request.uri.path == path,
        );
    _expect(
      recorded('GET', '/api/jobs').uri.queryParameters['per_page'] == '50',
      'catalog pagination query',
    );
    _expect(
      recorded('GET', '/api/jobs').uri.queryParameters['page'] == '1',
      'catalog first page query',
    );
    _expect(
      recorded('GET', '/api/jobs/7').method == 'GET',
      'detail method and path',
    );
    for (final pair in [
      ('GET', '/api/my-jobs'),
      ('GET', '/api/favorites'),
      ('POST', '/api/favorites'),
      ('GET', '/api/notifications'),
      ('POST', '/api/notifications/9/read'),
      ('POST', '/api/jobs'),
      ('DELETE', '/api/jobs/7'),
      ('POST', '/api/job-reports'),
    ]) {
      _expect(
        recorded(pair.$1, pair.$2).headers['X-Device-ID'] == _deviceId,
        '${pair.$1} ${pair.$2} device header',
      );
    }
    final favoriteBody =
        jsonDecode(recorded('POST', '/api/favorites').body) as Map;
    _expect(
      favoriteBody['device_id'] == _deviceId,
      'favorite writes device_id body',
    );
    _expect(favoriteBody['job_id'] == 7, 'favorite writes numeric job id');
    final createBody = jsonDecode(recorded('POST', '/api/jobs').body) as Map;
    _expect(
      createBody['device_id'] == _deviceId,
      'create writes device_id body',
    );
    expect(
      createBody,
      equals({...createInput, 'device_id': _deviceId}),
      reason: 'create preserves all fields and adds the device id',
    );
    final reportBody =
        jsonDecode(recorded('POST', '/api/job-reports').body) as Map;
    _expect(
      reportBody['device_id'] == _deviceId,
      'report writes device_id body',
    );
    _expect(reportBody['job_id'] == 7, 'report writes numeric job id');
    _expect(reportBody['reason'] == 'سبب واضح للاختبار', 'report reason body');
    final readBody =
        jsonDecode(recorded('POST', '/api/notifications/9/read').body) as Map;
    _expect(
      readBody['device_id'] == _deviceId,
      'read state writes device_id body',
    );
    final visitBody =
        jsonDecode(recorded('POST', '/api/app/visit').body) as Map;
    _expect(visitBody['device_id'] == _deviceId, 'visit writes device_id body');
    _expect(visitBody['platform'] == 'ios', 'visit platform body');
    for (final request in client.requests.where(
      (item) => item.body.isNotEmpty,
    )) {
      _expect(
        request.headers['Content-Type']!.startsWith('application/json'),
        '${request.method} ${request.uri.path} JSON content type',
      );
    }
  });

  test(
    'catalog traverses every API page and excludes unavailable states',
    () async {
      final client = _PagedCatalogClient();
      final api = SndApi(
        base: 'https://api.example.test',
        client: client,
        deviceId: _deviceId,
      );

      final jobs = await api.jobs();

      expect(jobs.map((job) => job.id), ['7', '10', '12']);
      expect(client.requests, hasLength(3));
      expect(
        client.requests.map((request) => request.uri.queryParameters['page']),
        ['1', '2', '3'],
      );
      for (final request in client.requests) {
        expect(request.method, 'GET');
        expect(request.uri.queryParameters['per_page'], '50');
      }
    },
  );

  test(
    'server filters send the collection contract and traverse all pages',
    () async {
      final client = _FilteredSearchClient();
      final api = SndApi(
        base: 'https://api.example.test',
        client: client,
        deviceId: _deviceId,
      );

      final jobs = await api.filteredJobs(
        search: 'مطور تطبيقات',
        categoryId: 4,
        filters: const JobFilters(
          country: 'SY',
          city: 'حمص',
          category: 'تقنية',
          workType: 'دوام كامل',
          workMode: 'عن بُعد',
          experience: 'متوسط',
          currency: 'USD',
          salaryPeriod: 'شهري',
          salaryOnly: true,
          minSalary: 600,
          sort: 'salary',
        ),
      );

      expect(jobs.map((job) => job.id), ['7', '8']);
      expect(client.requests, hasLength(2));
      for (var index = 0; index < client.requests.length; index++) {
        final request = client.requests[index];
        expect(request.method, 'GET');
        expect(request.uri.path, '/api/filterjob');
        expect(request.uri.queryParameters, {
          'country': 'سوريا',
          'per_page': '50',
          'sort': 'latest',
          'search': 'مطور تطبيقات',
          'job_field_id': '4',
          'state': 'حمص',
          'job_type': 'دوام كامل',
          'work_type': 'عن بُعد',
          'experience': 'متوسطة',
          'currency': 'USD',
          'salary_period': 'شهرياً',
          'salary_min': '600',
          'page': '${index + 1}',
        });
        expect(request.body, isEmpty);
        expect(request.headers['Content-Type'], isNull);
      }
    },
  );

  test('quick filters map product labels to live API values', () async {
    final client = _FilteredSearchClient();
    final api = SndApi(
      base: 'https://api.example.test',
      client: client,
      deviceId: _deviceId,
    );

    await api.filteredJobs(
      search: '',
      categoryId: null,
      filters: const JobFilters(workMode: 'من المكتب', experience: 'بدون خبرة'),
    );

    expect(client.requests.first.uri.queryParameters, {
      'per_page': '50',
      'sort': 'latest',
      'work_type': 'في المقر',
      'experience': 'غير مطلوبة',
      'page': '1',
    });
  });

  test('uncertain writes are never retried after a server error', () async {
    final client = _UnavailableMutationClient();
    final api = SndApi(
      base: 'https://api.example.test',
      client: client,
      deviceId: _deviceId,
    );

    await expectLater(
      api.toggleFavorite('7'),
      throwsA(
        isA<JobsException>().having(
          (error) => error.uncertainOutcome,
          'uncertain outcome',
          isTrue,
        ),
      ),
    );
    expect(client.requests, 1);
  });
}
