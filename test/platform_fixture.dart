import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:snad/features/jobs/data/jobs_store.dart';
import 'package:snad/features/platform/domain/platform_models.dart';

final platformFixtures = object(
  jsonDecode(
    File(
      'docs/backend-handoff-2026-11-03/examples/platform.json',
    ).readAsStringSync(),
  ),
);

Future<JobsStore> platformFixture(
  WidgetTester tester, {
  bool guest = false,
  bool empty = false,
  bool employer = false,
  bool newAccount = false,
  List<http.Request>? requests,
}) async {
  JobsStore.accountFeaturesOverride = true;
  debugDefaultTargetPlatformOverride = TargetPlatform.linux;
  SharedPreferences.setMockInitialValues({});
  const base = 'https://platform.example.test';
  FlutterSecureStorage.setMockInitialValues(
    guest
        ? {}
        : {
            'snad.platform.${Uri.encodeComponent(base)}.session': jsonEncode(
              platformFixtures['session'],
            ),
          },
  );
  return (await tester.runAsync(() async {
    final store = await JobsStore.create(
      base: base,
      client: MockClient((r) async {
        requests?.add(r);
        final path = r.url.path.replaceFirst('/api/v2', '');
        final f = platformFixtures;
        if (path == '/auth/email/verify' &&
            newAccount &&
            textOf(object(jsonDecode(r.body))['name']).isEmpty) {
          return http.Response(
            jsonEncode({
              'error': {
                'code': 'name_required',
                'message': 'أدخل اسمك لإنشاء حسابك.',
              },
            }),
            422,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }
        Object data = <Json>[];
        Json? meta;
        if (r.url.path == '/api/filterjob') {
          return _reply({
            'success': true,
            'data': [f['job']],
            'meta': {
              'current_page': 1,
              'last_page': 1,
              'per_page': 24,
              'total': 1,
            },
          });
        }
        if (r.url.path == '/api/job-fields') {
          return _reply({
            'success': true,
            'data': [
              {'id': 1, 'name_ar': 'تقنية', 'name_en': 'Technology'},
            ],
          });
        }
        if (path == '/capabilities') {
          data = {
            'platform_enabled': true,
            'email_login': true,
            'google_login': true,
            'apple_login': true,
          };
        } else if (path == '/auth/email/challenge') {
          data = {'challenge_id': 'challenge-test-1', 'retry_after': 60};
        } else if (path == '/auth/email/verify') {
          data = f['session'];
        } else if (path == '/me') {
          data = f['member'];
        } else if (path == '/me/favorite-ids') {
          data = empty ? [] : ['970001'];
        } else if (path == '/me/jobs') {
          data = empty ? [] : [f['own_job']];
        } else if (path == '/me/favorites') {
          data = empty ? [] : [f['job']];
        } else if (path == '/me/saved-searches') {
          data = empty ? [] : [f['search']];
        } else if (path == '/me/notifications') {
          data = empty ? [] : [f['notice']];
        } else if (path == '/me/applications' ||
            path == '/jobs/970001/applications') {
          data = r.method == 'POST'
              ? f['application']
              : empty
              ? []
              : [f['application']];
        } else if (path == '/applications/application-test-1') {
          data = {
            ...object(f['application']),
            'viewer_role': employer ? 'employer' : 'candidate',
            if (r.method == 'PATCH')
              'status': object(jsonDecode(r.body))['status'],
          };
        } else if (path == '/conversations') {
          data = empty ? [] : [f['conversation']];
        } else if (path == '/conversations/conversation-test-1/messages') {
          data = r.method == 'POST'
              ? {...object(f['message']), ...object(jsonDecode(r.body))}
              : empty
              ? []
              : [f['message']];
          meta = {'next_cursor': null, 'can_send': true};
        } else if (path == '/me/complaints') {
          data = empty ? [] : [f['complaint']];
        } else if (path == '/complaints') {
          data = f['complaint'];
        } else if (path == '/me/notification-preferences') {
          data = {
            'saved_search_matches': true,
            'job_moderation': true,
            'applications': true,
            'messages': true,
            'complaints': true,
          };
        } else if (path == '/uploads') {
          data = {'id': 'upload-test-1'};
        }
        return _reply({'data': data, 'meta': ?meta});
      }),
    );
    await store.platform.initialize();
    expect(store.accountsEnabled, isTrue);
    expect(store.platform.requiresAccount, isTrue);
    expect(store.platform.signedIn, !guest);
    await store.refresh();
    if (!guest) {
      await Future.wait(
        [
          '/me/jobs',
          '/me/favorites',
          '/me/favorite-ids',
          '/me/applications',
          '/conversations',
        ].map(store.platform.load),
      );
    }
    return store;
  }))!;
}

http.Response _reply(Object body) => http.Response.bytes(
  utf8.encode(jsonEncode(body)),
  200,
  headers: {'content-type': 'application/json'},
);
