import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Keeps the scroll viewport behind the glass navigation while reserving an
/// empty, non-interactive band for the banner above it. Scaffold.extendBody
/// supplies the measured banner + navigation height through MediaQuery.
class AdSeparatedContent extends StatelessWidget {
  const AdSeparatedContent({
    super.key,
    required this.bannerExtent,
    required this.child,
  });

  final double bannerExtent;
  final Widget child;

  @override
  Widget build(BuildContext context) => _ContentBand(
    bannerExtent: bannerExtent,
    footerExtent: MediaQuery.paddingOf(context).bottom,
    child: child,
  );
}

class _ContentBand extends SingleChildRenderObjectWidget {
  const _ContentBand({
    required this.bannerExtent,
    required this.footerExtent,
    required super.child,
  });

  final double bannerExtent, footerExtent;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderContentBand(bannerExtent, footerExtent);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderContentBand renderObject,
  ) {
    renderObject.update(bannerExtent, footerExtent);
  }
}

class _RenderContentBand extends RenderProxyBox {
  _RenderContentBand(this._bannerExtent, this._footerExtent);

  double _bannerExtent, _footerExtent;

  void update(double bannerExtent, double footerExtent) {
    if (_bannerExtent == bannerExtent && _footerExtent == footerExtent) return;
    _bannerExtent = bannerExtent;
    _footerExtent = footerExtent;
    markNeedsPaint();
    markNeedsSemanticsUpdate();
  }

  bool get _hasBanner => _bannerExtent > 0;
  double get _bandTop => math.max(0, size.height - _footerExtent);
  double get _bandBottom => math.min(size.height, _bandTop + _bannerExtent);

  @override
  void paint(PaintingContext context, Offset offset) {
    if (!_hasBanner) {
      super.paint(context, offset);
      return;
    }
    // Paint once, including platform views, with a real gap for the banner.
    // The lower strip is only a backdrop for navigation, never a tap target.
    final visible = Path()
      ..addRect(Rect.fromLTRB(0, 0, size.width, _bandTop))
      ..addRect(Rect.fromLTRB(0, _bandBottom, size.width, size.height));
    context.pushClipPath(
      needsCompositing,
      offset,
      Offset.zero & size,
      visible,
      super.paint,
      clipBehavior: Clip.hardEdge,
    );
  }

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) =>
      (!_hasBanner || position.dy < _bandTop) &&
      super.hitTest(result, position: position);

  @override
  Rect? describeSemanticsClip(RenderObject? child) => _hasBanner
      ? Rect.fromLTRB(0, 0, size.width, _bandTop)
      : super.describeSemanticsClip(child);
}
