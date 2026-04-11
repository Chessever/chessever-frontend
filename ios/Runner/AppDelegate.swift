import Flutter
import UIKit
import UserNotifications
import AVFoundation
import app_links

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
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
