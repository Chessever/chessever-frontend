import 'package:chessever2/screens/chessboard/analysis/chess_game.dart';
import 'package:chessever2/screens/chessboard/game_review/game_analysis_report.dart';
import 'package:chessever2/screens/chessboard/notation/notation_tree.dart';
import 'package:chessever2/screens/chessboard/provider/chess_board_screen_provider_new.dart';
import 'package:chessever2/screens/chessboard/utils/game_share_utils.dart';
import 'package:chessever2/screens/chessboard/view_model/chess_board_state_new.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:flutter_test/flutter_test.dart';

const _canonicalGameId = 'fe6351a5-6354-4c16-b7f6-9124e5d9a9ef';
const _fullPgn = '''
[Event "Test Event"]
[Site "ChessEver"]
[Date "2026.03.25"]
[White "White"]
[Black "Black"]
[Result "*"]

1. e4 e5 2. Nf3 Nc6 *
''';
const _headerOnlyPgn = '''
[Event "Test Event"]
[Site "ChessEver"]
[Date "2026.03.25"]
[White "White"]
[Black "Black"]
[Result "*"]

*
''';

GamesTourModel _game({
  String gameId = _canonicalGameId,
  GameSource source = GameSource.supabase,
  String? pgn,
}) {
  return GamesTourModel(
    gameId: gameId,
    source: source,
    whitePlayer: PlayerCard(
      name: 'White',
      federation: '',
      title: '',
      rating: 0,
      countryCode: '',
      team: null,
      fideId: null,
    ),
    blackPlayer: PlayerCard(
      name: 'Black',
      federation: '',
      title: '',
      rating: 0,
      countryCode: '',
      team: null,
      fideId: null,
    ),
    whiteTimeDisplay: '--:--',
    blackTimeDisplay: '--:--',
    whiteClockCentiseconds: 0,
    blackClockCentiseconds: 0,
    gameStatus: GameStatus.ongoing,
    roundId: 'round',
    roundSlug: 'A00',
    tourId: 'tour',
    tourSlug: 'tour-slug',
    pgn: pgn,
  );
}

SavedAnalysisData _savedAnalysisData({String? sourceGameId}) {
  return SavedAnalysisData(
    analysisId: 'analysis-1',
    sourceGameId: sourceGameId,
    chessGame: ChessGame.fromPgn('saved', _fullPgn),
    variationComments: const <String, String>{},
    isBoardFlipped: false,
    lastViewedPosition: 0,
  );
}

