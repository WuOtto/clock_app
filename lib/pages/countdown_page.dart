import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'dart:async';
import 'dart:io';

import 'settings_page.dart';
import 'clock_page.dart';
import '../status_bar_manager.dart';

class CountdownPage extends StatefulWidget {
  const CountdownPage({super.key});

  @override
  State<CountdownPage> createState() => _CountdownPageState();
}

class _CountdownPageState extends State<CountdownPage> with WidgetsBindingObserver {
  // 预设配置
  static const List<Map<String, dynamic>> _presets = [
    {'label': '番茄时钟', 'minutes': 25, 'icon': Icons.timer, 'color': Colors.red},
    {'label': '短休息', 'minutes': 5, 'icon': Icons.coffee, 'color': Colors.green},
    {'label': '长休息', 'minutes': 15, 'icon': Icons.hotel, 'color': Colors.blue},
  ];

  // 状态
  int _totalSeconds = 0;
  int _remainingSeconds = 0;
  int _intervalSeconds = 0; // 保存的时间间隔
  Timer? _timer;
  Timer? _clockTimer;
  bool _isRunning = false;
  bool _isPaused = false; // 是否暂停状态
  String? _timerLabel; // 倒计时标签
  Color _timerColor = Colors.deepPurple; // 进度条颜色
  DateTime? _targetTime; // 目标时间
  DateTime? _targetWallClock; // 时间选择器的绝对目标时间（壁钟时间）

  // 通知
  final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();
  
