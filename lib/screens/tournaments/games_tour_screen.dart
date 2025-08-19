import 'package:chessever2/screens/chessboard/chess_board_screen.dart';
import 'package:chessever2/screens/chessboard/provider/chess_board_screen_provider.dart';
import 'package:chessever2/screens/chessboard/widgets/chess_board_widget.dart';
import 'package:chessever2/screens/tournaments/model/games_tour_model.dart';
import 'package:chessever2/screens/tournaments/providers/chess_board_visibility_provider.dart';
import 'package:chessever2/screens/tournaments/providers/games_app_bar_provider.dart';
import 'package:chessever2/screens/tournaments/providers/games_tour_screen_provider.dart';
import 'package:chessever2/screens/tournaments/providers/tour_detail_screen_provider.dart';
import 'package:chessever2/screens/tournaments/widget/empty_widget.dart';
import 'package:chessever2/screens/tournaments/widget/game_card.dart';
import 'package:chessever2/screens/tournaments/widget/tour_loading_widget.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/generic_error_widget.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

// Provider for managing round expansion states
final roundExpansionProvider = StateNotifierProvider.autoDispose<
  RoundExpansionNotifier,
  Map<String, bool>
>((ref) => RoundExpansionNotifier());

class RoundExpansionNotifier extends StateNotifier<Map<String, bool>> {
  RoundExpansionNotifier() : super({});

  void initializeExpansion(List<dynamic> rounds, String? selectedRoundId) {
    final newState = <String, bool>{};

    // Collapse all rounds by default
    for (final round in rounds) {
      newState[round.id] = false;
    }

    // Expand only the selected/live round
    if (selectedRoundId != null) {
      newState[selectedRoundId] = true;
    }

    state = newState;
  }

  void toggleRound(String roundId) {
    state = {
      ...state,
      roundId: !(state[roundId] ?? false),
    };
  }

  void collapseAllExcept(String roundId) {
    final newState = <String, bool>{};
    for (final key in state.keys) {
      newState[key] = key == roundId;
    }
    state = newState;
  }

  bool isExpanded(String roundId) {
    return state[roundId] ?? false;
  }
}

// Provider for managing scroll state
final scrollStateProvider =
    StateNotifierProvider.autoDispose<ScrollStateNotifier, ScrollState>(
      (ref) => ScrollStateNotifier(),
    );

class ScrollState {
  final bool hasPerformedInitialScroll;
  final String? lastSelectedRound;
  final String? pendingScrollToRound;
  final bool isScrolling;

  const ScrollState({
    this.hasPerformedInitialScroll = false,
    this.lastSelectedRound,
    this.pendingScrollToRound,
    this.isScrolling = false,
  });

  ScrollState copyWith({
    bool? hasPerformedInitialScroll,
    String? lastSelectedRound,
    String? pendingScrollToRound,
    bool? isScrolling,
  }) {
    return ScrollState(
      hasPerformedInitialScroll:
          hasPerformedInitialScroll ?? this.hasPerformedInitialScroll,
      lastSelectedRound: lastSelectedRound ?? this.lastSelectedRound,
      pendingScrollToRound: pendingScrollToRound ?? this.pendingScrollToRound,
      isScrolling: isScrolling ?? this.isScrolling,
    );
  }
}

class ScrollStateNotifier extends StateNotifier<ScrollState> {
  ScrollStateNotifier() : super(const ScrollState());

  void setInitialScrollPerformed() {
    state = state.copyWith(hasPerformedInitialScroll: true);
  }

  void updateSelectedRound(String? roundId) {
    state = state.copyWith(lastSelectedRound: roundId);
  }

  void setPendingScroll(String? roundId) {
    state = state.copyWith(pendingScrollToRound: roundId);
  }

  void setScrolling(bool isScrolling) {
    state = state.copyWith(isScrolling: isScrolling);
  }

  void reset() {
    state = const ScrollState();
  }
}

class GamesTourScreen extends ConsumerWidget {
  const GamesTourScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return const GamesTourScreenContent();
  }
}

class GamesTourScreenContent extends ConsumerStatefulWidget {
  const GamesTourScreenContent({super.key});

  @override
  ConsumerState<GamesTourScreenContent> createState() =>
      _GamesTourScreenContentState();
}

