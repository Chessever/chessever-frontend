import 'dart:async';

import 'package:chessever2/providers/board_settings_provider.dart';
import 'package:chessever2/repository/local_storage/board_settings_repository/board_settings_repository.dart';
import 'package:chessever2/screens/chessboard/analysis/chess_game_navigator.dart';
import 'package:chessever2/screens/chessboard/analysis/move_impact_analyzer.dart';
import 'package:chessever2/screens/chessboard/analysis/simple_move_impact.dart';
import 'package:chessever2/screens/chessboard/provider/chess_board_screen_provider_new.dart';
import 'package:chessever2/screens/chessboard/view_model/chess_board_state_new.dart';
import 'package:chessever2/screens/chessboard/widgets/chess_board_bottom_nav_bar.dart';
import 'package:chessever2/screens/chessboard/widgets/evaluation_bar_widget.dart';
import 'package:chessever2/screens/chessboard/widgets/move_annotation_overlay.dart';
import 'package:chessever2/screens/group_event/providers/countryman_games_tour_screen_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_screen_provider.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/screens/chessboard/widgets/player_first_row_detail_widget.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/audio_player_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:chessever2/utils/svg_asset.dart';
import 'package:chessever2/widgets/divider_widget.dart';
import 'package:flutter_svg/svg.dart';

/// Cached move impact results keyed by game id/signature to avoid recomputation
class CachedMoveImpact {
  final String signature;
  final Map<int, MoveImpactAnalysis> impacts;

  const CachedMoveImpact({required this.signature, required this.impacts});
}

class MoveImpactCacheNotifier
    extends StateNotifier<Map<String, CachedMoveImpact>> {
  MoveImpactCacheNotifier() : super(<String, CachedMoveImpact>{});

  CachedMoveImpact? lookup(String gameId) => state[gameId];

  void store(String gameId, CachedMoveImpact cached) {
    state = {...state, gameId: cached};
  }

  void invalidate(String gameId) {
    if (!state.containsKey(gameId)) return;
    final copy = {...state};
    copy.remove(gameId);
    state = copy;
  }
}

final moveImpactCacheProvider = StateNotifierProvider<
  MoveImpactCacheNotifier,
  Map<String, CachedMoveImpact>
>((ref) => MoveImpactCacheNotifier());

/// Provider that calculates move impacts - COMPREHENSIVE ANALYSIS
/// Analyzes engine alternatives, finds player move rank, classifies impact
final gameMovesImpactProvider = FutureProvider.family.autoDispose<
  Map<int, MoveImpactAnalysis>?,
  ChessBoardProviderParams
>((ref, params) async {
  debugPrint(
    '🎨 gameMovesImpactProvider: START for game ${params.game.gameId}',
  );

  final link = ref.keepAlive();
  Timer? cleanupTimer;

  ref.onCancel(() {
    cleanupTimer = Timer(const Duration(seconds: 45), () {
      debugPrint(
        '🎨 gameMovesImpactProvider: releasing keepAlive for ${params.game.gameId}',
      );
      link.close();
    });
  });

  ref.onResume(() {
    cleanupTimer?.cancel();
    cleanupTimer = null;
  });

  ref.onDispose(() {
    cleanupTimer?.cancel();
  });

  // Use .select() to watch ONLY the moves data, not the entire state
  final allMoves = ref.watch(
    chessBoardScreenProviderNew(
      params,
    ).select((state) => state.valueOrNull?.allMoves),
  );
  final moveSans = ref.watch(
    chessBoardScreenProviderNew(
      params,
    ).select((state) => state.valueOrNull?.moveSans),
  );
  final startingPosition = ref.watch(
    chessBoardScreenProviderNew(
      params,
    ).select((state) => state.valueOrNull?.startingPosition),
  );

  if (allMoves == null || allMoves.isEmpty || moveSans == null) {
    debugPrint('🎨 gameMovesImpactProvider: NULL - no moves yet');
    return null;
  }

  debugPrint(
    '🎨 gameMovesImpactProvider: Got ${allMoves.length} moves, ${moveSans.length} SANs',
  );

  final cacheSignature = '${moveSans.length}:${moveSans.join('|')}';
  final cachedImpact = ref.read(moveImpactCacheProvider)[params.game.gameId];
  if (cachedImpact != null && cachedImpact.signature == cacheSignature) {
    debugPrint(
      '🎨 gameMovesImpactProvider: Using cached impacts for ${params.game.gameId}',
    );
    return cachedImpact.impacts;
  }

  // Generate position FENs (starting position + after each move)
  final fensParams = PositionFensParams(
    allMoves: allMoves,
    startingPosition: startingPosition,
    gameId: params.game.gameId,
  );
  final positionFens = ref.watch(positionFensProvider(fensParams));
  debugPrint(
    '🎨 gameMovesImpactProvider: Generated ${positionFens.length} position FENs',
  );

  // Determine which moves are white's
  final isWhiteMoves = List.generate(
    allMoves.length,
    (i) => i % 2 == 0, // Even indices = white's moves
  );

  // Use COMPREHENSIVE impact provider that analyzes alternatives
  final simpleParams = SimpleMoveImpactParams(
    positionFens: positionFens,
    isWhiteMoves: isWhiteMoves,
    moveSans: moveSans,
    gameId: params.game.gameId,
  );

  debugPrint('🎨 gameMovesImpactProvider: Calling simpleMoveImpactProvider...');
  final impacts = await ref.watch(
    simpleMoveImpactProvider(simpleParams).future,
  );
  debugPrint(
    '🎨 gameMovesImpactProvider: COMPLETE - got ${impacts.length} impacts',
  );

  ref
      .read(moveImpactCacheProvider.notifier)
      .store(
        params.game.gameId,
        CachedMoveImpact(
          signature: cacheSignature,
          impacts: Map.unmodifiable(impacts),
        ),
      );
  return impacts;
});

// Helper function to get move highlight color
Color getLastMoveHighlightColor(ChessBoardStateNew state) {
  if (state.currentMoveIndex < 0) return kPrimaryColor;

  // Determine if the current move (last move played) was by white or black
  // Move index 0 = white's first move, 1 = black's first move, etc.
  final isWhiteMove = state.currentMoveIndex % 2 == 0;

  return isWhiteMove ? kPrimaryColor : kChessBlackMoveColor;
}

// Helper function to get move highlight color for analysis mode
Color getAnalysisLastMoveHighlightColor(ChessBoardStateNew state) {
  if (state.analysisState.lastMove == null) return kPrimaryColor;

  // If it's black's turn, white made the last move, and vice versa.
  final isWhiteMove = state.analysisState.position.turn == Side.black;
  return isWhiteMove ? kPrimaryColor : kChessBlackMoveColor;
}

class ChessBoardScreenNew extends ConsumerStatefulWidget {
  final int currentIndex;
  final List<GamesTourModel> games;

  const ChessBoardScreenNew({
    required this.currentIndex,
    required this.games,
    super.key,
  });

  @override
  ConsumerState<ChessBoardScreenNew> createState() => _ChessBoardScreenState();
}

