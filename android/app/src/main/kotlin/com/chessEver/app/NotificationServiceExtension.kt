package com.chessEver.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.Shader
import android.graphics.Typeface
import android.graphics.BitmapFactory
import android.net.Uri
import androidx.core.app.NotificationCompat
import com.onesignal.notifications.IDisplayableMutableNotification
import com.onesignal.notifications.INotificationReceivedEvent
import com.onesignal.notifications.INotificationServiceExtension
import org.json.JSONObject
import kotlin.math.max
import kotlin.math.min

/**
 * OneSignal Notification Service Extension for ChessEver
 *
 * Handles live chess game notifications with rich visual presentation:
 * - Mini chess board rendering from FEN
 * - Evaluation bar showing position advantage
 * - Player names and last move display
 * - Collapsing notifications for live updates
 */
class NotificationServiceExtension : INotificationServiceExtension {

  override fun onNotificationReceived(event: INotificationReceivedEvent) {
    val notification = event.notification
    val data = notification.additionalData
    val live = data?.optJSONObject("live_notification")

    if (live == null) {
      // Not a live notification, let OneSignal handle it normally
      return
    }

    val context = event.context
    val updated = buildLiveNotification(context, live)

    if (updated == null) {
      // Failed to build custom notification, let OneSignal handle it
      return
    }

    val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
    val gameId = live.optJSONObject("event_attributes")?.optString("game_id") ?: "game"
    val notificationId = "live_$gameId".hashCode()

    manager.notify(notificationId, updated)

    // Prevent default OneSignal notification from displaying
    event.preventDefault()
  }

