import 'package:chessever2/utils/app_typography.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:chessever2/screens/chessboard/view_model/chess_viewmodel.dart';
import 'package:chessever2/screens/chessboard/widgets/chess_appbar.dart';
import 'package:chessever2/screens/chessboard/widgets/chess_board_widget.dart';
import 'package:chessever2/providers/board_settings_provider.dart';
import 'package:chessever2/repository/local_storage/board_settings_repository/board_settings_repository.dart';
import 'package:chessever2/screens/chessboard/widgets/player_first_row_detail_widget.dart';
import 'package:chessever2/screens/chessboard/widgets/player_info_widget.dart';
import 'package:chessever2/screens/chessboard/widgets/player_second_row_detail_widget.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:chessever2/screens/chessboard/widgets/chess_board_bottom_nav_bar.dart';
import 'package:squares/squares.dart'; // Add this import
import 'package:square_bishop/square_bishop.dart' as square_bishop;
import 'package:bishop/bishop.dart' as bishop;

class ChessScreen extends ConsumerStatefulWidget {
  const ChessScreen({super.key});

  @override
  ConsumerState<ChessScreen> createState() => _ChessScreenState();
}

class _ChessScreenState extends ConsumerState<ChessScreen> {
  late final String firstGmName;
  late final String secondGmName;
  late final String firstGmCountryCode;
  late final String secondGmCountryCode;
  late final String firstGmTime;
  late final String secondGmTime;
  late final String firstGmRank;
  late final String secondGmRank;
  late final String pgn;
  late List<String> pgnMoves;
  // Board state initialized in initState
  late BoardState boardState;
  late bishop.Game currentGame;
  List<bishop.Move> moves = [];
  int currentMoveIndex = -1;

  late final String finalFen;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final args =
          ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;

