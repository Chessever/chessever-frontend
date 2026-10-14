/// Identity of an unfiltered organizer event, without player or round URLs.
String? info64EventUrl(dynamic value, {bool team = false}) {
  if (value is! String) return null;
  final uri = Uri.tryParse(value);
  if (uri == null ||
      !['http', 'https'].contains(uri.scheme) ||
      uri.host != 'info64.org' ||
      uri.userInfo.isNotEmpty ||
      uri.hasPort ||
      uri.hasQuery ||
      uri.hasFragment) {
    return null;
  }
  final pattern = team
      ? r'^(/team/[a-z0-9]+(?:-[a-z0-9]+)*)(?:/(?:standings|crosstable|listing))?/?$'
      : r'^(/[a-z0-9]+(?:-[a-z0-9]+)*)(?:/(?:standings|crosstable))?/?$';
  final event = RegExp(pattern).firstMatch(uri.path)?.group(1);
  return event == null ? null : 'https://info64.org$event';
}
