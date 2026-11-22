import 'dart:async';
import 'package:flutter/widgets.dart';
import '../data/banner_ad_session.dart';
import '../domain/ad_config.dart';
import 'ad_slot.dart';

/// One presentation gate for every route sharing the banner session.
class ScreenBanner extends StatefulWidget {
  const ScreenBanner({
    super.key,
    required this.placement,
    required this.contextKey,
    this.enabled = true,
    this.session,
    this.onExtentChanged,
  });
  final String placement, contextKey;
  final bool enabled;
  final BannerAdSession? session;
  final ValueChanged<double>? onExtentChanged;
  @override
  State<ScreenBanner> createState() => _ScreenBannerState();
}

class _ScreenBannerState extends State<ScreenBanner>
    with WidgetsBindingObserver {
  late final session = widget.session ?? BannerAdSession.instance;
  bool foreground = true;
  bool active = false, started = false, startScheduled = false;
  @override
  void initState() {
    super.initState();
    foreground =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (mounted) {
      setState(() => foreground = state == AppLifecycleState.resumed);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    active =
        widget.enabled &&
        AdConfig.supported &&
        foreground &&
        MediaQuery.viewInsetsOf(context).bottom == 0 &&
        (ModalRoute.isCurrentOf(context) ?? true);
    if (active && !started && !startScheduled) {
      startScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        startScheduled = false;
        if (!mounted || !active) return;
        started = true;
        unawaited(session.ads.start());
      });
    }
    return SanadAdSlot(
      native: false,
      active: active,
      placement: widget.placement,
      contextKey: widget.contextKey,
      bannerSession: session,
      onExtentChanged: widget.onExtentChanged,
    );
  }
}
