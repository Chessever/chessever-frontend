import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';

/// A matchup's own kickoff. Shared stage dates and last-move timestamps are
/// never start times. Identity and UTC validation mirror the web schedule.
DateTime? matchPlayStartsAt(
  List<GamesTourModel> games, {
  Map<String, List<Map<String, dynamic>>> schedulesByTourId = const {},
  Map<String, DateTime?> ownRoundStartsById = const {},
}) {
  if (games.isEmpty) return null;
  final game = games.first;
  final a = game.whitePlayer.fideId;
  final b = game.blackPlayer.fideId;
  final pair = a == null || b == null || a <= 0 || b <= 0 || a == b
      ? null
      : ([a.toString(), b.toString()]..sort()).join(':');
  DateTime? scheduled;
  var conflicting = false;
  for (final row in schedulesByTourId[game.tourId] ?? const []) {
    if (row['roundId'] != game.roundId || pair == null) continue;
    final ids = row['fideIds'];
    final iso = row['startsAt'];
    if (ids is! List ||
        ids.length != 2 ||
        ids.any(
          (id) => id is! String || !RegExp(r'^[1-9]\d{0,8}$').hasMatch(id),
        ) ||
        (List<String>.from(ids)..sort()).join(':') != pair ||
        iso is! String ||
        !RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$').hasMatch(iso)) {
      continue;
    }
    final at = DateTime.tryParse(iso);
    if (at == null || at.toIso8601String() != iso.replaceFirst('Z', '.000Z')) {
      continue;
    }
    if (scheduled != null && scheduled != at) conflicting = true;
    scheduled = at;
  }
  if (conflicting) return null;
  if (scheduled != null) return scheduled;
  DateTime? first;
  for (final game in games) {
    final at = ownRoundStartsById[game.roundId];
    if (at != null && (first == null || at.isBefore(first))) first = at;
  }
  return first;
}
