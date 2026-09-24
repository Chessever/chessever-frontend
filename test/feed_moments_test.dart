import 'package:chessever2/screens/chessboard/classification_fx/move_class.dart';
import 'package:chessever2/screens/feed/logic/feed_exploration.dart';
import 'package:chessever2/screens/feed/logic/feed_moments.dart';
import 'package:chessever2/screens/feed/logic/feed_pgn.dart';
import 'package:chessever2/screens/feed/models/feed_models.dart';
import 'package:chessever2/screens/feed/logic/feed_codec.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter_test/flutter_test.dart';

/// Morphy vs Duke Karl / Count Isouard, Paris 1858 — the Opera Game.
const _operaGame = '''
[Event "Paris"]
[Site "Paris FRA"]
[Date "1858.??.??"]
[White "Paul Morphy"]
[Black "Duke Karl / Count Isouard"]
[Result "1-0"]

1. e4 e5 2. Nf3 d6 3. d4 Bg4 4. dxe5 Bxf3 5. Qxf3 dxe5 6. Bc4 Nf6 7. Qb3 Qe7
8. Nc3 c6 9. Bg5 b5 10. Nxb5 cxb5 11. Bxb5+ Nbd7 12. O-O-O Rd8 13. Rxd7 Rxd7
14. Rd1 Qe6 15. Bxd7+ Nxd7 16. Qb8+ Nxb8 17. Rd8# 1-0
''';

/// A prewarmed report export: every move carries `[%eval]`, and the report
/// wrote its classification block beside the standard glyph (`$242` best,
/// `$246` blunder). 2.Qh5 carries a big eval swing on purpose but no
/// classification — in a report game that swing must stay silent.
const _reportGame = '''
[Event "Feed fixture"]
[White "White"]
[Black "Black"]
[Result "1-0"]

1. e4 \$242 { [%eval 0.30] } 1... e5 \$242 { [%eval 0.25] }
2. Bc4 \$242 { [%eval 0.20] } 2... Nc6 \$242 { [%eval 0.20] }
3. Qh5 { [%eval -2.50] } 3... Nf6 \$4 \$246 { [%eval #1] }
4. Qxf7# \$242 1-0
''';

/// Same moves, evals only: verdicts must come from the lichess judgment.
const _evalOnlyGame = '''
[Event "Feed fixture"]
[Result "1-0"]

1. e4 { [%eval 0.30] } 1... e5 { [%eval 0.25] }
2. Bc4 { [%eval 0.20] } 2... Nc6 { [%eval 0.20] }
3. Qh5 { [%eval 0.10] } 3... Nf6 { [%eval #1] }
4. Qxf7# 1-0
''';

/// Standard glyph NAGs only, the way a hand-annotated PGN carries them.
const _glyphGame = '''
[Event "Feed fixture"]
[Result "*"]

1. e4 \$3 1... e5 \$6 2. Nf3 \$5 2... Nc6 \$1 3. Bb5 \$2 3... a6 \$4 *
''';

FeedMoment? _momentAt(List<FeedPly> plies, int ply) => plies[ply].moment;

