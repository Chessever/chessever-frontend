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

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
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
      try audioSession.setCategory(.ambient, mode: .default, options: [])
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
