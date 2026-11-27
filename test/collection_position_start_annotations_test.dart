// Trello #1460: a collection can share a position, or half a game, instead of
// a whole game. The PGN then starts from `[FEN]` at, say, move 92, and the
// annotator explains the position before the first move. Every comment of
// such a game must reach the reader, on the board and in Stories / Feed.
import 'package:chessever2/screens/chessboard/analysis/chess_game.dart';
import 'package:chessever2/screens/chessboard/analysis/chess_game_navigator.dart';
import 'package:chessever2/screens/chessboard/notation/notation_token_builder.dart';
import 'package:chessever2/screens/chessboard/notation/notation_tree.dart';
import 'package:chessever2/screens/feed/logic/feed_moments.dart';
import 'package:chessever2/screens/feed/logic/feed_pgn.dart';
import 'package:chessever2/screens/feed/models/feed_models.dart';
import 'package:chessever2/screens/feed/widgets/feed_format.dart';
import 'package:chessever2/screens/stories/story_models.dart';
import 'package:chessever2/screens/stories/story_moments.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessground/chessground.dart' show Arrow;
import 'package:dartchess/dartchess.dart';
import 'package:flutter_test/flutter_test.dart';

const _fen = '8/5pk1/6p1/3R4/7P/6P1/5PK1/1r6 b - - 3 92';

/// A ChessBase-style fragment: Black to move at 92, the position explained
/// before the first move, an alternative to that first move, a variation
/// that opens with its own lead-in, a glyph and an arrow.
const _fragment =
    '''
[Event "U.S. Championship 2026"]
[White "So, Wesley"]
[Black "Caruana, Fabiano"]
[Result "1/2-1/2"]
[Annotator "GM Vasif Durarbayli"]
[SetUp "1"]
[FEN "$_fen"]

{ The game has reached a rook endgame after 91.Kg2. [%cal Gb1b2] }
92... Rb2 { The rook goes behind. } ( 92... Kf6 { Too slow. } 93. Rd7 )
93. Rd7 \$1 { Activating at once. } ( { Instead } 93. h5 gxh5 { and Black is fine. } )
93... Kf6 94. Rd6+ { A useful check. } 94... Kg7 { [%cal Gd6d7] Back again. }
95. Rd7 Kf6 { Repetition. } 96. Rd6+ 1/2-1/2
''';

const _intro = 'The game has reached a rook endgame after 91.Kg2.';

List<NotationDisplayToken> _tokens(ChessGame game) {
  final tree = NotationTreeBuilder.build(game);
  return buildNotationTokens(
    tree.mainline,
    depth: 0,
    startingPly: tree.startingPly,
    pointerMap: <String, NotationMoveNode>{},
    forcedOpenIds: const {},
    variationComments: const {},
    lichessAnnotations: const {},
    collapsedVariationIds: const {},
    expandedVariationIds: const {},
    rootComments: tree.rootComments,
  );
}

