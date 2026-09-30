import 'dart:async';
import 'dart:math' as math;

import 'package:chessever2/screens/feed/audio/feed_sfx.dart';
import 'package:chessever2/utils/audio_player_service.dart';
import 'package:flutter/foundation.dart';

/// Where [RaceSfx] sends its sounds. Production plays through
/// [AudioPlayerService] as layers over the board; tests swap in a recorder
/// via [RaceSfx.forTesting].
abstract interface class RaceSfxOutput {
  /// Loads the race sounds (on demand, never at app start).
  Future<void> warmUp();

  /// One-shot at [volume] (0..1) and [speed] (rate and pitch, 1 = as
  /// recorded). Fire-and-forget.
  void play(SfxType type, {required double volume, required double speed});

  /// Starts [type] looping; null when it could not start.
  Future<SfxVoiceHandle?> startLoop(
    SfxType type, {
    required double volume,
    required double speed,
  });

  /// Glides a loop's volume and/or speed over [over].
  void fadeLoop(
    SfxVoiceHandle voice, {
    double? volume,
    double? speed,
    required Duration over,
  });

  /// Fades a loop out over [fade] and stops it.
  void stopLoop(SfxVoiceHandle voice, {required Duration fade});

  /// Whether a loop voice is still playing (the engine dies when the app
  /// backgrounds, and its voices with it).
  bool isAlive(SfxVoiceHandle voice);
}

class _AudioServiceOutput implements RaceSfxOutput {
  const _AudioServiceOutput();

  AudioPlayerService get _audio => AudioPlayerService.instance;

  @override
  Future<void> warmUp() => _audio.loadRaceAssets();

  @override
  void play(SfxType type, {required double volume, required double speed}) =>
      _audio.playOverlay(type, volume: volume, speed: speed);

  @override
  Future<SfxVoiceHandle?> startLoop(
    SfxType type, {
    required double volume,
    required double speed,
  }) => _audio.startLoop(type, volume: volume, speed: speed);

  @override
  void fadeLoop(
    SfxVoiceHandle voice, {
    double? volume,
    double? speed,
    required Duration over,
  }) => _audio.fadeVoice(voice, volume: volume, speed: speed, over: over);

  @override
  void stopLoop(SfxVoiceHandle voice, {required Duration fade}) =>
      _audio.stopVoice(voice, fade: fade);

  @override
  bool isAlive(SfxVoiceHandle voice) => _audio.isVoiceAlive(voice);
}

/// Puzzle Race sound design: ElevenLabs stingers that build pressure and
/// reward, separate from the board's move sounds (`assets/sfx/race_*.mp3`,
/// made by `tool/generate_race_sfx.py`).
///
/// One family with the board's wood and the classification set's felt and
/// glass: low wooden ticks count down, GO is the same wood struck bright, a
/// glass blip rewards a solve (the streak version is that blip layered a
/// fifth and an octave up, and climbs a step per further solve), a dull
/// buzz-thud marks a miss, and a heartbeat made of the countdown's wood runs
/// under the race, louder and faster as [setTension] rises.
///
/// Every call is fire-and-forget: it never awaits, queues or throws, and a
/// sound failure never reaches the race. Everything is silent while [muted]
/// or while the board's Sound setting is off ([boardSoundEnabled], which the
/// race mirrors itself rather than borrowing the Feed's copy).
///
/// Two sounds raised together are staggered so both read: a level-up lands
/// just after its solve's blip, the last-life heartbeat and a run-ending
/// finish just after the miss, the new-best flourish on the finish hit's
/// ring. These are short delays, not a queue; [stopAll] cancels them.
///
/// The tension bed is one looping voice at most, ever: a new intensity glides
/// the live voice (volume and heart rate), dropping to zero fades it out and
/// stops it, and a start still loading is adopted or stopped when it lands,
/// never doubled. The engine drops its voices when the app backgrounds; the
/// next race call (a solve, a miss, a tension change) restarts the bed.
///
/// Call [stopAll] when leaving the race.
class RaceSfx {
  RaceSfx._() : _output = const _AudioServiceOutput(), _now = _clockMs;

  static final RaceSfx instance = RaceSfx._();

  /// An instance over [sink] (a recorder), with the board's Sound setting
  /// taken as [boardSound] and time read from [nowMs]. A null [boardSound]
  /// leaves the setting unset, as production starts: the Feed's mirror
  /// stands in until the race binds its own ([boardSoundEnabled]).
  @visibleForTesting
  RaceSfx.forTesting({
    required RaceSfxOutput sink,
    bool? boardSound = true,
    int Function()? nowMs,
  }) : _output = sink,
       _boardSoundEnabled = boardSound,
       _now = nowMs ?? _clockMs;

