package com.chessEver.app

import android.app.Application
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.media.AudioAttributes
import android.media.RingtoneManager

class ChessEverApplication : Application() {
  override fun onCreate() {
    super.onCreate()
    createNotificationChannels()
  }

  private fun createNotificationChannels() {
    val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

    val silentAttrs = AudioAttributes.Builder()
      .setUsage(AudioAttributes.USAGE_NOTIFICATION)
      .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
      .build()

    val defaultSound = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)

    val liveUpdates = NotificationChannel(
      CHANNEL_LIVE_UPDATES,
      "Live Game Updates",
      NotificationManager.IMPORTANCE_LOW
    ).apply {
      description = "Real-time move updates for live games"
      setShowBadge(false)
      enableVibration(false)
      setSound(null, null)
    }

    val liveAlerts = NotificationChannel(
      CHANNEL_LIVE_ALERTS,
      "Live Game Alerts",
      NotificationManager.IMPORTANCE_DEFAULT
    ).apply {
      description = "Check and game end alerts for live games"
      setShowBadge(true)
      enableVibration(true)
      setSound(defaultSound, silentAttrs)
    }

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
      listOf(liveUpdates, liveAlerts, favorites, headsUp, general)
    )
  }

  companion object {
    const val CHANNEL_LIVE_UPDATES = "live_updates"
    const val CHANNEL_LIVE_ALERTS = "live_alerts"
    const val CHANNEL_FAVORITES = "fav_updates"
    const val CHANNEL_HEADS_UP = "heads_up"
    const val CHANNEL_GENERAL = "general"
  }
}
