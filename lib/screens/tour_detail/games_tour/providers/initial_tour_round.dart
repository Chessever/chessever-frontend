import 'package:chessever2/repository/supabase/round/round.dart';

/// Resolve only within the selected section. Explicit navigation wins over
/// live-round hints; future rounds never replace the latest started round.
String? initialTourRoundId({
  required List<Round> rounds,
  required DateTime now,
  String? requestedRoundId,
  List<String> liveRoundIds = const [],
}) {
  if (rounds.isEmpty) return null;
  if (rounds.any((round) => round.id == requestedRoundId)) {
    return requestedRoundId;
  }
  int newestFirst(Round a, Round b) {
    final date = (b.startsAt ?? b.createdAt).compareTo(
      a.startsAt ?? a.createdAt,
    );
    return date != 0 ? date : a.id.compareTo(b.id);
  }

  final live =
      rounds.where((r) => liveRoundIds.contains(r.id)).toList()
        ..sort(newestFirst);
  if (live.isNotEmpty) return live.first.id;
  final started =
      rounds
          .where((r) => r.startsAt != null && !r.startsAt!.isAfter(now))
          .toList()
        ..sort(newestFirst);
  if (started.isNotEmpty) return started.first.id;
  // Unknown start times need actual game-activity evidence from the caller.
  if (rounds.any((r) => r.startsAt == null)) return null;
  final upcoming = rounds.toList()..sort((a, b) => -newestFirst(a, b));
  return upcoming.first.id;
}
