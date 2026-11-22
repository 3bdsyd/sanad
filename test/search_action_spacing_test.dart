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
import 'package:snad/features/jobs/data/jobs_store.dart';
import 'package:snad/features/jobs/domain/job_filters.dart';
import 'package:snad/features/jobs/presentation/filter_sheet.dart';
import 'package:snad/features/jobs/presentation/home.dart';

Finder iconAction(String tooltip) => find.byWidgetPredicate(
  (widget) => widget is IconButton && widget.tooltip == tooltip,
);

void expectSeparated(WidgetTester tester, Finder first, Finder second) {
  final a = tester.getRect(first), b = tester.getRect(second);
  final gap = math.max(
    math.max(a.left - b.right, b.left - a.right),
    math.max(a.top - b.bottom, b.top - a.bottom),
  );
  expect(gap, greaterThanOrEqualTo(11.9), reason: '$a next to $b');
  expect(a.shortestSide, greaterThanOrEqualTo(44));
  expect(b.shortestSide, greaterThanOrEqualTo(44));
}

void main() {
  for (final (width, scale) in [
    (320.0, 1.0),
    (320.0, 2.0),
    (390.0, 1.0),
    (390.0, 2.0),
  ]) {
    testWidgets('search actions stay separate at $width and scale $scale', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      tester.view.physicalSize = Size(width, 844);
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
            final payload = switch (request.url.path) {
              '/api/filterjob' => fixtures['jobsPage'],
              '/api/job-fields' => fixtures['jobFields'],
              _ => {'success': true, 'data': []},
            };
            return http.Response.bytes(
              utf8.encode(jsonEncode(payload)),
              200,
              headers: {'content-type': 'application/json'},
            );
          }),
        ),
      ))!;
      await tester.runAsync(store.refresh);
      await tester.runAsync(() async {
        for (final query in ['تصميم', 'محاسب']) {
          store.setQuery(query);
          await store.saveSearch();
        }
      });
      store.setQuery('');
      store.updateFilters(const JobFilters(workMode: 'عن بُعد'));
      await tester.pumpWidget(
        MaterialApp(
          theme: sanadTheme(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              disableAnimations: true,
              textScaler: TextScaler.linear(scale),
            ),
            child: Directionality(
              textDirection: TextDirection.rtl,
              child: child!,
            ),
          ),
          home: JobsHome(store: store),
        ),
      );
      await tester.pumpAndSettle();
      for (final query in ['محاسب', 'Accountant']) {
        await tester.enterText(find.byType(TextField).first, query);
        await tester.pump(const Duration(milliseconds: 450));
        await tester.runAsync(() async {
          await Future<void>.delayed(Duration.zero);
        });
        await tester.pumpAndSettle();
        final clear = iconAction('مسح البحث');
        final filter = iconAction('تصفية الفرص');
        expectSeparated(tester, clear, filter);
        await tester.tap(clear);
        await tester.pumpAndSettle();
        expect(store.query, isEmpty);
        expect(store.filters.workMode, 'عن بُعد');
        expect(clear, findsNothing);
      }
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      final save = find.widgetWithText(TextButton, 'احفظ البحث');
      await tester.ensureVisible(save);
      await tester.pumpAndSettle();
      expectSeparated(tester, save, iconAction('مسح الفلاتر'));
      await tester.scrollUntilVisible(
        find.text('بحوثك'),
        -200,
        scrollable: find
            .descendant(
              of: find.byType(CustomScrollView).first,
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();
      final chips = find.byType(InputChip);
      expectSeparated(tester, chips.at(0), chips.at(1));
      final delete = find.descendant(
        of: chips.first,
        matching: find.byTooltip('حذف البحث المحفوظ'),
      );
      final deleteRect = tester.getRect(delete);
      final labelRect = tester.getRect(find.text('محاسب'));
      expect(labelRect.left - deleteRect.right, greaterThanOrEqualTo(11.9));
      await Scrollable.ensureVisible(tester.element(delete), alignment: .6);
      await tester.pumpAndSettle();
      expect(delete.hitTestable(), findsOneWidget);
      // The chip routes its whole 44px delete slot to this action, including
      // taps outside the visible 18px cross and near the adjacent label.
      await tester.runAsync(
        () => tester.tapAt(tester.getCenter(delete) + const Offset(20, 0)),
      );
      await tester.pumpAndSettle();
      expect(store.savedSearches.map((search) => search['name']), ['تصميم']);
      expect(store.query, isEmpty);
      expect(store.filters.workMode, 'عن بُعد');
      await tester.ensureVisible(iconAction('مسح الفلاتر'));
      await tester.pumpAndSettle();
      await tester.tap(iconAction('مسح الفلاتر'));
      await tester.pumpAndSettle();
      expect(store.filters.activeCount, 0);
      // Scrolling back up reveals the header and its filter action again.
      await tester.drag(
        find.byType(CustomScrollView).first,
        const Offset(0, 700),
      );
      await tester.pumpAndSettle();
      await tester.tap(iconAction('تصفية الفرص'));
      await tester.pumpAndSettle();
      expect(find.byType(FilterSheet), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      store.dispose();
      debugDefaultTargetPlatformOverride = null;
    });
  }
}
