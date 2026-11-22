import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../../../core/design.dart';
import '../data/banner_ad_session.dart';

class CachedBannerSlot extends StatefulWidget {
  const CachedBannerSlot({
    super.key,
    required this.active,
    required this.placement,
    this.session,
    this.onExtentChanged,
    this.contextKey,
  });
  final bool active;
  final String placement;
  final BannerAdSession? session;
  final ValueChanged<double>? onExtentChanged;
  final String? contextKey;
  @override
  State<CachedBannerSlot> createState() => _CachedBannerSlotState();
}

class _CachedBannerSlotState extends State<CachedBannerSlot> {
  late final session = widget.session ?? BannerAdSession.instance;
  final owner = Object();
  int width = 0;
  Orientation orientation = Orientation.portrait;
  bool scheduled = false;
  double reportedExtent = 0;
  String? acquiredContext;

  @override
  void initState() {
    super.initState();
    session.addListener(changed);
  }

  void changed() {
    if (mounted) setState(() {});
  }

  void sync() {
    if (scheduled) return;
    scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      scheduled = false;
      if (!mounted) return;
      if (!widget.active || width < 200) {
        session.release(owner);
        return;
      }
      final acquired = session.acquire(
        owner,
        width: width,
        orientation: orientation,
        placement: widget.placement,
        contextKey: widget.contextKey,
      );
      if (acquired) setState(() => acquiredContext = widget.contextKey);
    });
  }

  void extent(double value) {
    if (reportedExtent == value) return;
    reportedExtent = value;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onExtentChanged?.call(reportedExtent);
    });
  }

  @override
  void didUpdateWidget(CachedBannerSlot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.active) {
      session.release(owner);
      return;
    }
    if (oldWidget.active != widget.active ||
        oldWidget.placement != widget.placement ||
        oldWidget.contextKey != widget.contextKey) {
      sync();
    }
  }

  @override
  void dispose() {
    session.removeListener(changed);
    session.release(owner);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active || !session.ads.supported) {
      extent(0);
      return const SizedBox.shrink();
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final nextWidth = math.min(constraints.maxWidth.floor(), 728);
        final nextOrientation = MediaQuery.orientationOf(context);
        if (nextWidth < 200) {
          width = nextWidth;
          sync();
          extent(0);
          return const SizedBox.shrink();
        }
        final geometryChanged =
            width != nextWidth || orientation != nextOrientation;
        if (width != nextWidth ||
            orientation != nextOrientation ||
            !session.owns(owner)) {
          width = nextWidth;
          orientation = nextOrientation;
          sync();
        }
        if (geometryChanged ||
            acquiredContext != widget.contextKey ||
            !session.owns(owner) ||
            (!session.ready && !session.loading) ||
            session.size == null ||
            width < 200) {
          extent(0);
          return const SizedBox.shrink();
        }
        final size = session.size!;
        extent(size.height.toDouble() + 40);
        return Container(
          width: double.infinity,
          // Keep the same reserved extent, with no painted footer strip.
          padding: const EdgeInsets.only(top: 6, bottom: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: 16,
                child: Text(
                  'إعلان ممول',
                  style: TextStyle(
                    color: context.sanad.secondary,
                    fontSize: 11,
                    height: 1.2,
                  ),
                ),
              ),
              const SizedBox(height: 2),
              Center(
                child: SizedBox(
                  width: size.width.toDouble(),
                  height: size.height.toDouble(),
                  child: session.ready
                      ? AdWidget(key: ObjectKey(session.ad), ad: session.ad!)
                      : const SizedBox.expand(),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
