import 'dart:async';
import 'dart:math';

import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:stockfish/stockfish.dart';

class ChessProgressBar extends StatefulWidget {
  final String fen;
  final bool useStockfish;

  const ChessProgressBar({
    required this.fen,
    this.useStockfish = true,
    super.key,
  });

  @override
  _ChessProgressBarState createState() => _ChessProgressBarState();
}

class _ChessProgressBarState extends State<ChessProgressBar> {
  double progress = 0.5; // Start at neutral position
  Stockfish? sf;
  bool _isEvaluating = false;
  bool _disposed = false;
  Timer? _timeoutTimer;

  @override
  void initState() {
    super.initState();
    print("ChessProgressBar: initState called with FEN: ${widget.fen}");
    if (widget.useStockfish) {
      _startAndEvaluateWithStockfish(widget.fen);
    } else {
      _startAndEvaluateWithFallback(widget.fen);
    }
  }

  @override
  void didUpdateWidget(ChessProgressBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.fen != widget.fen) {
      print("ChessProgressBar: FEN changed, re-evaluating");
      if (widget.useStockfish) {
        _startAndEvaluateWithStockfish(widget.fen);
      } else {
        _startAndEvaluateWithFallback(widget.fen);
      }
    }
  }

  // Fallback evaluation using simple heuristics
  Future<void> _startAndEvaluateWithFallback(String fen) async {
    print("Using fallback evaluation for FEN: $fen");

    setState(() {
      _isEvaluating = true;
    });

    // Simulate analysis time
    await Future.delayed(const Duration(milliseconds: 1000));

    if (_disposed) return;

    // Simple heuristic evaluation based on material count
    double evaluation = _evaluatePositionHeuristic(fen);

    final clampedScore = evaluation.clamp(-10.0, 10.0);
    final newProgress = (clampedScore + 10.0) / 20.0;

    if (mounted) {
      setState(() {
        progress = newProgress;
        _isEvaluating = false;
      });
    }
  }

  // Simple material-based evaluation
  double _evaluatePositionHeuristic(String fen) {
    if (fen.isEmpty) return 0.0;

    final parts = fen.split(' ');
    if (parts.isEmpty) return 0.0;

    final position = parts[0];

    // Piece values
    const pieceValues = {
      'q': 9.0,
      'Q': 9.0,
      'r': 5.0,
      'R': 5.0,
      'b': 3.0,
      'B': 3.0,
      'n': 3.0,
      'N': 3.0,
      'p': 1.0,
      'P': 1.0,
    };

    double whiteScore = 0.0;
    double blackScore = 0.0;

    for (int i = 0; i < position.length; i++) {
      final char = position[i];
      if (pieceValues.containsKey(char)) {
        if (char == char.toUpperCase()) {
          whiteScore += pieceValues[char]!;
        } else {
          blackScore += pieceValues[char]!;
        }
      }
    }

    // Add some randomness for variety
    final random = Random(fen.hashCode);
    final randomFactor = (random.nextDouble() - 0.5) * 2.0; // -1.0 to 1.0

    return (whiteScore - blackScore) + randomFactor;
  }

  Future<void> _startAndEvaluateWithStockfish(String fen) async {
    print("Starting Stockfish evaluation for FEN: $fen");

    // Validate FEN input
    if (fen.isEmpty || fen.trim().isEmpty) {
      print('Invalid FEN: FEN string is empty');
      _startAndEvaluateWithFallback(fen);
      return;
    }

    // Clean up previous instance
    _cleanup();

    setState(() {
      _isEvaluating = true;
    });

    try {
      // Try to create Stockfish instance
      sf = Stockfish();
      print("Stockfish instance created");

      // Set up timeout
      _timeoutTimer = Timer(const Duration(seconds: 10), () {
        print('Stockfish initialization timeout - using fallback');
        _cleanup();
        _startAndEvaluateWithFallback(fen);
      });

      // Wait for initialization with shorter delay
      await Future.delayed(const Duration(milliseconds: 500));

      if (_disposed) return;

      // Check if Stockfish is ready before sending commands
      if (sf?.state != StockfishState.ready) {
        print("Stockfish not ready, waiting...");
        await Future.delayed(const Duration(milliseconds: 1000));

        if (sf?.state != StockfishState.ready) {
          print("Stockfish still not ready after waiting - using fallback");
          _cleanup();
          _startAndEvaluateWithFallback(fen);
          return;
        }
      }

      print("Sending UCI command");
      sf!.stdin = 'uci';
      await Future.delayed(const Duration(milliseconds: 300));

      if (_disposed) return;

      print("Sending isready command");
      sf!.stdin = 'isready';
      await Future.delayed(const Duration(milliseconds: 300));

      if (_disposed) return;

      double? evalCp;
      bool evaluationComplete = false;

      sf!.stdout.listen(
        (line) {
          print("Stockfish output: $line");

          if (_disposed || evaluationComplete) return;

          if (line.contains('readyok')) {
            print("Stockfish is ready");
          } else if (line.startsWith('info') && line.contains('score')) {
            if (line.contains('score cp ')) {
              try {
                final parts = line.split(' ');
                final cpIndex = parts.indexOf('cp');
                if (cpIndex != -1 && cpIndex + 1 < parts.length) {
                  evalCp = int.parse(parts[cpIndex + 1]) / 100.0;
                  print("Found CP score: $evalCp");
                }
              } catch (e) {
                print('Error parsing centipawn score: $e');
              }
            } else if (line.contains('score mate ')) {
              try {
                final parts = line.split(' ');
                final mateIndex = parts.indexOf('mate');
                if (mateIndex != -1 && mateIndex + 1 < parts.length) {
                  final mateValue = int.parse(parts[mateIndex + 1]);
                  evalCp = mateValue > 0 ? 1000.0 : -1000.0;
                  print("Found mate score: $evalCp");
                }
              } catch (e) {
                print('Error parsing mate score: $e');
              }
            }
          } else if (line.startsWith('bestmove')) {
            print("Evaluation complete. Best move: $line");
            if (!evaluationComplete && !_disposed) {
              evaluationComplete = true;
              _timeoutTimer?.cancel();

              final score = (evalCp ?? 0.0).clamp(-10.0, 10.0);
              final newProgress = (score + 10.0) / 20.0;

              print(
                "Final evaluation: $evalCp, clamped: $score, progress: $newProgress",
              );

              if (mounted) {
                setState(() {
                  progress = newProgress;
                  _isEvaluating = false;
                });
              }

              _cleanup();
            }
          }
        },
        onError: (error) {
          print('Stockfish stream error: $error');
          _timeoutTimer?.cancel();
          _cleanup();
          _startAndEvaluateWithFallback(fen);
        },
      );

      if (_disposed) return;

      print("Setting position: $fen");
      sf!.stdin = 'position fen $fen';
      await Future.delayed(const Duration(milliseconds: 100));

      if (_disposed) return;

      print("Starting analysis with depth 2");
      sf!.stdin = 'go depth 2'; // Reduced depth for faster results
    } catch (e) {
      print('Error starting Stockfish evaluation: $e');
      _timeoutTimer?.cancel();
      _cleanup();
      // Fallback to heuristic evaluation
      _startAndEvaluateWithFallback(fen);
    }
  }

  void _cleanup() {
    _timeoutTimer?.cancel();
    _timeoutTimer = null;

    if (sf != null) {
      try {
        sf?.dispose();
      } catch (e) {
        print('Error disposing Stockfish: $e');
      }
      sf = null;
    }
  }

  @override
  void dispose() {
    print("ChessProgressBar: dispose called");
    _disposed = true;
    _cleanup();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _ProgressWidget(progress: progress, isEvaluating: _isEvaluating);
  }
}

