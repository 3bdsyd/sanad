import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'fursa_icon_paths.dart';

/// Sanad Soft Line artwork on a 24-unit grid, shared with native UIKit.
/// The class name stays stable for existing application callers.
class FursaIcon extends StatelessWidget {
  const FursaIcon(
    this.name, {
    super.key,
    this.size = 24,
    this.color,
    this.filled = false,
    this.matchTextDirection = false,
  });
  final String name;
  final double size;
  final Color? color;
  final bool filled;
  final bool matchTextDirection;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Center(
      widthFactor: 1,
      heightFactor: 1,
      child: SizedBox.square(
        dimension: size,
        child: CustomPaint(
          painter: _FursaIconPainter(
            name,
            color ?? IconTheme.of(context).color ?? const Color(0xFF12233F),
            filled,
            matchTextDirection &&
                Directionality.of(context) == TextDirection.rtl,
          ),
        ),
      ),
    ),
  );

  static String? forSymbol(String symbol) => switch (symbol) {
    'house' || 'house.fill' => 'home',
    'heart' || 'heart.fill' => 'heart',
    'plus' => 'plus',
    'bell' => 'bell',
    'magnifyingglass' => 'search',
    'slider.horizontal.3' => 'filter',
    'mappin.and.ellipse' => 'pin',
    'arrow.up.right' => 'arrowUpRight',
    'arrow.up.left' => 'arrowUpLeft',
    'ellipsis' => 'more',
    'sparkle' || 'sparkles' => 'sparkles',
    'briefcase' || 'briefcase.fill' => 'briefcase',
    'envelope' => 'mail',
    'phone' => 'phone',
    'calendar' => 'calendar',
    'bookmark' || 'bookmark.fill' => 'bookmark',
    'checkmark' => 'check',
    'arrow.clockwise' => 'refresh',
    _ => null,
  };
}

/// Adapts the existing action contracts to the original vector family.
class AppIcon extends StatelessWidget {
  const AppIcon(
    this.icon, {
    super.key,
    this.color,
    this.size,
    this.semanticLabel,
  });
  final IconData? icon;
  final Color? color;
  final double? size;
  final String? semanticLabel;

  static String? nameOf(IconData? icon) => switch (icon) {
    CupertinoIcons.house || Icons.home_outlined => 'home',
    CupertinoIcons.heart ||
    CupertinoIcons.heart_fill ||
    Icons.favorite_rounded => 'heart',
    CupertinoIcons.plus ||
    CupertinoIcons.plus_app ||
    Icons.add ||
    Icons.add_circle_outline => 'plus',
    CupertinoIcons.bell => 'bell',
    CupertinoIcons.search || Icons.search_rounded => 'search',
    Icons.saved_search => 'savedSearch',
    CupertinoIcons.slider_horizontal_3 || Icons.tune_rounded => 'filter',
    CupertinoIcons.location || Icons.location_on_outlined => 'pin',
    CupertinoIcons.arrow_up_right ||
    Icons.arrow_outward_rounded => 'arrowUpRight',
    CupertinoIcons.arrow_up_left => 'arrowUpLeft',
    Icons.arrow_forward_rounded => 'arrowRight',
    CupertinoIcons.chevron_right => 'chevronRight',
    CupertinoIcons.chevron_left || Icons.chevron_left => 'chevronLeft',
    Icons.expand_more || CupertinoIcons.chevron_down => 'chevronDown',
    CupertinoIcons.chevron_up => 'chevronUp',
    CupertinoIcons.xmark || Icons.close => 'close',
    CupertinoIcons.xmark_circle_fill => 'closeCircle',
    CupertinoIcons.clock => 'clock',
    CupertinoIcons.sparkles ||
    Icons.auto_awesome_rounded ||
    Icons.spa_outlined => 'sparkles',
    Icons.tips_and_updates_outlined => 'hint',
    CupertinoIcons.info_circle ||
    Icons.info_outline ||
    Icons.info_outline_rounded => 'info',
    CupertinoIcons.briefcase || Icons.work_outline_rounded => 'briefcase',
    CupertinoIcons.checkmark || Icons.done_rounded => 'check',
    CupertinoIcons.checkmark_circle ||
    CupertinoIcons.checkmark_circle_fill ||
    Icons.check_circle_outline ||
    Icons.check_circle_outline_rounded => 'checkCircle',
    CupertinoIcons.refresh || Icons.refresh_rounded => 'refresh',
    CupertinoIcons.globe || Icons.public || Icons.explore_outlined => 'globe',
    CupertinoIcons.bookmark ||
    Icons.bookmark_border_rounded ||
    Icons.bookmark_rounded ||
    Icons.bookmark_add_outlined => 'bookmark',
    CupertinoIcons.lock_shield || Icons.privacy_tip_outlined => 'shield',
    Icons.support_agent_rounded => 'support',
    Icons.code_rounded => 'code',
    Icons.storefront_outlined => 'store',
    Icons.local_cafe_outlined => 'coffee',
    Icons.school_outlined => 'education',
    Icons.medical_services_outlined => 'health',
    Icons.account_balance_outlined => 'chart',
    Icons.campaign_outlined => 'megaphone',
    CupertinoIcons.wifi_slash || Icons.cloud_off_outlined => 'cloudOff',
    CupertinoIcons.ellipsis_vertical => 'moreVertical',
    CupertinoIcons.ellipsis => 'more',
    CupertinoIcons.envelope => 'mail',
    CupertinoIcons.phone => 'phone',
    CupertinoIcons.calendar => 'calendar',
    CupertinoIcons.chat_bubble || CupertinoIcons.chat_bubble_2_fill => 'chat',
    CupertinoIcons.doc_text => 'document',
    CupertinoIcons.square_grid_2x2 => 'grid',
    CupertinoIcons.circle || CupertinoIcons.circle_fill => 'circle',
    Icons.handyman_outlined => 'craft',
    Icons.visibility_off_outlined => 'eyeOff',
    Icons.copy_rounded => 'copy',
    Icons.flag_outlined => 'flag',
    _ => null,
  };

