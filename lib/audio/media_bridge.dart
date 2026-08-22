import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_media_session/flutter_media_session.dart';
import 'package:flutter_media_session/flutter_media_session_platform_interface.dart';
import 'package:path_provider/path_provider.dart';

import '../app.dart';
import '../models/track.dart';

/// 系统媒体控制桥接（通知栏 / 锁屏 / 蓝牙耳机 / 系统媒体中心）
///
/// 底层由 [flutter_media_session](https://pub.dev/packages/flutter_media_session)
/// 提供原生实现：Android 用 androidx.media3 的 MediaSessionService（Android
/// 15/16 官方推荐架构），iOS/macOS 用 MPNowPlayingInfoCenter，Windows/Web 用
/// 系统媒体传输控件。
///
/// 相比旧 audio_service 桥接的关键差异：
/// - 插件自带「服务未就绪时暂存元数据/状态、服务就绪后补发」机制
///   （pending sync），根治了 audio_service 上「服务未启动 → setMediaItem
///   静默丢失 → 通知卡片无歌曲信息且永不刷新」的问题；
/// - 前台服务与通知由 Media3 原生管线（MediaNotificationManager）管理，
///   无需自建 MediaStyle 通知与前台逻辑；
/// - 播放进度由服务端自增位置提供，系统进度条自动走动，无需高频推送。
///
/// 取舍：该插件无队列（playlist）API——系统侧显示当前曲目 + 上一曲/下一曲
/// + 进度条，不提供 Android Auto 的队列列表（audio_service 队列功能放弃）。
class PinkMediaBridge implements MediaSessionAdapter {
  bool _attached = false;
  String? _lastItemId;
  String? _lastArtUrl;
  StreamSubscription<MediaAction>? _actionSub;
  final Map<String, Future<String?>> _artFutures = {};
  bool _actionsPushed = false;

  void attach() {
    if (_attached) return;
    _attached = true;
    _init();
    AppServices.instance.player.addListener(_sync);
  }

  Future<void> _init() async {
    try {
      // Android：绑定媒体服务并自动请求通知权限（Android 13+）。
      // 返回前服务可能尚未创建，插件会暂存后续的元数据/状态并在服务就绪后补发。
      await FlutterMediaSession().activate();
    } catch (e) {
      debugPrint('PinkMediaBridge.activate error: $e');
    }
    bind(FlutterMediaSession());
    _ensureActions();
    _sync();
  }

  @override
  void bind(FlutterMediaSession session) {
    unbind();
    _actionSub = FlutterMediaSessionPlatform.instance.onMediaAction.listen(
      _onAction,
      onError: (Object e) => debugPrint('PinkMediaBridge action error: $e'),
    );
  }

  @override
  void unbind() {
    _actionSub?.cancel();
    _actionSub = null;
  }

  void _onAction(MediaAction action) {
    if (!AppServices.instanceReady) return;
    final engine = AppServices.instance.engine;
    final playerStore = AppServices.instance.player;
    switch (action.name) {
      case 'play':
        if (!playerStore.isPlaying) {
          unawaited(engine.togglePlay());
        }
        break;
      case 'pause':
        if (playerStore.isPlaying) {
          unawaited(engine.togglePlay());
        }
        break;
      case 'skipToNext':
        unawaited(engine.playNext());
        break;
      case 'skipToPrevious':
        unawaited(engine.playPrevious());
        break;
      case 'seekTo':
        final p = action.seekPosition;
        if (p != null) {
          unawaited(engine.seek(p.inMilliseconds / 1000.0));
        }
        break;
      case 'stop':
        // 无停止语义：映射为暂停（对齐旧桥接）。
        if (playerStore.isPlaying) {
          unawaited(engine.togglePlay());
        }
        break;
      case 'shuffle':
        playerStore.setPlayMode(
            playerStore.playMode == 'shuffle' ? 'order' : 'shuffle');
        break;
      case 'repeat':
        playerStore.setPlayMode(switch (playerStore.playMode) {
          'order' => 'loop',
          'loop' => 'single',
          _ => 'order',
        });
        break;
    }
  }

  // ── 状态同步 ─────────────────────────────────────────────────────────

  void _sync() {
    if (!AppServices.instanceReady) return;
    final store = AppServices.instance.player;
    final track = store.currentTrack;
    if (track == null) {
      if (_lastItemId != null) {
        _lastItemId = null;
        _lastArtUrl = null;
        _pushMetadata(const MediaMetadata(
            title: null, artist: null, album: null, artworkUri: null));
      }
      _pushState(
        status: store.audioError.isNotEmpty
            ? PlaybackStatus.error
            : PlaybackStatus.idle,
        position: Duration.zero,
        bufferedPosition: Duration.zero,
        repeatMode: MediaRepeatMode.none,
        shuffleModeEnabled: false,
      );
      return;
    }

    final id = _trackId(track);
    if (id != _lastItemId) {
      _lastItemId = id;
      _pushMetadata(_metadataFor(track));
    }
    _pushState(
      status: store.audioError.isNotEmpty
          ? PlaybackStatus.error
          : store.isAudioLoading
              ? PlaybackStatus.buffering
              : store.isPlaying
                  ? PlaybackStatus.playing
                  : PlaybackStatus.paused,
      position: Duration(milliseconds: (store.currentTime * 1000).round()),
      bufferedPosition: Duration(
          milliseconds:
              (store.duration * store.bufferedProgress / 100 * 1000).round()),
      repeatMode: switch (store.playMode) {
        'single' => MediaRepeatMode.one,
        'loop' => MediaRepeatMode.all,
        _ => MediaRepeatMode.none,
      },
      shuffleModeEnabled: store.playMode == 'shuffle',
    );
  }

