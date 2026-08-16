import 'package:flutter/material.dart';

import '../app.dart';

/// 分P（分集）面板
class SeriesPanel extends StatelessWidget {
  const SeriesPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final svc = AppServices.instance;
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: svc.player,
      builder: (context, _) {
        final eps = svc.player.currentVideoEpisodes;
        if (eps.isEmpty) {
          return const SafeArea(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: Text('暂无分P')),
            ),
          );
        }
        final currentIdx = svc.player.currentEpisodeIndex;
        return SafeArea(
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.6,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Text('分P（${eps.length}）',
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold)),
                      const Spacer(),
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('完成'),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: ListView.builder(
                    itemCount: eps.length,
                    itemBuilder: (context, i) {
                      final ep = eps[i];
                      final active = i == currentIdx;
                      return ListTile(
                        leading: CircleAvatar(
                          radius: 14,
                          backgroundColor: active
                              ? theme.colorScheme.primary
                              : theme.colorScheme.surfaceContainerHighest,
                          child: Text(
                            '${i + 1}',
                            style: TextStyle(
                              fontSize: 12,
                              color: active ? Colors.white : theme.hintColor,
                            ),
                          ),
                        ),
                        title: Text(
                          ep.title.isEmpty ? '第 ${i + 1} 话' : ep.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight:
                                active ? FontWeight.bold : FontWeight.normal,
                            color: active
                                ? theme.colorScheme.primary
                                : null,
                          ),
                        ),
                        trailing: ep.duration > 0
                            ? Text(_fmt(ep.duration.toInt()),
                                style: TextStyle(
                                    fontSize: 11,
                                    color: theme.hintColor))
                            : null,
                        onTap: () {
                          Navigator.pop(context);
                          svc.engine.playEpisode(ep);
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  static String _fmt(int sec) {
    final m = sec ~/ 60;
    final s = sec % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }
}
