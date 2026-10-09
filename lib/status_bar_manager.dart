import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:system_tray/system_tray.dart';

class StatusBarManager {
  static final StatusBarManager _instance = StatusBarManager._();
  factory StatusBarManager() => _instance;
  StatusBarManager._();

  final SystemTray _tray = SystemTray();
  bool _initialized = false;
  Timer? _blinkTimer;
  bool _isBlinking = false;
  String _currentTitle = '';
  
  // 平台通道用于激活窗口
  static const _channel = MethodChannel('countdown/status_bar');

  // 初始化状态栏
  Future<void> init() async {
    if (!Platform.isMacOS || _initialized) return;

    await _tray.initSystemTray(
      title: '',
      iconPath: 'assets/clock_app_icon.png',
    );

    // 注册左键点击事件 - 激活窗口
    _tray.registerSystemTrayEventHandler((String eventType) {
      if (eventType == 'click') {
        _activateApp();
      } else if (eventType == 'right-click') {
        _tray.popUpContextMenu();
      }
    });

    // 设置右键菜单
    final menu = Menu();
    await menu.buildFrom([
      MenuItemLabel(
        label: '显示主窗口',
        onClicked: (_) => _activateApp(),
      ),
      MenuItemLabel(
        label: '退出',
        onClicked: (_) {
          exit(0);
        },
      ),
    ]);
    await _tray.setContextMenu(menu);

    _initialized = true;
  }

  // 激活应用窗口（带到前台）
  Future<void> _activateApp() async {
    try {
      await _channel.invokeMethod('activateApp');
    } catch (_) {
      // 忽略错误
    }
  }

  // 更新状态栏显示的倒计时文本
  Future<void> updateCountdown(String timeText, {String? label, bool isUrgent = false}) async {
    if (!Platform.isMacOS || !_initialized) return;

    final displayText = label != null ? '$label $timeText' : timeText;
    _currentTitle = displayText;
    
    if (isUrgent) {
      // 开始闪烁效果
      _startBlinking();
    } else {
      // 停止闪烁
      _stopBlinking();
      await _tray.setTitle(displayText);
    }
  }
  
  // 开始闪烁效果
  void _startBlinking() {
    if (_isBlinking) return;
    
    _isBlinking = true;
    bool visible = true;
    
    _blinkTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) async {
      if (!_isBlinking) {
        timer.cancel();
        return;
      }
      
      if (visible) {
        await _tray.setTitle('⚠️ $_currentTitle');
      } else {
        await _tray.setTitle('');
      }
      visible = !visible;
    });
  }
  
  // 停止闪烁效果
  void _stopBlinking() {
    _isBlinking = false;
    _blinkTimer?.cancel();
    _blinkTimer = null;
  }

  // 清除状态栏显示
  Future<void> clear() async {
    if (!Platform.isMacOS || !_initialized) return;

    _stopBlinking();
    await _tray.setTitle('');
  }

  // 销毁
  Future<void> dispose() async {
    if (!Platform.isMacOS || !_initialized) return;

    _stopBlinking();
    await _tray.destroy();
    _initialized = false;
  }
}
