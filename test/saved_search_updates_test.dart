import 'dart:convert';
import 'dart:io';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:snad/features/jobs/data/jobs_store.dart';
import 'package:snad/features/jobs/domain/job_filters.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'saved searches baseline silently, deduplicate new jobs and survive restart without repeat alerts',
    () async {
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
      final fixtures =
          jsonDecode(
                File(
                  'docs/backend-handoff-2026-11-03/examples/responses.json',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>;
      final original = Map<String, dynamic>.from(
        ((fixtures['jobsPage'] as Map)['data'] as List).first as Map,
      );
      final requests = <Uri>[];
      var stage = 0;
      var fail = false;
      http.Client client() => MockClient((request) async {
        requests.add(request.url);
        Object payload = {'success': true, 'data': []};
        if (request.url.path == '/api/filterjob') {
          if (fail && request.url.queryParameters['per_page'] == '50') {
            payload = {
              'success': true,
              'data': null,
              'meta': {'total': 1},
            };
          } else {
            final rows = [
              if (stage >= 2)
                {
                  ...original,
                  'id': 970003,
                  'created_at': '2035-01-03T00:00:00Z',
                },
              if (stage >= 1)
                {
                  ...original,
                  'id': 970002,
                  'created_at': '2035-01-02T00:00:00Z',
                },
              original,
              if (stage >= 1)
                {
                  ...original,
                  'id': 969999,
                  'created_at': '2034-12-30T00:00:00Z',
                },
            ];
            payload = {
              'success': true,
              'data': rows,
              'meta': {'current_page': 1, 'last_page': 1, 'total': rows.length},
            };
          }
        } else if (request.url.path == '/api/job-fields') {
          payload = fixtures['jobFields'];
        }
        return http.Response.bytes(
          utf8.encode(jsonEncode(payload)),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      Future<void> settle(JobsStore store) async {
        for (var i = 0; i < 100 && store.savedMatchesLoading; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 1));
        }
        expect(store.savedMatchesLoading, isFalse);
      }

      final store = await JobsStore.create(client: client());
      await store.refresh();
      store.updateFilters(
        const JobFilters(
          country: 'AE',
          sort: 'salary',
          currency: 'AED',
          salaryPeriod: 'شهرياً',
        ),
      );
      store.setQuery('محاسب');
      await store.saveSearch();
      await settle(store);
      store.setQuery('مالي');
      await store.saveSearch();
      await settle(store);
      expect(
        store.newMatchAlertJobs,
        isEmpty,
        reason: 'The first visit must not describe existing jobs as new.',
      );
      stage = 1;
      // Watches must retain their own country, even after the home filter changes.
      store.updateFilters(const JobFilters(country: 'DE'));
      await store.refreshSavedSearchMatches(force: true);
      expect(store.newMatchAlertJobs.map((job) => job.id), ['970002']);
      expect(store.savedSearchMatches.map((job) => job.id).toSet(), {
        '970001',
        '970002',
        '969999',
      });
      final watchRequests = requests.where(
        (uri) =>
            uri.path == '/api/filterjob' &&
            uri.queryParameters['per_page'] == '50',
      );
      expect(watchRequests, isNotEmpty);
      for (final uri in watchRequests) {
        expect(uri.queryParameters['country'], 'الإمارات');
        expect(uri.queryParameters['sort'], 'latest');
        expect(uri.queryParameters['page'], '1');
      }
      await store.acknowledgeMatchAlert(['970002']);
      expect(store.newMatchAlertJobs, isEmpty);
      expect(store.isNewSavedMatch('970002'), isTrue);
      store.dispose();
      final restored = await JobsStore.create(client: client());
      await restored.refreshSavedSearchMatches(force: true);
      expect(restored.newMatchAlertJobs, isEmpty);
      stage = 2;
      fail = true;
      await restored.refreshSavedSearchMatches(force: true);
      expect(restored.savedMatchesError, isNotNull);
      expect(restored.newMatchAlertJobs, isEmpty);
      fail = false;
      await restored.refreshSavedSearchMatches(force: true);
      expect(restored.newMatchAlertJobs.map((job) => job.id), ['970003']);
      await restored.markUpdateRead('job-970003');
      expect(restored.newMatchAlertJobs, isEmpty);
      restored.dispose();
    },
  );
}
