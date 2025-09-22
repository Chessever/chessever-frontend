import 'package:chessever2/repository/local_storage/board_settings_repository/board_settings_repository.dart';
import 'package:chessever2/repository/supabase/game/game_repository.dart';
import 'package:chessever2/screens/chessboard/widgets/evaluation_bar_widget.dart';
import 'package:chessever2/screens/chessboard/widgets/player_first_row_detail_widget.dart';
import 'package:chessever2/screens/chessboard/view_model/chess_board_state_new.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../../providers/board_settings_provider.dart';

class ChessBoardFromFENNew extends ConsumerStatefulWidget {
  const ChessBoardFromFENNew({
    super.key,
    required this.gamesTourModel,
    required this.onChanged,
  });

  final GamesTourModel gamesTourModel;
  final VoidCallback onChanged;

  @override
  ConsumerState<ChessBoardFromFENNew> createState() =>
      _ChessBoardFromFENState();
}

class _ChessBoardFromFENState extends ConsumerState<ChessBoardFromFENNew> {
  Move? lastMove;
  Position? finalPosition;
  List<String> moveTimes = [];
  int currentMoveIndex = -1;

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

  @override
  Widget build(BuildContext context) {
    final boardSettingsValue = ref.watch(boardSettingsProvider);
    final boardTheme = ref
        .read(boardSettingsRepository)
        .getBoardTheme(boardSettingsValue.boardColor);

    final sideBarWidth = 20.w;
    final horizontalPadding = 48.sp * 2;
    final screenWidth = MediaQuery.of(context).size.width;
    final boardSize = screenWidth - sideBarWidth - horizontalPadding;

    return Padding(
      padding: EdgeInsets.only(left: 24.sp, right: 24.sp, bottom: 8.sp),
      child: InkWell(
        onTap: widget.onChanged,
        child: Column(
          children: [
            PlayerFirstRowDetailWidget(
              isWhitePlayer: false,
              gamesTourModel: widget.gamesTourModel,
              isCurrentPlayer: widget.gamesTourModel.activePlayer == Side.black,
              playerView: PlayerView.listView,
              chessBoardState: _createMockChessBoardState(),
            ),
            SizedBox(height: 4.h),
            Container(
              decoration: BoxDecoration(
                boxShadow: [
                  BoxShadow(
                    color: Colors.grey.withOpacity(0.5),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  EvaluationBarWidgetForGames(
                    width: sideBarWidth,
                    height: boardSize,
                    fen: widget.gamesTourModel.fen ?? '',
                  ),
                  SizedBox(
                    height: boardSize,
                    width: boardSize,
                    child: AbsorbPointer(
                      child: Chessboard.fixed(
                        size: boardSize,
                        settings: ChessboardSettings(
                          colorScheme: ChessboardColorScheme(
                            lightSquare: boardTheme.lightSquareColor,
                            darkSquare: boardTheme.darkSquareColor,
                            background: SolidColorChessboardBackground(
                              lightSquare: boardTheme.lightSquareColor,
                              darkSquare: boardTheme.darkSquareColor,
                            ),
                            whiteCoordBackground:
                                SolidColorChessboardBackground(
                                  lightSquare: boardTheme.lightSquareColor,
                                  darkSquare: boardTheme.darkSquareColor,
                                  coordinates: true,
                                  orientation: Side.white,
                                ),
                            blackCoordBackground:
                                SolidColorChessboardBackground(
                                  lightSquare: boardTheme.lightSquareColor,
                                  darkSquare: boardTheme.darkSquareColor,
                                  coordinates: true,
                                  orientation: Side.black,
                                ),
                            lastMove: HighlightDetails(
                              solidColor: kPrimaryColor,
                            ),
                            selected: const HighlightDetails(
                              solidColor: kPrimaryColor,
                            ),
                            validMoves: kPrimaryColor,
                            validPremoves: kPrimaryColor,
                          ),
                        ),
                        orientation: Side.white,
                        fen: finalPosition?.fen ?? "",
                        lastMove: lastMove,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: 4.h),
            PlayerFirstRowDetailWidget(
              gamesTourModel: widget.gamesTourModel,
              isWhitePlayer: true,
              isCurrentPlayer: widget.gamesTourModel.activePlayer == Side.white,
              playerView: PlayerView.listView,
              chessBoardState: _createMockChessBoardState(),
            ),
          ],
        ),
      ),
    );
  }

  // Create a mock ChessBoardState with parsed move times
  ChessBoardStateNew? _createMockChessBoardState() {
    if (moveTimes.isEmpty || currentMoveIndex < 0) return null;

    return ChessBoardStateNew(
      game: widget.gamesTourModel,
      position: finalPosition,
      moveTimes: moveTimes,
      currentMoveIndex: currentMoveIndex,
      moveSans: const [],
      isLoadingMoves: false,
      fenData: null,
      lastMove: lastMove,
      shapes: const ISet.empty(),
      evaluation: 0.0,
      mate: null,
      isBoardFlipped: false,
      isAnalysisMode: false,
      analysisState: const AnalysisBoardState(),
    );
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
}
