import 'dart:io' as io;

import 'package:chessever2/screens/chessboard/classification_fx/classification_fx.dart';
import 'package:chessever2/screens/chessboard/classification_fx/classification_landing.dart'
    show ClassificationLandingPainter;
import 'package:chessever2/screens/chessboard/classification_fx/move_class.dart';
import 'package:chessever2/screens/chessboard/game_review/game_analysis_report.dart';
import 'package:chessever2/screens/feed/audio/feed_sfx.dart';
import 'package:chessever2/screens/feed/models/feed_models.dart';
import 'package:chessever2/screens/feed/widgets/feed_move_sound.dart';
import 'package:chessever2/screens/feed/widgets/feed_playback.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/utils/audio_player_service.dart';
import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Records what [ClassificationSfx] asked to play instead of playing it.
class _RecordingOutput implements ClassificationSfxOutput {
  final List<String> calls = [];

  @override
  void playOrdinary(SfxType type) => calls.add('ordinary:${type.name}');

  @override
  void playClassification(SfxType type, {SfxType? fallback}) =>
      calls.add('class:${type.name}/${fallback?.name}');

  @override
  Future<void> warmUp() async => calls.add('warmUp');
}

class _ThrowingOutput implements ClassificationSfxOutput {
  @override
  void playOrdinary(SfxType type) => throw StateError('engine gone');

  @override
  void playClassification(SfxType type, {SfxType? fallback}) =>
      throw StateError('engine gone');

  @override
  Future<void> warmUp() async => throw StateError('engine gone');
}

/// A fake SoLoud: voices are ints, and the clock is set by hand. It drives
/// [SfxPriorityGate] exactly the way [AudioPlayerService] does.
class _FakePlayer {
  _FakePlayer() {
    gate = SfxPriorityGate<int>(nowMicros: () => nowMs * 1000);
  }

  late final SfxPriorityGate<int> gate;
  int nowMs = 0;
  int _nextHandle = 1;
  final Map<int, String> voices = {};
  final Set<int> stopped = {};
  final List<String> skipped = [];
  final List<({int ticket, SfxType sound})> _waiting = [];
  final List<({int ticket, SfxType type})> _decoding = [];

  /// Sounding = started and not cut.
  List<String> get sounding => [
    for (final entry in voices.entries)
      if (!stopped.contains(entry.key)) entry.value,
  ];

  /// An ordinary sound; [waitOnInit] holds its start until [finishInit], as
  /// the real service does while the engine initialises.
  void ordinary(SfxType sound, {bool waitOnInit = false}) {
    final ticket = gate.requestOrdinary(sound);
    if (ticket == null) {
      skipped.add(sound.name);
      return;
    }
    if (waitOnInit) {
      _waiting.add((ticket: ticket, sound: sound));
      return;
    }
    _startOrdinary(ticket, sound);
  }

  void finishInit() {
    for (final pending in List.of(_waiting)) {
      _startOrdinary(pending.ticket, pending.sound);
    }
    _waiting.clear();
  }

  void _startOrdinary(int ticket, SfxType sound) {
    if (!gate.mayStartOrdinary(ticket, sound)) {
      skipped.add(sound.name);
      return;
    }
    final handle = _nextHandle++;
    voices[handle] = sound.name;
    gate.ordinaryStarted(handle, sound);
  }

  /// A classification sound for the move whose ordinary sound is [move];
  /// [waitOnDecode] holds its start until [finishDecode], as the real service
  /// does on the first use of the class sounds.
  void classification(
    SfxType type, {
    SfxType? move,
    bool waitOnDecode = false,
  }) {
    final request = gate.requestClass(move);
    stopped.addAll(request.cut);
    if (waitOnDecode) {
      _decoding.add((ticket: request.ticket, type: type));
      return;
    }
    _startClass(request.ticket, type);
  }

  void finishDecode() {
    for (final pending in List.of(_decoding)) {
      _startClass(pending.ticket, pending.type);
    }
    _decoding.clear();
  }

  void _startClass(int ticket, SfxType type) {
    if (!gate.mayStartClass(ticket)) {
      skipped.add(type.name);
      return;
    }
    final handle = _nextHandle++;
    voices[handle] = type.name;
    gate.classStarted(ticket, handle);
  }
}

