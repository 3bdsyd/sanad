import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:snad/features/jobs/data/jobs_store.dart';
import 'package:snad/features/jobs/domain/job_filters.dart';

Map<String, Object?> apiJob(String id, String country) => {
  'id': id,
  'title': 'محاسب تجريبي',
  'company_name': 'جهة اختبار',
  'country': country,
  'state': 'مدينة اختبار',
  'job_field': {'id': 1, 'name_ar': 'تقنية'},
  'job_type': 'دوام كامل',
  'work_type': 'عن بُعد',
  'experience': 'متوسط',
  'description': 'هذه بيانات اختبار فقط وليست فرصة حقيقية.',
  'requirements': '',
  'contact': {'email': 'test@example.test'},
  'salary': {'currency': 'USD', 'period': 'شهري', 'min': 100},
  'status': 'published',
  'is_active': true,
  'created_at': '2026-01-01T00:00:00Z',
  'expires_at': '2035-01-01T00:00:00Z',
};

http.Response jsonResponse(Object data) => http.Response.bytes(
  utf8.encode(jsonEncode(data)),
  200,
  headers: {'content-type': 'application/json'},
);
http.Response page(
  String id,
  String country, {
  int current = 1,
  int last = 1,
}) => jsonResponse({
  'data': [apiJob(id, country)],
  'meta': {
    'current_page': current,
    'last_page': last,
    'per_page': 24,
    'total': last,
  },
});

Future<void> flushRequests() async {
  for (var i = 0; i < 12; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  test(
    'country filtering rejects a service that silently returns another country',
    () async {
      final store = await JobsStore.create(
        client: MockClient((request) async {
          if (request.url.path == '/api/filterjob') {
            return page('sy-1', 'سوريا');
          }
          return jsonResponse({'data': []});
        }),
      );
      await store.refresh();
      store.updateFilters(const JobFilters(country: 'AE'));
      await flushRequests();
      expect(store.visibleJobs, isEmpty);
      expect(store.totalCount, 0);
      expect(store.error, contains('البلد المحدد'));
      store.dispose();
    },
  );

  test(
    'country switch clears old rows and ignores a late previous-country response',
    () async {
      final ae = Completer<http.Response>();
      final requests = <Uri>[];
      final client = MockClient((request) async {
        if (request.url.path == '/api/filterjob') {
          requests.add(request.url);
          final country = request.url.queryParameters['country'];
          if (country == 'الإمارات') return ae.future;
          if (country == 'السعودية') {
            final n = int.parse(request.url.queryParameters['page']!);
            return page('sa-$n', 'السعودية', current: n, last: 2);
          }
          expect(country, isNull, reason: 'New installs search globally.');
          return page('sy-1', 'سوريا');
        }
        return jsonResponse({'data': []});
      });
      final store = await JobsStore.create(client: client);
      await store.refresh();
      expect(store.visibleJobs.single.country, 'سوريا');
      store.updateFilters(const JobFilters(country: 'AE'));
      expect(store.visibleJobs, isEmpty);
      expect(store.totalCount, 0);
      await flushRequests();
      expect(requests.last.queryParameters['country'], 'الإمارات');
      store.updateFilters(const JobFilters(country: 'SA'));
      await flushRequests();
      expect(store.visibleJobs.single.country, 'السعودية');
      ae.complete(page('ae-1', 'الإمارات'));
      await flushRequests();
      expect(store.visibleJobs.map((job) => job.id), ['sa-1']);
      await store.loadMore();
      expect(requests.last.queryParameters['country'], 'السعودية');
      expect(store.visibleJobs.map((job) => job.id), ['sa-1', 'sa-2']);
      await store.saveSearch();
      expect(store.savedSearches.single['name'], contains('السعودية'));
      final filters = store.savedSearches.single['filters'] as Map;
      expect(filters['country'], 'SA');
      store.dispose();
    },
  );

  test(
    'a saved country cannot load a cache belonging to a different country',
    () async {
      final prefix =
          'snad.live.v1.${base64Url.encode(utf8.encode('https://admin.jobsnad.com'))}';
      SharedPreferences.setMockInitialValues({
        '$prefix.discovery': jsonEncode({
          'query': '',
          'filters': const JobFilters(country: 'AE').toJson(),
          'searches': [],
          'read': [],
        }),
        '$prefix.cache': jsonEncode({
          'filters': const JobFilters(country: 'SY').toJson(),
          'query': '',
          'jobs': [],
          'fields': [],
          'total': 99,
          'updatedAt': '2026-01-01T00:00:00Z',
        }),
      });
      final pending = Completer<http.Response>();
      final store = await JobsStore.create(
        client: MockClient((request) async {
          if (request.url.path == '/api/filterjob') return pending.future;
          return jsonResponse({'data': []});
        }),
      );
      expect(store.filters.country, 'AE');
      expect(
        store.totalCount,
        0,
        reason: 'The Syrian total is not an Emirati total.',
      );
      expect(store.lastUpdated, isNull);
      pending.complete(page('ae-1', 'الإمارات'));
      await store.refresh();
      expect(store.visibleJobs.single.country, 'الإمارات');
      store.dispose();
    },
  );

  test(
    'a late initial global response cannot mark a failed new country fresh',
    () async {
      final initial = Completer<http.Response>();
      final store = await JobsStore.create(
        client: MockClient((request) async {
          if (request.url.path == '/api/filterjob') {
            if (request.url.queryParameters['country'] == null) {
              return initial.future;
            }
            return http.Response(
              '{"message":"تعذّر الطلب"}',
              400,
              headers: {'content-type': 'application/json'},
            );
          }
          if (request.url.path == '/api/job-fields') {
            return jsonResponse({
              'data': [
                {'id': 1, 'name_ar': 'تقنية'},
              ],
            });
          }
          return jsonResponse({'data': []});
        }),
      );
      store.updateFilters(const JobFilters(country: 'AE'));
      await flushRequests();
      expect(store.lastUpdated, isNull);
      initial.complete(page('sy-1', 'سوريا'));
      await store.refresh();
      expect(store.fields, hasLength(1));
      expect(store.filters.country, 'AE');
      expect(store.visibleJobs, isEmpty);
      expect(store.lastUpdated, isNull);
      expect(store.totalCount, 0);
      store.dispose();
    },
  );

  test(
    'legacy Syrian saved searches migrate without duplicating on save',
    () async {
      final prefix =
          'snad.live.v1.${base64Url.encode(utf8.encode('https://admin.jobsnad.com'))}';
      final legacy = const JobFilters(country: 'SY', city: 'دمشق').toJson()
        ..remove('country');
      SharedPreferences.setMockInitialValues({
        '$prefix.discovery': jsonEncode({
          'query': '',
          'filters': legacy,
          'read': [],
          'searches': [
            {
              'key': jsonEncode({'query': '', 'filters': legacy}),
              'query': '',
              'filters': legacy,
              'name': 'دمشق',
            },
          ],
        }),
      });
      final store = await JobsStore.create(
        client: MockClient((request) async {
          if (request.url.path == '/api/filterjob') {
            return page('sy-1', 'سوريا');
          }
          return jsonResponse({'data': []});
        }),
      );
      await store.refresh();
      expect(store.filters.country, 'SY');
      await store.saveSearch();
      expect(store.savedSearches, hasLength(1));
      expect((store.savedSearches.single['filters'] as Map)['country'], 'SY');
      store.dispose();
    },
  );
}
