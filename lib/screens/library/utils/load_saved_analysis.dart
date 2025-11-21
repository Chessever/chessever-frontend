import 'package:chessever2/repository/library/models/saved_analysis.dart';
import 'package:chessever2/screens/chessboard/chess_board_screen_new.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:flutter/material.dart';

/// Navigates to chess board screen with a loaded saved analysis
///
/// This converts the SavedAnalysis into a GamesTourModel and navigates
/// to the chess board. The analysis game with all variations will be loaded.
///
/// TODO: Full state restoration including:
/// - variationComments restoration
/// - movePointer navigation position
/// - isBoardFlipped preference
/// - lastViewedPosition
void loadSavedAnalysis(BuildContext context, SavedAnalysis analysis) {
  // Convert SavedAnalysis to GamesTourModel format
  final game = _convertToGamesTourModel(analysis);

  // Navigate to chess board
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => ChessBoardScreenNew(
        currentIndex: 0,
        games: [game],
      ),
    ),
  );
}

/// Converts a SavedAnalysis to GamesTourModel format
///
/// This creates a minimal GamesTourModel that the chess board can display.
/// The saved ChessGame contains all the analysis with variations.
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

  return GamesTourModel(
    gameId: analysis.sourceGameId ?? analysis.id,
    whitePlayer: whitePlayer,
    blackPlayer: blackPlayer,
    whiteTimeDisplay: '--:--',
    blackTimeDisplay: '--:--',
    whiteClockCentiseconds: 0,
    blackClockCentiseconds: 0,
    gameStatus: GameStatus.fromString(result),
    roundId: 'saved_analysis',
    tourId: 'library',
    pgn: _generatePgnFromChessGame(chessGame, whiteName, blackName, result),
  );
}

/// Generates a basic PGN from ChessGame
///
/// This creates a PGN string from the ChessGame mainline.
/// The ChessGame object itself contains the full variation tree,
/// which will be used by the chess board provider.
String _generatePgnFromChessGame(
  chessGame,
  String whiteName,
  String blackName,
  String result,
) {
  final buffer = StringBuffer();

  // Add headers
  buffer.writeln('[Event "Saved Analysis"]');
  buffer.writeln('[Site "ChessEver"]');
  buffer.writeln('[White "$whiteName"]');
  buffer.writeln('[Black "$blackName"]');
  buffer.writeln('[Result "$result"]');
  buffer.writeln();

  // Add moves from mainline
  for (var i = 0; i < chessGame.mainline.length; i++) {
    final move = chessGame.mainline[i];
    if (i % 2 == 0) {
      buffer.write('${(i ~/ 2) + 1}. ');
    }
    buffer.write('${move.san} ');
  }

  // Add result
  buffer.write(result);

  return buffer.toString();
}
