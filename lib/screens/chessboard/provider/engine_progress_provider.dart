import 'dart:async';

import 'package:chessever2/repository/lichess/cloud_eval/cloud_eval.dart';
import 'package:chessever2/screens/chessboard/provider/stockfish_singleton.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class EngineDepthState {
  final String fen;
  final int depth;
  final int knodes;
  final List<Pv> pvs;
  const EngineDepthState({
    required this.fen,
    required this.depth,
    required this.knodes,
    required this.pvs,
  });
}

final engineDepthProvider =
    StateNotifierProvider<EngineDepthNotifier, Map<String, EngineDepthState>>(
  (ref) {
    final notifier = EngineDepthNotifier();
    // Subscribe to stockfish progress stream
    final sub = StockfishSingleton().progressStream.listen((progress) {
      notifier._update(
        EngineDepthState(
          fen: progress.fen,
          depth: progress.depth,
          knodes: progress.knodes,
          pvs: progress.pvs,
        ),
      );
    });
    ref.onDispose(sub.cancel);
    return notifier;
  },
);

class EngineDepthNotifier extends StateNotifier<Map<String, EngineDepthState>> {
  EngineDepthNotifier() : super(<String, EngineDepthState>{});

  void _update(EngineDepthState s) {
    state = {...state, s.fen: s};
  }
}

