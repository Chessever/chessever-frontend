import 'package:chessever2/screens/tour_detail/games_tour/models/games_app_bar_view_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/knockout_tournament_state_provider.dart';
import 'package:dartchess/dartchess.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final gamesTourContentProvider = AutoDisposeProvider(
  (ref) => _GamesTourContentProvider(ref),
);

class MatchWithComparison {
  final GamesTourModel game;
  final MatchComparison comparison;

  MatchWithComparison({required this.game, required this.comparison});
}

/// The first team in a matchup header is the visual anchor for every board.
/// When that team's player has Black, the board is flipped so the team still
/// occupies the bottom side of board and grid previews.
Side teamOneBottomSide(MatchComparison comparison) => switch (comparison) {
  MatchComparison.sameOrder => Side.white,
  MatchComparison.oppositeOrder => Side.black,
  MatchComparison.different => Side.white,
};

/// Comparison that keeps a selected team on the left (compact cards) / bottom
/// (board previews). White for that team → natural order; Black → swap sides.
/// Shared by games-tab matchup grouping consumers and team score card boards.
MatchComparison matchComparisonForSelectedTeamSide({
  required bool selectedTeamIsWhite,
}) =>
    selectedTeamIsWhite
        ? MatchComparison.sameOrder
        : MatchComparison.oppositeOrder;

/// Player order for compact team-event cards. The matchup header's first team
/// stays on the first/left side even when that player is Black in this game.
({PlayerCard teamOne, PlayerCard teamTwo}) teamOrderedPlayers(
  MatchWithComparison match,
) => switch (match.comparison) {
  MatchComparison.sameOrder => (
    teamOne: match.game.whitePlayer,
    teamTwo: match.game.blackPlayer,
  ),
  MatchComparison.oppositeOrder => (
    teamOne: match.game.blackPlayer,
    teamTwo: match.game.whitePlayer,
  ),
  MatchComparison.different => (
    teamOne: match.game.whitePlayer,
    teamTwo: match.game.blackPlayer,
  ),
};

/// Groups a round's games by unordered team matchup while retaining, per
/// board, whether its actual White/Black order matches the stable header.
/// Compact cards use this comparison to keep Team 1 on the left; board and
/// grid previews use [teamOneBottomSide] to keep Team 1 at the bottom.
/// Lichess names a one-match team round `Team A - Team B`. The Games tab
/// header splits on ` vs `, so we rewrite the hyphen form when player tags
/// are still empty. A Swiss "Round 5" is not a pairing and is left alone.
String? pairingTitleFromRoundName(String name) {
  final trimmed = name.trim();
  if (trimmed.isEmpty) return null;
  final hyphen = trimmed.split(RegExp(r'\s+-\s+'));
  if (hyphen.length == 2 &&
      hyphen[0].trim().isNotEmpty &&
      hyphen[1].trim().isNotEmpty) {
    return '${hyphen[0].trim()} vs ${hyphen[1].trim()}';
  }
  final vs = trimmed.split(RegExp(r'\s+vs\.?\s+', caseSensitive: false));
  if (vs.length == 2 && vs[0].trim().isNotEmpty && vs[1].trim().isNotEmpty) {
    return '${vs[0].trim()} vs ${vs[1].trim()}';
  }
  return null;
}

String? _teamMatchupLabel(String? team) {
  final trimmed = team?.trim();
  if (trimmed == null || trimmed.isEmpty) return null;
  return trimmed;
}

Map<String, List<MatchWithComparison>> groupTeamGamesByMatchup({
  required String selectedRoundId,
  required List<GamesTourModel> games,
  String? fallbackMatchupTitle,
}) {
  final grouped = <String, List<MatchWithComparison>>{};
  final gamesPerRound = _gamesForTeamRound(
    roundId: selectedRoundId,
    games: games,
  );

  for (final game in gamesPerRound) {
    final whiteTeam = _teamMatchupLabel(game.whitePlayer.team);
    final blackTeam = _teamMatchupLabel(game.blackPlayer.team);
    final header =
        (whiteTeam != null && blackTeam != null)
            ? '$whiteTeam vs $blackTeam'
            : (fallbackMatchupTitle ?? '');
    final comparison = _compareAllTeamHeaders(grouped.keys, header);

    if (comparison == MatchComparison.sameOrder) {
      grouped[header]!.add(
        MatchWithComparison(game: game, comparison: comparison),
      );
    } else if (comparison == MatchComparison.oppositeOrder) {
      final existingHeader = grouped.keys.firstWhere(
        (candidate) =>
            _compareTeamHeaders(candidate, header) ==
            MatchComparison.oppositeOrder,
      );
      grouped[existingHeader]!.add(
        MatchWithComparison(game: game, comparison: comparison),
      );
    } else {
      grouped[header] = [
        MatchWithComparison(game: game, comparison: MatchComparison.sameOrder),
      ];
    }
  }
  return grouped;
}

List<GamesTourModel> _gamesForTeamRound({
  required String roundId,
  required List<GamesTourModel> games,
}) {
  final idLower = roundId.toLowerCase();
  if (idLower.startsWith('$kKnockoutStagePrefix-') ||
      idLower.startsWith('knockout-round-')) {
    return List<GamesTourModel>.from(games);
  }
  return games.where((game) => game.roundId == roundId).toList();
}

MatchComparison _compareAllTeamHeaders(
  Iterable<String> headers,
  String candidate,
) {
  var foundOpposite = false;
  for (final header in headers) {
    final comparison = _compareTeamHeaders(header, candidate);
    if (comparison == MatchComparison.sameOrder) return comparison;
    if (comparison == MatchComparison.oppositeOrder) foundOpposite = true;
  }
  return foundOpposite
      ? MatchComparison.oppositeOrder
      : MatchComparison.different;
}

String _normalizeTeamName(String name) => name.trim().toLowerCase();

MatchComparison _compareTeamHeaders(String first, String second) {
  final firstTeams = first.split(' vs ').map(_normalizeTeamName).toList();
  final secondTeams = second.split(' vs ').map(_normalizeTeamName).toList();
  if (firstTeams.length != 2 || secondTeams.length != 2) {
    return MatchComparison.different;
  }
  if (firstTeams[0] == secondTeams[0] && firstTeams[1] == secondTeams[1]) {
    return MatchComparison.sameOrder;
  }
  if (firstTeams[0] == secondTeams[1] && firstTeams[1] == secondTeams[0]) {
    return MatchComparison.oppositeOrder;
  }
  return MatchComparison.different;
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
    String? roundName,
  }) {
    return groupTeamGamesByMatchup(
      selectedRoundId: selectedRoundId,
      games: gamesScreenModel.gamesTourModels,
      fallbackMatchupTitle: pairingTitleFromRoundName(roundName ?? ''),
    );
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
}

enum MatchComparison { sameOrder, oppositeOrder, different }
