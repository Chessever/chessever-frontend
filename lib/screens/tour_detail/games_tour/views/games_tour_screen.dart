import 'dart:async';
import 'package:chessever2/screens/group_event/widget/tour_loading_widget.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_scroll_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/games_tour_content_body.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/chess_board_visibility_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_app_bar_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_screen_provider.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_screen_provider.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_app_bar_view_model.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/svg_asset.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

class GamesTourScreen extends ConsumerStatefulWidget {
  const GamesTourScreen({super.key});

  @override
  ConsumerState<ConsumerStatefulWidget> createState() =>
      _GamesTourScreenState();
}

class _GamesTourScreenState extends ConsumerState<GamesTourScreen> {
  late ItemPositionsListener _itemPositionsListener;

  @override
  void initState() {
    super.initState();
    _itemPositionsListener = ItemPositionsListener.create();
    _itemPositionsListener.itemPositions.addListener(_onItemPositionsChanged);
  }

  void _onItemPositionsChanged() {
    final positions = _itemPositionsListener.itemPositions.value;
    if (positions.isNotEmpty) {
      // Find the top-visible item (round header or game)
      final topItem =
          positions.where((pos) => pos.itemLeadingEdge < 0.5).firstOrNull;
      if (topItem != null) {
        final visibleRoundId = _getRoundIdFromItemIndex(topItem.index);
        if (visibleRoundId != null) {
          _updateDropdownToVisibleRound(visibleRoundId);
        }
      }
    }
  }

  void setupScrollToGameListener() {
    ref.listenManual<int?>(scrollToGameIndexProvider, (_, next) {
      if (next == null) return;

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;

        final games =
            ref.read(gamesTourScreenProvider).valueOrNull?.gamesTourModels;
        if (games == null || next >= games.length) return;

        final game = games[next];
        final roundId = game.roundId;
        final roundGames = games.where((g) => g.roundId == roundId).toList();
        final localIndex = roundGames.indexWhere(
          (g) => g.gameId == game.gameId,
        );
        if (localIndex == -1) return;

        scrollToGame(roundId, localIndex);
      });

      ref.read(scrollToGameIndexProvider.notifier).state = null;
    });
  }

  @override
  void dispose() {
    _itemPositionsListener.itemPositions.removeListener(
      _onItemPositionsChanged,
    );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isChessBoardVisible = ref.watch(chessBoardVisibilityProvider);
    final gamesTourAsync = ref.watch(gamesTourScreenProvider);

    return gamesTourAsync.when(
      data: (data) {
        final aboutTourModel =
            ref.watch(tourDetailScreenProvider).valueOrNull?.aboutTourModel;

        // Add loading check for dependencies before showing empty state
        final tourDetailAsync = ref.watch(tourDetailScreenProvider);
        final gamesAsync =
            aboutTourModel != null
                ? ref.watch(gamesTourProvider(aboutTourModel.id))
                : const AsyncValue.loading();

        // Don't show empty state if we're still loading dependencies
        if (tourDetailAsync.isLoading || gamesAsync.isLoading) {
          return const TourLoadingWidget();
        }

        if (data.gamesTourModels.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SvgPicture.asset(
                  SvgAsset.tournamentIcon,
                  height: 35,
                  width: 35,
                ),
                SizedBox(height: 10),
                Text(
                  'Currently there are no tournaments going!\nCome back later!',
                  style: AppTypography.textMdRegular.copyWith(
                    color: kWhiteColor,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
        }

        // Listener for dropdown selection -> scroll
        ref.listen<AsyncValue<GamesAppBarViewModel>>(gamesAppBarProvider, (
          previous,
          next,
        ) {
          final previousSelected = previous?.valueOrNull?.selectedId;
          final currentSelected = next.valueOrNull?.selectedId;
          final isUserSelected = next.valueOrNull?.userSelectedId ?? false;

          if (currentSelected != null &&
              currentSelected != previousSelected &&
              isUserSelected) {
            debugPrint(
              '🎯 User selected round from dropdown: $currentSelected',
            );
            // Scroll to the selected round
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                scrollToRound(currentSelected);
              }
            });
          }
        });

        return RefreshIndicator(
          onRefresh: () async {},
          color: kWhiteColor70,
          backgroundColor: kDarkGreyColor,
          displacement: 60.h,
          strokeWidth: 3.w,
          child: GamesTourContentBody(
            gamesScreenModel: data,
            isChessBoardVisible: isChessBoardVisible,
          ),
        );
      },
      error: (e, _) {
        return Center(
          child: Text(
            'Error: $e',
            style: AppTypography.textMdRegular.copyWith(color: kWhiteColor),
            textAlign: TextAlign.center,
          ),
        );
      },
      loading: () => const TourLoadingWidget(),
    );
  }
}

