import 'dart:async';
import 'dart:math' as math;

import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/repository/supabase/tour/tour.dart';
import 'package:chessever2/screens/standings/player_standing_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// PostgREST `in` filters blow up URL size (and can hang on some release HTTP
/// stacks) when hundreds of FIDE ids are packed into one request. Match the
/// chunk size used by [ChessPlayerRepository].
const int kStandingsFideEloInFilterChunkSize = 150;

/// Wall-clock budget for the optional FIDE Elo enrichment pass. Standings must
/// still paint if this is slow or stuck — rating-diff is nice-to-have.
const Duration kStandingsFideEloFetchTimeout = Duration(seconds: 8);

/// Shared standings computation used by the tournament detail "Standings" tab
/// and the smart event per-event standings sections. Extracted from
/// [PlayerTourScreenNotifier] so both surfaces produce identical numbers.

/// Uses the standings feed's played count when it is available. A zero value
/// represents a missing/unavailable count in [TournamentPlayer], so only then
/// do we fall back to the number of finished games found locally.
int resolveStandingsPlayedCount({
  required int sourcePlayed,
  required int countedFinishedGames,
}) => sourcePlayed > 0 ? sourcePlayed : countedFinishedGames;

/// Signature over the parts of live games that can change standings. Watching
/// `gamesTourProvider(tourId).select(standingsGamesSignature)` means move and
/// clock ticks don't rebuild standings, but new games or result changes do.
String standingsGamesSignature(AsyncValue<List<Games>> gamesAsync) {
  final games = gamesAsync.valueOrNull;
  if (games == null) {
    return gamesAsync.isLoading ? 'loading' : 'error';
  }

  return games
      .map((game) {
        final playersSignature =
            game.players?.map(_standingsPlayerSignature).join('~') ?? '';
        return [
          game.id,
          game.roundId,
          game.tourId,
          game.status ?? '',
          game.boardNr ?? '',
          game.timeControl ?? '',
          playersSignature,
        ].join('|');
      })
      .join('||');
}

String _standingsPlayerSignature(Player player) {
  return [
    player.name,
    player.title,
    player.rating,
    player.fideId,
    player.fed,
    player.team,
  ].join(':');
}

