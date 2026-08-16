import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 均衡器常量（精确移植 src/utils/audioEQ.js）
const List<num> kEqBands = [31, 62, 125, 250, 500, 1000, 2000, 4000, 8000, 16000];
const List<String> kEqBandLabels = [
  '31', '62', '125', '250', '500', '1K', '2K', '4K', '8K', '16K'
];
const double kEqDbMin = -12;
const double kEqDbMax = 12;
const double kEqDbStep = 0.5;

class EqPreset {
  final String key;
  final String name;
  final List<num> gains; // 31Hz → 16kHz

  const EqPreset(this.key, this.name, this.gains);
}

const List<EqPreset> kEqPresets = [
  EqPreset('flat', '默认', [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]),
  EqPreset('pop', '流行', [-1, 2, 4, 4, 1, -1, -1, 1, 2, 3]),
  EqPreset('rock', '摇滚', [4, 3, 1, 0, -1, -1, 1, 3, 4, 4]),
  EqPreset('jazz', '爵士', [3, 2, 1, 2, -1, -1, 0, 1, 2, 3]),
  EqPreset('classical', '古典', [4, 3, 2, 0, 0, 0, -1, -1, -1, -2]),
  EqPreset('electronic', '电子', [5, 3, 0, 0, -2, 1, 0, 1, 4, 5]),
  EqPreset('vocal', '人声', [-2, -1, 0, 3, 5, 5, 3, 0, -1, -2]),
  EqPreset('bass', '低音增强', [5, 4, 3, 1, 0, 0, 0, 0, 0, 0]),
];

EqPreset eqPresetFor(String key) =>
    kEqPresets.firstWhere((p) => p.key == key, orElse: () => kEqPresets.first);

/// 设置状态（schema v4 字段，精确移植 src/stores/settings.js）
class SettingsStore extends ChangeNotifier {
  static const String _key = 'pink-music-settings';

  String audioQuality = 'auto'; // auto | lossless | high | medium | low
  double audioVisualizerIntensity = 0.6; // 0-1（专辑波纹激进度）
  bool eqEnabled = true;
  List<num> eqBands = List<num>.filled(10, 0);
  String eqPreset = 'flat';
  String lyricDisplayMode = 'original'; // original | romaji | translation
  String lyricSource = 'netease'; // qq | netease （歌词来源，默认网易云，与原项目一致）
  double lyricFontSize = 16; // 歌词字号（12–28）

  // UI 状态（不持久化）
  bool showSettings = false;
  int activeSettingsTab = 0;

  void setAudioQuality(String q) {
    audioQuality = q;
    _persist();
    notifyListeners();
  }

  void setAudioVisualizerIntensity(double v) {
    audioVisualizerIntensity = v.clamp(0.0, 1.0);
    _persist();
    notifyListeners();
  }

  void setLyricFontSize(double v) {
    lyricFontSize = v.clamp(12.0, 28.0);
    _persist();
    notifyListeners();
  }

  void adjustLyricFontSize(double delta) {
    setLyricFontSize((lyricFontSize + delta).roundToDouble());
  }

  void setEqEnabled(bool v) {
    eqEnabled = v;
    _persist();
    notifyListeners();
  }

  /// 提交 EQ 频段（clamp 到 ±12，步进 0.5）
  void commitEQBands(List<num> bands) {
    eqBands = bands
        .map((b) {
          final clamped = b.clamp(kEqDbMin, kEqDbMax);
          return (clamped / kEqDbStep).round() * kEqDbStep;
        })
        .toList();
    _persist();
    notifyListeners();
  }

  void setEqPreset(String key) {
    eqPreset = key;
    eqBands = List<num>.from(eqPresetFor(key).gains);
    _persist();
    notifyListeners();
  }

  void resetEq() {
    eqEnabled = true;
    eqPreset = 'flat';
    eqBands = List<num>.filled(10, 0);
    _persist();
    notifyListeners();
  }

  void setLyricDisplayMode(String mode) {
    lyricDisplayMode = mode;
    _persist();
    notifyListeners();
  }

  void setLyricSource(String source) {
    lyricSource = source == 'netease' ? 'netease' : 'qq';
    _persist();
    notifyListeners();
  }

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw != null && raw.isNotEmpty) {
      try {
        final map = Map<String, dynamic>.from(jsonDecode(raw));
        audioQuality = map['audioQuality'] ?? 'auto';
        audioVisualizerIntensity = (map['audioVisualizerIntensity'] as num?)
                ?.toDouble() ??
            0.6;
        eqEnabled = map['eqEnabled'] ?? true;
        final bands = map['eqBands'];
        if (bands is List && bands.length == 10) {
          eqBands = bands.cast<num>();
        }
        eqPreset = map['eqPreset'] ?? 'flat';
        lyricDisplayMode = map['lyricDisplayMode'] ?? 'original';
        lyricSource = map['lyricSource'] ?? 'netease';
        lyricFontSize = (map['lyricFontSize'] as num?)?.toDouble() ?? 16;
      } catch (_) {}
    }
    notifyListeners();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _key,
        jsonEncode({
          'audioQuality': audioQuality,
          'audioVisualizerIntensity': audioVisualizerIntensity,
          'eqEnabled': eqEnabled,
          'eqBands': eqBands,
          'eqPreset': eqPreset,
          'lyricDisplayMode': lyricDisplayMode,
          'lyricSource': lyricSource,
          'lyricFontSize': lyricFontSize,
        }));
  }
}
