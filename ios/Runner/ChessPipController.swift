import AVFoundation
import AVKit
import Flutter
import UIKit

final class ChessPipController: NSObject {
  static let shared = ChessPipController()

  private var channel: FlutterMethodChannel?
  private var payload: [String: Any]?
  private var displayLayer: AVSampleBufferDisplayLayer?
  private var pipController: AVPictureInPictureController?
  private var timebase: CMTimebase?
  private var frameIndex: Int64 = 0
  private var renderTimer: DispatchSourceTimer?
  private var pollTimer: DispatchSourceTimer?
  private let pollQueue = DispatchQueue(label: "com.chessever.pip.poll")
  // Foreground keeps the layer "playing" with a cached frame; we only redraw the
  // 720x720 board when content changed or PiP is actually visible (ticking clock).
  private var cachedImage: CGImage?
  private var renderDirty = true
  // Native move SFX for PiP: Dart/SoLoud is suspended in the background, so the
  // poll plays these directly when a new move arrives while PiP is active.
  private var moveSoundPlayer: AVAudioPlayer?
  private var captureSoundPlayer: AVAudioPlayer?
  private var lastSoundedMove: String?

  private override init() {
    super.init()
  }

  func configure(binaryMessenger: FlutterBinaryMessenger) {
    let methodChannel = FlutterMethodChannel(
      name: "com.chessever/pip",
      binaryMessenger: binaryMessenger
    )
    channel = methodChannel
    methodChannel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(false)
        return
      }
      switch call.method {
      case "setActiveGame":
        guard
          let args = call.arguments as? [String: Any],
          args["eligible"] as? Bool == true
        else {
          self.clear()
          result(nil)
          return
        }
        self.payload = args
        self.renderDirty = true
        // Foreground baseline so the first PiP poll doesn't replay this move.
        self.lastSoundedMove = args["lastMoveUci"] as? String
        self.prepareIfNeeded()
        self.enqueueFrame()
        // Keep the sample-buffer layer actively streaming while foreground so
        // iOS can auto-start PiP on background, and so isPictureInPicturePossible
        // is already true for the manual enterIfEligible fallback.
        self.startRenderLoop()
        if self.pipController?.isPictureInPictureActive == true {
          self.startNativePollingIfPossible()
        }
        result(nil)
      case "updatePosition":
        guard
          let args = call.arguments as? [String: Any],
          args["eligible"] as? Bool == true
        else {
          self.clear()
          result(nil)
          return
        }
        self.mergePayload(args)
        // Foreground pushes update the baseline; SoLoud handles foreground SFX.
        if self.pipController?.isPictureInPictureActive != true {
          self.lastSoundedMove = args["lastMoveUci"] as? String
        }
        self.prepareIfNeeded()
        self.enqueueFrame()
        // Keep the sample-buffer layer actively streaming while foreground so
        // iOS can auto-start PiP on background, and so isPictureInPicturePossible
        // is already true for the manual enterIfEligible fallback.
        self.startRenderLoop()
        if self.pipController?.isPictureInPictureActive == true {
          self.startNativePollingIfPossible()
        }
        result(nil)
      case "enterIfEligible":
        result(self.enterIfEligible())
      case "clearActiveGame":
        self.clear()
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func prepareIfNeeded() {
    guard #available(iOS 15.0, *) else { return }
    guard AVPictureInPictureController.isPictureInPictureSupported() else { return }
    if pipController != nil { return }

    // Audio session must be active and use a category that supports PiP
    // BEFORE the controller is created and while we are still foreground.
    configureAudioSession()
    preloadSounds()

    let layer = AVSampleBufferDisplayLayer()
    layer.videoGravity = .resizeAspect
    layer.backgroundColor = UIColor.black.cgColor

    // For `canStartPictureInPictureAutomaticallyFromInline` to fire when the
    // app is backgrounded, the source layer must be attached to the visible
    // view hierarchy. We add it as a tiny, effectively invisible inline layer.
    attachLayerToRootView(layer)

    var tb: CMTimebase?
    CMTimebaseCreateWithSourceClock(
      allocator: kCFAllocatorDefault,
      sourceClock: CMClockGetHostTimeClock(),
      timebaseOut: &tb
    )
    if let tb {
      CMTimebaseSetRate(tb, rate: 1.0)
      layer.controlTimebase = tb
      timebase = tb
    }

    let source = AVPictureInPictureController.ContentSource(
      sampleBufferDisplayLayer: layer,
      playbackDelegate: self
    )
    let controller = AVPictureInPictureController(contentSource: source)
    controller.delegate = self
    applyPipControlPreferences(to: controller)
    controller.canStartPictureInPictureAutomaticallyFromInline = true

    displayLayer = layer
    pipController = controller
  }

  private func applyPipControlPreferences(to controller: AVPictureInPictureController) {
    controller.requiresLinearPlayback = true

    let controlsStyleSelector = NSSelectorFromString("setControlsStyle:")
    guard controller.responds(to: controlsStyleSelector) else { return }

    // AVPictureInPictureController does not expose a public API to hide the
    // playback overlay. This private style hides play/stop, skip buttons, and
    // the scrubber while keeping the system close/restore window controls.
    controller.setValue(1, forKey: "controlsStyle")
  }

  private func attachLayerToRootView(_ layer: AVSampleBufferDisplayLayer) {
    let rootView = Self.keyWindow?.rootViewController?.view
    guard let rootView else { return }
    // Small, near-invisible inline frame: present in the hierarchy (so the
    // system treats PiP as "inline") but visually unobtrusive.
    layer.frame = CGRect(x: 0, y: 0, width: 1, height: 1)
    layer.opacity = 0.01
    rootView.layer.addSublayer(layer)
  }

  private static var keyWindow: UIWindow? {
    UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap { $0.windows }
      .first { $0.isKeyWindow }
  }

  private func enterIfEligible() -> Bool {
    guard payload?["eligible"] as? Bool == true else { return false }
    configureAudioSession()
    prepareIfNeeded()
    enqueueFrame()
    startRenderLoop()
    guard let pipController else {
      print("[PiP] enterIfEligible: controller nil (PiP unsupported or pre-iOS15)")
      return false
    }
    if pipController.isPictureInPictureActive { return true }
    guard pipController.isPictureInPicturePossible else {
      print("[PiP] enterIfEligible: isPictureInPicturePossible=false — layer not yet streaming or audio session not .playback (category=\(AVAudioSession.sharedInstance().category.rawValue))")
      return false
    }
    startNativePollingIfPossible()
    pipController.startPictureInPicture()
    print("[PiP] enterIfEligible: startPictureInPicture() invoked")
    return true
  }

  private func clear() {
    payload = nil
    lastSoundedMove = nil
    stopNativePolling()
    stopRenderLoop()
    if pipController?.isPictureInPictureActive == true {
      pipController?.stopPictureInPicture()
    }
    // Hand the audio session back to the SFX layer (ambient respects the silent
    // switch and mixes with other audio) now that no game is PiP-eligible.
    restoreAmbientAudioSession()
  }

  private func configureAudioSession() {
    do {
      let session = AVAudioSession.sharedInstance()
      try session.setCategory(.playback, mode: .moviePlayback, options: [.mixWithOthers])
      try session.setActive(true)
    } catch {
      print("[PiP] Failed to configure audio session: \(error)")
    }
  }

  // Re-assert .playback if something (e.g. flutter_soloud lazily initializing on
  // the first move sound) reset the category to .ambient. PiP requires .playback
  // to be the active category at the moment the app backgrounds.
  private func ensurePlaybackAudioSession() {
    let session = AVAudioSession.sharedInstance()
    guard session.category != .playback else { return }
    do {
      try session.setCategory(.playback, mode: .moviePlayback, options: [.mixWithOthers])
      try session.setActive(true)
    } catch {
      print("[PiP] Failed to re-assert playback audio session: \(error)")
    }
  }

  private func restoreAmbientAudioSession() {
    do {
      try AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default, options: [.mixWithOthers])
    } catch {
      print("[PiP] Failed to restore ambient audio session: \(error)")
    }
  }