      setState(() {
        firstGmName = args?['gmName'] ?? '';
        secondGmName = args?['gmSecondName'] ?? '';
        firstGmCountryCode = args?['firstGmCountryCode'] ?? '';
        secondGmCountryCode = args?['secondGmCountryCode'] ?? '';
        firstGmTime = args?['firstGmTime'] ?? '';
        secondGmTime = args?['secondGmTime'] ?? '';
        firstGmRank = args?['firstGmRank'] ?? '';
        secondGmRank = args?['secondGmRank'] ?? '';
        pgn = args?['pgn'] ?? '';
        // Clean PGN header if needed
        final cleanedPgn = pgn.replaceAll(
          RegExp(r'\[Variant\s+"[^"]*"\]\n?'),
          '',
        );

        // Parse PGN and setup board
        final game = bishop.Game.fromPgn(cleanedPgn);
        final squaresState = game.squaresState(Squares.white);
        boardState = squaresState.board;

        finalFen = game.fen;
        // _initializePGNWithRiverpod(cleanedPgn);
      });
    });
  }

  // void _initializePGNWithRiverpod(String cleanedPgn) {
  //   try {
  //     // Extract moves from PGN
  //     final extractedMoves = _extractMovesFromPgn(cleanedPgn);

  //     // Reset the chess game with the extracted moves
  //     final chessViewModel = ref.read(chessViewModelProvider.notifier);
  //     chessViewModel.resetGame(extractedMoves);

  //     // Update local board state from the chess game
  //     final chessState = ref.read(chessViewModelProvider);
  //     boardState = chessState.squaresState.board;
  //     finalFen = chessState.game.fen;
  //   } catch (e) {
  //     print('Error initializing PGN: $e');

  //     // Fallback - reset to empty game
  //     final chessViewModel = ref.read(chessViewModelProvider.notifier);
  //     chessViewModel.resetGame([]);

  //     final chessState = ref.read(chessViewModelProvider);
  //     boardState = chessState.squaresState.board;
  //     finalFen = chessState.game.fen;
  //   }
  // }

  // List<String> _extractMovesFromPgn(String pgn) {
  //   String movesSection = pgn.replaceAll(RegExp(r'\[.*?\]\s*'), '');

  //   // Remove result (1-0, 0-1, 1/2-1/2, *)
  //   movesSection = movesSection.replaceAll(
  //     RegExp(r'\s*(1-0|0-1|1/2-1/2|\*)\s*$'),
  //     '',
  //   );

  //   // Split by whitespace and filter out move numbers
  //   List<String> tokens =
  //       movesSection
  //           .split(RegExp(r'\s+'))
  //           .where((token) => token.isNotEmpty)
  //           .toList();

  //   List<String> moves = [];
  //   for (String token in tokens) {
  //     // Skip move numbers (like "1.", "2.", etc.)
  //     if (!RegExp(r'^\d+\.').hasMatch(token)) {
  //       // Skip comments and annotations
  //       if (!token.startsWith('{') && !token.startsWith('(')) {
  //         moves.add(token);
  //       }
  //     }
  //   }

  //   return moves;
  // }

  @override
  Widget build(BuildContext context) {
    // final chessState = ref.watch(chessViewModelProvider);

    // // Update local board state when chess state changes
    // if (mounted) {
    //   WidgetsBinding.instance.addPostFrameCallback((_) {
    //     if (boardState != chessState.squaresState.board) {
    //       setState(() {
    //         boardState = chessState.squaresState.board;
    //         finalFen = chessState.game.fen;
    //       });
    //     }
    //   });
    // }
    return Scaffold(
      bottomNavigationBar: ChessBoardBottomNavBar(
        onRightMove: () {},
        onLeftMove: () {},
      ),
      appBar: ChessMatchAppBar(
        title: '${firstGmName} vs ${secondGmName}',
        onBackPressed: () {
          Navigator.pop(context);
        },
        onSettingsPressed: () {},
        onMoreOptionsPressed: () {
          // Handle share button press
        },
      ),
      body: SingleChildScrollView(
        child: Column(
          // mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Chess board
            Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                PlayerFirstRowDetailWidget(
                  name: firstGmName,
                  firstGmRank: firstGmRank,
                  countryCode: firstGmCountryCode,
                  // flagAsset: 'assets/usa_flag.png',
                  time: firstGmTime,
                ),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final screenWidth = MediaQuery.of(context).size.height;
                    final boardHeight = screenWidth; // Assuming a square board
                    const sideBarWidth = 20.0;

                    // Make sidebar total height match the board height
                    final sidebarTotalHeight = boardHeight;

                    // Adjust proportions to match board height
                    final adjustedTopHeight = sidebarTotalHeight * 0.27;
                    final adjustedRedBarHeight = sidebarTotalHeight * 0.02;
                    final adjustedBottomHeight = sidebarTotalHeight * 0.27;

                    return SizedBox(
                      child: Row(
                        children: [
                          SizedBox(
                            width: sideBarWidth,

                            child: Column(
                              children: [
                                Container(
                                  height: adjustedTopHeight,
                                  color: kborderLeftColors,
                                ),
                                Container(
                                  height: adjustedRedBarHeight,
                                  color: Colors.red,
                                ),
                                Container(
                                  height: adjustedBottomHeight,
                                  color: kWhiteColor,
                                ),
                              ],
                            ),
                          ),
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
                SizedBox(height: 3.h),

                PlayerSecondRowDetailWidget(
                  name: secondGmName,
                  countryCode: secondGmCountryCode,
                  time: secondGmTime,
                  secondGmRank: secondGmRank,
                ),
              ],
            ),

            // SizedBox(height: 15.h),

            // Moves section
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              margin: EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
              ),
              child: Text(
                finalFen,
                style: AppTypography.textXsMedium.copyWith(color: kGreenColor),
              ),
            ),

            // Add bottom padding to ensure content doesn't get hidden behind bottom buttons
            const SizedBox(height: 100),
          ],
        ),
      ),
    );
  }

  Widget _buildMovesText(BuildContext context, ChessGameState chessState) {
    if (chessState.pgnMoves.isEmpty) {
      return Text(
        'No moves loaded',
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
        ),
        textAlign: TextAlign.center,
      );
    }

    final moves = chessState.pgnMoves;
    final currentMoveIndex = chessState.currentMoveIndex;

    List<InlineSpan> spans = [];

    for (int i = 0; i < moves.length; i += 2) {
      final moveNumber = (i ~/ 2) + 1;
      final whiteMove = moves[i];
      final blackMove = i + 1 < moves.length ? moves[i + 1] : null;

      // Move number
      spans.add(
        TextSpan(
          text: '$moveNumber. ',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
            fontWeight: FontWeight.w500,
          ),
        ),
      );

      // White move
      spans.add(
        TextSpan(
          text: '$whiteMove ',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color:
                i < currentMoveIndex
                    ? Theme.of(context).colorScheme.primary
                    : (i == currentMoveIndex
                        ? Theme.of(context).colorScheme.error
                        : Theme.of(context).colorScheme.onSurface),
            fontWeight:
                i == currentMoveIndex ? FontWeight.bold : FontWeight.normal,
            backgroundColor:
                i == currentMoveIndex
                    ? Theme.of(
                      context,
                    ).colorScheme.errorContainer.withOpacity(0.3)
                    : null,
          ),
        ),
      );

      // Black move (if exists)
      if (blackMove != null) {
        spans.add(
          TextSpan(
            text: '$blackMove ',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color:
                  i + 1 < currentMoveIndex
                      ? Theme.of(context).colorScheme.primary
                      : (i + 1 == currentMoveIndex
                          ? Theme.of(context).colorScheme.error
                          : Theme.of(context).colorScheme.onSurface),
              fontWeight:
                  i + 1 == currentMoveIndex
                      ? FontWeight.bold
                      : FontWeight.normal,
              backgroundColor:
                  i + 1 == currentMoveIndex
                      ? Theme.of(
                        context,
                      ).colorScheme.errorContainer.withOpacity(0.3)
                      : null,
            ),
          ),
        );
      }

      // Add new line after every 4 move pairs for better readability
      if (i > 0 && (i ~/ 2) % 4 == 0) {
        spans.add(const TextSpan(text: '\n'));
      }
    }

    return RichText(text: TextSpan(children: spans), textAlign: TextAlign.left);
  }
}
