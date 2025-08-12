import 'dart:async';
import 'dart:collection';
import 'dart:ui';
import 'package:stockfish/stockfish.dart';

class StockfishSingleton {
  StockfishSingleton._();
  static final StockfishSingleton _i = StockfishSingleton._();
  factory StockfishSingleton() => _i;

  Stockfish? _engine;
  final Queue<_EvalJob> _queue = Queue<_EvalJob>();
  bool _isWorking = false;

  Future<double> evaluatePosition(String fen) async {
    final completer = Completer<double>();
    _queue.add(_EvalJob(fen, completer));
    _processQueue();
    return completer.future;
  }

  Future<void> _processQueue() async {
    if (_isWorking || _queue.isEmpty) return;
    _isWorking = true;

    // Ensure engine is ready
    if (_engine == null || _engine!.state.value != StockfishState.ready) {
      _engine?.dispose();
      _engine = Stockfish();
      await _waitUntilReady();
    }

    while (_queue.isNotEmpty) {
      final job = _queue.removeFirst();
      final fen = job.fen;
      final completer = job.completer;

      double result = 0.0;
      final sub = _engine!.stdout.listen((line) {
        final cp = RegExp(r'score cp (-?\d+)').firstMatch(line)?.group(1);
        if (cp != null) {
          result = int.parse(cp) / 100.0;
        } else {
          final mate = RegExp(r'score mate (-?\d+)').firstMatch(line)?.group(1);
          if (mate != null) result = int.parse(mate).sign * 10.0;
        }
        if (line.startsWith('bestmove')) {
          if (!completer.isCompleted) completer.complete(result);
        }
      });

      _engine!.stdin = 'position fen $fen';
      _engine!.stdin = 'go depth 10';

      await completer.future.timeout(
        const Duration(seconds: 3),
        onTimeout: () {
          if (!completer.isCompleted) completer.complete(0.0);
          return 0.0;
        },
      );

      sub.cancel();
    }

    _isWorking = false;
  }

  Future<void> _waitUntilReady() async {
    if (_engine!.state.value == StockfishState.ready) return;
    final completer = Completer<void>();
    late VoidCallback listener;
    listener = () {
      if (_engine!.state.value == StockfishState.ready) {
        _engine!.state.removeListener(listener);
        if (!completer.isCompleted) completer.complete();
      }
    };
    _engine!.state.addListener(listener);
    await completer.future;
  }

  void dispose() {
    _engine?.dispose();
    _engine = null;
  }
}

class _EvalJob {
  final String fen;
  final Completer<double> completer;
  _EvalJob(this.fen, this.completer);
}
