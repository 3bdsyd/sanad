import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../domain/ad_config.dart';
import '../domain/ad_load_policy.dart';
import 'ads_controller.dart';

/// One banner/request shared by eligible routes using the same unit/geometry.
/// No ad is prefetched until a visible screen first acquires it.
class BannerAdSession extends ChangeNotifier with WidgetsBindingObserver {
  BannerAdSession({
    required this.ads,
    AdLoadPolicy? policy,
    DateTime Function()? now,
    this.maxAge = const Duration(minutes: 55),
    this.minManualRefresh = const Duration(seconds: 60),
    this.loadTimeout = const Duration(seconds: 45),
  }) : policy = policy ?? adLoadPolicy,
       _now = now ?? DateTime.now {
    ads.addListener(_consentChanged);
    WidgetsBinding.instance.addObserver(this);
    foreground =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
  }
  static final instance = BannerAdSession(ads: AdsController.instance);
  final AdsController ads;
  final AdLoadPolicy policy;
  final DateTime Function() _now;
  final Duration maxAge;
  final Duration minManualRefresh;
  final Duration loadTimeout;
  bool foreground = true;
  BannerAd? _ad;
  AdSize? _size;
  DateTime? _loadedAt;
  Object? _owner;
  String? _signature;
  String? _contextKey;
  bool _impressed = false;
  String _placement = 'job_details_banner';
  int _width = 0, _generation = 0;
  bool _loading = false, _loaded = false, _disposed = false, _scheduled = false;
  Timer? _retry;
  Timer? _expiry;
  Timer? _timeout;
  AdLoadAttempt? _attempt;

  BannerAd? get ad => _ad;
  AdSize? get size => _size;
  bool get ready => ads.ready && _loaded && _ad != null;
  bool get loading => ads.ready && _loading;
  bool owns(Object owner) => identical(_owner, owner);
  bool get _expired =>
      _loadedAt != null && _now().difference(_loadedAt!) >= maxAge;
  String get _policyKey => 'shared_banner/${AdConfig.id(native: false)}';

  /// A retiring route can still own a mounted platform view for one frame.
  /// Wait for it; never attach the same native view to two AdWidgets.
  bool acquire(
    Object owner, {
    required int width,
    required Orientation orientation,
    required String placement,
    String? contextKey,
  }) {
    if (_disposed || !ads.supported || width < 200) return false;
    if (_owner != null && !owns(owner)) return false;
    if (_ad?.isMounted == true && !owns(owner)) return false;
    final signature = '$width/$orientation/${AdConfig.id(native: false)}';
    final nextContext = contextKey ?? placement;
    // Preserve unshown inventory and revisits to the same job. A new job is
    // a genuine new placement opportunity once the prior ad was impressed.
    if (_signature != signature ||
        _expired ||
        (_impressed &&
            _contextKey != nextContext &&
            _loadedAt != null &&
            _now().difference(_loadedAt!) >= minManualRefresh)) {
      _invalidate();
    }
    final reused = _owner == null && ready;
    _owner = owner;
    _signature = signature;
    _contextKey = nextContext;
    _placement = placement;
    _width = width;
    if (reused) AdDiagnostics.event(placement, 'reused');
    unawaited(_ensureLoaded());
    return true;
  }

  void release(Object owner) {
    if (!owns(owner)) return;
    _owner = null;
    _retry?.cancel();
    _retry = null;
    // Keep the request in flight and a successful result. Both belong to this
    // session, so rapid back/forward navigation cannot start a duplicate load.
    if (_expired) _invalidate();
    _publish();
  }

  void _publish() {
    if (_disposed || _scheduled) return;
    _scheduled = true;
    scheduleMicrotask(() {
      _scheduled = false;
      if (!_disposed) notifyListeners();
    });
  }

