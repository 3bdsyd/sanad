import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:snad/core/design.dart';
import 'package:snad/core/theme_preference.dart';
import 'package:snad/features/jobs/data/jobs_store.dart';
import 'package:snad/features/jobs/domain/job_filters.dart';
import 'package:snad/features/jobs/presentation/about_page.dart';
import 'package:snad/features/jobs/presentation/filter_sheet.dart';
import 'package:snad/features/jobs/presentation/job_details.dart';
import 'package:snad/features/jobs/presentation/location_picker.dart';
import 'package:snad/features/jobs/presentation/notifications.dart';
import 'package:snad/features/jobs/presentation/post_job.dart';
import 'package:snad/features/jobs/presentation/web/sanad_web_shell.dart';

Widget app(Widget home, {double scale = 1, bool dark = false}) => MaterialApp(
  theme: sanadTheme(brightness: dark ? Brightness.dark : Brightness.light),
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(
      context,
    ).copyWith(disableAnimations: true, textScaler: TextScaler.linear(scale)),
    child: Directionality(textDirection: TextDirection.rtl, child: child!),
  ),
  home: home,
);

void main() {
  for (final scale in [1.0, 2.0]) {
    testWidgets(
      'about actions have space and remain usable at text scale $scale',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.linux;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        tester.view.physicalSize = const Size(320, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        SharedPreferences.setMockInitialValues({});
        FlutterSecureStorage.setMockInitialValues({});
        final fixtures =
            jsonDecode(
                  File(
                    'docs/backend-handoff-2026-11-03/examples/responses.json',
                  ).readAsStringSync(),
                )
                as Map<String, dynamic>;
        final store = (await tester.runAsync(
          () => JobsStore.create(
            client: MockClient((request) async {
              final data = switch (request.url.path) {
                '/api/filterjob' => fixtures['jobsPage'],
                '/api/job-fields' => fixtures['jobFields'],
                '/api/my-jobs' => fixtures['myJobs'],
                _ => {'success': true, 'data': []},
              };
              return http.Response.bytes(
                utf8.encode(jsonEncode(data)),
                200,
                headers: {'content-type': 'application/json'},
              );
            }),
          ),
        ))!;
        await tester.runAsync(store.refresh);
        await tester.runAsync(() => store.hideEmployer(store.jobs.single));
        if (scale == 2) {
          for (final page in [
            FilterSheet(store: store),
            PostJobPage(store: store),
            JobDetails(store: store, job: store.jobs.single),
            LocationPickerPage(
              store: store,
              initial: const JobFilters(country: 'SY', city: 'د'),
            ),
            NotificationsPage(store: store, onJob: (_) {}, initialSection: 1),
          ]) {
            await tester.pumpWidget(app(page, scale: scale));
            await tester.pumpAndSettle();
            expect(
              tester.takeException(),
              isNull,
              reason:
                  '${page.runtimeType} must fit a narrow screen with large text',
            );
            if (page is LocationPickerPage) {
              expect(find.byType(TextFormField), findsNothing);
              final province = find.widgetWithText(ListTile, 'المحافظة');
              await tester.ensureVisible(province);
              await tester.tap(province);
              await tester.pumpAndSettle();
              await tester.enterText(find.byType(TextField), 'إدلب');
              await tester.pump();
              await tester.tap(find.widgetWithText(ListTile, 'إدلب'));
              await tester.pumpAndSettle();
              expect(find.text('إدلب'), findsOneWidget);
              expect(tester.takeException(), isNull);
            }
            if (page is NotificationsPage) {
              await tester.scrollUntilVisible(
                find.text('سحب الإعلان'),
                200,
                scrollable: find.byType(Scrollable).last,
              );
              await tester.pumpAndSettle();
              await tester.tap(find.text('سحب الإعلان'));
              await tester.pumpAndSettle();
              final cancel = find.widgetWithText(TextButton, 'إلغاء');
              final confirm = find.widgetWithText(TextButton, 'تأكيد السحب');
              final a = tester.getRect(cancel), b = tester.getRect(confirm);
              final gap = math.max(
                math.max(a.left - b.right, b.left - a.right),
                math.max(a.top - b.bottom, b.top - a.bottom),
              );
              expect(gap, greaterThanOrEqualTo(11.9));
              await tester.ensureVisible(cancel);
              await tester.pumpAndSettle();
              await tester.tap(cancel);
              await tester.pumpAndSettle();
              expect(confirm, findsNothing);
              expect(store.submissions, hasLength(1));
              expect(tester.takeException(), isNull);
            }
            await tester.pumpWidget(const SizedBox.shrink());
          }
        }
        final theme = SanadThemeController();
        await tester.pumpWidget(
          SanadThemeScope(
            controller: theme,
            child: app(
              AboutPage(store: store),
              scale: scale,
              dark: scale == 2,
            ),
          ),
        );
        await tester.pumpAndSettle();
        final start = find.widgetWithText(TextButton, 'شاشة البداية');
        await tester.scrollUntilVisible(
          start,
          250,
          scrollable: find.byType(Scrollable).last,
        );
        await tester.pumpAndSettle();
        final restore = find.widgetWithText(TextButton, 'إظهار 1 جهة مخفية');
        expect(
          tester.getRect(start).top - tester.getRect(restore).bottom,
          greaterThanOrEqualTo(11.9),
        );
        expect(start.hitTestable(), findsOneWidget);
        expect(restore.hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.runAsync(() async {
          await tester.tap(restore);
        });
        await tester.pumpAndSettle();
        expect(store.hiddenEmployerCount, 0);
        expect(restore, findsNothing);
        await tester.pumpWidget(const SizedBox.shrink());
        store.dispose();
        theme.dispose();
        debugDefaultTargetPlatformOverride = null;
      },
    );
  }

  for (final (width, scale) in [(320.0, 2.0), (980.0, 2.0), (1440.0, 1.0)]) {
    testWidgets('web navigation actions fit ${width}px at text scale $scale', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final theme = SanadThemeController();
      await tester.pumpWidget(
        SanadThemeScope(
          controller: theme,
          child: app(
            SanadWebShell(
              section: 0,
              onSection: (_) {},
              onNotices: () {},
              onAbout: () {},
              child: const SingleChildScrollView(
                child: Column(
                  children: [SizedBox(height: 100), SanadWebFooter()],
                ),
              ),
            ),
            scale: scale,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final buttons = find
          .byWidgetPredicate((widget) => widget is ButtonStyleButton)
          .hitTestable();
      final rects = [
        for (final element in buttons.evaluate())
          tester.getRect(find.byWidget(element.widget)),
      ];
      for (var i = 0; i < rects.length; i++) {
        expect(rects[i].height, greaterThanOrEqualTo(44));
        for (var j = i + 1; j < rects.length; j++) {
          final a = rects[i], b = rects[j];
          final gap = math.max(
            math.max(a.left - b.right, b.left - a.right),
            math.max(a.top - b.bottom, b.top - a.bottom),
          );
          expect(
            gap,
            greaterThanOrEqualTo(11.9),
            reason: 'Separate actions must not touch: $a, $b',
          );
        }
      }
      await tester.pumpWidget(const SizedBox.shrink());
      theme.dispose();
    });
  }
}
