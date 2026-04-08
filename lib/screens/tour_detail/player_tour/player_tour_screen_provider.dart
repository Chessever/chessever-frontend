import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:chessever2/repository/local_storage/favorite/favourate_standings_player_services.dart';
import 'package:chessever2/repository/supabase/tour/tour.dart';
import 'package:chessever2/screens/standings/player_standing_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_screen_provider.dart';
import 'package:chessever2/screens/group_event/model/tour_detail_view_model.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_mode_provider.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_screen_provider.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Provides player standings for the tournament detail "Players" tab.
/// Uses [AutoDisposeAsyncNotifier] so the heavy computation only runs when needed
/// and automatically refreshes when any dependency changes.
/// Provides a merged list of games for the tournament, automatically combining
/// games across pagination-purposed categories (e.g. "Boards 1-66" and "Boards 67-126").
/// This ensures components like the ScoreCardScreen have the full context.
final mergedTournamentGamesProvider = AutoDisposeProvider<List<GamesTourModel>>((ref) {
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
        final tourGamesAsync = ref.watch(gamesTourProvider(tourModel.tour.id));
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
});

final playerTourScreenProvider = AutoDisposeAsyncNotifierProvider<
  PlayerTourScreenNotifier,
  List<PlayerStandingModel>
>(PlayerTourScreenNotifier.new);

class PlayerTourScreenNotifier
    extends AutoDisposeAsyncNotifier<List<PlayerStandingModel>> {
  @override
  Future<List<PlayerStandingModel>> build() async {
    // Keep provider alive while the page is visible to avoid eager disposal
    ref.keepAlive();

    final selectedBroadcast = ref.watch(selectedBroadcastModelProvider);
    final tourDetailAsync = ref.watch(tourDetailScreenProvider);

    if (selectedBroadcast == null ||
        selectedBroadcast.id.isEmpty ||
        tourDetailAsync.isLoading ||
        tourDetailAsync.hasError) {
      return const [];
    }

    final tourDetail = tourDetailAsync.value!;
    final aboutTourModel = tourDetail.aboutTourModel;
    if (aboutTourModel.id.isEmpty) {
      return const [];
    }

    final List<TournamentPlayer> allPlayers;
    final List<GamesTourModel> allGames = ref.watch(mergedTournamentGamesProvider);

    // Detect if this is a pagination-purposed category (e.g. "Boards 1-66")
    if (_isPaginationCategory(aboutTourModel.name)) {
      final baseName = _getCategoryBaseName(aboutTourModel.name);
      final relatedTours =
          tourDetail.tours
              .where(
                (t) =>
                    _isPaginationCategory(t.tour.name) &&
                    _getCategoryBaseName(t.tour.name) == baseName,
              )
              .toList();

      if (relatedTours.length > 1) {
        // Merge players from all related pagination categories
        allPlayers = [];
        for (final tourModel in relatedTours) {
          allPlayers.addAll(tourModel.tour.players);
        }
      } else {
        // Only one such category exists
        allPlayers = List.from(relatedTours.firstOrNull?.tour.players ?? []);
      }
    } else {
      // Normal category - use only the selected tour
      final selectedTours = tourDetail.tours.where(
        (e) => e.tour.id == aboutTourModel.id,
      );
      allPlayers = [];
      for (final tour in selectedTours) {
        allPlayers.addAll(tour.tour.players);
      }
    }

    return _buildStandingsFromData(
      tournamentPlayers: allPlayers,
      gamesTourModels: allGames,
    );
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

  Future<List<PlayerStandingModel>> _buildStandingsFromData({
    required List<TournamentPlayer> tournamentPlayers,
    required List<GamesTourModel> gamesTourModels,
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
          totalRatingDiff += _calculateFideRatingChange(
            playerRating,
            opponentRating,
            status,
            gameRef.isWhite,
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

    // Sort by ABSOLUTE SCORE (not percentage!)
    enrichedPlayers.sort((a, b) {
      final aScore = a.score ?? 0.0;
      final bScore = b.score ?? 0.0;

      if (bScore != aScore) return bScore.compareTo(aScore);
      return (b.rating ?? 0).compareTo(a.rating ?? 0);
    });

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

  int _getKFactor(double rating) {
    if (rating >= 2400) {
      return 10;
    }
    return 20;
  }

  double _calculateFideRatingChange(
    double playerRating,
    double opponentRating,
    GameStatus gameStatus,
    bool isWhite,
  ) {
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
    final kFactor = _getKFactor(playerRating);
    return kFactor * (actualScore - expectedScore);
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
