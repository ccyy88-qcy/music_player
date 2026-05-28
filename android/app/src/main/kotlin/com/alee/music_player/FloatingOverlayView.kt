package com.alee.music_player

import android.content.Context
import android.graphics.*
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.view.MotionEvent
import android.view.View
import android.view.WindowInsets

class FloatingOverlayView(context: Context) : View(context) {

    // ===== 数据 =====
    var title: String = "狸音乐"
    var artist: String = ""
    var isPlaying: Boolean = false
    var positionMs: Long = 0L
    var durationMs: Long = 0L

    // ===== 回调 =====
    var onPlayPause: (() -> Unit)? = null
    var onNext: (() -> Unit)? = null
    var onPrev: (() -> Unit)? = null
    var onResize: ((widthDp: Int, heightDp: Int) -> Unit)? = null

    // ===== 状态 =====
    var collapsed = true
    private val handler = Handler(Looper.getMainLooper())
    private val collapseDelayMs = 3000L
    private val collapseRunnable = Runnable { toggleCollapse() }

    fun toggleCollapse() {
        collapsed = !collapsed
        handler.removeCallbacks(collapseRunnable)
        if (!collapsed) {
            // 展开后定时折叠
            handler.postDelayed(collapseRunnable, collapseDelayMs)
        }
        // 通知服务调整窗口尺寸
        val (w, h) = if (collapsed) Pair(CIRCLE_SIZE, CIRCLE_SIZE) else Pair(BAR_WIDTH, BAR_HEIGHT)
        onResize?.invoke(w, h)
        postInvalidate()
    }

    fun resetAutoCollapse() {
        if (!collapsed) {
            handler.removeCallbacks(collapseRunnable)
            handler.postDelayed(collapseRunnable, collapseDelayMs)
        }
    }

    private val dp: Float
        get() = resources.displayMetrics.density

    companion object {
        const val CIRCLE_SIZE = 36
        const val BAR_HEIGHT = 50
        const val BAR_WIDTH = 85 // 百分比
    }

    // ===== 绘制 =====
    private val bgPaint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val textPaint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val subTextPaint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val btnBgPaint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val btnPaint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val progressPaint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val accentGradient: LinearGradient

    // 按钮区域
    private val prevRect = RectF()
    private val playRect = RectF()
    private val nextRect = RectF()
    private var hasButtons = false
    private var btnSize = 0f

    // Path
    private val playPath = Path()
    private val pausePath = Path()
    private val prevPath = Path()
    private val nextPath = Path()

    init {
        bgPaint.color = Color.parseColor("#CC121218")

        accentGradient = LinearGradient(
            0f, 0f, 0f, 0f,
            Color.parseColor("#FF6B35"),
            Color.parseColor("#A855F7"),
            Shader.TileMode.CLAMP
        )

        textPaint.color = Color.parseColor("#F0F0F5")
        textPaint.isAntiAlias = true
        subTextPaint.color = Color.parseColor("#88889A")
        subTextPaint.isAntiAlias = true
        btnBgPaint.isAntiAlias = true
        btnPaint.isAntiAlias = true
        btnPaint.style = Paint.Style.FILL
        progressPaint.strokeCap = Paint.Cap.ROUND
    }

    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
        super.onSizeChanged(w, h, oldw, oldh)
        val fw = w.toFloat()
        val fh = h.toFloat()

        if (collapsed) return // 圆形无按钮区域

        accentGradient.setLocalMatrix(Matrix().apply {
            setRectToRect(RectF(0f, 0f, fw, fh),
                RectF(0f, 0f, fw, fh), Matrix.ScaleToFit.FILL)
        })

        btnSize = 34 * dp
        val gap = 6 * dp
        val rightMargin = fw - 14 * dp
        var rx = rightMargin - btnSize
        nextRect.set(rx, (fh - btnSize) / 2f, rx + btnSize, (fh + btnSize) / 2f)
        rx -= (btnSize + gap)
        playRect.set(rx, (fh - btnSize) / 2f, rx + btnSize, (fh + btnSize) / 2f)
        rx -= (btnSize + gap)
        prevRect.set(rx, (fh - btnSize) / 2f, rx + btnSize, (fh + btnSize) / 2f)
        hasButtons = prevRect.left > 40 * dp