void main() {
  group('parseFlowEval', () {
    test('reads centipawns, depth suffixes and mates', () {
      expect(parseFlowEval(['[%eval 0.35]']), (cp: 35, mate: null));
      expect(parseFlowEval(['[%clk 1:00:00] [%eval -1.20,24]']), (
        cp: -120,
        mate: null,
      ));
      expect(parseFlowEval(['[%eval #-3]']), (cp: null, mate: -3));
      expect(parseFlowEval(['[%eval +2]']), (cp: 200, mate: null));
      expect(parseFlowEval(['no eval here']), (cp: null, mate: null));
    });
  });

  group('Opera Game (Morphy 1858)', () {
    late FeedClip clip;

    setUpAll(() {
      clip = feedClipFromPgn(_operaGame)!;
    });

    test('parses the whole mainline with the start position at index 0', () {
      expect(clip.plyCount, 33);
      expect(clip.plies.first.san, isNull);
      expect(clip.plies[33].san, 'Rd8#');
      expect(clip.result, '1-0');
      expect(clip.hasEvals, isFalse);
    });

    test('16.Qb8+ is a queen sacrifice and 17.Rd8# is mate', () {
      final sac = _momentAt(clip.plies, 31)!;
      expect(clip.plies[31].san, 'Qb8+');
      expect(sac.type, FeedMomentType.sacrifice);
      expect(sac.label, 'Queen sacrifice');
      expect(sac.isHeadline, isTrue);

      final mate = _momentAt(clip.plies, 33)!;
      expect(mate.type, FeedMomentType.checkmate);
      expect(mate.severity, 3);
    });

    test('exchanges and recaptures are not sacrifices', () {
      // 10.Nxb5 cxb5 11.Bxb5+ nets -1; 13.Rxd7 Rxd7 nets -2.
      expect(_momentAt(clip.plies, 19)?.type, isNot(FeedMomentType.sacrifice));
      expect(_momentAt(clip.plies, 25)?.type, isNot(FeedMomentType.sacrifice));
      expect(_momentAt(clip.plies, 26)?.label, 'Recapture');
    });

    test('checks and castling are subtle beats', () {
      expect(_momentAt(clip.plies, 21)?.type, FeedMomentType.check);
      expect(_momentAt(clip.plies, 21)?.severity, 1);
      expect(_momentAt(clip.plies, 23)?.type, FeedMomentType.castle);
      expect(_momentAt(clip.plies, 23)?.label, 'Castles long');
    });

    test('headlines are the sacrifice and the mate, in ply order', () {
      expect(clip.headlines, [
        FeedMomentType.sacrifice,
        FeedMomentType.checkmate,
      ]);
      expect(clip.hasBrilliance, isTrue);
    });
  });

  group('prewarmed report PGN', () {
    late FeedClip clip;

    setUpAll(() {
      clip = feedClipFromPgn(_reportGame)!;
    });

    test('carries evals through to the plies', () {
      expect(clip.hasEvals, isTrue);
      expect(clip.plies[1].cp, 30);
      expect(clip.plies[6].mate, 1);
      expect(clip.plies[7].cp, isNull);
    });

    test(r'$246 is a blunder headline, $242 best moves stay silent', () {
      final blunder = _momentAt(clip.plies, 6)!;
      expect(blunder.type, FeedMomentType.blunder);
      expect(blunder.severity, 3);
      expect(_momentAt(clip.plies, 1), isNull);
      expect(_momentAt(clip.plies, 3), isNull);
    });

    test('the report owns verdicts: an unclassified eval swing is silent', () {
      // 3.Qh5 drops from +0.20 to -2.50 but the report left it unlabelled.
      expect(_momentAt(clip.plies, 5), isNull);
    });

    test('the final mate outranks game end', () {
      expect(_momentAt(clip.plies, 7)!.type, FeedMomentType.checkmate);
    });
  });

  group('eval-only PGN', () {
    test('judges the eval swing with the lichess table', () {
      final clip = feedClipFromPgn(_evalOnlyGame)!;
      // 3...Nf6 walks into mate from an equal position: MateSequence.created.
      final blunder = _momentAt(clip.plies, 6)!;
      expect(blunder.type, FeedMomentType.blunder);
      expect(_momentAt(clip.plies, 5), isNull);
    });

    test('throwing away a winning eval without losing is a missed win', () {
      const pgn = '''
[FEN "6k1/5ppp/8/8/8/8/5PPP/3R2K1 w - - 0 1"]
[Result "1/2-1/2"]

1. Rd7 { [%eval 5.00] } 1... Kf8 { [%eval 5.10] }
2. Kf1 { [%eval 0.10] } 2... Ke8 { [%eval 0.10] } 1/2-1/2
''';
      final clip = feedClipFromPgn(pgn)!;
      final missed = _momentAt(clip.plies, 3)!;
      expect(missed.type, FeedMomentType.missedWin);
      expect(missed.severity, 2);
      expect(_momentAt(clip.plies, 4)!.type, FeedMomentType.gameEnd);
      expect(_momentAt(clip.plies, 4)!.label, 'Draw');
    });
  });

  group('guards', () {
    test('a hung queen in a lost game is not a sacrifice', () {
      const pgn = '''
[Result "0-1"]

1. e4 e5 2. Qh5 Nc6 3. Qxe5+ Nxe5 0-1
''';
      final clip = feedClipFromPgn(pgn)!;
      expect(
        clip.plies.map((ply) => ply.moment?.type),
        isNot(contains(FeedMomentType.sacrifice)),
      );
      // Resignation after a quiet capture: the last ply carries the result.
      final end = _momentAt(clip.plies, 6)!;
      expect(end.type, FeedMomentType.gameEnd);
      expect(end.label, 'Black wins');
    });

    test('at most three headlines per game; the rest are demoted', () {
      const pgn = r'''
[Result "1-0"]

1. e4 $240 e5 $246 2. Nf3 $240 Nc6 $246 3. Bb5 $240 a6 $246 4. Ba4 Nf6 1-0
''';
      final clip = feedClipFromPgn(pgn)!;
      final headline = clip.plies.where(
        (ply) => ply.moment?.isHeadline ?? false,
      );
      expect(headline, hasLength(kFlowMaxHeadlines));
      // Brilliancies outrank blunders for the kept slots.
      expect(
        headline.map((ply) => ply.moment!.type),
        everyElement(FeedMomentType.brilliant),
      );
      // Demoted blunders still caption at severity 2.
      expect(_momentAt(clip.plies, 2)!.type, FeedMomentType.blunder);
      expect(_momentAt(clip.plies, 2)!.severity, 2);
    });

    test('garbage and empty PGNs yield no clip', () {
      expect(feedClipFromPgn(''), isNull);
      expect(feedClipFromPgn('[Event "x"]\n\n*'), isNull);
    });

    test('an illegal tail keeps the playable prefix', () {
      final clip = feedClipFromPgn('1. e4 e5 2. Ke2 Qxz9 *')!;
      expect(clip.plyCount, 3);
      expect(clip.result, isNull);
    });
  });

  group('first-page cache codec', () {
    FeedItem item({required String reason, DateTime? day}) {
      final clip = feedClipFromPgn(_operaGame)!;
      return FeedItem(
        game: GamesTourModel(
          gameId: 'opera-1858',
          whitePlayer: PlayerCard(
            name: 'Morphy, Paul',
            federation: 'USA',
            title: '',
            rating: 2690,
            countryCode: 'USA',
            team: null,
            fideId: 1,
          ),
          blackPlayer: PlayerCard(
            name: 'Duke Karl',
            federation: 'GER',
            title: '',
            rating: 0,
            countryCode: 'GER',
            team: null,
          ),
          whiteTimeDisplay: '--:--',
          blackTimeDisplay: '--:--',
          whiteClockCentiseconds: 0,
          blackClockCentiseconds: 0,
          gameStatus: GameStatus.whiteWins,
          roundId: 'r1',
          tourId: 't1',
          tourSlug: 'paris-1858',
          pgn: _operaGame,
          boardNr: 1,
          gameDay: day,
        ),
        plies: clip.plies,
        reason: reason,
        eventLabel: 'Paris',
        result: '1-0',
      );
    }

    test('round-trips plies, moments and the game', () {
      final now = DateTime(2026, 9, 22, 12);
      final original = item(reason: 'Because you follow Paul Morphy');
      final decoded = decodeFlowFeedCache(
        encodeFlowFeedCache([original]),
        now: now,
      ).single;

      expect(decoded.game.gameId, 'opera-1858');
      expect(decoded.game.whitePlayer.name, 'Morphy, Paul');
      expect(decoded.game.whitePlayer.fideId, 1);
      expect(decoded.game.gameStatus, GameStatus.whiteWins);
      expect(decoded.game.pgn, _operaGame);
      expect(decoded.reason, original.reason);
      expect(decoded.result, '1-0');
      expect(decoded.plyCount, 33);
      for (var i = 0; i < original.plies.length; i++) {
        expect(decoded.plies[i].fen, original.plies[i].fen);
        expect(decoded.plies[i].san, original.plies[i].san);
        expect(decoded.plies[i].moment?.type, original.plies[i].moment?.type);
        expect(
          decoded.plies[i].moment?.severity,
          original.plies[i].moment?.severity,
        );
      }
    });

    test('recomputes day-relative captions on read', () {
      final decoded = decodeFlowFeedCache(
        encodeFlowFeedCache([
          item(reason: 'Top board today', day: DateTime(2026, 9, 20)),
        ]),
        now: DateTime(2026, 9, 22, 12),
      ).single;
      // The Opera game ends in mate, which outranks the board caption.
      expect(decoded.reason, 'Brilliant finish');
    });

    test('garbage yields an empty page', () {
      expect(decodeFlowFeedCache('not json', now: DateTime.now()), isEmpty);
      expect(decodeFlowFeedCache('{"v":99}', now: DateTime.now()), isEmpty);
    });
  });

  group('move classes', () {
    test('a report verdict wins over the glyph beside it', () {
      final plies = feedClipFromPgn(_reportGame)!.plies;
      expect(plies[1].moveClass, MoveClass.best); // 1. e4 \$242
      expect(plies[6].moveClass, MoveClass.blunder); // 3... Nf6 \$4 \$246
      // 3. Qh5 carries no verdict; the report owns the game, so no class.
      expect(plies[5].moveClass, isNull);
      expect(plies[5].effectiveClass, isNull);
    });

    test('standard glyph NAGs map to their classes', () {
      final plies = feedClipFromPgn(_glyphGame)!.plies;
      expect(
        [for (final ply in plies.skip(1)) ply.moveClass],
        [
          MoveClass.brilliant,
          MoveClass.inaccuracy,
          MoveClass.interesting,
          MoveClass.great,
          MoveClass.mistake,
          MoveClass.blunder,
        ],
      );
    });

    test('an eval-swing verdict classifies the move for sound and badge', () {
      final plies = feedClipFromPgn(_evalOnlyGame)!.plies;
      // 3... Nf6 allows mate in one: no NAG, but Feed calls it a blunder.
      expect(plies[6].moveClass, isNull);
      expect(plies[6].moment?.type, FeedMomentType.blunder);
      expect(plies[6].effectiveClass, MoveClass.blunder);
      // Mate is a board event, not a verdict: ordinary sound.
      expect(plies[7].effectiveClass, isNull);
    });

    test('the cache keeps every class and drops v1 pages', () {
      final clip = feedClipFromPgn(_reportGame)!;
      final item = FeedItem(
        game: GamesTourModel(
          gameId: 'report-fixture',
          whitePlayer: PlayerCard(
            name: 'White',
            federation: '',
            title: '',
            rating: 0,
            countryCode: '',
            team: null,
          ),
          blackPlayer: PlayerCard(
            name: 'Black',
            federation: '',
            title: '',
            rating: 0,
            countryCode: '',
            team: null,
          ),
          whiteTimeDisplay: '--:--',
          blackTimeDisplay: '--:--',
          whiteClockCentiseconds: 0,
          blackClockCentiseconds: 0,
          gameStatus: GameStatus.whiteWins,
          roundId: 'r1',
          tourId: 't1',
        ),
        plies: clip.plies,
        reason: 'Brilliant finish',
        result: '1-0',
      );
      final decoded = decodeFlowFeedCache(
        encodeFlowFeedCache([item]),
        now: DateTime(2026, 9, 23),
      ).single;
      for (var i = 0; i < clip.plies.length; i++) {
        expect(decoded.plies[i].moveClass, clip.plies[i].moveClass);
      }
      expect(
        decodeFlowFeedCache('{"v":1,"items":[]}', now: DateTime.now()),
        isEmpty,
      );
    });
  });

  group('FeedExploration', () {
    Position start() => Chess.initial;

    test('plays legal moves with SAN and numbering', () {
      var line = FeedExploration(forkPly: 0, start: start());
      final (afterE4, e4) = line.play(Move.parse('e2e4')!)!;
      line = afterE4;
      final (afterE5, e5) = line.play(Move.parse('e7e5')!)!;
      line = afterE5;
      expect(e4.san, 'e4');
      expect(e5.san, 'e5');
      expect(line.cursor, 1);
      expect(line.numberAt(0), '1.');
      expect(line.numberAt(1), isNull);
      expect(line.labelAt(1), '1... e5');
      expect(line.play(Move.parse('e4e5')!), isNull); // blocked pawn
    });

    test("castling by the king's two-square move is stored king-to-rook", () {
      final position = Chess.fromSetup(
        Setup.parseFen('r3k2r/pppppppp/8/8/8/8/PPPPPPPP/R3K2R w KQkq - 0 1'),
      );
      final line = FeedExploration(forkPly: 4, start: position);
      final (_, castle) = line.play(Move.parse('e1g1')!)!;
      expect(castle.san, 'O-O');
      expect(castle.move.uci, 'e1h1');
    });

    test('playing from an earlier move replaces what came after', () {
      var line = FeedExploration(forkPly: 0, start: start());
      line = line.play(Move.parse('e2e4')!)!.$1;
      line = line.play(Move.parse('e7e5')!)!.$1;
      line = line.jumpTo(0);
      line = line.play(Move.parse('c7c5')!)!.$1;
      expect([for (final m in line.moves) m.san], ['e4', 'c5']);
      expect(line.numberAt(0), '1.');
      final blackFirst = FeedExploration(
        forkPly: 1,
        start: Chess.initial.play(Move.parse('e2e4')!),
      );
      final (_, reply) = blackFirst.play(Move.parse('c7c5')!)!;
      expect(reply.san, 'c5');
      expect(blackFirst.play(Move.parse('c7c5')!)!.$1.numberAt(0), '1...');
    });
  });
}
