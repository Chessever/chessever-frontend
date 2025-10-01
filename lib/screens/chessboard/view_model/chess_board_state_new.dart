import 'package:chessever2/screens/chessboard/analysis/chess_game.dart';
import 'package:chessever2/screens/chessboard/analysis/chess_game_navigator.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';

class AnalysisLine {
  final List<Move> moves;
  final List<String> sanMoves;
  final double? evaluation;
  final int? mate;

  const AnalysisLine({
    this.moves = const [],
    this.sanMoves = const [],
    this.evaluation,
    this.mate,
  });

  bool get isEmpty => moves.isEmpty;
  bool get isMate => mate != null;
  String get displayEval =>
      isMate
          ? '#$mate'
          : evaluation != null
          ? evaluation!.toStringAsFixed(1)
          : '';

  AnalysisLine copyWith({
    List<Move>? moves,
    List<String>? sanMoves,
    double? evaluation,
    int? mate,
  }) {
    return AnalysisLine(
      moves: moves ?? this.moves,
      sanMoves: sanMoves ?? this.sanMoves,
      evaluation: evaluation ?? this.evaluation,
      mate: mate ?? this.mate,
    );
  }
}

class AnalysisBoardState {
  final Move? lastMove;
  final NormalMove? promotionMove;
  final ValidMoves validMoves;
  final List<Position> positionHistory;
  final List<String> moveSans;
  final List<Move> allMoves;
  final Position position;
  final Position? startingPosition;
  final int currentMoveIndex;
  final List<AnalysisLine> suggestionLines;
  final ChessGame? game;
  final ChessMovePointer movePointer;

  bool get canMoveForward => currentMoveIndex < allMoves.length - 1;

  bool get canMoveBackward => currentMoveIndex >= 0;

  bool get isAtStart => currentMoveIndex == -1;

  bool get isAtEnd => currentMoveIndex == allMoves.length - 1;

  int get totalMoves => allMoves.length;

  const AnalysisBoardState({
    this.lastMove,
    this.promotionMove,
    this.validMoves = const IMap.empty(),
    this.positionHistory = const [],
    this.moveSans = const [],
    this.allMoves = const [],
    this.position = Chess.initial,
    this.currentMoveIndex = -1,
    this.startingPosition,
    this.suggestionLines = const [],
    this.game,
    this.movePointer = const [],
  });

  AnalysisBoardState copyWith({
    String? fen,
    Move? lastMove,
    NormalMove? promotionMove,
    ValidMoves? validMoves,
    List<Position>? positionHistory,
    List<String>? moveSans,
    List<Move>? allMoves,
    Position? position,
    int? currentMoveIndex,
    Position? startingPosition,
    List<AnalysisLine>? suggestionLines,
    ChessGame? game,
    ChessMovePointer? movePointer,
  }) {
    return AnalysisBoardState(
      lastMove: lastMove ?? this.lastMove,
      promotionMove: promotionMove ?? this.promotionMove,
      validMoves: validMoves ?? this.validMoves,
      positionHistory: positionHistory ?? this.positionHistory,
      moveSans: moveSans ?? this.moveSans,
      allMoves: allMoves ?? this.allMoves,
      position: position ?? this.position,
      currentMoveIndex: currentMoveIndex ?? this.currentMoveIndex,
      startingPosition: startingPosition ?? this.startingPosition,
      suggestionLines: suggestionLines ?? this.suggestionLines,
      game: game ?? this.game,
      movePointer: movePointer ?? this.movePointer,
    );
  }
}

class ChessBoardStateNew {
  final Position? position;
  final Position? startingPosition;
  final Move? lastMove;
  final List<Move> allMoves;
  final List<String> moveSans;
  final List<String> moveTimes;
  final int currentMoveIndex;
  final bool isPlaying;
  final bool isBoardFlipped;
  final bool isLoadingMoves;
  final double? evaluation; // Made nullable to indicate loading state
  final bool isEvaluating; // Flag to show evaluation is in progress
  final GamesTourModel game;
  final String? pgnData;
  final String? fenData;
  final ISet<Shape>? shapes;
  final bool isAnalysisMode;
  final AnalysisBoardState analysisState;
  final int? mate;
  final List<AnalysisLine> principalVariations;

