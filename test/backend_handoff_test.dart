import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:snad/features/app_access/data/app_access_service.dart';
import 'package:snad/features/app_access/domain/app_access.dart';
import 'package:snad/features/jobs/data/api_client.dart';
import 'package:snad/features/jobs/domain/job_filters.dart';

const _root = 'docs/backend-handoff-2026-11-03';
Map<String, dynamic> readFixture(String path) =>
    jsonDecode(File('$_root/$path').readAsStringSync()) as Map<String, dynamic>;

http.Response reply(Object payload, {int status = 200}) => http.Response.bytes(
  utf8.encode(jsonEncode(payload)),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

void main() {
  final responses = readFixture('examples/responses.json');
  final requests = readFixture('examples/requests.json');

  test('handoff examples work with all 16 current client operations', () async {
    final seen = <http.Request>[];
    var favoriteWrites = 0;
    final device = (requests['createJob'] as Map)['device_id'] as String;
    final client = MockClient((request) async {
      seen.add(request);
      final route = '${request.method} ${request.url.path}';
      final key = switch (route) {
        'GET /api/job-fields' => 'jobFields',
        'GET /api/jobs' || 'GET /api/filterjob' => 'jobsPage',
        'GET /api/job-locations' => 'jobLocations',
        'GET /api/jobs/970001' => 'jobDetail',
        'POST /api/jobs' => 'createJob',
        'GET /api/my-jobs' => 'myJobs',
        'GET /api/favorites' => 'favorites',
        'POST /api/favorites' =>
          ++favoriteWrites == 1 ? 'favoriteAdded' : 'favoriteRemoved',
        'POST /api/job-reports' => 'reportAccepted',
        'GET /api/notifications' => 'notifications',
        'POST /api/notifications/notice-test-1/read' ||
        'POST /api/app/visit' ||
        'DELETE /api/jobs/970001' => 'success',
        'GET /api/app/maintenance' => 'maintenanceOff',
        'GET /api/app/version-check' => 'noUpdate',
        _ => throw StateError('Undocumented request: $route'),
      };
      return reply(
        responses[key]!,
        status:
            key == 'createJob' ||
                key == 'favoriteAdded' ||
                key == 'reportAccepted'
            ? 201
            : 200,
      );
    });
    final api = SndApi(
      base: 'https://api.example.test',
      client: client,
      deviceId: device,
    );
    expect((await api.jobFields()).single.id, 1);
    expect((await api.jobs()).single.currency, 'AED');
    final page = await api.jobsPage(
      search: 'محاسب',
      filters: const JobFilters(
        country: 'AE',
        city: 'دبي',
        category: 'تقنية',
        workType: 'دوام كامل',
        workMode: 'من المكتب',
        experience: 'متوسط',
        currency: 'AED',
        salaryPeriod: 'شهري',
        minSalary: 3000,
        salaryOnly: true,
        sort: 'salary',
      ),
      categoryId: 1,
      page: 1,
    );
    expect((page.page, page.lastPage, page.total), (1, 1, 1));
    expect(await api.jobLocations('AE'), ['أبوظبي', 'دبي']);
    expect((await api.job('970001')).phone, '+390212345678');
    final created = await api.createJob(
      Map<String, dynamic>.from(requests['createJob'] as Map),
    );
    expect(
      (created.id, created.country, created.status),
      ('970001', 'الإمارات', 'pending'),
    );
    expect((await api.myJobs()).single.status, 'pending');
    expect((await api.favoriteJobs()).single.id, '970001');
    expect(await api.favoriteIds(), {'970001'});
    expect(await api.toggleFavorite('970001'), isTrue);
    expect(await api.toggleFavorite('970001'), isFalse);
    await api.report(
      '970001',
      (requests['reportJob'] as Map)['reason'] as String,
    );
    final notices = await api.notices();
    expect(notices.unread, 1);
    expect(notices.items.single.jobId, '970001');
    await api.markNoticeRead('notice-test-1');
    await api.registerPushToken(
      'ios',
      (requests['registerPush'] as Map)['fcm_token'] as String,
    );
    await api.visit('web');
    await api.deleteJob('970001');
    final access = await AppAccessService(
      base: 'https://api.example.test',
      client: client,
    ).check(platform: 'android', version: '1.0.0');
    expect(access.kind, AppAccessKind.allowed);

    http.Request sent(String method, String path) => seen.firstWhere(
      (request) => request.method == method && request.url.path == path,
    );
    expect(sent('GET', '/api/filterjob').url.queryParameters, {
      'country': 'الإمارات',
      'state': 'دبي',
      'search': 'محاسب',
      'per_page': '24',
      'page': '1',
      'sort': 'salary',
      'job_field_id': '1',
      'job_type': 'دوام كامل',
      'work_type': 'في المقر',
      'experience': 'متوسطة',
      'currency': 'AED',
      'salary_period': 'شهرياً',
      'salary_min': '3000',
      'has_salary': '1',
    });
    expect(sent('GET', '/api/job-locations').url.queryParameters, {
      'country': 'الإمارات',
    });
    expect(jsonDecode(sent('POST', '/api/jobs').body), requests['createJob']);
    expect(
      jsonDecode(sent('POST', '/api/favorites').body),
      requests['toggleFavorite'],
    );
    expect(
      jsonDecode(sent('POST', '/api/job-reports').body),
      requests['reportJob'],
    );
    expect(
      jsonDecode(sent('POST', '/api/notifications/notice-test-1/read').body),
      requests['markNoticeRead'],
    );
    expect(
      jsonDecode(sent('POST', '/api/app/visit').body),
      requests['registerPush'],
    );
    final webVisit = seen.lastWhere((r) => r.url.path == '/api/app/visit');
    expect(jsonDecode(webVisit.body), requests['visitWeb']);
    expect(webVisit.headers['X-Device-ID'], isNull);
    expect(sent('DELETE', '/api/jobs/970001').body, isEmpty);
    expect(sent('DELETE', '/api/jobs/970001').headers['X-Device-ID'], device);
    expect(sent('GET', '/api/app/maintenance').headers['X-Device-ID'], isNull);
    expect(sent('GET', '/api/app/version-check').url.queryParameters, {
      'version': '1.0.0',
      'platform': 'android',
    });
    String operation(http.Request r) => '${r.method} ${r.url.path}'
        .replaceAll('/jobs/970001', '/jobs/{jobId}')
        .replaceAll(
          '/notifications/notice-test-1/read',
          '/notifications/{noticeId}/read',
        );
    final declared =
        (readFixture('openapi.json')['x-client-operations'] as List)
            .map((row) => '${row['method']} ${row['path']}')
            .toSet();
    expect(seen.map(operation).toSet(), declared);
    expect(declared.length, 16);
    client.close();
  });

  test(
    'empty lists and Laravel field errors keep the documented behavior',
    () async {
      final api = SndApi(
        base: 'https://api.example.test',
        deviceId: 'contract-test-device-only',
        client: MockClient(
          (request) async => switch (request.url.path) {
            '/api/filterjob' => reply(responses['emptyPage']!),
            '/api/job-locations' => reply(responses['emptyLocations']!),
            '/api/favorites' => reply(responses['unavailableFavorite']!),
            '/api/jobs' => reply(responses['validationError']!, status: 422),
            _ => throw StateError('Unexpected route'),
          },
        ),
      );
      final page = await api.jobsPage(
        search: '',
        filters: const JobFilters(),
        categoryId: null,
        page: 1,
      );
      expect(page.jobs, isEmpty);
      expect(page.total, 0);
      expect(await api.jobLocations('AE'), isEmpty);
      expect(await api.favoriteJobs(), isEmpty);
      expect(await api.favoriteIds(), {'970001'});
      await expectLater(
        api.createJob(Map<String, dynamic>.from(requests['createJob'] as Map)),
        throwsA(
          isA<JobsException>()
              .having((e) => e.statusCode, 'status', 422)
              .having(
                (e) => e.uncertainOutcome,
                'known validation failure',
                isFalse,
              )
              .having(
                (e) => e.message,
                'Arabic field error',
                contains('بلداً'),
              ),
        ),
      );
    },
  );

  test('documented maintenance and update flags control app access', () async {
    for (final key in [
      'maintenanceOn',
      'optionalUpdateAndroid',
      'requiredUpdateAndroid',
    ]) {
      final client = MockClient((request) async {
        final maintenance = request.url.path.endsWith('/maintenance');
        return reply(
          responses[maintenance
              ? (key == 'maintenanceOn' ? key : 'maintenanceOff')
              : key]!,
          status: key == 'maintenanceOn' ? 503 : 200,
        );
      });
      final value = await AppAccessService(
        base: 'https://api.example.test',
        client: client,
      ).check(platform: 'android', version: '1.0.0');
      expect(
        value.kind,
        key == 'maintenanceOn'
            ? AppAccessKind.maintenance
            : AppAccessKind.update,
      );
      expect(value.requiredUpdate, key == 'requiredUpdateAndroid');
      if (key != 'maintenanceOn') {
        expect(value.storeUri?.host, 'play.google.com');
      }
      client.close();
    }
  });
}
