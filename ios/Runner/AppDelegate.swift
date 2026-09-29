import Flutter
import UIKit
import UserNotifications
import AVFoundation
import app_links
import OneSignalFramework

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var pushTapChannel: FlutterMethodChannel?
  private var pushTapListenerReady = false
  private var pendingPushTap: [String: Any]?

  // Scene-based launches do not put the response in UIApplication launchOptions.
  // Keep the tap until Dart has registered its listener.
  func captureDirectPushTap(_ response: UNNotificationResponse) {
    guard response.actionIdentifier == UNNotificationDefaultActionIdentifier else { return }
    let info = response.notification.request.content.userInfo
    guard let messageId = info["gcm.message_id"] as? String else { return }
    var data: [String: Any] = [:]
    for (key, value) in info {
      guard let key = key as? String, key != "aps" else { continue }
      data[key] = value
    }
    let tap: [String: Any] = ["messageId": messageId, "data": data]
    if pushTapListenerReady, let channel = pushTapChannel {
      channel.invokeMethod("notificationOpened", arguments: tap)
    } else {
      pendingPushTap = tap
    }
  }

  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    captureDirectPushTap(response)
    super.userNotificationCenter(center, didReceive: response,
                                 withCompletionHandler: completionHandler)
  }

  private func setupPushTapChannel(binaryMessenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "com.chessever/push_taps",
                                       binaryMessenger: binaryMessenger)
    pushTapChannel = channel
    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "takeInitialTap", let self = self else {
        result(FlutterMethodNotImplemented)
        return
      }
      self.pushTapListenerReady = true
      let tap = self.pendingPushTap
      self.pendingPushTap = nil
      result(tap)
    }
  }

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

  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    // Firebase forwards presentation to our existing Flutter delegate. Preserve
    // plugin handling, then explicitly enable banners for remote FCM messages.
    let isFirebasePush = notification.request.trigger is UNPushNotificationTrigger
      && notification.request.content.userInfo["gcm.message_id"] != nil
    super.userNotificationCenter(center, willPresent: notification) { options in
      guard isFirebasePush else {
        completionHandler(options)
        return
      }
      if #available(iOS 14.0, *) {
        completionHandler(options.union([.banner, .list, .sound, .badge]))
      } else {
        completionHandler(options.union([.alert, .sound, .badge]))
      }
    }
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
    setupPushTapChannel(binaryMessenger: engineBridge.applicationRegistrar.messenger())
    setupAudioSessionChannel(binaryMessenger: engineBridge.applicationRegistrar.messenger())
    setupPipChannel(binaryMessenger: engineBridge.applicationRegistrar.messenger())
    setupMediaPickerChannel(binaryMessenger: engineBridge.applicationRegistrar.messenger())
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

  private func setupPipChannel(binaryMessenger: FlutterBinaryMessenger) {
    ChessPipController.shared.configure(binaryMessenger: binaryMessenger)
  }

  private func setupMediaPickerChannel(binaryMessenger: FlutterBinaryMessenger) {
    MediaLibraryPicker.shared.configure(binaryMessenger: binaryMessenger)
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