  static final Stopwatch _clock = Stopwatch()..start();
  static int _clockMs() => _clock.elapsedMilliseconds;

  /// The same stinger asked for twice inside this window (a rebuild, two
  /// listeners on one event) plays once.
  static const Duration echoWindow = Duration(milliseconds: 80);

  /// A race ends once: a second finish inside this window (a plain one, then
  /// the one that knows about the best) does not strike the hit again.
  static const Duration finishWindow = Duration(seconds: 3);

  /// A level-up raised with its solve lands this long after the blip.
  static const Duration levelUpAfterCorrect = Duration(milliseconds: 170);

  /// The last-life heartbeat lands this long after the miss that caused it.
  static const Duration lastLifeAfterWrong = Duration(milliseconds: 260);

  /// A finish raised by the miss that ended the run lands this long after
  /// the miss, so the buzz is heard before the hit resolves it.
  static const Duration finishAfterWrong = Duration(milliseconds: 220);

  /// The new-best flourish lands on the finish hit's ring.
  static const Duration newBestAfterFinish = Duration(milliseconds: 380);

  /// A tension change glides the bed over this long.
  static const Duration tensionGlide = Duration(milliseconds: 900);

  /// A starting bed breathes in over this long.
  static const Duration bedFadeIn = Duration(milliseconds: 1200);

  /// Tension dropping to zero, or a mute, breathes the bed out over this.
  static const Duration bedFadeOut = Duration(milliseconds: 700);

  /// The bed's fade under the finish hit.
  static const Duration bedFinishFade = Duration(milliseconds: 450);

  /// The bed's fade when leaving the race.
  static const Duration bedStopFade = Duration(milliseconds: 160);

  /// Semitone steps of the streak sound for streaks 3, 4, 5 and 6+.
  static const List<int> streakSteps = [0, 2, 4, 5];

  /// Bed volume at the lowest non-zero tension and at full tension.
  static const double bedFloor = 0.08;
  static const double bedCeiling = 0.6;

  /// Heart rate at full tension, relative to the loop's 75 bpm (~84 bpm).
  static const double bedTopSpeed = 1.12;

  final RaceSfxOutput _output;
  final int Function() _now;

  bool _muted = false;
  bool? _boardSoundEnabled;

  double _tension = 0;
  SfxVoiceHandle? _bed;
  bool _bedStarting = false;
  Timer? _bedRelease;

  final Map<String, int> _lastPlayedMs = <String, int>{};
  int? _lastCorrectMs;
  int? _lastWrongMs;
  final Set<Timer> _pending = <Timer>{};
  Future<void>? _warming;

  /// Mutes/unmutes the race (the race follows the Feed's speaker toggle).
  /// Muting cancels staggered stingers and breathes the bed out; unmuting
  /// brings it back at the current tension.
  bool get muted => _muted;
  set muted(bool value) {
    if (_muted == value) return;
    _muted = value;
    if (value) _cancelPending();
    _applyTension();
  }

  /// The board's Sound setting (`BoardSettingsNew.soundEnabled`), read the
  /// way the board and Feed read it: off while loading or failed.
  ///
  /// The race mirrors it itself ([followBoardSettings], bound by
  /// `raceAudioProvider` on every settings emission), so a race opened from
  /// My Profile before the Feed tab was ever built still sounds. Only until
  /// that first emission lands does the Feed's mirror
  /// ([FeedSfx.boardSoundEnabled]) stand in; it starts off and is kept in
  /// step only once the Feed provider has been built.
  bool get boardSoundEnabled =>
      _boardSoundEnabled ?? FeedSfx.instance.boardSoundEnabled;
  set boardSoundEnabled(bool value) {
    final before = boardSoundEnabled;
    _boardSoundEnabled = value;
    if (before == value) return;
    if (!value) _cancelPending();
    _applyTension();
  }

  /// Takes one board-settings emission: [soundEnabled] is the loaded
  /// settings' Sound flag, null while they load or after they failed, which
  /// reads as off exactly like the board and Feed.
  void followBoardSettings(bool? soundEnabled) =>
      boardSoundEnabled = soundEnabled == true;

  bool get _silent => _muted || !boardSoundEnabled;

  /// The bed's intensity as last set (0..1, in 0.01 steps).
  @visibleForTesting
  double get tension => _tension;

