import 'package:chessever2/screens/feed/news/news_models.dart';

/// The public web route is also the native article address. Slugs are
/// decorative: publisher + id resolve the article even after a title edit.
class NewsLink {
  const NewsLink({
    this.id,
    this.publisher = NewsPublisher.chessever,
    this.slug,
  });

  final int? id;
  final NewsPublisher publisher;
  final String? slug;

  String? get key => id == null
      ? null
      : publisher.isPartner
      ? '${publisher.sourceId}:$id'
      : '$id';

  String get path {
    if (id == null) return '/news';
    final source = publisher.isPartner ? '/partners/${publisher.sourceId}' : '';
    return '/news$source/$id${slug == null ? '' : '/${Uri.encodeComponent(slug!)}'}';
  }

  static NewsLink? parse(Uri uri) {
    if (uri.userInfo.isNotEmpty) return null;
    var parts = uri.pathSegments.toList();
    if (parts.lastOrNull == '') parts.removeLast();
    if (uri.scheme == 'https') {
      if (!const {'chessever.com', 'www.chessever.com'}.contains(uri.host) ||
          uri.port != 443) {
        return null;
      }
    } else if (uri.scheme == 'com.chessever.app' && !uri.hasPort) {
      if (uri.host.isNotEmpty) parts.insert(0, uri.host);
    } else {
      return null;
    }
    if (parts.firstOrNull == 'app') parts.removeAt(0);
    if (parts.isEmpty ||
        parts.first != 'news' ||
        parts.any(
          (part) =>
              part.isEmpty ||
              part == '.' ||
              part == '..' ||
              RegExp(r'[/\\\x00-\x1f\x7f]').hasMatch(part),
        )) {
      return null;
    }
    if (parts.length == 1) return const NewsLink();
    if (parts.length == 3 && parts[1] == 'page' && _id(parts[2]) != null) {
      return const NewsLink();
    }
    var publisher = NewsPublisher.chessever;
    var idAt = 1;
    if (parts[1] == 'partners') {
      if (parts.length < 4) return null;
      final partner = NewsPublisher.ofSource(parts[2]);
      if (partner == null) return null;
      publisher = partner;
      idAt = 3;
    }
    if (parts.length != idAt + 1 && parts.length != idAt + 2) return null;
    final id = _id(parts[idAt]);
    if (id == null) return null;
    return NewsLink(
      id: id,
      publisher: publisher,
      slug: parts.length == idAt + 2 ? parts.last : null,
    );
  }

  static int? _id(String value) {
    if (!RegExp(r'^[1-9][0-9]{0,15}$').hasMatch(value)) return null;
    final id = int.tryParse(value);
    return id != null && id <= 9007199254740991 ? id : null;
  }
}
