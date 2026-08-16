import 'package:flutter/foundation.dart';

import '../models/track.dart';
import '../services/bilibili_api.dart';

/// 搜索状态（对应原项目 src/stores/search.js + useMusic.js）
class SearchStore extends ChangeNotifier {
  final BilibiliApi api;

  SearchStore(this.api);

  String searchQuery = '';
  bool isSearching = false;
  List<Track> searchResults = [];
  bool isLoadingSearch = false;
  List<Track> recommendedMusic = [];
  bool isLoadingRecommended = false;

  static const List<String> _recommendKeywords = [
    '热门音乐', '流行歌曲', '经典老歌', '电音', '摇滚',
    '民谣', '说唱', '古风', '轻音乐', '影视原声',
  ];

  List<String> get recommendKeywords =>
      List.of(_recommendKeywords)..shuffle();

  Future<void> handleSearch(String keyword) async {
    if (keyword.trim().isEmpty) return;
    searchQuery = keyword.trim();
    isLoadingSearch = true;
    isSearching = true;
    notifyListeners();
    try {
      searchResults = await api.searchMusic(searchQuery, 1, 30);
    } catch (e) {
      debugPrint('搜索失败: $e');
      searchResults = [];
    }
    isLoadingSearch = false;
    notifyListeners();
  }

  /// 加载推荐（音乐区推荐 + 随机关键词搜索混合洗牌）
  Future<void> loadRecommendations() async {
    isLoadingRecommended = true;
    notifyListeners();
    final feed = <Track>[];
    try {
      final shuffledKeywords = List<String>.from(_recommendKeywords)..shuffle();
      final searchKeyword = shuffledKeywords.isNotEmpty
          ? shuffledKeywords.first
          : _recommendKeywords.first;
      final results = await Future.wait([
        api.getMusicRegionFeed(1, 20),
        api.searchMusic(searchKeyword, 1, 20),
      ]);
      feed.addAll(results[0]);
      feed.addAll(results[1]);
      feed.shuffle();
    } catch (e) {
      debugPrint('加载推荐失败: $e');
      try {
        feed.addAll(await api.getMusicRegionFeed(1, 20));
      } catch (_) {}
    }
    recommendedMusic = feed;
    isLoadingRecommended = false;
    notifyListeners();
  }
}
