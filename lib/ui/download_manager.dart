import 'package:flutter/material.dart';

import '../app.dart';
import '../models/download_task.dart';
import 'widgets/dialogs.dart';

/// 下载管理器
class DownloadManager extends StatelessWidget {
  const DownloadManager({super.key});

  @override
  Widget build(BuildContext context) {
    final svc = AppServices.instance;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('下载管理'),
        actions: [
          ListenableBuilder(
            listenable: svc.downloads,
            builder: (context, _) {
              if (svc.downloads.tasks.isEmpty) {
                return const SizedBox.shrink();
              }
              return IconButton(
                icon: const Icon(Icons.delete_sweep),
                tooltip: '清空记录',
                onPressed: () async {
                  final ok = await appConfirm(context,
                      title: '清空下载记录',
                      message: '确定清空所有下载记录？',
                      okText: '清空');
                  if (ok) svc.downloads.clearTasks();
                },
              );
            },
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: svc.downloads,
        builder: (context, _) {
          final tasks = svc.downloads.tasks;
          if (tasks.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.download_outlined,
                      size: 56, color: theme.hintColor),
                  const SizedBox(height: 12),
                  Text('暂无下载任务', style: TextStyle(color: theme.hintColor)),
                ],
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: tasks.length,
            itemBuilder: (context, i) => _TaskTile(task: tasks[i]),
          );
        },
      ),
    );
  }
}

class _TaskTile extends StatelessWidget {
  final DownloadTask task;
  const _TaskTile({required this.task});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusColor = switch (task.status) {
      'completed' => const Color(0xFF22C55E),
      'error' => const Color(0xFFEF4444),
      _ => theme.colorScheme.primary,
    };
    final statusText = switch (task.status) {
      'waiting' => '等待中',
      'downloading' => '下载中 ${task.progress}%',
      'completed' => '已完成',
      'error' => '失败',
      _ => task.status,
    };
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: statusColor.withValues(alpha: 0.12),
        child: Icon(
          switch (task.status) {
            'completed' => Icons.check,
            'error' => Icons.error_outline,
            _ => Icons.download,
          },
          color: statusColor,
          size: 20,
        ),
      ),
      title: Text(task.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${task.author} · $statusText',
              style: TextStyle(fontSize: 12, color: theme.hintColor)),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: task.status == 'completed'
                  ? 1
                  : (task.progress / 100).clamp(0.0, 1.0),
              minHeight: 3,
              backgroundColor:
                  theme.colorScheme.surfaceContainerHighest,
            ),
          ),
        ],
      ),
      trailing: task.status == 'completed' && task.filePath.isNotEmpty
          ? PopupMenuButton<String>(
              icon: const Icon(Icons.more_horiz),
              onSelected: (v) {
                if (v == 'share') {
                  AppServices.instance.downloads.shareTask(task);
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(value: 'share', child: Text('分享文件')),
              ],
            )
          : null,
    );
  }
}
