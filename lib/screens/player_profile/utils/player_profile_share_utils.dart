/// Universal link for a player's overall profile page on the web,
/// `https://chessever.com/player/<fideId>`. The web route also serves a
/// canonical `/player/<name-slug>/<fideId>` form; both open the in-app player
/// profile via the deep link handler.
///
/// Returns null when there is no FIDE id — the web frontend cannot resolve
/// gamebase-only players, so those profiles share the image without a link.
String? buildPlayerProfileShareUrl(int? fideId) {
  if (fideId == null || fideId <= 0) return null;
  return 'https://chessever.com/player/$fideId';
}
