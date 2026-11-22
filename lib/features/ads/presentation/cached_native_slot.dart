import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../../../core/design.dart';
import '../data/native_ad_session.dart';

class CachedNativeSlot extends StatefulWidget {
  const CachedNativeSlot({
    super.key,
    required this.active,
    required this.placement,
    required this.session,
    this.onExtentChanged,
  });
  final bool active;
  final String placement;
  final NativeAdSession session;
  final ValueChanged<double>? onExtentChanged;
  @override
  State<CachedNativeSlot> createState() => _CachedNativeSlotState();
}

class _CachedNativeSlotState extends State<CachedNativeSlot> {
  final owner = Object();
  NativeAdSpec? spec;
  bool scheduled = false;
  double reportedExtent = 0;
  @override
  void initState() {
    super.initState();
    widget.session.addListener(changed);
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
      if (!widget.active || spec == null || spec!.width < 320) {
        widget.session.release(owner);
        return;
      }
      final acquired = widget.session.acquire(owner, widget.placement, spec!);
      if (acquired) setState(() {});
    });
  }

  void extent(double value) {
    if (reportedExtent == value) return;
    reportedExtent = value;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onExtentChanged?.call(value);
    });
  }

  @override
  void didUpdateWidget(CachedNativeSlot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session != widget.session) {
      oldWidget.session.removeListener(changed);
      oldWidget.session.release(owner);
      widget.session.addListener(changed);
    }
    if (!widget.active) {
      widget.session.release(owner);
    } else if (oldWidget.active != widget.active ||
        oldWidget.placement != widget.placement ||
        oldWidget.session != widget.session) {
      sync();
    }
  }

  @override
  void dispose() {
    widget.session.removeListener(changed);
    widget.session.release(owner);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active ||
        !widget.session.ads.supported ||
        !widget.session.ads.ready) {
      extent(0);
      return const SizedBox.shrink();
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final next = NativeAdSpec(
          width: math.min(constraints.maxWidth.floor(), 420),
          colors: context.sanad,
        );
        final key = next.key(widget.placement);
        final entry = widget.session.forOwner(owner);
        if (spec?.key(widget.placement) != key || entry == null) {
          spec = next;
          sync();
        }
        if (next.width < 320 ||
            entry == null ||
            entry.spec.key(entry.placement) != key ||
            (!entry.loaded && !entry.loading)) {
          extent(0);
          return const SizedBox.shrink();
        }
        // Reserve the eventual layout before the SDK finishes, so loading never
        // pushes a job or button away from a finger already heading toward it.
        extent(414);
        return Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 14),
          padding: const EdgeInsets.only(top: 8, bottom: 12),
          decoration: BoxDecoration(
            color: context.sanad.surface,
            borderRadius: BorderRadius.circular(18),
          ),
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
              const SizedBox(height: 4),
              Center(
                child: SizedBox(
                  width: next.width.toDouble(),
                  height: 360,
                  child: entry.loaded && entry.ad != null
                      ? AdWidget(key: ObjectKey(entry.ad), ad: entry.ad!)
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
