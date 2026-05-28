package com.alee.music_player

import android.app.*
import android.content.Context
import android.content.Intent
import android.graphics.PixelFormat
import android.os.Build
import android.os.IBinder
import android.view.Gravity
import android.view.WindowManager
import androidx.core.app.NotificationCompat

class FloatingOverlayService : Service() {

    companion object {
        const val CHANNEL_ID = "floating_overlay"
        const val NOTIFY_ID = 2002
        const val ACTION_SHOW = "com.alee.music_player.OVERLAY_SHOW"
        const val ACTION_HIDE = "com.alee.music_player.OVERLAY_HIDE"
        const val ACTION_UPDATE = "com.alee.music_player.OVERLAY_UPDATE"

        var isVisible = false
            private set

        // 当前状态
        internal var currentTitle = "狸音乐"
        internal var currentArtist = ""
        internal var currentPlaying = false
        internal var currentPositionMs = 0L
        internal var currentDurationMs = 0L
    }

    private var wm: WindowManager? = null
    private var overlayView: FloatingOverlayView? = null
    private var overlayLp: WindowManager.LayoutParams? = null

    override fun onCreate() {
        super.onCreate()
        wm = getSystemService(WINDOW_SERVICE) as WindowManager
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_SHOW -> {
                if (!isVisible) createOverlay()
                updateFromIntent(intent)
                updateView()
            }
            ACTION_UPDATE -> {
                updateFromIntent(intent)
                updateView()
            }
            ACTION_HIDE -> hideOverlay()
        }
        return START_NOT_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        removeOverlay()
        super.onDestroy()
    }

    private fun updateFromIntent(intent: Intent?) {
        intent?.let {
            it.getStringExtra("title")?.let { currentTitle = it }
            it.getStringExtra("artist")?.let { currentArtist = it }
            if (it.hasExtra("playing")) currentPlaying = it.getBooleanExtra("playing", false)
            if (it.hasExtra("positionMs")) currentPositionMs = it.getLongExtra("positionMs", 0L)
            if (it.hasExtra("durationMs")) currentDurationMs = it.getLongExtra("durationMs", 0L)
        }
    }

    private fun updateView() {
        overlayView?.let { v ->
            v.title = currentTitle
            v.artist = currentArtist
            v.isPlaying = currentPlaying
            v.positionMs = currentPositionMs
            v.durationMs = currentDurationMs
            v.postInvalidate()
        }
        // 更新前台通知
        startForeground(NOTIFY_ID, buildNotification())
    }

    private fun createOverlay() {
        if (overlayView != null) return

        val dm = resources.displayMetrics
        val dp = dm.density
        val width = dm.widthPixels
        val heightPx = (180 * dp).toInt()

        overlayView = FloatingOverlayView(this).apply {
            onPlayPause = { sendToActivity("playPause") }
            onNext = { sendToActivity("next") }
            onPrev = { sendToActivity("prev") }
        }

        val flags = (WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE
                or WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL
                or WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN)

        overlayLp = WindowManager.LayoutParams(
            width,
            heightPx,
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
            flags,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = 0
            y = 0
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                layoutInDisplayCutoutMode =
                    WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
            }
        }

        try {
            wm?.addView(overlayView, overlayLp)
            isVisible = true
            // 前台通知
            startForeground(NOTIFY_ID, buildNotification())
        } catch (_: Exception) {
            isVisible = false
        }
    }

    private fun removeOverlay() {
        overlayView?.let {
            try { wm?.removeView(it) } catch (_: Exception) {}
        }
        overlayView = null
        overlayLp = null
        isVisible = false
    }

    private fun hideOverlay() {
        removeOverlay()
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    private fun sendToActivity(action: String) {
        val intent = Intent(this, MainActivity::class.java).apply {
            this.action = action
            addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
        }
        startActivity(intent)
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            (getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
                .createNotificationChannel(NotificationChannel(CHANNEL_ID, "悬浮窗", NotificationManager.IMPORTANCE_LOW).apply {
                    description = "悬浮窗控制"
                    setShowBadge(false)
                    setSound(null, null)
                })
        }
    }

    private fun buildNotification(): Notification {
        val fl = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0
        val clickPi = PendingIntent.getActivity(this, 10, Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP
        }, fl)
        val hidePi = PendingIntent.getService(this, 11, Intent(this, FloatingOverlayService::class.java).apply {
            action = ACTION_HIDE
        }, fl)

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("狸音乐 · 悬浮窗")
            .setContentText(currentTitle)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentIntent(clickPi)
            .addAction(android.R.drawable.ic_menu_close_clear_cancel, "隐藏", hidePi)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setSilent(true)
            .build()
    }
}
