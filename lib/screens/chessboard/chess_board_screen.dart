import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart' as chess;
import 'package:chessever2/providers/board_settings_provider.dart';
import 'package:chessever2/repository/local_storage/board_settings_repository/board_settings_repository.dart';
import 'package:chessever2/screens/chessboard/provider/chess_board_screen_provider.dart';
import 'package:chessever2/screens/chessboard/view_model/chess_board_state.dart';
import 'package:chessever2/screens/chessboard/widgets/chess_board_bottom_nav_bar.dart';
import 'package:chessever2/screens/chessboard/widgets/evaluation_bar_widget.dart';
import 'package:chessever2/screens/tournaments/model/games_tour_model.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/screens/chessboard/widgets/player_first_row_detail_widget.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:chessever2/utils/svg_asset.dart';
import 'package:chessever2/widgets/divider_widget.dart';
import 'package:flutter_svg/svg.dart';

class ChessBoardScreen extends ConsumerStatefulWidget {
  final int currentIndex;
  final List<GamesTourModel> games;

  const ChessBoardScreen({
    required this.currentIndex,
    required this.games,
    super.key,
  });

  @override
  ConsumerState<ChessBoardScreen> createState() => _ChessBoardScreenState();
}

class _ChessBoardScreenState extends ConsumerState<ChessBoardScreen> {
  late PageController _pageController;
  int _currentPageIndex = 0;

