/// 歌曲/视频数据模型（对应原项目 music 对象）
class Track {
  final String bvid;
  final num aid;
  final num? cid;
  final String title;
  final String author;
  final String cover;
  final num duration;
  final num playCount;
  final num pubdate;
  final String description;
  final String recReason;
  final num videos;
  final num? favId;
  final num? favType;
  final bool isBiliFavoriteResource;
  final num? likeCount;
  final num? coinCount;
  final num? favoriteCount;
  final num? commentCount;

  const Track({
    required this.bvid,
    this.aid = 0,
    this.cid,
    this.title = '',
    this.author = '',
    this.cover = '',
    this.duration = 180,
    this.playCount = 0,
    this.pubdate = 0,
    this.description = '',
    this.recReason = '',
    this.videos = 0,
    this.favId,
    this.favType,
    this.isBiliFavoriteResource = false,
    this.likeCount,
    this.coinCount,
    this.favoriteCount,
    this.commentCount,
  });

  Track copyWith({
    String? bvid,
    num? aid,
    num? cid,
    String? title,
    String? author,
    String? cover,
    num? duration,
    num? playCount,
    num? pubdate,
    String? description,
    String? recReason,
    num? videos,
    num? favId,
    num? favType,
    bool? isBiliFavoriteResource,
    num? likeCount,
    num? coinCount,
    num? favoriteCount,
    num? commentCount,
  }) {
    return Track(
      bvid: bvid ?? this.bvid,
      aid: aid ?? this.aid,
      cid: cid ?? this.cid,
      title: title ?? this.title,
      author: author ?? this.author,
      cover: cover ?? this.cover,
      duration: duration ?? this.duration,
      playCount: playCount ?? this.playCount,
      pubdate: pubdate ?? this.pubdate,
      description: description ?? this.description,
      recReason: recReason ?? this.recReason,
      videos: videos ?? this.videos,
      favId: favId ?? this.favId,
      favType: favType ?? this.favType,
      isBiliFavoriteResource:
          isBiliFavoriteResource ?? this.isBiliFavoriteResource,
      likeCount: likeCount ?? this.likeCount,
      coinCount: coinCount ?? this.coinCount,
      favoriteCount: favoriteCount ?? this.favoriteCount,
      commentCount: commentCount ?? this.commentCount,
    );
  }

  /// 封面 URL 规范化：//x → https://x；CDN 封面追加 ?w=300
  static String fixCoverUrl(String url) {
    var fixed = url;
    if (fixed.startsWith('//')) fixed = 'https:$fixed';
    if ((fixed.contains('hdslb.com') || fixed.contains('bilibili.com')) &&
        !RegExp(r'[?&]w=').hasMatch(fixed)) {
      fixed = '$fixed${fixed.contains('?') ? '&' : '?'}w=300';
    }
    return fixed;
  }

  /// 从 /x/web-interface/search/all/v2 的 video 分节条目构造
  factory Track.fromSearchResult(Map<String, dynamic> item) {
    return Track(
      bvid: item['bvid'] ?? '',
      aid: item['aid'] ?? 0,
      title: _stripHtml(item['title'] ?? ''),
      author: _stripHtml(item['author'] ?? ''),
      cover: fixCoverUrl(item['pic'] ?? ''),
      duration: _parseDuration(item['duration']),
      playCount: item['play'] ?? 0,
      pubdate: item['pubdate'] ?? 0,
      description: item['description'] ?? '',
      videos: item['videos'] ?? 0,
    );
  }

  /// 从 /x/web-interface/region/feed/rcmd 推荐条目构造
  factory Track.fromRegionFeed(Map<String, dynamic> item) {
    return Track(
      bvid: item['bvid'] ?? '',
      aid: item['aid'] ?? 0,
      cid: item['cid'],
      title: _stripHtml(item['title'] ?? ''),
      author: item['author']?['name'] ?? '',
      cover: fixCoverUrl(item['cover'] ?? ''),
      duration: item['duration'] ?? 180,
      playCount: item['stat']?['view'] ?? 0,
      pubdate: item['pubdate'] ?? 0,
      recReason: item['rcmd_reason']?['content'] ?? '',
    );
  }

