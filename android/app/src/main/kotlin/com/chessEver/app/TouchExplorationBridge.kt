package com.chessEver.app

import android.content.Context
import android.view.accessibility.AccessibilityManager
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * Tells Flutter whether a screen reader actually explores the screen by touch
 * (TalkBack and its kin), and when that changes.
 *
 * Flutter's own `MediaQuery.accessibleNavigation` turns on, and stays on, the
 * first time ANY accessibility service reads the view tree: password
 * managers, OEM helpers, launchers and automation apps all do, so on many
 * Android phones it is true with no screen reader running, and every
 * behaviour keyed on it (the scroll-away bars above all) silently switched
 * off. iOS only reports it for VoiceOver. The app reads this instead on
 * Android, so both platforms behave the same.
 */
class TouchExplorationBridge(context: Context, messenger: BinaryMessenger) {
  private val manager =
    context.getSystemService(Context.ACCESSIBILITY_SERVICE) as? AccessibilityManager
  private val channel = MethodChannel(messenger, CHANNEL)

  private val listener =
    AccessibilityManager.TouchExplorationStateChangeListener { enabled ->
      channel.invokeMethod("touchExplorationChanged", enabled)
    }

  init {
    channel.setMethodCallHandler { call, result ->
      when (call.method) {
        "touchExploration" -> result.success(manager?.isTouchExplorationEnabled == true)
        else -> result.notImplemented()
      }
    }
    manager?.addTouchExplorationStateChangeListener(listener)
  }

  fun dispose() {
    manager?.removeTouchExplorationStateChangeListener(listener)
    channel.setMethodCallHandler(null)
  }

  companion object {
    const val CHANNEL = "com.chessever/touch_exploration"
  }
}
