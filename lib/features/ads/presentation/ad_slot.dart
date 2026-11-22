import 'package:flutter/widgets.dart';
import '../data/banner_ad_session.dart';
import '../data/native_ad_session.dart';
import 'cached_banner_slot.dart';
import 'cached_native_slot.dart';

/// Rebuilds and list-row eviction never own the underlying SDK request.
class SanadAdSlot extends StatelessWidget {
  const SanadAdSlot({
    super.key,
    required this.native,
    required this.active,
    required this.placement,
    this.onExtentChanged,
    this.bannerSession,
    this.nativeSession,
    this.contextKey,
  });
  final bool native, active;
  final String placement;
  final ValueChanged<double>? onExtentChanged;
  final BannerAdSession? bannerSession;
  final NativeAdSession? nativeSession;
  final String? contextKey;
  @override
  Widget build(BuildContext context) => native
      ? CachedNativeSlot(
          active: active,
          placement: placement,
          session: nativeSession ?? NativeAdSession.instance,
          onExtentChanged: onExtentChanged,
        )
      : CachedBannerSlot(
          active: active,
          placement: placement,
          session: bannerSession,
          onExtentChanged: onExtentChanged,
          contextKey: contextKey,
        );
}
