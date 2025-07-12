import 'package:chessever2/screens/tournaments/model/games_tour_model.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/screens/chessboard/widgets/chess_appbar.dart';
import 'package:chessever2/screens/chessboard/widgets/player_first_row_detail_widget.dart';
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
  late List<bishop.Game> _games;
  late List<List<String>> _allMoves;
  late List<int> _currentMoveIndex;

  @override
  void didChangeDependencies() {
    _pageController = PageController(initialPage: widget.currentIndex);
    _games = List.generate(widget.games.length, (index) => bishop.Game.fromPgn(_getPgnData()));
    _allMoves = _games.map((game) => game.moveHistoryAlgebraic).toList();
    _currentMoveIndex = List.filled(widget.games.length, 0);

    // Go to starting position
    for (int i = 0; i < _games.length; i++) {
      while (_games[i].canUndo) {
        _games[i].undo();
      }
    }

    super.didChangeDependencies();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  String _getPgnData() {
    return '''[Event "Round 3: Maxwell Z Yang - Jean Marco Cruz"]
[Site "?"]
[Date "????.??.??"]
[Round "3.2"]
[White "Maxwell Z Yang"]
[Black "Jean Marco Cruz"]
[Result "0-1"]
[BlackTitle "FM"]
[TimeControl "90+30"]
[ECO "E47"]
[Opening "Nimzo-Indian Defense: Normal Variation"]
[StudyName "Round 3"]
[ChapterName "Maxwell Z Yang - Jean Marco Cruz"]
[UTCDate "2025.06.28"]
[UTCTime "21:09:47"]
[GameURL "https://lichess.org/broadcast/-/-/WpR4zHCq"]

1. d4 { [%clk 1:25:46] } 1... Nf6 { [%clk 1:23:51] } 2. c4 { [%clk 1:26:10] } 2... e6 { [%clk 1:24:17] } 3. Nc3 { [%clk 1:26:33] } 3... Bb4 { [%clk 1:24:42] } 4. e3 { [%clk 1:26:59] } 4... O-O { [%clk 1:25:08] } 5. Bd3 { [%clk 1:27:24] } 5... Re8 { [%clk 1:25:34] } 6. Nf3 { [%clk 1:26:28] } 6... d6 { [%clk 1:26:01] } 7. O-O { [%clk 1:25:11] } 7... Bxc3 { [%clk 1:23:03] } 8. bxc3 { [%clk 1:25:32] } 8... e5 { [%clk 1:23:31] } 9. Nd2 { [%clk 1:16:47] } 9... Nc6 { [%clk 1:19:46] } 10. d5 { [%clk 1:11:22] } 10... Ne7 { [%clk 1:19:50] } 11. e4 { [%clk 1:10:51] } 11... Ng6 { [%clk 1:18:20] } 12. Nf3 { [%clk 1:10:24] } 12... Nh5 { [%clk 1:08:39] } 13. Be3 { [%clk 1:05:49] } 13... Ngf4 { [%clk 1:02:54] } 14. c5 { [%clk 1:00:50] } 14... Qf6 { [%clk 1:01:54] } 15. Ne1 { [%clk 0:54:43] } 15... Qg6 { [%clk 0:54:19] } 16. Kh1 { [%clk 0:48:43] } 16... Nxd3 { [%clk 0:53:16] } 17. Qxd3 { [%clk 0:48:35] } 17... f5 { [%clk 0:53:33] } 18. exf5 { [%clk 0:40:05] } 18... Bxf5 { [%clk 0:53:57] } 19. Qd2 { [%clk 0:40:01] } 19... Rf8 { [%clk 0:53:32] } 20. cxd6 { [%clk 0:37:53] } 20... cxd6 { [%clk 0:53:55] } 21. Nf3 { [%clk 0:37:45] } 21... Be4 { [%clk 0:52:31] } 22. Ne1 { [%clk 0:32:04] } 22... Nf4 { [%clk 0:33:58] } 23. Bxf4 { [%clk 0:28:03] } 23... Rxf4 { [%clk 0:34:26] } 24. f3 { [%clk 0:28:12] } 24... Raf8 { [%clk 0:34:47] } 25. Rg1 { [%clk 0:27:46] } 25... Bf5 { [%clk 0:28:08] } 26. Rd1 { [%clk 0:17:21] } 26... Rf6 { [%clk 0:26:04] } 27. Nd3 { [%clk 0:16:03] } 27... Bxd3 { [%clk 0:23:11] } 28. Qxd3 { [%clk 0:15:56] } 28... Qg3 { [%clk 0:23:32] } 29. Qb5 { [%clk 0:12:10] } 29... Rh6 { [%clk 0:22:59] } 30. Qe8+ { [%clk 0:11:53] } 30... Rf8 { [%clk 0:23:27] } 31. Qe6+ { [%clk 0:12:08] } 31... Rxe6 { [%clk 0:23:55] } 32. dxe6 { [%clk 0:12:29] } 32... Qg6 { [%clk 0:23:41] } 33. Rxd6 { [%clk 0:12:47] } 33... Re8 { [%clk 0:24:05] } 0-1''';
  }

  void _moveForward(int gameIndex) {
    if (_currentMoveIndex[gameIndex] < _allMoves[gameIndex].length) {
      setState(() {
        _games[gameIndex].makeMoveString(_allMoves[gameIndex][_currentMoveIndex[gameIndex]]);
        _currentMoveIndex[gameIndex]++;
      });
    }
  }

  void _moveBackward(int gameIndex) {
    if (_games[gameIndex].canUndo) {
      setState(() {
        _games[gameIndex].undo();
        _currentMoveIndex[gameIndex]--;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: PageView.builder(
        controller: _pageController,
        itemCount: widget.games.length,
        itemBuilder: (context, index) {
          final game = widget.games[index];
          final bishopGame = _games[index];

          final boardState = square_bishop.buildSquaresState(
            fen: bishopGame.fen,
          );

          if (boardState?.board == null) {
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

          return Scaffold(
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
                      final boardSize = screenWidth - sideBarWidth - 32;

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
                                  state: boardState!.board,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),

                  // Navigation controls
                  Container(
                    margin: EdgeInsets.all(16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        IconButton(
                          onPressed: bishopGame.canUndo
                              ? () => _moveBackward(index)
                              : null,
                          icon: Icon(Icons.arrow_back_ios),
                        ),
                        Text(
                          'Move ${_currentMoveIndex[index]} / ${_allMoves[index].length}',
                          style: AppTypography.textSmMedium,
                        ),
                        IconButton(
                          onPressed: _currentMoveIndex[index] < _allMoves[index].length
                              ? () => _moveForward(index)
                              : null,
                          icon: Icon(Icons.arrow_forward_ios),
                        ),
                      ],
                    ),
                  ),

                  // Bottom player (White)
                  PlayerFirstRowDetailWidget(
                    name: game.whitePlayer.name,
                    firstGmRank: game.whitePlayer.displayTitle,
                    countryCode: game.whitePlayer.countryCode,
                    time: game.whiteTimeDisplay,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
