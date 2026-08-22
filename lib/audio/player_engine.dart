import 'dart:async';
import 'dart:math';

import 'package:audio_session/audio_session.dart';
import 'package:just_audio/just_audio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/episode.dart';
import '../models/track.dart';
import '../services/audio_stream.dart';
import '../services/bilibili_api.dart';
import '../services/cookie_store.dart';
import '../services/http_client.dart';
import '../state/lyric_store.dart';
import '../state/player_store.dart';
import '../state/search_store.dart';
import '../state/settings_store.dart';
import 'eq_controller.dart';

/// 播放引擎（对应原项目 App.vue 中的音频逻辑）
class PlayerEngine {
  final AudioPlayer player = AudioPlayer(
    // 关键修复：just_audio 默认 useProxyForRequestHeaders=true 时，请求头经「本地
    // HTTP 代理」注入，Android 需要启用明文(cleartext)流量才可用；否则报
    // "Source error"。改为 false 走 ExoPlayer 原生 setUserAgent/setDefaultRequestProperties。
    useProxyForRequestHeaders: false,
    // B 站 CDN 对非浏览器 UA 返回 403，必须显式传浏览器 UA。
    userAgent:
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
  );
  final BilibiliApi api;
  final CookieStore cookies;
  final PlayerStore playerStore;
  final SearchStore searchStore;
  final SettingsStore settingsStore;
  final LyricStore lyricStore;
  final EqController eqController;

  final Map<String, String> _streamHeaders = {
    'Referer': 'https://www.bilibili.com/',
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
            '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
  };

  late final StreamSubscription<Duration> _positionSub;
  late final StreamSubscription<Duration?> _durationSub;
  late final StreamSubscription<PlaybackEvent> _eventSub;
  late final StreamSubscription<PlayerState> _stateSub;
  late final StreamSubscription<int?> _sessionSub;
  StreamSubscription<void>? _noisySub;

  String _currentPlayUrl = '';
  int _retryCount = 0;
  bool _retrying = false;
  String _lastPlayError = '';
  final Random _random = Random();

  PlayerEngine({
    required this.api,
    required this.cookies,
    required this.lyricStore,
    required this.playerStore,
    required this.searchStore,
    required this.settingsStore,
    required this.eqController,
  }) {
    _listen();
  }