  private func preloadSounds() {
    if moveSoundPlayer == nil {
      moveSoundPlayer = Self.loadSound("assets/sfx/piece_move.wav")
    }
    if captureSoundPlayer == nil {
      captureSoundPlayer = Self.loadSound("assets/sfx/piece_takeover.wav")
    }
  }

  private static func loadSound(_ assetSubpath: String) -> AVAudioPlayer? {
    let candidates = [
      "flutter_assets/\(assetSubpath)",
      "Frameworks/App.framework/flutter_assets/\(assetSubpath)",
    ]
    var url: URL?
    for candidate in candidates {
      if let path = Bundle.main.path(forResource: candidate, ofType: nil) {
        url = URL(fileURLWithPath: path)
        break
      }
      if let resourcePath = Bundle.main.resourcePath {
        let path = (resourcePath as NSString).appendingPathComponent(candidate)
        if FileManager.default.fileExists(atPath: path) {
          url = URL(fileURLWithPath: path)
          break
        }
      }
    }
    guard let url, let player = try? AVAudioPlayer(contentsOf: url) else {
      print("[PiP] Failed to load sound \(assetSubpath)")
      return nil
    }
    player.prepareToPlay()
    return player
  }

  // Play the move/capture SFX natively while in PiP (Dart/SoLoud is suspended in
  // the background). Foreground keeps using SoLoud, so this is gated to PiP-active
  // to avoid double sounds.
  private func playMoveSoundIfNeeded(
    previousMove: String?,
    newMove: String?,
    previousFen: String?,
    newFen: String?
  ) {
    guard pipController?.isPictureInPictureActive == true else { return }
    guard
      let newMove,
      !newMove.isEmpty,
      newMove != previousMove,
      newMove != lastSoundedMove
    else { return }
    lastSoundedMove = newMove

    let captured = Self.pieceCount(newFen) < Self.pieceCount(previousFen)
    let player = (captured ? captureSoundPlayer : moveSoundPlayer) ?? moveSoundPlayer
    player?.currentTime = 0
    player?.play()
  }

  private static func pieceCount(_ fen: String?) -> Int {
    guard let placement = fen?.split(separator: " ").first else { return 0 }
    return placement.reduce(0) { $0 + ($1.isLetter ? 1 : 0) }
  }

  private func enqueueFrame() {
    guard let displayLayer, let payload else { return }
    if !Thread.isMainThread {
      DispatchQueue.main.async { [weak self] in self?.enqueueFrame() }
      return
    }
    if displayLayer.status == .failed {
      displayLayer.flush()
    }
    let isActive = pipController?.isPictureInPictureActive == true
    let image: CGImage
    if !renderDirty, !isActive, let cached = cachedImage {
      // Foreground & invisible: re-enqueue the cached frame just to keep the
      // layer actively playing (cheap), skipping the Core Graphics redraw.
      image = cached
    } else {
      guard let rendered = ChessPipRenderer.render(payload: payload, size: CGSize(width: 720, height: 720)) else {
        return
      }
      image = rendered
      cachedImage = rendered
      renderDirty = false
    }
    guard let sampleBuffer = makeSampleBuffer(image: image) else { return }
    displayLayer.enqueue(sampleBuffer)
  }

