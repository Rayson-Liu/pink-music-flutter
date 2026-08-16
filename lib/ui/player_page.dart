import 'dart:math';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../app.dart';
import '../models/track.dart';
import 'lyric_display.dart';
import 'series_panel.dart';

/// 大屏播放页
class PlayerPage extends StatefulWidget {
  const PlayerPage({super.key});

  /// 统一的打开动画：底部上滑 + 淡入（对齐原项目 .player-page.active 过渡）
  static Route<void> route() {
    return PageRouteBuilder<void>(
      transitionDuration: const Duration(milliseconds: 360),
      reverseTransitionDuration: const Duration(milliseconds: 260),
      pageBuilder: (_, _, _) => const PlayerPage(),
      transitionsBuilder: (_, anim, _, child) {
        final curved = CurvedAnimation(
          parent: anim,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.08),
              end: Offset.zero,
            ).animate(curved),
            child: child,
          ),
        );
      },
    );
  }

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  bool _isSeeking = false;
  double _seekValue = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final track = AppServices.instance.player.currentTrack;
      if (track != null && track.videos > 1 &&
          AppServices.instance.player.currentVideoEpisodes.isEmpty) {
        AppServices.instance.engine.loadEpisodes(track.bvid);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final svc = AppServices.instance;
    final theme = Theme.of(context);
    final mediaQuery = MediaQuery.of(context);
    return Scaffold(
      body: ListenableBuilder(
        listenable: Listenable.merge(
            [svc.player, svc.settings, svc.lyric]),
        builder: (context, _) {
          final track = svc.player.currentTrack;
          if (track == null) {
            return const Center(child: Text('暂无播放'));
          }
          return Stack(
            children: [
              // 背景毛玻璃渐变
              _buildBackground(track),
              SafeArea(
                bottom: true,
                child: Column(
                  children: [
                    _buildTopBar(svc, theme, track.title),
                    Expanded(
                      child: _buildCoverArea(svc, theme, track),
                    ),
                    _buildLyricPreview(svc, theme),
                    _buildProgressBar(svc, theme),
                    _buildControls(svc, theme),
                    SizedBox(height: mediaQuery.padding.bottom + 8),
                  ],
                ),
              ),
              // 歌词全屏浮层
              if (svc.lyric.showLyricPanel)
                Positioned.fill(
                  child: LyricDisplay(
                    onClose: () => svc.lyric.setShowLyricPanel(false),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  // ---------- 背景 ----------

  Widget _buildBackground(Track track) {
    if (track.cover.isEmpty) return const SizedBox.shrink();
    return Positioned.fill(
      child: Container(
        decoration: BoxDecoration(
          image: DecorationImage(
            image: NetworkImage(track.cover),
            fit: BoxFit.cover,
            colorFilter: ColorFilter.mode(
                Theme.of(context).scaffoldBackgroundColor.withValues(alpha: 0.75),
                BlendMode.srcATop),
          ),
        ),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 60, sigmaY: 60),
          child: Container(color: Colors.transparent),
        ),
      ),
    );
  }

  // ---------- 顶部 ----------

  Widget _buildTopBar(AppServices svc, ThemeData theme, String title) {
    final track = svc.player.currentTrack!;
    final hasMultiP = track.videos > 1 ||
        svc.player.currentVideoEpisodes.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.keyboard_arrow_down),
            onPressed: () => Navigator.pop(context),
          ),
          Expanded(
            child: Text(
              title,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w600),
            ),
          ),
          if (hasMultiP)
            IconButton(
              icon: const Icon(Icons.video_library_outlined),
              tooltip: '分P',
              onPressed: () => showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                backgroundColor: theme.colorScheme.surface,
                builder: (_) => const SeriesPanel(),
              ),
            ),
          IconButton(
            icon: Icon(
              svc.lyric.showLyricPanel
                  ? Icons.lyrics
                  : Icons.lyrics_outlined,
              color: svc.lyric.showLyricPanel
                  ? theme.colorScheme.primary
                  : null,
            ),
            tooltip: '歌词',
            onPressed: () {
              if (svc.lyric.showLyricPanel) {
                svc.lyric.setShowLyricPanel(false);
              } else {
                svc.lyric.setShowLyricPanel(true);
                if (svc.lyric.loadedHash !=
                    svc.lyric.getCacheKey(track)) {
                  svc.lyric.loadLyricForTrack(track);
                }
              }
            },
          ),
        ],
      ),
    );
  }

  // ---------- 封面 ----------

  Widget _buildCoverArea(AppServices svc, ThemeData theme, Track track) {
    return Center(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = min(constraints.maxWidth * 0.72,
              constraints.maxHeight * 0.5);
          return Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _AlbumRipple(
                size: size,
                cover: track.cover,
                bvid: track.bvid,
                intensity: svc.settings.audioVisualizerIntensity,
              ),
              const SizedBox(height: 20),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  track.title,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                track.author,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, color: theme.hintColor),
              ),
              if (svc.player.audioError.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(svc.player.audioError,
                      style: TextStyle(
                          fontSize: 12, color: theme.colorScheme.error)),
                ),
            ],
          );
        },
      ),
    );
  }

  // ---------- 歌词预览 ----------

  Widget _buildLyricPreview(AppServices svc, ThemeData theme) {
    final lyric = svc.lyric.currentLyric;
    final idx = svc.lyric.currentLineIndex;
    if (lyric == null || idx < 0 || idx >= lyric.lines.length) {
      return SizedBox(
        height: 28,
        child: Center(
          child: Text(
            svc.lyric.isLyricLoading ? '歌词加载中…' : '暂无歌词',
            style: TextStyle(fontSize: 12, color: theme.hintColor),
          ),
        ),
      );
    }
    final line = lyric.lines[idx];
    final text = switch (svc.settings.lyricDisplayMode) {
      'romaji' when line.romaji.isNotEmpty => line.romaji,
      'translation' when line.translation.isNotEmpty => line.translation,
      _ => line.text,
    };
    return GestureDetector(
      onTap: () {
        svc.lyric.setShowLyricPanel(true);
      },
      child: SizedBox(
        height: 28,
        child: Center(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                fontSize: 13,
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w500),
          ),
        ),
      ),
    );
  }

  // ---------- 进度条 ----------

  Widget _buildProgressBar(AppServices svc, ThemeData theme) {
    final duration = svc.player.duration;
    final position = _isSeeking ? _seekValue : svc.player.currentTime;
    final buffered = svc.player.bufferedProgress; // 0-100 百分比
    // 缓冲进度需换算为秒（与 slider 的 value/max 同单位）
    final bufferedSeconds = duration > 0
        ? (buffered * duration / 100).clamp(0.0, duration)
        : 0.0;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Text(_fmtTime(position),
              style: TextStyle(fontSize: 11, color: theme.hintColor)),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                secondaryActiveTrackColor:
                    theme.colorScheme.primary.withValues(alpha: 0.3),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                thumbShape:
                    const RoundSliderThumbShape(enabledThumbRadius: 5),
              ),
              child: Slider(
                value: position.clamp(0, duration > 0 ? duration : 1),
                max: duration > 0 ? duration : 1,
                secondaryTrackValue: bufferedSeconds,
                onChangeStart: (_) => setState(() => _isSeeking = true),
                onChanged: (v) => setState(() => _seekValue = v),
                onChangeEnd: (v) {
                  setState(() => _isSeeking = false);
                  svc.engine.seek(v);
                },
              ),
            ),
          ),
          Text(_fmtTime(duration),
              style: TextStyle(fontSize: 11, color: theme.hintColor)),
        ],
      ),
    );
  }

  // ---------- 控制按钮 ----------

  Widget _buildControls(AppServices svc, ThemeData theme) {
    final primary = theme.colorScheme.primary;
    final modeIcon = switch (svc.player.playMode) {
      'order' => Icons.arrow_circle_up_outlined,
      'loop' => Icons.repeat,
      'single' => Icons.repeat_one,
      _ => Icons.shuffle,
    };
    final modeTooltip = switch (svc.player.playMode) {
      'order' => '顺序播放',
      'loop' => '列表循环',
      'single' => '单曲循环',
      _ => '随机播放',
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          IconButton(
            icon: Icon(modeIcon, color: primary, size: 24),
            tooltip: modeTooltip,
            onPressed: () => svc.player.togglePlayMode(),
          ),
          IconButton(
            icon: const Icon(Icons.skip_previous),
            iconSize: 36,
            onPressed: () => svc.engine.playPrevious(),
          ),
          // 播放/暂停大按钮：padding 归零 + 与 SizedBox 等大，保证图标严格居中
          SizedBox(
            width: 72,
            height: 72,
            child: IconButton(
              padding: EdgeInsets.zero,
              icon: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                transitionBuilder: (child, anim) =>
                    ScaleTransition(scale: anim, child: child),
                child: Icon(
                  svc.player.isAudioLoading
                      ? Icons.hourglass_top
                      : svc.player.isPlaying
                          ? Icons.pause_circle_filled
                          : Icons.play_circle_filled,
                  key: ValueKey(svc.player.isAudioLoading
                      ? 'loading'
                      : svc.player.isPlaying
                          ? 'pause'
                          : 'play'),
                ),
              ),
              iconSize: 72,
              color: primary,
              onPressed: () {
                HapticFeedback.lightImpact();
                svc.engine.togglePlay();
              },
            ),
          ),
          IconButton(
            icon: const Icon(Icons.skip_next),
            iconSize: 36,
            onPressed: () => svc.engine.playNext(),
          ),
          IconButton(
            icon: const Icon(Icons.share),
            iconSize: 26,
            onPressed: () => _shareTrack(svc),
          ),
        ],
      ),
    );
  }

  void _shareTrack(AppServices svc) {
    final track = svc.player.currentTrack;
    if (track == null) return;
    final url = 'https://www.bilibili.com/video/${track.bvid}';
    HapticFeedback.lightImpact();
    Share.share('${track.title} - ${track.author}\n$url');
  }

  // ---------- 时间格式化 ----------

  static String _fmtTime(double sec) {
    if (sec.isNaN || sec < 0) sec = 0;
    final m = sec ~/ 60;
    final s = (sec % 60).floor();
    return '$m:${s.toString().padLeft(2, '0')}';
  }
}

