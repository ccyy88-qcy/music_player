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

    // ===== 展开/折叠状态 =====
    private var expanded = false

    fun toggleExpand() { expanded = !expanded; postInvalidate() }
    fun collapse() { expanded = false; postInvalidate() }
    fun isExpanded() = expanded

    // ===== 绘制 =====
    private val bgPaint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val textPaint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val subTextPaint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val btnBgPaint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val btnPaint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val progressPaint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val accentGradient: LinearGradient

    // 按钮触摸区域（展开时可用）
    private val prevRect = RectF()
    private val playRect = RectF()
    private val nextRect = RectF()
    private var hasButtons = false

    // Path绘图
    private val playPath = Path()
    private val pausePath = Path()
    private val prevPath = Path()
    private val nextPath = Path()

    // 按钮尺寸缓存
    private var btnSize = 0f
    private var safeLeft = 0
    private var safeRight = 0

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
        subTextPaint.color = Color.parseColor("#88889A")
        subTextPaint.isAntiAlias = true
        btnBgPaint.isAntiAlias = true
        btnPaint.isAntiAlias = true
        btnPaint.style = Paint.Style.FILL
        progressPaint.strokeCap = Paint.Cap.ROUND
    }

    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
        super.onSizeChanged(w, h, oldw, oldh)
        accentGradient.setLocalMatrix(Matrix().apply {
            setRectToRect(RectF(0f, 0f, w.toFloat(), h.toFloat()),
                RectF(0f, 0f, w.toFloat(), h.toFloat()), Matrix.ScaleToFit.FILL)
        })

        btnSize = 30 * dp
        val gap = 4 * dp
        val rightMargin = w.toFloat() - 12 * dp
        var rx = rightMargin - btnSize
        nextRect.set(rx, (h - btnSize) / 2f, rx + btnSize, (h + btnSize) / 2f)
        rx -= (btnSize + gap)
        playRect.set(rx, (h - btnSize) / 2f, rx + btnSize, (h + btnSize) / 2f)
        rx -= (btnSize + gap)
        prevRect.set(rx, (h - btnSize) / 2f, rx + btnSize, (h + btnSize) / 2f)
        hasButtons = prevRect.left > 40 * dp

        _buildBtnPaths(btnSize)
    }

    private fun _buildBtnPaths(size: Float) {
        val half = size / 2f
        val triSize = size * 0.3f
        val midH = triSize * 0.5f

        prevPath.reset()
        for (i in 0..1) {
            val ox = -triSize * 0.7f + i * (triSize * 0.8f)
            prevPath.moveTo(half + ox, half - midH)
            prevPath.lineTo(half + ox - triSize, half)
            prevPath.lineTo(half + ox, half + midH)
            prevPath.close()
        }
        nextPath.reset()
        for (i in 0..1) {
            val ox = triSize * 1.2f - i * (triSize * 0.8f)
            nextPath.moveTo(half - ox, half - midH)
            nextPath.lineTo(half - ox + triSize, half)
            nextPath.lineTo(half - ox, half + midH)
            nextPath.close()
        }
        playPath.reset()
        playPath.moveTo(half - triSize * 0.4f, half - triSize * 0.55f)
        playPath.lineTo(half + triSize * 0.6f, half)
        playPath.lineTo(half - triSize * 0.4f, half + triSize * 0.55f)
        playPath.close()
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
            } else {
                safeLeft = insets.systemWindowInsetLeft
                safeRight = insets.systemWindowInsetRight
            }
        } else {
            safeLeft = insets.systemWindowInsetLeft
            safeRight = insets.systemWindowInsetRight
        }
        requestLayout()
        return super.onApplyWindowInsets(insets)
    }

    override fun onDraw(canvas: Canvas) {
        val w = width.toFloat()
        val h = height.toFloat()
        val d = dp
        val radius = 12 * d

        // ── 圆角背景 ──
        val bgPath = Path().apply { addRoundRect(RectF(0f, 0f, w, h), radius, radius, Path.Direction.CW) }
        canvas.drawPath(bgPath, bgPaint)

        // ── 底部进度线 ──
        val progressY = h - 1.5f * d
        val fraction = if (durationMs > 0) (positionMs.toFloat() / durationMs).coerceIn(0f, 1f) else 0f
        if (fraction > 0) {
            progressPaint.shader = accentGradient
            progressPaint.strokeWidth = 1.5f * d
            canvas.drawLine(radius, progressY, radius + (w - 2 * radius) * fraction, progressY, progressPaint)
            progressPaint.shader = null
        }

        // ── 左侧音符图标 ──
        val leftEdge = 10 * d
        val artSize = 22 * d
        val artY = (h - artSize) / 2f
        val artCx = leftEdge + artSize / 2
        val artCy = artY + artSize / 2

        btnBgPaint.color = Color.parseColor("#1AFF6B35")
        canvas.drawCircle(artCx, artCy, artSize / 2, btnBgPaint)
        btnPaint.color = Color.parseColor("#F0F0F5")
        btnPaint.strokeWidth = 1.2f * d
        btnPaint.style = Paint.Style.STROKE
        val notePath = Path().apply {
            moveTo(artCx - artSize * 0.2f, artCy - artSize * 0.4f)
            lineTo(artCx + artSize * 0.4f, artCy - artSize * 0.6f)
            lineTo(artCx + artSize * 0.4f, artCy + artSize * 0.15f)
        }
        canvas.drawPath(notePath, btnPaint)
        canvas.drawCircle(artCx - artSize * 0.2f, artCy + artSize * 0.15f, artSize * 0.15f, btnPaint)
        canvas.drawCircle(artCx + artSize * 0.4f, artCy + artSize * 0.15f, artSize * 0.15f, btnPaint)
        btnPaint.style = Paint.Style.FILL

        if (expanded && hasButtons) {
            // ── 展开态：显示歌名 + 按钮 ──
            // 歌名
            val maxTextW = prevRect.left - (leftEdge + artSize + 8 * d) - 4 * d
            textPaint.textSize = 12 * d
            val displayTitle = _ellipsize(title, textPaint, maxTextW)
            canvas.drawText(displayTitle, leftEdge + artSize + 8 * d, artCy + 4 * d, textPaint)

            // 按钮
            val btnRadius = nextRect.width() / 2f
            btnBgPaint.color = Color.parseColor("#0AFFFFFF")
            canvas.drawCircle(prevRect.centerX(), prevRect.centerY(), btnRadius, btnBgPaint)
            btnPaint.color = Color.parseColor("#D0F0F0F5")
            canvas.drawPath(prevPath, btnPaint)

            btnBgPaint.color = Color.parseColor("#1AFF6B35")
            canvas.drawCircle(playRect.centerX(), playRect.centerY(), btnRadius, btnBgPaint)
            btnPaint.color = Color.parseColor("#F0F0F5")
            canvas.drawPath(if (isPlaying) pausePath else playPath, btnPaint)

            btnBgPaint.color = Color.parseColor("#0AFFFFFF")
            canvas.drawCircle(nextRect.centerX(), nextRect.centerY(), btnRadius, btnBgPaint)
            btnPaint.color = Color.parseColor("#D0F0F0F5")
            canvas.drawPath(nextPath, btnPaint)
        } else {
            // ── 折叠态：只显示歌名+歌手 ──
            val titleX = leftEdge + artSize + 8 * d
            val maxTextW = w - titleX - 10 * d
            textPaint.textSize = 12 * d
            subTextPaint.textSize = 9 * d
            val displayTitle = _ellipsize(title, textPaint, maxTextW)
            val displayArtist = if (artist.isNotEmpty()) _ellipsize(artist, subTextPaint, maxTextW) else ""
            if (displayArtist.isNotEmpty() && textPaint.measureText("$displayTitle - $displayArtist") < maxTextW) {
                canvas.drawText("$displayTitle - $displayArtist", titleX, artCy + 4 * d, subTextPaint)
            } else {
                canvas.drawText(displayTitle, titleX, artCy + 4 * d, textPaint)
            }
            // 小箭头提示可展开
            btnPaint.color = Color.parseColor("#60FFFFFF")
            btnPaint.textSize = 10 * d
            canvas.drawText(">", w - 12 * d, artCy + 4 * d, btnPaint)
        }
    }

    private fun _ellipsize(s: String, paint: Paint, maxW: Float): String {
        if (paint.measureText(s) <= maxW) return s
        var t = s
        while (paint.measureText("$t…") > maxW && t.length > 1) t = t.substring(0, t.length - 1)
        return "$t…"
    }

    // ── 触摸事件 ──
    override fun onTouchEvent(event: MotionEvent): Boolean {
        if (event.action == MotionEvent.ACTION_UP) {
            val x = event.x
            val y = event.y
            if (expanded && hasButtons) {
                when {
                    prevRect.contains(x, y) -> { onPrev?.invoke(); return true }
                    playRect.contains(x, y) -> { onPlayPause?.invoke(); return true }
                    nextRect.contains(x, y) -> { onNext?.invoke(); return true }
                }
            }
            // 点击任意位置切换展开/折叠
            toggleExpand()
            return true
        }
        return true
    }
}