  /// 曲目标识：标题 + 作者 + cid（多P 切P 时标题可能相同，cid 区分；
  /// 重播同一曲目时不变，避免无意义重推）。
  String _trackId(Track t) =>
      '${t.title}|${t.author}|${t.cid ?? ''}';

  MediaMetadata _metadataFor(Track t) {
    final art = _cover512(t.cover);
    _lastArtUrl = art;
    if (art != null) _prepareLocalArtwork(art);
    return _buildMetadata(t, art);
  }

  MediaMetadata _buildMetadata(Track t, String? artworkUri) => MediaMetadata(
        title: t.title.isEmpty ? 'Pink Music' : t.title,
        artist: t.author.isEmpty ? null : t.author,
        album: 'Pink Music',
        artworkUri: artworkUri,
        duration: Duration(seconds: t.duration.toInt()),
      );

  void _pushMetadata(MediaMetadata metadata) {
    // ignore: discarded_futures
    FlutterMediaSessionPlatform.instance
        .updateMetadata(metadata)
        .catchError((Object e) {
      debugPrint('PinkMediaBridge.updateMetadata error: $e');
    });
  }

  void _pushState({
    required PlaybackStatus status,
    required Duration position,
    required Duration bufferedPosition,
    required MediaRepeatMode repeatMode,
    required bool shuffleModeEnabled,
  }) {
    // ignore: discarded_futures
    FlutterMediaSessionPlatform.instance
        .updatePlaybackState(PlaybackState(
      status: status,
      position: position,
      speed: 1.0,
      bufferedPosition: bufferedPosition,
      repeatMode: repeatMode,
      shuffleModeEnabled: shuffleModeEnabled,
    ))
        .catchError((Object e) {
      debugPrint('PinkMediaBridge.updatePlaybackState error: $e');
    });
  }

  /// 系统媒体中心的可用动作：播放/暂停/上一曲/下一曲/拖动进度。
  /// （shuffle/repeat 按钮不启用，播放模式在 App 内切换。）
  void _ensureActions() {
    if (_actionsPushed) return;
    _actionsPushed = true;
    // ignore: discarded_futures
    FlutterMediaSessionPlatform.instance
        .updateAvailableActions(<MediaAction>{
      MediaAction.play,
      MediaAction.pause,
      MediaAction.skipToNext,
      MediaAction.skipToPrevious,
      MediaAction.seekTo,
    })
        .catchError((Object e) {
      debugPrint('PinkMediaBridge.updateAvailableActions error: $e');
    });
  }

  // ── 封面 ──────────────────────────────────────────────────────────────

  /// 列表封面是 ?w=300，通知栏/锁屏大图用更高分辨率。
  static String? _cover512(String cover) {
    if (cover.isEmpty) return null;
    var u = cover;
    if (u.contains('hdslb.com') || u.contains('bilibili.com')) {
      u = u.replaceFirst(RegExp(r'[?&]w=\d+'), '?w=512');
      if (!u.contains('w=512')) {
        u = '$u${u.contains('?') ? '&' : '?'}w=512';
      }
    }
    return u;
  }

  /// Media3 默认 BitmapLoader 无法加载网络 artworkUri，需先下载到本地
  /// 文件再推送 file:// 路径。下载完成后若仍是当前曲目则重推一次元数据。
  void _prepareLocalArtwork(String url) {
    if (_artFutures.containsKey(url)) return;
    _artFutures[url] = _loadArtworkAndRepush(url);
  }

  Future<String?> _loadArtworkAndRepush(String url) async {
    try {
      final local = await _downloadArt(url);
      if (local != null && _lastArtUrl == url) {
        final track = AppServices.instance.player.currentTrack;
        if (track != null && _trackId(track) == _lastItemId) {
          _pushMetadata(_buildMetadata(track, local));
        }
      }
      return local;
    } catch (e) {
      debugPrint('PinkMediaBridge artwork error: $e');
      return null;
    }
  }

  Future<String?> _downloadArt(String url) async {
    try {
      final dir = await getTemporaryDirectory();
      final digest = md5.convert(utf8.encode(url)).toString();
      const ext = 'jpg';
      final file = File('${dir.path}${Platform.pathSeparator}pink_art_$digest.$ext');
      if (!await file.exists()) {
        final resp = await Dio().get<List<int>>(
          url,
          options: Options(responseType: ResponseType.bytes),
        );
        final data = resp.data;
        if (data == null || data.isEmpty) return null;
        await file.writeAsBytes(data, flush: true);
      }
      return file.uri.toString();
    } catch (e) {
      debugPrint('PinkMediaBridge art download failed: $e');
      return null;
    }
  }
}