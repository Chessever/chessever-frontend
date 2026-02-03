package com.chessEver.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import androidx.core.app.NotificationCompat
import com.onesignal.NotificationServiceExtension
import com.onesignal.OSNotificationReceivedEvent
import com.onesignal.OneSignal
import org.json.JSONObject

class NotificationServiceExtension : NotificationServiceExtension() {
  override fun onNotificationReceived(event: OSNotificationReceivedEvent) {
    val notification = event.notification
    val data = notification.additionalData
    val live = data?.optJSONObject("live_notification")
    if (live == null) {
      event.complete(notification)
      return
    }

    val context = OneSignal.getAppContext()
    val updated = buildLiveNotification(context, live)
    if (updated == null) {
      event.complete(notification)
      return
    }

    val manager =
      context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
    val notificationId = "live_${live.optJSONObject("event_attributes")?.optString("game_id") ?: "game"}"
      .hashCode()
    manager.notify(notificationId, updated)

    // Prevent default OneSignal notification from displaying
    event.complete(null)
  }

  private fun buildLiveNotification(
    context: Context,
    live: JSONObject,
  ): Notification? {
    val attrs = live.optJSONObject("event_attributes")
    val updates = live.optJSONObject("event_updates")
    val white = attrs?.optString("player_white") ?: "White"
    val black = attrs?.optString("player_black") ?: "Black"
    val lastMove = updates?.optString("last_move") ?: "Live update"
    val fen = updates?.optString("fen") ?: ""
    val evalCp = updates?.optDouble("eval_cp", Double.NaN)
    val evalMate = updates?.optInt("eval_mate", 0)

    ensureChannel(context)

    val builder = NotificationCompat.Builder(context, CHANNEL_ID)
      .setContentTitle("$white vs $black")
      .setContentText(lastMove)
      .setSmallIcon(context.applicationInfo.icon)
      .setOnlyAlertOnce(true)
      .setOngoing(true)
      .setCategory(NotificationCompat.CATEGORY_STATUS)
      .setPriority(NotificationCompat.PRIORITY_LOW)

    if (!evalCp.isNaN()) {
      val progress = ((evalCp + 2000.0) / 4000.0 * 100).toInt().coerceIn(0, 100)
      builder.setProgress(100, progress, false)
    } else if (evalMate != 0) {
      val progress = if (evalMate > 0) 100 else 0
      builder.setProgress(100, progress, false)
    }

    val boardBitmap = renderBoardBitmap(fen)
    if (boardBitmap != null) {
      builder.setStyle(
        NotificationCompat.BigPictureStyle()
          .bigPicture(boardBitmap)
          .bigLargeIcon(null as Bitmap?),
      )
    }

    return builder.build()
  }

  private fun ensureChannel(context: Context) {
    val manager =
      context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
    val existing = manager.getNotificationChannel(CHANNEL_ID)
    if (existing != null) return

    val channel = NotificationChannel(
      CHANNEL_ID,
      "Live Updates",
      NotificationManager.IMPORTANCE_LOW,
    )
    channel.description = "Live chess game updates"
    channel.setShowBadge(false)
    manager.createNotificationChannel(channel)
  }

  private fun renderBoardBitmap(fen: String): Bitmap? {
    val board = parseFenBoard(fen) ?: return null
    val size = 360
    val square = size / 8f
    val bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
    val canvas = Canvas(bitmap)
    val paint = Paint(Paint.ANTI_ALIAS_FLAG)
    val textPaint = Paint(Paint.ANTI_ALIAS_FLAG)
    textPaint.textAlign = Paint.Align.CENTER
    textPaint.textSize = square * 0.75f

    for (rank in 0 until 8) {
      for (file in 0 until 8) {
        val isLight = (rank + file) % 2 == 0
        paint.color = if (isLight) Color.parseColor("#E8E3D5") else Color.parseColor("#3A3A3A")
        val left = file * square
        val top = rank * square
        canvas.drawRect(left, top, left + square, top + square, paint)

        val piece = board[rank][file]
        if (piece != null) {
          textPaint.color = if (piece.isUpperCase()) Color.BLACK else Color.WHITE
          val x = left + square / 2
          val y = top + square / 2 - (textPaint.descent() + textPaint.ascent()) / 2
          canvas.drawText(pieceToUnicode(piece), x, y, textPaint)
        }
      }
    }

    return bitmap
  }

  private fun parseFenBoard(fen: String): Array<CharArray>? {
    if (fen.isBlank()) return null
    val boardPart = fen.split(" ").firstOrNull() ?: return null
    val ranks = boardPart.split("/")
    if (ranks.size != 8) return null
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

  private fun pieceToUnicode(piece: Char): String {
    return when (piece) {
      'K' -> "♔"
      'Q' -> "♕"
      'R' -> "♖"
      'B' -> "♗"
      'N' -> "♘"
      'P' -> "♙"
      'k' -> "♚"
      'q' -> "♛"
      'r' -> "♜"
      'b' -> "♝"
      'n' -> "♞"
      'p' -> "♟︎"
      else -> ""
    }
  }

  private companion object {
    const val CHANNEL_ID = "live_updates"
  }
}
