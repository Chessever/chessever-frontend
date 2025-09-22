import 'package:chessever2/repository/local_storage/board_settings_repository/board_settings_repository.dart';
import 'package:chessever2/repository/supabase/game/game_repository.dart';
import 'package:chessever2/screens/chessboard/widgets/context_pop_up_menu.dart';
import 'package:chessever2/screens/chessboard/widgets/evaluation_bar_widget.dart';
import 'package:chessever2/screens/chessboard/widgets/player_first_row_detail_widget.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:chessever2/providers/board_settings_provider.dart';

class ChessBoardFromFENNew extends ConsumerStatefulWidget {
  const ChessBoardFromFENNew({
    super.key,
    required this.gamesTourModel,
    required this.onChanged,
    required this.pinnedIds,
    required this.onPinToggle,
  });

  final GamesTourModel gamesTourModel;
  final VoidCallback onChanged;
  final List<String> pinnedIds;
  final void Function(GamesTourModel game) onPinToggle;

  @override
  ConsumerState<ChessBoardFromFENNew> createState() =>
      _ChessBoardFromFENState();
}

class _ChessBoardFromFENState extends ConsumerState<ChessBoardFromFENNew> {
  Move? lastMove;
  Position? finalPosition;
  List<String> moveTimes = [];
  int currentMoveIndex = -1;