Future<List<PlayerStandingModel>> buildStandingsFromData({
  required SupabaseClient supabase,
  required List<TournamentPlayer> tournamentPlayers,
  required List<GamesTourModel> gamesTourModels,
  bool useExternalOrder = false,
  bool singleTourScope = true,
}) async {
  final players = mergeTournamentRosterWithGamePlayers(
    tournamentPlayers: tournamentPlayers,
    gamesTourModels: gamesTourModels,
  );

  // Index games by normalized player name
  final gamesByPlayerKey = <String, List<_PlayerGameRef>>{};

  for (final game in gamesTourModels) {
    for (final ref in _expandGameRefs(game)) {
      if (ref.key.isEmpty) continue;
      gamesByPlayerKey.putIfAbsent(ref.key, () => []).add(ref);
    }
  }

  // Batch-fetch FIDE per-time-control ratings + K-factors for every player
  // with a fideId. This lets us apply the authoritative K (e.g. rapid_k=10
  // for someone who hit 2400 in rapid, not the hardcoded 20) instead of
  // guessing. One round-trip, all players at once.
  final fideIds = <int>{};
  for (final player in players) {
    final id = player.fideId;
    if (id != null && id > 0) fideIds.add(id);
  }
  // Also include opponents discovered via gamesByPlayerKey, since the
  // opponent's rating feeds into the expected-score calc.
  for (final game in gamesTourModels) {
    for (final card in [game.whitePlayer, game.blackPlayer]) {
      final id = card.fideId;
      if (id != null && id > 0) fideIds.add(id);
    }
  }
  final fideEloByFideId = await _fetchFideEloBatch(supabase, fideIds.toList());

  // Enrich player data and compute match results
  final enrichedPlayers = <TournamentPlayer>[];

  for (final player in players) {
    final key = _canonicalName(player.name);
    final playerGames = gamesByPlayerKey[key] ?? const <_PlayerGameRef>[];
    final referenceCard =
        playerGames.isNotEmpty ? playerGames.first.playerCard : null;

    final updatedPlayer = player.copyWith(
      federation:
          (player.federation?.trim().isNotEmpty ?? false)
              ? player.federation
              : _nonEmpty(referenceCard?.federation) ?? player.federation,
      title:
          (player.title?.trim().isNotEmpty ?? false)
              ? player.title
              : _nonEmpty(referenceCard?.title) ?? player.title,
      rating:
          (player.rating != null && player.rating! > 0)
              ? player.rating
              : _positive(referenceCard?.rating) ?? player.rating,
      fideId:
          (player.fideId != null && player.fideId! > 0)
              ? player.fideId
              : referenceCard?.fideId ?? player.fideId,
    );

    var calculatedScore = 0.0;
    var gamesPlayed = 0;
    var totalRatingDiff = 0.0;
    var hasCalculatedRatingDiff = false;

    for (final gameRef in playerGames) {
      final status = gameRef.game.gameStatus;
      if (status == GameStatus.ongoing || status == GameStatus.unknown) {
        continue;
      }

      gamesPlayed++;
      switch (status) {
        case GameStatus.whiteWins:
          if (gameRef.isWhite) calculatedScore += 1.0;
          break;
        case GameStatus.blackWins:
          if (!gameRef.isWhite) calculatedScore += 1.0;
          break;
        case GameStatus.draw:
          calculatedScore += 0.5;
          break;
        default:
          break;
      }

      final playerRating =
          _getPlayerRating(
            gameRef.game,
            playerCard: gameRef.playerCard,
            isWhite: gameRef.isWhite,
          ) ??
          _positive(updatedPlayer.rating)?.toDouble();
      final opponentCard =
          gameRef.isWhite ? gameRef.game.blackPlayer : gameRef.game.whitePlayer;
      final opponentRating = _getPlayerRating(
        gameRef.game,
        playerCard: opponentCard,
        isWhite: !gameRef.isWhite,
      );

      if (playerRating != null && opponentRating != null) {
        final tc = gameRef.game.timeControl;
        final playerFide =
            updatedPlayer.fideId != null
                ? fideEloByFideId[updatedPlayer.fideId!]
                : null;
        final opponentFideId = opponentCard.fideId;
        final opponentFide =
            opponentFideId != null ? fideEloByFideId[opponentFideId] : null;

        // Prefer FIDE per-time-control rating + K from chess_players.
        // A 2405 standard player can have rapid_k=10 while our old heuristic
        // hardcoded K=20 for rapid — causing 2x the real rating change.
        final fideK = tc != null ? playerFide?.getK(tc) : null;
        final fidePlayerRating =
            tc != null ? playerFide?.getRating(tc)?.toDouble() : null;
        final fideOpponentRating =
            tc != null ? opponentFide?.getRating(tc)?.toDouble() : null;

        totalRatingDiff += _calculateFideRatingChange(
          fidePlayerRating ?? playerRating,
          fideOpponentRating ?? opponentRating,
          status,
          gameRef.isWhite,
          title: gameRef.playerCard.title,
          timeControl: tc,
          fideK: fideK,
        );
        hasCalculatedRatingDiff = true;
      }
    }

    // Source-of-truth policy:
    //   Lichess (and chess-results) ship a per-player `score` + `ratingDiff`
    //   that already accounts for custom scoring (e.g. Norway Chess 3-1-0 +
    //   armageddon 1.5), official FIDE per-time-control K-factors, and rated
    //   vs. unrated rounds. We CANNOT reproduce any of that from `1/0/½`
    //   game outcomes alone, so whenever the source value is present we
    //   surface it verbatim. Client-side calculation stays as the fallback
    //   for legacy/empty payloads only.
    final double finalScore = updatedPlayer.score ?? calculatedScore;
    final int finalPlayed = resolveStandingsPlayedCount(
      sourcePlayed: updatedPlayer.played,
      countedFinishedGames: gamesPlayed,
    );
    final int? finalRatingDiff =
        updatedPlayer.ratingDiff ??
        (hasCalculatedRatingDiff ? totalRatingDiff.round() : null);

    enrichedPlayers.add(
      updatedPlayer.copyWith(
        score: finalScore,
        played: finalPlayed,
        ratingDiff: finalRatingDiff,
      ),
    );
  }

  // Buchholz Cut-1 tiebreaker: sum of opponents' final scores minus the
  // single lowest opponent score. Requires every player's score to be known,
  // so it runs as a second pass after the enrichment loop above.
  final scoreByKey = <String, double>{};
  for (final player in enrichedPlayers) {
    scoreByKey[_canonicalName(player.name)] = player.score ?? 0.0;
  }

  final buchholzByKey = <String, double>{};
  for (final player in enrichedPlayers) {
    final key = _canonicalName(player.name);
    final playerGames = gamesByPlayerKey[key] ?? const <_PlayerGameRef>[];

    final opponentScores = <double>[];
    for (final gameRef in playerGames) {
      final status = gameRef.game.gameStatus;
      if (status == GameStatus.ongoing || status == GameStatus.unknown) {
        continue;
      }
      final opponentCard =
          gameRef.isWhite ? gameRef.game.blackPlayer : gameRef.game.whitePlayer;
      final opponentKey = _canonicalGameKey(opponentCard.name);
      if (opponentKey.isEmpty) continue;
      opponentScores.add(scoreByKey[opponentKey] ?? 0.0);
    }

    double buchholz;
    if (opponentScores.isEmpty) {
      buchholz = 0.0;
    } else {
      final sum = opponentScores.fold<double>(0.0, (a, b) => a + b);
      final lowest = opponentScores.reduce((a, b) => a < b ? a : b);
      buchholz = sum - lowest;
    }
    buchholzByKey[key] = buchholz;
  }

  // Trust the server-supplied ranking whenever it exists AND scope is a
  // single tour. Lichess applies the tournament's official tiebreak system
  // (Direct Encounter, Sonneborn-Berger, Koya, etc.) which we cannot
  // reproduce client-side. chess-results tours come pre-sorted too
  // (flagged via `useExternalOrder`). Multi-tour pagination scopes concat
  // players from independent standings — ranks collide there, so client
  // sort is the only meaningful order.
  final hasUniversalRank =
      singleTourScope &&
      enrichedPlayers.isNotEmpty &&
      enrichedPlayers.every((p) => p.rank != null);
  if (useExternalOrder || hasUniversalRank) {
    enrichedPlayers.sort((a, b) {
      final aRank = a.rank ?? 1 << 30;
      final bRank = b.rank ?? 1 << 30;
      if (aRank != bRank) return aRank.compareTo(bRank);
      // Stable tie-break fallback: heavier score wins, then rating.
      final aScore = a.score ?? 0.0;
      final bScore = b.score ?? 0.0;
      if (bScore != aScore) return bScore.compareTo(aScore);
      return (b.rating ?? 0).compareTo(a.rating ?? 0);
    });
  } else {
    enrichedPlayers.sort((a, b) {
      final aScore = a.score ?? 0.0;
      final bScore = b.score ?? 0.0;
      if (bScore != aScore) return bScore.compareTo(aScore);

      final aBuch = buchholzByKey[_canonicalName(a.name)] ?? 0.0;
      final bBuch = buchholzByKey[_canonicalName(b.name)] ?? 0.0;
      if (bBuch != aBuch) return bBuch.compareTo(aBuch);

      return (b.rating ?? 0).compareTo(a.rating ?? 0);
    });
  }

  return enrichedPlayers
      .map((player) => PlayerStandingModel.fromPlayer(player))
      .toList();
}

