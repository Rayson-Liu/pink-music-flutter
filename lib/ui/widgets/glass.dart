import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

/// 液态玻璃（毛玻璃）面板：BackdropFilter 模糊 + 半透明填充 + 1px 高光边框 +
/// 左上角内高光渐变，对齐原项目 --glass-bg/--glass-border 与 useLiquidGlass 的视觉。
///
/// 注意：BackdropFilter 有 GPU 开销，仅用于少量浮动面板（迷你播放条、歌词浮层等），
/// 不要铺到列表每一条上。
class GlassSurface extends StatelessWidget {
  final Widget child;
  final double borderRadius;
  final double blur;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final Color? surfaceColor;

  const GlassSurface({
    super.key,
    required this.child,
    this.borderRadius = 16,
    this.blur = 24,
    this.padding = EdgeInsets.zero,
    this.margin = EdgeInsets.zero,
    this.surfaceColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;

    final base = surfaceColor ??
        (dark ? const Color(0xFF1A1A2E) : const Color(0xFFFFFFFF));
    // 暗色 0.62 透明度、浅色 0.78（对齐 --glass-bg rgba(26,26,46,.65) / rgba(255,255,255,.82)）
    final tint = base.withValues(alpha: dark ? 0.62 : 0.78);
    final border = dark
        ? Colors.white.withValues(alpha: 0.10)
        : Colors.black.withValues(alpha: 0.06);
    // 左上角内高光，模拟玻璃的“液面”反光
    final sheen = dark
        ? Colors.white.withValues(alpha: 0.06)
        : Colors.white.withValues(alpha: 0.55);

    return Padding(
      padding: margin,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(borderRadius),
              border: Border.all(color: border, width: 1),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color.alphaBlend(sheen, tint), tint],
              ),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}
