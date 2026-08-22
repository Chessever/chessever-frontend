import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';

final RegExp _roundNumberPattern = RegExp(r'\d+(?:\.\d+)?');

/// Keeps player-profile games newest-first. When Gamebase rows share the same
/// date, their numeric round is the recency tie-breaker.
int comparePlayerProfileGamesNewestFirst(GamesTourModel a, GamesTourModel b) {
  final aTime = a.lastMoveTime ?? DateTime.fromMillisecondsSinceEpoch(0);
  final bTime = b.lastMoveTime ?? DateTime.fromMillisecondsSinceEpoch(0);
  final dateComparison = bTime.compareTo(aTime);
  if (dateComparison != 0) return dateComparison;

  final aRound = _roundNumber(_roundLabel(a));
  final bRound = _roundNumber(_roundLabel(b));
  if (aRound != null || bRound != null) {
    final roundComparison = (bRound ?? -1).compareTo(aRound ?? -1);
    if (roundComparison != 0) return roundComparison;
  }

  return a.gameId.compareTo(b.gameId);
}

String? _roundLabel(GamesTourModel game) {
  if (game.roundId == 'twic_profile') return null;
  return game.roundSlug ?? game.roundId;
}

double? _roundNumber(String? value) {
  if (value == null) return null;
  final match = _roundNumberPattern.firstMatch(value);
  return match == null ? null : double.tryParse(match.group(0)!);
}

/// Preserves the Gamebase `round` field for display and recency ordering.
String playerProfileRoundLabel(
  Map<String, dynamic> row, {
  required String fallback,
}) {
  final round = row['round']?.toString().trim();
  return (round != null && round.isNotEmpty) ? round : fallback;
}