/// Returns the complete player set visible in [gamesTourModels], while keeping
/// the tournament roster as the authoritative source for standings fields.
///
/// Upstream broadcasts can provide a *partial* `tours.players` array. The old
/// fallback only read players from games when that array was entirely empty,
/// so teams present in games but absent from a non-empty partial roster had no
/// player standings and therefore no team-scorecard chips.
List<TournamentPlayer> mergeTournamentRosterWithGamePlayers({
  required List<TournamentPlayer> tournamentPlayers,
  required List<GamesTourModel> gamesTourModels,
}) {
  final merged = <TournamentPlayer>[];
  final indexByFideId = <int, int>{};
  final indexByNameAndTeam = <String, int>{};

  String nameAndTeamKey(String name, String? team) =>
      '${_canonicalName(name)}|${_normalizeTeam(team)}';

  void indexPlayer(int index, {TournamentPlayer? previous}) {
    if (previous != null) {
      final previousFideId = previous.fideId;
      if (previousFideId != null && indexByFideId[previousFideId] == index) {
        indexByFideId.remove(previousFideId);
      }
      final previousKey = nameAndTeamKey(previous.name, previous.team);
      if (indexByNameAndTeam[previousKey] == index) {
        indexByNameAndTeam.remove(previousKey);
      }
    }
    final player = merged[index];
    final fideId = player.fideId;
    if (fideId != null && fideId > 0) {
      indexByFideId[fideId] = index;
    }
    final name = _canonicalName(player.name);
    if (name.isNotEmpty) {
      indexByNameAndTeam[nameAndTeamKey(player.name, player.team)] = index;
    }
  }

  int? findPlayer({
    required String name,
    required int? fideId,
    required String? team,
  }) {
    final validFideId = _positive(fideId);
    final hasFideId = validFideId != null;
    if (validFideId != null) {
      final byId = indexByFideId[validFideId];
      if (byId != null) return byId;
    }

    final exact = indexByNameAndTeam[nameAndTeamKey(name, team)];
    if (exact != null) {
      final candidateFideId = merged[exact].fideId;
      // A name/team match may enrich a roster row that lacks an ID, but two
      // different positive FIDE IDs must remain two distinct people.
      if (!hasFideId || candidateFideId == null || candidateFideId <= 0) {
        return exact;
      }
    }

    // A roster entry can know the player but omit the team. A game card with
    // the same normalized name is then allowed to fill that missing team.
    if (_normalizeTeam(team).isNotEmpty) {
      final noTeam = indexByNameAndTeam[nameAndTeamKey(name, null)];
      if (noTeam != null) {
        final candidateFideId = merged[noTeam].fideId;
        if (!hasFideId || candidateFideId == null || candidateFideId <= 0) {
          return noTeam;
        }
      }
    }
    return null;
  }

  for (final player in tournamentPlayers) {
    if (_canonicalName(player.name).isEmpty) continue;
    final existing = findPlayer(
      name: player.name,
      fideId: player.fideId,
      team: player.team,
    );
    if (existing != null) continue;
    merged.add(player);
    indexPlayer(merged.length - 1);
  }

  for (final game in gamesTourModels) {
    for (final card in [game.whitePlayer, game.blackPlayer]) {
      if (_canonicalName(card.name).isEmpty) continue;
      final existingIndex = findPlayer(
        name: card.name,
        fideId: card.fideId,
        team: card.team,
      );

      if (existingIndex == null) {
        merged.add(
          TournamentPlayer(
            name: card.name,
            federation: _nonEmpty(card.federation),
            title: _nonEmpty(card.title),
            fideId: card.fideId,
            rating: _positive(card.rating),
            played: 0,
            team: _nonEmpty(card.team)?.trim(),
          ),
        );
        indexPlayer(merged.length - 1);
        continue;
      }

      final existing = merged[existingIndex];
      final enriched = existing.copyWith(
        federation:
            _nonEmpty(existing.federation) ?? _nonEmpty(card.federation),
        title: _nonEmpty(existing.title) ?? _nonEmpty(card.title),
        fideId: _positive(existing.fideId) ?? card.fideId,
        rating: _positive(existing.rating) ?? _positive(card.rating),
        // Team standings are computed from game-card team labels, so game
        // membership wins over a missing/stale roster label. The roster stays
        // authoritative for official score/rank/performance fields.
        team: _nonEmpty(card.team)?.trim() ?? _nonEmpty(existing.team),
      );
      merged[existingIndex] = enriched;
      indexPlayer(existingIndex, previous: existing);
    }
  }

  return merged;
}

