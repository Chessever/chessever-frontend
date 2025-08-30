import 'dart:async';
import 'package:advanced_chess_board/models/enums.dart';
import 'package:chessever2/screens/games_tour/providers/games_tour_scroll_state_provider.dart';
import 'package:chessever2/screens/games_tour/providers/games_tour_visibility_provider.dart';
import 'package:chessever2/screens/games_tour/widgets/games_tour_content_body.dart';
import 'package:chessever2/screens/group_event/model/games_tour_model.dart';
import 'package:chessever2/screens/group_event/providers/chess_board_visibility_provider.dart';
import 'package:chessever2/screens/group_event/providers/games_app_bar_provider.dart';
import 'package:chessever2/screens/group_event/providers/games_tour_screen_provider.dart';
import 'package:chessever2/screens/group_event/providers/tour_detail_screen_provider.dart';
import 'package:chessever2/screens/group_event/providers/group_event_screen_provider.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:chessever2/screens/group_event/model/games_app_bar_view_model.dart';
import '../widgets/top_most_visible_item_model.dart';

class GamesTourScreen extends ConsumerStatefulWidget {
  const GamesTourScreen({super.key});

  @override
  ConsumerState<ConsumerStatefulWidget> createState() =>
      _GamesTourScreenState();
}

class _GamesTourScreenState extends ConsumerState<GamesTourScreen> {
  late ScrollController _scrollController;
  final Map<String, GlobalKey> _headerKeys = {};
  final Map<String, List<GlobalKey>> _gameKeys = {};
  GamesScreenModel? _lastGamesData;

  Timer? _visibilityCheckTimer;
  bool _isScrolling = false;
  bool _isInitialized = false;

  bool _isViewSwitching = false;
  bool _isProgrammaticScroll = false;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    setupScrollListener(); // Using extension method
    setupViewSwitchListener(); // Using extension method

