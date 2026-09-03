package com.chessEver.app

import android.app.PictureInPictureParams
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.net.Uri
import android.provider.MediaStore
import android.provider.OpenableColumns
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Rect
import android.graphics.RectF
import android.graphics.Typeface
import android.media.AudioAttributes
import android.media.SoundPool
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
import java.time.Instant
import java.time.LocalDateTime
import java.time.OffsetDateTime
import java.time.ZoneOffset
import kotlin.math.roundToInt

class MainActivity : FlutterActivity() {
  companion object {
    private const val PICK_FEEDBACK_IMAGE = 7142
  }

  private var pipChannel: MethodChannel? = null
  private var mediaPickerChannel: MethodChannel? = null
  private var pendingFeedbackImageResult: MethodChannel.Result? = null
  private var pipPayload: MutableMap<String, Any?>? = null
  private var pipOverlay: ChessPipOverlayView? = null
  private val mainHandler = Handler(Looper.getMainLooper())
  private val httpClient = OkHttpClient()
  private var pollRunnable: Runnable? = null
  private var clockRunnable: Runnable? = null
  private var activePollCall: Call? = null
  private var isEnteringPip = false
  private var lastReportedPipMode = false
  private var pipLayoutListener: View.OnLayoutChangeListener? = null
  private var lastSoundedMove: String? = null
  // PiP move SFX are played natively: once the activity is in PiP, Flutter reports
  // `paused` and AudioPlayerService hibernates the SoLoud engine 300ms later, so
  // bouncing the request back into Dart never made a sound.
  private var sfxPool: SoundPool? = null
  private var moveSfxId = 0
  private var captureSfxId = 0

  override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    mediaPickerChannel = MethodChannel(
      flutterEngine.dartExecutor.binaryMessenger,
      "com.chessever/media_picker",
    )
    mediaPickerChannel?.setMethodCallHandler { call, result ->
      when (call.method) {
        "pickImage" -> pickFeedbackImage(result)
        else -> result.notImplemented()
      }
    }
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
            lastSoundedMove = args["lastMoveUci"] as? String
            preloadPipSfx()
            pipOverlay?.payload = pipPayload
            pipOverlay?.invalidate()
            if (isCurrentlyInPip()) {
              startClockTicker()
              startNativePollingIfPossible()
            }
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
            lastSoundedMove = args["lastMoveUci"] as? String
            preloadPipSfx()
            pipOverlay?.payload = pipPayload
            pipOverlay?.invalidate()
            if (isCurrentlyInPip()) {
              startClockTicker()
              startNativePollingIfPossible()
            }
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

  override fun onResume() {
    super.onResume()
    if (!isCurrentlyInPip() && (lastReportedPipMode || isEnteringPip || pipOverlay != null)) {
      cleanupExitedPip()
      notifyPipModeChanged(false)
    }
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
    isEnteringPip = false
    pipOverlay?.visibility = if (isInPictureInPictureMode) View.VISIBLE else View.GONE
    if (isInPictureInPictureMode) {
      pipPayload?.let { ensurePipOverlay(it) }
      startClockTicker()
      startNativePollingIfPossible()
    } else {
      cleanupExitedPip()
    }
    notifyPipModeChanged(isInPictureInPictureMode)
  }

  override fun onDestroy() {
    stopClockTicker()
    stopNativePolling()
    removePipOverlay()
    sfxPool?.release()
    sfxPool = null
    pendingFeedbackImageResult?.success(null)
    pendingFeedbackImageResult = null
    mediaPickerChannel?.setMethodCallHandler(null)
    pipChannel?.setMethodCallHandler(null)
    super.onDestroy()
  }