  /// 从收藏资源 infos 构造
  factory Track.fromFavResource(Map<String, dynamic> item) {
    final id = item['id'];
    final type = item['type'] ?? 2;
    return Track(
      bvid: item['bvid'] ?? item['bv_id'] ?? '',
      aid: item['aid'] ?? 0,
      cid: item['cid'],
      title: _stripHtml(item['title'] ?? ''),
      author: item['upper']?['name'] ?? '',
      cover: fixCoverUrl(item['cover'] ?? ''),
      duration: item['duration'] ?? 180,
      playCount: item['cnt_info']?['play'] ?? 0,
      pubdate: item['pubdate'] ?? 0,
      favId: id,
      favType: type,
      isBiliFavoriteResource: true,
    );
  }

  /// 从 /x/web-interface/view 构造（含统计信息）
  factory Track.fromView(Map<String, dynamic> data) {
    final stat = data['stat'] ?? <String, dynamic>{};
    return Track(
      bvid: data['bvid'] ?? '',
      aid: data['aid'] ?? 0,
      cid: data['cid'],
      title: _stripHtml(data['title'] ?? ''),
      author: data['owner']?['name'] ?? '',
      cover: fixCoverUrl(data['pic'] ?? ''),
      duration: data['duration'] ?? 180,
      playCount: stat['view'] ?? 0,
      pubdate: data['pubdate'] ?? 0,
      description: data['desc'] ?? '',
      videos: data['videos'] ?? 0,
      likeCount: stat['like'],
      coinCount: stat['coin'],
      favoriteCount: stat['favorite'],
      commentCount: stat['reply'],
    );
  }

  static String _stripHtml(String s) =>
      s.replaceAll(RegExp(r'<[^>]*>'), '');

  /// 解码常见 HTML 实体（第三方导出的歌单标题里常见 &#x27; / &amp; 等）
  static String _unescapeHtml(String s) => s
      .replaceAll('&#x27;', "'")
      .replaceAll('&#39;', "'")
      .replaceAll('&apos;', "'")
      .replaceAll('&quot;', '"')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&amp;', '&');

  static num _parseDuration(String d) {
    if (d.isEmpty) return 180;
    final parts = d.split(':');
    if (parts.length == 2) {
      return int.tryParse(parts[0])! * 60 + int.tryParse(parts[1])!;
    } else if (parts.length == 3) {
      return int.tryParse(parts[0])! * 3600 +
          int.tryParse(parts[1])! * 60 +
          int.tryParse(parts[2])!;
    }
    return 180;
  }

  /// 兼容 duration 为数字（秒）或字符串（"m:ss" / "h:mm:ss"）
  static num _parseAnyDuration(dynamic d) {
    if (d is num) return d;
    if (d is String) {
      try {
        return _parseDuration(d);
      } catch (_) {
        return 180;
      }
    }
    return 180;
  }

  Map<String, dynamic> toJson() => {
        'bvid': bvid,
        'aid': aid,
        'cid': cid,
        'title': title,
        'author': author,
        'cover': cover,
        'duration': duration,
        'playCount': playCount,
        'pubdate': pubdate,
        'description': description,
        'recReason': recReason,
        'videos': videos,
        'favId': favId,
        'favType': favType,
        'isBiliFavoriteResource': isBiliFavoriteResource,
        'likeCount': likeCount,
        'coinCount': coinCount,
        'favoriteCount': favoriteCount,
        'commentCount': commentCount,
      };

  factory Track.fromJson(Map<String, dynamic> json) => Track(
        bvid: json['bvid']?.toString() ?? '',
        aid: json['aid'] is num ? json['aid'] : 0,
        cid: json['cid'] is num ? json['cid'] : null,
        title: _unescapeHtml(_stripHtml(json['title']?.toString() ?? '')),
        author: _unescapeHtml(_stripHtml(json['author']?.toString() ?? '')),
        cover: json['cover']?.toString() ?? '',
        duration: _parseAnyDuration(json['duration']),
        playCount: json['playCount'] is num ? json['playCount'] : 0,
        pubdate: json['pubdate'] is num ? json['pubdate'] : 0,
        description: _unescapeHtml(json['description']?.toString() ?? ''),
        recReason: json['recReason']?.toString() ?? '',
        videos: json['videos'] is num ? json['videos'] : 0,
        favId: json['favId'],
        favType: json['favType'],
        isBiliFavoriteResource: json['isBiliFavoriteResource'] ?? false,
        likeCount: json['likeCount'],
        coinCount: json['coinCount'],
        favoriteCount: json['favoriteCount'],
        commentCount: json['commentCount'],
      );

  /// 播放历史去重 key
  String get dedupeKey => bvid;

  /// 添加歌单去重 key（bvid + cid）
  String get playlistDedupeKey => '$bvid:$cid';
}
