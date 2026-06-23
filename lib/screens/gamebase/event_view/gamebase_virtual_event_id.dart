/// Sentinel identity for gamebase-only "virtual" events rendered inside the
/// real tournament detail screen. Kept dependency-free (no model/repository
/// imports) so widely-imported files like `games_tour_model.dart` can use it
/// without creating an import cycle.
library;

const String _virtualPrefix = 'gamebase::';
const String _virtualV2Prefix = 'gamebasev2::';

String virtualBroadcastId(String eventName, {String? site, String? slug}) {
  final clean = eventName.trim();
  final cleanSite = _emptyToNull(site);
  final cleanSlug = _emptyToNull(slug);
  if ((cleanSite == null || cleanSite.isEmpty) &&
      (cleanSlug == null || cleanSlug.isEmpty)) {
    return '$_virtualPrefix$clean';
  }
  final query =
      Uri(
        queryParameters: {
          'name': clean,
          if (cleanSite != null) 'site': cleanSite,
          if (cleanSlug != null) 'slug': cleanSlug,
        },
      ).query;
  return '$_virtualV2Prefix$query';
}

bool isVirtualGamebaseId(String? id) =>
    id != null &&
    (id.startsWith(_virtualPrefix) || id.startsWith(_virtualV2Prefix));

GamebaseVirtualEventKey? virtualEventKeyFromId(String? id) {
  if (id == null) return null;
  if (id.startsWith(_virtualPrefix)) {
    return GamebaseVirtualEventKey(
      eventName: id.substring(_virtualPrefix.length),
    );
  }
  if (!id.startsWith(_virtualV2Prefix)) return null;
  final params = Uri.splitQueryString(id.substring(_virtualV2Prefix.length));
  final name = params['name']?.trim();
  if (name == null || name.isEmpty) return null;
  return GamebaseVirtualEventKey(
    eventName: name,
    site: _emptyToNull(params['site']),
    slug: _emptyToNull(params['slug']),
  );
}

String? eventNameFromVirtualId(String? id) =>
    virtualEventKeyFromId(id)?.eventName;

class GamebaseVirtualEventKey {
  const GamebaseVirtualEventKey({
    required this.eventName,
    this.site,
    this.slug,
  });

  final String eventName;
  final String? site;
  final String? slug;
}

String? _emptyToNull(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}
