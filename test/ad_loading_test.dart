import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:google_mobile_ads/src/ad_instance_manager.dart' as sdk;
import 'package:snad/core/design.dart';
import 'package:snad/features/ads/data/ads_controller.dart';
import 'package:snad/features/ads/data/native_ad_session.dart';
import 'package:snad/features/ads/domain/ad_load_policy.dart';
import 'package:snad/features/ads/presentation/ad_slot.dart';

class _Gateway implements AdsGateway {
  @override
  Future<void> updateConsent() async {}
  @override
  Future<void> showRequiredConsent() async {}
  @override
  Future<bool> canRequestAds() async => true;
  @override
  Future<bool> privacyRequired() async => false;
  @override
  Future<void> showPrivacyOptions() async {}
  @override
  Future<void> initialize() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'iOS no-fill and adapter errors retry instead of silencing the session',
    () {
      final p = AdLoadPolicy(now: () => DateTime(2026));
      p.failedSdk(p.begin('mediation', native: true)!, ios: true, code: 1);
      expect(
        p.waitFor('mediation', native: true),
        const Duration(seconds: 120),
      );
      p.failedSdk(p.begin('adapter', native: true)!, ios: true, code: 8);
      expect(p.waitFor('adapter', native: true), const Duration(seconds: 30));
    },
  );
  test(
    'native loads are bounded; stale callbacks cannot release other loads',
    () {
      final p = AdLoadPolicy();
      final a = p.begin('a', native: true)!;
      final b = p.begin('b', native: true)!;
      expect(p.begin('a', native: true), isNull);
      expect(p.begin('c', native: true), isNull);
      p.succeeded(a);
      p.begin('c', native: true);
      p.succeeded(a);
      expect(p.begin('d', native: true), isNull);
      p.succeeded(b);
      expect(p.begin('d', native: true), isNotNull);
    },
  );
  test('cooldown and retry limit survive a row being recreated', () {
    var now = DateTime(2026);
    final p = AdLoadPolicy(now: () => now);
    for (var i = 0; i < 4; i++) {
      p.failed(p.begin('slot', native: true)!);
      expect(p.begin('slot', native: true), isNull);
      if (i < 3) now = now.add(p.waitFor('slot', native: true)!);
    }
    expect(p.waitFor('slot', native: true), const Duration(minutes: 5));
    now = now.add(const Duration(minutes: 5));
    expect(p.begin('slot', native: true), isNotNull);
  });
  test('cancelling a request cannot immediately start another', () {
    var now = DateTime(2026);
    final p = AdLoadPolicy(now: () => now);
    p.abandoned(p.begin('slot', native: true)!);
    expect(p.begin('slot', native: true), isNull);
    now = now.add(const Duration(seconds: 15));
    expect(p.begin('slot', native: true), isNotNull);
  });
  test('no-fill waits two minutes; permanent errors stop retrying', () {
    final p = AdLoadPolicy(now: () => DateTime(2026));
    p.failed(p.begin('empty', native: true)!, noFill: true);
    expect(p.waitFor('empty', native: true), const Duration(minutes: 2));
    p.failed(p.begin('invalid', native: false)!, permanent: true);
    expect(p.waitFor('invalid', native: false), isNull);
  });

  testWidgets(
    'scrolling away from a loading native ad does not cancel or duplicate its request',
    (tester) async {
      final ads = AdsController(gateway: _Gateway(), supported: true);
      await ads.start();
      final p = AdLoadPolicy();
      final session = NativeAdSession(ads: ads, policy: p);
      final calls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        sdk.instanceManager.channel,
        (call) async {
          calls.add(call);
          return null;
        },
      );
      final scroll = ScrollController();
      await tester.pumpWidget(
        MaterialApp(
          theme: sanadTheme(),
          home: Scaffold(
            body: CustomScrollView(
              controller: scroll,
              scrollCacheExtent: const ScrollCacheExtent.pixels(0),
              slivers: [
                SliverList.builder(
                  itemCount: 40,
                  itemBuilder: (context, i) => i == 0
                      ? SanadAdSlot(
                          key: const ValueKey('loading'),
                          native: true,
                          active: true,
                          placement: 'loading',
                          nativeSession: session,
                        )
                      : const SizedBox(height: 200),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();
      expect(calls.where((c) => c.method == 'loadNativeAd').length, 1);
      scroll.jumpTo(2000);
      await tester.pump();
      expect(calls.where((c) => c.method == 'disposeAd'), isEmpty);
      scroll.jumpTo(0);
      await tester.pump();
      await tester.pump();
      expect(calls.where((c) => c.method == 'loadNativeAd').length, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      scroll.dispose();
      session.dispose();
      await tester.pump();
      ads.dispose();
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        sdk.instanceManager.channel,
        null,
      );
    },
  );

  for (final (code, seconds) in [(5, 30), (1, 120)]) {
    testWidgets(
      'iOS error $code keeps its cooldown after a native slot is rebuilt',
      (tester) async {
        final ads = AdsController(gateway: _Gateway(), supported: true);
        await ads.start();
        var now = DateTime(2026);
        final p = AdLoadPolicy(now: () => now);
        final session = NativeAdSession(ads: ads, policy: p);
        final calls = <MethodCall>[];
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          sdk.instanceManager.channel,
          (call) async {
            calls.add(call);
            return null;
          },
        );
        Widget page() => MaterialApp(
          theme: sanadTheme(),
          home: Scaffold(
            body: SanadAdSlot(
              native: true,
              active: true,
              placement: 'timeout',
              nativeSession: session,
            ),
          ),
        );
        await tester.pumpWidget(page());
        await tester.pump();
        final call = calls.singleWhere((c) => c.method == 'loadNativeAd');
        final ad =
            sdk.instanceManager.adFor(call.arguments['adId']) as NativeAd;
        ad.listener.onAdFailedToLoad!(
          ad,
          LoadAdError(code, 'com.google.admob', 'SDK load failure', null),
        );
        await tester.pump();
        expect(p.waitFor('timeout', native: true), Duration(seconds: seconds));
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpWidget(page());
        await tester.pump();
        expect(calls.where((c) => c.method == 'loadNativeAd').length, 1);
        now = now.add(Duration(seconds: seconds + 1));
        await tester.pump(Duration(seconds: seconds + 1));
        expect(calls.where((c) => c.method == 'loadNativeAd').length, 2);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        session.dispose();
        await tester.pump();
        ads.dispose();
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          sdk.instanceManager.channel,
          null,
        );
      },
      variant: TargetPlatformVariant({TargetPlatform.iOS}),
    );
  }
}
