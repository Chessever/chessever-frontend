import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

final urlLauncherProvider = AutoDisposeProvider<UrlLauncherService>((ref) {
  return UrlLauncherService();
});

class UrlLauncherService {
  UrlLauncherService();

  /// Launches a URL in the default browser.
  // Future<void> launchUrl(String url) async {
  //   final uri = Uri.parse(url);
  //   if (await canLaunchUrl(uri)) {
  //     await launchUrl(url);
  //   } else {
  //     throw 'Could not launch $url';
  //   }
  // }

  Future<void> launchCustomUrl(String url) async {
    String tempUrl = url;
    if (!url.contains("https://")) {
      tempUrl = "https://$url";
    }
    Uri urlValue = Uri.parse(tempUrl);
    await launchUrl(urlValue);
    if (await canLaunchUrl(urlValue)) {
    } else {
      debugPrint("contact app is not opened");
    }
  }

  // /// Opens a URL in the default browser.
  // Future<void> openUrl(String url) async {
  //   final uri = Uri.parse(url);
  //   if (await canLaunchUrl(uri)) {
  //     await launchUrl(url);
  //   } else {
  //     throw 'Could not open $url';
  //   }
  // }
}
