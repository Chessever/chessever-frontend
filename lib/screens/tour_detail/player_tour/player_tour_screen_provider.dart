import 'dart:math' as math;

import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/repository/supabase/supabase.dart';
import 'package:chessever2/repository/local_storage/favorite/favourate_standings_player_services.dart';
import 'package:chessever2/repository/supabase/tour/tour.dart';
import 'package:chessever2/screens/standings/player_standing_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_screen_provider.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_mode_provider.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_screen_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Provides player standings for the tournament detail "Players" tab.
/// Uses [AutoDisposeAsyncNotifier] so the heavy computation only runs when needed
/// and automatically refreshes when any dependency changes.
/// Provides a merged list of games for the tournament, automatically combining
/// games across pagination-purposed categories (e.g. "Boards 1-66" and "Boards 67-126").
/// This ensures components like the ScoreCardScreen have the full context.
final mergedTournamentGamesProvider = AutoDisposeProvider<List<GamesTourModel>>(
  (ref) {
    final tourDetailAsync = ref.watch(tourDetailScreenProvider);
    final gamesTourAsync = ref.watch(gamesTourScreenProvider);

    if (tourDetailAsync.isLoading ||
        tourDetailAsync.hasError ||
        gamesTourAsync.isLoading ||
        gamesTourAsync.hasError) {
      return const [];
    }

    final tourDetail = tourDetailAsync.value!;
    final aboutTourModel = tourDetail.aboutTourModel;
    if (aboutTourModel.id.isEmpty) {
      return const [];
    }

    bool isPaginationCategory(String name) {
      return RegExp(
        r'Boards?\s+\d+[\-\+]?\d*\+?$',
        caseSensitive: false,
      ).hasMatch(name);
    }

    String getCategoryBaseName(String name) {
      return name
          .replaceAll(
            RegExp(r'\s*Boards?\s+\d+[\-\+]?\d*\+?$', caseSensitive: false),
            '',
          )
          .trim();
    }

    final allGames = <GamesTourModel>[];

    if (isPaginationCategory(aboutTourModel.name)) {
      final baseName = getCategoryBaseName(aboutTourModel.name);
      final relatedTours =
          tourDetail.tours
              .where(
                (t) =>
                    isPaginationCategory(t.tour.name) &&
                    getCategoryBaseName(t.tour.name) == baseName,
              )
              .toList();

      if (relatedTours.length > 1) {
        for (final tourModel in relatedTours) {
          final tourGamesAsync = ref.watch(
            gamesTourProvider(tourModel.tour.id),
          );
          if (tourGamesAsync.hasValue) {
            for (final g in tourGamesAsync.value!) {
              try {
                allGames.add(GamesTourModel.fromGame(g));
              } catch (_) {}
            }
          }
        }
      } else {
        allGames.addAll(gamesTourAsync.value?.gamesTourModels ?? []);
      }
    } else {
      allGames.addAll(gamesTourAsync.value?.gamesTourModels ?? []);
    }

    return allGames;
  },
);

/// Search query for the standings tab
final standingsSearchQueryProvider = StateProvider.autoDispose<String>(
  (ref) => '',
);

List<PlayerStandingModel> assignOverallRanks(
  List<PlayerStandingModel> standings,
) {
  return [
    for (var i = 0; i < standings.length; i++)
      standings[i].copyWith(overallRank: i + 1),
  ];
}

List<PlayerStandingModel> filterStandingsByQuery(
  List<PlayerStandingModel> standings,
  String rawQuery,
) {
  final query = _normalizeStandingSearch(rawQuery);
  if (query.isEmpty) return standings;

  return standings
      .where((player) {
        final searchable = [
          player.name,
          player.title ?? '',
          player.countryCode,
        ].join(' ');
        return _matchesStandingSearch(searchable, query);
      })
      .toList(growable: false);
}

String _normalizeStandingSearch(String value) {
  return value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .trim()
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .join(' ');
}

bool _matchesStandingSearch(String value, String normalizedQuery) {
  final normalizedValue = _normalizeStandingSearch(value);
  if (normalizedValue.isEmpty) return false;
  if (normalizedValue.contains(normalizedQuery)) return true;

  final queryTokens = normalizedQuery.split(' ');
  return queryTokens.every(normalizedValue.contains);
}

