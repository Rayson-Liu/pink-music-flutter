import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/lyric.dart';
import '../models/track.dart';
import '../services/bilibili_api.dart';
import '../services/lyric_parser.dart';
import '../services/http_client.dart';
import '../services/netease_api.dart';
import '../services/qq_music_api.dart';
import 'settings_store.dart';

/// 歌词状态（对应原项目 src/stores/lyric.js）
class LyricStore extends ChangeNotifier {
  static const String _key = 'pink-music-lyrics';
  static const int _ttlMs = 7 * 24 * 60 * 60 * 1000;
  static const int _maxCache = 1000;
  static const double _offsetStep = 500; // ms

  final NeteaseApi api;
  final QQMusicApi qqApi;
  final SettingsStore settings;
  final BilibiliApi? biliApi;

  LyricStore(this.api,
      {required this.qqApi, required this.settings, this.biliApi});

  Lyric? currentLyric;
  String loadedHash = '';
  int currentLineIndex = -1;
  bool isLyricLoading = false;
  String lyricError = '';
  String lyricSource = ''; // netease | manual
  bool showLyricPanel = false;

  Map<String, Lyric> lyricCache = {};
  // 每首歌的缓存写入时间戳（用于 LRU 清理 + TTL），与 lyricCache 一一对应
  final Map<String, int> _cacheTimestamps = {};
  Map<String, int> lyricOffsets = {};
  Map<String, String> lyricSources = {};

  // 手动搜索
  List<Map<String, dynamic>> searchResults = [];
  bool isSearching = false;

  // ---------- 加载 ----------

  String getCacheKey(Track track) =>
      Lyric.cacheKey(track.bvid, track.cid, track.title, track.author);

  Future<void> loadLyricForTrack(Track track) async {
    final key = getCacheKey(track);
    loadedHash = key;
    lyricError = '';
    currentLineIndex = -1;
    currentLyric = null;
    notifyListeners();

    final cached = lyricCache[key];
    if (cached != null) {
      _applyLyric(cached, lyricSources[key] ?? 'netease');
      return;
    }

    isLyricLoading = true;
    notifyListeners();
    Object? firstError;
    Lyric? parsed;
    var source = 'qq';

    // 按设置顺序尝试歌词源：默认 QQ 音乐优先，失败/无结果自动兜底网易云
    final order = settings.lyricSource == 'qq'
        ? const ['qq', 'netease']
        : const ['netease', 'qq'];
    for (final src in order) {
      try {
        final Map<String, dynamic> result;
        if (src == 'qq') {
          result = await qqApi.getLyric(
            title: track.title,
            artist: track.author,
          );
        } else {
          result = await api.getLyric(
            bvid: track.bvid,
            cid: track.cid?.toInt() ?? 1,
            title: track.title,
            artist: track.author,
          );
        }
        final lrc = result['lrc']?.toString() ?? '';
        if (lrc.isNotEmpty) {
          final p = LyricParser.parseLyric(result);
          if (p.lines.isNotEmpty) {
            parsed = p;
            source = src;
            break;
          }
        }
      } catch (e) {
        firstError ??= e;
        debugPrint('${src == 'qq' ? 'QQ音乐' : '网易云'}歌词失败: $e');
      }
    }

    // 双源都失败/无结果 → B 站自带字幕兜底
    if (parsed == null && biliApi != null && track.cid != null) {
      try {
        final subs =
            await biliApi!.getBiliSubtitle(track.bvid, track.cid!);
        if (subs.isNotEmpty) {
          final lines = <LyricLine>[];
          for (final s in subs) {
            final from = s['from'];
            final content = s['content']?.toString() ?? '';
            if (from is! num || content.isEmpty) continue;
            lines.add(LyricLine(
                time: (from * 1000).round(), text: content));
          }
          if (lines.isNotEmpty) {
            parsed = Lyric(lines: lines);
            source = 'bilibili';
          }
        }
      } catch (e) {
        debugPrint('B 站字幕兜底失败: $e');
      }
    }

    // 竞态防护：异步请求期间可能已切歌，丢弃过期结果
    if (loadedHash != key) return;

    if (parsed == null) {
      lyricError = firstError != null
          ? '歌词加载失败：${_friendlyError(firstError)}'
          : '歌词加载失败：未找到歌词';
      isLyricLoading = false;
      notifyListeners();
      return;
    }
    lyricCache[key] = parsed;
    lyricSources[key] = source;
    _cacheTimestamps[key] = DateTime.now().millisecondsSinceEpoch;
    _trimCache();
    _persist();
    _applyLyric(parsed, source);
    isLyricLoading = false;
    notifyListeners();
  }

  void _applyLyric(Lyric lyric, String source) {
    currentLyric = lyric;
    lyricSource = source;
    currentLineIndex = -1; // 重置，避免旧索引越界（对应原 setCurrentLyric）
    // 关键复位：缓存命中/手动歌词/网络完成三条路径都会走到这里——
    // 否则在先一轮网络拉词仍在途时命中缓存（或竞态守卫丢弃在途结果）会
    // 让 isLyricLoading 永久卡在 true，歌词面板一直显示「正在匹配歌词…」。
    isLyricLoading = false;
    notifyListeners();
  }

  // ---------- 手动搜索 ----------

  Future<void> searchLyric(String keyword) async {
    isSearching = true;
    notifyListeners();
    try {
      final merged = <Map<String, dynamic>>[];
      final qq = await qqApi.searchLyric(keyword);
      final ne = await api.searchLyric(keyword);
      for (final r in ne) {
        r['source'] = 'netease';
      }
      // 按设置源排序展示，默认 QQ 音乐在前
      if (settings.lyricSource == 'qq') {
        merged.addAll(qq);
        merged.addAll(ne);
      } else {
        merged.addAll(ne);
        merged.addAll(qq);
      }
      searchResults = merged;
    } catch (e) {
      debugPrint('歌词搜索失败: $e');
      searchResults = [];
    }
    isSearching = false;
    notifyListeners();
  }

