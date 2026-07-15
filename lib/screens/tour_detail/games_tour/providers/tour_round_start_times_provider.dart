import 'package:chessever2/repository/supabase/round/round_repository.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Maps every published round of a tour to its scheduled start time.
///
/// Knockout matchup cards collapse the games of several source rounds into one
/// synthetic stage, so the only "when did this matchup happen" signal with time
/// precision is the source round's `starts_at`. Game rows carry date-granular
/// play dates (`gameDay`) that cannot order two matchups played on the same day,
/// and `lastMoveTime` is frequently null on bulk-imported finished games — hence
/// the ordering seam reads from this map first.
final tourRoundStartTimesProvider = FutureProvider.autoDispose
    .family<Map<String, DateTime?>, String>((ref, tourId) async {
      final rounds = await ref
          .watch(roundRepositoryProvider)
          .getRoundsByTourId(tourId);
      return {for (final round in rounds) round.id: round.startsAt};
    });