String _standingsGamesSignature(AsyncValue<List<Games>> gamesAsync) {
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

final playerTourScreenProvider = AutoDisposeAsyncNotifierProvider<
  PlayerTourScreenNotifier,
  List<PlayerStandingModel>
>(PlayerTourScreenNotifier.new);

class PlayerTourScreenNotifier
    extends AutoDisposeAsyncNotifier<List<PlayerStandingModel>> {
  String? _lastBroadcastId;
  String? _lastTourId;
  List<PlayerStandingModel>? _lastGoodStandings;

  @override
  Future<List<PlayerStandingModel>> build() async {
    // Keep provider alive while the page is visible to avoid eager disposal
    ref.keepAlive();

    // IMPORTANT: build() intentionally does NOT watch
    // `standingsSearchQueryProvider`. The full ranked standings are
    // recomputed only when the tour / games / broadcast change; search
    // filtering is applied cheaply in-widget so typing doesn't re-run the
    // (expensive) FIDE-Elo fetch and enrichment pass on every keystroke.
    final selectedBroadcast = ref.watch(selectedBroadcastModelProvider);

    if (selectedBroadcast == null || selectedBroadcast.id.isEmpty) {
      return const [];
    }

    final tourDetailAsync = ref.watch(tourDetailScreenProvider);
    if (tourDetailAsync.hasError) {
      final last = _lastGoodForBroadcast(selectedBroadcast.id);
      if (last != null) {
        return last;
      }
      Error.throwWithStackTrace(
        tourDetailAsync.error!,
        tourDetailAsync.stackTrace ?? StackTrace.current,
      );
    }

    final tourDetail = tourDetailAsync.valueOrNull;
    if (tourDetail == null) {
      return _lastGoodForBroadcast(selectedBroadcast.id) ?? const [];
    }
    final aboutTourModel = tourDetail.aboutTourModel;
    if (aboutTourModel.id.isEmpty) {
      return _lastGoodFor(
            broadcastId: selectedBroadcast.id,
            tourId: aboutTourModel.id,
          ) ??
          const [];
    }

    // Detect if this is a pagination-purposed category (e.g. "Boards 1-66")
    final List<TourModel> relatedTours;
    if (_isPaginationCategory(aboutTourModel.name)) {
      final baseName = _getCategoryBaseName(aboutTourModel.name);
      relatedTours =
          tourDetail.tours
              .where(
                (t) =>
                    _isPaginationCategory(t.tour.name) &&
                    _getCategoryBaseName(t.tour.name) == baseName,
              )
              .toList();
    } else {
      relatedTours =
          tourDetail.tours
              .where((e) => e.tour.id == aboutTourModel.id)
              .toList();
    }

    // Watch only the part of live games that can change standings. Move/clock
    // ticks should not rebuild this provider, but new games or result changes
    // should update scores gracefully while the list keeps its scroll offset.
    final allGames = _watchStandingsGamesForTours(relatedTours);

    final allPlayers = <TournamentPlayer>[];
    for (final tourModel in relatedTours) {
      allPlayers.addAll(tourModel.tour.players);
    }

    // Trust the server-side standings order only when scope is a single tour
    // that the data hub has flagged as canonically sorted (currently from
    // chess-results.com). Multi-tour pagination categories (e.g. "Boards 1-66"
    // + "Boards 67-126") interleave players from independent standings, so the
    // concatenation is not meaningful — fall back to client-side sort there.
    final useExternalOrder =
        relatedTours.length == 1 &&
        relatedTours.first.tour.usesExternalStandings;

    final builtStandings = await _buildStandingsFromData(
      tournamentPlayers: allPlayers,
      gamesTourModels: allGames,
      useExternalOrder: useExternalOrder,
    );

    if (builtStandings.isEmpty) {
      return _lastGoodFor(
            broadcastId: selectedBroadcast.id,
            tourId: aboutTourModel.id,
          ) ??
          const [];
    }

    // Assign 1-based ranks in unfiltered order. These stay attached to each
    // player so in-widget filter preserves the overall standing position.
    final rankedStandings = assignOverallRanks(builtStandings);
    _rememberGoodStandings(
      broadcastId: selectedBroadcast.id,
      tourId: aboutTourModel.id,
      standings: rankedStandings,
    );
    return rankedStandings;
  }

  List<PlayerStandingModel>? _lastGoodFor({
    required String broadcastId,
    required String tourId,
  }) {
    if (_lastBroadcastId != broadcastId || _lastTourId != tourId) {
      return null;
    }
    return _lastGoodStandings;
  }

  List<PlayerStandingModel>? _lastGoodForBroadcast(String broadcastId) {
    if (_lastBroadcastId != broadcastId) {
      return null;
    }
    return _lastGoodStandings;
  }

  void _rememberGoodStandings({
    required String broadcastId,
    required String tourId,
    required List<PlayerStandingModel> standings,
  }) {
    _lastBroadcastId = broadcastId;
    _lastTourId = tourId;
    _lastGoodStandings = standings;
  }

  List<GamesTourModel> _watchStandingsGamesForTours(
    List<TourModel> relatedTours,
  ) {
    final allGames = <GamesTourModel>[];

    for (final tourModel in relatedTours) {
      final tourId = tourModel.tour.id;
      ref.watch(gamesTourProvider(tourId).select(_standingsGamesSignature));
      final games = ref.read(gamesTourProvider(tourId)).valueOrNull;
      if (games == null || games.isEmpty) continue;

      for (final game in games) {
        try {
          allGames.add(GamesTourModel.fromGame(game));
        } catch (_) {
          // Skip malformed rows to keep standings resilient during live ingest.
        }
      }
    }

    return allGames;
  }

  /// Identifies categories like "Boards 1-66", "Boards 67-126", "Boards 252+"
  bool _isPaginationCategory(String name) {
    return RegExp(
      r'Boards?\s+\d+[\-\+]?\d*\+?$',
      caseSensitive: false,
    ).hasMatch(name);
  }

  /// Extracts the base name before the pagination suffix (e.g. "Open | Boards 1-50" -> "Open |")
  String _getCategoryBaseName(String name) {
    return name
        .replaceAll(
          RegExp(r'\s*Boards?\s+\d+[\-\+]?\d*\+?$', caseSensitive: false),
          '',
        )
        .trim();
  }

  Future<Map<int, _FideEloRow>> _fetchFideEloBatch(List<int> fideIds) async {
    if (fideIds.isEmpty) return const {};
    try {
      final supabase = ref.read(supabaseProvider);
      final rows = await supabase
          .from('chess_players')
          .select(
            'fideid, rating, rapid_rating, blitz_rating, k, rapid_k, blitz_k',
          )
          .inFilter('fideid', fideIds);

      final map = <int, _FideEloRow>{};
      for (final row in rows) {
        final id = row['fideid'];
        if (id is! int) continue;
        map[id] = _FideEloRow(
          standard: row['rating'] as int?,
          rapid: row['rapid_rating'] as int?,
          blitz: row['blitz_rating'] as int?,
          standardK: row['k'] as int?,
          rapidK: row['rapid_k'] as int?,
          blitzK: row['blitz_k'] as int?,
        );
      }
      return map;
    } catch (e) {
      debugPrint('Error fetching FIDE Elo batch: $e');
      return const {};
    }
  }

  Future<List<PlayerStandingModel>> _buildStandingsFromData({
    required List<TournamentPlayer> tournamentPlayers,
    required List<GamesTourModel> gamesTourModels,
    bool useExternalOrder = false,
  }) async {
    var players = List<TournamentPlayer>.from(tournamentPlayers);

    // Remove duplicates using a composite key (name + fideId + team) to avoid
    // merging similarly named players across different teams.
    final seen = <String>{};
    players =
        players.where((player) {
          final key =
              '${_canonicalName(player.name)}-${player.fideId ?? 0}-${player.team ?? ''}';
          if (seen.contains(key)) return false;
          seen.add(key);
          return true;
        }).toList();

    // Fallback: if tour has no player roster but has games, extract players
    // from the games themselves. This handles tournaments where the upstream
    // source didn't populate the players array (e.g. knockout stages).
    if (players.isEmpty && gamesTourModels.isNotEmpty) {
      final seenKeys = <String>{};
      for (final game in gamesTourModels) {
        for (final card in [game.whitePlayer, game.blackPlayer]) {
          final key = _canonicalName(card.name);
          if (key.isEmpty || seenKeys.contains(key)) continue;
          seenKeys.add(key);
          players.add(
            TournamentPlayer(
              name: card.name,
              federation: card.federation.isNotEmpty ? card.federation : null,
              title: card.title.isNotEmpty ? card.title : null,
              fideId: card.fideId,
              rating: card.rating > 0 ? card.rating : null,
              played: 0,
            ),
          );
        }
      }
    }

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
    final fideEloByFideId = await _fetchFideEloBatch(fideIds.toList());

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
            gameRef.isWhite
                ? gameRef.game.blackPlayer
                : gameRef.game.whitePlayer;
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

      enrichedPlayers.add(
        updatedPlayer.copyWith(
          score: calculatedScore,
          played: gamesPlayed,
          ratingDiff:
              updatedPlayer.ratingDiff ??
              (hasCalculatedRatingDiff ? totalRatingDiff.round() : null),
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
            gameRef.isWhite
                ? gameRef.game.blackPlayer
                : gameRef.game.whitePlayer;
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

    // Sort by absolute score, then Buchholz Cut-1, then current rating —
    // unless the caller has signalled that the server already supplied a
    // canonical order (e.g. chess-results.com tiebreaks). In that case we
    // preserve the input order so the displayed ranking matches the official
    // tournament standings, while keeping all the per-player enrichment
    // (score, Buchholz for display, rating diff, etc.).
    if (!useExternalOrder) {
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

/// Version counter to force refreshes when favorites change
final favoritesVersionProvider = StateProvider<int>((ref) => 0);

final tournamentFavoritePlayersProvider =
    FutureProvider<List<PlayerStandingModel>>((ref) async {
      // Watch the version to make this provider reactive to favorite changes
      ref.watch(favoritesVersionProvider);

      final favoritesService = ref.read(favoriteStandingsPlayerService);
      return favoritesService.getFavoritePlayers();
    });
