import 'package:flutter/material.dart';

import '../app.dart';
import '../models/playlist.dart';
import '../models/track.dart';
import 'player_page.dart';
import 'widgets/dialogs.dart';
import 'widgets/track_tile.dart';

/// 歌单详情页
class PlaylistDetailPage extends StatefulWidget {
  final String playlistId;
  const PlaylistDetailPage({super.key, required this.playlistId});

  @override
  State<PlaylistDetailPage> createState() => _PlaylistDetailPageState();
}

class _PlaylistDetailPageState extends State<PlaylistDetailPage> {
  bool _selectMode = false;
  final Set<String> _selected = {}; // bvid:favId:favType:index
  bool _loadingBili = false;
  String _biliProgress = '';

  @override
  Widget build(BuildContext context) {
    final svc = AppServices.instance;
    return Scaffold(
      appBar: AppBar(title: const Text('歌单')),
      body: ListenableBuilder(
        listenable: Listenable.merge([svc.playlists, svc.player]),
        builder: (context, _) {
          final p = svc.playlists.findById(widget.playlistId);
          if (p == null) {
            return const Center(child: Text('歌单不存在'));
          }
          return Column(
            children: [
              _buildHeader(svc, p),
              const Divider(height: 1),
              Expanded(child: _buildTrackList(svc, p)),
            ],
          );
        },
      ),
    );
  }

  Widget _buildHeader(AppServices svc, Playlist p) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: 72,
              height: 72,
              child: _PlaylistCover(p),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(p.name,
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                Text('${p.music.length} 首歌曲',
                    style:
                        TextStyle(fontSize: 12, color: Theme.of(context).hintColor)),
                if (_biliProgress.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(_biliProgress,
                        style: const TextStyle(
                            fontSize: 11, color: Colors.blueAccent)),
                  ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.play_circle_fill, size: 44),
            color: Theme.of(context).colorScheme.primary,
            onPressed: () {
              if (p.music.isEmpty) {
                showToast(context, '歌单为空');
                return;
              }
              svc.engine.playMusic(p.music.first,
                  view: 'playlist', queue: p.music);
              Navigator.push(context, PlayerPage.route());
            },
          ),
        ],
      ),
    );
  }

  Widget _buildTrackList(AppServices svc, Playlist p) {
    final theme = Theme.of(context);
    if (p.isBiliFavorite && p.music.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('收藏夹尚未加载', style: TextStyle(color: theme.hintColor)),
            const SizedBox(height: 12),
            FilledButton.icon(
              icon: _loadingBili
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.download),
              label: Text(_loadingBili ? '加载中…' : '加载视频'),
              onPressed: _loadingBili ? null : () => _loadBiliFavorites(svc, p),
            ),
          ],
        ),
      );
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            children: [
              TextButton.icon(
                icon: const Icon(Icons.play_arrow),
                label: const Text('播放全部'),
                onPressed: p.music.isEmpty
                    ? null
                    : () {
                        svc.engine.playMusic(p.music.first,
                            view: 'playlist', queue: p.music);
                        Navigator.push(context, PlayerPage.route());
                      },
              ),
              const Spacer(),
              if (_selectMode)
                TextButton(
                  onPressed: () => _confirmBatchDelete(svc, p),
                  child: const Text('删除所选'),
                )
              else
                IconButton(
                  icon: const Icon(Icons.checklist),
                  tooltip: '批量操作',
                  onPressed: () =>
                      setState(() => _selectMode = !_selectMode),
                ),
              if (_selectMode)
                TextButton(
                  onPressed: () => setState(() {
                    _selectMode = false;
                    _selected.clear();
                  }),
                  child: const Text('完成'),
                ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: p.music.length,
            itemBuilder: (context, i) {
              final t = p.music[i];
              final key = '${t.bvid}:${t.favId ?? i}:${t.favType ?? ''}:$i';
              return TrackTile(
                track: t,
                trailing: _selectMode
                    ? Checkbox(
                        value: _selected.contains(key),
                        onChanged: (v) => setState(() {
                          if (v == true) {
                            _selected.add(key);
                          } else {
                            _selected.remove(key);
                          }
                        }),
                      )
                    : null,
                onPlay: () {
                  if (_selectMode) return;
                  svc.engine.playMusic(t, view: 'playlist', queue: p.music);
                  Navigator.push(context, PlayerPage.route());
                },
                onPlayNext: () async {
                  final queued = await svc.engine.playNextLater(t);
                  if (context.mounted) {
                    showToast(context, queued ? '已添加到下一首' : '开始播放');
                  }
                },
                onDownload: (track) {
                  svc.downloads.downloadMusic(track);
                  showToast(context, '开始下载：${track.title}');
                },
                onShowSeries: () => svc.engine.loadEpisodes(t.bvid),
              );
            },
          ),
        ),
      ],
    );
  }

  void _confirmBatchDelete(AppServices svc, Playlist p) async {
    if (_selected.isEmpty) {
      showToast(context, '请先选择歌曲');
      return;
    }
    final ok = await appConfirm(context,
        title: '批量删除',
        message: '确定删除选中的 ${_selected.length} 首歌曲？',
        okText: '删除');
    if (!ok) return;
    final selectedKeys = Set<String>.from(_selected);
    final selectedTracks = <Track>[];
    for (var i = 0; i < p.music.length; i++) {
      final t = p.music[i];
      final key = '${t.bvid}:${t.favId ?? i}:${t.favType ?? ''}:$i';
      if (selectedKeys.contains(key)) selectedTracks.add(t);
    }
    for (final t in selectedTracks) {
      p.removeTrack(t);
    }
    svc.playlists.save();
    setState(() {
      _selected.clear();
      _selectMode = false;
    });
    if (!mounted) return;
    showToast(context, '已删除 ${selectedTracks.length} 首歌曲');
  }

  Future<void> _loadBiliFavorites(AppServices svc, Playlist p) async {
    setState(() {
      _loadingBili = true;
      _biliProgress = '正在获取收藏列表…';
    });
    try {
      final tracks = await svc.user.loadAllFavoriteResources(
        p,
        onProgress: (current, total, loaded) {
          if (mounted) {
            setState(() {
              _biliProgress = '加载中 $current/$total（已获取 $loaded 首）';
            });
          }
        },
      );
      if (!mounted) return;
      setState(() => _biliProgress = '');
      svc.playlists.updateBiliFavoriteMusic(p.id, tracks);
      showToast(context, '已加载 ${tracks.length} 首歌曲');
    } catch (e) {
      if (mounted) {
        setState(() => _biliProgress = '');
        showToast(context, '加载失败：${e.toString()}');
      }
    }
    if (mounted) setState(() => _loadingBili = false);
  }
}

/// 歌单封面（B 站收藏夹用收藏数，本地歌单用第一首封面）
class _PlaylistCover extends StatelessWidget {
  final Playlist p;
  const _PlaylistCover(this.p);

  @override
  Widget build(BuildContext context) {
    if (p.cover.isNotEmpty) {
      return Image.network(p.cover, fit: BoxFit.cover);
    }
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: const Icon(Icons.queue_music, color: Colors.white24),
    );
  }
}
