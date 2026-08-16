/// 歌词行（时间 ms + 原文 + 罗马音 + 翻译）
class LyricLine {
  final int time;
  final String text;
  final String romaji;
  final String translation;

  const LyricLine({
    required this.time,
    this.text = '',
    this.romaji = '',
    this.translation = '',
  });

  Map<String, dynamic> toJson() => {
        'time': time,
        'text': text,
        'romaji': romaji,
        'translation': translation,
      };

  factory LyricLine.fromJson(Map<String, dynamic> json) => LyricLine(
        time: (json['time'] ?? 0).toInt(),
        text: json['text'] ?? '',
        romaji: json['romaji'] ?? '',
        translation: json['translation'] ?? '',
      );
}

/// 解析后的歌词
class Lyric {
  final List<LyricLine> lines;
  final String title;
  final String artist;

  const Lyric({
    this.lines = const [],
    this.title = '',
    this.artist = '',
  });

  Map<String, dynamic> toJson() => {
        'lyrics': lines.map((l) => l.toJson()).toList(),
        'title': title,
        'artist': artist,
        '_lyricV3': true,
      };

  factory Lyric.fromJson(Map<String, dynamic> json) {
    final raw = json['lyrics'];
    return Lyric(
      lines: (raw is List)
          ? raw
              .whereType<Map<String, dynamic>>()
              .map(LyricLine.fromJson)
              .toList()
          : [],
      title: json['title'] ?? '',
      artist: json['artist'] ?? '',
    );
  }

  /// 缓存 key：bvid-cid-艺术家-标题（清洗非字母数字，截断）
  static String cacheKey(String bvid, num? cid, String title, String artist) {
    final safeTitle = _sanitize(title, 40);
    final safeArtist = _sanitize(artist, 20);
    return '$bvid-${cid ?? 1}-$safeArtist-$safeTitle';
  }

  static String _sanitize(String s, int maxLen) {
    final cleaned = s.replaceAll(RegExp('[^a-zA-Z0-9]'), '');
    return cleaned.length > maxLen ? cleaned.substring(0, maxLen) : cleaned;
  }
}
