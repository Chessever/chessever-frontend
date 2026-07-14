package com.chessEver.app

import android.app.Application
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.media.AudioAttributes
import android.media.RingtoneManager
import android.os.Build

class ChessEverApplication : Application() {
  override fun onCreate() {
    super.onCreate()
    createNotificationChannels()
  }

  private fun createNotificationChannels() {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return

    val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

    val silentAttrs = AudioAttributes.Builder()
      .setUsage(AudioAttributes.USAGE_NOTIFICATION)
      .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
      .build()

    val defaultSound = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)

    // Live Activity feature removed — delete its channels on existing installs so
    // the stale "Live Game Updates" / "Live Game Alerts" entries disappear from the
    // system notification settings after an app update. No-op on fresh installs.
    manager.deleteNotificationChannel("live_updates")
    manager.deleteNotificationChannel("live_alerts")

    val favorites = NotificationChannel(
      CHANNEL_FAVORITES,
      "Favorite Updates",
      NotificationManager.IMPORTANCE_DEFAULT
    ).apply {
      description = "Alerts for favorite players and events"
      setShowBadge(true)
      setSound(defaultSound, silentAttrs)
    }

    val headsUp = NotificationChannel(
      CHANNEL_HEADS_UP,
      "Heads-up Alerts",
      NotificationManager.IMPORTANCE_DEFAULT
    ).apply {
      description = "Reminders before rounds start"
      setShowBadge(true)
      setSound(defaultSound, silentAttrs)
    }

    val general = NotificationChannel(
      CHANNEL_GENERAL,
      "General Notifications",
      NotificationManager.IMPORTANCE_DEFAULT
    ).apply {
      description = "General notifications"
      setShowBadge(true)
      setSound(defaultSound, silentAttrs)
    }

    manager.createNotificationChannels(
      listOf(favorites, headsUp, general)
    )
  }

  companion object {
    const val CHANNEL_FAVORITES = "fav_updates"
    const val CHANNEL_HEADS_UP = "heads_up"
    const val CHANNEL_GENERAL = "general"
  }
}
