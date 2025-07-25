import 'dart:async';
import 'dart:ui';
import 'package:stockfish/stockfish.dart';

class StockfishSingleton {
  StockfishSingleton._();

  static final StockfishSingleton _i = StockfishSingleton._();

  factory StockfishSingleton() => _i;

  Stockfish? _engine;

  Future<Stockfish> get readyEngine async {
    if (_engine == null || _engine!.state.value != StockfishState.ready) {
      _engine?.dispose();
      _engine = Stockfish();
    }

    // Already ready
    if (_engine!.state.value == StockfishState.ready) return _engine!;

    // Otherwise wait for the ready signal
    final completer = Completer<Stockfish>();
    late VoidCallback listener;
    listener = () {
      if (_engine!.state.value == StockfishState.ready) {
        _engine!.state.removeListener(listener);
        if (!completer.isCompleted) completer.complete(_engine!);
      }
    };
    _engine!.state.addListener(listener);

    return completer.future;
  }

  void dispose() => _engine?.dispose();
}
