import 'package:chessever2/screens/chessboard/provider/chess_board_screen_provider_new.dart';
import 'package:chessever2/screens/player_profile/player_profile_data_source.dart';
import 'package:chessever2/screens/standings/player_standing_model.dart';
import 'package:chessever2/screens/standings/score_card_screen.dart';
import 'package:chessever2/screens/standings/team_standing_model.dart';
import 'package:chessever2/screens/tour_detail/team_tour/team_tour_screen_provider.dart';
import 'package:flutter/widgets.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Opens a team player's individual score card within the current event
/// (same flow the individual standings row uses).
void openPlayerScoreCard(
  BuildContext context,
  WidgetRef ref,
  PlayerStandingModel player,
) {
  ref.read(selectedPlayerProvider.notifier).state = player;
  // Tournament games come from gamesTourScreenProvider — clear any prior context.
  ref.read(scoreCardGamesContextProvider.notifier).state = null;
  ref.read(scoreCardPlayerProfileDataSourceProvider.notifier).state =
      PlayerProfileDataSource.supabase;
  ref.read(chessboardViewFromProviderNew.notifier).state = ChessboardView.tour;
  Navigator.of(context).pushNamed('/scorecard_screen');
}

/// Opens a team score card by name. Uses a push (not replace) so callers like
/// the Games tab keep their scroll position on pop. Looks up the ranked
/// [TeamStandingModel] when standings are ready; otherwise opens a minimal
/// stub so the screen still loads matches for that team name.
void openTeamScoreCard(
  BuildContext context,
  WidgetRef ref,
  String teamName,
) {
  final trimmed = teamName.trim();
  if (trimmed.isEmpty) return;

  final standings = ref.read(teamStandingsProvider).valueOrNull;
  TeamStandingModel? matched;
  if (standings != null) {
    for (final t in standings) {
      if (t.teamName == trimmed) {
        matched = t;
        break;
      }
    }
  }

  ref.read(selectedTeamProvider.notifier).state =
      matched ??
      TeamStandingModel(
        teamName: trimmed,
        rank: 0,
        matchPoints: 0,
        gamePoints: 0,
        matchesWon: 0,
        matchesDrawn: 0,
        matchesLost: 0,
        boardsPlayed: 0,
        players: const [],
      );
  Navigator.of(context).pushNamed('/team_scorecard_screen');
}
