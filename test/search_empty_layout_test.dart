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
import 'package:snad/features/jobs/presentation/home.dart';

void main() {
  for (final scale in [1.0, 2.0]) {
    testWidgets('empty search stays usable at 320px and text scale $scale', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      tester.view.physicalSize = const Size(320, 640);
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
              '/api/filterjob' =>
                fixtures[request.url.queryParameters.containsKey('search')
                    ? 'emptyPage'
                    : 'jobsPage'],
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
      await tester.enterText(find.byType(TextField).first, 'لا يوجد هذا العمل');
      await tester.pump(const Duration(milliseconds: 450));
      await tester.runAsync(() async {
        await Future<void>.delayed(Duration.zero);
      });
      await tester.pumpAndSettle();
      expect(store.visibleJobs, isEmpty);
      expect(store.totalCount, 0);
      expect(store.error, isNull);
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('وسّع نطاق البحث'),
        220,
        scrollable: find
            .descendant(
              of: find.byType(CustomScrollView).first,
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();
      expect(find.text('وسّع نطاق البحث'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('عرض كل الفرص'));
      await tester.pumpAndSettle();
      expect(find.text('عرض كل الفرص').hitTestable(), findsOneWidget);
      await tester.tap(find.text('عرض كل الفرص'));
      await tester.pump(const Duration(milliseconds: 450));
      await tester.runAsync(() async {
        await Future<void>.delayed(Duration.zero);
      });
      await tester.pumpAndSettle();
      expect(store.query, isEmpty);
      expect(store.visibleJobs, hasLength(1));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      store.dispose();
      debugDefaultTargetPlatformOverride = null;
    });
  }
}