  private fun buildLiveNotification(context: Context, live: JSONObject): Notification? {
    val attrs = live.optJSONObject("event_attributes") ?: return null
    val updates = live.optJSONObject("event_updates") ?: return null
    val eventType = live.optString("event", "update")

    val white = attrs.optString("player_white", "White")
    val black = attrs.optString("player_black", "Black")
    val whiteTitle = attrs.optString("white_title", "")
    val blackTitle = attrs.optString("black_title", "")
    val whiteFed = attrs.optString("white_fed", "")
    val blackFed = attrs.optString("black_fed", "")
    val whitePhoto = attrs.optString("white_photo", "")
    val blackPhoto = attrs.optString("black_photo", "")
    val eventName = attrs.optString("event_name", "")
    val roundName = attrs.optString("round_name", "")
    val gameId = attrs.optString("game_id", "")

    val lastMove = updates.optString("last_move", "...")
    val lastMoveUci = updates.optString("last_move_uci", lastMove)
    val fen = updates.optString("fen", "")
    val evalCp = if (updates.has("eval_cp") && !updates.isNull("eval_cp")) updates.optDouble("eval_cp") else null
    val evalMate = if (updates.has("eval_mate") && !updates.isNull("eval_mate")) updates.optInt("eval_mate") else null
    val whiteClockSeconds = if (updates.has("white_clock_seconds") && !updates.isNull("white_clock_seconds")) updates.optInt("white_clock_seconds") else null
    val blackClockSeconds = if (updates.has("black_clock_seconds") && !updates.isNull("black_clock_seconds")) updates.optInt("black_clock_seconds") else null
    val prettyEventName = formatEventName(eventName.ifEmpty { roundName })

    ensureChannel(context)

    // Create large icon (chess board)
    val boardBitmap = renderBoardBitmap(context, fen, 256, lastMoveUci)
    val whiteBitmap = fetchBitmap(whitePhoto)
    val blackBitmap = fetchBitmap(blackPhoto)

    // Create big picture (chess board + info panel)
    val bigPictureBitmap = renderExpandedView(
      context = context,
      fen = fen,
      white = white,
      black = black,
      lastMove = lastMove,
      evalCp = evalCp,
      evalMate = evalMate,
      eventName = prettyEventName,
      whiteClockSeconds = whiteClockSeconds,
      blackClockSeconds = blackClockSeconds,
      whitePhoto = whiteBitmap,
      blackPhoto = blackBitmap,
      lastMoveUci = lastMoveUci,
      whiteTitle = whiteTitle,
      blackTitle = blackTitle,
      whiteFed = whiteFed,
      blackFed = blackFed
    )

    // Intent to open the app
    val intent = Intent(
      Intent.ACTION_VIEW,
      Uri.parse("https://chessever.com/games/$gameId")
    ).apply {
      setPackage(context.packageName)
      flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
    }
    val pendingIntent = PendingIntent.getActivity(
      context,
      notificationId(gameId),
      intent,
      PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
    )

    // Format eval text
    val evalText = formatEval(evalCp, evalMate)

    // Build notification
    val builder = NotificationCompat.Builder(context, CHANNEL_ID)
      .setContentTitle("$white vs $black")
      .setContentText("$lastMove  $evalText")
      .setSubText(if (prettyEventName.isNotEmpty()) prettyEventName else null)
      .setSmallIcon(context.applicationInfo.icon)
      .setLargeIcon(boardBitmap)
      .setOnlyAlertOnce(true)
      .setOngoing(eventType != "end")
      .setAutoCancel(eventType == "end")
      .setCategory(NotificationCompat.CATEGORY_STATUS)
      .setPriority(NotificationCompat.PRIORITY_LOW)
      .setContentIntent(pendingIntent)
      .setGroup("live_games")
      .setGroupAlertBehavior(NotificationCompat.GROUP_ALERT_SUMMARY)

    // Set progress bar for eval
    if (evalCp != null || evalMate != null) {
      val progress = evalToProgress(evalCp, evalMate)
      builder.setProgress(100, progress, false)
    }

    // Add big picture style for expanded view
    if (bigPictureBitmap != null) {
      builder.setStyle(
        NotificationCompat.BigPictureStyle()
          .bigPicture(bigPictureBitmap)
          .bigLargeIcon(null as Bitmap?)
          .setSummaryText("$lastMove  $evalText")
      )
    }

    // Add action to end updates
    if (eventType != "end") {
      val stopIntent = Intent(context, NotificationActionReceiver::class.java).apply {
        action = "STOP_LIVE_UPDATES"
        putExtra("game_id", gameId)
      }
      val stopPendingIntent = PendingIntent.getBroadcast(
        context,
        notificationId(gameId) + 1,
        stopIntent,
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
      )
      builder.addAction(0, "Stop Updates", stopPendingIntent)
    }

    return builder.build()
  }

  private fun ensureChannel(context: Context) {
    val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
    if (manager.getNotificationChannel(CHANNEL_ID) != null) return

    val channel = NotificationChannel(
      CHANNEL_ID,
      "Live Game Updates",
      NotificationManager.IMPORTANCE_LOW
    ).apply {
      description = "Real-time updates for chess games you're following"
      setShowBadge(false)
      enableVibration(false)
      setSound(null, null)
    }
    manager.createNotificationChannel(channel)
  }

  private fun notificationId(gameId: String): Int = "live_$gameId".hashCode()

  // MARK: - Rendering