class _ChessBoardScreenState extends ConsumerState<ChessBoardScreenNew> {
  late PageController _pageController;
  bool analysisMode = false;
  int? _lastViewedIndex;
  int _currentPageIndex = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: widget.currentIndex);
    _currentPageIndex = widget.currentIndex;

    // Note: We'll enable streaming in didChangeDependencies when ref is available
  }

  @override
  void didUpdateWidget(covariant ChessBoardScreenNew oldWidget) {
    super.didUpdateWidget(oldWidget);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Set the initial visible page index - delayed to avoid modifying provider during build
    Future.microtask(() {
      if (mounted) {
        ref.read(currentlyVisiblePageIndexProvider.notifier).state =
            _currentPageIndex;
      }
    });
  }

  void _onPageChanged(int newIndex) {
    if (_currentPageIndex == newIndex) return;

    _lastViewedIndex = newIndex;
    final previousIndex = _currentPageIndex;

    // Update current page index immediately
    setState(() {
      _currentPageIndex = newIndex;
    });

    // CRITICAL: Update the global provider to track which page is visible
    // This prevents off-screen games from playing audio
    ref.read(currentlyVisiblePageIndexProvider.notifier).state = newIndex;

    // OPTIMIZED: Don't read provider state during page changes - just manage the chess board providers
    // This prevents unnecessary provider lookups that could trigger rebuilds

    // Only pause if the previous provider should still be alive (within ±1 range)
    if ((newIndex - previousIndex).abs() <= 1) {
      try {
        final prevGame = widget.games[previousIndex];
        ref
            .read(
              chessBoardScreenProviderNew(
                ChessBoardProviderParams(game: prevGame, index: previousIndex),
              ).notifier,
            )
            .pauseGame();
      } catch (e) {
        // Provider was disposed, which is fine
      }
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        try {
          final newGame = widget.games[newIndex];
          ref
              .read(
                chessBoardScreenProviderNew(
                  ChessBoardProviderParams(game: newGame, index: newIndex),
                ).notifier,
              )
              .parseMoves();
        } catch (e) {
          debugPrint('Error parsing moves for new index: $e');
        }
      }
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _navigateToGame(int gameIndex) {
    if (gameIndex == _currentPageIndex) return;

    // OPTIMIZED: Don't read provider during navigation - just pause the current game
    try {
      final currentGame = widget.games[_currentPageIndex];
      ref
          .read(
            chessBoardScreenProviderNew(
              ChessBoardProviderParams(
                game: currentGame,
                index: _currentPageIndex,
              ),
            ).notifier,
          )
          .pauseGame();
    } catch (e) {
      debugPrint('Error pausing game during navigation: $e');
    }

    _pageController.animateToPage(
      gameIndex,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentGame = widget.games[_currentPageIndex];
    ref.listen(
      chessBoardScreenProviderNew(
        ChessBoardProviderParams(game: currentGame, index: _currentPageIndex),
      ),
      (prev, next) {
        final prevState = prev?.valueOrNull;
        final nextState = next.valueOrNull;
        final prevIndex =
            prevState == null
                ? -1
                : (prevState.isAnalysisMode
                    ? prevState.analysisState.currentMoveIndex
                    : prevState.currentMoveIndex);
        final currentIndex =
            nextState == null
                ? -1
                : (nextState.isAnalysisMode
                    ? nextState.analysisState.currentMoveIndex
                    : nextState.currentMoveIndex);

        if (prevIndex != currentIndex && next.valueOrNull != null) {
          // CRITICAL FIX: Only play audio if this chess board screen is currently active
          // This prevents audio from playing when other games in the tournament get moves
          final route = ModalRoute.of(context);
          if (route == null || !route.isCurrent) {
            // Screen is not visible, don't play audio
            return;
          }

          final state = nextState!;

          // ENHANCED FIX: Verify this update is for the currently viewed game
          // Only play audio if the provider index matches the current page
          final providerGameIndex = _currentPageIndex;
          final viewGameId = widget.games[providerGameIndex].gameId;
          if (state.game.gameId != viewGameId) {
            // This update is for a different game, don't play audio
            return;
          }

          // Additional check: Only play audio for significant move index changes
          // This prevents audio from playing due to minor state updates
          if ((currentIndex - prevIndex).abs() != 1 && currentIndex != -1) {
            // Not a sequential move change, likely a background update
            return;
          }

          // Final check: Make sure we're viewing the correct page in PageView
          // Use a small tolerance for floating-point comparison
          final currentPage =
              _pageController.page ?? _currentPageIndex.toDouble();
          if ((currentPage - _currentPageIndex).abs() > 0.1) {
            // PageView is not on the current game, don't play audio
            return;
          }

          final audioService = AudioPlayerService.instance;

          // Determine if we're going forward or backward
          final isMovingForward = currentIndex > prevIndex;

          // For backward navigation, we want to play the sound of the move we just "undid"
          // For forward navigation, we want to play the sound of the move we just made
          final moveIndexForSound = isMovingForward ? currentIndex : prevIndex;

          final movesSan =
              state.isAnalysisMode
                  ? state.analysisState.moveSans
                  : state.moveSans;

          // Check if we have a valid move to play sound for
          if (moveIndexForSound >= 0 && moveIndexForSound < movesSan.length) {
            // Get the move notation for the appropriate move
            final moveSan = movesSan[moveIndexForSound];

            // Determine which sound to play based on PGN notation
            // Priority order matters: checkmate > check > special moves > capture > regular
            if (moveSan.contains('#')) {
              // Checkmate notation
              audioService.player.play(audioService.pieceCheckmateSfx);
            } else if (moveSan.contains('+')) {
              // Check notation (but not checkmate)
              audioService.player.play(audioService.pieceCheckSfx);
            } else if (moveSan == 'O-O' || moveSan == 'O-O-O') {
              // Castling (kingside or queenside) - exact match
              audioService.player.play(audioService.pieceCastlingSfx);
            } else if (moveSan.contains('=')) {
              // Pawn promotion (e.g., e8=Q)
              audioService.player.play(audioService.piecePromotionSfx);
            } else if (moveSan.contains('x')) {
              // Capture notation
              audioService.player.play(audioService.pieceTakeoverSfx);
            } else {
              // Regular move (no special notation)
              audioService.player.play(audioService.pieceMoveSfx);
            }
          } else if (currentIndex == -1 && prevIndex >= 0) {
            // Moving back to the starting position (before first move)
            // Play a regular move sound for the "undo" action
            audioService.player.play(audioService.pieceMoveSfx);
          } else if (currentIndex == movesSan.length && movesSan.isNotEmpty) {
            // We're at the end of the game, check for game-ending conditions
            final lastMoveSan = movesSan.last;

            if (lastMoveSan.contains('#')) {
              // Game ended with checkmate
              audioService.player.play(audioService.pieceCheckmateSfx);
            } else if (state.game.gameStatus == GameStatus.draw) {
              // Game ended in a draw
              audioService.player.play(audioService.pieceDrawSfx);
            } else {
              // Other game endings (resignation, time out, etc.)
              audioService.player.play(audioService.pieceMoveSfx);
            }
          } else {
            // Fallback for edge cases (shouldn't normally happen)
            audioService.player.play(audioService.pieceMoveSfx);
          }
        }
      },
      onError: (e, st) {
        debugPrint("Error in chessBoardScreenProviderNew listener: $e");
      },
    );
    // OPTIMIZED: Only watch for updates to games that are currently visible in the PageView
    // This prevents rebuilds when other games in the tournament get updated
    final view = ref.watch(chessboardViewFromProviderNew);
    final gamesAsync =
        view == ChessboardView.tour
            ? ref.watch(
              gamesTourScreenProvider.select((value) {
                // Only trigger rebuild if the games we care about have changed
                if (!value.hasValue) return value;

                final allGames = value.value!.gamesTourModels;
                final gameIds = widget.games.map((g) => g.gameId).toSet();

                // Return only the games relevant to this chess board screen
                final relevantGames =
                    allGames.where((g) => gameIds.contains(g.gameId)).toList();
                return AsyncValue.data(
                  value.value!.copyWith(gamesTourModels: relevantGames),
                );
              }),
            )
            : ref.watch(countrymanGamesTourScreenProvider);

    // Show loading screen if data isn't ready
    if (!gamesAsync.hasValue || gamesAsync.value?.gamesTourModels == null) {
      return _LoadingScreen(
        games: widget.games.isNotEmpty ? widget.games : [widget.games.first],
        currentGameIndex: _currentPageIndex.clamp(0, widget.games.length - 1),
        onGameChanged: (index) {}, // Disabled during loading
        lastViewedIndex: _lastViewedIndex,
      );
    }

    // Map only the games relevant to this chess board screen
    final liveGamesMap = Map.fromEntries(
      gamesAsync.value!.gamesTourModels.map((g) => MapEntry(g.gameId, g)),
    );
    final liveGames =
        widget.games.map((originalGame) {
          // Get the updated game data from the live stream, or fallback to original if not found
          return liveGamesMap[originalGame.gameId] ?? originalGame;
        }).toList();

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          Navigator.of(context).pop(_lastViewedIndex);
        }
      },
      child: Scaffold(
        body: RawGestureDetector(
          gestures: <Type, GestureRecognizerFactory>{
            HorizontalDragGestureRecognizer:
                GestureRecognizerFactoryWithHandlers<
                  HorizontalDragGestureRecognizer
                >(() => HorizontalDragGestureRecognizer(), (
                  HorizontalDragGestureRecognizer instance,
                ) {
                  instance.onStart = (_) {};
                  instance.onUpdate = (_) {};
                  instance.onEnd = (_) {};
                }),
          },
          behavior: HitTestBehavior.translucent,
          child: PageView.builder(
            padEnds: true,
            allowImplicitScrolling: true,
            // helps the framework build ahead
            physics:
                analysisMode
                    ? NeverScrollableScrollPhysics()
                    : const PageScrollPhysics(),
            controller: _pageController,
            onPageChanged: _onPageChanged,
            itemCount: liveGames.length,
            itemBuilder: (context, index) {
              // Build current page and adjacent pages
              if (index == _currentPageIndex - 1 ||
                  index == _currentPageIndex ||
                  index == _currentPageIndex + 1) {
                try {
                  final game = liveGames[index];
                  return ref
                      .watch(
                        chessBoardScreenProviderNew(
                          ChessBoardProviderParams(game: game, index: index),
                        ),
                      )
                      .when(
                        data: (chessBoardState) {
                          if (chessBoardState.isAnalysisMode != analysisMode) {
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (_pageController.hasClients) {
                                setState(() {
                                  analysisMode = chessBoardState.isAnalysisMode;
                                });
                              }
                            });
                          }
                          return _GamePage(
                            game: liveGames[index],
                            state: chessBoardState,
                            games: liveGames,
                            currentGameIndex: index,
                            currentPageIndex: _currentPageIndex,
                            onGameChanged: _navigateToGame,
                            lastViewedIndex: _lastViewedIndex,
                          );
                        },
                        error: (e, _) => ErrorWidget(e),
                        loading:
                            () => _LoadingScreen(
                              games: liveGames,
                              currentGameIndex: index,
                              onGameChanged: _navigateToGame,
                              lastViewedIndex: _lastViewedIndex,
                            ),
                      );
                } catch (e) {
                  // Fallback for when provider isn't ready
                  return _LoadingScreen(
                    games: liveGames,
                    currentGameIndex: index,
                    onGameChanged: _navigateToGame,
                    lastViewedIndex: _lastViewedIndex,
                  );
                }
              } else {
                return SizedBox.shrink();
              }
            },
          ),
        ),
      ),
    );
  }
}