class _GamesTourScreenContentState
    extends ConsumerState<GamesTourScreenContent> {
  late ScrollController _scrollController;
  final Map<String, GlobalKey> _headerKeys = {};
  GamesScreenModel? _lastGamesData;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Reset state when dependencies change - use Future.microtask to avoid build-time modifications
    Future.microtask(() {
      if (mounted) {
        ref.read(scrollStateProvider.notifier).reset();
        _headerKeys.clear();
      }
    });
  }

  GlobalKey _getHeaderKey(String roundId) {
    return _headerKeys.putIfAbsent(roundId, () => GlobalKey());
  }

  @override
  Widget build(BuildContext context) {
    // Watch providers
    final isChessBoardVisible = ref.watch(chessBoardVisibilityProvider);
    final gamesAppBarAsync = ref.watch(gamesAppBarProvider);
    final gamesTourAsync = ref.watch(gamesTourScreenProvider);
    final scrollState = ref.watch(scrollStateProvider);

    // Handle scroll logic after build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _handleScrollLogic(gamesAppBarAsync, gamesTourAsync, scrollState);
      }
    });

    return RefreshIndicator(
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
        getHeaderKey: _getHeaderKey,
        lastGamesData: _lastGamesData,
        onGamesDataUpdate: (data) => _lastGamesData = data,
      ),
    );
  }

  void _handleScrollLogic(
    AsyncValue gamesAppBarAsync,
    AsyncValue<GamesScreenModel> gamesTourAsync,
    ScrollState scrollState,
  ) {
    final current = gamesAppBarAsync.valueOrNull?.selectedId;

    // Handle initial scroll
    if (!scrollState.hasPerformedInitialScroll &&
        gamesAppBarAsync.hasValue &&
        gamesTourAsync.hasValue &&
        current != null) {
      Future.microtask(() {
        if (mounted) {
          ref.read(scrollStateProvider.notifier).setInitialScrollPerformed();
          ref.read(scrollStateProvider.notifier).updateSelectedRound(current);
          ref.read(scrollStateProvider.notifier).setPendingScroll(current);

          Future.delayed(const Duration(milliseconds: 500), () {
            if (mounted) {
              _performScrollToRound(current);
            }
          });
        }
      });
      return;
    }

    // Handle round changes
    if (current != null &&
        scrollState.hasPerformedInitialScroll &&
        current != scrollState.lastSelectedRound) {
      Future.microtask(() {
        if (mounted) {
          ref.read(scrollStateProvider.notifier).updateSelectedRound(current);
          ref.read(scrollStateProvider.notifier).setPendingScroll(current);

          // Collapse all rounds except the selected one
          ref.read(roundExpansionProvider.notifier).collapseAllExcept(current);

          Future.delayed(const Duration(milliseconds: 100), () {
            if (mounted) {
              _performScrollToRound(current);
            }
          });
        }
      });
    }
  }

  Future<void> _performScrollToRound(String roundId) async {
    final scrollState = ref.read(scrollStateProvider);
    if (scrollState.isScrolling || !mounted) return;

    Future.microtask(() {
      if (mounted) {
        ref.read(scrollStateProvider.notifier).setScrolling(true);
      }
    });

    try {
      if (!_scrollController.hasClients) return;

      final headerKey = _getHeaderKey(roundId);

      // Wait for the widget tree to be built
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
  final GlobalKey Function(String) getHeaderKey;
  final GamesScreenModel? lastGamesData;
  final Function(GamesScreenModel?) onGamesDataUpdate;

  const GamesTourContentBody({
    super.key,
    required this.gamesAppBarAsync,
    required this.gamesTourAsync,
    required this.isChessBoardVisible,
    required this.scrollController,
    required this.headerKeys,
    required this.getHeaderKey,
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
      return const EmptyWidget(
        title:
            "No games available yet. Check back soon or set a\nreminder for updates.",
      );
    }

    return GamesTourMainContent(
      gamesData: gamesData,
      isChessBoardVisible: isChessBoardVisible,
      scrollController: scrollController,
      headerKeys: headerKeys,
      getHeaderKey: getHeaderKey,
    );
  }
}

class GamesTourMainContent extends ConsumerWidget {
  final GamesScreenModel gamesData;
  final bool isChessBoardVisible;
  final ScrollController scrollController;
  final Map<String, GlobalKey> headerKeys;
  final GlobalKey Function(String) getHeaderKey;

  const GamesTourMainContent({
    super.key,
    required this.gamesData,
    required this.isChessBoardVisible,
    required this.scrollController,
    required this.headerKeys,
    required this.getHeaderKey,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rounds =
        ref.watch(gamesAppBarProvider).value?.gamesAppBarModels ?? [];
    final gamesAppBarValue = ref.watch(gamesAppBarProvider).valueOrNull;

    // Group games by round
    final gamesByRound = <String, List<GamesTourModel>>{};
    for (final game in gamesData.gamesTourModels) {
      gamesByRound.putIfAbsent(game.roundId, () => []).add(game);
    }

    final visibleRounds =
        rounds
            .where((round) => (gamesByRound[round.id]?.isNotEmpty ?? false))
            .toList();

    // Initialize expansion states
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (context.mounted) {
        ref
            .read(roundExpansionProvider.notifier)
            .initializeExpansion(visibleRounds, gamesAppBarValue?.selectedId);
      }
    });

    return GamesListView(
      rounds: visibleRounds,
      gamesByRound: gamesByRound,
      gamesData: gamesData,
      isChessBoardVisible: isChessBoardVisible,
      scrollController: scrollController,
      headerKeys: headerKeys,
      getHeaderKey: getHeaderKey,
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
  final GlobalKey Function(String) getHeaderKey;

  const GamesListView({
    super.key,
    required this.rounds,
    required this.gamesByRound,
    required this.gamesData,
    required this.isChessBoardVisible,
    required this.scrollController,
    required this.headerKeys,
    required this.getHeaderKey,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final expandedRounds = ref.watch(roundExpansionProvider);

    // Calculate total items
    int itemCount = 0;
    for (final round in rounds) {
      itemCount += 1; // Header
      final isExpanded = expandedRounds[round.id] ?? false;
      if (isExpanded) {
        itemCount += gamesByRound[round.id]?.length ?? 0;
      }
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
            expandedRounds: expandedRounds,
            getHeaderKey: getHeaderKey,
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
  final Map<String, bool> expandedRounds;
  final GlobalKey Function(String) getHeaderKey;

  const GameListItemBuilder({
    super.key,
    required this.index,
    required this.rounds,
    required this.gamesByRound,
    required this.gamesData,
    required this.isChessBoardVisible,
    required this.expandedRounds,
    required this.getHeaderKey,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    int currentIndex = 0;

    for (final round in rounds) {
      final isExpanded = expandedRounds[round.id] ?? false;
      final roundGames = gamesByRound[round.id] ?? [];

      // Check if this is the header
      if (index == currentIndex) {
        return RoundHeader(
          round: round,
          roundGames: roundGames,
          isExpanded: isExpanded,
          headerKey: getHeaderKey(round.id),
        );
      }
      currentIndex += 1;

      // If expanded, show games
      if (isExpanded) {
        if (index < currentIndex + roundGames.length) {
          final gameIndexInRound = index - currentIndex;
          final game = roundGames[gameIndexInRound];
          final globalGameIndex = gamesData.gamesTourModels.indexOf(game);

          return AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
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
    }

    return const SizedBox.shrink();
  }
}

class RoundHeader extends ConsumerWidget {
  final dynamic round;
  final List<GamesTourModel> roundGames;
  final bool isExpanded;
  final GlobalKey headerKey;

  const RoundHeader({
    super.key,
    required this.round,
    required this.roundGames,
    required this.isExpanded,
    required this.headerKey,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      onTap:
          () => ref.read(roundExpansionProvider.notifier).toggleRound(round.id),
      child: Container(
        key: headerKey,
        margin: EdgeInsets.only(top: 16.h, bottom: 8.h),
        padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
        decoration: BoxDecoration(
          color: kDarkGreyColor,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: kWhiteColor.withOpacity(0.1)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 4.w,
              height: 20.h,
              decoration: BoxDecoration(
                color: kPrimaryColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            SizedBox(width: 12.w),
            Expanded(
              child: Text(
                '${round.name} ⚫ ${roundGames.length} games',
                style: TextStyle(
                  color: kWhiteColor,
                  fontSize: 16.sp,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            AnimatedRotation(
              turns: isExpanded ? 0.5 : 0.0,
              duration: const Duration(milliseconds: 200),
              child: Icon(
                Icons.keyboard_arrow_down,
                color: kWhiteColor70,
                size: 24.sp,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class GameCardWrapper extends ConsumerWidget {
  final GamesTourModel game;
  final GamesScreenModel gamesData;
  final int gameIndex;
  final bool isChessBoardVisible;

  const GameCardWrapper({
    super.key,
    required this.game,
    required this.gamesData,
    required this.gameIndex,
    required this.isChessBoardVisible,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return isChessBoardVisible
        ? ChessBoardFromFEN(
          gamesTourModel: game,
          onChanged: () => _navigateToChessBoard(context, ref),
        )
        : GameCard(
          gamesTourModel: game,
          pinnedIds: gamesData.pinnedGamedIs,
          onPinToggle: (_) => _handlePinToggle(ref),
          onTap: () => _navigateToChessBoard(context, ref),
        );
  }

  void _navigateToChessBoard(BuildContext context, WidgetRef ref) {
    ref.read(chessboardViewFromProvider.notifier).state = ChessboardView.tour;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (_) => ChessBoardScreen(
              games: gamesData.gamesTourModels,
              currentIndex: gameIndex,
            ),
      ),
    );
  }

  Future<void> _handlePinToggle(WidgetRef ref) async {
    await ref.read(gamesTourScreenProvider.notifier).togglePinGame(game.gameId);
  }
}

class GamesErrorWidget extends ConsumerWidget {
  final String errorMessage;

  const GamesErrorWidget({
    super.key,
    required this.errorMessage,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const GenericErrorWidget(),
          SizedBox(height: 16.h),
          Text(
            errorMessage,
            textAlign: TextAlign.center,
            style: TextStyle(color: kWhiteColor70),
          ),
          SizedBox(height: 16.h),
          ElevatedButton(
            onPressed: () async {
              await ref.read(gamesAppBarProvider.notifier).refreshRounds();
              await ref.read(gamesTourScreenProvider.notifier).refreshGames();
            },
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}
