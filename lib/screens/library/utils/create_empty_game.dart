import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';

/// Creates an empty game with starting position for analysis
///
/// This creates a minimal GamesTourModel with:
/// - Empty starting position (initial chess position)
/// - Placeholder player names
/// - Unique game ID for the session
GamesTourModel createEmptyGame() {
  final timestamp = DateTime.now().millisecondsSinceEpoch;

  // Create minimal player cards
  final whitePlayer = PlayerCard(
    name: 'White',
    federation: '',
    title: '',
    rating: 0,
    countryCode: '',
    team: null,
    fideId: null,
  );

  final blackPlayer = PlayerCard(
    name: 'Black',
    federation: '',
    title: '',
    rating: 0,
    countryCode: '',
    team: null,
    fideId: null,
  );

  // Create basic PGN with just headers and starting position
  final pgn = '''[Event "New Analysis"]
[Site "ChessEver"]
[Date "${DateTime.now().toIso8601String().split('T')[0]}"]
[White "White"]
[Black "Black"]
[Result "*"]

*''';

  return GamesTourModel(
    gameId: 'empty_game_$timestamp',
    source: GameSource.localAnalysis,
    whitePlayer: whitePlayer,
    blackPlayer: blackPlayer,
    whiteTimeDisplay: '--:--',
    blackTimeDisplay: '--:--',
    whiteClockCentiseconds: 0,
    blackClockCentiseconds: 0,
    gameStatus: GameStatus.unknown,
    roundId: 'library_new_analysis',
    tourId: 'library',
    pgn: pgn,
  );
}