Future<Map<int, _FideEloRow>> _fetchFideEloBatch(
  SupabaseClient supabase,
  List<int> fideIds,
) async {
  if (fideIds.isEmpty) return const {};

  // One giant `in.(…)` request is a known failure mode on release/AOT builds:
  // long URLs can stall the HTTP client with no error, which left the Standings
  // tab on its skeleton forever (debug often "worked" because of different
  // timing and smaller warm caches). Chunk + timeout so standings always settle.
  try {
    return await _fetchFideEloBatchChunked(
      supabase,
      fideIds,
    ).timeout(kStandingsFideEloFetchTimeout);
  } catch (e) {
    debugPrint('Error fetching FIDE Elo batch: $e');
    return const {};
  }
}

Future<Map<int, _FideEloRow>> _fetchFideEloBatchChunked(
  SupabaseClient supabase,
  List<int> fideIds,
) async {
  final map = <int, _FideEloRow>{};
  final unique = fideIds.toSet().toList(growable: false);

  for (var i = 0; i < unique.length; i += kStandingsFideEloInFilterChunkSize) {
    final end = math.min(i + kStandingsFideEloInFilterChunkSize, unique.length);
    final chunk = unique.sublist(i, end);
    final rows = await supabase
        .from('chess_players')
        .select(
          'fideid, rating, rapid_rating, blitz_rating, k, rapid_k, blitz_k',
        )
        .inFilter('fideid', chunk);

    for (final row in rows as List) {
      final raw = Map<String, dynamic>.from(row as Map);
      final id = _readJsonInt(raw['fideid']);
      if (id == null || id <= 0) continue;
      map[id] = _FideEloRow(
        standard: _readJsonInt(raw['rating']),
        rapid: _readJsonInt(raw['rapid_rating']),
        blitz: _readJsonInt(raw['blitz_rating']),
        standardK: _readJsonInt(raw['k']),
        rapidK: _readJsonInt(raw['rapid_k']),
        blitzK: _readJsonInt(raw['blitz_k']),
      );
    }
  }

  return map;
}

