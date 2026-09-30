import 'dart:async';
import 'dart:io' as io;
import 'dart:math' as math;

import 'package:chessever2/screens/feed/race/race_sfx.dart';
import 'package:chessever2/utils/audio_player_service.dart';
import 'package:flutter_soloud/flutter_soloud.dart' show SoundHandle;
import 'package:flutter_test/flutter_test.dart';

/// Records what [RaceSfx] asks of the audio engine. Loop starts land at once
/// unless [holdStarts] is set, in which case each waits for [land].
class _Recorder implements RaceSfxOutput {
  final List<({SfxType type, double speed})> plays = [];
  final List<SoundHandle> started = [];
  final Set<SoundHandle> stopped = {};
  final Set<SoundHandle> dead = {};
  final List<({SoundHandle voice, double? volume, double? speed})> fades = [];
  final List<Completer<SoundHandle?>> _held = [];
  /// Misuse seen from inside callbacks (asserted by [expectClean]).
  final List<String> violations = [];
  int startCalls = 0;
  int warmUps = 0;
  bool holdStarts = false;
  int _nextId = 1;

  /// Loop voices started and not asked to stop (nor dropped by the engine).
  List<SoundHandle> get live => started
      .where((v) => !stopped.contains(v) && !dead.contains(v))
      .toList();

  List<SfxType> get played => plays.map((p) => p.type).toList();

  void expectClean() => expect(violations, isEmpty);

  /// Lets every held loop start land.
  void land() {
    for (final start in _held) {
      start.complete(_newVoice());
    }
    _held.clear();
  }

  SoundHandle _newVoice() {
    final voice = SoundHandle(_nextId++);
    started.add(voice);
    return voice;
  }

  @override
  Future<void> warmUp() async => warmUps++;

  @override
  void play(SfxType type, {required double volume, required double speed}) =>
      plays.add((type: type, speed: speed));

  @override
  Future<SoundHandle?> startLoop(
    SfxType type, {
    required double volume,
    required double speed,
  }) {
    if (type != SfxType.raceTensionLoop) violations.add('looped $type');
    startCalls++;
    if (holdStarts) {
      final start = Completer<SoundHandle?>();
      _held.add(start);
      return start.future;
    }
    return Future.value(_newVoice());
  }

  @override
  void fadeLoop(
    SoundHandle voice, {
    double? volume,
    double? speed,
    required Duration over,
  }) {
    if (stopped.contains(voice)) violations.add('faded stopped $voice');
    fades.add((voice: voice, volume: volume, speed: speed));
  }

  @override
  void stopLoop(SoundHandle voice, {required Duration fade}) =>
      stopped.add(voice);

  @override
  bool isAlive(SoundHandle voice) =>
      started.contains(voice) &&
      !stopped.contains(voice) &&
      !dead.contains(voice);
}

