import '../../repository/supabase/game/games.dart';

int? watchInt(Object? value) =>
    value is num ? value.toInt() : int.tryParse(value?.toString() ?? '');

class WatchEvent {
  const WatchEvent({
    required this.id,
    required this.name,
    this.timeControl = '',
  });
  factory WatchEvent.fromJson(Map<String, dynamic> json) => WatchEvent(
    id: json['id'].toString(),
    name: json['name'] as String? ?? 'Event',
    timeControl: json['time_control'] as String? ?? '',
  );
  final String id;
  final String name;
  final String timeControl;
}

class WatchTour {
  WatchTour({
    required this.id,
    required this.eventId,
    required this.name,
    required this.players,
  });
  factory WatchTour.fromJson(Map<String, dynamic> json) => WatchTour(
    id: json['id'].toString(),
    eventId: json['group_broadcast_id'].toString(),
    name: json['name'] as String? ?? 'Section',
    players: (json['players'] as List? ?? [])
        .whereType<Map>()
        .map((p) => WatchStanding.fromJson(Map<String, dynamic>.from(p)))
        .toList(),
  );
  final String id;
  final String eventId;
  final String name;
  final List<WatchStanding> players;

  /// Respect published ranks and tiebreak order. Without ranks, only score
  /// determines groups; equal-score players retain the source's ordering.
  List<WatchStanding> get standings {
    final indexed = players.asMap().entries.toList();
    final ranked = players.isNotEmpty && players.every((p) => p.rank != null);
    indexed.sort((a, b) {
      final byValue = ranked
          ? a.value.rank!.compareTo(b.value.rank!)
          : (b.value.score ?? -1).compareTo(a.value.score ?? -1);
      return byValue != 0 ? byValue : a.key.compareTo(b.key);
    });
    return indexed.map((e) => e.value).toList();
  }
}

class WatchStanding {
  const WatchStanding({
    required this.name,
    this.fideId,
    this.rank,
    this.rating,
    this.score,
    this.played,
    this.performance,
    this.ratingDiff,
    this.title = '',
    this.federation = '',
  });
  factory WatchStanding.fromJson(Map<String, dynamic> json) {
    int? metric(String flat, String nested) {
      final direct = watchInt(json[flat]);
      if (direct != null) return direct;
      final buckets = json[nested];
      if (buckets is Map) {
        for (final key in ['standard', 'classical', 'rapid', 'blitz']) {
          final value = watchInt(buckets[key]);
          if (value != null) return value;
        }
      }
      return null;
    }

    return WatchStanding(
      name: json['name'] as String? ?? 'Player',
      fideId: json['fideId']?.toString(),
      rank: watchInt(json['rank']),
      rating: watchInt(json['rating']),
      score: double.tryParse(json['score']?.toString() ?? ''),
      played: watchInt(json['played']),
      performance: metric('performance', 'performances'),
      ratingDiff: metric('ratingDiff', 'ratingDiffs'),
      title: json['title'] as String? ?? '',
      federation: json['fed'] as String? ?? '',
    );
  }
  final String name;
  final String? fideId;
  final int? rank;
  final int? rating;
  final double? score;
  final int? played;
  final int? performance;
  final int? ratingDiff;
  final String title;
  final String federation;
}

class WatchRound {
  const WatchRound({required this.id, required this.name, this.startsAt});
  factory WatchRound.fromJson(Map<String, dynamic> json) => WatchRound(
    id: json['id'].toString(),
    name: json['name'] as String? ?? 'Round',
    startsAt: DateTime.tryParse(json['starts_at']?.toString() ?? ''),
  );
  final String id;
  final String name;
  final DateTime? startsAt;
}

bool watchGameIsLive(Games game) =>
    ['*', 'live', 'ongoing'].contains(game.status?.trim().toLowerCase());

String watchResult(String? status) => switch (status) {
  '1/2-1/2' => '½–½',
  '1-0' => '1–0',
  '0-1' => '0–1',
  '*' || 'live' || 'ongoing' => 'Live',
  _ => 'Scheduled',
};

String watchScore(double? value) {
  if (value == null) return 'Unavailable';
  final whole = value.floor();
  if (value == whole) return whole.toString();
  if (value - whole == 0.5) return whole == 0 ? '½' : '$whole½';
  return value.toString();
}

String watchStandingScore(WatchStanding player) =>
    '${watchScore(player.score)}'
    '${player.played == null ? '' : ' / ${player.played}'}';

bool watchPlayerMatches(Player player, WatchStanding standing) =>
    (int.tryParse(standing.fideId ?? '') ?? 0) > 0 && player.fideId > 0
    ? player.fideId.toString() == standing.fideId
    : player.name.trim().toLowerCase() == standing.name.trim().toLowerCase();
