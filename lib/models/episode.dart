/// 分P（分集）模型
class Episode {
  final String bvid;
  final num cid;
  final String title;
  final num duration;
  final String cover;
  final String firstFrame;

  const Episode({
    required this.bvid,
    required this.cid,
    this.title = '',
    this.duration = 0,
    this.cover = '',
    this.firstFrame = '',
  });

  factory Episode.fromJson(Map<String, dynamic> json) => Episode(
        bvid: json['bvid'] ?? '',
        cid: json['cid'] ?? 0,
        title: json['part'] ?? '',
        duration: json['duration'] ?? 0,
        cover: json['cover'] ?? '',
        firstFrame: json['first_frame'] ?? '',
      );
}
