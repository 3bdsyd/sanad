import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:snad/core/design.dart';
import 'package:snad/features/jobs/data/jobs_store.dart';
import 'package:snad/features/jobs/presentation/post_job.dart';
import 'package:snad/features/jobs/presentation/geography_picker.dart';
import 'package:snad/features/jobs/presentation/location_picker.dart';
import 'package:snad/features/jobs/domain/job_filters.dart';

void main() {
  testWidgets(
    'Syria governorate and original fields reach the actual submission body without login',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
      Map<String, dynamic>? posted;
      final store = await tester.runAsync(
        () => JobsStore.create(
          client: MockClient((request) async {
            Object data = [];
            if (request.url.path == '/api/job-fields') {
              data = [
                {'id': 1, 'name_ar': 'تقنية', 'is_active': true},
              ];
            }
            if (request.method == 'POST' && request.url.path == '/api/jobs') {
              posted = jsonDecode(request.body) as Map<String, dynamic>;
              data = {
                ...posted!,
                'id': 700,
                'status': 'pending',
                'is_active': true,
                'created_at': '2026-11-03T00:00:00Z',
                'expires_at': '2035-01-01T00:00:00Z',
              };
            }
            return http.Response.bytes(
              utf8.encode(jsonEncode({'data': data})),
              200,
              headers: {'content-type': 'application/json'},
            );
          }),
        ),
      );
      await tester.runAsync(() => store!.refresh());
      await tester.pumpWidget(
        MaterialApp(
          theme: sanadTheme(),
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: PostJobPage(store: store!),
          ),
        ),
      );
      await tester.pumpAndSettle();

      Future<void> enter(String label, String value) async {
        final field = find.ancestor(
          of: find.text(label),
          matching: find.byType(TextFormField),
        );
        await tester.ensureVisible(field);
        await tester.enterText(field, value);
        await tester.pump(const Duration(milliseconds: 400));
      }

      await enter('المسمّى الوظيفي', 'محاسب مالي');
      await enter('اسم جهة العمل', 'جهة اختبار');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await Scrollable.ensureVisible(
        tester.element(find.text('اختر المحافظة')),
        alignment: .5,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('اختر المحافظة'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'دمشق');
      await tester.pump();
      await tester.tap(find.widgetWithText(ListTile, 'دمشق'));
      await tester.pumpAndSettle();
      await enter(
        'وصف الوظيفة والمسؤوليات',
        'وصف تجريبي واضح للوظيفة والمسؤوليات المطلوبة ضمن الفريق.',
      );
      await tester.tap(find.text('التالي: التواصل والراتب'));
      await tester.pumpAndSettle();
      expect(find.text('+963'), findsOneWidget);
      await enter('رقم واتساب', '0944123456');
      await enter('البريد الإلكتروني', 'candidate-test@example.test');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await Scrollable.ensureVisible(
        tester.element(find.byType(CheckboxListTile)),
        alignment: .5,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pump();
      await tester.runAsync(() async {
        await tester.tap(find.text('إرسال للمراجعة'));
        for (var i = 0; i < 12; i++) {
          await Future<void>.delayed(Duration.zero);
        }
      });
      await tester.pumpAndSettle();
      expect(posted, isNotNull);
      expect(posted!['country'], 'سوريا');
      expect(posted!['state'], 'دمشق');
      expect(posted!['currency'], 'SYP');
      expect(posted!['phone'], '+963944123456');
      expect(store.submissions.single.job.country, 'سوريا');
      expect(store.submissions.single.status, 'pending');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      store.dispose();
    },
  );

  testWidgets(
    'country and currency lists fit narrow screens at 200 percent text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final currency in [false, true]) {
        await tester.pumpWidget(
          MaterialApp(
            theme: sanadTheme(),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(2)),
              child: child!,
            ),
            home: GeographyPickerPage(
              title: currency ? 'عملة الراتب' : 'البلد',
              selected: '',
              options: [
                if (currency)
                  const GeographyOption('EGP', 'جنيه مصري', 'EGP')
                else
                  const GeographyOption(
                    'AE',
                    'الإمارات العربية المتحدة',
                    'United Arab Emirates · AE',
                  ),
              ],
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byType(TextField),
          currency ? 'EGP' : 'Emirates',
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(find.byType(ListTile), findsOneWidget);
        await tester.pumpWidget(const SizedBox.shrink());
      }
    },
  );

  testWidgets(
    'location changes stay staged and work without the city suggestions endpoint',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
      final store = (await tester.runAsync(
        () => JobsStore.create(
          client: MockClient((request) async {
            if (request.url.path == '/api/job-locations') {
              return http.Response('{}', 404);
            }
            return http.Response(
              '{"data":[]}',
              200,
              headers: {'content-type': 'application/json'},
            );
          }),
        ),
      ))!;
      await tester.runAsync(() async {
        await store.refresh();
        store.updateFilters(const JobFilters(country: 'SY', city: 'دمشق'));
        await store.refresh();
      });
      await tester.pumpWidget(
        MaterialApp(
          theme: sanadTheme(),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => LocationPickerPage(
                      store: store,
                      initial: store.filters,
                      applyToStore: true,
                    ),
                  ),
                ),
                child: const Text('تغيير المكان'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('تغيير المكان'));
      await tester.pumpAndSettle();
      expect(find.byType(TextFormField), findsNothing);
      expect(store.filters.country, 'SY');
      await tester.tap(find.text('دمشق'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'حلب');
      await tester.pump();
      await tester.tap(find.widgetWithText(ListTile, 'حلب'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('عرض الفرص'));
      await tester.pumpAndSettle();
      await tester.runAsync(() => store.refresh());
      expect(store.filters.country, 'SY');
      expect(store.filters.city, 'حلب');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      store.dispose();
    },
  );
}
