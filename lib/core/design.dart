import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/services.dart';
import 'sanad_brand.dart';
import 'appearance.dart';
export 'appearance.dart';
export 'sanad_brand.dart';
import 'native_bridge.dart';
import 'snad_icons.dart';
import 'web_layout.dart';
export 'snad_icons.dart';
export 'primary_button.dart';

const blue = SanadPalette.primary;
const ink = SanadPalette.ink;
const secondary = SanadPalette.secondary;
const background = SanadPalette.background;
const surface = Colors.white;
const line = SanadPalette.border;
const paleBlue = SanadPalette.tint;

/// Keep Android system buttons visible over the page without a coloured strip.
SystemUiOverlayStyle sanadSystemBars(SanadColors colors) =>
    (colors.isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark)
        .copyWith(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: colors.isDark
              ? Brightness.light
              : Brightness.dark,
          statusBarBrightness: colors.isDark
              ? Brightness.dark
              : Brightness.light,
          systemStatusBarContrastEnforced: false,
          systemNavigationBarColor: Colors.transparent,
          systemNavigationBarDividerColor: Colors.transparent,
          systemNavigationBarIconBrightness: colors.isDark
              ? Brightness.light
              : Brightness.dark,
          systemNavigationBarContrastEnforced: false,
        );

/// Frosted header: white on top into a stronger page-blue at the bottom.
/// Stops stay translucent so BackdropFilter glass reads clearly.
LinearGradient sanadHeaderGradient(SanadColors colors) {
  final soft = colors.backdropColors[1];
  final deep = colors.backdropColors.first;
  if (colors.isDark) {
    return LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        colors.surface.withValues(alpha: .72),
        soft.withValues(alpha: .58),
        deep.withValues(alpha: .78),
      ],
      stops: const [0, .4, 1],
    );
  }
  return LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      Colors.white.withValues(alpha: .56),
      soft.withValues(alpha: .38),
      deep.withValues(alpha: .58),
    ],
    stops: const [0, .36, 1],
  );
}

Color sanadHeaderTone(SanadColors colors, double t) {
  final clamped = t.clamp(0.0, 1.0);
  final gradient = sanadHeaderGradient(colors);
  final stops =
      gradient.stops ??
      List<double>.generate(
        gradient.colors.length,
        (index) => index / (gradient.colors.length - 1),
      );
  final swatch = gradient.colors;
  if (clamped <= stops.first) return swatch.first;
  for (var i = 0; i < stops.length - 1; i++) {
    final end = stops[i + 1];
    if (clamped <= end) {
      final span = end - stops[i];
      final local = span == 0 ? 0.0 : (clamped - stops[i]) / span;
      return Color.lerp(swatch[i], swatch[i + 1], local)!;
    }
  }
  return swatch.last;
}

LinearGradient sanadHeaderSlice(SanadColors colors, double from, double to) {
  final start = from.clamp(0.0, 1.0);
  final end = to.clamp(start, 1.0);
  final mid = start + (end - start) * .5;
  return LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      sanadHeaderTone(colors, start),
      sanadHeaderTone(colors, mid),
      sanadHeaderTone(colors, end),
    ],
  );
}

/// Glass header chrome shared by home strips and every AppBar.
///
/// Pass `blur: false` when nothing scrolls behind the strip (a plain AppBar or
/// a header above the list): it looks the same, while every BackdropFilter
/// re-samples the screen on each frame, which is costly on Android GPUs.
Widget sanadHeaderChrome({
  required BuildContext context,
  Widget? child,
  double from = 0,
  double to = 1,
  bool edge = true,
  bool blur = true,
  bool opaque = false,
}) {
  final colors = context.sanad;
  final slice = sanadHeaderSlice(colors, from, to);
  // Composite against a fixed theme colour, never the moving feed underneath.
  final gradient = opaque
      ? LinearGradient(
          begin: slice.begin,
          end: slice.end,
          colors: [
            for (final color in slice.colors)
              Color.alphaBlend(color, colors.backdropColors[1]),
          ],
        )
      : slice;
  final tint = DecoratedBox(
    decoration: BoxDecoration(
      gradient: gradient,
      border: edge
          ? Border(
              bottom: BorderSide(
                color: colors.border.withValues(
                  alpha: colors.isDark ? .35 : .55,
                ),
              ),
            )
          : null,
    ),
    child: child ?? const SizedBox.expand(),
  );
  if (!blur || opaque) return tint;
  return ClipRect(
    child: BackdropFilter(
      filter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
      child: tint,
    ),
  );
}