class _GamePage extends StatelessWidget {
  final GamesTourModel game;
  final ChessBoardStateNew state;
  final List<GamesTourModel> games;
  final int currentGameIndex;
  final int currentPageIndex;
  final void Function(int) onGameChanged;
  final int? lastViewedIndex;

  const _GamePage({
    required this.game,
    required this.state,
    required this.games,
    required this.currentGameIndex,
    required this.currentPageIndex,
    required this.onGameChanged,
    this.lastViewedIndex,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      bottomNavigationBar: _BottomNavBar(
        index: currentGameIndex,
        state: state,
        game: game,
      ),
      appBar: _AppBar(
        game: game,
        games: games,
        currentGameIndex: currentGameIndex,
        onGameChanged: onGameChanged,
        lastViewedIndex: lastViewedIndex,
      ),
      body: _GameBody(
        index: currentGameIndex,
        currentPageIndex: currentPageIndex,
        game: game,
        state: state,
      ),
    );
  }
}

class _LoadingScreen extends StatelessWidget {
  final List<GamesTourModel> games;
  final int currentGameIndex;
  final void Function(int) onGameChanged;
  final int? lastViewedIndex;

  const _LoadingScreen({
    required this.games,
    required this.currentGameIndex,
    required this.onGameChanged,
    this.lastViewedIndex,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _AppBar(
        game: games[currentGameIndex],
        games: games,
        currentGameIndex: currentGameIndex,
        onGameChanged: onGameChanged,
        isLoading: true,
        lastViewedIndex: lastViewedIndex,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: kGreenColor),
            SizedBox(height: 16.h),
            Text('Loading game...', style: AppTypography.textSmMedium),
          ],
        ),
      ),
    );
  }
}

class _AppBar extends StatelessWidget implements PreferredSizeWidget {
  final GamesTourModel game;
  final List<GamesTourModel> games;
  final int currentGameIndex;
  final void Function(int) onGameChanged;
  final bool isLoading;
  final int? lastViewedIndex;

  const _AppBar({
    required this.game,
    required this.games,
    required this.currentGameIndex,
    required this.onGameChanged,
    this.isLoading = false,
    this.lastViewedIndex,
  });