  bool get canMoveForward => currentMoveIndex < allMoves.length - 1;

  bool get canMoveBackward => currentMoveIndex >= 0;

  bool get isAtStart => currentMoveIndex == -1;

  bool get isAtEnd => currentMoveIndex == allMoves.length - 1;

  int get totalMoves => allMoves.length;

  const ChessBoardStateNew({
    this.position,
    this.startingPosition,
    this.lastMove,
    this.allMoves = const [],
    this.moveSans = const [],
    this.moveTimes = const [],
    this.currentMoveIndex = -1,
    this.isPlaying = false,
    this.isBoardFlipped = false,
    this.isLoadingMoves = false,
    this.evaluation = 0,
    this.isEvaluating = false,
    required this.game,
    this.pgnData,
    this.fenData,
    this.isAnalysisMode = false,
    this.analysisState = const AnalysisBoardState(),
    this.shapes = const ISet.empty(),
    this.mate,
    this.principalVariations = const [],
  });

  ChessBoardStateNew copyWith({
    Position? position,
    Position? startingPosition,
    Move? lastMove,
    List<Move>? allMoves,
    List<String>? moveSans,
    List<String>? moveTimes,
    int? currentMoveIndex,
    bool? isPlaying,
    bool? isBoardFlipped,
    bool? isLoadingMoves,
    double? evaluation,
    bool? isEvaluating,
    int? mate,
    GamesTourModel? game,
    String? pgnData,
    String? fenData,
    bool? isAnalysisMode,
    AnalysisBoardState? analysisState,
    ISet<Shape>? shapes,
    List<AnalysisLine>? principalVariations,
  }) {
    return ChessBoardStateNew(
      position: position ?? this.position,
      startingPosition: startingPosition ?? this.startingPosition,
      lastMove: lastMove ?? this.lastMove,
      allMoves: allMoves ?? this.allMoves,
      moveSans: moveSans ?? this.moveSans,
      moveTimes: moveTimes ?? this.moveTimes,
      currentMoveIndex: currentMoveIndex ?? this.currentMoveIndex,
      isPlaying: isPlaying ?? this.isPlaying,
      isBoardFlipped: isBoardFlipped ?? this.isBoardFlipped,
      isLoadingMoves: isLoadingMoves ?? this.isLoadingMoves,
      evaluation: evaluation ?? this.evaluation,
      isEvaluating: isEvaluating ?? this.isEvaluating,
      game: game ?? this.game,
      pgnData: pgnData ?? this.pgnData,
      fenData: fenData ?? this.fenData,
      mate: mate ?? this.mate,
      isAnalysisMode: isAnalysisMode ?? this.isAnalysisMode,
      shapes: shapes ?? this.shapes,
      principalVariations: principalVariations ?? this.principalVariations,
      analysisState:
          analysisState != null
              ? analysisState.copyWith(
                lastMove: analysisState.lastMove ?? this.analysisState.lastMove,
                promotionMove:
                    analysisState.promotionMove ??
                    this.analysisState.promotionMove,
                validMoves: analysisState.validMoves,
                positionHistory: analysisState.positionHistory,
                moveSans: analysisState.moveSans,
                allMoves: analysisState.allMoves,
                position: analysisState.position,
                currentMoveIndex: analysisState.currentMoveIndex,
                startingPosition:
                    analysisState.startingPosition ??
                    this.analysisState.startingPosition,
                suggestionLines: analysisState.suggestionLines,
                fen: fenData ?? this.fenData,
              )
              : this.analysisState,
    );
  }
}
