import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pink_music_android_main/state/app_theme.dart';
import 'package:pink_music_android_main/state/theme_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  test('ThemeStore defaults to dark pink theme', () {
    final store = ThemeStore();
    expect(store.isDark, isTrue);
    expect(store.currentColor, 'pink');
    expect(store.colors.name, 'pink');
  });

  test('ThemeStore toggles dark/light', () {
    final store = ThemeStore();
    store.toggleTheme();
    expect(store.isDark, isFalse);
    store.toggleTheme();
    expect(store.isDark, isTrue);
  });

  test('ThemeStore switches color theme', () {
    final store = ThemeStore();
    store.setColor('purple');
    expect(store.currentColor, 'purple');
    expect(store.colors.name, 'purple');
  });

  test('AppTheme builds dark and light ThemeData', () {
    final darkStore = ThemeStore();
    final dark = AppTheme.build(darkStore);
    expect(dark.brightness, Brightness.dark);

    final lightStore = ThemeStore()..setTheme('light');
    final light = AppTheme.build(lightStore);
    expect(light.brightness, Brightness.light);
  });
}
