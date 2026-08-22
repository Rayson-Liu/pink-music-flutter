import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/episode.dart';
import '../models/track.dart';

/// 播放器状态（对应原项目 src/stores/player.js）
class PlayerStore extends ChangeNotifier {
  static const String _historyKey = 'pink-music-play-history';
  static const int _historyMax = 50;

  Track? currentTrack;
  bool isPlaying = false;
  bool showPlayerPage = false;
  double currentTime = 0;
  double duration = 180;
  bool isAudioLoading = false;
  String audioError = '';
  int bufferedProgress = 0; // 0-100
  String playMode = 'order'; // order | loop | single | shuffle

  List<Track> playHistory = [];
  bool _historyDirty = false;
  DateTime? _lastHistorySave;
  Timer? _historySaveTimer;

  // 分P状态
  List<Episode> currentVideoEpisodes = [];
  bool showSeriesPanel = false;
  int currentEpisodeIndex = -1;
  bool isLoadingEpisodes = false;

  // 队列上下文（由视图设置，用于推导播放顺序）
  String currentView = 'home'; // home | search | playlist
  List<Track> currentQueue = [];

  // ---------- 播放控制 ----------

  /// 设置当前曲目。`recordHistory` 为 false 时不写入播放历史
  /// （用于分P/同视频内切P，避免历史被刷屏）。
  void setCurrentTrack(Track track, {bool recordHistory = true}) {
    currentTrack = track;
    audioError = '';
    if (recordHistory) {
      addToPlayHistory(track);
    }
    notifyListeners();
  }

  /// 直接设置播放模式（供系统媒体中心 repeat/shuffle 命令调用）。
  void setPlayMode(String mode) {
    if (mode == playMode) return;
    playMode = mode;
    notifyListeners();
  }

  void setPlaying(bool playing) {
    isPlaying = playing;
    notifyListeners();
  }

  void setCurrentTime(double t) {
    currentTime = t;
    notifyListeners();
  }

  void setDuration(double d) {
    duration = d > 0 ? d : 180;
    notifyListeners();
  }

  void setAudioLoading(bool loading) {
    isAudioLoading = loading;
    notifyListeners();
  }

  void setAudioError(String err) {
    audioError = err;
    isAudioLoading = false;
    notifyListeners();
  }

  void setBuffered(int p) {
    bufferedProgress = p;
    notifyListeners();
  }

  void togglePlayMode() {
    playMode = switch (playMode) {
      'order' => 'loop',
      'loop' => 'single',
      'single' => 'shuffle',
      _ => 'order',
    };
    notifyListeners();
  }

  void setShowPlayerPage(bool show) {
    showPlayerPage = show;
    notifyListeners();
  }

  // ---------- 播放历史 ----------

  void addToPlayHistory(Track track) {
    playHistory.removeWhere((t) => t.bvid == track.bvid);
    playHistory.insert(0, track);
    if (playHistory.length > _historyMax) {
      playHistory = playHistory.sublist(0, _historyMax);
    }
    _scheduleHistorySave();
  }

  void _scheduleHistorySave() {
    _historyDirty = true;
    final now = DateTime.now();
    final last = _lastHistorySave;
    // 取消上一轮定时器，避免快速切歌时积累多个 flush
    _historySaveTimer?.cancel();
    if (last != null && now.difference(last).inSeconds < 1) {
      _historySaveTimer = Timer(const Duration(milliseconds: 1000), () {
        _historySaveTimer = null;
        _flushHistory();
      });
      return;
    }
    _flushHistory();
  }

  Future<void> _flushHistory() async {
    if (!_historyDirty) return;
    _historyDirty = false;
    _lastHistorySave = DateTime.now();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _historyKey, jsonEncode(playHistory.map((t) => t.toJson()).toList()));
  }

  Future<void> loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_historyKey);
    if (raw == null || raw.isEmpty) return;
    try {
      final list = jsonDecode(raw);
      if (list is List) {
        playHistory = list
            .whereType<Map<String, dynamic>>()
            .map(Track.fromJson)
            .toList();
      }
    } catch (_) {}
    notifyListeners();
  }

  // ---------- 分P ----------

  void setEpisodes(List<Episode> eps, {int? activeIndex}) {
    currentVideoEpisodes = eps;
    currentEpisodeIndex = activeIndex ?? -1;
    notifyListeners();
  }

  void setShowSeriesPanel(bool show) {
    showSeriesPanel = show;
    notifyListeners();
  }

  void setIsLoadingEpisodes(bool loading) {
    isLoadingEpisodes = loading;
    notifyListeners();
  }

  // ---------- 队列上下文 ----------

  void setQueueContext(String view, List<Track> queue) {
    currentView = view;
    currentQueue = queue;
    notifyListeners();
  }

  int get currentQueueIndex {
    final t = currentTrack;
    if (t == null) return -1;
    // 优先按 bvid+cid 精确匹配（多P 同 bvid 不同 cid）；cid 为空时退化按 bvid
    final exact = currentQueue.indexWhere(
        (m) => m.bvid == t.bvid && m.cid == t.cid);
    if (exact >= 0) return exact;
    return currentQueue.indexWhere((m) => m.bvid == t.bvid);
  }
}