Widget sanadHeaderFill(BuildContext context, {bool blur = true}) =>
    sanadHeaderChrome(context: context, blur: blur);

/// Compact controls apply throughout the phone website, including nested routes.
bool compactWebControls(BuildContext context) =>
    kIsWeb && MediaQuery.sizeOf(context).width < WebLayout.compactMax;

const sanadActionGap = 12.0;

IconData sanadPickerIcon(String label) => switch (label) {
  'المجال' => CupertinoIcons.briefcase,
  'نوع الدوام' => CupertinoIcons.clock,
  'طريقة العمل' => CupertinoIcons.globe,
  'متطلبات الخبرة' || 'الخبرة' => Icons.school_outlined,
  'فترة الراتب' => CupertinoIcons.calendar,
  _ => CupertinoIcons.slider_horizontal_3,
};

/// Keeps separate actions apart, including after wrapping onto another line.
class SanadActions extends StatelessWidget {
  const SanadActions({
    super.key,
    required this.children,
    this.vertical = false,
    this.alignment = WrapAlignment.start,
  });

  final List<Widget> children;
  final bool vertical;
  final WrapAlignment alignment;

  @override
  Widget build(BuildContext context) => vertical
      ? Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: sanadActionGap,
          children: children,
        )
      : Wrap(
          spacing: sanadActionGap,
          runSpacing: sanadActionGap,
          crossAxisAlignment: WrapCrossAlignment.center,
          alignment: alignment,
          children: children,
        );
}

/// Stacks the actions below a heading when the viewport or text needs room.
class SanadActionHeader extends StatelessWidget {
  const SanadActionHeader({
    super.key,
    required this.title,
    this.actions = const [],
    this.minimumRowWidth = 480,
  });

  final Widget title;
  final List<Widget> actions;
  final double minimumRowWidth;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (actions.isEmpty) return title;
      final actionGroup = SanadActions(children: actions);
      final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;
      if (constraints.maxWidth < minimumRowWidth * textScale) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          spacing: sanadActionGap,
          children: [title, actionGroup],
        );
      }
      return Row(
        children: [
          Expanded(child: title),
          const SizedBox(width: sanadActionGap),
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: constraints.maxWidth * .6),
            child: actionGroup,
          ),
        ],
      );
    },
  );
}

