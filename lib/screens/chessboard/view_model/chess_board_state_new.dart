import 'package:chessever2/screens/chessboard/analysis/chess_game.dart';
import 'package:chessever2/screens/chessboard/analysis/chess_game_navigator.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:collection/collection.dart';
import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';

class AnalysisLine {
  static const ListEquality<String> _stringListEquality =
      ListEquality<String>();

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

  List<String> _uciMoves() =>
      moves.map((move) => move.uci).toList(growable: false);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    if (other is! AnalysisLine) {
      return false;
    }
    return other.evaluation == evaluation &&
        other.mate == mate &&
        _stringListEquality.equals(other.sanMoves, sanMoves) &&
        _stringListEquality.equals(other._uciMoves(), _uciMoves());
  }

  @override
  int get hashCode {
    return Object.hash(
      evaluation,
      mate,
      Object.hashAll(_uciMoves()),
      Object.hashAll(sanMoves),
    );
  }
}

class AnalysisBoardState {
  static const ListEquality<String> _stringListEquality =
      ListEquality<String>();
  static const ListEquality<AnalysisLine> _analysisLineListEquality =
      ListEquality<AnalysisLine>();

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

  static List<String> _movesToUci(List<Move> moves) =>
      moves.map((move) => move.uci).toList(growable: false);

  static List<String> _positionsToFen(List<Position> positions) =>
      positions.map((position) => position.fen).toList(growable: false);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    if (other is! AnalysisBoardState) {
      return false;
    }

    return other.currentMoveIndex == currentMoveIndex &&
        other.branchPointMoveIndex == branchPointMoveIndex &&
        other.position.fen == position.fen &&
        _stringListEquality.equals(other.moveSans, moveSans) &&
        _stringListEquality.equals(
          _movesToUci(other.allMoves),
          _movesToUci(allMoves),
        ) &&
        _stringListEquality.equals(
          _positionsToFen(other.positionHistory),
          _positionsToFen(positionHistory),
        ) &&
        _stringListEquality.equals(other.analysisMoveSans, analysisMoveSans) &&
        _stringListEquality.equals(
          _movesToUci(other.analysisMoves),
          _movesToUci(analysisMoves),
        ) &&
        _stringListEquality.equals(
          _positionsToFen(other.analysisPositionHistory),
          _positionsToFen(analysisPositionHistory),
        ) &&
        _analysisLineListEquality.equals(
          other.suggestionLines,
          suggestionLines,
        );
  }

  @override
  int get hashCode {
    return Object.hashAll([
      currentMoveIndex,
      branchPointMoveIndex,
      position.fen,
      Object.hashAll(moveSans),
      Object.hashAll(_movesToUci(allMoves)),
      Object.hashAll(_positionsToFen(positionHistory)),
      Object.hashAll(analysisMoveSans),
      Object.hashAll(_movesToUci(analysisMoves)),
      Object.hashAll(_positionsToFen(analysisPositionHistory)),
      Object.hashAll(suggestionLines),
    ]);
  }
}

class ChessBoardStateNew {
  static const ListEquality<String> _stringListEquality =
      ListEquality<String>();
  static const ListEquality<int> _intListEquality = ListEquality<int>();
  static const ListEquality<AnalysisLine> _analysisLineListEquality =
      ListEquality<AnalysisLine>();
  static const ListEquality<dynamic> _dynamicListEquality =
      ListEquality<dynamic>();

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
  final String? principalVariationsBaseFen;
  final int? selectedVariantIndex; // Track which engine suggestion is selected
  final List<int> variantMovePointer; // Track progress through selected variant
  final bool
  showEngineAnalysis; // Toggle visibility of engine gauge and principal variations
  final bool
  showPrincipalVariations; // Toggle visibility of principal variation cards only
  final bool
  hasUnseenMoves; // Flag to indicate if there are unseen moves (for live games)
  /// FEN position where current PVs were generated
  final String? variantBaseFen;

  /// Navigator position where PVs start
  final ChessMovePointer? variantBaseMovePointer;

  /// Last move before variant exploration
  final Move? variantBaseLastMove;

  /// Move index before variant exploration
  final int? variantBaseMoveIndex;
  final bool isPvPreviewActive;
  final int? pvPreviewVariantIndex;
  final int? pvPreviewMoveIndex;

  /// Locked PV line preserved during preview mode
  final AnalysisLine? lockedPvLine;

  /// Merged PGN history + PV moves for static card navigation (SAN notation)
  final List<String>? lockedPvMergedMoves;

  /// Current navigation index within the locked PV card
  final int? lockedPvNavigationIndex;

  /// Combined move objects (PGN history + PV moves) for preview navigation
  final List<Move>? lockedPvMergedMoveObjects;

