import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  double _sliderValue = 25;
  late DateTime _now;
  late DateTime _selectedTime;
  late DateTime _maxTime;
  Timer? _clockTimer;

  @override
  void initState() {
    super.initState();
    _now = DateTime.now();
    _selectedTime = _now.add(const Duration(minutes: 1));
    _maxTime = _now.add(const Duration(minutes: 120));
    _startClock();
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    super.dispose();
  }

  void _startClock() {
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() {
        _now = DateTime.now();
        // 确保选中时间不早于当前时间
        if (_selectedTime.isBefore(_now)) {
          _selectedTime = _now.add(const Duration(minutes: 1));
          _maxTime = _now.add(const Duration(minutes: 120));
        }
      });
    });
  }

  // 滑块设置
  void _setSliderTime() {
    Navigator.pop(context, {
      'seconds': (_sliderValue * 60).toInt(),
      'label': '自定义 ${_sliderValue.toInt()} 分钟',
      'color': Colors.deepPurple,
    });
  }

  // 时间选择器设置
  void _setTimePickerTime() {
    final diffSeconds = _selectedTime.difference(_now).inSeconds;
    if (diffSeconds <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请选择未来的时间')),
      );
      return;
    }
    final hour = _selectedTime.hour.toString().padLeft(2, '0');
    final minute = _selectedTime.minute.toString().padLeft(2, '0');
    final second = _selectedTime.second.toString().padLeft(2, '0');
    Navigator.pop(context, {
      'seconds': diffSeconds,
      'label': '至 $hour:$minute:$second',
      'color': Colors.deepPurple,
      'targetTime': _selectedTime.toIso8601String(),
    });
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('设置倒计时'),
          centerTitle: true,
          bottom: const TabBar(
            tabs: [
              Tab(text: '滑块选择', icon: Icon(Icons.tune)),
              Tab(text: '时间选择', icon: Icon(Icons.timer_outlined)),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildSliderTab(),
            _buildTimerPickerTab(),
          ],
        ),
      ),
    );
  }

  // 滑块选择 Tab
  Widget _buildSliderTab() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text(
            '滑动选择时间',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 24),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Text(
                    '${_sliderValue.toInt()} 分钟',
                    style: const TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Slider(
                    value: _sliderValue,
                    min: 1,
                    max: 120,
                    divisions: 119,
                    label: '${_sliderValue.toInt()} 分钟',
                    onChanged: (value) {
                      setState(() => _sliderValue = value);
                    },
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _setSliderTime,
                      child: const Text('确认设置'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 时间选择器 Tab
  Widget _buildTimerPickerTab() {
    final diffSeconds = _selectedTime.difference(_now).inSeconds;
    final diffMin = diffSeconds ~/ 60;
    final diffSec = diffSeconds % 60;
    final diffText = diffMin > 0
        ? '$diffMin 分 $diffSec 秒'
        : '$diffSec 秒';
    return Column(
      children: [
        const SizedBox(height: 16),
        Text(
          '选择目标时间（当前时间后120分钟内）',
          style: const TextStyle(color: Colors.grey),
        ),
        const SizedBox(height: 8),
        Text(
          '当前时间：${_now.hour.toString().padLeft(2, '0')}:${_now.minute.toString().padLeft(2, '0')}:${_now.second.toString().padLeft(2, '0')}',
          style: const TextStyle(fontSize: 14, color: Colors.grey),
        ),
        const SizedBox(height: 8),
        // CupertinoDatePicker
        SizedBox(
          height: 200,
          child: CupertinoDatePicker(
            mode: CupertinoDatePickerMode.time,
            initialDateTime: _selectedTime,
            minuteInterval: 1,
            use24hFormat: true,
            minimumDate: _now,
            maximumDate: _maxTime,
            onDateTimeChanged: (DateTime dateTime) {
              setState(() => _selectedTime = dateTime);
            },
          ),
        ),
        const SizedBox(height: 16),
        // 显示选中时间和倒计时时长
        Text(
          '${_selectedTime.hour.toString().padLeft(2, '0')}:${_selectedTime.minute.toString().padLeft(2, '0')}:${_selectedTime.second.toString().padLeft(2, '0')}',
          style: const TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '倒计时 $diffText',
          style: TextStyle(
            fontSize: 16,
            color: Colors.grey[400],
          ),
        ),
        const SizedBox(height: 24),
        // 确认按钮
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _setTimePickerTime,
              child: const Text('确认设置'),
            ),
          ),
        ),
      ],
    );
  }
}