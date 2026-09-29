import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'design.dart';

Duration motionDuration(BuildContext context, [int milliseconds = 280]) =>
    MediaQuery.disableAnimationsOf(context)
    ? Duration.zero
    : Duration(milliseconds: milliseconds);

/// Reduced motion bypasses the animated render object entirely. A zero-duration
/// AnimatedSize can otherwise notify its controller during its own layout.
class MotionSize extends StatelessWidget {
  const MotionSize({
    super.key,
    required this.duration,
    this.curve = Curves.linear,
    this.alignment = Alignment.center,
    required this.child,
  });

  final Duration duration;
  final Curve curve;
  final AlignmentGeometry alignment;
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      duration == Duration.zero || MediaQuery.disableAnimationsOf(context)
      ? child
      : AnimatedSize(
          duration: duration,
          curve: curve,
          alignment: alignment,
          child: child,
        );
}

/// A regular page keeps the task and its back path clear, without a modal layer.
Future<T?> openPage<T>(BuildContext context, Widget page) {
  final direction = Directionality.of(context) == TextDirection.rtl
      ? -1.0
      : 1.0;
  return Navigator.of(context).push<T>(
    PageRouteBuilder<T>(
      transitionDuration: motionDuration(context, 380),
      reverseTransitionDuration: motionDuration(context, 300),
      pageBuilder: (_, _, _) => page,
      transitionsBuilder: (_, animation, _, child) {
        final progress = animation.drive(
          CurveTween(curve: Curves.easeOutQuart),
        );
        return FadeTransition(
          opacity: progress,
          child: SlideTransition(
            position: progress.drive(
              Tween(begin: Offset(direction * .035, 0), end: Offset.zero),
            ),
            child: child,
          ),
        );
      },
    ),
  );
}

/// Soft fade between welcome and home so the brand [Hero] can fly with it.
class SanadFadePage<T> extends Page<T> {
  const SanadFadePage({required super.key, required this.child, super.name});

  final Widget child;

  @override
  Route<T> createRoute(BuildContext context) => PageRouteBuilder<T>(
    settings: this,
    transitionDuration: motionDuration(context, 520),
    reverseTransitionDuration: motionDuration(context, 380),
    pageBuilder: (context, animation, secondaryAnimation) => child,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final fade = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(opacity: fade, child: child);
    },
  );
}

/// ScrollController.animateTo rejects zero duration; reduced motion must jump.
Future<void> animateScrollTo(
  BuildContext context,
  ScrollController controller,
  double offset, {
  int milliseconds = 280,
}) async {
  if (!controller.hasClients) return;
  final target = offset.clamp(
    controller.position.minScrollExtent,
    controller.position.maxScrollExtent,
  );
  final duration = motionDuration(context, milliseconds);
  if (duration == Duration.zero) {
    controller.jumpTo(target);
    return;
  }
  await controller.animateTo(
    target,
    duration: duration,
    curve: Curves.easeOutCubic,
  );
}

/// A pinned surface always fills its extent, including fixed-height headers.
class MorphHeader extends SliverPersistentHeaderDelegate {
  MorphHeader({
    required this.expanded,
    required this.collapsed,
    required this.builder,
  }) : assert(expanded >= collapsed),
       assert(collapsed >= 0);
  final double expanded, collapsed;
  final Widget Function(BuildContext, double) builder;
  @override
  double get minExtent => collapsed;
  @override
  double get maxExtent => expanded;
  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final progress = expanded == collapsed
        ? (overlapsContent ? 1.0 : 0.0)
        : (shrinkOffset / (expanded - collapsed)).clamp(0.0, 1.0);
    return ClipRect(child: SizedBox.expand(child: builder(context, progress)));
  }

  @override
  bool shouldRebuild(covariant MorphHeader oldDelegate) =>
      oldDelegate.expanded != expanded ||
      oldDelegate.collapsed != collapsed ||
      oldDelegate.builder != builder;
}

class CardSnapshot {
  CardSnapshot(this.image, this.rect);
  final ui.Image image;
  final Rect rect;

  /// Call before fading, removing, or replacing the source card.
  static Future<CardSnapshot?> capture(GlobalKey key) async {
    await WidgetsBinding.instance.endOfFrame;
    final render = key.currentContext?.findRenderObject();
    if (render is! RenderRepaintBoundary ||
        !render.attached ||
        !render.hasSize ||
        render.size.isEmpty ||
        (kDebugMode && render.debugNeedsPaint)) {
      return null;
    }
    try {
      final rect = Rect.fromPoints(
        render.localToGlobal(Offset.zero),
        render.localToGlobal(render.size.bottomRight(Offset.zero)),
      );
      final image = await render.toImage(pixelRatio: 1.5);
      return CardSnapshot(image, rect);
    } catch (_) {
      // A recycled list item can disappear between a tap and the next paint.
      return null;
    }
  }
}

