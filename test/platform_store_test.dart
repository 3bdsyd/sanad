import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:snad/features/platform/data/platform_store.dart';
import 'package:snad/features/platform/domain/platform_models.dart';

final fixtures = object(
  jsonDecode(
    File(
      'docs/backend-handoff-2026-11-03/examples/platform.json',
    ).readAsStringSync(),
  ),
);
http.Response reply(
  Object data, {
  int status = 200,
  Map<String, String>? headers,
}) => http.Response.bytes(
  utf8.encode(jsonEncode(data)),
  status,
  headers: {'content-type': 'application/json', ...?headers},
);

class Harness {
  Harness(
    Future<http.Response> Function(http.Request) handle, {
    this.base = 'https://platform.example.test',
    Map<String, String>? secrets,
  }) : secrets = secrets ?? {} {
    client = MockClient((r) async {
      requests.add(r);
      return handle(r);
    });
    store = PlatformStore(
      base: base,
      client: client,
      readSecret: (key) async => this.secrets[key],
      writeSecret: (key, value) async {
        if (value == null) {
          this.secrets.remove(key);
        } else {
          this.secrets[key] = value;
        }
      },
    );
  }
  final String base;
  final Map<String, String> secrets;
  final requests = <http.Request>[];
  late final http.Client client;
  late final PlatformStore store;
  Future<void> login() async {
    secrets['snad.platform.${Uri.encodeComponent(base)}.session'] = jsonEncode(
      fixtures['session'],
    );
    await store.initialize();
  }

  void close() {
    store.dispose();
    client.close();
  }
}

