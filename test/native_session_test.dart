import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:google_mobile_ads/src/ad_instance_manager.dart' as sdk;
import 'package:snad/core/design.dart';
import 'package:snad/features/ads/data/ads_controller.dart';
import 'package:snad/features/ads/data/native_ad_session.dart';
import 'package:snad/features/ads/domain/ad_load_policy.dart';
import 'package:snad/features/ads/presentation/ad_slot.dart';
import 'package:snad/features/ads/presentation/cached_native_slot.dart';
import 'banner_session_test.dart' show Gateway;
import 'release_experience_test.dart' show createStore, app;
import 'package:snad/features/jobs/presentation/home.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

const light = NativeAdSpec(width: 350, colors: SanadColors.light);

class Harness {
  Harness(this.tester);
  final WidgetTester tester;
  final gateway = Gateway();
  late AdsController ads;
  late NativeAdSession pool;
  var now = DateTime(2026);
  final calls = <MethodCall>[];
  int get requests => calls.where((c) => c.method == 'loadNativeAd').length;
  NativeAd get lastAd {
    final c = calls.lastWhere((c) => c.method == 'loadNativeAd');
    return sdk.instanceManager.adFor(c.arguments['adId']) as NativeAd;
  }

  Future<void> start({int capacity = 3}) async {
    ads = AdsController(gateway: gateway, supported: true);
    await ads.start();
    pool = NativeAdSession(
      ads: ads,
      policy: AdLoadPolicy(now: () => now),
      now: () => now,
      capacity: capacity,
    );
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      sdk.instanceManager.channel,
      (c) async {
        calls.add(c);
        return null;
      },
    );
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform_views,
      (c) async => null,
    );
    addTearDown(close);
  }

  bool closed = false;
  Future<void> close() async {
    if (closed) return;
    closed = true;
    await tester.pumpWidget(const SizedBox.shrink());
    pool.dispose();
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
  }
}