void main() {
  late _Recorder out;
  late int now;
  late RaceSfx sfx;

  RaceSfx make({bool boardSound = true}) =>
      RaceSfx.forTesting(sink: out, boardSound: boardSound, nowMs: () => now);

  setUp(() {
    out = _Recorder();
    now = 1000;
    sfx = make();
  });

  tearDown(() => out.expectClean());

  /// Advances both the fake clock and the test's timers.
  Future<void> wait(WidgetTester tester, int ms) async {
    now += ms;
    await tester.pump(Duration(milliseconds: ms));
  }

  group('assets', () {
    final race = SfxType.values.where((t) => t.isRace).toList();

    test('every race sound has its own race_*.mp3, and nothing else does', () {
      expect(race, hasLength(10));
      expect(
        AudioPlayerService.raceAssetPaths.keys.toSet(),
        race.toSet(),
      );
      final paths = AudioPlayerService.raceAssetPaths.values.toSet();
      expect(paths, hasLength(race.length), reason: 'one file per sound');
      for (final entry in AudioPlayerService.raceAssetPaths.entries) {
        final path = entry.value;
        expect(path, matches(RegExp(r'^assets/sfx/race_[a-z_]+\.mp3$')));
        final file = io.File(path);
        expect(file.existsSync(), isTrue, reason: path);
        final size = file.lengthSync();
        // Short, levelled stingers (the 3.2 s loop is the largest).
        expect(size, inInclusiveRange(2 * 1024, 120 * 1024), reason: path);
      }
      final onDisk = io.Directory('assets/sfx')
          .listSync()
          .map((f) => 'assets/sfx/${f.uri.pathSegments.last}')
          .where((p) => p.startsWith('assets/sfx/race_'))
          .toSet();
      expect(onDisk, paths, reason: 'no stray or missing race files');
    });

    test('race sounds sit between the swipe and the classification sounds', () {
      for (final type in race) {
        expect(type.isOnDemand, isTrue, reason: '$type');
        expect(type.isClassification, isFalse, reason: '$type');
        expect(type.index, greaterThan(SfxType.feedSwipe.index));
        expect(type.index, lessThan(SfxType.nagBrilliant.index));
        expect(AudioPlayerService.gainFor(type), 1.0, reason: '$type');
        // Never loaded with the classification set.
        expect(AudioPlayerService.onDemandAssetPaths, isNot(contains(type)));
      }
      for (final type in SfxType.values.take(7)) {
        expect(type.isOnDemand, isFalse, reason: '$type');
        expect(type.isRace, isFalse, reason: '$type');
      }
      expect(SfxType.feedSwipe.isRace, isFalse);
      final classification = SfxType.values.where((t) => t.isClassification);
      expect(classification, hasLength(9));
      for (final type in classification) {
        expect(type.name, startsWith('nag'));
        expect(type.isRace, isFalse);
        expect(AudioPlayerService.onDemandAssetPaths, contains(type));
      }
    });
  });

  group('gating', () {
    /// A whole race: countdown, a streak with a level-up, a miss on the last
    /// life, the tension climbing, and a finish with a new best.
    Future<void> race(WidgetTester tester) async {
      sfx
        ..countdownBeat(3)
        ..go()
        ..setTension(0.6);
      await wait(tester, 500);
      sfx
        ..correct(streak: 4)
        ..levelUp();
      await wait(tester, 500);
      sfx
        ..wrong()
        ..lastLife();
      await wait(tester, 500);
      sfx.finish(newBest: true);
      await wait(tester, 1500);
    }

    testWidgets('muted: nothing sounds and no bed starts', (tester) async {
      sfx.muted = true;
      await race(tester);
      expect(out.plays, isEmpty);
      expect(out.startCalls, 0);
    });

    testWidgets('board Sound off: nothing sounds', (tester) async {
      sfx = make(boardSound: false);
      await race(tester);
      expect(out.plays, isEmpty);
      expect(out.startCalls, 0);
    });

    testWidgets('both on: every stinger sounds', (tester) async {
      await race(tester);
      expect(
        out.played.toSet(),
        containsAll(<SfxType>[
          SfxType.raceCountdownBeat,
          SfxType.raceGo,
          SfxType.raceCorrectStreak,
          SfxType.raceWrong,
          SfxType.raceLevelUp,
          SfxType.raceLastLife,
          SfxType.raceFinish,
          SfxType.raceNewBest,
        ]),
      );
      expect(out.startCalls, 1);
      expect(out.live, isEmpty, reason: 'finish ends the bed');
    });

    testWidgets('muting breathes the bed out; unmuting brings it back', (
      tester,
    ) async {
      sfx.setTension(0.5);
      await tester.pump();
      expect(out.live, hasLength(1));

      sfx.muted = true;
      expect(out.fades.last.volume, 0);
      await wait(tester, 1000);
      expect(out.live, isEmpty);

      sfx.muted = false;
      await tester.pump();
      expect(out.live, hasLength(1));
      expect(out.fades.last.volume, greaterThan(0));
      sfx.stopAll();
    });

    testWidgets('muting cancels a staggered stinger', (tester) async {
      sfx
        ..correct()
        ..levelUp();
      sfx.muted = true;
      await wait(tester, 500);
      expect(out.played, [SfxType.raceCorrect]);
    });

    testWidgets('turning board Sound off silences the race', (tester) async {
      sfx.setTension(0.3);
      await tester.pump();
      sfx.boardSoundEnabled = false;
      await wait(tester, 1000);
      expect(out.live, isEmpty);
      sfx.go();
      expect(out.plays, isEmpty);
    });
  });

  group('tension bed', () {
    testWidgets('setTension is idempotent', (tester) async {
      sfx.setTension(0.4);
      await tester.pump();
      expect(out.startCalls, 1);
      final fades = out.fades.length;

      sfx
        ..setTension(0.4)
        ..setTension(0.4)
        ..setTension(0.401); // the same step
      await wait(tester, 2000);
      expect(out.startCalls, 1);
      expect(out.fades, hasLength(fades));
      expect(out.live, hasLength(1));
      expect(sfx.tension, 0.4);
      sfx.stopAll();
    });

    testWidgets('a new tension glides the one live voice', (tester) async {
      sfx.setTension(0.2);
      await tester.pump();
      final voice = out.live.single;
      final quiet = out.fades.last.volume!;

      sfx.setTension(0.9);
      expect(out.startCalls, 1);
      expect(out.fades.last.voice, voice);
      expect(out.fades.last.volume, greaterThan(quiet));
      expect(out.fades.last.speed, greaterThan(1));
      expect(out.fades.last.volume, lessThanOrEqualTo(RaceSfx.bedCeiling));
      sfx.stopAll();
    });

    testWidgets('never stacks while a start is loading', (tester) async {
      out.holdStarts = true;
      sfx
        ..setTension(0.2)
        ..setTension(0.5)
        ..setTension(0.8)
        ..correct()
        ..wrong();
      expect(out.startCalls, 1);

      out.land();
      await tester.pump();
      expect(out.live, hasLength(1));
      // It lands at the newest tension, not the first.
      final top = out.fades.last;
      sfx.setTension(0.8);
      expect(out.fades.last, top);
      expect(top.volume, closeTo(0.08 + 0.52 * 0.8, 1e-9));
      sfx.stopAll();
    });

    testWidgets('a start that lands after stopAll is stopped, not kept', (
      tester,
    ) async {
      out.holdStarts = true;
      sfx.setTension(0.5);
      sfx.stopAll();
      out.land();
      await tester.pump();
      expect(out.started, hasLength(1));
      expect(out.live, isEmpty);
    });

    testWidgets('stopAll then a new race: one bed, the new one', (
      tester,
    ) async {
      out.holdStarts = true;
      sfx.setTension(0.5);
      sfx.stopAll();
      sfx.setTension(0.3); // the next race, before the old start landed
      expect(out.startCalls, 1);
      out.land();
      await tester.pump();
      expect(out.live, hasLength(1));
      sfx.stopAll();
    });

    testWidgets('dropping to zero fades out, then stops', (tester) async {
      sfx.setTension(0.5);
      await tester.pump();
      final voice = out.live.single;

      sfx.setTension(0);
      expect(out.fades.last.voice, voice);
      expect(out.fades.last.volume, 0);
      expect(out.live, hasLength(1), reason: 'still breathing out');

      await wait(tester, RaceSfx.bedFadeOut.inMilliseconds + 100);
      expect(out.live, isEmpty);
    });

    testWidgets('rising again while breathing out reuses the voice', (
      tester,
    ) async {
      sfx.setTension(0.5);
      await tester.pump();
      final voice = out.live.single;

      sfx.setTension(0);
      await wait(tester, 200);
      sfx.setTension(0.6);
      await wait(tester, 2000);
      expect(out.startCalls, 1);
      expect(out.live, [voice]);
      expect(out.fades.last.volume, greaterThan(0));
      sfx.stopAll();
    });

    testWidgets('a bed the engine dropped comes back on the next event', (
      tester,
    ) async {
      sfx.setTension(0.5);
      await tester.pump();
      out.dead.add(out.live.single); // the app went to the background

      sfx.correct();
      await tester.pump();
      expect(out.startCalls, 2);
      expect(out.live, hasLength(1));

      out.dead.add(out.live.single);
      sfx.setTension(0.5); // same value: still heals, still one voice
      await tester.pump();
      expect(out.startCalls, 3);
      expect(out.live, hasLength(1));
      sfx.stopAll();
    });

    testWidgets('never more than one live bed, whatever the order', (
      tester,
    ) async {
      final random = math.Random(7);
      out.holdStarts = true;
      for (var step = 0; step < 400; step++) {
        switch (random.nextInt(8)) {
          case 0:
          case 1:
          case 2:
            sfx.setTension(random.nextInt(5) / 4);
          case 3:
            sfx.muted = random.nextBool();
          case 4:
            sfx.stopAll();
          case 5:
            out.land();
          case 6:
            if (out.live.isNotEmpty && random.nextInt(4) == 0) {
              out.dead.add(out.live.first);
            }
            sfx.correct();
          case 7:
            sfx.finish();
        }
        await wait(tester, random.nextInt(400));
        expect(out.live.length, lessThanOrEqualTo(1), reason: 'step $step');
      }
      sfx.stopAll();
      out.land();
      await wait(tester, 2000);
      expect(out.live, isEmpty);
    });

    testWidgets('stopAll ends the bed and cancels what is pending', (
      tester,
    ) async {
      sfx.setTension(0.7);
      await tester.pump();
      sfx
        ..wrong()
        ..lastLife()
        ..stopAll();
      await wait(tester, 1000);
      expect(out.live, isEmpty);
      expect(out.played, [SfxType.raceWrong]);
      expect(sfx.tension, 0);
    });
  });

  group('stingers', () {
    testWidgets('a level-up raised with its solve lands after the blip', (
      tester,
    ) async {
      sfx
        ..correct()
        ..levelUp();
      expect(out.played, [SfxType.raceCorrect]);
      await wait(tester, RaceSfx.levelUpAfterCorrect.inMilliseconds - 20);
      expect(out.played, [SfxType.raceCorrect]);
      await wait(tester, 40);
      expect(out.played, [SfxType.raceCorrect, SfxType.raceLevelUp]);
    });

    testWidgets('a lone level-up plays at once', (tester) async {
      sfx.levelUp();
      expect(out.played, [SfxType.raceLevelUp]);
    });

    testWidgets('the last life lands after its miss', (tester) async {
      sfx
        ..wrong()
        ..lastLife();
      expect(out.played, [SfxType.raceWrong]);
      await wait(tester, RaceSfx.lastLifeAfterWrong.inMilliseconds + 10);
      expect(out.played, [SfxType.raceWrong, SfxType.raceLastLife]);
    });

    test('streaks escalate: layered at 3, a step higher per solve, capped', () {
      double speedFor(int streak) {
        now += 1000;
        sfx.correct(streak: streak);
        return out.plays.last.speed;
      }

      for (final streak in [0, 1, 2]) {
        expect(speedFor(streak), 1.0);
        expect(out.plays.last.type, SfxType.raceCorrect);
      }
      final semitone = math.pow(2, 1 / 12);
      expect(speedFor(3), 1.0);
      expect(out.plays.last.type, SfxType.raceCorrectStreak);
      expect(speedFor(4), closeTo(math.pow(semitone, 2), 1e-9));
      expect(speedFor(5), closeTo(math.pow(semitone, 4), 1e-9));
      expect(speedFor(6), closeTo(math.pow(semitone, 5), 1e-9));
      expect(speedFor(20), closeTo(math.pow(semitone, 5), 1e-9));
    });

    test('countdown: 3 and 2 alike, 1 a semitone up, echoes play once', () {
      sfx.countdownBeat(3);
      sfx.countdownBeat(3); // a rebuild raising it again
      now += 1000;
      sfx.countdownBeat(2);
      now += 1000;
      sfx.countdownBeat(1);
      sfx.countdownBeat(0); // "0" is go()
      expect(out.played, List.filled(3, SfxType.raceCountdownBeat));
      expect(out.plays[0].speed, 1.0);
      expect(out.plays[1].speed, 1.0);
      expect(out.plays[2].speed, closeTo(math.pow(2, 1 / 12), 1e-9));
    });

    testWidgets('a run-ending miss: the buzz, then the finish hit', (
      tester,
    ) async {
      sfx
        ..wrong()
        ..finish();
      expect(out.played, [SfxType.raceWrong]);
      await wait(tester, RaceSfx.finishAfterWrong.inMilliseconds + 10);
      expect(out.played, [SfxType.raceWrong, SfxType.raceFinish]);
    });

    testWidgets('finish: the hit once, the new-best flourish on its ring', (
      tester,
    ) async {
      sfx.setTension(0.8);
      await tester.pump();
      sfx.finish();
      expect(out.live, isEmpty);
      await wait(tester, 400);
      sfx.finish(newBest: true); // the call that knows about the best
      expect(
        out.played.where((t) => t == SfxType.raceFinish),
        hasLength(1),
      );
      await wait(tester, RaceSfx.newBestAfterFinish.inMilliseconds + 10);
      expect(out.played.last, SfxType.raceNewBest);
    });

    test('warmUp loads on demand and is safe to repeat', () async {
      expect(out.warmUps, 0, reason: 'nothing loads before a race');
      await sfx.warmUp();
      await sfx.warmUp();
      expect(out.warmUps, 2);
    });
  });
}
