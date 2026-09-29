import 'package:flutter/widgets.dart';

/// Breakpoints for the Sanad website shell (Flutter web only).
enum WebBreakpoint { compact, medium, expanded }

abstract final class WebLayout {
  static const compactMax = 720.0;
  static const mediumMax = 1100.0;
  static const contentMax = 1200.0;
  static const readingMax = 880.0;
  static const formMax = 760.0;

  static WebBreakpoint of(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width < compactMax) return WebBreakpoint.compact;
    if (width < mediumMax) return WebBreakpoint.medium;
    return WebBreakpoint.expanded;
  }

  static int jobColumns(WebBreakpoint breakpoint) => switch (breakpoint) {
    WebBreakpoint.compact => 1,
    WebBreakpoint.medium => 2,
    WebBreakpoint.expanded => 3,
  };

  static EdgeInsets pagePadding(WebBreakpoint breakpoint) =>
      switch (breakpoint) {
        WebBreakpoint.compact => const EdgeInsets.symmetric(horizontal: 20),
        WebBreakpoint.medium => const EdgeInsets.symmetric(horizontal: 32),
        WebBreakpoint.expanded => const EdgeInsets.symmetric(horizontal: 40),
      };

  static double gutter(WebBreakpoint breakpoint) =>
      breakpoint == WebBreakpoint.compact ? 14 : 18;
}
