import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/playlist.dart';
import '../models/track.dart';

/// 歌单管理（对应原项目 src/stores/playlist.js）
class PlaylistStore extends ChangeNotifier {
  static const String _key = 'pink-music-playlists';

  List<Playlist> userPlaylists = [];

  Playlist? get defaultPlaylistOrNull =>
      userPlaylists.firstWhere((p) => p.isDefault, orElse: () => throw StateError('no default'));

  Playlist get defaultPlaylist {
    if (userPlaylists.isEmpty) throw StateError('userPlaylists is empty, call load() first');
    return defaultPlaylistOrNull!;
  }

  Playlist? findById(String id) {
    for (final p in userPlaylists) {
      if (p.id == id) return p;
    }
    return null;
  }

  Playlist? findBiliFavorite(num mediaId) {
    for (final p in userPlaylists) {
      if (p.isBiliFavorite && p.biliMediaId == mediaId.toString()) return p;
    }
    return null;
  }

  void _ensureDefault() {
    if (!userPlaylists.any((p) => p.isDefault)) {
      userPlaylists.insert(
          0,
          Playlist(
              id: 'favorites',
              name: '收藏夹',
              isDefault: true));
    }
  }

  /// 创建歌单
  Playlist createPlaylist(String name, {Map<String, dynamic>? extra}) {
    final playlist = Playlist(
      id: Playlist.genId(),
      name: name.isEmpty ? '新建歌单' : name,
      music: extra?['music'] is List
          ? List<Track>.from(extra!['music'] as List)
          : [],
      cover: extra?['cover'] ?? '',
      isBiliFavorite: extra?['isBiliFavorite'] ?? false,
      mediaCount: extra?['media_count'] ?? 0,
      biliSource: extra?['biliSource'] ?? '',
      biliMediaId: extra?['biliMediaId']?.toString(),
    );
    userPlaylists.add(playlist);
    save();
    notifyListeners();
    return playlist;
  }

  bool deletePlaylist(String id) {
    final p = findById(id);
    if (p == null || p.isDefault) return false;
    userPlaylists.removeWhere((pl) => pl.id == id);
    save();
    notifyListeners();
    return true;
  }

  void renamePlaylist(String id, String name) {
    final p = findById(id);
    if (p == null) return;
    p.name = name.isEmpty ? '新建歌单' : name;
    save();
    notifyListeners();
  }

  /// 添加到歌单（bvid+cid 去重）
  bool addToPlaylist(Track track, {String? playlistId}) {
    final target = playlistId != null
        ? findById(playlistId)
        : (findById('favorites') ?? defaultPlaylistOrNull);
    if (target == null) return false;
    final added = target.addTrack(track);
    save();
    notifyListeners();
    return added;
  }

  void removeFromPlaylist(String playlistId, Track track) {
    final p = findById(playlistId);
    if (p == null) return;
    p.removeTrack(track);
    save();
    notifyListeners();
  }

  /// 批量删除歌单
  void batchDeletePlaylists(Set<String> ids) {
    final before = userPlaylists.length;
    userPlaylists.removeWhere((p) => ids.contains(p.id) && !p.isDefault);
    save();
    if (userPlaylists.length != before) notifyListeners();
  }

  /// 批量添加歌曲到歌单（bvid:cid 去重）
  int pushTracksToPlaylist(String playlistId, List<Track> tracks) {
    final p = findById(playlistId);
    if (p == null) return 0;
    var added = 0;
    for (final t in tracks) {
      if (p.addTrack(t)) added++;
    }
    save();
    notifyListeners();
    return added;
  }

  /// 合并 B 站收藏夹（对应 mergeBiliFavorites）
  void mergeBiliFavorites(List<Map<String, dynamic>> favList) {
    for (final f in favList) {
      final id = f['id'];
      final playlistId = 'bili-fav-$id';
      final existing = findById(playlistId);
      if (existing != null) {
        existing.name = f['title'] ?? existing.name;
        if (f['cover'] != null && f['cover'].toString().isNotEmpty) {
          existing.cover = f['cover'].toString();
        }
        existing.mediaCount = f['media_count'] ?? existing.mediaCount;
      } else {
        userPlaylists.add(Playlist(
          id: playlistId,
          name: f['title'] ?? '收藏夹',
          cover: f['cover'] ?? '',
          isBiliFavorite: true,
          mediaCount: f['media_count'] ?? 0,
          biliSource: f['source'] ?? 'created',
          biliMediaId: id.toString(),
        ));
      }
    }
    save();
    notifyListeners();
  }

  /// 更新收藏夹内的歌曲（加载收藏资源后）
  void updateBiliFavoriteMusic(String playlistId, List<Track> tracks) {
    final p = findById(playlistId);
    if (p == null) return;
    p.music = tracks;
    save();
    notifyListeners();
  }

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw != null && raw.isNotEmpty) {
      try {
        final list = jsonDecode(raw);
        if (list is List) {
          userPlaylists = list
              .whereType<Map<String, dynamic>>()
              .map(Playlist.fromJson)
              .toList();
        }
      } catch (_) {
        userPlaylists = [];
      }
    }
    _ensureDefault();
    notifyListeners();
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _key, jsonEncode(userPlaylists.map((p) => p.toJson()).toList()));
  }
}
