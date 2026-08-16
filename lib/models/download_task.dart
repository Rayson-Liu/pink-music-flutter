import 'dart:math';

/// 下载任务模型
class DownloadTask {
  final String id;
  final String title;
  final String author;
  final String bvid;
  final num? cid;
  final String quality;
  final String audioCodecs;
  final String fileName;
  String filePath;
  String status; // waiting | downloading | completed | error
  num progress; // 0-100
  num totalBytes;
  num downloadedBytes;
  final num createdTime;
  String error;

  DownloadTask({
    required this.id,
    this.title = '',
    this.author = '',
    this.bvid = '',
    this.cid,
    this.quality = 'auto',
    this.audioCodecs = '',
    this.fileName = '',
    this.filePath = '',
    this.status = 'waiting',
    this.progress = 0,
    this.totalBytes = 0,
    this.downloadedBytes = 0,
    DateTime? createdTime,
    this.error = '',
  }) : createdTime = (createdTime ?? DateTime.now()).millisecondsSinceEpoch;

  static final Random _rng = Random();

  /// 生成任务 id：时间戳 + 随机后缀（对齐原项目
  /// `dl_${Date.now()}_${Math.random().toString(36).substring(2, 11)}`）。
  /// 之前的 `microsecondsSinceEpoch.toString().substring(8, 17)` 在 16 位数字上
  /// 会越界抛 RangeError，导致任务根本创建不出来（下载项不出现）。
  static String genId() {
    final ts = DateTime.now().millisecondsSinceEpoch;
    final rand = _rng.nextInt(0x7fffffff).toRadixString(36);
    return 'dl_${ts}_$rand';
  }

  DownloadTask copyWith({
    String? filePath,
    String? status,
    num? progress,
    num? totalBytes,
    num? downloadedBytes,
    String? error,
  }) {
    return DownloadTask(
      id: id,
      title: title,
      author: author,
      bvid: bvid,
      cid: cid,
      quality: quality,
      audioCodecs: audioCodecs,
      fileName: fileName,
      filePath: filePath ?? this.filePath,
      status: status ?? this.status,
      progress: progress ?? this.progress,
      totalBytes: totalBytes ?? this.totalBytes,
      downloadedBytes: downloadedBytes ?? this.downloadedBytes,
      createdTime: DateTime.fromMillisecondsSinceEpoch(createdTime.toInt()),
      error: error ?? this.error,
    );
  }
}
