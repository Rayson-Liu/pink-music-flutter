import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app.dart';
import '../models/lyric.dart';

/// 全屏歌词页（重新设计：毛玻璃背景、居中自动跟随、字号调节、上下渐隐）
class LyricDisplay extends StatefulWidget {
  final VoidCallback onClose;

  const LyricDisplay({super.key, required this.onClose});

  @override
  State<LyricDisplay> createState() => _LyricDisplayState();
}

class _LyricDisplayState extends State<LyricDisplay> {
  final ScrollController _scroll = ScrollController();
  bool _manualScroll = false;
  DateTime _lastManualScroll = DateTime.now();
  final TextEditingController _searchController = TextEditingController();
  bool _showSearch = false;
  int _lastAutoScrolledIndex = -1;

  @override
  void dispose() {
    _scroll.dispose();
    _searchController.dispose();
    super.dispose();
  }

  /// 每行固定高度：容纳主行 + 附注行 + 呼吸留白，保证滚动居中计算稳定
  double get _lineHeight {
    final f = AppServices.instance.settings.lyricFontSize;
    return (f * 2.4 + 24).clamp(52.0, 100.0);
  }

  @override
  Widget build(BuildContext context) {
    final svc = AppServices.instance;
    final theme = Theme.of(context);
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
        child: Scaffold(
          backgroundColor:
              theme.scaffoldBackgroundColor.withValues(alpha: 0.66),
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            leading: IconButton(
                icon: const Icon(Icons.keyboard_arrow_down),
                onPressed: widget.onClose),
            title: const Text('歌词'),
            actions: [
              _buildFontControls(svc, theme),
              IconButton(
                icon: const Icon(Icons.search),
                tooltip: '搜索歌词',
                onPressed: () => setState(() {
                  _showSearch = !_showSearch;
                  _searchController.clear();
                }),
              ),
              PopupMenuButton<String>(
                onSelected: (v) => svc.settings.setLyricDisplayMode(v),
                itemBuilder: (context) => [
                  const PopupMenuItem(value: 'original', child: Text('原文')),
                  const PopupMenuItem(value: 'romaji', child: Text('罗马音')),
                  const PopupMenuItem(value: 'translation', child: Text('翻译')),
                ],
                icon: const Icon(Icons.tune),
              ),
            ],
          ),
          body: ListenableBuilder(
            listenable: Listenable.merge(
                [svc.lyric, svc.settings, svc.player]),
            builder: (context, _) {
              return Column(
                children: [
                  if (_showSearch) _buildSearchBox(svc, theme),
                  if (_showSearch) _buildSearchResults(svc),
                  Expanded(child: _buildLyricArea(svc, theme)),
                  _buildToolbar(svc, theme),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  // ---------- 字号控制 ----------

  Widget _buildFontControls(AppServices svc, ThemeData theme) {
    final size = svc.settings.lyricFontSize.round();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.text_decrease),
          tooltip: '减小字号',
          onPressed: () => svc.settings.adjustLyricFontSize(-2),
        ),
        SizedBox(
          width: 26,
          child: Text('$size',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: theme.hintColor)),
        ),
        IconButton(
          icon: const Icon(Icons.text_increase),
          tooltip: '增大字号',
          onPressed: () => svc.settings.adjustLyricFontSize(2),
        ),
      ],
    );
  }

  // ---------- 歌词主区 ----------

