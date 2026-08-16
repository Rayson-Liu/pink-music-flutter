import 'package:flutter/material.dart';

import '../../app.dart';
import '../../models/episode.dart';
import '../../models/track.dart';
import 'dialogs.dart';

/// 把曲目加入歌单的入口：多分P 视频先选分P，再选目标歌单；单P 直接选歌单。
/// 对应原项目 openAddPSelect / addSelectedPsToPlaylist / pushTracksToPlaylist。
Future<void> addTrackToPlaylist(BuildContext context, Track track) async {
  final svc = AppServices.instance;
  if (track.bvid.isEmpty && track.favId == null) return;

  // 1. 检测多P：与原项目一致，不依赖 videos 字段，只要有 bvid 就拉取分P列表。
  //    （推荐流 / 收藏夹里 videos 常为 0，但视频本身可能是多P）
  var episodes = <Episode>[];
  if (track.bvid.isNotEmpty) {
    try {
      episodes = await svc.api.getVideoEpisodes(track.bvid);
    } catch (_) {
      episodes = [];
    }
  }
  final isMultiP = episodes.length > 1;

  if (!context.mounted) return;

  // 2. 多P：让用户勾选要加入的分P
  final selectedCids = <num>{};
  if (isMultiP) {
    final result = await showModalBottomSheet<Set<num>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (_) => _PartSelectSheet(source: track, episodes: episodes),
    );
    if (result == null || result.isEmpty) return;
    selectedCids.addAll(result);
  }

  if (!context.mounted) return;

  // 3. 选择目标歌单
  final playlistId = await _pickPlaylist(context);
  if (playlistId == null) return;

  // 4. 构造待添加曲目（分P 继承整稿信息 + 各自 cid/标题/时长/封面）
  final tracks = <Track>[];
  if (isMultiP) {
    for (final ep in episodes) {
      if (selectedCids.contains(ep.cid)) {
        tracks.add(buildEpisodeTrack(ep, track));
      }
    }
  } else {
    tracks.add(track);
  }
  if (tracks.isEmpty) return;

  final added = svc.playlists.pushTracksToPlaylist(playlistId, tracks);
  if (context.mounted) {
    showToast(context, added > 0 ? '已添加 $added 首到歌单' : '所选歌曲已在歌单中');
  }
}

/// 构造分P对应的 Track：继承整稿信息，写入 cid / part 标题 / 分P时长 / 分P封面
Track buildEpisodeTrack(Episode ep, Track source) {
  return Track(
    bvid: source.bvid,
    aid: source.aid,
    cid: ep.cid,
    title: ep.title.isNotEmpty ? ep.title : source.title,
    author: source.author,
    cover: ep.firstFrame.isNotEmpty
        ? Track.fixCoverUrl(ep.firstFrame)
        : source.cover,
    duration: ep.duration > 0 ? ep.duration : source.duration,
    playCount: source.playCount,
    pubdate: source.pubdate,
    description: source.description,
    recReason: source.recReason,
    videos: source.videos,
  );
}

const String _createSentinel = '__create_new__';

/// 选目标歌单（返回歌单 id；"新建歌单"先提示命名再创建）
Future<String?> _pickPlaylist(BuildContext context) async {
  final svc = AppServices.instance;
  final result = await showModalBottomSheet<String>(
    context: context,
    builder: (ctx) {
      final items = svc.playlists.userPlaylists
          .where((p) => !p.isBiliFavorite)
          .toList();
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text('添加到歌单',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: items.length + 1,
                itemBuilder: (ctx, i) {
                  if (i == 0) {
                    return ListTile(
                      leading: const Icon(Icons.add),
                      title: const Text('新建歌单'),
                      onTap: () => Navigator.pop(ctx, _createSentinel),
                    );
                  }
                  final p = items[i - 1];
                  return ListTile(
                    leading: const Icon(Icons.queue_music),
                    title: Text(p.name),
                    trailing: Text('${p.music.length} 首',
                        style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context).hintColor)),
                    onTap: () => Navigator.pop(ctx, p.id),
                  );
                },
              ),
            ),
          ],
        ),
      );
    },
  );

  if (result == _createSentinel) {
    if (!context.mounted) return null;
    final name = await promptText(context, title: '新建歌单');
    if (name == null || name.trim().isEmpty) return null;
    final p = svc.playlists.createPlaylist(name.trim());
    return p.id;
  }
  return result;
}

/// 分P 选择弹层（勾选 + 全选 + 下一步）
class _PartSelectSheet extends StatefulWidget {
  final Track source;
  final List<Episode> episodes;
  const _PartSelectSheet({required this.source, required this.episodes});

  @override
  State<_PartSelectSheet> createState() => _PartSelectSheetState();
}

class _PartSelectSheetState extends State<_PartSelectSheet> {
  final Set<num> _selected = {};

  @override
  Widget build(BuildContext context) {
    final allSelected =
        _selected.length == widget.episodes.length && widget.episodes.isNotEmpty;
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.62,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${widget.source.title}\n（共 ${widget.episodes.length} P）',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                  ),
                  TextButton(
                    onPressed: () => setState(() {
                      if (allSelected) {
                        _selected.clear();
                      } else {
                        _selected.addAll(widget.episodes.map((e) => e.cid));
                      }
                    }),
                    child: Text(allSelected ? '取消全选' : '全选'),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                itemCount: widget.episodes.length,
                itemBuilder: (context, i) {
                  final ep = widget.episodes[i];
                  final selected = _selected.contains(ep.cid);
                  return CheckboxListTile(
                    value: selected,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: Text(
                      ep.title.isEmpty ? '第 ${i + 1} 话' : ep.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(_fmtDuration(ep.duration)),
                    onChanged: (v) => setState(() {
                      if (v == true) {
                        _selected.add(ep.cid);
                      } else {
                        _selected.remove(ep.cid);
                      }
                    }),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('取消'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: _selected.isEmpty
                          ? null
                          : () => Navigator.pop(
                              context, Set<num>.from(_selected)),
                      child: Text('下一步（已选 ${_selected.length}）'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _fmtDuration(num sec) {
    final s = sec.toInt();
    final m = s ~/ 60;
    final r = s % 60;
    return '$m:${r.toString().padLeft(2, '0')}';
  }
}
