import 'package:stockfish/stockfish.dart';

class StockfishSingleton {
  static final StockfishSingleton _i = StockfishSingleton._();
  StockfishSingleton._();
  factory StockfishSingleton() => _i;

  Stockfish? _engine;
  Stockfish get engine {
    if (_engine == null || _engine!.state.value != StockfishState.ready) {
      _engine?.dispose();
      _engine = Stockfish();
    }
    return _engine!;
  }

  void dispose() => _engine?.dispose();
}