package com.alee.music_player

import android.content.Context
import android.graphics.*
import android.graphics.drawable.Drawable
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.view.MotionEvent
import android.view.View
import android.view.WindowInsets
import androidx.core.content.ContextCompat

class FloatingOverlayView(context: Context) : View(context) {

    var title: String = "狸音乐"
    var artist: String = ""
    var isPlaying: Boolean = false
    var positionMs: Long = 0L
    var durationMs: Long = 0L

    var onPlayPause: (() -> Unit)? = null
    var onNext: (() -> Unit)? = null
    var onPrev: (() -> Unit)? = null
    var onResize: ((widthDp: Int, heightDp: Int, yOffsetDp: Int) -> Unit)? = null

    var collapsed = true
    private val handler = Handler(Looper.getMainLooper())
    private val collapseDelayMs = 5000L
    private val collapseRunnable = Runnable { toggleCollapse() }
    private var currentY = 48 // 当前Y偏移(dp)

    fun toggleCollapse() {
        collapsed = !collapsed
        handler.removeCallbacks(collapseRunnable)
        if (!collapsed) handler.postDelayed(collapseRunnable, collapseDelayMs)
        val (w, h, yOff) = if (collapsed) Triple(CIRCLE_SIZE, CIRCLE_SIZE, currentY) else Triple(BAR_WIDTH, BAR_HEIGHT, currentY + 32)
        onResize?.invoke(w, h, yOff)
        postInvalidate()
    }

    fun resetAutoCollapse() {
        if (!collapsed) { handler.removeCallbacks(collapseRunnable); handler.postDelayed(collapseRunnable, collapseDelayMs) }
    }

    private val dp: Float get() = resources.displayMetrics.density

    companion object {
        const val CIRCLE_SIZE = 36; const val BAR_HEIGHT = 60; const val BAR_WIDTH = 85
    }

    // 系统标准媒体图标
    private val prevDrawable: Drawable? = ContextCompat.getDrawable(context, android.R.drawable.ic_media_previous)
    private val nextDrawable: Drawable? = ContextCompat.getDrawable(context, android.R.drawable.ic_media_next)
    private val playDrawable: Drawable? = ContextCompat.getDrawable(context, android.R.drawable.ic_media_play)
    private val pauseDrawable: Drawable? = ContextCompat.getDrawable(context, android.R.drawable.ic_media_pause)

    private val bgPaint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val textPaint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val subTextPaint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val circlePaint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val btnBgPaint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val progressPaint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val accentGradient: LinearGradient

    // 按钮触摸区域
    private val prevRect = RectF(); private val playRect = RectF(); private val nextRect = RectF()
    private var hasButtons = false; private var btnSize = 0f

    init {
        bgPaint.color = Color.parseColor("#CC121218")
        accentGradient = LinearGradient(0f, 0f, 0f, 0f, Color.parseColor("#FF6B35"), Color.parseColor("#A855F7"), Shader.TileMode.CLAMP)
        textPaint.color = Color.parseColor("#F0F0F5"); textPaint.isAntiAlias = true
        subTextPaint.color = Color.parseColor("#88889A"); subTextPaint.isAntiAlias = true
        circlePaint.isAntiAlias = true; circlePaint.style = Paint.Style.FILL
        btnBgPaint.isAntiAlias = true
        progressPaint.strokeCap = Paint.Cap.ROUND
    }

    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
        super.onSizeChanged(w, h, oldw, oldh)
        val fw = w.toFloat(); val fh = h.toFloat()
        if (collapsed) return
        accentGradient.setLocalMatrix(Matrix().apply { setRectToRect(RectF(0f, 0f, fw, fh), RectF(0f, 0f, fw, fh), Matrix.ScaleToFit.FILL) })

        btnSize = 34 * dp; val gap = 6 * dp; val rm = fw - 14 * dp
        var rx = rm - btnSize
        nextRect.set(rx, (fh - btnSize) / 2f, rx + btnSize, (fh + btnSize) / 2f)
        rx -= (btnSize + gap)
        playRect.set(rx, (fh - btnSize) / 2f, rx + btnSize, (fh + btnSize) / 2f)
        rx -= (btnSize + gap)
        prevRect.set(rx, (fh - btnSize) / 2f, rx + btnSize, (fh + btnSize) / 2f)
        hasButtons = prevRect.left > 40 * dp

