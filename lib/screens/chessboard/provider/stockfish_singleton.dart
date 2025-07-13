import 'package:stockfish/stockfish.dart';

// stockfish_singleton.dart
import 'package:stockfish/stockfish.dart';

class StockfishSingleton {
  static final StockfishSingleton _instance = StockfishSingleton._internal();

  late final Stockfish _stockfish;

  factory StockfishSingleton() => _instance;

  Stockfish get stockfish => _stockfish;

  StockfishSingleton._internal() {
    _stockfish = Stockfish();
  }

  void dispose() {
    _stockfish.dispose();
  }
}
