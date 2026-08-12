import 'dart:async';

import 'package:chessever2/repository/supabase/supabase.dart';
import 'package:chessever2/screens/standings/player_standing_model.dart';
import 'package:chessever2/screens/standings/standings_builder.dart';
import 'package:chessever2/screens/standings/team_standing_model.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_mode_provider.dart';
import 'package:chessever2/screens/tour_detail/team_tour/team_tour_screen_provider.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Maps event / broadcast time-control labels to the FIDE rating bucket used
/// by `chess_players` (`standard` | `rapid` | `blitz`).
///
/// Accepts both the compact group_broadcast value (`"rapid"`) and free-form
/// clock strings (`"45 min + 10 sec"`, `"90min/40moves+…"`). When the string
/// is ambiguous we default to classical/standard — the majority of team
/// events.
String normalizeEventTimeControlBucket(String? raw) {
  final lower = (raw ?? '').trim().toLowerCase();
  if (lower.isEmpty) return 'standard';
  if (lower.contains('blitz') || lower.contains('bullet')) return 'blitz';
  if (lower.contains('rapid')) return 'rapid';
  if (lower.contains('classic') ||
      lower.contains('standard') ||
      lower.contains('classical')) {
    return 'standard';
  }
  // Bare enum from group_broadcasts.time_control.
  if (lower == 'blitz' || lower == 'bullet') return 'blitz';
  if (lower == 'rapid') return 'rapid';
  return 'standard';
}

/// Mean of strictly positive Elo values, rounded to the nearest integer.
/// Returns null when nothing usable is present.
int? averagePositiveRatings(Iterable<int> ratings) {
  var sum = 0;
  var count = 0;
  for (final r in ratings) {
    if (r > 0) {
      sum += r;
      count += 1;
    }
  }
  if (count == 0) return null;
  return (sum / count).round();
}

/// Synchronous roster average using the standings [PlayerStandingModel.score]
/// field (the tour feed's event-time-control rating). Instant UI fallback
/// while the FIDE batch is in flight.
int? teamAverageEloFromStandings(TeamStandingModel team) =>
    averagePositiveRatings(team.players.map((p) => p.score));

/// Formats an average Elo for compact UI (e.g. app bar): `"2654"` or `"—"`.
String formatTeamAvgElo(int? avg) => avg == null ? '—' : avg.toString();

int? _ratingFromChessPlayerRow(
  Map<String, dynamic> row,
  String timeControlBucket,
) {
  final raw = switch (timeControlBucket) {
    'rapid' => row['rapid_rating'],
    'blitz' => row['blitz_rating'],
    _ => row['rating'],
  };
  if (raw is int && raw > 0) return raw;
  if (raw is num && raw > 0) return raw.round();
  if (raw is String) {
    final parsed = int.tryParse(raw) ?? double.tryParse(raw)?.round();
    if (parsed != null && parsed > 0) return parsed;
  }
  return null;
}

/// Average Elo of a team's roster for the event's time control.
///
/// 1. Resolve TC bucket from [selectedBroadcastModelProvider.timeControl]
/// 2. Batch-load `chess_players` ratings (standard / rapid / blitz) by FIDE id
/// 3. Per player: TC rating from FIDE → else standings score
/// 4. Mean of positive ratings
final teamAvgEloProvider = FutureProvider.autoDispose.family<int?, String>((
  ref,
  teamName,
) async {
  final trimmed = teamName.trim();
  if (trimmed.isEmpty) return null;

  TeamStandingModel? team = ref.watch(selectedTeamStandingProvider);
  if (team == null || team.teamName != trimmed) {
    final standings = ref.watch(teamStandingsProvider).valueOrNull;
    if (standings != null) {
      for (final t in standings) {
        if (t.teamName == trimmed) {
          team = t;
          break;
        }
      }
    }
  }
  if (team == null) return null;

  final fallback = teamAverageEloFromStandings(team);
  final broadcastTc = ref.watch(selectedBroadcastModelProvider)?.timeControl;
  final bucket = normalizeEventTimeControlBucket(broadcastTc);

  final fideIds = <int>[
    for (final p in team.players)
      if (p.fideId != null && p.fideId! > 0) p.fideId!,
  ];
  if (fideIds.isEmpty) return fallback;

  try {
    final supabase = ref.read(supabaseProvider);
    // Same chunk/timeout policy as standings FIDE enrichment — a single large
    // inFilter can stall release HTTP without throwing.
    final byFide = <int, Map<String, dynamic>>{};
    final unique = fideIds.toSet().toList(growable: false);
    const chunkSize = kStandingsFideEloInFilterChunkSize;

    Future<void> loadChunks() async {
      for (var i = 0; i < unique.length; i += chunkSize) {
        final end =
            (i + chunkSize < unique.length) ? i + chunkSize : unique.length;
        final chunk = unique.sublist(i, end);
        final rows = await supabase
            .from('chess_players')
            .select('fideid, rating, rapid_rating, blitz_rating')
            .inFilter('fideid', chunk);
        for (final row in rows as List) {
          final map = Map<String, dynamic>.from(row as Map);
          final id = map['fideid'];
          final fideId =
              id is int
                  ? id
                  : id is num
                  ? id.toInt()
                  : int.tryParse('$id');
          if (fideId == null) continue;
          byFide[fideId] = map;
        }
      }
    }

    await loadChunks().timeout(kStandingsFideEloFetchTimeout);

    final ratings = <int>[];
    for (final p in team.players) {
      int? elo;
      final fid = p.fideId;
      if (fid != null && byFide.containsKey(fid)) {
        elo = _ratingFromChessPlayerRow(byFide[fid]!, bucket);
      }
      elo ??= p.score > 0 ? p.score : null;
      if (elo != null && elo > 0) ratings.add(elo);
    }
    return averagePositiveRatings(ratings) ?? fallback;
  } catch (_) {
    return fallback;
  }
});
