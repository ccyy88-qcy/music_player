package com.alee.music_player

import android.content.Context
import android.graphics.*
import android.os.Build
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

    // ===== 点击回调 =====
    var onPlayPause: (() -> Unit)? = null
    var onNext: (() -> Unit)? = null
    var onPrev: (() -> Unit)? = null

    // ===== 绘制 =====
    private val bgPaint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val textPaint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val btnBgPaint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val btnPaint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val progressBgPaint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val progressPaint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val accentGradient: LinearGradient

    // 按钮触摸区域
    private val prevRect = RectF()
    private val playRect = RectF()
    private val nextRect = RectF()

    // Path绘图
    private val playPath = Path()
    private val pausePath = Path()
    private val prevPath = Path()
    private val nextPath = Path()

    // 安全区域
    private var safeLeft = 0
    private var safeRight = 0
    private var safeTop = 0

    private val dp: Float
        get() = resources.displayMetrics.density

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

        btnBgPaint.isAntiAlias = true
        btnPaint.isAntiAlias = true
        btnPaint.style = Paint.Style.FILL

        progressBgPaint.color = Color.parseColor("#1A555566")
        progressBgPaint.strokeCap = Paint.Cap.ROUND
        progressPaint.strokeCap = Paint.Cap.ROUND
    }

    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
        super.onSizeChanged(w, h, oldw, oldh)
        accentGradient.setLocalMatrix(Matrix().apply {
            setRectToRect(RectF(0f, 0f, w.toFloat(), h.toFloat()),
                RectF(0f, 0f, w.toFloat(), h.toFloat()), Matrix.ScaleToFit.FILL)
        })

        val btnSize = 32 * dp
        val gap = 4 * dp
        val rightMargin = w.toFloat() - 8 * dp
        var rx = rightMargin - btnSize
        nextRect.set(rx, (h - btnSize) / 2f, rx + btnSize, (h + btnSize) / 2f)
        rx -= (btnSize + gap)
        playRect.set(rx, (h - btnSize) / 2f, rx + btnSize, (h + btnSize) / 2f)
        rx -= (btnSize + gap)
        prevRect.set(rx, (h - btnSize) / 2f, rx + btnSize, (h + btnSize) / 2f)

        // 构建按钮Path（居中显示）
        _buildBtnPaths(btnSize)
    }

    private fun _buildBtnPaths(size: Float) {
        val half = size / 2f
        val triSize = size * 0.3f
        val midH = triSize * 0.5f

        // 上一首：两个向左三角
        prevPath.reset()
        for (i in 0..1) {
            val ox = -triSize * 0.7f + i * (triSize * 0.8f)
            prevPath.moveTo(half + ox, half - midH)
            prevPath.lineTo(half + ox - triSize, half)
            prevPath.lineTo(half + ox, half + midH)
            prevPath.close()
        }

        // 下一首：两个向右三角
        nextPath.reset()
        for (i in 0..1) {
            val ox = triSize * 1.2f - i * (triSize * 0.8f)
            nextPath.moveTo(half - ox, half - midH)
            nextPath.lineTo(half - ox + triSize, half)
            nextPath.lineTo(half - ox, half + midH)
            nextPath.close()
        }

        // 播放：三角
        playPath.reset()
        playPath.moveTo(half - triSize * 0.4f, half - triSize * 0.55f)
        playPath.lineTo(half + triSize * 0.6f, half)
        playPath.lineTo(half - triSize * 0.4f, half + triSize * 0.55f)
        playPath.close()

        // 暂停：两条竖杠
        val barW = triSize * 0.3f
        val barH = triSize * 0.6f
        val barGap = triSize * 0.2f
        pausePath.reset()
        pausePath.addRect(half - barGap - barW, half - barH, half - barGap, half + barH, Path.Direction.CW)
        pausePath.addRect(half + barGap, half - barH, half + barGap + barW, half + barH, Path.Direction.CW)
    }

    override fun onApplyWindowInsets(insets: WindowInsets): WindowInsets {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val cutout = insets.displayCutout
            if (cutout != null) {
                safeLeft = cutout.safeInsetLeft
                safeRight = cutout.safeInsetRight
                safeTop = cutout.safeInsetTop
            } else {
                safeLeft = insets.systemWindowInsetLeft
                safeRight = insets.systemWindowInsetRight
                safeTop = insets.systemWindowInsetTop
            }
        } else {
            safeLeft = insets.systemWindowInsetLeft
            safeRight = insets.systemWindowInsetRight
            safeTop = insets.systemWindowInsetTop
        }
        requestLayout()
        return super.onApplyWindowInsets(insets)
    }

    override fun onDraw(canvas: Canvas) {
        val w = width.toFloat()
        val h = height.toFloat()
        val d = dp

        // ── 背景 ──
        canvas.drawRect(0f, 0f, w, h, bgPaint)

        // ── 底部进度条（细线） ──
        val progressY = h - 2 * d
        progressBgPaint.strokeWidth = 1.5f * d
        canvas.drawLine(0f, progressY, w, progressY, progressBgPaint)

        val fraction = if (durationMs > 0) (positionMs.toFloat() / durationMs).coerceIn(0f, 1f) else 0f
        if (fraction > 0) {
            progressPaint.shader = accentGradient
            progressPaint.strokeWidth = 1.5f * d
            canvas.drawLine(0f, progressY, w * fraction, progressY, progressPaint)
            progressPaint.shader = null
        }

        // ── 左侧：封面圆 + 歌名 ──
        val leftEdge = (safeLeft + 6).coerceAtLeast(6).toFloat() * d
        val artSize = 28 * d
        val artY = (h - artSize) / 2f
        val artCx = leftEdge + artSize / 2
        val artCy = artY + artSize / 2

        // 封面圆
        btnBgPaint.color = Color.parseColor("#1AFF6B35")
        canvas.drawCircle(artCx, artCy, artSize / 2, btnBgPaint)
        // 音符图标（用Path画）
        btnPaint.color = Color.parseColor("#F0F0F5")
        btnPaint.strokeWidth = 1.5f * d
        btnPaint.style = Paint.Style.STROKE
        _drawNote(canvas, artCx, artCy, artSize * 0.3f, d)
        btnPaint.style = Paint.Style.FILL

        // 歌名
        val titleX = leftEdge + artSize + 8 * d
        val maxTitleW = prevRect.left - titleX - 4 * d
        textPaint.textSize = 12 * d
        val displayTitle = if (textPaint.measureText(title) > maxTitleW) {
            var t = title
            while (textPaint.measureText("$t…") > maxTitleW && t.length > 1)
                t = t.substring(0, t.length - 1)
            "$t…"
        } else title
        canvas.drawText(displayTitle, titleX, artCy + 4 * d, textPaint)

        // ── 右侧控制按钮（圆形背景 + Path图标） ──
        val btnRadius = nextRect.width() / 2f

        // 上一首
        btnBgPaint.color = Color.parseColor("#0AFFFFFF")
        canvas.drawCircle(prevRect.centerX(), prevRect.centerY(), btnRadius, btnBgPaint)
        btnPaint.color = Color.parseColor("#D0F0F0F5")
        canvas.drawPath(prevPath, btnPaint)

        // 播放/暂停（实心高亮）
        btnBgPaint.color = Color.parseColor("#1AFF6B35")
        canvas.drawCircle(playRect.centerX(), playRect.centerY(), btnRadius, btnBgPaint)
        btnPaint.color = Color.parseColor("#F0F0F5")
        canvas.drawPath(if (isPlaying) pausePath else playPath, btnPaint)

        // 下一首
        btnBgPaint.color = Color.parseColor("#0AFFFFFF")
        canvas.drawCircle(nextRect.centerX(), nextRect.centerY(), btnRadius, btnBgPaint)
        btnPaint.color = Color.parseColor("#D0F0F0F5")
        canvas.drawPath(nextPath, btnPaint)
    }

    private fun _drawNote(canvas: Canvas, cx: Float, cy: Float, size: Float, d: Float) {
        val path = Path()
        path.moveTo(cx - size * 0.3f, cy - size * 0.5f)
        path.lineTo(cx + size * 0.5f, cy - size * 0.8f)
        path.lineTo(cx + size * 0.5f, cy + size * 0.2f)
        canvas.drawPath(path, btnPaint)
        canvas.drawCircle(cx - size * 0.3f, cy + size * 0.2f, size * 0.2f, btnPaint)
        canvas.drawCircle(cx + size * 0.5f, cy + size * 0.2f, size * 0.2f, btnPaint)
    }

    // ── 触摸事件 ──
    override fun onTouchEvent(event: MotionEvent): Boolean {
        if (event.action == MotionEvent.ACTION_UP) {
            val x = event.x
            val y = event.y
            when {
                prevRect.contains(x, y) -> onPrev?.invoke()
                playRect.contains(x, y) -> onPlayPause?.invoke()
                nextRect.contains(x, y) -> onNext?.invoke()
            }
            return true
        }
        return true
    }
}
