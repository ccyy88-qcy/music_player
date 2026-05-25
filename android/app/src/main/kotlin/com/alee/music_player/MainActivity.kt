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
    }

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "start" -> {
                        val title = call.argument<String>("title") ?: "🦊 狸音乐"
                        val artist = call.argument<String>("artist") ?: ""
                        val playing = call.argument<Boolean>("playing") ?: true
                        startMusicService(title, artist, playing)
                        result.success(true)
                    }
                    "update" -> {
                        val title = call.argument<String>("title") ?: "🦊 狸音乐"
                        val artist = call.argument<String>("artist") ?: ""
                        val playing = call.argument<Boolean>("playing") ?: false
                        updateMusicService(title, artist, playing)
                        result.success(true)
                    }
                    "stop" -> {
                        stopMusicService()
                        result.success(true)
                    }
                    "requestBattery" -> {
                        requestIgnoreBatteryOptimizations()
                        result.success(true)
                    }
                    "isBatteryIgnored" -> {
                        result.success(isIgnoringBatteryOptimizations())
                    }
                    else -> result.notImplemented()
                }
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
        if (!MusicService.isRunning) {
            startMusicService(title, artist, playing)
            return
        }
        val intent = Intent(this, MusicService::class.java).apply {
            putExtra("title", title)
            putExtra("artist", artist)
            putExtra("playing", playing)
        }
        startService(intent)
    }

    private fun stopMusicService() {
        val intent = Intent(this, MusicService::class.java).apply {
            action = MusicService.ACTION_STOP
        }
        startService(intent)
    }

    private fun requestIgnoreBatteryOptimizations() {
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

    private fun isIgnoringBatteryOptimizations(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            (getSystemService(POWER_SERVICE) as PowerManager).isIgnoringBatteryOptimizations(packageName)
        } else true
    }
}
