import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../../../core/appearance.dart';
import '../domain/ad_config.dart';
import '../domain/ad_load_policy.dart';
import 'ads_controller.dart';

/// Geometry and native-template colors form part of the cached SDK object.
class NativeAdSpec {
  const NativeAdSpec({required this.width, required this.colors});
  final int width;
  final SanadColors colors;
  String key(String placement) =>
      '$placement/$width/${colors.isDark}/${AdConfig.id(native: true)}';
}

/// The SDK exposes this public mixin for inline-ad mount ownership checks.
class SessionNativeAd extends NativeAd with AdWithViewMounted {
  SessionNativeAd({
    required super.adUnitId,
    required super.listener,
    required super.request,
    super.nativeAdOptions,
    super.nativeTemplateStyle,
  });
}

class NativeAdEntry {
  NativeAdEntry(this.placement, this.spec);
  final String placement;
  final NativeAdSpec spec;
  SessionNativeAd? ad;
  Object? owner;
  DateTime? loadedAt, impressedAt;
  bool loaded = false, loading = false;
  AdLoadAttempt? attempt;
  Timer? retry, expiry, timeout;
}

/// Keeps SDK objects and their callbacks independent of evicted list rows.
/// There is no creative serialization or app-level periodic native refresh.
class NativeAdSession extends ChangeNotifier with WidgetsBindingObserver {
  NativeAdSession({
    required this.ads,
    AdLoadPolicy? policy,
    DateTime Function()? now,
    this.capacity = 3,
    this.maxAge = const Duration(minutes: 55),
    this.loadTimeout = const Duration(seconds: 45),
    this.minRevisitRefresh = const Duration(seconds: 60),
  }) : policy = policy ?? adLoadPolicy,
       _now = now ?? DateTime.now {
    ads.addListener(_consentChanged);
    WidgetsBinding.instance.addObserver(this);
    foreground =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
  }
  static final instance = NativeAdSession(ads: AdsController.instance);
  final AdsController ads;
  final AdLoadPolicy policy;
  final DateTime Function() _now;
  final int capacity;
  final Duration maxAge;
  final Duration loadTimeout;
  final Duration minRevisitRefresh;
  final _entries = <String, NativeAdEntry>{};
  final _owners = <Object, String>{};
  // Tiny timing metadata survives creative eviction, not process termination.
  final _impressions = <String, DateTime>{};
  bool foreground = true, _disposed = false, _scheduled = false;

  int get length => _entries.length;
  NativeAdEntry? forOwner(Object owner) => _entries[_owners[owner]];
  bool _current(NativeAdEntry entry) =>
      !_disposed && identical(_entries[entry.spec.key(entry.placement)], entry);
  bool _expired(NativeAdEntry entry) =>
      entry.loadedAt != null && _now().difference(entry.loadedAt!) >= maxAge;
  Duration _impressionWait(NativeAdEntry entry) {
    final stamp = _impressions[entry.spec.key(entry.placement)];
    if (stamp == null) return Duration.zero;
    final wait = minRevisitRefresh - _now().difference(stamp);
    return wait > Duration.zero ? wait : Duration.zero;
  }

  void _publish() {
    if (_disposed || _scheduled) return;
    _scheduled = true;
    scheduleMicrotask(() {
      _scheduled = false;
      if (!_disposed) notifyListeners();
    });
  }

  NativeAdEntry _entry(String placement, NativeAdSpec spec) {
    final key = spec.key(placement);
    var entry = _entries.remove(key);
    final newVisit =
        entry != null &&
        entry.owner == null &&
        entry.impressedAt != null &&
        _now().difference(entry.impressedAt!) >= minRevisitRefresh;
    if (entry != null && (_expired(entry) || newVisit)) {
      _discard(entry);
      entry = null;
    }
    return _entries[key] = entry ?? NativeAdEntry(placement, spec);
  }

  /// Warm only the next approaching placement; never a whole result page.
  void prefetch(String placement, NativeAdSpec spec) {
    if (_disposed || !foreground || !ads.ready || spec.width < 320) return;
    final entry = _entry(placement, spec);
    // No background retry chain for speculative inventory.
    _ensureLoaded(entry);
    if (!entry.loading && !entry.loaded && entry.owner == null) _remove(entry);
    _trim();
  }