/// Shared capsule geometry, a gentle highlight and a tactile content response.
ButtonStyle sanadButtonStyle({
  Color foreground = blue,
  Color fill = paleBlue,
  bool compact = false,
  bool dense = false,
  bool dark = false,
}) => ButtonStyle(
  minimumSize: WidgetStatePropertyAll(
    Size(dense ? 44 : (compact ? 48 : 56), dense ? 44 : (compact ? 48 : 56)),
  ),
  visualDensity: dense ? VisualDensity.standard : null,
  padding: WidgetStatePropertyAll(
    dense
        ? (compact
              ? const EdgeInsets.all(10)
              : const EdgeInsets.symmetric(horizontal: 16, vertical: 10))
        : (compact
              ? const EdgeInsets.all(12)
              : const EdgeInsets.symmetric(horizontal: 22, vertical: 15)),
  ),
  foregroundColor: WidgetStateProperty.resolveWith(
    (states) => states.contains(WidgetState.disabled)
        ? foreground.withValues(alpha: .42)
        : foreground,
  ),
  backgroundColor: WidgetStateProperty.resolveWith(
    (states) => states.contains(WidgetState.disabled)
        ? fill.withValues(alpha: .48)
        : fill,
  ),
  shape: WidgetStatePropertyAll(
    RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
  ),
  side: WidgetStateProperty.resolveWith(
    (states) => BorderSide(
      color: states.contains(WidgetState.focused)
          ? foreground
          : (dark
                ? foreground.withValues(alpha: .18)
                : Colors.white.withValues(alpha: .55)),
      width: states.contains(WidgetState.focused) ? 1.6 : 1,
    ),
  ),
  tapTargetSize: dense ? MaterialTapTargetSize.shrinkWrap : null,
  textStyle: WidgetStatePropertyAll(
    TextStyle(
      fontFamily: 'Vazirmatn',
      fontWeight: FontWeight.w700,
      fontSize: 14,
      height: dense ? 1.3 : null,
    ),
  ),
  animationDuration: const Duration(milliseconds: 220),
  overlayColor: const WidgetStatePropertyAll(Colors.transparent),
  elevation: const WidgetStatePropertyAll(0),
  mouseCursor: WidgetStateProperty.resolveWith(
    (states) => states.contains(WidgetState.disabled)
        ? SystemMouseCursors.basic
        : SystemMouseCursors.click,
  ),
  backgroundBuilder: (context, states, child) => AnimatedContainer(
    duration: MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 220),
    curve: Curves.easeOutCubic,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(24),
      gradient: LinearGradient(
        begin: Alignment.topRight,
        end: Alignment.bottomLeft,
        colors: [
          Colors.white.withValues(
            alpha: states.contains(WidgetState.pressed)
                ? .02
                : (dark ? .04 : .16),
          ),
          foreground.withValues(alpha: .055),
        ],
      ),
    ),
    child: child,
  ),
  foregroundBuilder: (context, states, child) => AnimatedScale(
    scale:
        !MediaQuery.disableAnimationsOf(context) &&
            states.contains(WidgetState.pressed)
        ? .965
        : 1,
    duration: MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 200),
    curve: Curves.easeOutCubic,
    child: child,
  ),
);

