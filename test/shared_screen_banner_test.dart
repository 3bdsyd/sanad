import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:google_mobile_ads/src/ad_instance_manager.dart' as sdk;
import 'package:snad/core/design.dart';
import 'package:snad/features/ads/data/ads_controller.dart';
import 'package:snad/features/ads/data/banner_ad_session.dart';
import 'package:snad/features/ads/domain/ad_load_policy.dart';
import 'package:snad/features/jobs/data/jobs_store.dart';
import 'package:snad/features/jobs/presentation/job_details.dart';
import 'package:snad/features/jobs/presentation/notifications.dart';
import 'package:snad/features/jobs/presentation/home.dart';
import 'banner_session_test.dart' show Gateway;
import 'release_experience_test.dart' show createStore, app;

Future<void> bannerCase(
  WidgetTester tester,
  Future<void> Function(
    JobsStore store,
    BannerAdSession session,
    List<MethodCall> calls,
  )
  body,
) async {
  SharedPreferences.setMockInitialValues({});
  FlutterSecureStorage.setMockInitialValues({});
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  final ads = AdsController(gateway: Gateway(), supported: true);
  await ads.start();
  final session = BannerAdSession(ads: ads, policy: AdLoadPolicy());
  final calls = <MethodCall>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    sdk.instanceManager.channel,
    (c) async {
      calls.add(c);
      return c.method == 'AdSize#getLargeAnchoredAdaptiveBannerAdSize'
          ? 60
          : null;
    },
  );
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform_views,
    (c) async => null,
  );
  final store = await createStore(tester);
  try {
    await body(store, session, calls);
  } finally {
    await tester.pumpWidget(const SizedBox.shrink());
    session.dispose();
    ads.dispose();
    store.dispose();
    await tester.pump();
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      sdk.instanceManager.channel,
      null,
    );
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform_views,
      null,
    );
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  }
}

void main() {
  testWidgets(
    'real details and notifications share a single banner through covered routes',
    (tester) async {
      await bannerCase(tester, (store, session, calls) async {
        await tester.pumpWidget(
          app(
            JobDetails(
              store: store,
              job: store.jobs.first,
              bannerSession: session,
            ),
          ),
        );
        await tester.pumpAndSettle();
        final ad = session.ad!;
        ad.listener.onAdLoaded!(ad);
        ad.listener.onAdImpression!(ad);
        await tester.pumpAndSettle();
        expect(
          tester.getCenter(find.text('تفاصيل الفرصة')).dx,
          closeTo(195, .5),
        );
        final contact = find.ancestor(
          of: find.text('التواصل عبر واتساب'),
          matching: find.byType(SanadPrimaryButton),
        );
        expect(844 - tester.getRect(contact).bottom, lessThanOrEqualTo(4));
        await tester.drag(find.byType(CustomScrollView), const Offset(0, -350));
        await tester.pumpAndSettle();
        await tester.drag(find.byType(CustomScrollView), const Offset(0, 55));
        await tester.pumpAndSettle();
        final compactTitle = find.descendant(
          of: find.byType(AppBar),
          matching: find.text(store.jobs.first.title),
        );
        expect(tester.getCenter(compactTitle).dx, closeTo(195, .5));
        final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
        unawaited(
          nav.push(
            MaterialPageRoute<void>(
              builder: (_) => NotificationsPage(
                store: store,
                initialSection: 1,
                onJob: (_) {},
                bannerSession: session,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(calls.where((c) => c.method == 'loadBannerAd'), hasLength(1));
        expect(find.byType(AdWidget), findsOneWidget);
        expect(tester.widget<AdWidget>(find.byType(AdWidget)).ad, same(ad));
        unawaited(
          nav.push(
            MaterialPageRoute<void>(
              builder: (_) => JobDetails(
                store: store,
                job: store.jobs[1],
                bannerSession: session,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(calls.where((c) => c.method == 'loadBannerAd'), hasLength(1));
        expect(find.byType(AdWidget), findsOneWidget);
        nav.pop();
        await tester.pumpAndSettle();
        nav.pop();
        await tester.pumpAndSettle();
        expect(tester.widget<AdWidget>(find.byType(AdWidget)).ad, same(ad));
        expect(calls.where((c) => c.method == 'loadBannerAd'), hasLength(1));
        expect(tester.takeException(), isNull);
      });
    },
    variant: TargetPlatformVariant({TargetPlatform.iOS}),
  );

  testWidgets(
    'empty notification section makes no request; switching to populated content claims the shared banner',
    (tester) async {
      await bannerCase(tester, (store, session, calls) async {
        await tester.pumpWidget(
          app(
            NotificationsPage(
              store: store,
              onJob: (_) {},
              bannerSession: session,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(calls.where((c) => c.method == 'loadBannerAd'), isEmpty);
        await tester.tap(find.textContaining('إعلاناتي').first);
        await tester.pumpAndSettle();
        expect(calls.where((c) => c.method == 'loadBannerAd'), hasLength(1));
        final ad = session.ad!;
        ad.listener.onAdLoaded!(ad);
        await tester.pumpAndSettle();
        await tester.tap(find.text('الفرص المطابقة'));
        await tester.pumpAndSettle();
        expect(find.byType(AdWidget), findsNothing);
        await tester.tap(find.textContaining('إعلاناتي').first);
        await tester.pumpAndSettle();
        expect(calls.where((c) => c.method == 'loadBannerAd'), hasLength(1));
        expect(tester.widget<AdWidget>(find.byType(AdWidget)).ad, same(ad));
        expect(tester.takeException(), isNull);
      });
    },
    variant: TargetPlatformVariant({TargetPlatform.iOS}),
  );

  for (final scale in [1.0, 2.0]) {
    testWidgets(
      'publisher has a compact add action and no refresh/card at scale $scale',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        FlutterSecureStorage.setMockInitialValues({});
        debugDefaultTargetPlatformOverride = TargetPlatform.linux;
        tester.view.physicalSize = Size(scale == 1 ? 390 : 320, 844);
        tester.view.devicePixelRatio = 1;
        final store = await createStore(tester);
        try {
          await tester.pumpWidget(app(JobsHome(store: store), scale: scale));
          await tester.pumpAndSettle();
          await tester.tap(find.text('إعلاناتك').last);
          await tester.pumpAndSettle();
          expect(find.text('إدخال بيانات فرصة العمل'), findsNothing);
          expect(find.text('تحديث'), findsNothing);
          expect(find.byTooltip('تحديث إعلاناتي'), findsNothing);
          final action = find.widgetWithText(
            SanadPrimaryButton,
            'أضف فرصة عمل',
          );
          expect(action.hitTestable(), findsOneWidget);
          expect(find.text('إعلاناتك').first, findsOneWidget);
          if (scale == 1) {
            expect(
              tester.getCenter(find.text('إعلاناتك').first).dy,
              closeTo(tester.getCenter(action).dy, 2),
            );
            expect(
              tester.getRect(action).right,
              lessThan(tester.getRect(find.text('إعلاناتك').first).left),
            );
          }
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          store.dispose();
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );
  }
}
