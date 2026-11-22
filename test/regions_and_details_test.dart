import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:google_mobile_ads/src/ad_instance_manager.dart' as sdk;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:snad/features/ads/data/ads_controller.dart';
import 'package:snad/features/ads/data/banner_ad_session.dart';
import 'package:snad/features/ads/domain/ad_load_policy.dart';
import 'package:snad/features/jobs/domain/job_geography.dart';
import 'package:snad/features/jobs/domain/job_regions.dart';
import 'package:snad/features/jobs/presentation/job_details.dart';
import 'package:snad/features/jobs/presentation/filter_sheet.dart';
import 'package:snad/features/jobs/presentation/home.dart';
import 'package:snad/features/jobs/domain/job.dart';
import 'banner_session_test.dart' show Gateway;
import 'release_experience_test.dart' show createStore, app;

void main() {
  testWidgets('details dock can collapse with Reduce Motion on a tall phone', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = await createStore(tester);
    await tester.pumpWidget(
      app(JobDetails(store: store, job: store.jobs.first)),
    );
    await tester.pumpAndSettle();
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -350));
    await tester.pumpAndSettle();
    expect(find.text('التواصل عبر واتساب').hitTestable(), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.drag(find.byType(CustomScrollView), const Offset(0, 55));
    await tester.pumpAndSettle();
    expect(find.text('التواصل عبر واتساب').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    store.dispose();
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets(
    'category opens a searchable page and toolbar actions have bottom space',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      final store = await createStore(tester);
      await tester.pumpWidget(app(FilterSheet(store: store)));
      await tester.pumpAndSettle();
      final bar = tester.getRect(find.byType(AppBar));
      final reset = tester.getRect(
        find.widgetWithText(TextButton, 'إعادة ضبط'),
      );
      expect(bar.bottom - reset.bottom, greaterThanOrEqualTo(9.9));
      expect(reset.height, greaterThanOrEqualTo(44));
      final category = find.widgetWithText(ListTile, 'المجال');
      await tester.ensureVisible(category);
      await tester.pumpAndSettle();
      await tester.tap(category);
      await tester.pumpAndSettle();
      final name = store.categoryOptions.first;
      await tester.enterText(find.byType(TextField), name);
      await tester.pump();
      expect(find.widgetWithText(ListTile, name), findsOneWidget);
      await tester.tap(find.widgetWithText(ListTile, name));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(ListTile, name), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      store.dispose();
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets('long press offers sharing without starting a save drag', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    final store = await createStore(tester);
    await tester.pumpWidget(app(JobsHome(store: store)));
    await tester.pumpAndSettle();
    final title = find.text(store.jobs.first.title).first;
    await tester.ensureVisible(title);
    await tester.pumpAndSettle();
    final gesture = await tester.startGesture(tester.getCenter(title));
    await tester.pump(const Duration(milliseconds: 650));
    await tester.pumpAndSettle();
    expect(find.text('مشاركة الفرصة'), findsOneWidget);
    expect(find.byType(LongPressDraggable<Job>), findsNothing);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    store.dispose();
    debugDefaultTargetPlatformOverride = null;
  });

  test('every selectable country has offline regions with scoped aliases', () {
    for (final country in availableJobCountries) {
      final regions = regionsFor(country.code);
      expect(regions, isNotEmpty, reason: country.code);
      expect(regions.map((r) => r.code).toSet().length, regions.length);
    }
    expect(regionsFor('SY'), hasLength(14));
    expect(regionsFor('AE'), hasLength(7));
    expect(regionsFor('DE'), hasLength(16));
    expect(canonicalRegion('DE', 'Berlin'), 'برلين');
    expect(canonicalRegion('SY', 'Berlin'), isNull);
    expect(canonicalRegion('AE', 'مدينة غير معروفة'), isNull);
  });

  testWidgets(
    'details chrome reverses without remounting or requesting the banner',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
      // Initialize the unrelated global native controller without UMP timers.
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      AdsController.instance;
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final store = await createStore(tester);
      final ads = AdsController(gateway: Gateway(), supported: true);
      await ads.start();
      final session = BannerAdSession(ads: ads, policy: AdLoadPolicy());
      final calls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        sdk.instanceManager.channel,
        (call) async {
          calls.add(call);
          return call.method == 'AdSize#getLargeAnchoredAdaptiveBannerAdSize'
              ? 60
              : null;
        },
      );
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform_views,
        (call) async => null,
      );
      await tester.pumpWidget(
        app(
          JobDetails(
            job: store.jobs.first,
            store: store,
            bannerSession: session,
          ),
          reduce: false,
        ),
      );
      await tester.pump();
      final load = calls.singleWhere((c) => c.method == 'loadBannerAd');
      final ad = sdk.instanceManager.adFor(load.arguments['adId']) as BannerAd;
      ad.listener.onAdLoaded!(ad);
      await tester.pumpAndSettle();
      final original = tester.widget<AdWidget>(find.byType(AdWidget)).ad;
      final scroller = find.byType(CustomScrollView);
      await tester.drag(scroller, const Offset(0, -350));
      await tester.pumpAndSettle();
      final hidden = find.ancestor(
        of: find.byType(AppBar),
        matching: find.byType(AnimatedOpacity),
      );
      expect(tester.widget<AnimatedOpacity>(hidden).opacity, 0);
      expect(find.text('التواصل عبر واتساب').hitTestable(), findsNothing);
      expect(tester.widget<AdWidget>(find.byType(AdWidget)).ad, same(original));
      await tester.drag(scroller, const Offset(0, 55));
      await tester.pumpAndSettle();
      expect(tester.widget<AnimatedOpacity>(hidden).opacity, 1);
      expect(find.text('التواصل عبر واتساب').hitTestable(), findsOneWidget);
      store.notifyListeners();
      await tester.pumpAndSettle();
      expect(calls.where((c) => c.method == 'loadBannerAd'), hasLength(1));
      expect(tester.widget<AdWidget>(find.byType(AdWidget)).ad, same(original));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      session.dispose();
      ads.dispose();
      store.dispose();
      await tester.pump();
      debugDefaultTargetPlatformOverride = null;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        sdk.instanceManager.channel,
        null,
      );
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform_views,
        null,
      );
    },
  );
}
