import 'package:chessever2/screens/tour_detail/games_tour/models/games_app_bar_view_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/knockout_tournament_state_provider.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final gamesTourContentProvider = AutoDisposeProvider(
  (ref) => _GamesTourContentProvider(ref),
);

class MatchWithComparison {
  final GamesTourModel game;
  final MatchComparison comparison;

  MatchWithComparison({required this.game, required this.comparison});
}

class _GamesTourContentProvider {
  _GamesTourContentProvider(this.ref);

  final Ref ref;

  GamesScreenModel getOrderedGamesForChessBoard({
    required List<GamesAppBarModel> rounds,
    required GamesScreenModel gamesScreenModel,
  }) {
    final orderedGamesForChessBoard = <GamesTourModel>[];
    for (var a = 0; a < rounds.length; a++) {
      final allGamesForRound = _gamesForRound(
        roundId: rounds[a].id,
        gamesScreenModel: gamesScreenModel,
      );
      orderedGamesForChessBoard.addAll(allGamesForRound);
    }

    return GamesScreenModel(
      gamesTourModels: orderedGamesForChessBoard,
      pinnedGamedIs: gamesScreenModel.pinnedGamedIs,
    );
  }

  Map<String, List<MatchWithComparison>> getGroupHeader({
    required String selectedRoundId,
    required GamesScreenModel gamesScreenModel,
  }) {
    final grouped = <String, List<MatchWithComparison>>{};

    final gamesPerRound = _gamesForRound(
      roundId: selectedRoundId,
      gamesScreenModel: gamesScreenModel,
    );

    for (var game in gamesPerRound) {
      final whiteTeam = game.whitePlayer.team ?? game.whitePlayer.countryCode;
      final blackTeam = game.blackPlayer.team ?? game.blackPlayer.countryCode;
      final header = '$whiteTeam vs $blackTeam';

      // Check existing headers
      final comparison = _compareAllWithOne(grouped.keys.toList(), header);

      if (comparison == MatchComparison.sameOrder) {
        // Same header, add to same list
        grouped[header]!.add(
          MatchWithComparison(game: game, comparison: comparison),
        );
      } else if (comparison == MatchComparison.oppositeOrder) {
        // Opposite header exists, find it and add there
        final existingHeader = grouped.keys.firstWhere(
          (h) =>
              _compareMatchHeaders(h, header) == MatchComparison.oppositeOrder,
        );
        grouped[existingHeader]!.add(
          MatchWithComparison(game: game, comparison: comparison),
        );
      } else {
        // No matching header, create a new one
        grouped[header] = [
          MatchWithComparison(
            game: game,
            comparison: MatchComparison.sameOrder,
          ),
        ];
      }
    }
    return grouped;
  }

  List<GamesTourModel> _gamesForRound({
    required String roundId,
    required GamesScreenModel gamesScreenModel,
  }) {
    final idLower = roundId.toLowerCase();
    if (idLower.startsWith('$kKnockoutStagePrefix-') ||
        idLower.startsWith('knockout-round-')) {
      return List<GamesTourModel>.from(gamesScreenModel.gamesTourModels);
    }

    return gamesScreenModel.gamesTourModels
        .where((game) => game.roundId == roundId)
        .toList();
  }

  MatchComparison _compareAllWithOne(List<String> headers, String compare) {
    var allHeaders = <MatchComparison>[];

    for (final header in headers) {
      final comparison = _compareMatchHeaders(header, compare);
      allHeaders.add(comparison);
    }
    if (allHeaders.contains(MatchComparison.sameOrder)) {
      return MatchComparison.sameOrder;
    } else if (allHeaders.contains(MatchComparison.oppositeOrder)) {
      return MatchComparison.oppositeOrder;
    } else {
      return MatchComparison.different;
    }
  }

  /// Normalize team names for consistent comparison
  String _normalizeTeamName(String name) {
    return name.trim().toLowerCase();
  }

  MatchComparison _compareMatchHeaders(String h1, String h2) {
    final split1 = h1.split(' vs ').map((e) => e.trim()).toList();
    final split2 = h2.split(' vs ').map((e) => e.trim()).toList();

    // Normalize team names for case-insensitive comparison
    final team1A = _normalizeTeamName(split1[0]);
    final team1B = _normalizeTeamName(split1[1]);
    final team2A = _normalizeTeamName(split2[0]);
    final team2B = _normalizeTeamName(split2[1]);

    if (team1A == team2A && team1B == team2B) {
      return MatchComparison.sameOrder;
    } else if (team1A == team2B && team1B == team2A) {
      return MatchComparison.oppositeOrder;
    } else {
      return MatchComparison.different;
    }
  }
}

enum MatchComparison { sameOrder, oppositeOrder, different }
