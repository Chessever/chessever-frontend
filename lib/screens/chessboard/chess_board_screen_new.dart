import 'package:chessever2/providers/board_settings_provider.dart';
import 'package:chessever2/repository/local_storage/board_settings_repository/board_settings_repository.dart';
import 'package:chessever2/screens/chessboard/provider/chess_board_screen_provider_new.dart';
import 'package:chessever2/screens/chessboard/view_model/chess_board_state_new.dart';
import 'package:chessever2/screens/chessboard/widgets/chess_board_bottom_nav_bar.dart';
import 'package:chessever2/screens/chessboard/widgets/evaluation_bar_widget.dart';
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
    _currentPageIndex = widget.currentIndex;
    _pageController = PageController(initialPage: widget.currentIndex);
  }

  @override
  void didUpdateWidget(covariant ChessBoardScreenNew oldWidget) {
    super.didUpdateWidget(oldWidget);
  }

  void _onPageChanged(int newIndex) {
    if (_currentPageIndex == newIndex) return;

    _lastViewedIndex = newIndex;

    // Pause the current game before switching
    final view = ref.read(chessboardViewFromProviderNew);
    final gamesAsync =
        view == ChessboardView.tour
            ? ref.read(gamesTourScreenProvider)
            : ref.read(countrymanGamesTourScreenProvider);

    if (gamesAsync.hasValue && gamesAsync.value?.gamesTourModels != null) {
      try {
        ref
            .read(chessBoardScreenProviderNew(_currentPageIndex).notifier)
            .pauseGame();
      } catch (e) {
        // Provider might already be disposed, ignore
      }
    }

    // Update the current page index AFTER pausing the old game
    setState(() {
      _currentPageIndex = newIndex;
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _navigateToGame(int gameIndex) {
    if (gameIndex == _currentPageIndex) return;

    // Check if provider is available before trying to access it
    final view = ref.read(chessboardViewFromProviderNew);
    final gamesAsync =
        view == ChessboardView.tour
            ? ref.read(gamesTourScreenProvider)
            : ref.read(countrymanGamesTourScreenProvider);

    if (gamesAsync.hasValue && gamesAsync.value?.gamesTourModels != null) {
      try {
        ref
            .read(chessBoardScreenProviderNew(_currentPageIndex).notifier)
            .pauseGame();
      } catch (e) {
        // Provider might already be disposed, ignore
      }
    }

    _pageController.animateToPage(
      gameIndex,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(chessBoardScreenProviderNew(_currentPageIndex), (
      prev,
      next,
    ) {
      if (prev?.valueOrNull?.currentMoveIndex !=
          next.valueOrNull?.currentMoveIndex && next.valueOrNull != null) {
        final state = next.valueOrNull!;
        final prevIndex = prev?.valueOrNull?.currentMoveIndex ?? -1;
        final currentIndex = state.currentMoveIndex;
        final audioService = AudioPlayerService.instance;

        // Determine if we're going forward or backward
        final isMovingForward = currentIndex > prevIndex;

        // For backward navigation, we want to play the sound of the move we just "undid"
        // For forward navigation, we want to play the sound of the move we just made
        final moveIndexForSound = isMovingForward ? currentIndex : prevIndex;

        // Check if we have a valid move to play sound for
        if (moveIndexForSound >= 0 && moveIndexForSound < state.moveSans.length) {
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
        } else if (currentIndex == state.moveSans.length && state.moveSans.isNotEmpty) {
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
    },onError: (e,st) {
      debugPrint("Error in chessBoardScreenProviderNew listener: $e");
    });
    // Check if the required data is available before building the main content
    final view = ref.watch(chessboardViewFromProviderNew);
    final gamesAsync =
        view == ChessboardView.tour
            ? ref.watch(gamesTourScreenProvider)
            : ref.watch(countrymanGamesTourScreenProvider);

    // Show loading screen if data isn't ready
    if (!gamesAsync.hasValue || gamesAsync.value?.gamesTourModels == null) {
      return _LoadingScreen(
        games:
            widget.games.isNotEmpty
                ? widget.games
                : [widget.games.first], // Fallback for empty games
        currentGameIndex: _currentPageIndex.clamp(0, widget.games.length - 1),
        onGameChanged: (index) {}, // Disabled during loading
        lastViewedIndex: _lastViewedIndex,
      );
    }

    return WillPopScope(
      onWillPop: () async {
        Navigator.of(context).pop(_lastViewedIndex);
        return false;
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
            itemCount: widget.games.length,
            itemBuilder: (context, index) {
              // Build current page and adjacent pages
              if (index == _currentPageIndex - 1 ||
                  index == _currentPageIndex ||
                  index == _currentPageIndex + 1) {
                try {
                  return ref
                      .watch(chessBoardScreenProviderNew(index))
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
                            game: widget.games[index],
                            state: chessBoardState,
                            games: widget.games,
                            currentGameIndex: index,
                            onGameChanged: _navigateToGame,
                            lastViewedIndex: _lastViewedIndex,
                          );
                        },
                        error: (e, _) => ErrorWidget(e),
                        loading:
                            () => _LoadingScreen(
                              games: widget.games,
                              currentGameIndex: index,
                              onGameChanged: _navigateToGame,
                              lastViewedIndex: _lastViewedIndex,
                            ),
                      );
                } catch (e) {
                  // Fallback for when provider isn't ready
                  return _LoadingScreen(
                    games: widget.games,
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
  final void Function(int) onGameChanged;
  final int? lastViewedIndex;

  const _GamePage({
    required this.game,
    required this.state,
    required this.games,
    required this.currentGameIndex,
    required this.onGameChanged,
    this.lastViewedIndex,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      bottomNavigationBar: _BottomNavBar(index: currentGameIndex, state: state),
      appBar: _AppBar(
        game: game,
        games: games,
        currentGameIndex: currentGameIndex,
        onGameChanged: onGameChanged,
        lastViewedIndex: lastViewedIndex,
      ),
      body: _GameBody(index: currentGameIndex, game: game, state: state),
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
                '${_formatName(game.blackPlayer.displayName, maxWidth: 120)} vs ${_formatName(game.whitePlayer.displayName, maxWidth: 120)}',
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
            '${_formatName(game.whitePlayer.name, maxWidth: 80)} vs ${_formatName(game.blackPlayer.name, maxWidth: 80)}',
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

  const _BottomNavBar({required this.index, required this.state});

  @override
  Widget build(BuildContext context, WidgetRef ref) {

    return ChessBoardBottomNavBar(
      gameIndex: index,
      onFlip: () => ref.read(chessBoardScreenProviderNew(index).notifier).flipBoard(),
      onRightMove: state.canMoveForward ? () => ref.read(chessBoardScreenProviderNew(index).notifier).moveForward() : null,
      onLeftMove: state.canMoveBackward ? () => ref.read(chessBoardScreenProviderNew(index).notifier).moveBackward() : null,
      canMoveForward: state.canMoveForward,
      canMoveBackward: state.canMoveBackward,
      isAnalysisMode: state.isAnalysisMode,
      toggleAnalysisMode: () => ref.read(chessBoardScreenProviderNew(index).notifier).toggleAnalysisMode(),
    );
  }
}

class _GameBody extends StatelessWidget {
  final int index;
  final GamesTourModel game;
  final ChessBoardStateNew state;

  const _GameBody({
    required this.index,
    required this.game,
    required this.state,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _PlayerWidget(
          game: game,
          isFlipped: state.isBoardFlipped,
          blackPlayer: false,
          state: state,
        ),
        SizedBox(height: 2.h),
        _BoardWithSidebar(index: index, state: state),
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
              color: kDarkGreyColor.withOpacity(0.3),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(12.sp),
                topRight: Radius.circular(12.sp),
              ),
            ),
            child: NotificationListener<ScrollNotification>(
              onNotification: (notification) {
                // Allow only vertical scrolling
                if (notification is ScrollStartNotification) {
                  // You can add additional logic here if needed
                }
                return false; // Allow the notification to continue bubbling up
              },
              child: SingleChildScrollView(
                scrollDirection: Axis.vertical,
                physics: const ClampingScrollPhysics(),
                dragStartBehavior:
                    DragStartBehavior.down, // Start drag from down gesture
                child: GestureDetector(
                  onHorizontalDragStart: (_) {},
                  // Consume horizontal gestures
                  onHorizontalDragUpdate: (_) {},
                  onHorizontalDragEnd: (_) {},
                  behavior: HitTestBehavior.translucent,
                  child: _MovesDisplay(
                    index: index,
                    state: state,
                    sanMoves:
                        state.isAnalysisMode
                            ? state.analysisState.moveSans
                            : state.moveSans,
                    currentMoveIndex:
                        state.isAnalysisMode
                            ? state.analysisState.currentMoveIndex
                            : state.currentMoveIndex,
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

    // Check whose turn it is currently
    final currentTurn = state.position?.turn ?? Side.white;
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

class _BoardWithSidebar extends StatelessWidget {
  final int index;
  final ChessBoardStateNew state;

  const _BoardWithSidebar({required this.index, required this.state});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final sideBarWidth = 20.w;
        final screenWidth = MediaQuery.of(context).size.width;
        final boardSize = screenWidth - sideBarWidth - 32.w;

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
              ),
              state.isAnalysisMode
                  ? _AnalysisBoard(
                    size: boardSize,
                    chessBoardState: state,
                    isFlipped: state.isBoardFlipped,
                    index: index,
                  )
                  : _ChessBoardNew(
                    size: boardSize,
                    chessBoardState: state,
                    isFlipped: state.isBoardFlipped,
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
          lastMove: HighlightDetails(solidColor: kPrimaryColor),
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

  const _AnalysisBoard({
    required this.size,
    required this.chessBoardState,
    this.isFlipped = false,
    required this.index,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final boardSettingsValue = ref.watch(boardSettingsProvider);
    final boardTheme = ref
        .read(boardSettingsRepository)
        .getBoardTheme(boardSettingsValue.boardColor);
    final notifier = ref.read(chessBoardScreenProviderNew(index).notifier);

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
          lastMove: HighlightDetails(solidColor: kPrimaryColor),
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

  const _MovesDisplay({
    required this.state,
    required this.index,
    required this.sanMoves,
    required this.currentMoveIndex,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(chessBoardScreenProviderNew(index).notifier);

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

              return GestureDetector(
                onTap: () => notifier.goToMove(moveIndex),
                child: Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: 6.sp,
                    vertical: 2.sp,
                  ),
                  decoration: BoxDecoration(
                    color:
                        isCurrentMove
                            ? kWhiteColor70.withOpacity(0.4)
                            : Colors.transparent,
                    borderRadius: BorderRadius.circular(4.sp),
                    border: Border.all(
                      color: isCurrentMove ? kWhiteColor : Colors.transparent,
                      width: 0.5,
                    ),
                  ),
                  child: Text(
                    isWhiteMove ? '$fullMoveNumber. $move' : move,
                    style: AppTypography.textXsMedium.copyWith(
                      color: notifier.getMoveColor(move, moveIndex),
                      fontWeight:
                          isCurrentMove ? FontWeight.bold : FontWeight.normal,
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
            color: kWhiteColor.withOpacity(_animation.value * 0.15),
            borderRadius: BorderRadius.circular(widget.borderRadius),
          ),
        );
      },
    );
  }
}
