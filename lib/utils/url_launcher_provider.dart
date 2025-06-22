import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

final urlLauncherProvider = AutoDisposeProvider<UrlLauncherService>((ref) {
  return UrlLauncherService();
});

class UrlLauncherService {
  UrlLauncherService();

  /// Launches a URL in the default browser.
  Future<void> launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(url);
    } else {
      throw 'Could not launch $url';
    }
  }

  /// Opens a URL in the default browser.
  Future<void> openUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(url);
    } else {
      throw 'Could not open $url';
    }
  }
}