  /// Loads the race sounds on demand (first race), never at app start.
  /// Idempotent and cheap to repeat.
  Future<void> warmUp() => _warming ??= _output
      .warmUp()
      .catchError((Object error) {
        debugPrint('[RaceSfx] warm-up failed: $error');
      })
      .whenComplete(() => _warming = null);

  /// 3-2-1 before the clock starts (call once per beat, [n] = 3, 2, 1). The
  /// "1" sits a semitone above the others, leaning into the start.
  void countdownBeat(int n) {
    if (n < 1) return;
    _play(
      SfxType.raceCountdownBeat,
      key: 'beat$n',
      speed: n == 1 ? _semitones(1) : 1,
    );
  }

  /// The clock starts.
  void go() => _play(SfxType.raceGo);

  /// Correct answer; [streak] >= 3 escalates the sound: the layered streak
  /// blip, a step higher for each further solve up to a fourth.
  void correct({int streak = 0}) {
    _lastCorrectMs = _now();
    if (streak >= 3) {
      final step = streakSteps[math.min(streak - 3, streakSteps.length - 1)];
      _play(SfxType.raceCorrectStreak, key: 'correct', speed: _semitones(step));
    } else {
      _play(SfxType.raceCorrect, key: 'correct');
    }
    _healBed();
  }

  /// Wrong answer (a life lost in Survival).
  void wrong() {
    _lastWrongMs = _now();
    _play(SfxType.raceWrong);
    _healBed();
  }

  /// Difficulty climbed a step (every few solves). Raised with the solve, it
  /// lands just after the solve's blip.
  void levelUp() =>
      _after(_lastCorrectMs, levelUpAfterCorrect, SfxType.raceLevelUp);

  /// Low, rising pulse under the race; [intensity] 0..1 grows with level and
  /// with lives lost. Idempotent: calling with the same value does nothing.
  void setTension(double intensity) {
    final next = _quantize(intensity);
    if (next == _tension) {
      _healBed();
      return;
    }
    _tension = next;
    _applyTension();
  }

  /// Last life in Survival: one heavier heartbeat, just after the miss.
  void lastLife() =>
      _after(_lastWrongMs, lastLifeAfterWrong, SfxType.raceLastLife);

  /// Race over (stopped, out of lives, or opponent finished). The bed fades
  /// under the finish hit; a [newBest] flourish lands on its ring. A second
  /// call (a plain finish, then the one that knows about the best) plays the
  /// hit once and still adds the flourish.
  void finish({bool newBest = false}) {
    _cancelPending();
    _tension = 0;
    _endBed(bedFinishFade);
    if (_silent) return;
    final hitIn = _remainingMs(_lastWrongMs, finishAfterWrong);
    _at(hitIn, () => _play(SfxType.raceFinish, window: finishWindow));
    if (newBest) {
      _at(
        hitIn + newBestAfterFinish.inMilliseconds,
        () => _play(SfxType.raceNewBest),
      );
    }
  }

  /// Stops any looping/tension sound and pending stinger (leaving the race).
  void stopAll() {
    _cancelPending();
    _tension = 0;
    _endBed(bedStopFade);
  }

  // -------------------------------------------------------------------------
  // One-shots.

  void _play(
    SfxType type, {
    String? key,
    double speed = 1,
    Duration window = echoWindow,
  }) {
    if (_silent) return;
    final echoKey = key ?? type.name;
    final now = _now();
    final last = _lastPlayedMs[echoKey];
    if (last != null && now - last >= 0 && now - last < window.inMilliseconds) {
      return;
    }
    _lastPlayedMs[echoKey] = now;
    _safely(() => _output.play(type, volume: 1, speed: speed));
  }

  /// Plays [type] now, or [gap] after [sinceMs] when that is still ahead.
  void _after(int? sinceMs, Duration gap, SfxType type) {
    if (_silent) return;
    _at(_remainingMs(sinceMs, gap), () => _play(type));
  }

  /// How much of [gap] after [sinceMs] is still ahead (0 when none).
  int _remainingMs(int? sinceMs, Duration gap) {
    if (sinceMs == null) return 0;
    final since = _now() - sinceMs;
    if (since < 0) return 0;
    return math.max(0, gap.inMilliseconds - since);
  }

  /// Runs [call] now, or in [ms] (cancelled by [_cancelPending]).
  void _at(int ms, void Function() call) {
    if (ms <= 0) {
      call();
      return;
    }
    late final Timer timer;
    timer = Timer(Duration(milliseconds: ms), () {
      _pending.remove(timer);
      call();
    });
    _pending.add(timer);
  }

