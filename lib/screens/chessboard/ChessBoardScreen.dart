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

class ChessScreen extends StatefulWidget {
  const ChessScreen({super.key});

  @override
  State<ChessScreen> createState() => _ChessScreenState();
}

class _ChessScreenState extends State<ChessScreen> {
  late final String firstGmName;
  late final String secondGmName;
  late final String firstGmCountryCode;
  late final String secondGmCountryCode;
  late final String firstGmTime;
  late final String secondGmTime;
  late final String firstGmRank;
  late final String secondGmRank;
  late final String pgn;

  // Board state initialized in initState
  late BoardState boardState;
  //   final String pgn = '''
  // [Event "AAG S50 W50 S65"]
  // [Site "idChess.com"]
  // [Date "????.??.??"]
  // [Round "1"]
  // [White "Altan-Och, Genden"]
  // [Black "Leong, Ignatius"]
  // [Result "1/2-1/2"]
  // [WhiteElo "2198"]
  // [WhiteTitle "FM"]
  // [WhiteFideId "4900278"]
  // [BlackElo "1666"]
  // [BlackTitle "FM"]
  // [BlackFideId "5800242"]
  // [Board "8"]
  // [Variant "Standard"]
  // [ECO "D02"]
  // [Opening "Queen's Gambit Declined: Baltic Defense, Pseudo-Slav"]
  // [StudyName "Round 1"]
  // [ChapterName "Altan-Och, Genden - Leong, Ignatius"]
  // [UTCDate "2025.07.02"]
  // [UTCTime "07:48:48"]
  // [GameURL "https://lichess.org/broadcast/-/-/ZxgjkL1I"]

  // 1. d4 d5 2. c4 c6 3. Nf3 Bf5 4. Nc3 e6 5. cxd5 exd5 6. Bg5 Be7 7. Bf4 Nd7 8. e3 Ngf6 9. Bd3 Ne4 10. O-O Ndf6 11. Nh4 Nxc3 1/2-1/2
  // ''';

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
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 10,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Column(
                children: [
                  PlayerFirstRowDetailWidget(
                    name: firstGmName,
                    firstGmRank: firstGmRank,
                    countryCode: firstGmCountryCode,
                    // flagAsset: 'assets/usa_flag.png',
                    time: firstGmTime,
                  ),
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
                        // Column(
                        //   children: [
                        //     Container(
                        //       height: MediaQuery.of(context).size.height * 0.28,
                        //       width: 20.w,
                        //       color: kborderLeftColors,
                        //     ),
                        //     Container(
                        //       height: 6.h,
                        //       width: 20.w,
                        //       color: Colors.red,
                        //     ),
                        //     Container(
                        //       height: MediaQuery.of(context).size.height * 0.28,
                        //       width: 20.w,
                        //       color: kWhiteColor,
                        //     ),
                        //   ],
                        // ),

                        // Main Board area
                        Expanded(
                          child: Container(
                            color: Colors.transparent, // Avoid any blur/overlay
                            child: AbsorbPointer(
                              child: Board(
                                size: BoardSize.standard,
                                pieceSet: PieceSet.merida(),
                                playState: PlayState.observing,
                                state: boardState,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Container(
                  //   decoration: BoxDecoration(
                  //     border: Border.all(color: kBlackColor, width: 2.w),
                  //     boxShadow: [
                  //       BoxShadow(
                  //         color: Colors.grey.withOpacity(0.5),
                  //         blurRadius: 8.br,
                  //         offset: const Offset(0, 4),
                  //       ),
                  //     ],
                  //   ),
                  //   child: Board(
                  //     size: BoardSize.standard,
                  //     pieceSet: PieceSet.merida(),
                  //     playState: PlayState.observing,
                  //     state: boardState,
                  //   ),
                  // ),
                  SizedBox(height: 3.h),

                  PlayerSecondRowDetailWidget(
                    name: secondGmName,
                    countryCode: secondGmCountryCode,
                    time: secondGmTime,
                    secondGmRank: secondGmRank,
                  ),
                ],
              ),
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

      bottomNavigationBar: const ChessBoardBottomNavBar(),
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