/// First gradient stop of a badge SVG, as the app draws it.
Color _badgeTopStop(String asset) {
  final svg = io.File(asset).readAsStringSync();
  final hex = RegExp(r'stop-color="#([0-9A-Fa-f]{6})"').firstMatch(svg)!;
  return Color(int.parse('FF${hex.group(1)}', radix: 16));
}

/// A Feed ply: [moment] is Feed's eval-swing judgement, [verdict] the PGN's
/// own class (it wins over the moment, as [FeedPly.effectiveClass] says).
FeedPly _ply(
  String san, {
  FeedMomentType? moment,
  int severity = 1,
  MoveClass? verdict,
}) => FeedPly(
  fen: kInitialFEN,
  san: san,
  moveClass: verdict,
  moment: moment == null
      ? null
      : FeedMoment(type: moment, label: moment.name, severity: severity),
);

/// The Feed player exactly as a clip wires it: [FeedPlayback] sounding its
/// moves through a real [FeedMoveSound] (board sound on).
FeedPlayback _playback(FeedItem item) {
  final sfx = FeedSfx.forTesting();
  return FeedPlayback(item: item, sfx: sfx, moveSound: FeedMoveSound(sfx));
}

/// Longer than [FeedMoveSound]'s 90 ms spacing, which runs on a real
/// stopwatch, and well inside the 450 ms headline hold Feed does not have.
Future<void> _pastSpacing() =>
    Future<void>.delayed(const Duration(milliseconds: 150));

