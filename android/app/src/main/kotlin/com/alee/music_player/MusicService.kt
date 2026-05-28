package com.alee.music_player

import android.app.*
import android.content.Context
import android.content.Intent
import android.graphics.BitmapFactory
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat

class MusicService : Service() {

    companion object {
        const val CHANNEL_ID = "music_foreground"
        const val NOTIFY_ID = 2001
        const val ACTION_STOP = "com.alee.music_player.STOP"
        const val ACTION_PLAY_PAUSE = "com.alee.music_player.PLAY_PAUSE"
        const val ACTION_NEXT = "com.alee.music_player.NEXT"
        const val ACTION_PREV = "com.alee.music_player.PREV"
        var isRunning = false; var isPlaying = true
        var currentTitle = "狸音乐"; var currentArtist = ""
    }

    override fun onCreate() { super.onCreate(); createNotificationChannel() }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            stopForeground(STOP_FOREGROUND_REMOVE); stopSelf(); isRunning = false
            return START_NOT_STICKY
        }
        intent?.getStringExtra("title")?.let { currentTitle = it }
        intent?.getStringExtra("artist")?.let { currentArtist = it }
        intent?.getBooleanExtra("playing", true)?.let { isPlaying = it }
        startForeground(NOTIFY_ID, buildNotification())
        isRunning = true
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null
    override fun onDestroy() { isRunning = false; super.onDestroy() }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
            (getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
                .createNotificationChannel(NotificationChannel(CHANNEL_ID, "音乐播放", NotificationManager.IMPORTANCE_LOW).apply {
                    description = "后台播放通知"; setShowBadge(false); setSound(null, null)
                })
    }

    private fun buildNotification(): Notification {
        val fl = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0
        val clickPi = PendingIntent.getActivity(this, 0, Intent(this, MainActivity::class.java).apply { flags = Intent.FLAG_ACTIVITY_SINGLE_TOP }, fl)
        val ppPi = PendingIntent.getActivity(this, 1, Intent(this, MainActivity::class.java).apply { action = ACTION_PLAY_PAUSE; addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP) }, fl)
        val prPi = PendingIntent.getActivity(this, 2, Intent(this, MainActivity::class.java).apply { action = ACTION_PREV; addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP) }, fl)
        val nxPi = PendingIntent.getActivity(this, 3, Intent(this, MainActivity::class.java).apply { action = ACTION_NEXT; addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP) }, fl)
        val stPi = PendingIntent.getService(this, 4, Intent(this, MusicService::class.java).apply { action = ACTION_STOP }, fl)

        val icon = if (isPlaying) android.R.drawable.ic_media_pause else android.R.drawable.ic_media_play
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(currentTitle)
            .setContentText(currentArtist)
            .setSubText(if (isPlaying) "正在播放" else "已暂停")
            .setSmallIcon(R.drawable.ic_notification)
            .setLargeIcon(BitmapFactory.decodeResource(resources, R.drawable.ic_notification))
            .setContentIntent(clickPi)
            .addAction(android.R.drawable.ic_media_previous, "上一首", prPi)
            .addAction(icon, if (isPlaying) "暂停" else "播放", ppPi)
            .addAction(android.R.drawable.ic_media_next, "下一首", nxPi)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setSilent(true)
            .build()
    }
}
