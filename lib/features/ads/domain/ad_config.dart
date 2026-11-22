import 'package:flutter/foundation.dart';

abstract final class AdConfig {
  static const enabled = bool.fromEnvironment(
    'ADS_ENABLED',
    defaultValue: true,
  );
  static const forceTest = bool.fromEnvironment('ADS_TEST_MODE');
  static const testDeviceId = String.fromEnvironment('ADS_TEST_DEVICE_ID');

  static List<String> testDevices(String value) {
    final id = value.trim();
    if (id.isEmpty) return const [];
    if (!RegExp(r'^[a-fA-F0-9]{32}$').hasMatch(id)) {
      throw ArgumentError(
        'ADS_TEST_DEVICE_ID must be the SDK test-device hash.',
      );
    }
    return [id];
  }

  static bool get supported =>
      enabled &&
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);
  static bool get testAds => !kReleaseMode || forceTest;

  static String unitId({
    required bool ios,
    required bool native,
    required bool test,
  }) {
    if (test) {
      return native
          ? (ios
                ? 'ca-app-pub-3940256099942544/3986624511'
                : 'ca-app-pub-3940256099942544/2247696110')
          : (ios
                ? 'ca-app-pub-3940256099942544/2435281174'
                : 'ca-app-pub-3940256099942544/9214589741');
    }
    return native
        ? (ios
              ? 'ca-app-pub-7383022949817999/8514878200'
              : 'ca-app-pub-7383022949817999/1630613497')
        : (ios
              ? 'ca-app-pub-7383022949817999/1019531566'
              : 'ca-app-pub-7383022949817999/7483199262');
  }

  static String id({required bool native}) => unitId(
    ios: defaultTargetPlatform == TargetPlatform.iOS,
    native: native,
    test: testAds,
  );
}

/// Ad rows never participate in job pagination, filtering, or result counts.
class AdFeedLayout {
  AdFeedLayout({
    required this.jobs,
    required this.columns,
    required this.enabled,
  });
  final int jobs, columns;
  final bool enabled;
  int get rows => (jobs / columns).ceil();
  int get first => (6 / columns).ceil();
  int get interval => (10 / columns).ceil();
  int get ads => !enabled || rows < first ? 0 : 1 + (rows - first) ~/ interval;
  int get itemCount => rows + ads;
  bool isAd(int index) =>
      enabled &&
      index >= first &&
      (index - first) % (interval + 1) == 0 &&
      (index - first) ~/ (interval + 1) < ads;
  int rowAt(int index) =>
      index -
      (!enabled || index < first
          ? 0
          : (1 + (index - first) ~/ (interval + 1)).clamp(0, ads));
  int itemForRow(int row) =>
      row +
      (!enabled || row < first
          ? 0
          : (1 + (row - first) ~/ interval).clamp(0, ads));
  int slotAt(int index) => (index - first) ~/ (interval + 1);
}