  bool get isPinned => widget.pinnedIds.contains(widget.gamesTourModel.gameId);

  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      await _initializeGame();
    });
  }

  Future<void> _initializeGame() async {
    try {
      if (!mounted) return;
      final gameWithPGn = await ref
          .read(gameRepositoryProvider)
          .getGameById(widget.gamesTourModel.gameId);
      var game = GamesTourModel.fromGame(gameWithPGn);
      if (!mounted) return;
      final pgnData = game.pgn ?? "";
      final gameData = PgnGame.parsePgn(pgnData);
      final startingPos = PgnGame.startingPosition(gameData.headers);

      // Parse all moves and store them
      Position tempPosition = startingPos;
      List<Move> allMoves = [];
      List<String> moveSans = [];

      // Parse move times from PGN (same logic as GameCard)
      moveTimes = _parseMoveTimesFromPgn(pgnData);

      for (final node in gameData.moves.mainline()) {
        final move = tempPosition.parseSan(node.san);
        if (move == null) break; // Illegal move
        allMoves.add(move);
        moveSans.add(node.san);
        tempPosition = tempPosition.play(move);
      }

      // Set to the last position initially
      final lastMoveIndex = allMoves.length - 1;
      currentMoveIndex = lastMoveIndex;
      finalPosition = startingPos;

      // Replay to final position
      for (int i = 0; i <= lastMoveIndex; i++) {
        lastMove = allMoves[i];
        finalPosition = finalPosition!.play(allMoves[i]);
      }
      setState(() {});
    } catch (error) {
      debugPrint('Error initializing game: $error');
    }
  }

  // PGN parsing methods copied from GameCard to ensure consistency
  static List<String> _parseMoveTimesFromPgn(String pgn) {
    final List<String> times = [];

    try {
      final game = PgnGame.parsePgn(pgn);

      // Iterate through the mainline moves
      for (final nodeData in game.moves.mainline()) {
        String? timeString;

        // Check if this move has comments
        if (nodeData.comments != null) {
          // Extract time if it exists in any comment
          for (String comment in nodeData.comments!) {
            final timeMatch = RegExp(
              r'\[%clk (\d+:\d+:\d+)\]',
            ).firstMatch(comment);
            if (timeMatch != null) {
              timeString = timeMatch.group(1);
              break; // Found time, no need to check other comments for this move
            }
          }
        }

        // Add formatted time or default if no time found
        if (timeString != null) {
          times.add(_formatDisplayTime(timeString));
        } else {
          times.add('-:--:--'); // Default for moves without time
        }
      }
    } catch (e) {
      // Fallback to regex method if dartchess parsing fails
      return _parseMoveTimesFromPgnFallback(pgn);
    }

    return times;
  }

  // Fallback method using the original regex approach
  static List<String> _parseMoveTimesFromPgnFallback(String pgn) {
    final List<String> times = [];
    final regex = RegExp(r'\{ \[%clk (\d+:\d+:\d+)\] \}');
    final matches = regex.allMatches(pgn);

    for (final match in matches) {
      final timeString = match.group(1) ?? '0:00:00';
      times.add(_formatDisplayTime(timeString));
    }

    return times;
  }

  static String _formatDisplayTime(String timeString) {
    // Convert "1:40:57" to display format
    final parts = timeString.split(':');
    if (parts.length == 3) {
      final hours = int.parse(parts[0]);
      final minutes = parts[1];
      final seconds = parts[2];

      // If less than an hour, show MM:SS format
      if (hours == 0) {
        return '$minutes:$seconds';
      }
      // Otherwise show H:MM:SS format
      return '$hours:$minutes:$seconds';
    }
    return timeString;
  }

  @override
  void didUpdateWidget(ChessBoardFromFENNew oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.gamesTourModel.lastMove != widget.gamesTourModel.lastMove) {
      _initializeGame();
    }
  }

  @override
  void dispose() {
    super.dispose();
  }

  void _showBlurredPopup(BuildContext context, LongPressStartDetails details) {
    final RenderBox boardRenderBox = context.findRenderObject() as RenderBox;
    final Offset boardPosition = boardRenderBox.localToGlobal(Offset.zero);
    final Size boardSize = boardRenderBox.size;

    final double screenHeight = MediaQuery.of(context).size.height;
    const double popupHeight = 100;
    final double spaceBelow =
        screenHeight - (boardPosition.dy + boardSize.height);

    bool showAbove = spaceBelow < popupHeight;

    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      pageBuilder: (
        BuildContext buildContext,
        Animation<double> animation,
        Animation<double> secondaryAnimation,
      ) {
        final double menuTop =
            showAbove
                ? boardPosition.dy - popupHeight - 8.sp
                : boardPosition.dy + boardSize.height + 8.sp;
        return Material(
          color: Colors.transparent,
          child: GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Stack(
              children: [
                SelectiveBlurBackground(
                  clearPosition: boardPosition,
                  clearSize: boardSize,
                ),
                Positioned(
                  left: boardPosition.dx,
                  top: boardPosition.dy,
                  child: _ChessBoardContent(
                    gamesTourModel: widget.gamesTourModel,
                    finalPosition: finalPosition,
                    lastMove: lastMove,
                    boardSize: boardSize,
                    isPinned: isPinned,
                  ),
                ),

                Positioned(
                  left: details.globalPosition.dx - 120.w,
                  top: menuTop,
                  child: ContextPopupMenu(
                    isPinned: isPinned,
                    onPinToggle: () {
                      Navigator.pop(context);
                      widget.onPinToggle(widget.gamesTourModel);
                    },
                    onShare: () {},
                  ),
                ),
              ],
            ),
          ),
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        return FadeTransition(opacity: animation, child: child);
      },
      transitionDuration: const Duration(milliseconds: 300),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sideBarWidth = 20.w;
    final horizontalPadding = 48.sp * 2;
    final screenWidth = MediaQuery.of(context).size.width;
    final boardSize = screenWidth - sideBarWidth - horizontalPadding;

    return Padding(
      padding: EdgeInsets.only(left: 24.sp, right: 24.sp, bottom: 8.sp),
      child: GestureDetector(
        onTap: widget.onChanged,
        onLongPressStart: (details) {
          HapticFeedback.lightImpact();
          _showBlurredPopup(context, details);
        },
        child: _ChessBoardLayout(
          gamesTourModel: widget.gamesTourModel,
          finalPosition: finalPosition,
          lastMove: lastMove,
          sideBarWidth: sideBarWidth,
          boardSize: boardSize,
          isPinned: isPinned,
        ),
      ),
    );
  }
}

class _ChessBoardLayout extends ConsumerWidget {
  const _ChessBoardLayout({
    required this.gamesTourModel,
    required this.finalPosition,
    required this.lastMove,
    required this.sideBarWidth,
    required this.boardSize,
    required this.isPinned,
  });

  final GamesTourModel gamesTourModel;
  final Position? finalPosition;
  final Move? lastMove;
  final double sideBarWidth;
  final double boardSize;
  final bool isPinned;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      children: [
        _PlayerRow(
          gamesTourModel: gamesTourModel,
          isWhitePlayer: false,
          isCurrentPlayer: gamesTourModel.activePlayer == Side.black,
          isPinned: isPinned,
        ),
        SizedBox(height: 4.h),
        _ChessBoardWithEvaluation(
          gamesTourModel: gamesTourModel,
          finalPosition: finalPosition,
          lastMove: lastMove,
          sideBarWidth: sideBarWidth,
          boardSize: boardSize,
        ),
        SizedBox(height: 4.h),
        _PlayerRow(
          gamesTourModel: gamesTourModel,
          isWhitePlayer: true,
          isCurrentPlayer: gamesTourModel.activePlayer == Side.white,
          isPinned: false,
        ),
      ],
    );
  }
}

