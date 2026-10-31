import 'app_destination.dart';

/// News IDs are exact native article identities, never a player/event fallback.
/// Ignore any competing route/url in this notification category.
AppDestination? favoritePlayerNewsDestination(Map<String, dynamic> data) {
  if (data['type'] != 'favorite_player_news') return null;
  final value = data['news_id'];
  final id = value is int
      ? '$value'
      : value is String
      ? value
      : '';
  if (!RegExp(r'^[1-9][0-9]{0,14}$').hasMatch(id)) return null;
  return parseAppDestination('/app/news/$id');
}
