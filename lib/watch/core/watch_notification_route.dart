import 'dart:convert';

class WatchNotificationRoute {
  const WatchNotificationRoute({
    this.eventId,
    this.tourId,
    this.roundId,
    this.gameId,
  });
  final String? eventId;
  final String? tourId;
  final String? roundId;
  final String? gameId;

  factory WatchNotificationRoute.fromPayload(Map<String, dynamic> payload) {
    Map<String, dynamic> object(Object? value) {
      try {
        final data = value is String ? jsonDecode(value) : value;
        return data is Map ? Map<String, dynamic>.from(data) : {};
      } catch (_) {
        return {};
      }
    }

    final custom = object(payload['custom']);
    final data = {
      ...payload,
      ...object(payload['data']),
      ...object(custom['a']),
    };
    final url = Uri.tryParse(
      data['url'] is String ? data['url'] as String : '',
    );
    if (url != null &&
        url.scheme == 'https' &&
        const ['chessever.com', 'www.chessever.com'].contains(url.host)) {
      final parts = url.pathSegments;
      if (parts.length >= 2 && parts.first == 'games') {
        data.putIfAbsent('game_id', () => parts[1]);
      } else if (parts.length >= 2 && parts.first == 'broadcast') {
        data.putIfAbsent(
          'group_broadcast_id',
          () => parts.length >= 3 ? parts[2] : parts[1],
        );
      }
    }
    String? id(List<String> keys) {
      for (final key in keys) {
        final value = data[key];
        if (value is String &&
            RegExp(r'^[A-Za-z0-9_-]{1,100}$').hasMatch(value)) {
          return value;
        }
      }
      return null;
    }

    return WatchNotificationRoute(
      eventId: id([
        'group_broadcast_id',
        'groupBroadcastId',
        'group_id',
        'event_id',
      ]),
      tourId: id(['tour_id', 'tourId', 'category_id']),
      roundId: id(['round_id', 'roundId']),
      gameId: id(['game_id', 'gameId']),
    );
  }
}