extension GamesTourScreenLogic on _GamesTourScreenState {
  Future<void> scrollToGame(String roundId, int gameIndex) async {
    final controller = ref.read(gamesTourScrollProvider);
    final itemIndex = _calculateItemIndex(roundId, gameIndex);
    await controller.scrollTo(
      index: itemIndex,
      duration: const Duration(milliseconds: 300),
    );
  }

  Future<void> scrollToRound(String roundId) async {
    final controller = ref.read(gamesTourScrollProvider);
    final itemIndex = _calculateRoundHeaderIndex(roundId);
    await controller.scrollTo(
      index: itemIndex,
      duration: const Duration(milliseconds: 300),
    );
  }

  int _calculateItemIndex(String roundId, int gameIndex) {
    // Based on reversed rounds: Each round has 1 header + N games
    final rounds =
        ref.read(gamesAppBarProvider).valueOrNull?.gamesAppBarModels ?? [];
    final reversedRounds = rounds.reversed.toList();
    int index = 0;
    for (final round in reversedRounds) {
      if (round.id == roundId) {
        return index + 1 + gameIndex; // Header + games before this one
      }
      final gamesInRound =
          ref
              .read(gamesTourScreenProvider)
              .valueOrNull
              ?.gamesTourModels
              .where((g) => g.roundId == round.id)
              .length ??
          0;
      index += 1 + gamesInRound; // Header + games
    }
    return 0;
  }

  int _calculateRoundHeaderIndex(String roundId) {
    // Based on reversed rounds: Find the header index for the round
    final rounds =
        ref.read(gamesAppBarProvider).valueOrNull?.gamesAppBarModels ?? [];
    final reversedRounds = rounds.reversed.toList();
    int index = 0;
    for (final round in reversedRounds) {
      if (round.id == roundId) {
        return index;
      }
      final gamesInRound =
          ref
              .read(gamesTourScreenProvider)
              .valueOrNull
              ?.gamesTourModels
              .where((g) => g.roundId == round.id)
              .length ??
          0;
      index += 1 + gamesInRound; // Header + games
    }
    return 0;
  }

  String? _getRoundIdFromItemIndex(int itemIndex) {
    // Reverse-engineer the round from item index
    final rounds =
        ref.read(gamesAppBarProvider).valueOrNull?.gamesAppBarModels ?? [];
    final reversedRounds = rounds.reversed.toList();
    int currentIndex = 0;
    for (final round in reversedRounds) {
      if (itemIndex == currentIndex) {
        return round.id; // It's a header
      }
      final gamesInRound =
          ref
              .read(gamesTourScreenProvider)
              .valueOrNull
              ?.gamesTourModels
              .where((g) => g.roundId == round.id)
              .length ??
          0;
      currentIndex += 1 + gamesInRound;
      if (itemIndex < currentIndex) {
        return round.id; // It's a game in this round
      }
    }
    return null;
  }

  void _updateDropdownToVisibleRound(String roundId) {
    final gamesAppBarAsync = ref.read(gamesAppBarProvider);
    final currentSelected = gamesAppBarAsync.valueOrNull?.selectedId;
    if (currentSelected != roundId) {
      final gamesAppBarData = gamesAppBarAsync.valueOrNull;
      if (gamesAppBarData != null) {
        final targetRound =
            gamesAppBarData.gamesAppBarModels
                .where((round) => round.id == roundId)
                .firstOrNull;
        if (targetRound != null) {
          ref.read(gamesAppBarProvider.notifier).selectSilently(targetRound);
        }
      }
    }
  }
}
