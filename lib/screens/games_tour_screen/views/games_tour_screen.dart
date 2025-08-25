import 'dart:async';
import 'package:chessever2/screens/games_tour_screen/providers/games_tour_scroll_state_provider.dart';
import 'package:chessever2/screens/games_tour_screen/providers/games_tour_visibility_provider.dart';
import 'package:chessever2/screens/games_tour_screen/widgets/game_card_wrapper_widget.dart';
import 'package:chessever2/screens/games_tour_screen/widgets/game_error_widget.dart';
import 'package:chessever2/screens/games_tour_screen/widgets/round_header_widget.dart';
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

import '../../tournaments/model/games_app_bar_view_model.dart';

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

  String? _topVisibleGameId;
  bool _isViewSwitching = false;
  bool _isProgrammaticScroll = false;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _setupScrollListener();
    _setupViewSwitchListener();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _synchronizeInitialSelection();
    });
  }

  void _synchronizeInitialSelection() {
    if (!mounted || _isInitialized) return;

    final gamesAppBarAsync = ref.read(gamesAppBarProvider);
    final gamesTourAsync = ref.read(gamesTourScreenProvider);

    if (!gamesAppBarAsync.hasValue || !gamesTourAsync.hasValue) {
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted && !_isInitialized) _synchronizeInitialSelection();
      });
      return;
    }

    final gamesData = gamesTourAsync.valueOrNull;
    final appBarData = gamesAppBarAsync.valueOrNull;

    if (gamesData == null || appBarData == null) {
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted && !_isInitialized) _synchronizeInitialSelection();
      });
      return;
    }

    final selectedRoundId = appBarData.selectedId;
    debugPrint('🎯 Selected round ID from dropdown: $selectedRoundId');

    final gamesByRound = <String, List<GamesTourModel>>{};
    for (final game in gamesData.gamesTourModels) {
      gamesByRound.putIfAbsent(game.roundId, () => []).add(game);
    }

    String? targetRoundId;

    if (selectedRoundId != null &&
        gamesByRound[selectedRoundId]?.isNotEmpty == true) {
      targetRoundId = selectedRoundId;
      debugPrint('🎯 Using selected round: $targetRoundId');
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

    if (targetRoundId != null) {
      _isInitialized = true;

      ref.read(scrollStateProvider.notifier).setInitialScrollPerformed();
      ref.read(scrollStateProvider.notifier).updateSelectedRound(targetRoundId);
      ref.read(scrollStateProvider.notifier).setUserScrolling(false);

      Future.delayed(const Duration(milliseconds: 1000), () {
        if (mounted) {
          _scrollToRound(targetRoundId!);
        }
      });
    }
  }

  void _setupScrollListener() {
    _scrollController.addListener(() {
      if (!_isScrolling && !_isViewSwitching && !_isProgrammaticScroll) {
        _isScrolling = true;
        ref.read(scrollStateProvider.notifier).setUserScrolling(true);
      }

      _visibilityCheckTimer?.cancel();
      _visibilityCheckTimer = Timer(const Duration(milliseconds: 100), () {
        if (mounted && !_isViewSwitching && !_isProgrammaticScroll) {
          _checkRoundContentVisibility();
        }
      });
    });
  }

  void _setupViewSwitchListener() {
    ref.listenManual(chessBoardVisibilityProvider, (previous, next) {
      if (previous != null && previous != next) {
        _handleViewSwitch();
      }
    });
  }

  void _handleViewSwitch() {
    if (!mounted || !_scrollController.hasClients) return;

    _isViewSwitching = true;

    _topVisibleGameId = _findTopVisibleGameId();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _topVisibleGameId != null) {
        _scrollToGameAfterViewSwitch(_topVisibleGameId!);
      }
    });
  }

  String? _findTopVisibleGameId() {
    final gamesData =
        _lastGamesData ?? ref.read(gamesTourScreenProvider).valueOrNull;
    if (gamesData == null) return null;

    final screenHeight = MediaQuery.of(context).size.height;
    final topPadding = MediaQuery.of(context).padding.top;
    final appBarHeight = kToolbarHeight;
    final visibleAreaTop = topPadding + appBarHeight + 50;
    final gamesByRound = <String, List<GamesTourModel>>{};
    for (final game in gamesData.gamesTourModels) {
      gamesByRound.putIfAbsent(game.roundId, () => []).add(game);
    }

    for (final roundId in gamesByRound.keys) {
      final roundGames = gamesByRound[roundId] ?? [];

      for (int gameIndex = 0; gameIndex < roundGames.length; gameIndex++) {
        final gameKey = _getGameKey(roundId, gameIndex);
        final gameContext = gameKey.currentContext;

        if (gameContext != null) {
          final gameRenderBox = gameContext.findRenderObject() as RenderBox?;
          if (gameRenderBox?.attached == true) {
            final gamePosition = gameRenderBox!.localToGlobal(Offset.zero);
            final gameSize = gameRenderBox.size;

            final gameTop = gamePosition.dy;
            final gameBottom = gamePosition.dy + gameSize.height;

            if (gameBottom > visibleAreaTop && gameTop < visibleAreaTop + 100) {
              return roundGames[gameIndex].gameId;
            }
          }
        }
      }
    }

    return null;
  }

  Future<void> _scrollToGameAfterViewSwitch(String gameId) async {
    await Future.delayed(const Duration(milliseconds: 300));

    if (!mounted) return;

    final gamesData =
        _lastGamesData ?? ref.read(gamesTourScreenProvider).valueOrNull;
    if (gamesData == null) return;

    GamesTourModel? targetGame;
    String? targetRoundId;
    int? targetGameIndex;

    final gamesByRound = <String, List<GamesTourModel>>{};
    for (final game in gamesData.gamesTourModels) {
      gamesByRound.putIfAbsent(game.roundId, () => []).add(game);
      if (game.gameId == gameId) {
        targetGame = game;
        targetRoundId = game.roundId;
      }
    }

    if (targetGame == null || targetRoundId == null) {
      _isViewSwitching = false;
      return;
    }

    final roundGames = gamesByRound[targetRoundId] ?? [];
    targetGameIndex = roundGames.indexOf(targetGame);

    if (targetGameIndex == -1) {
      _isViewSwitching = false;
      return;
    }

    final gameKey = _getGameKey(targetRoundId, targetGameIndex);

    for (int retry = 0; retry < 20; retry++) {
      await Future.delayed(const Duration(milliseconds: 100));

      if (gameKey.currentContext != null) {
        try {
          await Scrollable.ensureVisible(
            gameKey.currentContext!,
            alignment: 0.0,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
          );
          break;
        } catch (e) {
          debugPrint('[GamesTourScreen] View switch scroll error: $e');
        }
      }
    }

    Future.delayed(const Duration(milliseconds: 500), () {
      _isViewSwitching = false;
      _topVisibleGameId = null;
    });
  }

  void _checkRoundContentVisibility() {
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

      final visibilityScore = _calculateRoundContentVisibility(
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
        debugPrint(
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

    final headerKey = _getHeaderKey(roundId);
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
      final gameKey = _getGameKey(roundId, gameIndex);
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

  GlobalKey _getHeaderKey(String roundId) {
    return _headerKeys.putIfAbsent(roundId, () => GlobalKey());
  }

  GlobalKey _getGameKey(String roundId, int gameIndex) {
    _gameKeys.putIfAbsent(roundId, () => []);
    final gameList = _gameKeys[roundId]!;

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
            _scrollToRound(currentSelected);
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

  Future<void> _scrollToRound(String roundId) async {
    if (!mounted || _isViewSwitching) return;

    _isProgrammaticScroll = true;

    ref.read(scrollStateProvider.notifier).setScrolling(true);
    ref.read(scrollStateProvider.notifier).setUserScrolling(false);
    ref.read(scrollStateProvider.notifier).updateSelectedRound(roundId);

    try {
      if (!_scrollController.hasClients) return;

      final headerKey = _getHeaderKey(roundId);

      final position = _calculateScrollPositionForRound(roundId);
      if (position != null && position >= 0) {
        await _scrollController.animateTo(
          position,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeInOut,
        );
      }

      bool found = false;

      for (int retry = 0; retry < 30; retry++) {
        await Future.delayed(const Duration(milliseconds: 50));

        if (headerKey.currentContext != null) {
          try {
            await Scrollable.ensureVisible(
              headerKey.currentContext!,
              alignment: 0.0,
              duration: const Duration(milliseconds: 400),
              curve: Curves.easeInOut,
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
          debugPrint(' Key not found on retry $retry for round $roundId');
        }
      }

      if (!found) {
        debugPrint(' Failed to scroll to round: $roundId after all attempts');
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

  double? _calculateScrollPositionForRound(String roundId) {
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
      const double headerHeight = 50;
      const double gameHeight = 120;
      const double padding = 16;
      position += padding;

      for (final round in visibleRounds) {
        debugPrint('🎯 Position before ${round.name} (${round.id}): $position');
        if (round.id == roundId) {
          return position;
        }

        position += headerHeight;

        final games = gamesByRound[round.id] ?? [];
        position += games.length * (gameHeight + 12);

        if (position > _scrollController.position.maxScrollExtent) {
          return _scrollController.position.maxScrollExtent;
        }
      }

      return null;
    } catch (e) {
      debugPrint('Error calculating scroll position: $e');
      return null;
    }
  }

  Future<void> _handleRefresh(
    AsyncValue gamesAppBarAsync,
    AsyncValue<GamesScreenModel> gamesTourAsync,
  ) async {
    debugPrint('[GamesTourScreen] Refresh triggered');
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

    _isInitialized = false;
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) {
        _synchronizeInitialSelection();
      }
    });
  }
}

class GamesTourContentBody extends ConsumerWidget {
  final AsyncValue gamesAppBarAsync;
  final AsyncValue<GamesScreenModel> gamesTourAsync;
  final bool isChessBoardVisible;
  final ScrollController scrollController;
  final Map<String, GlobalKey> headerKeys;
  final Map<String, List<GlobalKey>> gameKeys;
  final GlobalKey Function(String) getHeaderKey;
  final GlobalKey Function(String, int) getGameKey;
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

    if (tourId == null ||
        tourDetails.isLoading ||
        !tourDetails.hasValue ||
        tourDetails.valueOrNull?.aboutTourModel == null) {
      return const TourLoadingWidget();
    }

    if (tourDetails.hasError) {
      return GamesErrorWidget(
        errorMessage: 'Error loading tournament: ${tourDetails.error}',
      );
    }

    if (gamesTourAsync.hasValue) {
      onGamesDataUpdate(gamesTourAsync.valueOrNull);
    }

    if ((gamesAppBarAsync.isLoading || gamesTourAsync.isLoading) &&
        lastGamesData == null) {
      return const TourLoadingWidget();
    }

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
    final reversedRounds = rounds.reversed.toList();
    final roundPositionMap = <String, int>{};
    for (int i = 0; i < reversedRounds.length; i++) {
      roundPositionMap[reversedRounds[i].id] = i;
    }

    int itemCount = 0;
    for (final round in reversedRounds) {
      itemCount += 1;
      itemCount += gamesByRound[round.id]?.length ?? 0;
    }

    return ListView.builder(
      controller: scrollController,
      cacheExtent: MediaQuery.of(context).size.height * 2,
      padding: EdgeInsets.only(
        left: 20.sp,
        right: 20.sp,
        top: 16.sp,
        bottom: MediaQuery.of(context).viewPadding.bottom,
      ),
      itemCount: itemCount,
      itemBuilder:
          (context, index) => GameListItemBuilder(
            index: index,
            rounds: reversedRounds,
            originalRounds: rounds,
            gamesByRound: gamesByRound,
            gamesData: gamesData,
            isChessBoardVisible: isChessBoardVisible,
            getHeaderKey: getHeaderKey,
            getGameKey: getGameKey,
            roundPositionMap: roundPositionMap,
          ),
    );
  }
}

class GameListItemBuilder extends ConsumerWidget {
  final int index;
  final List rounds;
  final List originalRounds;
  final Map<String, List<GamesTourModel>> gamesByRound;
  final GamesScreenModel gamesData;
  final bool isChessBoardVisible;
  final GlobalKey Function(String) getHeaderKey;
  final GlobalKey Function(String, int) getGameKey;
  final Map<String, int> roundPositionMap;

  const GameListItemBuilder({
    super.key,
    required this.index,
    required this.rounds,
    required this.originalRounds,
    required this.gamesByRound,
    required this.gamesData,
    required this.isChessBoardVisible,
    required this.getHeaderKey,
    required this.getGameKey,
    required this.roundPositionMap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    int currentIndex = 0;

    for (final round in rounds) {
      final roundGames = gamesByRound[round.id] ?? [];

      if (index == currentIndex) {
        return RoundHeader(
          round: round,
          roundGames: roundGames,
          headerKey: getHeaderKey(round.id),
        );
      }
      currentIndex += 1;

      if (index < currentIndex + roundGames.length) {
        final gameIndexInRound = index - currentIndex;
        final game = roundGames[gameIndexInRound];
        final globalGameIndex = gamesData.gamesTourModels.indexOf(game);

        return Container(
          key: getGameKey(
            round.id,
            gameIndexInRound,
          ),
          child: Padding(
            padding: EdgeInsets.only(bottom: 12.sp),
            child: GameCardWrapperWidget(
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
