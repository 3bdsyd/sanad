import 'package:flutter/material.dart';

/// Semantic colors for the system appearance; artwork keeps its brand palette.
@immutable
class SanadColors extends ThemeExtension<SanadColors> {
  const SanadColors({
    required this.isDark,
    required this.primary,
    required this.ink,
    required this.secondary,
    required this.background,
    required this.surface,
    required this.border,
    required this.tint,
    required this.accent,
    required this.fieldFill,
    required this.backdropColors,
  });

  static const light = SanadColors(
    isDark: false,
    primary: Color(0xFF20508A),
    ink: Color(0xFF12233F),
    secondary: Color(0xFF577395),
    background: Color(0xFFF2F7FC),
    surface: Color(0xFFFFFFFF),
    border: Color(0xFFDCE8F5),
    tint: Color(0xFFE7F0FA),
    accent: Color(0xFF9CC9FA),
    fieldFill: Color(0xFFE2EFFB),
    backdropColors: [Color(0xFF8FB1E1), Color(0xFFB6D1EE), Color(0xFFF2F7FC)],
  );
  static const dark = SanadColors(
    isDark: true,
    primary: Color(0xFF95C3FF),
    ink: Color(0xFFECF3FF),
    secondary: Color(0xFFAABCD3),
    background: Color(0xFF0D1523),
    surface: Color(0xFF172435),
    border: Color(0xFF30465F),
    tint: Color(0xFF20344E),
    accent: Color(0xFFB9D7FF),
    fieldFill: Color(0xFF20334B),
    backdropColors: [Color(0xFF1C3554), Color(0xFF14263C), Color(0xFF0D1523)],
  );
  final bool isDark;
  final Color primary,
      ink,
      secondary,
      background,
      surface,
      border,
      tint,
      accent,
      fieldFill;
  final List<Color> backdropColors;

  @override
  SanadColors copyWith({
    bool? isDark,
    Color? primary,
    Color? ink,
    Color? secondary,
    Color? background,
    Color? surface,
    Color? border,
    Color? tint,
    Color? accent,
    Color? fieldFill,
    List<Color>? backdropColors,
  }) => SanadColors(
    isDark: isDark ?? this.isDark,
    primary: primary ?? this.primary,
    ink: ink ?? this.ink,
    secondary: secondary ?? this.secondary,
    background: background ?? this.background,
    surface: surface ?? this.surface,
    border: border ?? this.border,
    tint: tint ?? this.tint,
    accent: accent ?? this.accent,
    fieldFill: fieldFill ?? this.fieldFill,
    backdropColors: backdropColors ?? this.backdropColors,
  );

  @override
  SanadColors lerp(covariant SanadColors? other, double t) {
    if (other == null) return this;
    return SanadColors(
      isDark: t < .5 ? isDark : other.isDark,
      primary: Color.lerp(primary, other.primary, t)!,
      ink: Color.lerp(ink, other.ink, t)!,
      secondary: Color.lerp(secondary, other.secondary, t)!,
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      border: Color.lerp(border, other.border, t)!,
      tint: Color.lerp(tint, other.tint, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      fieldFill: Color.lerp(fieldFill, other.fieldFill, t)!,
      backdropColors: [
        for (var i = 0; i < backdropColors.length; i++)
          Color.lerp(backdropColors[i], other.backdropColors[i], t)!,
      ],
    );
  }
}

extension SanadThemeContext on BuildContext {
  SanadColors get sanad =>
      Theme.of(this).extension<SanadColors>() ??
      (Theme.of(this).brightness == Brightness.dark
          ? SanadColors.dark
          : SanadColors.light);
}