  private func makeSampleBuffer(image: CGImage) -> CMSampleBuffer? {
    let width = image.width
    let height = image.height
    var pixelBuffer: CVPixelBuffer?
    let attrs: [String: Any] = [
      kCVPixelBufferCGImageCompatibilityKey as String: true,
      kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
      kCVPixelBufferIOSurfacePropertiesKey as String: [:],
    ]
    let status = CVPixelBufferCreate(
      kCFAllocatorDefault,
      width,
      height,
      kCVPixelFormatType_32BGRA,
      attrs as CFDictionary,
      &pixelBuffer
    )
    guard status == kCVReturnSuccess, let pixelBuffer else { return nil }

    CVPixelBufferLockBaseAddress(pixelBuffer, [])
    defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

    guard
      let context = CGContext(
        data: CVPixelBufferGetBaseAddress(pixelBuffer),
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
      )
    else { return nil }

    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

    var formatDescription: CMVideoFormatDescription?
    CMVideoFormatDescriptionCreateForImageBuffer(
      allocator: kCFAllocatorDefault,
      imageBuffer: pixelBuffer,
      formatDescriptionOut: &formatDescription
    )
    guard let formatDescription else { return nil }

    let pts = CMTime(value: frameIndex, timescale: 2)
    frameIndex += 1
    var timing = CMSampleTimingInfo(
      duration: CMTime(value: 1, timescale: 2),
      presentationTimeStamp: pts,
      decodeTimeStamp: .invalid
    )
    var sampleBuffer: CMSampleBuffer?
    CMSampleBufferCreateReadyWithImageBuffer(
      allocator: kCFAllocatorDefault,
      imageBuffer: pixelBuffer,
      formatDescription: formatDescription,
      sampleTiming: &timing,
      sampleBufferOut: &sampleBuffer
    )
    if let sampleBuffer {
      markSampleBufferDisplayImmediately(sampleBuffer)
    }
    return sampleBuffer
  }

  private func markSampleBufferDisplayImmediately(_ sampleBuffer: CMSampleBuffer) {
    guard
      let attachments = CMSampleBufferGetSampleAttachmentsArray(
        sampleBuffer,
        createIfNecessary: true
      ),
      CFArrayGetCount(attachments) > 0
    else { return }

    let rawAttachment = CFArrayGetValueAtIndex(attachments, 0)
    let attachment = unsafeBitCast(rawAttachment, to: CFMutableDictionary.self)
    CFDictionarySetValue(
      attachment,
      Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
      Unmanaged.passUnretained(kCFBooleanTrue).toOpaque()
    )
  }

  private func mergePayload(_ update: [String: Any]) {
    var merged = payload ?? [:]
    for (key, value) in update {
      merged[key] = value
    }
    payload = merged
    renderDirty = true
  }

  private func startRenderLoop() {
    guard renderTimer == nil else { return }
    let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.main)
    timer.schedule(deadline: .now(), repeating: 1.0)
    timer.setEventHandler { [weak self] in
      guard let self, self.payload != nil else { return }
      // Only re-assert .playback while PiP is actually visible. Doing it every
      // second in the foreground churned the shared AVAudioSession and competed
      // with the app's SoLoud engine + main thread (a slowdown source). In the
      // foreground the loop just re-enqueues the cached frame to keep the layer
      // PiP-eligible — no audio-session work needed.
      if self.pipController?.isPictureInPictureActive == true {
        self.ensurePlaybackAudioSession()
      }
      self.enqueueFrame()
    }
    timer.resume()
    renderTimer = timer
  }

  private func stopRenderLoop() {
    renderTimer?.cancel()
    renderTimer = nil
  }

  private func startNativePollingIfPossible() {
    guard pollTimer == nil else { return }
    guard pollingConfig() != nil else {
      print("[PiP] Native polling unavailable: missing Supabase config")
      return
    }

    let timer = DispatchSource.makeTimerSource(queue: pollQueue)
    timer.schedule(deadline: .now(), repeating: 4.0)
    timer.setEventHandler { [weak self] in
      self?.pollLatestGame()
    }
    timer.resume()
    pollTimer = timer
  }

  private func stopNativePolling() {
    pollTimer?.cancel()
    pollTimer = nil
  }

  private func pollingConfig() -> (gameId: String, url: String, anonKey: String, bearer: String)? {
    guard
      let payload,
      let gameId = payload["gameId"] as? String,
      !gameId.isEmpty,
      let url = payload["supabaseUrl"] as? String,
      !url.isEmpty,
      let anonKey = payload["supabaseAnonKey"] as? String,
      !anonKey.isEmpty
    else { return nil }

    let accessToken = payload["supabaseAccessToken"] as? String
    return (gameId, url, anonKey, accessToken?.isEmpty == false ? accessToken! : anonKey)
  }

  private func pollLatestGame() {
    guard let config = pollingConfig() else { return }

    var components = URLComponents(string: "\(config.url)/rest/v1/games")
    components?.queryItems = [
      URLQueryItem(
        name: "select",
        value: "fen,last_move,last_move_time,last_clock_white,last_clock_black,status"
      ),
      URLQueryItem(name: "id", value: "eq.\(config.gameId)"),
      URLQueryItem(name: "limit", value: "1"),
    ]
    guard let url = components?.url else { return }

    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    request.setValue(config.anonKey, forHTTPHeaderField: "apikey")
    request.setValue("Bearer \(config.bearer)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Accept")

    URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
      if let error {
        print("[PiP] Native poll failed: \(error)")
        return
      }
      if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
        print("[PiP] Native poll HTTP \(http.statusCode)")
        return
      }
      guard
        let data,
        let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
        let row = rows.first
      else { return }

      DispatchQueue.main.async {
        self?.mergeLiveRow(row)
      }
    }.resume()
  }

  private func mergeLiveRow(_ row: [String: Any]) {
    guard var payload else { return }
    // Frozen on an earlier move: keep the viewed position, ignore newer live data.
    if (payload["followLive"] as? Bool) == false { return }

    let previousMove = payload["lastMoveUci"] as? String ?? payload["lastMove"] as? String
    let previousFen = payload["fen"] as? String

    if let fen = row["fen"] as? String, !fen.isEmpty {
      payload["fen"] = fen
    }
    if let lastMove = row["last_move"] as? String, !lastMove.isEmpty {
      payload["lastMoveUci"] = lastMove
      payload["lastMove"] = lastMove
    }
    if let lastMoveTime = row["last_move_time"] as? String, !lastMoveTime.isEmpty {
      payload["lastMoveTime"] = lastMoveTime
    }
    if let whiteClock = row["last_clock_white"] as? NSNumber {
      payload["whiteClockSeconds"] = whiteClock.intValue
      payload["whiteClock"] = Self.formatClock(seconds: whiteClock.intValue)
    }
    if let blackClock = row["last_clock_black"] as? NSNumber {
      payload["blackClockSeconds"] = blackClock.intValue
      payload["blackClock"] = Self.formatClock(seconds: blackClock.intValue)
    }
    if let status = row["status"] as? String {
      payload["status"] = status
    }

    self.payload = payload
    renderDirty = true
    enqueueFrame()
    playMoveSoundIfNeeded(
      previousMove: previousMove,
      newMove: payload["lastMoveUci"] as? String,
      previousFen: previousFen,
      newFen: payload["fen"] as? String
    )
  }

  private static func formatClock(seconds: Int) -> String {
    let clamped = max(0, seconds)
    let hours = clamped / 3600
    let minutes = (clamped % 3600) / 60
    let secs = clamped % 60
    if hours > 0 {
      return String(format: "%d:%02d:%02d", hours, minutes, secs)
    }
    return String(format: "%02d:%02d", minutes, secs)
  }
}

