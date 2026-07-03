import 'dart:async';

import 'package:chessever2/repository/lichess/broadcast/lichess_broadcast_pairings_repository.dart';
import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class LichessPairingsRequest {
  const LichessPairingsRequest({
    required this.roundId,
    required this.tourId,
    this.tourSlug = '',
    this.roundSlug = '',
  });

  final String roundId;
  final String tourId;
  final String tourSlug;
  final String roundSlug;

  @override
  bool operator ==(Object other) =>
      other is LichessPairingsRequest &&
      other.roundId == roundId &&
      other.tourId == tourId;

  @override
  int get hashCode => Object.hash(roundId, tourId);
}

/// Published pairings for a single upcoming round, fetched straight from the
/// public Lichess broadcast API. Used by the Games tab as a FALLBACK while
/// our own `games` table has no rows for the round (round breaks): the data
/// hub's pairing sync may be disabled or lagging, but the boards are already
/// public on Lichess. Re-fetches every 90s while watched so pairings appear
/// shortly after Lichess publishes them; disposes as soon as no screen needs
/// it (e.g. once real rows exist in the DB).
final lichessPairingsFallbackProvider = FutureProvider.autoDispose
    .family<List<Games>, LichessPairingsRequest>((ref, request) async {
      final refreshTimer = Timer(const Duration(seconds: 90), () {
        ref.invalidateSelf();
      });
      ref.onDispose(refreshTimer.cancel);

      return ref
          .read(lichessBroadcastPairingsRepoProvider)
          .fetchRoundPairings(
            roundId: request.roundId,
            tourId: request.tourId,
            tourSlug: request.tourSlug,
            roundSlug: request.roundSlug,
          );
    });