ThemeData sanadTheme({
  Brightness brightness = Brightness.light,
  bool compactWeb = false,
}) {
  final c = brightness == Brightness.dark
      ? SanadColors.dark
      : SanadColors.light;
  final onPrimary = c.isDark ? const Color(0xFF10233C) : Colors.white;
  return ThemeData(
    useMaterial3: true,
    splashFactory: NoSplash.splashFactory,
    splashColor: Colors.transparent,
    highlightColor: Colors.transparent,
    brightness: brightness,
    extensions: [c],
    fontFamily: 'Vazirmatn',
    scaffoldBackgroundColor: c.background,
    iconTheme: IconThemeData(color: c.ink),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: c.primary,
      selectionColor: c.primary.withValues(alpha: .25),
      selectionHandleColor: c.primary,
    ),
    colorScheme: ColorScheme.fromSeed(
      brightness: brightness,
      seedColor: c.primary,
      primary: c.primary,
      surface: c.surface,
      onSurface: c.ink,
      onSurfaceVariant: c.secondary,
      onPrimary: onPrimary,
      secondary: c.accent,
      outline: c.border,
      error: c.isDark ? const Color(0xFFFFABA3) : const Color(0xFFAC443B),
    ),
    textTheme: TextTheme(
      headlineLarge: TextStyle(
        fontSize: 38,
        fontWeight: FontWeight.w700,
        color: c.ink,
        height: 1.4,
      ),
      headlineSmall: TextStyle(
        fontSize: 26,
        fontWeight: FontWeight.w700,
        color: c.ink,
        height: 1.5,
      ),
      titleLarge: TextStyle(
        fontSize: 21,
        fontWeight: FontWeight.w700,
        color: c.ink,
      ),
      titleMedium: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        color: c.ink,
      ),
      bodyMedium: TextStyle(fontSize: 14, color: c.ink, height: 1.7),
      bodySmall: TextStyle(fontSize: 12, color: c.secondary, height: 1.6),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: c.surface,
      hintStyle: TextStyle(color: c.secondary),
      labelStyle: TextStyle(color: c.secondary),
      isDense: compactWeb,
      contentPadding: EdgeInsets.symmetric(
        horizontal: compactWeb ? 14 : 18,
        vertical: compactWeb ? 12 : 17,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: c.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: c.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: c.primary, width: 1.5),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: sanadButtonStyle(
        foreground: onPrimary,
        fill: c.primary,
        dark: c.isDark,
        dense: compactWeb,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: sanadButtonStyle(
        foreground: c.primary,
        fill: c.tint,
        dark: c.isDark,
        dense: compactWeb,
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: sanadButtonStyle(
        foreground: onPrimary,
        fill: c.primary,
        dark: c.isDark,
        dense: compactWeb,
      ),
    ),
    appBarTheme: AppBarTheme(
      toolbarHeight: 72,
      actionsPadding: const EdgeInsets.symmetric(vertical: 10),
      systemOverlayStyle: sanadSystemBars(c),
      backgroundColor: Colors.transparent,
      foregroundColor: c.ink,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: true,
      titleTextStyle: TextStyle(
        fontFamily: 'Vazirmatn',
        fontSize: 17,
        fontWeight: FontWeight.w700,
        color: c.ink,
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: sanadButtonStyle(
        compact: true,
        foreground: c.primary,
        fill: c.tint,
        dark: c.isDark,
        dense: compactWeb,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: sanadButtonStyle(
        foreground: c.primary,
        fill: c.tint,
        dark: c.isDark,
        dense: compactWeb,
      ),
    ),
    dividerTheme: DividerThemeData(color: c.border, thickness: 1, space: 1),
    chipTheme: ChipThemeData(
      backgroundColor: c.tint,
      selectedColor: c.primary.withValues(alpha: .18),
      labelStyle: TextStyle(
        fontFamily: 'Vazirmatn',
        color: c.primary,
        fontWeight: FontWeight.w700,
      ),
      side: BorderSide(
        color: c.isDark ? c.border : Colors.white.withValues(alpha: .65),
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    ),
  );
}

/// Calm reading surfaces keep the accent for actions and orientation.
class ReferenceBackdrop extends StatelessWidget {
  const ReferenceBackdrop({super.key, required this.child, this.dark = false});
  final Widget child;
  final bool dark;
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topRight,
        end: Alignment.bottomLeft,
        colors: dark && !context.sanad.isDark
            ? const [Color(0xFF20508A), Color(0xFF8FB1E1), Color(0xFFE7F0FA)]
            : context.sanad.backdropColors,
      ),
    ),
    child: child,
  );
}

class RoundGlassButton extends StatelessWidget {
  const RoundGlassButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.color,
  });
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final Color? color;
  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: context.sanad.surface.withValues(
        alpha: color == Colors.white ? .07 : .42,
      ),
      border: Border.all(color: context.sanad.border.withValues(alpha: .5)),
    ),
    child: IconButton(
      constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
      tooltip: tooltip,
      onPressed: onPressed,
      icon: AppIcon(icon, size: 21, color: color ?? context.sanad.ink),
    ),
  );
}

/// Reading cards stay opaque: glass is reserved for native navigation.
class Glass extends StatelessWidget {
  const Glass({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.radius = 24,
    this.opacity = 1,
  });
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius, opacity;
  @override
  Widget build(BuildContext context) => Material(
    color: context.sanad.surface,
    clipBehavior: Clip.antiAlias,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radius),
      side: BorderSide(color: context.sanad.border),
    ),
    child: Padding(padding: padding, child: child),
  );
}

