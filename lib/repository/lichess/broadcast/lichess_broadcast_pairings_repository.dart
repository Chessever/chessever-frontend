import 'dart:async';
import 'dart:convert';

import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:http/http.dart' as http;

final lichessBroadcastPairingsRepoProvider =
    Provider<LichessBroadcastPairingsRepository>(
      (ref) => LichessBroadcastPairingsRepository(),
    );

/// User-Agent header for Lichess API requests
/// Required by Lichess to identify API consumers and coordinate breaking changes
const _lichessUserAgent = 'chessever.com';

const _placeholderNames = {'', '?', '??', 'tbd', 'tba', 'unknown'};

bool _isResolvedName(String? name) {
  final normalized = (name ?? '').trim().toLowerCase();
  return !_placeholderNames.contains(normalized);
}

/// Fetches an upcoming round's published pairings straight from the public
/// Lichess broadcast API. Fallback for round breaks where our own `games`
/// table has no rows for the round yet: Lichess publishes next-round boards
/// (resolved player names, no moves) minutes before the round starts.
class LichessBroadcastPairingsRepository {
  /// Endpoint: GET /api/broadcast/-/-/{roundId} — the tour/round slug
  /// segments are ignored by Lichess when the round id matches.
  static const _baseUrl = 'https://lichess.org/api/broadcast/-/-';

  Future<List<Games>> fetchRoundPairings({
    required String roundId,
    required String tourId,
    required String tourSlug,
    required String roundSlug,
  }) async {
    try {
      final uri = Uri.parse('$_baseUrl/$roundId');
      final resp = await http
          .get(uri, headers: {'User-Agent': _lichessUserAgent})
          .timeout(
            const Duration(seconds: 8),
            onTimeout:
                () =>
                    throw TimeoutException('Lichess broadcast round timeout'),
          );
      if (resp.statusCode != 200) {
        return const [];
      }
      final decoded = jsonDecode(resp.body);
      if (decoded is! Map<String, dynamic>) return const [];
      return parseRoundPairings(
        decoded,
        roundId: roundId,
        tourId: tourId,
        tourSlug: tourSlug,
        roundSlug: roundSlug,
      );
    } catch (e) {
      // Fallback data source only — the Games tab simply keeps its current
      // content when Lichess is unreachable.
      return const [];
    }
  }

  /// Maps the Lichess round JSON `games` array to [Games] rows shaped like
  /// our own upcoming-pairing rows (no moves, status "*"). Boards whose
  /// players are still unresolved ("?"/TBD) are dropped, mirroring the data
  /// hub's placeholder ingest gate.
  static List<Games> parseRoundPairings(
    Map<String, dynamic> roundJson, {
    required String roundId,
    required String tourId,
    required String tourSlug,
    required String roundSlug,
  }) {
    final rawGames = roundJson['games'];
    if (rawGames is! List) return const [];

    final pairings = <Games>[];
    for (var i = 0; i < rawGames.length; i++) {
      final rawGame = rawGames[i];
      if (rawGame is! Map<String, dynamic>) continue;
      final gameId = rawGame['id'] as String?;
      final rawPlayers = rawGame['players'];
      if (gameId == null || gameId.isEmpty || rawPlayers is! List) continue;
      if (rawPlayers.length < 2) continue;

      final players =
          rawPlayers
              .whereType<Map<String, dynamic>>()
              .map(Player.fromJson)
              .toList();
      if (players.length < 2 ||
          !_isResolvedName(players[0].name) ||
          !_isResolvedName(players[1].name)) {
        continue;
      }

      pairings.add(
        Games(
          id: gameId,
          roundId: roundId,
          roundSlug: roundSlug,
          tourId: tourId,
          tourSlug: tourSlug,
          name:
              rawGame['name'] as String? ??
              '${players[0].name} - ${players[1].name}',
          players: players,
          status: rawGame['status'] as String? ?? '*',
          lichessId: gameId,
          boardNr: i + 1,
        ),
      );
    }
    return pairings;
  }
}
