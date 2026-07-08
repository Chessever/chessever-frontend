import 'package:chessever2/screens/chessboard/provider/chess_board_screen_provider_new.dart';
import 'package:chessever2/screens/player_profile/player_profile_data_source.dart';
import 'package:chessever2/screens/standings/player_standing_model.dart';
import 'package:chessever2/screens/standings/score_card_screen.dart';
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
