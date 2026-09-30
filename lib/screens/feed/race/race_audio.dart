import 'dart:async';

import 'package:chessever2/providers/board_settings_provider_new.dart';
import 'package:chessever2/screens/chessboard/classification_fx/classification_fx.dart';
import 'package:chessever2/screens/feed/audio/feed_sfx.dart';
import 'package:chessever2/screens/feed/race/race_sfx.dart';
import 'package:chessever2/screens/feed/widgets/feed_sfx_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Everything a race sounds like: the [RaceSfx] stingers, and the board's
/// own move sounds for the moves on the board. Fire-and-forget; a sound
/// failure never reaches the race. Tests override [raceAudioProvider] with a
/// recorder.
abstract interface class RaceAudio {
  void warmUp();
  void countdownBeat(int n);
  void go();
  void correct({int streak = 0});
  void wrong();
  void levelUp();
  void setTension(double intensity);
  void lastLife();
  void finish({bool newBest = false});
  void stopAll();

  /// The board's ordinary sound for a move written [san].
  void move(String san);
}

/// The race's stinger engine. Production is [RaceSfx.instance]; tests swap
/// in `RaceSfx.forTesting` over a recorder.
final raceSfxProvider = Provider<RaceSfx>((ref) => RaceSfx.instance);

/// The race's sounds. Binds the board's Sound setting to [RaceSfx] itself on
/// every settings emission (loading or failed reads as off), so the race
/// never depends on the Feed tab having been built to learn it: a race
/// opened from My Profile first thing in a session sounds like any other.
final raceAudioProvider = Provider<RaceAudio>((ref) {
  final sfx = ref.watch(raceSfxProvider);
  ref.listen<AsyncValue<BoardSettingsNew>>(boardSettingsProviderNew, (_, next) {
    try {
      sfx.followBoardSettings(next.valueOrNull?.soundEnabled);
    } catch (error) {
      debugPrint('[Race] board sound sync failed: $error');
    }
  }, fireImmediately: true);
  return RaceSfxAudio(ref.read(feedSfxProvider), sfx: sfx);
});

/// [RaceSfx] for the stingers; the Feed's speaker toggle and the board's
/// Sound setting (as the race mirrors it, [RaceSfx.boardSoundEnabled])
/// decide whether moves sound.
class RaceSfxAudio implements RaceAudio {
  RaceSfxAudio(this._feed, {RaceSfx? sfx}) : _sfxOverride = sfx;

  final FeedSfx _feed;
  final RaceSfx? _sfxOverride;

  RaceSfx get _sfx => _sfxOverride ?? RaceSfx.instance;

  bool get _movesSilent => _feed.muted || !_sfx.boardSoundEnabled;

  static void _safely(void Function() call) {
    try {
      call();
    } catch (error) {
      debugPrint('[Race] sound failed: $error');
    }
  }

  @override
  void warmUp() => _safely(() {
    // The race follows the Feed's speaker.
    _sfx.muted = _feed.muted;
    // Decode the race set only when it will be heard, as the Feed and the
    // board do: a warm-up marks the set wanted, and a wanted set is decoded
    // again on every engine re-init (each return to the foreground). A race
    // that turns audible later still loads on its first sound.
    if (_movesSilent) return;
    unawaited(
      _sfx.warmUp().catchError((Object error) {
        debugPrint('[Race] sound warm-up failed: $error');
      }),
    );
  });

  @override
  void countdownBeat(int n) => _safely(() => _sfx.countdownBeat(n));

  @override
  void go() => _safely(_sfx.go);

  @override
  void correct({int streak = 0}) => _safely(() => _sfx.correct(streak: streak));

  @override
  void wrong() => _safely(_sfx.wrong);

  @override
  void levelUp() => _safely(_sfx.levelUp);

  @override
  void setTension(double intensity) =>
      _safely(() => _sfx.setTension(intensity));

  @override
  void lastLife() => _safely(_sfx.lastLife);

  @override
  void finish({bool newBest = false}) =>
      _safely(() => _sfx.finish(newBest: newBest));

  @override
  void stopAll() => _safely(_sfx.stopAll);

  @override
  void move(String san) => _safely(() {
    if (_movesSilent) return;
    ClassificationSfx.playMove(san: san);
  });
}
