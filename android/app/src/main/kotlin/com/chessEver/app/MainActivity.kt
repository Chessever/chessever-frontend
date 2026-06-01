package com.chessEver.app

import android.app.PictureInPictureParams
import android.content.Context
import android.content.res.Configuration
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.Typeface
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.Rational
import android.util.Log
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlin.math.max
import kotlin.math.min
import okhttp3.Call
import okhttp3.Callback
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import org.json.JSONArray
import org.json.JSONObject
import java.io.IOException

class MainActivity : FlutterActivity() {
  private var pipChannel: MethodChannel? = null
  private var pipPayload: MutableMap<String, Any?>? = null
  private var pipOverlay: ChessPipOverlayView? = null
  private val mainHandler = Handler(Looper.getMainLooper())
  private val httpClient = OkHttpClient()
  private var pollRunnable: Runnable? = null
  private var activePollCall: Call? = null

  override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    pipChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.chessever/pip")
    pipChannel?.setMethodCallHandler { call, result ->
      when (call.method) {
        "setActiveGame" -> {
          @Suppress("UNCHECKED_CAST")
          val args = call.arguments as? Map<String, Any?>
          if (args == null || args["eligible"] != true) {
            clearPipState()
          } else {
            pipPayload = args.toMutableMap()
            pipOverlay?.payload = pipPayload
            pipOverlay?.invalidate()
            if (isCurrentlyInPip()) startNativePollingIfPossible()
          }
          result.success(null)
        }
        "updatePosition" -> {
          @Suppress("UNCHECKED_CAST")
          val args = call.arguments as? Map<String, Any?>
          if (args == null || args["eligible"] != true) {
            clearPipState()
          } else {
            mergePayload(args)
            pipOverlay?.payload = pipPayload
            pipOverlay?.invalidate()
            if (isCurrentlyInPip()) startNativePollingIfPossible()
          }
          result.success(null)
        }
        "enterIfEligible" -> result.success(enterPipIfEligible())
        "clearActiveGame" -> {
          clearPipState()
          result.success(null)
        }
        else -> result.notImplemented()
      }
    }
  }

  override fun onCreate(savedInstanceState: Bundle?) {
    super.onCreate(savedInstanceState)
  }

  override fun onUserLeaveHint() {
    enterPipIfEligible()
    super.onUserLeaveHint()
  }

  override fun onPictureInPictureModeChanged(
    isInPictureInPictureMode: Boolean,
    newConfig: Configuration
  ) {
    super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
    pipOverlay?.visibility = if (isInPictureInPictureMode) View.VISIBLE else View.GONE
    if (isInPictureInPictureMode) {
      startNativePollingIfPossible()
    } else {
      stopNativePolling()
      removePipOverlay()
    }
    pipChannel?.invokeMethod(
      "onPipModeChanged",
      mapOf("isInPip" to isInPictureInPictureMode)
    )
  }

  override fun onDestroy() {
    stopNativePolling()
    super.onDestroy()
  }

  private fun isCurrentlyInPip(): Boolean {
    return Build.VERSION.SDK_INT >= Build.VERSION_CODES.N && isInPictureInPictureMode
  }

  private fun enterPipIfEligible(): Boolean {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return false
    val payload = pipPayload ?: return false
    if (payload["eligible"] != true) return false
    if (isInPictureInPictureMode) return true

    ensurePipOverlay(payload)
    val paramsBuilder = PictureInPictureParams.Builder()
      .setAspectRatio(Rational(1, 1))
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
      paramsBuilder.setSeamlessResizeEnabled(true)
    }
    return try {
      enterPictureInPictureMode(paramsBuilder.build())
    } catch (e: Exception) {
      Log.w("ChessPiP", "Failed to enter picture-in-picture", e)
      removePipOverlay()
      false
    }
  }

  private fun ensurePipOverlay(payload: MutableMap<String, Any?>) {
    val content = findViewById<ViewGroup>(android.R.id.content)
    val existing = pipOverlay
    if (existing != null && existing.parent != null) {
      existing.payload = payload
      existing.visibility = View.VISIBLE
      existing.invalidate()
      return
    }
    val overlay = ChessPipOverlayView(this).apply {
      this.payload = payload
      layoutParams = FrameLayout.LayoutParams(
        FrameLayout.LayoutParams.MATCH_PARENT,
        FrameLayout.LayoutParams.MATCH_PARENT
      )
      setBackgroundColor(Color.BLACK)
      visibility = View.VISIBLE
    }
    pipOverlay = overlay
    content.addView(overlay)
  }

  private fun clearPipState() {
    pipPayload = null
    stopNativePolling()
    removePipOverlay()
  }

  private fun removePipOverlay() {
    val overlay = pipOverlay ?: return
    (overlay.parent as? ViewGroup)?.removeView(overlay)
    pipOverlay = null
  }

  private fun mergePayload(update: Map<String, Any?>) {
    val merged = pipPayload ?: mutableMapOf()
    for ((key, value) in update) {
      merged[key] = value
    }
    pipPayload = merged
  }

  private fun startNativePollingIfPossible() {
    if (pollRunnable != null) return
    if (pollingConfig() == null) {
      Log.d("ChessPiP", "Native polling unavailable: missing Supabase config")
      return
    }

    val runnable = object : Runnable {
      override fun run() {
        pollLatestGame()
        mainHandler.postDelayed(this, 4_000L)
      }
    }
    pollRunnable = runnable
    mainHandler.post(runnable)
  }

  private fun stopNativePolling() {
    pollRunnable?.let { mainHandler.removeCallbacks(it) }
    pollRunnable = null
    activePollCall?.cancel()
    activePollCall = null
  }

  private data class PollingConfig(
    val gameId: String,
    val url: String,
    val anonKey: String,
    val bearer: String,
  )

  private fun pollingConfig(): PollingConfig? {
    val payload = pipPayload ?: return null
    val gameId = payload["gameId"] as? String ?: return null
    val supabaseUrl = payload["supabaseUrl"] as? String ?: return null
    val anonKey = payload["supabaseAnonKey"] as? String ?: return null
    if (gameId.isBlank() || supabaseUrl.isBlank() || anonKey.isBlank()) return null

    val accessToken = payload["supabaseAccessToken"] as? String
    return PollingConfig(
      gameId = gameId,
      url = supabaseUrl.trimEnd('/'),
      anonKey = anonKey,
      bearer = accessToken?.takeIf { it.isNotBlank() } ?: anonKey,
    )
  }

  private fun pollLatestGame() {
    val config = pollingConfig() ?: return
    val url = "${config.url}/rest/v1/games".toHttpUrlOrNull()
      ?.newBuilder()
      ?.addQueryParameter(
        "select",
        "fen,last_move,last_move_time,last_clock_white,last_clock_black,status",
      )
      ?.addQueryParameter("id", "eq.${config.gameId}")
      ?.addQueryParameter("limit", "1")
      ?.build()
      ?: return

    val request = Request.Builder()
      .url(url)
      .get()
      .header("apikey", config.anonKey)
      .header("Authorization", "Bearer ${config.bearer}")
      .header("Accept", "application/json")
      .build()

    activePollCall?.cancel()
    activePollCall = httpClient.newCall(request).also { call ->
      call.enqueue(object : Callback {
        override fun onFailure(call: Call, e: IOException) {
          if (!call.isCanceled()) Log.w("ChessPiP", "Native poll failed", e)
        }

        override fun onResponse(call: Call, response: Response) {
          response.use {
            if (!it.isSuccessful) {
              Log.w("ChessPiP", "Native poll HTTP ${it.code}")
              return
            }
            val body = it.body?.string() ?: return
            val row = JSONArray(body).optJSONObject(0) ?: return
            mainHandler.post { mergeLiveRow(row) }
          }
        }
      })
    }
  }

  private fun mergeLiveRow(row: JSONObject) {
    val payload = pipPayload ?: return

    if (row.has("fen") && !row.isNull("fen")) {
      row.optString("fen").takeIf { it.isNotBlank() }?.let { payload["fen"] = it }
    }
    if (row.has("last_move") && !row.isNull("last_move")) {
      row.optString("last_move").takeIf { it.isNotBlank() }?.let {
        payload["lastMoveUci"] = it
        payload["lastMove"] = it
      }
    }
    if (row.has("last_move_time") && !row.isNull("last_move_time")) {
      row.optString("last_move_time").takeIf { it.isNotBlank() }?.let {
        payload["lastMoveTime"] = it
      }
    }
    if (row.has("last_clock_white") && !row.isNull("last_clock_white")) {
      val seconds = row.optInt("last_clock_white")
      payload["whiteClockSeconds"] = seconds
      payload["whiteClock"] = formatClock(seconds)
    }
    if (row.has("last_clock_black") && !row.isNull("last_clock_black")) {
      val seconds = row.optInt("last_clock_black")
      payload["blackClockSeconds"] = seconds
      payload["blackClock"] = formatClock(seconds)
    }
    if (row.has("status") && !row.isNull("status")) {
      payload["status"] = row.optString("status")
    }

    pipOverlay?.payload = payload
    pipOverlay?.invalidate()
  }

  private fun formatClock(seconds: Int): String {
    val clamped = max(0, seconds)
    val hours = clamped / 3600
    val minutes = (clamped % 3600) / 60
    val secs = clamped % 60
    return if (hours > 0) {
      "%d:%02d:%02d".format(hours, minutes, secs)
    } else {
      "%d:%02d".format(minutes, secs)
    }
  }
}

