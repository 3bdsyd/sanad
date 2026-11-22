import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:snad/core/design.dart';
import 'package:snad/features/jobs/data/jobs_store.dart';
import 'package:snad/features/jobs/domain/job_geography.dart';
import 'package:snad/features/jobs/presentation/country_setup.dart';
import 'package:snad/features/jobs/presentation/home.dart';
import 'package:snad/features/jobs/presentation/post_job.dart';
import 'package:snad/features/jobs/presentation/notifications.dart';

final fixtures =
    jsonDecode(
          File(
            'docs/backend-handoff-2026-11-03/examples/responses.json',
          ).readAsStringSync(),
        )
        as Map<String, dynamic>;
http.Response response(Object payload) => http.Response.bytes(
  utf8.encode(jsonEncode(payload)),
  200,
  headers: {'content-type': 'application/json'},
);

Future<JobsStore> createStore(
  WidgetTester tester, {
  List<Uri>? requests,
}) async => (await tester.runAsync(() async {
  final store = await JobsStore.create(
    client: MockClient((request) async {
      requests?.add(request.url);
      if (request.url.path == '/api/filterjob') {
        final page = Map<String, dynamic>.from(fixtures['jobsPage'] as Map);
        final row = Map<String, dynamic>.from(
          (page['data'] as List).first as Map,
        );
        final requestedCountry = request.url.queryParameters['country'];
        if (requestedCountry != null) row['country'] = requestedCountry;
        page['data'] = [
          for (var i = 0; i < 30; i++) {...row, 'id': 970001 + i},
        ];
        page['meta'] = {'current_page': 1, 'last_page': 1, 'total': 30};
        return response(page);
      }
      if (request.url.path == '/api/job-fields') {
        return response(fixtures['jobFields']);
      }
      if (request.url.path == '/api/my-jobs') {
        return response(fixtures['myJobs']);
      }
      return response({'success': true, 'data': []});
    }),
  );
  await store.refresh();
  return store;
}))!;

Widget app(Widget child, {double scale = 1, bool reduce = true}) => MaterialApp(
  theme: sanadTheme(),
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(
      context,
    ).copyWith(disableAnimations: reduce, textScaler: TextScaler.linear(scale)),
    child: Directionality(textDirection: TextDirection.rtl, child: child!),
  ),
  home: child,
);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  test(
    'only Syria is selectable while legacy country parsing stays available',
    () {
      expect(availableJobCountries.map((country) => country.code), ['SY']);
      expect(countryFor('JP')!.currency, 'JPY');
    },
  );

  testWidgets('Syria opens directly without a country selection at 200%', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final requests = <Uri>[];
    final store = await createStore(tester, requests: requests);
    await tester.pumpWidget(
      app(
        CountryGate(
          store: store,
          child: const Scaffold(body: Text('ready')),
        ),
        scale: 2,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(CountrySetupPage), findsNothing);
    expect(store.filters.country, 'SY');
    expect(store.needsCountryChoice, isFalse);
    expect(find.text('ready'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(() async {
      await store.refresh();
    });
    expect(
      requests.any((uri) => uri.queryParameters['country'] == 'سوريا'),
      isTrue,
    );
    store.dispose();
    final restored = await createStore(tester);
    expect(restored.needsCountryChoice, isFalse);
    expect(restored.filters.country, 'SY');
    restored.dispose();
  });

  for (final reduce in [false, true]) {
    testWidgets(
      'primary button animates its whole surface, reduceMotion=$reduce',
      (tester) async {
        var presses = 0;
        await tester.pumpWidget(
          app(
            Scaffold(
              body: Center(
                child: SanadPrimaryButton(
                  onPressed: () => presses++,
                  child: const Text('متابعة'),
                ),
              ),
            ),
            reduce: reduce,
          ),
        );
        final transform = find
            .descendant(
              of: find.byType(SanadPrimaryButton),
              matching: find.byType(Transform),
            )
            .first;
        double scale() =>
            tester.widget<Transform>(transform).transform.storage[0];
        final gesture = await tester.startGesture(
          tester.getCenter(find.text('متابعة')),
        );
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 110));
        expect(scale(), closeTo(reduce ? 1 : .965, .001));
        await gesture.up();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 140));
        expect(scale(), closeTo(reduce ? 1 : 1.025, .001));
        await tester.pumpAndSettle();
        expect(scale(), closeTo(1, .001));
        expect(presses, 1);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets(
    'home top bar stays fixed while only search floats and pins for typing',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = await createStore(tester);
      await tester.pumpWidget(app(JobsHome(store: store)));
      await tester.pumpAndSettle();
      final top = tester.getRect(find.text('سند'));
      final scroll = find.byType(CustomScrollView).first;
      await tester.drag(scroll, const Offset(0, -900));
      await tester.pumpAndSettle();
      expect(tester.getRect(find.text('سند')), top);
      expect(find.byType(TextField).hitTestable(), findsNothing);
      await tester.drag(scroll, const Offset(0, 90));
      await tester.pumpAndSettle();
      expect(find.byType(TextField).hitTestable(), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'محاسب');
      await tester.pump(const Duration(milliseconds: 450));
      await tester.drag(scroll, const Offset(0, -400));
      await tester.pumpAndSettle();
      expect(find.byType(TextField).hitTestable(), findsOneWidget);
      expect(tester.getRect(find.text('سند')), top);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      store.dispose();
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets(
    'post steps hide down and return immediately, while its app bar stays fixed',
    (tester) async {
      final store = await createStore(tester);
      await tester.pumpWidget(app(PostJobPage(store: store)));
      await tester.pumpAndSettle();
      final titleRect = tester.getRect(find.text('إضافة فرصة'));
      expect(find.text('التواصل').hitTestable(), findsOneWidget);
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -650));
      await tester.pumpAndSettle();
      expect(find.text('التواصل').hitTestable(), findsNothing);
      expect(tester.getRect(find.text('إضافة فرصة')), titleRect);
      await tester.drag(find.byType(CustomScrollView), const Offset(0, 90));
      await tester.pumpAndSettle();
      expect(find.text('التواصل').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      store.dispose();
    },
  );

  testWidgets(
    'notification sections are separate and refresh appears below the app bar',
    (tester) async {
      final store = await createStore(tester);
      await tester.pumpWidget(
        app(NotificationsPage(store: store, onJob: (_) {}), scale: 2),
      );
      await tester.pumpAndSettle();
      expect(find.text('سحب الإعلان'), findsNothing);
      final ownerTab = find.text('إعلاناتي · 1');
      await tester.tap(ownerTab);
      await tester.pumpAndSettle();
      expect(find.text('تنبيهات سند'), findsOneWidget);
      await tester.tap(find.byTooltip('تحديث الإشعارات'));
      await tester.pump(const Duration(milliseconds: 400));
      final titleBottom = tester.getRect(find.byType(AppBar)).bottom;
      expect(
        tester.getRect(find.text('جارٍ تحديث الإشعارات…')).top,
        greaterThanOrEqualTo(titleBottom),
      );
      await tester.runAsync(() async {
        await Future<void>.delayed(Duration.zero);
      });
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      store.dispose();
    },
  );
}