void main() {
  group('board model', () {
    test('keeps the intro, the lead-in and the alternative to move 92', () {
      final game = ChessGame.fromPgn('fragment', _fragment);

      expect(game.startingFen, _fen);
      expect(game.rootComments.single, contains(_intro));
      expect(game.mainline.first.san, 'Rb2');
      expect(game.mainline.first.num, 92);

      final firstBranches = game.mainline.first.variations!;
      final alternative = firstBranches.singleWhere(
        (line) => isAlternativeToMove(game.mainline.first, line),
      );
      expect(alternative.map((m) => m.san), ['Kf6', 'Rd7']);
      expect(alternative.first.comments, ['Too slow.']);

      final leadIn = firstBranches.singleWhere(
        (line) => !isAlternativeToMove(game.mainline.first, line),
      );
      expect(leadIn.first.san, 'h5');
      expect(leadIn.first.startingComments, ['Instead']);
      expect(leadIn.last.comments, ['and Black is fine.']);
    });

    test('a full game from move 1 keeps its intro too', () {
      final game = ChessGame.fromPgn(
        'full',
        '{ Intro } 1. e4 e5 ( { Alt } 1... c5 ) 2. Nf3 *',
      );
      expect(game.rootComments, ['Intro']);
      expect(game.mainline.first.variations!.single.first.startingComments, [
        'Alt',
      ]);
    });

    test('saved JSON keeps both, under the desktop keys', () {
      final game = ChessGame.fromPgn('fragment', _fragment);
      final json = game.toJson();
      expect(json['rc'], game.rootComments);

      final restored = ChessGame.fromJson(json);
      expect(restored.rootComments, game.rootComments);
      final leadIn = restored.mainline.first.variations!.firstWhere(
        (line) => line.first.san == 'h5',
      );
      expect(leadIn.first.startingComments, ['Instead']);
      // A game with neither writes no extra keys.
      expect(ChessGame.fromPgn('x', '1. e4 e5 *').toJson().containsKey('rc'),
          isFalse);
    });

    test('PGN export round-trips every comment and stays legal', () {
      final game = ChessGame.fromPgn('fragment', _fragment);
      final pgn = exportGameToPgn(game);

      final reparsed = PgnGame.parsePgn(pgn);
      expect(reparsed.comments.single, contains(_intro));
      // The alternative to 92...Rb2 is its sibling, playable from the FEN.
      expect(
        reparsed.moves.children.map((n) => n.data.san),
        ['Rb2', 'Kf6'],
      );

      final again = ChessGame.fromPgn('fragment', pgn);
      expect(again.rootComments, game.rootComments);
      expect(notationGameSignature(again), notationGameSignature(game));
      expect(
        _tokens(again).map((t) => '${t.type.name}:${t.text}').toList(),
        _tokens(game).map((t) => '${t.type.name}:${t.text}').toList(),
      );
    });
  });

  group('board navigator', () {
    test('playing the book alternative to move 92 enters the annotated line',
        () {
      final game = ChessGame.fromPgn('fragment', _fragment);
      final navigator = ChessGameNavigator(game)..goToHead();
      final before = game.mainline.first.variations!.length;

      navigator.makeOrGoToMove('g7f6'); // 92... Kf6

      final state = navigator.state;
      expect(state.game.mainline.first.variations, hasLength(before));
      expect(state.currentMove?.san, 'Kf6');
      expect(state.currentMove?.comments, ['Too slow.']);
    });

    test('promoting the alternative to move 92 swaps it with 92...Rb2', () {
      final game = ChessGame.fromPgn('fragment', _fragment);
      final index = game.mainline.first.variations!.indexWhere(
        (line) => isAlternativeToMove(game.mainline.first, line),
      );
      final navigator = ChessGameNavigator(game)
        ..promoteVariationToMainline([0, index, 0]);

      final promoted = navigator.state.game;
      expect(promoted.mainline.map((m) => m.san), ['Kf6', 'Rd7']);
      expect(navigator.state.movePointer, [0]);
      final demoted = promoted.mainline.first.variations!.singleWhere(
        (line) => line.first.san == 'Rb2',
      );
      expect(isAlternativeToMove(promoted.mainline.first, demoted), isTrue);
      expect(demoted.first.comments, ['The rook goes behind.']);
      // Rb2 keeps its own branch (the lead-in line replacing 93.Rd7).
      expect(
        demoted.first.variations!.single.first.startingComments,
        ['Instead'],
      );

      // The saved/shared PGN stays legal and keeps every line.
      final again = ChessGame.fromPgn('again', exportGameToPgn(promoted));
      expect(notationGameSignature(again), notationGameSignature(promoted));
      expect(again.rootComments, game.rootComments);
    });
  });

  group('board notation', () {
    test('reads intro, numbered first move, alternative and lead-in in order',
        () {
      final game = ChessGame.fromPgn('fragment', _fragment);
      final tokens = _tokens(game);
      final read = [
        for (final t in tokens)
          if (t.type == NotationTokenType.move ||
              t.type == NotationTokenType.comment ||
              t.type == NotationTokenType.openParen)
            t.type == NotationTokenType.openParen ? '(' : t.text,
      ];

      expect(read.take(8), [
        _intro, // the [%cal] command is drawn, not printed
        '92... Rb2',
        'The rook goes behind.',
        '(',
        'Kf6', // its header names the move it replaces
        'Too slow.',
        '93. Rd7',
        '93. Rd7',
      ]);
      expect(read.skip(8).take(5), [
        'Activating at once.',
        '(',
        'Instead',
        '93. h5',
        'gxh5',
      ]);
      for (final text in [
        'and Black is fine.',
        'A useful check.',
        'Back again.',
        'Repetition.',
      ]) {
        expect(read.where((r) => r == text), hasLength(1), reason: text);
      }

      // Text written before a move is shown as the source wrote it.
      final intro = tokens.first;
      expect(intro.commentId, isNotNull);
      expect(intro.editable, isFalse);
      expect(
        tokens.firstWhere((t) => t.text == 'Instead').editable,
        isFalse,
      );
      expect(
        tokens.firstWhere((t) => t.text == 'The rook goes behind.').editable,
        isTrue,
      );
    });

    test('the alternative to the first move sits on its own move', () {
      final game = ChessGame.fromPgn('fragment', _fragment);
      final tree = NotationTreeBuilder.build(game);
      final pointerMap = <String, NotationMoveNode>{};
      buildNotationTokens(
        tree.mainline,
        depth: 0,
        startingPly: tree.startingPly,
        pointerMap: pointerMap,
        forcedOpenIds: const {},
        variationComments: const {},
        lichessAnnotations: const {},
        collapsedVariationIds: const {},
        expandedVariationIds: const {},
      );
      final alternative = tree.mainline.first.variations.singleWhere(
        (v) => v.replacesParent,
      );
      final head = alternative.moves.first;
      expect(head.moveNumber, 92);
      expect(head.isWhiteMove, isFalse);
      expect(variationAlternativeToText(alternative, pointerMap),
          'Alt to 92...Rb2');

      final continuation = tree.mainline.first.variations.singleWhere(
        (v) => !v.replacesParent,
      );
      expect(continuation.moves.first.moveNumber, 93);
      expect(variationAlternativeToText(continuation, pointerMap),
          'Alt to 93.Rd7');
    });

    test('raw PGN mode still hides prose', () {
      final game = ChessGame.fromPgn('fragment', _fragment);
      final tree = NotationTreeBuilder.build(game);
      final tokens = buildNotationTokens(
        tree.mainline,
        depth: 0,
        startingPly: tree.startingPly,
        pointerMap: <String, NotationMoveNode>{},
        forcedOpenIds: const {},
        variationComments: const {},
        lichessAnnotations: const {},
        collapsedVariationIds: const {},
        expandedVariationIds: const {},
        rawPgnMode: true,
        rootComments: tree.rootComments,
      );
      expect(tokens.where((t) => t.type == NotationTokenType.comment), isEmpty);
    });

    test('a White-to-move start keeps its numbering', () {
      final game = ChessGame.fromPgn(
        'white',
        '[FEN "8/5pk1/6p1/3R4/7P/6P1/1r3PK1/8 w - - 4 93"]\n\n'
            '{ White to move. } 93. Rd7 { first } 93... Kf6 *',
      );
      final read = [
        for (final t in _tokens(game))
          if (t.type != NotationTokenType.lichessComment) t.text,
      ];
      expect(read, ['White to move.', '93. Rd7', 'first', 'Kf6']);
    });
  });

  group('Stories and Feed', () {
    test('the first story stop reads the intro with move 92', () {
      final story = parseStoryPgn(_fragment)!;
      expect(story.game.comments.single, contains(_intro));

      final segments = completeCollectionStory(
        story,
        pickStorySegments(story),
      );
      final first = segments.first;
      expect(first.ply, 1);
      expect(first.number, '92…');
      expect(first.comment, startsWith(_intro));
      expect(first.comment, contains('The rook goes behind.'));
      // The intro's arrow marks the start position; the stop shows the
      // board after 92...Rb2, so it is not drawn there.
      expect(first.shapes.whereType<Arrow>(), isEmpty);
    });

    test('an inspected first move reads the intro too', () {
      final analysis = analyzeStoryJobs([
        StoryAnalysisJob(id: 'fragment', pgn: _fragment, plies: const [1]),
      ])['fragment']!;
      expect(analysis.segments.single.comment, startsWith(_intro));

      final later = analyzeStoryJobs([
        StoryAnalysisJob(id: 'fragment', pgn: _fragment, plies: const [2]),
      ])['fragment']!;
      expect(later.segments.single.comment, isNot(contains(_intro)));
    });

    test('the move counter pairs a Black-first start correctly', () {
      final game = parseFlowPgn(_fragment)!;
      final item = FeedItem(
        game: GamesTourModel(
          gameId: 'fragment',
          whitePlayer: PlayerCard(
            name: 'So, Wesley',
            federation: 'USA',
            title: 'GM',
            rating: 0,
            countryCode: 'USA',
            team: null,
          ),
          blackPlayer: PlayerCard(
            name: 'Caruana, Fabiano',
            federation: 'USA',
            title: 'GM',
            rating: 0,
            countryCode: 'USA',
            team: null,
          ),
          whiteTimeDisplay: '--:--',
          blackTimeDisplay: '--:--',
          whiteClockCentiseconds: 0,
          blackClockCentiseconds: 0,
          gameStatus: GameStatus.draw,
          roundId: 'r',
          tourId: 't',
          pgn: _fragment,
        ),
        plies: buildFlowPlies(game),
        reason: 'test',
      );
      // 92...Rb2 93.Rd7 Kf6 94.Rd6+ Kg7 95.Rd7 Kf6 96.Rd6+
      expect(item.plyCount, 8);
      expect(feedMoveLabel(item, 1), '92... Rb2');
      expect(feedPlyText(item, 1), 'move 92 of 96');
      expect(feedPlyText(item, 2), 'move 93 of 96');
      expect(feedPlyText(item, 3), 'move 93 of 96');
      expect(feedPlyText(item, 8), 'move 96 of 96');
      expect(feedMoveCounter(item, 0), '0/5');
      expect(feedMoveCounter(item, 1), '1/5');
      expect(feedMoveCounter(item, 2), '2/5');
      expect(feedMoveCounter(item, 3), '2/5');
      expect(feedMoveCounter(item, 8), '5/5');
    });
  });
}
