/// 滴嗒音效数据模型
///
/// 每个音效对应 assets/sounds/ 下的一段长录音（连续走动的钟表声），
/// 播放时整段循环（[ReleaseMode.loop]），而非每秒触发短音。
class TickSound {
  final String id;
  final String name;
  /// AssetSource 相对路径（不带 assets/ 前缀）
  final String asset;

  const TickSound({
    required this.id,
    required this.name,
    required this.asset,
  });

  /// 默认音效：机械挂钟
  static const defaultSound = TickSound(
    id: 'mech_clock',
    name: '机械挂钟',
    asset: 'sounds/mech_clock.mp3',
  );

  /// 全部音效（顺序即展示顺序）
  static const all = [
    defaultSound,
    TickSound(id: 'quartz_clock', name: '石英钟', asset: 'sounds/quartz_clock.mp3'),
    TickSound(id: 'stopwatch_1', name: '秒表 1', asset: 'sounds/stopwatch_1.mp3'),
    TickSound(id: 'stopwatch_2', name: '秒表 2', asset: 'sounds/stopwatch_2.mp3'),
    TickSound(id: 'alarm_clock_1', name: '机械闹钟 1', asset: 'sounds/alarm_clock_1.mp3'),
    TickSound(id: 'alarm_clock_2', name: '机械闹钟 2', asset: 'sounds/alarm_clock_2.mp3'),
    TickSound(id: 'alarm_clock_3', name: '机械闹钟 3', asset: 'sounds/alarm_clock_3.mp3'),
    TickSound(id: 'alarm_clock_4', name: '机械闹钟 4', asset: 'sounds/alarm_clock_4.mp3'),
    TickSound(id: 'alarm_clock_5', name: '机械闹钟 5', asset: 'sounds/alarm_clock_5.mp3'),
    TickSound(id: 'timer', name: '计时器', asset: 'sounds/timer.mp3'),
  ];

  /// 通过 id 查找音效，找不到则返回默认
  static TickSound byId(String id) {
    for (final s in all) {
      if (s.id == id) return s;
    }
    return defaultSound;
  }
}