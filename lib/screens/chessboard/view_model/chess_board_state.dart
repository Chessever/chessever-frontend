import 'dart:async';
import 'package:bishop/bishop.dart' as bishop;
import 'package:supabase_flutter/supabase_flutter.dart';

// State class for chess board
class ChessBoardState {
  final bishop.Game game;
  final List<String> allMoves;
  final List<String> sanMoves;
  final int currentMoveIndex;
  final bool isPlaying;
  final bool isBoardFlipped;
  final double evaluations;
  final Timer? autoPlayTimer;
  final RealtimeSubscribeStatus? subscriptionStatus;
  final bool isConnected;
  final String? lastError;
  final int? lastUpdatedGameIndex;
  final DateTime? lastUpdateTime;

  ChessBoardState({
    required this.game,
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
    bishop.Game? game,
    List<String>? allMoves,
    List<String>? sanMoves,
    int? currentMoveIndex,
    bool? isPlaying,
    bool? isBoardFlipped,
    double? evaluations,
    Timer? autoPlayTimer,
    RealtimeSubscribeStatus? subscriptionStatus,
    bool? isConnected,
    String? lastError,
    int? lastUpdatedGameIndex,
    DateTime? lastUpdateTime,
  }) {
    return ChessBoardState(
      game: game ?? this.game,
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
