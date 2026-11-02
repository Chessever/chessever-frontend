package com.chessEver.app

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.app.NotificationManager
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/** Native OS permission queries; no push-provider SDK or cached permission state. */
class PushPermissionBridge(private val activity: Activity, messenger: BinaryMessenger) {
  private val channel = MethodChannel(messenger, "com.chessever/push_permission")
  private val history = activity.getSharedPreferences("chessever_push_permission", Context.MODE_PRIVATE)
  private var pending: MethodChannel.Result? = null
  private val requestCode = 7143

  init {
    channel.setMethodCallHandler { call, result ->
      when (call.method) {
        "permission" -> result.success(granted())
        "canRequest" -> result.success(canRequest())
        "requestPermission" -> {
          if (pending != null) {
            result.error("BUSY", "Notification permission request is already open", null)
          } else if (!canRequest()) {
            result.success(granted())
          } else if (Build.VERSION.SDK_INT >= 33) {
            pending = result
            activity.requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), requestCode)
          } else {
            result.success(granted())
          }
        }
        else -> result.notImplemented()
      }
    }
  }

  private fun granted(): Boolean = (activity.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager).areNotificationsEnabled()

  private fun canRequest(): Boolean {
    if (Build.VERSION.SDK_INT < 33 || granted()) return false
    return !history.getBoolean("asked", false) ||
      activity.shouldShowRequestPermissionRationale(Manifest.permission.POST_NOTIFICATIONS)
  }

  fun onRequestPermissionsResult(code: Int, grantResults: IntArray): Boolean {
    if (code != requestCode) return false
    if (grantResults.isNotEmpty()) history.edit().putBoolean("asked", true).apply()
    val result = pending
    pending = null
    result?.success(granted())
    return true
  }

  fun dispose() {
    pending?.error("PERMISSION_UNAVAILABLE", "Activity closed during notification permission request", null)
    pending = null
    channel.setMethodCallHandler(null)
  }
}
