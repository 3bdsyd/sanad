import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:snad/core/design.dart';
import 'package:snad/features/jobs/presentation/home.dart';
import 'package:snad/features/platform/domain/platform_models.dart';
import 'package:snad/features/platform/presentation/auth_page.dart';
import 'package:snad/features/platform/presentation/account_page.dart';
import 'package:snad/features/platform/presentation/applications_page.dart';
import 'package:snad/features/platform/presentation/chat_page.dart';
import 'package:snad/features/platform/presentation/complaints_page.dart';
import 'package:snad/features/platform/presentation/publisher_panel.dart';
import 'package:snad/features/platform/presentation/platform_ui.dart';
import 'package:snad/features/platform/presentation/web_download_gate.dart';
import 'package:snad/features/jobs/domain/job.dart';
import 'platform_fixture.dart';
import 'release_experience_test.dart' show app;

Finder listScrollable() => find
    .descendant(
      of: find.byType(ListView).last,
      matching: find.byType(Scrollable),
    )
    .first;

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 3; i++) {
    await tester.pump();
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 40));
    });
    await tester.pumpAndSettle();
  }
}

void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);
  void size(WidgetTester tester, {bool narrow = false}) {
    tester.view.physicalSize = Size(narrow ? 320 : 390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  testWidgets('empty publisher explains the process and offers posting', (
    tester,
  ) async {
    size(tester);
    final store = await platformFixture(tester, empty: true);
    await tester.pumpWidget(app(Scaffold(body: PublisherPanel(store: store))));
    await settle(tester);
    expect(find.text('فرصتك الأولى تبدأ هنا'), findsOneWidget);
    expect(find.text('أضف فرصة عمل'), findsOneWidget);
    expect(find.text('مراجعة ثم نشر'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
    debugDefaultTargetPlatformOverride = null;
  });
  testWidgets('owner card contains description and location before opening', (
    tester,
  ) async {
    size(tester);
    final store = await platformFixture(tester);
    await tester.pumpWidget(app(Scaffold(body: PublisherPanel(store: store))));
    await settle(tester);
    expect(
      find.textContaining(
        Job.fromApi(object(platformFixtures['own_job'])).description,
      ),
      findsOneWidget,
    );
    expect(find.text('تفاصيل الإعلان'), findsOneWidget);
    expect(find.text('قيد المراجعة'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
    debugDefaultTargetPlatformOverride = null;
  });
  testWidgets('protected heart opens auth and resumes exact save after OTP', (
    tester,
  ) async {
    size(tester);
    final requests = <http.Request>[];
    final store = await platformFixture(
      tester,
      guest: true,
      requests: requests,
    );
    await tester.pumpWidget(app(JobsHome(store: store)));
    await settle(tester);
    await tester.tap(find.byTooltip('حفظ الفرصة').first);
    await settle(tester);
    expect(find.byType(AuthPage), findsOneWidget);
    expect(
      requests.where(
        (r) => r.method == 'PUT' && r.url.path.contains('/favorites/'),
      ),
      isEmpty,
    );
    await tester.enterText(
      find.byType(TextFormField),
      'candidate@example.test',
    );
    await tester.scrollUntilVisible(
      find.byType(CheckboxListTile),
      250,
      scrollable: listScrollable(),
    );
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pump();
    await tester.ensureVisible(find.text('إرسال رمز التحقق'));
    await tester.tap(find.text('إرسال رمز التحقق'));
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await settle(tester);
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), '123456');

    await tester.ensureVisible(find.text('الدخول إلى سند'));
    await tester.tap(find.text('الدخول إلى سند'));
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await settle(tester);
    expect(store.platform.signedIn, isTrue);
    expect(
      requests
          .where(
            (r) =>
                r.method == 'PUT' && r.url.path.endsWith('/favorites/970001'),
          )
          .length,
      1,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
    debugDefaultTargetPlatformOverride = null;
  });
  testWidgets('application confirms server success and exposes follow up', (
    tester,
  ) async {
    size(tester);
    final requests = <http.Request>[];
    final store = await platformFixture(tester, requests: requests);
    await tester.pumpWidget(
      app(
        ApplyPage(
          store: store,
          job: Job.fromApi(object(platformFixtures['job'])),
        ),
      ),
    );
    await settle(tester);
    await tester.scrollUntilVisible(
      find.byType(CheckboxListTile),
      250,
      scrollable: listScrollable(),
    );
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pump();
    await tester.ensureVisible(find.text('إرسال الطلب'));
    await tester.tap(find.text('إرسال الطلب'));
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 60));
    });
    await settle(tester);
    expect(find.text('تم إرسال طلبك'), findsOneWidget);
    expect(find.text('متابعة طلباتي'), findsOneWidget);
    expect(
      requests
          .where(
            (r) => r.method == 'POST' && r.url.path.endsWith('/applications'),
          )
          .length,
      1,
    );
    await tester.pumpWidget(const SizedBox());
    store.dispose();
    debugDefaultTargetPlatformOverride = null;
  });
  testWidgets('only a new email account asks for its name after proving OTP', (
    tester,
  ) async {
    size(tester);
    final store = await platformFixture(tester, guest: true, newAccount: true);
    await tester.pumpWidget(
      app(
        Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => ensureAccount(context, store.platform),
              child: const Text('دخول الاختبار'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('دخول الاختبار'));
    await settle(tester);
    await tester.enterText(find.byType(TextFormField), 'new@example.test');
    await tester.scrollUntilVisible(
      find.byType(CheckboxListTile),
      250,
      scrollable: listScrollable(),
    );
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pump();
    await tester.ensureVisible(find.text('إرسال رمز التحقق'));
    await tester.tap(find.text('إرسال رمز التحقق'));
    await settle(tester);
    expect(find.byType(TextField), findsOneWidget);
    await tester.enterText(find.byType(TextField), '123456');
    await tester.ensureVisible(find.text('الدخول إلى سند'));
    await tester.tap(find.text('الدخول إلى سند'));
    await settle(tester);
    expect(store.platform.signedIn, isFalse);
    expect(find.byType(TextField), findsNWidgets(2));
    await tester.enterText(find.byType(TextField).at(1), 'مستخدم جديد');
    await tester.ensureVisible(find.text('الدخول إلى سند'));
    await tester.tap(find.text('الدخول إلى سند'));
    await settle(tester);
    expect(store.platform.signedIn, isTrue);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
    debugDefaultTargetPlatformOverride = null;
  });
  for (final screen in [
    'auth',
    'account',
    'applications',
    'chat',
    'complaint',
    'publisher',
    'profile',
    'preferences',
  ]) {
    testWidgets('$screen supports 320px, 200% text and Reduce Motion', (
      tester,
    ) async {
      size(tester, narrow: true);
      final store = await platformFixture(tester, empty: screen == 'publisher');
      final page = switch (screen) {
        'auth' => AuthPage(store: store.platform),
        'account' => AccountPage(store: store),
        'applications' => ApplicationsPage(store: store),
        'chat' => ChatPage(
          store: store.platform,
          conversation: Conversation(object(platformFixtures['conversation'])),
        ),
        'complaint' => ComplaintPage(store: store.platform),
        'publisher' => PlatformScaffold(
          title: 'إعلاناتك',
          child: PublisherPanel(store: store),
        ),
        'profile' => ProfilePage(store: store.platform),
        _ => NotificationPreferencesPage(store: store.platform),
      };
      await tester.pumpWidget(app(page, scale: 2));
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 30));
      });
      await settle(tester);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      store.dispose();
      debugDefaultTargetPlatformOverride = null;
    });
  }
  testWidgets('dark outgoing chat text maintains readable contrast', (
    tester,
  ) async {
    size(tester);
    final store = await platformFixture(tester);
    final theme = sanadTheme(brightness: Brightness.dark);
    await tester.pumpWidget(
      app(
        Theme(
          data: theme,
          child: ChatPage(
            store: store.platform,
            conversation: Conversation(
              object(platformFixtures['conversation']),
            ),
          ),
        ),
      ),
    );
    await settle(tester);
    final text = tester.widget<SelectableText>(
      find.byType(SelectableText).first,
    );
    final foreground = text.style!.color!.computeLuminance();
    final background = theme.colorScheme.primary.computeLuminance();
    final ratio =
        (foreground > background ? foreground + .05 : background + .05) /
        (foreground > background ? background + .05 : foreground + .05);
    expect(ratio, greaterThanOrEqualTo(4.5));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
    debugDefaultTargetPlatformOverride = null;
  });
  testWidgets('download cover closes and preserves the underlying screen', (
    tester,
  ) async {
    size(tester, narrow: true);
    await tester.pumpWidget(
      app(
        const WebDownloadGate(child: Scaffold(body: Text('الفرصة المطلوبة'))),
        scale: 2,
      ),
    );
    await settle(tester);
    expect(find.text('قريباً على App Store'), findsOneWidget);
    await tester.tap(find.byTooltip('متابعة التصفح'));
    await settle(tester);
    expect(find.text('قريباً على App Store'), findsNothing);
    expect(find.text('الفرصة المطلوبة'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'application filters reach server and reset without local truncation',
    (tester) async {
      size(tester);
      final requests = <http.Request>[];
      final store = await platformFixture(tester, requests: requests);
      await tester.pumpWidget(app(ApplicationsPage(store: store)));
      await settle(tester);
      await tester.enterText(find.byType(TextField), 'Flutter');
      await tester.tap(find.byTooltip('بحث في الطلبات'));
      await settle(tester);
      expect(
        requests
            .lastWhere((r) => r.url.path == '/api/v2/me/applications')
            .url
            .queryParameters['q'],
        'Flutter',
      );
      await tester.tap(find.text('تصفية الطلبات'));
      await settle(tester);
      await tester.scrollUntilVisible(
        find.widgetWithText(ChoiceChip, 'قيد الدراسة'),
        150,
        scrollable: listScrollable(),
      );
      await tester.tap(find.widgetWithText(ChoiceChip, 'قيد الدراسة'));
      await settle(tester);
      final query = requests
          .lastWhere((r) => r.url.path == '/api/v2/me/applications')
          .url
          .queryParameters;
      expect(query, {'q': 'Flutter', 'status': 'under_review'});
      await tester.scrollUntilVisible(
        find.text('إعادة ضبط'),
        -200,
        scrollable: listScrollable(),
      );
      await tester.tap(find.text('إعادة ضبط'));
      await settle(tester);
      expect(
        requests
            .lastWhere((r) => r.url.path == '/api/v2/me/applications')
            .url
            .queryParameters,
        isEmpty,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      store.dispose();
      debugDefaultTargetPlatformOverride = null;
    },
  );
}