void main() {
  test(
    'private requests never use a device identity or guest fallback',
    () async {
      final h = Harness((_) async => reply({}));
      addTearDown(h.close);
      await h.store.initialize();
      await expectLater(
        h.store.load('/me/applications'),
        throwsA(isA<PlatformFailure>().having((e) => e.status, 'status', 401)),
      );
      expect(h.requests, isEmpty);
    },
  );
  test(
    'OTP verifies into securely persisted account, no token in query',
    () async {
      final h = Harness(
        (r) async => reply({
          'data': r.url.path.endsWith('/capabilities')
              ? {'platform_enabled': true, 'email_login': true}
              : r.url.path.endsWith('/challenge')
              ? {'challenge_id': 'challenge-test-1', 'retry_after': 60}
              : fixtures['session'],
        }),
      );
      addTearDown(h.close);
      final challenge = await h.store.requestCode('candidate@example.test');
      await h.store.verifyCode(
        textOf(challenge['challenge_id']),
        '123456',
        'مستخدم الاختبار',
      );
      expect(h.store.signedIn, isTrue);
      expect(
        h.secrets.values.any((v) => v.contains('TEST_ONLY_REFRESH')),
        isTrue,
      );
      for (final r in h.requests) {
        expect(r.url.query, isEmpty);
        expect(r.headers.containsKey('X-Device-ID'), isFalse);
      }
    },
  );
  test(
    'concurrent 401s rotate once and replay under new access token',
    () async {
      var rotations = 0;
      final gate = Completer<void>();
      final h = Harness((r) async {
        if (r.url.path.endsWith('/auth/refresh')) {
          rotations++;
          await gate.future;
          return reply({
            'data': {
              ...object(fixtures['session']),
              'access_token': 'rotated-access',
              'refresh_token': 'rotated-refresh',
            },
          });
        }
        if (r.headers['Authorization'] != 'Bearer rotated-access') {
          return reply({
            'error': {'code': 'expired', 'message': 'انتهت الجلسة'},
          }, status: 401);
        }
        return reply({'data': []});
      });
      addTearDown(h.close);
      await h.login();
      final a = h.store.load('/me/applications'), b = h.store.load('/me/jobs');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      gate.complete();
      await Future.wait([a, b]);
      expect(rotations, 1);
      expect(h.store.signedIn, isTrue);
      expect(
        h.requests
            .where((r) => r.headers['Authorization'] == 'Bearer rotated-access')
            .length,
        2,
      );
    },
  );
  test('single-flight reads share one HTTP request', () async {
    final h = Harness((_) async => reply({'data': []}));
    addTearDown(h.close);
    await h.login();
    await Future.wait(List.generate(8, (_) => h.store.load('/conversations')));
    expect(h.requests.length, 1);
  });
  test(
    'logout blocks a late personal response and clears disk snapshots',
    () async {
      final pending = Completer<http.Response>();
      final h = Harness(
        (r) async => r.method == 'GET'
            ? pending.future
            : reply({
                'data': {'success': true},
              }),
      );
      addTearDown(h.close);
      await h.login();
      final read = h.store.load('/me/jobs');
      final checked = expectLater(read, completion(isEmpty));
      await Future<void>.delayed(Duration.zero);
      await h.store.logout();
      pending.complete(
        reply({
          'data': [fixtures['own_job']],
        }),
      );
      await checked;
      expect(h.store.signedIn, isFalse);
      expect(h.store.postings, isEmpty);
      expect(h.secrets, isEmpty);
    },
  );
  test(
    'message retry survives restart with the same client ID and key',
    () async {
      final keys = <String>[];
      var fail = true;
      Future<http.Response> handle(http.Request r) async {
        keys.add(r.headers['Idempotency-Key']!);
        if (fail) throw const SocketException('offline');
        final body = object(jsonDecode(r.body));
        return reply({
          'data': {
            ...object(fixtures['message']),
            'client_id': body['client_id'],
          },
        });
      }

      final h = Harness(handle);
      await h.login();
      await expectLater(
        h.store.sendMessage('conversation-test-1', 'رسالة اختبار'),
        throwsA(isA<PlatformFailure>()),
      );
      final pending = h.store.messages('conversation-test-1').single;
      expect(pending.failed, isTrue);
      final secrets = Map<String, String>.from(h.secrets);
      h.close();
      fail = false;
      final restored = Harness(handle, secrets: secrets);
      addTearDown(restored.close);
      await restored.store.initialize();
      expect(
        restored.store.messages('conversation-test-1').single.failed,
        isTrue,
      );
      await restored.store.retryMessage(pending.clientId);
      expect(keys[0], keys[1]);
      expect(
        restored.store.messages('conversation-test-1').single.failed,
        isFalse,
      );
      expect(restored.store.messages('conversation-test-1').length, 1);
    },
  );
  test('uncertain job create retains idempotency key across restart', () async {
    final keys = <String>[];
    var fail = true;
    Future<http.Response> handle(http.Request r) async {
      keys.add(r.headers['Idempotency-Key']!);
      if (fail) throw const SocketException('lost response');
      return reply({'data': fixtures['own_job']}, status: 201);
    }

    final h = Harness(handle);
    await h.login();
    await expectLater(
      h.store.createJob({'title': 'اختبار'}),
      throwsA(
        isA<PlatformFailure>().having((e) => e.uncertain, 'uncertain', isTrue),
      ),
    );
    final secrets = Map<String, String>.from(h.secrets);
    h.close();
    fail = false;
    final restored = Harness(handle, secrets: secrets);
    addTearDown(restored.close);
    await restored.store.initialize();
    await restored.store.createJob({'title': 'اختبار'});
    expect(keys.toSet().length, 1);
  });
  test('forbidden resource purges its cached contents', () async {
    var allowed = true;
    final h = Harness(
      (_) async => allowed
          ? reply({
              'data': [fixtures['message']],
              'meta': {'next_cursor': null, 'can_send': true},
            })
          : reply({
              'error': {'code': 'forbidden', 'message': 'غير متاح'},
            }, status: 403),
    );
    addTearDown(h.close);
    await h.login();
    await h.store.load('/conversations/conversation-test-1/messages');
    allowed = false;
    await expectLater(
      h.store.load('/conversations/conversation-test-1/messages'),
      throwsA(isA<PlatformFailure>()),
    );
    expect(h.store.messages('conversation-test-1'), isEmpty);
  });
  test('429 respects cooldown and never retries mutations silently', () async {
    final h = Harness(
      (_) async => reply(
        {
          'error': {'code': 'rate_limited', 'message': 'انتظر'},
        },
        status: 429,
        headers: {'retry-after': '60'},
      ),
    );
    addTearDown(h.close);
    await h.login();
    await expectLater(
      h.store.setFavorite('970001', true),
      throwsA(isA<PlatformFailure>()),
    );
    await expectLater(
      h.store.setFavorite('970001', true),
      throwsA(isA<PlatformFailure>()),
    );
    expect(h.requests.length, 1);
  });
  test(
    'favorite PUT returns confirmed card and ID without a second fetch',
    () async {
      final h = Harness((_) async => reply({'data': fixtures['job']}));
      addTearDown(h.close);
      await h.login();
      await h.store.setFavorite('970001', true);
      expect(h.store.favoriteIds, {'970001'});
      expect(h.store.favorites.single.title, isNotEmpty);
      expect(h.requests.single.method, 'PUT');
    },
  );
  test('foreign API namespace cannot restore another API account', () async {
    final a = Harness((_) async => reply({}));
    await a.login();
    final b = Harness(
      (_) async => reply({}),
      base: 'https://another.example.test',
      secrets: a.secrets,
    );
    addTearDown(b.close);
    await b.store.initialize();
    expect(b.store.signedIn, isFalse);
    a.close();
  });
  test('redirect is never followed with a Bearer token', () async {
    final h = Harness(
      (_) async => reply(
        {},
        status: 302,
        headers: {'location': 'https://untrusted.example/steal'},
      ),
    );
    addTearDown(h.close);
    await h.login();
    await expectLater(
      h.store.load('/me/jobs'),
      throwsA(isA<PlatformFailure>()),
    );
    expect(h.requests.single.followRedirects, isFalse);
  });
  test(
    'application status sends optimistic version, not client ownership',
    () async {
      final h = Harness((_) async => reply({'data': fixtures['application']}));
      addTearDown(h.close);
      await h.login();
      await h.store.applicationAction(
        'application-test-1',
        'under_review',
        expectedVersion: 3,
      );
      final body = object(jsonDecode(h.requests.single.body));
      expect(body, {
        'status': 'under_review',
        'note': '',
        'expected_version': 3,
      });
    },
  );
  test('image size and format rejected before an upload request', () async {
    final h = Harness((_) async => reply({}));
    addTearDown(h.close);
    await h.login();
    await expectLater(
      h.store.uploadComplaintImage(Uint8List(1), 'application/pdf'),
      throwsA(isA<PlatformFailure>()),
    );
    expect(h.requests, isEmpty);
  });
  test('an older favorite read cannot erase a confirmed save', () async {
    final old = Completer<http.Response>();
    final h = Harness(
      (r) async =>
          r.method == 'GET' ? old.future : reply({'data': fixtures['job']}),
    );
    addTearDown(h.close);
    await h.login();
    final reading = h.store.load('/me/favorites');
    await Future<void>.delayed(Duration.zero);
    await h.store.setFavorite('970001', true);
    old.complete(reply({'data': []}));
    await reading;
    expect(h.store.favoriteIds, {'970001'});
    expect(h.store.favorites.single.id, '970001');
  });
  test('chat refresh keeps loaded history and its older cursor', () async {
    final h = Harness(
      (r) async => reply({
        'data': [
          {
            ...object(fixtures['message']),
            'id': r.url.queryParameters.containsKey('cursor')
                ? 'old-message'
                : 'new-message',
            'created_at': r.url.queryParameters.containsKey('cursor')
                ? '2035-01-01T10:00:00Z'
                : '2035-01-01T12:00:00Z',
          },
        ],
        'meta': {
          'can_send': true,
          'next_cursor': r.url.queryParameters.containsKey('cursor')
              ? 'cursor-older'
              : 'cursor-first',
        },
      }),
    );
    addTearDown(h.close);
    await h.login();
    const path = '/conversations/conversation-test-1/messages';
    await h.store.load(path);
    await h.store.loadMore(path);
    await h.store.load(path);
    expect(h.store.messages('conversation-test-1').length, 2);
    expect(
      object(h.store.snapshot(path)['meta'])['next_cursor'],
      'cursor-older',
    );
  });
  test(
    'confirmed notification read also updates its cached unread state',
    () async {
      final h = Harness(
        (r) async => reply(
          r.method == 'GET'
              ? {
                  'data': [fixtures['notice']],
                  'meta': {'next_cursor': null, 'unread_count': 1},
                }
              : {
                  'data': {'success': true},
                },
        ),
      );
      addTearDown(h.close);
      await h.login();
      await h.store.load('/me/notifications');
      await h.store.markNoticeRead('notice-test-1');
      expect(
        objects(
          h.store.snapshot('/me/notifications')['data'],
        ).single['is_read'],
        isTrue,
      );
      expect(
        object(h.store.snapshot('/me/notifications')['meta'])['unread_count'],
        0,
      );
    },
  );
  test('private restore invalidates an early guest favorite read', () async {
    final h = Harness((_) async => reply({'data': []}));
    addTearDown(h.close);
    expect(h.store.favoriteIds, isEmpty);
    h.secrets['snad.platform.${Uri.encodeComponent(h.base)}.member-test-1.private'] =
        jsonEncode({
          'cached_at': DateTime.now().toUtc().toIso8601String(),
          'snapshots': {
            '/me/favorite-ids': {
              'data': ['970001'],
            },
          },
        });
    await h.login();
    expect(h.store.favoriteIds, {'970001'});
  });
  test('confirmed image uploads use a new key when selected again', () async {
    final h = Harness(
      (_) async => reply({
        'data': {'id': 'image-1'},
      }),
    );
    addTearDown(h.close);
    await h.login();
    final image = Uint8List.fromList([137, 80, 78, 71]);
    await h.store.uploadComplaintImage(image, 'image/png');
    await h.store.uploadComplaintImage(image, 'image/png');
    expect(h.requests.length, 2);
    expect(
      h.requests.first.headers['Idempotency-Key'],
      isNot(h.requests.last.headers['Idempotency-Key']),
    );
  });
  test('professional profile supports legacy defaults and zero years', () {
    const old = Member({'id': 'member-1', 'name': 'مستخدم'});
    expect(old.skills, isEmpty);
    expect(old.experienceYears, isNull);
    const firstJob = Member({
      'experience_years': 0,
      'skills': ['Flutter'],
    });
    expect(firstJob.profileSteps['سنوات الخبرة'], isTrue);
    expect(profileYears('٠'), 0);
    expect(profileYears('۱۲'), 12);
    expect(profileLabels('Flutter، Dart, Flutter'), ['Flutter', 'Dart']);
    expect(validateProfileLabels('a' * 41, 20), isNotNull);
  });
  test(
    'profile mutation rejects a mismatched member without replacing session',
    () async {
      final h = Harness(
        (_) async => reply({
          'data': {...object(fixtures['member']), 'id': 'wrong-member'},
        }),
      );
      addTearDown(h.close);
      await h.login();
      await expectLater(
        h.store.updateProfile({'name': 'اسم جديد'}),
        throwsA(isA<PlatformFailure>()),
      );
      expect(h.store.user!.id, 'member-test-1');
      expect(h.store.signedIn, isTrue);
    },
  );
  test(
    'changing application status removes it from a cached previous-status query',
    () async {
      var changed = false;
      final h = Harness((r) async {
        if (r.method == 'PATCH') {
          changed = true;
          return reply({
            'data': {
              ...object(fixtures['application']),
              'status': 'under_review',
              'version': 2,
            },
          });
        }
        return reply({
          'data': changed ? [] : [fixtures['application']],
          'meta': {'next_cursor': null},
        });
      });
      addTearDown(h.close);
      await h.login();
      const path = '/me/applications?status=submitted&q=Flutter';
      await h.store.load(path);
      expect(objects(h.store.snapshot(path)['data']), hasLength(1));
      await h.store.applicationAction(
        'application-test-1',
        'under_review',
        expectedVersion: 1,
      );
      expect(objects(h.store.snapshot(path)['data']), isEmpty);
    },
  );
  test(
    'a first in-flight application query cannot restore the pre-mutation status',
    () async {
      final old = Completer<http.Response>();
      var changed = false;
      final h = Harness((r) async {
        if (r.method == 'PATCH') {
          changed = true;
          return reply({
            'data': {
              ...object(fixtures['application']),
              'status': 'under_review',
              'version': 2,
            },
          });
        }
        return changed
            ? reply({
                'data': [],
                'meta': {'next_cursor': null},
              })
            : old.future;
      });
      addTearDown(h.close);
      await h.login();
      const path = '/me/applications?status=submitted';
      final reading = h.store.load(path);
      await Future<void>.delayed(Duration.zero);
      await h.store.applicationAction(
        'application-test-1',
        'under_review',
        expectedVersion: 1,
      );
      old.complete(
        reply({
          'data': [fixtures['application']],
        }),
      );
      await reading;
      expect(objects(h.store.snapshot(path)['data']), isEmpty);
      expect(h.requests.where((r) => r.method == 'GET'), hasLength(2));
    },
  );
}