  @Deprecated("Deprecated in Java")
  override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
    if (requestCode == PICK_FEEDBACK_IMAGE) {
      handleFeedbackImageResult(resultCode, data)
      return
    }
    @Suppress("DEPRECATION")
    super.onActivityResult(requestCode, resultCode, data)
  }

  private fun pickFeedbackImage(result: MethodChannel.Result) {
    if (pendingFeedbackImageResult != null) {
      result.error("BUSY", "A picture picker is already open.", null)
      return
    }
    pendingFeedbackImageResult = result
    launchFeedbackImagePicker()
  }

  // Opens a picker that runs in a system process and returns one scoped URI,
  // so the app never needs READ_MEDIA_IMAGES / READ_EXTERNAL_STORAGE. Google
  // Play rejects API 33+ apps that ask for those when a system picker is
  // enough, which is why neither this code nor the manifest declares one.
  private fun launchFeedbackImagePicker() {
    val intents = listOfNotNull(systemPhotoPickerIntent(), openDocumentIntent())
    for (intent in intents) {
      try {
        @Suppress("DEPRECATION")
        startActivityForResult(intent, PICK_FEEDBACK_IMAGE)
        return
      } catch (_: Exception) {
        // Try the next picker.
      }
    }
    val reply = pendingFeedbackImageResult
    pendingFeedbackImageResult = null
    reply?.error("PICK_FAILED", "Could not open the photo library.", null)
  }

  // The Android photo picker: shipped with API 33+, and back-ported to API
  // 30-32 through a Google Play system module, hence the resolve check
  // instead of a plain SDK_INT gate.
  private fun systemPhotoPickerIntent(): Intent? {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return null
    val intent = Intent(MediaStore.ACTION_PICK_IMAGES).apply { type = "image/*" }
    return if (intent.resolveActivity(packageManager) != null) intent else null
  }

  // Storage Access Framework fallback for devices without the photo picker.
  // Also permission-free: the picked document arrives as a granted URI.
  private fun openDocumentIntent(): Intent {
    return Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
      addCategory(Intent.CATEGORY_OPENABLE)
      type = "image/*"
    }
  }

  private fun handleFeedbackImageResult(resultCode: Int, data: Intent?) {
    val reply = pendingFeedbackImageResult
    pendingFeedbackImageResult = null
    if (reply == null) return
    if (resultCode != RESULT_OK) {
      reply.success(null)
      return
    }
    val uri = data?.data
    if (uri == null) {
      reply.success(null)
      return
    }
    Thread {
      try {
        val bytes = contentResolver.openInputStream(uri)?.use { it.readBytes() }
        if (bytes == null || bytes.isEmpty()) {
          mainHandler.post {
            reply.error("READ_FAILED", "Could not read the selected picture.", null)
          }
          return@Thread
        }
        val payload = hashMapOf<String, Any>(
          "bytes" to bytes,
          "fileName" to feedbackImageFileName(uri),
        )
        mainHandler.post { reply.success(payload) }
      } catch (e: Exception) {
        mainHandler.post {
          reply.error("READ_FAILED", e.message, null)
        }
      }
    }.start()
  }

  private fun feedbackImageFileName(uri: Uri): String {
    contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { cursor ->
      if (cursor.moveToFirst()) {
        val index = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
        if (index >= 0) {
          val name = cursor.getString(index)
          if (!name.isNullOrBlank()) return name
        }
      }
    }
    val ext = when (contentResolver.getType(uri)) {
      "image/png" -> "png"
      "image/webp" -> "webp"
      "image/heic", "image/heif" -> "heic"
      else -> "jpg"
    }
    return "photo.$ext"
  }

  private fun isCurrentlyInPip(): Boolean {
    return Build.VERSION.SDK_INT >= Build.VERSION_CODES.N && isInPictureInPictureMode
  }

  private fun enterPipIfEligible(): Boolean {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return false
    if (!packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)) {
      return false
    }
    val payload = pipPayload ?: return false
    if (payload["eligible"] != true) return false
    if (isInPictureInPictureMode) return true
    if (isEnteringPip) return true

    val overlay = ensurePipOverlay(payload)
    overlay.postInvalidateOnAnimation()
    updatePipParamsForOverlay(overlay)
    isEnteringPip = true
    return try {
      val entered = PipApi26.enter(this, pipSourceRectHint(overlay))
      if (!entered) {
        isEnteringPip = false
        removePipOverlay()
      }
      entered
    } catch (e: Exception) {
      Log.w("ChessPiP", "Failed to enter picture-in-picture", e)
      isEnteringPip = false
      removePipOverlay()
      false
    }
  }

  private fun ensurePipOverlay(payload: MutableMap<String, Any?>): ChessPipOverlayView {
    val content = findViewById<ViewGroup>(android.R.id.content)
    val existing = pipOverlay
    if (existing != null && existing.parent != null) {
      existing.payload = payload
      existing.visibility = View.VISIBLE
      existing.invalidate()
      attachPipSourceRectTracker(existing)
      return existing
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
    attachPipSourceRectTracker(overlay)
    return overlay
  }

  private fun clearPipState() {
    isEnteringPip = false
    if (isCurrentlyInPip()) {
      stopNativePolling()
      pipOverlay?.payload = pipPayload
      pipOverlay?.invalidate()
      startClockTicker()
      return
    }
    pipPayload = null
    stopClockTicker()
    stopNativePolling()
    removePipOverlay()
  }

  private fun removePipOverlay() {
    val overlay = pipOverlay ?: return
    detachPipSourceRectTracker(overlay)
    overlay.visibility = View.GONE
    overlay.payload = null
    (overlay.parent as? ViewGroup)?.removeView(overlay)
    pipOverlay = null
  }

  private fun cleanupExitedPip() {
    isEnteringPip = false
    stopClockTicker()
    stopNativePolling()
    removePipOverlay()
  }

  private fun notifyPipModeChanged(isInPip: Boolean) {
    if (lastReportedPipMode == isInPip) return
    lastReportedPipMode = isInPip
    pipChannel?.invokeMethod(
      "onPipModeChanged",
      mapOf("isInPip" to isInPip)
    )
  }

  private fun pipSourceRectHint(overlay: ChessPipOverlayView?): Rect? {
    overlay?.sourceRectHint()?.let { return it }
    val content = findViewById<View>(android.R.id.content) ?: return null
    val rect = Rect()
    return if (content.getGlobalVisibleRect(rect) && !rect.isEmpty) rect else null
  }

  private fun updatePipParamsForOverlay(overlay: ChessPipOverlayView?) {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
    try {
      PipApi26.update(this, pipSourceRectHint(overlay))
    } catch (e: Exception) {
      Log.w("ChessPiP", "Failed to update PiP params", e)
    }
  }

  private fun attachPipSourceRectTracker(overlay: ChessPipOverlayView) {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
    if (pipLayoutListener != null) return
    val listener = View.OnLayoutChangeListener { view, left, top, right, bottom, oldLeft, oldTop, oldRight, oldBottom ->
      if (view !== overlay) return@OnLayoutChangeListener
      if (left == oldLeft && top == oldTop && right == oldRight && bottom == oldBottom) return@OnLayoutChangeListener
      updatePipParamsForOverlay(overlay)
    }
    pipLayoutListener = listener
    overlay.addOnLayoutChangeListener(listener)
  }

  private fun detachPipSourceRectTracker(overlay: ChessPipOverlayView) {
    pipLayoutListener?.let { overlay.removeOnLayoutChangeListener(it) }
    pipLayoutListener = null
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

  private fun startClockTicker() {
    if (clockRunnable != null) return

    val runnable = object : Runnable {
      override fun run() {
        if (isCurrentlyInPip() && pipOverlay == null) {
          pipPayload?.let { ensurePipOverlay(it) }
        }
        pipOverlay?.postInvalidateOnAnimation()
        mainHandler.postDelayed(this, 1_000L)
      }
    }
    clockRunnable = runnable
    mainHandler.post(runnable)
  }

  private fun stopClockTicker() {
    clockRunnable?.let { mainHandler.removeCallbacks(it) }
    clockRunnable = null
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
    // Frozen on an earlier move: keep the viewed position, ignore newer live data.
    if (payload["followLive"] == false) return
    val previousMove = (payload["lastMoveUci"] ?: payload["lastMove"]) as? String
    val previousFen = payload["fen"] as? String

    if (row.has("fen") && !row.isNull("fen")) {
      row.optString("fen").takeIf { it.isNotBlank() }?.let {
        payload["fen"] = it
        // The polled row is now the freshest thing we have, so the side-to-move it
        // carries beats the hint Flutter sent at PiP entry. Leaving that hint in
        // place would pin the ticking clock to the wrong player for the rest of
        // the PiP session.
        payload.remove("clockTurnIsWhite")
      }
    }
    if (row.has("last_move") && !row.isNull("last_move")) {
      row.optString("last_move").takeIf { it.isNotBlank() }?.let {
        payload["lastMoveUci"] = it
        payload["lastMove"] = it
        payload.remove("lastMoveSan")
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

    val newMove = payload["lastMoveUci"] as? String
    if (isCurrentlyInPip() &&
        payload["soundEnabled"] == true &&
        !newMove.isNullOrBlank() &&
        newMove != previousMove &&
        newMove != lastSoundedMove) {
      lastSoundedMove = newMove
      val captured = fenPieceCount(payload["fen"] as? String) < fenPieceCount(previousFen)
      playPipSfx(captured)
    }
  }

  // Build the pool while still foreground so SoundPool.load (async) has finished
  // long before the first live move lands in PiP — a sample that is still loading
  // is dropped silently.
  private fun preloadPipSfx() {
    if (sfxPool != null) return
    val attributes = AudioAttributes.Builder()
      .setUsage(AudioAttributes.USAGE_GAME)
      .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
      .build()
    val pool = SoundPool.Builder().setMaxStreams(2).setAudioAttributes(attributes).build()
    moveSfxId = loadSfx(pool, "flutter_assets/assets/sfx/piece_move.wav")
    captureSfxId = loadSfx(pool, "flutter_assets/assets/sfx/piece_takeover.wav")
    sfxPool = pool
  }

  private fun loadSfx(pool: SoundPool, path: String): Int {
    return try {
      // openFd (not open) because SoundPool needs an offset/length into the APK.
      // .wav is in aapt2's no-compress list, so the entry is stored uncompressed.
      assets.openFd(path).use { pool.load(it, 1) }
    } catch (e: Exception) {
      Log.w("ChessPiP", "Failed to load PiP SFX $path", e)
      0
    }
  }

  private fun playPipSfx(captured: Boolean) {
    val pool = sfxPool ?: return
    val soundId = if (captured) captureSfxId else moveSfxId
    if (soundId == 0) return
    // No audio focus request: a move blip should not duck the user's music.
    pool.play(soundId, 1f, 1f, 1, 0, 1f)
  }

  private fun fenPieceCount(fen: String?): Int {
    val placement = fen?.substringBefore(' ') ?: return 0
    return placement.count { it.isLetter() }
  }

  private fun formatClock(seconds: Int): String {
    val clamped = max(0, seconds)
    val hours = clamped / 3600
    val minutes = (clamped % 3600) / 60
    val secs = clamped % 60
    return if (hours > 0) {
      "%d:%02d:%02d".format(hours, minutes, secs)
    } else {
      "%02d:%02d".format(minutes, secs)
    }
  }
}

private object PipApi26 {
  fun enter(activity: MainActivity, sourceRectHint: Rect?): Boolean {
    return activity.enterPictureInPictureMode(buildParams(sourceRectHint))
  }

  fun update(activity: MainActivity, sourceRectHint: Rect?) {
    activity.setPictureInPictureParams(buildParams(sourceRectHint))
  }

  private fun buildParams(sourceRectHint: Rect?): PictureInPictureParams {
    val builder = PictureInPictureParams.Builder()
      .setAspectRatio(Rational(1, 1))
    sourceRectHint?.let { builder.setSourceRectHint(it) }
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
      builder.setSeamlessResizeEnabled(false)
    }
    return builder.build()
  }
}

private class ChessPipOverlayView(context: Context) : View(context) {
  var payload: Map<String, Any?>? = null

  private val fideToIso2 = mapOf(
    "USA" to "US", "ENG" to "GB", "SCO" to "GB", "WLS" to "GB", "RUS" to "RU",
    "CHN" to "CN", "IND" to "IN", "GER" to "DE", "FRA" to "FR", "ESP" to "ES",
    "ITA" to "IT", "NED" to "NL", "POL" to "PL", "CZE" to "CZ", "HUN" to "HU",
    "ROU" to "RO", "UKR" to "UA", "AZE" to "AZ", "ARM" to "AM", "GEO" to "GE",
    "TUR" to "TR", "ISR" to "IL", "ARG" to "AR", "BRA" to "BR", "PER" to "PE",
    "CUB" to "CU", "CAN" to "CA", "MEX" to "MX", "COL" to "CO", "CHI" to "CL",
    "VEN" to "VE", "ECU" to "EC", "URU" to "UY", "PAR" to "PY", "BOL" to "BO",
    "CRC" to "CR", "PAN" to "PA", "GUA" to "GT", "ESA" to "SV", "HON" to "HN",
    "NOR" to "NO", "SWE" to "SE", "DEN" to "DK", "FIN" to "FI", "ISL" to "IS",
    "AUT" to "AT", "SUI" to "CH", "BEL" to "BE", "POR" to "PT", "GRE" to "GR",
    "BUL" to "BG", "CRO" to "HR", "SRB" to "RS", "SLO" to "SI", "SVK" to "SK",
    "BIH" to "BA", "MKD" to "MK", "MNE" to "ME", "ALB" to "AL", "MDA" to "MD",
    "BLR" to "BY", "LTU" to "LT", "LAT" to "LV", "EST" to "EE", "IRL" to "IE",
    "LUX" to "LU", "MLT" to "MT", "CYP" to "CY", "AND" to "AD", "MON" to "MC",
    "SMR" to "SM", "KAZ" to "KZ", "UZB" to "UZ", "KGZ" to "KG", "TJK" to "TJ",
    "TKM" to "TM", "IRI" to "IR", "IRQ" to "IQ", "JOR" to "JO", "LBN" to "LB",
    "SYR" to "SY", "UAE" to "AE", "QAT" to "QA", "KUW" to "KW", "BRN" to "BH",
    "OMA" to "OM", "KSA" to "SA", "YEM" to "YE", "EGY" to "EG", "MAR" to "MA",
    "ALG" to "DZ", "TUN" to "TN", "LBA" to "LY", "RSA" to "ZA", "NGR" to "NG",
    "KEN" to "KE", "ETH" to "ET", "GHA" to "GH", "UGA" to "UG", "ZAM" to "ZM",
    "ZIM" to "ZW", "BOT" to "BW", "ANG" to "AO", "MOZ" to "MZ", "MAD" to "MG",
    "AUS" to "AU", "NZL" to "NZ", "JPN" to "JP", "KOR" to "KR", "PRK" to "KP",
    "MGL" to "MN", "VIE" to "VN", "THA" to "TH", "MAS" to "MY", "SIN" to "SG",
    "INA" to "ID", "PHI" to "PH", "HKG" to "HK", "TPE" to "TW", "PAK" to "PK",
    "BAN" to "BD", "SRI" to "LK", "NEP" to "NP", "AFG" to "AF",
  )
  private val countryNameToIso2 = mapOf(
    "united states" to "US", "usa" to "US", "america" to "US",
    "england" to "GB", "scotland" to "GB", "wales" to "GB",
    "united kingdom" to "GB", "great britain" to "GB",
    "germany" to "DE", "france" to "FR", "spain" to "ES", "italy" to "IT",
    "netherlands" to "NL", "norway" to "NO", "sweden" to "SE", "denmark" to "DK",
    "finland" to "FI", "india" to "IN", "china" to "CN", "russia" to "RU",
    "ukraine" to "UA", "poland" to "PL", "czech republic" to "CZ",
    "hungary" to "HU", "romania" to "RO", "turkey" to "TR", "israel" to "IL",
    "armenia" to "AM", "azerbaijan" to "AZ", "georgia" to "GE",
    "canada" to "CA", "mexico" to "MX", "brazil" to "BR", "argentina" to "AR",
    "peru" to "PE", "cuba" to "CU", "australia" to "AU", "new zealand" to "NZ",
    "japan" to "JP", "south korea" to "KR", "iran" to "IR", "egypt" to "EG",
    "south africa" to "ZA",
  )
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
    val data = payload ?: emptyMap()
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
      status = data["status"] as? String,
      x = boardLeft,
      y = boardTop,
      size = actualBoardSize,
      boardThemeIndex = (data["boardThemeIndex"] as? Number)?.toInt() ?: 9,
      pieceStyleIndex = (data["pieceStyleIndex"] as? Number)?.toInt() ?: 0,
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

  fun sourceRectHint(): Rect? {
    if (width <= 0 || height <= 0) return null
    val rect = contentRect()
    val location = IntArray(2)
    getLocationOnScreen(location)
    return Rect(
      (location[0] + rect.left).roundToInt(),
      (location[1] + rect.top).roundToInt(),
      (location[0] + rect.right).roundToInt(),
      (location[1] + rect.bottom).roundToInt(),
    ).takeUnless { it.isEmpty }
  }

  private fun contentRect(): RectF {
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
    return RectF(groupLeft, top, groupLeft + groupWidth, top + totalHeight)
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
    val clock = displayClock(data, isWhite)
    val nameText = listOf(title, name, rating).filter { it.isNotBlank() }.joinToString(" ")

    textPaint.textSize = height * 0.48f
    secondaryPaint.textSize = height * 0.42f
    val flag = flagDisplay(fed)
    val flagW = if (flag != null) height * 0.9f else 0f
    if (flag != null) drawFlag(canvas, flag, RectF(x, y + height * 0.16f, x + flagW, y + height * 0.84f), height)

    val clockW = if (clock.isNotBlank()) textPaint.measureText(clock) + height * 0.5f else 0f
    if (clock.isNotBlank()) {
      val clockRect = RectF(x + width - clockW, y, x + width, y + height)
      Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.rgb(32, 169, 210) }.also {
        if (isOngoing(data) && clockSideIsWhite(data) == isWhite) canvas.drawRect(clockRect, it)
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

  private fun drawFlag(canvas: Canvas, flag: String, rect: RectF, rowHeight: Float) {
    val bg = Paint(Paint.ANTI_ALIAS_FLAG).apply {
      color = if (flag == "🌐") Color.rgb(55, 65, 81) else Color.TRANSPARENT
    }
    if (flag == "🌐" || flag == "FIDE") {
      canvas.drawRoundRect(rect, 4f, 4f, bg.apply {
        color = if (flag == "FIDE") Color.rgb(32, 169, 210) else Color.rgb(55, 65, 81)
      })
    }
    val fp = Paint(Paint.ANTI_ALIAS_FLAG).apply {
      color = Color.WHITE
      textAlign = Paint.Align.CENTER
      typeface = Typeface.DEFAULT_BOLD
      textSize = if (flag == "FIDE") rowHeight * 0.22f else rowHeight * 0.56f
    }
    canvas.drawText(flag, rect.centerX(), rect.centerY() - (fp.descent() + fp.ascent()) / 2f, fp)
  }

  private fun flagDisplay(rawFed: String): String? {
    val raw = rawFed.trim()
    if (raw.isEmpty()) return null
    val upper = raw.uppercase()
    val lower = raw.lowercase()
    if (setOf("UNKNOWN", "NONE", "UNRATED", "N/A", "NA", "?", "-").contains(upper)) return "🌐"
    if (upper == "FID" || upper == "FIDE") return "FIDE"

    val iso2 = when {
      upper.length == 2 -> upper
      upper.length == 3 -> fideToIso2[upper]
      else -> countryNameToIso2[lower]
    } ?: return null
    if (iso2.length != 2) return null
    return flagEmoji(iso2)
  }

  private fun flagEmoji(iso2: String): String {
    val base = 0x1F1E6 - 'A'.code
    return iso2.uppercase().mapNotNull { ch ->
      if (ch in 'A'..'Z') String(Character.toChars(base + ch.code)) else null
    }.joinToString("")
  }

  private fun displayClock(data: Map<String, Any?>, isWhite: Boolean): String {
    val prefix = if (isWhite) "white" else "black"
    val fallback = data["${prefix}Clock"] as? String ?: ""
    if (!isOngoing(data) || data["followLive"] == false || clockSideIsWhite(data) != isWhite) return fallback

    val baseSeconds = intValue(data["${prefix}ClockSeconds"]) ?: return fallback
    val lastMoveMillis = instantMillis(data["lastMoveTime"] as? String) ?: return fallback
    val elapsedSeconds = kotlin.math.abs((System.currentTimeMillis() - lastMoveMillis) / 1000L).toInt()
    return formatClock(max(0, baseSeconds - elapsedSeconds))
  }

  private fun isOngoing(data: Map<String, Any?>): Boolean {
    val status = (data["status"] as? String ?: "").trim().lowercase()
    return status.isEmpty() || status == "ongoing" || status == "*"
  }

  // Which side's clock is running. Flutter sends `clockTurnIsWhite` taken from the
  // same model it builds the clock values from; the board FEN can legitimately sit
  // a move behind that model, and deriving the ticking side from it would run the
  // wrong player's clock. Falls back to the FEN once the native poll takes over as
  // the source of truth (mergeLiveRow drops the key when it lands a fresh FEN).
  private fun clockSideIsWhite(data: Map<String, Any?>): Boolean {
    (data["clockTurnIsWhite"] as? Boolean)?.let { return it }
    return isWhiteToMove(data)
  }

  private fun isWhiteToMove(data: Map<String, Any?>): Boolean {
    val fen = data["fen"] as? String ?: ""
    val parts = fen.split(" ")
    return parts.getOrNull(1) != "b"
  }

  private fun intValue(value: Any?): Int? {
    return when (value) {
      is Int -> value
      is Number -> value.toInt()
      is String -> value.toIntOrNull()
      else -> null
    }
  }

  private fun instantMillis(value: String?): Long? {
    if (value.isNullOrBlank()) return null
    val normalized = value.trim()
    return parseInstantMillis(normalized)
      ?: parseOffsetDateTimeMillis(normalized)
      ?: parseLocalDateTimeMillis(normalized)
  }

  private fun parseInstantMillis(value: String): Long? {
    return try {
      Instant.parse(value).toEpochMilli()
    } catch (_: Exception) {
      null
    }
  }

  private fun parseOffsetDateTimeMillis(value: String): Long? {
    return try {
      OffsetDateTime.parse(value).toInstant().toEpochMilli()
    } catch (_: Exception) {
      null
    }
  }

  private fun parseLocalDateTimeMillis(value: String): Long? {
    return try {
      LocalDateTime.parse(value).toInstant(ZoneOffset.UTC).toEpochMilli()
    } catch (_: Exception) {
      null
    }
  }

  private fun formatClock(seconds: Int): String {
    val clamped = max(0, seconds)
    val hours = clamped / 3600
    val minutes = (clamped % 3600) / 60
    val secs = clamped % 60
    return if (hours > 0) {
      "%d:%02d:%02d".format(hours, minutes, secs)
    } else {
      "%02d:%02d".format(minutes, secs)
    }
  }

  private fun drawBoard(
    canvas: Canvas,
    fen: String,
    lastMove: String?,
    status: String?,
    x: Float,
    y: Float,
    size: Float,
    boardThemeIndex: Int,
    pieceStyleIndex: Int
  ) {
    val board = parseFenBoard(fen)
    val square = size / 8f
    val (light, dark) = boardThemeColors(boardThemeIndex)
    val lightPaint = Paint().apply { color = light }
    val darkPaint = Paint().apply { color = dark }
    val fromTo = parseUciSquares(lastMove)
    val from = fromTo.getOrNull(0)
    val to = fromTo.getOrNull(1)
    val lastMoveLightPaint = Paint().apply { color = Color.rgb(173, 185, 207) }
    val lastMoveDarkPaint = Paint().apply { color = Color.rgb(157, 170, 194) }
    val loserKing = loserKingPiece(status)
    val loserSquare = loserKing?.let { findPiece(board, it) }
    val drawSquares = if (isDrawStatus(status)) {
      listOfNotNull(findPiece(board, 'K'), findPiece(board, 'k'))
    } else {
      emptyList()
    }
    val loserPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
      color = Color.argb(204, 245, 50, 54)
    }
    val drawPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
      color = Color.argb(205, 173, 225, 205)
    }

    for (rank in 0 until 8) {
      for (file in 0 until 8) {
        val left = x + file * square
        val top = y + rank * square
        canvas.drawRect(left, top, left + square, top + square, if ((rank + file) % 2 == 0) lightPaint else darkPaint)
        val sq = BoardSquare(file, rank)
        if (sq == from || sq == to) {
          canvas.drawRect(
            left,
            top,
            left + square,
            top + square,
            if (isLightChessSquare(file, rank)) lastMoveLightPaint else lastMoveDarkPaint
          )
        }
        val isLoserKingSquare = loserSquare == sq
        if (isLoserKingSquare) canvas.drawRect(left, top, left + square, top + square, loserPaint)
        val isDrawKingSquare = drawSquares.any { it.file == file && it.rank == rank }
        if (isDrawKingSquare) canvas.drawRect(left, top, left + square, top + square, drawPaint)
        val piece = board[rank][file]
        if (piece != '\u0000') {
          val inset = square * 0.07f
          val rect = RectF(left + inset, top + inset, left + square - inset, top + square - inset)
          drawPiece(canvas, piece, rect, if (isLoserKingSquare) -45f else 0f, pieceStyleIndex)
        }
        if (isDrawKingSquare) {
          drawDrawIcon(canvas, RectF(left, top, left + square, top + square))
        }
      }
    }
  }

  private fun isLightChessSquare(file: Int, displayRank: Int): Boolean {
    return (file + (7 - displayRank)) % 2 == 1
  }

  private fun loserKingPiece(status: String?): Char? {
    return when (status?.trim()?.lowercase()) {
      "whitewins", "white_wins", "1-0", "w" -> 'k'
      "blackwins", "black_wins", "0-1", "b" -> 'K'
      else -> null
    }
  }

  private fun drawPiece(canvas: Canvas, piece: Char, rect: RectF, rotationDegrees: Float, pieceStyleIndex: Int) {
    canvas.save()
    if (rotationDegrees != 0f) {
      canvas.rotate(rotationDegrees, rect.centerX(), rect.centerY())
    }
    val bitmap = loadPieceBitmap(piece, pieceStyleIndex)
    if (bitmap != null) {
      canvas.drawBitmap(bitmap, null, rect, null)
    } else {
      val fp = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = if (piece.isUpperCase()) Color.WHITE else Color.BLACK
        textAlign = Paint.Align.CENTER
        typeface = Typeface.DEFAULT_BOLD
        textSize = rect.height() * 0.62f
      }
      canvas.drawText(piece.uppercaseChar().toString(), rect.centerX(), rect.centerY() - (fp.descent() + fp.ascent()) / 2, fp)
    }
    canvas.restore()
  }

  private fun isDrawStatus(status: String?): Boolean {
    val normalized = status?.trim()?.lowercase() ?: return false
    return normalized == "draw" ||
      normalized == "1/2-1/2" ||
      normalized == "½-½" ||
      normalized == "0.5-0.5" ||
      normalized == "d"
  }

  private fun findPiece(board: Array<CharArray>, piece: Char): BoardSquare? {
    for (rank in 0 until 8) {
      for (file in 0 until 8) {
        if (board[rank][file] == piece) return BoardSquare(file, rank)
      }
    }
    return null
  }

  private fun drawDrawIcon(canvas: Canvas, squareRect: RectF) {
    val iconSize = squareRect.width() * 0.24f
    val iconRect = RectF(
      squareRect.right - iconSize * 1.06f,
      squareRect.top + iconSize * 0.08f,
      squareRect.right - iconSize * 0.06f,
      squareRect.top + iconSize * 1.08f
    )
    val bg = Paint(Paint.ANTI_ALIAS_FLAG).apply {
      color = Color.argb(220, 32, 169, 210)
    }
    canvas.drawOval(iconRect, bg)
    val text = Paint(Paint.ANTI_ALIAS_FLAG).apply {
      color = Color.WHITE
      textAlign = Paint.Align.CENTER
      typeface = Typeface.DEFAULT_BOLD
      textSize = iconSize * 0.48f
    }
    canvas.drawText("1/2", iconRect.centerX(), iconRect.centerY() - (text.descent() + text.ascent()) / 2f, text)
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

  // Piece set folder names matching chessground PieceSet.values order (index 0..39),
  // so pieceStyleIndex selects the same set the in-app board renders.
  private val pieceSetNames = listOf(
    "cburnett", "merida", "pirouetti", "chessnut", "chess7", "alpha", "reillycraig",
    "companion", "riohacha", "kosal", "leipzig", "fantasy", "spatial", "celtic",
    "california", "caliente", "pixel", "firi", "rhosgfx", "maestro", "fresca",
    "cardinal", "gioco", "tatiana", "staunty", "governor", "dubrovny", "icpieces",
    "mpchess", "monarchy", "cooke", "shapes", "kiwen-suwi", "horsey", "anarcandy",
    "xkcd", "letter", "disguised", "symmetric", "totoy",
  )

  private fun pieceSetName(index: Int): String = pieceSetNames.getOrElse(index) { "cburnett" }

  private fun pieceAssetCode(piece: Char): String? {
    val type = when (piece.uppercaseChar()) {
      'K', 'Q', 'R', 'B', 'N', 'P' -> piece.uppercaseChar()
      else -> return null
    }
    val color = if (piece.isUpperCase()) "w" else "b"
    return "$color$type"
  }

  private fun loadPieceBitmap(piece: Char, pieceStyleIndex: Int): Bitmap? {
    val code = pieceAssetCode(piece) ?: return null
    val set = pieceSetName(pieceStyleIndex)
    val cacheKey = "$set/$code"
    return pieceCache.getOrPut(cacheKey) {
      loadPieceFromAssets(set, code) ?: loadPieceFromDrawable(piece)
    }
  }

  private fun loadPieceFromAssets(set: String, code: String): Bitmap? {
    val path = "flutter_assets/packages/chessground/assets/piece_sets/$set/$code.webp"
    return try {
      context.assets.open(path).use { BitmapFactory.decodeStream(it) }
    } catch (_: Exception) {
      null
    }
  }

  private fun loadPieceFromDrawable(piece: Char): Bitmap? {
    val resName = when (piece) {
      'K' -> "piece_wk"; 'Q' -> "piece_wq"; 'R' -> "piece_wr"; 'B' -> "piece_wb"; 'N' -> "piece_wn"; 'P' -> "piece_wp"
      'k' -> "piece_bk"; 'q' -> "piece_bq"; 'r' -> "piece_br"; 'b' -> "piece_bb"; 'n' -> "piece_bn"; 'p' -> "piece_bp"
      else -> return null
    }
    val resId = context.resources.getIdentifier(resName, "drawable", context.packageName)
    return if (resId == 0) null else BitmapFactory.decodeResource(context.resources, resId)
  }

  // Solid light/dark square colors for each chessground board theme, matching
  // kBoardThemes order in lib/utils/board_customization_utils.dart (index 0..24).
  // Default index 9 (Grey) mirrors BoardSettingsModel.defaultSettings.
  private fun boardThemeColors(index: Int): Pair<Int, Int> = when (index) {
    0 -> Pair(0xFFF0D9B6.toInt(), 0xFFB58863.toInt())
    1 -> Pair(0xFFDEE3E6.toInt(), 0xFF8CA2AD.toInt())
    2 -> Pair(0xFFFFFFDD.toInt(), 0xFF86A666.toInt())
    3 -> Pair(0xFFECECEC.toInt(), 0xFFC1C18E.toInt())
    4 -> Pair(0xFF97B2C7.toInt(), 0xFF546F82.toInt())
    5 -> Pair(0xFFD9E0E6.toInt(), 0xFF315991.toInt())
    6 -> Pair(0xFFEAE6DD.toInt(), 0xFF7C7F87.toInt())
    7 -> Pair(0xFFD7DAEB.toInt(), 0xFF547388.toInt())
    8 -> Pair(0xFFF2F9BB.toInt(), 0xFF59935D.toInt())
    9 -> Pair(0xFFB8B8B8.toInt(), 0xFF7D7D7D.toInt())
    10 -> Pair(0xFFF0D9B5.toInt(), 0xFF946F51.toInt())
    11 -> Pair(0xFFD1D1C9.toInt(), 0xFFC28E16.toInt())
    12 -> Pair(0xFFE8CEAB.toInt(), 0xFFBC7944.toInt())
    13 -> Pair(0xFFE2C89F.toInt(), 0xFF996633.toInt())
    14 -> Pair(0xFF93AB91.toInt(), 0xFF4F644E.toInt())
    15 -> Pair(0xFFC9C9C9.toInt(), 0xFF727272.toInt())
    16 -> Pair(0xFFFFFFFF.toInt(), 0xFF8D8D8D.toInt())
    17 -> Pair(0xFFB8B19F.toInt(), 0xFF6D6655.toInt())
    18 -> Pair(0xFFE8E9B7.toInt(), 0xFFED7272.toInt())
    19 -> Pair(0xFF9F90B0.toInt(), 0xFF7D4A8D.toInt())
    20 -> Pair(0xFFE5DAF0.toInt(), 0xFF957AB0.toInt())
    21 -> Pair(0xFFD8A45B.toInt(), 0xFF9B4D0F.toInt())
    22 -> Pair(0xFFA38B5D.toInt(), 0xFF6C5017.toInt())
    23 -> Pair(0xFFD0CECA.toInt(), 0xFF755839.toInt())
    24 -> Pair(0xFFCAAF7D.toInt(), 0xFF7B5330.toInt())
    else -> Pair(0xFFB8B8B8.toInt(), 0xFF7D7D7D.toInt())
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
