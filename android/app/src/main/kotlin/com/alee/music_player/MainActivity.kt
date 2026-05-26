package com.alee.music_player

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.PowerManager
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
                        val filePath = call.argument<String>("path") ?: ""
                        val success = deleteFileViaMediaStore(filePath)
                        result.success(success)
                    }
                    else -> result.notImplemented()
                }
            }

        mediaChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, MEDIA_CHANNEL)

        // 请求通知权限（Android 13+必须）
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
                    data = Uri.parse("package:$packageName"); addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
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
            // 方法1: MediaStore 查询URI后删除
            val uri = MediaStore.Files.getContentUri("external")
            val projection = arrayOf(MediaStore.Files.FileColumns._ID)
            val selection = MediaStore.Files.FileColumns.DATA + "=?"
            val selectionArgs = arrayOf(filePath)
            val cursor = contentResolver.query(uri, projection, selection, selectionArgs, null)
            cursor?.use { c ->
                while (c.moveToNext()) {
                    val id = c.getLong(0)
                    val deleteUri = Uri.withAppendedPath(uri, id.toString())
                    contentResolver.delete(deleteUri, null, null)
                    return true
                }
            }
            // 方法2: 直接文件删除
            file.delete()
        } catch (_: Exception) { false }
    }
}
