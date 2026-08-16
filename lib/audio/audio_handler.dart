import 'package:audio_service/audio_service.dart';

import '../app.dart';
import '../models/track.dart';

/// 系统媒体控制桥接（通知栏 / 锁屏 / 蓝牙耳机）
/// 对应原项目"适配系统自带音频控件"
class PinkAudioHandler extends BaseAudioHandler with SeekHandler {
  bool _attached = false;
  String? _lastMediaItemId;

  void attach() {
    if (_attached) return;
    _attached = true;
    AppServices.instance.player.addListener(_sync);
    _sync();
  }

  void _sync() {
    if (!AppServices.instanceReady) return;
    final store = AppServices.instance.player;
    final track = store.currentTrack;
    if (track == null) {
      if (_lastMediaItemId != null) {
        _lastMediaItemId = null;
        mediaItem.add(null);
        queue.add([]);
      }
      return;
    }

    // 仅在切歌时重发 mediaItem / queue，避免每次位置更新都重渲染通知导致闪烁
    final id = track.bvid.isEmpty ? 'fav:${track.favId ?? track.title}' : track.bvid;
    if (_lastMediaItemId != id) {
      _lastMediaItemId = id;
      mediaItem.add(_toMediaItem(track));
      final q = store.currentQueue;
      if (q.isNotEmpty) {
        queue.add(q.map(_toMediaItem).toList());
        queueTitle.add('播放队列');
      }
    }

    final queueIndex = store.currentQueueIndex;
    playbackState.add(PlaybackState(
      controls: [
        MediaControl.skipToPrevious,
        if (store.isPlaying) MediaControl.pause else MediaControl.play,
        MediaControl.skipToNext,
      ],
      systemActions: const {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
      },
      androidCompactActionIndices: const [0, 1, 2],
      processingState: store.isAudioLoading
          ? AudioProcessingState.loading
          : AudioProcessingState.ready,
      playing: store.isPlaying,
      updatePosition: Duration(milliseconds: (store.currentTime * 1000).round()),
      bufferedPosition: Duration(
          milliseconds:
              (store.duration * store.bufferedProgress / 100 * 1000).round()),
      speed: 1.0,
      queueIndex: queueIndex >= 0 ? queueIndex : null,
    ));
  }

  MediaItem _toMediaItem(Track t) => MediaItem(
        id: t.bvid.isEmpty ? 'fav:${t.favId ?? t.title}' : t.bvid,
        title: t.title,
        artist: t.author,
        album: 'Pink Music',
        // 封面：提升到 512 宽，供通知栏大图 / 超级岛高清展示
        artUri: _artUri(t.cover),
        duration: Duration(seconds: t.duration.toInt()),
      );

  static Uri? _artUri(String cover) {
    if (cover.isEmpty) return null;
    var u = cover;
    // 列表封面是 ?w=300，通知栏/超级岛用更高分辨率
    if (u.contains('hdslb.com') || u.contains('bilibili.com')) {
      u = u.replaceFirst(RegExp(r'[?&]w=\d+'), '?w=512');
      if (!u.contains('w=512')) {
        u = '$u${u.contains('?') ? '&' : '?'}w=512';
      }
    }
    return Uri.tryParse(u);
  }

  @override
  Future<void> play() async {
    if (!AppServices.instanceReady) return;
    final engine = AppServices.instance.engine;
    if (!engine.playerStore.isPlaying) await engine.togglePlay();
  }

  @override
  Future<void> pause() async {
    if (!AppServices.instanceReady) return;
    final engine = AppServices.instance.engine;
    if (engine.playerStore.isPlaying) await engine.togglePlay();
  }

  @override
  Future<void> skipToNext() async {
    if (!AppServices.instanceReady) return;
    await AppServices.instance.engine.playNext();
  }

  @override
  Future<void> skipToPrevious() async {
    if (!AppServices.instanceReady) return;
    await AppServices.instance.engine.playPrevious();
  }

  @override
  Future<void> seek(Duration position) async {
    if (!AppServices.instanceReady) return;
    await AppServices.instance.engine.seek(position.inMilliseconds / 1000.0);
  }

  @override
  Future<void> stop() async {
    if (AppServices.instanceReady) {
      final engine = AppServices.instance.engine;
      if (engine.playerStore.isPlaying) await engine.togglePlay();
    }
    await super.stop();
  }
}
