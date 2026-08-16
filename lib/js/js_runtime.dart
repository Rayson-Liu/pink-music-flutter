/// JS 运行时 — 通过 flujs 将 window.electronAPI 注入 JS 环境
///
/// 双模式设计：
/// - 原生 Dart 层：已有的 BilibiliApi、HttpClient 等直接调用
/// - JS 层：通过 addInterface 注入方法，使原项目 JS 代码可运行
///
/// 网络请求复用：JS bilibili.js 中的数据解析逻辑保留，
/// 底层网络调用通过 addInterface 映射到 Dart 实现。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/episode.dart';
import '../models/track.dart';
import '../services/bilibili_api.dart';
import '../services/cookie_store.dart';
import '../services/netease_api.dart';
import '../state/download_store.dart';
import '../state/settings_store.dart';

// ── flujs 导入 ─────────────────────────────────────────────────────────
import 'package:flujs/flujs.dart' as flujs;
import 'package:flujs_qjs/qjs.dart' as qjs;
import 'package:flujs_jsc/jsc.dart' as jsc;

/// JS 运行时包装器
class JsRuntime {
  final BilibiliApi biliApi;
  final NeteaseApi neteaseApi;
  final CookieStore cookies;
  final DownloadStore downloadStore;
  final SettingsStore settingsStore;

  flujs.JSFContext? ctx;

  JsRuntime({
    required this.biliApi,
    required this.neteaseApi,
    required this.cookies,
    required this.downloadStore,
    required this.settingsStore,
  });

  bool get isAvailable => ctx != null;

  Future<void> init() async {
    try {
      await _initEngine();
      if (ctx != null) {
        await _injectInterfaces();
        await _loadBilibiliJs();
        debugPrint('JsRuntime.init OK (JS mode enabled)');
      } else {
        debugPrint('JsRuntime.init: flujs not available, JS mode disabled');
      }
    } catch (e, st) {
      debugPrint('JsRuntime.init error: $e\n$st');
    }
  }

  // ── 引擎初始化 ──────────────────────────────────────────────────────

