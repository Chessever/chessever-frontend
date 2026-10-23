import '../../utils/favorite_event_ids.dart';

/// Only a phone-owned display snapshot crosses WatchConnectivity. No session,
/// refresh token, email, or privileged key is ever sent to the watch.
class WatchAccount {
  const WatchAccount({
    required this.revision,
    this.userId,
    this.name = '',
    this.eventIds = const [],
    this.playerIds = const [],
    this.playerNames = const [],
    this.preferences = const {},
    this.publicApiKey = '',
  });

  static const kind = 'chessever.account.v1';
  final int revision;
  final String? userId;
  final String name;
  final List<String> eventIds;
  final List<String> playerIds;
  final List<String> playerNames;
  final Map<String, bool> preferences;
  final String publicApiKey;
  bool get signedIn => userId != null;

  factory WatchAccount.fromJson(Map<String, dynamic> json) {
    final userId = json['userId'] as String?;
    List<String> strings(String key) =>
        (json[key] as List? ?? []).whereType<String>().toList();
    return WatchAccount(
      revision: (json['revision'] as num?)?.toInt() ?? 0,
      userId: userId,
      name: userId == null ? '' : json['name'] as String? ?? '',
      eventIds: userId == null ? const [] : strings('eventIds'),
      playerIds: userId == null ? const [] : strings('playerIds'),
      playerNames: userId == null ? const [] : strings('playerNames'),
      preferences: userId == null
          ? const {}
          : {
              for (final entry in (json['preferences'] as Map? ?? {}).entries)
                if (entry.key is String && entry.value is bool)
                  entry.key as String: entry.value as bool,
            },
      publicApiKey: json['publicApiKey'] as String? ?? '',
    );
  }

  Map<String, Object?> toJson() => {
    'kind': kind,
    'revision': revision,
    'userId': userId,
    'name': signedIn ? name : '',
    'eventIds': signedIn ? eventIds : <String>[],
    'playerIds': signedIn ? playerIds : <String>[],
    'playerNames': signedIn ? playerNames : <String>[],
    'preferences': signedIn ? preferences : <String, bool>{},
    'publicApiKey': publicApiKey,
  };

  bool followsPlayer(String? fideId, String playerName) =>
      signedIn &&
      ((fideId != null && playerIds.contains(fideId)) ||
          playerNames.any(
            (name) => name.toLowerCase() == playerName.toLowerCase(),
          ));

  bool followsEvent(String id, String name) =>
      signedIn &&
      favoriteEventIdCandidates(id, eventName: name).any(eventIds.contains);
}
