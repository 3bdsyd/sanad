import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:google_mobile_ads/src/ad_instance_manager.dart'
    show AdMessageCodec;
import 'package:snad/features/ads/data/ads_controller.dart';
import 'package:snad/features/ads/domain/ad_config.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final channel = MethodChannel(
    'plugins.flutter.io/google_mobile_ads',
    StandardMethodCodec(AdMessageCodec()),
  );
  final calls = <MethodCall>[];
  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (call.method == 'MobileAds#initialize') {
            return InitializationStatus({});
          }
          return null;
        });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('QA device is configured before SDK initialization', () async {
    const id = '0123456789abcdef0123456789abcdef';
    await GoogleAdsGateway(testDeviceId: id).initialize();
    final relevant = calls
        .where((call) => call.method.startsWith('MobileAds#'))
        .toList();
    expect(relevant.map((call) => call.method), [
      'MobileAds#updateRequestConfiguration',
      'MobileAds#initialize',
    ]);
    expect((relevant.first.arguments as Map)['testDeviceIds'], [id]);
  });

  test(
    'invalid device hash cannot fall through to live ad initialization',
    () async {
      await expectLater(
        GoogleAdsGateway(testDeviceId: 'wrong-id').initialize(),
        throwsArgumentError,
      );
      expect(calls, isEmpty);
      expect(AdConfig.testDevices(''), isEmpty);
    },
  );
}
