import 'dart:async';
import 'package:chessever2/screens/games_tour_screen/providers/games_tour_scroll_state_provider.dart';
import 'package:chessever2/screens/games_tour_screen/providers/games_tour_visibility_provider.dart';
import 'package:chessever2/screens/games_tour_screen/widgets/games_tour_content_body.dart';
import 'package:chessever2/screens/tournaments/model/games_tour_model.dart';
import 'package:chessever2/screens/tournaments/providers/chess_board_visibility_provider.dart';
import 'package:chessever2/screens/tournaments/providers/games_app_bar_provider.dart';
import 'package:chessever2/screens/tournaments/providers/games_tour_screen_provider.dart';
import 'package:chessever2/screens/tournaments/providers/tour_detail_screen_provider.dart';
import 'package:chessever2/screens/tournaments/providers/group_event_screen_provider.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:chessever2/screens/tournaments/model/games_app_bar_view_model.dart';

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
            scrollToRound(currentSelected); // Using extension method
          }
        });
      }
    });

    // Listen to visible round changes and update app bar selection
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
        onRefresh:
            () => handleRefresh(
              gamesAppBarAsync,
              gamesTourAsync,
            ), // Using extension method
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
          getHeaderKey: getHeaderKey, // Using extension method
          getGameKey: getGameKey, // Using extension method
          lastGamesData: _lastGamesData,
          onGamesDataUpdate: (data) => _lastGamesData = data,
        ),
      ),
    );
  }
}




// Enum to identify the type of top-most visible item
enum TopMostItemType { header, game }

// Data class to hold information about the top-most visible item
class TopMostVisibleItem {
  final TopMostItemType type;
  final String roundId;
  final int? gameIndex;
  final String? gameId;
  final double scrollOffset;
  final double? relativePosition; // Position relative to visible area top

  TopMostVisibleItem({
    required this.type,
    required this.roundId,
    this.gameIndex,
    this.gameId,
    required this.scrollOffset,
    this.relativePosition,
  });
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
        final visibleRounds = rounds
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
        debugPrint(
          'Failed to scroll to game in round $roundId, index $gameIndex after all attempts. Falling back to round scroll.',
        );
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
    if (!mounted || !_scrollController.hasClients) return;

    _isViewSwitching = true;

    // Always capture the top-most visible item before view switch
    final topMostVisibleItem = findTopMostVisibleItem();
    