  void _discard(BannerAd ad) {
    if (ad.isMounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) => ad.dispose());
    } else {
      unawaited(ad.dispose());
    }
  }

  void _invalidate() {
    _generation++;
    _retry?.cancel();
    _retry = null;
    _expiry?.cancel();
    _expiry = null;
    _timeout?.cancel();
    _timeout = null;
    if (_attempt case final attempt?) policy.abandoned(attempt);
    _attempt = null;
    final old = _ad;
    _ad = null;
    _size = null;
    _loadedAt = null;
    _loading = _loaded = false;
    _impressed = false;
    if (old != null) _discard(old);
  }

  void _consentChanged() {
    if (!ads.ready) _invalidate();
    if (_owner != null) unawaited(_ensureLoaded());
    _publish();
  }

  void _retryWhenAllowed() {
    if (_disposed ||
        !foreground ||
        !ads.ready ||
        _owner == null ||
        _retry != null) {
      return;
    }
    final wait = policy.waitFor(_policyKey, native: false);
    if (wait == null) return;
    _retry = Timer(
      wait == Duration.zero ? const Duration(seconds: 1) : wait,
      () {
        _retry = null;
        unawaited(_ensureLoaded());
      },
    );
  }

  void _failed(BannerAd? ad, {LoadAdError? error}) {
    if (_disposed || (ad != null && !identical(ad, _ad))) return;
    if (_loaded && _attempt == null) {
      // A refresh of an already displayed banner belongs to the SDK. Keep
      // its view and refresh schedule; don't add an app-level retry loop.
      AdDiagnostics.event(
        _placement,
        'refresh_failed_${error?.code ?? 'transport'}',
      );
      return;
    }
    final attempt = _attempt ?? policy.begin(_policyKey, native: false);
    if (attempt != null) {
      final ios = defaultTargetPlatform == TargetPlatform.iOS;
      policy.failedSdk(attempt, ios: ios, code: error?.code);
    }
    _attempt = null;
    AdDiagnostics.event(_placement, 'failed_${error?.code ?? 'transport'}');
    _invalidate();
    _publish();
    _retryWhenAllowed();
  }

  Future<void> _ensureLoaded() async {
    if (_disposed ||
        !foreground ||
        !ads.ready ||
        _owner == null ||
        _loading ||
        _loaded) {
      return;
    }
    if (policy.waitFor(_policyKey, native: false) != Duration.zero) {
      _retryWhenAllowed();
      return;
    }
    _loading = true;
    _retry?.cancel();
    _retry = null;
    final generation = _generation;
    try {
      final size = await AdSize.getLargeAnchoredAdaptiveBannerAdSize(_width);
      if (_disposed || generation != _generation) return;
      if (_owner == null || !ads.ready || !foreground) {
        _loading = false;
        return;
      }
      if (size == null) {
        _failed(null);
        return;
      }
      final attempt = policy.begin(_policyKey, native: false);
      if (attempt == null) {
        _loading = false;
        _retryWhenAllowed();
        return;
      }
      _attempt = attempt;
      _size = size;
      _publish();
      final placement = _placement;
      final ad = BannerAd(
        adUnitId: AdConfig.id(native: false),
        size: size,
        request: const AdRequest(),
        listener: BannerAdListener(
          onAdLoaded: (ad) {
            if (_disposed || !identical(ad, _ad) || !ads.ready) return;
            if (_attempt case final pending?) policy.succeeded(pending);
            _attempt = null;
            _timeout?.cancel();
            _timeout = null;
            _loading = false;
            _loaded = true;
            _impressed = false;
            // This also renews the timestamp when the SDK auto-refreshes.
            _loadedAt = _now();
            _expiry?.cancel();
            _expiry = Timer(maxAge, () {
              _expiry = null;
              // SDK refreshes renew this timer. If none arrived for 55 minutes,
              // retire the expired creative even when the page is still open.
              _invalidate();
              _publish();
              if (_owner != null && foreground) unawaited(_ensureLoaded());
            });
            AdDiagnostics.event(placement, 'loaded');
            _publish();
          },
          onAdFailedToLoad: (ad, error) =>
              _failed(ad as BannerAd, error: error),
          onAdImpression: (ad) {
            if (_disposed || !identical(ad, _ad)) return;
            _impressed = true;
            AdDiagnostics.event(_placement, 'impression');
          },
          onAdClicked: (_) => AdDiagnostics.event(_placement, 'click'),
          onPaidEvent: (_, micros, precision, currency) =>
              AdDiagnostics.paid(_placement, micros, currency),
        ),
      );
      _ad = ad;
      _timeout = Timer(loadTimeout, () {
        if (identical(ad, _ad) && !_loaded) _failed(ad);
      });
      AdDiagnostics.event(placement, 'request');
      await ad.load();
    } catch (_) {
      if (!_disposed && generation == _generation) _failed(_ad);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
    if (!foreground) {
      _retry?.cancel();
      _retry = null;
    } else {
      if (_expired) _invalidate();
      if (_owner != null) unawaited(_ensureLoaded());
    }
    _publish();
  }

  @override
  void didHaveMemoryPressure() {
    if (_owner == null) {
      _invalidate();
      _publish();
    }
  }

  @override
  void dispose() {
    ads.removeListener(_consentChanged);
    WidgetsBinding.instance.removeObserver(this);
    _disposed = true;
    _invalidate();
    super.dispose();
  }
}