  bool acquire(Object owner, String placement, NativeAdSpec spec) {
    if (_disposed || !ads.supported || spec.width < 320) return false;
    final key = spec.key(placement);
    final previous = _owners[owner];
    if (previous != null && previous != key) release(owner);
    final entry = _entry(placement, spec);
    if (entry.owner != null && !identical(entry.owner, owner)) return false;
    if (entry.ad?.isMounted == true && !identical(entry.owner, owner)) {
      return false;
    }
    final reused = entry.owner == null && entry.loaded;
    entry.owner = owner;
    _owners[owner] = key;
    if (reused) AdDiagnostics.event(placement, 'reused');
    _ensureLoaded(entry);
    _trim();
    return true;
  }

  void release(Object owner) {
    final key = _owners.remove(owner);
    final entry = _entries[key];
    if (entry == null || !identical(entry.owner, owner)) return;
    entry.owner = null;
    entry.retry?.cancel();
    entry.retry = null;
    // In-flight loads may finish into the bounded memory cache.
    if (_expired(entry) || (!entry.loading && !entry.loaded)) _remove(entry);
    _trim();
    _publish();
  }

  void _trim() {
    final idle = _entries.values.where((e) => e.owner == null).toList();
    for (final entry in idle) {
      if (_expired(entry)) _remove(entry);
    }
    final remaining = _entries.values.where((e) => e.owner == null).toList();
    for (final entry in remaining.take(
      (remaining.length - capacity).clamp(0, remaining.length),
    )) {
      _remove(entry);
    }
  }