  @override
  void initState() {
    _currentPageIndex = widget.currentIndex;
    _pageController = PageController(initialPage: widget.currentIndex);
    super.initState();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _onPageChanged(int newIndex) {
    if (_currentPageIndex == newIndex) return;

    ref.read(chessBoardScreenProvider(_currentPageIndex).notifier).pauseGame();
    _currentPageIndex = newIndex;
  }

  void _navigateToGame(int gameIndex) {
    if (gameIndex == _currentPageIndex) return;

    // Pause current game
    ref.read(chessBoardScreenProvider(_currentPageIndex).notifier).pauseGame();

    // Navigate to new game
    _pageController.animateToPage(
      gameIndex,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  // Add these methods to handle swipes
  void _handleSwipeLeft() {
    if (_currentPageIndex < widget.games.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  void _handleSwipeRight() {
    if (_currentPageIndex > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: PageView.builder(
        physics: const NeverScrollableScrollPhysics(),
        controller: _pageController,
        onPageChanged: _onPageChanged,
        itemCount: widget.games.length,
        itemBuilder: (context, index) {
          if ((index - _currentPageIndex).abs() > 1) {
            return Container();
          }
          return ref
              .watch(chessBoardScreenProvider(index))
              .when(
                data: (chessBoardState) {
                  return _GamePage(
                    index: index,
                    game: widget.games[index],
                    state: chessBoardState,
                    games: widget.games,
                    currentGameIndex: _currentPageIndex,
                    onGameChanged: _navigateToGame,
                    onSwipeLeft: _handleSwipeLeft,
                    onSwipeRight: _handleSwipeRight,
                  );
                },
                error: (e, _) => ErrorWidget(e),
                loading:
                    () => _LoadingScreen(
                      games: widget.games,
                      currentGameIndex: _currentPageIndex,
                      onGameChanged: _navigateToGame,
                    ),
              );
        },
      ),
    );
  }
}

class _GamePage extends StatelessWidget {
  final int index;
  final GamesTourModel game;
  final ChessBoardState state;
  final List<GamesTourModel> games;
  final int currentGameIndex;
  final void Function(int) onGameChanged;
  final VoidCallback onSwipeLeft;
  final VoidCallback onSwipeRight;

  const _GamePage({
    required this.index,
    required this.game,
    required this.state,
    required this.games,
    required this.currentGameIndex,
    required this.onGameChanged,
    required this.onSwipeLeft,
    required this.onSwipeRight,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      bottomNavigationBar: _BottomNavBar(index: index, state: state),
      appBar: _AppBar(
        game: game,
        games: games,
        currentGameIndex: currentGameIndex,
        onGameChanged: onGameChanged,
      ),
      body: _GameBody(
        index: index,
        game: game,
        state: state,
        onSwipeLeft: onSwipeLeft,
        onSwipeRight: onSwipeRight,
      ),
    );
  }
}

class _LoadingScreen extends StatelessWidget {
  final List<GamesTourModel> games;
  final int currentGameIndex;
  final void Function(int) onGameChanged;

  const _LoadingScreen({
    required this.games,
    required this.currentGameIndex,
    required this.onGameChanged,
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

// Enhanced App Bar with Game Selection Dropdown
class _AppBar extends StatelessWidget implements PreferredSizeWidget {
  final GamesTourModel game;
  final List<GamesTourModel> games;
  final int currentGameIndex;
  final void Function(int) onGameChanged;
  final bool isLoading;

  const _AppBar({
    required this.game,
    required this.games,
    required this.currentGameIndex,
    required this.onGameChanged,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return AppBar(
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new, color: kWhiteColor),
        onPressed: () => Navigator.pop(context),
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
          onSelected: (value) {
            switch (value) {
              case 'share':
                // Share game functionality
                break;
              case 'analyze':
                // Analyze game functionality
                break;
              case 'copy_pgn':
                // Copy PGN functionality
                break;
            }
          },
          itemBuilder:
              (context) => [
                PopupMenuItem(
                  value: 'share',
                  child: Row(
                    children: [
                      Icon(Icons.share, color: kWhiteColor),
                      SizedBox(width: 8.w),
                      Text('Share Game'),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'analyze',
                  child: Row(
                    children: [
                      Icon(Icons.analytics, color: kWhiteColor),
                      SizedBox(width: 8.w),
                      Text('Analyze'),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'copy_pgn',
                  child: Row(
                    children: [
                      Icon(Icons.copy, color: kWhiteColor),
                      SizedBox(width: 8.w),
                      Text('Copy PGN'),
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

// Game Selection Dropdown Widget
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

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 32.h,
      constraints: BoxConstraints(maxWidth: 200.w),
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
            final index = entry.key;
            final game = entry.value;

            return Container(
              padding: EdgeInsets.symmetric(horizontal: 12.sp),
              alignment: Alignment.center,
              child: Text(
                '${game.blackPlayer.displayName} vs ${game.whitePlayer.displayName}',
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

// Individual Game Dropdown Item
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

  Widget _buildStatusIcon() {
    if (isLoading) {
      return SizedBox(
        width: 16.w,
        height: 16.h,
        child: CircularProgressIndicator(
          strokeWidth: 1.5,
          color: kPrimaryColor,
        ),
      );
    }

    // Use the correct GameStatus enum values
    switch (game.gameStatus) {
      case GameStatus.whiteWins:
      case GameStatus.blackWins:
      case GameStatus.draw:
        // Completed games (any result)
        return SvgPicture.asset(
          SvgAsset.check,
          width: 16.w,
          height: 16.h,
        );
      case GameStatus.ongoing:
        // Ongoing/Live games
        return SvgPicture.asset(
          SvgAsset.selectedSvg,
          width: 16.w,
          height: 16.h,
        );
      case GameStatus.unknown:
      default:
        // Unknown status - use calendar icon
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // // Game title with round info
              // Text(
              //   'Game $gameNumber - ${game.roundDisplayName}',
              //   style: AppTypography.textXsRegular.copyWith(color: kWhiteColor),
              //   maxLines: 1,
              //   overflow: TextOverflow.ellipsis,
              // ),
              // SizedBox(height: 2.h),
              // // Player names
              Text(
                '${game.whitePlayer.name} vs ${game.blackPlayer.name}',
                style: AppTypography.textXsRegular.copyWith(
                  color: kWhiteColor70,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        SizedBox(width: 8.w),
        _buildStatusIcon(),
      ],
    );
  }
}

// You'll need to add these imports at the top of the file

// Remove the _GameStatusIndicator class as we're now using SVG icons directly

// Enhanced bottom navigation bar with proper state integration
class _BottomNavBar extends ConsumerWidget {
  final int index;
  final ChessBoardState state;

  const _BottomNavBar({required this.index, required this.state});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(chessBoardScreenProvider(index).notifier);

    return ChessBoardBottomNavBar(
      gameIndex: index,
      onFlip: () => notifier.flipBoard(index),
      onRightMove: state.canMoveForward ? () => notifier.moveForward() : null,
      onLeftMove: state.canMoveBackward ? () => notifier.moveBackward() : null,
      onPlayPause: () => notifier.togglePlayPause(),
      onReset: () => notifier.resetGame(),
      onJumpToStart: state.canMoveBackward ? () => notifier.resetGame() : null,
      onJumpToEnd: state.canMoveForward ? () => notifier.jumpToEnd() : null,
      isPlaying: state.isPlaying,
      currentMove: state.currentMoveIndex,
      totalMoves: state.totalMoves,
      canMoveForward: state.canMoveForward,
      canMoveBackward: state.canMoveBackward,
      isAtStart: state.isAtStart,
      isAtEnd: state.isAtEnd,
    );
  }
}

class _GameBody extends StatelessWidget {
  final int index;
  final GamesTourModel game;
  final ChessBoardState state;
  final VoidCallback onSwipeLeft;
  final VoidCallback onSwipeRight;

  _GameBody({
    required this.index,
    required this.game,
    required this.state,
    required this.onSwipeLeft,
    required this.onSwipeRight,
  });

  Offset? _panStartPosition;
  double _totalHorizontalDelta = 0.0;
  double _totalVerticalDelta = 0.0;
  bool _isHorizontalSwipe = false;
  DateTime? _lastSwipeTime;

  static const Duration _swipeDebounceTime = Duration(milliseconds: 300);

  void _resetSwipeTracking() {
    _totalHorizontalDelta = 0.0;
    _totalVerticalDelta = 0.0;
    _isHorizontalSwipe = false;
  }

  bool _canSwipe() {
    if (_lastSwipeTime == null) return true;
    return DateTime.now().difference(_lastSwipeTime!) > _swipeDebounceTime;
  }

  void _recordSwipe() {
    _lastSwipeTime = DateTime.now();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _PlayerWidget(
          game: game,
          isFlipped: state.isBoardFlipped,
          blackPlayer: false,
        ),
        SizedBox(height: 2.h),
        GestureDetector(
          // Make sure we can receive pan gestures
          behavior: HitTestBehavior.translucent,
          onPanStart: (details) {
            _panStartPosition = details.globalPosition;
            _resetSwipeTracking();
          },
          onPanUpdate: (details) {
            if (_panStartPosition == null) {
              return;
            }

            // Accumulate deltas to track total movement
            _totalHorizontalDelta += details.delta.dx;
            _totalVerticalDelta += details.delta.dy;

            // Check if this is primarily a horizontal movement
            const double minHorizontalMovement = 5.0; // Reduced threshold
            const double maxVerticalTolerance = 80.0; // Increased tolerance

            // More lenient horizontal detection
            if (_totalHorizontalDelta.abs() > minHorizontalMovement) {
              // Check if horizontal movement is dominant
              if (_totalVerticalDelta.abs() == 0 ||
                  _totalHorizontalDelta.abs() >
                      _totalVerticalDelta.abs() * 0.7) {
                _isHorizontalSwipe = true;
              }
            }

            if (_totalVerticalDelta.abs() > maxVerticalTolerance &&
                _totalVerticalDelta.abs() > _totalHorizontalDelta.abs() * 2) {
              // Too much vertical movement - definitely not a horizontal swipe
              _isHorizontalSwipe = false;
            }
          },
          onPanEnd: (details) {
            if (!_canSwipe()) {
              _resetSwipeTracking();
              _panStartPosition = null;
              return;
            }

            if (!_isHorizontalSwipe) {
              _resetSwipeTracking();
              _panStartPosition = null;
              return;
            }
            // Calculate final swipe metrics
            const double minSwipeDistance = 30.0; // Reduced minimum distance
            const double minSwipeVelocity = 200.0; // Reduced minimum velocity

            double velocity = details.velocity.pixelsPerSecond.dx;
            double totalDistance = _totalHorizontalDelta.abs();

            // Require either sufficient distance OR velocity for a swipe
            bool isValidSwipe =
                totalDistance > minSwipeDistance ||
                velocity.abs() > minSwipeVelocity;

            if (isValidSwipe) {
              _recordSwipe();
              // Determine direction based on accumulated delta (more reliable than velocity alone)
              if (_totalHorizontalDelta > 0) {
                // Swiping right - go to previous game
                onSwipeRight.call();
              } else {
                // Swiping left - go to next game
                onSwipeLeft.call();
              }
            }
            _resetSwipeTracking();
            _panStartPosition = null;
          },
          onPanCancel: () {
            _resetSwipeTracking();
            _panStartPosition = null;
          },
          child: _BoardWithSidebar(index: index, state: state),
        ),
        SizedBox(height: 2.h),
        _PlayerWidget(
          game: game,
          isFlipped: state.isBoardFlipped,
          blackPlayer: true,
        ),
        // Moves section with consistent height to prevent layout shifts
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
            child: SingleChildScrollView(
              child: _MovesDisplay(index: index, state: state),
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

  const _PlayerWidget({
    required this.game,
    required this.isFlipped,
    required this.blackPlayer,
  });

  @override
  Widget build(BuildContext context) {
    final player =
        (blackPlayer && !isFlipped) || (!blackPlayer && isFlipped)
            ? game.whitePlayer
            : game.blackPlayer;
    final time =
        (blackPlayer && !isFlipped) || (!blackPlayer && isFlipped)
            ? game.whiteTimeDisplay
            : game.blackTimeDisplay;

    return PlayerFirstRowDetailWidget(
      name: player.name,
      firstGmRank: player.title,
      countryCode: player.countryCode,
      time: time,
    );
  }
}

class _BoardWithSidebar extends StatelessWidget {
  final int index;
  final ChessBoardState state;

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
                evaluation: state.evaluations,
              ),
              _ChessBoard(
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

// Enhanced chess board with integrated last move highlighting
class _ChessBoard extends ConsumerWidget {
  final double size;
  final ChessBoardState chessBoardState;
  final bool isFlipped;

  const _ChessBoard({
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

    // Get last move squares for highlighting
    final (fromSquare, toSquare) = chessBoardState.lastMoveSquares;

    return SizedBox(
      height: size,
      width: size,
      child: Chessboard(
        key: ValueKey(
          'chess_board_${chessBoardState.currentMoveIndex}_${chessBoardState.currentPosition.fen}',
        ),
        size: size,
        fen: chessBoardState.currentPosition.fen,
        orientation: isFlipped ? Side.black : Side.white,
        lastMove: fromSquare != null && toSquare != null
            ? [
                Square.fromName(fromSquare),
                Square.fromName(toSquare),
              ]
            : null,
        settings: BoardSettings(
          lightSquare: boardTheme.lightSquareColor,
          darkSquare: boardTheme.darkSquareColor,
          draggable: false,
        ),
      ),
    );
  }
}

// Enhanced moves display with proper highlighting and navigation
class _MovesDisplay extends ConsumerWidget {
  final int index;
  final ChessBoardState state;

  const _MovesDisplay({required this.state, required this.index});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(chessBoardScreenProvider(index).notifier);

    // Show loading skeleton while moves are being fetched
    if (state.isLoadingMoves) {
      return _buildMovesLoadingSkeleton();
    }

    // Show empty state only when loading is complete and no moves exist
    if (state.sanMoves.isEmpty && !state.isLoadingMoves) {
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
            state.sanMoves.asMap().entries.map((entry) {
              final moveIndex = entry.key;
              final move = entry.value;

              // Check if this move is currently displayed on board
              final isCurrentMove = moveIndex == state.currentMoveIndex - 1;
              final fullMoveNumber = (moveIndex / 2).floor() + 1;
              final isWhiteMove = moveIndex % 2 == 0;

              return GestureDetector(
                onTap: () => notifier.navigateToMove(moveIndex),
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
          // Title skeleton
          _SkeletonContainer(height: 16.h, width: 80.w, borderRadius: 4.sp),
          SizedBox(height: 12.h),
          // Moves skeleton - simulate move notation layout
          ...List.generate(6, (rowIndex) {
            return Padding(
              padding: EdgeInsets.only(bottom: 8.h),
              child: Wrap(
                spacing: 8.sp,
                children: [
                  // Move number + white move
                  _SkeletonContainer(
                    height: 14.h,
                    width: (60 + (rowIndex % 3) * 20).w, // Varying widths
                    borderRadius: 3.sp,
                  ),
                  // Black move
                  _SkeletonContainer(
                    height: 14.h,
                    width: (45 + (rowIndex % 4) * 15).w, // Varying widths
                    borderRadius: 3.sp,
                  ),
                ],
              ),
            );
          }),
          SizedBox(height: 8.h),
          // Additional skeleton moves
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
