package com.alee.music_player

import android.app.Service
import android.content.Intent
import android.graphics.PixelFormat
import android.os.IBinder
import android.view.Gravity
import android.view.WindowManager

class FloatingOverlayService : Service() {

    companion object {
        const val ACTION_SHOW = "com.alee.music_player.OVERLAY_SHOW"
        const val ACTION_HIDE = "com.alee.music_player.OVERLAY_HIDE"
        const val ACTION_UPDATE = "com.alee.music_player.OVERLAY_UPDATE"

        var isVisible = false
            private set

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
    }

    private fun resizeOverlay(widthDp: Int, heightDp: Int) {
        val dm = resources.displayMetrics
        val dp = dm.density
        val w = if (widthDp == FloatingOverlayView.CIRCLE_SIZE) {
            (FloatingOverlayView.CIRCLE_SIZE * dp).toInt()
        } else {
            (dm.widthPixels * FloatingOverlayView.BAR_WIDTH / 100).toInt()
        }
        val h = (heightDp * dp).toInt()
        overlayLp?.let { lp ->
            lp.width = w
            lp.height = h
            try { wm?.updateViewLayout(overlayView, lp) } catch (_: Exception) {}
        }
    }

    private fun createOverlay() {
        if (overlayView != null) return

        val dm = resources.displayMetrics
        val dp = dm.density
        val circleSize = (FloatingOverlayView.CIRCLE_SIZE * dp).toInt()

        overlayView = FloatingOverlayView(this).apply {
            onPlayPause = { sendToActivity("playPause") }
            onNext = { sendToActivity("next") }
            onPrev = { sendToActivity("prev") }
            onResize = { wDp, hDp -> resizeOverlay(wDp, hDp) }
        }

        val flags = (WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE
                or WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL
                or WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN)

        overlayLp = WindowManager.LayoutParams(
            circleSize,
            circleSize,
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
            flags,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.TOP or Gravity.CENTER_HORIZONTAL
            y = (12 * dp).toInt()
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.P) {
                layoutInDisplayCutoutMode =
                    WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
            }
        }

        try {
            wm?.addView(overlayView, overlayLp)
            isVisible = true
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
        stopSelf()
    }

    private fun sendToActivity(action: String) {
        val intent = Intent(this, MainActivity::class.java).apply {
            this.action = action
            addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        startActivity(intent)
    }
}