  Future<void> init() async {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());
    // 拔出耳机 / 断开蓝牙：自动暂停，避免音频在扬声器上外放
    // （Android ACTION_AUDIO_BECOMING_NOISY，对应「蓝牙设备控制」体验闭环）
    _noisySub = session.becomingNoisyEventStream.listen((_) {
      if (player.playing) {
        player.pause();
      }
    });
  }

  void _listen() {
    _positionSub = player.positionStream.listen((pos) {
      final t = pos.inMilliseconds / 1000.0;
      playerStore.setCurrentTime(t);
      lyricStore.updateCurrentLine(t);
    });
    _durationSub = player.durationStream.listen((dur) {
      playerStore.setDuration(
          dur != null ? dur.inMilliseconds / 1000.0 : 180);
    });
    _eventSub = player.playbackEventStream.listen((event) {
      if (event.errorCode != null) {
        _onPlaybackError(event.errorCode!, event.errorMessage ?? '音频加载失败');
        return;
      }
      final buffered = event.bufferedPosition;
      final duration = player.duration;
      if (duration != null && duration.inMilliseconds > 0) {
        playerStore.setBuffered(
            ((buffered.inMilliseconds / duration.inMilliseconds) * 100)
                .round()
                .clamp(0, 100));
      }
      if (event.processingState == ProcessingState.completed) {
        _handleTrackEnd();
      }
    });
    _stateSub = player.playerStateStream.listen((state) {
      playerStore.setPlaying(state.playing && state.processingState != ProcessingState.completed);
      playerStore.setAudioLoading(state.processingState == ProcessingState.loading);
    });
    _sessionSub = player.androidAudioSessionIdStream.listen((sessionId) {
      if (sessionId != null) {
        eqController.attach(sessionId);
        _syncEq();
      }
    });
  }

  // ---------- 播放 ----------

  Future<void> playMusic(
    Track track, {
    String view = 'home',
    List<Track>? queue,
  }) async {
    if (track.bvid.isEmpty && track.favId == null) {
      playerStore.setAudioError('该收藏内容暂不支持播放');
      return;
    }
    // Android 13+：若启动时的通知权限弹窗被忽略/未授，媒体通知与系统媒体
    // 控制（通知栏卡片 / 锁屏 / Android Auto）都不会出现。首次点播时再请求
    // 一次（已授权时原生侧幂等直接返回，无副作用）。
    if (defaultTargetPlatform == TargetPlatform.android) {
      try {
        const channel = MethodChannel('com.pinkmusic.app/permissions');
        await channel.invokeMethod('requestNotificationPermission');
      } catch (_) {
        // 通道未实现/失败不阻塞播放
      }
    }
    _retryCount = 0;
    _retrying = false;
    playerStore.setAudioError('');
    // 关键：先设置队列上下文，再设置当前曲目。否则 _sync 在 setCurrentTrack 的
    // 首次 notify 里推送 mediaItem/queue 时，currentQueue 仍是空（q.isNotEmpty
    // 为 false，queue 被跳过），而第二次 notify 的 id 未变又被守卫挡住——
    // 系统媒体控制（锁屏队列 / Android Auto）永远拿不到队列与完整歌曲信息。
    if (queue != null) {
      playerStore.setQueueContext(view, queue);
    } else {
      playerStore.setQueueContext(view, [track]);
    }
    playerStore.setCurrentTrack(track);
    // 多P：自动加载分P列表
    if (track.videos > 1) {
      loadEpisodes(track.bvid);
    } else {
      playerStore.setEpisodes([]);
    }
    await _loadAndPlay(track);
  }

  Future<void> _loadAndPlay(Track track) async {
    var resolved = track;
    var cid = track.cid;
    if (cid == null) {
      try {
        final info = await api.getMusicInfo(track.bvid);
        cid = info['cid'];
        if (info['videos'] != null && (info['videos'] as num) > 1 &&
            playerStore.currentVideoEpisodes.isEmpty) {
          loadEpisodes(track.bvid);
        }
        if (cid != null) {
          // 回写 cid，供重试/分P逻辑使用（recordHistory:false 避免重复入历史；
          // 走 setCurrentTrack 保证 UI 与系统媒体中心同步刷新）
          resolved = track.copyWith(cid: cid);
          playerStore.setCurrentTrack(resolved, recordHistory: false);
        }
      } catch (e) {
        debugPrint('获取视频信息失败: $e');
        // 网络抖动/风控偶发：重试一次
        try {
          await Future<void>.delayed(const Duration(milliseconds: 600));
          final info = await api.getMusicInfo(track.bvid);
          cid = info['cid'];
          if (cid != null) {
            resolved = track.copyWith(cid: cid);
            playerStore.setCurrentTrack(resolved, recordHistory: false);
          }
        } catch (e2) {
          debugPrint('获取视频信息重试失败: $e2');
          playerStore.setAudioError(_infoErrorMessage(e2));
          return;
        }
      }
    }
    if (cid == null) {
      playerStore.setAudioError('播放失败：cid 为空');
      return;
    }

    final data = await _fetchPlayUrl(track.bvid, cid);
    if (data == null) return;
    final candidates = selectAudioCandidates(data, settingsStore.audioQuality);
    if (candidates.isEmpty) {
      playerStore.setAudioError('播放失败：无可用音源');
      return;
    }
    debugPrint('播放候选: ${candidates.map((c) => c.label).join(' > ')}');
    await _playStream(resolved, candidates);
  }

  String _urlHost(String url) {
    try {
      return Uri.parse(url).host;
    } catch (_) {
      return url.substring(0, url.length > 40 ? 40 : url.length);
    }
  }

  /// 把 getMusicInfo 的异常转成可读的播放失败文案
  String _infoErrorMessage(Object e) {
    if (e is ApiException) return '播放失败：${e.message} (${e.code})';
    final s = e.toString();
    if (s.contains('connectionTimeout') ||
        s.contains('connectionError') ||
        s.contains('SocketException') ||
        s.contains('Failed host lookup')) {
      return '播放失败：网络异常，请检查网络后重试';
    }
    return '播放失败：无法获取视频信息';
  }

  /// 获取播放地址；失败时设置错误文案并返回 null
  Future<Map<String, dynamic>?> _fetchPlayUrl(String bvid, num cid,
      {bool anonymous = false}) async {
    try {
      final data = await api.getMusicPlayUrl(bvid, cid,
          useCookies: !anonymous);
      debugPrint('播放地址${anonymous ? '(匿名)' : ''}获取成功');
      return data;
    } on ApiException catch (e) {
      debugPrint('获取播放地址失败: ${e.code} ${e.message}');
      playerStore.setAudioError('播放失败：获取播放地址被拒 (${e.code} ${e.message})');
      return null;
    } catch (e) {
      debugPrint('获取播放地址失败: $e');
      playerStore.setAudioError('播放失败：网络异常');
      return null;
    }
  }

  /// 候选链播放：FLAC→DASH各档→durl，每档依次尝试 主/备地址 × 带/不带 Cookie。
  /// 任一候选成功返回 true；全部失败时触发重试并返回 false（供重试链补错误文案）。
  Future<bool> _playStream(Track track, List<StreamInfo> candidates) async {
    for (final stream in candidates) {
      final urls = <String>[stream.url, ...stream.backupUrls];
      for (final url in urls) {
        if (url.isEmpty || url == 'null') continue;
        if (url == _currentPlayUrl && player.playing) return true;
        for (final withCookie in [true, false]) {
          try {
            _currentPlayUrl = url;
            await player.setUrl(
              url,
              headers: withCookie
                  ? _streamHeadersWithCookie()
                  : Map.of(_streamHeaders),
              tag: <String, String>{
                'title': track.title,
                'author': track.author,
                'url': url,
              },
            );
            // 播放成功：清掉之前的错误文案
            playerStore.setAudioError('');
            await player.play();
            debugPrint('播放成功: ${stream.label} host=${_urlHost(url)}');
            return true;
          } catch (e) {
            _lastPlayError = '$e';
            debugPrint('播放流失败(${stream.label} '
                '${withCookie ? '带Cookie' : '无Cookie'}): $e');
          }
        }
      }
    }
    // 全部地址失败 → 统一走重试（事件流错误也可能同时触发，由 _retrying 去重）
    final detail = _lastPlayError.isEmpty ? '无可用音源' : _lastPlayError;
    _onPlaybackError(-1, detail);
    return false;
  }

  /// 拉流请求头：Referer + UA + 登录态 Cookie（对齐原项目 electron 的请求拦截器）
  Map<String, String> _streamHeadersWithCookie() {
    final header = Map<String, String>.from(_streamHeaders);
    final cookie = cookies.toHeader();
    if (cookie.isNotEmpty) header['Cookie'] = cookie;
    return header;
  }

  void _onPlaybackError(int code, String message) {
    debugPrint('播放错误($code): $message');
    if (message.isNotEmpty) _lastPlayError = message;
    if (_retrying) return; // 重试正在进行
    if (_retryCount >= 2) {
      final detail = _lastPlayError.isEmpty ? '' : '：${_shortError(_lastPlayError)}';
      playerStore.setAudioError('播放失败$detail');
      return;
    }
    _retryPlayback();
  }

  String _shortError(String s) => s.length > 120 ? s.substring(0, 120) : s;

  /// 重新获取播放地址并播放。
  /// 第 1 轮带登录态重试；第 2 轮走匿名 playurl（mid=0 地址最稳定）。
  Future<void> _retryPlayback() async {
    if (_retrying) return;
    _retrying = true;
    try {
      _retryCount++;
      _currentPlayUrl = '';
      final track = playerStore.currentTrack;
      if (track == null || track.bvid.isEmpty) {
        playerStore.setAudioError('播放失败');
        return;
      }
      final cid = track.cid;
      if (cid == null) {
        playerStore.setAudioError('播放失败');
        return;
      }
      final anonymous = _retryCount >= 2;
      final data = await _fetchPlayUrl(track.bvid, cid, anonymous: anonymous);
      if (data == null) return;
      final candidates =
          selectAudioCandidates(data, settingsStore.audioQuality);
      if (candidates.isEmpty) {
        playerStore.setAudioError('播放失败：无可用音源');
        return;
      }
      final ok = await _playStream(track, candidates);
      if (!ok) {
        // 重试链全部耗尽：必须在这里补出错误文案——重试期间 _onPlaybackError
        // 会被 _retrying 守卫吞掉，否则界面只剩「点了没反应」的静默失败。
        final detail = _lastPlayError.isEmpty
            ? ''
            : '：${_shortError(_lastPlayError)}';
        playerStore.setAudioError('播放失败$detail');
      }
    } catch (e) {
      debugPrint('重试播放失败: $e');
      _lastPlayError = '$e';
      playerStore.setAudioError('播放失败：${_shortError(_lastPlayError)}');
    } finally {
      _retrying = false;
    }
  }

  Future<void> togglePlay() async {
    if (playerStore.currentTrack == null) return;
    try {
      if (player.playing) {
        await player.pause();
      } else if (player.processingState == ProcessingState.idle) {
        // 空闲/错误态：just_audio 加载失败后 processingState 即回到 idle
        // （错误随 errorCode 播报），与「尚未加载」一样重新加载当前曲目
        _retryCount = 0;
        _lastPlayError = '';
        final track = playerStore.currentTrack;
        if (track != null) {
          await _loadAndPlay(track);
        }
      } else if (player.processingState == ProcessingState.completed) {
        // 播完态：just_audio 在 completed 上直接 play() 不会重新起播
        // （ExoPlayer 停在末尾，需先 seek 归零），这里归零后重播当前曲目。
        _retryCount = 0;
        _lastPlayError = '';
        await player.seek(Duration.zero);
        await player.play();
      } else {
        await player.play();
      }
    } catch (e) {
      debugPrint('togglePlay 失败: $e');
    }
  }

  Future<void> seek(double seconds) async {
    await player.seek(Duration(milliseconds: (seconds * 1000).round()));
  }

  Future<void> seekToRelative(double offsetSeconds) async {
    final target = playerStore.currentTime + offsetSeconds;
    await seek(target < 0 ? 0 : target);
  }

  // ---------- 上一首/下一首 ----------

  /// 对应原 App.vue 的 getNextMusicIndex
  int getNextMusicIndex() {
    final track = playerStore.currentTrack;
    if (track == null) return -1;
    final queue = playerStore.currentQueue;
    final current = playerStore.currentQueueIndex;
    if (queue.isEmpty || current < 0) return -1;
    final mode = playerStore.playMode;
    switch (mode) {
      case 'single':
        return current;
      case 'shuffle':
        if (queue.length == 1) return current;
        var next = current;
        while (next == current) {
          next = _random.nextInt(queue.length);
        }
        return next;
      case 'loop':
        return (current + 1) % queue.length;
      default: // order
        return current + 1 < queue.length ? current + 1 : -1;
    }
  }

  int getPreviousMusicIndex() {
    final queue = playerStore.currentQueue;
    final current = playerStore.currentQueueIndex;
    if (queue.isEmpty || current < 0) return -1;
    final mode = playerStore.playMode;
    if (mode == 'shuffle') {
      if (queue.length == 1) return current;
      var prev = current;
      while (prev == current) {
        prev = _random.nextInt(queue.length);
      }
      return prev;
    }
    return current > 0 ? current - 1 : queue.length - 1;
  }

  Future<void> playNext() async {
    // 分P优先
    if (playerStore.currentVideoEpisodes.isNotEmpty) {
      final eps = playerStore.currentVideoEpisodes;
      final idx = playerStore.currentEpisodeIndex;
      final mode = playerStore.playMode;
      int next;
      if (eps.length == 1) {
        next = 0;
      } else if (mode == 'shuffle') {
        // 与队列分支一致：随机时排除当前P，避免「下一首」原地不动
        do {
          next = _random.nextInt(eps.length);
        } while (next == idx);
      } else if (mode == 'order' && idx >= eps.length - 1) {
        // 顺序播放：最后一P 后停止（对齐原项目 getNextMusicIndex 的 order 语义）
        await player.pause();
        return;
      } else {
        next = (idx + 1) % eps.length;
      }
      await playEpisode(eps[next]);
      return;
    }
    final idx = getNextMusicIndex();
    if (idx == -1) {
      await player.pause();
      return;
    }
    final queue = playerStore.currentQueue;
    if (idx < queue.length) {
      // 关键：必须把当前 view + 完整队列回传 playMusic，否则它默认会
      // setQueueContext(view, [track]) 把队列重置为单曲，导致切到第二首后
      // 无论任何播放模式都无法再继续切歌（order 停、其余重复同一首）。
      await playMusic(queue[idx],
          view: playerStore.currentView, queue: playerStore.currentQueue);
    }
  }

  /// 「下一首播放」：把曲目插入到当前队列中当前曲目之后，不打断正在播放。
  /// 无播放 / 当前曲目不在队列时，直接开始播放。返回 true=已入队，false=直接播放。
  Future<bool> playNextLater(Track track) async {
    final store = playerStore;
    final q = store.currentQueue;
    final idx = store.currentQueueIndex;

    if (store.currentTrack == null || q.isEmpty || idx < 0) {
      await playMusic(track);
      return false;
    }

    // 去重：已在队列则忽略
    final exists = q.any((m) => m.bvid == track.bvid && m.cid == track.cid);
    if (exists) return true;

    final newQueue = List<Track>.from(q);
    newQueue.insert(idx + 1, track);
    store.setQueueContext(store.currentView, newQueue);
    return true;
  }

  Future<void> playPrevious() async {
    if (playerStore.currentVideoEpisodes.isNotEmpty) {
      final eps = playerStore.currentVideoEpisodes;
      final idx = playerStore.currentEpisodeIndex;
      int prev;
      if (playerStore.playMode == 'shuffle') {
        prev = _random.nextInt(eps.length);
      } else {
        prev = idx > 0 ? idx - 1 : eps.length - 1;
      }
      await playEpisode(eps[prev]);
      return;
    }
    final idx = getPreviousMusicIndex();
    final queue = playerStore.currentQueue;
    if (idx >= 0 && idx < queue.length) {
      // 同上：保留 view + 完整队列，避免 playMusic 把队列重置为单曲
      await playMusic(queue[idx],
          view: playerStore.currentView, queue: playerStore.currentQueue);
    }
  }

  Future<void> _handleTrackEnd() async {
    if (playerStore.playMode == 'single') {
      await player.seek(Duration.zero);
      await player.play();
      return;
    }
    playNext();
  }

  // ---------- 分P ----------

  Future<void> loadEpisodes(String bvid) async {
    playerStore.setIsLoadingEpisodes(true);
    try {
      final eps = await api.getVideoEpisodes(bvid);
      playerStore.setEpisodes(eps);
      final track = playerStore.currentTrack;
      if (track != null) {
        playerStore.setEpisodes(eps,
            activeIndex: eps.indexWhere((e) => e.cid == track.cid));
      } else {
        playerStore.setEpisodes(eps);
      }
    } catch (_) {
      playerStore.setEpisodes([]);
    }
    playerStore.setIsLoadingEpisodes(false);
  }

  Future<void> playEpisode(Episode ep) async {
    final track = playerStore.currentTrack;
    if (track == null) return;
    final merged = track.copyWith(
      cid: ep.cid,
      title: ep.title.isEmpty ? track.title : ep.title,
      duration: ep.duration > 0 ? ep.duration : track.duration,
    );
    playerStore.setEpisodes(playerStore.currentVideoEpisodes,
        activeIndex: playerStore.currentVideoEpisodes
            .indexWhere((e) => e.cid == ep.cid));
    // 同步当前曲目为分P合并后的版本（标题/时长/cid），但不写入播放历史，
    // 通知栏元数据与播放页标题随之刷新（bvid 不变、cid/title 变化）。
    playerStore.setCurrentTrack(merged, recordHistory: false);
    await _loadAndPlay(merged);
  }

  // ---------- 均衡器同步 ----------

  void _syncEq() {
    eqController.setEnabled(settingsStore.eqEnabled);
    eqController.setBands(settingsStore.eqEnabled ? settingsStore.eqBands : List.filled(10, 0));
  }

  /// 设置变化时调用（Draft+Apply）
  void syncEqNow() => _syncEq();

  Future<void> dispose() async {
    await _positionSub.cancel();
    await _durationSub.cancel();
    await _eventSub.cancel();
    await _stateSub.cancel();
    await _sessionSub.cancel();
    await _noisySub?.cancel();
    await eqController.release();
    await player.dispose();
  }
}
