import 'dart:async';
import 'package:chessever2/screens/group_event/widget/tour_loading_widget.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_scroll_state_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_visibility_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/games_tour_content_body.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/chess_board_visibility_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_app_bar_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_screen_provider.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_screen_provider.dart';
import 'package:chessever2/screens/group_event/providers/group_event_screen_provider.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_app_bar_view_model.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/svg_asset.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/top_most_visible_item_model.dart';

class GamesTourScreen extends ConsumerStatefulWidget {
  const GamesTourScreen({required this.scrollController, super.key});

  final ScrollController scrollController;

  @override
  ConsumerState<ConsumerStatefulWidget> createState() =>
      _GamesTourScreenState();
}

class _GamesTourScreenState extends ConsumerState<GamesTourScreen> {
  final Map<String, GlobalKey> _headerKeys = {};
  final Map<String, List<GlobalKey>> _gameKeys = {};

  Timer? _visibilityCheckTimer;
  bool _isScrolling = false;
  bool _isInitialized = false;

  bool _isViewSwitching = false;
  bool _isProgrammaticScroll = false;

  @override
  void initState() {
    super.initState();
    setupScrollListener(); // Using extension method
    setupViewSwitchListener(); // Using extension method
    setupScrollToGameListener();
    setupRoundScrollListener(); // Add this new listener

    WidgetsBinding.instance.addPostFrameCallback((_) {
      synchronizeInitialSelection(); // Using extension method
    });
  }

  void setupRoundScrollListener() {
    ref.listenManual<int?>(roundScrollPositionProvider, (_, next) {
      if (next == null) return;

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;

        debugPrint('🎯 Received scroll to index: $next');

        final games =
            ref.read(gamesTourScreenProvider).valueOrNull?.gamesTourModels;
        if (games == null || next >= games.length) {
          debugPrint('❌ Invalid scroll index or no games available');
          return;
        }

        final game = games[next];
        final roundId = game.roundId;

        debugPrint('🎯 Scrolling to round: $roundId at index: $next');

        // First try to scroll to the specific round header
        scrollToRound(roundId);
      });

      // Clear the provider after handling
      ref.read(roundScrollPositionProvider.notifier).state = null;
    });
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
    _visibilityCheckTimer?.cancel();
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

        // FIXED: Better listener for dropdown -> scroll synchronization
        ref.listen<AsyncValue<GamesAppBarViewModel>>(gamesAppBarProvider, (
          previous,
          next,
        ) {
          if (!_isInitialized) return;

          final previousSelected = previous?.valueOrNull?.selectedId;
          final currentSelected = next.valueOrNull?.selectedId;
          final isUserSelected = next.valueOrNull?.userSelectedId ?? false;

          // FIXED: Only scroll when user explicitly selects from dropdown
          if (currentSelected != null &&
              currentSelected != previousSelected &&
              isUserSelected) {
            // This is the key fix

            debugPrint(
              '🎯 User selected round from dropdown: $currentSelected',
            );

            ref.read(scrollStateProvider.notifier).setUserScrolling(false);
            ref.read(scrollStateProvider.notifier).setScrolling(false);
            ref
                .read(scrollStateProvider.notifier)
                .updateSelectedRound(currentSelected);

            // FIXED: Immediate scroll without delay
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                scrollToRound(currentSelected);
              }
            });
          }
        });

        // FIXED: Better listener for scroll -> dropdown synchronization
        ref.listen<String?>(currentVisibleRoundProvider, (previous, next) {
          final gamesAppBarAsync = ref.read(gamesAppBarProvider);
          if (next != null && next != previous && _isInitialized) {
            final currentSelected = gamesAppBarAsync.valueOrNull?.selectedId;
            final scrollState = ref.read(scrollStateProvider);

            // FIXED: Only update dropdown when user is manually scrolling
            if (scrollState.isUserScrolling &&
                !scrollState.isScrolling &&
                currentSelected != next &&
                !_isViewSwitching &&
                !_isProgrammaticScroll) {
              debugPrint('🔄 Updating dropdown due to manual scroll: $next');

              final gamesAppBarData = gamesAppBarAsync.valueOrNull;
              if (gamesAppBarData != null) {
                final targetRound =
                    gamesAppBarData.gamesAppBarModels
                        .where((round) => round.id == next)
                        .firstOrNull;

                if (targetRound != null) {
                  // Use selectSilently to avoid triggering another scroll
                  ref
                      .read(gamesAppBarProvider.notifier)
                      .selectSilently(targetRound);
                }
              }
            }
          }
        });

        return NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            if (notification is ScrollStartNotification &&
                !_isViewSwitching &&
                !_isProgrammaticScroll) {
              _isScrolling = true;
              ref.read(scrollStateProvider.notifier).setUserScrolling(true);
            } else if (notification is ScrollEndNotification &&
                !_isViewSwitching) {
              _isScrolling = false;
              _isProgrammaticScroll = false;
              Future.delayed(const Duration(milliseconds: 50), () {
                if (mounted && !_isViewSwitching) {
                  checkRoundContentVisibility();
                  ref
                      .read(scrollStateProvider.notifier)
                      .setUserScrolling(false);
                }
              });
            }

            return false;
          },
          child: RefreshIndicator(
            onRefresh: handleRefresh,
            color: kWhiteColor70,
            backgroundColor: kDarkGreyColor,
            displacement: 60.h,
            strokeWidth: 3.w,
            child: GamesTourContentBody(
              gamesScreenModel: data,
              isChessBoardVisible: isChessBoardVisible,
              scrollController: widget.scrollController,
              getHeaderKey: getHeaderKey,
              getGameKey: getGameKey,
            ),
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
      loading: () {
        return const TourLoadingWidget();
      },
    );
  }
}

