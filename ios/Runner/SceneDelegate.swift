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

  override func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
    super.scene(scene, continue: userActivity)

    if userActivity.activityType == NSUserActivityTypeBrowsingWeb,
       let url = userActivity.webpageURL {
      AppLinks.shared.handleLink(url: url)
    }
  }

  override func scene(
    _ scene: UIScene,
    openURLContexts URLContexts: Set<UIOpenURLContext>
  ) {
    super.scene(scene, openURLContexts: URLContexts)

    for context in URLContexts {
      AppLinks.shared.handleLink(url: context.url)
    }
  }
}
