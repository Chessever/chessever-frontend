import 'package:flutter/material.dart';
import 'package:flutter_chess_board/flutter_chess_board.dart';
import 'package:chessever2/models/evaluation.dart';
import '../models/game.dart';
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

  @override
  void initState() {
    super.initState();
    _initializeEngine();
    _loadInitialPosition();
    _loadMoves();
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
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not load game position.')),
          );
        }
      });
    }
  }

  void _loadMoves() {
    widget.game.broadcastGame.evaluation.variations.then((list) {
      if (list.isNotEmpty) {
        setState(() {
          _moves = list.first.moves;
        });
      }
    }).catchError((_) {});
  }

  void _resetEngine() {
    _engine = chess_logic.Chess.fromFEN(widget.game.broadcastGame.fen);
  }

  void _onSliderChangeStart(double value) {
    _resetEngine();
    setState(() {
      _prevIndex = 0;
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

    return Scaffold(
      appBar: AppBar(
        title: Text('${players[0]} vs ${players[1]}'),
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: ChessBoard(
                controller: _controller,
                boardColor: BoardColor.brown,
                boardOrientation: PlayerColor.white,
                enableUserMoves: false,
              ),
            ),
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
                child: Text(
                  _moves.join(' '),
                  style: const TextStyle(fontSize: 14),
                ),
              ),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                child: Slider(
                  min: 0,
                  max: _moves.length.toDouble(),
                  divisions: _moves.length,
                  value: _sliderValue,
                  label: _sliderValue > 0
                      ? _moves[_sliderValue.toInt() - 1]
                      : 'Start',
                  onChangeStart: _onSliderChangeStart,
                  onChanged: _onSliderChanged,
                ),
              ),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16.0, vertical: 0),
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
