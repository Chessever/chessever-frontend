import 'dart:async';

import 'package:chessever2/screens/gamesTourScreen/models/scroll_state_model.dart';
import 'package:chessever2/screens/gamesTourScreen/providers/games_tour_scroll_state_provider.dart';
import 'package:chessever2/screens/gamesTourScreen/providers/games_tour_visibility_provider.dart';

import 'package:chessever2/screens/gamesTourScreen/widgets/game_card_wrapper_widget.dart';
import 'package:chessever2/screens/gamesTourScreen/widgets/game_error_widget.dart';
import 'package:chessever2/screens/gamesTourScreen/widgets/round_header_widget.dart';
import 'package:chessever2/screens/tournaments/model/games_tour_model.dart';
import 'package:chessever2/screens/tournaments/providers/chess_board_visibility_provider.dart';
import 'package:chessever2/screens/tournaments/providers/games_app_bar_provider.dart';
import 'package:chessever2/screens/tournaments/providers/games_tour_screen_provider.dart';
import 'package:chessever2/screens/tournaments/providers/tour_detail_screen_provider.dart';
import 'package:chessever2/screens/tournaments/widget/empty_widget.dart';
import 'package:chessever2/screens/tournaments/widget/tour_loading_widget.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class GamesTourScreen extends ConsumerStatefulWidget {
  const GamesTourScreen({super.key});

  @override
  ConsumerState<ConsumerStatefulWidget> createState() =>
      _GamesTourScreenState();
}

class _GamesTourScreenState extends ConsumerState<GamesTourScreen> {
  late ScrollController _scrollController;
  final Map<String, GlobalKey> _headerKeys = {};
  final Map<String, List<GlobalKey>> _gameKeys =
      {}; // Track game keys per round
  GamesScreenModel? _lastGamesData;

