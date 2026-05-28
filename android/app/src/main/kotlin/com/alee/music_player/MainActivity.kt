package com.alee.music_player

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.media.audiofx.Equalizer
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.MediaStore
import android.provider.Settings
import androidx.annotation.NonNull
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        const val CHANNEL = "com.alee.music_player/service"
        const val MEDIA_CHANNEL = "com.alee.music_player/media"
    }

    private var mediaChannel: MethodChannel? = null
    private var equalizer: Equalizer? = null

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "start" -> {
                        startMusicService(call.argument("title") ?: "狸音乐", call.argument("artist") ?: "", call.argument("playing") ?: true)
                        result.success(true)
                    }
                    "update" -> {
                        updateMusicService(call.argument("title") ?: "狸音乐", call.argument("artist") ?: "", call.argument("playing") ?: false)
                        result.success(true)
                    }
                    "stop" -> { stopMusicService(); result.success(true) }
                    "requestBattery" -> { requestBatteryOpt(); result.success(true) }
                    "requestNotification" -> { requestNotificationPermission(); result.success(true) }
                    "isBatteryIgnored" -> { result.success(isBatteryIgnored()) }
                    "deleteFile" -> {
                        val fp = call.argument<String>("path") ?: ""
                        result.success(deleteFileViaMediaStore(fp))
                    }
                    "setEqualizer" -> {
                        val preset = call.argument<String>("preset") ?: "flat"
                        val sessionId = call.argument<Int>("sessionId") ?: 0
                        setEqualizer(preset, sessionId)
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }

        mediaChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, MEDIA_CHANNEL)
        requestNotificationPermission()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        when (intent.action) {
            MusicService.ACTION_PLAY_PAUSE -> mediaChannel?.invokeMethod("playPause", null)
            MusicService.ACTION_NEXT -> mediaChannel?.invokeMethod("next", null)
            MusicService.ACTION_PREV -> mediaChannel?.invokeMethod("prev", null)
            MusicService.ACTION_STOP -> mediaChannel?.invokeMethod("stop", null)
        }
    }

    private fun requestNotificationPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            if (ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
                ActivityCompat.requestPermissions(this, arrayOf(Manifest.permission.POST_NOTIFICATIONS), 100)
            }
        }
    }

    private fun startMusicService(title: String, artist: String, playing: Boolean) {
        val intent = Intent(this, MusicService::class.java).apply {
            putExtra("title", title); putExtra("artist", artist); putExtra("playing", playing)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) startForegroundService(intent) else startService(intent)
    }

    private fun updateMusicService(title: String, artist: String, playing: Boolean) {
        startService(Intent(this, MusicService::class.java).apply { putExtra("title", title); putExtra("artist", artist); putExtra("playing", playing) })
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
                })
            }
        }
    }

    private fun isBatteryIgnored() = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M)
        (getSystemService(POWER_SERVICE) as PowerManager).isIgnoringBatteryOptimizations(packageName) else true

    private fun deleteFileViaMediaStore(filePath: String): Boolean {
        return try {
            val file = java.io.File(filePath)
            if (!file.exists()) return true
            val uri = MediaStore.Files.getContentUri("external")
            val projection = arrayOf(MediaStore.Files.FileColumns._ID)
            val sel = MediaStore.Files.FileColumns.DATA + "=?"
            val cursor = contentResolver.query(uri, projection, sel, arrayOf(filePath), null)
            cursor?.use { c ->
                while (c.moveToNext()) {
                    val id = c.getLong(0)
                    contentResolver.delete(Uri.withAppendedPath(uri, id.toString()), null, null)
                    return true
                }
            }
            file.delete()
        } catch (_: Exception) { false }
    }

    private fun setEqualizer(preset: String, sessionId: Int) {
        try {
            val sid = if (sessionId > 0) sessionId else {
                // 尝试获取音频session
                try {
                    val dummy = android.media.MediaPlayer()
                    val id = dummy.audioSessionId
                    dummy.release()
                    id
                } catch (_: Exception) { 0 }
            }
            if (equalizer == null && sid > 0) {
                equalizer = Equalizer(0, sid)
                equalizer?.enabled = true
            }
            val eq = equalizer ?: return
            val bands = eq.numberOfBands
            if (bands < 5) return
            // 5-band EQ settings (60Hz, 230Hz, 910Hz, 3.6kHz, 14kHz)
            val settings = when (preset) {
                "flat" -> shortArrayOf(0, 0, 0, 0, 0)
                "djBass" -> shortArrayOf(800, 500, 200, 0, 0)
                "pop" -> shortArrayOf(0, 200, 400, 300, 100)
                "vocal" -> shortArrayOf(-200, 100, 400, 500, 300)
                "classical" -> shortArrayOf(300, 200, 0, 200, 300)
                "heavyBass" -> shortArrayOf(1000, 700, 300, 100, 0)
                else -> shortArrayOf(0, 0, 0, 0, 0)
            }
            for (i in 0 until minOf(bands, settings.size)) {
                eq.setBandLevel(i.toShort(), settings[i])
            }
        } catch (_: Exception) {}
    }
}
