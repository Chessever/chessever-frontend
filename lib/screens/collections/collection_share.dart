import 'package:chessever2/repository/gamebase/collections/collections_models.dart';
import 'package:chessever2/services/analytics/analytics_service.dart';
import 'package:flutter/widgets.dart';
import 'package:share_plus/share_plus.dart';

/// The path segment a shared collection lives under on chessever.com. The
/// web page there only previews it (title, cover, the OG card) and hands the
/// visitor to the apps; the collection itself is read in-app.
const String kCollectionSharePath = 'collections';

const _webHosts = {'chessever.com', 'www.chessever.com'};
const _appScheme = 'com.chessever.app';

/// `https://chessever.com/collections/<slug>`, the link Share sends. Null for
/// a collection without a slug, which nobody else could open.
String? buildCollectionShareUrl(String? slug) {
  final s = slug?.trim();
  if (s == null || s.isEmpty) return null;
  return 'https://chessever.com/$kCollectionSharePath/'
      '${Uri.encodeComponent(s)}';
}

/// The collection slug in a shared link: `https://chessever.com/collections/<slug>`
/// (or `www.`), and the web page's app hand-off
/// `com.chessever.app://collections/<slug>`. Null for any other link.
String? collectionSlugFromUri(Uri uri) {
  final scheme = uri.scheme.toLowerCase();
  final host = uri.host.toLowerCase();
  final List<String> rest;
  if ((scheme == 'https' || scheme == 'http') && _webHosts.contains(host)) {
    final segs = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (segs.isEmpty || segs.first != kCollectionSharePath) return null;
    rest = segs.sublist(1);
  } else if (scheme == _appScheme && host == kCollectionSharePath) {
    rest = uri.pathSegments.where((s) => s.isNotEmpty).toList();
  } else {
    return null;
  }
  // pathSegments are already percent-decoded by Uri.
  final slug = rest.isEmpty ? '' : rest.first.trim();
  return slug.isEmpty ? null : slug;
}

/// Opens the share sheet with [collection]'s link, anchored (on iPad) to
/// [context]'s box.
Future<void> shareCollection(
  BuildContext context,
  Collection collection,
) async {
  final url = buildCollectionShareUrl(collection.slug);
  if (url == null) return;
  final box = context.mounted ? context.findRenderObject() : null;
  final origin = box is RenderBox && box.hasSize
      ? box.localToGlobal(Offset.zero) & box.size
      : const Rect.fromLTWH(0, 0, 1, 1);
  AnalyticsService.instance.trackEventDetached(
    'Collection Shared',
    properties: {
      'collection_slug': collection.slug,
      'collection_kind': collection.kind.name,
    },
  );
  try {
    await Share.share(url, sharePositionOrigin: origin);
  } catch (e) {
    debugPrint('[Collections] share failed: $e');
  }
}
