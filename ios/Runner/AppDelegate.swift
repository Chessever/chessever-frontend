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
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    OneSignal.LiveActivities.setupDefault()

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
          result([
            "ok": true,
            "enabled": ActivityAuthorizationInfo().areActivitiesEnabled,
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
  private func serializeDefaultLiveActivity(
    _ activity: Activity<DefaultLiveActivityAttributes>
  ) -> [String: Any] {
    return [
      "systemId": activity.id,
      "activityId": activity.attributes.onesignal.activityId,
      "state": String(describing: activity.activityState),
      "gameId": activity.attributes.data["game_id"]?.asString() ?? NSNull(),
    ]
  }

  /// Configure audio session for ambient mode - doesn't interrupt other audio
  private func configureAmbientAudioSession(result: @escaping FlutterResult) {
    do {
      let audioSession = AVAudioSession.sharedInstance()

      // Use .ambient category which:
      // - Mixes with other audio (won't stop music/podcasts)
      // - Respects the silent switch
      // - Doesn't request audio focus
      // Added .mixWithOthers just to be explicit
      try audioSession.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
      try audioSession.setActive(true)

      result(true)
    } catch {
      print("Failed to configure audio session: \(error)")
      result(FlutterError(code: "AUDIO_SESSION_ERROR",
                         message: "Failed to configure audio session",
                         details: error.localizedDescription))
    }
  }
}