int? _readJsonInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}

/// Normalizes a player's name into a canonical form so that "Magnus Carlsen"
/// and "Carlsen Magnus" collapse to the same key.
String _canonicalName(String name) {
  final normalized = _normalizeName(name);
  if (normalized.isEmpty) return normalized;

  final parts = normalized.split(' ');
  if (parts.length == 2) {
    final reversed = '${parts[1]} ${parts[0]}';
    return normalized.compareTo(reversed) <= 0 ? normalized : reversed;
  }
  return normalized;
}

String _normalizeName(String name) {
  return name
      .toLowerCase()
      .replaceAll(',', '')
      .trim()
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .join(' ');
}

String _normalizeTeam(String? team) =>
    team?.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ') ?? '';

String? _nonEmpty(String? value) =>
    (value != null && value.trim().isNotEmpty) ? value : null;

int? _positive(int? value) => (value != null && value > 0) ? value : null;

double? _extractRatingFromPGN(String? pgn, bool isWhite) {
  if (pgn == null || pgn.isEmpty) return null;

  final patterns =
      isWhite
          ? [
            RegExp(r'\[WhiteElo "(\d+(?:\.\d+)?)"\]'),
            RegExp(r'\[WhiteElo (\d+(?:\.\d+)?)\]'),
            RegExp(r'WhiteElo\s+(\d+(?:\.\d+)?)'),
          ]
          : [
            RegExp(r'\[BlackElo "(\d+(?:\.\d+)?)"\]'),
            RegExp(r'\[BlackElo (\d+(?:\.\d+)?)\]'),
            RegExp(r'BlackElo\s+(\d+(?:\.\d+)?)'),
          ];

  for (final pattern in patterns) {
    final match = pattern.firstMatch(pgn);
    if (match != null && match.group(1) != null) {
      final rating = double.tryParse(match.group(1)!);
      if (rating != null && rating > 0) {
        return rating;
      }
    }
  }
  return null;
}

double? _getPlayerRating(
  GamesTourModel game, {
  required PlayerCard playerCard,
  required bool isWhite,
}) {
  if (playerCard.rating > 0) {
    return playerCard.rating.toDouble();
  }

  final pgnRating = _extractRatingFromPGN(game.pgn, isWhite);
  if (pgnRating != null && pgnRating > 0) {
    return pgnRating;
  }

  return null;
}

