import 'package:flutter/services.dart';

/// 10 段均衡器控制器（Android DynamicsProcessing，平台通道）
class EqController {
  static const MethodChannel _channel =
      MethodChannel('com.pinkmusic.app/equalizer');

  bool _attached = false;
  bool _supported = true;

  bool get supported => _supported;
  bool get attached => _attached;

  /// 监听 just_audio 的音频会话 ID 并挂载均衡器
  Future<void> attach(int audioSessionId) async {
    if (!_supported || _attached) return;
    try {
      await _channel.invokeMethod('attach', {
        'sessionId': audioSessionId,
      });
      _attached = true;
    } catch (e) {
      _supported = false;
      _attached = false;
    }
  }

  Future<void> setEnabled(bool enabled) async {
    if (!_attached) return;
    try {
      await _channel.invokeMethod('setEnabled', {
        'enabled': enabled,
      });
    } catch (_) {}
  }

  /// gains: 10 个 dB 增益（31Hz→16kHz），对应原 setTargetState
  Future<void> setBands(List<num> gains) async {
    if (!_attached) return;
    try {
      await _channel.invokeMethod('setBands', {
        'gains': gains.map((g) => g.toDouble()).toList(),
      });
    } catch (_) {}
  }

  Future<void> release() async {
    if (!_attached) return;
    try {
      await _channel.invokeMethod('release');
    } catch (_) {}
    _attached = false;
  }
}
