import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/clock_theme.dart';
import '../models/tick_sound.dart';
import '../services/tick_sound_service.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// 数字时钟页
///
/// 全屏展示当前时间，支持 5 套主题切换与每秒滴嗒声。
/// 通过 [Navigator.push] 进入，返回后不影响任何上游状态。
class ClockPage extends StatefulWidget {
  const ClockPage({super.key});

  @override
  State<ClockPage> createState() => _ClockPageState();
}

class _ClockPageState extends State<ClockPage> {
  static const String _kKeyTheme = 'clock_theme_id';
  static const String _kKeySoundEnabled = 'clock_sound_enabled';
  static const String _kKeySound = 'clock_sound_id';

  Timer? _timer;
  DateTime _now = DateTime.now();
  ClockTheme _theme = ClockTheme.deepsea;
  TickSound _selectedSound = TickSound.defaultSound;
  bool _soundEnabled = false; // 时钟页默认静音
  bool _showControls = true; // 顶栏按钮显隐状态
  bool _isLandscape = false; // 是否强制横屏

  // 电量信息（在沉浸式下也需要显示，所以单独管理）
  // 通过 MethodChannel 调用 Android 原生 BatteryManager，不引入第三方插件，
  // 避免 battery_plus 拉一堆 AGP/Gradle 依赖在离线/镜像仓库下失败。
  static const _batteryChannel = MethodChannel('countdown/battery');
  Timer? _batteryTimer;
  int _batteryLevel = -1; // -1 表示未知
  bool _isCharging = false;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
    _startClockLoop();
    _initBattery();
    // 进入时钟页即进入沉浸式全屏：隐藏状态栏与底部导航栏。
    // Android 上为 immersiveSticky：从边缘滑动时系统栏短暂浮现后自动隐藏，
    // 不会挤压布局；iOS 上同样隐藏状态栏。
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky, overlays: []);
    // 数字时钟页默认保持屏幕常亮，离开时由 [dispose] 关闭
    WakelockPlus.enable();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _batteryTimer?.cancel();
    // 离开数字时钟页时暂停滴嗒声，关闭屏幕常亮，恢复为竖屏，保持与主页一致
    TickSoundService.instance.setEnabled(false);
    WakelockPlus.disable();
    // 离开时钟页时恢复系统栏显示（edgeToEdge 为 Android 15+ / Flutter 默认形态）
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations(const [DeviceOrientation.portraitUp]);
    super.dispose();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _theme = ClockTheme.byId(prefs.getString(_kKeyTheme) ?? ClockTheme.deepsea.id);
      _soundEnabled = prefs.getBool(_kKeySoundEnabled) ?? false;
      _selectedSound = TickSound.byId(prefs.getString(_kKeySound) ?? TickSound.defaultSound.id);
    });
    // 初始化播放器并按持久化状态恢复播放
    await TickSoundService.instance.init();
    if (_soundEnabled) {
      await TickSoundService.instance.selectSound(_selectedSound, play: true);
    }
  }

  Future<void> _savePrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kKeyTheme, _theme.id);
    await prefs.setBool(_kKeySoundEnabled, _soundEnabled);
    await prefs.setString(_kKeySound, _selectedSound.id);
  }

  /// 初始化电量读取并订阅变化
  ///
  /// 仅 Android / iOS 走原生通道（两端注册了同名 MethodChannel）；
  /// 其他平台直接不启动轮询，电量指示器也不显示。
  Future<void> _initBattery() async {
    if (!_isBatteryPlatform) return;
    await _refreshBattery();
    _batteryTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _refreshBattery(),
    );
  }

  Future<void> _refreshBattery() async {
    if (!_isBatteryPlatform) return;
    try {
      final info =
          await _batteryChannel.invokeMethod<Map<dynamic, dynamic>>('getInfo');
      if (!mounted || info == null) return;
      setState(() {
        _batteryLevel = (info['level'] as num?)?.toInt() ?? -1;
        _isCharging = info['charging'] as bool? ?? false;
      });
    } catch (_) {
      // 通道未注册 / 系统调用异常：保持上一次状态或 -1，UI 显示「--」
    }
  }

  /// 是否启用原生电量通道：当前仅 Android 端有原生实现
  static bool get _isBatteryPlatform => Platform.isAndroid;

  /// 精确整秒对齐时钟循环，避免累积漂移
  ///
  /// 不使用 [Timer.periodic] 固定 1000ms 周期，而是每次回调完成后
  /// 重新计算到下一个整秒的延迟并重新调度。这样即使 [setState] / 渲染
  /// 偶尔多耗几毫秒，下一次仍会精确对齐整秒，长期累积也不会变慢。
  void _startClockLoop() {
    _scheduleNextTick();
  }

  void _scheduleNextTick() {
    final now = DateTime.now();
    // 微秒也参与计算，避免仅对齐到毫秒导致的 0~999ms 抖动
    final msToNextSecond =
        1000 - now.millisecond - now.microsecond ~/ 1000;
    _timer = Timer(Duration(milliseconds: msToNextSecond), () {
      if (!mounted) return;
      _tick();
      _scheduleNextTick();
    });
  }

  void _tick() {
    if (!mounted) return;
    setState(() => _now = DateTime.now());
    // 滴嗒声由 TickSoundService 循环播放，无需每秒触发
  }

  void _toggleSound() {
    setState(() => _soundEnabled = !_soundEnabled);
    _savePrefs();
    TickSoundService.instance.setEnabled(_soundEnabled);
  }

  /// 切换顶栏按钮的显示/隐藏
  void _toggleControls() {
    setState(() => _showControls = !_showControls);
  }

  /// 切换横竖屏方向
  ///
  /// 通过 [SystemChrome.setPreferredOrientations] 强制应用方向，
  /// 不依赖系统是否开启了「自动旋转」，仅与原生层（iOS Info.plist /
  /// Android AndroidManifest）的方向白名单有关。
  Future<void> _toggleOrientation() async {
    if (_isLandscape) {
      await SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]);
    } else {
      await SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    }
    if (mounted) {
      setState(() => _isLandscape = !_isLandscape);
    }
  }

  Future<void> _showThemePicker() async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true, // 允许弹窗突破默认最大高度
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            // 键盘弹出时把弹窗顶上去，避免被遮挡
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom,
            ),
            child: Container(
              margin: const EdgeInsets.all(12),
              constraints: BoxConstraints(
                // 横屏时限制最大高度为屏幕 75%，避免超出可视范围
                maxHeight: MediaQuery.of(ctx).size.height * 0.75,
              ),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.88),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 顶部拖动指示条 + 标题
                  Padding(
                    padding: const EdgeInsets.only(top: 10, bottom: 4),
                    child: Column(
                      children: [
                        Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.25),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 14),
                          child: Text(
                            '选择主题',
                            style: TextStyle(color: Colors.white, fontSize: 16, letterSpacing: 2),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // 列表区域：内容超长时支持滚动
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: ClockTheme.all.map((t) {
                          final isSelected = t.id == _theme.id;
                          return _buildThemeTile(ctx, t, isSelected);
                        }).toList(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),
        );
      },
    );

    if (selected != null && mounted) {
      setState(() => _theme = ClockTheme.byId(selected));
      _savePrefs();
    }
  }

  Widget _buildThemeTile(BuildContext ctx, ClockTheme t, bool isSelected) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Material(
        color: isSelected
            ? Colors.white.withValues(alpha: 0.12)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: () => Navigator.pop(ctx, t.id),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(colors: t.backgroundGradient),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.3),
                      width: 1,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    t.name,
                    style: const TextStyle(color: Colors.white, fontSize: 15),
                  ),
                ),
                if (isSelected)
                  const Icon(Icons.check_circle, color: Colors.white, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showSoundPicker() async {
    // 弹窗内的静音状态快照（StatefulBuilder 局部管理，
    // 因为父页面 setState 不会触发 BottomSheet 重建）
    bool isMuted = !_soundEnabled;

    Future<void> enableSound(StateSetter setSheetState) async {
      setSheetState(() => isMuted = false);
      if (!_soundEnabled) {
        setState(() => _soundEnabled = true);
        _savePrefs();
        // 播放当前选中的音效
        await TickSoundService.instance.selectSound(_selectedSound, play: true);
      }
    }

    final selected = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.of(ctx).viewInsets.bottom,
                ),
                child: Container(
                  margin: const EdgeInsets.all(12),
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(ctx).size.height * 0.75,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.88),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 顶部拖动指示条 + 标题
                      Padding(
                        padding: const EdgeInsets.only(top: 10, bottom: 4),
                        child: Column(
                          children: [
                            Container(
                              width: 40,
                              height: 4,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.25),
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 14),
                              child: Text(
                                '选择滴嗒音效',
                                style: TextStyle(color: Colors.white, fontSize: 16, letterSpacing: 2),
                              ),
                            ),
                          ],
                        ),
                      ),
                      // 静音提示条：仅在静音状态下显示，提供一键开启声音
                      if (isMuted)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.volume_off, color: Colors.white54, size: 18),
                                const SizedBox(width: 8),
                                const Expanded(
                                  child: Text(
                                    '当前已静音，选择音效后不会播放',
                                    style: TextStyle(color: Colors.white54, fontSize: 12),
                                  ),
                                ),
                                TextButton(
                                  onPressed: () => enableSound(setSheetState),
                                  style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 12),
                                    visualDensity: VisualDensity.compact,
                                  ),
                                  child: const Text(
                                    '开启声音',
                                    style: TextStyle(color: Colors.lightBlueAccent, fontSize: 13),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      // 列表区域：内容超长时支持滚动
                      Flexible(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: TickSound.all.map((s) {
                              final isSelected = s.id == _selectedSound.id;
                              return _buildSoundTile(ctx, s, isSelected);
                            }).toList(),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    if (selected != null && mounted) {
      final sound = TickSound.byId(selected);
      setState(() => _selectedSound = sound);
      _savePrefs();
      // 静音状态下仅切换资源不播放，无任何试听
      await TickSoundService.instance.selectSound(sound, play: _soundEnabled);
    }
  }

  Widget _buildSoundTile(BuildContext ctx, TickSound s, bool isSelected) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Material(
        color: isSelected
            ? Colors.white.withValues(alpha: 0.12)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: () => Navigator.pop(ctx, s.id),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.1),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.3),
                      width: 1,
                    ),
                  ),
                  child: Icon(
                    Icons.graphic_eq,
                    color: isSelected ? Colors.white : Colors.white54,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    s.name,
                    style: const TextStyle(color: Colors.white, fontSize: 15),
                  ),
                ),
                if (isSelected)
                  const Icon(Icons.check_circle, color: Colors.white, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _format(int n) => n.toString().padLeft(2, '0');

  String _weekdayText() {
    const weekdays = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
    return weekdays[_now.weekday - 1];
  }

  String _dateText() => '${_now.year} 年 ${_now.month} 月 ${_now.day} 日';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GestureDetector(
        onTap: _toggleControls,
        behavior: HitTestBehavior.translucent,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 400),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: _theme.backgroundGradient,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: SafeArea(
            child: Column(
              children: [
                _buildTopBar(),
                Expanded(child: _buildClockDisplay()),
                // 电量固定在右下角，不随顶栏按钮显隐，沉浸式下也可随时看到
                Align(
                  alignment: Alignment.centerRight,
                  child: _buildBatteryIndicator(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    final iconColor = _theme.digitColor.withValues(alpha: 0.75);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Row(
        children: [
          // 顶栏功能按钮：点击空白处会整体淡出
          Expanded(
            child: AnimatedOpacity(
              opacity: _showControls ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 250),
              child: IgnorePointer(
                ignoring: !_showControls,
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      tooltip: '返回',
                      icon: Icon(Icons.arrow_back_ios_new, color: iconColor, size: 20),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: _toggleOrientation,
                      tooltip: _isLandscape ? '切换为竖屏' : '切换为横屏',
                      icon: Icon(
                        _isLandscape
                            ? Icons.stay_current_portrait
                            : Icons.stay_current_landscape,
                        color: iconColor,
                      ),
                    ),
                    IconButton(
                      onPressed: _showSoundPicker,
                      tooltip: '选择音效（$_selectedSound.name）',
                      icon: Icon(Icons.graphic_eq, color: iconColor),
                    ),
                    IconButton(
                      onPressed: _toggleSound,
                      tooltip: _soundEnabled ? '关闭滴答声' : '开启滴答声',
                      icon: Icon(
                        _soundEnabled ? Icons.volume_up : Icons.volume_off,
                        color: iconColor,
                      ),
                    ),
                    IconButton(
                      onPressed: _showThemePicker,
                      tooltip: '切换主题',
                      icon: Icon(Icons.palette_outlined, color: iconColor),
                    ),
                    const SizedBox(width: 4),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 电量指示器
  ///
  /// 沉浸式全屏时系统状态栏被隐藏，这里用一个小胶囊替代显示当前电量。
  /// 用 [IgnorePointer] 包裹，点击该区域仍会触发 body 上的 _toggleControls，
  /// 行为与点击空白处一致。
  ///
  /// 仅在 Android 上显示，其他平台（iOS / macOS / Windows / Web / Linux）不渲染。
  Widget _buildBatteryIndicator() {
    if (!_isBatteryPlatform) return const SizedBox.shrink();
    final color = _theme.digitColor.withValues(alpha: 0.7);
    final hasLevel = _batteryLevel >= 0;
    return IgnorePointer(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _isCharging ? Icons.bolt : Icons.battery_full,
              size: 16,
              color: color,
            ),
            const SizedBox(width: 2),
            Text(
              hasLevel ? '$_batteryLevel%' : '--',
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontFeatures: const [FontFeature.tabularFigures()],
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildClockDisplay() {
    final hour = _format(_now.hour);
    final minute = _format(_now.minute);
    final second = _format(_now.second);

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // 时分秒大字
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _buildAnimatedDigit(hour, color: _theme.digitColor, animateFade: true),
                  _buildSeparator(),
                  _buildAnimatedDigit(minute, color: _theme.digitColor, animateFade: true),
                  _buildSeparator(),
                  _buildAnimatedDigit(second, color: _theme.secondColor, animateFade: false),
                ],
              ),
            ),
            const SizedBox(height: 32),
            // 日期 + 星期
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: Text(
                '${_dateText()} · ${_weekdayText()}',
                key: ValueKey('${_now.day}-${_theme.id}'),
                style: TextStyle(
                  color: _theme.subtitleColor,
                  fontSize: 16,
                  fontWeight: FontWeight.w400,
                  letterSpacing: 3,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSeparator() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Text(
        ':',
        style: TextStyle(
          color: _theme.separatorColor.withValues(alpha: 0.7),
          fontSize: 110,
          fontWeight: _theme.digitWeight,
          height: 1,
        ),
      ),
    );
  }

  Widget _buildAnimatedDigit(String value, {required Color color, required bool animateFade}) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      transitionBuilder: (child, anim) {
        if (animateFade) {
          return FadeTransition(opacity: anim, child: child);
        }
        return FadeTransition(
          opacity: anim,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.2),
              end: Offset.zero,
            ).animate(anim),
            child: child,
          ),
        );
      },
      child: Text(
        value,
        key: ValueKey(value),
        style: TextStyle(
          color: color,
          fontSize: 140,
          fontWeight: _theme.digitWeight,
          fontFeatures: const [FontFeature.tabularFigures()],
          height: 1,
          letterSpacing: 4,
        ),
      ),
    );
  }

  }