  // 状态栏
  final StatusBarManager _statusBar = StatusBarManager();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startClock();
    _initNotifications();
    _statusBar.init();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _clockTimer?.cancel();
    _statusBar.dispose();
    super.dispose();
  }
  
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // 当应用从后台恢复时，重新计算剩余时间
    if (state == AppLifecycleState.resumed && _isRunning && _targetTime != null) {
      _syncRemainingTime();
    }
  }

  // 初始化通知
  Future<void> _initNotifications() async {
    const settings = InitializationSettings(
      iOS: DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      ),
      macOS: DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      ),
      linux: LinuxInitializationSettings(defaultActionName: '打开'),
    );
    await _notifications.initialize(settings);
  }

  // 发送通知
  Future<void> _showNotification(String title, String body) async {
    // PC 端（macOS/Linux/Windows）使用通知
    if (Platform.isMacOS || Platform.isLinux || Platform.isWindows) {
      const details = NotificationDetails(
        macOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
        linux: LinuxNotificationDetails(),
      );
      await _notifications.show(0, title, body, details);
    }
    // 移动端也发送通知
    if (Platform.isIOS) {
      const details = NotificationDetails(
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      );
      await _notifications.show(0, title, body, details);
    }
    if (Platform.isAndroid) {
      const details = NotificationDetails(
        android: AndroidNotificationDetails('countdown', '倒计时', importance: Importance.high),
      );
      await _notifications.show(0, title, body, details);
    }
  }

  // 精确时钟：对齐到整秒
  void _startClock() {
    final now = DateTime.now();
    final delay = Duration(milliseconds: 1000 - now.millisecond);
    _clockTimer = Timer(delay, () {
      setState(() {});
      // 后续每秒刷新
      _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        setState(() {});
      });
    });
  }

  // 选择预设
  void _selectPreset(int index) {
    final preset = _presets[index];
    if (_isRunning) _stopTimer();
    setState(() {
      _intervalSeconds = preset['minutes'] * 60;
      _totalSeconds = _intervalSeconds;
      _remainingSeconds = _intervalSeconds;
      _timerLabel = preset['label'];
      _timerColor = preset['color'];
      _isPaused = false;
      _targetTime = null;
      _targetWallClock = null;
    });
  }

  // 打开设置页面
  Future<void> _openSettings() async {
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(builder: (_) => const SettingsPage()),
    );

    if (result == null) return;

    // 如果正在运行，先停止
    if (_isRunning) _stopTimer();

    setState(() {
      final now = DateTime.now();
      final targetTimeStr = result['targetTime'] as String?;
      if (targetTimeStr != null) {
        // 时间选择器：基于绝对目标时间计算剩余秒数
        _targetWallClock = DateTime.parse(targetTimeStr);
        _intervalSeconds = _targetWallClock!.difference(now).inSeconds;
        if (_intervalSeconds < 0) _intervalSeconds = 0;
      } else {
        // 滑块：固定时长
        _targetWallClock = null;
        _intervalSeconds = result['seconds'] as int;
      }
      _totalSeconds = _intervalSeconds;
      _remainingSeconds = _totalSeconds;
      _timerLabel = result['label'] as String?;
      _timerColor = result['color'] as Color? ?? Colors.deepPurple;
      _isPaused = false;
      _targetTime = null;
    });
  }

  // 开始/暂停
  void _toggleTimer() {
    if (_totalSeconds == 0) return;
    if (_isRunning) {
      _stopTimer();
    } else {
      _startTimer();
    }
  }

  void _startTimer() {
    // 如果是首次开始（非暂停恢复），重新计算目标时间
    if (!_isPaused) {
      final now = DateTime.now();
      if (_targetWallClock != null) {
        // 时间选择器：基于绝对目标时间重新计算剩余秒数
        _remainingSeconds = _targetWallClock!.difference(now).inSeconds;
        if (_remainingSeconds <= 0) {
          _remainingSeconds = 0;
          setState(() => _isRunning = false);
          _onTimerComplete();
          return;
        }
        _intervalSeconds = _remainingSeconds;
        _totalSeconds = _remainingSeconds;
        _targetTime = _targetWallClock;
      } else {
        // 滑块：基于当前时间 + 固定时长
        _targetTime = now.add(Duration(seconds: _intervalSeconds));
        _totalSeconds = _intervalSeconds;
        _remainingSeconds = _intervalSeconds;
      }
    }
    _isPaused = false;
    setState(() => _isRunning = true);
    // 立即更新状态栏
    _updateStatusBar();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_targetTime == null) return;
      
      final now = DateTime.now();
      final remaining = _targetTime!.difference(now).inSeconds;
      
      setState(() {
        if (remaining > 0) {
          _remainingSeconds = remaining;
          _updateStatusBar();
        } else {
          _remainingSeconds = 0;
          _stopTimer();
          _onTimerComplete();
        }
      });
    });
  }

  void _stopTimer() {
    _timer?.cancel();
    setState(() {
      _isRunning = false;
      _isPaused = true; // 标记为暂停状态
    });
    _statusBar.clear();
  }
  
  // 更新状态栏显示
  void _updateStatusBar() {
    final timeText = _formatTime(_remainingSeconds);
    // 当剩余时间少于1分钟时，使用强提示
    final isUrgent = _remainingSeconds <= 60 && _remainingSeconds > 0;
    _statusBar.updateCountdown(timeText, label: _timerLabel, isUrgent: isUrgent);
  }
  
  // 同步剩余时间（用于应用从后台恢复）
  void _syncRemainingTime() {
    if (_targetTime == null) return;
    
    final now = DateTime.now();
    final remaining = _targetTime!.difference(now).inSeconds;
    
    setState(() {
      if (remaining > 0) {
        _remainingSeconds = remaining;
        _updateStatusBar();
      } else {
        _remainingSeconds = 0;
        _stopTimer();
        _onTimerComplete();
      }
    });
  }

  // 重置
  void _resetTimer() {
    _stopTimer();
    setState(() {
      _remainingSeconds = _intervalSeconds;
      _totalSeconds = _intervalSeconds;
      _isPaused = false;
      _targetTime = null;
      _targetWallClock = null;
    });
  }

  // 停止并清空
  void _clearTimer() {
    _stopTimer();
    setState(() {
      _totalSeconds = 0;
      _remainingSeconds = 0;
      _intervalSeconds = 0;
      _timerLabel = null;
      _timerColor = Colors.deepPurple;
      _isPaused = false;
      _targetTime = null;
      _targetWallClock = null;
    });
  }

  // 倒计时完成
  void _onTimerComplete() {
    // 发送系统通知
    final title = '倒计时结束';
    final body = _timerLabel != null ? '$_timerLabel 结束了' : '倒计时结束';
    _showNotification(title, body);

    // 显示弹窗
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('时间到！'),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  // 格式化时间
  String _formatTime(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  // 进度
  double get _progress =>
      _totalSeconds > 0 ? _remainingSeconds / _totalSeconds : 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            // 小屏适配：iPhone SE 1 (320x568) 等高度 < 600 的设备启用紧凑布局，
            // 通过缩小圆环、间距与按钮尺寸避免底部按钮被遮挡。
            final isCompact = constraints.maxHeight < 600;
            return SingleChildScrollView(
              physics: const ClampingScrollPhysics(),
              child: ConstrainedBox(
                // 内容能在小屏上保持居中；超出时退化为可滚动布局。
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // 顶部栏：当前时间 + 设置按钮
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _buildCurrentTime(),
                          IconButton(
                            onPressed: _isRunning ? null : _openSettings,
                            icon: const Icon(Icons.settings),
                            tooltip: '自定义设置',
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: isCompact ? 12 : 24),
                    // 预设按钮
                    _buildPresets(isCompact: isCompact),
                    SizedBox(height: isCompact ? 12 : 24),
                    // 标签
                    if (_timerLabel != null)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: _timerColor.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          _timerLabel!,
                          style: TextStyle(
                            color: _timerColor,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    SizedBox(height: isCompact ? 12 : 24),
                    // 倒计时圆环
                    _buildTimerDisplay(isCompact: isCompact),
                    SizedBox(height: isCompact ? 16 : 28),
                    // 控制按钮
                    _buildControls(isCompact: isCompact),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  // 当前时间（点击进入数字时钟页）
  Widget _buildCurrentTime() {
    final now = DateTime.now();
    final hour = now.hour.toString().padLeft(2, '0');
    final minute = now.minute.toString().padLeft(2, '0');
    final second = now.second.toString().padLeft(2, '0');
    return GestureDetector(
      onTap: _openClockPage,
      behavior: HitTestBehavior.opaque,
      child: Text(
        '$hour:$minute:$second',
        style: TextStyle(
          fontSize: 32,
          fontWeight: FontWeight.w300,
          color: Colors.grey[400],
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }

  // 打开数字时钟页
  Future<void> _openClockPage() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ClockPage()),
    );
  }

  // 预设按钮
  Widget _buildPresets({bool isCompact = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: List.generate(_presets.length, (index) {
          final preset = _presets[index];
          final isSelected = _timerLabel == preset['label'] && !_isRunning;
          return Expanded(
            child: Padding(
              padding: EdgeInsets.only(
                left: index == 0 ? 0 : 8,
                right: index == _presets.length - 1 ? 0 : 8,
              ),
              child: Material(
                color: isSelected
                    ? preset['color'].withValues(alpha: 0.2)
                    : Colors.white10,
                borderRadius: BorderRadius.circular(16),
                child: InkWell(
                  onTap: _isRunning ? null : () => _selectPreset(index),
                  borderRadius: BorderRadius.circular(16),
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: isCompact ? 10 : 16),
                    child: Column(
                      children: [
                        Icon(
                          preset['icon'],
                          color: preset['color'],
                          size: isCompact ? 24 : 28,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          preset['label'],
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: isSelected ? preset['color'] : null,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${preset['minutes']}分钟',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[400],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  // 倒计时显示
  Widget _buildTimerDisplay({bool isCompact = false}) {
    final size = isCompact ? 200.0 : 240.0;
    final stroke = isCompact ? 12.0 : 14.0;
    final textSize = isCompact ? 50.0 : 60.0;
    return Stack(
      alignment: Alignment.center,
      children: [
        SizedBox(
          width: size,
          height: size,
          child: CircularProgressIndicator(
            value: _progress,
            strokeWidth: stroke,
            backgroundColor: Colors.white12,
            color: _timerColor,
            strokeCap: StrokeCap.round,
          ),
        ),
        Column(
          children: [
            Text(
              _formatTime(_remainingSeconds),
              style: TextStyle(
                fontSize: textSize,
                fontWeight: FontWeight.bold,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            if (_targetTime != null && _isRunning)
              Text(
                '目标: ${_targetTime!.hour.toString().padLeft(2, '0')}:${_targetTime!.minute.toString().padLeft(2, '0')}:${_targetTime!.second.toString().padLeft(2, '0')}',
                style: TextStyle(
                  fontSize: 14,
                  color: _timerColor,
                  fontWeight: FontWeight.w500,
                ),
              ),
            if (_totalSeconds > 0 && _targetTime == null)
              Text(
                _isRunning ? '进行中' : (_isPaused ? '已暂停' : '就绪'),
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[500],
                ),
              ),
            if (_totalSeconds == 0)
              Text(
                '请设置倒计时',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[500],
                ),
              ),
          ],
        ),
      ],
    );
  }

  // 控制按钮
  Widget _buildControls({bool isCompact = false}) {
    final bigSize = isCompact ? 64.0 : 80.0;
    final bigIcon = isCompact ? 32.0 : 40.0;
    final smallIcon = isCompact ? 24.0 : 28.0;
    final smallPadding = isCompact ? 12.0 : 16.0;
    final gap = isCompact ? 16.0 : 24.0;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton.filledTonal(
          onPressed: _totalSeconds > 0 ? _resetTimer : null,
          icon: const Icon(Icons.replay),
          iconSize: smallIcon,
          style: IconButton.styleFrom(padding: EdgeInsets.all(smallPadding)),
        ),
        SizedBox(width: gap),
        SizedBox(
          width: bigSize,
          height: bigSize,
          child: IconButton.filled(
            onPressed: _toggleTimer,
            icon: Icon(_isRunning ? Icons.pause : Icons.play_arrow),
            iconSize: bigIcon,
            style: IconButton.styleFrom(shape: const CircleBorder()),
          ),
        ),
        SizedBox(width: gap),
        IconButton.filledTonal(
          onPressed: _totalSeconds > 0 ? _clearTimer : null,
          icon: const Icon(Icons.stop),
          iconSize: smallIcon,
          style: IconButton.styleFrom(padding: EdgeInsets.all(smallPadding)),
        ),
      ],
    );
  }
}