  void _cancelPending() {
    for (final timer in _pending) {
      timer.cancel();
    }
    _pending.clear();
  }

  // -------------------------------------------------------------------------
  // The tension bed: one looping voice at most.

  bool get _wantsBed => !_silent && _tension > 0;

  /// Moves the bed to the current tension (or out, when silent / at zero).
  void _applyTension() {
    if (!_wantsBed) {
      _releaseBed();
      return;
    }
    // Rising again while it breathed out: the same voice comes back (or, if
    // the engine dropped it, a fresh one starts).
    _bedRelease?.cancel();
    _bedRelease = null;
    final bed = _bed;
    if (bed != null && _alive(bed)) {
      _safely(
        () => _output.fadeLoop(
          bed,
          volume: _bedVolume(_tension),
          speed: _bedSpeed(_tension),
          over: tensionGlide,
        ),
      );
      return;
    }
    _bed = null;
    _startBed();
  }

  /// Restarts a bed the engine dropped (backgrounding) or brings back one
  /// that was breathing out, and lets one go that should be silent now (the
  /// board's Sound setting changed under it).
  void _healBed() {
    if (!_wantsBed) {
      _releaseBed();
      return;
    }
    if (_bedStarting) return;
    final bed = _bed;
    if (bed != null && _bedRelease == null && _alive(bed)) return;
    _applyTension();
  }

  void _startBed() {
    // A start in flight picks up the latest tension when it lands.
    if (_bedStarting) return;
    _bedStarting = true;
    final Future<SfxVoiceHandle?> starting;
    try {
      starting = _output.startLoop(
        SfxType.raceTensionLoop,
        volume: 0,
        speed: _bedSpeed(_tension),
      );
    } catch (error) {
      _bedStarting = false;
      debugPrint('[RaceSfx] bed failed to start: $error');
      return;
    }
    unawaited(
      starting.then(
        (voice) {
          _bedStarting = false;
          if (voice == null) return;
          if (!_wantsBed || _bed != null) {
            // Stopped, muted or finished while it loaded.
            _safely(() => _output.stopLoop(voice, fade: Duration.zero));
            return;
          }
          _bed = voice;
          _safely(
            () => _output.fadeLoop(
              voice,
              volume: _bedVolume(_tension),
              speed: _bedSpeed(_tension),
              over: bedFadeIn,
            ),
          );
        },
        onError: (Object error) {
          _bedStarting = false;
          debugPrint('[RaceSfx] bed failed to start: $error');
        },
      ),
    );
  }

  /// Breathes the bed out and stops it; rising tension before it is gone
  /// brings the same voice back ([_applyTension]).
  void _releaseBed() {
    final bed = _bed;
    if (bed == null || _bedRelease != null) return;
    if (!_alive(bed)) {
      _bed = null;
      return;
    }
    _safely(() => _output.fadeLoop(bed, volume: 0, over: bedFadeOut));
    _bedRelease = Timer(bedFadeOut + const Duration(milliseconds: 60), () {
      _bedRelease = null;
      if (_bed != bed) return;
      _bed = null;
      _safely(() => _output.stopLoop(bed, fade: Duration.zero));
    });
  }

  /// Ends the bed for good (finish, leaving): no voice survives to be reused.
  void _endBed(Duration fade) {
    _bedRelease?.cancel();
    _bedRelease = null;
    final bed = _bed;
    _bed = null;
    if (bed != null) _safely(() => _output.stopLoop(bed, fade: fade));
  }

  bool _alive(SfxVoiceHandle voice) {
    try {
      return _output.isAlive(voice);
    } catch (_) {
      return false;
    }
  }

  // -------------------------------------------------------------------------

  static double _quantize(double value) {
    if (!value.isFinite) return 0;
    return (value.clamp(0.0, 1.0) * 100).round() / 100;
  }

  static double _bedVolume(double tension) => tension <= 0
      ? 0
      : bedFloor + (bedCeiling - bedFloor) * tension.clamp(0.0, 1.0);

  static double _bedSpeed(double tension) =>
      1 + (bedTopSpeed - 1) * tension.clamp(0.0, 1.0);

  static double _semitones(int steps) =>
      steps == 0 ? 1 : math.pow(2, steps / 12).toDouble();

  static void _safely(void Function() call) {
    try {
      call();
    } catch (error) {
      debugPrint('[RaceSfx] sound failed: $error');
    }
  }
}