private class ChessPipOverlayView(context: Context) : View(context) {
  var payload: Map<String, Any?>? = null

  private val pieceCache = mutableMapOf<String, Bitmap?>()
  private val bgPaint = Paint().apply { color = Color.rgb(10, 10, 12) }
  private val textPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
    color = Color.WHITE
    typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
  }
  private val secondaryPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
    color = Color.rgb(185, 185, 190)
    typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
  }

  override fun onDraw(canvas: Canvas) {
    super.onDraw(canvas)
    val data = payload ?: return
    canvas.drawRect(0f, 0f, width.toFloat(), height.toFloat(), bgPaint)

    val side = min(width, height).toFloat()
    val left = (width - side) / 2f
    val headerH = side * 0.07f
    val footerH = side * 0.07f
    val evalW = side * 0.028f
    val evalGap = side * 0.018f
    val horizontalMargin = side * 0.06f
    val maxBoardWidth = side - horizontalMargin * 2f - evalW - evalGap
    val maxBoardHeight = side - headerH - footerH - side * 0.025f
    val actualBoardSize = min(maxBoardWidth, maxBoardHeight)
    val groupWidth = evalW + evalGap + actualBoardSize
    val groupLeft = left + (side - groupWidth) / 2f
    val totalHeight = headerH + actualBoardSize + footerH
    val top = (height - totalHeight) / 2f
    val boardLeft = groupLeft + evalW + evalGap
    val boardTop = top + headerH

    drawPlayerRow(
      canvas,
      data,
      isWhite = false,
      x = boardLeft,
      y = top,
      width = actualBoardSize,
      height = headerH,
    )
    drawEvalBar(
      canvas,
      x = groupLeft,
      y = boardTop,
      width = evalW,
      height = actualBoardSize,
      evalCp = (data["evalCp"] as? Number)?.toDouble(),
      mate = (data["mate"] as? Number)?.toInt()
    )
    drawBoard(
      canvas,
      fen = data["fen"] as? String ?: "",
      lastMove = data["lastMoveUci"] as? String,
      x = boardLeft,
      y = boardTop,
      size = actualBoardSize,
      boardThemeIndex = (data["boardThemeIndex"] as? Number)?.toInt() ?: 0,
    )
    drawPlayerRow(
      canvas,
      data,
      isWhite = true,
      x = boardLeft,
      y = boardTop + actualBoardSize,
      width = actualBoardSize,
      height = footerH,
    )
  }

  private fun drawPlayerRow(
    canvas: Canvas,
    data: Map<String, Any?>,
    isWhite: Boolean,
    x: Float,
    y: Float,
    width: Float,
    height: Float
  ) {
    val prefix = if (isWhite) "white" else "black"
    val name = data["${prefix}Name"] as? String ?: ""
    val title = data["${prefix}Title"] as? String ?: ""
    val rating = (data["${prefix}Rating"] as? Number)?.toInt()?.takeIf { it > 0 }?.toString() ?: ""
    val fed = (data["${prefix}Fed"] as? String ?: "").uppercase()
    val clock = data["${prefix}Clock"] as? String ?: ""
    val nameText = listOf(title, name, rating).filter { it.isNotBlank() }.joinToString(" ")

    textPaint.textSize = height * 0.48f
    secondaryPaint.textSize = height * 0.42f
    val flagW = if (fed.isNotBlank()) height * 0.7f else 0f
    if (fed.isNotBlank()) {
      val flagRect = RectF(x, y + height * 0.22f, x + flagW, y + height * 0.78f)
      Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.rgb(28, 174, 212) }.also {
        canvas.drawRoundRect(flagRect, 4f, 4f, it)
      }
      val fp = Paint(secondaryPaint).apply {
        color = Color.WHITE
        textAlign = Paint.Align.CENTER
        textSize = height * 0.22f
      }
      canvas.drawText(fed.take(3), flagRect.centerX(), flagRect.centerY() - (fp.descent() + fp.ascent()) / 2, fp)
    }

    val clockW = if (clock.isNotBlank()) textPaint.measureText(clock) + height * 0.5f else 0f
    if (clock.isNotBlank()) {
      val clockRect = RectF(x + width - clockW, y, x + width, y + height)
      Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.rgb(32, 169, 210) }.also {
        if (!isWhite) canvas.drawRect(clockRect, it)
      }
      val cp = Paint(textPaint).apply {
        color = Color.WHITE
        textAlign = Paint.Align.CENTER
        textSize = height * 0.52f
      }
      canvas.drawText(clock, clockRect.centerX(), y + height * 0.66f, cp)
    }

    val nameX = x + flagW + if (flagW > 0f) height * 0.18f else 0f
    val maxNameW = width - (nameX - x) - clockW - height * 0.15f
    drawFittedText(canvas, nameText, nameX, y + height * 0.68f, maxNameW, textPaint)
  }

  private fun drawBoard(
    canvas: Canvas,
    fen: String,
    lastMove: String?,
    x: Float,
    y: Float,
    size: Float,
    boardThemeIndex: Int
  ) {
    val board = parseFenBoard(fen)
    val square = size / 8f
    val (light, dark) = boardThemeColors(boardThemeIndex)
    val lightPaint = Paint().apply { color = light }
    val darkPaint = Paint().apply { color = dark }
    val fromTo = parseUciSquares(lastMove)
    val from = fromTo.getOrNull(0)
    val to = fromTo.getOrNull(1)
    val fromPaint = Paint().apply { color = Color.argb(115, 255, 211, 52) }
    val toPaint = Paint().apply { color = Color.argb(115, 89, 139, 232) }

    for (rank in 0 until 8) {
      for (file in 0 until 8) {
        val left = x + file * square
        val top = y + rank * square
        canvas.drawRect(left, top, left + square, top + square, if ((rank + file) % 2 == 0) lightPaint else darkPaint)
        val sq = BoardSquare(file, rank)
        if (sq == from) canvas.drawRect(left, top, left + square, top + square, fromPaint)
        if (sq == to) canvas.drawRect(left, top, left + square, top + square, toPaint)
        val piece = board[rank][file]
        if (piece != '\u0000') {
          val bitmap = loadPieceBitmap(piece)
          val inset = square * 0.07f
          val rect = RectF(left + inset, top + inset, left + square - inset, top + square - inset)
          if (bitmap != null) {
            canvas.drawBitmap(bitmap, null, rect, null)
          } else {
            val fp = Paint(Paint.ANTI_ALIAS_FLAG).apply {
              color = if (piece.isUpperCase()) Color.WHITE else Color.BLACK
              textAlign = Paint.Align.CENTER
              typeface = Typeface.DEFAULT_BOLD
              textSize = square * 0.58f
            }
            canvas.drawText(piece.uppercaseChar().toString(), rect.centerX(), rect.centerY() - (fp.descent() + fp.ascent()) / 2, fp)
          }
        }
      }
    }
  }

  private fun drawEvalBar(canvas: Canvas, x: Float, y: Float, width: Float, height: Float, evalCp: Double?, mate: Int?) {
    val ratio = evalToRatio(evalCp, mate)
    val bg = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.rgb(12, 12, 12) }
    val white = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.WHITE }
    canvas.drawRect(x, y, x + width, y + height, bg)
    canvas.drawRect(x, y + height * (1f - ratio), x + width, y + height, white)
    val label = formatEval(evalCp, mate)
    val labelPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
      color = Color.WHITE
      textSize = width * 0.75f
      typeface = Typeface.DEFAULT_BOLD
      textAlign = Paint.Align.CENTER
    }
    val labelBg = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.rgb(32, 169, 210) }
    val labelH = width * 1.35f
    val labelY = y + height * (1f - ratio)
    canvas.drawRect(x - width * 0.25f, labelY - labelH / 2, x + width * 1.25f, labelY + labelH / 2, labelBg)
    canvas.drawText(label, x + width / 2, labelY - (labelPaint.descent() + labelPaint.ascent()) / 2, labelPaint)
  }

  private fun drawFittedText(canvas: Canvas, text: String, x: Float, baseline: Float, maxWidth: Float, paint: Paint) {
    if (text.isBlank() || maxWidth <= 0f) return
    val p = Paint(paint)
    val measured = p.measureText(text)
    if (measured > maxWidth) {
      p.textSize *= max(0.55f, maxWidth / measured)
    }
    canvas.save()
    canvas.clipRect(x, baseline - p.textSize, x + maxWidth, baseline + p.textSize * 0.3f)
    canvas.drawText(text, x, baseline, p)
    canvas.restore()
  }

  private fun parseFenBoard(fen: String): Array<CharArray> {
    val ranks = fen.split(" ").firstOrNull()?.split("/") ?: emptyList()
    if (ranks.size != 8) return defaultBoard()
    val board = Array(8) { CharArray(8) { '\u0000' } }
    for ((rankIndex, rank) in ranks.withIndex()) {
      var fileIndex = 0
      for (ch in rank) {
        if (ch.isDigit()) {
          fileIndex += ch.digitToInt()
        } else if (fileIndex in 0..7) {
          board[rankIndex][fileIndex] = ch
          fileIndex++
        }
      }
    }
    return board
  }

  private fun defaultBoard(): Array<CharArray> = arrayOf(
    charArrayOf('r', 'n', 'b', 'q', 'k', 'b', 'n', 'r'),
    charArrayOf('p', 'p', 'p', 'p', 'p', 'p', 'p', 'p'),
    CharArray(8) { '\u0000' },
    CharArray(8) { '\u0000' },
    CharArray(8) { '\u0000' },
    CharArray(8) { '\u0000' },
    charArrayOf('P', 'P', 'P', 'P', 'P', 'P', 'P', 'P'),
    charArrayOf('R', 'N', 'B', 'Q', 'K', 'B', 'N', 'R')
  )

  private data class BoardSquare(val file: Int, val rank: Int)

  private fun parseUciSquares(uci: String?): List<BoardSquare> {
    if (uci == null || uci.length < 4) return emptyList()
    return listOfNotNull(squareFromAlgebraic(uci.substring(0, 2)), squareFromAlgebraic(uci.substring(2, 4)))
  }

  private fun squareFromAlgebraic(square: String): BoardSquare? {
    val file = square.getOrNull(0)?.lowercaseChar()?.code?.minus('a'.code) ?: return null
    val rankValue = square.getOrNull(1)?.digitToIntOrNull() ?: return null
    if (file !in 0..7 || rankValue !in 1..8) return null
    return BoardSquare(file, 8 - rankValue)
  }

  private fun loadPieceBitmap(piece: Char): Bitmap? {
    val resName = when (piece) {
      'K' -> "piece_wk"; 'Q' -> "piece_wq"; 'R' -> "piece_wr"; 'B' -> "piece_wb"; 'N' -> "piece_wn"; 'P' -> "piece_wp"
      'k' -> "piece_bk"; 'q' -> "piece_bq"; 'r' -> "piece_br"; 'b' -> "piece_bb"; 'n' -> "piece_bn"; 'p' -> "piece_bp"
      else -> return null
    }
    return pieceCache.getOrPut(resName) {
      val resId = context.resources.getIdentifier(resName, "drawable", context.packageName)
      if (resId == 0) null else BitmapFactory.decodeResource(context.resources, resId)
    }
  }

  private fun boardThemeColors(index: Int): Pair<Int, Int> = when (index) {
    1 -> Pair(Color.rgb(240, 217, 181), Color.rgb(181, 136, 99))
    2 -> Pair(Color.rgb(238, 238, 210), Color.rgb(118, 150, 86))
    3 -> Pair(Color.rgb(210, 210, 210), Color.rgb(150, 150, 150))
    4 -> Pair(Color.rgb(238, 214, 175), Color.rgb(198, 124, 78))
    5 -> Pair(Color.rgb(220, 204, 230), Color.rgb(136, 110, 170))
    6 -> Pair(Color.rgb(210, 222, 238), Color.rgb(112, 142, 180))
    else -> Pair(Color.rgb(210, 210, 210), Color.rgb(150, 150, 150))
  }

  private fun evalToRatio(evalCp: Double?, mate: Int?): Float {
    val eval = if (mate != null && mate != 0) {
      if (mate > 0) 10.0 else -10.0
    } else {
      (evalCp ?: 0.0) / 100.0
    }
    return (((min(10.0, max(-10.0, eval)) + 10.0) / 20.0).toFloat())
  }

  private fun formatEval(evalCp: Double?, mate: Int?): String {
    if (mate != null && mate != 0) return "M${kotlin.math.abs(mate)}"
    val eval = (evalCp ?: 0.0) / 100.0
    return (if (eval >= 0) "+" else "") + String.format("%.1f", eval)
  }
}
