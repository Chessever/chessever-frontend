/// Only web documents may be opened by a WebView link. Credentials in an
/// authority and control characters are rejected before reaching the platform.
Uri? webViewUrl(String? value) {
  if (value == null || RegExp(r'[\x00-\x1f\x7f]').hasMatch(value)) {
    return null;
  }
  final uri = Uri.tryParse(value.trim());
  if (uri == null ||
      !const {'https', 'http'}.contains(uri.scheme) ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty) {
    return null;
  }
  return uri;
}

bool isWebViewLink(Uri uri) {
  final custom = uri.scheme == 'com.chessever.app';
  final web =
      uri.scheme == 'https' &&
      const {'chessever.com', 'www.chessever.com'}.contains(uri.host) &&
      uri.port == 443;
  final relative = !uri.hasScheme && !uri.hasAuthority;
  if (uri.userInfo.isNotEmpty || (!custom && !web && !relative)) return false;
  final path = custom ? '/${uri.host}${uri.path}' : uri.path;
  return const {'/webview', '/app/webview'}.contains(path);
}

Uri? webViewLinkTarget(Uri uri) {
  if (!isWebViewLink(uri)) return null;
  final urls = uri.queryParametersAll['url'];
  return urls?.length == 1 ? webViewUrl(urls!.single) : null;
}

/// Invalid native destinations must still fall back to Inbox/Home. A caller
/// can explicitly wrap one in /webview when it really wants the website.
bool isNativeAppLink(Uri uri) =>
    uri.scheme == 'https' &&
    uri.port == 443 &&
    const {'chessever.com', 'www.chessever.com'}.contains(uri.host) &&
    uri.pathSegments.firstOrNull == 'app';

/// Deliberately an exact host allowlist, never a suffix match. A link to a
/// partner, arbitrary subdomain, HTTP page or alternate port gets no session.
bool canShareWebViewSession(Uri uri) =>
    uri.scheme == 'https' &&
    uri.port == 443 &&
    uri.userInfo.isEmpty &&
    const {
      'chessever.com',
      'www.chessever.com',
      'broadcast.chessever.com',
    }.contains(uri.host);
