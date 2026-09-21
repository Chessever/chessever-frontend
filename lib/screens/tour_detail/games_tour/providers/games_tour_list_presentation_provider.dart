import 'package:chessever2/screens/tour_detail/games_tour/models/games_app_bar_view_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_app_bar_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_list_view_mode_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_display_rounds.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_flattened_layout.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_grouped_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_screen_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/match_expansion_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/round_expansion_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/tour_round_start_times_provider.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_screen_provider.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class GamesTourListPresentation {
  const GamesTourListPresentation({
    required this.displayRounds,
    required this.gamesByRound,
    required this.layout,
  });

  final List<GamesAppBarModel> displayRounds;
  final Map<String, List<GamesTourModel>> gamesByRound;
  final GamesTourFlattenedLayout layout;
}

/// Canonical presentation snapshot for the regular tournament Games list.
///
/// The widget paints [layout], while dropdown and scroll providers query the
/// same flattened entries. This removes all parallel header/game counting.
final gamesTourListPresentationProvider =
    Provider.autoDispose<GamesTourListPresentation>((ref) {
      final grouped = ref.watch(gamesTourGroupedProvider);
      final appBar = ref.watch(gamesAppBarProvider).valueOrNull;
      final screen = ref.watch(gamesTourScreenProvider).valueOrNull;
      final viewMode = ref.watch(gamesListViewModeProvider);
      final isSearchMode = screen?.isSearchMode ?? false;
      // Knockout matchup cards collapse several source rounds into one stage;
      // order them by the source round start time so the latest matchup is
      // top-most. Only knockout events collapse, so skip the fetch otherwise.
      final tourDetail = ref.watch(tourDetailScreenProvider).valueOrNull;
      final tourId = tourDetail?.aboutTourModel.id;
      final roundStartTimesById =
          grouped.isKnockoutTournament && tourId != null
              ? (ref.watch(tourRoundStartTimesProvider(tourId)).valueOrNull ??
                  const <String, DateTime?>{})
              : const <String, DateTime?>{};
      final displayRounds = selectGamesTourDisplayRounds(
        rounds: grouped.rounds,
        effectiveRounds: grouped.filteredRounds,
        gamesByRound: grouped.gamesByRound,
        upcomingPairingRoundIds: grouped.upcomingPairingRoundIds,
        isSearchMode: isSearchMode,
        isMultiStageKnockout: grouped.isMultiStageKnockout,
        selectedRoundId: appBar?.selectedId,
        userSelected: appBar?.userSelectedId ?? false,
      );
      final layout = buildGamesTourFlattenedLayout(
        rounds: displayRounds,
        gamesByRound: grouped.gamesByRound,
        mode: viewMode,
        matchExpansionState:
            isSearchMode
                ? const <String, bool>{}
                : ref.watch(matchExpansionProvider),
        roundExpansionState:
            isSearchMode
                ? const <String, bool>{}
                : ref.watch(roundExpansionProvider),
        isKnockoutTournament: grouped.isKnockoutTournament,
        displayMode: screen?.gameDisplayMode ?? GameDisplayMode.all,
        isSearchMode: isSearchMode,
        matchFormatHeader: grouped.matchFormatHeader,
        roundStartTimesById: roundStartTimesById,
        sourceStandingsByTourId: {
          for (final tourModel in tourDetail?.tours ?? const [])
            tourModel.tour.id: tourModel.tour.players,
        },
      );

      return GamesTourListPresentation(
        displayRounds: displayRounds,
        gamesByRound: grouped.gamesByRound,
        layout: layout,
      );
    });