/// 专辑封面涟漪动效（对应 AlbumRipple，激进度驱动）
class _AlbumRipple extends StatefulWidget {
  final double size;
  final String cover;
  final String bvid;
  final double intensity;

  const _AlbumRipple({
    required this.size,
    required this.cover,
    required this.bvid,
    required this.intensity,
  });

  @override
  State<_AlbumRipple> createState() => _AlbumRippleState();
}

class _AlbumRippleState extends State<_AlbumRipple>
    with SingleTickerProviderStateMixin {
  // 环扩散用独立控制器，保证 60fps 平滑（不再依赖 DateTime.now() 的取模）
  late final AnimationController _ripple;

  @override
  void initState() {
    super.initState();
    _ripple = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );
    // 播放态时由 build 里的 ListenableBuilder 控制 repeat/stop
  }

  @override
  void dispose() {
    _ripple.dispose();
    super.dispose();
  }

  void _sync(bool playing) {
    if (playing) {
      if (!_ripple.isAnimating) _ripple.repeat();
    } else {
      if (_ripple.isAnimating) {
        _ripple.stop();
        _ripple.value = 0;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final svc = AppServices.instance;
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final baseAlpha = (0.12 + widget.intensity * 0.15).clamp(0.0, 0.4);
    return SizedBox(
      width: widget.size + 60,
      height: widget.size + 60,
      child: ListenableBuilder(
        listenable: svc.player,
        builder: (context, _) {
          final playing = svc.player.isPlaying;
          _sync(playing);
          return Center(
            child: AnimatedBuilder(
              animation: _ripple,
              builder: (context, _) {
                final t = _ripple.value;
                // 扩散环（平滑控制器驱动）
                final rings = <Widget>[];
                if (playing) {
                  for (var i = 0; i < 3; i++) {
                    final phase = (t + i / 3) % 1.0;
                    final ringSize = widget.size +
                        8 +
                        phase * 60 * (0.5 + widget.intensity);
                    rings.add(Container(
                      width: ringSize,
                      height: ringSize,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: primary.withValues(
                              alpha: (1 - phase) * baseAlpha * 1.8),
                          width: 2,
                        ),
                      ),
                    ));
                  }
                }
                // 播放时轻微呼吸缩放（涟漪控制器驱动，正弦平滑）
                final breath = playing
                    ? 1.0 + 0.015 * (0.5 + 0.5 * sin(t * 2 * pi))
                    : 1.0;
                return Stack(
                  alignment: Alignment.center,
                  children: [
                    ...rings,
                    Transform.scale(
                      scale: breath,
                      child: Hero(
                        tag: 'player-cover-${widget.bvid}',
                        child: Container(
                          width: widget.size,
                          height: widget.size,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(28),
                            boxShadow: [
                              BoxShadow(
                                color: primary.withValues(
                                    alpha: 0.4 * (0.5 + widget.intensity)),
                                blurRadius: 30 + widget.intensity * 30,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(28),
                            child: widget.cover.isEmpty
                                ? Container(
                                    color: theme
                                        .colorScheme.surfaceContainerHighest,
                                    child: const Icon(Icons.music_note,
                                        color: Colors.white24, size: 60),
                                  )
                                : Image.network(widget.cover,
                                    fit: BoxFit.cover),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          );
        },
      ),
    );
  }
}
