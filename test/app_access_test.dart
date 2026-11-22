import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:snad/core/design.dart';
import 'package:snad/features/app_access/data/app_access_controller.dart';
import 'package:snad/features/app_access/data/app_access_service.dart';
import 'package:snad/features/app_access/domain/app_access.dart';
import 'package:snad/features/app_access/presentation/app_access_page.dart';
import 'package:snad/features/jobs/presentation/welcome.dart';

void main() {
  test('status checks use the same HTTPS boundary as the catalog', () async {
    final client = MockClient((_) async => throw StateError('Must not send'));
    for (final base in [
      'http://api.test',
      'https://user@api.test',
      'https://api.test?key=value',
      'https://api.test#fragment',
      'bad address',
    ]) {
      await expectLater(
        AppAccessService(base: base, client: client).check(),
        throwsA(isA<FormatException>()),
      );
    }
    client.close();
  });

  test(
    'maintenance (including HTTP 503) takes priority over version checks',
    () async {
      for (final code in [200, 503]) {
        final paths = <String>[];
        final client = MockClient((request) async {
          paths.add(request.url.path);
          expect(request.followRedirects, isFalse);
          return http.Response(
            jsonEncode({
              'data': {'maintenance': '1'},
            }),
            code,
          );
        });
        final result = await AppAccessService(
          base: 'https://api.test',
          client: client,
        ).check(platform: 'android', version: '1.0.0');
        expect(result.kind, AppAccessKind.maintenance);
        expect(paths, ['/api/app/maintenance']);
        client.close();
      }
    },
  );

  test(
    'uses the supplied installed version and refuses the live admin URL',
    () async {
      final client = MockClient((request) async {
        if (request.url.path.endsWith('/maintenance')) {
          return http.Response('{"maintenance":false}', 200);
        }
        expect(request.url.queryParameters, {
          'version': '2.3.4',
          'platform': 'android',
        });
        return http.Response(
          jsonEncode({
            'force_update': true,
            'update_available': false,
            'latest_version': '3.0',
            'store_url': 'https://admin.jobsnad.com/admin/app-versions',
          }),
          200,
        );
      });
      final result = await AppAccessService(
        base: 'https://api.test/',
        client: client,
      ).check(platform: 'android', version: '2.3.4');
      expect(result.kind, AppAccessKind.update);
      expect(result.requiredUpdate, isTrue);
      expect(result.storeUri, isNull);
      client.close();
    },
  );

  test('web only checks maintenance; demo never sends a request', () async {
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      expect(request.url.path, '/api/app/maintenance');
      return http.Response('{"maintenance":false}', 200);
    });
    expect(
      (await AppAccessService(
        base: 'https://api.test',
        client: client,
      ).check()).kind,
      AppAccessKind.allowed,
    );
    await AppAccessService(base: 'demo', client: client).check(platform: 'ios');
    expect(calls, 1);
    client.close();
  });

  test(
    'missing optional routes allow entry, malformed and failed replies do not',
    () async {
      for (final sample in [
        (404, 'not found', false),
        (200, '[]', true),
        (500, '{}', true),
        (302, '{}', true),
        (200, '{"success":false}', true),
      ]) {
        final client = MockClient(
          (_) async => http.Response(sample.$2, sample.$1),
        );
        final future = AppAccessService(
          base: 'https://api.test',
          client: client,
        ).check(platform: 'ios', version: '1.0.0');
        if (sample.$3) {
          await expectLater(future, throwsA(isA<FormatException>()));
        } else {
          expect((await future).kind, AppAccessKind.allowed);
        }
        client.close();
      }
    },
  );

  test('store links reject other apps, credentials, and misleading hosts', () {
    const valid =
        'https://play.google.com/store/apps/details?id=com.jobsnad.snad';
    expect(AppAccess.validStoreUri(valid, 'android'), Uri.parse(valid));
    expect(
      AppAccess.validStoreUri(
        'https://apps.apple.com/us/app/sanad/id1234',
        'ios',
      ),
      isNotNull,
    );
    for (final bad in [
      valid.replaceFirst('https', 'http'),
      valid.replaceFirst('play.google.com', 'play.google.com.evil.test'),
      valid.replaceFirst('play.google.com', 'user@play.google.com'),
      valid.replaceFirst('com.jobsnad.snad', 'other.app'),
      'https://admin.jobsnad.com/admin/app-versions',
    ]) {
      expect(AppAccess.validStoreUri(bad, 'android'), isNull);
    }
  });

  for (final platform in ['android', 'ios']) {
    test(
      'uses the platform-specific URL returned by the API: $platform',
      () async {
        final link = platform == 'ios'
            ? 'https://apps.apple.com/app/sanad/id12345678'
            : 'https://play.google.com/store/apps/details?id=com.jobsnad.snad';
        final client = MockClient((request) async {
          if (request.url.path.endsWith('/maintenance')) {
            return http.Response(
              '{"maintenance":false,"message":"maintenance text"}',
              200,
            );
          }
          expect(request.url.queryParameters['platform'], platform);
          return http.Response(
            jsonEncode({
              'success': true,
              'data': {
                'update_available': true,
                'force_update': true,
                'store_url': link,
              },
            }),
            200,
          );
        });
        final result = await AppAccessService(
          base: 'https://api.test',
          client: client,
        ).check(platform: platform, version: '1.0.0');
        expect(result.storeUri, Uri.parse(link));
        expect(
          AppAccess.validStoreUri(link, platform == 'ios' ? 'android' : 'ios'),
          isNull,
        );
        client.close();
      },
    );
  }

  testWidgets('routine status checks have no robot speech message', (
    tester,
  ) async {
    final pending = Completer<AppAccess>();
    final controller = AppAccessController(() => pending.future);
    final check = controller.refresh();
    await tester.pumpWidget(
      MaterialApp(
        theme: sanadTheme(),
        home: AppAccessPage(controller: controller),
      ),
    );
    expect(find.text('جارٍ التحقق من الخدمة'), findsNothing);
    expect(
      find.text('جارٍ التحقق من حالة الخدمة وتوفر تحديثات للتطبيق.'),
      findsNothing,
    );
    pending.complete(const AppAccess());
    await check;
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  test('an unsuccessful recheck never dismisses a required gate', () async {
    for (final status in [
      const AppAccess(kind: AppAccessKind.maintenance),
      const AppAccess(kind: AppAccessKind.update, requiredUpdate: true),
    ]) {
      var fail = false;
      final controller = AppAccessController(() async {
        if (fail) throw TimeoutException('offline');
        return status;
      });
      await controller.refresh();
      controller.skipUpdate();
      expect(controller.allowed, isFalse);
      fail = true;
      await controller.refresh();
      expect(controller.status, same(status));
      expect(controller.allowed, isFalse);
      expect(controller.error, isNotNull);
      controller.dispose();
    }
  });

  test(
    'only optional updates can be skipped; a later forced update still blocks',
    () async {
      var required = false;
      final controller = AppAccessController(
        () async => AppAccess(
          kind: AppAccessKind.update,
          latestVersion: '1.5',
          requiredUpdate: required,
        ),
      );
      await controller.refresh();
      controller.skipUpdate();
      expect(controller.allowed, isTrue);
      await controller.refresh();
      expect(controller.allowed, isTrue);
      required = true;
      await controller.refresh();
      expect(controller.allowed, isFalse);
      controller.dispose();
    },
  );

  test(
    'clearing maintenance allows entry and concurrent checks are coalesced',
    () async {
      final pending = Completer<AppAccess>();
      var calls = 0;
      final controller = AppAccessController(() {
        calls++;
        return pending.future;
      });
      final first = controller.refresh();
      await controller.refresh();
      expect(calls, 1);
      expect(controller.allowed, isFalse);
      pending.complete(const AppAccess());
      await first;
      expect(controller.allowed, isTrue);
      controller.dispose();
    },
  );

  test('dispose while checking does not notify disposed listeners', () async {
    final pending = Completer<AppAccess>();
    final controller = AppAccessController(() => pending.future);
    final check = controller.refresh();
    controller.dispose();
    pending.complete(const AppAccess());
    await check;
  });

  for (final dark in [false, true]) {
    testWidgets(
      'gates and welcome fit a small screen at 200% text, dark=$dark',
      (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final states = [
          const AppAccess(kind: AppAccessKind.maintenance),
          const AppAccess(
            kind: AppAccessKind.update,
            requiredUpdate: true,
            latestVersion: '1.5',
          ),
          const AppAccess(kind: AppAccessKind.update),
        ];
        for (final state in states) {
          final controller = AppAccessController(() async => state);
          await controller.refresh();
          await tester.pumpWidget(
            MaterialApp(
              theme: sanadTheme(
                brightness: dark ? Brightness.dark : Brightness.light,
              ),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: TextScaler.linear(2),
                  disableAnimations: true,
                ),
                child: Directionality(
                  textDirection: TextDirection.rtl,
                  child: child!,
                ),
              ),
              home: AppAccessPage(controller: controller),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(find.byType(Scrollable), findsNothing);
          expect(find.text('حدّث هلّق'), findsNothing);
          expect(
            find.text('المتابعة لاحقاً'),
            state.kind == AppAccessKind.update && !state.requiredUpdate
                ? findsOneWidget
                : findsNothing,
          );
          await tester.pumpWidget(const SizedBox());
          controller.dispose();
        }
        await tester.pumpWidget(
          MaterialApp(
            theme: sanadTheme(
              brightness: dark ? Brightness.dark : Brightness.light,
            ),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(2),
                disableAnimations: true,
              ),
              child: Directionality(
                textDirection: TextDirection.rtl,
                child: child!,
              ),
            ),
            home: WelcomePage(onContinue: () {}),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('ابدأ الاستخدام'), findsOneWidget);
        expect(find.byType(Scrollable), findsNothing);
        expect(find.text('ابدأ الاستخدام').hitTestable(), findsOneWidget);
      },
    );
  }
}
