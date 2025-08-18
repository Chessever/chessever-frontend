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

class GamesTourScreen extends ConsumerStatefulWidget {
  const GamesTourScreen({super.key});

  @override
  ConsumerState<GamesTourScreen> createState() => _GamesTourScreenState();
}

class _GamesTourScreenState extends ConsumerState<GamesTourScreen> {
  bool _hasPerformedInitialScroll = false;
  late ScrollController _scrollController;
  final GlobalKey _listViewKey = GlobalKey();
  GamesScreenModel? _lastGamesData;
  String? _lastSelectedRound;
  String? _pendingScrollToRound;
  bool _isScrolling = false;
  final Map<String, GlobalKey> _headerKeys = {};
  final Map<String, bool> _expandedRounds = {}; // Track expanded state

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
    _lastSelectedRound = null;
    _pendingScrollToRound = null;
    _isScrolling = false;
    _hasPerformedInitialScroll = false;
    _headerKeys.clear();
    _expandedRounds.clear();
  }

  GlobalKey _getHeaderKey(String roundId) {
    return _headerKeys.putIfAbsent(roundId, () => GlobalKey());
  }

  void _toggleRoundExpansion(String roundId) {
    setState(() {
      _expandedRounds[roundId] = !(_expandedRounds[roundId] ?? true);
    });
  }

  bool _isRoundExpanded(String roundId) {
    return _expandedRounds[roundId] ?? true; // Default to expanded
  }

  @override
  Widget build(BuildContext context) {
    final isChessBoardVisible = ref.watch(chessBoardVisibilityProvider);
    final gamesAppBarAsync = ref.watch(gamesAppBarProvider);
    final gamesTourAsync = ref.watch(gamesTourScreenProvider);

    _handleRoundChange(gamesAppBarAsync);
    _handleInitialScroll(gamesAppBarAsync, gamesTourAsync);

    return RefreshIndicator(
      onRefresh: () async {
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
        if (futures.isNotEmpty) await Future.wait(futures);
      },
      color: kWhiteColor70,
      backgroundColor: kDarkGreyColor,
      displacement: 60.h,
      strokeWidth: 3.w,
      child: _buildContent(
        context,
        ref,
        gamesAppBarAsync,
        gamesTourAsync,
        isChessBoardVisible,
      ),
    );
  }

  /// Handle initial scroll after first load
  void _handleInitialScroll(
    AsyncValue gamesAppBarAsync,
    AsyncValue<GamesScreenModel> gamesTourAsync,
  ) {
    if (_hasPerformedInitialScroll ||
        !gamesAppBarAsync.hasValue ||
        !gamesTourAsync.hasValue)
      return;

    final selectedRoundId = gamesAppBarAsync.valueOrNull?.selectedId;
    if (selectedRoundId == null) return;

    _hasPerformedInitialScroll = true;
    _lastSelectedRound = selectedRoundId;
    _pendingScrollToRound = selectedRoundId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted && _pendingScrollToRound == selectedRoundId) {
          _performScrollToRound(selectedRoundId);
        }
      });
    });
  }

  /// Handle round changes (scroll to new round)
  void _handleRoundChange(AsyncValue gamesAppBarAsync) {
    final current = gamesAppBarAsync.valueOrNull?.selectedId;
    if (current == null ||
        !_hasPerformedInitialScroll ||
        current == _lastSelectedRound)
      return;

    _lastSelectedRound = current;
    _pendingScrollToRound = current;
    _isScrolling = false;

    // Ensure round is expanded before scrolling
    if (!_isRoundExpanded(current)) {
      setState(() {
        _expandedRounds[current] = true;
      });
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _pendingScrollToRound == current) {
        _performScrollToRound(current);
      }
    });
  }

  Future<void> _performScrollToRound(String roundId) async {
    if (_isScrolling || !mounted) return;
    _isScrolling = true;

    try {
      if (!_scrollController.hasClients) return;

      // First, ensure the header key exists and is generated
      final headerKey = _getHeaderKey(roundId);

      // Wait for the widget tree to be built and keys to be attached
      for (int retry = 0; retry < 30; retry++) {
        await Future.delayed(const Duration(milliseconds: 100));

        if (headerKey.currentContext != null) {
          debugPrint(
            '[GamesTourScreen] Found header context for round: $roundId, attempting scroll...',
          );

          await Scrollable.ensureVisible(
            headerKey.currentContext!,
            alignment: 0.0,
            duration: const Duration(milliseconds: 0),
            curve: Curves.easeInOut,
            alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
          );

          debugPrint(
            '[GamesTourScreen] Successfully scrolled to round: $roundId',
          );
          break;
        }

        debugPrint(
          '[GamesTourScreen] Retry $retry: Header context not found for round: $roundId',
        );
      }
    } catch (e) {
      debugPrint('[GamesTourScreen] Scroll error: $e');
    } finally {
      _isScrolling = false;
      _pendingScrollToRound = null;
    }
  }

  Widget _buildContent(
    BuildContext context,
    WidgetRef ref,
    AsyncValue gamesAppBarAsync,
    AsyncValue<GamesScreenModel> gamesTourAsync,
    bool isChessBoardVisible,
  ) {
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
        retryAppBar: false,
        retryGames: false,
      );
    }

    if (gamesTourAsync.hasValue) {
      _lastGamesData = gamesTourAsync.valueOrNull;
    }

    if ((gamesAppBarAsync.isLoading || gamesTourAsync.isLoading) &&
        _lastGamesData == null) {
      return const TourLoadingWidget();
    }

    if (gamesAppBarAsync.hasError || gamesTourAsync.hasError) {
      return GamesErrorWidget(
        errorMessage:
            gamesAppBarAsync.error?.toString() ??
            gamesTourAsync.error?.toString() ??
            "An error occurred",
        retryAppBar: gamesAppBarAsync.hasError,
        retryGames: gamesTourAsync.hasError,
      );
    }

    final gamesData = _lastGamesData ?? gamesTourAsync.valueOrNull;
    if (gamesData == null) return const TourLoadingWidget();

    if (gamesData.gamesTourModels.isEmpty && !gamesTourAsync.isLoading) {
      return const EmptyWidget(
        title:
            "No games available yet. Check back soon or set a\nreminder for updates.",
      );
    }

    final rounds =
        ref.watch(gamesAppBarProvider).value?.gamesAppBarModels ?? [];
    final games = gamesData.gamesTourModels;
    final gamesByRound = <String, List<GamesTourModel>>{};
    for (final game in games) {
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
      scrollController: _scrollController,
      listViewKey: _listViewKey,
      headerKeys: _headerKeys,
      expandedRounds: _expandedRounds,
      onToggleExpansion: _toggleRoundExpansion,
      getHeaderKey: _getHeaderKey, // Pass the method to ensure key generation
    );
  }
}