class NativeIcon extends StatelessWidget {
  const NativeIcon(
    this.symbol, {
    super.key,
    required this.fallback,
    this.color,
    this.size = 22,
  });
  final String symbol;
  final IconData fallback;
  final Color? color;
  final double size;
  @override
  Widget build(BuildContext context) {
    final iconColor = color ?? context.sanad.ink;
    final original = SnadIcon.forSymbol(symbol);
    if (original != null) {
      return SnadIcon(
        original,
        size: size,
        color: iconColor,
        filled: symbol.endsWith('.fill'),
      );
    }
    return FutureBuilder(
      future: NativeBridge.symbol(symbol, size: size, color: iconColor),
      builder: (context, snapshot) => snapshot.data == null
          ? AppIcon(fallback, color: iconColor, size: size)
          : Image.memory(
              snapshot.data!,
              width: size,
              height: size,
              gaplessPlayback: true,
            ),
    );
  }
}

class AnimatedSaveIcon extends StatefulWidget {
  const AnimatedSaveIcon({super.key, required this.saved, this.size = 22});
  final bool saved;
  final double size;
  @override
  State<AnimatedSaveIcon> createState() => _AnimatedSaveIconState();
}

class _AnimatedSaveIconState extends State<AnimatedSaveIcon>
    with SingleTickerProviderStateMixin {
  late final _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 520),
    value: 1,
  );

  @override
  void didUpdateWidget(AnimatedSaveIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.saved != widget.saved &&
        !MediaQuery.disableAnimationsOf(context)) {
      _pulse.forward(from: 0);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) _pulse.value = 1;
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _pulse,
    child: SnadIcon(
      'heart',
      filled: widget.saved,
      color: widget.saved ? context.sanad.primary : context.sanad.ink,
      size: widget.size,
    ),
    builder: (context, child) {
      final t = _pulse.value;
      final wave = math.sin(t * math.pi);
      return SizedBox.square(
        dimension: widget.size,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            if (widget.saved && t < 1)
              Positioned.fill(
                child: Transform.scale(
                  scale: 1 + t * 1.15,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: context.sanad.primary.withValues(
                          alpha: (1 - t) * .45,
                        ),
                        width: 1.6,
                      ),
                    ),
                  ),
                ),
              ),
            Transform.scale(scale: 1 + wave * .17, child: child),
          ],
        ),
      );
    },
  );
}

class OpportunityMotion extends StatelessWidget {
  const OpportunityMotion({super.key, this.size = 100});
  final double size;
  @override
  Widget build(BuildContext context) => SanadLogo(size: size);
}

class Pressable extends StatefulWidget {
  const Pressable({super.key, required this.child, required this.onTap});
  final Widget child;
  final VoidCallback onTap;
  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool down = false;
  bool focused = false;
  bool hovered = false;
  @override
  Widget build(BuildContext context) => FocusableActionDetector(
    mouseCursor: SystemMouseCursors.click,
    onShowFocusHighlight: (value) => setState(() => focused = value),
    onShowHoverHighlight: (value) => setState(() => hovered = value),
    actions: <Type, Action<Intent>>{
      ActivateIntent: CallbackAction<ActivateIntent>(
        onInvoke: (_) {
          widget.onTap();
          return null;
        },
      ),
    },
    child: GestureDetector(
      onTapDown: (_) => setState(() => down = true),
      onTapCancel: () => setState(() => down = false),
      onTapUp: (_) => setState(() => down = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: MediaQuery.disableAnimationsOf(context)
            ? 1
            : down
            ? .978
            : (hovered ? 1.006 : 1),
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 150),
        curve: Curves.easeOutCubic,
        child: DecoratedBox(
          position: DecorationPosition.foreground,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(35),
            border: focused
                ? Border.all(color: context.sanad.primary, width: 2)
                : null,
          ),
          child: widget.child,
        ),
      ),
    ),
  );
}

