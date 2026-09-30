import 'package:chessever2/providers/board_settings_provider_new.dart';
import 'package:chessever2/screens/chessboard/classification_fx/classification_fx.dart';
import 'package:chessever2/screens/feed/audio/feed_sfx.dart';
import 'package:chessever2/screens/feed/race/puzzle_rating_range.dart';
import 'package:chessever2/screens/feed/race/race_audio.dart';
import 'package:chessever2/screens/feed/race/race_client.dart';
import 'package:chessever2/screens/feed/race/race_controller.dart';
import 'package:chessever2/screens/feed/race/race_flames.dart';
import 'package:chessever2/screens/feed/race/race_sfx.dart';
import 'package:chessever2/screens/feed/widgets/feed_sfx_provider.dart';
import 'package:chessever2/utils/audio_player_service.dart';
import 'package:flutter_soloud/flutter_soloud.dart' show SoundHandle;
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'puzzle_race_fakes.dart';

/// Lets zero-length timers and socket events run.
Future<void> settle() async {
  for (var i = 0; i < 12; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

class _Race {
  _Race(
    this.harness, {
    Duration soloCountdown = Duration.zero,
    Duration replyTimeout = RaceConnection.defaultReplyTimeout,
    List<Duration> backoff = const [Duration.zero],
  }) : container = ProviderContainer(
         overrides: [
           raceDepsProvider.overrideWithValue(
             harness.deps(
               soloCountdown: soloCountdown,
               replyTimeout: replyTimeout,
               backoff: backoff,
             ),
           ),
         ],
       ) {
    // The controller is auto-disposed; keep it for the whole test.
    container.listen(raceControllerProvider, (_, _) {});
  }

  final RaceHarness harness;
  final ProviderContainer container;

  RaceController get controller =>
      container.read(raceControllerProvider.notifier);
  RaceState get state => container.read(raceControllerProvider);
  FakeRaceSocket get socket => harness.server.last;

  /// Solo Survival up to the first puzzle on the board.
  Future<void> startSoloRunning({RaceMode mode = RaceMode.survival}) async {
    controller.selectMode(mode);
    await controller.startSolo();
    await settle();
    socket.push(snapshot(mode: mode.wire));
    await settle();
    socket.push(
      snapshot(mode: mode.wire, state: 'running', startedAt: 1790000000000),
    );
    socket.push(puzzle());
    await settle();
  }

  void dispose() => container.dispose();
}

/// The board's settings, loaded with Sound on; [setSound] is the user
/// flipping it in board settings.
class _BoardSettings extends BoardSettingsNotifierNew {
  @override
  Future<BoardSettingsNew> build() async => const BoardSettingsNew();

  void setSound(bool on) =>
      state = AsyncData(BoardSettingsNew(soundEnabled: on));
}

/// What [RaceSfx] asks of the audio engine.
class _Stingers implements RaceSfxOutput {
  final List<SfxType> played = [];
  final List<SoundHandle> started = [];
  final Set<SoundHandle> stopped = {};
  int _next = 1;

  @override
  Future<void> warmUp() async {}

  @override
  void play(SfxType type, {required double volume, required double speed}) =>
      played.add(type);

  @override
  Future<SoundHandle?> startLoop(
    SfxType type, {
    required double volume,
    required double speed,
  }) async {
    final voice = SoundHandle(_next++);
    started.add(voice);
    return voice;
  }

  @override
  void fadeLoop(
    SoundHandle voice, {
    double? volume,
    double? speed,
    required Duration over,
  }) {}

  @override
  void stopLoop(SoundHandle voice, {required Duration fade}) =>
      stopped.add(voice);

  @override
  bool isAlive(SoundHandle voice) =>
      started.contains(voice) && !stopped.contains(voice);
}

/// The board's move sounds, as [ClassificationSfx] plays them.
class _Moves implements ClassificationSfxOutput {
  final List<SfxType> played = [];

  @override
  void playOrdinary(SfxType type) => played.add(type);

  @override
  void playClassification(SfxType type, {SfxType? fallback}) =>
      played.add(type);

  @override
  Future<void> warmUp() async {}
}

/// A race on the real [raceAudioProvider] (stingers into [stingers], moves
/// into [moves]) with the Feed never built: its sound engine was never told
/// the board setting, exactly as when the race is opened from My Profile
/// first thing in a session.
class _SoundedRace {
  factory _SoundedRace(RaceHarness harness) {
    final stingers = _Stingers();
    // Unset, as production starts: nothing has told it the board setting.
    final sfx = RaceSfx.forTesting(sink: stingers, boardSound: null);
    return _SoundedRace._(harness, stingers, sfx);
  }

  _SoundedRace._(this.harness, this.stingers, this.sfx) {
    container = ProviderContainer(
      overrides: [
        raceSfxProvider.overrideWithValue(sfx),
        feedSfxProvider.overrideWithValue(
          FeedSfx.forTesting(boardSoundEnabled: false),
        ),
        boardSettingsProviderNew.overrideWith(_BoardSettings.new),
        raceDepsProvider.overrideWith(
          (ref) => harness.deps(audio: ref.read(raceAudioProvider)),
        ),
      ],
    );
    container.listen(raceControllerProvider, (_, _) {});
    ClassificationSfx.output = moves;
  }

  final RaceHarness harness;
  final _Stingers stingers;
  final RaceSfx sfx;
  final _Moves moves = _Moves();
  late final ProviderContainer container;

  RaceController get controller =>
      container.read(raceControllerProvider.notifier);
  FakeRaceSocket get socket => harness.server.last;

  /// The board playing a move's sound, as `RaceBoard` does.
  void boardMove(String san) =>
      container.read(raceDepsProvider).audio.move(san);

  void setSound(bool on) =>
      (container.read(boardSettingsProviderNew.notifier) as _BoardSettings)
          .setSound(on);

  Future<void> startRunning() async {
    await controller.startSolo();
    await settle();
    socket.push(snapshot());
    await settle();
    socket.push(snapshot(state: 'running', startedAt: 1790000000000));
    socket.push(puzzle());
    await settle();
  }

  void dispose() {
    container.dispose();
    ClassificationSfx.output = null;
  }
}

void main() {
  group('solo race', () {
    test('countdown, running, verdicts, three mistakes, results', () async {
      final h = RaceHarness();
      final race = _Race(h);
      addTearDown(race.dispose);

      await race.controller.startSolo();
      await settle();
      // A guest: no token on the POST, the seat on the upgrade.
      expect(h.api.creates.single.token, isNull);
      expect(h.api.creates.single.multiplayer, isFalse);
      expect(h.server.connects.single.headers, {
        'X-Race-Seat': 'AAAAAAAAAAAAAAAAAAAAAA',
      });
      expect(race.socket.sentTypes, ['join', 'ping']);
      expect(race.socket.sentJson.first['name'], 'Magnus');
      expect(race.state.link, RaceLinkStatus.open);

      race.socket.push(snapshot());
      await settle();
      // Solo starts itself after its own 3-2-1.
      expect(race.socket.sentTypes.last, 'start');
      expect(race.state.phase, RacePhase.countdown);

      race.socket.push(snapshot(state: 'running', startedAt: 1790000000000));
      await settle();
      expect(race.state.phase, RacePhase.running);
      expect(h.audio.calls, contains('go'));
      expect(race.state.livesLeft, 3);

      race.socket.push(puzzle());
      await settle();
      expect(race.state.puzzle!.index, 0);
      expect(race.state.puzzle!.rating, 812);

      // Right: the room says so, the next puzzle follows.
      expect(race.controller.submitMove('a1a8'), isTrue);
      expect(race.state.awaitingVerdict, isTrue);
      // One move at a time.
      expect(race.controller.submitMove('b1b8'), isFalse);
      expect(race.socket.sentJson.last, {
        'type': 'move',
        'puzzleIndex': 0,
        'uci': 'a1a8',
        'ply': 1,
      });
      race.socket.push(verdict(score: 1, level: 1, elapsedMs: 4200));
      race.socket.push(puzzle(index: 1, rating: 851, level: 1));
      await settle();
      expect(race.state.score, 1);
      expect(race.state.streak, 1);
      expect(race.state.records.single.solved, isTrue);
      expect(race.state.records.single.timeMs, 4200);
      expect(race.state.lastMove!.correct, isTrue);
      expect(race.state.lastMove!.complete, isTrue);
      expect(race.state.puzzle!.index, 1);
      expect(h.audio.calls, contains('correct1'));

      // Three wrong answers end a Survival run.
      for (var i = 1; i <= 3; i++) {
        expect(race.controller.submitMove('b1b7'), isTrue);
        race.socket.push(
          verdict(
            index: i,
            correct: false,
            score: 1,
            mistakes: i,
            level: 1,
            elapsedMs: 4200 + i * 3000,
          ),
        );
        if (i < 3) race.socket.push(puzzle(index: i + 1, level: 1));
        await settle();
        expect(race.state.mistakes, i);
        expect(race.state.livesLeft, 3 - i);
        expect(race.state.streak, 0);
      }
      expect(h.audio.calls.where((c) => c == 'wrong'), hasLength(3));
      expect(h.audio.calls.where((c) => c == 'lastLife'), hasLength(1));
      // The missed puzzle keeps the wrong move for its final board.
      expect(race.state.records[1].finalLine, ['b1b7']);
      expect(race.state.records[1].solution, ['a1a8']);

      race.socket.push(
        finished(
          results: [
            result(
              score: 1,
              mistakes: 3,
              level: 1,
              elapsedMs: 13200,
              finishReason: 'lives',
            ),
          ],
        ),
      );
      await race.socket.drop(1000);
      await settle();
      final s = race.state;
      expect(s.phase, RacePhase.finished);
      expect(s.finishReason, RaceFinishReason.lives);
      // The last miss is still to be seen before the results.
      expect(s.endedOnVerdict, isTrue);
      expect(s.finalElapsedMs, 13200);
      expect(s.accuracy, closeTo(0.25, 0.001));
      expect(s.bestStreak, 1);
      // A clean close after the finish is not an error.
      expect(s.errorCode, isNull);

      // Personal bests are written once.
      expect(h.stats.recorded, hasLength(1));
      expect(h.stats.recorded.single.mode, RaceMode.survival);
      expect(h.stats.recorded.single.score, 1);
      expect(h.stats.recorded.single.bestStreak, 1);
      expect(s.newBest, isTrue);
      expect(h.audio.calls, contains('finishBest'));
    });

    test('a multi-move line: reply, then the next ply', () async {
      final h = RaceHarness();
      final race = _Race(h);
      addTearDown(race.dispose);
      await race.startSoloRunning();

      race.controller.submitMove('a1a7');
      race.socket.push(
        verdict(
          complete: false,
          expectedReply: 'h8g8',
          nextPly: 3,
          score: 0,
          level: 0,
        ),
      );
      await settle();
      expect(race.state.ply, 3);
      expect(race.state.lastMove!.reply, 'h8g8');
      expect(race.state.lastMove!.uci, 'a1a7');
      expect(race.state.lastMove!.complete, isFalse);
      expect(race.state.records, isEmpty);
      // Mid-line is not a solve: no stinger yet.
      expect(h.audio.calls, isNot(contains('correct1')));

      race.controller.submitMove('b1b8');
      expect(race.socket.sentJson.last['ply'], 3);
    });

    test('infinite never runs out of lives', () async {
      final h = RaceHarness();
      final race = _Race(h);
      addTearDown(race.dispose);
      await race.startSoloRunning(mode: RaceMode.infinite);
      expect(race.state.startLives, isNull);
      for (var i = 0; i < 5; i++) {
        race.controller.submitMove('b1b7');
        race.socket.push(
          verdict(index: i, correct: false, score: 0, mistakes: i + 1),
        );
        race.socket.push(puzzle(index: i + 1));
        await settle();
      }
      expect(race.state.phase, RacePhase.running);
      expect(race.state.livesLeft, isNull);
      expect(h.audio.calls, isNot(contains('lastLife')));
    });

    test('level-ups every three solves', () async {
      final h = RaceHarness();
      final race = _Race(h);
      addTearDown(race.dispose);
      await race.startSoloRunning();
      for (var i = 0; i < 3; i++) {
        race.controller.submitMove('a1a8');
        race.socket.push(verdict(index: i, score: i + 1, level: i + 1));
        race.socket.push(puzzle(index: i + 1, level: i + 1));
        await settle();
      }
      expect(race.state.displayLevel, 2);
      expect(race.state.levelUpSeq, 1);
      expect(h.audio.calls.where((c) => c == 'levelUp'), hasLength(1));
      expect(race.state.streak, 3);
    });

    test('stop ends the run through the room', () async {
      final h = RaceHarness();
      final race = _Race(h);
      addTearDown(race.dispose);
      await race.startSoloRunning();

      race.controller.stop();
      expect(race.socket.sentTypes.last, 'stop');
      race.socket.push(
        finished(
          results: [result(score: 0, elapsedMs: 2500, finishReason: 'stopped')],
        ),
      );
      await settle();
      expect(race.state.phase, RacePhase.finished);
      expect(race.state.finishReason, RaceFinishReason.stopped);
      expect(race.state.endedOnVerdict, isFalse);
      expect(race.state.finalElapsedMs, 2500);
      // Zero is never a best.
      expect(race.state.newBest, isFalse);
    });

    test('reconnects with the same seat and resumes the puzzle', () async {
      final h = RaceHarness();
      final race = _Race(h);
      addTearDown(race.dispose);
      await race.startSoloRunning();
      final first = race.socket;

      // A move goes out; the network drops before the verdict.
      race.controller.submitMove('a1a8');
      await first.drop(1006);
      await settle();
      expect(h.server.connects, hasLength(2));
      expect(h.server.connects.last.headers, {
        'X-Race-Seat': 'AAAAAAAAAAAAAAAAAAAAAA',
      });
      final second = race.socket;
      expect(identical(first, second), isFalse);
      // The resume starts with `join`.
      expect(second.sentTypes.first, 'join');
      expect(race.state.link, RaceLinkStatus.open);

      // The room never got the move: same puzzle, same ply.
      second.push(snapshot(state: 'running', startedAt: 1790000000000));
      second.push(puzzle());
      await settle();
      expect(race.state.phase, RacePhase.running);
      expect(race.state.awaitingVerdict, isFalse);
      expect(race.state.puzzle!.revision, 1);
      expect(race.controller.submitMove('a1a8'), isTrue);
    });

    test('a replaced connection is not reconnected', () async {
      final h = RaceHarness();
      final race = _Race(h);
      addTearDown(race.dispose);
      await race.startSoloRunning();
      // A life lost: the heartbeat bed is up.
      race.controller.submitMove('b1b7');
      race.socket.push(verdict(correct: false, score: 0, mistakes: 1));
      race.socket.push(puzzle(index: 1));
      await settle();
      expect(h.audio.calls.last, 'tension0.15');
      await race.socket.drop(4001);
      await settle();
      expect(h.server.connects, hasLength(1));
      expect(race.state.phase, RacePhase.failed);
      expect(race.state.errorCode, 'replaced');
      // The race's sound ends with it, not on the setup screen after.
      final after = h.audio.calls.skipWhile((c) => c != 'tension0.15').skip(1);
      expect(after, containsAllInOrder(['tension0.00', 'stopAll']));
    });

    test('losing the room for good ends the run on the last figures', () async {
      final h = RaceHarness();
      final race = _Race(h);
      addTearDown(race.dispose);
      await race.startSoloRunning();
      race.controller.submitMove('a1a8');
      race.socket.push(verdict(score: 1, level: 1, elapsedMs: 3000));
      race.socket.push(puzzle(index: 1));
      await settle();
      h.server.failures.addAll(const [
        RaceApiException('network'),
        RaceApiException('network'),
        RaceApiException('network'),
        RaceApiException('network'),
      ]);
      await race.socket.drop(1006);
      await settle();
      // The room is asked for its standings; it cannot be read, so the last
      // figures stand, marked as unconfirmed rather than as a stop.
      expect(h.api.resultsRequests, ['7KQ2MX']);
      expect(race.state.phase, RacePhase.finished);
      expect(race.state.unconfirmed, isTrue);
      expect(race.state.finishReason, isNull);
      expect(race.state.score, 1);
      expect(race.state.finalElapsedMs, 3000);
      expect(h.stats.recorded, hasLength(1));
    });

    test('stale moves are taken back and the room is asked again', () async {
      final h = RaceHarness();
      final race = _Race(h);
      addTearDown(race.dispose);
      await race.startSoloRunning();
      race.controller.submitMove('a1a8');
      race.socket.push({
        'type': 'error',
        'code': 'stale',
        'expectedIndex': 0,
        'expectedPly': 1,
      });
      await settle();
      expect(race.state.awaitingVerdict, isFalse);
      expect(race.state.lastReject!.index, 0);
      expect(race.socket.sentTypes.last, 'join');
    });

    test('puzzle source down at the start: failed, then retry', () async {
      final h = RaceHarness();
      final race = _Race(h);
      addTearDown(race.dispose);
      await race.controller.startSolo();
      await settle();
      race.socket.push(snapshot());
      await settle();
      expect(race.socket.sentTypes.last, 'start');
      race.socket.push({'type': 'error', 'code': 'puzzle_source_unavailable'});
      race.socket.push(snapshot());
      await settle();
      expect(race.state.phase, RacePhase.failed);
      expect(race.state.errorCode, 'puzzle_source_unavailable');

      await race.controller.retry();
      await settle();
      // Still in the same room: only a new start.
      expect(h.api.creates, hasLength(1));
      expect(race.socket.sentTypes.where((t) => t == 'start'), hasLength(2));
    });

    test('a stale token falls back to a guest seat for solo', () async {
      final h = RaceHarness(token: 'expired');
      h.api.failures.add(
        const RaceApiException('invalid_token', statusCode: 401),
      );
      final race = _Race(h);
      addTearDown(race.dispose);
      await race.controller.startSolo();
      await settle();
      expect(h.api.creates.map((c) => c.token), ['expired', null]);
      expect(h.server.connects.single.headers.keys, ['X-Race-Seat']);
    });

    test(
      'a move left unanswered resumes instead of locking the board',
      () async {
        final h = RaceHarness();
        final race = _Race(h, replyTimeout: const Duration(milliseconds: 30));
        addTearDown(race.dispose);
        await race.startSoloRunning();
        final first = race.socket;
        expect(race.controller.submitMove('a1a8'), isTrue);
        expect(race.state.awaitingVerdict, isTrue);
        // Half-open: the socket reads open, but no verdict ever comes back.
        await Future<void>.delayed(const Duration(milliseconds: 120));
        await settle();
        expect(first.closeCode, RaceConnection.silentCloseCode);
        expect(h.server.connects, hasLength(2));
        final second = race.socket;
        expect(second.sentTypes.first, 'join');
        second.push(snapshot(state: 'running', startedAt: 1790000000000));
        second.push(puzzle());
        await settle();
        expect(race.state.phase, RacePhase.running);
        expect(race.state.awaitingVerdict, isFalse);
        expect(race.controller.submitMove('a1a8'), isTrue);
      },
    );

    test(
      'tokens near expiry wait for the refresh; a resumed 401 retries',
      () async {
        final auth = FakeRefreshingRaceAuth(
          accessToken: 'stale',
          displayName: 'Magnus',
          fresh: ['fresh1', 'fresh1', 'fresh2', 'fresh3'],
        );
        final h = RaceHarness(auth: auth);
        final race = _Race(h);
        addTearDown(race.dispose);
        await race.controller.createRoom();
        await settle();
        // The room is created and joined with the refreshed token.
        expect(h.api.creates.single.token, 'fresh1');
        expect(h.server.connects.single.headers, {
          'Authorization': 'Bearer fresh1',
        });
        race.socket.push(snapshot(multiplayer: true));
        await settle();
        expect(race.state.phase, RacePhase.lobby);

        // Back from the background: the first try beats the refresh.
        h.server.failures.add(
          const RaceApiException('authentication_required', statusCode: 401),
        );
        await race.socket.drop(1006);
        await settle();
        expect(
          h.server.connects.skip(1).map((c) => c.headers['Authorization']),
          ['Bearer fresh2', 'Bearer fresh3'],
        );
        expect(race.state.link, RaceLinkStatus.open);
        expect(race.state.phase, RacePhase.lobby);
        expect(race.state.notice, isNull);
      },
    );

    test('the clock offset comes from the room', () async {
      final h = RaceHarness();
      final race = _Race(h);
      addTearDown(race.dispose);
      await race.controller.startSolo();
      await settle();
      final sentAt = race.socket.sentJson[1]['t']! as int;
      // The room's clock runs 5s ahead; a 100ms round trip.
      h.clock = sentAt + 100;
      race.socket.push({
        'type': 'pong',
        'serverNow': sentAt + 50 + 5000,
        't': sentAt,
      });
      await settle();
      expect(race.state.clockOffsetMs, 5000);
      race.socket.push(
        snapshot(state: 'running', startedAt: h.clock + 5000 - 1000),
      );
      await settle();
      expect(race.state.elapsedAt(h.clock), 1000);
      expect(race.state.elapsedAt(h.clock + 2500), 3500);
    });
  });

  group('multiplayer', () {
    test('needs an account', () async {
      final h = RaceHarness();
      final race = _Race(h);
      addTearDown(race.dispose);
      await race.controller.createRoom();
      expect(h.api.creates, isEmpty);
      expect(race.state.notice!.code, 'authentication_required');
      await race.controller.joinRoom('7KQ2MX');
      expect(h.server.connects, isEmpty);
    });

    test('host lobby, countdown, running, live opponents', () async {
      final h = RaceHarness(token: 'jwt');
      final race = _Race(h);
      addTearDown(race.dispose);
      await race.controller.createRoom();
      await settle();
      expect(h.api.creates.single.multiplayer, isTrue);
      expect(h.api.creates.single.token, 'jwt');
      expect(h.server.connects.single.headers, {'Authorization': 'Bearer jwt'});

      race.socket.push(
        snapshot(
          multiplayer: true,
          players: [
            player(),
            player(id: kRival, name: 'Hikaru', ready: true),
          ],
        ),
      );
      await settle();
      expect(race.state.phase, RacePhase.lobby);
      expect(race.state.isHost, isTrue);
      expect(race.state.opponents.single.name, 'Hikaru');
      // A room never starts itself.
      expect(race.socket.sentTypes, isNot(contains('start')));

      race.controller.startRace();
      expect(race.socket.sentTypes.last, 'start');
      race.socket.push(
        snapshot(
          multiplayer: true,
          state: 'countdown',
          countdownEndsAt: 1790000003000,
          players: [
            player(),
            player(id: kRival, name: 'Hikaru'),
          ],
        ),
      );
      await settle();
      expect(race.state.phase, RacePhase.countdown);
      expect(race.state.countdownLeftAt(h.clock), 3000);

      race.socket.push(
        snapshot(
          multiplayer: true,
          state: 'running',
          startedAt: 1790000003000,
          players: [
            player(),
            player(id: kRival, name: 'Hikaru', score: 2, mistakes: 1),
          ],
        ),
      );
      race.socket.push(puzzle());
      await settle();
      expect(race.state.phase, RacePhase.running);
      expect(race.state.opponents.single.score, 2);
      expect(race.state.countdownEndsAt, isNull);

      // My run ends while Hikaru races on; standings keep updating.
      race.socket.push(
        finished(
          playerId: kYou,
          reason: 'stopped',
          roomFinished: false,
          results: [
            result(id: kRival, name: 'Hikaru', score: 2, finished: false),
            result(rank: 2, score: 0, finishReason: 'stopped', elapsedMs: 900),
          ],
        ),
      );
      await settle();
      expect(race.state.phase, RacePhase.finished);
      expect(race.state.roomFinished, isFalse);
      expect(race.state.myResult!.rank, 2);
      race.socket.push(
        snapshot(
          multiplayer: true,
          state: 'running',
          startedAt: 1790000003000,
          players: [
            player(finished: true),
            player(id: kRival, name: 'Hikaru', score: 5),
          ],
        ),
      );
      await settle();
      expect(race.state.phase, RacePhase.finished);
      expect(race.state.opponents.single.score, 5);
      race.socket.push(finished(roomFinished: true));
      await settle();
      expect(race.state.roomFinished, isTrue);
    });

    test('joining: bad codes and refusals are calm', () async {
      final h = RaceHarness(token: 'jwt');
      final race = _Race(h);
      addTearDown(race.dispose);
      await race.controller.joinRoom('7KQ');
      expect(race.state.notice!.code, 'invalid_code');
      expect(h.server.connects, isEmpty);

      h.server.failures.add(
        const RaceApiException('room_not_found', statusCode: 404),
      );
      await race.controller.joinRoom('7kq-2mx');
      await settle();
      expect(h.server.connects.single.uri.path, '/v1/races/7KQ2MX/ws');
      expect(race.state.phase, RacePhase.failed);
      expect(race.state.errorCode, 'room_not_found');

      // The room's first snapshot already names `you`, before `join` seats
      // anyone; the last seat going to someone else must still fail the join.
      race.controller.backToSetup();
      await race.controller.joinRoom('7KQ2MX');
      await settle();
      race.socket.push(
        snapshot(
          multiplayer: true,
          hostId: kRival,
          players: [player(id: kRival, name: 'Hikaru')],
        ),
      );
      await settle();
      expect(race.state.phase, RacePhase.lobby);
      race.socket.push({'type': 'error', 'code': 'room_full'});
      await settle();
      expect(race.state.phase, RacePhase.failed);
      expect(race.state.errorCode, 'room_full');
    });

    test('leaving a lobby frees the seat', () async {
      final h = RaceHarness(token: 'jwt');
      final race = _Race(h);
      addTearDown(race.dispose);
      await race.controller.joinRoom('7KQ2MX');
      await settle();
      race.socket.push(
        snapshot(
          multiplayer: true,
          hostId: kRival,
          players: [
            player(id: kRival, name: 'Hikaru'),
            player(),
          ],
        ),
      );
      await settle();
      expect(race.state.isHost, isFalse);
      race.controller.setReady(true);
      expect(race.socket.sentJson.last, {'type': 'ready', 'ready': true});
      final socket = race.socket;
      race.controller.leave();
      await settle();
      expect(socket.sentTypes.last, 'stop');
      expect(socket.closedByApp, isTrue);
      expect(race.state.phase, RacePhase.setup);
      expect(race.state.multiplayer, isTrue);
    });
  });

  group('board Sound setting', () {
    test('Feed never built, Sound on: stingers and moves sound', () async {
      // The Feed provider never ran, so its mirror of the setting is off.
      expect(FeedSfx.instance.boardSoundEnabled, isFalse);
      final race = _SoundedRace(RaceHarness());
      addTearDown(race.dispose);
      // Unbound, the race would have borrowed that mirror and stayed silent.
      expect(race.sfx.boardSoundEnabled, isFalse);

      await race.startRunning();
      expect(race.sfx.boardSoundEnabled, isTrue);
      race.boardMove('Kh8');

      expect(race.controller.submitMove('a1a8'), isTrue);
      race.socket.push(verdict(score: 1, level: 1));
      race.socket.push(puzzle(index: 1, level: 1));
      await settle();
      race.boardMove('Ra8#');

      expect(race.controller.submitMove('b1b7'), isTrue);
      race.socket.push(
        verdict(index: 1, correct: false, score: 1, mistakes: 1, level: 1),
      );
      race.socket.push(puzzle(index: 2, level: 1));
      await settle();

      expect(
        race.stingers.played,
        containsAll(<SfxType>[
          SfxType.raceGo,
          SfxType.raceCorrect,
          SfxType.raceWrong,
        ]),
      );
      expect(race.stingers.started, hasLength(1), reason: 'the tension bed');
      expect(race.moves.played, [SfxType.move, SfxType.checkmate]);
    });

    test('turning Sound off mid-race silences stingers and moves', () async {
      final race = _SoundedRace(RaceHarness());
      addTearDown(race.dispose);
      await race.startRunning();
      expect(race.stingers.played, contains(SfxType.raceGo));

      race.setSound(false);
      await settle();
      expect(race.sfx.boardSoundEnabled, isFalse);
      final before = race.stingers.played.length;

      race.boardMove('Kh8');
      expect(race.controller.submitMove('a1a8'), isTrue);
      race.socket.push(verdict(score: 1, level: 1));
      race.socket.push(puzzle(index: 1, level: 1));
      await settle();

      expect(race.stingers.played, hasLength(before));
      expect(race.moves.played, isEmpty);

      race.setSound(true);
      await settle();
      race.boardMove('Ra8#');
      expect(race.moves.played, [SfxType.checkmate]);
    });
  });

  group('ending cleanly when the link does not', () {
    test('stop while reconnecting goes out first on the next open', () async {
      final h = RaceHarness();
      final race = _Race(h, backoff: const [Duration(milliseconds: 40)]);
      addTearDown(race.dispose);
      await race.startSoloRunning();
      await race.socket.drop(1006);
      await settle();
      expect(race.state.link, RaceLinkStatus.reconnecting);

      race.controller.stop();
      // Not ended on this device: the room still has to hear it.
      expect(race.state.phase, RacePhase.running);
      expect(race.state.notice!.code, 'stop_queued');
      expect(race.controller.submitMove('a1a8'), isFalse);

      await Future<void>.delayed(const Duration(milliseconds: 80));
      await settle();
      expect(h.server.connects, hasLength(2));
      // `stop`, and no `join` to re-send the puzzle.
      expect(race.socket.sentTypes, ['stop', 'ping']);
      race.socket.push(
        finished(
          results: [result(score: 0, elapsedMs: 4100, finishReason: 'stopped')],
        ),
      );
      await settle();
      expect(race.state.phase, RacePhase.finished);
      expect(race.state.finishReason, RaceFinishReason.stopped);
      expect(race.state.finalElapsedMs, 4100);
      expect(race.state.unconfirmed, isFalse);
    });

    test('leaving mid-reconnect hands the stop to the link', () async {
      final h = RaceHarness();
      final race = _Race(h, backoff: const [Duration(milliseconds: 40)]);
      await race.startSoloRunning();
      await race.socket.drop(1006);
      await settle();
      expect(race.state.link, RaceLinkStatus.reconnecting);

      // The player leaves the screen: the controller is disposed.
      race.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 80));
      await settle();
      expect(h.server.connects, hasLength(2));
      expect(race.socket.sentTypes, ['stop']);
      expect(race.socket.closedByApp, isTrue);
    });

    test(
      'a room that finished meanwhile answers with its own results',
      () async {
        final h = RaceHarness();
        final race = _Race(h);
        addTearDown(race.dispose);
        await race.startSoloRunning();
        race.controller.submitMove('a1a8');
        race.socket.push(verdict(score: 1, level: 1, elapsedMs: 3000));
        race.socket.push(puzzle(index: 1, level: 1));
        await settle();

        // The third miss and the `finished` were lost with the socket; the
        // reconnect finds the room over.
        h.api.summary = RaceRoomSummary.fromJson(
          roomSummary(
            results: [
              result(
                score: 1,
                mistakes: 3,
                level: 1,
                elapsedMs: 42000,
                finishReason: 'lives',
              ),
            ],
          ),
        );
        h.server.failures.add(
          const RaceApiException('race_finished', statusCode: 410),
        );
        await race.socket.drop(1006);
        await settle();

        final s = race.state;
        expect(s.phase, RacePhase.finished);
        expect(s.unconfirmed, isFalse);
        expect(s.finishReason, RaceFinishReason.lives);
        expect(s.mistakes, 3);
        expect(s.finalElapsedMs, 42000);
        expect(s.roomFinished, isTrue);
        expect(h.stats.recorded.single.score, 1);
      },
    );

    test('a run the room still counts keeps its score from the room', () async {
      final h = RaceHarness(token: 'jwt');
      final race = _Race(h);
      addTearDown(race.dispose);
      await race.controller.createRoom();
      await settle();
      final players = [player(), player(id: kRival, name: 'Hikaru')];
      race.socket.push(snapshot(multiplayer: true, players: players));
      await settle();
      race.socket.push(
        snapshot(
          multiplayer: true,
          state: 'running',
          startedAt: 1790000000000,
          players: players,
        ),
      );
      race.socket.push(puzzle());
      await settle();
      race.controller.submitMove('a1a8');
      race.socket.push(verdict(score: 1, level: 1, elapsedMs: 3000));
      race.socket.push(puzzle(index: 1, level: 1));
      await settle();

      // A second solve reached the room; its verdict never came back.
      h.api.summary = RaceRoomSummary.fromJson(
        roomSummary(
          state: 'running',
          multiplayer: true,
          results: [
            result(score: 2, level: 2, elapsedMs: 9000, finished: false),
            result(
              rank: 2,
              id: kRival,
              name: 'Hikaru',
              score: 1,
              elapsedMs: 9000,
              finished: false,
            ),
          ],
        ),
      );
      h.server.failures.addAll(const [
        RaceApiException('network'),
        RaceApiException('network'),
        RaceApiException('network'),
        RaceApiException('network'),
      ]);
      await race.socket.drop(1006);
      await settle();

      final s = race.state;
      expect(s.phase, RacePhase.finished);
      // The room has not ended the run, so the end stays unconfirmed...
      expect(s.unconfirmed, isTrue);
      // ...but its score and standings are the room's.
      expect(s.score, 2);
      expect(s.results, hasLength(2));
      expect(s.myResult!.finished, isTrue);
      expect(s.myResult!.elapsedMs, 3000);
      expect(h.stats.recorded.single.score, 2);
    });

    test('a move between the two resume copies keeps its verdict', () async {
      final h = RaceHarness();
      final race = _Race(h);
      addTearDown(race.dispose);
      await race.startSoloRunning();
      await race.socket.drop(1006);
      await settle();
      final second = race.socket;
      // The upgrade resumes the seat and re-sends the puzzle...
      second.push(snapshot(state: 'running', startedAt: 1790000000000));
      second.push(puzzle());
      await settle();
      expect(race.state.puzzle!.revision, 0);
      // ...the player moves at once...
      expect(race.controller.submitMove('a1a8'), isTrue);
      // ...and the copy answering `join` lands before the verdict.
      second.push(puzzle());
      await settle();
      expect(race.state.awaitingVerdict, isTrue);
      expect(race.state.puzzle!.revision, 0);
      second.push(verdict(score: 1, level: 1));
      await settle();
      expect(race.state.lastMove!.uci, 'a1a8');
      expect(race.state.records.single.solved, isTrue);
    });

    test('a puzzle source that stays down backs off, tells once, then ends '
        'the run through the room', () async {
      final h = RaceHarness();
      final race = _Race(h);
      addTearDown(race.dispose);
      final notices = <String>[];
      race.container.listen<RaceNotice?>(
        raceControllerProvider.select((s) => s.notice),
        (_, next) {
          if (next != null) notices.add(next.code);
        },
      );
      await race.startSoloRunning();
      race.controller.submitMove('a1a8');
      race.socket.push(verdict(score: 1, level: 1));
      await settle();
      final before = race.socket.sentTypes.length;
      for (var i = 0; i < 6; i++) {
        race.socket.push({
          'type': 'error',
          'code': 'puzzle_source_unavailable',
        });
        await settle();
      }
      final sent = race.socket.sentTypes.skip(before).toList();
      expect(sent.where((t) => t == 'join'), hasLength(5));
      expect(sent.last, 'stop');
      expect(notices, ['puzzle_source_unavailable', 'puzzle_source_gave_up']);
      race.socket.push(
        finished(results: [result(score: 1, finishReason: 'stopped')]),
      );
      await settle();
      expect(race.state.phase, RacePhase.finished);
      expect(race.state.score, 1);
    });

    test('a puzzle arriving ends the outage', () async {
      final h = RaceHarness();
      final race = _Race(h);
      addTearDown(race.dispose);
      final notices = <String>[];
      race.container.listen<RaceNotice?>(
        raceControllerProvider.select((s) => s.notice),
        (_, next) {
          if (next != null) notices.add(next.code);
        },
      );
      await race.startSoloRunning();
      for (var round = 0; round < 2; round++) {
        for (var i = 0; i < 5; i++) {
          race.socket.push({
            'type': 'error',
            'code': 'puzzle_source_unavailable',
          });
          await settle();
        }
        race.socket.push(puzzle(index: round + 1));
        await settle();
      }
      // Two outages, each told once; neither reached the limit.
      expect(notices, [
        'puzzle_source_unavailable',
        'puzzle_source_unavailable',
      ]);
      expect(race.socket.sentTypes, isNot(contains('stop')));
      expect(race.state.phase, RacePhase.running);
    });

    test('a room that refused this player does not carry them into its '
        'race', () async {
      final h = RaceHarness(token: 'jwt');
      final race = _Race(h);
      addTearDown(race.dispose);
      await race.controller.joinRoom('7KQ2MX');
      await settle();
      final socket = race.socket;
      socket.push(
        snapshot(
          multiplayer: true,
          hostId: kRival,
          players: [player(id: kRival, name: 'Hikaru')],
        ),
      );
      await settle();
      socket.push({'type': 'error', 'code': 'already_started'});
      await settle();
      expect(race.state.phase, RacePhase.failed);
      expect(race.state.errorCode, 'already_started');
      expect(socket.closedByApp, isTrue);
      expect(race.state.link, isNot(RaceLinkStatus.open));
    });

    test('a failure waiting on "Try again" ignores the room', () async {
      final h = RaceHarness();
      final race = _Race(h);
      addTearDown(race.dispose);
      await race.controller.startSolo();
      await settle();
      race.socket.push(snapshot());
      await settle();
      race.socket.push({'type': 'error', 'code': 'puzzle_source_unavailable'});
      await settle();
      expect(race.state.phase, RacePhase.failed);
      race.socket.push(snapshot(state: 'running', startedAt: 1790000000000));
      race.socket.push(puzzle());
      await settle();
      expect(race.state.phase, RacePhase.failed);
      expect(race.state.puzzle, isNull);
    });

    test('joining a finished room says it finished', () async {
      final h = RaceHarness(token: 'jwt');
      final race = _Race(h);
      addTearDown(race.dispose);
      h.server.failures.add(
        const RaceApiException('race_finished', statusCode: 410),
      );
      await race.controller.joinRoom('7KQ2MX');
      await settle();
      expect(race.state.phase, RacePhase.failed);
      expect(race.state.errorCode, 'race_finished');
    });

    test('a host whose lobby link died goes back into the same room', () async {
      final h = RaceHarness(token: 'jwt');
      final race = _Race(h);
      addTearDown(race.dispose);
      await race.controller.createRoom();
      await settle();
      race.socket.push(
        snapshot(
          multiplayer: true,
          players: [
            player(),
            player(id: kRival, name: 'Hikaru'),
          ],
        ),
      );
      await settle();
      expect(race.state.isHost, isTrue);
      h.server.failures.addAll(const [
        RaceApiException('network'),
        RaceApiException('network'),
        RaceApiException('network'),
        RaceApiException('network'),
      ]);
      await race.socket.drop(1006);
      await settle();
      expect(race.state.phase, RacePhase.failed);
      expect(race.state.errorCode, 'connection_lost');

      h.server.failures.clear();
      await race.controller.retry();
      await settle();
      // The same code, not a new room the friends never heard of.
      expect(h.api.creates, hasLength(1));
      expect(h.server.connects.last.uri.path, '/v1/races/7KQ2MX/ws');
      expect(race.state.code, '7KQ2MX');
      expect(race.socket.sentTypes.first, 'join');

      // A room that is gone by then: a new one after all.
      h.server.failures.addAll(const [
        RaceApiException('network'),
        RaceApiException('network'),
        RaceApiException('network'),
        RaceApiException('network'),
      ]);
      race.socket.push(snapshot(multiplayer: true, players: [player()]));
      await settle();
      await race.socket.drop(1006);
      await settle();
      expect(race.state.errorCode, 'connection_lost');
      h.server.failures
        ..clear()
        ..add(const RaceApiException('room_not_found', statusCode: 404));
      await race.controller.retry();
      await settle();
      expect(h.api.creates, hasLength(2));
    });
  });

  test('not configured: nothing is sent', () async {
    final h = RaceHarness(configured: false);
    final race = _Race(h);
    addTearDown(race.dispose);
    await race.controller.startSolo();
    expect(h.api.creates, isEmpty);
    expect(race.state.phase, RacePhase.failed);
    expect(race.state.errorCode, 'not_configured');
  });

  group('difficulty', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('every room starts at the chosen start, the default until one is '
        'chosen, and never carries a ceiling', () async {
      final h = RaceHarness();
      final race = _Race(h);
      addTearDown(race.dispose);

      await race.controller.startSolo();
      await settle();
      expect(h.api.creates.single.minRating, kDefaultPuzzleRatingRange.min);
      // The band's top is the Feed's: a race climbs freely from its start.
      expect(h.api.creates.single.maxRating, isNull);

      race.controller.stop();
      await settle();
      await race.container
          .read(puzzleRatingRangeProvider.notifier)
          .choose(PuzzleRatingPreset.expert);
      race.controller.backToSetup();
      await race.controller.startSolo();
      await settle();
      expect(h.api.creates.last.minRating, 2000);
      expect(h.api.creates.last.maxRating, isNull);
    });

    test('a stale token falls back to a guest seat on the same start', () async {
      SharedPreferences.setMockInitialValues({
        kPuzzleRatingRangePrefsKey: '1500-2000',
      });
      final h = RaceHarness(token: 'expired');
      h.api.failures.add(
        const RaceApiException('invalid_token', statusCode: 401),
      );
      final race = _Race(h);
      addTearDown(race.dispose);
      // The saved range reads in before the first race.
      race.container.read(puzzleRatingRangeProvider);
      await settle();
      await race.controller.startSolo();
      await settle();
      expect(h.api.creates.map((c) => c.token), ['expired', null]);
      expect(h.api.creates.map((c) => c.minRating), [1500, 1500]);
      expect(h.api.creates.map((c) => c.maxRating), [null, null]);
    });

    test('the room says where its ladder runs, and an older room says '
        'nothing', () async {
      final h = RaceHarness();
      final race = _Race(h);
      addTearDown(race.dispose);
      await race.controller.startSolo();
      await settle();
      race.socket.push(snapshot());
      await settle();
      // A room from before difficulty: nothing to claim.
      expect(race.state.startRating, isNull);
      expect(race.state.maxRating, isNull);

      race.socket.push(snapshot(startRating: 1000, maxRating: 1500));
      await settle();
      expect(race.state.startRating, 1000);
      expect(race.state.maxRating, 1500);

      // A later copy without the fields keeps what the room said.
      race.socket.push(snapshot(state: 'running', startedAt: 1790000000000));
      await settle();
      expect(race.state.startRating, 1000);
      expect(race.state.maxRating, 1500);

      // Back to the setup forgets the room.
      race.controller.stop();
      await settle();
      race.controller.backToSetup();
      expect(race.state.startRating, isNull);
      expect(race.state.maxRating, isNull);
    });
  });

  group('flames', () {
    test("the room's count is what the run earned, and what is kept", () async {
      final h = RaceHarness();
      final race = _Race(h);
      addTearDown(race.dispose);
      await race.startSoloRunning();
      race.controller.submitMove('a1a8');
      race.socket.push(verdict(score: 1, level: 1, elapsedMs: 3000));
      race.socket.push(puzzle(index: 1, rating: 1620, level: 1));
      await settle();
      expect(race.state.flamesEarned, isNull);

      race.socket.push(
        finished(
          results: [
            result(
              score: 1,
              mistakes: 3,
              elapsedMs: 9000,
              finishReason: 'lives',
              flames: 7,
            ),
          ],
        ),
      );
      await settle();
      expect(race.state.phase, RacePhase.finished);
      expect(race.state.flamesEarned, 7);
      expect(h.stats.recorded.single.flames, 7);
    });

    test('a room from before flames: the device counts the solves', () async {
      final h = RaceHarness();
      final race = _Race(h);
      addTearDown(race.dispose);
      await race.startSoloRunning();
      // 812 earns 1.
      race.controller.submitMove('a1a8');
      race.socket.push(verdict(score: 1, level: 1, elapsedMs: 3000));
      race.socket.push(puzzle(index: 1, rating: 1620, level: 1));
      await settle();
      // 1620 earns 3.
      race.controller.submitMove('a1a8');
      race.socket.push(
        verdict(index: 1, score: 2, level: 2, elapsedMs: 6000),
      );
      race.socket.push(puzzle(index: 2, rating: 1700, level: 2));
      await settle();
      // A miss earns nothing.
      race.controller.submitMove('b1b7');
      race.socket.push(
        verdict(
          index: 2,
          correct: false,
          score: 2,
          mistakes: 1,
          level: 2,
          elapsedMs: 8000,
        ),
      );
      await settle();

      race.socket.push(
        finished(
          results: [
            result(score: 2, mistakes: 1, elapsedMs: 9000, finishReason: 'stopped'),
          ],
        ),
      );
      await settle();
      expect(race.state.flamesEarned, 4);
      expect(h.stats.recorded.single.flames, 4);
    });

    test('a run the room never confirmed: counted here, then the room '
        'corrects it', () async {
      final h = RaceHarness();
      final race = _Race(h);
      addTearDown(race.dispose);
      await race.startSoloRunning();
      race.controller.submitMove('a1a8');
      race.socket.push(verdict(score: 1, level: 1, elapsedMs: 3000));
      race.socket.push(puzzle(index: 1, rating: 2100, level: 1));
      await settle();

      // The room counted a second solve whose verdict never came back.
      h.api.summary = RaceRoomSummary.fromJson(
        roomSummary(
          results: [
            result(
              score: 2,
              mistakes: 3,
              level: 2,
              elapsedMs: 12000,
              finishReason: 'lives',
              flames: 5,
            ),
          ],
        ),
      );
      h.server.failures.add(
        const RaceApiException('race_finished', statusCode: 410),
      );
      await race.socket.drop(1006);
      await settle();
      expect(race.state.phase, RacePhase.finished);
      expect(race.state.flamesEarned, 5);
      expect(h.stats.recorded.single.flames, 5);
    });

    test('with no answer from the room, the device count stands', () async {
      final h = RaceHarness();
      final race = _Race(h);
      addTearDown(race.dispose);
      await race.startSoloRunning();
      race.controller.submitMove('a1a8');
      race.socket.push(verdict(score: 1, level: 1, elapsedMs: 3000));
      race.socket.push(puzzle(index: 1));
      await settle();
      h.server.failures.addAll(const [
        RaceApiException('network'),
        RaceApiException('network'),
        RaceApiException('network'),
        RaceApiException('network'),
      ]);
      await race.socket.drop(1006);
      await settle();
      expect(race.state.unconfirmed, isTrue);
      expect(race.state.flamesEarned, raceFlamesForRating(812));
      expect(h.stats.recorded.single.flames, 1);
    });
  });
}