class RoundHeader extends StatelessWidget {
  final String roundId;
  final String roundName;
  final GlobalKey headerKey;
  final bool isExpanded;
  final VoidCallback onTap;
  final int gamesCount;

  const RoundHeader({
    super.key,
    required this.roundId,
    required this.roundName,
    required this.headerKey,
    required this.isExpanded,
    required this.onTap,
    required this.gamesCount,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
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
                '$roundName ⚫ $gamesCount games',
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
    void navigateToChessBoard() {
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

    Future<void> handlePinToggle() async {
      await ref
          .read(gamesTourScreenProvider.notifier)
          .togglePinGame(game.gameId);
    }

    return isChessBoardVisible
        ? ChessBoardFromFEN(
          gamesTourModel: game,
          onChanged: navigateToChessBoard,
        )
        : GameCard(
          gamesTourModel: game,
          pinnedIds: gamesData.pinnedGamedIs,
          onPinToggle: (_) => handlePinToggle(),
          onTap: navigateToChessBoard,
        );
  }
}

class GamesErrorWidget extends ConsumerWidget {
  final String errorMessage;
  final bool retryAppBar;
  final bool retryGames;

  const GamesErrorWidget({
    super.key,
    required this.errorMessage,
    this.retryAppBar = false,
    this.retryGames = false,
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
              if (retryAppBar) {
                await ref.read(gamesAppBarProvider.notifier).refreshRounds();
              }
              if (retryGames) {
                await ref.read(gamesTourScreenProvider.notifier).refreshGames();
              }
            },
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}

class GamesListView extends StatelessWidget {
  final List rounds;
  final Map<String, List<GamesTourModel>> gamesByRound;
  final GamesScreenModel gamesData;
  final bool isChessBoardVisible;
  final ScrollController scrollController;
  final GlobalKey listViewKey;
  final Map<String, GlobalKey> headerKeys;
  final Map<String, bool> expandedRounds;
  final Function(String) onToggleExpansion;
  final GlobalKey Function(String) getHeaderKey; // Added this parameter

  const GamesListView({
    super.key,
    required this.rounds,
    required this.gamesByRound,
    required this.gamesData,
    required this.isChessBoardVisible,
    required this.scrollController,
    required this.listViewKey,
    required this.headerKeys,
    required this.expandedRounds,
    required this.onToggleExpansion,
    required this.getHeaderKey, // Added this parameter
  });

  @override
  Widget build(BuildContext context) {
    // Calculate total items including headers and games (only expanded ones)
    int itemCount = 0;
    for (final round in rounds) {
      itemCount += 1; // Header
      final isExpanded = expandedRounds[round.id] ?? true;
      if (isExpanded) {
        itemCount += gamesByRound[round.id]?.length ?? 0; // Games
      }
    }

    return ListView.builder(
      key: listViewKey,
      controller: scrollController,
      padding: EdgeInsets.only(
        left: 20.sp,
        right: 20.sp,
        top: 16.sp,
        bottom: MediaQuery.of(context).viewPadding.bottom,
      ),
      cacheExtent: 30000.0,
      itemCount: itemCount,
      itemBuilder: (context, index) {
        int currentIndex = 0;

        for (final round in rounds) {
          final isExpanded = expandedRounds[round.id] ?? true;
          final roundGames = gamesByRound[round.id] ?? [];

          // Check if this is the header
          if (index == currentIndex) {
            return RoundHeader(
              roundId: round.id,
              roundName: round.name,
              headerKey: getHeaderKey(round.id),
              // Use the method to ensure key generation
              isExpanded: isExpanded,
              gamesCount: roundGames.length,
              onTap: () => onToggleExpansion(round.id),
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
      },
    );
  }
}
