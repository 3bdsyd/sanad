import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'design.dart';
import 'motion.dart';
import 'native_bridge.dart';

/// The scroll gesture is owned by Flutter; its visual feedback belongs to Sanad.
/// Return an error message from [onRefresh] when the repository handles an error
/// internally. A completed Future alone must never imply a successful refresh.
class SanadRefresh extends StatefulWidget {
  const SanadRefresh({
    super.key,
    required this.onRefresh,
    required this.child,
    this.enabled = true,
    this.successLabel = 'صارت النتائج محدّثة',
    this.loadingLabel = 'عم نلاقي الجديد…',
    this.topInset = 0,
    this.indicatorTop,
  });

  final Future<String?> Function() onRefresh;
  final Widget child;
  final bool enabled;
  final String successLabel, loadingLabel;
  final double topInset;
  final double? indicatorTop;

  @override
  State<SanadRefresh> createState() => SanadRefreshState();
}

class SanadRefreshState extends State<SanadRefresh> {
  final _indicator = GlobalKey<RefreshIndicatorState>();
  Timer? _completionTimer;
  RefreshIndicatorStatus? _status;
  double _dragDistance = 0, _progress = 0;
  bool _running = false, _complete = false, _thresholdHaptic = false;
  String? _error;

  bool get _pulling =>
      _status == RefreshIndicatorStatus.drag ||
      _status == RefreshIndicatorStatus.armed;
  bool get _working => _running || _status == RefreshIndicatorStatus.snap;
  bool get _visible => (_pulling && _progress > 0) || _working || _complete;

  /// Gives the button/keyboard path the exact same feedback as the pull gesture.
  Future<void> refresh() async {
    if (!mounted || _running || !widget.enabled) return;
    await _indicator.currentState?.show();
  }

  @override
  void dispose() {
    _completionTimer?.cancel();
    super.dispose();
  }

  void _statusChanged(RefreshIndicatorStatus? value) {
    if (!mounted) return;
    if (value == RefreshIndicatorStatus.drag) {
      _completionTimer?.cancel();
      _thresholdHaptic = false;
      _dragDistance = 0;
      _progress = 0;
      _complete = false;
      _error = null;
    }
    if (value == RefreshIndicatorStatus.armed && !_thresholdHaptic) {
      _thresholdHaptic = true;
      unawaited(NativeBridge.selectionHaptic());
    }
    if (value == RefreshIndicatorStatus.canceled) {
      _progress = 0;
    }
    setState(() => _status = value);
  }

  bool _scrolling(ScrollNotification notification) {
    if (notification.depth != 0 ||
        notification.metrics.axis != Axis.vertical ||
        !_pulling) {
      return false;
    }
    if (notification is ScrollUpdateNotification) {
      _dragDistance -= notification.scrollDelta ?? 0;
    } else if (notification is OverscrollNotification) {
      _dragDistance -= notification.overscroll;
    } else {
      return false;
    }
    // Match RefreshIndicator's native arming distance (viewport / 6).
    final threshold = math.max(1.0, notification.metrics.viewportDimension / 6);
    final progress = (_dragDistance / threshold).clamp(0.0, 1.0);
    if ((_progress - progress).abs() > .008) {
      setState(() => _progress = progress);
    }
    return false;
  }

  Future<void> _perform() async {
    if (_running || !mounted) return;
    _completionTimer?.cancel();
    setState(() {
      _running = true;
      _complete = false;
      _error = null;
    });
    String? error;
    try {
      error = await widget.onRefresh();
    } catch (_) {
      error = 'تعذّر التحديث. تأكد من الاتصال وجرّب مرة تانية.';
    } finally {
      if (mounted) {
        setState(() {
          _running = false;
          _complete = true;
          _error = error;
          _progress = 1;
        });
        if (error == null) {
          _completionTimer = Timer(const Duration(milliseconds: 1800), _close);
        }
      }
    }
  }

