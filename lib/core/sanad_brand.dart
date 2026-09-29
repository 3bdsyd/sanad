import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'appearance.dart';

/// One palette for Flutter, the native launch screen and the generated artwork.
abstract final class SanadPalette {
  static const primary = Color(0xFF20508A);
  static const ink = Color(0xFF12233F);
  static const secondary = Color(0xFF577395);
  static const background = Color(0xFFF2F7FC);
  static const border = Color(0xFFDCE8F5);
  static const tint = Color(0xFFE7F0FA);
  static const accent = Color(0xFF9CC9FA);
}

/// The same square artwork and corner ratio are used by LaunchScreen.storyboard.
/// Keep the initial launch at 96 logical pixels, centered in the whole window.
class SanadLogo extends StatefulWidget {
  const SanadLogo({
    super.key,
    this.size = 64,
    this.animated = false,
    this.onDark = false,
    this.highContrast = false,
    this.bare = false,
    this.hero = false,
  });

  static const asset = 'assets/images/sanad-logo.png';
  static const contrastAsset = 'assets/images/sanad-logo-contrast.png';
  static const heroTag = 'sanad.brand.logo';
  final double size;
  final bool animated, onDark, highContrast, bare, hero;

  @override
  State<SanadLogo> createState() => _SanadLogoState();
}

class _SanadLogoState extends State<SanadLogo>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _motion = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  );
  bool _visible = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(covariant SanadLogo oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _visible = state == AppLifecycleState.resumed;
    _sync();
  }

  void _sync() {
    final run =
        widget.animated &&
        _visible &&
        TickerMode.valuesOf(context).enabled &&
        !MediaQuery.disableAnimationsOf(context);
    if (run && !_motion.isAnimating) {
      _motion.repeat();
    } else if (!run) {
      _motion.stop();
      if (_motion.value != 0) _motion.value = 0;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mark = ExcludeSemantics(
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: _motion,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(widget.size / 4),
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: widget.bare
                    ? null
                    : LinearGradient(
                        begin: Alignment.topRight,
                        end: Alignment.bottomLeft,
                        colors: widget.highContrast
                            ? const [SanadPalette.primary, Color(0xFF173D6D)]
                            : [context.sanad.surface, context.sanad.tint],
                      ),
              ),
              child: Image.asset(
                widget.highContrast ? SanadLogo.contrastAsset : SanadLogo.asset,
                color: !widget.highContrast && context.sanad.isDark
                    ? context.sanad.primary
                    : null,
                colorBlendMode: BlendMode.srcIn,
                width: widget.size,
                height: widget.size,
                fit: BoxFit.cover,
                filterQuality: FilterQuality.medium,
                gaplessPlayback: true,
                errorBuilder: (_, _, _) => SizedBox.square(
                  dimension: widget.size,
                  child: Center(
                    child: Text(
                      'سند',
                      textDirection: TextDirection.rtl,
                      textScaler: TextScaler.noScaling,
                      style: TextStyle(
                        fontSize: widget.size * .30,
                        fontWeight: FontWeight.w700,
                        color: widget.highContrast
                            ? Colors.white
                            : context.sanad.primary,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          builder: (context, child) {
            final breathe = math.sin(_motion.value * math.pi * 2);
            return CustomPaint(
              foregroundPainter: widget.animated
                  ? _LogoThread(
                      _motion.value,
                      onDark: widget.onDark,
                      quiet: MediaQuery.disableAnimationsOf(context),
                    )
                  : null,
              child: Transform.scale(
                scale: 1 - (1 - math.cos(_motion.value * math.pi * 2)) * .018,
                child: Transform.rotate(angle: breathe * .016, child: child),
              ),
            );
          },
        ),
      ),
    );
    if (!widget.hero) return mark;
    return Hero(
      tag: SanadLogo.heroTag,
      createRectTween: (begin, end) =>
          MaterialRectArcTween(begin: begin, end: end),
      child: mark,
    );
  }
}

/// Brand entrance while the app prepares its first page.
/// Uses the full high-contrast mark so refresh never shows an empty blue tile.
class SanadLogoIntro extends StatelessWidget {
  const SanadLogoIntro({super.key, this.size = 112});
  final double size;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'جاري فتح سند',
    liveRegion: true,
    child: SanadLogo(
      size: size,
      highContrast: true,
      animated: !MediaQuery.disableAnimationsOf(context),
    ),
  );
}

/// A travelling stitch suggests support and continuity without spinning Arabic.
class _LogoThread extends CustomPainter {
  const _LogoThread(this.progress, {required this.onDark, required this.quiet});
  final double progress;
  final bool onDark, quiet;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(size.width * .045);
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(size.width * .22)),
      );
    final paint = Paint()
      ..color = SanadPalette.accent.withValues(alpha: quiet ? .6 : .9)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = (size.width * .022).clamp(1.2, 2.4);
    final metric = path.computeMetrics().first;
    final start = (quiet ? .06 : progress) * metric.length;
    final length = metric.length * .18;
    canvas.drawPath(
      metric.extractPath(start, math.min(start + length, metric.length)),
      paint,
    );
    if (start + length > metric.length) {
      canvas.drawPath(
        metric.extractPath(0, start + length - metric.length),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_LogoThread oldDelegate) =>
      progress != oldDelegate.progress ||
      quiet != oldDelegate.quiet ||
      onDark != oldDelegate.onDark;
}

class SanadLoader extends StatelessWidget {
  const SanadLoader({
    super.key,
    this.size = 32,
    this.label,
    this.onDark = false,
  });
  final double size;
  final String? label;
  final bool onDark;

  @override
  Widget build(BuildContext context) => Semantics(
    label: label ?? 'جاري التحميل',
    liveRegion: true,
    child: ExcludeSemantics(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SanadLogo(size: size, animated: true, onDark: onDark),
          if (label != null) ...[
            const SizedBox(width: 12),
            Flexible(
              child: Text(
                label!,
                style: TextStyle(
                  color: onDark ? Colors.white : context.sanad.secondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ],
      ),
    ),
  );
}

/// A single entry gesture, never a repeating attention animation.
class SanadReveal extends StatelessWidget {
  const SanadReveal({super.key, required this.child, this.order = 0});
  final Widget child;
  final int order;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 420 + order.clamp(0, 5) * 65),
      curve: Curves.easeOutCubic,
      child: child,
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(
          offset: Offset(0, 16 * (1 - value)),
          child: child,
        ),
      ),
    );
  }
}

/// Determinate progress is reserved for real, known steps such as the form.
class SanadStepTrack extends StatelessWidget {
  const SanadStepTrack({super.key, required this.value});
  final double value;

  @override
  Widget build(BuildContext context) => Semantics(
    value: '${(value.clamp(0, 1) * 100).round()}٪',
    label: 'تقدّم الخطوات',
    child: TweenAnimationBuilder<double>(
      tween: Tween(end: value.clamp(0, 1)),
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 380),
      curve: Curves.easeInOutCubicEmphasized,
      builder: (context, progress, _) => ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          height: 5,
          child: Stack(
            children: [
              Positioned.fill(child: ColoredBox(color: context.sanad.tint)),
              FractionallySizedBox(
                widthFactor: progress,
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    gradient: LinearGradient(
                      colors: [context.sanad.primary, context.sanad.accent],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