  @override
  Widget build(BuildContext context) {
    return AppBar(
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new, color: kWhiteColor),
        onPressed: () => Navigator.pop(context, lastViewedIndex),
      ),
      title: _GameSelectionDropdown(
        games: games,
        currentGameIndex: currentGameIndex,
        onGameChanged: onGameChanged,
        isLoading: isLoading,
      ),
      actions: [
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert, color: kWhiteColor),
          enabled: !isLoading,
          onSelected: (_) {},
          itemBuilder:
              (context) => [
                PopupMenuItem(
                  value: 'share',
                  child: Row(
                    children: [
                      Icon(Icons.share, color: kWhiteColor),
                      SizedBox(width: 8.w),
                      const Text('Share Game'),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'analyze',
                  child: Row(
                    children: [
                      Icon(Icons.analytics, color: kWhiteColor),
                      SizedBox(width: 8.w),
                      const Text('Analyze'),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'copy_pgn',
                  child: Row(
                    children: [
                      Icon(Icons.copy, color: kWhiteColor),
                      SizedBox(width: 8.w),
                      const Text('Copy PGN'),
                    ],
                  ),
                ),
              ],
        ),
      ],
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}

class _GameSelectionDropdown extends StatelessWidget {
  final List<GamesTourModel> games;
  final int currentGameIndex;
  final void Function(int) onGameChanged;
  final bool isLoading;

  const _GameSelectionDropdown({
    required this.games,
    required this.currentGameIndex,
    required this.onGameChanged,
    this.isLoading = false,
  });

  String _formatName(String fullName, {double? maxWidth}) {
    List<String> nameParts =
        fullName.trim().split(' ').where((part) => part.isNotEmpty).toList();
    if (nameParts.length <= 1) return fullName;

    String familyName = nameParts.last;
    List<String> otherNames = nameParts.sublist(0, nameParts.length - 1);

    // Try full names first
    String fullVersion = '${otherNames.join(' ')} $familyName';

    // If no width constraint or it fits, return full version
    if (maxWidth == null) return fullVersion;

    // Estimate text width (rough approximation)
    double estimatedWidth =
        fullVersion.length * 6.0; // Approximate character width
    if (estimatedWidth <= maxWidth) return fullVersion;

    // If too long, progressively abbreviate from left to right
    List<String> displayNames = List.from(otherNames);

    for (int i = 0; i < displayNames.length; i++) {
      if (displayNames[i].length > 1) {
        displayNames[i] = '${displayNames[i][0]}.';
        String newVersion = '${displayNames.join(' ')} $familyName';
        double newEstimatedWidth = newVersion.length * 6.0;
        if (newEstimatedWidth <= maxWidth) {
          return newVersion;
        }
      }
    }

    // Fallback: all abbreviated
    return '${displayNames.join(' ')} $familyName';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 32.h,
      constraints: BoxConstraints(maxWidth: 300.w),
      child: DropdownButton<int>(
        value: currentGameIndex,
        underline: Container(),
        icon: Icon(
          Icons.keyboard_arrow_down_outlined,
          color: kWhiteColor,
          size: 20.sp,
        ),
        dropdownColor: kBlack2Color,
        borderRadius: BorderRadius.circular(20.sp),
        isExpanded: true,
        style: AppTypography.textMdBold,
        onChanged:
            isLoading
                ? null
                : (int? newIndex) {
                  if (newIndex != null && newIndex != currentGameIndex) {
                    onGameChanged(newIndex);
                  }
                },
        selectedItemBuilder: (BuildContext context) {
          return games.asMap().entries.map<Widget>((entry) {
            final game = entry.value;

            return Container(
              padding: EdgeInsets.symmetric(horizontal: 12.sp),
              alignment: Alignment.center,
              child: Text(
                '${_formatName(game.whitePlayer.displayName, maxWidth: 120)} vs ${_formatName(game.blackPlayer.displayName, maxWidth: 120)}',
                style: AppTypography.textXsMedium.copyWith(color: kWhiteColor),
                overflow: TextOverflow.ellipsis,
              ),
            );
          }).toList();
        },
        items:
            games.asMap().entries.map<DropdownMenuItem<int>>((entry) {
              final index = entry.key;
              final game = entry.value;
              final isLast = index == games.length - 1;

              return DropdownMenuItem<int>(
                value: index,
                child: SingleChildScrollView(
                  physics: const NeverScrollableScrollPhysics(),
                  child: Column(
                    children: [
                      _GameDropdownItem(
                        game: game,
                        gameNumber: index + 1,
                        isSelected: index == currentGameIndex,
                        isLoading: isLoading && index == currentGameIndex,
                      ),
                      if (!isLast)
                        Padding(
                          padding: EdgeInsets.symmetric(vertical: 5.h),
                          child: DividerWidget(),
                        ),
                    ],
                  ),
                ),
              );
            }).toList(),
      ),
    );
  }
}

class _GameDropdownItem extends StatelessWidget {
  final GamesTourModel game;
  final int gameNumber;
  final bool isSelected;
  final bool isLoading;

  const _GameDropdownItem({
    required this.game,
    required this.gameNumber,
    required this.isSelected,
    required this.isLoading,
  });

  String _formatName(String fullName, {double? maxWidth}) {
    List<String> nameParts =
        fullName.trim().split(' ').where((part) => part.isNotEmpty).toList();
    if (nameParts.length <= 1) return fullName;

    String familyName = nameParts.last;
    List<String> otherNames = nameParts.sublist(0, nameParts.length - 1);

    // Try full names first
    String fullVersion = '${otherNames.join(' ')} $familyName';

    // If no width constraint or it fits, return full version
    if (maxWidth == null) return fullVersion;

    // Estimate text width (rough approximation)
    double estimatedWidth =
        fullVersion.length * 5.0; // Approximate character width
    if (estimatedWidth <= maxWidth) return fullVersion;

    // If too long, progressively abbreviate from left to right
    List<String> displayNames = List.from(otherNames);

    for (int i = 0; i < displayNames.length; i++) {
      if (displayNames[i].length > 1) {
        displayNames[i] = '${displayNames[i][0]}.';
        String newVersion = '${displayNames.join(' ')} $familyName';
        double newEstimatedWidth = newVersion.length * 5.0;
        if (newEstimatedWidth <= maxWidth) {
          return newVersion;
        }
      }
    }

    // Fallback: all abbreviated
    return '${displayNames.join(' ')} $familyName';
  }

  String _getRoundLabel(GamesTourModel game) {
    final slug = game.roundSlug;
    if (slug == null || slug.isEmpty) {
      return 'R:';
    }

    // Try to extract number from various patterns
    // Examples: "round-12", "rapid-8", "blitz-8", "13", "game-4", "losers-r3--armageddon"
    final patterns = [
      RegExp(r'round[-\s]?(\d+)', caseSensitive: false), // round-12, round 12
      RegExp(r'rapid[-\s]?(\d+)', caseSensitive: false), // rapid-8
      RegExp(r'blitz[-\s]?(\d+)', caseSensitive: false), // blitz-8
      RegExp(r'^(\d+)$'), // just a number like "13"
      RegExp(r'r(\d+)', caseSensitive: false), // r3 in losers-r3
      RegExp(r'game[-\s]?(\d+)', caseSensitive: false), // game-4
    ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(slug);
      if (match != null) {
        final roundNumber = match.group(1);
        return 'R$roundNumber:';
      }
    }

    // If no pattern matches, return a simplified version
    return 'R:';
  }