extension ChessPipController: AVPictureInPictureControllerDelegate {
  func pictureInPictureControllerDidStartPictureInPicture(
    _ pictureInPictureController: AVPictureInPictureController
  ) {
    startRenderLoop()
    startNativePollingIfPossible()
    channel?.invokeMethod("onPipModeChanged", arguments: ["isInPip": true])
  }

  func pictureInPictureControllerDidStopPictureInPicture(
    _ pictureInPictureController: AVPictureInPictureController
  ) {
    stopNativePolling()
    stopRenderLoop()
    channel?.invokeMethod("onPipModeChanged", arguments: ["isInPip": false])
  }

  // Tapping the PiP window's restore control asks the app to bring its UI back.
  // AVKit holds the PiP overlay and the expand animation until we acknowledge
  // restoration via this completion handler; if the delegate method is absent,
  // AVKit waits out its internal timeout — that stall is the multi-second freeze
  // seen when returning from PiP. Flutter runs a single FlutterViewController
  // that is still mounted underneath the overlay, so there is nothing to
  // re-present: ack immediately on the main thread so the transition snaps back.
  func pictureInPictureController(
    _ pictureInPictureController: AVPictureInPictureController,
    restoreUserInterfaceForPictureInPictureStop completionHandler: @escaping (Bool) -> Void
  ) {
    if Thread.isMainThread {
      completionHandler(true)
    } else {
      DispatchQueue.main.async { completionHandler(true) }
    }
  }
}

@available(iOS 15.0, *)
extension ChessPipController: AVPictureInPictureSampleBufferPlaybackDelegate {
  func pictureInPictureController(
    _ pictureInPictureController: AVPictureInPictureController,
    setPlaying playing: Bool
  ) {}

  func pictureInPictureControllerTimeRangeForPlayback(
    _ pictureInPictureController: AVPictureInPictureController
  ) -> CMTimeRange {
    CMTimeRange(start: .zero, duration: .positiveInfinity)
  }

  func pictureInPictureControllerIsPlaybackPaused(
    _ pictureInPictureController: AVPictureInPictureController
  ) -> Bool {
    false
  }

  func pictureInPictureController(
    _ pictureInPictureController: AVPictureInPictureController,
    didTransitionToRenderSize newRenderSize: CMVideoDimensions
  ) {}

  func pictureInPictureController(
    _ pictureInPictureController: AVPictureInPictureController,
    skipByInterval skipInterval: CMTime,
    completion completionHandler: @escaping () -> Void
  ) {
    completionHandler()
  }
}

