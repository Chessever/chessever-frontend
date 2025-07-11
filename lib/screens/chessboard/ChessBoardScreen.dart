import 'package:chessever2/screens/chessboard/view_model/chess_board_fen_model.dart';
import 'package:chessever2/screens/tournaments/model/games_tour_model.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:chessever2/screens/chessboard/widgets/chess_appbar.dart';

import 'package:chessever2/screens/chessboard/widgets/player_first_row_detail_widget.dart';
import 'package:chessever2/screens/chessboard/widgets/player_second_row_detail_widget.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:chessever2/screens/chessboard/widgets/chess_board_bottom_nav_bar.dart';
import 'package:squares/squares.dart'; // Add this import
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

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    _pageController = PageController(initialPage: widget.currentIndex);
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

          // Parse PGN and board state
          final cleanedPgn = game.pgn!.replaceAll(
            RegExp(r'\[Variant\s+"[^"]*"\]\n?'),
            '',
          );
          final bishopGame = bishop.Game.fromPgn(cleanedPgn);
          final boardState = bishopGame.squaresState(0).board;

          final fen = bishopGame.fen;

          return Scaffold(
            // bottomNavigationBar: ChessBoardBottomNavBar(
            //   onRightMove: () {},
            //   onLeftMove: () {},
            // ),
            appBar: ChessMatchAppBar(
              title: '${game.whitePlayer.name} vs ${game.blackPlayer.name}',
              onBackPressed: () {
                Navigator.pop(context);
              },
              onSettingsPressed: () {},
              onMoreOptionsPressed: () {},
            ),
            body: SingleChildScrollView(
              child: Column(
                children: [
                  /// Top player info
                  PlayerFirstRowDetailWidget(
                    name: game.whitePlayer.name,
                    firstGmRank: game.whitePlayer.displayTitle,
                    countryCode: game.whitePlayer.countryCode,
                    time: game.whiteTimeDisplay,
                  ),

                  /// Board with left bar
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final screenHeight = MediaQuery.of(context).size.height;
                      final boardHeight = screenHeight;
                      const sideBarWidth = 20.0;

                      final sidebarTotalHeight = boardHeight;
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

                  /// Bottom player info
                  SizedBox(height: 12),
                  PlayerSecondRowDetailWidget(
                    name: game.blackPlayer.name,
                    secondGmRank: game.blackPlayer.displayTitle,
                    countryCode: game.blackPlayer.countryCode,
                    time: game.blackTimeDisplay,
                  ),

                  /// FEN display
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    margin: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                    ),
                    child: Text(
                      fen,
                      style: AppTypography.textXsMedium.copyWith(
                        color: kGreenColor,
                      ),
                    ),
                  ),

                  const SizedBox(height: 100),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