        _buildBtnPaths(btnSize)
    }

    private fun _buildBtnPaths(size: Float) {
        val half = size / 2f
        val triSize = size * 0.5f

        prevPath.reset()
        for (i in 0..1) {
            val ox = -triSize * 0.6f + i * (triSize * 0.8f)
            prevPath.moveTo(half + ox, half - triSize * 0.5f)
            prevPath.lineTo(half + ox - triSize, half)
            prevPath.lineTo(half + ox, half + triSize * 0.5f)
            prevPath.close()
        }
        nextPath.reset()
        for (i in 0..1) {
            val ox = triSize * 1.1f - i * (triSize * 0.8f)
            nextPath.moveTo(half - ox, half - triSize * 0.5f)
            nextPath.lineTo(half - ox + triSize, half)
            nextPath.lineTo(half - ox, half + triSize * 0.5f)
            nextPath.close()
        }
        playPath.reset()
        playPath.moveTo(half - triSize * 0.45f, half - triSize * 0.6f)
        playPath.lineTo(half + triSize * 0.65f, half)
        playPath.lineTo(half - triSize * 0.45f, half + triSize * 0.6f)
        playPath.close()
        val barW = triSize * 0.3f; val barH = triSize * 0.65f; val barGap = triSize * 0.2f
        pausePath.reset()
        pausePath.addRect(half - barGap - barW, half - barH, half - barGap, half + barH, Path.Direction.CW)
        pausePath.addRect(half + barGap, half - barH, half + barGap + barW, half + barH, Path.Direction.CW)
    }

    override fun onDraw(canvas: Canvas) {
        val w = width.toFloat()
        val h = height.toFloat()
        val d = dp

        if (collapsed) {
            // ── 圆球态 ──
            val cx = w / 2f
            val cy = h / 2f
            val radius = w.coerceAtMost(h) / 2f

            bgPaint.color = Color.parseColor("#CC121218")
            canvas.drawCircle(cx, cy, radius, bgPaint)

            // 实色播放/暂停图标
            btnPaint.color = Color.parseColor("#FFFFFF")
            val iconSize = radius * 0.55f
            val iconPath = Path().apply {
                if (isPlaying) {
                    // 暂停两条杠
                    val bw = iconSize * 0.3f; val bg = iconSize * 0.15f
                    addRect(cx - bg - bw, cy - iconSize * 0.6f, cx - bg, cy + iconSize * 0.6f, Path.Direction.CW)
                    addRect(cx + bg, cy - iconSize * 0.6f, cx + bg + bw, cy + iconSize * 0.6f, Path.Direction.CW)
                } else {
                    // 播放三角
                    moveTo(cx - iconSize * 0.4f, cy - iconSize * 0.6f)
                    lineTo(cx + iconSize * 0.6f, cy)
                    lineTo(cx - iconSize * 0.4f, cy + iconSize * 0.6f)
                    close()
                }
            }
            canvas.drawPath(iconPath, btnPaint)
        } else {
            // ── 展开条形 ──
            val radius = 12 * d
            val bgPath = Path().apply {
                addRoundRect(RectF(0f, 0f, w, h), radius, radius, Path.Direction.CW)
            }
            bgPaint.color = Color.parseColor("#CC121218")
            canvas.drawPath(bgPath, bgPaint)

            // 进度条(细)
            val progressY = h - 1.5f * d
            val fraction = if (durationMs > 0) (positionMs.toFloat() / durationMs).coerceIn(0f, 1f) else 0f
            if (fraction > 0) {
                progressPaint.shader = accentGradient
                progressPaint.strokeWidth = 1.5f * d
                canvas.drawLine(radius, progressY, radius + (w - 2 * radius) * fraction, progressY, progressPaint)
                progressPaint.shader = null
            }

            // 封面圆
            val leftEdge = 10 * d
            val artSize = 24 * d
            val artY = (h - artSize) / 2f
            val artCx = leftEdge + artSize / 2
            val artCy = artY + artSize / 2

            btnBgPaint.color = Color.parseColor("#1AFF6B35")
            canvas.drawCircle(artCx, artCy, artSize / 2, btnBgPaint)
            btnPaint.color = Color.parseColor("#F0F0F5")
            btnPaint.strokeWidth = 1.2f * d
            btnPaint.style = Paint.Style.STROKE
            val noteP = Path().apply {
                moveTo(artCx - artSize * 0.2f, artCy - artSize * 0.4f)
                lineTo(artCx + artSize * 0.4f, artCy - artSize * 0.6f)
                lineTo(artCx + artSize * 0.4f, artCy + artSize * 0.15f)
            }
            canvas.drawPath(noteP, btnPaint)
            canvas.drawCircle(artCx - artSize * 0.2f, artCy + artSize * 0.15f, artSize * 0.15f, btnPaint)
            canvas.drawCircle(artCx + artSize * 0.4f, artCy + artSize * 0.15f, artSize * 0.15f, btnPaint)
            btnPaint.style = Paint.Style.FILL

            if (hasButtons) {
                // 歌名
                val titleX = leftEdge + artSize + 8 * d
                val maxTextW = prevRect.left - titleX - 4 * d
                textPaint.textSize = 12 * d
                val dt = _ellipsize(title, textPaint, maxTextW)
                canvas.drawText(dt, titleX, artCy + 4 * d, textPaint)

                // 三个按钮 - 实色背景+白色粗图标
                val br = nextRect.width() / 2f
                
                btnBgPaint.color = Color.parseColor("#40FFFFFF")
                canvas.drawCircle(prevRect.centerX(), prevRect.centerY(), br, btnBgPaint)
                btnPaint.color = Color.parseColor("#FFFFFFFF")
                btnPaint.strokeWidth = 0f
                canvas.drawPath(prevPath, btnPaint)

                btnBgPaint.color = Color.parseColor("#50FF6B35")
                canvas.drawCircle(playRect.centerX(), playRect.centerY(), br, btnBgPaint)
                btnPaint.color = Color.parseColor("#FFFFFFFF")
                canvas.drawPath(if (isPlaying) pausePath else playPath, btnPaint)

                btnBgPaint.color = Color.parseColor("#40FFFFFF")
                canvas.drawCircle(nextRect.centerX(), nextRect.centerY(), br, btnBgPaint)
                btnPaint.color = Color.parseColor("#FFFFFFFF")
                canvas.drawPath(nextPath, btnPaint)
            }
        }
    }

    private fun _ellipsize(s: String, paint: Paint, maxW: Float): String {
        if (paint.measureText(s) <= maxW) return s
        var t = s
        while (paint.measureText("$t…") > maxW && t.length > 1) t = t.substring(0, t.length - 1)
        return "$t…"
    }

    // ── 触摸 ──
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
            toggleCollapse()
            return true
        }
        return true
    }
}
