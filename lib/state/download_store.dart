import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../models/download_task.dart';
import '../models/track.dart';
import '../services/audio_stream.dart';
import '../services/bilibili_api.dart';
import '../services/cookie_store.dart';
import '../state/settings_store.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// 下载管理（对应原项目 src/stores/download.js + electron 下载实现）
class DownloadStore extends ChangeNotifier {
  final BilibiliApi api;
  final SettingsStore settings;
  final CookieStore cookies;

  DownloadStore(this.api, this.settings, this.cookies);

  List<DownloadTask> tasks = [];
  String? downloadDir;

  /// 添加下载任务
  Future<void> downloadMusic(Track track,
      {void Function(DownloadTask)? onProgress}) async {
    var cid = track.cid;
    if (cid == null) {
      try {
        final info = await api.getMusicInfo(track.bvid);
        cid = info['cid'];
      } catch (e) {
        _fail(track, '获取视频信息失败：${_brief(e)}');
        return;
      }
    }
    if (cid == null) {
      _fail(track, '获取视频信息失败');
      return;
    }

    StreamInfo stream;
    try {
      final data = await api.getMusicPlayUrl(track.bvid, cid);
      stream = selectAudioInfo(data, settings.audioQuality);
    } catch (e) {
      _fail(track, '获取音源失败：${_brief(e)}');
      return;
    }

    final id = DownloadTask.genId();
    final fileName = _sanitizeFileName('${track.title} - ${track.author}');
    final ext = getAudioExtByCodecs(stream.codecs);
    final task = DownloadTask(
      id: id,
      title: track.title,
      author: track.author,
      bvid: track.bvid,
      cid: cid,
      quality: settings.audioQuality,
      audioCodecs: stream.codecs,
      fileName: '$fileName$ext',
      status: 'downloading',
    );
    tasks.insert(0, task);
    notifyListeners();

    try {
      await _doDownload(task, stream, onProgress ?? (_) {});
    } catch (e) {
      final idx = tasks.indexWhere((t) => t.id == id);
      if (idx >= 0) {
        tasks[idx] = task.copyWith(status: 'error', error: _brief(e));
        notifyListeners();
      }
    }
  }

  /// 依次尝试 主地址 + 备用地址，任一成功即完成；全部失败抛异常。
  Future<void> _doDownload(DownloadTask task, StreamInfo stream,
      void Function(DownloadTask) onProgress) async {
    final urls = <String>[
      stream.url,
      ...stream.backupUrls.where((u) => u.isNotEmpty),
    ].where((u) => u.isNotEmpty && u != 'null').toSet().toList();

    Object? lastError;
    for (final url in urls) {
      try {
        await _downloadOne(task, url, onProgress);
        return;
      } catch (e) {
        lastError = e;
        debugPrint('下载地址失败，尝试下一个: ${_urlHost(url)} $e');
        task.downloadedBytes = 0;
        task.totalBytes = 0;
        task.progress = 0;
      }
    }
    throw Exception(lastError ?? '无可用下载地址');
  }

  static String _urlHost(String url) {
    try {
      return Uri.parse(url).host;
    } catch (_) {
      return url.length > 40 ? url.substring(0, 40) : url;
    }
  }

  Future<void> _downloadOne(DownloadTask task, String url,
      void Function(DownloadTask) onProgress) async {
    final dir = await _ensureDownloadDir();
    final file = File('${dir.path}/${task.fileName}');

    final dio = Dio(BaseOptions(
      headers: {
        // 与原项目 electron/main.js 的下载请求头一致：Referer + UA。
        // B 站 CDN 对缺 Referer / 非浏览器 UA 的请求会返回 403。
        'Referer': 'https://www.bilibili.com/',
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
                '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        'Accept': '*/*',
        'Origin': 'https://www.bilibili.com',
      },
    ));
    if (cookies.toHeader().isNotEmpty) {
      dio.options.headers['Cookie'] = cookies.toHeader();
    }

    final response = await dio.get(
      url,
      options: Options(responseType: ResponseType.bytes),
      onReceiveProgress: (received, total) {
        task.downloadedBytes = received;
        task.totalBytes = total > 0 ? total : 0;
        task.progress = total > 0 ? ((received / total) * 100).round() : 0;
        _updateTask(task);
        onProgress(task);
      },
    );

    // B 站 CDN 常规返回 200；部分边缘节点对无 Range 请求也可能返回 206。
    if (response.statusCode != 200 && response.statusCode != 206) {
      throw Exception('下载失败 (HTTP ${response.statusCode})');
    }

    final bytes = response.data as List<int>;
    await file.writeAsBytes(bytes);
    task.totalBytes = bytes.length;
    task.downloadedBytes = bytes.length;
    task.progress = 100;
    _updateTask(task);
    onProgress(task);

    task.status = 'completed';
    task.filePath = file.path;
    _updateTask(task);
    onProgress(task);
  }

  void _updateTask(DownloadTask task) {
    final idx = tasks.indexWhere((t) => t.id == task.id);
    if (idx >= 0) {
      tasks[idx] = task;
      notifyListeners();
    }
  }

  void _fail(Track track, String message) {
    final task = DownloadTask(
      id: DownloadTask.genId(),
      title: track.title,
      author: track.author,
      bvid: track.bvid,
      cid: track.cid,
      status: 'error',
      error: message,
    );
    tasks.insert(0, task);
    notifyListeners();
  }

  void clearTasks() {
    tasks.clear();
    notifyListeners();
  }

  /// 分享下载文件（替代桌面版"打开下载文件夹"）
  Future<void> shareTask(DownloadTask task) async {
    if (task.filePath.isEmpty) return;
    final file = File(task.filePath);
    if (!await file.exists()) return;
    await Share.shareXFiles(
      [XFile(file.path)],
      text: task.fileName,
      fileNameOverrides: [task.fileName],
    );
  }

  Future<Directory> _ensureDownloadDir() async {
    if (downloadDir != null) {
      final d = Directory(downloadDir!);
      if (await d.exists()) return d;
    }
    // 优先应用外部存储目录；失败/为 null 时回退到应用文档目录（始终可写）
    Directory? base;
    try {
      base = await getExternalStorageDirectory();
    } catch (e) {
      debugPrint('获取外部存储目录失败: $e');
    }
    base ??= await getApplicationDocumentsDirectory();
    final d = await Directory('${base.path}/Download').create(recursive: true);
    downloadDir = d.path;
    return d;
  }

  /// 公开：获取/创建下载目录
  Future<Directory> ensureDownloadDirPublic() => _ensureDownloadDir();

  static String _sanitizeFileName(String name) {
    var cleaned = name.replaceAll(RegExp(r'[<>"/\\|?*]'), '');
    if (cleaned.length > 100) cleaned = cleaned.substring(0, 100);
    return cleaned.trim().isEmpty ? 'audio' : cleaned.trim();
  }

  static String _brief(Object e) {
    if (e is DioException) {
      final resp = e.response;
      if (resp != null) {
        final data = resp.data;
        if (data is Map && data['message'] != null) {
          return '${data['code']} ${data['message']}';
        }
        return 'HTTP ${resp.statusCode}';
      }
      return e.type.name;
    }
    final s = e.toString();
    return s.length > 80 ? s.substring(0, 80) : s;
  }
}
