import 'package:chessever2/repository/local_storage/favorite/favourate_standings_player_services.dart';
import 'package:chessever2/repository/supabase/tour/tour.dart';
import 'package:chessever2/screens/standings/player_standing_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_screen_provider.dart';
import 'package:chessever2/screens/group_event/model/tour_detail_view_model.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_mode_provider.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_screen_provider.dart';
import 'package:chessever2/utils/broadcast_custom_scoring.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Provides player standings for the tournament detail "Players" tab.
/// Uses [AutoDisposeAsyncNotifier] so the heavy computation only runs when needed
/// and automatically refreshes when any dependency changes.
final playerTourScreenProvider =
    AutoDisposeAsyncNotifierProvider<
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
    final gamesTourAsync = ref.watch(gamesTourScreenProvider);

    if (selectedBroadcast == null ||
        selectedBroadcast.id.isEmpty ||
        tourDetailAsync.isLoading ||
        tourDetailAsync.hasError ||
        gamesTourAsync.isLoading ||
        gamesTourAsync.hasError) {
      return const [];
    }

    final aboutTourModel = tourDetailAsync.value?.aboutTourModel;
    if (aboutTourModel == null || aboutTourModel.id.isEmpty) {
      return const [];
    }

    final tourDetail = tourDetailAsync.value!;
    final gamesData = gamesTourAsync.value!;

    return _buildStandings(
      tourDetail: tourDetail,
      gamesData: gamesData,
      tourId: aboutTourModel.id,
    );
  }

  Future<List<PlayerStandingModel>> _buildStandings({
    required TourDetailViewModel tourDetail,
    required GamesScreenModel gamesData,
    required String tourId,
  }) async {
    // Step 1: Collect all players for the active tour
    final selectedTours = tourDetail.tours.where((e) => e.tour.id == tourId);
    var tournamentPlayers = <TournamentPlayer>[];
    for (final tour in selectedTours) {
      tournamentPlayers.addAll(tour.tour.players);
    }

    // Remove duplicates using a composite key (name + fideId + team) to avoid
    // merging similarly named players across different teams.
    final seen = <String>{};
    tournamentPlayers = tournamentPlayers.where((player) {
      final key =
          '${_canonicalName(player.name)}-${player.fideId ?? 0}-${player.team ?? ''}';
      if (seen.contains(key)) return false;
      seen.add(key);
      return true;
    }).toList();

    // Step 2: Index games by normalized player name
    final gamesByPlayerKey = <String, List<_PlayerGameRef>>{};

    for (final game in gamesData.gamesTourModels) {
      for (final ref in _expandGameRefs(game)) {
        if (ref.key.isEmpty) continue;
        gamesByPlayerKey.putIfAbsent(ref.key, () => []).add(ref);
      }
    }

    // Step 3: Enrich player data and compute match results
    final enrichedPlayers = <TournamentPlayer>[];

    for (final player in tournamentPlayers) {
      final key = _canonicalName(player.name);
      final playerGames = gamesByPlayerKey[key] ?? const <_PlayerGameRef>[];
      final referenceCard = playerGames.isNotEmpty
          ? playerGames.first.playerCard
          : null;

      final updatedPlayer = player.copyWith(
        federation: (player.federation?.trim().isNotEmpty ?? false)
            ? player.federation
            : _nonEmpty(referenceCard?.federation) ?? player.federation,
        title: (player.title?.trim().isNotEmpty ?? false)
            ? player.title
            : _nonEmpty(referenceCard?.title) ?? player.title,
        rating: (player.rating != null && player.rating! > 0)
            ? player.rating
            : _positive(referenceCard?.rating) ?? player.rating,
        fideId: (player.fideId != null && player.fideId! > 0)
            ? player.fideId
            : referenceCard?.fideId ?? player.fideId,
      );

      var calculatedScore = 0.0;
      var gamesPlayed = 0;

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
      }

      final resolvedScore = resolveBroadcastStandingScore(
        sourceScore: player.score,
        sourcePlayed: player.played,
        calculatedScore: calculatedScore,
        calculatedPlayed: gamesPlayed,
      );

      enrichedPlayers.add(
        updatedPlayer.copyWith(
          score: resolvedScore.score,
          played: resolvedScore.played,
        ),
      );
    }

    // Step 4: Sort by ABSOLUTE SCORE (not percentage!)
    // Example: 3.5/4 (87.5%) should rank HIGHER than 3/3 (100%) because 3.5 > 3
    enrichedPlayers.sort((a, b) {
      final aScore = a.score ?? 0.0; // Absolute points collected (e.g., 3.5)
      final bScore = b.score ?? 0.0; // Absolute points collected (e.g., 3.0)

      // Primary sort: by absolute score descending (whoever collected MORE points)
      if (bScore != aScore) return bScore.compareTo(aScore);

      // Secondary sort: by rating/ELO descending (higher rated player first when scores equal)
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
