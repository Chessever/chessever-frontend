import 'package:chessever2/screens/tour_detail/games_tour/models/games_app_bar_view_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_list_view_mode_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/group_event_match_card.dart';

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_app_bar_provider.dart';
import 'package:chessever2/screens/group_event/widget/tour_loading_widget.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';

class GroupEventGamesTourContentBody extends ConsumerStatefulWidget {
  final GamesScreenModel gamesScreenModel;
  final GamesListViewMode gamesListViewMode;
  final void Function(int)? onReturnFromChessboard;

  const GroupEventGamesTourContentBody({
    super.key,
    required this.gamesScreenModel,
    required this.gamesListViewMode,
    this.onReturnFromChessboard,
  });

  @override
  ConsumerState<GroupEventGamesTourContentBody> createState() =>
      _GroupEventGamesTourContentBodyState();
}

class _GroupEventGamesTourContentBodyState
    extends ConsumerState<GroupEventGamesTourContentBody> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selectedRoundId = ref.watch(
      gamesAppBarProvider.select((v) => v.value?.selectedId),
    );

    final gamesAppBar = ref.watch(gamesAppBarProvider);
    if (gamesAppBar.isLoading || !gamesAppBar.hasValue) {
      return const TourLoadingWidget();
    }
    final rounds = gamesAppBar.value!.gamesAppBarModels;

    final orderedGamesForChessBoard = <GamesTourModel>[];
    for (var a = 0; a < rounds.length; a++) {
      final allGamesForRound =
          widget.gamesScreenModel.gamesTourModels
              .where((game) => game.roundId == rounds[a].id)
              .toList();
      orderedGamesForChessBoard.addAll(allGamesForRound);
    }

    final orderedGamesData = GamesScreenModel(
      gamesTourModels: orderedGamesForChessBoard,
      pinnedGamedIs: widget.gamesScreenModel.pinnedGamedIs,
    );

    return Column(
      children: [
        Expanded(
          child:
              selectedRoundId != null
                  ? Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: 16.sp,
                      vertical: 12.sp,
                    ),
                    child: _buildGroupedGameCardsBuilder(
                      rounds,
                      rounds.firstWhere((r) => r.id == selectedRoundId),
                      orderedGamesData,
                    ),
                  )
                  : const SizedBox.shrink(),
        ),
        if (rounds.isNotEmpty)
          Align(
            alignment: Alignment.bottomRight,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 15),
              child: Container(
                width: MediaQuery.of(context).size.width * 0.5,
                height: 48,
                margin: EdgeInsets.only(right: 16.sp, bottom: 16.sp),
                child: SingleChildScrollView(
                  controller: _scrollController,
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  child: Row(
                    children: List.generate(rounds.length, (index) {
                      final round = rounds[index];
                      final isSelected = round.id == selectedRoundId;

                      String roundNumber = '${index + 1}';
                      final m = RegExp(r'\d+').firstMatch(round.name);
                      if (m != null) roundNumber = m.group(0)!;

                      return GestureDetector(
                        onTap: () {
                          ref.read(gamesAppBarProvider.notifier).select(round);
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          margin: EdgeInsets.only(right: 12.sp),
                          padding: EdgeInsets.symmetric(
                            horizontal: 20.sp,
                            vertical: 12.sp,
                          ),
                          decoration: BoxDecoration(
                            color: kBlack2Color,
                            borderRadius: BorderRadius.circular(8),
                            border:
                                isSelected
                                    ? Border.all(
                                      color: const Color(0xFF404040),
                                      width: 1,
                                    )
                                    : null,
                          ),
                          child: Text(
                            roundNumber,
                            style: AppTypography.textSmMedium.copyWith(
                              color:
                                  isSelected
                                      ? Colors.white
                                      : const Color(0xFF666666),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildGroupedGameCardsBuilder(
    List<GamesAppBarModel> gamesAppBarModels,
    GamesAppBarModel selectedRound,
    GamesScreenModel orderedGamesData,
  ) {
    final grouped = <String, List<GamesTourModel>>{};

    final gamesPerRound =
        widget.gamesScreenModel.gamesTourModels
            .where((game) => game.roundId == selectedRound.id)
            .toList();

    for (var game in gamesPerRound) {
      final whiteTeam = game.whitePlayer.team ?? game.whitePlayer.countryCode;
      final blackTeam = game.blackPlayer.team ?? game.blackPlayer.countryCode;
      final header = '$whiteTeam vs $blackTeam';

      // Check existing headers
      final comparison = _compareAllWithOne(grouped.keys.toList(), header);

      if (comparison == _MatchComparison.sameOrder) {
        // Same header, add to same list
        grouped[header]!.add(game);
      } else if (comparison == _MatchComparison.oppositeOrder) {
        // Opposite header exists, find it and add there
        final existingHeader = grouped.keys.firstWhere(
          (h) =>
              _compareMatchHeaders(h, header) == _MatchComparison.oppositeOrder,
        );
        grouped[existingHeader]!.add(game);
      } else {
        // No matching header, create a new one
        grouped[header] = [game];
      }
    }

    // Build grouped cards
    return ListView.builder(
      itemCount: grouped.length,
      itemBuilder: (context, index) {
        final header = grouped.keys.elementAt(index);
        final gamesForTeam = grouped[header]!;

        return GroupEventMatchCard(
          roundTitle: header,
          games: gamesForTeam,
          gamesData: orderedGamesData,
          gamesListViewMode: widget.gamesListViewMode,
          onReturnFromChessboard: widget.onReturnFromChessboard,
        );
      },
    );
  }
}

enum _MatchComparison { sameOrder, oppositeOrder, different }

_MatchComparison _compareAllWithOne(List<String> headers, String compare) {
  var allHeaders = <_MatchComparison>[];

  for (final header in headers) {
    final comparison = _compareMatchHeaders(header, compare);
    allHeaders.add(comparison);
  }
  if (allHeaders.contains(_MatchComparison.sameOrder)) {
    return _MatchComparison.sameOrder;
  } else if (allHeaders.contains(_MatchComparison.oppositeOrder)) {
    return _MatchComparison.oppositeOrder;
  } else {
    return _MatchComparison.different;
  }
}

_MatchComparison _compareMatchHeaders(String h1, String h2) {
  final split1 = h1.split(' vs ').map((e) => e.trim()).toList();
  final split2 = h2.split(' vs ').map((e) => e.trim()).toList();

  if (split1[0] == split2[0] && split1[1] == split2[1]) {
    return _MatchComparison.sameOrder;
  } else if (split1[0] == split2[1] && split1[1] == split2[0]) {
    return _MatchComparison.oppositeOrder;
  } else {
    return _MatchComparison.different;
  }
}