  // Performance optimization
  Timer? _visibilityCheckTimer;
  bool _isScrolling = false;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _setupScrollListener();
  }

  void _setupScrollListener() {
    _scrollController.addListener(() {
      if (!_isScrolling) {
        _isScrolling = true;
        ref.read(scrollStateProvider.notifier).setUserScrolling(true);
      }

      // Debounce visibility checks for better performance
      _visibilityCheckTimer?.cancel();
      _visibilityCheckTimer = Timer(const Duration(milliseconds: 100), () {
        if (mounted) {
          _checkRoundContentVisibility();
        }
      });
    });
  }

  void _checkRoundContentVisibility() {
    final scrollState = ref.read(scrollStateProvider);

    // Only check during user scrolling, not programmatic scrolling
    if (!scrollState.isUserScrolling || scrollState.isScrolling) return;

    final gamesData =
        _lastGamesData ?? ref.read(gamesTourScreenProvider).valueOrNull;
    if (gamesData == null) return;

    // Group games by round
    final gamesByRound = <String, List<GamesTourModel>>{};
    for (final game in gamesData.gamesTourModels) {
      gamesByRound.putIfAbsent(game.roundId, () => []).add(game);
    }

    String? mostVisibleRound;
    double maxVisibilityScore = 0;

    // Check each round's content visibility
    for (final roundId in gamesByRound.keys) {
      final roundGames = gamesByRound[roundId] ?? [];
      if (roundGames.isEmpty) continue;

      final visibilityScore = _calculateRoundContentVisibility(
        roundId,
        roundGames,
      );

      if (visibilityScore > maxVisibilityScore) {
        maxVisibilityScore = visibilityScore;
        mostVisibleRound = roundId;
      }
    }

    // Update only if we have a significant visibility score
    if (mostVisibleRound != null && maxVisibilityScore > 0.1) {
      final currentVisible = ref.read(currentVisibleRoundProvider);
      if (currentVisible != mostVisibleRound) {
        print(
          '🎯 Most visible round: $mostVisibleRound (score: ${maxVisibilityScore.toStringAsFixed(2)})',
        );
        ref
            .read(roundVisibilityNotifierProvider)
            .updateVisibleRound(mostVisibleRound);
      }
    }
  }

  double _calculateRoundContentVisibility(
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

    // Check header visibility first
    final headerKey = _getHeaderKey(roundId);
    final headerContext = headerKey.currentContext;
    if (headerContext != null) {
      final headerRenderBox = headerContext.findRenderObject() as RenderBox?;
      if (headerRenderBox?.attached == true) {
        final headerPosition = headerRenderBox!.localToGlobal(Offset.zero);
        final headerSize = headerRenderBox.size;

        totalRoundHeight += headerSize.height;

        // Calculate visible portion of header
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

    // Check game cards visibility (sample some games for performance)
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
      final gameKey = _getGameKey(roundId, gameIndex);
      final gameContext = gameKey.currentContext;

      if (gameContext != null) {
        final gameRenderBox = gameContext.findRenderObject() as RenderBox?;
        if (gameRenderBox?.attached == true) {
          final gamePosition = gameRenderBox!.localToGlobal(Offset.zero);
          final gameSize = gameRenderBox.size;

          totalRoundHeight += gameSize.height;

          // Calculate visible portion of game card
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

    // Calculate base visibility score
    double visibilityScore = totalVisibleHeight / totalRoundHeight;

    // Bonus for having content in the upper portion of screen (more natural)
    final _headerKey = _getHeaderKey(roundId);
    final _headerContext = headerKey.currentContext;

    if (headerContext != null) {
      final headerRenderBox = headerContext.findRenderObject() as RenderBox?;
      if (headerRenderBox?.attached == true) {
        final headerPosition = headerRenderBox!.localToGlobal(Offset.zero);

        // Bonus if header or content is in upper 60% of visible area
        if (headerPosition.dy >= visibleAreaTop &&
            headerPosition.dy <= visibleAreaTop + (visibleAreaHeight * 0.6)) {
          visibilityScore += 0.2;
        }
      }
    }

    return visibilityScore.clamp(0.0, 1.0);
  }

  GlobalKey _getHeaderKey(String roundId) {
    return _headerKeys.putIfAbsent(roundId, () => GlobalKey());
  }

  GlobalKey _getGameKey(String roundId, int gameIndex) {
    _gameKeys.putIfAbsent(roundId, () => []);
    final gameList = _gameKeys[roundId]!;

    // Extend list if needed
    while (gameList.length <= gameIndex) {
      gameList.add(GlobalKey());
    }

    return gameList[gameIndex];
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
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isChessBoardVisible = ref.watch(chessBoardVisibilityProvider);
    final gamesAppBarAsync = ref.watch(gamesAppBarProvider);
    final gamesTourAsync = ref.watch(gamesTourScreenProvider);
    final scrollState = ref.watch(scrollStateProvider);

    // Listen for visible round changes and update dropdown
    ref.listen<String?>(currentVisibleRoundProvider, (previous, next) {
      if (next != null && next != previous) {
        final scrollState = ref.read(scrollStateProvider);
        final currentSelected = gamesAppBarAsync.valueOrNull?.selectedId;

        if (scrollState.isUserScrolling &&
            !scrollState.isScrolling &&
            currentSelected != next) {
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

    // Handle scroll logic after build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _handleScrollLogic(gamesAppBarAsync, gamesTourAsync, scrollState);
      }
    });

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification is ScrollStartNotification) {
          _isScrolling = true;
          ref.read(scrollStateProvider.notifier).setUserScrolling(true);
        } else if (notification is ScrollEndNotification) {
          _isScrolling = false;
          // Final check when scrolling ends
          Future.delayed(const Duration(milliseconds: 50), () {
            if (mounted) {
              _checkRoundContentVisibility();
              ref.read(scrollStateProvider.notifier).setUserScrolling(false);
            }
          });
        }

        return false;
      },
      child: RefreshIndicator(
        onRefresh: () => _handleRefresh(gamesAppBarAsync, gamesTourAsync),
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
          getHeaderKey: _getHeaderKey,
          getGameKey: _getGameKey,
          lastGamesData: _lastGamesData,
          onGamesDataUpdate: (data) => _lastGamesData = data,
        ),
      ),
    );
  }

  // Rest of the methods remain the same...
  void _handleScrollLogic(
    AsyncValue gamesAppBarAsync,
    AsyncValue<GamesScreenModel> gamesTourAsync,
    ScrollState scrollState,
  ) {
    final current = gamesAppBarAsync.valueOrNull?.selectedId;

    if (!scrollState.hasPerformedInitialScroll &&
        gamesAppBarAsync.hasValue &&
        gamesTourAsync.hasValue &&
        current != null) {
      _performInitialScroll(current);
      return;
    }

    if (current != null &&
        scrollState.hasPerformedInitialScroll &&
        current != scrollState.lastSelectedRound &&
        !scrollState.isUserScrolling) {
      _performRoundChangeScroll(current);
    }
  }

  void _performInitialScroll(String roundId) {
    Future.microtask(() {
      if (mounted) {
        ref.read(scrollStateProvider.notifier).setInitialScrollPerformed();
        ref.read(scrollStateProvider.notifier).updateSelectedRound(roundId);
        ref.read(scrollStateProvider.notifier).setPendingScroll(roundId);

        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted) {
            _scrollToRound(roundId);
          }
        });
      }
    });
  }

  void _performRoundChangeScroll(String roundId) {
    Future.microtask(() {
      if (mounted) {
        ref.read(scrollStateProvider.notifier).updateSelectedRound(roundId);
        ref.read(scrollStateProvider.notifier).setPendingScroll(roundId);

        Future.delayed(const Duration(milliseconds: 100), () {
          if (mounted) {
            _scrollToRound(roundId);
          }
        });
      }
    });
  }

  Future<void> _scrollToRound(String roundId) async {
    final scrollState = ref.read(scrollStateProvider);
    if (scrollState.isScrolling || !mounted) return;

    Future.microtask(() {
      if (mounted) {
        ref.read(scrollStateProvider.notifier).setScrolling(true);
        ref.read(scrollStateProvider.notifier).setUserScrolling(false);
      }
    });

    try {
      if (!_scrollController.hasClients) return;

      final headerKey = _getHeaderKey(roundId);

      for (int retry = 0; retry < 30; retry++) {
        await Future.delayed(const Duration(milliseconds: 100));

        if (headerKey.currentContext != null) {
          await Scrollable.ensureVisible(
            headerKey.currentContext!,
            alignment: 0.0,
            duration: const Duration(milliseconds: 0),
            curve: Curves.easeInOut,
            alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
          );
          break;
        }
      }
    } catch (e) {
      debugPrint('[GamesTourScreen] Scroll error: $e');
    } finally {
      Future.microtask(() {
        if (mounted) {
          ref.read(scrollStateProvider.notifier).setScrolling(false);
          ref.read(scrollStateProvider.notifier).setPendingScroll(null);
        }
      });
    }
  }

  Future<void> _handleRefresh(
    AsyncValue gamesAppBarAsync,
    AsyncValue<GamesScreenModel> gamesTourAsync,
  ) async {
    debugPrint('[GamesTourScreen] 🔄 Refresh triggered');
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
      futures.add(
        ref.read(gamesTourScreenProvider.notifier).refreshGames(),
      );
    }

    if (futures.isNotEmpty) {
      await Future.wait(futures);
    }
  }
}