IconData categoryIcon(String category) => switch (category) {
  'تقنية' => Icons.code_rounded,
  'تصميم' => Icons.auto_awesome_rounded,
  'تسويق' => Icons.campaign_outlined,
  'مبيعات' => Icons.storefront_outlined,
  'مطاعم وضيافة' => Icons.local_cafe_outlined,
  'حِرف ومهن' => Icons.handyman_outlined,
  'إدارة ومحاسبة' => Icons.account_balance_outlined,
  'تعليم' => Icons.school_outlined,
  'صحة' => Icons.medical_services_outlined,
  _ => Icons.work_outline_rounded,
};

Color categoryColor(String category) => switch (category) {
  'تقنية' => blue,
  'تصميم' => const Color(0xFF6874A0),
  'تسويق' => const Color(0xFF857449),
  'مبيعات' => const Color(0xFF3B82B8),
  'مطاعم وضيافة' => const Color(0xFF8D7362),
  _ => const Color(0xFF577395),
};

/// Original industry marks: these never imply a real company endorsement.
class CompanyMark extends StatelessWidget {
  const CompanyMark(this.category, {super.key, this.size = 48});
  final String category;
  final double size;
  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: context.sanad.surface,
      shape: BoxShape.circle,
    ),
    padding: EdgeInsets.all(size * .22),
    child: CustomPaint(
      painter: _IndustryMark(category, dark: context.sanad.isDark),
    ),
  );
}

class _IndustryMark extends CustomPainter {
  const _IndustryMark(this.category, {required this.dark});
  final String category;
  final bool dark;
  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final colors = [
      dark
          ? Color.lerp(categoryColor(category), Colors.white, .4)!
          : categoryColor(category),
      const Color(0xFF4A8BD9),
      const Color(0xFF9CC9FA),
      const Color(0xFF6E83B8),
    ];
    if (category == 'تقنية') {
      for (var i = 0; i < 4; i++) {
        final paint = Paint()
          ..color = colors[i]
          ..style = PaintingStyle.stroke
          ..strokeWidth = size.width * .2
          ..strokeCap = StrokeCap.round;
        canvas.drawArc(
          Rect.fromCircle(center: center, radius: size.width * .34),
          i * math.pi / 2 + .10,
          math.pi / 2 - .26,
          false,
          paint,
        );
      }
      canvas.drawCircle(
        center,
        size.width * .09,
        Paint()..color = colors.first,
      );
    } else {
      for (var i = 0; i < 4; i++) {
        canvas.save();
        canvas.translate(center.dx, center.dy);
        canvas.rotate(i * math.pi / 2);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(
              size.width * .03,
              size.width * .03,
              size.width * .4,
              size.width * .4,
            ),
            Radius.circular(size.width * (i.isEven ? .18 : .035)),
          ),
          Paint()..color = colors[i],
        );
        canvas.restore();
      }
    }
  }

  @override
  bool shouldRepaint(_IndustryMark oldDelegate) =>
      oldDelegate.category != category || oldDelegate.dark != dark;
}

class AppTag extends StatelessWidget {
  const AppTag(
    this.text, {
    super.key,
    this.icon,
    this.color,
    this.light = false,
  });
  final String text;
  final IconData? icon;
  final Color? color;
  final bool light;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
    decoration: BoxDecoration(
      color: light ? Colors.white.withValues(alpha: .12) : context.sanad.tint,
      borderRadius: BorderRadius.circular(30),
      border: Border.all(
        color: light ? Colors.white.withValues(alpha: .30) : context.sanad.tint,
      ),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          AppIcon(
            icon,
            color: light ? Colors.white : color ?? context.sanad.secondary,
            size: 13,
          ),
          const SizedBox(width: 5),
        ],
        Flexible(
          child: Text(
            text,
            style: TextStyle(
              color: light ? Colors.white : color ?? context.sanad.secondary,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    ),
  );
}

/// Desktop/web scrolling with mouse drag and trackpad, matching mobile feel.
class SanadScrollBehavior extends MaterialScrollBehavior {
  const SanadScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.trackpad,
    PointerDeviceKind.stylus,
  };

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) {
    if (kIsWeb ||
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux) {
      return const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      );
    }
    return super.getScrollPhysics(context);
  }
}