  /// Position history aligned with [lockedPvMergedMoveObjects]
  final List<Position>? lockedPvMergedPositions;

  /// Number of moves that belong to the original PGN history
  final int? lockedPvBaseMoveCount;

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
    this.principalVariationsBaseFen,
    this.selectedVariantIndex,
    this.variantMovePointer = const [],
    this.showEngineAnalysis = true, // Active by default
    this.showPrincipalVariations = true, // Active by default
    this.hasUnseenMoves = false,
    this.variantBaseFen,
    this.variantBaseMovePointer,
    this.variantBaseLastMove,
    this.variantBaseMoveIndex,
    this.isPvPreviewActive = false,
    this.pvPreviewVariantIndex,
    this.pvPreviewMoveIndex,
    this.lockedPvLine,
    this.lockedPvMergedMoves,
    this.lockedPvNavigationIndex,
    this.lockedPvMergedMoveObjects,
    this.lockedPvMergedPositions,
    this.lockedPvBaseMoveCount,
  });

  static const _noChange = Object();

  static List<String> _movesToUci(List<Move> moves) =>
      moves.map((move) => move.uci).toList(growable: false);

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
    Object? principalVariationsBaseFen = _noChange,
    Object? selectedVariantIndex = _noChange,
    List<int>? variantMovePointer,
    bool? showEngineAnalysis,
    bool? showPrincipalVariations,
    bool? hasUnseenMoves,
    Object? variantBaseFen = _noChange,
    Object? variantBaseMovePointer = _noChange,
    Object? variantBaseLastMove = _noChange,
    Object? variantBaseMoveIndex = _noChange,
    bool? isPvPreviewActive,
    Object? pvPreviewVariantIndex = _noChange,
    Object? pvPreviewMoveIndex = _noChange,
    Object? lockedPvLine = _noChange,
    Object? lockedPvMergedMoves = _noChange,
    Object? lockedPvNavigationIndex = _noChange,
    Object? lockedPvMergedMoveObjects = _noChange,
    Object? lockedPvMergedPositions = _noChange,
    Object? lockedPvBaseMoveCount = _noChange,
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
      principalVariationsBaseFen:
          identical(principalVariationsBaseFen, _noChange)
              ? this.principalVariationsBaseFen
              : principalVariationsBaseFen as String?,
      selectedVariantIndex:
          identical(selectedVariantIndex, _noChange)
              ? this.selectedVariantIndex
              : selectedVariantIndex as int?,
      variantMovePointer: variantMovePointer ?? this.variantMovePointer,
      showEngineAnalysis: showEngineAnalysis ?? this.showEngineAnalysis,
      showPrincipalVariations:
          showPrincipalVariations ?? this.showPrincipalVariations,
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
      isPvPreviewActive: isPvPreviewActive ?? this.isPvPreviewActive,
      pvPreviewVariantIndex:
          identical(pvPreviewVariantIndex, _noChange)
              ? this.pvPreviewVariantIndex
              : pvPreviewVariantIndex as int?,
      pvPreviewMoveIndex:
          identical(pvPreviewMoveIndex, _noChange)
              ? this.pvPreviewMoveIndex
              : pvPreviewMoveIndex as int?,
      lockedPvLine:
          identical(lockedPvLine, _noChange)
              ? this.lockedPvLine
              : lockedPvLine as AnalysisLine?,
      lockedPvMergedMoves:
          identical(lockedPvMergedMoves, _noChange)
              ? this.lockedPvMergedMoves
              : lockedPvMergedMoves as List<String>?,
      lockedPvNavigationIndex:
          identical(lockedPvNavigationIndex, _noChange)
              ? this.lockedPvNavigationIndex
              : lockedPvNavigationIndex as int?,
      lockedPvMergedMoveObjects:
          identical(lockedPvMergedMoveObjects, _noChange)
              ? this.lockedPvMergedMoveObjects
              : lockedPvMergedMoveObjects as List<Move>?,
      lockedPvMergedPositions:
          identical(lockedPvMergedPositions, _noChange)
              ? this.lockedPvMergedPositions
              : lockedPvMergedPositions as List<Position>?,
      lockedPvBaseMoveCount:
          identical(lockedPvBaseMoveCount, _noChange)
              ? this.lockedPvBaseMoveCount
              : lockedPvBaseMoveCount as int?,
      analysisState: newAnalysisState,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    if (other is! ChessBoardStateNew) {
      return false;
    }

    final positionsEqual =
        (other.position == null && position == null) ||
        (other.position != null &&
            position != null &&
            other.position!.fen == position!.fen);
    final startingPositionsEqual =
        (other.startingPosition == null && startingPosition == null) ||
        (other.startingPosition != null &&
            startingPosition != null &&
            other.startingPosition!.fen == startingPosition!.fen);
    final lastMovesEqual =
        (other.lastMove == null && lastMove == null) ||
        (other.lastMove != null &&
            lastMove != null &&
            other.lastMove!.uci == lastMove!.uci);
    final variantLastMovesEqual =
        (other.variantBaseLastMove == null && variantBaseLastMove == null) ||
        (other.variantBaseLastMove != null &&
            variantBaseLastMove != null &&
            other.variantBaseLastMove!.uci == variantBaseLastMove!.uci);

    return other.game == game &&
        positionsEqual &&
        startingPositionsEqual &&
        lastMovesEqual &&
        other.currentMoveIndex == currentMoveIndex &&
        other.isPlaying == isPlaying &&
        other.isBoardFlipped == isBoardFlipped &&
        other.isLoadingMoves == isLoadingMoves &&
        other.evaluation == evaluation &&
        other.isEvaluating == isEvaluating &&
        other.mate == mate &&
        other.pgnData == pgnData &&
        other.fenData == fenData &&
        other.isAnalysisMode == isAnalysisMode &&
        other.showEngineAnalysis == showEngineAnalysis &&
        other.showPrincipalVariations == showPrincipalVariations &&
        other.hasUnseenMoves == hasUnseenMoves &&
        other.variantBaseFen == variantBaseFen &&
        _dynamicListEquality.equals(
          other.variantBaseMovePointer,
          variantBaseMovePointer,
        ) &&
        variantLastMovesEqual &&
        other.variantBaseMoveIndex == variantBaseMoveIndex &&
        other.isPvPreviewActive == isPvPreviewActive &&
        other.pvPreviewVariantIndex == pvPreviewVariantIndex &&
        other.pvPreviewMoveIndex == pvPreviewMoveIndex &&
        other.lockedPvLine == lockedPvLine &&
        _stringListEquality.equals(
          other.lockedPvMergedMoves,
          lockedPvMergedMoves,
        ) &&
        other.lockedPvNavigationIndex == lockedPvNavigationIndex &&
        _stringListEquality.equals(
          _movesToUci(other.lockedPvMergedMoveObjects ?? const []),
          _movesToUci(lockedPvMergedMoveObjects ?? const []),
        ) &&
        _stringListEquality.equals(
          AnalysisBoardState._positionsToFen(
            other.lockedPvMergedPositions ?? const [],
          ),
          AnalysisBoardState._positionsToFen(
            lockedPvMergedPositions ?? const [],
          ),
        ) &&
        other.lockedPvBaseMoveCount == lockedPvBaseMoveCount &&
        other.selectedVariantIndex == selectedVariantIndex &&
        other.shapes == shapes &&
        other.analysisState == analysisState &&
        _stringListEquality.equals(other.moveSans, moveSans) &&
        _stringListEquality.equals(other.moveTimes, moveTimes) &&
        _stringListEquality.equals(
          _movesToUci(other.allMoves),
          _movesToUci(allMoves),
        ) &&
        _analysisLineListEquality.equals(
          other.principalVariations,
          principalVariations,
        ) &&
        other.principalVariationsBaseFen == principalVariationsBaseFen &&
        _intListEquality.equals(
          other.variantMovePointer,
          variantMovePointer,
        );
  }

  @override
  int get hashCode {
    return Object.hashAll([
      game,
      position?.fen,
      startingPosition?.fen,
      lastMove?.uci,
      currentMoveIndex,
      isPlaying,
      isBoardFlipped,
      isLoadingMoves,
      evaluation,
      isEvaluating,
      mate,
      pgnData,
      fenData,
      isAnalysisMode,
      showEngineAnalysis,
      showPrincipalVariations,
      hasUnseenMoves,
      variantBaseFen,
      variantBaseMovePointer == null
          ? null
          : Object.hashAll(variantBaseMovePointer!),
      variantBaseLastMove?.uci,
      variantBaseMoveIndex,
      selectedVariantIndex,
      shapes,
      analysisState,
      Object.hashAll(_movesToUci(allMoves)),
      Object.hashAll(moveSans),
      Object.hashAll(moveTimes),
      Object.hashAll(principalVariations),
      principalVariationsBaseFen,
      Object.hashAll(variantMovePointer),
      isPvPreviewActive,
      pvPreviewVariantIndex,
      pvPreviewMoveIndex,
      lockedPvLine,
      lockedPvMergedMoves == null ? null : Object.hashAll(lockedPvMergedMoves!),
      lockedPvNavigationIndex,
      lockedPvMergedMoveObjects == null
          ? null
          : Object.hashAll(_movesToUci(lockedPvMergedMoveObjects!)),
      lockedPvMergedPositions == null
          ? null
          : Object.hashAll(
            AnalysisBoardState._positionsToFen(lockedPvMergedPositions!),
          ),
      lockedPvBaseMoveCount,
    ]);
  }
}
