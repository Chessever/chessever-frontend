import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';

/// Matches the first number in a round label, so `6`, `Round 6` and `6.1` all
/// resolve to a comparable value. Kept as a decimal parse because knockout
/// events label tie-breaks as `6.1`, `6.2` — those must stay *after* `6`.
final RegExp _roundNumberPattern = RegExp(r'\d+(?:\.\d+)?');

/// The epoch stand-in for a row with no play time. Ordering is newest-first, so
/// undated rows sink to the bottom rather than floating to the top.
final DateTime _undated = DateTime.fromMillisecondsSinceEpoch(0);

/// Orders a player's games newest-first.
///
/// Date is the primary key and stays authoritative: a genuinely newer game
/// always outranks a higher round number from an older date.
///
/// Round is only a **tie-breaker**, and it exists because Gamebase (TWIC) rows
/// carry a single `date` for a whole playing day — every round of an event can
/// share one date, leaving the comparator with nothing to separate them and
/// letting Round 1 surface above the latest round. Supabase-backed rows do not
/// have this problem: `getGamesByFideIdPaginated` already orders
/// `date_start desc, last_move_time desc` server-side, so their finer-grained
/// play time resolves the tie before this ever looks at a round.
///
/// The final `gameId` comparison keeps the result total and stable, so a
/// re-sort after a pagination merge cannot shuffle rows the user is reading.
int comparePlayerProfileGamesNewestFirst(GamesTourModel a, GamesTourModel b) {
  final dateComparison = (b.lastMoveTime ?? _undated).compareTo(
    a.lastMoveTime ?? _undated,
  );
  if (dateComparison != 0) return dateComparison;

  final aRound = _roundNumber(_roundLabel(a));
  final bRound = _roundNumber(_roundLabel(b));
  if (aRound != null || bRound != null) {
    // A row with no round sorts below one that has a round, rather than
    // colliding with round 0.
    final roundComparison = (bRound ?? -1).compareTo(aRound ?? -1);
    if (roundComparison != 0) return roundComparison;
  }

  return a.gameId.compareTo(b.gameId);
}

/// The round text to rank by, or `null` when the row never carried one.
///
/// `twic_profile` is the sentinel used when the Gamebase row had no `round`
/// field; treating it as a label would make every such row compare equal on a
/// number parsed out of nothing.
String? _roundLabel(GamesTourModel game) {
  if (game.roundId == 'twic_profile') return null;
  final slug = game.roundSlug;
  if (slug != null && slug.trim().isNotEmpty) return slug;
  return game.roundId;
}

double? _roundNumber(String? value) {
  if (value == null) return null;
  final match = _roundNumberPattern.firstMatch(value);
  return match == null ? null : double.tryParse(match.group(0)!);
}

/// Reads the Gamebase row's own `round` field.
///
/// The player-games endpoint returns `round` per game, but the profile mappers
/// used to overwrite it with an ECO code or time control before the model was
/// built — which is exactly why same-date events lost their ordering. Keeping
/// the server's value is what makes the tie-break above possible; [fallback]
/// preserves the previous display text for rows that genuinely have no round.
String playerProfileRoundLabel(
  Map<String, dynamic> row, {
  required String fallback,
}) {
  final round = row['round']?.toString().trim();
  return (round != null && round.isNotEmpty) ? round : fallback;
}
