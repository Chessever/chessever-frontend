import 'package:chessever2/repository/supabase/round/round.dart';
import 'package:chessever2/repository/supabase/round/round_repository.dart';
import 'package:chessever2/repository/supabase/tour/tour_repository.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class NextRoundInfo {
  final String name;
  final DateTime startsAt;

  const NextRoundInfo({required this.name, required this.startsAt});
}

/// Resolves the next round (smallest `starts_at` in the future) across every
/// tour that belongs to the given group-broadcast event. Calendar/community
/// events have no rounds in our DB, so we skip the network call for those.
///
/// Intentionally NOT autoDispose: keeping the resolved round in cache across
/// scrolls prevents the card from flipping back to its loading/shimmer state
/// every time a card leaves and re-enters the viewport.
final eventNextRoundProvider = FutureProvider
    .family<NextRoundInfo?, String>((ref, eventId) async {
      if (eventId.startsWith('cal_event_')) return null;

      try {
        final tourRepo = ref.read(tourRepositoryProvider);
        final tours = await tourRepo.getTourByGroupId(eventId);
        if (tours.isEmpty) return null;

        final tourIds = tours.map((t) => t.id).toList(growable: false);
        final roundRepo = ref.read(roundRepositoryProvider);
        final grouped = await roundRepo.getRoundsByTourIds(tourIds);

        final now = DateTime.now();
        Round? best;
        DateTime? bestLocal;
        for (final rounds in grouped.values) {
          for (final r in rounds) {
            final startsAt = r.startsAt?.toLocal();
            if (startsAt == null || !startsAt.isAfter(now)) continue;
            if (bestLocal == null || startsAt.isBefore(bestLocal)) {
              best = r;
              bestLocal = startsAt;
            }
          }
        }

        if (best == null || bestLocal == null) return null;
        return NextRoundInfo(name: best.name, startsAt: bestLocal);
      } catch (e) {
        debugPrint('[eventNextRoundProvider] $eventId: $e');
        return null;
      }
    });