  private fun renderBoardBitmap(
    context: Context,
    fen: String,
    size: Int,
    lastMoveUci: String?
  ): Bitmap {
    val board = parseFenBoard(fen)
    val bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
    val canvas = Canvas(bitmap)
    val squareSize = size / 8f

    val lightPaint = Paint().apply { color = LIGHT_SQUARE_COLOR }
    val darkPaint = Paint().apply { color = DARK_SQUARE_COLOR }
    val highlightFromPaint = Paint().apply { color = HIGHLIGHT_FROM_COLOR }
    val highlightToPaint = Paint().apply { color = HIGHLIGHT_TO_COLOR }
    val highlights = parseUciSquares(lastMoveUci)
    val fromSquare = highlights.getOrNull(0)
    val toSquare = highlights.getOrNull(1)

    for (rank in 0 until 8) {
      for (file in 0 until 8) {
        val isLight = (rank + file) % 2 == 0
        val left = file * squareSize
        val top = rank * squareSize

        canvas.drawRect(left, top, left + squareSize, top + squareSize,
          if (isLight) lightPaint else darkPaint)

        val currentSquare = BoardSquare(file, rank)
        if (fromSquare != null && currentSquare == fromSquare) {
          canvas.drawRect(left, top, left + squareSize, top + squareSize, highlightFromPaint)
        } else if (toSquare != null && currentSquare == toSquare) {
          canvas.drawRect(left, top, left + squareSize, top + squareSize, highlightToPaint)
        }

        board?.get(rank)?.get(file)?.let { piece ->
          val pieceBitmap = loadPieceBitmap(context, piece)
          if (pieceBitmap != null) {
            val inset = squareSize * 0.08f
            val rect = RectF(
              left + inset,
              top + inset,
              left + squareSize - inset,
              top + squareSize - inset
            )
            canvas.drawBitmap(pieceBitmap, null, rect, null)
          } else {
            val x = left + squareSize / 2
            val y = top + squareSize / 2
            val fallbackPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
              textAlign = Paint.Align.CENTER
              textSize = squareSize * 0.42f
              typeface = Typeface.create(Typeface.SANS_SERIF, Typeface.BOLD)
              color = if (piece.isUpperCase()) BLACK_PIECE_TEXT_COLOR else WHITE_PIECE_TEXT_COLOR
            }
            val textY = y - (fallbackPaint.descent() + fallbackPaint.ascent()) / 2
            canvas.drawText(pieceToLetter(piece), x, textY, fallbackPaint)
          }
        }
      }
    }

