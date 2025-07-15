import 'dart:async';
import 'package:bishop/bishop.dart' as bishop;
import 'package:supabase_flutter/supabase_flutter.dart';

// State class for chess board
class ChessBoardState {
  final List<bishop.Game> games;
  final List<List<String>> allMoves;
  final List<List<String>> sanMoves;
  final List<int> currentMoveIndex;
  final List<bool> isPlaying;
  final List<bool> isBoardFlipped;
  final List<double> evaluations;
  final Timer? autoPlayTimer;
  final RealtimeSubscribeStatus? subscriptionStatus;
  final bool isConnected;
  final String? lastError;
  final int? lastUpdatedGameIndex;
  final DateTime? lastUpdateTime;

  ChessBoardState({
    required this.games,
    required this.allMoves,
    required this.sanMoves,
    required this.currentMoveIndex,
    required this.isPlaying,
    required this.isBoardFlipped,
    required this.evaluations,
    this.autoPlayTimer,
    this.subscriptionStatus,
    required this.isConnected,
    this.lastError,
    this.lastUpdatedGameIndex,
    this.lastUpdateTime,
  });

  ChessBoardState copyWith({
    List<bishop.Game>? games,
    List<List<String>>? allMoves,
    List<List<String>>? sanMoves,
    List<int>? currentMoveIndex,
    List<bool>? isPlaying,
    List<bool>? isBoardFlipped,
    List<double>? evaluations,
    Timer? autoPlayTimer,
    RealtimeSubscribeStatus? subscriptionStatus,
    bool? isConnected,
    String? lastError,
    int? lastUpdatedGameIndex,
    DateTime? lastUpdateTime,
  }) {
    return ChessBoardState(
      games: games ?? this.games,
      allMoves: allMoves ?? this.allMoves,
      sanMoves: sanMoves ?? this.sanMoves,
      currentMoveIndex: currentMoveIndex ?? this.currentMoveIndex,
      isPlaying: isPlaying ?? this.isPlaying,
      isBoardFlipped: isBoardFlipped ?? this.isBoardFlipped,
      evaluations: evaluations ?? this.evaluations,
      autoPlayTimer: autoPlayTimer ?? this.autoPlayTimer,
      subscriptionStatus: subscriptionStatus ?? this.subscriptionStatus,
      isConnected: isConnected ?? this.isConnected,
      lastError: lastError ?? this.lastError,
      lastUpdatedGameIndex: lastUpdatedGameIndex,
      lastUpdateTime: lastUpdateTime,
    );
  }
}
