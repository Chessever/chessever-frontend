import Flutter
import UIKit
import UserNotifications
import AVFoundation
import ActivityKit
import app_links
import OneSignalFramework
import OneSignalLiveActivities

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var liveActivityTokenObserverTasks: [String: Task<Void, Never>] = [:]

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // NOTE: OneSignal.LiveActivities.setupDefault() is intentionally NOT called here.
    // It must run AFTER OneSignal.initialize() (which happens in Dart), otherwise the
    // LiveActivities module has no appId/subscription and never registers the Live
    // Activity push token (server updates then reach 0 recipients). It is invoked from
    // Dart in LiveUpdatesService.setup(), immediately after OneSignal.initialize().

    // Forward deep link URL from launch options to app_links plugin.
    // On cold start (app killed), iOS puts the URL in launchOptions instead of
    // calling application(_:open:options:), so we must extract it manually.
    if let url = AppLinks.shared.getLink(launchOptions: launchOptions) {
      AppLinks.shared.handleLink(url: url)
    }

    if #available(iOS 10.0, *) {
      UNUserNotificationCenter.current().delegate = self as? UNUserNotificationCenterDelegate
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  override func application(
    _ application: UIApplication,
    continue userActivity: NSUserActivity,
    restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void
  ) -> Bool {
    let isBrowsingWeb = userActivity.activityType == NSUserActivityTypeBrowsingWeb
    let hasWebpageURL = userActivity.webpageURL != nil

    if isBrowsingWeb,
       let url = userActivity.webpageURL {
      AppLinks.shared.handleLink(url: url)
    }

    let superResult = super.application(
      application,
      continue: userActivity,
      restorationHandler: restorationHandler
    )
    return superResult || (isBrowsingWeb && hasWebpageURL)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    // Storyboard-based apps use an implicit engine, so plugin and channel
    // registration must happen here exactly once.
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    setupAudioSessionChannel(binaryMessenger: engineBridge.applicationRegistrar.messenger())
    setupLiveActivitiesChannel(binaryMessenger: engineBridge.applicationRegistrar.messenger())
    setupPipChannel(binaryMessenger: engineBridge.applicationRegistrar.messenger())
  }

  private func setupAudioSessionChannel(binaryMessenger: FlutterBinaryMessenger) {
    let audioSessionChannel = FlutterMethodChannel(
      name: "com.chessever/audio_session",
      binaryMessenger: binaryMessenger
    )

    audioSessionChannel.setMethodCallHandler { [weak self] (call, result) in
      switch call.method {
      case "configureAmbientSession":
        self?.configureAmbientAudioSession(result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func setupLiveActivitiesChannel(binaryMessenger: FlutterBinaryMessenger) {
    let liveActivitiesChannel = FlutterMethodChannel(
      name: "com.chessever/live_activities",
      binaryMessenger: binaryMessenger
    )

    liveActivitiesChannel.setMethodCallHandler { [weak self] (call, result) in
      switch call.method {
      case "startDefaultVerified":
        self?.startDefaultVerified(call: call, result: result)
      case "getLiveActivityDebugState":
        self?.getLiveActivityDebugState(result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func setupPipChannel(binaryMessenger: FlutterBinaryMessenger) {
    ChessPipController.shared.configure(binaryMessenger: binaryMessenger)
  }

  private func getLiveActivityDebugState(result: @escaping FlutterResult) {
    guard #available(iOS 16.1, *) else {
      result([
        "supported": false,
        "enabled": false,
        "activities": [],
      ])
      return
    }

    let authorizationInfo = ActivityAuthorizationInfo()
    let activities = Activity<DefaultLiveActivityAttributes>.activities.map { activity in
      serializeDefaultLiveActivity(activity)
    }

    result([
      "supported": true,
      "enabled": authorizationInfo.areActivitiesEnabled,
      "activities": activities,
    ])
  }

  private func startDefaultVerified(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard #available(iOS 16.1, *) else {
      result(FlutterError(
        code: "LIVE_ACTIVITY_UNAVAILABLE",
        message: "Live Activities require iOS 16.1+",
        details: nil
      ))
      return
    }

    guard
      let args = call.arguments as? [String: Any],
      let activityId = args["activityId"] as? String,
      let attributes = args["attributes"] as? [String: Any],
      let content = args["content"] as? [String: Any]
    else {
      result(FlutterError(
        code: "INVALID_ARGUMENTS",
        message: "Missing activityId, attributes, or content",
        details: nil
      ))
      return
    }

    // ALWAYS use the public OneSignal wrapper, NOT the internal Obj-C class.
    OneSignal.LiveActivities.startDefault(
      activityId,
      attributes: attributes,
      content: content
    )

    Task { @MainActor in
      // Wait up to 2 seconds for ActivityKit to register the activity
      for _ in 0..<20 {
        if let activity = Activity<DefaultLiveActivityAttributes>.activities.first(
          where: { $0.attributes.onesignal.activityId == activityId }
        ) {
          let pushTokenHex = await waitForLiveActivityUpdateToken(activity)
          if let pushTokenHex {
            OneSignalLiveActivitiesManagerImpl.enter(activityId, withToken: pushTokenHex)
          }
          observeLiveActivityUpdateToken(activity, activityId: activityId)
          result([
            "ok": true,
            "enabled": ActivityAuthorizationInfo().areActivitiesEnabled,
            "pushTokenPresent": pushTokenHex != nil,
            "pushTokenPrefix": pushTokenHex.map { String($0.prefix(12)) } ?? NSNull(),
            "activity": serializeDefaultLiveActivity(activity),
          ])
          return
        }
        try? await Task.sleep(nanoseconds: 100_000_000)
      }

      // If we reach here, it failed to start.
      result([
        "ok": false,
        "enabled": ActivityAuthorizationInfo().areActivitiesEnabled,
        "message": "ActivityKit did not persist a matching live activity after startDefault",
        "activities": Activity<DefaultLiveActivityAttributes>.activities.map {
          serializeDefaultLiveActivity($0)
        },
      ])
    }
  }

  @available(iOS 16.1, *)
  private func waitForLiveActivityUpdateToken(
    _ activity: Activity<DefaultLiveActivityAttributes>
  ) async -> String? {
    if let token = activity.pushToken?.hexEncodedString() {
      return token
    }

    return await withTaskGroup(of: String?.self) { group in
      group.addTask {
        for await tokenData in activity.pushTokenUpdates {
          return tokenData.hexEncodedString()
        }
        return nil
      }
      group.addTask {
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        return nil
      }

      let token = await group.next() ?? nil
      group.cancelAll()
      return token
    }
  }

  @available(iOS 16.1, *)
  private func observeLiveActivityUpdateToken(
    _ activity: Activity<DefaultLiveActivityAttributes>,
    activityId: String
  ) {
    liveActivityTokenObserverTasks[activityId]?.cancel()
    liveActivityTokenObserverTasks[activityId] = Task {
      if let token = activity.pushToken?.hexEncodedString() {
        OneSignalLiveActivitiesManagerImpl.enter(activityId, withToken: token)
      }

      for await tokenData in activity.pushTokenUpdates {
        guard !Task.isCancelled else { return }
        OneSignalLiveActivitiesManagerImpl.enter(
          activityId,
          withToken: tokenData.hexEncodedString()
        )
      }
    }
  }

  @available(iOS 16.1, *)
  private func serializeDefaultLiveActivity(
    _ activity: Activity<DefaultLiveActivityAttributes>
  ) -> [String: Any] {
    let contentData = activity.contentState.data
    let attributesData = activity.attributes.data
    let pushTokenHex = activity.pushToken?.hexEncodedString()
    let gameId: Any
    if let contentGameId = contentData["game_id"]?.asString() {
      gameId = contentGameId
    } else if let attributeGameId = attributesData["game_id"]?.asString() {
      gameId = attributeGameId
    } else {
      gameId = NSNull()
    }

    return [
      "systemId": activity.id,
      "activityId": activity.attributes.onesignal.activityId,
      "state": String(describing: activity.activityState),
      "gameId": gameId,
      "pushTokenPresent": pushTokenHex != nil,
      "pushTokenPrefix": pushTokenHex.map { String($0.prefix(12)) } ?? NSNull(),
      "content": liveActivityDataSnapshot(contentData),
      "attributes": liveActivityDataSnapshot(attributesData),
    ]
  }

  private func liveActivityDataSnapshot(_ data: [String: AnyCodable]) -> [String: Any] {
    let fen = data["fen"]?.asString()
    let fenParts = fen?.split(separator: " ").map(String.init) ?? []

    let keys = [
      "game_id",
      "fen",
      "last_move",
      "last_move_uci",
      "last_move_san",
      "last_move_numbered",
      "last_move_time",
      "white_clock_seconds",
      "black_clock_seconds",
      "clock_anchor_time",
      "active_clock_color",
      "active_clock_deadline",
      "eval_cp",
      "eval_mate",
      "is_check",
      "is_checkmate",
      "is_game_over",
      "follow_live",
      "status",
      "refresh_ts",
      "board_theme_index",
      "piece_style_index",
    ]

    let sideToMove: Any = fenParts.count > 1 ? fenParts[1] as Any : NSNull()
    let fullmove: Any = fenParts.count > 5 ? fenParts[5] as Any : NSNull()
    var snapshot: [String: Any] = [
      "keys": data.keys.sorted(),
      "side_to_move": sideToMove,
      "fullmove": fullmove,
    ]

    for key in keys {
      if let value = liveActivityCodableValue(data[key]) {
        snapshot[key] = value
      }
    }

    return snapshot
  }

  private func liveActivityCodableValue(_ value: AnyCodable?) -> Any? {
    guard let value else { return nil }
    if let boolValue = value.asBool() { return boolValue }
    if let intValue = value.asInt() { return intValue }
    if let doubleValue = value.asDouble() { return doubleValue }
    if let stringValue = value.asString() { return stringValue }
    return nil
  }

  /// Configure audio session for ambient mode - doesn't interrupt other audio
  private func configureAmbientAudioSession(result: @escaping FlutterResult) {
    // AVAudioSession.setCategory/setActive can block for hundreds of ms (or more)
    // while reacquiring the audio route — especially right after a long
    // background, when this is invoked from the resume audio reinit. Run it OFF
    // the platform/main thread so the resume frame isn't stalled, then reply on
    // main. Use .ambient: mixes with other audio, respects the silent switch,
    // doesn't request audio focus.
    DispatchQueue.global(qos: .userInitiated).async {
      do {
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
        try audioSession.setActive(true)
        DispatchQueue.main.async { result(true) }
      } catch {
        print("Failed to configure audio session: \(error)")
        DispatchQueue.main.async {
          result(FlutterError(code: "AUDIO_SESSION_ERROR",
                              message: "Failed to configure audio session",
                              details: error.localizedDescription))
        }
      }
    }
  }
}

private extension Data {
  func hexEncodedString() -> String {
    map { String(format: "%02x", $0) }.joined()
  }
}