void main() {
  group('buildGameShareUrl', () {
    test('returns a deep link for canonical Supabase games', () {
      final url = buildGameShareUrl(game: _game());

      expect(
        url,
        'https://chessever.com/games/$_canonicalGameId?tour=tour-slug&round=A00',
      );
    });

    test(
      'returns a deep link for saved analyses with canonical source IDs',
      () {
        final url = buildGameShareUrl(
          game: _game(
            gameId: 'saved_analysis_1',
            source: GameSource.savedAnalysis,
          ),
          savedAnalysisData: _savedAnalysisData(sourceGameId: _canonicalGameId),
        );

        expect(
          url,
          'https://chessever.com/games/$_canonicalGameId?tour=tour-slug&round=A00',
        );
      },
    );

    test(
      'derives a link from the Lichess broadcast Site header for TWIC games',
      () {
        const broadcastPgn = '''
[Event "Norway Chess 2026"]
[Site "https://lichess.org/broadcast/norway-chess-2026/round-6/AbCd1234/xYz45678"]
[White "White"]
[Black "Black"]
[Result "1-0"]

*
''';
        final url = buildGameShareUrl(
          game: _game(
            gameId: 'twic-1',
            source: GameSource.twic,
            pgn: broadcastPgn,
          ),
        );

        // TWIC tourSlug/roundSlug are display labels, not slugs — no query.
        expect(url, 'https://chessever.com/games/xYz45678');
      },
    );

    test('derives a link from a rebranded direct game URL for gamebase', () {
      const rebrandedPgn = '''
[Event "Some Event"]
[Site "https://chessever.com/aBcDeF12"]
[White "White"]
[Black "Black"]
[Result "1/2-1/2"]

*
''';
      final url = buildGameShareUrl(
        game: _game(
          gameId: 'gamebase-1',
          source: GameSource.gamebase,
          pgn: rebrandedPgn,
        ),
      );

      expect(url, 'https://chessever.com/games/aBcDeF12');
    });

    test(
      'falls back to a gamebase deep link for TWIC games whose Site has no '
      'game id',
      () {
        const roundOnlyPgn = '''
[Event "Norway Chess 2026"]
[Site "https://lichess.org/broadcast/norway-chess-2026/round-6/AbCd1234"]
[White "White"]
[Black "Black"]
[Result "1-0"]

*
''';
        expect(
          buildGameShareUrl(
            game: _game(source: GameSource.twic, pgn: roundOnlyPgn),
          ),
          'https://chessever.com/games/$_canonicalGameId?src=gamebase',
        );
      },
    );

    test(
      'falls back to a gamebase deep link for TWIC/gamebase games with a '
      'plain-text Site',
      () {
        const chessComPgn = '''
[Event "Titled Tuesday"]
[Site "chess.com INT"]
[White "White"]
[Black "Black"]
[Result "1-0"]

*
''';
        for (final source in [GameSource.twic, GameSource.gamebase]) {
          expect(
            buildGameShareUrl(game: _game(source: source, pgn: chessComPgn)),
            'https://chessever.com/games/$_canonicalGameId?src=gamebase',
          );
        }
      },
    );

    test('prefers the Lichess game id over the gamebase uuid', () {
      const broadcastPgn = '''
[Event "Norway Chess 2026"]
[Site "https://lichess.org/broadcast/norway-chess-2026/round-6/AbCd1234/xYz45678"]
[White "White"]
[Black "Black"]
[Result "1-0"]

*
''';
      expect(
        buildGameShareUrl(
          game: _game(source: GameSource.twic, pgn: broadcastPgn),
        ),
        'https://chessever.com/games/xYz45678',
      );
    });

    test('returns null for TWIC games with no Lichess id and a non-uuid game '
        'id', () {
      expect(
        buildGameShareUrl(
          game: _game(gameId: 'twic-1', source: GameSource.twic),
        ),
        isNull,
      );
    });

    test(
      'returns null for non-canonical sources and unresolved saved analyses',
      () {
        expect(
          buildGameShareUrl(
            game: _game(gameId: 'gamebase-1', source: GameSource.gamebase),
          ),
          isNull,
        );
        expect(
          buildGameShareUrl(
            game: _game(gameId: 'twic-1', source: GameSource.twic),
          ),
          isNull,
        );
        expect(
          buildGameShareUrl(
            game: _game(
              gameId: 'explorer_123',
              source: GameSource.openingExplorer,
            ),
          ),
          isNull,
        );
        expect(
          buildGameShareUrl(
            game: _game(gameId: 'editor_123', source: GameSource.boardEditor),
          ),
          isNull,
        );
        expect(
          buildGameShareUrl(
            game: _game(gameId: 'local_123', source: GameSource.localAnalysis),
          ),
          isNull,
        );
        expect(
          buildGameShareUrl(
            game: _game(
              gameId: 'saved_analysis_1',
              source: GameSource.savedAnalysis,
            ),
            savedAnalysisData: _savedAnalysisData(sourceGameId: 'gamebase-1'),
          ),
          isNull,
        );
      },
    );
  });

  group('resolveGameSharePgn', () {
    test('prefers the parsed analysis game and skips remote fetches', () async {
      var supabaseCalls = 0;
      var gamebaseCalls = 0;

      final resolved = await resolveGameSharePgn(
        game: _game(pgn: _headerOnlyPgn),
        analysisGame: ChessGame.fromPgn('analysis', _fullPgn),
        savedAnalysisData: null,
        fetchSupabasePgn: (_) async {
          supabaseCalls++;
          return _fullPgn;
        },
        fetchGamebasePgn: (_) async {
          gamebaseCalls++;
          return _fullPgn;
        },
      );

      expect(resolved, contains('1. e4 e5'));
      expect(supabaseCalls, 0);
      expect(gamebaseCalls, 0);
    });

    test(
      'keeps local widget PGN for early share when it already has moves',
      () async {
        final resolved = await resolveGameSharePgn(
          game: _game(
            gameId: 'explorer_1',
            source: GameSource.openingExplorer,
            pgn: _fullPgn,
          ),
          analysisGame: null,
          savedAnalysisData: null,
        );

        expect(resolved, contains('1. e4 e5'));
      },
    );

    test('upgrades a header-only canonical PGN via Supabase fetch', () async {
      final resolved = await resolveGameSharePgn(
        game: _game(pgn: _headerOnlyPgn),
        analysisGame: null,
        savedAnalysisData: null,
        fetchSupabasePgn: (_) async => _fullPgn,
      );

      expect(resolved, contains('1. e4 e5'));
    });

    test(
      'falls back to saved analysis PGN before header-only fallback',
      () async {
        final resolved = await resolveGameSharePgn(
          game: _game(
            gameId: 'saved_analysis_1',
            source: GameSource.savedAnalysis,
            pgn: _headerOnlyPgn,
          ),
          analysisGame: null,
          savedAnalysisData: _savedAnalysisData(sourceGameId: _canonicalGameId),
        );

        expect(resolved, contains('1. e4 e5'));
      },
    );

    test('upgrades a header-only Gamebase PGN via Gamebase fetch', () async {
      final resolved = await resolveGameSharePgn(
        game: _game(
          gameId: 'gamebase-1',
          source: GameSource.gamebase,
          pgn: _headerOnlyPgn,
        ),
        analysisGame: null,
        savedAnalysisData: null,
        fetchGamebasePgn: (_) async => _fullPgn,
      );

      expect(resolved, contains('1. e4 e5'));
    });
  });

  group('mergeGameReportAnnotationsForGif', () {
    test('uses Game Analysis evals instead of older PGN evals', () {
      final game = ChessGame.fromPgn(
        'gif-evals',
        r'1. e4 {[%eval 0.15]} e5 2. Nf3 Nc6 *',
      );
      final report = GameAnalysisReport(
        fingerprint: gameReportFingerprint(game),
        positions: const [],
        moves: const [
          GameReportMove(
            ply: 1,
            san: 'e4',
            uci: 'e2e4',
            isWhite: true,
            classification: GameMoveClassification.brilliant,
            evaluation: GameReportLine(
              moves: ['e2e4'],
              depth: 18,
              centipawns: 42,
            ),
          ),
          GameReportMove(
            ply: 2,
            san: 'e5',
            uci: 'e7e5',
            isWhite: false,
            classification: GameMoveClassification.inaccuracy,
            evaluation: GameReportLine(
              moves: ['e7e5'],
              depth: 18,
              centipawns: -31,
            ),
          ),
          GameReportMove(
            ply: 3,
            san: 'Nf3',
            uci: 'g1f3',
            isWhite: true,
            classification: GameMoveClassification.missedWin,
            evaluation: GameReportLine(moves: ['g1f3'], depth: 18, mate: 3),
          ),
          GameReportMove(
            ply: 4,
            san: 'Nc6',
            uci: 'b8c6',
            isWhite: false,
            classification: GameMoveClassification.bookMove,
            evaluation: GameReportLine(
              moves: ['b8c6'],
              depth: 18,
              centipawns: 18,
            ),
          ),
        ],
        whiteAccuracy: 90,
        blackAccuracy: 80,
        generatedAt: DateTime.utc(2026, 7, 29),
      );

      final merged = mergeGameReportAnnotationsForGif(game, report);
      final pgn = exportGameToPgn(merged);

      expect(merged.mainline[0].eval, '0.42');
      expect(merged.mainline[1].eval, '-0.31');
      expect(merged.mainline[2].eval, '#3');
      expect(pgn, contains('[%eval 0.42]'));
      expect(pgn, isNot(contains('[%eval 0.15]')));
      expect(pgn, contains('[%eval -0.31]'));
      expect(pgn, contains('[%eval #3]'));
      expect(pgn, contains('[%chessever_annotation brilliant]'));
      expect(pgn, contains('[%chessever_annotation inaccuracy]'));
      expect(pgn, contains('[%chessever_annotation missed_win]'));
      expect(pgn, contains('[%chessever_annotation book_move]'));
    });

    test('ignores a report for a different game', () {
      final game = ChessGame.fromPgn('gif-evals', '1. e4 e5 *');
      final report = GameAnalysisReport(
        fingerprint: 'different-game',
        positions: const [],
        moves: const [
          GameReportMove(
            ply: 1,
            san: 'e4',
            uci: 'e2e4',
            isWhite: true,
            classification: GameMoveClassification.bestMove,
            evaluation: GameReportLine(
              moves: ['e2e4'],
              depth: 18,
              centipawns: 25,
            ),
          ),
        ],
        whiteAccuracy: 90,
        blackAccuracy: 80,
        generatedAt: DateTime.utc(2026, 7, 29),
      );

      expect(mergeGameReportAnnotationsForGif(game, report), same(game));
    });
  });

  group('buildGameShareSnapshot', () {
    test('parses the PGN when the board state is still loading', () {
      final game = _game(
        gameId: 'explorer_1',
        source: GameSource.openingExplorer,
        pgn: _fullPgn,
      );
      final state = ChessBoardStateNew(
        game: game,
        pgnData: null,
        isLoadingMoves: true,
      );

      final snapshot = buildGameShareSnapshot(
        game: game,
        pgn: _fullPgn,
        state: state,
      );

      expect(snapshot.moveSans, isNotEmpty);
      expect(snapshot.currentMoveIndex, snapshot.moveSans.length - 1);
      expect(snapshot.positionFen, isNotEmpty);
    });

    test(
      'resolved PGN stays complete when the snapshot is focused mid-game',
      () async {
        // Board is ready but the user navigated back to move 2: the analysis
        // state's moveSans is truncated to the path-to-current ply, while the
        // game tree still holds the full mainline.
        final game = _game(gameId: 'live_1', source: GameSource.supabase);
        final fullGame = ChessGame.fromPgn('analysis', _fullPgn);
        final state = ChessBoardStateNew(
          game: game,
          pgnData: null,
          isLoadingMoves: false,
          analysisState: AnalysisBoardState(
            game: fullGame,
            moveSans: const ['e4', 'e5'], // truncated to focused move 2
            currentMoveIndex: 1,
          ),
        );

        final resolvedPgn = await resolveGameSharePgn(
          game: game,
          analysisGame: fullGame,
          savedAnalysisData: null,
        );
        final snapshot = buildGameShareSnapshot(
          game: game,
          pgn: resolvedPgn,
          state: state,
        );

        // Share Image stays at the focused position.
        expect(snapshot.moveSans, const ['e4', 'e5']);
        expect(snapshot.currentMoveIndex, 1);
        // Cloud GIF receives all four plies from the resolved PGN.
        expect(resolvedPgn, contains('1. e4 e5 2. Nf3 Nc6'));
      },
    );
  });
}