/// The captured card retains its proportions throughout both transitions.
class _SnapshotSurface extends StatelessWidget {
  const _SnapshotSurface(this.image);
  final ui.Image image;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (_, constraints) {
      final width = constraints.maxWidth;
      final height = width * image.height / image.width;
      return OverflowBox(
        alignment: Alignment.topCenter,
        minWidth: width,
        maxWidth: width,
        minHeight: height,
        maxHeight: height,
        child: RawImage(
          image: image,
          width: width,
          height: height,
          fit: BoxFit.fill,
        ),
      );
    },
  );
}

class _ContainerClip extends CustomClipper<Path> {
  const _ContainerClip(this.rect, this.radius);
  final Rect rect;
  final double radius;
  @override
  Path getClip(Size size) =>
      Path()..addRRect(RRect.fromRectAndRadius(rect, Radius.circular(radius)));
  @override
  bool shouldReclip(_ContainerClip oldClipper) =>
      rect != oldClipper.rect || radius != oldClipper.radius;
}

Future<void> openFromCard(
  BuildContext context,
  GlobalKey? key,
  Widget page,
) async {
  final reduceMotion = MediaQuery.disableAnimationsOf(context);
  final snapshot = key == null || reduceMotion
      ? null
      : await CardSnapshot.capture(key);
  if (!context.mounted) {
    snapshot?.image.dispose();
    return;
  }
  final route = PageRouteBuilder<void>(
    transitionDuration: motionDuration(context, 360),
    reverseTransitionDuration: motionDuration(context, 280),
    pageBuilder: (_, _, _) => page,
    transitionsBuilder: (context, animation, _, child) => LayoutBuilder(
      builder: (context, constraints) => AnimatedBuilder(
        animation: animation,
        builder: (context, _) {
          if (snapshot == null ||
              (animation.status == AnimationStatus.reverse &&
                  key?.currentContext == null)) {
            return FadeTransition(opacity: animation, child: child);
          }
          final t = Curves.easeInOutCubicEmphasized.transform(animation.value);
          final full = Offset.zero & constraints.biggest;
          final render = context.findRenderObject();
          final origin = render is RenderBox && render.attached
              ? render.localToGlobal(Offset.zero)
              : Offset.zero;
          final source = snapshot.rect.shift(-origin);
          final rect = Rect.lerp(source, full, t)!;
          final radius = 26 * (1 - t);
          return ClipPath(
            clipper: _ContainerClip(rect, radius),
            child: Stack(
              fit: StackFit.expand,
              children: [
                ColoredBox(color: context.sanad.background),
                // Only the mask changes size. The page always lays out at its
                // final viewport, so text and sticky controls cannot reflow.
                Opacity(
                  opacity: ((t - .08) / .48).clamp(0.0, 1.0),
                  child: child,
                ),
                if (t < .48)
                  Positioned.fromRect(
                    rect: rect,
                    child: Opacity(
                      opacity: (1 - t / .48).clamp(0.0, 1.0),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(radius),
                        child: _SnapshotSurface(snapshot.image),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    ),
  );
  try {
    await Navigator.of(context).push(route);
    // Popping resolves push before the reverse transition has finished.
    await route.completed;
  } finally {
    snapshot?.image.dispose();
  }
}

/// Persistent inline feedback, announced to assistive technology and never timed.
class SignalCard extends StatelessWidget {
  const SignalCard(
    this.message, {
    super.key,
    this.onClose,
    this.action,
    this.actionLabel = 'حاول مجدداً',
  });
  final String message, actionLabel;
  final VoidCallback? onClose, action;
  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    liveRegion: true,
    child: Material(
      color: context.sanad.tint,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: context.sanad.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(14, 14, 10, 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: AppIcon(
                Icons.info_outline_rounded,
                color: context.sanad.primary,
                size: 22,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    message,
                    style: TextStyle(
                      color: context.sanad.ink,
                      fontSize: 14,
                      height: 1.6,
                    ),
                  ),
                  if (action != null) ...[
                    const SizedBox(height: 2),
                    TextButton(
                      onPressed: action,
                      style: TextButton.styleFrom(
                        minimumSize: const Size(44, 44),
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        alignment: AlignmentDirectional.centerStart,
                      ),
                      child: Text(actionLabel),
                    ),
                  ],
                ],
              ),
            ),
            if (onClose != null)
              IconButton(
                onPressed: onClose,
                tooltip: 'إغلاق الملاحظة',
                constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                icon: AppIcon(
                  Icons.close,
                  color: context.sanad.primary,
                  size: 18,
                ),
              ),
          ],
        ),
      ),
    ),
  );
}
