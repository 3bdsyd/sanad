import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:google_mobile_ads/src/ad_instance_manager.dart' as sdk;
import 'package:snad/core/design.dart';
import 'package:snad/features/ads/data/ads_controller.dart';
import 'package:snad/features/ads/data/banner_ad_session.dart';
import 'package:snad/features/ads/domain/ad_load_policy.dart';
import 'package:snad/features/ads/presentation/cached_banner_slot.dart';

class Gateway implements AdsGateway {
  bool allowed = true;
  @override
  Future<void> updateConsent() async {}
  @override
  Future<void> showRequiredConsent() async {}
  @override
  Future<bool> canRequestAds() async => allowed;
  @override
  Future<bool> privacyRequired() async => false;
  @override
  Future<void> showPrivacyOptions() async {}
  @override
  Future<void> initialize() async {}
}

void main() {
  final variant = TargetPlatformVariant({TargetPlatform.iOS});
  testWidgets(
    'backgrounding during banner sizing cannot start a network request',
    (tester) async {
      final ads = AdsController(gateway: Gateway(), supported: true);
      await ads.start();
      final session = BannerAdSession(ads: ads, policy: AdLoadPolicy());
      final sizing = Completer<int>();
      final calls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        sdk.instanceManager.channel,
        (call) async {
          calls.add(call);
          return call.method == 'AdSize#getLargeAnchoredAdaptiveBannerAdSize'
              ? sizing.future
              : null;
        },
      );
      final owner = Object();
      session.acquire(
        owner,
        width: 390,
        orientation: Orientation.portrait,
        placement: 'job_details_banner',
      );
      await tester.pump();
      session.didChangeAppLifecycleState(AppLifecycleState.paused);
      sizing.complete(60);
      await tester.pump();
      expect(calls.where((c) => c.method == 'loadBannerAd'), isEmpty);
      session.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await tester.pump();
      expect(calls.where((c) => c.method == 'loadBannerAd'), hasLength(1));
      session.release(owner);
      session.dispose();
      ads.dispose();
      await tester.pump();
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        sdk.instanceManager.channel,
        null,
      );
    },
    variant: variant,
  );
  testWidgets(
    'SDK banner refresh renews TTL; a truly stale visible banner is replaced',
    (tester) async {
      final ads = AdsController(gateway: Gateway(), supported: true);
      await ads.start();
      var now = DateTime(2026);
      final session = BannerAdSession(
        ads: ads,
        now: () => now,
        policy: AdLoadPolicy(now: () => now),
      );
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
      final owner = Object();
      session.acquire(
        owner,
        width: 390,
        orientation: Orientation.portrait,
        placement: 'job_details_banner',
      );
      await tester.pump();
      final ad = session.ad!;
      ad.listener.onAdLoaded!(ad);
      now = now.add(const Duration(minutes: 54));
      await tester.pump(const Duration(minutes: 54));
      ad.listener.onAdLoaded!(ad);
      now = now.add(const Duration(minutes: 1));
      await tester.pump(const Duration(minutes: 1));
      expect(session.ad, same(ad));
      expect(calls.where((c) => c.method == 'loadBannerAd'), hasLength(1));
      now = now.add(const Duration(minutes: 54));
      await tester.pump(const Duration(minutes: 54));
      await tester.pump();
      expect(session.ad, isNot(same(ad)));
      expect(calls.where((c) => c.method == 'loadBannerAd'), hasLength(2));
      session.release(owner);
      session.dispose();
      ads.dispose();
      await tester.pump();
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        sdk.instanceManager.channel,
        null,
      );
    },
    variant: variant,
  );
  testWidgets(
    'banner timeout recovers after foreground resume without background requests',
    (tester) async {
      final ads = AdsController(gateway: Gateway(), supported: true);
      await ads.start();
      var now = DateTime(2026);
      final session = BannerAdSession(
        ads: ads,
        now: () => now,
        policy: AdLoadPolicy(now: () => now),
      );
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
      final owner = Object();
      session.acquire(
        owner,
        width: 390,
        orientation: Orientation.portrait,
        placement: 'job_details_banner',
      );
      await tester.pump();
      final first = session.ad!;
      now = now.add(const Duration(seconds: 45));
      await tester.pump(const Duration(seconds: 45));
      expect(session.ad, isNull);
      session.didChangeAppLifecycleState(AppLifecycleState.paused);
      now = now.add(const Duration(seconds: 31));
      await tester.pump(const Duration(seconds: 31));
      expect(calls.where((c) => c.method == 'loadBannerAd'), hasLength(1));
      session.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await tester.pump();
      expect(calls.where((c) => c.method == 'loadBannerAd'), hasLength(2));
      first.listener.onAdLoaded!(first);
      await tester.pump();
      expect(session.ready, isFalse);
      final current = session.ad!;
      current.listener.onAdLoaded!(current);
      await tester.pump();
      session.didHaveMemoryPressure();
      expect(session.ad, same(current));
      session.release(owner);
      session.didHaveMemoryPressure();
      await tester.pump();
      expect(session.ad, isNull);
      session.dispose();
      ads.dispose();
      await tester.pump();
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        sdk.instanceManager.channel,
        null,
      );
    },
    variant: variant,
  );

  testWidgets(
    'shared no-fill cooldown survives changing screens and never retries while hidden',
    (tester) async {
      final ads = AdsController(gateway: Gateway(), supported: true);
      await ads.start();
      var now = DateTime(2026);
      final policy = AdLoadPolicy(now: () => now);
      final session = BannerAdSession(ads: ads, policy: policy, now: () => now);
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
      final first = Object(), second = Object();
      session.acquire(
        first,
        width: 390,
        orientation: Orientation.portrait,
        placement: 'job_details_banner',
      );
      await tester.pump();
      final ad = session.ad!;
      ad.listener.onAdFailedToLoad!(
        ad,
        LoadAdError(1, 'admob', 'no fill', null),
      );
      await tester.pump();
      session.release(first);
      session.acquire(
        second,
        width: 390,
        orientation: Orientation.portrait,
        placement: 'notifications_banner',
      );
      await tester.pump();
      expect(
        calls.where((call) => call.method == 'loadBannerAd'),
        hasLength(1),
      );
      session.release(second);
      now = now.add(const Duration(seconds: 121));
      await tester.pump(const Duration(seconds: 121));
      expect(
        calls.where((call) => call.method == 'loadBannerAd'),
        hasLength(1),
      );
      session.acquire(
        second,
        width: 390,
        orientation: Orientation.portrait,
        placement: 'job_details_banner',
      );
      await tester.pump();
      expect(
        calls.where((call) => call.method == 'loadBannerAd'),
        hasLength(2),
      );
      session.release(second);
      session.acquire(
        second,
        width: 390,
        orientation: Orientation.portrait,
        placement: 'notifications_banner',
      );
      await tester.pump();
      expect(
        calls.where((call) => call.method == 'loadBannerAd'),
        hasLength(2),
      );
      session.release(second);
      session.dispose();
      await tester.pump();
      ads.dispose();
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        sdk.instanceManager.channel,
        null,
      );
    },
    variant: variant,
  );
  for (final completesWhileHidden in [false, true]) {
    testWidgets(
      'details reuse one banner/request, completesWhileHidden=$completesWhileHidden',
      (tester) async {
        final gateway = Gateway();
        final ads = AdsController(gateway: gateway, supported: true);
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
        final first = Object(), second = Object(), third = Object();
        bool attach(Object owner) => session.acquire(
          owner,
          width: 390,
          orientation: Orientation.portrait,
          placement: 'job_details_banner',
        );
        attach(first);
        await tester.pump();
        final load = calls.singleWhere((call) => call.method == 'loadBannerAd');
        final ad =
            sdk.instanceManager.adFor(load.arguments['adId']) as BannerAd;
        session.release(first);
        if (!completesWhileHidden) attach(second);
        ad.listener.onAdLoaded!(ad);
        await tester.pump();
        if (completesWhileHidden) attach(second);
        expect(session.ready, isTrue);
        expect(session.ad, same(ad));
        session.release(second);
        attach(third);
        await tester.pump();
        expect(
          calls.where((call) => call.method == 'loadBannerAd'),
          hasLength(1),
        );
        expect(calls.where((call) => call.method == 'disposeAd'), isEmpty);
        session.release(third);
        session.dispose();
        await tester.pump();
        expect(calls.where((call) => call.method == 'disposeAd'), hasLength(1));
        ads.dispose();
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          sdk.instanceManager.channel,
          null,
        );
      },
      variant: variant,
    );
  }

  testWidgets(
    'expired or resized banners reload; privacy revocation clears cached ads',
    (tester) async {
      final gateway = Gateway();
      final ads = AdsController(gateway: gateway, supported: true);
      await ads.start();
      var now = DateTime(2026);
      final session = BannerAdSession(
        ads: ads,
        now: () => now,
        policy: AdLoadPolicy(now: () => now),
      );
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
      final owner = Object();
      Future<BannerAd> attach({int width = 390}) async {
        session.acquire(
          owner,
          width: width,
          orientation: Orientation.portrait,
          placement: 'job_details_banner',
        );
        await tester.pump();
        final call = calls.lastWhere((call) => call.method == 'loadBannerAd');
        return sdk.instanceManager.adFor(call.arguments['adId']) as BannerAd;
      }

      final first = await attach();
      first.listener.onAdLoaded!(first);
      session.release(owner);
      now = now.add(const Duration(minutes: 55));
      final second = await attach();
      expect(second, isNot(same(first)));
      expect(
        calls.where((call) => call.method == 'loadBannerAd'),
        hasLength(2),
      );
      second.listener.onAdLoaded!(second);
      session.release(owner);
      final third = await attach(width: 400);
      first.listener.onAdLoaded!(first);
      expect(
        session.ready,
        isFalse,
        reason: 'A stale creative cannot complete the replacement request.',
      );
      third.listener.onAdLoaded!(third);
      await tester.pump();
      expect(session.ready, isTrue);
      expect(session.size!.width, 400);
      session.release(owner);
      gateway.allowed = false;
      await ads.editPrivacy();
      await tester.pump();
      expect(session.ad, isNull);
      expect(session.ready, isFalse);
      expect(calls.where((call) => call.method == 'disposeAd'), hasLength(3));
      session.dispose();
      ads.dispose();
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        sdk.instanceManager.channel,
        null,
      );
    },
    variant: variant,
  );

  testWidgets(
    'unshown inventory is shared; an impressed banner renews for a new job only',
    (tester) async {
      final ads = AdsController(gateway: Gateway(), supported: true);
      await ads.start();
      var now = DateTime(2026);
      final session = BannerAdSession(
        ads: ads,
        policy: AdLoadPolicy(),
        now: () => now,
      );
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
      final owner = Object();
      void attach(String job) => session.acquire(
        owner,
        width: 390,
        orientation: Orientation.portrait,
        placement: 'job_details_banner',
        contextKey: job,
      );
      attach('job-a');
      await tester.pump();
      final first = session.ad!;
      first.listener.onAdLoaded!(first);
      session.release(owner);
      attach('job-b');
      await tester.pump();
      expect(
        session.ad,
        same(first),
        reason: 'An ad that never recorded an impression is still usable.',
      );
      first.listener.onAdImpression!(first);
      first.listener.onAdFailedToLoad!(
        first,
        LoadAdError(1, 'admob', 'SDK refresh no fill', null),
      );
      await tester.pump();
      expect(session.ready, isTrue);
      expect(
        calls.where((call) => call.method == 'disposeAd'),
        isEmpty,
        reason: 'The SDK retains control of its automatic refresh.',
      );
      session.release(owner);
      attach('job-b');
      await tester.pump();
      expect(session.ad, same(first));
      session.release(owner);
      attach('job-c');
      await tester.pump();
      expect(
        session.ad,
        same(first),
        reason: 'Rapid navigation reuses the banner for at least 60 seconds.',
      );
      expect(
        calls.where((call) => call.method == 'loadBannerAd'),
        hasLength(1),
      );
      session.release(owner);
      now = now.add(const Duration(seconds: 60));
      attach('job-d');
      await tester.pump();
      expect(session.ad, isNot(same(first)));
      expect(
        calls.where((call) => call.method == 'loadBannerAd'),
        hasLength(2),
      );
      session.release(owner);
      session.dispose();
      await tester.pump();
      ads.dispose();
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        sdk.instanceManager.channel,
        null,
      );
    },
    variant: variant,
  );

  testWidgets(
    'route handoff never mounts a cached banner twice or reloads for dark mode',
    (tester) async {
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
      Widget page({bool second = false, bool dark = false}) => MaterialApp(
        theme: sanadTheme(
          brightness: dark ? Brightness.dark : Brightness.light,
        ),
        home: Scaffold(
          body: Column(
            children: [
              CachedBannerSlot(
                key: const ValueKey('first'),
                active: !second,
                placement: 'job_details_banner',
                session: session,
              ),
              CachedBannerSlot(
                key: const ValueKey('second'),
                active: second,
                placement: 'job_details_banner',
                session: session,
              ),
            ],
          ),
        ),
      );
      await tester.pumpWidget(page());
      await tester.pump();
      final call = calls.singleWhere((call) => call.method == 'loadBannerAd');
      final ad = sdk.instanceManager.adFor(call.arguments['adId']) as BannerAd;
      await tester.pump();
      final reservedSize = tester.getSize(find.byType(CachedBannerSlot).first);
      expect(reservedSize.height, 100);
      expect(find.byType(AdWidget), findsNothing);
      ad.listener.onAdLoaded!(ad);
      await tester.pumpAndSettle();
      expect(ad.isMounted, isTrue);
      expect(find.byType(AdWidget), findsOneWidget);
      expect(
        tester.getSize(find.byType(CachedBannerSlot).first),
        reservedSize,
        reason: 'Loading the creative must not move the surrounding content.',
      );
      await tester.pumpWidget(page(second: true, dark: true));
      await tester.pumpAndSettle();
      expect(find.byType(AdWidget), findsOneWidget);
      expect(ad.isMounted, isTrue);
      expect(
        calls.where((call) => call.method == 'loadBannerAd'),
        hasLength(1),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(ad.isMounted, isFalse);
      session.dispose();
      await tester.pump();
      ads.dispose();
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        sdk.instanceManager.channel,
        null,
      );
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform_views,
        null,
      );
    },
    variant: variant,
  );
}