        // 初始设置图标尺寸
        prevDrawable?.setBounds(prevRect.left.toInt(), prevRect.top.toInt(), prevRect.right.toInt(), prevRect.bottom.toInt())
        playDrawable?.setBounds(playRect.left.toInt(), playRect.top.toInt(), playRect.right.toInt(), playRect.bottom.toInt())
        pauseDrawable?.setBounds(playRect.left.toInt(), playRect.top.toInt(), playRect.right.toInt(), playRect.bottom.toInt())
        nextDrawable?.setBounds(nextRect.left.toInt(), nextRect.top.toInt(), nextRect.right.toInt(), nextRect.bottom.toInt())
    }

    override fun onDraw(canvas: Canvas) {
        val w = width.toFloat(); val h = height.toFloat(); val d = dp

        if (collapsed) {
            val cx = w / 2f; val cy = h / 2f; val r = w.coerceAtMost(h) / 2f
            circlePaint.color = Color.parseColor("#E6121218")
            canvas.drawCircle(cx, cy, r, circlePaint)
            // 系统标准图标
            val icon = if (isPlaying) pauseDrawable else playDrawable
            icon?.let {
                val iconSz = (r * 1.4f).toInt()
                it.setBounds((cx - iconSz / 2f).toInt(), (cy - iconSz / 2f).toInt(), (cx + iconSz / 2f).toInt(), (cy + iconSz / 2f).toInt())
                it.draw(canvas)
            }
        } else {
            // 圆角背景
            val radius = 12 * d
            val bgPath = Path().apply { addRoundRect(RectF(0f, 0f, w, h), radius, radius, Path.Direction.CW) }
            circlePaint.color = Color.parseColor("#CC121218"); canvas.drawPath(bgPath, circlePaint)

            // 进度条
            val py = h - 1.5f * d
            val fr = if (durationMs > 0) (positionMs.toFloat() / durationMs).coerceIn(0f, 1f) else 0f
            if (fr > 0) {
                progressPaint.shader = accentGradient; progressPaint.strokeWidth = 1.5f * d
                canvas.drawLine(radius, py, radius + (w - 2 * radius) * fr, py, progressPaint)
                progressPaint.shader = null
            }

            // 封面
            val le = 10 * d; val as_ = 24 * d; val ay = (h - as_) / 2f
            val acx = le + as_ / 2; val acy = ay + as_ / 2
            circlePaint.color = Color.parseColor("#1AFF6B35"); canvas.drawCircle(acx, acy, as_ / 2, circlePaint)

            // 歌名
            val tx = le + as_ + 8 * d; val mtw = prevRect.left - tx - 4 * d
            textPaint.textSize = 12 * d
            val dt = _ellipsize(title, textPaint, mtw)
            canvas.drawText(dt, tx, acy + 4 * d, textPaint)

            if (hasButtons) {
                val br = nextRect.width() / 2f + 2 * d
                // 上一首
                btnBgPaint.color = Color.parseColor("#35FFFFFF"); canvas.drawCircle(prevRect.centerX(), prevRect.centerY(), br, btnBgPaint)
                prevDrawable?.setBounds(prevRect.left.toInt(), prevRect.top.toInt(), prevRect.right.toInt(), prevRect.bottom.toInt())
                prevDrawable?.draw(canvas)
                // 播放/暂停
                btnBgPaint.color = Color.parseColor("#40FF6B35"); canvas.drawCircle(playRect.centerX(), playRect.centerY(), br, btnBgPaint)
                val pIcon = if (isPlaying) pauseDrawable else playDrawable
                pIcon?.setBounds(playRect.left.toInt(), playRect.top.toInt(), playRect.right.toInt(), playRect.bottom.toInt())
                pIcon?.draw(canvas)
                // 下一首
                btnBgPaint.color = Color.parseColor("#35FFFFFF"); canvas.drawCircle(nextRect.centerX(), nextRect.centerY(), br, btnBgPaint)
                nextDrawable?.setBounds(nextRect.left.toInt(), nextRect.top.toInt(), nextRect.right.toInt(), nextRect.bottom.toInt())
                nextDrawable?.draw(canvas)
            }
        }
    }

    private fun _ellipsize(s: String, paint: Paint, maxW: Float): String {
        if (paint.measureText(s) <= maxW) return s
        var t = s; while (paint.measureText("$t…") > maxW && t.length > 1) t = t.substring(0, t.length - 1)
        return "$t…"
    }

    override fun onTouchEvent(event: MotionEvent): Boolean {
        if (event.action == MotionEvent.ACTION_UP) {
            val x = event.x; val y = event.y
            if (!collapsed && hasButtons) {
                when {
                    prevRect.contains(x, y) -> { onPrev?.invoke(); resetAutoCollapse(); return true }
                    playRect.contains(x, y) -> { onPlayPause?.invoke(); resetAutoCollapse(); return true }
                    nextRect.contains(x, y) -> { onNext?.invoke(); resetAutoCollapse(); return true }
                }
            }
            toggleCollapse(); return true
        }
        return true
    }
}
