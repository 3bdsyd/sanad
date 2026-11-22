import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../domain/ad_config.dart';

abstract interface class AdsGateway {
  Future<void> updateConsent();
  Future<void> showRequiredConsent();
  Future<bool> canRequestAds();
  Future<bool> privacyRequired();
  Future<void> showPrivacyOptions();
  Future<void> initialize();
}

class GoogleAdsGateway implements AdsGateway {
  GoogleAdsGateway({this.testDeviceId = AdConfig.testDeviceId});
  final String testDeviceId;

  @override
  Future<void> updateConsent() {
    final result = Completer<void>();
    ConsentInformation.instance.requestConsentInfoUpdate(
      ConsentRequestParameters(),
      () => result.complete(),
      (error) => result.completeError(error),
    );
    return result.future.timeout(const Duration(seconds: 15));
  }

  @override
  Future<void> showRequiredConsent() {
    final result = Completer<void>();
    ConsentForm.loadAndShowConsentFormIfRequired((error) {
      if (error == null) {
        result.complete();
      } else {
        result.completeError(error);
      }
    });
    return result.future;
  }

  @override
  Future<bool> canRequestAds() => ConsentInformation.instance.canRequestAds();
  @override
  Future<bool> privacyRequired() async =>
      await ConsentInformation.instance.getPrivacyOptionsRequirementStatus() ==
      PrivacyOptionsRequirementStatus.required;
  @override
  Future<void> showPrivacyOptions() {
    final result = Completer<void>();
    ConsentForm.showPrivacyOptionsForm((error) {
      if (error == null) {
        result.complete();
      } else {
        result.completeError(error);
      }
    });
    return result.future;
  }

  @override
  Future<void> initialize() async {
    final devices = AdConfig.testDevices(testDeviceId);
    if (devices.isNotEmpty) {
      await MobileAds.instance.updateRequestConfiguration(
        RequestConfiguration(testDeviceIds: devices),
      );
    }
    await MobileAds.instance.initialize();
  }
}

class AdsController extends ChangeNotifier {
  AdsController({
    required this.gateway,
    required this.supported,
    this.retryDelays = const [
      Duration(seconds: 30),
      Duration(minutes: 2),
      Duration(minutes: 5),
    ],
  });
  static final instance = AdsController(
    gateway: GoogleAdsGateway(),
    supported: AdConfig.supported,
  );
  final AdsGateway gateway;
  final bool supported;
  final List<Duration> retryDelays;
  bool ready = false, privacyRequired = false;
  Timer? _retry;
  int _retries = 0;
  bool _initialized = false,
      _started = false,
      _disposed = false,
      _editing = false;
  Future<void>? _starting;

  Future<void> start() {
    if (!supported || _started) return Future.value();
    _retry?.cancel();
    return _starting ??= _start().whenComplete(() => _starting = null);
  }

  Future<void> _start() async {
    var checked = false;
    try {
      await gateway.updateConsent();
      if (_disposed) return;
      await gateway.showRequiredConsent();
      checked = true;
    } catch (_) {
      // UMP alone decides whether a previous choice still permits requests.
    }
    await _reconcile();
    if (_disposed) return;
    // A failed check on a weak network must not silence ads for the session.
    _started = checked || ready;
    if (!_started && _retries < retryDelays.length) {
      _retry = Timer(retryDelays[_retries++], () => unawaited(start()));
    }
  }

  Future<void> _reconcile() async {
    try {
      final allowed = await gateway.canRequestAds();
      final required = await gateway.privacyRequired();
      if (_disposed) return;
      privacyRequired = required;
      if (allowed && !_initialized) {
        await gateway.initialize();
        _initialized = true;
      }
      if (_disposed) return;
      ready = allowed && _initialized;
    } catch (_) {
      ready = false;
    }
    if (!_disposed) notifyListeners();
  }

  Future<bool> editPrivacy() async {
    if (!supported || _editing) return false;
    _editing = true;
    ready = false;
    notifyListeners();
    var success = true;
    try {
      await gateway.showPrivacyOptions();
    } catch (_) {
      success = false;
    }
    await _reconcile();
    _editing = false;
    return success;
  }

  @override
  void dispose() {
    _disposed = true;
    _retry?.cancel();
    super.dispose();
  }
}

/// Diagnostic callbacks only. Financial reports remain in AdMob, separated by unit.
abstract final class AdDiagnostics {
  static final counts = <String, int>{};
  static void event(String placement, String event) {
    final key = '$placement.$event';
    counts[key] = (counts[key] ?? 0) + 1;
    if (kDebugMode) debugPrint('Ads $key: ${counts[key]}');
  }

  static void paid(String placement, double micros, String currency) {
    event(placement, 'paid');
    if (kDebugMode) {
      debugPrint('Ads $placement revenueMicros=$micros currency=$currency');
    }
  }
}
