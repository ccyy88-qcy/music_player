package com.alee.music_player

import android.app.*
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import android.support.v4.media.session.MediaSessionCompat
import android.support.v4.media.session.PlaybackStateCompat
import androidx.core.app.NotificationCompat

class MusicService : Service() {

    companion object {
        const val CHANNEL_ID = "music_foreground"
        const val NOTIFY_ID = 2001
        const val ACTION_STOP = "com.alee.music_player.STOP"

        // 媒体控制动作
        const val ACTION_PLAY_PAUSE = "com.alee.music_player.PLAY_PAUSE"
        const val ACTION_NEXT = "com.alee.music_player.NEXT"
        const val ACTION_PREV = "com.alee.music_player.PREV"

        var isRunning = false
        var isPlaying = true
        var currentTitle = "🦊 狸音乐"
        var currentArtist = ""

        private var mediaSession: MediaSessionCompat? = null
    }

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        createMediaSession()
    }

    private fun createMediaSession() {
        mediaSession = MediaSessionCompat(this, "MusicService").apply {
            setFlags(MediaSessionCompat.FLAG_HANDLES_MEDIA_BUTTONS or MediaSessionCompat.FLAG_HANDLES_TRANSPORT_CONTROLS)
            setPlaybackState(PlaybackStateCompat.Builder()
                .setActions(
                    PlaybackStateCompat.ACTION_PLAY or PlaybackStateCompat.ACTION_PAUSE or
                    PlaybackStateCompat.ACTION_SKIP_TO_NEXT or PlaybackStateCompat.ACTION_SKIP_TO_PREVIOUS or
                    PlaybackStateCompat.ACTION_STOP or PlaybackStateCompat.ACTION_SEEK_TO
                )
                .setState(PlaybackStateCompat.STATE_PLAYING, 0, 1.0f)
                .build()
            )
            setCallback(object : MediaSessionCompat.Callback() {
                override fun onPlay() { sendCommand(ACTION_PLAY_PAUSE) }
                override fun onPause() { sendCommand(ACTION_PLAY_PAUSE) }
                override fun onSkipToNext() { sendCommand(ACTION_NEXT) }
                override fun onSkipToPrevious() { sendCommand(ACTION_PREV) }
                override fun onStop() { sendCommand(ACTION_STOP) }
            })
            isActive = true
        }
    }

    /** 发送媒体控制命令到 MainActivity → Flutter */
    private fun sendCommand(action: String) {
        val intent = Intent(this, MainActivity::class.java).apply {
            this.action = action
            addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        startActivity(intent)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                mediaSession?.isActive = false
                mediaSession?.release()
                mediaSession = null
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf()
                isRunning = false
                return START_NOT_STICKY
            }
        }

        intent?.getStringExtra("title")?.let { currentTitle = it }
        intent?.getStringExtra("artist")?.let { currentArtist = it }
        intent?.getBooleanExtra("playing", true)?.let { isPlaying = it }

        updatePlaybackState()
        val notification = buildNotification()
        startForeground(NOTIFY_ID, notification)
        isRunning = true
        return START_STICKY
    }

    private fun updatePlaybackState() {
        mediaSession?.setPlaybackState(PlaybackStateCompat.Builder()
            .setActions(
                PlaybackStateCompat.ACTION_PLAY or PlaybackStateCompat.ACTION_PAUSE or
                PlaybackStateCompat.ACTION_SKIP_TO_NEXT or PlaybackStateCompat.ACTION_SKIP_TO_PREVIOUS or
                PlaybackStateCompat.ACTION_STOP or PlaybackStateCompat.ACTION_SEEK_TO
            )
            .setState(
                if (isPlaying) PlaybackStateCompat.STATE_PLAYING else PlaybackStateCompat.STATE_PAUSED,
                0, 1.0f
            )
            .build()
        )
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        mediaSession?.isActive = false
        mediaSession?.release()
        mediaSession = null
        isRunning = false
        super.onDestroy()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID, "音乐播放", NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "后台播放通知"
                setShowBadge(false)
                setSound(null, null)
            }
            (getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
                .createNotificationChannel(channel)
        }
    }

    private fun buildNotification(): Notification {
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0

        // 点击通知 → 打开App
        val clickIntent = PendingIntent.getActivity(this, 0,
            Intent(this, MainActivity::class.java).apply { flags = Intent.FLAG_ACTIVITY_SINGLE_TOP },
            flags
        )

        // 播放/暂停按钮
        val playPauseIcon = if (isPlaying) android.R.drawable.ic_media_pause else android.R.drawable.ic_media_play
        val playPauseIntent = PendingIntent.getActivity(this, 1,
            Intent(this, MainActivity::class.java).apply { action = ACTION_PLAY_PAUSE; addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP) },
            flags
        )

        // 上一首
        val prevIntent = PendingIntent.getActivity(this, 2,
            Intent(this, MainActivity::class.java).apply { action = ACTION_PREV; addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP) },
            flags
        )

        // 下一首
        val nextIntent = PendingIntent.getActivity(this, 3,
            Intent(this, MainActivity::class.java).apply { action = ACTION_NEXT; addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP) },
            flags
        )

        // 停止
        val stopIntent = PendingIntent.getService(this, 4,
            Intent(this, MusicService::class.java).apply { action = ACTION_STOP },
            flags
        )

        val statusText = if (isPlaying) "$currentArtist ▶ 正在播放" else "$currentArtist ⏸ 已暂停"

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(currentTitle)
            .setContentText(statusText)
            .setSmallIcon(android.R.drawable.ic_media_play)
            .setContentIntent(clickIntent)
            .addAction(android.R.drawable.ic_media_previous, "上一首", prevIntent)
            .addAction(playPauseIcon, if (isPlaying) "暂停" else "播放", playPauseIntent)
            .addAction(android.R.drawable.ic_media_next, "下一首", nextIntent)
            .addAction(android.R.drawable.ic_delete, "停止", stopIntent)
            .setStyle(androidx.media.app.NotificationCompat.MediaStyle()
                .setMediaSession(mediaSession?.sessionToken)
                .setShowActionsInCompactView(0, 1, 2)
            )
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setSilent(true)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .build()
    }
}
