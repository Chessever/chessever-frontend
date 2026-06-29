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
import android.os.Build
import android.os.Bundle
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
    val eventType = liveEventType(live)
    val gameId = liveGameId(live)
    if (eventType == "dismiss") {
      gameId?.let {
        suppressLiveNotification(context, it)
        cancelLiveNotification(context, it)
      }
      event.preventDefault()
      return
    }

    if (gameId != null && isLiveNotificationSuppressed(context, gameId)) {
      cancelLiveNotification(context, gameId)
      event.preventDefault()
      return
    }

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

  /**
   * Posts/updates a live-game notification locally (mirrors the iOS on-device
   * Live Activity start). [live] uses the same {event, event_attributes,
   * event_updates} shape as the OneSignal push payload, so rendering is shared
   * with [onNotificationReceived]. Called from MainActivity's MethodChannel.
   */
  fun postLocalLiveNotification(context: Context, live: JSONObject) {
    val eventType = liveEventType(live)
    val gameId = liveGameId(live)
    if (eventType == "dismiss") {
      gameId?.let {
        suppressLiveNotification(context, it)
        cancelLiveNotification(context, it)
      }
      return
    }

    gameId?.let { clearLiveNotificationSuppression(context, it) }

    val notification = buildLiveNotification(context, live) ?: return
    val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
    val notificationGameId = live.optJSONObject("event_attributes")?.optString("game_id") ?: "game"
    manager.notify(notificationId(notificationGameId), notification)
  }

  fun cancelLiveNotification(context: Context, gameId: String) {
    val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
    manager.cancel(notificationId(gameId))
  }

  private fun buildLiveNotification(context: Context, live: JSONObject): Notification? {
    val attrs = live.optJSONObject("event_attributes") ?: return null
    val updates = live.optJSONObject("event_updates") ?: return null
    val eventType = liveEventType(live)

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

    val lastMove = updates.optString("last_move", "—")
    val lastMoveUci = updates.optString("last_move_uci", lastMove)
    val fen = updates.optString("fen", "")
    // Display SAN with its move number. Prefer a server-numbered move; otherwise
    // derive the number from the FEN. Keep `lastMove` raw above for the UCI
    // highlight fallback — only the rendered label gets the number.
    val lastMoveDisplay = numberMove(
      updates.optString("last_move_numbered", "")
        .ifEmpty { updates.optString("last_move_san", "") }
        .ifEmpty { lastMove },
      fen,
    )
    val themeIndex = when {
      updates.has("board_theme_index") -> updates.optInt("board_theme_index", 0)
      attrs.has("board_theme_index") -> attrs.optInt("board_theme_index", 0)
      else -> 0
    }
    val pieceStyleIndex = when {
      updates.has("piece_style_index") -> updates.optInt("piece_style_index", 0)
      attrs.has("piece_style_index") -> attrs.optInt("piece_style_index", 0)
      else -> 0
    }
    val evalCp = if (updates.has("eval_cp") && !updates.isNull("eval_cp")) updates.optDouble("eval_cp") else null
    val evalMate = if (updates.has("eval_mate") && !updates.isNull("eval_mate")) updates.optInt("eval_mate") else null
    val whiteClockSeconds = if (updates.has("white_clock_seconds") && !updates.isNull("white_clock_seconds")) updates.optInt("white_clock_seconds") else null
    val blackClockSeconds = if (updates.has("black_clock_seconds") && !updates.isNull("black_clock_seconds")) updates.optInt("black_clock_seconds") else null
    val prettyEventName = formatEventName(eventName.ifEmpty { roundName })

    // Live-clock + finished-state inputs.
    val statusStr = updates.optString("status", "")
    val isGameOver = (updates.optInt("is_game_over", 0) != 0) || eventType == "end"
    // A server push always represents the live tail, so default to following.
    val followLive = updates.optInt("follow_live", 1) != 0
    val lastMoveTimeMillis = parseIsoMillis(updates.optString("last_move_time", ""))
    val whiteToMove = fen.split(" ").let { if (it.size > 1) it[1] == "w" else true }
    val sideToMoveRemainingSeconds = if (whiteToMove) whiteClockSeconds else blackClockSeconds
    val resultText = when (statusStr) {
      "1-0" -> "$white won · 1-0"
      "0-1" -> "$black won · 0-1"
      "1/2-1/2", "½-½", "0.5-0.5" -> "Draw · ½-½"
      else -> "Final"
    }
    // Flag emojis (sent by the client/local-start; server pushes fall back to fed text).
    val whiteFlag = attrs.optString("white_flag", "").ifEmpty { updates.optString("white_flag", "") }
    val blackFlag = attrs.optString("black_flag", "").ifEmpty { updates.optString("black_flag", "") }
    // Per-player score, shown next to the name on a finished game.
    val whiteScore: String? = if (!isGameOver) null else when (statusStr) {
      "1-0" -> "1"
      "0-1" -> "0"
      "1/2-1/2", "½-½", "0.5-0.5", "1/2" -> "½"
      else -> null
    }
    val blackScore: String? = if (!isGameOver) null else when (statusStr) {
      "1-0" -> "0"
      "0-1" -> "1"
      "1/2-1/2", "½-½", "0.5-0.5", "1/2" -> "½"
      else -> null
    }

    ensureChannel(context)

    // Create large icon (chess board)
    val boardBitmap = renderBoardBitmap(context, fen, 256, lastMoveUci, themeIndex, pieceStyleIndex)
    val whiteBitmap = fetchBitmap(whitePhoto)
    val blackBitmap = fetchBitmap(blackPhoto)

    // Create big picture (chess board + info panel)
    val bigPictureBitmap = renderExpandedView(
      context = context,
      fen = fen,
      white = white,
      black = black,
      lastMove = lastMoveDisplay,
      evalCp = evalCp,
      evalMate = evalMate,
      eventName = prettyEventName,
      whiteClockSeconds = whiteClockSeconds,
      blackClockSeconds = blackClockSeconds,
      whitePhoto = whiteBitmap,
      blackPhoto = blackBitmap,
      lastMoveUci = lastMoveUci,
      boardThemeIndex = themeIndex,
      pieceStyleIndex = pieceStyleIndex,
      whiteTitle = whiteTitle,
      blackTitle = blackTitle,
      whiteFed = whiteFed,
      blackFed = blackFed,
      whiteFlag = whiteFlag,
      blackFlag = blackFlag,
      whiteScore = whiteScore,
      blackScore = blackScore
    )

    // Intent to open the app
    // Carry the focused move's FEN so tapping opens the app on that exact move
    // (not the live tail). buildUpon().appendQueryParameter encodes the FEN.
    val deepLinkUri = Uri.parse("https://chessever.com/games/$gameId")
      .buildUpon()
      .apply { if (fen.isNotEmpty()) appendQueryParameter("fen", fen) }
      .build()
    val intent = Intent(
      Intent.ACTION_VIEW,
      deepLinkUri
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

    val deleteIntent = Intent(context, NotificationActionReceiver::class.java).apply {
      action = ACTION_DISMISS_LIVE_UPDATES
      putExtra("game_id", gameId)
    }
    val deletePendingIntent = PendingIntent.getBroadcast(
      context,
      notificationId(gameId) + 2,
      deleteIntent,
      PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
    )

    // Build notification
    val builder = NotificationCompat.Builder(context, CHANNEL_ID)
      .setContentTitle("$white vs $black")
      // Collapsed text only — and only for a finished game (a terminal one-shot
      // result line). A live game shows nothing here: the move + eval already live
      // inside the rich card, so a duplicate "b2b3  +0.0" line above it is removed.
      .setContentText(if (isGameOver) resultText else null)
      .setSubText(if (prettyEventName.isNotEmpty()) prettyEventName else null)
      .setSmallIcon(R.drawable.ic_notification)
      .setLargeIcon(boardBitmap)
      .setOnlyAlertOnce(true)
      .setOngoing(eventType != "end")
      .setAutoCancel(eventType == "end")
      .setCategory(NotificationCompat.CATEGORY_STATUS)
      .setPriority(NotificationCompat.PRIORITY_DEFAULT)
      .setContentIntent(pendingIntent)
      .setDeleteIntent(deletePendingIntent)
      .setGroup("live_games")
      .setGroupAlertBehavior(NotificationCompat.GROUP_ALERT_SUMMARY)

    // No progress bar: it duplicated the eval bar that already lives inside the
    // rich card. Removed so the embedded card carries the evaluation alone.

    // Clocks removed from the live card — no chronometer. The notification updates
    // the board, last move and evaluation on each move only.
    builder.setShowWhen(false)

    // Always show the rich expanded card from renderExpandedView (eval bar, names
    // + titles, score, last move, eval pill). The Android 15+ promoted "BigText"
    // format stripped it to title + event name + a progress bar (no board, no eval
    // bar) — so we use the bitmap on EVERY version to match the iOS card.
    if (bigPictureBitmap != null) {
      // No summary text: when expanded, BigPictureStyle would show "b2b3  +0.0"
      // above the picture, duplicating what's inside the card. Omitted so the
      // card takes the whole expanded space under the title.
      builder.setStyle(
        NotificationCompat.BigPictureStyle()
          .bigPicture(bigPictureBitmap)
          .bigLargeIcon(null as Bitmap?)
      )
    }

    // NOTE: we intentionally do NOT request Android 15+ "promoted ongoing" here.
    // That format strips the card to title + text + a progress bar and cannot show
    // our rich BigPicture (eval bar / board / players + titles / score). The rich
    // expanded card is the goal, so this stays a normal ongoing notification.

    // Add action to end updates
    if (eventType != "end") {
      val stopIntent = Intent(context, NotificationActionReceiver::class.java).apply {
        action = ACTION_STOP_LIVE_UPDATES
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

  private fun liveEventType(live: JSONObject): String {
    return live.optString("event", "update").trim().lowercase()
  }

  private fun liveGameId(live: JSONObject): String? {
    return live.optJSONObject("event_attributes")
      ?.optString("game_id")
      ?.takeIf { it.isNotBlank() }
      ?: live.optJSONObject("event_updates")
        ?.optString("game_id")
        ?.takeIf { it.isNotBlank() }
      ?: live.optString("key")
        .takeIf { it.isNotBlank() }
  }

  /// Parse an ISO-8601 UTC timestamp (e.g. "2026-06-05T20:04:30.123Z") to epoch
  /// millis. Returns null on empty/invalid input so the caller falls back to a
  /// static clock instead of a bad countdown anchor.
  private fun parseIsoMillis(value: String): Long? {
    if (value.isEmpty()) return null
    return try {
      java.time.Instant.parse(value).toEpochMilli()
    } catch (e: Exception) {
      null
    }
  }

  private fun ensureChannel(context: Context) {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return

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
    lastMoveUci: String?,
    boardThemeIndex: Int,
    pieceStyleIndex: Int
  ): Bitmap {
    val board = parseFenBoard(fen)
    val bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
    val canvas = Canvas(bitmap)
    val squareSize = size / 8f

    val themeColors = boardThemeColors(boardThemeIndex)
    val lightPaint = Paint().apply { color = themeColors.first }
    val darkPaint = Paint().apply { color = themeColors.second }
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

        board?.get(rank)?.get(file)?.takeIf { it != '\u0000' }?.let { piece ->
          val pieceBitmap = loadPieceBitmap(context, piece, pieceStyleIndex)
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
    boardThemeIndex: Int,
    pieceStyleIndex: Int,
    whiteTitle: String?,
    blackTitle: String?,
    whiteFed: String?,
    blackFed: String?,
    whiteFlag: String?,
    blackFlag: String?,
    whiteScore: String?,
    blackScore: String?
  ): Bitmap? {
    val width = 600
    val height = 280
    val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
    val canvas = Canvas(bitmap)

    // Background
    val bgPaint = Paint().apply { color = BACKGROUND_COLOR }
    canvas.drawRect(0f, 0f, width.toFloat(), height.toFloat(), bgPaint)

    val padding = 20f

    // --- Left zone: eval bar + board share one vertical band (40..240) ---
    // The board is the anchor; the eval bar matches its exact top + height so the
    // two read as one unit instead of the bar over-running top and bottom.
    val boardSize = 200
    val boardTop = (height - boardSize) / 2f               // 40
    val evalBarWidth = 14f
    val evalBarX = padding                                  // 20
    renderEvalBar(canvas, evalBarX, boardTop, evalBarWidth, boardSize.toFloat(), evalCp, evalMate)

    val boardX = evalBarX + evalBarWidth + 14f             // 48
    val boardBitmap = renderBoardBitmap(context, fen, boardSize, lastMoveUci, boardThemeIndex, pieceStyleIndex)
    canvas.drawBitmap(boardBitmap, boardX, boardTop, null)

    // Logo avatar fallback for players without a profile photo (loaded once).
    val logo = loadLogoBitmap(context)

    // --- Right zone: player pair + result, balanced across the board's band ---
    // NO event eyebrow: the event name already shows in the notification's native
    // sub-text line above this card, so it's dropped here. The reclaimed top space
    // goes to the names, which become the hero of the column.
    val textX = boardX + boardSize + 24f                   // 272
    val textRight = width - padding                        // 580
    val textWidth = textRight - textX                      // 308

    // Players — 58px row pitch (black on top, white below). The wide pitch keeps
    // black's meta line clear of white's avatar (the old overlap bug).
    val blackBaseline = boardTop + 40f                     // 80
    val whiteBaseline = boardTop + 98f                     // 138
    drawPlayerRow(
      canvas, textX, blackBaseline, black, false,
      !isWhiteAdvantage(evalCp, evalMate), textWidth, blackPhoto, blackClockSeconds,
      blackTitle, blackFed, blackFlag, blackScore, logo
    )
    drawPlayerRow(
      canvas, textX, whiteBaseline, white, true,
      isWhiteAdvantage(evalCp, evalMate), textWidth, whitePhoto, whiteClockSeconds,
      whiteTitle, whiteFed, whiteFlag, whiteScore, logo
    )

    // Hairline divider — the single, faint separator before the result.
    val dividerY = boardTop + 142f                         // 182
    val dividerPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
      color = DIVIDER_COLOR
      strokeWidth = 1f
    }
    canvas.drawLine(textX, dividerY, textRight, dividerY, dividerPaint)

    // Result band — last move (left, the hero glyph) + eval chip (right) on one
    // shared optical centre via the (descent + ascent)/2 baseline trick.
    val resultCenterY = boardTop + 172f                    // 212
    val evalText = formatEval(evalCp, evalMate)
    val evalPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
      color = TEXT_PRIMARY_COLOR
      textSize = 23f
      typeface = Typeface.create(Typeface.MONOSPACE, Typeface.BOLD)
    }
    val pillHeight = evalPaint.textSize + 15f              // 38
    val pillWidth = evalPaint.measureText(evalText) + 28f
    val pillLeft = textRight - pillWidth
    val pillTop = resultCenterY - pillHeight / 2f
    val pillRect = RectF(pillLeft, pillTop, textRight, pillTop + pillHeight)
    val pillFill = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = SURFACE_COLOR }
    canvas.drawRoundRect(pillRect, pillHeight / 2f, pillHeight / 2f, pillFill)
    // A 1px accent hairline gives the eval chip a crisp, deliberate edge.
    val pillStroke = Paint(Paint.ANTI_ALIAS_FLAG).apply {
      color = ACCENT_COLOR
      style = Paint.Style.STROKE
      strokeWidth = 1f
    }
    canvas.drawRoundRect(pillRect, pillHeight / 2f, pillHeight / 2f, pillStroke)
    val evalTextY = resultCenterY - (evalPaint.descent() + evalPaint.ascent()) / 2f
    canvas.drawText(evalText, pillLeft + 14f, evalTextY, evalPaint)

    val movePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
      color = TEXT_PRIMARY_COLOR
      textSize = 32f
      typeface = Typeface.create(Typeface.MONOSPACE, Typeface.BOLD)
    }
    val moveAvailable = (pillLeft - 14f) - textX
    val moveBaseline = resultCenterY - (movePaint.descent() + movePaint.ascent()) / 2f
    drawFittedText(canvas, lastMove, textX, moveBaseline, moveAvailable, movePaint, minScale = 0.5f)

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
    fed: String?,
    flag: String?,
    score: String?,
    logo: Bitmap?
  ) {
    val avatarRadius = 13f
    val avatarCx = x + avatarRadius
    // Centre the avatar on the optical middle of the 26px name cap, not the baseline.
    val avatarCy = y - 8f

    if (!flag.isNullOrEmpty()) {
      // Flag emoji in place of the avatar (next to the name).
      val flagPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        textSize = 28f
        textAlign = Paint.Align.CENTER
      }
      canvas.drawText(flag, avatarCx, avatarCy + 10f, flagPaint)
    } else if (photo != null) {
      drawCircularImage(canvas, photo, avatarCx, avatarCy, avatarRadius)
    } else if (logo != null) {
      // No profile photo → the ChessEver logo, not a blank circle.
      drawCircularImage(canvas, logo, avatarCx, avatarCy, avatarRadius)
    } else {
      val circlePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = if (isWhite) Color.WHITE else Color.parseColor("#3A3A3D")
        style = Paint.Style.FILL
      }
      canvas.drawCircle(avatarCx, avatarCy, avatarRadius, circlePaint)
    }

    // Accent ring on the side with the advantage (only around a circular avatar, not a flag).
    if (isAdvantage && flag.isNullOrEmpty()) {
      val borderPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = ACCENT_COLOR
        style = Paint.Style.STROKE
        strokeWidth = 2f
      }
      canvas.drawCircle(avatarCx, avatarCy, avatarRadius + 1.5f, borderPaint)
    }

    val nameX = x + avatarRadius * 2 + 12f
    // Reserve room on the right only for a finished-game score; live games give the
    // name the full column width.
    val baseAvailable = maxWidth - (nameX - x)
    val trailingWidth = if (score != null) 36f else 0f
    val availableWidth = if (trailingWidth > 0f) baseAvailable - trailingWidth - 10f else baseAvailable

    // Name — the hero. The winning side is bold + bright, the other dimmed (mirrors the eval bar).
    val namePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
      color = if (isAdvantage) TEXT_PRIMARY_COLOR else NAME_DIM_COLOR
      textSize = 26f
      typeface = if (isAdvantage) Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
                 else Typeface.create(Typeface.DEFAULT, Typeface.NORMAL)
    }
    drawFittedText(canvas, name, nameX, y, availableWidth, namePaint, minScale = 0.65f)

    // Supporting line: TITLE • FED, tracked out a touch for a clean broadcast feel.
    val meta = listOfNotNull(
      title?.takeIf { it.isNotBlank() },
      fed?.takeIf { it.isNotBlank() }?.uppercase()
    ).joinToString(" • ")
    if (meta.isNotEmpty()) {
      val metaPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = TEXT_SECONDARY_COLOR
        textSize = 15f
        letterSpacing = 0.06f
        typeface = Typeface.create(Typeface.DEFAULT, Typeface.NORMAL)
      }
      drawFittedText(canvas, meta, nameX, y + 22f, availableWidth, metaPaint, minScale = 0.65f)
    }

    // Finished-game score — right-aligned, vertically centred on the name+meta block.
    if (score != null) {
      val scorePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = TEXT_PRIMARY_COLOR
        textSize = 28f
        typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
        textAlign = Paint.Align.RIGHT
      }
      val rowCenterY = y + 11f
      val scoreBaseline = rowCenterY - (scorePaint.descent() + scorePaint.ascent()) / 2f
      canvas.drawText(score, x + maxWidth, scoreBaseline, scorePaint)
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

  /**
   * Prepends the chess move number to a bare SAN ("Ne3" -> "38.Ne3" /
   * "38...Ne3"). The FEN is the position AFTER the move, so the side to move is
   * the opponent: black-to-move means White just moved ("N."), white-to-move
   * means Black just moved ("(N-1)...", since the fullmove counter increments
   * after Black's move). Returns the SAN unchanged when it is the placeholder,
   * already numbered, or the FEN lacks a usable fullmove field.
   */
  private fun numberMove(san: String, fen: String): String {
    if (san.isBlank() || san == "—") return san
    if (san.first().isDigit()) return san
    val parts = fen.split(" ")
    if (parts.size < 6) return san
    val fullmove = parts[5].toIntOrNull() ?: return san
    val whiteJustMoved = parts[1] == "b"
    val number = if (whiteJustMoved) fullmove else fullmove - 1
    if (number <= 0) return san
    return if (whiteJustMoved) "$number.$san" else "$number...$san"
  }

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

  private fun drawFittedText(
    canvas: Canvas,
    text: String,
    x: Float,
    y: Float,
    maxWidth: Float,
    basePaint: Paint,
    minScale: Float = 0.6f
  ) {
    if (text.isBlank()) return
    if (maxWidth <= 0f) {
      canvas.drawText(text, x, y, basePaint)
      return
    }
    val paint = Paint(basePaint)
    val measured = paint.measureText(text)
    if (measured > maxWidth) {
      val scale = maxWidth / measured
      paint.textSize = paint.textSize * max(scale, minScale)
    }
    val finalWidth = paint.measureText(text)
    if (finalWidth > maxWidth) {
      val top = y - paint.textSize
      val bottom = y + paint.textSize * 0.3f
      canvas.save()
      canvas.clipRect(x, top, x + maxWidth, bottom)
      canvas.drawText(text, x, y, paint)
      canvas.restore()
    } else {
      canvas.drawText(text, x, y, paint)
    }
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

  /**
   * The ChessEver logo, used as the avatar when a player has no profile photo
   * (nicer than a blank circle). Loaded once from the bundled Flutter asset and
   * cached; falls back to the launcher icon, then null (caller draws a plain
   * circle if even that fails).
   */
  private fun loadLogoBitmap(context: Context): Bitmap? {
    synchronized(logoLock) {
      if (logoLoaded) return logoBitmap
      logoLoaded = true
      val assetCandidates = listOf(
        "flutter_assets/assets/pngs/new_app_logo_circle.webp",
        "flutter_assets/assets/pngs/new_app_logo.webp"
      )
      for (path in assetCandidates) {
        val bmp = try {
          context.assets.open(path).use { BitmapFactory.decodeStream(it) }
        } catch (_: Exception) {
          null
        }
        if (bmp != null) {
          logoBitmap = bmp
          return logoBitmap
        }
      }
      val resId = context.resources.getIdentifier("ic_launcher", "mipmap", context.packageName)
      if (resId != 0) {
        logoBitmap = try {
          BitmapFactory.decodeResource(context.resources, resId)
        } catch (_: Exception) {
          null
        }
      }
      return logoBitmap
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

  private fun loadPieceBitmap(context: Context, piece: Char, pieceStyleIndex: Int): Bitmap? {
    val fileName = when (piece) {
      'K' -> "wK.png"
      'Q' -> "wQ.png"
      'R' -> "wR.png"
      'B' -> "wB.png"
      'N' -> "wN.png"
      'P' -> "wP.png"
      'k' -> "bK.png"
      'q' -> "bQ.png"
      'r' -> "bR.png"
      'b' -> "bB.png"
      'n' -> "bN.png"
      'p' -> "bP.png"
      else -> null
    } ?: return null

    val dir = pieceSetDirectory(pieceStyleIndex)
    val cacheKey = "$dir/$fileName"

    synchronized(pieceBitmapCache) {
      if (pieceBitmapCache.containsKey(cacheKey)) {
        return pieceBitmapCache[cacheKey]
      }
    }

    // Prefer Flutter assets, so native rendering matches the piece set selected in-app.
    val assetPath = "flutter_assets/packages/chessground/assets/piece_sets/$dir/$fileName"
    val bitmapFromAssets = try {
      context.assets.open(assetPath).use { BitmapFactory.decodeStream(it) }
    } catch (_: Exception) {
      null
    }

    if (bitmapFromAssets != null) {
      synchronized(pieceBitmapCache) {
        pieceBitmapCache[cacheKey] = bitmapFromAssets
      }
      return bitmapFromAssets
    }

    // Fallback to bundled cburnett resources (keeps notifications working even if assets move).
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
    if (resId == 0) {
      synchronized(pieceBitmapCache) {
        pieceBitmapCache[cacheKey] = null
      }
      return null
    }

    val bitmapFromRes = try {
      BitmapFactory.decodeResource(context.resources, resId)
    } catch (_: Exception) {
      null
    }

    synchronized(pieceBitmapCache) {
      pieceBitmapCache[cacheKey] = bitmapFromRes
    }
    return bitmapFromRes
  }

  companion object {
    private const val CHANNEL_ID = "live_updates"
    private const val PREFS_NAME = "chessever_live_notification_prefs"
    private const val SUPPRESSED_PREFIX = "suppressed_live_game_"
    const val ACTION_STOP_LIVE_UPDATES = "STOP_LIVE_UPDATES"
    const val ACTION_DISMISS_LIVE_UPDATES = "DISMISS_LIVE_UPDATES"

    fun suppressLiveNotification(context: Context, gameId: String) {
      if (gameId.isBlank()) return
      context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        .edit()
        .putBoolean(SUPPRESSED_PREFIX + gameId, true)
        .apply()
    }

    fun clearLiveNotificationSuppression(context: Context, gameId: String) {
      if (gameId.isBlank()) return
      context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        .edit()
        .remove(SUPPRESSED_PREFIX + gameId)
        .apply()
    }

    fun isLiveNotificationSuppressed(context: Context, gameId: String): Boolean {
      if (gameId.isBlank()) return false
      return context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        .getBoolean(SUPPRESSED_PREFIX + gameId, false)
    }

    private val photoCache = mutableMapOf<String, Bitmap?>()
    private val pieceBitmapCache = mutableMapOf<String, Bitmap?>()
    // ChessEver logo avatar fallback — loaded once, reused for every card.
    private val logoLock = Any()
    private var logoLoaded = false
    private var logoBitmap: Bitmap? = null

    // Must match PieceSet.values order in chessground:
    // /Users/berkay/.pub-cache/hosted/pub.dev/chessground-7.3.0/lib/src/piece_set.dart
    private val PIECE_SET_DIRS = listOf(
      "cburnett",
      "merida",
      "pirouetti",
      "chessnut",
      "chess7",
      "alpha",
      "reillycraig",
      "companion",
      "riohacha",
      "kosal",
      "leipzig",
      "fantasy",
      "spatial",
      "celtic",
      "california",
      "caliente",
      "pixel",
      "firi",
      "rhosgfx",
      "maestro",
      "fresca",
      "cardinal",
      "gioco",
      "tatiana",
      "staunty",
      "governor",
      "dubrovny",
      "icpieces",
      "mpchess",
      "monarchy",
      "cooke",
      "shapes",
      "kiwen-suwi",
      "horsey",
      "anarcandy",
      "xkcd",
      "letter",
      "disguised",
      "symmetric"
    )

    private fun pieceSetDirectory(index: Int): String {
      return if (index in 0 until PIECE_SET_DIRS.size) PIECE_SET_DIRS[index] else PIECE_SET_DIRS[0]
    }

    // Design colors matching iOS
    private val BACKGROUND_COLOR = Color.parseColor("#0C0C0E")
    private val SURFACE_COLOR = Color.parseColor("#141416")
    private val ACCENT_COLOR = Color.parseColor("#0FB4E5")
    private val TEXT_PRIMARY_COLOR = Color.WHITE
    private val TEXT_SECONDARY_COLOR = Color.parseColor("#999999")
    // Dimmed name for the side that isn't ahead — brighter than secondary so the
    // name stays legible while still reading as "not the leader".
    private val NAME_DIM_COLOR = Color.parseColor("#B0B0B0")
    // Hairline rule (white ~15%) between the players and the result band.
    private val DIVIDER_COLOR = Color.parseColor("#26FFFFFF")
    private val HIGHLIGHT_FROM_COLOR = Color.parseColor("#4D0FB4E5")
    private val HIGHLIGHT_TO_COLOR = Color.parseColor("#800FB4E5")

    private fun boardThemeColors(index: Int): Pair<Int, Int> {
      val palettes = listOf(
        Pair(0xfff0d9b6.toInt(), 0xffb58863.toInt()), // Brown
        Pair(0xffdee3e6.toInt(), 0xff8ca2ad.toInt()), // Blue
        Pair(0xffffffdd.toInt(), 0xff86a666.toInt()), // Green
        Pair(0xffececec.toInt(), 0xffc1c18e.toInt()), // IC
        Pair(0xff97b2c7.toInt(), 0xff546f82.toInt()), // Blue 2
        Pair(0xffd9e0e6.toInt(), 0xff315991.toInt()), // Blue 3
        Pair(0xffeae6dd.toInt(), 0xff7c7f87.toInt()), // Blue Marble
        Pair(0xffd7daeb.toInt(), 0xff547388.toInt()), // Canvas
        Pair(0xfff2f9bb.toInt(), 0xff59935d.toInt()), // Green Plastic
        Pair(0xffb8b8b8.toInt(), 0xff7d7d7d.toInt()), // Grey
        Pair(0xfff0d9b5.toInt(), 0xff946f51.toInt()), // Horsey
        Pair(0xffd1d1c9.toInt(), 0xffc28e16.toInt()), // Leather
        Pair(0xffe8ceab.toInt(), 0xffbc7944.toInt()), // Maple
        Pair(0xffe2c89f.toInt(), 0xff996633.toInt()), // Maple 2
        Pair(0xff93ab91.toInt(), 0xff4f644e.toInt()), // Marble
        Pair(0xffc9c9c9.toInt(), 0xff727272.toInt()), // Metal
        Pair(0xffffffff.toInt(), 0xff8d8d8d.toInt()), // Newspaper
        Pair(0xffb8b19f.toInt(), 0xff6d6655.toInt()), // Olive
        Pair(0xffe8e9b7.toInt(), 0xffed7272.toInt()), // Pink Pyramid
        Pair(0xff9f90b0.toInt(), 0xff7d4a8d.toInt()), // Purple
        Pair(0xffe5daf0.toInt(), 0xff957ab0.toInt()), // Purple Diag
        Pair(0xffd8a45b.toInt(), 0xff9b4d0f.toInt()), // Wood
        Pair(0xffa38b5d.toInt(), 0xff6c5017.toInt()), // Wood 2
        Pair(0xffd0ceca.toInt(), 0xff755839.toInt()), // Wood 3
        Pair(0xffcaaf7d.toInt(), 0xff7b5330.toInt()), // Wood 4
      )
      val safeIndex = index.coerceIn(0, palettes.size - 1)
      return palettes[safeIndex]
    }

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
    if (intent.action == NotificationServiceExtension.ACTION_STOP_LIVE_UPDATES) {
      val gameId = intent.getStringExtra("game_id") ?: return
      NotificationServiceExtension.suppressLiveNotification(context, gameId)
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
    } else if (intent.action == NotificationServiceExtension.ACTION_DISMISS_LIVE_UPDATES) {
      val gameId = intent.getStringExtra("game_id") ?: return
      NotificationServiceExtension.suppressLiveNotification(context, gameId)
      val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
      val notificationId = "live_$gameId".hashCode()
      manager.cancel(notificationId)
    }
  }
}
