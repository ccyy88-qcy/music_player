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
    private val glassPaint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val textPaint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val subTextPaint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val btnPaint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val btnBgPaint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val progressBgPaint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val progressPaint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val progressDotPaint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val accentGradient: LinearGradient
    private val dividerPaint = Paint(Paint.ANTI_ALIAS_FLAG)

    // 按钮区域
    private val prevRect = RectF()
    private val playRect = RectF()
    private val nextRect = RectF()

    // 安全区域
    private var safeLeft = 0
    private var safeRight = 0
    private var safeTop = 0

    private val dp: Float
        get() = resources.displayMetrics.density

    private var rightZoneStart = 0f

    init {
        // 深色玻璃背景
        bgPaint.color = Color.parseColor("#CC121218")

        glassPaint.color = Color.parseColor("#0AFFFFFF")

        // 渐变强调色 (AppColors.orange -> purple)
        accentGradient = LinearGradient(
            0f, 0f, 0f, 0f,
            Color.parseColor("#FF6B35"),
            Color.parseColor("#A855F7"),
            Shader.TileMode.CLAMP
        )

        textPaint.color = Color.parseColor("#F0F0F5")
        textPaint.textSize = 14 * dp
        textPaint.isAntiAlias = true

        subTextPaint.color = Color.parseColor("#88889A")
        subTextPaint.textSize = 10 * dp
        subTextPaint.isAntiAlias = true

        btnPaint.color = Color.parseColor("#F0F0F5")
        btnPaint.isAntiAlias = true
        btnPaint.style = Paint.Style.FILL

        btnBgPaint.color = Color.parseColor("#14FFFFFF")
        btnBgPaint.isAntiAlias = true

        progressBgPaint.color = Color.parseColor("#1A555566")
        progressBgPaint.strokeCap = Paint.Cap.ROUND
        progressPaint.strokeCap = Paint.Cap.ROUND
        progressDotPaint.isAntiAlias = true

        dividerPaint.color = Color.parseColor("#12FFFFFF")
        dividerPaint.strokeWidth = 0.5f * dp
    }

    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
        super.onSizeChanged(w, h, oldw, oldh)
        accentGradient.setLocalMatrix(Matrix().apply { setRectToRect(RectF(0f, 0f, w.toFloat(), h.toFloat()), RectF(0f, 0f, w.toFloat(), h.toFloat()), Matrix.ScaleToFit.FILL) })

        val btnSize = 36 * dp
        val gap = 8 * dp
        val rightMargin = (safeRight.coerceAtMost(w - 12)).toFloat()
        var rx = rightMargin - btnSize
        nextRect.set(rx, (h - btnSize) / 2f, rx + btnSize, (h + btnSize) / 2f)
        rx -= (btnSize + gap)
        playRect.set(rx, (h - btnSize) / 2f, rx + btnSize, (h + btnSize) / 2f)
        rx -= (btnSize + gap)
        prevRect.set(rx, (h - btnSize) / 2f, rx + btnSize, (h + btnSize) / 2f)

        rightZoneStart = prevRect.left - 4 * dp
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

        // 底部细线
        canvas.drawRect(0f, h - d, w, h, glassPaint)

        // 分隔线（progress上面
        dividerPaint.strokeWidth = d * 0.3f
        canvas.drawLine(0f, h - 5 * d, w, h - 5 * d, dividerPaint)

        // ── 进度条 ──
        val progressH = 3 * d
        val progressY = h - 2.5f * d
        val progressW = w - (safeLeft + safeRight).coerceAtMost(0)
        val progressX = safeLeft.toFloat()

        progressBgPaint.strokeWidth = 2 * d
        canvas.drawLine(progressX, progressY, progressX + progressW, progressY, progressBgPaint)

        val fraction = if (durationMs > 0) (positionMs.toFloat() / durationMs).coerceIn(0f, 1f) else 0f
        if (fraction > 0) {
            progressPaint.shader = accentGradient
            progressPaint.strokeWidth = 2 * d
            canvas.drawLine(progressX, progressY, progressX + progressW * fraction, progressY, progressPaint)
            progressPaint.shader = null
            // 小圆点
            val dotX = progressX + progressW * fraction
            progressDotPaint.color = Color.parseColor("#FF6B35")
            canvas.drawCircle(dotX, progressY, 3.5f * d, progressDotPaint)
            progressDotPaint.color = Color.parseColor("#30FF6B35")
            canvas.drawCircle(dotX, progressY, 7f * d, progressDotPaint)
        }

        // ── 左侧：封面占位 + 文字 ──
        val leftEdge = safeLeft.coerceAtLeast(12).toFloat() + 8 * d
        val artSize = 32 * d
        val artY = (h - artSize) / 2f

        // 封面占位圆
        btnBgPaint.color = Color.parseColor("#1AFF6B35")
        canvas.drawCircle(leftEdge + artSize / 2, artY + artSize / 2, artSize / 2, btnBgPaint)
        btnPaint.textSize = 16 * d
        canvas.drawText("♫", leftEdge + artSize / 2 - 6 * d, artY + artSize / 2 + 5 * d, btnPaint)

        // 标题 (带省略)
        val titleX = leftEdge + artSize + 12 * d
        val maxTitleW = rightZoneStart - titleX - 8 * d
        textPaint.textSize = 14 * d
        val displayTitle = if (textPaint.measureText(title) > maxTitleW) {
            // 省略
            var t = title
            while (textPaint.measureText("$t…") > maxTitleW && t.length > 1) t = t.substring(0, t.length - 1)
            "$t…"
        } else title
        canvas.drawText(displayTitle, titleX, artY + artSize / 2 + d, textPaint)

        // ── 右侧控制按钮 ──
        // 上一首
        _drawPlaybackIcon(canvas, prevRect, "◀◀", 12 * d)
        // 播放/暂停
        _drawPlayBtn(canvas, playRect, isPlaying)
        // 下一首
        _drawPlaybackIcon(canvas, nextRect, "▶▶", 12 * d)
    }

    private fun _drawPlayBtn(canvas: Canvas, rect: RectF, playing: Boolean) {
        btnBgPaint.color = Color.parseColor("#1AFF6B35")
        canvas.drawCircle(rect.centerX(), rect.centerY(), rect.width() / 2f, btnBgPaint)
        btnPaint.color = Color.parseColor("#F0F0F5")
        btnPaint.textSize = rect.width() * 0.45f
        val icon = if (playing) "⏸" else "▶"
        canvas.drawText(icon,
            rect.centerX() - btnPaint.measureText(icon) / 2f,
            rect.centerY() + btnPaint.textSize * 0.35f,
            btnPaint)
    }

    private fun _drawPlaybackIcon(canvas: Canvas, rect: RectF, icon: String, textSize: Float) {
        btnBgPaint.color = Color.parseColor("#0AFFFFFF")
        canvas.drawCircle(rect.centerX(), rect.centerY(), rect.width() / 2f, btnBgPaint)
        btnPaint.color = Color.parseColor("#C0F0F0F5")
        btnPaint.textSize = textSize
        canvas.drawText(icon,
            rect.centerX() - btnPaint.measureText(icon) / 2f,
            rect.centerY() + btnPaint.textSize * 0.35f,
            btnPaint)
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
