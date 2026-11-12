import '../../repository/supabase/game/games.dart';

int? watchInt(Object? value) =>
    value is num ? value.toInt() : int.tryParse(value?.toString() ?? '');

class WatchEvent {
  const WatchEvent({
    required this.id,
    required this.name,
    this.timeControl = '',
    this.closestRound,
  });
  factory WatchEvent.fromJson(Map<String, dynamic> json) => WatchEvent(
    id: json['id'].toString(),
    name: json['name'] as String? ?? 'Event',
    timeControl: json['time_control'] as String? ?? '',
    closestRound: DateTime.tryParse(
      json['date_closest_round'] as String? ?? '',
    )?.toLocal(),
  );
  final String id;
  final String name;
  final String timeControl;

  /// The feed's closest round start. It can already be in the past (a round
  /// in progress, or a finished event still listed as current).
  final DateTime? closestRound;
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

/// Feed time controls arrive lowercase (`rapid`, `standard`); set them as a
/// label: `Rapid`, `Classical`.
String? watchTimeControl(String? value) {
  if (value == null || value.isEmpty) return value;
  if (value.toLowerCase() == 'standard') return 'Classical';
  return value[0].toUpperCase() + value.substring(1);
}

/// Whose move it is in [fen], or null when the FEN is missing.
bool? watchWhiteToMove(String? fen) {
  final parts = fen?.split(' ');
  if (parts == null || parts.length < 2) return null;
  return parts[1] == 'w';
}

/// Live polling keeps its normal tick, but when watchOS is in Low Power Mode
/// or under thermal pressure only every fourth tick fetches (15 s → 60 s).
bool watchShouldPoll(int tick, {required bool constrained}) =>
    !constrained || tick % 4 == 0;

bool watchIsLive(String? status) =>
    status == '*' || status == 'live' || status == 'ongoing';

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

/// Short form of a player's name for tight rows: `Carlsen, Magnus` →
/// `Carlsen, M.`, `Magnus Carlsen` → `M. Carlsen`. Names that cannot be
/// shortened come back unchanged.
String watchShortName(String name) {
  final trimmed = name.trim();
  final comma = trimmed.indexOf(',');
  if (comma > 0) {
    final last = trimmed.substring(0, comma).trim();
    final first = trimmed.substring(comma + 1).trim();
    if (first.isEmpty) return last;
    return '$last, ${String.fromCharCode(first.runes.first)}.';
  }
  final parts = trimmed.split(RegExp(r'\s+'));
  if (parts.length < 2) return trimmed;
  return '${String.fromCharCode(parts.first.runes.first)}. ${parts.skip(1).join(' ')}';
}

/// Where a round stands, read from its boards and its start time.
enum WatchRoundPhase { upcoming, live, finished, empty }

class WatchRoundState {
  const WatchRoundState(
    this.phase, {
    this.live = 0,
    this.done = 0,
    this.total = 0,
  });
  final WatchRoundPhase phase;
  final int live;
  final int done;
  final int total;
}

bool watchGameIsFinished(Games game) =>
    const ['1-0', '0-1', '1/2-1/2'].contains(game.status?.trim());

WatchRoundState watchRoundState(
  WatchRound? round,
  List<Games> games,
  DateTime now,
) {
  final live = games.where(watchGameIsLive).length;
  final done = games.where(watchGameIsFinished).length;
  if (round?.startsAt != null &&
      round!.startsAt!.isAfter(now) &&
      live == 0 &&
      done == 0) {
    return const WatchRoundState(WatchRoundPhase.upcoming);
  }
  if (games.isEmpty) return const WatchRoundState(WatchRoundPhase.empty);
  return WatchRoundState(
    live > 0 ? WatchRoundPhase.live : WatchRoundPhase.finished,
    live: live,
    done: done,
    total: games.length,
  );
}

/// One team match inside a round: the boards between the same two teams.
/// [home] is the team named first by the organiser, read from the lowest
/// board. Colours alternate per board in team chess, so every point is
/// credited to the team of the player who earned it, never to a colour.
class WatchTeamMatch {
  WatchTeamMatch(this.home, this.away);
  final String home;
  final String away;
  final List<Games> games = [];
  double homeScore = 0;
  double awayScore = 0;

  String get key => watchTeamMatchKey(home, away);
  bool get live => games.any(watchGameIsLive);
  bool get finished => games.isNotEmpty && games.every(watchGameIsFinished);
  int get firstBoard => games
      .map((g) => g.boardNr ?? 1 << 20)
      .fold(1 << 20, (a, b) => a < b ? a : b);
}

String watchTeamMatchKey(String a, String b) {
  final names = [a.trim().toLowerCase(), b.trim().toLowerCase()]..sort();
  return names.join('\u0000');
}

String? _team(Player? player) {
  final team = player?.team.trim();
  return team == null || team.isEmpty ? null : team;
}

/// Groups a round's boards into team matches, or returns null when the
/// round is not a team round (fewer than three in four boards name two
/// different teams). Boards without teams are left out of the matches.
List<WatchTeamMatch>? watchTeamMatches(List<Games> games) {
  if (games.isEmpty) return null;
  final teamed = games.where((g) {
    final white = _team(g.players?.elementAtOrNull(0));
    final black = _team(g.players?.elementAtOrNull(1));
    return white != null &&
        black != null &&
        white.toLowerCase() != black.toLowerCase();
  }).toList();
  if (teamed.length * 4 < games.length * 3) return null;
  teamed.sort((a, b) => (a.boardNr ?? 1 << 20).compareTo(b.boardNr ?? 1 << 20));
  final matches = <String, WatchTeamMatch>{};
  for (final game in teamed) {
    final white = _team(game.players![0])!;
    final black = _team(game.players![1])!;
    final match = matches.putIfAbsent(
      watchTeamMatchKey(white, black),
      () => WatchTeamMatch(white, black),
    );
    match.games.add(game);
    final whiteIsHome =
        white.trim().toLowerCase() == match.home.trim().toLowerCase();
    final (double w, double b) = switch (game.status?.trim()) {
      '1-0' => (1, 0),
      '0-1' => (0, 1),
      '1/2-1/2' => (0.5, 0.5),
      _ => (0, 0),
    };
    match.homeScore += whiteIsHome ? w : b;
    match.awayScore += whiteIsHome ? b : w;
  }
  return matches.values.toList()
    ..sort((a, b) => a.firstBoard.compareTo(b.firstBoard));
}