extension GamesTourScreenLogic on _GamesTourScreenState {
  void synchronizeInitialSelection() {
    if (!mounted || _isInitialized) return;

    final gamesAppBarAsync = ref.read(gamesAppBarProvider);
    final gamesTourAsync = ref.read(gamesTourScreenProvider);
    final selectedPlayerName = ref.read(selectedPlayerNameProvider);

    if (!gamesAppBarAsync.hasValue || !gamesTourAsync.hasValue) {
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted && !_isInitialized) synchronizeInitialSelection();
      });
      return;
    }

    final gamesData = gamesTourAsync.valueOrNull;
    final appBarData = gamesAppBarAsync.valueOrNull;

    if (gamesData == null || appBarData == null) {
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted && !_isInitialized) synchronizeInitialSelection();
      });
      return;
    }

    final gamesByRound = <String, List<GamesTourModel>>{};
    for (final game in gamesData.gamesTourModels) {
      gamesByRound.putIfAbsent(game.roundId, () => []).add(game);
    }

    String? targetRoundId;
    int? targetGameIndex;

    if (selectedPlayerName != null) {
      final normalizedPlayerName = selectedPlayerName.toLowerCase().trim();
      for (final roundId in gamesByRound.keys) {
        final roundGames = gamesByRound[roundId] ?? [];
        for (int i = 0; i < roundGames.length; i++) {
          final game = roundGames[i];
          final white = game.whitePlayer.name.toLowerCase().trim();
          final black = game.blackPlayer.name.toLowerCase().trim();
          if (white.contains(normalizedPlayerName) ||
              black.contains(normalizedPlayerName)) {
            targetRoundId = roundId;
            targetGameIndex = i;
            break;
          }
        }
        if (targetRoundId != null) break;
      }
    }

    if (targetRoundId == null) {
      final selectedRoundId = appBarData.selectedId;

      if (selectedRoundId != null &&
          gamesByRound[selectedRoundId]?.isNotEmpty == true) {
        targetRoundId = selectedRoundId;
      } else {
        final rounds = appBarData.gamesAppBarModels;
        final visibleRounds =
            rounds
                .where((round) => (gamesByRound[round.id]?.isNotEmpty ?? false))
                .toList();

        if (visibleRounds.isNotEmpty) {
          final targetRound = visibleRounds.reversed.first;
          targetRoundId = targetRound.id;
          ref.read(gamesAppBarProvider.notifier).selectSilently(targetRound);
        }
      }
    }

    if (targetRoundId != null) {
      _isInitialized = true;

      ref.read(scrollStateProvider.notifier).setInitialScrollPerformed();
      ref.read(scrollStateProvider.notifier).updateSelectedRound(targetRoundId);
      ref.read(scrollStateProvider.notifier).setUserScrolling(false);

      // FIXED: Better timing for initial scroll
      Future.delayed(const Duration(milliseconds: 600), () {
        if (mounted) {
          if (targetGameIndex != null && selectedPlayerName != null) {
            scrollToGame(targetRoundId!, targetGameIndex);
          } else {
            scrollToRound(targetRoundId!);
          }
          ref.read(selectedPlayerNameProvider.notifier).state = null;
        }
      });
    }
  }

  Future<void> scrollToGame(String roundId, int gameIndex) async {
    debugPrint(
      '[GamesTourScreen] scrollToGame called: round=$roundId, game=$gameIndex',
    );
    if (!mounted || _isViewSwitching) return;

    _isProgrammaticScroll = true;

    ref.read(scrollStateProvider.notifier).setScrolling(true);
    ref.read(scrollStateProvider.notifier).setUserScrolling(false);
    ref.read(scrollStateProvider.notifier).updateSelectedRound(roundId);

    try {
      if (!widget.scrollController.hasClients) {
        return;
      }

      final gameKey = getGameKey(roundId, gameIndex);

      bool found = false;
      for (int retry = 0; retry < 30; retry++) {
        await Future.delayed(const Duration(milliseconds: 50));

        if (gameKey.currentContext != null) {
          try {
            // Remove animation - instant scroll
            Scrollable.ensureVisible(
              gameKey.currentContext!,
              alignment: 0.0,
              duration: Duration.zero, // Instant scroll
              alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
            );

            found = true;
            break;
          } catch (e) {
            debugPrint(
              '[GamesTourScreen] Game scroll error on retry $retry: $e',
            );
          }
        } else {
          debugPrint(
            'Game key not found on retry $retry for round $roundId, index $gameIndex',
          );
        }
      }
      if (!found) {
        await scrollToRound(roundId);
      }
    } catch (e) {
      debugPrint('[GamesTourScreen] Game scroll error: $e');
    } finally {
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) {
          ref.read(scrollStateProvider.notifier).setScrolling(false);
          _isProgrammaticScroll = false;
        }
      });
    }
  }

  void setupViewSwitchListener() {
    ref.listenManual(chessBoardVisibilityProvider, (previous, next) {
      if (previous != next) {
        handleViewSwitch();
      }
    });
  }

  void handleViewSwitch() {
    if (!mounted || !widget.scrollController.hasClients) {
      return;
    }

    _isViewSwitching = true;
    final topMostVisibleItem = findTopMostVisibleItem();

    if (topMostVisibleItem == null) {
      _isViewSwitching = false;
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        scrollToTopMostVisibleItemAfterViewSwitch(topMostVisibleItem);
      } else {
        _isViewSwitching = false;
      }
    });
  }

  TopMostVisibleItem? findTopMostVisibleItem() {
    final gamesData = ref.read(gamesTourScreenProvider).valueOrNull;
    if (gamesData == null) return null;

    final screenHeight = MediaQuery.of(context).size.height;
    final topPadding = MediaQuery.of(context).padding.top;
    final appBarHeight = kToolbarHeight;
    final visibleAreaTop = topPadding + appBarHeight;

    final gamesByRound = <String, List<GamesTourModel>>{};
    for (final game in gamesData.gamesTourModels) {
      gamesByRound.putIfAbsent(game.roundId, () => []).add(game);
    }

    final currentScrollOffset =
        widget.scrollController.hasClients
            ? widget.scrollController.offset
            : 0.0;

    final rounds = ref.read(gamesAppBarProvider).value?.gamesAppBarModels ?? [];
    final visibleRounds =
        rounds
            .where((round) => (gamesByRound[round.id]?.isNotEmpty ?? false))
            .toList()
            .reversed
            .toList();

    TopMostVisibleItem? topMostItem;
    double smallestDistanceFromTop = double.infinity;

    for (final round in visibleRounds) {
      final roundId = round.id;
      final roundGames = gamesByRound[roundId] ?? [];

      final headerKey = getHeaderKey(roundId);
      final headerContext = headerKey.currentContext;
      if (headerContext != null) {
        final headerRenderBox = headerContext.findRenderObject() as RenderBox?;
        if (headerRenderBox?.attached == true) {
          final headerPosition = headerRenderBox!.localToGlobal(Offset.zero);
          final headerTop = headerPosition.dy;
          final headerBottom = headerPosition.dy + headerRenderBox.size.height;

          if (headerBottom > visibleAreaTop) {
            final distanceFromTop = (headerTop - visibleAreaTop).abs();

            if (headerTop >= visibleAreaTop - 3 &&
                distanceFromTop < smallestDistanceFromTop) {
              smallestDistanceFromTop = distanceFromTop;
              topMostItem = TopMostVisibleItem(
                type: TopMostItemType.header,
                roundId: roundId,
                gameIndex: null,
                gameId: null,
                scrollOffset: currentScrollOffset,
                relativePosition: headerTop - visibleAreaTop,
              );
            }
          }
        }
      }

      // Check games in this round
      for (int gameIndex = 0; gameIndex < roundGames.length; gameIndex++) {
        final game = roundGames[gameIndex];
        final gameKey = getGameKey(roundId, gameIndex);
        final gameContext = gameKey.currentContext;

        if (gameContext != null) {
          final gameRenderBox = gameContext.findRenderObject() as RenderBox?;
          if (gameRenderBox?.attached == true) {
            final gamePosition = gameRenderBox!.localToGlobal(Offset.zero);
            final gameTop = gamePosition.dy;
            final gameBottom = gamePosition.dy + gameRenderBox.size.height;

            if (gameBottom > visibleAreaTop) {
              final distanceFromTop = (gameTop - visibleAreaTop).abs();

              if (gameTop >= visibleAreaTop - 3 &&
                  distanceFromTop < smallestDistanceFromTop) {
                if (topMostItem?.type == TopMostItemType.header &&
                    distanceFromTop > 3) {
                  continue;
                }

                smallestDistanceFromTop = distanceFromTop;
                topMostItem = TopMostVisibleItem(
                  type: TopMostItemType.game,
                  roundId: roundId,
                  gameIndex: gameIndex,
                  gameId: game.gameId,
                  scrollOffset: currentScrollOffset,
                  relativePosition: gameTop - visibleAreaTop,
                );
              }
            }
          }
        }
      }
    }

    return topMostItem;
  }

  Future<void> scrollToTopMostVisibleItemAfterViewSwitch(
    TopMostVisibleItem item,
  ) async {
    await Future.delayed(const Duration(milliseconds: 400));

    if (!mounted || !widget.scrollController.hasClients) {
      _isViewSwitching = false;
      return;
    }

    try {
      if (item.type == TopMostItemType.game && item.gameIndex != null) {
        await _scrollToGameWithEnhancedPositioning(item);
      } else {
        await _scrollToHeaderWithEnhancedPositioning(item);
      }
    } catch (e) {
      debugPrint('[GamesTourScreen] Error in enhanced scroll: $e');
    } finally {
      _isViewSwitching = false;
    }
  }

  Future<void> _scrollToGameWithEnhancedPositioning(
    TopMostVisibleItem item,
  ) async {
    if (item.gameIndex == null) return;

    final gameKey = getGameKey(item.roundId, item.gameIndex!);
    final desiredRelativePosition = item.relativePosition ?? 0.0;

    final targetOffset = calculateTargetScrollOffsetForGame(item);
    if (targetOffset != null && widget.scrollController.hasClients) {
      final maxOffset = widget.scrollController.position.maxScrollExtent;
      final clampedOffset = targetOffset.clamp(0.0, maxOffset);
      widget.scrollController.jumpTo(clampedOffset);
      await Future.delayed(const Duration(milliseconds: 300));
    }

    bool positionAchieved = false;
    for (int retry = 0; retry < 15; retry++) {
      await Future.delayed(const Duration(milliseconds: 100));

      if (!mounted || !widget.scrollController.hasClients) break;

      if (gameKey.currentContext != null) {
        try {
          final renderBox =
              gameKey.currentContext!.findRenderObject() as RenderBox?;
          if (renderBox?.attached == true) {
            final position = renderBox!.localToGlobal(Offset.zero);
            final topPadding = MediaQuery.of(context).padding.top;
            final appBarHeight = kToolbarHeight;
            final visibleAreaTop = topPadding + appBarHeight;
            final currentRelativePosition = position.dy - visibleAreaTop;

            final adjustment =
                currentRelativePosition - desiredRelativePosition;

            if (adjustment.abs() <= 5) {
              positionAchieved = true;

              break;
            }

            final currentOffset = widget.scrollController.offset;
            final newOffset = currentOffset + adjustment;
            final maxOffset = widget.scrollController.position.maxScrollExtent;
            final clampedOffset = newOffset.clamp(0.0, maxOffset);

            widget.scrollController.jumpTo(clampedOffset);
          }
        } catch (e) {
          debugPrint(
            '[GamesTourScreen] Game positioning error on retry $retry: $e',
          );
        }
      } else {
        debugPrint('Game key not available, retry $retry/15');
      }
    }

    if (!positionAchieved) {
      if (gameKey.currentContext != null) {
        try {
          await Scrollable.ensureVisible(
            gameKey.currentContext!,
            alignment: 0.0,
            duration: Duration.zero,
          );
        } catch (e) {
          debugPrint('Fallback ensureVisible failed: $e');
        }
      }
    }
  }

  Future<void> _scrollToHeaderWithEnhancedPositioning(
    TopMostVisibleItem item,
  ) async {
    final headerKey = getHeaderKey(item.roundId);
    final desiredRelativePosition = item.relativePosition ?? 0.0;

    final targetOffset = calculateTargetScrollOffset(item);
    if (targetOffset != null && widget.scrollController.hasClients) {
      final maxOffset = widget.scrollController.position.maxScrollExtent;
      final clampedOffset = targetOffset.clamp(0.0, maxOffset);
      widget.scrollController.jumpTo(clampedOffset);
      await Future.delayed(const Duration(milliseconds: 200));
    }

    for (int retry = 0; retry < 10; retry++) {
      await Future.delayed(const Duration(milliseconds: 100));

      if (!mounted || !widget.scrollController.hasClients) break;

      if (headerKey.currentContext != null) {
        try {
          final renderBox =
              headerKey.currentContext!.findRenderObject() as RenderBox?;
          if (renderBox?.attached == true) {
            final position = renderBox!.localToGlobal(Offset.zero);
            final topPadding = MediaQuery.of(context).padding.top;
            final appBarHeight = kToolbarHeight;
            final visibleAreaTop = topPadding + appBarHeight;
            final currentRelativePosition = position.dy - visibleAreaTop;

            final adjustment =
                currentRelativePosition - desiredRelativePosition;

            if (adjustment.abs() <= 5) {
              break;
            }

            final currentOffset = widget.scrollController.offset;
            final newOffset = currentOffset + adjustment;
            final maxOffset = widget.scrollController.position.maxScrollExtent;
            final clampedOffset = newOffset.clamp(0.0, maxOffset);

            widget.scrollController.jumpTo(clampedOffset);
          }
        } catch (e) {
          debugPrint('[GamesTourScreen] Header positioning error: $e');
        }
      }
    }
  }

  double? calculateTargetScrollOffset(TopMostVisibleItem item) {
    try {
      final gamesData = ref.read(gamesTourScreenProvider).valueOrNull;
      if (gamesData == null) {
        return null;
      }

      final rounds =
          ref.read(gamesAppBarProvider).value?.gamesAppBarModels ?? [];
      final gamesByRound = <String, List<GamesTourModel>>{};
      for (final game in gamesData.gamesTourModels) {
        gamesByRound.putIfAbsent(game.roundId, () => []).add(game);
      }

      final visibleRounds =
          rounds
              .where((round) => (gamesByRound[round.id]?.isNotEmpty ?? false))
              .toList()
              .reversed
              .toList();

      double calculatedOffset = 0;
      double headerHeight = 50;
      const double headerTopMargin = 16;
      const double headerBottomMargin = 8;
      const double gameSpacing = 12;
      const double contentPadding = 16;
      final isCurrentlyChessBoard = ref.read(chessBoardVisibilityProvider);
      double gameHeight = isCurrentlyChessBoard ? 310.1 : 91.8;

      final headerKey = getHeaderKey(item.roundId);
      if (headerKey.currentContext != null) {
        final headerRenderBox =
            headerKey.currentContext!.findRenderObject() as RenderBox?;
        if (headerRenderBox != null && headerRenderBox.attached) {
          headerHeight = headerRenderBox.size.height;
        }
      }

      calculatedOffset += contentPadding;

      bool foundTargetRound = false;

      for (final round in visibleRounds) {
        if (round.id == item.roundId) {
          foundTargetRound = true;

          if (item.type == TopMostItemType.game && item.gameIndex != null) {
            calculatedOffset +=
                headerTopMargin + headerHeight + headerBottomMargin;

            final priorGamesCount = item.gameIndex!;
            if (priorGamesCount > 0) {
              double priorGamesHeight = 0;
              for (int i = 0; i < priorGamesCount; i++) {
                final gameKey = getGameKey(round.id, i);
                double currentGameHeight = gameHeight;
                if (gameKey.currentContext != null) {
                  final gameRenderBox =
                      gameKey.currentContext!.findRenderObject() as RenderBox?;
                  if (gameRenderBox != null && gameRenderBox.attached) {
                    currentGameHeight = gameRenderBox.size.height;
                  }
                } else {
                  debugPrint(
                    'Using default game height for round ${round.id}, index $i: ${currentGameHeight.toStringAsFixed(1)}',
                  );
                }
                priorGamesHeight += currentGameHeight;
              }
              priorGamesHeight += (priorGamesCount - 1) * gameSpacing;
              calculatedOffset += priorGamesHeight;
            }
          } else {
            calculatedOffset += headerTopMargin;
          }
          break;
        }

        if (!foundTargetRound) {
          calculatedOffset +=
              headerTopMargin + headerHeight + headerBottomMargin;

          // Add games in prior round
          final games = gamesByRound[round.id] ?? [];
          final numGames = games.length;
          if (numGames > 0) {
            double roundGamesHeight = 0;
            for (int i = 0; i < numGames; i++) {
              final gameKey = getGameKey(round.id, i);
              double currentGameHeight = gameHeight;
              if (gameKey.currentContext != null) {
                final gameRenderBox =
                    gameKey.currentContext!.findRenderObject() as RenderBox?;
                if (gameRenderBox != null && gameRenderBox.attached) {
                  currentGameHeight = gameRenderBox.size.height;
                }
              } else {
                debugPrint(
                  'Using default game height for prior round ${round.id}, index $i: ${currentGameHeight.toStringAsFixed(1)}',
                );
              }
              roundGamesHeight += currentGameHeight;
            }
            roundGamesHeight += (numGames - 1) * gameSpacing;
            calculatedOffset += roundGamesHeight;
          }
        }
      }

      if (widget.scrollController.hasClients) {
        final maxOffset = widget.scrollController.position.maxScrollExtent;
        calculatedOffset = calculatedOffset.clamp(0.0, maxOffset);
      }

      return calculatedOffset;
    } catch (e) {
      return null;
    }
  }

  double? calculateTargetScrollOffsetForGame(TopMostVisibleItem item) {
    try {
      final gamesData = ref.read(gamesTourScreenProvider).valueOrNull;
      if (gamesData == null || item.gameIndex == null) return null;

      final rounds =
          ref.read(gamesAppBarProvider).value?.gamesAppBarModels ?? [];
      final gamesByRound = <String, List<GamesTourModel>>{};

      for (final game in gamesData.gamesTourModels) {
        gamesByRound.putIfAbsent(game.roundId, () => []).add(game);
      }

      final visibleRounds =
          rounds
              .where((round) => (gamesByRound[round.id]?.isNotEmpty ?? false))
              .toList()
              .reversed
              .toList();

      double calculatedOffset = 0;
      const double headerHeight = 50;
      const double padding = 16;
      const double gameSpacing = 12;

      final bool isCurrentlyChessBoard = ref.read(chessBoardVisibilityProvider);
      final double gameHeight = isCurrentlyChessBoard ? 300 : 120;

      calculatedOffset += padding;

      bool foundTargetRound = false;

      for (final round in visibleRounds) {
        if (round.id == item.roundId) {
          foundTargetRound = true;

          calculatedOffset += headerHeight;

          calculatedOffset += item.gameIndex! * (gameHeight + gameSpacing);

          break;
        }

        if (!foundTargetRound) {
          calculatedOffset += headerHeight;
          final games = gamesByRound[round.id] ?? [];
          calculatedOffset += games.length * (gameHeight + gameSpacing);
        }
      }

      if (widget.scrollController.hasClients) {
        final maxOffset = widget.scrollController.position.maxScrollExtent;
        calculatedOffset = calculatedOffset.clamp(0.0, maxOffset);
      }

      return calculatedOffset;
    } catch (e) {
      return null;
    }
  }

  void checkRoundContentVisibility() {
    final scrollState = ref.read(scrollStateProvider);

    if (!scrollState.isUserScrolling ||
        scrollState.isScrolling ||
        _isViewSwitching ||
        _isProgrammaticScroll)
      return;

    final gamesData = ref.read(gamesTourScreenProvider).valueOrNull;
    if (gamesData == null) return;

    final gamesByRound = <String, List<GamesTourModel>>{};
    for (final game in gamesData.gamesTourModels) {
      gamesByRound.putIfAbsent(game.roundId, () => []).add(game);
    }

    final rounds = ref.read(gamesAppBarProvider).value?.gamesAppBarModels ?? [];
    final visibleRounds =
        rounds
            .where((round) => (gamesByRound[round.id]?.isNotEmpty ?? false))
            .toList();
    final reversedRounds = visibleRounds.reversed.toList();

    String? mostVisibleRound;
    double maxVisibilityScore = 0;

    // IMPROVED: Also track header visibility specifically
    String? headerInViewport;
    double headerVisibilityScore = 0;

    for (final round in reversedRounds) {
      final roundGames = gamesByRound[round.id] ?? [];
      if (roundGames.isEmpty) continue;

      // Check header visibility first
      final headerKey = getHeaderKey(round.id);
      final headerContext = headerKey.currentContext;
      if (headerContext != null) {
        final headerRenderBox = headerContext.findRenderObject() as RenderBox?;
        if (headerRenderBox?.attached == true) {
          final headerPosition = headerRenderBox!.localToGlobal(Offset.zero);
          final topPadding = MediaQuery.of(context).padding.top;
          final appBarHeight = kToolbarHeight;
          final visibleAreaTop = topPadding + appBarHeight;
          final visibleAreaBottom = MediaQuery.of(context).size.height;

          final headerTop = headerPosition.dy;
          final headerBottom = headerPosition.dy + headerRenderBox.size.height;

          // Header is in viewport
          if (headerBottom > visibleAreaTop && headerTop < visibleAreaBottom) {
            final headerVisibleHeight =
                (headerBottom.clamp(visibleAreaTop, visibleAreaBottom) -
                        headerTop.clamp(visibleAreaTop, visibleAreaBottom))
                    .abs();
            final headerTotalHeight = headerRenderBox.size.height;
            final currentHeaderScore = headerVisibleHeight / headerTotalHeight;

            // IMPROVED: Prioritize headers that are near the top of viewport
            final distanceFromTop = (headerTop - visibleAreaTop).abs();
            final proximityBonus = distanceFromTop < 100 ? 0.5 : 0.0;
            final adjustedHeaderScore = currentHeaderScore + proximityBonus;

            if (adjustedHeaderScore > headerVisibilityScore) {
              headerVisibilityScore = adjustedHeaderScore;
              headerInViewport = round.id;
            }
          }
        }
      }

      // Calculate overall round content visibility
      final visibilityScore = calculateRoundContentVisibility(
        round.id,
        roundGames,
      );

      if (visibilityScore > maxVisibilityScore) {
        maxVisibilityScore = visibilityScore;
        mostVisibleRound = round.id;
      }
    }

    // IMPROVED: Decision logic - prioritize header visibility for dropdown updates
    String? finalRoundToSelect;

    if (headerInViewport != null && headerVisibilityScore > 0.3) {
      // If a header is clearly visible, use it
      finalRoundToSelect = headerInViewport;
      debugPrint(
        '🎯 Selected round based on header visibility: $headerInViewport (score: ${headerVisibilityScore.toStringAsFixed(2)})',
      );
    } else if (mostVisibleRound != null && maxVisibilityScore > 0.4) {
      // Otherwise fall back to content visibility
      finalRoundToSelect = mostVisibleRound;
      debugPrint(
        '🎯 Selected round based on content visibility: $mostVisibleRound (score: ${maxVisibilityScore.toStringAsFixed(2)})',
      );
    }

    if (finalRoundToSelect != null) {
      final currentVisible = ref.read(currentVisibleRoundProvider);
      final currentSelected =
          ref.read(gamesAppBarProvider).valueOrNull?.selectedId;

      if (currentVisible != finalRoundToSelect) {
        ref
            .read(roundVisibilityNotifierProvider)
            .updateVisibleRound(finalRoundToSelect);

        // Update dropdown immediately if user is scrolling manually
        if (currentSelected != finalRoundToSelect && !_isProgrammaticScroll) {
          final gamesAppBarData = ref.read(gamesAppBarProvider).valueOrNull;
          if (gamesAppBarData != null) {
            final targetRound =
                gamesAppBarData.gamesAppBarModels
                    .where((round) => round.id == finalRoundToSelect)
                    .firstOrNull;

            if (targetRound != null) {
              debugPrint('🔄 Updating dropdown to: ${targetRound.name}');
              ref
                  .read(gamesAppBarProvider.notifier)
                  .selectSilently(targetRound);
            }
          }
        }
      }
    }
  }

  // IMPROVED: Also update the scroll listener to be more responsive
  void setupScrollListener() {
    widget.scrollController.addListener(() {
      if (!_isScrolling && !_isViewSwitching && !_isProgrammaticScroll) {
        _isScrolling = true;
        ref.read(scrollStateProvider.notifier).setUserScrolling(true);
      }

      _visibilityCheckTimer?.cancel();
      // IMPROVED: Faster response time for better UX
      _visibilityCheckTimer = Timer(const Duration(milliseconds: 100), () {
        if (mounted && !_isViewSwitching && !_isProgrammaticScroll) {
          checkRoundContentVisibility();
        }
      });
    });
  }

  Future<void> scrollToRound(String roundId) async {
    if (!mounted || _isViewSwitching) return;

    debugPrint('🎯 scrollToRound called for: $roundId');

    _isProgrammaticScroll = true;

    ref.read(scrollStateProvider.notifier).setScrolling(true);
    ref.read(scrollStateProvider.notifier).setUserScrolling(false);
    ref.read(scrollStateProvider.notifier).updateSelectedRound(roundId);

    try {
      if (!widget.scrollController.hasClients) {
        return;
      }

      // STRATEGY 1: Try calculated position first for long distances
      final calculatedPosition = calculateScrollPositionForRound(roundId);
      if (calculatedPosition != null) {
        final maxOffset = widget.scrollController.position.maxScrollExtent;
        final clampedPosition = calculatedPosition.clamp(0.0, maxOffset);

        debugPrint(
          '📐 Using calculated position: $clampedPosition for round: $roundId',
        );

        // Jump to approximate position first
        widget.scrollController.jumpTo(clampedPosition);

        // Wait for render
        await Future.delayed(const Duration(milliseconds: 200));
      }

      // STRATEGY 2: Now try to find the exact header and fine-tune
      final headerKey = getHeaderKey(roundId);
      bool scrollSuccess = false;

      // Give more attempts for long distances
      for (int attempt = 0; attempt < 40; attempt++) {
        await Future.delayed(const Duration(milliseconds: 50));

        if (headerKey.currentContext != null) {
          try {
            final renderBox =
                headerKey.currentContext!.findRenderObject() as RenderBox?;
            if (renderBox?.attached == true) {
              // Check if the header is already visible and well-positioned
              final position = renderBox!.localToGlobal(Offset.zero);
              final topPadding = MediaQuery.of(context).padding.top;
              final appBarHeight = kToolbarHeight;
              final visibleAreaTop = topPadding + appBarHeight;

              // If header is already in a good position, we're done
              if (position.dy >= visibleAreaTop &&
                  position.dy <= visibleAreaTop + 100) {
                scrollSuccess = true;
                debugPrint(
                  '✅ Header already in good position on attempt $attempt',
                );
                break;
              }

              // Otherwise, scroll to it
              await Scrollable.ensureVisible(
                headerKey.currentContext!,
                alignment: 0.0,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
                alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
              );
              scrollSuccess = true;
              debugPrint('✅ Scroll successful on attempt $attempt');
              break;
            }
          } catch (e) {
            debugPrint('❌ Scroll attempt $attempt failed: $e');
          }
        } else {
          // If header context is not available, force a rebuild by scrolling slightly
          if (attempt % 10 == 0 && attempt > 0) {
            final currentOffset = widget.scrollController.offset;
            widget.scrollController.jumpTo(
              (currentOffset + 1).clamp(
                0.0,
                widget.scrollController.position.maxScrollExtent,
              ),
            );
            await Future.delayed(const Duration(milliseconds: 100));
          }
        }
      }

      if (!scrollSuccess) {
        debugPrint('❌ All scroll attempts failed for round: $roundId');

        // STRATEGY 3: Fallback - try to scroll to the first game of this round
        final gamesData = ref.read(gamesTourScreenProvider).valueOrNull;
        if (gamesData != null) {
          final gameIndex = _findFirstGameIndexForRound(
            gamesData.gamesTourModels,
            roundId,
          );
          if (gameIndex != null &&
              gameIndex < gamesData.gamesTourModels.length) {
            final game = gamesData.gamesTourModels[gameIndex];
            final gameKey = getGameKey(
              game.roundId,
              gameIndex % 100,
            ); // Approximate local index

            for (int gameAttempt = 0; gameAttempt < 20; gameAttempt++) {
              await Future.delayed(const Duration(milliseconds: 50));
              if (gameKey.currentContext != null) {
                try {
                  await Scrollable.ensureVisible(
                    gameKey.currentContext!,
                    alignment: 0.0,
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                  );
                  debugPrint('✅ Fallback scroll to game successful');
                  scrollSuccess = true;
                  break;
                } catch (e) {
                  debugPrint(
                    '❌ Fallback game scroll attempt $gameAttempt failed: $e',
                  );
                }
              }
            }
          }
        }
      }
    } catch (e) {
      debugPrint('❌ Scroll error: $e');
    } finally {
      // Reset flags with proper delay
      Future.delayed(const Duration(milliseconds: 800), () {
        if (mounted) {
          ref.read(scrollStateProvider.notifier).setScrolling(false);
          _isProgrammaticScroll = false;
          debugPrint('🔄 Reset scroll flags for round: $roundId');
        }
      });
    }
  }

  // Helper method to find first game index for a round
  int? _findFirstGameIndexForRound(List<GamesTourModel> games, String roundId) {
    for (int i = 0; i < games.length; i++) {
      if (games[i].roundId == roundId) {
        return i;
      }
    }
    return null;
  }

  double calculateRoundContentVisibility(
    String roundId,
    List<GamesTourModel> roundGames,
  ) {
    final screenHeight = MediaQuery.of(context).size.height;
    final topPadding = MediaQuery.of(context).padding.top;
    final appBarHeight = kToolbarHeight;

    final visibleAreaTop = topPadding + appBarHeight;
    final visibleAreaBottom = screenHeight;
    final visibleAreaHeight = visibleAreaBottom - visibleAreaTop;

    double totalVisibleHeight = 0;
    double totalRoundHeight = 0;
    int itemsChecked = 0;

    final headerKey = getHeaderKey(roundId);
    final headerContext = headerKey.currentContext;
    if (headerContext != null) {
      final headerRenderBox = headerContext.findRenderObject() as RenderBox?;
      if (headerRenderBox?.attached == true) {
        final headerPosition = headerRenderBox!.localToGlobal(Offset.zero);
        final headerSize = headerRenderBox.size;

        totalRoundHeight += headerSize.height;

        final headerTop = headerPosition.dy;
        final headerBottom = headerPosition.dy + headerSize.height;

        if (headerBottom > visibleAreaTop && headerTop < visibleAreaBottom) {
          final visibleTop = headerTop.clamp(visibleAreaTop, visibleAreaBottom);
          final visibleBottom = headerBottom.clamp(
            visibleAreaTop,
            visibleAreaBottom,
          );
          totalVisibleHeight += (visibleBottom - visibleTop).clamp(
            0.0,
            headerSize.height,
          );
        }

        itemsChecked++;
      }
    }

    final gamesToCheck =
        roundGames.length > 10
            ? [
              roundGames.first,
              ...roundGames.skip(roundGames.length ~/ 2).take(5),
              roundGames.last,
            ]
            : roundGames;

    for (final game in gamesToCheck) {
      final gameIndex = roundGames.indexOf(game);
      final gameKey = getGameKey(roundId, gameIndex);
      final gameContext = gameKey.currentContext;

      if (gameContext != null) {
        final gameRenderBox = gameContext.findRenderObject() as RenderBox?;
        if (gameRenderBox?.attached == true) {
          final gamePosition = gameRenderBox!.localToGlobal(Offset.zero);
          final gameSize = gameRenderBox.size;

          totalRoundHeight += gameSize.height;

          final gameTop = gamePosition.dy;
          final gameBottom = gamePosition.dy + gameSize.height;

          if (gameBottom > visibleAreaTop && gameTop < visibleAreaBottom) {
            final visibleTop = gameTop.clamp(visibleAreaTop, visibleAreaBottom);
            final visibleBottom = gameBottom.clamp(
              visibleAreaTop,
              visibleAreaBottom,
            );
            totalVisibleHeight += (visibleBottom - visibleTop).clamp(
              0.0,
              gameSize.height,
            );
          }

          itemsChecked++;
        }
      }
    }

    if (itemsChecked == 0 || totalRoundHeight == 0) return 0;

    double visibilityScore = totalVisibleHeight / totalRoundHeight;

    final headerContext2 = headerKey.currentContext;

    if (headerContext2 != null) {
      final headerRenderBox = headerContext2.findRenderObject() as RenderBox?;
      if (headerRenderBox?.attached == true) {
        final headerPosition = headerRenderBox!.localToGlobal(Offset.zero);

        if (headerPosition.dy >= visibleAreaTop &&
            headerPosition.dy <= visibleAreaTop + (visibleAreaHeight * 0.6)) {
          visibilityScore += 0.2;
        }
      }
    }

    return visibilityScore.clamp(0.0, 1.0);
  }

  GlobalKey getHeaderKey(String roundId) {
    if (!_headerKeys.containsKey(roundId)) {
      _headerKeys[roundId] = GlobalKey(debugLabel: 'header_$roundId');
    }
    return _headerKeys[roundId]!;
  }

  GlobalKey getGameKey(String roundId, int gameIndex) {
    _gameKeys.putIfAbsent(roundId, () => []);
    final gameList = _gameKeys[roundId]!;
    while (gameList.length <= gameIndex) {
      gameList.add(GlobalKey(debugLabel: 'game_${roundId}_$gameIndex'));
    }
    return gameList[gameIndex];
  }

  double? calculateScrollPositionForRound(String roundId) {
    try {
      final gamesData = ref.read(gamesTourScreenProvider).valueOrNull;
      if (gamesData == null) return null;

      final rounds =
          ref.read(gamesAppBarProvider).value?.gamesAppBarModels ?? [];
      final gamesByRound = <String, List<GamesTourModel>>{};

      for (final game in gamesData.gamesTourModels) {
        gamesByRound.putIfAbsent(game.roundId, () => []).add(game);
      }

      final visibleRounds =
          rounds
              .where((round) => (gamesByRound[round.id]?.isNotEmpty ?? false))
              .toList()
              .reversed
              .toList();

      double position = 0;
      double headerHeight = 50;
      const double headerTopMargin = 16;
      const double headerBottomMargin = 8;
      const double gameSpacing = 12;
      const double contentPadding = 16;
      final isChessBoard = ref.read(chessBoardVisibilityProvider);
      double gameHeight = isChessBoard ? 310.1 : 91.8;

      // Get actual header height for target round
      final headerKey = getHeaderKey(roundId);
      if (headerKey.currentContext != null) {
        final headerRenderBox =
            headerKey.currentContext!.findRenderObject() as RenderBox?;
        if (headerRenderBox != null && headerRenderBox.attached) {
          headerHeight = headerRenderBox.size.height;
        }
      }

      position += contentPadding;

      for (final round in visibleRounds) {
        if (round.id == roundId) {
          position += headerTopMargin;
          return position;
        }
        position += headerTopMargin + headerHeight + headerBottomMargin;

        final games = gamesByRound[round.id] ?? [];
        final numGames = games.length;
        if (numGames > 0) {
          double roundGamesHeight = 0;
          for (int i = 0; i < numGames; i++) {
            final gameKey = getGameKey(round.id, i);
            double currentGameHeight = gameHeight;
            if (gameKey.currentContext != null) {
              final gameRenderBox =
                  gameKey.currentContext!.findRenderObject() as RenderBox?;
              if (gameRenderBox != null && gameRenderBox.attached) {
                currentGameHeight = gameRenderBox.size.height;
              }
            } else {
              debugPrint(
                'Using default game height for prior round ${round.id}, index $i: ${currentGameHeight.toStringAsFixed(1)}',
              );
            }
            roundGamesHeight += currentGameHeight;
          }
          roundGamesHeight += (numGames - 1) * gameSpacing;
          position += roundGamesHeight;
        }

        if (widget.scrollController.hasClients &&
            position > widget.scrollController.position.maxScrollExtent) {
          return widget.scrollController.position.maxScrollExtent;
        }
      }

      return null;
    } catch (e) {
      return null;
    }
  }

  Future<void> handleRefresh() async {
    try {
      FocusScope.of(context).unfocus();
      final futures = <Future>[];
      futures.add(
        ref.read(tourDetailScreenProvider.notifier).refreshTourDetails(),
      );
      futures.add(ref.read(gamesAppBarProvider.notifier).refresh());
      futures.add(ref.read(gamesTourScreenProvider.notifier).refreshGames());
      await Future.wait(futures);
      _isInitialized = false;
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) {
          synchronizeInitialSelection();
        }
      });
    } catch (_) {}
  }
}