  Widget _buildLyricArea(AppServices svc, ThemeData theme) {
    final lyricStore = svc.lyric;
    final lyric = lyricStore.currentLyric;
    if (lyricStore.isLyricLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(
                width: 26,
                height: 26,
                child: CircularProgressIndicator(strokeWidth: 2)),
            const SizedBox(height: 12),
            Text('正在匹配歌词…', style: TextStyle(color: theme.hintColor)),
          ],
        ),
      );
    }
    if (lyric == null || lyric.lines.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.lyrics_outlined, size: 48, color: theme.hintColor),
            const SizedBox(height: 12),
            Text(lyricStore.lyricError.isNotEmpty
                ? lyricStore.lyricError
                : '暂无歌词', style: TextStyle(color: theme.hintColor)),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              icon: const Icon(Icons.search),
              label: const Text('搜索歌词'),
              onPressed: () => setState(() {
                _showSearch = true;
                _searchController.clear();
              }),
            ),
          ],
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final viewport = constraints.maxHeight;
        // 上下各留半屏，让首尾行也能滚到正中；此时目标滚动量 = index * lineHeight
        final half = ((viewport - _lineHeight) / 2).clamp(0.0, double.infinity);
        return NotificationListener<ScrollNotification>(
          onNotification: (n) {
            if (n is UserScrollNotification) {
              _manualScroll = true;
              _lastManualScroll = DateTime.now();
            }
            return false;
          },
          child: ShaderMask(
            shaderCallback: (rect) => LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.transparent,
                Colors.black,
                Colors.black,
                Colors.transparent,
              ],
              stops: const [0.0, 0.12, 0.88, 1.0],
            ).createShader(rect),
            blendMode: BlendMode.dstIn,
            child: ListView.builder(
              controller: _scroll,
              padding: EdgeInsets.symmetric(vertical: half),
              itemExtent: _lineHeight,
          itemCount: lyric.lines.length,
          itemBuilder: (context, i) {
            final line = lyric.lines[i];
            final active = i == lyricStore.currentLineIndex;
            // 自动滚动跟随（仅当索引变化且非手动模式）
            if (active && i != _lastAutoScrolledIndex && !_manualScroll) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted &&
                    !_manualScroll &&
                    _scroll.hasClients &&
                    active) {
                  _scrollTo(i);
                  _lastAutoScrolledIndex = i;
                }
              });
            }
            // 手动滚动 6 秒后恢复自动跟随
            if (_manualScroll &&
                DateTime.now().difference(_lastManualScroll).inSeconds > 6) {
              _manualScroll = false;
            }
            return _LyricLine(
              line: line,
              active: active,
              past: i < lyricStore.currentLineIndex && !_manualScroll,
              fontSize: svc.settings.lyricFontSize,
              displayMode: svc.settings.lyricDisplayMode,
              primaryColor: theme.colorScheme.primary,
              onTap: () {
                _manualScroll = false;
                svc.engine.seek(lyricStore.lineTimeToSeconds(i));
              },
            );
          },
        ),
      ),
    );
      },
    );
  }

  void _scrollTo(int index) {
    if (!_scroll.hasClients) return;
    final target = index * _lineHeight;
    _scroll.animateTo(
      target.clamp(0.0, _scroll.position.maxScrollExtent),
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeOutCubic,
    );
  }

  // ---------- 工具栏 ----------

  Widget _buildToolbar(AppServices svc, ThemeData theme) {
    final offset = svc.lyric.currentOffset;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _toolBtn(
              theme,
              icon: Icons.fast_rewind,
              tooltip: '歌词提前 0.5 秒',
              onTap: () {
                HapticFeedback.lightImpact();
                svc.lyric.adjustOffset(-1);
              },
            ),
            Text('偏移 ${(offset / 1000).toStringAsFixed(1)}s',
                style: TextStyle(fontSize: 12, color: theme.hintColor)),
            _toolBtn(
              theme,
              icon: Icons.fast_forward,
              tooltip: '歌词延后 0.5 秒',
              onTap: () {
                HapticFeedback.lightImpact();
                svc.lyric.adjustOffset(1);
              },
            ),
            if (offset != 0)
              TextButton(
                onPressed: () => svc.lyric.resetOffset(),
                child: const Text('重置', style: TextStyle(fontSize: 12)),
              ),
            const Spacer(),
            if (svc.lyric.lyricSource == 'manual')
              TextButton.icon(
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('恢复默认', style: TextStyle(fontSize: 12)),
                onPressed: () => svc.lyric.resetManualLyric(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _toolBtn(ThemeData theme,
      {required IconData icon,
      required String tooltip,
      required VoidCallback onTap}) {
    return IconButton(
      icon: Icon(icon, size: 20),
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      onPressed: onTap,
    );
  }

  // ---------- 搜索 ----------

  Widget _buildSearchBox(AppServices svc, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _searchController,
              textInputAction: TextInputAction.search,
              onSubmitted: (kw) {
                if (kw.trim().isNotEmpty) svc.lyric.searchLyric(kw.trim());
              },
              decoration: const InputDecoration(
                  hintText: '搜索歌词（按歌曲名）', isDense: true),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: () {
              if (_searchController.text.trim().isNotEmpty) {
                svc.lyric.searchLyric(_searchController.text.trim());
              }
            },
            child: const Text('搜索'),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchResults(AppServices svc) {
    if (!_showSearch) return const SizedBox.shrink();
    final results = svc.lyric.searchResults;
    return SizedBox(
      height: 260,
      child: ListView.builder(
        itemCount: results.length,
        itemBuilder: (context, i) {
          final r = results[i];
          return ListTile(
            dense: true,
            leading: const Icon(Icons.music_note),
            title: Text('${r['name']}',
                maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text('${r['artist']}',
                maxLines: 1, overflow: TextOverflow.ellipsis),
            onTap: () {
              setState(() => _showSearch = false);
              svc.lyric.loadLyricById(r['id'],
                  source: (r['source'] ?? 'netease').toString());
            },
          );
        },
      ),
    );
  }
}

/// 单行歌词
class _LyricLine extends StatelessWidget {
  final LyricLine line;
  final bool active;
  final bool past;
  final double fontSize;
  final String displayMode;
  final Color primaryColor;
  final VoidCallback onTap;

  const _LyricLine({
    required this.line,
    required this.active,
    required this.past,
    required this.fontSize,
    required this.displayMode,
    required this.primaryColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final main = switch (displayMode) {
      'romaji' when line.romaji.isNotEmpty => line.romaji,
      'translation' when line.translation.isNotEmpty => line.translation,
      _ => line.text,
    };
    final sub = switch (displayMode) {
      'romaji' when line.romaji.isNotEmpty => line.text,
      'translation' when line.translation.isNotEmpty => line.text,
      _ => (line.romaji.isNotEmpty || line.translation.isNotEmpty)
          ? (line.romaji.isNotEmpty ? line.romaji : line.translation)
          : null,
    };

    final mainColor = active
        ? primaryColor
        : (past
            ? theme.hintColor.withValues(alpha: 0.35)
            : theme.hintColor);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOut,
              style: TextStyle(
                fontSize: active ? fontSize + 5 : fontSize,
                fontWeight: active ? FontWeight.w800 : FontWeight.w500,
                color: mainColor,
                height: 1.25,
              ),
              child: Text(
                main,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (sub != null && sub.isNotEmpty)
              Text(
                sub,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: fontSize * 0.62,
                  height: 1.2,
                  color: active
                      ? primaryColor.withValues(alpha: 0.7)
                      : theme.hintColor.withValues(alpha: 0.55),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