  void _close() {
    if (!mounted || _working) return;
    _completionTimer?.cancel();
    setState(() {
      _complete = false;
      _status = null;
      _progress = 0;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final armed = _status == RefreshIndicatorStatus.armed;
    final label = _working
        ? widget.loadingLabel
        : _complete
        ? _error == null
              ? widget.successLabel
              : 'ما اكتمل التحديث'
        : armed
        ? 'فلّت، وسند بيجيب الجديد'
        : 'اسحب شوي… للجديد';
    final indicator = MotionSize(
      duration: motionDuration(context, _pulling ? 80 : 240),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: !_visible
          ? const SizedBox(width: double.infinity)
          : ClipRect(
              child: Align(
                alignment: Alignment.topCenter,
                heightFactor: _pulling
                    ? Curves.easeOut.transform(_progress)
                    : 1,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(20, widget.topInset + 8, 20, 8),
                  child: Semantics(
                    liveRegion: !_pulling,
                    label: _error ?? label,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 13,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: _error == null
                            ? context.sanad.tint
                            : context.sanad.isDark
                            ? const Color(0xFF3B292D)
                            : const Color(0xFFF8ECE8),
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(
                          color: _error == null
                              ? context.sanad.border
                              : context.sanad.isDark
                              ? const Color(0xFF704A50)
                              : const Color(0xFFEED6CB),
                        ),
                      ),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 45,
                            height: 45,
                            child: _working
                                ? const SanadLoader(size: 38)
                                : _complete
                                ? Center(
                                    child: AppIcon(
                                      _error == null
                                          ? CupertinoIcons.checkmark
                                          : CupertinoIcons.wifi_exclamationmark,
                                      color: _error == null
                                          ? context.sanad.primary
                                          : context.sanad.isDark
                                          ? const Color(0xFFFFB4A8)
                                          : const Color(0xFF9A4B35),
                                      size: 24,
                                    ),
                                  )
                                : CustomPaint(
                                    painter: _PullTrail(
                                      armed ? 1 : _progress,
                                      context.sanad.primary,
                                    ),
                                    child: Center(
                                      child: Transform.scale(
                                        scale:
                                            .78 + .22 * (armed ? 1 : _progress),
                                        child: const SanadLogo(size: 28),
                                      ),
                                    ),
                                  ),
                          ),
                          const SizedBox(width: 11),
                          Expanded(
                            child: ExcludeSemantics(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    label,
                                    style: TextStyle(
                                      color: context.sanad.ink,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 12,
                                    ),
                                  ),
                                  if (_error != null) ...[
                                    const SizedBox(height: 3),
                                    Text(
                                      _error!,
                                      maxLines: 3,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: context.sanad.secondary,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                          if (_complete && !_working)
                            IconButton(
                              tooltip: 'إخفاء حالة التحديث',
                              onPressed: _close,
                              icon: AppIcon(
                                CupertinoIcons.xmark,
                                color: context.sanad.secondary,
                                size: 15,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
    );
    final scrollable = NotificationListener<ScrollNotification>(
      onNotification: _scrolling,
      child: RefreshIndicator.noSpinner(
        key: _indicator,
        onRefresh: _perform,
        onStatusChange: _statusChanged,
        semanticsLabel: 'تحديث النتائج',
        notificationPredicate: (notification) =>
            notification.depth == 0 && (widget.enabled || _running),
        child: widget.child,
      ),
    );
    if (widget.indicatorTop case final top?) {
      return Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(child: scrollable),
          Positioned(top: top, left: 0, right: 0, child: indicator),
        ],
      );
    }
    return Column(
      children: [
        indicator,
        Expanded(child: scrollable),
      ],
    );
  }
}

/// Two growing strokes join around the logo as the pull becomes ready.
class _PullTrail extends CustomPainter {
  const _PullTrail(this.progress, this.color);
  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round
      ..color = color;
    for (final start in [-math.pi / 2, math.pi / 2]) {
      canvas.drawArc(
        rect.deflate(2.5),
        start,
        (math.pi - .35) * progress,
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_PullTrail oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.color != color;
}
