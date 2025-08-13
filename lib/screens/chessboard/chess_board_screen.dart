import 'package:advanced_chess_board/advanced_chess_board.dart';
import 'package:advanced_chess_board/models/enums.dart';
import 'package:chessever2/providers/board_settings_provider.dart';
import 'package:chessever2/repository/local_storage/board_settings_repository/board_settings_repository.dart';
import 'package:chessever2/screens/chessboard/provider/chess_board_screen_provider.dart';
import 'package:chessever2/screens/chessboard/view_model/chess_board_state.dart';
import 'package:chessever2/screens/chessboard/widgets/chess_board_bottom_nav_bar.dart';
import 'package:chessever2/screens/chessboard/widgets/evaluation_bar_widget.dart';
import 'package:chessever2/screens/tournaments/model/games_tour_model.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/screens/chessboard/widgets/chess_appbar.dart';
import 'package:chessever2/screens/chessboard/widgets/player_first_row_detail_widget.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: PageView.builder(
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
                  );
                },
                error: (e, _) => ErrorWidget(e),
                loading: () => const _LoadingScreen(),
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

  const _GamePage({
    required this.index,
    required this.game,
    required this.state,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      bottomNavigationBar: _BottomNavBar(index: index, state: state),
      appBar: _AppBar(game: game),
      body: _GameBody(index: index, game: game, state: state),
    );
  }
}

class _LoadingScreen extends StatelessWidget {
  const _LoadingScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: ChessMatchAppBar(
        title: 'Loading...',
        showDownArrow: false,
        onBackPressed: () => Navigator.pop(context),
        onSettingsPressed: () {},
        onMoreOptionsPressed: () {},
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: kGreenColor),
            const SizedBox(height: 16),
            Text('Loading game...', style: AppTypography.textSmMedium),
          ],
        ),
      ),
    );
  }
}

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

class _AppBar extends StatelessWidget implements PreferredSizeWidget {
  final GamesTourModel game;

  const _AppBar({required this.game});

  @override
  Widget build(BuildContext context) {
    return ChessMatchAppBar(
      title: '${game.whitePlayer.name} vs ${game.blackPlayer.name}',
      showDownArrow: false,
      onBackPressed: () => Navigator.pop(context),
      onSettingsPressed: () {},
      onMoreOptionsPressed: () {},
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}

class _GameBody extends StatelessWidget {
  final int index;
  final GamesTourModel game;
  final ChessBoardState state;

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
        ),
        SizedBox(height: 2.h),
        _BoardWithSidebar(index: index, state: state),
        SizedBox(height: 2.h),
        _PlayerWidget(
          game: game,
          isFlipped: state.isBoardFlipped,
          blackPlayer: true,
        ),
        Expanded(
          child: SingleChildScrollView(
            child: _MovesDisplay(index: index, state: state),
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

  const _BoardWithSidebar({
    required this.index,
    required this.state,
  });

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
      child: AdvancedChessBoard(
        key: ValueKey(
          'chess_board_${chessBoardState.currentMoveIndex}_${chessBoardState.currentPosition.fen}',
        ),
        controller: chessBoardState.chessBoardController,
        lightSquareColor: boardTheme.lightSquareColor,
        darkSquareColor: boardTheme.darkSquareColor,
        boardOrientation: isFlipped ? PlayerColor.black : PlayerColor.white,
        enableMoves: false,
        // Read-only for game viewing
        highlightLastMove: true,
        lastMoveFrom: fromSquare,
        lastMoveTo: toSquare,
        lastMoveFromColor: kPrimaryColor,
        lastMoveToColor: kPrimaryColor,
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

    if (state.sanMoves.isEmpty) {
      return Container(
        alignment: Alignment.center,
        padding: EdgeInsets.all(20.sp),
        child: Text(
          "No Moves Made yet!",
          style: AppTypography.textXsMedium.copyWith(
            color: kWhiteColor,
            fontWeight: FontWeight.bold,
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
}
