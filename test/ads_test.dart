import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:snad/features/ads/data/ads_controller.dart';
import 'package:snad/features/ads/domain/ad_config.dart';

class FakeAdsGateway implements AdsGateway {
  bool allowed = false, requiresPrivacy = false, updateFails = false;
  bool revokeOnEdit = false;
  int updates = 0, initializations = 0, forms = 0;
  Completer<void>? waitForConsent;
  @override
  Future<void> updateConsent() async {
    updates++;
    if (updateFails) throw StateError('offline');
    await waitForConsent?.future;
  }

  @override
  Future<void> showRequiredConsent() async {
    forms++;
  }

  @override
  Future<bool> canRequestAds() async => allowed;
  @override
  Future<bool> privacyRequired() async => requiresPrivacy;
  @override
  Future<void> initialize() async {
    initializations++;
  }

  @override
  Future<void> showPrivacyOptions() async {
    if (revokeOnEdit) allowed = false;
  }
}

void main() {
  test(
    'feed preserves every job and pagination index with one or two columns',
    () {
      for (final columns in [1, 2]) {
        for (var jobs = 0; jobs < 160; jobs++) {
          final layout = AdFeedLayout(
            jobs: jobs,
            columns: columns,
            enabled: true,
          );
          final rows = <int>[];
          var ads = 0;
          for (var i = 0; i < layout.itemCount; i++) {
            if (layout.isAd(i)) {
              expect(layout.slotAt(i), ads++);
            } else {
              final row = layout.rowAt(i);
              rows.add(row);
              expect(layout.itemForRow(row), i);
            }
          }
          expect(rows, List.generate(layout.rows, (i) => i));
          expect(ads, layout.ads);
        }
      }
    },
  );

  test('native ads keep appearing through a long catalog', () {
    final layout = AdFeedLayout(jobs: 1000, columns: 1, enabled: true);
    expect(layout.ads, 100);
    expect(layout.isAd(layout.first + 99 * (layout.interval + 1)), isTrue);
    expect(layout.itemCount, 1100);
  });

  test('native slots stay in place when the next catalog page arrives', () {
    final first = AdFeedLayout(jobs: 24, columns: 1, enabled: true);
    final next = AdFeedLayout(jobs: 48, columns: 1, enabled: true);
    expect(first.isAd(6), isTrue);
    expect(first.isAd(17), isTrue);
    for (var row = 0; row < first.rows; row++) {
      expect(next.itemForRow(row), first.itemForRow(row));
    }
    final disabled = AdFeedLayout(jobs: 24, columns: 1, enabled: false);
    expect(disabled.itemCount, 24);
    expect(disabled.ads, 0);
  });

  test(
    'platform and format select the supplied production units; debug uses Google test units',
    () {
      expect(
        AdConfig.unitId(ios: false, native: false, test: false),
        endsWith('/7483199262'),
      );
      expect(
        AdConfig.unitId(ios: false, native: true, test: false),
        endsWith('/1630613497'),
      );
      expect(
        AdConfig.unitId(ios: true, native: false, test: false),
        endsWith('/1019531566'),
      );
      expect(
        AdConfig.unitId(ios: true, native: true, test: false),
        endsWith('/8514878200'),
      );
      for (final ios in [false, true]) {
        for (final native in [false, true]) {
          expect(
            AdConfig.unitId(ios: ios, native: native, test: true),
            startsWith('ca-app-pub-3940256099942544/'),
          );
        }
      }
      expect(AdConfig.testAds, isTrue);
    },
  );

  test(
    'concurrent startup waits for consent and initializes exactly once',
    () async {
      final gateway = FakeAdsGateway()
        ..allowed = true
        ..waitForConsent = Completer<void>();
      final ads = AdsController(gateway: gateway, supported: true);
      addTearDown(ads.dispose);
      final first = ads.start();
      final second = ads.start();
      expect(gateway.initializations, 0);
      expect(ads.ready, isFalse);
      gateway.waitForConsent!.complete();
      await Future.wait([first, second]);
      await ads.start();
      expect(gateway.updates, 1);
      expect(gateway.initializations, 1);
      expect(ads.ready, isTrue);
    },
  );

  test('consent failure cannot enable ads without UMP permission', () async {
    final gateway = FakeAdsGateway()..updateFails = true;
    final ads = AdsController(gateway: gateway, supported: true);
    addTearDown(ads.dispose);
    await ads.start();
    expect(ads.ready, isFalse);
    expect(gateway.initializations, 0);
  });

  test(
    'UMP may allow prior consent offline and privacy revocation stops requests',
    () async {
      final gateway = FakeAdsGateway()
        ..updateFails = true
        ..allowed = true
        ..requiresPrivacy = true
        ..revokeOnEdit = true;
      final ads = AdsController(gateway: gateway, supported: true);
      addTearDown(ads.dispose);
      await ads.start();
      expect(ads.ready, isTrue);
      expect(ads.privacyRequired, isTrue);
      final edit = ads.editPrivacy();
      expect(ads.ready, isFalse);
      expect(await edit, isTrue);
      expect(ads.ready, isFalse);
      expect(gateway.initializations, 1);
    },
  );

  test('a failed consent check retries and can still enable ads', () async {
    final gateway = FakeAdsGateway()..updateFails = true;
    final ads = AdsController(
      gateway: gateway,
      supported: true,
      retryDelays: const [Duration.zero],
    );
    addTearDown(ads.dispose);
    await ads.start();
    expect(ads.ready, isFalse);
    gateway
      ..updateFails = false
      ..allowed = true;
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(gateway.updates, 2);
    expect(ads.ready, isTrue);
    await ads.start();
    expect(gateway.updates, 2);
  });

  test('consent retries stop at the configured limit', () async {
    final gateway = FakeAdsGateway()..updateFails = true;
    final ads = AdsController(
      gateway: gateway,
      supported: true,
      retryDelays: const [Duration.zero],
    );
    addTearDown(ads.dispose);
    await ads.start();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(gateway.updates, 2);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(gateway.updates, 2);
  });

  test('a declined consent check is final for the session', () async {
    final gateway = FakeAdsGateway();
    final ads = AdsController(
      gateway: gateway,
      supported: true,
      retryDelays: const [Duration.zero],
    );
    addTearDown(ads.dispose);
    await ads.start();
    await ads.start();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(gateway.updates, 1);
    expect(ads.ready, isFalse);
  });

  test('disabled platforms never initialize advertising', () async {
    final gateway = FakeAdsGateway()..allowed = true;
    final ads = AdsController(gateway: gateway, supported: false);
    addTearDown(ads.dispose);
    await ads.start();
    expect(gateway.updates, 0);
    expect(gateway.initializations, 0);
    expect(ads.ready, isFalse);
  });
}
