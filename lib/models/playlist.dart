import 'track.dart';

/// 歌单模型（对应原项目 playlist 对象）
class Playlist {
  final String id;
  String name;
  List<Track> music;
  bool isDefault;
  String cover;
  bool isBiliFavorite;
  num mediaCount;
  String biliSource; // created | collected
  String? biliMediaId;

  Playlist({
    required this.id,
    required this.name,
    List<Track>? music,
    this.isDefault = false,
    this.cover = '',
    this.isBiliFavorite = false,
    this.mediaCount = 0,
    this.biliSource = '',
    this.biliMediaId,
  }) : music = music ?? [];

  static String genId() {
    final ts = DateTime.now().millisecondsSinceEpoch;
    final rand =
        DateTime.now().microsecondsSinceEpoch.toString().substring(8, 15);
    return '$ts-$rand';
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'music': music.map((t) => t.toJson()).toList(),
        'isDefault': isDefault,
        'cover': cover,
        'isBiliFavorite': isBiliFavorite,
        'media_count': mediaCount,
        'biliSource': biliSource,
        'biliMediaId': biliMediaId,
      };

  factory Playlist.fromJson(Map<String, dynamic> json) {
    final rawMusic = json['music'];
    return Playlist(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '新建歌单',
      music: (rawMusic is List)
          ? rawMusic
              .whereType<Map<String, dynamic>>()
              .map(Track.fromJson)
              .toList()
          : [],
      isDefault: json['isDefault'] ?? false,
      cover: json['cover']?.toString() ?? '',
      isBiliFavorite: json['isBiliFavorite'] ?? false,
      mediaCount: json['media_count'] is num ? json['media_count'] : 0,
      biliSource: json['biliSource']?.toString() ?? '',
      biliMediaId: json['biliMediaId']?.toString(),
    );
  }

  /// 同步封面（默认歌单/本地歌单取第一首歌封面）
  void syncCover() {
    if (isBiliFavorite) return;
    cover = music.isNotEmpty ? music.first.cover : '';
  }

  /// 添加歌曲（bvid+cid 去重）
  bool addTrack(Track t) {
    final key = '${t.bvid}:${t.cid}';
    final exists = music.any((m) => '${m.bvid}:${m.cid}' == key);
    if (exists) return false;
    music.add(t);
    syncCover();
    return true;
  }

  bool removeTrack(Track t) {
    final before = music.length;
    music.removeWhere((m) =>
        m.bvid == t.bvid &&
        (t.cid == null || m.cid == t.cid) &&
        (t.favId == null || m.favId == t.favId));
    syncCover();
    return music.length != before;
  }
}
