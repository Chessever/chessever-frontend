import 'package:chessever2/providers/board_settings_provider.dart';
import 'package:chessever2/repository/local_storage/board_settings_repository/board_settings_repository.dart';
import 'package:chessever2/screens/chessboard/analysis/chess_game_navigator.dart';
import 'package:chessever2/screens/chessboard/analysis/chess_line_display.dart';
import 'package:chessever2/screens/chessboard/analysis/move_impact_analyzer.dart';
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
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:chessever2/utils/svg_asset.dart';
import 'package:chessever2/widgets/divider_widget.dart';
import 'package:flutter_svg/svg.dart';

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
        ref.read(currentlyVisiblePageIndexProvider.notifier).state = _currentPageIndex;
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
            .read(chessBoardScreenProviderNew(ChessBoardProviderParams(
              game: prevGame,
              index: previousIndex,
            )).notifier)
            .pauseGame();
      } catch (e) {
        // Provider was disposed, which is fine
      }
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        try {
          final newGame = widget.games[newIndex];
          ref.read(chessBoardScreenProviderNew(ChessBoardProviderParams(
            game: newGame,
            index: newIndex,
          )).notifier).parseMoves();
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
          .read(chessBoardScreenProviderNew(ChessBoardProviderParams(
            game: currentGame,
            index: _currentPageIndex,
          )).notifier)
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
      chessBoardScreenProviderNew(ChessBoardProviderParams(
        game: currentGame,
        index: _currentPageIndex,
      )),
      (prev, next) {
        if (prev?.valueOrNull?.currentMoveIndex !=
                next.valueOrNull?.currentMoveIndex &&
            next.valueOrNull != null) {
          // CRITICAL FIX: Only play audio if this chess board screen is currently active
          // This prevents audio from playing when other games in the tournament get moves
          final route = ModalRoute.of(context);
          if (route == null || !route.isCurrent) {
            // Screen is not visible, don't play audio
            return;
          }

          final state = next.valueOrNull!;
          final prevIndex = prev?.valueOrNull?.currentMoveIndex ?? -1;
          final currentIndex = state.currentMoveIndex;

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

          // Check if we have a valid move to play sound for
          if (moveIndexForSound >= 0 &&
              moveIndexForSound < state.moveSans.length) {
            // Get the move notation for the appropriate move
            final moveSan = state.moveSans[moveIndexForSound];

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
          } else if (currentIndex == state.moveSans.length &&
              state.moveSans.isNotEmpty) {
            // We're at the end of the game, check for game-ending conditions
            final lastMoveSan = state.moveSans.last;

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
                      .watch(chessBoardScreenProviderNew(ChessBoardProviderParams(
                        game: game,
                        index: index,
                      )))
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
      bottomNavigationBar: _BottomNavBar(index: currentGameIndex, state: state, game: game),
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

  const _BottomNavBar({required this.index, required this.state, required this.game});

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
                    sanMoves: state.moveSans,
                    currentMoveIndex: state.currentMoveIndex,
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
            child: _AnalysisMovesDisplay(
              index: index,
              currentPageIndex: currentPageIndex,
              state: state,
              game: game,
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

    // Check if variant is selected - if so, forward button plays variant moves
    final hasSelectedVariant = state?.selectedVariantIndex != null;

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
              color: hasSelectedVariant ? kWhiteColor.withValues(alpha: 0.7) : kWhiteColor,
            ),
            onPressed: () {
              debugPrint('🎯 NAV BACK: hasSelectedVariant=$hasSelectedVariant');
              if (hasSelectedVariant) {
                notifier.playVariantMoveBackward();
              } else {
                notifier.analysisStepBackward();
              }
            },
          ),
          IconButton(
            icon: Icon(
              Icons.arrow_forward,
              color: hasSelectedVariant ? kWhiteColor.withValues(alpha: 0.7) : kWhiteColor,
            ),
            onPressed: () {
              debugPrint('🎯 NAV FORWARD: hasSelectedVariant=$hasSelectedVariant');
              if (hasSelectedVariant) {
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

class _AnalysisMovesDisplay extends ConsumerWidget {
  final int index;
  final ChessBoardStateNew state;
  final GamesTourModel game;
  final int currentPageIndex;

  const _AnalysisMovesDisplay({
    required this.index,
    required this.state,
    required this.game,
    required this.currentPageIndex,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final analysis = state.analysisState;
    final chessGame = analysis.game;

    if (state.isLoadingMoves) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(24.sp),
          child: CircularProgressIndicator(color: kGreenColor),
        ),
      );
    }

    // Get move impacts for colorful notation display - ONLY if this page is visible
    Map<int, MoveImpactAnalysis>? allMovesImpact;
    if (index == currentPageIndex) {
      // Use position-based analysis (has alternative move data for proper classification)
      // PGN-based analysis deprecated - cannot classify without alternatives
      if (state.allMoves.isNotEmpty) {
        final fensParams = PositionFensParams(
          allMoves: state.allMoves,
          startingPosition: state.startingPosition,
          gameId: game.gameId,
        );
        final positionFens = ref.watch(positionFensProvider(fensParams));

        final positionParams = PositionAnalysisParams(
          positionFens: positionFens,
          moveSans: state.moveSans,
          gameId: game.gameId,
        );

        final fallbackAsync = ref.watch(allMovesImpactFromPositionsProvider(positionParams));

        // Handle async states properly - don't lose data while loading
        fallbackAsync.when(
          data: (data) {
            allMovesImpact = data;
          },
          loading: () {
            // Loading...
          },
          error: (err, stack) {
            debugPrint('🎨 NOTATION (ChessLineDisplay): Error in position-based analysis: $err');
          },
        );
      }
    }

    // Watch navigator only if chess game is available - no loading spinner
    final navigatorState = chessGame != null
        ? ref.watch(chessGameNavigatorProvider(chessGame))
        : null;

    // Fallback: show moves from state if navigator not ready or chess game null
    if (navigatorState == null || chessGame == null) {
      if (state.moveSans.isEmpty) {
        return Center(
          child: Padding(
            padding: EdgeInsets.all(20.sp),
            child: Text(
              'No moves available for this game',
              style: AppTypography.textXsMedium.copyWith(
                color: kWhiteColor70,
                fontWeight: FontWeight.normal,
              ),
            ),
          ),
        );
      }

      // Display existing moves while navigator initializes
      return SingleChildScrollView(
        padding: EdgeInsets.all(20.sp),
        child: Wrap(
          spacing: 4.sp,
          runSpacing: 4.sp,
          children: state.moveSans.asMap().entries.map((entry) {
            final moveIndex = entry.key;
            final move = entry.value;
            final isCurrentMove = moveIndex == state.analysisState.currentMoveIndex;
            final fullMoveNumber = (moveIndex / 2).floor() + 1;
            final isWhiteMove = moveIndex % 2 == 0;
            final displayText = isWhiteMove ? '$fullMoveNumber. $move' : move;

            return Container(
              padding: EdgeInsets.symmetric(horizontal: 6.sp, vertical: 2.sp),
              decoration: BoxDecoration(
                color: isCurrentMove ? kWhiteColor70.withValues(alpha: 0.4) : Colors.transparent,
                borderRadius: BorderRadius.circular(4.sp),
              ),
              child: Text(
                displayText,
                style: AppTypography.textXsMedium.copyWith(
                  color: isCurrentMove ? kWhiteColor : kWhiteColor70,
                  fontWeight: isCurrentMove ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            );
          }).toList(),
        ),
      );
    }

    if (navigatorState.game.mainline.isEmpty) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(20.sp),
          child: Text(
            'No moves available for this game',
            style: AppTypography.textXsMedium.copyWith(
              color: kWhiteColor70,
              fontWeight: FontWeight.normal,
            ),
          ),
        ),
      );
    }

    return SingleChildScrollView(
      padding: EdgeInsets.all(20.sp),
      child: ChessLineDisplay(
        line: navigatorState.game.mainline,
        currentFen: navigatorState.currentFen,
        movePointer: const [], // Empty pointer for mainline - ChessLineDisplay builds child pointers
        allMovesImpact: allMovesImpact,
        onClick: (pointer) {
          final params = ChessBoardProviderParams(game: game, index: index);
          ref
              .read(chessBoardScreenProviderNew(params).notifier)
              .goToMovePointer(pointer);
        },
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
    if (state.lastMove == null) return null;
    if (state.lastMove is NormalMove) {
      final move = state.lastMove as NormalMove;
      return move.to.name;
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

        // Evaluate ALL moves from PGN and get current move impact from the map - ONLY if this page is visible
        Map<int, MoveImpactAnalysis>? allMovesImpact;
        MoveImpactAnalysis? currentMoveImpact;

        if (index == currentPageIndex) {
          // Use position-based analysis (has alternative move data for proper classification)
          // PGN-based analysis deprecated - cannot classify without alternatives
          if (state.allMoves.isNotEmpty) {
            final fensParams = PositionFensParams(
              allMoves: state.allMoves,
              startingPosition: state.startingPosition,
              gameId: game.gameId,
            );
            final positionFens = ref.watch(positionFensProvider(fensParams));

            final positionParams = PositionAnalysisParams(
              positionFens: positionFens,
              moveSans: state.moveSans,
              gameId: game.gameId,
            );

            final fallbackAsync = ref.watch(allMovesImpactFromPositionsProvider(positionParams));

            // Handle async states properly - don't lose data while loading
            fallbackAsync.when(
              data: (data) {
                allMovesImpact = data;
              },
              loading: () {
                // Loading...
              },
              error: (err, stack) {
                debugPrint('🎨 NOTATION (Board): Error in position-based analysis: $err');
              },
            );
          }

          // Get impact for current move from the map
          final impacts = allMovesImpact;
          if (impacts != null && state.currentMoveIndex >= 0) {
            currentMoveImpact = impacts[state.currentMoveIndex];
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
                  if (currentMoveImpact != null && currentMoveImpact.impact != MoveImpactType.normal)
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
  final List<String> sanMoves;
  final int currentMoveIndex;
  final GamesTourModel game;
  final int currentPageIndex;

  const _MovesDisplay({
    required this.state,
    required this.index,
    required this.sanMoves,
    required this.currentMoveIndex,
    required this.game,
    required this.currentPageIndex,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (state.isLoadingMoves) {
      return _buildMovesLoadingSkeleton();
    }

    if (sanMoves.isEmpty && !state.isLoadingMoves) {
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

    // Evaluate ALL moves from PGN in parallel - ONLY if this page is visible
    Map<int, MoveImpactAnalysis>? allMovesImpact;
    if (index == currentPageIndex) {
      // Use position-based analysis (has alternative move data for proper classification)
      // PGN-based analysis deprecated - cannot classify without alternatives
      if (state.allMoves.isNotEmpty) {
        final fensParams = PositionFensParams(
          allMoves: state.allMoves,
          startingPosition: state.startingPosition,
          gameId: game.gameId,
        );
        final positionFens = ref.watch(positionFensProvider(fensParams));

        final positionParams = PositionAnalysisParams(
          positionFens: positionFens,
          moveSans: state.moveSans,
          gameId: game.gameId,
        );

        final fallbackAsync = ref.watch(allMovesImpactFromPositionsProvider(positionParams));

        // Handle async states properly - don't lose data while loading
        fallbackAsync.when(
          data: (data) {
            allMovesImpact = data;
          },
          loading: () {
            // Loading...
          },
          error: (err, stack) {
            debugPrint('🎨 NOTATION (Wrap): Error in position-based analysis: $err');
          },
        );
      }
    }

    return Container(
      alignment: Alignment.centerLeft,
      padding: EdgeInsets.all(20.sp),
      child: Wrap(
        spacing: 2.sp,
        runSpacing: 2.sp,
        children:
            sanMoves.asMap().entries.map((entry) {
              final moveIndex = entry.key;
              final move = entry.value;

              final isCurrentMove = moveIndex == currentMoveIndex;
              final fullMoveNumber = (moveIndex / 2).floor() + 1;
              final isWhiteMove = moveIndex % 2 == 0;

              // Get impact from the map
              final impact = allMovesImpact?[moveIndex];

              final displayText = isWhiteMove ? '$fullMoveNumber. $move' : move;
              final impactSymbol = impact?.impact.symbol ?? '';

              // Determine text color - PRIORITY: impact color > current move > default
              final params = ChessBoardProviderParams(game: game, index: index);
              Color textColor;
              if (impact != null && impact.impact != MoveImpactType.normal) {
                // Impact color has highest priority (even when selected)
                textColor = impact.impact.color;
              } else if (isCurrentMove) {
                textColor = kWhiteColor;
              } else {
                textColor = ref.read(chessBoardScreenProviderNew(params).notifier).getMoveColor(move, moveIndex);
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
                        isCurrentMove
                            ? kWhiteColor70.withValues(alpha: 0.4)
                            : Colors.transparent,
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
                            fontWeight: isCurrentMove ? FontWeight.bold : FontWeight.normal,
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

  const _PrincipalVariationList({required this.index, required this.state, required this.game});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lines = state.principalVariations.take(2).toList();
    if (lines.isEmpty) {
      return const SizedBox.shrink();
    }

    final position =
        state.isAnalysisMode ? state.analysisState.position : state.position;
    final baseMoveNumber = position?.fullmoves ?? 1;
    final isWhiteToMove = (position?.turn ?? Side.white) == Side.white;

    return Padding(
      padding: EdgeInsets.fromLTRB(20.sp, 20.sp, 20.sp, 8.sp),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Engine suggestions',
            style: AppTypography.textSmMedium.copyWith(color: kWhiteColor),
          ),
          SizedBox(height: 8.h),
          ...lines.asMap().entries.map((entry) {
            final variantIndex = entry.key;
            final line = entry.value;
            final isSelected = state.selectedVariantIndex == variantIndex;

            final sanMoves = _formatPv(
              line.sanMoves,
              baseMoveNumber,
              isWhiteToMove,
            );
            final evalText = line.displayEval;

            final params = ChessBoardProviderParams(game: game, index: index);
            return GestureDetector(
              onTap: () {
                debugPrint('🎯 VARIANT TAP: Selecting variant $variantIndex');
                ref
                    .read(chessBoardScreenProviderNew(params).notifier)
                    .selectVariant(variantIndex);
              },
              child: Container(
                margin: EdgeInsets.only(bottom: 6.h),
                decoration: BoxDecoration(
                  border: isSelected
                      ? Border.all(color: kWhiteColor.withValues(alpha: 0.3), width: 1)
                      : Border.all(color: kWhiteColor.withValues(alpha: 0.1), width: 1),
                  borderRadius: BorderRadius.circular(6.sp),
                  color: isSelected
                      ? kWhiteColor.withValues(alpha: 0.08)
                      : kWhiteColor.withValues(alpha: 0.02),
                ),
                padding: EdgeInsets.symmetric(horizontal: 8.sp, vertical: 6.sp),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      margin: EdgeInsets.only(right: 8.sp),
                      decoration: BoxDecoration(
                        color: kWhiteColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4.sp),
                      ),
                      padding: EdgeInsets.symmetric(
                        horizontal: 6.sp,
                        vertical: 2.sp,
                      ),
                      child: Text(
                        evalText.isEmpty ? '—' : evalText,
                        style: AppTypography.textXsMedium.copyWith(
                          color: kWhiteColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        sanMoves.join(' '),
                        style: AppTypography.textXsMedium.copyWith(
                          color: kWhiteColor.withValues(alpha: 0.85),
                          fontWeight: isSelected ? FontWeight.w500 : FontWeight.normal,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 2,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
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
