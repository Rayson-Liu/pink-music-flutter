import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../app.dart';
import '../models/playlist.dart';
import 'download_manager.dart';
import 'login_panel.dart';
import 'player_page.dart';
import 'playlist_detail.dart';
import 'settings_panel.dart';
import 'widgets/cover_image.dart';
import 'widgets/dialogs.dart';

/// 我的页：登录 + 收藏夹 + 本地歌单 + 下载/设置入口
class MineView extends StatefulWidget {
  const MineView({super.key});

  @override
  State<MineView> createState() => _MineViewState();
}

class _MineViewState extends State<MineView> {
  bool _selectMode = false;
  final Set<String> _selected = {};

  @override
  Widget build(BuildContext context) {
    final svc = AppServices.instance;
    final theme = Theme.of(context);
    return SafeArea(
      bottom: false,
      child: ListenableBuilder(
        listenable: Listenable.merge([svc.user, svc.playlists]),
        builder: (context, _) {
          final playlists = svc.playlists.userPlaylists;
          final biliFavs =
              playlists.where((p) => p.isBiliFavorite).toList();
          final local =
              playlists.where((p) => !p.isBiliFavorite).toList();

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Row(
                  children: [
                    Text('我的',
                        style: theme.textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.bold)),
                    const Spacer(),
                    if (_selectMode)
                      TextButton(
                        onPressed: () {
                          final toDelete =
                              _selected.where((id) =>
                                  !(svc.playlists.findById(id)?.isDefault ??
                                      false));
                          if (toDelete.isNotEmpty) {
                            appConfirm(context,
                                title: '删除歌单',
                                message: '确定删除选中的 ${toDelete.length} 个歌单？',
                                okText: '删除').then((ok) {
                              if (ok) {
                                svc.playlists.batchDeletePlaylists(
                                    _selected.toSet());
                              }
                              setState(() {
                                _selectMode = false;
                                _selected.clear();
                              });
                            });
                          } else {
                            setState(() {
                              _selectMode = false;
                              _selected.clear();
                            });
                          }
                        },
                        child: const Text('删除'),
                      )
                    else
                      IconButton(
                        icon: const Icon(Icons.edit),
                        tooltip: '批量管理',
                        onPressed: () =>
                            setState(() => _selectMode = true),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.only(bottom: 120),
                  children: [
                    _buildUserCard(svc, theme),
                    const SizedBox(height: 8),
                    if (biliFavs.isNotEmpty) ...[
                      _entryHeader('B 站收藏夹'),
                      ...biliFavs.map((p) => _playlistTile(svc, p)),
                    ],
                    _entryHeader('本地歌单'),
                    ...local.map((p) => _playlistTile(svc, p)),
                    _entryHeader('更多'),
                    ListTile(
                      leading: const Icon(Icons.file_upload_outlined),
                      title: const Text('导入歌单'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _importPlaylist(svc),
                    ),
                    ListTile(
                      leading: const Icon(Icons.download),
                      title: const Text('下载管理'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const DownloadManager())),
                    ),
                    ListTile(
                      leading: const Icon(Icons.settings),
                      title: const Text('设置'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const SettingsPanel())),
                    ),
                    ListTile(
                      leading: const Icon(Icons.info_outline),
                      title: const Text('关于'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => showAboutDialog(
                        context: context,
                        applicationName: 'Pink Music',
                        applicationVersion: '1.0.0',
                        applicationIcon: const Icon(Icons.music_note,
                            size: 40, color: Colors.pinkAccent),
                        children: const [
                          Text('基于哔哩哔哩公开接口的移动端音乐播放器\n'
                              '仅供学习与研究使用，禁止商业用途。\n'
                              '项目地址：https://github.com/Rayson-Liu/pink-music-flutter'),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // ---------- 登录卡片 ----------

  Widget _buildUserCard(AppServices svc, ThemeData theme) {
    if (svc.user.isLoggedIn) {
      return Card(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        child: ListTile(
          leading: ClipOval(
            child: CoverImage(
              url: svc.user.face ?? '',
              size: 44,
              radius: 22,
            ),
          ),
          title: Text(svc.user.uname ?? 'B 站用户',
              style: const TextStyle(fontWeight: FontWeight.bold)),
          subtitle: const Text('已登录'),
          trailing: TextButton(
            onPressed: () async {
              final ok = await appConfirm(context,
                  title: '退出登录',
                  message: '确定退出当前账号？',
                  okText: '退出');
              if (ok) await svc.user.logout();
            },
            child: const Text('退出'),
          ),
        ),
      );
    }
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.15),
          child: Icon(Icons.person, color: theme.colorScheme.primary),
        ),
        title: const Text('登录哔哩哔哩',
            style: TextStyle(fontWeight: FontWeight.bold)),
        subtitle: const Text('登录后同步收藏夹'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const LoginPanel())),
      ),
    );
  }

  // ---------- 歌单 ----------

  Widget _playlistTile(AppServices svc, Playlist p) {
    final theme = Theme.of(context);
    return ListTile(
      leading: Stack(
        children: [
          CoverImage(url: p.cover, size: 44),
          if (p.isBiliFavorite)
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text('B',
                    style: TextStyle(color: Colors.white, fontSize: 8)),
              ),
            ),
        ],
      ),
      title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(
          '${p.isBiliFavorite ? (p.mediaCount > 0 ? '${p.mediaCount} 个收藏 · ' : '') : ''}${p.music.length} 首'),
      trailing: _selectMode
          ? Checkbox(
              value: _selected.contains(p.id),
              onChanged: (v) => setState(() {
                if (v == true) {
                  _selected.add(p.id);
                } else {
                  _selected.remove(p.id);
                }
              }),
            )
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.play_circle_outline),
                  tooltip: '播放全部',
                  onPressed: () => _playAll(svc, p),
                ),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_horiz),
                  onSelected: (v) => _handlePlaylistMenu(svc, p, v),
                  itemBuilder: (context) => [
                    const PopupMenuItem(value: 'play', child: Text('播放全部')),
                    if (!p.isBiliFavorite) ...[
                      const PopupMenuItem(value: 'rename', child: Text('重命名')),
                      const PopupMenuItem(value: 'export', child: Text('导出')),
                    ],
                    if (!p.isDefault)
                      const PopupMenuItem(value: 'delete', child: Text('删除')),
                  ],
                ),
              ],
            ),
      onTap: () {
        if (_selectMode) {
          setState(() {
            if (!_selected.contains(p.id)) {
              _selected.add(p.id);
            } else {
              _selected.remove(p.id);
            }
          });
        } else {
          Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => PlaylistDetailPage(playlistId: p.id)));
        }
      },
    );
  }

  void _playAll(AppServices svc, Playlist p) {
    if (p.music.isEmpty) {
      showToast(context, p.isBiliFavorite ? '该收藏夹尚未加载到本地歌单，请先点击"加载视频"' : '歌单为空');
      return;
    }
    svc.engine.playMusic(p.music.first, view: 'playlist', queue: p.music);
    Navigator.push(context, PlayerPage.route());
  }

  void _handlePlaylistMenu(AppServices svc, Playlist p, String value) {
    switch (value) {
      case 'play':
        _playAll(svc, p);
      case 'rename':
        promptText(context, title: '重命名歌单', initial: p.name).then((name) {
          if (name != null && name.isNotEmpty) {
            svc.playlists.renamePlaylist(p.id, name);
          }
        });
      case 'export':
        _exportPlaylist(svc, p);
      case 'delete':
        appConfirm(context,
            title: '删除歌单',
            message: '确定删除歌单「${p.name}」？',
            okText: '删除').then((ok) {
          if (ok) svc.playlists.deletePlaylist(p.id);
        });
    }
  }

  void _exportPlaylist(AppServices svc, Playlist p) async {
    final json = jsonEncodePlaylist(p);
    final fileName = '${p.name}.json';
    final dir = await svc.downloads.ensureDownloadDirPublic();
    final file = await _writeFile('${dir.path}/$fileName', json);
    if (!mounted) return;
    final ok = await appConfirm(context,
        title: '导出歌单',
        message: '已导出到下载目录\n$fileName',
        okText: '分享文件');
    if (ok) {
      await _shareFile(file);
    }
  }

  void _importPlaylist(AppServices svc) async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    final path = result?.files.first.path;
    if (path == null) return;
    try {
      final content = await File(path).readAsString();
      final map = jsonDecode(content);
      if (map is! Map) throw Exception();
      final imported = Playlist.fromJson(Map<String, dynamic>.from(map));
      if (imported.name.isEmpty) throw Exception();
      svc.playlists.createPlaylist(imported.name,
          extra: {
            'music': imported.music,
            'cover': imported.cover,
          });
      if (!mounted) return;
      showToast(context, '歌单「${imported.name}」导入成功');
    } catch (_) {
      if (!mounted) return;
      showToast(context, '导入失败：文件格式不正确');
    }
  }

  Widget _entryHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
      child: Text(title,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
    );
  }
}

String jsonEncodePlaylist(Playlist p) =>
    const JsonEncoder.withIndent('  ').convert(p.toJson());

Future<File> _writeFile(String path, String content) async {
  final file = File(path);
  await file.writeAsString(content);
  return file;
}

Future<void> _shareFile(File file) async {
  await Share.shareXFiles(
    [XFile(file.path)],
    fileNameOverrides: [file.path.split('/').last],
  );
}
