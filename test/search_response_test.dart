import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:snad/features/jobs/data/api_client.dart';
import 'package:snad/features/jobs/data/jobs_store.dart';
import 'package:snad/features/jobs/domain/job_filters.dart';

http.Response response(Object payload, {int status = 200}) =>
    http.Response.bytes(
      utf8.encode(jsonEncode(payload)),
      status,
      headers: {'content-type': 'application/json'},
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final fixtures =
      jsonDecode(
            File(
              'docs/backend-handoff-2026-11-03/examples/responses.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;
  final empty = Map<String, dynamic>.from(fixtures['emptyPage'] as Map);
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  test(
    'explicit zero-result paginators accept [] and legacy null rows',
    () async {
      for (final payload in [
        empty,
        {...empty, 'data': null},
        {
          'success': true,
          'data': {'data': null, 'total': 0, 'last_page': 1},
        },
      ]) {
        final client = MockClient((request) async {
          expect(request.url.queryParameters['search'], 'no-match');
          return response(payload);
        });
        final api = SndApi(
          base: 'https://api.example.test',
          client: client,
          deviceId: 'test',
        );
        final page = await api.jobsPage(
          search: 'no-match',
          filters: const JobFilters(),
          categoryId: null,
          page: 1,
        );
        expect(page.jobs, isEmpty);
        expect(page.total, 0);
        expect(page.lastPage, 1);
        client.close();
      }
    },
  );

  test(
    'malformed responses and failed requests cannot masquerade as no results',
    () async {
      for (final (payload, status) in [
        ({'success': true, 'data': null}, 200),
        (
          {
            'success': true,
            'meta': {'total': 0},
          },
          200,
        ),
        (
          {
            'success': true,
            'data': null,
            'meta': {'total': 5},
          },
          200,
        ),
        ({...empty, 'success': false, 'message': 'تعذّر البحث.'}, 200),
        (empty, 404),
      ]) {
        final client = MockClient(
          (_) async => response(payload, status: status),
        );
        final api = SndApi(
          base: 'https://api.example.test',
          client: client,
          deviceId: 'test',
        );
        await expectLater(
          api.jobsPage(
            search: 'x',
            filters: const JobFilters(),
            categoryId: null,
            page: 1,
          ),
          throwsA(isA<JobsException>()),
        );
        client.close();
      }
    },
  );

  test(
    'successful empty search clears its previous error and keeps other errors',
    () async {
      final store = await JobsStore.create(
        client: MockClient((request) async {
          if (request.url.path == '/api/filterjob') {
            if (request.url.queryParameters['search'] == 'bad') {
              return response({'message': 'تعذّر البحث حالياً.'}, status: 422);
            }
            return response(
              request.url.queryParameters.containsKey('search')
                  ? {...empty, 'data': null}
                  : fixtures['jobsPage']!,
            );
          }
          if (request.url.path == '/api/job-fields') {
            return response(fixtures['jobFields']!);
          }
          return response({'success': true, 'data': []});
        }),
      );
      addTearDown(store.dispose);
      await store.refresh();
      expect(store.visibleJobs, hasLength(1));
      store.setQuery('bad');
      if (store.discoveryLoading) {
        final done = Completer<void>();
        void changed() {
          if (!store.discoveryLoading && !done.isCompleted) done.complete();
        }

        store.addListener(changed);
        try {
          await done.future.timeout(const Duration(seconds: 3));
        } finally {
          store.removeListener(changed);
        }
      }
      expect(store.error, 'تعذّر البحث حالياً.');
      store.setQuery('empty');
      if (store.discoveryLoading) {
        final done = Completer<void>();
        void changed() {
          if (!store.discoveryLoading && !done.isCompleted) done.complete();
        }

        store.addListener(changed);
        try {
          await done.future.timeout(const Duration(seconds: 3));
        } finally {
          store.removeListener(changed);
        }
      }
      expect(store.error, isNull);
      expect(store.visibleJobs, isEmpty);
      expect(store.totalCount, 0);
      expect(store.hasMore, isFalse);
      store.showError('تعذّر تحديث الإشعارات.');
      store.setQuery('another-empty');
      if (store.discoveryLoading) {
        final done = Completer<void>();
        void changed() {
          if (!store.discoveryLoading && !done.isCompleted) done.complete();
        }

        store.addListener(changed);
        try {
          await done.future.timeout(const Duration(seconds: 3));
        } finally {
          store.removeListener(changed);
        }
      }
      expect(store.error, 'تعذّر تحديث الإشعارات.');
      store.setQuery('bad');
      if (store.discoveryLoading) {
        final done = Completer<void>();
        void changed() {
          if (!store.discoveryLoading && !done.isCompleted) done.complete();
        }

        store.addListener(changed);
        try {
          await done.future.timeout(const Duration(seconds: 3));
        } finally {
          store.removeListener(changed);
        }
      }
      store.showError('تعذّر البحث حالياً.');
      store.setQuery('empty');
      if (store.discoveryLoading) {
        final done = Completer<void>();
        void changed() {
          if (!store.discoveryLoading && !done.isCompleted) done.complete();
        }

        store.addListener(changed);
        try {
          await done.future.timeout(const Duration(seconds: 3));
        } finally {
          store.removeListener(changed);
        }
      }
      expect(
        store.error,
        'تعذّر البحث حالياً.',
        reason:
            'A newer error must survive even if its text matches the previous search error.',
      );
    },
  );

  test(
    'an obsolete initial failure cannot replace a successful empty search',
    () async {
      final initial = Completer<http.Response>();
      final store = await JobsStore.create(
        client: MockClient((request) async {
          if (request.url.path == '/api/filterjob') {
            if (!request.url.queryParameters.containsKey('search')) {
              return initial.future;
            }
            return response(empty);
          }
          return response({'success': true, 'data': []});
        }),
      );
      addTearDown(store.dispose);
      final refresh = store.refresh();
      store.setQuery('empty');
      await Future<void>.delayed(const Duration(milliseconds: 450));
      expect(store.visibleJobs, isEmpty);
      expect(store.error, isNull);
      initial.complete(response({'message': 'طلب قديم تعذّر.'}, status: 422));
      await refresh;
      expect(store.error, isNull);
      expect(store.isOffline, isFalse);
    },
  );
}