private enum ChessPipRenderer {
  private static let isoDateFormatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
  }()

  private static let isoDateFormatterNoFraction: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter
  }()

  private static let fideToIso2: [String: String] = [
    "USA": "US", "ENG": "GB", "SCO": "GB", "WLS": "GB", "RUS": "RU",
    "CHN": "CN", "IND": "IN", "GER": "DE", "FRA": "FR", "ESP": "ES",
    "ITA": "IT", "NED": "NL", "POL": "PL", "CZE": "CZ", "HUN": "HU",
    "ROU": "RO", "UKR": "UA", "AZE": "AZ", "ARM": "AM", "GEO": "GE",
    "TUR": "TR", "ISR": "IL", "ARG": "AR", "BRA": "BR", "PER": "PE",
    "CUB": "CU", "CAN": "CA", "MEX": "MX", "COL": "CO", "CHI": "CL",
    "VEN": "VE", "ECU": "EC", "URU": "UY", "PAR": "PY", "BOL": "BO",
    "CRC": "CR", "PAN": "PA", "GUA": "GT", "ESA": "SV", "HON": "HN",
    "NOR": "NO", "SWE": "SE", "DEN": "DK", "FIN": "FI", "ISL": "IS",
    "AUT": "AT", "SUI": "CH", "BEL": "BE", "POR": "PT", "GRE": "GR",
    "BUL": "BG", "CRO": "HR", "SRB": "RS", "SLO": "SI", "SVK": "SK",
    "BIH": "BA", "MKD": "MK", "MNE": "ME", "ALB": "AL", "MDA": "MD",
    "BLR": "BY", "LTU": "LT", "LAT": "LV", "EST": "EE", "IRL": "IE",
    "LUX": "LU", "MLT": "MT", "CYP": "CY", "AND": "AD", "MON": "MC",
    "SMR": "SM", "KAZ": "KZ", "UZB": "UZ", "KGZ": "KG", "TJK": "TJ",
    "TKM": "TM", "IRI": "IR", "IRQ": "IQ", "JOR": "JO", "LBN": "LB",
    "SYR": "SY", "UAE": "AE", "QAT": "QA", "KUW": "KW", "BRN": "BH",
    "OMA": "OM", "KSA": "SA", "YEM": "YE", "EGY": "EG", "MAR": "MA",
    "ALG": "DZ", "TUN": "TN", "LBA": "LY", "RSA": "ZA", "NGR": "NG",
    "KEN": "KE", "ETH": "ET", "GHA": "GH", "UGA": "UG", "ZAM": "ZM",
    "ZIM": "ZW", "BOT": "BW", "ANG": "AO", "MOZ": "MZ", "MAD": "MG",
    "AUS": "AU", "NZL": "NZ", "JPN": "JP", "KOR": "KR", "PRK": "KP",
    "MGL": "MN", "VIE": "VN", "THA": "TH", "MAS": "MY", "SIN": "SG",
    "INA": "ID", "PHI": "PH", "HKG": "HK", "TPE": "TW", "PAK": "PK",
    "BAN": "BD", "SRI": "LK", "NEP": "NP", "AFG": "AF",
  ]

  private static let countryNameToIso2: [String: String] = [
    "united states": "US", "usa": "US", "america": "US",
    "england": "GB", "scotland": "GB", "wales": "GB",
    "united kingdom": "GB", "great britain": "GB",
    "germany": "DE", "france": "FR", "spain": "ES", "italy": "IT",
    "netherlands": "NL", "norway": "NO", "sweden": "SE", "denmark": "DK",
    "finland": "FI", "india": "IN", "china": "CN", "russia": "RU",
    "ukraine": "UA", "poland": "PL", "czech republic": "CZ",
    "hungary": "HU", "romania": "RO", "turkey": "TR", "israel": "IL",
    "armenia": "AM", "azerbaijan": "AZ", "georgia": "GE",
    "canada": "CA", "mexico": "MX", "brazil": "BR", "argentina": "AR",
    "peru": "PE", "cuba": "CU", "australia": "AU", "new zealand": "NZ",
    "japan": "JP", "south korea": "KR", "iran": "IR", "egypt": "EG",
    "south africa": "ZA",
  ]

  static func render(payload: [String: Any], size: CGSize) -> CGImage? {
    let renderer = UIGraphicsImageRenderer(size: size)
    let image = renderer.image { context in
      UIColor(red: 0.04, green: 0.04, blue: 0.05, alpha: 1).setFill()
      context.cgContext.fill(CGRect(origin: .zero, size: size))

      let side = min(size.width, size.height)
      let left = (size.width - side) / 2
      let headerH = side * 0.07
      let footerH = side * 0.07
      let evalW = side * 0.028
      let evalGap = side * 0.018
      let horizontalMargin = side * 0.06
      let maxBoardWidth = side - horizontalMargin * 2 - evalW - evalGap
      let maxBoardHeight = side - headerH - footerH - side * 0.025
      let boardSize = min(maxBoardWidth, maxBoardHeight)
      let groupWidth = evalW + evalGap + boardSize
      let groupLeft = left + (side - groupWidth) / 2
      let totalHeight = headerH + boardSize + footerH
      let top = (size.height - totalHeight) / 2
      let boardRect = CGRect(x: groupLeft + evalW + evalGap, y: top + headerH, width: boardSize, height: boardSize)

      drawPlayerRow(payload: payload, isWhite: false, rect: CGRect(x: boardRect.minX, y: top, width: boardRect.width, height: headerH))
      drawEvalBar(payload: payload, rect: CGRect(x: groupLeft, y: boardRect.minY, width: evalW, height: boardRect.height))
      drawBoard(payload: payload, rect: boardRect)
      drawPlayerRow(payload: payload, isWhite: true, rect: CGRect(x: boardRect.minX, y: boardRect.maxY, width: boardRect.width, height: footerH))
    }
    return image.cgImage
  }

  private static func drawPlayerRow(payload: [String: Any], isWhite: Bool, rect: CGRect) {
    let prefix = isWhite ? "white" : "black"
    let title = payload["\(prefix)Title"] as? String ?? ""
    let name = payload["\(prefix)Name"] as? String ?? ""
    let ratingValue = payload["\(prefix)Rating"] as? Int ?? 0
    let rating = ratingValue > 0 ? "\(ratingValue)" : ""
    let fed = (payload["\(prefix)Fed"] as? String ?? "").uppercased()
    let clock = displayClock(payload: payload, isWhite: isWhite)
    let label = [title, name, rating].filter { !$0.isEmpty }.joined(separator: " ")

    let flag = flagDisplay(for: fed)
    if flag != nil {
      let flagRect = CGRect(x: rect.minX, y: rect.minY + rect.height * 0.16, width: rect.height * 0.9, height: rect.height * 0.68)
      drawText(flag!, in: flagRect, size: rect.height * 0.58, color: .white, alignment: .center)
    }

    let clockW = clock.isEmpty ? 0 : rect.height * 1.9
    if !clock.isEmpty {
      let clockRect = CGRect(x: rect.maxX - clockW, y: rect.minY, width: clockW, height: rect.height)
      if isOngoing(payload: payload) && isWhiteToMove(payload: payload) == isWhite {
        UIColor(red: 0.13, green: 0.66, blue: 0.82, alpha: 1).setFill()
        UIRectFill(clockRect)
      }
      drawText(clock, in: clockRect, size: rect.height * 0.5, color: .white, alignment: .center)
    }

    let nameX = rect.minX + (flag == nil ? 0 : rect.height * 1.08)
    let textRect = CGRect(
      x: nameX,
      y: rect.minY,
      width: rect.maxX - nameX - clockW - rect.height * 0.1,
      height: rect.height
    )
    drawText(label, in: textRect, size: rect.height * 0.48, color: .white, alignment: .left)
  }

  private static func displayClock(payload: [String: Any], isWhite: Bool) -> String {
    let prefix = isWhite ? "white" : "black"
    let fallback = payload["\(prefix)Clock"] as? String ?? ""
    guard
      isOngoing(payload: payload),
      (payload["followLive"] as? Bool) != false,
      isWhiteToMove(payload: payload) == isWhite,
      let baseSeconds = intValue(payload["\(prefix)ClockSeconds"]),
      let lastMoveTime = dateValue(payload["lastMoveTime"] as? String)
    else {
      return fallback
    }

    let elapsed = max(0, Int(Date().timeIntervalSince(lastMoveTime)))
    return formatClock(seconds: max(0, baseSeconds - elapsed))
  }

  private static func isOngoing(payload: [String: Any]) -> Bool {
    let status = (payload["status"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return status.isEmpty || status == "ongoing" || status == "*"
  }

  private static func isWhiteToMove(payload: [String: Any]) -> Bool {
    let fen = payload["fen"] as? String ?? ""
    let parts = fen.split(separator: " ")
    guard parts.count > 1 else { return true }
    return parts[1] == "w"
  }

  private static func intValue(_ value: Any?) -> Int? {
    if let int = value as? Int { return int }
    if let number = value as? NSNumber { return number.intValue }
    if let string = value as? String { return Int(string) }
    return nil
  }

  private static func dateValue(_ value: String?) -> Date? {
    guard let value, !value.isEmpty else { return nil }
    return isoDateFormatter.date(from: value) ?? isoDateFormatterNoFraction.date(from: value)
  }

  private static func formatClock(seconds: Int) -> String {
    let clamped = max(0, seconds)
    let hours = clamped / 3600
    let minutes = (clamped % 3600) / 60
    let secs = clamped % 60
    if hours > 0 {
      return String(format: "%d:%02d:%02d", hours, minutes, secs)
    }
    return String(format: "%02d:%02d", minutes, secs)
  }

  private static func rgbColor(_ hex: Int) -> UIColor {
    UIColor(
      red: CGFloat((hex >> 16) & 0xff) / 255.0,
      green: CGFloat((hex >> 8) & 0xff) / 255.0,
      blue: CGFloat(hex & 0xff) / 255.0,
      alpha: 1
    )
  }

  // Solid light/dark square colors for each chessground board theme, matching
  // kBoardThemes order in lib/utils/board_customization_utils.dart (index 0..24).
  // Default index 9 (Grey) mirrors BoardSettingsModel.defaultSettings.
  private static func boardSquareColors(_ index: Int) -> (light: UIColor, dark: UIColor) {
    switch index {
    case 0: return (rgbColor(0xf0d9b6), rgbColor(0xb58863))
    case 1: return (rgbColor(0xdee3e6), rgbColor(0x8ca2ad))
    case 2: return (rgbColor(0xffffdd), rgbColor(0x86a666))
    case 3: return (rgbColor(0xececec), rgbColor(0xc1c18e))
    case 4: return (rgbColor(0x97b2c7), rgbColor(0x546f82))
    case 5: return (rgbColor(0xd9e0e6), rgbColor(0x315991))
    case 6: return (rgbColor(0xeae6dd), rgbColor(0x7c7f87))
    case 7: return (rgbColor(0xd7daeb), rgbColor(0x547388))
    case 8: return (rgbColor(0xf2f9bb), rgbColor(0x59935d))
    case 9: return (rgbColor(0xb8b8b8), rgbColor(0x7d7d7d))
    case 10: return (rgbColor(0xf0d9b5), rgbColor(0x946f51))
    case 11: return (rgbColor(0xd1d1c9), rgbColor(0xc28e16))
    case 12: return (rgbColor(0xe8ceab), rgbColor(0xbc7944))
    case 13: return (rgbColor(0xe2c89f), rgbColor(0x996633))
    case 14: return (rgbColor(0x93ab91), rgbColor(0x4f644e))
    case 15: return (rgbColor(0xc9c9c9), rgbColor(0x727272))
    case 16: return (rgbColor(0xffffff), rgbColor(0x8d8d8d))
    case 17: return (rgbColor(0xb8b19f), rgbColor(0x6d6655))
    case 18: return (rgbColor(0xe8e9b7), rgbColor(0xed7272))
    case 19: return (rgbColor(0x9f90b0), rgbColor(0x7d4a8d))
    case 20: return (rgbColor(0xe5daf0), rgbColor(0x957ab0))
    case 21: return (rgbColor(0xd8a45b), rgbColor(0x9b4d0f))
    case 22: return (rgbColor(0xa38b5d), rgbColor(0x6c5017))
    case 23: return (rgbColor(0xd0ceca), rgbColor(0x755839))
    case 24: return (rgbColor(0xcaaf7d), rgbColor(0x7b5330))
    default: return (rgbColor(0xb8b8b8), rgbColor(0x7d7d7d))
    }
  }

  private static func drawBoard(payload: [String: Any], rect: CGRect) {
    let fen = payload["fen"] as? String ?? ""
    let board = parseFen(fen)
    let square = rect.width / 8
    let themeColors = boardSquareColors(intValue(payload["boardThemeIndex"]) ?? 9)
    let lastMove = payload["lastMoveUci"] as? String
    let highlights = parseUci(lastMove)
    let loserKing = loserKingPiece(payload: payload)
    let loserSquare = loserKing.flatMap { findPiece($0, in: board) }
    let drawKingSquares = isDrawStatus(payload: payload)
      ? [findPiece("K", in: board), findPiece("k", in: board)].compactMap { $0 }
      : []

    for rank in 0..<8 {
      for file in 0..<8 {
        let squareRect = CGRect(
          x: rect.minX + CGFloat(file) * square,
          y: rect.minY + CGFloat(rank) * square,
          width: square,
          height: square
        )
        ((rank + file).isMultiple(of: 2) ? themeColors.light : themeColors.dark).setFill()
        UIRectFill(squareRect)
        let from = highlights.first
        let to = highlights.dropFirst().first
        if (from?.0 == file && from?.1 == rank) || (to?.0 == file && to?.1 == rank) {
          UIColor(red: 0.678, green: 0.725, blue: 0.812, alpha: 1).setFill()
          UIRectFill(squareRect)
        }

        let isLoserKingSquare = loserSquare?.0 == file && loserSquare?.1 == rank
        if isLoserKingSquare {
          UIColor(red: 0.961, green: 0.196, blue: 0.212, alpha: 0.8).setFill()
          UIRectFill(squareRect)
        }

        let isDrawKingSquare = drawKingSquares.contains { $0.0 == file && $0.1 == rank }
        if isDrawKingSquare {
          UIColor(red: 0.678, green: 0.882, blue: 0.804, alpha: 0.8).setFill()
          UIRectFill(squareRect)
        }

        let piece = board[rank][file]
        if piece != "\0" {
          drawPiece(
            piece,
            payload: payload,
            in: squareRect.insetBy(dx: square * 0.03, dy: square * 0.03),
            rotation: isLoserKingSquare ? -CGFloat.pi / 4 : nil
          )
        }
        if isDrawKingSquare {
          drawPeaceIcon(in: squareRect)
        }
      }
    }
  }

  private static func drawPiece(
    _ piece: String,
    payload: [String: Any],
    in rect: CGRect,
    rotation: CGFloat? = nil
  ) {
    if let rotation {
      guard let context = UIGraphicsGetCurrentContext() else { return }
      context.saveGState()
      context.translateBy(x: rect.midX, y: rect.midY)
      context.rotate(by: rotation)
      context.translateBy(x: -rect.midX, y: -rect.midY)
      drawPiece(piece, payload: payload, in: rect, rotation: nil)
      context.restoreGState()
      return
    }

    if let image = PieceImageCache.shared.image(for: piece, payload: payload) {
      image.draw(in: rect)
      return
    }

    drawText(
      piece.uppercased(),
      in: rect.insetBy(dx: rect.width * 0.05, dy: rect.height * 0.05),
      size: rect.height * 0.56,
      color: piece == piece.uppercased() ? .white : .black,
      alignment: .center
    )
  }

  private static func loserKingPiece(payload: [String: Any]) -> String? {
    let status = (payload["status"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    switch status {
    case "whitewins", "white_wins", "1-0", "w":
      return "k"
    case "blackwins", "black_wins", "0-1", "b":
      return "K"
    default:
      return nil
    }
  }

  private static func isDrawStatus(payload: [String: Any]) -> Bool {
    let status = (payload["status"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return status == "draw" || status == "1/2-1/2" || status == "½-½" || status == "0.5-0.5" || status == "d"
  }

  private static func drawPeaceIcon(in squareRect: CGRect) {
    let iconSize = squareRect.width * 0.24
    let iconRect = CGRect(
      x: squareRect.maxX - iconSize * 1.06,
      y: squareRect.minY + iconSize * 0.08,
      width: iconSize,
      height: iconSize
    )
    drawText("🕊️", in: iconRect, size: iconSize * 0.78, color: .white, alignment: .center)
  }

  private static func findPiece(_ piece: String, in board: [[String]]) -> (Int, Int)? {
    for rank in 0..<8 {
      for file in 0..<8 where board[rank][file] == piece {
        return (file, rank)
      }
    }
    return nil
  }

  private static func flagDisplay(for federation: String) -> String? {
    let raw = federation.trimmingCharacters(in: .whitespacesAndNewlines)
    if raw.isEmpty { return nil }
    let upper = raw.uppercased()
    let lower = raw.lowercased()
    if ["UNKNOWN", "NONE", "UNRATED", "N/A", "NA", "?", "-"].contains(upper) {
      return "🌐"
    }
    if upper == "FID" || upper == "FIDE" {
      return "FIDE"
    }

    let iso2: String?
    if upper.count == 2 {
      iso2 = upper
    } else if upper.count == 3 {
      iso2 = fideToIso2[upper]
    } else {
      iso2 = countryNameToIso2[lower]
    }
    guard let iso2, iso2.count == 2 else { return nil }
    return flagEmoji(iso2: iso2)
  }

  private static func flagEmoji(iso2: String) -> String {
    let base: UInt32 = 127397
    return String(String.UnicodeScalarView(iso2.uppercased().unicodeScalars.compactMap {
      UnicodeScalar(base + $0.value)
    }))
  }

  private static func drawEvalBar(payload: [String: Any], rect: CGRect) {
    UIColor.black.setFill()
    UIRectFill(rect)
    let evalCp = payload["evalCp"] as? Int
    let mate = payload["mate"] as? Int
    let eval = mate == nil || mate == 0 ? Double(evalCp ?? 0) / 100.0 : (mate! > 0 ? 10.0 : -10.0)
    let ratio = CGFloat((min(10.0, max(-10.0, eval)) + 10.0) / 20.0)
    let whiteRect = CGRect(x: rect.minX, y: rect.maxY - rect.height * ratio, width: rect.width, height: rect.height * ratio)
    UIColor.white.setFill()
    UIRectFill(whiteRect)

    let label = mate != nil && mate != 0 ? "M\(abs(mate!))" : String(format: "%+.1f", Double(evalCp ?? 0) / 100.0)
    let labelRect = CGRect(x: rect.minX - rect.width * 0.25, y: whiteRect.minY - rect.width * 0.68, width: rect.width * 1.5, height: rect.width * 1.36)
    UIColor(red: 0.13, green: 0.66, blue: 0.82, alpha: 1).setFill()
    UIRectFill(labelRect)
    drawText(label, in: labelRect, size: rect.width * 0.72, color: .white, alignment: .center)
  }

  private static func drawText(
    _ text: String,
    in rect: CGRect,
    size: CGFloat,
    color: UIColor,
    alignment: NSTextAlignment
  ) {
    guard rect.width > 0, rect.height > 0, !text.isEmpty else { return }
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = alignment
    paragraph.lineBreakMode = .byClipping
    let attributes: [NSAttributedString.Key: Any] = [
      .font: UIFont.boldSystemFont(ofSize: size),
      .foregroundColor: color,
      .paragraphStyle: paragraph,
    ]
    let string = NSString(string: text)
    string.draw(
      with: rect.insetBy(dx: 2, dy: max(0, (rect.height - size) / 2 - 2)),
      options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
      attributes: attributes,
      context: nil
    )
  }

  private static func parseFen(_ fen: String) -> [[String]] {
    let ranks = fen.split(separator: " ").first?.split(separator: "/") ?? []
    guard ranks.count == 8 else { return defaultBoard() }
    var board = Array(repeating: Array(repeating: "\0", count: 8), count: 8)
    for (rankIndex, rank) in ranks.enumerated() {
      var file = 0
      for ch in rank {
        if let empty = ch.wholeNumberValue {
          file += empty
        } else if file < 8 {
          board[rankIndex][file] = String(ch)
          file += 1
        }
      }
    }
    return board
  }

  private static func defaultBoard() -> [[String]] {
    [
      ["r", "n", "b", "q", "k", "b", "n", "r"],
      ["p", "p", "p", "p", "p", "p", "p", "p"],
      Array(repeating: "\0", count: 8),
      Array(repeating: "\0", count: 8),
      Array(repeating: "\0", count: 8),
      Array(repeating: "\0", count: 8),
      ["P", "P", "P", "P", "P", "P", "P", "P"],
      ["R", "N", "B", "Q", "K", "B", "N", "R"],
    ]
  }

  private static func parseUci(_ uci: String?) -> [(Int, Int)] {
    guard let uci, uci.count >= 4 else { return [] }
    return [square(String(uci.prefix(2))), square(String(uci.dropFirst(2).prefix(2)))].compactMap { $0 }
  }

  private static func square(_ value: String) -> (Int, Int)? {
    guard value.count >= 2 else { return nil }
    let chars = Array(value.lowercased())
    guard let fileScalar = chars[0].unicodeScalars.first, let rank = chars[1].wholeNumberValue else {
      return nil
    }
    let aValue = "a".unicodeScalars.first?.value ?? 97
    let file = Int(fileScalar.value) - Int(aValue)
    guard (0...7).contains(file), (1...8).contains(rank) else { return nil }
    return (file, 8 - rank)
  }
}

private final class PieceImageCache {
  static let shared = PieceImageCache()

  private let cache = NSCache<NSString, UIImage>()
  private let pieceSetNames = [
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
    "symmetric",
  ]

  private init() {}

  func image(for piece: String, payload: [String: Any]) -> UIImage? {
    guard let pieceCode = pieceCode(for: piece) else { return nil }
    let pieceSet = pieceSetName(for: payload["pieceStyleIndex"] as? Int)
    let cacheKey = "\(pieceSet)/\(pieceCode)" as NSString
    if let cached = cache.object(forKey: cacheKey) {
      return cached
    }

    guard let image = loadImage(pieceSet: pieceSet, pieceCode: pieceCode) else {
      return nil
    }
    cache.setObject(image, forKey: cacheKey)
    return image
  }

  private func pieceSetName(for index: Int?) -> String {
    let value = index ?? 0
    guard value >= 0 && value < pieceSetNames.count else {
      return "cburnett"
    }
    return pieceSetNames[value]
  }

  private func pieceCode(for piece: String) -> String? {
    guard let scalar = piece.unicodeScalars.first else { return nil }
    let prefix = CharacterSet.uppercaseLetters.contains(scalar) ? "w" : "b"
    switch Character(scalar).uppercased() {
    case "K": return "\(prefix)K"
    case "Q": return "\(prefix)Q"
    case "R": return "\(prefix)R"
    case "B": return "\(prefix)B"
    case "N": return "\(prefix)N"
    case "P": return "\(prefix)P"
    default: return nil
    }
  }

  private func loadImage(pieceSet: String, pieceCode: String) -> UIImage? {
    let assetPath = "packages/chessground/assets/piece_sets/\(pieceSet)/\(pieceCode).png"
    let candidates = [
      "flutter_assets/\(assetPath)",
      "Frameworks/App.framework/flutter_assets/\(assetPath)",
    ]

    for candidate in candidates {
      if
        let path = Bundle.main.path(forResource: candidate, ofType: nil),
        let image = UIImage(contentsOfFile: path)
      {
        return image
      }
    }

    guard let resourcePath = Bundle.main.resourcePath else { return nil }
    for candidate in candidates {
      let path = (resourcePath as NSString).appendingPathComponent(candidate)
      if let image = UIImage(contentsOfFile: path) {
        return image
      }
    }

    return nil
  }
}
