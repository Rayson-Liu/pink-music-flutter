import 'package:flutter/material.dart';

import '../app.dart';
import '../services/audio_stream.dart';
import '../state/settings_store.dart';
import '../state/theme_store.dart';
import 'widgets/dialogs.dart';

/// 设置面板（音频 / 外观 / 关于）
class SettingsPanel extends StatefulWidget {
  const SettingsPanel({super.key});

  @override
  State<SettingsPanel> createState() => _SettingsPanelState();
}

class _SettingsPanelState extends State<SettingsPanel>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  List<num> _pendingBands = List<num>.filled(10, 0);
  bool _draftInitialized = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final svc = AppServices.instance;
    return Scaffold(
      appBar: AppBar(
        title: const Text('设置'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: '音频'),
            Tab(text: '外观'),
            Tab(text: '关于'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          ListenableBuilder(
            listenable: svc.settings,
            builder: (context, _) => _buildAudioTab(svc),
          ),
          ListenableBuilder(
            listenable: svc.theme,
            builder: (context, _) => _buildAppearanceTab(svc),
          ),
          _buildAboutTab(),
        ],
      ),
    );
  }

  // ---------------- 音频 ----------------

  Widget _buildAudioTab(AppServices svc) {
    final s = svc.settings;
    if (!_draftInitialized) {
      _pendingBands = List<num>.from(s.eqBands);
      _draftInitialized = true;
    }
    return ListView(
      padding: const EdgeInsets.only(bottom: 40),
      children: [
        _sectionTitle('播放'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: DropdownButtonFormField<String>(
            initialValue: s.audioQuality,
            decoration: const InputDecoration(
              labelText: '音质',
              prefixIcon: Icon(Icons.audio_file),
            ),
            items: AudioQuality.options
                .map((q) => DropdownMenuItem(
                    value: q, child: Text(AudioQuality.label(q))))
                .toList(),
            onChanged: (v) {
              if (v != null) s.setAudioQuality(v);
            },
          ),
        ),
        SwitchListTile(
          secondary: const Icon(Icons.equalizer),
          title: const Text('均衡器'),
          subtitle: const Text('10 段均衡（31Hz–16kHz，±12dB）'),
          value: s.eqEnabled,
          onChanged: (v) {
            s.setEqEnabled(v);
            svc.engine.syncEqNow();
          },
        ),
        const Divider(),
        _sectionTitle('专辑波纹'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              const Text('激进度', style: TextStyle(fontSize: 13)),
              Expanded(
                child: Slider(
                  value: (s.audioVisualizerIntensity * 100).roundToDouble(),
                  min: 0,
                  max: 100,
                  divisions: 100,
                  label: '${(s.audioVisualizerIntensity * 100).round()}',
                  onChanged: (v) => s.setAudioVisualizerIntensity(v / 100),
                ),
              ),
              Text('${(s.audioVisualizerIntensity * 100).round()}',
                  style: const TextStyle(fontSize: 12)),
            ],
          ),
        ),
        const Divider(),
        _sectionTitle('歌词'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: DropdownButtonFormField<String>(
            initialValue: s.lyricDisplayMode,
            decoration: const InputDecoration(labelText: '歌词显示'),
            items: const [
              DropdownMenuItem(value: 'original', child: Text('原文')),
              DropdownMenuItem(value: 'romaji', child: Text('罗马音')),
              DropdownMenuItem(value: 'translation', child: Text('翻译')),
            ],
            onChanged: (v) => s.setLyricDisplayMode(v!),
          ),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: DropdownButtonFormField<String>(
            initialValue: s.lyricSource,
            decoration: const InputDecoration(labelText: '歌词来源'),
            items: const [
              DropdownMenuItem(value: 'netease', child: Text('网易云音乐（默认）')),
              DropdownMenuItem(value: 'qq', child: Text('QQ音乐')),
            ],
            onChanged: (v) {
              if (v != null) s.setLyricSource(v);
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              const Text('歌词字号', style: TextStyle(fontSize: 13)),
              Expanded(
                child: Slider(
                  value: s.lyricFontSize.clamp(12, 28),
                  min: 12,
                  max: 28,
                  divisions: 8,
                  label: '${s.lyricFontSize.round()}',
                  onChanged: (v) => s.setLyricFontSize(v),
                ),
              ),
              Text('${s.lyricFontSize.round()}',
                  style: const TextStyle(fontSize: 12)),
            ],
          ),
        ),
        const Divider(),
        if (s.eqEnabled) _buildEqSection(svc),
      ],
    );
  }

  Widget _buildEqSection(AppServices svc) {
    final s = svc.settings;
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Text('均衡器', style: theme.textTheme.titleMedium),
              const Spacer(),
              TextButton(
                onPressed: () {
                  s.resetEq();
                  _pendingBands = List<num>.from(s.eqBands);
                  svc.engine.syncEqNow();
                },
                child: const Text('重置'),
              ),
              FilledButton(
                onPressed: () {
                  s.commitEQBands(_pendingBands);
                  svc.engine.syncEqNow();
                  showToast(context, '已应用均衡器');
                },
                child: const Text('应用'),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: DropdownButtonFormField<String>(
            initialValue: s.eqPreset,
            decoration: const InputDecoration(labelText: '预设'),
            items: kEqPresets
                .map((p) => DropdownMenuItem(
                    value: p.key, child: Text(p.name)))
                .toList(),
            onChanged: (v) {
              s.setEqPreset(v!);
              _pendingBands = List<num>.from(s.eqBands);
              svc.engine.syncEqNow();
            },
          ),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text('拖动滑块调整增益，点击「应用」生效',
              style: TextStyle(fontSize: 11, color: theme.hintColor)),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 220,
          child: Row(
            children: List.generate(10, (i) {
              final value = _pendingBands[i].toDouble();
              return Expanded(
                child: Column(
                  children: [
                    Text('${value >= 0 ? '+' : ''}${value.toStringAsFixed(1)}',
                        style: TextStyle(
                            fontSize: 10,
                            color: value != 0
                                ? theme.colorScheme.primary
                                : theme.hintColor)),
                    Expanded(
                      child: RotatedBox(
                        quarterTurns: 3,
                        child: Slider(
                          value: value.clamp(kEqDbMin, kEqDbMax),
                          min: kEqDbMin,
                          max: kEqDbMax,
                          divisions: ((kEqDbMax - kEqDbMin) / kEqDbStep)
                              .round(),
                          onChanged: (v) {
                            setState(() {
                              _pendingBands[i] =
                                  (v / kEqDbStep).round() * kEqDbStep;
                            });
                          },
                        ),
                      ),
                    ),
                    Text(kEqBandLabels[i],
                        style: const TextStyle(fontSize: 9)),
                  ],
                ),
              );
            }),
          ),
        ),
      ],
    );
  }

  // ---------------- 外观 ----------------

  Widget _buildAppearanceTab(AppServices svc) {
    final t = svc.theme;
    return ListView(
      padding: const EdgeInsets.only(bottom: 40),
      children: [
        _sectionTitle('模式'),
        SwitchListTile(
          secondary: const Icon(Icons.dark_mode_outlined),
          title: Text(t.isDark ? '深色模式' : '浅色模式'),
          value: t.isDark,
          onChanged: (_) => t.toggleTheme(),
        ),
        _sectionTitle('主题颜色'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            children: kColorThemes.map((c) {
              final selected = t.currentColor == c.name;
              return InkWell(
                onTap: () => t.setColor(c.name),
                borderRadius: BorderRadius.circular(28),
                child: Column(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: c.primary,
                        shape: BoxShape.circle,
                        border: selected
                            ? Border.all(
                                color: Theme.of(context).colorScheme.onSurface,
                                width: 3)
                            : null,
                      ),
                      child: selected
                          ? Icon(Icons.check,
                              color: c.name == 'pink' ||
                                      c.name == 'purple' ||
                                      c.name == 'apple-music'
                                  ? Colors.white
                                  : Colors.black,
                              size: 20)
                          : null,
                    ),
                    const SizedBox(height: 4),
                    Text(_colorName(c.name),
                        style: const TextStyle(fontSize: 11)),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  static String _colorName(String name) => switch (name) {
        'pink' => '粉色',
        'purple' => '紫色',
        'blue' => '蓝色',
        'green' => '绿色',
        'orange' => '橙色',
        'apple-music' => 'Apple Music',
        _ => name,
      };

  // ---------------- 关于 ----------------

  Widget _buildAboutTab() {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const SizedBox(height: 16),
        Center(
          child: Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.music_note,
                size: 40, color: theme.colorScheme.primary),
          ),
        ),
        const SizedBox(height: 12),
        const Center(
          child: Text('Pink Music',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        ),
        const Center(
            child: Text('v1.0.0',
                style: TextStyle(fontSize: 12, color: Colors.grey))),
        const SizedBox(height: 24),
        const Text('基于哔哩哔哩（B 站）公开接口的移动端音乐播放器',
            style: TextStyle(fontSize: 13)),
        const SizedBox(height: 8),
        const Text(
            '本应用仅供学习与研究使用，禁止任何形式的商业用途。\n'
            '与哔哩哔哩无任何官方关联或背书；使用时请遵守 B 站用户协议。',
            style: TextStyle(fontSize: 12, color: Colors.grey, height: 1.5)),
        const SizedBox(height: 16),
        const Text('开源项目：https://github.com/Rayson-Liu/pink-music-flutter',
            style: TextStyle(fontSize: 12, color: Colors.grey)),
      ],
    );
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(title,
          style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.primary)),
    );
  }
}