void main() {
  group('MoveClass mapping', () {
    test('report verdicts map one to one', () {
      expect(
        {
          for (final c in GameMoveClassification.values)
            c: moveClassFromClassification(c),
        },
        {
          GameMoveClassification.brilliant: MoveClass.brilliant,
          GameMoveClassification.goodMove: MoveClass.great,
          GameMoveClassification.bestMove: MoveClass.best,
          GameMoveClassification.missedWin: MoveClass.missedWin,
          GameMoveClassification.inaccuracy: MoveClass.inaccuracy,
          GameMoveClassification.mistake: MoveClass.mistake,
          GameMoveClassification.blunder: MoveClass.blunder,
          GameMoveClassification.bookMove: MoveClass.book,
        },
      );
    });

    test('glyph NAGs \$1-\$6 map to their meanings, others to null', () {
      expect(moveClassFromGlyphNag(1), MoveClass.great);
      expect(moveClassFromGlyphNag(2), MoveClass.mistake);
      expect(moveClassFromGlyphNag(3), MoveClass.brilliant);
      expect(moveClassFromGlyphNag(4), MoveClass.blunder);
      expect(moveClassFromGlyphNag(5), MoveClass.interesting);
      expect(moveClassFromGlyphNag(6), MoveClass.inaccuracy);
      expect(moveClassFromGlyphNag(0), isNull);
      expect(moveClassFromGlyphNag(7), isNull);
      expect(moveClassFromGlyphNag(14), isNull);
    });

    test('a ChessEver verdict (\$240-\$247) wins over a glyph', () {
      expect(moveClassFromNags(const [240]), MoveClass.brilliant);
      expect(moveClassFromNags(const [242]), MoveClass.best);
      expect(moveClassFromNags(const [243]), MoveClass.missedWin);
      expect(moveClassFromNags(const [247]), MoveClass.book);
      expect(moveClassFromNags(const [1, 246]), MoveClass.blunder);
      expect(moveClassFromNags(const [5]), MoveClass.interesting);
      expect(moveClassFromNags(const [14, 6]), MoveClass.inaccuracy);
      expect(moveClassFromNags(const [14]), isNull);
      expect(moveClassFromNags(const []), isNull);
      expect(moveClassFromNags(null), isNull);
    });

    test('Feed moments: only verdicts are classified', () {
      FeedMoment moment(FeedMomentType type) =>
          FeedMoment(type: type, label: type.name);
      expect(
        moveClassForFeedMoment(moment(FeedMomentType.brilliant)),
        MoveClass.brilliant,
      );
      expect(
        moveClassForFeedMoment(moment(FeedMomentType.blunder)),
        MoveClass.blunder,
      );
      expect(
        moveClassForFeedMoment(moment(FeedMomentType.missedWin)),
        MoveClass.missedWin,
      );
      expect(
        moveClassForFeedMoment(moment(FeedMomentType.mistake)),
        MoveClass.mistake,
      );
      expect(
        moveClassForFeedMoment(moment(FeedMomentType.inaccuracy)),
        MoveClass.inaccuracy,
      );
      for (final type in [
        FeedMomentType.checkmate,
        FeedMomentType.sacrifice,
        FeedMomentType.promotion,
        FeedMomentType.check,
        FeedMomentType.capture,
        FeedMomentType.castle,
        FeedMomentType.gameEnd,
      ]) {
        expect(moveClassForFeedMoment(moment(type)), isNull, reason: '$type');
      }
      expect(moveClassForFeedMoment(null), isNull);
    });

    test('every class has its own sound, and the asset exists', () {
      final types = {for (final c in MoveClass.values) c.sfxType};
      expect(types, hasLength(MoveClass.values.length));
      for (final c in MoveClass.values) {
        expect(c.sfxType.isClassification, isTrue, reason: '$c');
        final path = AudioPlayerService.onDemandAssetPaths[c.sfxType];
        expect(path, isNotNull, reason: '$c');
        expect(io.File(path!).existsSync(), isTrue, reason: path);
      }
      expect(io.File('assets/sfx/feed_swipe.mp3').existsSync(), isTrue);
    });

    test('the board sounds are untouched and the Flow stingers are gone', () {
      for (final name in [
        'move',
        'castling',
        'check',
        'checkmate',
        'draw',
        'promotion',
        'takeover',
      ]) {
        expect(io.File('assets/sfx/piece_$name.wav').existsSync(), isTrue);
      }
      final flow = io.Directory('assets/sfx')
          .listSync()
          .map((f) => f.uri.pathSegments.last)
          .where((n) => n.startsWith('flow_'));
      expect(flow, isEmpty);
      for (final type in SfxType.values.take(7)) {
        expect(type.isOnDemand, isFalse, reason: '$type');
        expect(AudioPlayerService.gainFor(type), 1.0, reason: '$type');
      }
    });

    test('effect colours match the badge SVGs', () {
      const badges = {
        MoveClass.brilliant: 'brilliant',
        MoveClass.great: 'good',
        MoveClass.best: 'best',
        MoveClass.inaccuracy: 'inaccuracy',
        MoveClass.mistake: 'mistake',
        MoveClass.blunder: 'blunder',
        MoveClass.missedWin: 'missed_win',
        MoveClass.book: 'book',
      };
      for (final entry in badges.entries) {
        expect(
          entry.key.fxColor,
          _badgeTopStop('assets/svgs/${entry.value}.svg'),
          reason: entry.value,
        );
      }
      // `!?` has no badge: the notation glyph's magenta.
      expect(MoveClass.interesting.fxColor, const Color(0xFFEA45D8));
    });
  });

  group('SfxPriorityGate (fake player)', () {
    test('a classification sound cuts its own move\'s ordinary sound', () {
      final player = _FakePlayer();
      player.ordinary(SfxType.move); // the board's other trigger went first
      player.nowMs = 100;
      player.classification(SfxType.nagBrilliant, move: SfxType.move);
      expect(player.sounding, ['nagBrilliant']);
      expect(player.stopped, hasLength(1));
    });

    test('another move\'s ordinary sound is never cut', () {
      final player = _FakePlayer();
      player.ordinary(SfxType.takeover); // the previous ply, fast taps
      player.nowMs = 60;
      player.classification(SfxType.nagBlunder, move: SfxType.move);
      player.nowMs = 200;
      player.ordinary(SfxType.move);
      player.nowMs = 400; // same sound, but a later move
      player.classification(SfxType.nagMistake, move: SfxType.move);
      expect(player.sounding, ['takeover', 'move', 'nagMistake']);
      expect(player.stopped, hasLength(1)); // only nagBlunder, by nagMistake
    });

    test('the same move\'s echo is skipped; the next move still sounds', () {
      final player = _FakePlayer();
      player.classification(SfxType.nagMistake, move: SfxType.check);
      player.nowMs = 2;
      player.ordinary(SfxType.check); // the board's second trigger
      expect(player.skipped, ['check']);

      // Long-press stepping: the next plies land every 150 ms, whatever
      // their sound, and keep their board sound.
      player.nowMs = 150;
      player.ordinary(SfxType.check);
      player.nowMs = 300;
      player.ordinary(SfxType.takeover);
      expect(player.sounding, ['nagMistake', 'check', 'takeover']);
      expect(player.skipped, ['check']);
    });

    test('a quick next move with a different sound is not held', () {
      final player = _FakePlayer();
      player.classification(SfxType.nagBest, move: SfxType.move);
      player.nowMs = 80;
      player.ordinary(SfxType.takeover);
      expect(player.sounding, ['nagBest', 'takeover']);
      expect(player.skipped, isEmpty);
    });

    test('never both: the move\'s ordinary waiting on init is dropped', () {
      final player = _FakePlayer();
      player.ordinary(SfxType.move, waitOnInit: true);
      player.ordinary(SfxType.takeover, waitOnInit: true); // another move
      player.classification(SfxType.nagBook, move: SfxType.move);
      player.finishInit();
      expect(player.sounding, ['nagBook', 'takeover']);
      expect(player.skipped, ['move']);
    });

    test('fast stepping never stacks classification voices', () {
      final player = _FakePlayer();
      for (var ply = 0; ply < 5; ply++) {
        player.nowMs = ply * 150;
        player.classification(
          ply.isEven ? SfxType.nagBest : SfxType.nagBook,
          move: SfxType.move,
        );
      }
      expect(player.sounding, ['nagBest']);
      expect(player.stopped, hasLength(4));
    });

    test('a classification still decoding yields to a newer one', () {
      final player = _FakePlayer();
      player.classification(
        SfxType.nagGreat,
        move: SfxType.move,
        waitOnDecode: true,
      );
      player.nowMs = 150;
      player.classification(
        SfxType.nagBlunder,
        move: SfxType.takeover,
        waitOnDecode: true,
      );
      player.finishDecode();
      expect(player.sounding, ['nagBlunder']);
      expect(player.skipped, ['nagGreat']);
    });

    test('ordinary sounds flow freely with no classification around', () {
      final player = _FakePlayer();
      const sounds = [
        SfxType.move,
        SfxType.takeover,
        SfxType.check,
        SfxType.move,
      ];
      for (var i = 0; i < sounds.length; i++) {
        player.nowMs = i * 30;
        player.ordinary(sounds[i]);
      }
      expect(player.sounding, ['move', 'takeover', 'check', 'move']);
      expect(player.skipped, isEmpty);
    });
  });

  group('ClassificationSfx', () {
    late _RecordingOutput output;

    setUp(() => ClassificationSfx.output = output = _RecordingOutput());
    tearDown(() => ClassificationSfx.output = null);

    test('unclassified moves keep the board sound for their SAN', () {
      for (final san in ['Nf3', 'exd5', 'Qf7+', 'Qh7#', 'O-O', 'e8=Q']) {
        ClassificationSfx.playMove(san: san);
      }
      expect(output.calls, [
        'ordinary:move',
        'ordinary:takeover',
        'ordinary:check',
        'ordinary:checkmate',
        'ordinary:castling',
        'ordinary:promotion',
      ]);
    });

    test('a classified move plays its class sound INSTEAD, never both', () {
      ClassificationSfx.playMove(san: 'Qxf7+', moveClass: MoveClass.blunder);
      ClassificationSfx.playMove(san: 'Nf3', moveClass: MoveClass.book);
      expect(output.calls, ['class:nagBlunder/check', 'class:nagBook/move']);
    });

    test('playClass plays just the class sound', () {
      for (final c in MoveClass.values) {
        ClassificationSfx.playClass(c);
      }
      expect(output.calls, [
        for (final c in MoveClass.values) 'class:${c.sfxType.name}/null',
      ]);
    });

    test('a failing engine never reaches the caller', () async {
      ClassificationSfx.output = _ThrowingOutput();
      expect(() => ClassificationSfx.playMove(san: 'e4'), returnsNormally);
      expect(
        () => ClassificationSfx.playMove(san: 'e4', moveClass: MoveClass.great),
        returnsNormally,
      );
      expect(
        () => ClassificationSfx.playClass(MoveClass.best),
        returnsNormally,
      );
      await expectLater(ClassificationSfx.warmUp(), completes);
    });

    // Feed sounds its moves through FeedPlayback -> FeedMoveSound, the path a
    // clip ships with.

    testWidgets('Feed: 2x autoplay sounds every move, verdicts as themselves', (
      tester,
    ) async {
      // Fake time drives the playback timer but not FeedMoveSound's real
      // stopwatch, so the one ordinary move goes first: classified moves are
      // never spaced out, ordinary ones would be (a test artefact; at 2x the
      // moves are 325 ms apart).
      final playback = _playback(
        _item('½-½', [
          _ply('e4'),
          _ply('a3', moment: FeedMomentType.inaccuracy),
          _ply('Nc3', verdict: MoveClass.book),
          _ply(
            'Qxb7',
            moment: FeedMomentType.mistake,
            severity: 2,
            verdict: MoveClass.best,
          ),
        ]),
      );
      addTearDown(playback.dispose);

      playback
        ..restart()
        ..setSuspended(false)
        ..setFast(true);
      await tester.pump(const Duration(seconds: 5));

      expect(playback.isEnded, isTrue);
      expect(output.calls, [
        'ordinary:move', // an unclassified move still sounds at 2x
        'class:nagInaccuracy/move', // a severity-1 verdict too
        'class:nagBook/move', // the report's verdicts sound as themselves
        'class:nagBest/takeover', // the PGN's verdict wins over the moment
        'ordinary:draw',
      ]);
    });

    test('Feed: a step sounds the landed move like the board, back is '
        'silent', () async {
      final playback = _playback(
        _item('1-0', [
          _ply('Bxh7+', moment: FeedMomentType.sacrifice, severity: 3),
          _ply('Kxh7'),
          _ply('Qh7#', moment: FeedMomentType.checkmate, severity: 3),
        ]),
      );
      addTearDown(playback.dispose);

      playback.stepTo(1);
      playback.stepTo(0);
      await _pastSpacing();
      playback.stepTo(3);

      expect(output.calls, ['ordinary:check', 'ordinary:checkmate']);
    });

    test('Feed: scrubbing sounds only classified moves, spaced', () async {
      final playback = _playback(
        _item(null, [
          _ply('e4'),
          _ply('a3', moment: FeedMomentType.inaccuracy),
          _ply('Nxe5', moment: FeedMomentType.mistake, severity: 2),
          _ply('Qxb7', moment: FeedMomentType.blunder, severity: 3),
        ]),
      );
      addTearDown(playback.dispose);

      playback
        ..beginScrub(0)
        ..scrubTo(1) // e4: unclassified, silent while scrubbing
        ..scrubTo(2) // ?!: sounds, whatever its severity
        ..scrubTo(3) // ?: under 90 ms after the last sound, dropped
        ..scrubTo(2); // back: silent
      await _pastSpacing();
      playback
        ..scrubTo(4)
        ..endScrub();

      expect(output.calls, [
        'class:nagInaccuracy/move',
        'class:nagBlunder/takeover',
      ]);
    });

    test('Feed: ordinary moves keep their spacing, and no headline hold '
        'follows a brilliant', () async {
      final sound = FeedMoveSound(FeedSfx.forTesting());
      sound.play(san: 'e4');
      sound.play(san: 'e5'); // under 90 ms after e4: dropped
      sound.play(san: 'Qxh7+', moveClass: MoveClass.brilliant); // never spaced
      await _pastSpacing();
      sound.play(san: 'Kxh7');
      expect(output.calls, [
        'ordinary:move',
        'class:nagBrilliant/check',
        'ordinary:takeover',
      ]);
    });

    test('Feed: muted or board sound off plays nothing', () {
      final sfx = FeedSfx.forTesting()..muted = true;
      var boardSoundOn = true;
      final sound = FeedMoveSound(sfx, boardSoundOn: () => boardSoundOn);
      sound.play(san: 'e4');
      sound.play(san: 'Qxh7+', moveClass: MoveClass.blunder);
      sfx.playSwipe();
      sfx.playGameEnd(_item('½-½'));

      sfx.muted = false;
      boardSoundOn = false; // the board's Sound setting, as the provider reads
      sfx.boardSoundEnabled = false;
      sound.play(san: 'e4');
      sound.play(san: 'Qxh7+', moveClass: MoveClass.blunder);
      sfx.playGameEnd(_item('½-½'));
      expect(output.calls, isEmpty);
    });

    test('Feed: swipes whoosh; a drawn game ends on the board draw chime, a '
        'win does not', () {
      final sfx = FeedSfx.forTesting();
      sfx.playSwipe();
      sfx.playGameEnd(_item('1-0'));
      sfx.playGameEnd(_item('½-½'));
      expect(output.calls, ['ordinary:feedSwipe', 'ordinary:draw']);
    });
  });

  group('ClassificationLanding', () {
    Widget host({
      required MoveClass? moveClass,
      required Object? trigger,
      bool disableAnimations = false,
      Square? square = Square.e4,
    }) {
      return MediaQuery(
        data: MediaQueryData(disableAnimations: disableAnimations),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: SizedBox.square(
              dimension: 320,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: ClassificationLanding(
                      square: square,
                      moveClass: moveClass,
                      orientation: Side.white,
                      trigger: trigger,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    Finder painterFinder() => find.descendant(
      of: find.byType(ClassificationLanding),
      matching: find.byWidgetPredicate(
        (w) => w is CustomPaint && w.painter is ClassificationLandingPainter,
      ),
    );

    for (final moveClass in MoveClass.values) {
      testWidgets('${moveClass.name} plays, stays out of input, and ends '
          'fully transparent', (tester) async {
        await tester.pumpWidget(host(moveClass: moveClass, trigger: 0));
        expect(painterFinder(), findsNothing); // arriving is not landing

        await tester.pumpWidget(host(moveClass: moveClass, trigger: 1));
        await tester.pump(kClassificationLandingDelay);
        await tester.pump(const Duration(milliseconds: 60));
        expect(painterFinder(), findsOneWidget);
        expect(
          find.ancestor(
            of: painterFinder(),
            matching: find.byType(IgnorePointer),
          ),
          findsWidgets,
        );
        final render = tester.renderObject<RenderCustomPaint>(painterFinder());
        expect(render, paints..something((_, _) => true));

        await tester.pumpAndSettle();
        expect(render, paintsNothing);
      });
    }

    testWidgets('a zero delay starts on the landing frame itself', (
      tester,
    ) async {
      Widget zero(Object trigger) => Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox.square(
          dimension: 320,
          child: ClassificationLanding(
            square: Square.g7,
            moveClass: MoveClass.great,
            orientation: Side.black,
            trigger: trigger,
            delay: Duration.zero,
          ),
        ),
      );
      await tester.pumpWidget(zero(0));
      await tester.pumpWidget(zero(1));
      await tester.pump(const Duration(milliseconds: 16));
      expect(painterFinder(), findsOneWidget);
      expect(
        tester.renderObject<RenderCustomPaint>(painterFinder()),
        paints..something((_, _) => true),
      );
      await tester.pumpAndSettle();
    });

    testWidgets('playOnMount plays a board that appears on the move', (
      tester,
    ) async {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: SizedBox.square(
            dimension: 320,
            child: ClassificationLanding(
              square: Square.c3,
              moveClass: MoveClass.book,
              orientation: Side.white,
              trigger: 0,
              delay: Duration.zero,
              playOnMount: true,
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 16));
      expect(painterFinder(), findsOneWidget);
      await tester.pumpAndSettle();
    });

    testWidgets('draws nothing for an unclassified move', (tester) async {
      await tester.pumpWidget(host(moveClass: null, trigger: 0));
      await tester.pumpWidget(host(moveClass: null, trigger: 1));
      await tester.pump(kClassificationLandingDelay);
      await tester.pump(const Duration(milliseconds: 60));
      expect(painterFinder(), findsNothing);
      await tester.pumpAndSettle();
    });

    testWidgets('draws nothing with no square', (tester) async {
      await tester.pumpWidget(
        host(moveClass: MoveClass.brilliant, trigger: 0, square: null),
      );
      await tester.pumpWidget(
        host(moveClass: MoveClass.brilliant, trigger: 1, square: null),
      );
      await tester.pump(kClassificationLandingDelay);
      expect(painterFinder(), findsNothing);
    });

    testWidgets('reduced motion draws nothing at all', (tester) async {
      await tester.pumpWidget(
        host(moveClass: MoveClass.blunder, trigger: 0, disableAnimations: true),
      );
      await tester.pumpWidget(
        host(moveClass: MoveClass.blunder, trigger: 1, disableAnimations: true),
      );
      await tester.pump(kClassificationLandingDelay);
      await tester.pump(const Duration(milliseconds: 60));
      expect(painterFinder(), findsNothing);
    });

    test('the painter draws on the destination square, per orientation', () {
      final progress = AlwaysStoppedAnimation<double>(0.2);
      Rect firstRect(Side orientation) {
        final canvas = TestRecordingCanvas();
        ClassificationLandingPainter(
          progress: progress,
          square: Square.a1,
          moveClass: MoveClass.blunder,
          orientation: orientation,
        ).paint(canvas, const Size.square(320));
        final draw = canvas.invocations.firstWhere(
          (i) => i.invocation.memberName == #drawRect,
        );
        return draw.invocation.positionalArguments.first as Rect;
      }

      // a1 is bottom-left for White (shaken by at most 3 px) ...
      expect(firstRect(Side.white).center.dx, closeTo(20, 3.01));
      expect(firstRect(Side.white).center.dy, closeTo(300, 0.01));
      // ... and top-right for Black.
      expect(firstRect(Side.black).center.dx, closeTo(300, 3.01));
      expect(firstRect(Side.black).center.dy, closeTo(20, 0.01));
    });

    test('a finished landing paints nothing', () {
      for (final moveClass in MoveClass.values) {
        final canvas = TestRecordingCanvas();
        ClassificationLandingPainter(
          progress: const AlwaysStoppedAnimation<double>(1),
          square: Square.d5,
          moveClass: moveClass,
          orientation: Side.white,
        ).paint(canvas, const Size.square(320));
        expect(canvas.invocations, isEmpty, reason: '$moveClass');
      }
    });
  });

  group('chessground landing settle (vendored patch)', () {
    ChessboardController controllerFor(String fen) => ChessboardController(
      game: GameData(
        fen: fen,
        playerSide: PlayerSide.none,
        sideToMove: Setup.parseFen(fen).turn,
        validMoves: const <Square, Set<Square>>{},
      ),
    );

    Widget board(
      ChessboardController controller, {
      Square? landingSquare,
      Object? landingKey,
    }) {
      return Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: Chessboard(
            size: 320,
            controller: controller,
            orientation: Side.white,
            settings: const ChessboardSettings(
              animationDuration: Duration(milliseconds: 200),
            ),
            landingSquare: landingSquare,
            landingKey: landingKey,
          ),
        ),
      );
    }

    Iterable<LandingPiecePainter> landingPainters(WidgetTester tester) => tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((w) => w.painter)
        .whereType<LandingPiecePainter>();

    testWidgets('boards that do not ask for it are unchanged', (tester) async {
      final controller = controllerFor(kInitialFEN);
      addTearDown(controller.dispose);
      await tester.pumpWidget(board(controller));
      expect(landingPainters(tester), isEmpty);
    });

    testWidgets('the landed piece settles after its move animation, then '
        'returns to the static layer', (tester) async {
      final controller = controllerFor(kInitialFEN);
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        board(controller, landingSquare: Square.e4, landingKey: 0),
      );
      final painter = landingPainters(tester).single;
      expect(painter.landingSquareNotifier.value, isNull);

      const afterE4 =
          'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1';
      controller.updatePosition(
        GameData(
          fen: afterE4,
          playerSide: PlayerSide.none,
          sideToMove: Side.black,
          validMoves: const <Square, Set<Square>>{},
          lastMove: const NormalMove(from: Square.e2, to: Square.e4),
        ),
      );
      await tester.pumpWidget(
        board(controller, landingSquare: Square.e4, landingKey: 1),
      );
      // Still translating: the settle waits for the piece to land.
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        landingPainters(tester).single.landingSquareNotifier.value,
        isNull,
      );

      await tester.pump(const Duration(milliseconds: 150));
      expect(
        landingPainters(tester).single.landingSquareNotifier.value,
        Square.e4,
      );

      await tester.pumpAndSettle();
      expect(
        landingPainters(tester).single.landingSquareNotifier.value,
        isNull,
      );
    });
  });
}

/// A clip of [moves] after the starting position.
FeedItem _item(String? result, [List<FeedPly> moves = const []]) => FeedItem(
  game: _FakeGame(),
  plies: [
    const FeedPly(fen: kInitialFEN),
    ...moves,
  ],
  reason: 'test',
  result: result,
);

class _FakeGame extends Fake implements GamesTourModel {}