class _ChessBoardContent extends ConsumerWidget {
  const _ChessBoardContent({
    required this.gamesTourModel,
    required this.finalPosition,
    required this.lastMove,
    required this.boardSize,
    required this.isPinned,
  });

  final GamesTourModel gamesTourModel;
  final Position? finalPosition;
  final Move? lastMove;
  final Size boardSize;
  final bool isPinned;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sideBarWidth = 20.w;
    final horizontalPadding = 48.sp * 2;
    final screenWidth = MediaQuery.of(context).size.width;
    final chessBoardSize = screenWidth - sideBarWidth - horizontalPadding;

    return SizedBox(
      width: boardSize.width,
      height: boardSize.height,
      child: Padding(
        padding: EdgeInsets.only(left: 24.sp, right: 24.sp, bottom: 8.sp),
        child: Column(
          children: [
            _PlayerRow(
              gamesTourModel: gamesTourModel,
              isWhitePlayer: false,
              isCurrentPlayer: gamesTourModel.activePlayer == Side.black,
              isPinned: isPinned,
            ),
            SizedBox(height: 4.h),
            _ChessBoardWithEvaluation(
              gamesTourModel: gamesTourModel,
              finalPosition: finalPosition,
              lastMove: lastMove,
              sideBarWidth: sideBarWidth,
              boardSize: chessBoardSize,
            ),
            SizedBox(height: 4.h),
            _PlayerRow(
              gamesTourModel: gamesTourModel,
              isWhitePlayer: true,
              isCurrentPlayer: gamesTourModel.activePlayer == Side.white,
              isPinned: false,
            ),
          ],
        ),
      ),
    );
  }
}

class _PlayerRow extends StatelessWidget {
  const _PlayerRow({
    required this.gamesTourModel,
    required this.isWhitePlayer,
    required this.isCurrentPlayer,
    required this.isPinned,
  });

  final GamesTourModel gamesTourModel;
  final bool isWhitePlayer;
  final bool isCurrentPlayer;
  final bool isPinned;

  @override
  Widget build(BuildContext context) {
    return PlayerFirstRowDetailWidget(
      gamesTourModel: gamesTourModel,
      isWhitePlayer: isWhitePlayer,
      isCurrentPlayer: isCurrentPlayer,
      playerView: PlayerView.listView,
      isPinned: isPinned,
    );
  }
}

class _ChessBoardWithEvaluation extends ConsumerWidget {
  const _ChessBoardWithEvaluation({
    required this.gamesTourModel,
    required this.finalPosition,
    required this.lastMove,
    required this.sideBarWidth,
    required this.boardSize,
  });

  final GamesTourModel gamesTourModel;
  final Position? finalPosition;
  final Move? lastMove;
  final double sideBarWidth;
  final double boardSize;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      decoration: _buildShadowDecoration(),
      child: Row(
        children: [
          EvaluationBarWidgetForGames(
            width: sideBarWidth,
            height: boardSize,
            fen: gamesTourModel.fen ?? '',
          ),
          _ChessBoardWidget(
            finalPosition: finalPosition,
            lastMove: lastMove,
            boardSize: boardSize,
          ),
        ],
      ),
    );
  }

  BoxDecoration _buildShadowDecoration() {
    return BoxDecoration(
      boxShadow: [
        BoxShadow(
          color: kBoardLightGrey.withOpacity(0.5),
          blurRadius: 8,
          offset: const Offset(0, 4),
        ),
      ],
    );
  }
}

class _ChessBoardWidget extends ConsumerWidget {
  const _ChessBoardWidget({
    required this.finalPosition,
    required this.lastMove,
    required this.boardSize,
  });

  final Position? finalPosition;
  final Move? lastMove;
  final double boardSize;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final boardSettingsValue = ref.watch(boardSettingsProvider);
    final boardTheme = ref
        .read(boardSettingsRepository)
        .getBoardTheme(boardSettingsValue.boardColor);

    return SizedBox(
      height: boardSize,
      width: boardSize,
      child: AbsorbPointer(
        child: Chessboard.fixed(
          size: boardSize,
          settings: ChessboardSettings(
            colorScheme: _buildColorScheme(boardTheme),
          ),
          orientation: Side.white,
          fen: finalPosition?.fen ?? "",
          lastMove: lastMove,
        ),
      ),
    );
  }

  ChessboardColorScheme _buildColorScheme(dynamic boardTheme) {
    return ChessboardColorScheme(
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
    );
  }
}
