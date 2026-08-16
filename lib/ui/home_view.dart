import 'package:flutter/material.dart';

import '../app.dart';
import '../models/track.dart';
import 'playlist_detail.dart';
import 'widgets/cover_image.dart';
import 'widgets/dialogs.dart';
import 'widgets/track_tile.dart';

/// 首页：推荐 + 播放历史 + 歌单
class HomeView extends StatefulWidget {
  const HomeView({super.key});

  @override
  State<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<HomeView> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      AppServices.instance.search.loadRecommendations();
    });
  }

  @override
  Widget build(BuildContext context) {
    final svc = AppServices.instance;
    final theme = Theme.of(context);
    return SafeArea(
      bottom: false,
      child: RefreshIndicator(
        onRefresh: () => svc.search.loadRecommendations(),
        child: ListenableBuilder(
          listenable: Listenable.merge(
              [svc.search, svc.player, svc.playlists]),
          builder: (context, _) {
            final recommended = svc.search.recommendedMusic;
            final history = svc.player.playHistory;
            final playlists = svc.playlists.userPlaylists;
            return CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: Text('Pink Music',
                        style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.primary)),
                  ),
                ),
                if (history.isNotEmpty) ...[
                  const SliverToBoxAdapter(
                    child: _SectionHeader('播放历史'),
                  ),
                  SliverList.builder(
                    itemCount: history.length.clamp(0, 5),
                    itemBuilder: (context, i) => TrackTile(
                      track: history[i],
                      onPlay: () => svc.engine.playMusic(history[i],
                          view: 'home', queue: history),
                      onPlayNext: () async {
                        final queued =
                            await svc.engine.playNextLater(history[i]);
                        if (context.mounted) {
                          showToast(context,
                              queued ? '已添加到下一首' : '开始播放');
                        }
                      },
                      onDownload: (t) => _download(t),
                      onShowSeries: () => svc.engine.loadEpisodes(history[i].bvid),
                    ),
                  ),
                ],
                if (playlists.isNotEmpty) ...[
                  const SliverToBoxAdapter(
                    child: _SectionHeader('歌单'),
                  ),
                  SliverToBoxAdapter(
                    child: SizedBox(
                      height: 108,
                      child: ListView.separated(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        scrollDirection: Axis.horizontal,
                        itemCount: playlists.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 12),
                        itemBuilder: (context, i) => _PlaylistCard(
                          cover: playlists[i].cover,
                          name: playlists[i].name,
                          count: playlists[i].music.length,
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => PlaylistDetailPage(
                                    playlistId: playlists[i].id),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ],
                const SliverToBoxAdapter(
                  child: _SectionHeader('推荐音乐'),
                ),
                if (svc.search.isLoadingRecommended && recommended.isEmpty)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(child: CircularProgressIndicator()),
                  )
                else
                  SliverList.builder(
                    itemCount: recommended.length,
                    itemBuilder: (context, i) {
                      final t = recommended[i];
                      return TrackTile(
                        track: t,
                        onPlay: () => svc.engine.playMusic(t,
                            view: 'home', queue: recommended),
                        onPlayNext: () async {
                          final queued = await svc.engine.playNextLater(t);
                          if (context.mounted) {
                            showToast(context,
                                queued ? '已添加到下一首' : '开始播放');
                          }
                        },
                        onDownload: (track) => _download(track),
                        onShowSeries: () => svc.engine.loadEpisodes(t.bvid),
                      );
                    },
                  ),
                const SliverToBoxAdapter(child: SizedBox(height: 80)),
              ],
            );
          },
        ),
      ),
    );
  }

  void _download(Track t) {
    AppServices.instance.downloads.downloadMusic(t);
    showToast(context, '开始下载：${t.title}');
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(title,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
    );
  }
}

/// 歌单横向卡片
class _PlaylistCard extends StatelessWidget {
  final String cover;
  final String name;
  final int count;
  final VoidCallback onTap;

  const _PlaylistCard({
    required this.cover,
    required this.name,
    required this.count,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: 100,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                CoverImage(url: cover, size: 100, radius: 12),
                Positioned(
                  right: 4,
                  bottom: 4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text('$count 首',
                        style: const TextStyle(
                            color: Colors.white, fontSize: 9)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}
