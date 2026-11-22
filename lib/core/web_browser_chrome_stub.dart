import 'package:flutter/widgets.dart';

/// No-op outside the browser.
class WebBrowserChrome {
  WebBrowserChrome._();

  /// Sync Safari/Chrome toolbar colors with the active Sanad surface.
  static void apply({required bool isDark, required String headerColor}) {}

  static Widget wrap(Widget child) => child;
}