  Widget _buildStatusIcon() {
    if (isLoading) {
      return SizedBox(
        width: 16.w,
        height: 16.h,
        child: const CircularProgressIndicator(
          strokeWidth: 1.5,
          color: kPrimaryColor,
        ),
      );
    }

    switch (game.gameStatus) {
      case GameStatus.whiteWins:
        return Container(
          width: 16.w,
          height: 16.h,
          alignment: Alignment.center,
          child: Text(
            '1',
            style: AppTypography.textXsBold.copyWith(
              color: kWhiteColor,
              fontSize: 12.sp,
            ),
          ),
        );
      case GameStatus.blackWins:
        return Container(
          width: 16.w,
          height: 16.h,
          alignment: Alignment.center,
          child: Text(
            '0',
            style: AppTypography.textXsBold.copyWith(
              color: kWhiteColor,
              fontSize: 12.sp,
            ),
          ),
        );
      case GameStatus.draw:
        return Container(
          width: 16.w,
          height: 16.h,
          alignment: Alignment.center,
          child: Text(
            '½',
            style: AppTypography.textXsBold.copyWith(
              color: kWhiteColor,
              fontSize: 12.sp,
            ),
          ),
        );
      case GameStatus.ongoing:
        return SvgPicture.asset(
          SvgAsset.selectedSvg,
          width: 16.w,
          height: 16.h,
        );
      case GameStatus.unknown:
        return SvgPicture.asset(
          SvgAsset.calendarIcon,
          width: 16.w,
          height: 16.h,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(
          child: Text(
            '${_getRoundLabel(game)} ${_formatName(game.whitePlayer.name, maxWidth: 65)} vs ${_formatName(game.blackPlayer.name, maxWidth: 65)}',
            style: AppTypography.textXsRegular.copyWith(color: kWhiteColor70),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        SizedBox(width: 8.w),
        _buildStatusIcon(),
      ],
    );
  }
}

class _BottomNavBar extends ConsumerWidget {
  final int index;
  final ChessBoardStateNew state;
  final GamesTourModel game;

  const _BottomNavBar({
    required this.index,
    required this.state,
    required this.game,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final params = ChessBoardProviderParams(game: game, index: index);
    final notifier = ref.read(chessBoardScreenProviderNew(params).notifier);

    return ChessBoardBottomNavBar(
      gameIndex: index,
      onFlip: () => notifier.flipBoard(),
      onRightMove: state.canMoveForward ? () => notifier.moveForward() : null,
      onLeftMove: state.canMoveBackward ? () => notifier.moveBackward() : null,
      onLongPressBackwardStart: () => notifier.startLongPressBackward(),
      onLongPressBackwardEnd: () => notifier.stopLongPress(),
      onLongPressForwardStart: () => notifier.startLongPressForward(),
      onLongPressForwardEnd: () => notifier.stopLongPress(),
      canMoveForward: state.canMoveForward,
      canMoveBackward: state.canMoveBackward,
      isAnalysisMode: state.isAnalysisMode,
      toggleAnalysisMode: () => notifier.toggleAnalysisMode(),
    );
  }
}

class _GameBody extends StatelessWidget {
  final int index;
  final int currentPageIndex;
  final GamesTourModel game;
  final ChessBoardStateNew state;

  const _GameBody({
    required this.index,
    required this.currentPageIndex,
    required this.game,
    required this.state,
  });

  @override
  Widget build(BuildContext context) {
    if (state.isAnalysisMode) {
      return _AnalysisGameBody(
        index: index,
        currentPageIndex: currentPageIndex,
        game: game,
        state: state,
      );
    }

    return Column(
      children: [
        _PlayerWidget(
          game: game,
          isFlipped: state.isBoardFlipped,
          blackPlayer: false,
          state: state,
        ),
        SizedBox(height: 2.h),
        _BoardWithSidebar(
          index: index,
          currentPageIndex: currentPageIndex,
          state: state,
          game: game,
        ),
        SizedBox(height: 2.h),
        _PlayerWidget(
          game: game,
          isFlipped: state.isBoardFlipped,
          blackPlayer: true,
          state: state,
        ),
        Expanded(
          child: Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: kDarkGreyColor.withValues(alpha: 0.3),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(12.sp),
                topRight: Radius.circular(12.sp),
              ),
            ),
            child: NotificationListener<ScrollNotification>(
              onNotification: (notification) {
                if (notification is ScrollStartNotification) {
                  // additional logic hook
                }
                return false;
              },
              child: SingleChildScrollView(
                scrollDirection: Axis.vertical,
                physics: const ClampingScrollPhysics(),
                dragStartBehavior: DragStartBehavior.down,
                child: GestureDetector(
                  onHorizontalDragStart: (_) {},
                  onHorizontalDragUpdate: (_) {},
                  onHorizontalDragEnd: (_) {},
                  behavior: HitTestBehavior.translucent,
                  child: _MovesDisplay(
                    index: index,
                    currentPageIndex: currentPageIndex,
                    state: state,
                    game: game,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _AnalysisGameBody extends ConsumerWidget {
  final int index;
  final int currentPageIndex;
  final GamesTourModel game;
  final ChessBoardStateNew state;

  const _AnalysisGameBody({
    required this.index,
    required this.currentPageIndex,
    required this.game,
    required this.state,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      children: [
        _PlayerWidget(
          game: game,
          isFlipped: state.isBoardFlipped,
          blackPlayer: false,
          state: state,
        ),
        SizedBox(height: 2.h),
        _BoardWithSidebar(
          index: index,
          currentPageIndex: currentPageIndex,
          state: state,
          game: game,
        ),
        if (state.principalVariations.isNotEmpty)
          _PrincipalVariationList(index: index, state: state, game: game),
        SizedBox(height: 2.h),
        _PlayerWidget(
          game: game,
          isFlipped: state.isBoardFlipped,
          blackPlayer: true,
          state: state,
        ),
        _AnalysisControlsRow(index: index, game: game),
        Expanded(
          child: Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: kDarkGreyColor.withValues(alpha: 0.3),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(12.sp),
                topRight: Radius.circular(12.sp),
              ),
            ),
            child: NotificationListener<ScrollNotification>(
              onNotification: (notification) {
                if (notification is ScrollStartNotification) {
                  // placeholder hook
                }
                return false;
              },
              child: SingleChildScrollView(
                scrollDirection: Axis.vertical,
                physics: const ClampingScrollPhysics(),
                dragStartBehavior: DragStartBehavior.down,
                child: GestureDetector(
                  onHorizontalDragStart: (_) {},
                  onHorizontalDragUpdate: (_) {},
                  onHorizontalDragEnd: (_) {},
                  behavior: HitTestBehavior.translucent,
                  child: _MovesDisplay(
                    index: index,
                    currentPageIndex: currentPageIndex,
                    state: state,
                    game: game,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _AnalysisControlsRow extends ConsumerWidget {
  final int index;
  final GamesTourModel game;

  const _AnalysisControlsRow({required this.index, required this.game});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final params = ChessBoardProviderParams(game: game, index: index);
    final state = ref.watch(chessBoardScreenProviderNew(params)).valueOrNull;
    final notifier = ref.read(chessBoardScreenProviderNew(params).notifier);

    // Use variants when available; default to first PV if none explicitly selected
    final hasVariant = state?.principalVariations.isNotEmpty ?? false;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 8.sp, vertical: 4.sp),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            icon: const Icon(Icons.fast_rewind, color: kWhiteColor),
            onPressed: notifier.jumpToStart,
          ),
          IconButton(
            icon: Icon(
              Icons.arrow_back,
              color:
                  hasVariant ? kWhiteColor.withValues(alpha: 0.7) : kWhiteColor,
            ),
            onPressed: () {
              debugPrint('🎯 NAV BACK: hasVariant=$hasVariant');
              if (hasVariant) {
                notifier.playVariantMoveBackward();
              } else {
                notifier.analysisStepBackward();
              }
            },
          ),
          IconButton(
            icon: Icon(
              Icons.arrow_forward,
              color:
                  hasVariant ? kWhiteColor.withValues(alpha: 0.7) : kWhiteColor,
            ),
            onPressed: () {
              debugPrint('🎯 NAV FORWARD: hasVariant=$hasVariant');
              if (hasVariant) {
                notifier.playVariantMoveForward();
              } else {
                notifier.analysisStepForward();
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.fast_forward, color: kWhiteColor),
            onPressed: notifier.jumpToEnd,
          ),
        ],
      ),
    );
  }
}

class _PlayerWidget extends StatelessWidget {
  final GamesTourModel game;
  final bool isFlipped;
  final bool blackPlayer;
  final ChessBoardStateNew state;

  const _PlayerWidget({
    required this.game,
    required this.isFlipped,
    required this.blackPlayer,
    required this.state,
  });

  @override
  Widget build(BuildContext context) {
    // Determine if this is the white player
    final isWhitePlayer =
        (blackPlayer && !isFlipped) || (!blackPlayer && isFlipped);

    final currentPosition =
        state.isAnalysisMode ? state.analysisState.position : state.position;

    // Check whose turn it is currently
    final currentTurn = currentPosition?.turn ?? Side.white;
    final isCurrentPlayer =
        (isWhitePlayer && currentTurn == Side.white) ||
        (!isWhitePlayer && currentTurn == Side.black);

    return PlayerFirstRowDetailWidget(
      isCurrentPlayer: isCurrentPlayer,
      isWhitePlayer: isWhitePlayer,
      playerView: PlayerView.boardView,
      gamesTourModel: game,
      chessBoardState: state, // Pass the state for move time calculation
    );
  }
}

class _BoardWithSidebar extends ConsumerWidget {
  final int index;
  final ChessBoardStateNew state;
  final int currentPageIndex;
  final GamesTourModel game;

  const _BoardWithSidebar({
    required this.index,
    required this.state,
    required this.currentPageIndex,
    required this.game,
  });

  String? _getLastMoveSquare() {
    // Use analysis state when in analysis mode, otherwise use live state
    final lastMove =
        state.isAnalysisMode ? state.analysisState.lastMove : state.lastMove;
    if (lastMove == null) return null;
    if (lastMove is NormalMove) {
      return lastMove.to.name;
    }
    return null;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final sideBarWidth = 20.w;
        final screenWidth = MediaQuery.of(context).size.width;
        final boardSize = screenWidth - sideBarWidth - 32.w;

        // Select correct state fields based on mode
        final moves =
            state.isAnalysisMode
                ? state.analysisState.allMoves
                : state.allMoves;
        final sans =
            state.isAnalysisMode
                ? state.analysisState.moveSans
                : state.moveSans;
        final startPos =
            state.isAnalysisMode
                ? state.analysisState.startingPosition
                : state.startingPosition;
        final currentIndex =
            state.isAnalysisMode
                ? state.analysisState.currentMoveIndex
                : state.currentMoveIndex;

        // Evaluate ALL moves from PGN and get current move impact from the map - ONLY if this page is visible
        Map<int, MoveImpactAnalysis>? allMovesImpact;
        MoveImpactAnalysis? currentMoveImpact;

        // Watch impacts using provider params to avoid analysis mode rebuild loops
        if (index == currentPageIndex && state.allMoves.isNotEmpty) {
          final params = ChessBoardProviderParams(game: game, index: index);
          final impactsAsync = ref.watch(gameMovesImpactProvider(params));
          allMovesImpact = impactsAsync.whenOrNull(data: (data) => data);

          if (allMovesImpact != null && currentIndex >= 0) {
            currentMoveImpact = allMovesImpact[currentIndex];
          }
        }

        return Container(
          margin: EdgeInsets.symmetric(horizontal: 16.sp),
          child: Row(
            children: [
              EvaluationBarWidget(
                width: sideBarWidth,
                height: boardSize,
                index: index,
                isFlipped: state.isBoardFlipped,
                evaluation: state.evaluation,
                mate: state.mate ?? 0,
                isEvaluating: state.isEvaluating,
              ),
              Stack(
                children: [
                  state.isAnalysisMode
                      ? _AnalysisBoard(
                        size: boardSize,
                        chessBoardState: state,
                        isFlipped: state.isBoardFlipped,
                        index: index,
                        game: state.game,
                      )
                      : _ChessBoardNew(
                        size: boardSize,
                        chessBoardState: state,
                        isFlipped: state.isBoardFlipped,
                      ),
                  // Add move annotation overlay - only show if impact is not normal
                  if (currentMoveImpact != null &&
                      currentMoveImpact.impact != MoveImpactType.normal &&
                      !(state.isAnalysisMode &&
                          state.selectedVariantIndex != null))
                    BoardMoveAnnotation(
                      moveImpact: currentMoveImpact,
                      boardSize: boardSize,
                      isFlipped: state.isBoardFlipped,
                      lastMoveSquare: _getLastMoveSquare(),
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ChessBoardNew extends ConsumerWidget {
  final double size;
  final ChessBoardStateNew chessBoardState;
  final bool isFlipped;

  const _ChessBoardNew({
    required this.size,
    required this.chessBoardState,
    this.isFlipped = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final boardSettingsValue = ref.watch(boardSettingsProvider);
    final boardTheme = ref
        .read(boardSettingsRepository)
        .getBoardTheme(boardSettingsValue.boardColor);

    return Chessboard.fixed(
      size: size,
      settings: ChessboardSettings(
        colorScheme: ChessboardColorScheme(
          lightSquare: boardTheme.lightSquareColor,
          darkSquare: boardTheme.darkSquareColor,
          background: SolidColorChessboardBackground(
            lightSquare: boardTheme.lightSquareColor,
            darkSquare: boardTheme.darkSquareColor,
          ),
          whiteCoordBackground: SolidColorChessboardBackground(
            lightSquare: boardTheme.lightSquareColor,
            darkSquare: boardTheme.darkSquareColor,
            coordinates: true,
            orientation: Side.white,
          ),
          blackCoordBackground: SolidColorChessboardBackground(
            lightSquare: boardTheme.lightSquareColor,
            darkSquare: boardTheme.darkSquareColor,
            coordinates: true,
            orientation: Side.black,
          ),
          lastMove: HighlightDetails(
            solidColor: getLastMoveHighlightColor(chessBoardState),
          ),
          selected: const HighlightDetails(solidColor: kPrimaryColor),
          validMoves: kPrimaryColor,
          validPremoves: kPrimaryColor,
        ),
      ),
      orientation: isFlipped ? Side.black : Side.white,
      shapes: chessBoardState.shapes,
      fen:
          chessBoardState.isLoadingMoves
              ? (chessBoardState.fenData ?? "")
              : chessBoardState.position!.fen,
      lastMove:
          chessBoardState.isLoadingMoves ? null : chessBoardState.lastMove,
    );
  }
}

class _AnalysisBoard extends ConsumerWidget {
  final double size;
  final ChessBoardStateNew chessBoardState;
  final bool isFlipped;
  final int index;
  final GamesTourModel game;

  const _AnalysisBoard({
    required this.size,
    required this.chessBoardState,
    this.isFlipped = false,
    required this.index,
    required this.game,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final boardSettingsValue = ref.watch(boardSettingsProvider);
    final boardTheme = ref
        .read(boardSettingsRepository)
        .getBoardTheme(boardSettingsValue.boardColor);
    final params = ChessBoardProviderParams(game: game, index: index);
    final notifier = ref.read(chessBoardScreenProviderNew(params).notifier);

    return Chessboard(
      size: size,
      settings: ChessboardSettings(
        enableCoordinates: true,

        animationDuration: const Duration(milliseconds: 200),
        dragFeedbackScale: 1,
        dragTargetKind: DragTargetKind.none,
        pieceShiftMethod: PieceShiftMethod.either,
        autoQueenPromotionOnPremove: false,
        pieceOrientationBehavior: PieceOrientationBehavior.facingUser,
        colorScheme: ChessboardColorScheme(
          lightSquare: boardTheme.lightSquareColor,
          darkSquare: boardTheme.darkSquareColor,
          background: SolidColorChessboardBackground(
            lightSquare: boardTheme.lightSquareColor,
            darkSquare: boardTheme.darkSquareColor,
          ),
          whiteCoordBackground: SolidColorChessboardBackground(
            lightSquare: boardTheme.lightSquareColor,
            darkSquare: boardTheme.darkSquareColor,
            coordinates: true,
            orientation: Side.white,
          ),
          blackCoordBackground: SolidColorChessboardBackground(
            lightSquare: boardTheme.lightSquareColor,
            darkSquare: boardTheme.darkSquareColor,
            coordinates: true,
            orientation: Side.black,
          ),
          lastMove: HighlightDetails(
            solidColor: getAnalysisLastMoveHighlightColor(chessBoardState),
          ),
          selected: const HighlightDetails(solidColor: kPrimaryColor),
          validMoves: kPrimaryColor,
          validPremoves: kPrimaryColor,
        ),
      ),
      orientation: isFlipped ? Side.black : Side.white,
      fen: chessBoardState.analysisState.position.fen,
      lastMove: chessBoardState.analysisState.lastMove,
      shapes: chessBoardState.shapes,
      game: GameData(
        playerSide:
            chessBoardState.analysisState.position.turn == Side.white
                ? PlayerSide.white
                : PlayerSide.black,
        validMoves: chessBoardState.analysisState.validMoves,
        sideToMove: chessBoardState.analysisState.position.turn,
        isCheck: chessBoardState.analysisState.position.isCheck,
        promotionMove: chessBoardState.analysisState.promotionMove,
        onMove: notifier.onAnalysisMove,
        onPromotionSelection: notifier.onAnalysisPromotionSelection,
      ),
    );
  }
}

class _MovesDisplay extends ConsumerWidget {
  final int index;
  final ChessBoardStateNew state;
  final GamesTourModel game;
  final int currentPageIndex;

  const _MovesDisplay({
    required this.state,
    required this.index,
    required this.game,
    required this.currentPageIndex,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (state.isLoadingMoves) {
      return _buildMovesLoadingSkeleton();
    }

    // Select correct state fields based on mode
    final moves =
        state.isAnalysisMode ? state.analysisState.allMoves : state.allMoves;
    final sans =
        state.isAnalysisMode ? state.analysisState.moveSans : state.moveSans;
    final startPos =
        state.isAnalysisMode
            ? state.analysisState.startingPosition
            : state.startingPosition;

    if (sans.isEmpty && !state.isLoadingMoves) {
      return Container(
        alignment: Alignment.center,
        padding: EdgeInsets.all(20.sp),
        child: Text(
          "No moves available for this game",
          style: AppTypography.textXsMedium.copyWith(
            color: kWhiteColor70,
            fontWeight: FontWeight.normal,
          ),
        ),
      );
    }

    // Watch impacts using provider params to avoid analysis mode rebuild loops
    Map<int, MoveImpactAnalysis>? allMovesImpact;
    if (index == currentPageIndex && state.allMoves.isNotEmpty) {
      final params = ChessBoardProviderParams(game: game, index: index);
      final impactsAsync = ref.watch(gameMovesImpactProvider(params));
      allMovesImpact = impactsAsync.whenOrNull(data: (data) => data);
    }

    return Container(
      alignment: Alignment.centerLeft,
      padding: EdgeInsets.all(20.sp),
      child: Wrap(
        spacing: 2.sp,
        runSpacing: 2.sp,
        children:
            sans.asMap().entries.map((entry) {
              final moveIndex = entry.key;
              final move = entry.value;

              // Use mode-aware current index for highlighting
              final modeAwareCurrentIndex =
                  state.isAnalysisMode
                      ? state.analysisState.currentMoveIndex
                      : state.currentMoveIndex;
              final isCurrentMove = moveIndex == modeAwareCurrentIndex;
              final fullMoveNumber = (moveIndex / 2).floor() + 1;
              final isWhiteMove = moveIndex % 2 == 0;

              // Get impact from the map
              final impact = allMovesImpact?[moveIndex];

              // Check if this is a variant-explored move (user made manual analysis moves)
              final isVariantMove =
                  state.isAnalysisMode &&
                  moveIndex >= (state.variantBaseMoveIndex ?? state.allMoves.length);

              final displayText = isWhiteMove ? '$fullMoveNumber. $move' : move;
              final impactSymbol = impact?.impact.symbol ?? '';

              // Determine text color - PRIORITY: impact color > variant > current move > default
              final params = ChessBoardProviderParams(game: game, index: index);
              Color textColor;
              Color? backgroundColor;

              if (impact != null && impact.impact != MoveImpactType.normal) {
                // Impact color has highest priority (even when selected)
                textColor = impact.impact.color;
              } else if (isVariantMove) {
                // Variant moves get special coloring
                textColor = kPrimaryColor;
                backgroundColor = kPrimaryColor.withValues(alpha: 0.2);
              } else if (isCurrentMove) {
                textColor = kWhiteColor;
              } else {
                textColor = ref
                    .read(chessBoardScreenProviderNew(params).notifier)
                    .getMoveColor(move, moveIndex);
              }

              return GestureDetector(
                onTap:
                    () => ref
                        .read(chessBoardScreenProviderNew(params).notifier)
                        .goToMove(moveIndex),
                child: Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: 6.sp,
                    vertical: 2.sp,
                  ),
                  decoration: BoxDecoration(
                    color:
                        backgroundColor ??
                        (isCurrentMove
                            ? kWhiteColor70.withValues(alpha: 0.4)
                            : Colors.transparent),
                    borderRadius: BorderRadius.circular(4.sp),
                    border: Border.all(
                      color: isCurrentMove ? kWhiteColor : Colors.transparent,
                      width: 0.5,
                    ),
                  ),
                  child: RichText(
                    text: TextSpan(
                      children: [
                        TextSpan(
                          text: displayText,
                          style: AppTypography.textXsMedium.copyWith(
                            color: textColor,
                            fontWeight:
                                isCurrentMove
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                          ),
                        ),
                        if (impactSymbol.isNotEmpty)
                          TextSpan(
                            text: impactSymbol,
                            style: AppTypography.textXsMedium.copyWith(
                              color: impact!.impact.color,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
      ),
    );
  }

  Widget _buildMovesLoadingSkeleton() {
    return Container(
      alignment: Alignment.centerLeft,
      padding: EdgeInsets.all(20.sp),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SkeletonContainer(height: 16.h, width: 80.w, borderRadius: 4.sp),
          SizedBox(height: 12.h),
          ...List.generate(6, (rowIndex) {
            return Padding(
              padding: EdgeInsets.only(bottom: 8.h),
              child: Wrap(
                spacing: 8.sp,
                children: [
                  _SkeletonContainer(
                    height: 14.h,
                    width: (60 + (rowIndex % 3) * 20).w,
                    borderRadius: 3.sp,
                  ),
                  _SkeletonContainer(
                    height: 14.h,
                    width: (45 + (rowIndex % 4) * 15).w,
                    borderRadius: 3.sp,
                  ),
                ],
              ),
            );
          }),
          SizedBox(height: 8.h),
          Wrap(
            spacing: 6.sp,
            runSpacing: 6.sp,
            children: List.generate(8, (index) {
              return _SkeletonContainer(
                height: 14.h,
                width: (35 + (index % 5) * 20).w,
                borderRadius: 3.sp,
              );
            }),
          ),
        ],
      ),
    );
  }
}

class _PrincipalVariationList extends ConsumerWidget {
  final int index;
  final ChessBoardStateNew state;
  final GamesTourModel game;

  const _PrincipalVariationList({
    required this.index,
    required this.state,
    required this.game,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lines = state.principalVariations.take(3).toList();
    if (lines.isEmpty) {
      return const SizedBox.shrink();
    }

    final params = ChessBoardProviderParams(game: game, index: index);
    final notifier = ref.read(chessBoardScreenProviderNew(params).notifier);
    final position =
        state.isAnalysisMode ? state.analysisState.position : state.position;
    final baseMoveNumber = position?.fullmoves ?? 1;
    final isWhiteToMove = (position?.turn ?? Side.white) == Side.white;

    return Padding(
      padding: EdgeInsets.fromLTRB(20.sp, 20.sp, 20.sp, 8.sp),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        transitionBuilder:
            (child, animation) => FadeTransition(
              opacity: animation,
              child: SizeTransition(
                sizeFactor: animation,
                axisAlignment: -1,
                child: child,
              ),
            ),
        child: Column(
          key: ValueKey(
            lines
                .map((line) => '${line.sanMoves.join(' ')}|${line.displayEval}')
                .join('|'),
          ),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'Engine suggestions (${lines.length})',
                  style: AppTypography.textSmMedium.copyWith(
                    color: kWhiteColor,
                  ),
                ),
                const Spacer(),
                if (lines.length > 1)
                  Row(
                    children: [
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        iconSize: 18.sp,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed: () => notifier.cycleVariant(-1),
                        icon: const Icon(
                          Icons.chevron_left,
                          color: kWhiteColor,
                        ),
                      ),
                      SizedBox(width: 8.w),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        iconSize: 18.sp,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed: () => notifier.cycleVariant(1),
                        icon: const Icon(
                          Icons.chevron_right,
                          color: kWhiteColor,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
            SizedBox(height: 8.h),
            SizedBox(
              height: 78.h,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: lines.length,
                itemBuilder: (context, index) {
                  final variantIndex = index;
                  final line = lines[index];
                  final isSelected = state.selectedVariantIndex == variantIndex;

                  final sanMoves = _formatPv(
                    line.sanMoves,
                    baseMoveNumber,
                    isWhiteToMove,
                  );
                  final evalText = _formatEvalLabel(line);
                  final evalBackground = _variantEvalBackground(line);
                  final evalBorder = _variantEvalBorder(line, isSelected);

                  // Get variant color matching the arrow color
                  final variantColor = notifier.getVariantColor(variantIndex, isSelected);

                  return Padding(
                    padding: EdgeInsets.only(
                      right: index < lines.length - 1 ? 8.sp : 0,
                    ),
                    child: GestureDetector(
                      onTap: () {
                        HapticFeedback.selectionClick();
                        if (isSelected) {
                          notifier.playVariantMoveForward();
                        } else {
                          notifier.playPrincipalVariationMove(line);
                        }
                      },
                      child: Container(
                        width: MediaQuery.of(context).size.width - 40.sp,
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: variantColor.withValues(alpha: isSelected ? 0.7 : 0.4),
                            width: isSelected ? 2.0 : 1.5,
                          ),
                          borderRadius: BorderRadius.circular(6.sp),
                          color:
                              isSelected
                                  ? variantColor.withValues(alpha: 0.15)
                                  : variantColor.withValues(alpha: 0.05),
                        ),
                        padding: EdgeInsets.symmetric(
                          horizontal: 12.sp,
                          vertical: 10.sp,
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              margin: EdgeInsets.only(right: 10.sp),
                              padding: EdgeInsets.symmetric(
                                horizontal: 8.sp,
                                vertical: 4.sp,
                              ),
                              decoration: BoxDecoration(
                                color: evalBackground,
                                borderRadius: BorderRadius.circular(4.sp),
                                border: Border.all(
                                  color: evalBorder,
                                  width: 0.8,
                                ),
                              ),
                              alignment: Alignment.center,
                              child: AnimatedSwitcher(
                                duration: const Duration(milliseconds: 200),
                                child: Text(
                                  evalText,
                                  key: ValueKey(evalText),
                                  style: AppTypography.textXsMedium.copyWith(
                                    color: kWhiteColor,
                                    fontWeight:
                                        isSelected
                                            ? FontWeight.w600
                                            : FontWeight.w500,
                                  ),
                                ),
                              ),
                            ),
                            Expanded(
                              child: Text(
                                sanMoves.join(' '),
                                style: AppTypography.textXsMedium.copyWith(
                                  color: kWhiteColor.withValues(alpha: 0.9),
                                  fontWeight:
                                      isSelected
                                          ? FontWeight.w600
                                          : FontWeight.normal,
                                ),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 3,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<String> _formatPv(
    List<String> sanMoves,
    int baseMoveNumber,
    bool whiteToMove,
  ) {
    final formatted = <String>[];
    for (var i = 0; i < sanMoves.length; i++) {
      final moveOffset = i ~/ 2;
      final moveNumber = baseMoveNumber + moveOffset;
      final isWhiteMove = whiteToMove ? i.isEven : i.isOdd;
      final prefix = isWhiteMove ? '$moveNumber.' : '$moveNumber...';
      formatted.add('$prefix ${sanMoves[i]}');
    }
    return formatted;
  }

  String _formatEvalLabel(AnalysisLine line) {
    if (line.isMate) {
      final mate = line.mate ?? 0;
      final absMate = mate.abs();
      final prefix = mate >= 0 ? '#+' : '#-';
      return '$prefix$absMate';
    }

    final eval = line.evaluation;
    if (eval == null) {
      return '--';
    }

    final formatted = eval.abs().toStringAsFixed(1);
    return eval >= 0 ? '+$formatted' : '-$formatted';
  }

  Color _variantEvalBackground(AnalysisLine line) {
    if (line.isMate) {
      final mate = line.mate ?? 0;
      return mate >= 0
          ? kPrimaryColor.withValues(alpha: 0.35)
          : kRedColor.withValues(alpha: 0.35);
    }

    final eval = line.evaluation ?? 0;
    if (eval >= 1.5) {
      return kPrimaryColor.withValues(alpha: 0.35);
    }
    if (eval <= -1.5) {
      return kRedColor.withValues(alpha: 0.35);
    }
    return kWhiteColor.withValues(alpha: 0.08);
  }

  Color _variantEvalBorder(AnalysisLine line, bool isSelected) {
    if (isSelected) {
      return kWhiteColor.withValues(alpha: 0.5);
    }
    if (line.isMate) {
      final mate = line.mate ?? 0;
      return mate >= 0
          ? kPrimaryColor.withValues(alpha: 0.55)
          : kRedColor.withValues(alpha: 0.55);
    }
    final eval = line.evaluation ?? 0;
    if (eval >= 1.5) {
      return kPrimaryColor.withValues(alpha: 0.45);
    }
    if (eval <= -1.5) {
      return kRedColor.withValues(alpha: 0.45);
    }
    return kWhiteColor.withValues(alpha: 0.15);
  }
}

class _SkeletonContainer extends StatefulWidget {
  final double height;
  final double width;
  final double borderRadius;

  const _SkeletonContainer({
    required this.height,
    required this.width,
    required this.borderRadius,
  });

  @override
  State<_SkeletonContainer> createState() => _SkeletonContainerState();
}

class _SkeletonContainerState extends State<_SkeletonContainer>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );
    _animation = Tween<double>(begin: 0.3, end: 0.7).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
    _animationController.repeat(reverse: true);
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Container(
          height: widget.height,
          width: widget.width,
          decoration: BoxDecoration(
            color: kWhiteColor.withValues(alpha: _animation.value * 0.15),
            borderRadius: BorderRadius.circular(widget.borderRadius),
          ),
        );
      },
    );
  }
}
