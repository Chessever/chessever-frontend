import Flutter
import UIKit
import app_links

class SceneDelegate: FlutterSceneDelegate {
  override func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    super.scene(scene, willConnectTo: session, options: connectionOptions)

    if let response = connectionOptions.notificationResponse,
       let appDelegate = UIApplication.shared.delegate as? AppDelegate {
      appDelegate.captureDirectPushTap(response)
    }

    for context in connectionOptions.urlContexts {
      let url = context.url
      DispatchQueue.main.async {
        AppLinks.shared.handleLink(url: url)
      }
    }

    for userActivity in connectionOptions.userActivities {
      if userActivity.activityType == NSUserActivityTypeBrowsingWeb,
         let url = userActivity.webpageURL {
        DispatchQueue.main.async {
          AppLinks.shared.handleLink(url: url)
        }
      }
    }
  }

  // A universal link while the app runs. `super` already hands it to
  // app_links: no scene plugin claims it (AppsFlyer returns NO), so
  // FlutterSceneDelegate falls back to the plugins' application delegates,
  // and app_links (an application delegate only, 6.x) calls handleLink.
  // Forwarding it here as well delivered every link to Dart twice (a
  // `/webview?url=` link stacked two pages). Flutter 3.38+ (pubspec needs
  // 3.44) has that fallback.
  override func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
    super.scene(scene, continue: userActivity)
  }

  override func scene(
    _ scene: UIScene,
    openURLContexts URLContexts: Set<UIOpenURLContext>
  ) {
    super.scene(scene, openURLContexts: URLContexts)

    // Kept: google_sign_in's scene handler for these returns no BOOL, so
    // whether Flutter falls back to app_links is not certain. When it does,
    // Dart drops the second delivery (DeepLinkService.handleDeepLink).
    for context in URLContexts {
      AppLinks.shared.handleLink(url: context.url)
    }
  }
}