    // Round corners
    return roundCorners(bitmap, size * 0.05f)
  }

  private fun renderExpandedView(
    context: Context,
    fen: String,
    white: String,
    black: String,
    lastMove: String,
    evalCp: Double?,
    evalMate: Int?,
    eventName: String,
    whiteClockSeconds: Int?,
    blackClockSeconds: Int?,
    whitePhoto: Bitmap?,
    blackPhoto: Bitmap?,
    lastMoveUci: String?,
    whiteTitle: String?,
    blackTitle: String?,
    whiteFed: String?,
    blackFed: String?
  ): Bitmap? {
    val width = 600
    val height = 280
    val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
    val canvas = Canvas(bitmap)

    // Background
    val bgPaint = Paint().apply { color = BACKGROUND_COLOR }
    canvas.drawRect(0f, 0f, width.toFloat(), height.toFloat(), bgPaint)

    // Eval bar on left
    val evalBarWidth = 16f
    val evalBarMargin = 16f
    renderEvalBar(canvas, evalBarMargin, 16f, evalBarWidth, height - 32f, evalCp, evalMate)

    // Chess board
    val boardSize = 180
    val boardX = evalBarMargin + evalBarWidth + 16f
    val boardY = (height - boardSize) / 2f
    val boardBitmap = renderBoardBitmap(context, fen, boardSize, lastMoveUci)
    canvas.drawBitmap(boardBitmap, boardX, boardY, null)

    // Text area
    val textX = boardX + boardSize + 20f
    val textWidth = width - textX - 16f

    // Event name
    val eventPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
      color = ACCENT_COLOR
      textSize = 24f
      typeface = Typeface.create(Typeface.DEFAULT, Typeface.NORMAL)
    }
    if (eventName.isNotEmpty()) {
      canvas.drawText(truncateText(eventName, eventPaint, textWidth), textX, 40f, eventPaint)
    }

    // Player names
    val playerPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
      color = TEXT_PRIMARY_COLOR
      textSize = 28f
      typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
    }
    val secondaryPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
      color = TEXT_SECONDARY_COLOR
      textSize = 28f
      typeface = Typeface.create(Typeface.DEFAULT, Typeface.NORMAL)
    }

    // Black player on top
    drawPlayerRow(
      canvas,
      textX,
      85f,
      black,
      false,
      !isWhiteAdvantage(evalCp, evalMate),
      textWidth,
      blackPhoto,
      blackClockSeconds,
      blackTitle,
      blackFed
    )
    // White player on bottom
    drawPlayerRow(
      canvas,
      textX,
      125f,
      white,
      true,
      isWhiteAdvantage(evalCp, evalMate),
      textWidth,
      whitePhoto,
      whiteClockSeconds,
      whiteTitle,
      whiteFed
    )

    // Last move
    val movePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
      color = TEXT_PRIMARY_COLOR
      textSize = 40f
      typeface = Typeface.create(Typeface.MONOSPACE, Typeface.BOLD)
    }
    canvas.drawText(lastMove, textX, 195f, movePaint)

    // Eval pill
    val evalText = formatEval(evalCp, evalMate)
    val evalPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
      color = TEXT_PRIMARY_COLOR
      textSize = 28f
      typeface = Typeface.create(Typeface.MONOSPACE, Typeface.BOLD)
    }
    val pillPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
      color = SURFACE_COLOR
    }
    val pillWidth = evalPaint.measureText(evalText) + 24f
    val pillRect = RectF(textX, 215f, textX + pillWidth, 250f)
    canvas.drawRoundRect(pillRect, 17.5f, 17.5f, pillPaint)
    canvas.drawText(evalText, textX + 12f, 242f, evalPaint)

    return bitmap
  }

  private fun drawPlayerRow(
    canvas: Canvas,
    x: Float,
    y: Float,
    name: String,
    isWhite: Boolean,
    isAdvantage: Boolean,
    maxWidth: Float,
    photo: Bitmap?,
    clockSeconds: Int?,
    title: String?,
    fed: String?
  ) {
    val avatarRadius = 12f
    val avatarCx = x + avatarRadius
    val avatarCy = y - 9f

    if (photo != null) {
      drawCircularImage(canvas, photo, avatarCx, avatarCy, avatarRadius)
    } else {
      val circlePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = if (isWhite) Color.WHITE else Color.parseColor("#262626")
        style = Paint.Style.FILL
      }
      canvas.drawCircle(avatarCx, avatarCy, avatarRadius, circlePaint)
    }

    // Border for advantage
    if (isAdvantage) {
      val borderPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = ACCENT_COLOR
        style = Paint.Style.STROKE
        strokeWidth = 2f
      }
      canvas.drawCircle(avatarCx, avatarCy, avatarRadius + 1f, borderPaint)
    }

    // Name
    val namePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
      color = if (isAdvantage) TEXT_PRIMARY_COLOR else TEXT_SECONDARY_COLOR
      textSize = 26f
      typeface = if (isAdvantage) Typeface.create(Typeface.DEFAULT, Typeface.BOLD) else Typeface.DEFAULT
    }
    val nameX = x + avatarRadius * 2 + 8f
    canvas.drawText(name, nameX, y, namePaint)

    val meta = listOfNotNull(
      title?.takeIf { it.isNotBlank() },
      fed?.takeIf { it.isNotBlank() }?.uppercase()
    ).joinToString(" • ")
    if (meta.isNotEmpty()) {
      val metaPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = TEXT_SECONDARY_COLOR
        textSize = 18f
        typeface = Typeface.create(Typeface.DEFAULT, Typeface.NORMAL)
      }
      canvas.drawText(meta, nameX, y + 20f, metaPaint)
    }

    val clockText = clockSeconds?.let { formatClock(it) }
    if (clockText != null) {
      drawClockPill(
        canvas,
        x + maxWidth - 4f,
        y - 20f,
        clockText
      )
    }
  }

  private fun renderEvalBar(
    canvas: Canvas,
    x: Float,
    y: Float,
    width: Float,
    height: Float,
    evalCp: Double?,
    evalMate: Int?
  ) {
    // Background (black side)
    val bgPaint = Paint().apply { color = EVAL_BLACK_COLOR }
    val rect = RectF(x, y, x + width, y + height)
    canvas.drawRoundRect(rect, width / 2, width / 2, bgPaint)

    // White portion
    val ratio = evalToRatio(evalCp, evalMate)
    val whiteHeight = height * ratio
    val whitePaint = Paint().apply { color = Color.WHITE }
    val whiteRect = RectF(x, y + height - whiteHeight, x + width, y + height)
    canvas.drawRoundRect(whiteRect, width / 2, width / 2, whitePaint)
  }

  // MARK: - Utilities

  private fun parseFenBoard(fen: String): Array<CharArray>? {
    if (fen.isBlank()) return defaultBoard()
    val boardPart = fen.split(" ").firstOrNull() ?: return defaultBoard()
    val ranks = boardPart.split("/")
    if (ranks.size != 8) return defaultBoard()

    val board = Array(8) { CharArray(8) { '\u0000' } }
    for ((rankIndex, rank) in ranks.withIndex()) {
      var fileIndex = 0
      for (ch in rank) {
        if (ch.isDigit()) {
          fileIndex += ch.digitToInt()
        } else if (fileIndex < 8) {
          board[rankIndex][fileIndex] = ch
          fileIndex++
        }
      }
    }
    return board
  }

  private data class BoardSquare(val file: Int, val rank: Int)

  private fun parseUciSquares(uci: String?): List<BoardSquare> {
    if (uci == null || uci.length < 4) return emptyList()
    val from = uci.substring(0, 2)
    val to = uci.substring(2, 4)
    val squares = mutableListOf<BoardSquare>()
    squareFromAlgebraic(from)?.let { squares.add(it) }
    squareFromAlgebraic(to)?.let { squares.add(it) }
    return squares
  }

  private fun squareFromAlgebraic(square: String): BoardSquare? {
    if (square.length < 2) return null
    val fileChar = square[0].lowercaseChar()
    val rankChar = square[1]
    val file = fileChar.code - 'a'.code
    val rankValue = rankChar.digitToIntOrNull() ?: return null
    if (file !in 0..7 || rankValue !in 1..8) return null
    val rank = 8 - rankValue
    return BoardSquare(file, rank)
  }

  private fun defaultBoard(): Array<CharArray> {
    return arrayOf(
      charArrayOf('r', 'n', 'b', 'q', 'k', 'b', 'n', 'r'),
      charArrayOf('p', 'p', 'p', 'p', 'p', 'p', 'p', 'p'),
      CharArray(8) { '\u0000' },
      CharArray(8) { '\u0000' },
      CharArray(8) { '\u0000' },
      CharArray(8) { '\u0000' },
      charArrayOf('P', 'P', 'P', 'P', 'P', 'P', 'P', 'P'),
      charArrayOf('R', 'N', 'B', 'Q', 'K', 'B', 'N', 'R')
    )
  }

  private fun pieceToLetter(piece: Char): String {
    return when (piece) {
      'K', 'k' -> "K"
      'Q', 'q' -> "Q"
      'R', 'r' -> "R"
      'B', 'b' -> "B"
      'N', 'n' -> "N"
      'P', 'p' -> "P"
      else -> "?"
    }
  }

  private fun formatEval(evalCp: Double?, evalMate: Int?): String {
    if (evalMate != null && evalMate != 0) {
      return if (evalMate > 0) "M$evalMate" else "M${-evalMate}"
    }
    if (evalCp != null) {
      val eval = evalCp / 100.0
      val sign = if (eval >= 0) "+" else ""
      return "$sign${String.format("%.1f", eval)}"
    }
    return "0.0"
  }

  private fun formatEventName(raw: String?): String {
    if (raw.isNullOrBlank()) return ""
    return raw
      .replace("-", " ")
      .replace("_", " ")
      .replace("/", " ")
      .split(" ")
      .filter { it.isNotBlank() }
      .joinToString(" ") { word ->
        word.lowercase().replaceFirstChar { if (it.isLowerCase()) it.titlecase() else it.toString() }
      }
  }

  private fun evalToProgress(evalCp: Double?, evalMate: Int?): Int {
    val ratio = evalToRatio(evalCp, evalMate)
    return (ratio * 100).toInt().coerceIn(0, 100)
  }

  private fun evalToRatio(evalCp: Double?, evalMate: Int?): Float {
    val eval = if (evalMate != null && evalMate != 0) {
      if (evalMate > 0) 10.0 else -10.0
    } else {
      (evalCp ?: 0.0) / 100.0
    }
    val clamped = max(-10.0, min(10.0, eval))
    return ((clamped + 10.0) / 20.0).toFloat()
  }

  private fun isWhiteAdvantage(evalCp: Double?, evalMate: Int?): Boolean {
    if (evalMate != null && evalMate != 0) return evalMate > 0
    return (evalCp ?: 0.0) >= 0
  }

  private fun truncateText(text: String, paint: Paint, maxWidth: Float): String {
    if (paint.measureText(text) <= maxWidth) return text
    var truncated = text
    while (paint.measureText("$truncated...") > maxWidth && truncated.isNotEmpty()) {
      truncated = truncated.dropLast(1)
    }
    return "$truncated..."
  }

  private fun roundCorners(bitmap: Bitmap, radius: Float): Bitmap {
    val output = Bitmap.createBitmap(bitmap.width, bitmap.height, Bitmap.Config.ARGB_8888)
    val canvas = Canvas(output)
    val paint = Paint(Paint.ANTI_ALIAS_FLAG)
    val rect = RectF(0f, 0f, bitmap.width.toFloat(), bitmap.height.toFloat())
    canvas.drawRoundRect(rect, radius, radius, paint)
    paint.xfermode = android.graphics.PorterDuffXfermode(android.graphics.PorterDuff.Mode.SRC_IN)
    canvas.drawBitmap(bitmap, 0f, 0f, paint)
    return output
  }

  private fun drawClockPill(canvas: Canvas, rightX: Float, topY: Float, text: String) {
    val textPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
      color = TEXT_PRIMARY_COLOR
      textSize = 20f
      typeface = Typeface.create(Typeface.MONOSPACE, Typeface.BOLD)
    }
    val paddingX = 10f
    val paddingY = 6f
    val textWidth = textPaint.measureText(text)
    val height = textPaint.textSize + paddingY * 2
    val width = textWidth + paddingX * 2
    val left = rightX - width
    val rect = RectF(left, topY, rightX, topY + height)

    val pillPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = SURFACE_COLOR }
    canvas.drawRoundRect(rect, height / 2, height / 2, pillPaint)

    val textY = topY + paddingY + textPaint.textSize - 4f
    canvas.drawText(text, left + paddingX, textY, textPaint)
  }

  private fun formatClock(seconds: Int): String {
    val clamped = max(0, seconds)
    val hours = clamped / 3600
    val minutes = (clamped % 3600) / 60
    val secs = clamped % 60
    return if (hours > 0) {
      String.format("%d:%02d:%02d", hours, minutes, secs)
    } else {
      String.format("%d:%02d", minutes, secs)
    }
  }

  private fun fetchBitmap(url: String): Bitmap? {
    if (url.isBlank()) return null
    synchronized(photoCache) {
      if (photoCache.containsKey(url)) {
        return photoCache[url]
      }
    }
    return try {
      val connection = java.net.URL(url).openConnection() as java.net.HttpURLConnection
      connection.connectTimeout = 1500
      connection.readTimeout = 1500
      connection.instanceFollowRedirects = true
      connection.doInput = true
      connection.connect()
      val stream = connection.inputStream
      val bitmap = android.graphics.BitmapFactory.decodeStream(stream)
      stream.close()
      synchronized(photoCache) {
        photoCache[url] = bitmap
      }
      bitmap
    } catch (e: Exception) {
      synchronized(photoCache) {
        photoCache[url] = null
      }
      null
    }
  }

  private fun drawCircularImage(
    canvas: Canvas,
    bitmap: Bitmap,
    cx: Float,
    cy: Float,
    radius: Float
  ) {
    val shader = android.graphics.BitmapShader(
      bitmap,
      android.graphics.Shader.TileMode.CLAMP,
      android.graphics.Shader.TileMode.CLAMP
    )
    val matrix = android.graphics.Matrix()
    val scale = (radius * 2) / min(bitmap.width, bitmap.height).toFloat()
    matrix.setScale(scale, scale)
    matrix.postTranslate(cx - radius, cy - radius)
    shader.setLocalMatrix(matrix)

    val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
      this.shader = shader
    }
    canvas.drawCircle(cx, cy, radius, paint)
  }

  private fun loadPieceBitmap(context: Context, piece: Char): Bitmap? {
    val resName = when (piece) {
      'K' -> "piece_wk"
      'Q' -> "piece_wq"
      'R' -> "piece_wr"
      'B' -> "piece_wb"
      'N' -> "piece_wn"
      'P' -> "piece_wp"
      'k' -> "piece_bk"
      'q' -> "piece_bq"
      'r' -> "piece_br"
      'b' -> "piece_bb"
      'n' -> "piece_bn"
      'p' -> "piece_bp"
      else -> null
    } ?: return null

    val resId = context.resources.getIdentifier(resName, "drawable", context.packageName)
    if (resId == 0) return null

    synchronized(pieceBitmapCache) {
      if (pieceBitmapCache.containsKey(resId)) {
        return pieceBitmapCache[resId]
      }
    }

    return try {
      val bitmap = BitmapFactory.decodeResource(context.resources, resId)
      synchronized(pieceBitmapCache) {
        pieceBitmapCache[resId] = bitmap
      }
      bitmap
    } catch (e: Exception) {
      synchronized(pieceBitmapCache) {
        pieceBitmapCache[resId] = null
      }
      null
    }
  }

  companion object {
    private const val CHANNEL_ID = "live_updates"
    private val photoCache = mutableMapOf<String, Bitmap?>()
    private val pieceBitmapCache = mutableMapOf<Int, Bitmap?>()

    // Design colors matching iOS
    private val BACKGROUND_COLOR = Color.parseColor("#0C0C0E")
    private val SURFACE_COLOR = Color.parseColor("#141416")
    private val ACCENT_COLOR = Color.parseColor("#0FB4E5")
    private val TEXT_PRIMARY_COLOR = Color.WHITE
    private val TEXT_SECONDARY_COLOR = Color.parseColor("#999999")
    private val HIGHLIGHT_FROM_COLOR = Color.parseColor("#4D0FB4E5")
    private val HIGHLIGHT_TO_COLOR = Color.parseColor("#800FB4E5")

    // Board colors
    private val LIGHT_SQUARE_COLOR = Color.parseColor("#E8E3D6")
    private val DARK_SQUARE_COLOR = Color.parseColor("#B58863")

    // Piece colors
    private val WHITE_PIECE_COLOR = Color.parseColor("#F2F2F2")
    private val BLACK_PIECE_COLOR = Color.parseColor("#1A1A1A")
    private val WHITE_PIECE_TEXT_COLOR = Color.parseColor("#111111")
    private val BLACK_PIECE_TEXT_COLOR = Color.parseColor("#F9F9F9")

    // Eval colors
    private val EVAL_BLACK_COLOR = Color.parseColor("#262626")
  }
}

/**
 * Broadcast receiver for notification actions
 */
class NotificationActionReceiver : android.content.BroadcastReceiver() {
  override fun onReceive(context: Context, intent: Intent) {
    if (intent.action == "STOP_LIVE_UPDATES") {
      val gameId = intent.getStringExtra("game_id") ?: return
      val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
      val notificationId = "live_$gameId".hashCode()
      manager.cancel(notificationId)
      val deepLink = Intent(
        Intent.ACTION_VIEW,
        Uri.parse("https://chessever.com/games/$gameId?stop_live=1")
      ).apply {
        setPackage(context.packageName)
        flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
      }
      context.startActivity(deepLink)
    }
  }
}