  void _discard(NativeAdEntry entry) {
    entry.retry?.cancel();
    entry.expiry?.cancel();
    entry.timeout?.cancel();
    if (entry.attempt case final attempt?) policy.abandoned(attempt);
    entry.attempt = null;
    if (entry.owner case final owner?) _owners.remove(owner);
    final ad = entry.ad;
    if (ad == null) return;
    if (ad.isMounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) => ad.dispose());
    } else {
      unawaited(ad.dispose());
    }
  }

  void _remove(NativeAdEntry entry) {
    _entries.remove(entry.spec.key(entry.placement));
    _discard(entry);
  }

  void _retryWhenAllowed(NativeAdEntry entry) {
    if (!_current(entry) ||
        !foreground ||
        !ads.ready ||
        entry.owner == null ||
        entry.retry != null) {
      return;
    }
    final wait = policy.waitFor(entry.placement, native: true);
    if (wait == null) return;
    final shownWait = _impressionWait(entry);
    final delay = wait > shownWait ? wait : shownWait;
    entry.retry = Timer(
      delay == Duration.zero ? const Duration(seconds: 1) : delay,
      () {
        entry.retry = null;
        _ensureLoaded(entry);
      },
    );
  }

  void _ensureLoaded(NativeAdEntry entry) {
    if (!_current(entry) ||
        !foreground ||
        !ads.ready ||
        entry.loading ||
        entry.loaded) {
      return;
    }
    if (_impressionWait(entry) > Duration.zero) {
      _retryWhenAllowed(entry);
      return;
    }
    final attempt = policy.begin(entry.placement, native: true);
    if (attempt == null) {
      _retryWhenAllowed(entry);
      return;
    }
    entry.attempt = attempt;
    entry.loading = true;
    final colors = entry.spec.colors;
    final ad = SessionNativeAd(
      adUnitId: AdConfig.id(native: true),
      request: const AdRequest(),
      nativeAdOptions: NativeAdOptions(
        mediaAspectRatio: MediaAspectRatio.any,
        videoOptions: VideoOptions(startMuted: true),
        adChoicesPlacement: AdChoicesPlacement.topRightCorner,
      ),
      nativeTemplateStyle: NativeTemplateStyle(
        templateType: TemplateType.medium,
        mainBackgroundColor: colors.surface,
        cornerRadius: 16,
        primaryTextStyle: NativeTemplateTextStyle(
          textColor: colors.ink,
          size: 16,
        ),
        secondaryTextStyle: NativeTemplateTextStyle(
          textColor: colors.secondary,
          size: 13,
        ),
        tertiaryTextStyle: NativeTemplateTextStyle(
          textColor: colors.secondary,
          size: 13,
        ),
        callToActionTextStyle: NativeTemplateTextStyle(
          textColor: Colors.white,
          backgroundColor: colors.primary,
          size: 15,
        ),
      ),
      listener: NativeAdListener(
        onAdLoaded: (ad) {
          if (!_current(entry) || !identical(entry.ad, ad) || !ads.ready) {
            return;
          }
          policy.succeeded(attempt);
          entry.attempt = null;
          entry.timeout?.cancel();
          entry.timeout = null;
          entry.loading = false;
          entry.loaded = true;
          entry.loadedAt = _now();
          entry.expiry?.cancel();
          entry.expiry = Timer(maxAge, () {
            if (!_current(entry)) return;
            _remove(entry);
            _publish();
          });
          AdDiagnostics.event(entry.placement, 'loaded');
          _trim();
          _publish();
        },
        onAdFailedToLoad: (ad, error) {
          if (identical(entry.ad, ad)) _failed(entry, error);
        },
        onAdImpression: (ad) {
          if (_current(entry) && identical(entry.ad, ad)) {
            entry.impressedAt = _now();
            final key = entry.spec.key(entry.placement);
            _impressions.remove(key);
            _impressions[key] = entry.impressedAt!;
            while (_impressions.length > 256) {
              _impressions.remove(_impressions.keys.first);
            }
            AdDiagnostics.event(entry.placement, 'impression');
          }
        },
        onAdClicked: (_) => AdDiagnostics.event(entry.placement, 'click'),
        onPaidEvent: (_, micros, precision, currency) =>
            AdDiagnostics.paid(entry.placement, micros, currency),
      ),
    );
    entry.ad = ad;
    entry.timeout = Timer(loadTimeout, () {
      if (identical(entry.ad, ad)) _failed(entry, null);
    });
    AdDiagnostics.event(entry.placement, 'request');
    unawaited(
      ad.load().catchError((Object _) {
        if (identical(entry.ad, ad)) _failed(entry, null);
      }),
    );
  }

  void _failed(NativeAdEntry entry, LoadAdError? error) {
    if (!_current(entry)) return;
    final attempt = entry.attempt;
    if (attempt == null) return;
    final ios = defaultTargetPlatform == TargetPlatform.iOS;
    entry.timeout?.cancel();
    entry.timeout = null;
    policy.failedSdk(attempt, ios: ios, code: error?.code);
    entry.attempt = null;
    entry.loading = false;
    final ad = entry.ad;
    entry.ad = null;
    if (ad != null) unawaited(ad.dispose());
    AdDiagnostics.event(
      entry.placement,
      'failed_${error?.code ?? 'transport'}',
    );
    _retryWhenAllowed(entry);
    if (entry.owner == null) _remove(entry);
    _publish();
  }

  void _consentChanged() {
    if (!ads.ready) {
      _impressions.clear();
      for (final entry in _entries.values.toList()) {
        _remove(entry);
      }
    } else if (foreground) {
      for (final entry in _entries.values.toList()) {
        if (entry.owner != null) _ensureLoaded(entry);
      }
    }
    _publish();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
    for (final entry in _entries.values.toList()) {
      if (!foreground) {
        entry.retry?.cancel();
        entry.retry = null;
      } else if (_expired(entry)) {
        _remove(entry);
      } else if (entry.owner != null) {
        _ensureLoaded(entry);
      }
    }
    _publish();
  }

  @override
  void didHaveMemoryPressure() {
    for (final entry in _entries.values.toList()) {
      if (entry.owner == null) _remove(entry);
    }
    _publish();
  }

  @override
  void dispose() {
    _disposed = true;
    ads.removeListener(_consentChanged);
    WidgetsBinding.instance.removeObserver(this);
    for (final entry in _entries.values.toList()) {
      _remove(entry);
    }
    super.dispose();
  }
}
