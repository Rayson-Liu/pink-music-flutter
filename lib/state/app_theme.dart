import 'package:flutter/material.dart';

import 'theme_store.dart';

/// 根据主题状态构建 ThemeData（背景/文字色精确移植原 CSS 变量）
class AppTheme {
  static ThemeData build(ThemeStore store) {
    final c = store.colors;
    final dark = store.isDark;
    final isApple = store.currentColor == 'apple-music';
    final useAppleColors = dark
        ? isApple
        : false;

    final bgPrimary = dark
        ? (useAppleColors ? const Color(0xFF1A1A1A) : const Color(0xFF0A0A14))
        : (isApple ? const Color(0xFFF5F5F7) : const Color(0xFFF8FAFC));
    final bgSecondary = dark
        ? (useAppleColors ? const Color(0xFF222222) : const Color(0xFF121220))
        : (isApple ? const Color(0xFFFFFFFF) : const Color(0xFFFFFFFF));
    final bgTertiary = dark
        ? (useAppleColors ? const Color(0xFF2C2C2C) : const Color(0xFF1A1A2E))
        : (isApple ? const Color(0xFFE8E8ED) : const Color(0xFFF1F5F9));

    final primary = dark ? c.primary : _lightPrimary(c);
    final textPrimary =
        dark ? Colors.white : (isApple ? const Color(0xFF1D1D1F) : const Color(0xFF1E293B));
    final textSecondary = dark
        ? (useAppleColors
            ? Colors.white.withValues(alpha: 0.7)
            : const Color(0xFFC0C0D0))
        : (isApple
            ? Colors.black.withValues(alpha: 0.65)
            : const Color(0xFF64748B));
    final textMuted = dark
        ? (useAppleColors
            ? Colors.white.withValues(alpha: 0.4)
            : const Color(0xFF7A7A8A))
        : (isApple
            ? Colors.black.withValues(alpha: 0.35)
            : const Color(0xFF94A3B8));

    final scheme = ColorScheme.fromSeed(
      seedColor: primary,
      brightness: dark ? Brightness.dark : Brightness.light,
      primary: primary,
      surface: bgPrimary,
      onSurface: textPrimary,
      error: const Color(0xFFEF4444),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: dark ? Brightness.dark : Brightness.light,
      colorScheme: scheme,
      scaffoldBackgroundColor: bgPrimary,
      canvasColor: bgPrimary,
      cardColor: bgTertiary,
      dividerColor: textMuted.withValues(alpha: 0.3),
      splashFactory: InkSparkle.splashFactory,
      textTheme: Typography.material2021(platform: TargetPlatform.android)
          .black
          .apply(
            bodyColor: textPrimary,
            displayColor: textPrimary,
          ),
      appBarTheme: AppBarTheme(
        backgroundColor: bgPrimary,
        foregroundColor: textPrimary,
        elevation: 0,
        centerTitle: true,
      ),
      iconTheme: IconThemeData(color: textSecondary),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: bgPrimary,
        indicatorColor: primary.withValues(alpha: 0.15),
        labelTextStyle: WidgetStatePropertyAll(
            TextStyle(color: textSecondary, fontSize: 12)),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
              color: selected ? primary : textSecondary, size: 24);
        }),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: primary,
        thumbColor: primary,
        inactiveTrackColor: bgTertiary,
        overlayColor: primary.withValues(alpha: 0.12),
        trackHeight: 2,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? primary : null),
        trackColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected)
                ? primary.withValues(alpha: 0.5)
                : null),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: primary),
      dialogTheme: DialogThemeData(backgroundColor: bgSecondary),
      bottomSheetTheme:
          BottomSheetThemeData(backgroundColor: bgSecondary),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: bgTertiary,
        contentTextStyle: TextStyle(color: textPrimary),
        behavior: SnackBarBehavior.floating,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: bgTertiary,
        hintStyle: TextStyle(color: textMuted),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  static Color _lightPrimary(ThemeColors c) => switch (c.name) {
        'pink' => const Color(0xFFEC4899),
        'purple' => const Color(0xFFA855F7),
        'blue' => const Color(0xFF3B82F6),
        'green' => const Color(0xFF22C55E),
        'orange' => const Color(0xFFF97316),
        'apple-music' => const Color(0xFFFF3B30),
        _ => c.primary,
      };
}
