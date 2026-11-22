import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// User appearance choice: follows the device, or pins light / dark.
class SanadThemeController extends ChangeNotifier {
  static const prefsKey = 'snad.theme.mode';

  ThemeMode _mode = ThemeMode.system;
  ThemeMode get mode => _mode;

  Future<void> load() async {
    final preferences = await SharedPreferences.getInstance();
    final current = preferences.getString(prefsKey);
    _mode = _decode(current);
    notifyListeners();
  }

  Future<void> setMode(ThemeMode value) async {
    if (_mode == value) return;
    _mode = value;
    notifyListeners();
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(prefsKey, _encode(value));
  }

  /// Switches directly to the opposite visible appearance.
  Future<void> toggle(Brightness brightness) =>
      setMode(brightness == Brightness.dark ? ThemeMode.light : ThemeMode.dark);

  String get label => switch (_mode) {
    ThemeMode.system => 'تلقائي مع الجهاز',
    ThemeMode.light => 'فاتح',
    ThemeMode.dark => 'داكن',
  };

  IconData get icon => switch (_mode) {
    ThemeMode.system => Icons.brightness_auto_rounded,
    ThemeMode.light => Icons.light_mode_rounded,
    ThemeMode.dark => Icons.dark_mode_rounded,
  };

  static ThemeMode _decode(String? raw) => switch (raw) {
    'light' => ThemeMode.light,
    'dark' => ThemeMode.dark,
    _ => ThemeMode.system,
  };

  static String _encode(ThemeMode mode) => switch (mode) {
    ThemeMode.light => 'light',
    ThemeMode.dark => 'dark',
    ThemeMode.system => 'system',
  };
}

class SanadThemeScope extends InheritedNotifier<SanadThemeController> {
  const SanadThemeScope({
    super.key,
    required SanadThemeController controller,
    required super.child,
  }) : super(notifier: controller);

  static SanadThemeController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<SanadThemeScope>();
    assert(scope != null, 'SanadThemeScope is missing');
    return scope!.notifier!;
  }

  static SanadThemeController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SanadThemeScope>()?.notifier;
}
