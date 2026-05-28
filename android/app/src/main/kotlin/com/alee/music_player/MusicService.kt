package com.alee.music_player

import android.app.*
import android.content.Context
import android.content.Intent
import android.graphics.BitmapFactory
import android.media.session.MediaSession
import android.media.session.PlaybackState
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
        const val ACTION_SEEK = "com.alee.music_player.SEEK"

        var isRunning = false
        var isPlaying = true
        var currentTitle = "狸音乐"
        var currentArtist = ""
        var currentPositionMs = 0L
        var currentDurationMs = 0L
    }

    private var mediaSession: MediaSession? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        // 创建 MediaSession — Android框架内置，无需额外依赖
        // Android 11+ 只要有活跃的MediaSession，系统自动在锁屏显示播放控件
        mediaSession = MediaSession(this, "MusicService")
        mediaSession?.setCallback(object : MediaSession.Callback() {
            override fun onPlay() { sendAction("playPause") }
            override fun onPause() { sendAction("playPause") }
            override fun onSkipToNext() { sendAction("next") }
            override fun onSkipToPrevious() { sendAction("prev") }
            override fun onSeekTo(pos: Long) {
                val intent = Intent(this@MusicService, MainActivity::class.java).apply {
                    action = ACTION_SEEK
                    putExtra("positionMs", pos)
                    addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
                }
                startActivity(intent)
            }
            override fun onStop() {
                sendAction("stop")
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf()
                isRunning = false
            }
        })
        mediaSession?.isActive = true
    }

    private fun sendAction(action: String) {
        val intent = Intent(this, MainActivity::class.java).apply {
            this.action = when (action) {
                "playPause" -> ACTION_PLAY_PAUSE
                "next" -> ACTION_NEXT
                "prev" -> ACTION_PREV
                "stop" -> ACTION_STOP
                else -> ACTION_PLAY_PAUSE
            }
            addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
        }
        startActivity(intent)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            mediaSession?.isActive = false
            mediaSession?.release()
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
            isRunning = false
            return START_NOT_STICKY
        }

        intent?.getStringExtra("title")?.let { currentTitle = it }
        intent?.getStringExtra("artist")?.let { currentArtist = it }
        intent?.getBooleanExtra("playing", true)?.let { isPlaying = it }
        if (intent?.hasExtra("positionMs") == true) currentPositionMs = intent.getLongExtra("positionMs", 0L)
        if (intent?.hasExtra("durationMs") == true) currentDurationMs = intent.getLongExtra("durationMs", 0L)

        // 更新MediaSession — 系统自动在锁屏/通知栏显示播放控件+进度
        updateMediaSession(currentTitle, currentArtist, isPlaying, currentPositionMs, currentDurationMs)

        startForeground(NOTIFY_ID, buildNotification())
        isRunning = true
        return START_STICKY
    }

    private fun updateMediaSession(title: String, artist: String, playing: Boolean, posMs: Long, durMs: Long) {
        val session = mediaSession ?: return

        session.setMetadata(
            android.media.MediaMetadata.Builder()
                .putString(android.media.MediaMetadata.METADATA_KEY_TITLE, title)
                .putString(android.media.MediaMetadata.METADATA_KEY_ARTIST, artist.ifEmpty { "狸音乐" })
                .putLong(android.media.MediaMetadata.METADATA_KEY_DURATION, durMs)
                .build()
        )

        val state = if (playing) PlaybackState.STATE_PLAYING else PlaybackState.STATE_PAUSED
        val actions = PlaybackState.ACTION_PLAY_PAUSE or
                PlaybackState.ACTION_SKIP_TO_NEXT or
                PlaybackState.ACTION_SKIP_TO_PREVIOUS or
                PlaybackState.ACTION_SEEK_TO or
                PlaybackState.ACTION_PLAY or
                PlaybackState.ACTION_PAUSE or
                PlaybackState.ACTION_STOP
        session.setPlaybackState(
            PlaybackState.Builder()
                .setState(state, posMs, 1.0f)
                .setActions(actions)
                .build()
        )
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        isRunning = false
        try { mediaSession?.isActive = false; mediaSession?.release() } catch (_: Exception) {}
        super.onDestroy()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
            (getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
                .createNotificationChannel(NotificationChannel(CHANNEL_ID, "音乐播放", NotificationManager.IMPORTANCE_LOW).apply {
                    description = "后台播放通知"; setShowBadge(false); setSound(null, null)
                })
    }

    private fun buildNotification(): Notification {
        val fl = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0
        val clickPi = PendingIntent.getActivity(this, 0, Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP
        }, fl)
        val ppPi = PendingIntent.getActivity(this, 1, Intent(this, MainActivity::class.java).apply {
            action = ACTION_PLAY_PAUSE; addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
        }, fl)
        val prPi = PendingIntent.getActivity(this, 2, Intent(this, MainActivity::class.java).apply {
            action = ACTION_PREV; addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
        }, fl)
        val nxPi = PendingIntent.getActivity(this, 3, Intent(this, MainActivity::class.java).apply {
            action = ACTION_NEXT; addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
        }, fl)
        val stPi = PendingIntent.getService(this, 4, Intent(this, MusicService::class.java).apply {
            action = ACTION_STOP
        }, fl)

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
            // 手动进度条
            .setProgress(
                if (currentDurationMs > 0) currentDurationMs.toInt() else 0,
                currentPositionMs.toInt(),
                false
            )
            .build()
    }
}
