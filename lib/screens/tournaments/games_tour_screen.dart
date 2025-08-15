import 'package:chessever2/screens/chessboard/chess_board_screen.dart';
import 'package:chessever2/screens/chessboard/provider/chess_board_screen_provider.dart';
import 'package:chessever2/screens/chessboard/widgets/chess_board_widget.dart';
import 'package:chessever2/screens/tournaments/model/games_tour_model.dart';
import 'package:chessever2/screens/tournaments/providers/chess_board_visibility_provider.dart';
import 'package:chessever2/screens/tournaments/providers/game_fen_stream_provider.dart';
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

  // Keep last loaded model to avoid loading flash
  GamesScreenModel? _lastGamesData;

  // Track round changes for scrolling
  String? _lastSelectedRound;
  String? _pendingScrollToRound;
  bool _isScrolling = false;

  // Store header keys for each round
  final Map<String, GlobalKey> _headerKeys = {};

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
    // Reset scroll state for new tournament
    _lastSelectedRound = null;
    _pendingScrollToRound = null;
    _isScrolling = false;
    _hasPerformedInitialScroll = false; // Reset initial scroll flag
    _headerKeys.clear();
  }

  GlobalKey _getHeaderKey(String roundId) {
    return _headerKeys.putIfAbsent(roundId, () => GlobalKey());
  }

  @override
  Widget build(BuildContext context) {
    final isChessBoardVisible = ref.watch(chessBoardVisibilityProvider);
    final gamesAppBarAsync = ref.watch(gamesAppBarProvider);
    final gamesTourAsync = ref.watch(gamesTourScreenProvider);

    // Debug logging to understand loading sequence
    debugPrint(
      '  - App bar: ${gamesAppBarAsync.isLoading
          ? "loading"
          : gamesAppBarAsync.hasValue
          ? "loaded"
          : "error"}',
    );
    debugPrint(
      '  - Games: ${gamesTourAsync.isLoading
          ? "loading"
          : gamesTourAsync.hasValue
          ? "loaded"
          : "error"}',
    );

    // Handle round changes (including initial load)
    _handleRoundChange(gamesAppBarAsync);

    // Handle initial scroll when data is first loaded
    _handleInitialScroll(gamesAppBarAsync, gamesTourAsync);

    return RefreshIndicator(
      onRefresh: () async {
        debugPrint('🔄 Refresh triggered');
        FocusScope.of(context).unfocus();

        final futures = <Future>[];

        // Always try to refresh tour details first
        try {
          futures.add(
            ref.read(tourDetailScreenProvider.notifier).refreshTourDetails(),
          );
        } catch (e) {
          debugPrint('Error refreshing tour details: $e');
        }

        // Then refresh app bar if available
        if (gamesAppBarAsync.hasValue) {
          try {
            futures.add(ref.read(gamesAppBarProvider.notifier).refreshRounds());
          } catch (e) {
            debugPrint('Error refreshing app bar: $e');
          }
        }

        // Finally refresh games if available
        if (gamesTourAsync.hasValue) {
          try {
            futures.add(
              ref.read(gamesTourScreenProvider.notifier).refreshGames(),
            );
          } catch (e) {
            debugPrint('Error refreshing games: $e');
          }
        }

        if (futures.isNotEmpty) {
          await Future.wait(futures);
        }

        debugPrint('🔄 Refresh completed');
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

  void _handleInitialScroll(
    AsyncValue gamesAppBarAsync,
    AsyncValue<GamesScreenModel> gamesTourAsync,
  ) {
    // Only perform initial scroll once and when both data are loaded
    if (_hasPerformedInitialScroll ||
        !gamesAppBarAsync.hasValue ||
        !gamesTourAsync.hasValue) {
      return;
    }

    final selectedRoundId = gamesAppBarAsync.valueOrNull?.selectedId;

    if (selectedRoundId == null) {
      debugPrint('No selected round for initial scroll');
      return;
    }

    debugPrint('Performing initial scroll to selected round: $selectedRoundId');

    _hasPerformedInitialScroll = true;
    _lastSelectedRound = selectedRoundId;
    _pendingScrollToRound = selectedRoundId;

    // Schedule initial scroll after the UI is built
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Give extra time for SingleChildScrollView to build all widgets
      Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted && _pendingScrollToRound == selectedRoundId) {
          debugPrint('Executing initial scroll to: $selectedRoundId');
          _performScrollToRound(selectedRoundId);
        }
      });
    });
  }

  /* --------------------------------------------------------------------------
   * ROUND CHANGE + SCROLL LOGIC
   * -------------------------------------------------------------------------- */
  void _handleRoundChange(AsyncValue gamesAppBarAsync) {
    final current = gamesAppBarAsync.valueOrNull?.selectedId;

    // No current selection
    if (current == null) return;

    // Skip if this is the initial load (handled by _handleInitialScroll)
    if (!_hasPerformedInitialScroll) {
      return;
    }

    // No change from last selected round
    if (current == _lastSelectedRound) return;

    debugPrint('Round changed from $_lastSelectedRound to $current');

    _lastSelectedRound = current;
    _pendingScrollToRound = current;

    // Reset scroll state
    _isScrolling = false;

    // Schedule scroll
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted && _pendingScrollToRound == current) {
          _performScrollToRound(current);
        }
      });
    });
  }

  Future<void> _performScrollToRound(String roundId) async {
    // Prevent multiple concurrent scrolls
    if (_isScrolling || !mounted) return;

    _isScrolling = true;

    try {
      // Ensure scroll controller is attached
      if (!_scrollController.hasClients) {
        debugPrint('ScrollController not attached');
        return;
      }

      debugPrint('Scrolling to round: $roundId');

      // Get the header key - should always exist and have context now
      final headerKey = _headerKeys[roundId];

      if (headerKey?.currentContext == null) {
        debugPrint('ERROR: Header context not available for round $roundId');

        // Last resort: wait longer and try again
        await Future.delayed(const Duration(milliseconds: 500));

        if (headerKey?.currentContext == null) {
          debugPrint(
            'CRITICAL: Header context still not available after extended delay',
          );

          // Ultimate fallback: try to scroll by estimated position
          await _scrollToRoundByEstimation(roundId);
          return;
        }
      }

      debugPrint('Found header context for round $roundId, scrolling...');

      // Scroll to the header
      await Scrollable.ensureVisible(
        headerKey!.currentContext!,
        alignment: 0.0,
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeInOutCubic,
        alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
      );

      debugPrint('Successfully scrolled to round: $roundId');
    } catch (e) {
      debugPrint('Scroll error: $e');
      // Fallback to estimation
      await _scrollToRoundByEstimation(roundId);
    } finally {
      _isScrolling = false;
      _pendingScrollToRound = null;
    }
  }

  Future<void> _scrollToRoundByEstimation(String roundId) async {
    try {
      debugPrint('Using estimation fallback for round: $roundId');

      final rounds =
          ref.read(gamesAppBarProvider).value?.gamesAppBarModels ?? [];
      final gamesData = _lastGamesData;

      if (gamesData == null || rounds.isEmpty) {
        debugPrint('No data available for estimation');
        return;
      }

      // Find the target round index
      int targetRoundIndex = rounds.indexWhere((round) => round.id == roundId);

      if (targetRoundIndex == -1) {
        debugPrint('Round $roundId not found in rounds list');
        return;
      }

      // Calculate estimated scroll position
      double estimatedOffset = 0.0;
      const double headerHeight = 76.0; // Header + margins
      const double gameHeight = 140.0; // Game card + padding
      const double emptyRoundHeight = 60.0; // Empty round message height

      for (int i = 0; i < targetRoundIndex; i++) {
        final round = rounds[i];

        // Add header height
        estimatedOffset += headerHeight;

        // Add height for all games in this round
        final gamesInRound =
            gamesData.gamesTourModels
                .where((game) => game.roundId == round.id)
                .length;

        if (gamesInRound == 0) {
          estimatedOffset += emptyRoundHeight;
        } else {
          estimatedOffset += gamesInRound * gameHeight;
        }
      }

      // Clamp the offset to valid range
      estimatedOffset = estimatedOffset.clamp(
        0.0,
        _scrollController.position.maxScrollExtent,
      );

      debugPrint('Scrolling to estimated offset: $estimatedOffset');

      await _scrollController.animateTo(
        estimatedOffset,
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeInOutCubic,
      );
    } catch (e) {
      debugPrint('Estimation fallback error: $e');
    }
  }

  /* --------------------------------------------------------------------------
   * UI BUILDERS
   * -------------------------------------------------------------------------- */
  Widget _buildContent(
    BuildContext context,
    WidgetRef ref,
    AsyncValue gamesAppBarAsync,
    AsyncValue<GamesScreenModel> gamesTourAsync,
    bool isChessBoardVisible,
  ) {
    // Check critical dependencies first
    final tourId = ref.watch(selectedTourIdProvider);
    final tourDetails = ref.watch(tourDetailScreenProvider);

    // Show loading for missing critical dependencies
    if (tourId == null) {
      return const TourLoadingWidget();
    }

    // Show loading while tour details are loading
    if (tourDetails.isLoading) {
      return const TourLoadingWidget();
    }

    // Handle tour details errors
    if (tourDetails.hasError) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error, color: Colors.red, size: 48),
            const SizedBox(height: 16),
            Text(
              'Error loading tournament: ${tourDetails.error}',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                ref
                    .read(tourDetailScreenProvider.notifier)
                    .refreshTourDetails();
              },
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    // Check if tour details are available
    if (!tourDetails.hasValue ||
        tourDetails.valueOrNull?.aboutTourModel == null) {
      return const TourLoadingWidget();
    }

    // Keep the last valid model even when refreshing
    if (gamesTourAsync.hasValue) {
      _lastGamesData = gamesTourAsync.valueOrNull;
    }

    // Show loading for app bar if it's still loading and we don't have cached data
    if (gamesAppBarAsync.isLoading && _lastGamesData == null) {
      return const TourLoadingWidget();
    }

    // Show loading for games if loading and no cached data
    if (gamesTourAsync.isLoading && _lastGamesData == null) {
      return const TourLoadingWidget();
    }

    // Handle app bar errors
    if (gamesAppBarAsync.hasError) {
      return _buildErrorWidget(context, ref, gamesAppBarAsync, gamesTourAsync);
    }

    // Handle games errors
    if (gamesTourAsync.hasError) {
      return _buildErrorWidget(context, ref, gamesAppBarAsync, gamesTourAsync);
    }

    // Get games data (use cached if available)
    final gamesData = _lastGamesData ?? gamesTourAsync.valueOrNull;

    // Still show loading if no games data at all
    if (gamesData == null) {
      return const TourLoadingWidget();
    }

    // Show empty state only if we have confirmed empty games
    if (gamesData.gamesTourModels.isEmpty && !gamesTourAsync.isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            EmptyWidget(
              title:
                  "No games available yet. Check back soon or set a\nreminder for updates.",
            ),
          ],
        ),
      );
    }

    return _buildGamesList(context, ref, gamesData, isChessBoardVisible);
  }

  Widget _buildErrorWidget(
    BuildContext context,
    WidgetRef ref,
    AsyncValue gamesAppBarAsync,
    AsyncValue<GamesScreenModel> gamesTourAsync,
  ) {
    final appBarError = gamesAppBarAsync.error;
    final gamesError = gamesTourAsync.error;

    String errorMessage = 'An error occurred';
    if (appBarError != null) {
      errorMessage = 'App bar error: ${appBarError.toString()}';
    } else if (gamesError != null) {
      errorMessage = 'Games error: ${gamesError.toString()}';
    }

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
              try {
                if (gamesAppBarAsync.hasError) {
                  await ref.read(gamesAppBarProvider.notifier).refreshRounds();
                }
                if (gamesTourAsync.hasError) {
                  await ref
                      .read(gamesTourScreenProvider.notifier)
                      .refreshGames();
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Retry failed: ${e.toString()}'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _buildGamesList(
    BuildContext context,
    WidgetRef ref,
    GamesScreenModel gamesData,
    bool isChessBoardVisible,
  ) {
    // Pre-build all items
    final allItems = _buildAllItems(
      context,
      ref,
      gamesData,
      isChessBoardVisible,
    );

    return SingleChildScrollView(
      controller: _scrollController,
      padding: EdgeInsets.only(
        left: 20.sp,
        right: 20.sp,
        top: 16.sp,
        bottom: MediaQuery.of(context).viewPadding.bottom,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: allItems,
      ),
    );
  }

  List<Widget> _buildAllItems(
    BuildContext context,
    WidgetRef ref,
    GamesScreenModel gamesData,
    bool isChessBoardVisible,
  ) {
    final items = <Widget>[];
    final rounds =
        ref.watch(gamesAppBarProvider).value?.gamesAppBarModels ?? [];
    final games = gamesData.gamesTourModels;

    // Group games by round
    final gamesByRound = <String, List<GamesTourModel>>{};
    for (final game in games) {
      gamesByRound.putIfAbsent(game.roundId, () => []).add(game);
    }

    debugPrint('Building items for ${rounds.length} rounds');

    // Build items for each round - INCLUDING empty rounds
    for (final round in rounds) {
      final roundGames = gamesByRound[round.id] ?? [];

      if (roundGames.isEmpty) {
        debugPrint('Skipping empty round ${round.id} (${round.name})');
        continue;
      }

      debugPrint(
        'Building round ${round.id} (${round.name}) with ${roundGames.length} games',
      );

      // ALWAYS add round header, even if no games
      items.add(
        _buildRoundHeader({
          'roundId': round.id,
          'roundName': round.name,
        }),
      );

      if (roundGames.isEmpty) {
        // Add an empty state widget for rounds with no games
        items.add(
          Padding(
            padding: EdgeInsets.symmetric(vertical: 8.h, horizontal: 16.w),
            child: Container(
              padding: EdgeInsets.all(16.sp),
              decoration: BoxDecoration(
                color: kDarkGreyColor.withOpacity(0.3),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: kWhiteColor.withOpacity(0.1)),
              ),
              child: Text(
                'No games scheduled for this round',
                style: TextStyle(
                  color: kWhiteColor70,
                  fontSize: 14.sp,
                  fontStyle: FontStyle.italic,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        );
      } else {
        // Add all games for this round
        for (int i = 0; i < roundGames.length; i++) {
          final game = roundGames[i];
          final globalGameIndex = games.indexOf(game);

          items.add(
            Padding(
              padding: EdgeInsets.only(bottom: 12.sp),
              child: _buildGameCard(
                context,
                ref,
                game,
                gamesData,
                globalGameIndex,
                isChessBoardVisible,
              ),
            ),
          );
        }
      }
    }

    debugPrint('Built ${items.length} total items');
    return items;
  }

  /* --------------------------------------------------------------------------
   * ITEM HELPERS
   * -------------------------------------------------------------------------- */

  Widget _buildRoundHeader(Map<String, dynamic> round) {
    final roundId = round['roundId'] as String;
    final headerKey = _getHeaderKey(roundId);

    return Container(
      key: headerKey,
      margin: EdgeInsets.only(top: 16.h, bottom: 8.h),
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
      decoration: BoxDecoration(
        color: kDarkGreyColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: kWhiteColor.withOpacity(0.1)),
      ),
      child: Row(
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
          Text(
            (round['roundName'] ?? round['roundId']).toString(),
            style: TextStyle(
              color: kWhiteColor,
              fontSize: 16.sp,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGameCard(
    BuildContext context,
    WidgetRef ref,
    GamesTourModel gamesTourModel,
    GamesScreenModel gamesData,
    int gameIndex,
    bool isChessBoardVisible,
  ) {
    void navigateToChessBoard() {
      try {
        ref.read(chessboardViewFromProvider.notifier).state =
            ChessboardView.tour;

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
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to open chess board: ${e.toString()}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }

    Future<void> handlePinToggle() async {
      try {
        await ref
            .read(gamesTourScreenProvider.notifier)
            .togglePinGame(gamesTourModel.gameId);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to toggle pin: ${e.toString()}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }

    if (isChessBoardVisible) {
      return ChessBoardFromFEN(
        gamesTourModel: gamesTourModel,
        onChanged: navigateToChessBoard,
      );
    } else {
      return GameCard(
        gamesTourModel: gamesTourModel,
        pinnedIds: gamesData.pinnedGamedIs,
        onPinToggle: (_) => handlePinToggle(),
        onTap: navigateToChessBoard,
      );
    }
  }
}
