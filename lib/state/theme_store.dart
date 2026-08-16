import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 主题色定义（精确移植 style.css 色值）
class ThemeColors {
  final String name;
  final Color primary;
  final Color primaryDark;
  final Color primaryLight;
  final Color glow;

  const ThemeColors(this.name, this.primary, this.primaryDark,
      this.primaryLight, this.glow);
}

const List<ThemeColors> kColorThemes = [
  ThemeColors('pink', Color(0xFFFF69B4), Color(0xFFC9356A),
      Color(0xFFFFB6D9), Color(0x66FF69B4)),
  ThemeColors('purple', Color(0xFFA855F7), Color(0xFF7C3AED),
      Color(0xFFC084FC), Color(0x66A855F7)),
  ThemeColors('blue', Color(0xFF3B82F6), Color(0xFF2563EB),
      Color(0xFF60A5FA), Color(0x663B82F6)),
  ThemeColors('green', Color(0xFF22C55E), Color(0xFF16A34A),
      Color(0xFF4ADE80), Color(0x6622C55E)),
  ThemeColors('orange', Color(0xFFF97316), Color(0xFFEA580C),
      Color(0xFFFB923C), Color(0x66F97316)),
  ThemeColors('apple-music', Color(0xFFFF3B30), Color(0xFFD70015),
      Color(0xFFFF6B6B), Color(0x1FFF3B30)),
];

ThemeColors colorThemeFor(String name) => kColorThemes.firstWhere(
      (c) => c.name == name,
      orElse: () => kColorThemes.first,
    );

/// 主题状态（深/浅色 × 6 色）
class ThemeStore extends ChangeNotifier {
  static const String _key = 'pink-music-theme';

  String currentTheme = 'dark'; // dark | light
  String currentColor = 'pink';

  bool get isDark => currentTheme == 'dark';

  ThemeColors get colors => colorThemeFor(currentColor);

  void setTheme(String theme) {
    currentTheme = theme;
    _persist();
    notifyListeners();
  }

  void toggleTheme() => setTheme(isDark ? 'light' : 'dark');

  void setColor(String color) {
    currentColor = color;
    _persist();
    notifyListeners();
  }

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw != null) {
      try {
        final map = Map<String, dynamic>.from(
            (jsonDecode(raw) is Map) ? jsonDecode(raw) : {});
        currentTheme = map['currentTheme'] ?? 'dark';
        currentColor = map['currentColor'] ?? 'pink';
      } catch (_) {}
    }
    notifyListeners();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _key, jsonEncode({'currentTheme': currentTheme, 'currentColor': currentColor}));
  }
}