class _ProgressWidget extends StatelessWidget {
  const _ProgressWidget({
    required this.progress,
    required this.isEvaluating,
    super.key,
  });

  final double progress;
  final bool isEvaluating;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 48.w,
      height: 12.h,
      child: Stack(
        children: [
          // Background container
          Container(
            width: 48.w,
            height: 12.h,
            decoration: BoxDecoration(
              color: kBlack2Color,
              borderRadius: BorderRadius.all(Radius.circular(4.br)),
            ),
          ),
          // Progress container
          AnimatedContainer(
            duration: const Duration(milliseconds: 500),
            width: (48.w * progress).clamp(0.0, 48.w),
            height: 12.h,
            decoration: BoxDecoration(
              color: kWhiteColor,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(4.br),
                bottomLeft: Radius.circular(4.br),
                topRight:
                    progress >= 0.99 ? Radius.circular(4.br) : Radius.zero,
                bottomRight:
                    progress >= 0.99 ? Radius.circular(4.br) : Radius.zero,
              ),
            ),
          ),
          // Loading indicator when evaluating
          if (isEvaluating)
            Container(
              width: 48.w,
              height: 12.h,
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.3),
                borderRadius: BorderRadius.all(Radius.circular(4.br)),
              ),
              child: Center(
                child: SizedBox(
                  width: 8,
                  height: 8,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
