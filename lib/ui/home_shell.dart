import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app.dart';
import '../models/track.dart';
import 'home_view.dart';
import 'mine_view.dart';
import 'player_page.dart';
import 'search_view.dart';
import 'widgets/cover_image.dart';
import 'widgets/glass.dart';

/// 主框架：底部导航 + 迷你播放条
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;
  bool _initTimeout = false;

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(seconds: 5), () {
      if (!mounted) return;
      if (!AppServices.instanceReady) {
        setState(() => _initTimeout = true);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final svc = AppServices.instance;
    return Scaffold(
      body: _initTimeout
          ? Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.info_outline,
                        color: Colors.orange, size: 48),
                    const SizedBox(height: 16),
                    const Text('初始化超时，请检查网络',
                        style: TextStyle(fontSize: 16)),
                    if (svc.initError != null) ...[
                      const SizedBox(height: 8),
                      Text(svc.initError!,
                          style: const TextStyle(
                              fontSize: 12, color: Colors.grey),
                          textAlign: TextAlign.center),
                    ],
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: () => setState(() => _initTimeout = false),
                      child: const Text('重试'),
                    ),
                  ],
                ),
              ),
            )
          : IndexedStack(
              index: _index,
              children: const [HomeView(), SearchView(), MineView()],
            ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListenableBuilder(
            listenable: svc.player,
            builder: (context, _) {
              final track = svc.player.currentTrack;
              if (track == null) return const SizedBox.shrink();
              return _MiniPlayerBar(
                track: track,
                onTap: () {
                  Navigator.push(context, PlayerPage.route());
                },
              );
            },
          ),
          NavigationBar(
            selectedIndex: _index,
            onDestinationSelected: (i) => setState(() => _index = i),
            destinations: const [
              NavigationDestination(
                  icon: Icon(Icons.home_outlined),
                  selectedIcon: Icon(Icons.home),
                  label: '首页'),
              NavigationDestination(
                  icon: Icon(Icons.search),
                  label: '搜索'),
              NavigationDestination(
                  icon: Icon(Icons.person_outline),
                  selectedIcon: Icon(Icons.person),
                  label: '我的'),
            ],
          ),
        ],
      ),
    );
  }
}

/// 迷你播放条
class _MiniPlayerBar extends StatelessWidget {
  final Track track;
  final VoidCallback onTap;

  const _MiniPlayerBar({required this.track, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final svc = AppServices.instance;
    final theme = Theme.of(context);
    // 浮动液态玻璃迷你播放条（对齐原项目 player-bar 的 useLiquidGlass）
    return GlassSurface(
      margin: const EdgeInsets.fromLTRB(10, 6, 10, 6),
      borderRadius: 16,
      blur: 22,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Row(
                  children: [
                    Hero(
                      tag: 'player-cover-${track.bvid}',
                      child: CoverImage(url: track.cover, size: 40, radius: 8),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(track.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600)),
                          Text(track.author,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 11, color: theme.hintColor)),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
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
                      iconSize: 36,
                      color: theme.colorScheme.primary,
                      onPressed: () {
                        HapticFeedback.lightImpact();
                        svc.engine.togglePlay();
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.skip_next),
                      iconSize: 26,
                      onPressed: () => svc.engine.playNext(),
                    ),
                  ],
                ),
              ),
              // 迷你进度条
              _MiniProgress(
                listenable: svc.player,
                progress: svc.player.duration > 0
                    ? (svc.player.currentTime / svc.player.duration)
                        .clamp(0.0, 1.0)
                    : 0.0,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 迷你播放条底部的细进度线（随播放实时推进）
class _MiniProgress extends StatelessWidget {
  final Listenable listenable;
  final double progress;

  const _MiniProgress({required this.listenable, required this.progress});

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return ListenableBuilder(
      listenable: listenable,
      builder: (context, _) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(1),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 2,
            backgroundColor: Colors.transparent,
            valueColor: AlwaysStoppedAnimation<Color>(
                primary.withValues(alpha: 0.7)),
          ),
        );
      },
    );
  }
}