void main() {
  testWidgets('evicting a shown native retains its quick-return cooldown', (
    tester,
  ) async {
    final h = Harness(tester);
    await h.start(capacity: 1);
    final owner = Object();
    h.pool.acquire(owner, 'one', light);
    await tester.pump();
    final ad = h.lastAd;
    ad.listener.onAdLoaded!(ad);
    ad.listener.onAdImpression!(ad);
    h.pool.release(owner);
    h.pool.prefetch('two', light);
    await tester.pump();
    h.lastAd.listener.onAdLoaded!(h.lastAd);
    h.now = h.now.add(const Duration(seconds: 5));
    h.pool.acquire(owner, 'one', light);
    await tester.pump();
    expect(
      h.requests,
      2,
      reason:
          'Dropping an SDK object cannot bypass the 60-second revisit rule.',
    );
    h.now = h.now.add(const Duration(seconds: 55));
    await tester.pump(const Duration(seconds: 55));
    expect(h.requests, 3);
    await h.close();
  });

  testWidgets(
    'actual home prefetches the approaching ad before creating its display row',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final h = Harness(tester);
      await h.start();
      final store = await createStore(tester);
      await tester.pumpWidget(app(JobsHome(store: store, nativeAds: h.pool)));
      await tester.pumpAndSettle();
      for (var i = 0; i < 25 && h.requests == 0; i++) {
        await tester.drag(
          find.byType(CustomScrollView).first,
          const Offset(0, -120),
        );
        await tester.pumpAndSettle();
      }
      expect(h.requests, 1);
      expect(
        find.byType(CachedNativeSlot),
        findsNothing,
        reason:
            'Warmup precedes the ad slot rather than starting on its rebuild.',
      );
      final ad = h.lastAd;
      ad.listener.onAdLoaded!(ad);
      await tester.pump();
      for (var i = 0; i < 25 && find.byType(AdWidget).evaluate().isEmpty; i++) {
        await tester.drag(
          find.byType(CustomScrollView).first,
          const Offset(0, -120),
        );
        await tester.pumpAndSettle();
      }
      expect(find.byType(AdWidget), findsOneWidget);
      expect(h.requests, 1);
      expect(tester.widget<AdWidget>(find.byType(AdWidget)).ad, same(ad));
      expect(tester.takeException(), isNull);
      await h.close();
      store.dispose();
    },
    variant: TargetPlatformVariant({TargetPlatform.iOS}),
  );
  testWidgets(
    'shown natives refresh on a later visit, never on rebuild or quick return',
    (tester) async {
      final h = Harness(tester);
      await h.start();
      final owner = Object();
      h.pool.acquire(owner, 'feed', light);
      await tester.pump();
      final ad = h.lastAd;
      ad.listener.onAdLoaded!(ad);
      ad.listener.onAdImpression!(ad);
      h.now = h.now.add(const Duration(seconds: 15));
      h.pool.release(owner);
      h.pool.acquire(owner, 'feed', light);
      await tester.pump();
      expect(h.requests, 1);
      expect(h.pool.forOwner(owner)!.ad, same(ad));
      h.now = h.now.add(const Duration(seconds: 50));
      h.pool.acquire(owner, 'feed', light);
      await tester.pump();
      expect(
        h.requests,
        1,
        reason: 'An owned on-screen ad is not refreshed by rebuilds.',
      );
      h.pool.release(owner);
      h.pool.prefetch('feed', light);
      await tester.pump();
      expect(h.requests, 2);
      expect(h.lastAd, isNot(same(ad)));
      await h.close();
    },
  );

  testWidgets(
    'a missing native SDK callback times out once and frees loading capacity',
    (tester) async {
      final h = Harness(tester);
      await h.start();
      final owner = Object();
      h.pool.acquire(owner, 'feed', light);
      await tester.pump();
      final stale = h.lastAd;
      h.now = h.now.add(const Duration(seconds: 45));
      await tester.pump(const Duration(seconds: 45));
      expect(h.requests, 1);
      expect(h.pool.forOwner(owner)!.loading, isFalse);
      h.now = h.now.add(const Duration(seconds: 30));
      await tester.pump(const Duration(seconds: 30));
      expect(h.requests, 2);
      stale.listener.onAdLoaded!(stale);
      await tester.pump();
      expect(h.pool.forOwner(owner)!.loaded, isFalse);
      h.pool.release(owner);
      await h.close();
    },
  );

  testWidgets(
    'prefetch, row eviction and revisits share one pending and loaded native ad',
    (tester) async {
      final h = Harness(tester);
      await h.start();
      h.pool.prefetch('feed', light);
      await tester.pump();
      final ad = h.lastAd, first = Object(), second = Object();
      h.pool.acquire(first, 'feed', light);
      h.pool.release(first);
      h.pool.prefetch('feed', light);
      await tester.pump();
      expect(h.requests, 1);
      ad.listener.onAdLoaded!(ad);
      await tester.pump();
      h.pool.acquire(second, 'feed', light);
      expect(h.pool.forOwner(second)!.ad, same(ad));
      h.pool.release(second);
      h.pool.acquire(first, 'feed', light);
      expect(h.requests, 1);
      expect(h.pool.forOwner(first)!.loaded, isTrue);
      h.pool.release(first);
      await h.close();
    },
  );

  testWidgets(
    'native view has one owner, fixed loading space, and reuses both theme variants',
    (tester) async {
      final h = Harness(tester);
      await h.start();
      Widget page({bool second = false, bool dark = false}) => MaterialApp(
        theme: sanadTheme(
          brightness: dark ? Brightness.dark : Brightness.light,
        ),
        home: Scaffold(
          body: Column(
            children: [
              SanadAdSlot(
                key: const ValueKey('a'),
                native: true,
                active: !second,
                placement: 'feed',
                nativeSession: h.pool,
              ),
              SanadAdSlot(
                key: const ValueKey('b'),
                native: true,
                active: second,
                placement: 'feed',
                nativeSession: h.pool,
              ),
            ],
          ),
        ),
      );
      await tester.pumpWidget(page());
      await tester.pump();
      final ad = h.lastAd;
      final size = tester.getSize(find.byType(CachedNativeSlot).first);
      expect(size.height, 414);
      ad.listener.onAdLoaded!(ad);
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byType(CachedNativeSlot).first), size);
      await tester.pumpWidget(page(second: true));
      await tester.pumpAndSettle();
      expect(h.requests, 1);
      expect(find.byType(AdWidget), findsOneWidget);
      expect(tester.widget<AdWidget>(find.byType(AdWidget)).ad, same(ad));
      await tester.pumpWidget(page(second: true, dark: true));
      await tester.pumpAndSettle();
      expect(h.requests, 2);
      await tester.pumpWidget(page(second: true));
      await tester.pumpAndSettle();
      expect(h.requests, 2);
      expect(find.byType(AdWidget), findsOneWidget);
      expect(tester.widget<AdWidget>(find.byType(AdWidget)).ad, same(ad));
      expect(tester.takeException(), isNull);
      await h.close();
    },
    variant: TargetPlatformVariant({TargetPlatform.iOS}),
  );

  testWidgets(
    'hidden native cache expires without network; stale callbacks cannot revive it',
    (tester) async {
      final h = Harness(tester);
      await h.start();
      h.pool.prefetch('feed', light);
      await tester.pump();
      final ad = h.lastAd;
      ad.listener.onAdLoaded!(ad);
      h.now = h.now.add(const Duration(minutes: 55));
      await tester.pump(const Duration(minutes: 55));
      expect(h.pool.length, 0);
      expect(h.requests, 1);
      final owner = Object();
      h.pool.acquire(owner, 'feed', light);
      await tester.pump();
      final replacement = h.lastAd;
      expect(h.requests, 2);
      ad.listener.onAdLoaded!(ad);
      await tester.pump();
      expect(h.pool.forOwner(owner)!.loaded, isFalse);
      expect(h.pool.forOwner(owner)!.ad, same(replacement));
      h.pool.release(owner);
      await h.close();
    },
  );

  testWidgets(
    'background stops new loads and hidden no-fill retry; resume keeps valid inventory',
    (tester) async {
      final h = Harness(tester);
      await h.start();
      final owner = Object();
      h.pool.acquire(owner, 'feed', light);
      await tester.pump();
      final ad = h.lastAd;
      ad.listener.onAdFailedToLoad!(
        ad,
        LoadAdError(3, 'admob', 'no fill', null),
      );
      h.pool.release(owner);
      h.pool.didChangeAppLifecycleState(AppLifecycleState.paused);
      h.pool.prefetch('next', light);
      h.now = h.now.add(const Duration(minutes: 3));
      await tester.pump(const Duration(minutes: 3));
      expect(h.requests, 1);
      h.pool.acquire(owner, 'feed', light);
      await tester.pump();
      expect(h.requests, 1);
      h.pool.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await tester.pump();
      expect(h.requests, 2);
      final replacement = h.lastAd;
      replacement.listener.onAdLoaded!(replacement);
      h.pool.release(owner);
      h.pool.didChangeAppLifecycleState(AppLifecycleState.paused);
      h.pool.didChangeAppLifecycleState(AppLifecycleState.resumed);
      h.pool.acquire(owner, 'feed', light);
      await tester.pump();
      expect(h.requests, 2);
      expect(h.pool.forOwner(owner)!.ad, same(replacement));
      h.pool.release(owner);
      await h.close();
    },
  );

  testWidgets(
    'idle LRU and memory pressure release ads while consent clears all inventory',
    (tester) async {
      final h = Harness(tester);
      await h.start(capacity: 1);
      h.pool.prefetch('one', light);
      await tester.pump();
      final old = h.lastAd;
      old.listener.onAdLoaded!(old);
      h.pool.prefetch('two', light);
      await tester.pump();
      final current = h.lastAd;
      current.listener.onAdLoaded!(current);
      expect(h.pool.length, 1);
      final owner = Object();
      h.pool.acquire(owner, 'two', light);
      h.pool.prefetch('next', light);
      await tester.pump();
      h.pool.didHaveMemoryPressure();
      await tester.pump();
      expect(h.pool.length, 1);
      expect(h.pool.forOwner(owner)!.ad, same(current));
      h.gateway.allowed = false;
      await h.ads.editPrivacy();
      await tester.pump();
      expect(h.pool.length, 0);
      expect(h.pool.forOwner(owner), isNull);
      old.listener.onAdLoaded!(old);
      await tester.pump();
      expect(h.pool.length, 0);
      await h.close();
    },
  );
}
