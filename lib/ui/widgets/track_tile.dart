import 'package:flutter/material.dart';

import '../../models/track.dart';
import 'add_to_playlist.dart';
import 'cover_image.dart';

/// 歌曲列表项（对应原项目音乐卡片/列表行）
class TrackTile extends StatelessWidget {
  final Track track;
  final VoidCallback onPlay;
  final VoidCallback? onPlayNext;
  final void Function(Track)? onDownload;
  final VoidCallback? onShowSeries;
  final bool showSubtitle;
  final Widget? trailing;

  const TrackTile({
    super.key,
    required this.track,
    required this.onPlay,
    this.onPlayNext,
    this.onDownload,
    this.onShowSeries,
    this.showSubtitle = true,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtitle = showSubtitle
        ? '${track.author} · ${_formatDuration(track.duration.toInt())}'
            '${track.playCount > 0 ? ' · ${_formatCount(track.playCount)}' : ''}'
        : '';
    final hasMultiP = track.videos > 1;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      leading: Stack(
        children: [
          CoverImage(url: track.cover, size: 48),
          if (track.playCount > 0)
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: const BorderRadius.only(
                      bottomRight: Radius.circular(10)),
                ),
                child: Text(
                  _formatCount(track.playCount),
                  style: const TextStyle(color: Colors.white, fontSize: 8),
                ),
              ),
            ),
        ],
      ),
      title: Text(
        track.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
      ),
      subtitle: subtitle.isEmpty
          ? null
          : Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: theme.hintColor),
            ),
      trailing: trailing ?? PopupMenuButton<String>(
        icon: const Icon(Icons.more_horiz),
        onSelected: (v) => _handleMenu(context, v),
        itemBuilder: (context) => [
          const PopupMenuItem(value: 'play', child: Text('播放')),
          if (onPlayNext != null)
            const PopupMenuItem(value: 'next', child: Text('下一首播放')),
          const PopupMenuItem(value: 'playlist', child: Text('添加到歌单')),
          if (onDownload != null)
            const PopupMenuItem(value: 'download', child: Text('下载')),
          if (hasMultiP && onShowSeries != null)
            const PopupMenuItem(value: 'series', child: Text('分P')),
        ],
      ),
      onTap: onPlay,
    );
  }

  void _handleMenu(BuildContext context, String value) {
    switch (value) {
      case 'play':
        onPlay();
      case 'next':
        onPlayNext?.call();
      case 'download':
        onDownload?.call(track);
      case 'playlist':
        addTrackToPlaylist(context, track);
      case 'series':
        onShowSeries?.call();
    }
  }

  static String _formatDuration(int sec) {
    final m = sec ~/ 60;
    final s = sec % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  static String _formatCount(num count) {
    if (count >= 100000000) return '${(count / 100000000).toStringAsFixed(1)}亿';
    if (count >= 10000) return '${(count / 10000).toStringAsFixed(1)}万';
    return count.toString();
  }
}