  Future<void> _initEngine() async {
    flujs.JSFRuntime? rt;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
      case TargetPlatform.windows:
      case TargetPlatform.linux:
        rt = qjs.getJSFRuntime();
        break;
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
        rt = jsc.getJSFRuntime();
        break;
      default:
        rt = qjs.getJSFRuntime();
    }
    ctx = rt.newContext();
    ctx!.loadExtension();
  }

  // ── 注入 electronAPI 方法 ────────────────────────────────────────────

  Future<void> _injectInterfaces() async {
    if (ctx == null) return;
    final c = ctx!;

    // === 音乐 API ===
    c.addInterface('searchMusic', _jsSearchMusic);
    c.addInterface('getMusicInfo', _jsGetMusicInfo);
    c.addInterface('getMusicPlayUrl', _jsGetMusicPlayUrl);
    c.addInterface('getVideoEpisodes', _jsGetVideoEpisodes);
    c.addInterface('getRecommendations', _jsGetRecommendations);
    c.addInterface('getVideoSeries', _jsGetVideoSeries);
    c.addInterface('proxyAudio', _jsProxyAudio);

    // === 登录 ===
    c.addInterface('generateQrcode', _jsGenerateQrcode);
    c.addInterface('pollQrcode', _jsPollQrcode);
    c.addInterface('getUserInfo', _jsGetUserInfo);
    c.addInterface('getBilibiliCookies', _jsGetBilibiliCookies);
    c.addInterface('logoutBilibili', _jsLogoutBilibili);
    c.addInterface('getCookie', _jsGetCookie);
    c.addInterface('setCookie', _jsSetCookie);

    // === 收藏夹 ===
    c.addInterface('getFavFolderCreatedList', _jsGetFavCreatedList);
    c.addInterface('getFavFolderCollectedList', _jsGetFavCollectedList);
    c.addInterface('getFavResourceIds', _jsGetFavResourceIds);
    c.addInterface('getFavResourceInfos', _jsGetFavResourceInfos);

    // === 持久化存储 ===
    c.addInterface('appData', _jsAppData);
    c.addInterface('appDataEncrypted', _jsAppData);

    // === 缓存 ===
    c.addInterface('getCacheSize', _jsGetCacheSize);
    c.addInterface('clearCache', _jsClearCache);

    // === 下载目录 ===
    c.addInterface('selectDownloadDirectory', _jsSelectDownloadDir);
    c.addInterface('getDownloadDirectory', _jsGetDownloadDir);
    c.addInterface('setDownloadDirectory', _jsSetDownloadDir);

    // === 下载任务 ===
    c.addInterface('downloadAudio', _jsDownloadAudio);
    c.addInterface('getDownloadTasks', _jsGetDownloadTasks);
    c.addInterface('clearDownloadTasks', _jsClearDownloadTasks);
    c.addInterface('onDownloadProgress', _jsOnDownloadProgress);
    c.addInterface('openDownloadFolder', _jsOpenDownloadFolder);

    // === 歌词 ===
    c.addInterface('getLyric', _jsGetLyric);
    c.addInterface('searchLyric', _jsSearchLyric);
    c.addInterface('getLyricById', _jsGetLyricById);

    // === UI ===
    c.addInterface('showMessageBox', _jsShowMessageBox);
    c.addInterface('openGitHub', _jsOpenGitHub);

    // === 平台 ===
    c.addInterface('getPlatform', _jsGetPlatform);
  }

  // ── 方法实现 ─────────────────────────────────────────────────────────

  dynamic _jsSearchMusic(dynamic args) async {
    final list = args as List<dynamic>;
    final keyword = list[0] as String;
    final page = (list[1] as num?)?.toInt() ?? 1;
    final pageSize = (list[2] as num?)?.toInt() ?? 30;
    try {
      final tracks = await biliApi.searchMusic(keyword, page, pageSize);
      return {
        'code': 0,
        'data': {'result': tracks.map((t) => _trackToMap(t)).toList()}
      };
    } catch (e) {
      return {'code': -1, 'message': e.toString()};
    }
  }

  dynamic _jsGetMusicInfo(dynamic args) async {
    final list = args as List<dynamic>;
    final bvid = list[0] as String;
    try {
      final data = await biliApi.getMusicInfo(bvid);
      return {'code': 0, 'data': data};
    } catch (e) {
      return {'code': -1, 'message': e.toString()};
    }
  }

  dynamic _jsGetMusicPlayUrl(dynamic args) async {
    final list = args as List<dynamic>;
    final bvid = list[0] as String;
    final cid = list[1] as num;
    try {
      final data = await biliApi.getMusicPlayUrl(bvid, cid);
      return {'code': 0, 'data': data};
    } catch (e) {
      return {'code': -1, 'message': e.toString()};
    }
  }

  dynamic _jsGetVideoEpisodes(dynamic args) async {
    final list = args as List<dynamic>;
    final bvid = list[0] as String;
    try {
      final episodes = await biliApi.getVideoEpisodes(bvid);
      return {
        'code': 0,
        'data': episodes.map((e) => _episodeToMap(e)).toList()
      };
    } catch (e) {
      return {'code': -1, 'message': e.toString()};
    }
  }

  dynamic _jsGetRecommendations(dynamic args) async {
    try {
      final tracks = await biliApi.getMusicRegionFeed(1, 15);
      return {'code': 0, 'data': {'item': tracks.map(_trackToMap).toList()}};
    } catch (e) {
      return {'code': -1, 'message': e.toString()};
    }
  }

  dynamic _jsGetVideoSeries(dynamic args) async {
    final list = args as List<dynamic>;
    final bvid = list[0] as String;
    try {
      final info = await biliApi.getMusicInfo(bvid);
      if (info['season_id'] != null) {
        final dio = Dio();
        final resp = await dio.get(
          'https://api.bilibili.com/x/polymer/web-space/seasons_archives_list',
          queryParameters: {
            'mid': info['owner']?['mid'],
            'season_id': info['season_id'],
          },
        );
        return {'code': 0, 'data': resp.data};
      }
      return {'code': -1, 'message': '未找到合集'};
    } catch (e) {
      return {'code': -1, 'message': e.toString()};
    }
  }

  dynamic _jsProxyAudio(dynamic args) async {
    final list = args as List<dynamic>;
    final audioUrl = list[0] as String;
    try {
      final dio = Dio();
      final resp = await dio.get<dynamic>(
        audioUrl,
        options: Options(responseType: ResponseType.bytes),
      );
      return {'code': 0, 'data': base64Encode(resp.data as List<int>)};
    } catch (e) {
      return {'code': -1, 'message': e.toString()};
    }
  }

  dynamic _jsGenerateQrcode(dynamic args) async {
    try {
      final data = await biliApi.generateQrcode();
      return {'code': 0, 'data': data};
    } catch (e) {
      return {'code': -1, 'message': e.toString()};
    }
  }

  dynamic _jsPollQrcode(dynamic args) async {
    final list = args as List<dynamic>;
    final key = list[0] as String;
    try {
      final data = await biliApi.pollQrcode(key);
      return {'code': 0, 'data': data, 'headers': {}};
    } catch (e) {
      return {'code': -1, 'message': e.toString()};
    }
  }

  dynamic _jsGetUserInfo(dynamic args) async {
    try {
      final data = await biliApi.getUserInfo();
      return {'code': 0, 'data': data};
    } catch (e) {
      return {'code': -1, 'message': e.toString()};
    }
  }

  dynamic _jsGetBilibiliCookies(dynamic args) async {
    return {'code': 0, 'data': Map.from(cookies.all)};
  }

  dynamic _jsLogoutBilibili(dynamic args) async {
    cookies.clear();
    await cookies.save();
    return {'code': 0};
  }

  dynamic _jsGetCookie(dynamic args) async {
    final list = args as List<dynamic>;
    final name = list[0] as String;
    return {'code': 0, 'data': cookies[name] ?? ''};
  }

  dynamic _jsSetCookie(dynamic args) async {
    final list = args as List<dynamic>;
    final name = list[0] as String;
    final value = list[1] as String;
    cookies.set(name, value);
    await cookies.save();
    return {'code': 0};
  }

  dynamic _jsGetFavCreatedList(dynamic args) async {
    final list = args as List<dynamic>;
    final mid = list[0] as num;
    final pn = (list[1] as num?)?.toInt() ?? 1;
    final ps = (list[2] as num?)?.toInt() ?? 50;
    try {
      final list2 = await biliApi.getFavFolderCreatedList(mid, pn, ps);
      return {'code': 0, 'data': list2};
    } catch (e) {
      return {'code': -1, 'message': e.toString()};
    }
  }

  dynamic _jsGetFavCollectedList(dynamic args) async {
    final list = args as List<dynamic>;
    final mid = list[0] as num;
    final pn = (list[1] as num?)?.toInt() ?? 1;
    final ps = (list[2] as num?)?.toInt() ?? 50;
    try {
      final list2 = await biliApi.getFavFolderCollectedList(mid, pn, ps);
      return {'code': 0, 'data': list2};
    } catch (e) {
      return {'code': -1, 'message': e.toString()};
    }
  }

  dynamic _jsGetFavResourceIds(dynamic args) async {
    final list = args as List<dynamic>;
    final mediaId = list[0] as num;
    try {
      final list2 = await biliApi.getFavResourceIds(mediaId);
      return {'code': 0, 'data': list2};
    } catch (e) {
      return {'code': -1, 'message': e.toString()};
    }
  }

  dynamic _jsGetFavResourceInfos(dynamic args) async {
    final list = args as List<dynamic>;
    final resources = list[0] as String;
    try {
      final list2 = await biliApi.getFavResourceInfos(resources);
      return {'code': 0, 'data': list2};
    } catch (e) {
      return {'code': -1, 'message': e.toString()};
    }
  }

  dynamic _jsAppData(dynamic args) async {
    final prefs = await SharedPreferences.getInstance();
    return _AppDataProxy(prefs);
  }

  dynamic _jsGetCacheSize(dynamic args) async {
    try {
      final dir = await downloadStore.ensureDownloadDirPublic();
      final size = await _calcDirSize(dir.path);
      return {'code': 0, 'size': size};
    } catch (e) {
      return {'code': -1, 'message': e.toString()};
    }
  }

  dynamic _jsClearCache(dynamic args) async {
    try {
      final dir = await downloadStore.ensureDownloadDirPublic();
      await _clearDir(dir.path);
      return {'code': 0};
    } catch (e) {
      return {'code': -1, 'message': e.toString()};
    }
  }

  dynamic _jsSelectDownloadDir(dynamic args) async {
    try {
      final result = await FilePicker.getDirectoryPath();
      if (result != null) return {'code': 0, 'path': result};
      return {'code': 1, 'message': '未选择目录'};
    } catch (e) {
      return {'code': -1, 'message': e.toString()};
    }
  }

  dynamic _jsGetDownloadDir(dynamic args) async {
    try {
      final dir = await downloadStore.ensureDownloadDirPublic();
      return {'code': 0, 'path': dir.path};
    } catch (e) {
      return {'code': -1, 'message': e.toString()};
    }
  }

  dynamic _jsSetDownloadDir(dynamic args) async {
    final list = args as List<dynamic>;
    final dirPath = list[0] as String;
    downloadStore.downloadDir = dirPath;
    return {'code': 0};
  }

  dynamic _jsDownloadAudio(dynamic args) async {
    final list = args as List<dynamic>;
    final taskInfo = list[0] as Map<String, dynamic>;
    try {
      final track = Track(
        bvid: taskInfo['bvid']?.toString() ?? '',
        title: taskInfo['title']?.toString() ?? '',
        author: taskInfo['author']?.toString() ?? '',
        cover: taskInfo['cover']?.toString() ?? '',
        duration: (taskInfo['duration'] as num?)?.toInt() ?? 180,
      );
      await downloadStore.downloadMusic(track);
      return {'code': 0};
    } catch (e) {
      return {'code': -1, 'message': e.toString()};
    }
  }

  dynamic _jsGetDownloadTasks(dynamic args) async {
    return {
      'code': 0,
      'data': downloadStore.tasks.map((t) => <String, dynamic>{
        'id': t.id,
        'title': t.title,
        'author': t.author,
        'bvid': t.bvid,
        'cid': t.cid,
        'quality': t.quality,
        'audioCodecs': t.audioCodecs,
        'fileName': t.fileName,
        'filePath': t.filePath,
        'status': t.status,
        'progress': t.progress,
        'totalBytes': t.totalBytes,
        'downloadedBytes': t.downloadedBytes,
        'createdTime': t.createdTime,
        'error': t.error,
      }).toList()
    };
  }

  dynamic _jsClearDownloadTasks(dynamic args) async {
    downloadStore.clearTasks();
    return {'code': 0};
  }

  dynamic _jsOnDownloadProgress(dynamic args) async {
    return {'code': 0};
  }

  dynamic _jsOpenDownloadFolder(dynamic args) async {
    try {
      final dir = await downloadStore.ensureDownloadDirPublic();
      await launchUrl(Uri.directory(dir.path));
      return {'code': 0};
    } catch (e) {
      return {'code': -1, 'message': e.toString()};
    }
  }

  dynamic _jsGetLyric(dynamic args) async {
    final list = args as List<dynamic>;
    final params = list[0] as Map<String, dynamic>;
    try {
      final result = await neteaseApi.getLyric(
        bvid: params['bvid']?.toString() ?? '',
        cid: (params['cid'] as num?)?.toInt() ?? 1,
        title: params['title']?.toString() ?? '',
        artist: params['artist']?.toString() ?? '',
      );
      return {
        'code': 0,
        'data': result['lrc'],
        'source': result['source']
      };
    } catch (e) {
      return {'code': -1, 'message': e.toString()};
    }
  }

  dynamic _jsSearchLyric(dynamic args) async {
    final list = args as List<dynamic>;
    final keyword = list[0] as String;
    try {
      final results = await neteaseApi.searchLyric(keyword);
      return {'code': 0, 'data': results};
    } catch (e) {
      return {'code': -1, 'message': e.toString()};
    }
  }

  dynamic _jsGetLyricById(dynamic args) async {
    final list = args as List<dynamic>;
    final songId = list[0] as num;
    try {
      final data = await neteaseApi.getLyricById(songId);
      return {'code': 0, 'data': data['lrc']};
    } catch (e) {
      return {'code': -1, 'message': e.toString()};
    }
  }

  dynamic _jsShowMessageBox(dynamic args) async {
    return {'response': 1};
  }

  dynamic _jsOpenGitHub(dynamic args) async {
    try {
      await launchUrl(
        Uri.parse('https://github.com/Rayson-Liu/pink-music-flutter'),
        mode: LaunchMode.externalApplication,
      );
      return {'code': 0};
    } catch (e) {
      return {'code': -1, 'message': e.toString()};
    }
  }

  dynamic _jsGetPlatform(dynamic args) async {
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => 'android',
      TargetPlatform.iOS => 'ios',
      TargetPlatform.linux => 'linux',
      TargetPlatform.macOS => 'darwin',
      TargetPlatform.windows => 'windows',
      _ => 'unknown',
    };
  }

  // ── 加载 JS 代码 ────────────────────────────────────────────────────

  Future<void> _loadBilibiliJs() async {
    if (ctx == null) return;
    ctx!.eval(_bilibiliJsCode);
    debugPrint('JsRuntime: bilibili.js loaded');
  }

  static const String _bilibiliJsCode = r'''
// BilibiliAPI for JS environment (flujs injected)
class BilibiliAPI {
  constructor() {
    this.defaultCover = 'https://images.unsplash.com/photo-1470225620780-dba8ba36b745?w=400';
    this.defaultCovers = [
      'https://images.unsplash.com/photo-1470225620780-dba8ba36b745?w=400',
      'https://images.unsplash.com/photo-1493225457124-a3eb161ffa5f?w=400',
      'https://images.unsplash.com/photo-1514320291840-2e0a9bf2a9ae?w=400',
      'https://images.unsplash.com/photo-1511671782779-c97d3d27a1d4?w=400',
      'https://images.unsplash.com/photo-1459749411175-04bf5292ceea?w=400'
    ];
  }
  getDefaultCover(index = 0) {
    return this.defaultCovers[index % this.defaultCovers.length];
  }
  processCoverUrl(coverUrl, fallbackIndex = 0) {
    if (!coverUrl) return this.getDefaultCover(fallbackIndex);
    let u = coverUrl;
    if (u.startsWith('//')) u = 'https:' + u;
    if (!u.startsWith('http')) u = 'https://' + u;
    return u;
  }
  async searchMusic(keyword, page = 1, pageSize = 30) {
    if (!window.electronAPI?.searchMusic) return { success: false, error: 'electronAPI unavailable', music: [] };
    try {
      const r = await window.electronAPI.searchMusic(keyword, page, pageSize);
      if (r.code === 0 && r.data?.result) return { success: true, music: r.data.result };
      return { success: true, music: [] };
    } catch (e) { return { success: false, error: e.message, music: [] }; }
  }
  async getMusicInfo(bvid) {
    if (!window.electronAPI?.getMusicInfo) return { success: false, error: 'electronAPI unavailable' };
    try {
      const r = await window.electronAPI.getMusicInfo(bvid);
      if (r.code === 0) {
        const i = r.data;
        return { success: true, music: {
          bvid: i.bvid, aid: i.aid, title: i.title,
          author: i.owner?.name || '未知作者',
          cover: this.processCoverUrl(i.pic),
          duration: i.duration || 180, cid: i.cid,
          playCount: i.stat?.view || 0
        }};
      }
      return { success: false, error: r.message || 'not found' };
    } catch (e) { return { success: false, error: e.message }; }
  }
  async getMusicPlayUrl(bvid, cid) {
    if (!window.electronAPI?.getMusicPlayUrl) return { success: false, error: 'electronAPI unavailable' };
    try {
      const r = await window.electronAPI.getMusicPlayUrl(bvid, cid);
      if (r.code === 0) {
        const d = r.data;
        if (d?.durl?.[0]?.url) return { success: true, url: d.durl[0].url };
        if (d?.data?.durl?.[0]?.url) return { success: true, url: d.data.durl[0].url };
        if (d?.url) return { success: true, url: d.url };
        if (d?.dash?.audio?.[0]?.baseUrl) return { success: true, url: d.dash.audio[0].baseUrl };
        if (d?.dash?.audio?.[0]?.url) return { success: true, url: d.dash.audio[0].url };
      }
      return { success: false, error: r.message || 'no url' };
    } catch (e) { return { success: false, error: e.message }; }
  }
  async getVideoEpisodes(bvid) {
    if (!window.electronAPI?.getVideoEpisodes) return { success: false, error: 'electronAPI unavailable' };
    try {
      const r = await window.electronAPI.getVideoEpisodes(bvid);
      return r.code === 0 ? { success: true, episodes: r.data || [] } : { success: false, error: r.message };
    } catch (e) { return { success: false, error: e.message }; }
  }
  async getRecommendations() {
    if (!window.electronAPI?.getRecommendations) return { success: false, error: 'electronAPI unavailable' };
    try {
      const r = await window.electronAPI.getRecommendations();
      return r.code === 0 && r.data?.item ? { success: true, music: r.data.item } : { success: false, error: r.message };
    } catch (e) { return { success: false, error: e.message }; }
  }
  async getVideoSeries(bvid) {
    if (!window.electronAPI?.getVideoSeries) return { success: false, error: 'electronAPI unavailable' };
    try {
      const r = await window.electronAPI.getVideoSeries(bvid);
      return r.code === 0 && r.data ? { success: true, series: r.data } : { success: false, error: r.message };
    } catch (e) { return { success: false, error: e.message }; }
  }
  stripHtmlTags(s) { return s.replace(/<[^>]*>/g, ''); }
  parseDuration(d) {
    if (!d) return 180;
    if (typeof d === 'number') return d;
    const p = d.split(':');
    return p.length === 2 ? parseInt(p[0]) * 60 + parseInt(p[1]) : 180;
  }
}
const bilibiliAPI = new BilibiliAPI();
''';

  // ── 辅助方法 ────────────────────────────────────────────────────────

  Map<String, dynamic> _trackToMap(Track t) => t.toJson();

  Map<String, dynamic> _episodeToMap(Episode e) => {
        'bvid': e.bvid,
        'cid': e.cid,
        'title': e.title,
        'duration': e.duration,
        'cover': e.cover,
        'firstFrame': e.firstFrame,
      };

  Future<int> _calcDirSize(String path) async {
    try {
      final dir = Directory(path);
      if (!await dir.exists()) return 0;
      int total = 0;
      await for (final entity in dir.list(recursive: true)) {
        if (entity is File) total += await entity.length();
      }
      return total;
    } catch (_) {
      return 0;
    }
  }

  Future<void> _clearDir(String path) async {
    try {
      final dir = Directory(path);
      if (await dir.exists()) {
        await dir.delete(recursive: true);
        await dir.create(recursive: true);
      }
    } catch (_) {}
  }
}

/// appData 持久化代理（对应 persistentStorage.js 的主存储层）
class _AppDataProxy {
  final SharedPreferences prefs;
  _AppDataProxy(this.prefs);

  Future<Map<String, dynamic>> get(String key) async {
    final raw = prefs.getString('pink-music-appdata-$key');
    if (raw == null) return {'code': -1, 'message': 'not found'};
    try {
      return {'code': 0, 'data': jsonDecode(raw)};
    } catch (_) {
      return {'code': -1, 'message': 'parse error'};
    }
  }

  Future<Map<String, dynamic>> set(String key, dynamic value) async {
    await prefs.setString('pink-music-appdata-$key', jsonEncode(value));
    return {'code': 0};
  }

  Future<Map<String, dynamic>> remove(String key) async {
    await prefs.remove('pink-music-appdata-$key');
    return {'code': 0};
  }
}
