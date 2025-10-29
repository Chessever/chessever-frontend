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

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is AnalysisLine &&
        other.evaluation == evaluation &&
        other.mate == mate &&
        other.sanMoves.length == sanMoves.length;
  }

  @override
  int get hashCode {
    return (evaluation?.hashCode ?? 0) ^
        (mate?.hashCode ?? 0) ^
        sanMoves.length.hashCode;
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

  // Analysis variation tracking
  final int?
  branchPointMoveIndex; // The move index where analysis branch started
  final List<String> analysisMoveSans; // SAN moves made in analysis mode
  final List<Move> analysisMoves; // Moves made in analysis mode
  final List<Position>
  analysisPositionHistory; // Position history for analysis moves

  bool get canMoveForward =>
      isInAnalysisVariation
          ? currentMoveIndex <
              (branchPointMoveIndex ?? -1) + analysisMoves.length
          : currentMoveIndex < allMoves.length - 1;

  bool get canMoveBackward => currentMoveIndex >= 0;

  bool get isAtStart => currentMoveIndex == -1;

  bool get isAtEnd =>
      isInAnalysisVariation
          ? currentMoveIndex ==
              (branchPointMoveIndex ?? -1) + analysisMoves.length
          : currentMoveIndex == allMoves.length - 1;

  int get totalMoves =>
      isInAnalysisVariation
          ? (branchPointMoveIndex ?? 0) + 1 + analysisMoves.length
          : allMoves.length;

  bool get isInAnalysisVariation =>
      branchPointMoveIndex != null && analysisMoves.isNotEmpty;

  bool get isAtBranchPoint => currentMoveIndex == branchPointMoveIndex;

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
    this.branchPointMoveIndex,
    this.analysisMoveSans = const [],
    this.analysisMoves = const [],
    this.analysisPositionHistory = const [],
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
    int? branchPointMoveIndex,
    List<String>? analysisMoveSans,
    List<Move>? analysisMoves,
    List<Position>? analysisPositionHistory,
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
      branchPointMoveIndex: branchPointMoveIndex ?? this.branchPointMoveIndex,
      analysisMoveSans: analysisMoveSans ?? this.analysisMoveSans,
      analysisMoves: analysisMoves ?? this.analysisMoves,
      analysisPositionHistory:
          analysisPositionHistory ?? this.analysisPositionHistory,
    );
  }

  /// Get combined move SAN list (mainline + analysis moves)
  List<String> get combinedMoveSans {
    if (!isInAnalysisVariation) {
      return moveSans;
    }
    final branchIndex = branchPointMoveIndex ?? -1;
    return [...moveSans.take(branchIndex + 1), ...analysisMoveSans];
  }

  /// Get combined move list (mainline + analysis moves)
  List<Move> get combinedMoves {
    if (!isInAnalysisVariation) {
      return allMoves;
    }
    final branchIndex = branchPointMoveIndex ?? -1;
    return [...allMoves.take(branchIndex + 1), ...analysisMoves];
  }

  /// Get combined position history (mainline + analysis positions)
  List<Position> get combinedPositionHistory {
    if (!isInAnalysisVariation) {
      return positionHistory;
    }
    final branchIndex = branchPointMoveIndex ?? -1;
    return [
      ...positionHistory.take(
        branchIndex + 2,
      ), // +2 because history includes starting position
      ...analysisPositionHistory,
    ];
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is AnalysisBoardState &&
        other.currentMoveIndex == currentMoveIndex &&
        other.position.fen == position.fen &&
        other.moveSans.length == moveSans.length &&
        other.branchPointMoveIndex == branchPointMoveIndex &&
        other.analysisMoves.length == analysisMoves.length;
  }

  @override
  int get hashCode {
    return currentMoveIndex.hashCode ^
        position.fen.hashCode ^
        moveSans.length.hashCode ^
        (branchPointMoveIndex?.hashCode ?? 0) ^
        analysisMoves.length.hashCode;
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
  final int? selectedVariantIndex; // Track which engine suggestion is selected
  final List<int> variantMovePointer; // Track progress through selected variant
  final bool showEngineAnalysis; // Toggle visibility of engine gauge and principal variations
  final bool showPrincipalVariations; // Toggle visibility of principal variation cards only
  final bool hasUnseenMoves; // Track if there are new moves the user hasn't seen yet
  /// FEN position where current PVs were generated
  final String? variantBaseFen;

  /// Navigator position where PVs start
  final ChessMovePointer? variantBaseMovePointer;

  /// Last move before variant exploration
  final Move? variantBaseLastMove;

  /// Move index before variant exploration
  final int? variantBaseMoveIndex;

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
    this.selectedVariantIndex,
    this.variantMovePointer = const [],
    this.showEngineAnalysis = true, // Active by default
    this.showPrincipalVariations = true, // Active by default
    this.hasUnseenMoves = false,
    this.variantBaseFen,
    this.variantBaseMovePointer,
    this.variantBaseLastMove,
    this.variantBaseMoveIndex,
  });

  static const _noChange = Object();

  ChessBoardStateNew copyWith({
    Object? position = _noChange,
    Object? startingPosition = _noChange,
    Object? lastMove = _noChange,
    List<Move>? allMoves,
    List<String>? moveSans,
    List<String>? moveTimes,
    int? currentMoveIndex,
    bool? isPlaying,
    bool? isBoardFlipped,
    bool? isLoadingMoves,
    Object? evaluation = _noChange,
    bool? isEvaluating,
    Object? mate = _noChange,
    GamesTourModel? game,
    Object? pgnData = _noChange,
    Object? fenData = _noChange,
    bool? isAnalysisMode,
    AnalysisBoardState? analysisState,
    ISet<Shape>? shapes,
    List<AnalysisLine>? principalVariations,
    Object? selectedVariantIndex = _noChange,
    List<int>? variantMovePointer,
    bool? showEngineAnalysis,
    bool? showPrincipalVariations,
    bool? hasUnseenMoves,
    Object? variantBaseFen = _noChange,
    Object? variantBaseMovePointer = _noChange,
    Object? variantBaseLastMove = _noChange,
    Object? variantBaseMoveIndex = _noChange,
  }) {
    final newAnalysisState = analysisState ?? this.analysisState;

    return ChessBoardStateNew(
      position:
          identical(position, _noChange)
              ? this.position
              : position as Position?,
      startingPosition:
          identical(startingPosition, _noChange)
              ? this.startingPosition
              : startingPosition as Position?,
      lastMove:
          identical(lastMove, _noChange) ? this.lastMove : lastMove as Move?,
      allMoves: allMoves ?? this.allMoves,
      moveSans: moveSans ?? this.moveSans,
      moveTimes: moveTimes ?? this.moveTimes,
      currentMoveIndex: currentMoveIndex ?? this.currentMoveIndex,
      isPlaying: isPlaying ?? this.isPlaying,
      isBoardFlipped: isBoardFlipped ?? this.isBoardFlipped,
      isLoadingMoves: isLoadingMoves ?? this.isLoadingMoves,
      evaluation:
          identical(evaluation, _noChange)
              ? this.evaluation
              : evaluation as double?,
      isEvaluating: isEvaluating ?? this.isEvaluating,
      game: game ?? this.game,
      pgnData:
          identical(pgnData, _noChange) ? this.pgnData : pgnData as String?,
      fenData:
          identical(fenData, _noChange) ? this.fenData : fenData as String?,
      mate: identical(mate, _noChange) ? this.mate : mate as int?,
      isAnalysisMode: isAnalysisMode ?? this.isAnalysisMode,
      shapes: shapes ?? this.shapes,
      principalVariations: principalVariations ?? this.principalVariations,
      selectedVariantIndex:
          identical(selectedVariantIndex, _noChange)
              ? this.selectedVariantIndex
              : selectedVariantIndex as int?,
      variantMovePointer: variantMovePointer ?? this.variantMovePointer,
      showEngineAnalysis: showEngineAnalysis ?? this.showEngineAnalysis,
      showPrincipalVariations: showPrincipalVariations ?? this.showPrincipalVariations,
      hasUnseenMoves: hasUnseenMoves ?? this.hasUnseenMoves,
      variantBaseFen:
          identical(variantBaseFen, _noChange)
              ? this.variantBaseFen
              : variantBaseFen as String?,
      variantBaseMovePointer:
          identical(variantBaseMovePointer, _noChange)
              ? this.variantBaseMovePointer
              : variantBaseMovePointer as ChessMovePointer?,
      variantBaseLastMove:
          identical(variantBaseLastMove, _noChange)
              ? this.variantBaseLastMove
              : variantBaseLastMove as Move?,
      variantBaseMoveIndex:
          identical(variantBaseMoveIndex, _noChange)
              ? this.variantBaseMoveIndex
              : variantBaseMoveIndex as int?,
      analysisState: newAnalysisState,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ChessBoardStateNew &&
        other.game == game &&
        other.currentMoveIndex == currentMoveIndex &&
        other.isPlaying == isPlaying &&
        other.isBoardFlipped == isBoardFlipped &&
        other.isLoadingMoves == isLoadingMoves &&
        other.evaluation == evaluation &&
        other.isEvaluating == isEvaluating &&
        other.pgnData == pgnData &&
        other.fenData == fenData &&
        other.isAnalysisMode == isAnalysisMode &&
        other.mate == mate &&
        other.selectedVariantIndex == selectedVariantIndex &&
        other.showEngineAnalysis == showEngineAnalysis &&
        other.showPrincipalVariations == showPrincipalVariations &&
        other.hasUnseenMoves == hasUnseenMoves &&
        other.variantBaseFen == variantBaseFen;
  }

  @override
  int get hashCode {
    return game.hashCode ^
        currentMoveIndex.hashCode ^
        isPlaying.hashCode ^
        isBoardFlipped.hashCode ^
        isLoadingMoves.hashCode ^
        (evaluation?.hashCode ?? 0) ^
        isEvaluating.hashCode ^
        (pgnData?.hashCode ?? 0) ^
        (fenData?.hashCode ?? 0) ^
        isAnalysisMode.hashCode ^
        (mate?.hashCode ?? 0) ^
        (selectedVariantIndex?.hashCode ?? 0) ^
        showEngineAnalysis.hashCode ^
        showPrincipalVariations.hashCode ^
        hasUnseenMoves.hashCode ^
        (variantBaseFen?.hashCode ?? 0);
  }
}
