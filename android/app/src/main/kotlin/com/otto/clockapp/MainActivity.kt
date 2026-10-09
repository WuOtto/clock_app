package com.otto.clockapp

import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.BatteryManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    /**
     * Dart ↔ 原生电量通道
     *
     * 之所以不引入 battery_plus 插件，是因为它会把 AGP 8.2.0 拉进 plugin classpath，
     * 在只镜像了部分 Google 仓库的环境下会解析不到 com.android.tools.ddms:ddmlib:31.2.0，
     * 进而整个项目编译失败。这里用系统的 [BatteryManager] 直接读取，零依赖。
     *
     * 方法：
     *   - getInfo: 返回 { level: Int (0~100, -1 表示未知), charging: Bool }
     */
    private val channelName = "countdown/battery"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getInfo" -> result.success(getBatteryInfo())
                    else -> result.notImplemented()
                }
            }
    }

    private fun getBatteryInfo(): Map<String, Any> {
        // 1) 电量百分比（API 21+ 直接可用）
        var level = -1
        try {
            val bm = getSystemService(Context.BATTERY_SERVICE) as? BatteryManager
            if (bm != null) {
                level = bm.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY)
            }
        } catch (_: Throwable) {
            // 部分定制 ROM 可能抛异常，降级走 sticky intent
        }

        // 2) 充放状态：用 sticky broadcast 拿 EXTRA_STATUS，比电池管理器更通用
        val intent: Intent? = try {
            registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
        } catch (_: Throwable) {
            null
        }

        if (level < 0 && intent != null) {
            val rawLevel = intent.getIntExtra(BatteryManager.EXTRA_LEVEL, -1)
            val scale = intent.getIntExtra(BatteryManager.EXTRA_SCALE, -1)
            if (rawLevel >= 0 && scale > 0) {
                level = rawLevel * 100 / scale
            }
        }

        val status = intent?.getIntExtra(BatteryManager.EXTRA_STATUS, -1) ?: -1
        val charging = status == BatteryManager.BATTERY_STATUS_CHARGING ||
                status == BatteryManager.BATTERY_STATUS_FULL

        return mapOf("level" to level, "charging" to charging)
    }
}