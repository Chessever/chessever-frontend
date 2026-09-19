import 'package:chessever2/screens/tour_detail/games_tour/models/games_app_bar_view_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/knockout_tournament_state_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/utils/knockout_match_detector.dart';
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

  // Pin/favorite sorting changes presentation order, never the match's sides.
  // Anchor each pairing to its lowest numbered board (stable id breaks ties).
  final anchors = <String, GamesTourModel>{};
  String matchupKey(GamesTourModel game) {
    final teams = [
      _teamMatchupLabel(game.whitePlayer.team)?.toLowerCase() ?? '',
      _teamMatchupLabel(game.blackPlayer.team)?.toLowerCase() ?? '',
    ]..sort();
    return teams.join('\u0000');
  }

  for (final game in gamesPerRound) {
    final key = matchupKey(game);
    final previous = anchors[key];
    final boardOrder = (game.boardNr ?? 0x7fffffff).compareTo(
      previous?.boardNr ?? 0x7fffffff,
    );
    if (previous == null ||
        boardOrder < 0 ||
        (boardOrder == 0 && game.gameId.compareTo(previous.gameId) < 0)) {
      anchors[key] = game;
    }
  }
  for (final game in gamesPerRound) {
    final anchor = anchors[matchupKey(game)]!;
    final left = _teamMatchupLabel(anchor.whitePlayer.team);
    final right = _teamMatchupLabel(anchor.blackPlayer.team);
    final header =
        left != null && right != null
            ? '$left vs $right'
            : (fallbackMatchupTitle ?? '');
    final comparison =
        left == null ||
                right == null ||
                _teamMatchupLabel(game.whitePlayer.team)?.toLowerCase() ==
                    left.toLowerCase()
            ? MatchComparison.sameOrder
            : MatchComparison.oppositeOrder;
    grouped
        .putIfAbsent(header, () => [])
        .add(MatchWithComparison(game: game, comparison: comparison));
  }
  return grouped;
}

/// Flattens one round's matchup groups into the order this tab renders its
/// cards: every board of team one vs team two, then the next pairing.
List<GamesTourModel> orderedGamesForTeamMatchups(
  Map<String, List<MatchWithComparison>> grouped,
) => <GamesTourModel>[
  for (final gamesForTeam in grouped.values)
    for (final match in gamesForTeam) match.game,
];

/// True when the Games tab would render [games] as team matchup cards: every
/// game carries a team on both sides. Knockout feeds are excluded — their
/// visual order is already match-grouped, so reordering by team pairing could
/// pull a leg out from under its bracket.
bool looksLikeTeamMatchupGames(List<GamesTourModel> games) {
  if (games.length < 2) return false;
  if (KnockoutMatchDetector.isKnockoutMatchFormat(games)) return false;
  for (final game in games) {
    if (_teamMatchupLabel(game.whitePlayer.team) == null ||
        _teamMatchupLabel(game.blackPlayer.team) == null) {
      return false;
    }
  }
  return true;
}

/// Board-switcher order for a team event: per round, matchups in first-seen
/// order, then each pairing's boards. The flat Games-tab sort (round DESC →
/// game DESC → board ASC) interleaves matchups because board numbers restart
/// per pairing, so swiping used to land on the next team's board instead of
/// the adjacent one (Trello #1158).
List<GamesTourModel> orderTeamEventGamesForBoardNavigation(
  List<GamesTourModel> games,
) {
  if (games.length < 2) return games;

  final roundOrder = <String>[];
  final gamesByRound = <String, List<GamesTourModel>>{};
  for (final game in games) {
    gamesByRound
        .putIfAbsent(game.roundId, () {
          roundOrder.add(game.roundId);
          return <GamesTourModel>[];
        })
        .add(game);
  }

  final ordered = <GamesTourModel>[];
  for (final roundId in roundOrder) {
    ordered.addAll(
      orderedGamesForTeamMatchups(
        groupTeamGamesByMatchup(
          selectedRoundId: roundId,
          games: gamesByRound[roundId]!,
        ),
      ),
    );
  }
  return ordered;
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