    debugPrint('🔄 View switching - captured item: ${topMostVisibleItem?.type} at round ${topMostVisibleItem?.roundId}');
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        // Wait longer to ensure AnimatedSwitcher completes and new widgets are built
        Future.delayed(const Duration(milliseconds: 1200), () {
          if (mounted && topMostVisibleItem != null) {
            scrollToTopMostVisibleItemAfterViewSwitch(topMostVisibleItem);
          } else {
            debugPrint('⚠️ No top-most item found or widget unmounted');
            _isViewSwitching = false;
          }
        });
      }
    });
  }

  // Enhanced data class to hold more precise position information
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

    // Get current scroll position
    final currentScrollOffset = _scrollController.hasClients 
        ? _scrollController.offset 
        : 0.0;

    // Check all rounds in order
    final rounds = ref.read(gamesAppBarProvider).value?.gamesAppBarModels ?? [];
    final visibleRounds = rounds
        .where((round) => (gamesByRound[round.id]?.isNotEmpty ?? false))
        .toList()
        .reversed
        .toList();

    TopMostVisibleItem? topMostItem;
    double topMostPosition = double.infinity;

    for (final round in visibleRounds) {
      final roundId = round.id;
      final roundGames = gamesByRound[roundId] ?? [];

      // Check header first
      final headerKey = getHeaderKey(roundId);
      final headerContext = headerKey.currentContext;
      if (headerContext != null) {
        final headerRenderBox = headerContext.findRenderObject() as RenderBox?;
        if (headerRenderBox?.attached == true) {
          final headerPosition = headerRenderBox!.localToGlobal(Offset.zero);
          final headerTop = headerPosition.dy;
          final headerBottom = headerPosition.dy + headerRenderBox.size.height;

          // If header is visible and is the topmost so far
          if (headerBottom > visibleAreaTop && 
              headerTop < topMostPosition && 
              headerTop >= visibleAreaTop - 200) { // Increased tolerance
            topMostPosition = headerTop;
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

            // If game is visible and is the topmost so far
            if (gameBottom > visibleAreaTop && 
                gameTop < topMostPosition && 
                gameTop >= visibleAreaTop - 200) { // Increased tolerance
              topMostPosition = gameTop;
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

    debugPrint('🎯 Found top-most visible item: ${topMostItem?.type} - Round: ${topMostItem?.roundId}, GameIndex: ${topMostItem?.gameIndex}, RelativePos: ${topMostItem?.relativePosition}');
    return topMostItem;
  }

  Future<void> scrollToTopMostVisibleItemAfterViewSwitch(TopMostVisibleItem item) async {
    debugPrint('Starting view switch scroll to: ${item.type} - Round: ${item.roundId}${item.type == TopMostItemType.game ? ', Game: ${item.gameIndex}' : ''}');
    
    await Future.delayed(const Duration(milliseconds: 300));

    if (!mounted) {
      _isViewSwitching = false;
      return;
    }

    try {
      // For game widgets, use enhanced positioning strategy
      if (item.type == TopMostItemType.game) {
        await _scrollToGameWithPrecisePositioning(item);
      } else {
        await _scrollToHeaderWithStandardPositioning(item);
      }

      debugPrint('View switch scroll completed');
    } catch (e) {
      debugPrint('[GamesTourScreen] Error scrolling to top-most item: $e');
    } finally {
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) {
          _isViewSwitching = false;
        }
      });
    }
  }

  // Enhanced game-specific positioning
  Future<void> _scrollToGameWithPrecisePositioning(TopMostVisibleItem item) async {
    if (item.gameIndex == null) return;

    // Step 1: Calculate target position based on new widget heights
    final targetOffset = calculateTargetScrollOffsetForGame(item);
    if (targetOffset != null && _scrollController.hasClients) {
      final maxOffset = _scrollController.position.maxScrollExtent;
      final clampedOffset = targetOffset.clamp(0.0, maxOffset);
      
      debugPrint('Calculated target offset for game: $clampedOffset');
      _scrollController.jumpTo(clampedOffset);
      
      await Future.delayed(const Duration(milliseconds: 300));
    }

    // Step 2: Fine-tune using widget keys with enhanced retry logic
    final gameKey = getGameKey(item.roundId, item.gameIndex!);
    
    bool positionAchieved = false;
    for (int retry = 0; retry < 20; retry++) {
      await Future.delayed(const Duration(milliseconds: 150));

      if (gameKey.currentContext != null) {
        try {
          final renderBox = gameKey.currentContext!.findRenderObject() as RenderBox?;
          if (renderBox?.attached == true) {
            final position = renderBox!.localToGlobal(Offset.zero);
            final topPadding = MediaQuery.of(context).padding.top;
            final appBarHeight = kToolbarHeight;
            final visibleAreaTop = topPadding + appBarHeight;
            
            final currentRelativePosition = position.dy - visibleAreaTop;
            
            // For game widgets, aim to keep them precisely at the top (within 10px tolerance)
            if (currentRelativePosition.abs() <= 10) {
              positionAchieved = true;
              debugPrint('Game widget positioned correctly at relative position: ${currentRelativePosition.toStringAsFixed(1)}');
              break;
            }
            
            // If not positioned correctly, adjust
            if (_scrollController.hasClients) {
              final adjustment = currentRelativePosition; // Scroll by this amount to bring to top
              final currentOffset = _scrollController.offset;
              final newOffset = currentOffset + adjustment;
              final maxOffset = _scrollController.position.maxScrollExtent;
              final clampedOffset = newOffset.clamp(0.0, maxOffset);
              
              debugPrint('Adjusting game position: current: ${currentOffset.toStringAsFixed(1)}, adjustment: ${adjustment.toStringAsFixed(1)}, new: ${clampedOffset.toStringAsFixed(1)}');
              
              _scrollController.jumpTo(clampedOffset);
            }
          }
        } catch (e) {
          debugPrint('[GamesTourScreen] Game positioning error: $e');
        }
      } else {
        debugPrint('Game key not available, retry $retry/20');
      }
    }

    if (!positionAchieved) {
      debugPrint('Warning: Could not achieve precise game positioning after all retries');
    }
  }

  // Standard header positioning (existing logic)
  Future<void> _scrollToHeaderWithStandardPositioning(TopMostVisibleItem item) async {
    final targetOffset = calculateTargetScrollOffset(item);
    if (targetOffset != null && _scrollController.hasClients) {
      final maxOffset = _scrollController.position.maxScrollExtent;
      final clampedOffset = targetOffset.clamp(0.0, maxOffset);
      
      _scrollController.jumpTo(clampedOffset);
      await Future.delayed(const Duration(milliseconds: 200));
    }

    final headerKey = getHeaderKey(item.roundId);
    
    for (int retry = 0; retry < 15; retry++) {
      await Future.delayed(const Duration(milliseconds: 100));

      if (headerKey.currentContext != null) {
        try {
          final renderBox = headerKey.currentContext!.findRenderObject() as RenderBox?;
          if (renderBox?.attached == true) {
            final position = renderBox!.localToGlobal(Offset.zero);
            final topPadding = MediaQuery.of(context).padding.top;
            final appBarHeight = kToolbarHeight;
            final visibleAreaTop = topPadding + appBarHeight;
            
            final currentRelativePosition = position.dy - visibleAreaTop;
            final desiredRelativePosition = item.relativePosition ?? 0;
            final adjustment = currentRelativePosition - desiredRelativePosition;
            
            if (_scrollController.hasClients && adjustment.abs() > 10) {
              final currentOffset = _scrollController.offset;
              final newOffset = currentOffset + adjustment;
              final maxOffset = _scrollController.position.maxScrollExtent;
              final clampedOffset = newOffset.clamp(0.0, maxOffset);
              
              _scrollController.jumpTo(clampedOffset);
            }
            break;
          }
        } catch (e) {
          debugPrint('[GamesTourScreen] Header positioning error: $e');
        }
      }
    }
  }

  // Enhanced calculation specifically for game widgets
  double? calculateTargetScrollOffsetForGame(TopMostVisibleItem item) {
    try {
      final gamesData = _lastGamesData ?? ref.read(gamesTourScreenProvider).valueOrNull;
      if (gamesData == null || item.gameIndex == null) return null;

      final rounds = ref.read(gamesAppBarProvider).value?.gamesAppBarModels ?? [];
      final gamesByRound = <String, List<GamesTourModel>>{};

      for (final game in gamesData.gamesTourModels) {
        gamesByRound.putIfAbsent(game.roundId, () => []).add(game);
      }

      final visibleRounds = rounds
          .where((round) => (gamesByRound[round.id]?.isNotEmpty ?? false))
          .toList()
          .reversed
          .toList();

      double calculatedOffset = 0;
      const double headerHeight = 50;
      const double padding = 16;
      const double gameSpacing = 12;
      
      // Get heights for current view mode
      final bool isCurrentlyChessBoard = ref.read(chessBoardVisibilityProvider);
      final double gameHeight = isCurrentlyChessBoard ? 300 : 120;
      
      calculatedOffset += padding;

      bool foundTargetRound = false;
      
      for (final round in visibleRounds) {
        if (round.id == item.roundId) {
          foundTargetRound = true;
          
          // Add header height
          calculatedOffset += headerHeight;
          
          // Add height for games before the target game
          calculatedOffset += item.gameIndex! * (gameHeight + gameSpacing);
          
          // For game widgets, we want them precisely at the top, so no relative position adjustment
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
      debugPrint('Error calculating target scroll offset for game: $e');
      return null;
    }
  }

  // Calculate target scroll offset based on the item and view mode
  double? calculateTargetScrollOffset(TopMostVisibleItem item) {
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

      final visibleRounds = rounds
          .where((round) => (gamesByRound[round.id]?.isNotEmpty ?? false))
          .toList()
          .reversed
          .toList();

      double calculatedOffset = 0;
      const double headerHeight = 50;
      const double padding = 16;
      
      // Different heights for different view modes
      final bool isCurrentlyChessBoard = ref.read(chessBoardVisibilityProvider);
      final double gameCardHeight = 120;
      final double chessBoardHeight = 300;
      final double gameSpacing = 12;
      
      calculatedOffset += padding;

      bool foundTargetRound = false;
      
      for (final round in visibleRounds) {
        if (round.id == item.roundId) {
          foundTargetRound = true;
          
          // Add header height if we're looking for a game, not the header itself
          if (item.type == TopMostItemType.game) {
            calculatedOffset += headerHeight;
            
            // Add height for games before the target game
            if (item.gameIndex != null) {
              final targetGameHeight = isCurrentlyChessBoard ? chessBoardHeight : gameCardHeight;
              calculatedOffset += item.gameIndex! * (targetGameHeight + gameSpacing);
            }
          }
          
          // Adjust for relative position within the item
          if (item.relativePosition != null && item.relativePosition! > 0) {
            // If the item was partially visible, maintain that partial visibility
            calculatedOffset -= item.relativePosition!;
          }
          
          break;
        }

        if (!foundTargetRound) {
          // Add header height
          calculatedOffset += headerHeight;

          // Add all games height for this round
          final games = gamesByRound[round.id] ?? [];
          final gameHeight = isCurrentlyChessBoard ? chessBoardHeight : gameCardHeight;
          calculatedOffset += games.length * (gameHeight + gameSpacing);
        }
      }

      // Ensure we don't exceed bounds
      if (_scrollController.hasClients) {
        final maxOffset = _scrollController.position.maxScrollExtent;
        calculatedOffset = calculatedOffset.clamp(0.0, maxOffset);
      }

      return calculatedOffset;
    } catch (e) {
      debugPrint('Error calculating target scroll offset: $e');
      return null;
    }
  }

  void checkRoundContentVisibility() {
    final scrollState = ref.read(scrollStateProvider);

    if (!scrollState.isUserScrolling ||
        scrollState.isScrolling ||
        _isViewSwitching ||
        _isProgrammaticScroll) return;

    final gamesData =
        _lastGamesData ?? ref.read(gamesTourScreenProvider).valueOrNull;
    if (gamesData == null) return;

    final gamesByRound = <String, List<GamesTourModel>>{};
    for (final game in gamesData.gamesTourModels) {
      gamesByRound.putIfAbsent(game.roundId, () => []).add(game);
    }

    final rounds = ref.read(gamesAppBarProvider).value?.gamesAppBarModels ?? [];
    final visibleRounds = rounds
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

    final gamesToCheck = roundGames.length > 10
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
    return _headerKeys.putIfAbsent(roundId, () => GlobalKey());
  }

  GlobalKey getGameKey(String roundId, int gameIndex) {
    _gameKeys.putIfAbsent(roundId, () => []);
    final gameList = _gameKeys[roundId]!;

    while (gameList.length <= gameIndex) {
      gameList.add(GlobalKey());
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
        // Remove animation - instant jump to position
        _scrollController.jumpTo(position);
      }

      bool found = false;

      for (int retry = 0; retry < 30; retry++) {
        await Future.delayed(const Duration(milliseconds: 50));

        if (headerKey.currentContext != null) {
          try {
            // Remove animation - instant scroll
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

      final visibleRounds = rounds
          .where((round) => (gamesByRound[round.id]?.isNotEmpty ?? false))
          .toList()
          .reversed
          .toList();

      double position = 0;
      const double headerHeight = 50;
      final double gameHeight = ref.read(chessBoardVisibilityProvider) ? 300 : 120;
      const double padding = 16;
      position += padding;

      for (final round in visibleRounds) {
        if (round.id == roundId) {
          return position;
        }

        position += headerHeight;

        final games = gamesByRound[round.id] ?? [];
        position += games.length * (gameHeight + 12);

        if (_scrollController.hasClients &&
            position > _scrollController.position.maxScrollExtent) {
          return _scrollController.position.maxScrollExtent;
        }
      }

      return null;
    } catch (e) {
      debugPrint('Error calculating scroll position: $e');
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