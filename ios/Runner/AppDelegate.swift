import Flutter
import UIKit
import UserNotifications
import AVFoundation

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {

    GeneratedPluginRegistrant.register(with: self)

    if #available(iOS 10.0, *) {
      UNUserNotificationCenter.current().delegate = self as? UNUserNotificationCenterDelegate
    }

    // Setup audio session channel for configuring ambient mode
    setupAudioSessionChannel()

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  private func setupAudioSessionChannel() {
    guard let controller = window?.rootViewController as? FlutterViewController else {
      return
    }

    let audioSessionChannel = FlutterMethodChannel(
      name: "com.chessever/audio_session",
      binaryMessenger: controller.binaryMessenger
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
