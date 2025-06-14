import 'package:chessever2/repository/models/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_chess_board/flutter_chess_board.dart';
import 'package:chess/chess.dart' as chess_logic;

class InGameView extends StatefulWidget {
  final DetailedGame game;

  const InGameView({super.key, required this.game});

  @override
  State<InGameView> createState() => _InGameViewState();
}

class _InGameViewState extends State<InGameView> {
  final ChessBoardController _controller = ChessBoardController();
  late chess_logic.Chess _engine;
  double _sliderValue = 0.0;
  int _prevIndex = 0;
  List<String> _moves = [];

  // Cached evaluation
  String _evalString = '?';
  double _evalNormalized = 0.5;
  bool _evalReady = false;

  @override
  void initState() {
    super.initState();
    _initializeEngine();
    _loadInitialPosition();
    _loadMoves();
    _loadEvaluation();
  }

  void _initializeEngine() {
    _engine = chess_logic.Chess.fromFEN(widget.game.broadcastGame.fen);
    _prevIndex = 0;
  }

  void _loadInitialPosition() {
    try {
      _controller.loadFen(widget.game.broadcastGame.fen);
    } catch (e) {
      debugPrint('Error loading FEN: $e');
    }
  }

  void _loadMoves() {
    widget.game.broadcastGame.evaluation.variations
        .then((list) {
          if (list.isNotEmpty) {
            setState(() {
              _moves = list.first.moves;
            });
          }
        })
        .catchError((_) {});
  }

  void _loadEvaluation() async {
    try {
      final s = await widget.game.broadcastGame.evaluation.evalString;
      final raw = double.tryParse(s) ?? 0;
      const maxCp = 7.0;
      final norm = ((raw + maxCp) / (2 * maxCp)).clamp(0.0, 1.0);
      setState(() {
        _evalString = s;
        _evalNormalized = norm;
        _evalReady = true;
      });
    } catch (_) {
      // keep defaults
    }
  }

  void _resetEngine() {
    _engine = chess_logic.Chess.fromFEN(widget.game.broadcastGame.fen);
    _prevIndex = 0;
  }

  void _onSliderChangeStart(double value) {
    _resetEngine();
    setState(() {
      _sliderValue = 0.0;
    });
  }

  void _onSliderChanged(double value) {
    final newIndex = value.toInt();
    if (newIndex > _prevIndex) {
      for (var i = _prevIndex; i < newIndex; i++) {
        final uci = _moves[i];
        final from = uci.substring(0, 2);
        final to = uci.substring(2, 4);
        _engine.move({'from': from, 'to': to});
      }
    } else if (newIndex < _prevIndex) {
      for (var i = 0; i < (_prevIndex - newIndex); i++) {
        _engine.undo_move();
      }
    }
    _prevIndex = newIndex;
    _controller.loadFen(_engine.fen);
    setState(() {
      _sliderValue = value;
    });
  }

  @override
  Widget build(BuildContext context) {
    final players = widget.game.broadcastGame.players;
    final screenHeight = MediaQuery.of(context).size.height;
    final maxBoardDim = screenHeight * 0.5;

    return Scaffold(
      appBar: AppBar(title: Text('${players[0]} vs ${players[1]}')),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Chess board with max half-screen height
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: maxBoardDim,
                    maxWidth: maxBoardDim,
                  ),
                  child: AspectRatio(
                    aspectRatio: 1.0,
                    child: ChessBoard(
                      controller: _controller,
                      boardColor: BoardColor.brown,
                      boardOrientation: PlayerColor.white,
                      enableUserMoves: false,
                    ),
                  ),
                ),
              ),
            ),

            // Evaluation bar (black-to-white)
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 16.0,
                vertical: 8.0,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    height: 4,
                    child: LinearProgressIndicator(
                      value: _evalNormalized,
                      backgroundColor: Colors.black,
                      valueColor: AlwaysStoppedAnimation(Colors.white),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _evalReady ? _evalString : '…',
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),

            // Principal variation slider
            if (_moves.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Text(
                  'Principal Variation:',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16.0,
                  vertical: 4.0,
                ),
                child: Text(
                  _moves.join(' '),
                  style: const TextStyle(fontSize: 14),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16.0,
                  vertical: 8.0,
                ),
                child: Slider(
                  min: 0,
                  max: _moves.length.toDouble(),
                  divisions: _moves.length,
                  value: _sliderValue,
                  label:
                      _sliderValue > 0
                          ? _moves[_sliderValue.toInt() - 1]
                          : 'Start',
                  onChangeStart: _onSliderChangeStart,
                  onChanged: _onSliderChanged,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Text(
                  'Move ${_sliderValue.toInt()} of ${_moves.length}',
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
