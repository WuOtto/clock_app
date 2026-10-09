import 'package:audioplayers/audioplayers.dart';

import '../models/tick_sound.dart';

/// 滴嗒声服务（循环长音频模式）
///
/// 音频资源是连续走动的钟表录音（6.7s ~ 66s），
/// 播放策略为整段 [ReleaseMode.loop] 循环：
/// - 进入数字时钟页 → [selectSound] 设置资源并开始播放
/// - 静音开关 → [setEnabled] pause/resume
/// - 切换音效   → [selectSound] 替换 source
/// - 离开页面   → [setEnabled](false) 暂停
class TickSoundService {
  TickSoundService._();
  static final TickSoundService instance = TickSoundService._();

  final AudioPlayer _player = AudioPlayer(playerId: 'tick_sound_player');
  bool _initialized = false;

  /// 初始化播放器（设置循环模式）
  Future<void> init() async {
    if (_initialized) return;
    try {
      await _player.setReleaseMode(ReleaseMode.loop);
      _initialized = true;
    } catch (_) {
      _initialized = false;
    }
  }

  /// 选择音效并开始/保持播放
  ///
  /// [play] 为 true 时立即播放（用于试听/开启状态切换），
  /// false 时仅预加载不播放（用于静音状态下换音效）。
  Future<void> selectSound(TickSound sound, {bool play = true}) async {
    if (!_initialized) return;
    try {
      await _player.setSource(AssetSource(sound.asset));
      if (play) {
        await _player.resume();
      }
    } catch (_) {
      // 资源加载失败静默忽略（保持无声，不打断 UI）
    }
  }

  /// 静音开关：暂停 / 恢复
  Future<void> setEnabled(bool enabled) async {
    if (!_initialized) return;
    try {
      if (enabled) {
        await _player.resume();
      } else {
        await _player.pause();
      }
    } catch (_) {}
  }

  Future<void> dispose() async {
    if (_initialized) {
      await _player.dispose();
    }
    _initialized = false;
  }
}