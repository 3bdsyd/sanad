import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:snad/features/jobs/data/api_client.dart';

void main() {
  for (final platform in ['android', 'ios']) {
    test(
      'registers refreshed FCM token with the same device identity: $platform',
      () async {
        final sent = <String>[];
        final client = MockClient((request) async {
          expect(request.method, 'POST');
          expect(request.url.path, '/api/app/visit');
          expect(request.followRedirects, isFalse);
          expect(request.headers['X-Device-ID'], 'test-device');
          final body = jsonDecode(request.body) as Map;
          expect(body['device_id'], 'test-device');
          expect(body['platform'], platform);
          sent.add(body['fcm_token'] as String);
          return http.Response('{"success":true}', 200);
        });
        final api = SndApi(
          base: 'https://api.test',
          client: client,
          deviceId: 'test-device',
        );
        await api.registerPushToken(platform, 'first-token');
        await api.registerPushToken(platform, 'refreshed-token');
        expect(sent, ['first-token', 'refreshed-token']);
        client.close();
      },
    );
  }
  test(
    'registration failures propagate instead of reporting push ready',
    () async {
      final client = MockClient(
        (_) async => http.Response('{"message":"invalid token"}', 422),
      );
      final api = SndApi(
        base: 'https://api.test',
        client: client,
        deviceId: 'test-device',
      );
      await expectLater(
        api.registerPushToken('ios', 'bad-token'),
        throwsA(isA<JobsException>()),
      );
      client.close();
    },
  );
  test(
    'HTTP 200 without success does not mark registration complete',
    () async {
      final client = MockClient(
        (_) async => http.Response('{"success":false}', 200),
      );
      final api = SndApi(
        base: 'https://api.test',
        client: client,
        deviceId: 'test-device',
      );
      await expectLater(
        api.registerPushToken('android', 'test-token'),
        throwsA(isA<JobsException>()),
      );
      client.close();
    },
  );
}