// Heuristic K-factor fallback used only when FIDE's per-time-control K is
// unavailable. FIDE's authoritative K (sticky 2400 → 10, U18 < 2300 → 40,
// default 20) lives in `chess_players.{k,rapid_k,blitz_k}` and must be
// preferred; see [_calculateFideRatingChange].
int _heuristicKFactor(double rating, {String? title, String? timeControl}) {
  final tc = timeControl?.toLowerCase();
  if (tc == 'rapid' || tc == 'blitz') {
    return 20;
  }

  if (rating >= 2400) {
    return 10;
  }

  if (title != null) {
    final t = title.toUpperCase();
    if (t == 'GM' || t == 'IM') {
      return 10;
    }
  }

  return 20;
}

double _calculateFideRatingChange(
  double playerRating,
  double opponentRating,
  GameStatus gameStatus,
  bool isWhite, {
  String? title,
  String? timeControl,
  int? fideK,
}) {
  double actualScore;

  switch (gameStatus) {
    case GameStatus.whiteWins:
      actualScore = isWhite ? 1.0 : 0.0;
      break;
    case GameStatus.blackWins:
      actualScore = isWhite ? 0.0 : 1.0;
      break;
    case GameStatus.draw:
      actualScore = 0.5;
      break;
    default:
      return 0.0;
  }

  final ratingDiff = (opponentRating - playerRating).clamp(-400.0, 400.0);
  final expectedScore = 1 / (1 + math.pow(10, ratingDiff / 400.0));
  final kFactor =
      fideK ??
      _heuristicKFactor(playerRating, title: title, timeControl: timeControl);
  return kFactor * (actualScore - expectedScore);
}

/// One player's FIDE per-time-control ratings + K-factors, as stored in
/// `chess_players`. Source of truth for Elo change calculations.
class _FideEloRow {
  const _FideEloRow({
    this.standard,
    this.rapid,
    this.blitz,
    this.standardK,
    this.rapidK,
    this.blitzK,
  });

  final int? standard;
  final int? rapid;
  final int? blitz;
  final int? standardK;
  final int? rapidK;
  final int? blitzK;

  int? getRating(String timeControl) {
    final tc = timeControl.toLowerCase();
    final raw = switch (tc) {
      'standard' || 'classical' => standard,
      'rapid' => rapid,
      'blitz' => blitz,
      _ => standard,
    };
    if (raw == null || raw <= 0) return null;
    return raw;
  }

  int? getK(String timeControl) {
    final tc = timeControl.toLowerCase();
    final raw = switch (tc) {
      'standard' || 'classical' => standardK,
      'rapid' => rapidK,
      'blitz' => blitzK,
      _ => standardK,
    };
    if (raw == null || raw <= 0) return null;
    return raw;
  }
}

class _PlayerGameRef {
  _PlayerGameRef({
    required this.key,
    required this.game,
    required this.playerCard,
    required this.isWhite,
  });

  final String key;
  final GamesTourModel game;
  final PlayerCard playerCard;
  final bool isWhite;
}

Iterable<_PlayerGameRef> _expandGameRefs(GamesTourModel game) {
  final whiteRef = _PlayerGameRef(
    key: _canonicalGameKey(game.whitePlayer.name),
    game: game,
    playerCard: game.whitePlayer,
    isWhite: true,
  );

  final blackRef = _PlayerGameRef(
    key: _canonicalGameKey(game.blackPlayer.name),
    game: game,
    playerCard: game.blackPlayer,
    isWhite: false,
  );

  return <_PlayerGameRef>[whiteRef, blackRef];
}

String _canonicalGameKey(String name) {
  final normalized = name
      .toLowerCase()
      .replaceAll(',', '')
      .trim()
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .join(' ');

  if (normalized.isEmpty) return normalized;

  final parts = normalized.split(' ');
  if (parts.length == 2) {
    final reversed = '${parts[1]} ${parts[0]}';
    return normalized.compareTo(reversed) <= 0 ? normalized : reversed;
  }
  return normalized;
}