  Future<void> loadLyricById(dynamic songId, {String source = 'netease'}) async {
    if (loadedHash.isEmpty) return;
    isLyricLoading = true;
    notifyListeners();
    try {
      final Map<String, dynamic> data;
      if (source == 'qq') {
        data = await qqApi.getLyricById(songId.toString());
      } else {
        data = await api.getLyricById(songId);
      }
      final parsed = LyricParser.parseLyric(data);
      lyricCache[loadedHash] = parsed;
      lyricSources[loadedHash] = source; // qq | netease
      _cacheTimestamps[loadedHash] = DateTime.now().millisecondsSinceEpoch;
      _trimCache();
      _persist();
      _applyLyric(parsed, 'manual');
    } catch (e) {
      lyricError = '歌词加载失败';
      debugPrint('手动歌词加载失败: $e');
    }
    isLyricLoading = false;
    notifyListeners();
  }

  String _friendlyError(Object e) {
    if (e is ApiException) return e.message;
    final s = e.toString();
    if (s.contains('connectionTimeout')) return '网络超时，请检查网络后重试';
    if (s.contains('receiveTimeout')) return '服务响应超时，请稍后重试';
    if (s.contains('connectionError') ||
        s.contains('SocketException') ||
        s.contains('Failed host lookup')) {
      return '网络连接失败，请检查网络后重试';
    }
    return s.length > 60 ? s.substring(0, 60) : s;
  }

  /// 重置为自动匹配（清空手动来源）
  Future<void> resetManualLyric() async {
    if (loadedHash.isEmpty || lyricSource != 'manual') return;
    lyricSources.remove(loadedHash);
    lyricCache.remove(loadedHash);
    _cacheTimestamps.remove(loadedHash);
    _persist();
    notifyListeners();
  }

  // ---------- 偏移 ----------

  int get currentOffset => lyricOffsets[loadedHash] ?? 0;

  void adjustOffset(int steps) {
    final key = loadedHash;
    if (key.isEmpty) return;
    lyricOffsets[key] = (lyricOffsets[key] ?? 0) + (steps * _offsetStep).round();
    _persist();
    notifyListeners();
  }

  void resetOffset() {
    final key = loadedHash;
    if (key.isEmpty) return;
    lyricOffsets.remove(key);
    _persist();
    notifyListeners();
  }

  // ---------- 显示 ----------

  void updateCurrentLine(double currentTime) {
    final lyric = currentLyric;
    if (lyric == null) {
      if (currentLineIndex != -1) {
        currentLineIndex = -1;
        notifyListeners();
      }
      return;
    }
    final adjusted = (currentTime * 1000 + currentOffset).round();
    var idx = -1;
    for (var i = lyric.lines.length - 1; i >= 0; i--) {
      if (lyric.lines[i].time <= adjusted + 500) {
        idx = i;
        break;
      }
    }
    if (idx != currentLineIndex) {
      currentLineIndex = idx;
      notifyListeners();
    }
  }

  void setShowLyricPanel(bool show) {
    showLyricPanel = show;
    notifyListeners();
  }

  /// 点击歌词行跳转
  double lineTimeToSeconds(int index) {
    final line = currentLyric?.lines[index];
    if (line == null) return 0;
    return (line.time - currentOffset) / 1000;
  }

  // ---------- 持久化 ----------

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return;
    try {
      final map = Map<String, dynamic>.from(jsonDecode(raw));
      final cache = map['cache'];
      if (cache is Map) {
        final now = DateTime.now().millisecondsSinceEpoch;
        cache.forEach((k, v) {
          final entry = v;
          if (entry is Map) {
            final ts = entry['timestamp'];
            if (ts is! num || now - ts.toInt() > _ttlMs) return;
            final data = entry['data'];
            // _lyricV3 标记在 data 内部（v.toJson() 输出），不是 entry 顶层
            if (data is Map && data['_lyricV3'] == true) {
              final key = k.toString();
              lyricCache[key] =
                  Lyric.fromJson(Map<String, dynamic>.from(data));
              _cacheTimestamps[key] = ts.toInt();
            }
          }
        });
      }
      final offsets = map['offsets'];
      if (offsets is Map) {
        offsets.forEach((k, v) => lyricOffsets[k.toString()] = (v as num).toInt());
      }
      final sources = map['sources'];
      if (sources is Map) {
        sources.forEach((k, v) => lyricSources[k.toString()] = v.toString());
      }
    } catch (e) {
      debugPrint('歌词缓存解析失败: $e');
    }
    notifyListeners();
  }

  void _trimCache() {
    if (lyricCache.length <= _maxCache) return;
    // 按缓存写入时间升序排列，移除最旧的前 N 条（与原版 Vue 的清理逻辑一致）
    final sorted = lyricCache.keys.toList()
      ..sort((a, b) =>
          (_cacheTimestamps[a] ?? 0).compareTo(_cacheTimestamps[b] ?? 0));
    final removeCount = lyricCache.length - _maxCache;
    for (var i = 0; i < removeCount; i++) {
      final key = sorted[i];
      lyricCache.remove(key);
      _cacheTimestamps.remove(key);
    }
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _key,
        jsonEncode({
          'cache': lyricCache.map((k, v) => MapEntry(
              k,
              {
                'data': v.toJson(),
                'timestamp': _cacheTimestamps[k] ??
                    DateTime.now().millisecondsSinceEpoch,
                'source': lyricSources[k] ?? 'netease',
              })),
          'offsets': lyricOffsets,
          'sources': lyricSources,
        }));
  }
}
