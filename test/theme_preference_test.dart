import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:snad/core/theme_preference.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the first appearance toggle changes the visible theme', () async {
    SharedPreferences.setMockInitialValues({});
    final controller = SanadThemeController();

    expect(controller.mode, ThemeMode.system);
    await controller.toggle(Brightness.light);
    expect(controller.mode, ThemeMode.dark);

    await controller.toggle(Brightness.dark);
    expect(controller.mode, ThemeMode.light);
  });
}
