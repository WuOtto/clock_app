import 'package:flutter/material.dart';

/// 时钟主题数据模型
/// 定义数字时钟页的视觉样式
class ClockTheme {
  final String id;
  final String name;
  final List<Color> backgroundGradient;
  final Color digitColor;
  final Color secondColor;
  final Color separatorColor;
  final Color subtitleColor;
  final FontWeight digitWeight;
  final bool isDark;

  const ClockTheme({
    required this.id,
    required this.name,
    required this.backgroundGradient,
    required this.digitColor,
    required this.secondColor,
    required this.separatorColor,
    required this.subtitleColor,
    required this.digitWeight,
    required this.isDark,
  });

  /// 默认主题：深海（深蓝渐变 + 浅蓝数字）
  static const deepsea = ClockTheme(
    id: 'deepsea',
    name: '深海',
    backgroundGradient: [Color(0xFF001428), Color(0xFF003366), Color(0xFF001f3f)],
    digitColor: Color(0xFFFFFFFF),
    secondColor: Color(0xFF7FDBFF),
    separatorColor: Color(0xFF7FDBFF),
    subtitleColor: Color(0xCC7FDBFF),
    digitWeight: FontWeight.w200,
    isDark: true,
  );

  /// 极简黑（纯黑底 + 纯白数字）
  static const minimal = ClockTheme(
    id: 'minimal',
    name: '极简黑',
    backgroundGradient: [Color(0xFF000000), Color(0xFF0A0A0A)],
    digitColor: Color(0xFFFFFFFF),
    secondColor: Color(0xFFE0E0E0),
    separatorColor: Color(0xFF666666),
    subtitleColor: Color(0x99CCCCCC),
    digitWeight: FontWeight.w300,
    isDark: true,
  );

  /// 极光（紫绿渐变 + 青色数字）
  static const aurora = ClockTheme(
    id: 'aurora',
    name: '极光',
    backgroundGradient: [Color(0xFF1A0033), Color(0xFF003322), Color(0xFF220055)],
    digitColor: Color(0xFFE0FFE5),
    secondColor: Color(0xFF00FFC8),
    separatorColor: Color(0xFF00FFC8),
    subtitleColor: Color(0xAA00FFC8),
    digitWeight: FontWeight.w300,
    isDark: true,
  );

  /// 霓虹城市（深紫底 + 粉/青霓虹）
  static const neon = ClockTheme(
    id: 'neon',
    name: '霓虹城市',
    backgroundGradient: [Color(0xFF0a0a16), Color(0xFF1A0A2E), Color(0xFF0a0a16)],
    digitColor: Color(0xFFFFFFFF),
    secondColor: Color(0xFFFF00E5),
    separatorColor: Color(0xFF00F0FF),
    subtitleColor: Color(0xCC00F0FF),
    digitWeight: FontWeight.w700,
    isDark: true,
  );

  /// 水墨（米黄纸 + 墨色数字）
  static const ink = ClockTheme(
    id: 'ink',
    name: '水墨',
    backgroundGradient: [Color(0xFFF5F0E8), Color(0xFFEDE5D3)],
    digitColor: Color(0xFF1A1A1A),
    secondColor: Color(0xFF333333),
    separatorColor: Color(0xFF888888),
    subtitleColor: Color(0x99555555),
    digitWeight: FontWeight.w400,
    isDark: false,
  );

  /// 全部主题（顺序即展示顺序）
  static const all = [deepsea, minimal, aurora, neon, ink];

  /// 通过 id 查找主题，找不到则返回默认
  static ClockTheme byId(String id) {
    for (final t in all) {
      if (t.id == id) return t;
    }
    return deepsea;
  }
}