class GamesTourContentBody extends ConsumerWidget {
  final AsyncValue gamesAppBarAsync;
  final AsyncValue<GamesScreenModel> gamesTourAsync;
  final bool isChessBoardVisible;
  final ScrollController scrollController;
  final Map<String, GlobalKey> headerKeys;
  final Map<String, List<GlobalKey>> gameKeys; // New parameter
  final GlobalKey Function(String) getHeaderKey;
  final GlobalKey Function(String, int) getGameKey; // New parameter
  final GamesScreenModel? lastGamesData;
  final Function(GamesScreenModel?) onGamesDataUpdate;

  const GamesTourContentBody({
    super.key,
    required this.gamesAppBarAsync,
    required this.gamesTourAsync,
    required this.isChessBoardVisible,
    required this.scrollController,
    required this.headerKeys,
    required this.gameKeys,
    required this.getHeaderKey,
    required this.getGameKey,
    required this.lastGamesData,
    required this.onGamesDataUpdate,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tourId = ref.watch(selectedTourIdProvider);
    final tourDetails = ref.watch(tourDetailScreenProvider);

    // Loading states
    if (tourId == null ||
        tourDetails.isLoading ||
        !tourDetails.hasValue ||
        tourDetails.valueOrNull?.aboutTourModel == null) {
      return const TourLoadingWidget();
    }

    // Error states
    if (tourDetails.hasError) {
      return GamesErrorWidget(
        errorMessage: 'Error loading tournament: ${tourDetails.error}',
      );
    }

    // Update cached games data
    if (gamesTourAsync.hasValue) {
      onGamesDataUpdate(gamesTourAsync.valueOrNull);
    }

    // Loading with cached data
    if ((gamesAppBarAsync.isLoading || gamesTourAsync.isLoading) &&
        lastGamesData == null) {
      return const TourLoadingWidget();
    }

    // Error handling
    if (gamesAppBarAsync.hasError || gamesTourAsync.hasError) {
      return GamesErrorWidget(
        errorMessage:
            gamesAppBarAsync.error?.toString() ??
            gamesTourAsync.error?.toString() ??
            "An error occurred",
      );
    }

    final gamesData = lastGamesData ?? gamesTourAsync.valueOrNull;
    if (gamesData == null) return const TourLoadingWidget();

    // Empty state
    if (gamesData.gamesTourModels.isEmpty && !gamesTourAsync.isLoading) {
      return const Center(
        child: EmptyWidget(
          title:
              "No games available yet. Check back soon or set a\nreminder for updates.",
        ),
      );
    }

    return GamesTourMainContent(
      gamesData: gamesData,
      isChessBoardVisible: isChessBoardVisible,
      scrollController: scrollController,
      headerKeys: headerKeys,
      gameKeys: gameKeys,
      getHeaderKey: getHeaderKey,
      getGameKey: getGameKey,
    );
  }
}

class GamesTourMainContent extends ConsumerWidget {
  final GamesScreenModel gamesData;
  final bool isChessBoardVisible;
  final ScrollController scrollController;
  final Map<String, GlobalKey> headerKeys;
  final Map<String, List<GlobalKey>> gameKeys;
  final GlobalKey Function(String) getHeaderKey;
  final GlobalKey Function(String, int) getGameKey;

