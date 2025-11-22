import 'dart:async';

import 'package:chessever2/repository/library/library_repository.dart';
import 'package:chessever2/repository/library/models/saved_analysis.dart';
import 'package:chessever2/screens/chessboard/chess_board_screen_new.dart';
import 'package:chessever2/screens/chessboard/provider/chess_board_screen_provider_new.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Navigates to chess board screen with a loaded saved analysis
///
/// This creates a SavedAnalysisData from the SavedAnalysis and passes it
/// to ChessBoardScreenNew for full state restoration including:
/// - All variations from the ChessGame tree
/// - variationComments restoration
/// - movePointer navigation position (via lastViewedPosition)
/// - isBoardFlipped preference (from analysisState)
Future<void> loadSavedAnalysis(
  BuildContext context,
  SavedAnalysis analysis,
) async {
  // Update last opened timestamp but don't block navigation on errors
  try {
    final container = ProviderScope.containerOf(context, listen: false);
    final repository = container.read(libraryRepositoryProvider);
    await repository.updateLastOpened(analysis.id);
  } catch (_) {
    // Best-effort update; proceed even if we cannot write
  }

  if (!context.mounted) return;

  // Convert SavedAnalysis to GamesTourModel format
  final game = _convertToGamesTourModel(analysis);

  // Create SavedAnalysisData for full state restoration
  final savedAnalysisData = _createSavedAnalysisData(analysis);

  // Navigate to chess board with saved analysis data
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => ChessBoardScreenNew(
        currentIndex: 0,
        games: [game],
        savedAnalysisData: savedAnalysisData,
      ),
    ),
  );
}

/// Creates SavedAnalysisData from SavedAnalysis for state restoration
SavedAnalysisData _createSavedAnalysisData(SavedAnalysis analysis) {
  // Extract board flip preference from analysisState (snake_case from DB)
  final isBoardFlipped =
      analysis.analysisState['is_board_flipped'] as bool? ?? false;

  // Extract movePointer from analysisState if saved (snake_case from DB)
  List<int>? movePointer;
  final savedPointer = analysis.analysisState['move_pointer'];
  if (savedPointer is List) {
    movePointer = savedPointer.cast<int>();
  }

  return SavedAnalysisData(
    analysisId: analysis.id,
    chessGame: analysis.chessGame,
    variationComments: analysis.variationComments,
    movePointer: movePointer,
    isBoardFlipped: isBoardFlipped,
    lastViewedPosition: analysis.lastViewedPosition,
  );
}

/// Converts a SavedAnalysis to GamesTourModel format
///
/// This creates a minimal GamesTourModel that the chess board can display.
/// Uses analysis.id as gameId to avoid conflicts with live games.
GamesTourModel _convertToGamesTourModel(SavedAnalysis analysis) {
  final chessGame = analysis.chessGame;

  // Extract player info from metadata
  final whiteName = chessGame.metadata['White'] as String? ?? 'White';
  final blackName = chessGame.metadata['Black'] as String? ?? 'Black';
  final result = chessGame.metadata['Result'] as String? ?? '*';

  // Create player cards with minimal info
  final whitePlayer = PlayerCard(
    name: whiteName,
    federation: '',
    title: '',
    rating: 0,
    countryCode: '',
    team: null,
    fideId: null,
  );

  final blackPlayer = PlayerCard(
    name: blackName,
    federation: '',
    title: '',
    rating: 0,
    countryCode: '',
    team: null,
    fideId: null,
  );

  // Use analysis.id as gameId to avoid conflicts with live games
  // The original source game ID is preserved in analysis.sourceGameId
  return GamesTourModel(
    gameId: 'saved_analysis_${analysis.id}',
    whitePlayer: whitePlayer,
    blackPlayer: blackPlayer,
    whiteTimeDisplay: '--:--',
    blackTimeDisplay: '--:--',
    whiteClockCentiseconds: 0,
    blackClockCentiseconds: 0,
    gameStatus: GameStatus.fromString(result),
    roundId: 'saved_analysis',
    tourId: 'library',
    // PGN is not used when savedAnalysisData is provided - the ChessGame is used directly
    pgn: '',
  );
}