  @override
  Widget build(BuildContext context) {
    final name = nameOf(icon);
    final child = name == null
        ? Icon(icon, color: color, size: size)
        : FursaIcon(
            name,
            color: color,
            matchTextDirection: icon?.matchTextDirection ?? false,
            size: size ?? IconTheme.of(context).size ?? 24,
            filled:
                icon == CupertinoIcons.heart_fill ||
                icon == Icons.favorite_rounded ||
                icon == CupertinoIcons.circle_fill ||
                icon == Icons.bookmark_rounded,
          );
    return semanticLabel == null
        ? child
        : Semantics(label: semanticLabel, child: child);
  }
}

class _FursaIconPainter extends CustomPainter {
  const _FursaIconPainter(this.name, this.color, this.filled, this.mirror);
  final String name;
  final Color color;
  final bool filled;
  final bool mirror;
  static final Map<String, Path> _cache = {};

  static Path _path(String source) {
    final tokens = RegExp(
      r'[MLHVQCZ]|-?\d+(?:\.\d+)?',
    ).allMatches(source).map((match) => match.group(0)!).toList();
    final path = Path();
    var i = 0;
    var x = 0.0;
    var y = 0.0;
    double number() => double.parse(tokens[i++]);
    while (i < tokens.length) {
      switch (tokens[i++]) {
        case 'M':
          x = number();
          y = number();
          path.moveTo(x, y);
        case 'L':
          x = number();
          y = number();
          path.lineTo(x, y);
        case 'H':
          x = number();
          path.lineTo(x, y);
        case 'V':
          y = number();
          path.lineTo(x, y);
        case 'C':
          final x1 = number(), y1 = number(), x2 = number(), y2 = number();
          x = number();
          y = number();
          path.cubicTo(x1, y1, x2, y2, x, y);
        case 'Q':
          final x1 = number(), y1 = number();
          x = number();
          y = number();
          path.quadraticBezierTo(x1, y1, x, y);
        case 'Z':
          path.close();
      }
    }
    return path;
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 24, size.height / 24);
    if (mirror) {
      canvas.translate(24, 0);
      canvas.scale(-1, 1);
    }
    final source = fursaIconPaths[name];
    if (source == null) return;
    final accent = fursaIconAccents[name];
    if (!filled && accent != null) {
      canvas.drawPath(
        _cache.putIfAbsent('$name.accent', () => _path(accent)),
        Paint()
          ..color = color.withValues(alpha: color.a * fursaIconAccentOpacity)
          ..style = PaintingStyle.fill,
      );
    }
    final path = _cache.putIfAbsent(name, () => _path(source));
    // Filling an open symbol (e.g. home/briefcase) creates accidental wedges.
    // Only closed, single-silhouette glyphs have a solid selected state.
    if (filled && const {'heart', 'bookmark', 'circle'}.contains(name)) {
      canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..style = PaintingStyle.fill,
      );
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..strokeWidth = fursaIconStrokeWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(_FursaIconPainter oldDelegate) =>
      oldDelegate.name != name ||
      oldDelegate.color != color ||
      oldDelegate.filled != filled ||
      oldDelegate.mirror != mirror;
}