  const GamesTourMainContent({
    super.key,
    required this.gamesData,
    required this.isChessBoardVisible,
    required this.scrollController,
    required this.headerKeys,
    required this.gameKeys,
    required this.getHeaderKey,
    required this.getGameKey,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rounds =
        ref.watch(gamesAppBarProvider).value?.gamesAppBarModels ?? [];

    // Group games by round
    final gamesByRound = <String, List<GamesTourModel>>{};
    for (final game in gamesData.gamesTourModels) {
      gamesByRound.putIfAbsent(game.roundId, () => []).add(game);
    }

    final visibleRounds =
        rounds
            .where((round) => (gamesByRound[round.id]?.isNotEmpty ?? false))
            .toList();

    return GamesListView(
      rounds: visibleRounds,
      gamesByRound: gamesByRound,
      gamesData: gamesData,
      isChessBoardVisible: isChessBoardVisible,
      scrollController: scrollController,
      headerKeys: headerKeys,
      gameKeys: gameKeys,
      getHeaderKey: getHeaderKey,
      getGameKey: getGameKey,
    );
  }
}

class GamesListView extends ConsumerWidget {
  final List rounds;
  final Map<String, List<GamesTourModel>> gamesByRound;
  final GamesScreenModel gamesData;
  final bool isChessBoardVisible;
  final ScrollController scrollController;
  final Map<String, GlobalKey> headerKeys;
  final Map<String, List<GlobalKey>> gameKeys;
  final GlobalKey Function(String) getHeaderKey;
  final GlobalKey Function(String, int) getGameKey;

  const GamesListView({
    super.key,
    required this.rounds,
    required this.gamesByRound,
    required this.gamesData,
    required this.isChessBoardVisible,
    required this.scrollController,
    required this.headerKeys,
    required this.gameKeys,
    required this.getHeaderKey,
    required this.getGameKey,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Calculate total items (all rounds are always expanded)
    int itemCount = 0;
    for (final round in rounds) {
      itemCount += 1; // Header
      itemCount += gamesByRound[round.id]?.length ?? 0; // Games
    }

    return ListView.builder(
      controller: scrollController,
      padding: EdgeInsets.only(
        left: 20.sp,
        right: 20.sp,
        top: 16.sp,
        bottom: MediaQuery.of(context).viewPadding.bottom,
      ),
      cacheExtent: 30000.0,
      itemCount: itemCount,
      itemBuilder:
          (context, index) => GameListItemBuilder(
            index: index,
            rounds: rounds,
            gamesByRound: gamesByRound,
            gamesData: gamesData,
            isChessBoardVisible: isChessBoardVisible,
            getHeaderKey: getHeaderKey,
            getGameKey: getGameKey,
          ),
    );
  }
}

class GameListItemBuilder extends ConsumerWidget {
  final int index;
  final List rounds;
  final Map<String, List<GamesTourModel>> gamesByRound;
  final GamesScreenModel gamesData;
  final bool isChessBoardVisible;
  final GlobalKey Function(String) getHeaderKey;
  final GlobalKey Function(String, int) getGameKey;

  const GameListItemBuilder({
    super.key,
    required this.index,
    required this.rounds,
    required this.gamesByRound,
    required this.gamesData,
    required this.isChessBoardVisible,
    required this.getHeaderKey,
    required this.getGameKey,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    int currentIndex = 0;

    for (final round in rounds) {
      final roundGames = gamesByRound[round.id] ?? [];

      // Check if this is the header
      if (index == currentIndex) {
        return RoundHeader(
          round: round,
          roundGames: roundGames,
          headerKey: getHeaderKey(round.id),
        );
      }
      currentIndex += 1;

      // Show games (always expanded now)
      if (index < currentIndex + roundGames.length) {
        final gameIndexInRound = index - currentIndex;
        final game = roundGames[gameIndexInRound];
        final globalGameIndex = gamesData.gamesTourModels.indexOf(game);

        return Container(
          key: getGameKey(round.id, gameIndexInRound), // Add game key here
          child: Padding(
            padding: EdgeInsets.only(bottom: 12.sp),
            child: GameCardWrapper(
              game: game,
              gamesData: gamesData,
              gameIndex: globalGameIndex,
              isChessBoardVisible: isChessBoardVisible,
            ),
          ),
        );
      }
      currentIndex += roundGames.length;
    }

    return const SizedBox.shrink();
  }
}
