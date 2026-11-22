import 'package:flutter/widgets.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/rendering.dart' show ScrollDirection;

/// Reveal the complete, naturally sized header as one surface. Scroll speed
/// never stretches it or drags a clipped capsule across the fixed app bar.
class FeedScrollHeader extends StatefulWidget {
  const FeedScrollHeader({
    super.key,
    required this.searchFocused,
    required this.child,
    this.onExtentChanged,
    this.visibility,
  });

  final bool searchFocused;
  final Widget child;
  final ValueChanged<double>? onExtentChanged;
  final ValueListenable<bool>? visibility;

  @override
  State<FeedScrollHeader> createState() => _FeedScrollHeaderState();
}

class _FeedScrollHeaderState extends State<FeedScrollHeader> {
  final _contentKey = GlobalKey();
  double? _reportedExtent;
  double? _lastOffset;
  double _directionDistance = 0;
  ScrollDirection _direction = ScrollDirection.idle;
  bool _visible = true;

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final render = _contentKey.currentContext?.findRenderObject();
      if (render is RenderBox &&
          render.hasSize &&
          render.size.height != _reportedExtent) {
        _reportedExtent = render.size.height;
        widget.onExtentChanged?.call(render.size.height);
      }
    });
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return SliverLayoutBuilder(
      builder: (context, constraints) {
        final offset = constraints.scrollOffset;
        final delta = _lastOffset == null ? 0.0 : offset - _lastOffset!;
        if (_lastOffset == null) _visible = offset <= 0;
        _lastOffset = offset;
        if (widget.searchFocused || offset <= (_reportedExtent ?? 0)) {
          _visible = true;
          _directionDistance = 0;
        } else if (delta.abs() > .01) {
          final direction = delta < 0
              ? ScrollDirection.forward
              : ScrollDirection.reverse;
          if (_direction != direction) {
            _direction = direction;
            _directionDistance = 0;
          }
          _directionDistance += delta.abs();
          if (_directionDistance >= 4) {
            _visible = _direction == ScrollDirection.forward;
          }
        }
        Widget surface(bool visible) {
          final duration = reduceMotion
              ? Duration.zero
              : Duration(milliseconds: visible ? 320 : 220);
          return IgnorePointer(
            ignoring: !visible,
            child: ExcludeSemantics(
              excluding: !visible,
              child: AnimatedSlide(
                offset: visible ? Offset.zero : const Offset(0, -.08),
                duration: duration,
                curve: Curves.easeInOutCubic,
                child: AnimatedOpacity(
                  opacity: visible ? 1 : 0,
                  duration: duration,
                  curve: Curves.easeInOutCubic,
                  child: KeyedSubtree(key: _contentKey, child: widget.child),
                ),
              ),
            ),
          );
        }

        return PinnedHeaderSliver(
          child: widget.visibility == null
              ? surface(_visible)
              : ValueListenableBuilder<bool>(
                  valueListenable: widget.visibility!,
                  builder: (context, visible, _) => surface(visible),
                ),
        );
      },
    );
  }
}
