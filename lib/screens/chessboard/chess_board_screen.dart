import 'package:chessever2/screens/chessboard/widgets/chess_board_bottom_nav_bar.dart';
import 'package:chessever2/screens/tournaments/model/games_tour_model.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/screens/chessboard/widgets/chess_appbar.dart';
import 'package:chessever2/screens/chessboard/widgets/player_first_row_detail_widget.dart';
import 'package:chessever2/screens/chessboard/widgets/player_second_row_detail_widget.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:squares/squares.dart';
import 'package:square_bishop/square_bishop.dart' as square_bishop;
import 'package:bishop/bishop.dart' as bishop;

class ChessBoardScreen extends ConsumerStatefulWidget {
  final List<GamesTourModel> games;
  final int currentIndex;

  const ChessBoardScreen(this.games, {required this.currentIndex, super.key});

  @override
  ConsumerState<ChessBoardScreen> createState() => _ChessBoardScreenState();
}

class _ChessBoardScreenState extends ConsumerState<ChessBoardScreen> {
  late PageController _pageController;
  Map<int, ChessGameState> _gameStates = {};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _pageController = PageController(initialPage: widget.currentIndex);
    _initializeGameStates();
  }

  /// Initialize game states for all games with PGN parsing
  void _initializeGameStates() {
    for (int i = 0; i < widget.games.length; i++) {
      final game = widget.games[i];

      try {
        // Clean and parse PGN
        String cleanedPgn = _cleanPgn(game.pgn ?? '');
        print("Current Moves : \n${cleanedPgn}");
        List<ChessMove> parsedMoves = _parsePgnMoves(cleanedPgn);

        // Create bishop game
        final bishopGame = bishop.Game.fromPgn(cleanedPgn);

        _gameStates[i] = ChessGameState(
          bishopGame: bishopGame,
          currentMoveIndex: 0,
          totalMoves: bishopGame.history.length,
          // Use bishop game's move count
          isPlaying: false,
          moves: parsedMoves,
        );

        print(
          'Game $i initialized: ${parsedMoves.length} parsed moves, ${bishopGame.history.length} bishop moves',
        );
      } catch (e) {
        print('Error initializing game $i: $e');

        // Fallback to empty game
        _gameStates[i] = ChessGameState(
          bishopGame: bishop.Game(),
          currentMoveIndex: 0,
          totalMoves: 0,
          isPlaying: false,
          moves: [],
        );
      }
    }
  }

  /// Clean PGN by removing problematic headers
  String _cleanPgn(String pgn) {
    if (pgn.isEmpty) return '';

    String cleaned = pgn;

    // Remove problematic headers but keep essential ones
    cleaned = cleaned.replaceAll(RegExp(r'\[Variant\s+"[^"]*"\]\s*'), '');
    cleaned = cleaned.replaceAll(RegExp(r'\[FEN\s+"[^"]*"\]\s*'), '');
    cleaned = cleaned.replaceAll(RegExp(r'\[SetUp\s+"[^"]*"\]\s*'), '');

    return cleaned.trim();
  }

  /// Parse PGN moves with clock times and proper formatting
  List<ChessMove> _parsePgnMoves(String pgn) {
    List<ChessMove> moves = [];

    // Remove headers first
    String movesSection = pgn.replaceAll(
      RegExp(r'^\[.*?\]\s*', multiLine: true),
      '',
    );

    // Pattern to match: "1. e4 { [%clk 1:59:57] }" or "1... e6 { [%clk 1:59:52] }"
    RegExp movePattern = RegExp(
      r'(\d+)(\.{1,3})\s*([a-zA-Z0-9+#=\-O]+)\s*(?:\{\s*\[%clk\s*([\d:]+)\]\s*\})?',
      multiLine: true,
    );

    Iterable<RegExpMatch> matches = movePattern.allMatches(movesSection);

    for (RegExpMatch match in matches) {
      String moveNumber = match.group(1) ?? '';
      String dots = match.group(2) ?? '.';
      String move = match.group(3) ?? '';
      String? clockTime = match.group(4);

      // Skip if it's a game result
      if (RegExp(r'^(1-0|0-1|1/2-1/2|\*)$').hasMatch(move)) continue;

      bool isWhiteMove = dots == '.';

      if (move.isNotEmpty) {
        moves.add(
          ChessMove(
            notation: move,
            moveNumber: int.tryParse(moveNumber) ?? 1,
            isWhiteMove: isWhiteMove,
            clockTime: clockTime,
            fullMoveText:
                '${isWhiteMove ? moveNumber + '.' : moveNumber + '...'} $move',
          ),
        );
      }
    }

    // Fallback: simple parsing if regex fails
    if (moves.isEmpty) {
      moves = _parseMovesSimple(movesSection);
    }

    return moves;
  }

  /// Simple fallback parsing method
  List<ChessMove> _parseMovesSimple(String movesText) {
    List<ChessMove> moves = [];

    // Remove clock annotations and other noise
    String cleaned =
        movesText
            .replaceAll(RegExp(r'\{[^}]*\}'), '') // Remove {comments}
            .replaceAll(RegExp(r'\([^)]*\)'), '') // Remove (annotations)
            .replaceAll(RegExp(r'\s+'), ' ') // Normalize whitespace
            .trim();

    List<String> tokens = cleaned.split(' ');
    int currentMoveNumber = 1;
    bool expectingWhiteMove = true;

    for (String token in tokens) {
      token = token.trim();
      if (token.isEmpty) continue;

      // Skip move numbers
      if (RegExp(r'^\d+\.{1,3}$').hasMatch(token)) {
        if (token.endsWith('...')) {
          expectingWhiteMove = false;
        } else {
          expectingWhiteMove = true;
          currentMoveNumber =
              int.tryParse(token.replaceAll('.', '')) ?? currentMoveNumber;
        }
        continue;
      }

      // Skip game results
      if (RegExp(r'^(1-0|0-1|1/2-1/2|\*)$').hasMatch(token)) continue;

      // This should be a move
      if (RegExp(r'^[a-zA-Z0-9+#=\-O]+$').hasMatch(token)) {
        moves.add(
          ChessMove(
            notation: token,
            moveNumber: currentMoveNumber,
            isWhiteMove: expectingWhiteMove,
            clockTime: null,
            fullMoveText:
                '${expectingWhiteMove ? currentMoveNumber.toString() + '.' : currentMoveNumber.toString() + '...'} $token',
          ),
        );

        if (expectingWhiteMove) {
          expectingWhiteMove = false;
        } else {
          expectingWhiteMove = true;
          currentMoveNumber++;
        }
      }
    }

    return moves;
  }

  /// Navigate to next move
  void _goToNextMove(int gameIndex) {
    print('Next move clicked for game $gameIndex');
    final state = _gameStates[gameIndex];
    if (state != null && state.currentMoveIndex < state.totalMoves) {
      final newMoveIndex = state.currentMoveIndex + 1;
      print(
        'Moving from ${state.currentMoveIndex} to $newMoveIndex (total: ${state.totalMoves})',
      );

      setState(() {
        _gameStates[gameIndex] = state.copyWith(currentMoveIndex: newMoveIndex);
      });

      print('Successfully moved to: $newMoveIndex/${state.totalMoves}');
    } else {
      print(
        'Cannot move next: current=${state?.currentMoveIndex}, total=${state?.totalMoves}',
      );
    }
  }

  /// Navigate to previous move
  void _goToPreviousMove(int gameIndex) {
    print('Previous move clicked for game $gameIndex');
    final state = _gameStates[gameIndex];
    if (state != null && state.currentMoveIndex > 0) {
      final newMoveIndex = state.currentMoveIndex - 1;
      print('Moving from ${state.currentMoveIndex} to $newMoveIndex');

      setState(() {
        _gameStates[gameIndex] = state.copyWith(currentMoveIndex: newMoveIndex);
      });

      print('Successfully moved to: $newMoveIndex/${state.totalMoves}');
    } else {
      print('Cannot move previous: current=${state?.currentMoveIndex}');
    }
  }

  /// Toggle auto-play functionality
  void _togglePlayPause(int gameIndex) {
    print('Play/Pause clicked for game $gameIndex');
    final state = _gameStates[gameIndex];
    if (state != null) {
      setState(() {
        _gameStates[gameIndex] = state.copyWith(isPlaying: !state.isPlaying);
      });

      if (!state.isPlaying) {
        _startAutoPlay(gameIndex);
      }
    }
  }

  /// Start automatic move playback
  void _startAutoPlay(int gameIndex) async {
    while (_gameStates[gameIndex]?.isPlaying == true) {
      await Future.delayed(
        Duration(milliseconds: 1500),
      ); // 1.5 second intervals

      if (_gameStates[gameIndex]?.isPlaying == true) {
        final state = _gameStates[gameIndex]!;

        if (state.currentMoveIndex < state.totalMoves) {
          _goToNextMove(gameIndex);
        } else {
          // Reached end, stop playing
          setState(() {
            _gameStates[gameIndex] = state.copyWith(isPlaying: false);
          });
          break;
        }
      }
    }
  }

  /// Reset game to starting position
  void _resetGame(int gameIndex) {
    print('Reset clicked for game $gameIndex');
    final state = _gameStates[gameIndex];
    if (state != null) {
      setState(() {
        _gameStates[gameIndex] = state.copyWith(
          currentMoveIndex: 0,
          isPlaying: false,
        );
      });
    }
  }

  /// Build the moves display text with highlighting
  List<TextSpan> _buildMovesDisplay(
    List<ChessMove> moves,
    int currentMoveIndex,
    BuildContext context,
  ) {
    List<TextSpan> spans = [];

    for (int i = 0; i < moves.length; i++) {
      final move = moves[i];
      final isCurrentMove = i == currentMoveIndex - 1;
      final isDark = Theme.of(context).brightness == Brightness.dark;

      // Add move number for white moves or when starting a new move pair
      if (move.isWhiteMove ||
          (i > 0 && moves[i - 1].moveNumber != move.moveNumber)) {
        spans.add(
          TextSpan(
            text: '${move.moveNumber}${move.isWhiteMove ? '.' : '...'} ',
            style: AppTypography.textXsMedium.copyWith(
              color: Colors.grey[isDark ? 400 : 600],
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        );
      }

      // Add the move notation with highlighting
      spans.add(
        TextSpan(
          text: move.notation,
          style: AppTypography.textXsMedium.copyWith(
            color:
                isCurrentMove
                    ? Colors.white
                    : (isDark ? Colors.grey[300] : Colors.grey[800]),
            backgroundColor: isCurrentMove ? kGreenColor : null,
            fontWeight: isCurrentMove ? FontWeight.bold : FontWeight.w500,
            fontSize: 14,
          ),
        ),
      );

      // Add space after move
      spans.add(TextSpan(text: ' '));

      // Add line break after black moves for better readability
      if (!move.isWhiteMove && (i + 1) % 6 == 0) {
        spans.add(TextSpan(text: '\n'));
      }
    }

    return spans;
  }

  /// Get current board state safely
  BoardState _getCurrentBoardState(ChessGameState gameState) {
    try {
      final squareState = gameState.bishopGame.squaresState(
        gameState.currentMoveIndex,
      );
      return squareState.board;
    } catch (e) {
      print(
        'Error getting board state at move ${gameState.currentMoveIndex}: $e',
      );
      // Fallback to starting position
      return gameState.bishopGame.squaresState(0).board;
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: PageView.builder(
        controller: _pageController,
        itemCount: widget.games.length,
        itemBuilder: (context, index) {
          final game = widget.games[index];
          final gameState = _gameStates[index];

          // Show loading if game state not ready
          if (gameState == null) {
            return Scaffold(
              appBar: ChessMatchAppBar(
                title: 'Loading...',
                onBackPressed: () => Navigator.pop(context),
                onSettingsPressed: () {},
                onMoreOptionsPressed: () {},
              ),
              body: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(color: kGreenColor),
                    SizedBox(height: 16),
                    Text('Loading game...', style: AppTypography.textSmMedium),
                  ],
                ),
              ),
            );
          }

          // Get current board state
          final boardState = _getCurrentBoardState(gameState);

          return Scaffold(
            bottomNavigationBar: ChessBoardBottomNavBar(
              onRightMove: () => _goToNextMove(index),
              onLeftMove: () => _goToPreviousMove(index),
              onPlayPause: () => _togglePlayPause(index),
              onReset: () => _resetGame(index),
              isPlaying: gameState.isPlaying,
              currentMove: gameState.currentMoveIndex,
              totalMoves: gameState.totalMoves,
            ),
            appBar: ChessMatchAppBar(
              title: '${game.whitePlayer.name} vs ${game.blackPlayer.name}',
              onBackPressed: () => Navigator.pop(context),
              onSettingsPressed: () {},
              onMoreOptionsPressed: () {},
            ),
            body: SingleChildScrollView(
              child: Column(
                children: [
                  // Top player (Black)
                  PlayerFirstRowDetailWidget(
                    name: game.blackPlayer.name,
                    firstGmRank: game.blackPlayer.displayTitle,
                    countryCode: game.blackPlayer.countryCode,
                    time: game.blackTimeDisplay,
                  ),

                  // Chess board with sidebar
                  LayoutBuilder(
                    builder: (context, constraints) {
                      const sideBarWidth = 20.0;
                      final screenWidth = MediaQuery.of(context).size.width;
                      final boardSize =
                          screenWidth -
                          sideBarWidth -
                          32; // Account for padding

                      return Container(
                        margin: EdgeInsets.symmetric(horizontal: 16),
                        child: Row(
                          children: [
                            // Left sidebar
                            Container(
                              width: sideBarWidth,
                              height: boardSize,
                              child: Column(
                                children: [
                                  Expanded(
                                    flex: 27,
                                    child: Container(color: kborderLeftColors),
                                  ),
                                  Expanded(
                                    flex: 2,
                                    child: Container(color: kRedColor),
                                  ),
                                  Expanded(
                                    flex: 27,
                                    child: Container(color: kWhiteColor),
                                  ),
                                ],
                              ),
                            ),

                            // Chess board
                            Expanded(
                              child: AbsorbPointer(
                                child: Board(
                                  size: BoardSize.standard,
                                  pieceSet: PieceSet.merida(),
                                  playState: PlayState.observing,
                                  state: boardState,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),

                  SizedBox(height: 16),

                  // Bottom player (White)
                  PlayerSecondRowDetailWidget(
                    name: game.whitePlayer.name,
                    secondGmRank: game.whitePlayer.displayTitle,
                    countryCode: game.whitePlayer.countryCode,
                    time: game.whiteTimeDisplay,
                  ),

                  SizedBox(height: 16),

                  // Moves display section
                  Container(
                    width: double.infinity,
                    margin: EdgeInsets.symmetric(horizontal: 16),
                    padding: EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Theme.of(context).cardColor,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 4,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Header with move counter
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Game Moves',
                              style: AppTypography.textXsBold.copyWith(
                                color: kGreenColor,
                              ),
                            ),
                            Container(
                              padding: EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: kGreenColor.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                '${gameState.currentMoveIndex}/${gameState.totalMoves}',
                                style: AppTypography.textSmMedium.copyWith(
                                  color: kGreenColor,
                                ),
                              ),
                            ),
                          ],
                        ),

                        SizedBox(height: 12),

                        // Moves display
                        if (gameState.moves.isNotEmpty)
                          Container(
                            height: 140,
                            width: double.infinity,
                            padding: EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color:
                                  Theme.of(context).brightness ==
                                          Brightness.dark
                                      ? Colors.grey[900]
                                      : Colors.grey[50],
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: Colors.grey.withOpacity(0.3),
                              ),
                            ),
                            child: SingleChildScrollView(
                              child: RichText(
                                text: TextSpan(
                                  children: _buildMovesDisplay(
                                    gameState.moves,
                                    gameState.currentMoveIndex,
                                    context,
                                  ),
                                ),
                              ),
                            ),
                          )
                        else
                          Container(
                            height: 60,
                            child: Center(
                              child: Text(
                                'No moves available',
                                style: AppTypography.textSmMedium.copyWith(
                                  color: Colors.grey[500],
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),

                  SizedBox(height: 120), // Space for bottom navigation
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// Data class for chess moves
class ChessMove {
  final String notation;
  final int moveNumber;
  final bool isWhiteMove;
  final String? clockTime;
  final String fullMoveText;

  ChessMove({
    required this.notation,
    required this.moveNumber,
    required this.isWhiteMove,
    this.clockTime,
    required this.fullMoveText,
  });

  @override
  String toString() {
    return fullMoveText;
  }
}

// Game state management class
class ChessGameState {
  final bishop.Game bishopGame;
  final int currentMoveIndex;
  final int totalMoves;
  final bool isPlaying;
  final List<ChessMove> moves;

  ChessGameState({
    required this.bishopGame,
    required this.currentMoveIndex,
    required this.totalMoves,
    required this.isPlaying,
    required this.moves,
  });

  ChessGameState copyWith({
    bishop.Game? bishopGame,
    int? currentMoveIndex,
    int? totalMoves,
    bool? isPlaying,
    List<ChessMove>? moves,
  }) {
    return ChessGameState(
      bishopGame: bishopGame ?? this.bishopGame,
      currentMoveIndex: currentMoveIndex ?? this.currentMoveIndex,
      totalMoves: totalMoves ?? this.totalMoves,
      isPlaying: isPlaying ?? this.isPlaying,
      moves: moves ?? this.moves,
    );
  }
}
