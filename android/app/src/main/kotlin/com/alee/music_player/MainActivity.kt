package com.alee.music_player

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    companion object {
        const val CHANNEL = "com.alee.music_player/service"
        // 媒体控制通道（通知栏按钮 → Flutter）
        const val MEDIA_CHANNEL = "com.alee.music_player/media"
    }

    private var mediaChannel: MethodChannel? = null

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // 服务控制通道（Flutter → Native）
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "start" -> {
                        startMusicService(
                            call.argument("title") ?: "狸音乐",
                            call.argument("artist") ?: "",
                            call.argument("playing") ?: true
                        )
                        result.success(true)
                    }
                    "update" -> {
                        updateMusicService(
                            call.argument("title") ?: "狸音乐",
                            call.argument("artist") ?: "",
                            call.argument("playing") ?: false
                        )
                        result.success(true)
                    }
                    "stop" -> { stopMusicService(); result.success(true) }
                    "requestBattery" -> { requestBatteryOpt(); result.success(true) }
                    "isBatteryIgnored" -> { result.success(isBatteryIgnored()) }
                    else -> result.notImplemented()
                }
            }

        // 媒体控制通道（Native → Flutter 按钮事件）
        mediaChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, MEDIA_CHANNEL)
    }

    /** 处理来自通知栏按钮的 Intent */
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        when (intent.action) {
            MusicService.ACTION_PLAY_PAUSE -> mediaChannel?.invokeMethod("playPause", null)
            MusicService.ACTION_NEXT -> mediaChannel?.invokeMethod("next", null)
            MusicService.ACTION_PREV -> mediaChannel?.invokeMethod("prev", null)
            MusicService.ACTION_STOP -> mediaChannel?.invokeMethod("stop", null)
        }
    }

    private fun startMusicService(title: String, artist: String, playing: Boolean) {
        val intent = Intent(this, MusicService::class.java).apply {
            putExtra("title", title)
            putExtra("artist", artist)
            putExtra("playing", playing)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
    }

    private fun updateMusicService(title: String, artist: String, playing: Boolean) {
        val intent = Intent(this, MusicService::class.java).apply {
            putExtra("title", title)
            putExtra("artist", artist)
            putExtra("playing", playing)
        }
        startService(intent)
    }

    private fun stopMusicService() {
        startService(Intent(this, MusicService::class.java).apply { action = MusicService.ACTION_STOP })
    }

    private fun requestBatteryOpt() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val pm = getSystemService(POWER_SERVICE) as PowerManager
            if (!pm.isIgnoringBatteryOptimizations(packageName)) {
                startActivity(Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                    data = Uri.parse("package:$packageName")
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                })
            }
        }
    }

    private fun isBatteryIgnored(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            (getSystemService(POWER_SERVICE) as PowerManager).isIgnoringBatteryOptimizations(packageName)
        } else true
    }
}