    WidgetsBinding.instance.addPostFrameCallback((_) {
      synchronizeInitialSelection(); // Using extension method
    });
  }

  @override
  void dispose() {
    _visibilityCheckTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    Future.microtask(() {
      if (mounted) {
        ref.read(scrollStateProvider.notifier).reset();
        ref.read(currentVisibleRoundProvider.notifier).state = null;
        _headerKeys.clear();
        _gameKeys.clear();
        _isInitialized = false;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isChessBoardVisible = ref.watch(chessBoardVisibilityProvider);
    final gamesAppBarAsync = ref.watch(gamesAppBarProvider);
    final gamesTourAsync = ref.watch(gamesTourScreenProvider);
    final scrollState = ref.watch(scrollStateProvider);

    // Listen to app bar changes and scroll to selected round
    ref.listen<AsyncValue<GamesAppBarViewModel>>(gamesAppBarProvider, (
      previous,
      next,
    ) {
      if (!_isInitialized) return;

      final previousSelected = previous?.valueOrNull?.selectedId;
      final currentSelected = next.valueOrNull?.selectedId;

      if (currentSelected != null &&
          currentSelected != previousSelected &&
          next.valueOrNull?.userSelectedId == true) {
        ref.read(scrollStateProvider.notifier).setUserScrolling(false);
        ref.read(scrollStateProvider.notifier).setScrolling(false);
        ref
            .read(scrollStateProvider.notifier)
            .updateSelectedRound(currentSelected);

        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted) {
            scrollToRound(currentSelected);
          }
        });
      }
    });

    ref.listen<String?>(currentVisibleRoundProvider, (previous, next) {
      if (next != null && next != previous && _isInitialized) {
        final scrollState = ref.read(scrollStateProvider);
        final currentSelected = gamesAppBarAsync.valueOrNull?.selectedId;

        if (scrollState.isUserScrolling &&
            !scrollState.isScrolling &&
            currentSelected != next &&
            !_isViewSwitching &&
            !_isProgrammaticScroll) {
          final gamesAppBarData = gamesAppBarAsync.valueOrNull;
          if (gamesAppBarData != null) {
            final targetRound =
                gamesAppBarData.gamesAppBarModels
                    .where((round) => round.id == next)
                    .firstOrNull;

            if (targetRound != null) {
              ref
                  .read(gamesAppBarProvider.notifier)
                  .selectNewRoundSilently(targetRound);
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
        } else if (notification is ScrollEndNotification && !_isViewSwitching) {
          _isScrolling = false;
          _isProgrammaticScroll = false;
          Future.delayed(const Duration(milliseconds: 50), () {
            if (mounted && !_isViewSwitching) {
              checkRoundContentVisibility(); // Using extension method
              ref.read(scrollStateProvider.notifier).setUserScrolling(false);
            }
          });
        }

        return false;
      },
      child: RefreshIndicator(
        onRefresh: () => handleRefresh(gamesAppBarAsync, gamesTourAsync),
        // Using extension method
        color: kWhiteColor70,
        backgroundColor: kDarkGreyColor,
        displacement: 60.h,
        strokeWidth: 3.w,
        child: GamesTourContentBody(
          gamesAppBarAsync: gamesAppBarAsync,
          gamesTourAsync: gamesTourAsync,
          isChessBoardVisible: isChessBoardVisible,
          scrollController: _scrollController,
          headerKeys: _headerKeys,
          gameKeys: _gameKeys,
          getHeaderKey: getHeaderKey,
          // Using extension method
          getGameKey: getGameKey,
          // Using extension method
          lastGamesData: _lastGamesData,
          onGamesDataUpdate: (data) => _lastGamesData = data,
        ),
      ),
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
      if (targetRoundId == null) {
        debugPrint(
          '⚠️ Player "$normalizedPlayerName" not found in any game. Falling back to round selection.',
        );
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
          ref
              .read(gamesAppBarProvider.notifier)
              .selectNewRoundSilently(targetRound);
        }
      }
    }

    if (targetRoundId != null) {
      _isInitialized = true;

      ref.read(scrollStateProvider.notifier).setInitialScrollPerformed();
      ref.read(scrollStateProvider.notifier).updateSelectedRound(targetRoundId);
      ref.read(scrollStateProvider.notifier).setUserScrolling(false);

      Future.delayed(const Duration(milliseconds: 1000), () {
        if (mounted) {
          if (targetGameIndex != null && selectedPlayerName != null) {
            scrollToGame(targetRoundId!, targetGameIndex);
          } else {
            scrollToRound(targetRoundId!);
          }
          ref.read(selectedPlayerNameProvider.notifier).state = null;
        }
      });
    } else {
      debugPrint('No target round found for scrolling.');
    }
  }

  Future<void> scrollToGame(String roundId, int gameIndex) async {
    if (!mounted || _isViewSwitching) return;

    _isProgrammaticScroll = true;

    ref.read(scrollStateProvider.notifier).setScrolling(true);
    ref.read(scrollStateProvider.notifier).setUserScrolling(false);
    ref.read(scrollStateProvider.notifier).updateSelectedRound(roundId);

    try {
      if (!_scrollController.hasClients) {
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

  void setupScrollListener() {
    _scrollController.addListener(() {
      if (!_isScrolling && !_isViewSwitching && !_isProgrammaticScroll) {
        _isScrolling = true;
        ref.read(scrollStateProvider.notifier).setUserScrolling(true);
      }

      _visibilityCheckTimer?.cancel();
      _visibilityCheckTimer = Timer(const Duration(milliseconds: 100), () {
        if (mounted && !_isViewSwitching && !_isProgrammaticScroll) {
          checkRoundContentVisibility();
        }
      });
    });
  }

  void setupViewSwitchListener() {
    ref.listenManual(chessBoardVisibilityProvider, (previous, next) {
      if (previous != next) {
        handleViewSwitch();
      }
    });
  }

  void handleViewSwitch() {
    if (!mounted || !_scrollController.hasClients) {
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
    final gamesData =
        _lastGamesData ?? ref.read(gamesTourScreenProvider).valueOrNull;
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
        _scrollController.hasClients ? _scrollController.offset : 0.0;

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
    await Future.delayed(const Duration(milliseconds: 1200));

    if (!mounted || !_scrollController.hasClients) {
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
    if (targetOffset != null && _scrollController.hasClients) {
      final maxOffset = _scrollController.position.maxScrollExtent;
      final clampedOffset = targetOffset.clamp(0.0, maxOffset);
      _scrollController.jumpTo(clampedOffset);
      await Future.delayed(const Duration(milliseconds: 300));
    }

    bool positionAchieved = false;
    for (int retry = 0; retry < 15; retry++) {
      await Future.delayed(const Duration(milliseconds: 100));

      if (!mounted || !_scrollController.hasClients) break;

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

            final currentOffset = _scrollController.offset;
            final newOffset = currentOffset + adjustment;
            final maxOffset = _scrollController.position.maxScrollExtent;
            final clampedOffset = newOffset.clamp(0.0, maxOffset);

            _scrollController.jumpTo(clampedOffset);
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
    if (targetOffset != null && _scrollController.hasClients) {
      final maxOffset = _scrollController.position.maxScrollExtent;
      final clampedOffset = targetOffset.clamp(0.0, maxOffset);
      _scrollController.jumpTo(clampedOffset);
      await Future.delayed(const Duration(milliseconds: 200));
    }

    for (int retry = 0; retry < 10; retry++) {
      await Future.delayed(const Duration(milliseconds: 100));

      if (!mounted || !_scrollController.hasClients) break;

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

            final currentOffset = _scrollController.offset;
            final newOffset = currentOffset + adjustment;
            final maxOffset = _scrollController.position.maxScrollExtent;
            final clampedOffset = newOffset.clamp(0.0, maxOffset);

            _scrollController.jumpTo(clampedOffset);
          }
        } catch (e) {
          debugPrint('[GamesTourScreen] Header positioning error: $e');
        }
      }
    }
  }

  double? calculateTargetScrollOffset(TopMostVisibleItem item) {
    try {
      final gamesData =
          _lastGamesData ?? ref.read(gamesTourScreenProvider).valueOrNull;
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

      if (_scrollController.hasClients) {
        final maxOffset = _scrollController.position.maxScrollExtent;
        calculatedOffset = calculatedOffset.clamp(0.0, maxOffset);
      }

      return calculatedOffset;
    } catch (e) {
      return null;
    }
  }

  double? calculateTargetScrollOffsetForGame(TopMostVisibleItem item) {
    try {
      final gamesData =
          _lastGamesData ?? ref.read(gamesTourScreenProvider).valueOrNull;
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

      if (_scrollController.hasClients) {
        final maxOffset = _scrollController.position.maxScrollExtent;
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

    final gamesData =
        _lastGamesData ?? ref.read(gamesTourScreenProvider).valueOrNull;
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

    for (final round in reversedRounds) {
      final roundGames = gamesByRound[round.id] ?? [];
      if (roundGames.isEmpty) continue;

      final visibilityScore = calculateRoundContentVisibility(
        round.id,
        roundGames,
      );

      if (visibilityScore > maxVisibilityScore) {
        maxVisibilityScore = visibilityScore;
        mostVisibleRound = round.id;
      }
    }

    if (mostVisibleRound != null && maxVisibilityScore > 0.1) {
      final currentVisible = ref.read(currentVisibleRoundProvider);
      if (currentVisible != mostVisibleRound) {
        ref
            .read(roundVisibilityNotifierProvider)
            .updateVisibleRound(mostVisibleRound);
      }
    }
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

  Future<void> scrollToRound(String roundId) async {
    if (!mounted || _isViewSwitching) return;

    _isProgrammaticScroll = true;

    ref.read(scrollStateProvider.notifier).setScrolling(true);
    ref.read(scrollStateProvider.notifier).setUserScrolling(false);
    ref.read(scrollStateProvider.notifier).updateSelectedRound(roundId);

    try {
      if (!_scrollController.hasClients) {
        return;
      }

      final headerKey = getHeaderKey(roundId);
      final position = calculateScrollPositionForRound(roundId);

      if (position != null && position >= 0) {
        _scrollController.jumpTo(position);
      }

      bool found = false;

      for (int retry = 0; retry < 30; retry++) {
        await Future.delayed(const Duration(milliseconds: 50));

        if (headerKey.currentContext != null) {
          try {
            Scrollable.ensureVisible(
              headerKey.currentContext!,
              alignment: 0.0,
              duration: Duration.zero, // Instant scroll
              alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
            );
            found = true;
            break;
          } catch (e) {
            debugPrint(
              '[GamesTourScreen] Scroll error with key on retry $retry: $e',
            );
          }
        } else {
          debugPrint('Key not found on retry $retry for round $roundId');
        }
      }

      if (!found) {
        debugPrint('Failed to scroll to round: $roundId after all attempts');
      }
    } catch (e) {
      debugPrint('[GamesTourScreen] Scroll error: $e');
    } finally {
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) {
          ref.read(scrollStateProvider.notifier).setScrolling(false);
          _isProgrammaticScroll = false;
        }
      });
    }
  }

  double? calculateScrollPositionForRound(String roundId) {
    try {
      final gamesData =
          _lastGamesData ?? ref.read(gamesTourScreenProvider).valueOrNull;
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

        if (_scrollController.hasClients &&
            position > _scrollController.position.maxScrollExtent) {
          return _scrollController.position.maxScrollExtent;
        }
      }

      return null;
    } catch (e) {
      return null;
    }
  }

  Future<void> handleRefresh(
    AsyncValue gamesAppBarAsync,
    AsyncValue<GamesScreenModel> gamesTourAsync,
  ) async {
    FocusScope.of(context).unfocus();

    final futures = <Future>[];

    try {
      futures.add(
        ref.read(tourDetailScreenProvider.notifier).refreshTourDetails(),
      );
    } catch (_) {}

    if (gamesAppBarAsync.hasValue) {
      futures.add(ref.read(gamesAppBarProvider.notifier).refreshRounds());
    }

    if (gamesTourAsync.hasValue) {
      futures.add(ref.read(gamesTourScreenProvider.notifier).refreshGames());
    }

    if (futures.isNotEmpty) {
      await Future.wait(futures);
    }

    _isInitialized = false;
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) {
        synchronizeInitialSelection();
      }
    });
  }
}
