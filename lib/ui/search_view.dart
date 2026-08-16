import 'package:flutter/material.dart';

import '../app.dart';
import '../models/track.dart';
import 'widgets/dialogs.dart';
import 'widgets/track_tile.dart';

/// 搜索页
class SearchView extends StatefulWidget {
  const SearchView({super.key});

  @override
  State<SearchView> createState() => _SearchViewState();
}

class _SearchViewState extends State<SearchView> {
  final TextEditingController _controller = TextEditingController();
  bool _submitted = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _search(String keyword) {
    if (keyword.trim().isEmpty) return;
    setState(() => _submitted = true);
    FocusScope.of(context).unfocus();
    AppServices.instance.search.handleSearch(keyword);
  }

  @override
  Widget build(BuildContext context) {
    final svc = AppServices.instance;
    final theme = Theme.of(context);
    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    textInputAction: TextInputAction.search,
                    onSubmitted: _search,
                    decoration: InputDecoration(
                      hintText: '搜索 B 站音乐',
                      prefixIcon: const Icon(Icons.search, size: 20),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () {
                          _controller.clear();
                          setState(() => _submitted = false);
                        },
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () => _search(_controller.text),
                  child: const Text('搜索'),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListenableBuilder(
              listenable: svc.search,
              builder: (context, _) {
                if (!_submitted) return _buildIdle(theme);
                return _buildResults(svc);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIdle(ThemeData theme) {
    final svc = AppServices.instance;
    final keywords = svc.search.recommendKeywords.take(10).toList();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('推荐搜索',
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: keywords
              .map((k) => ActionChip(
                    label: Text(k),
                    onPressed: () {
                      _controller.text = k;
                      _search(k);
                    },
                  ))
              .toList(),
        ),
        if (svc.search.recommendedMusic.isNotEmpty) ...[
          const SizedBox(height: 24),
          Text('为你推荐',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          ...svc.search.recommendedMusic.take(10).map((t) => TrackTile(
                track: t,
                onPlay: () => svc.engine.playMusic(t,
                    view: 'search', queue: svc.search.recommendedMusic),
                onPlayNext: () async {
                  final queued = await svc.engine.playNextLater(t);
                  if (mounted) {
                    showToast(context, queued ? '已添加到下一首' : '开始播放');
                  }
                },
                onDownload: (track) => _download(track),
              )),
        ],
      ],
    );
  }

  Widget _buildResults(AppServices svc) {
    if (svc.search.isLoadingSearch) {
      return const Center(child: CircularProgressIndicator());
    }
    final results = svc.search.searchResults;
    if (results.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.music_off,
                size: 56, color: Theme.of(context).hintColor),
            const SizedBox(height: 12),
            Text('未找到「${svc.search.searchQuery}」相关音乐',
                style: TextStyle(color: Theme.of(context).hintColor)),
          ],
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 80),
      itemCount: results.length,
      itemBuilder: (context, i) {
        final t = results[i];
        return TrackTile(
          track: t,
          onPlay: () =>
              svc.engine.playMusic(t, view: 'search', queue: results),
          onPlayNext: () async {
            final queued = await svc.engine.playNextLater(t);
            if (context.mounted) {
              showToast(context, queued ? '已添加到下一首' : '开始播放');
            }
          },
          onDownload: (track) => _download(track),
          onShowSeries: () => svc.engine.loadEpisodes(t.bvid),
        );
      },
    );
  }

  void _download(Track t) {
    AppServices.instance.downloads.downloadMusic(t);
    showToast(context, '开始下载：${t.title}');
  }
}
