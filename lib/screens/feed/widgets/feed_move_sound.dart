import 'package:chessever2/providers/board_settings_provider_new.dart';
import 'package:chessever2/screens/chessboard/classification_fx/classification_fx.dart';
import 'package:chessever2/screens/chessboard/classification_fx/move_class.dart';
import 'package:chessever2/screens/feed/audio/feed_sfx.dart';
import 'package:chessever2/screens/feed/widgets/feed_sfx_provider.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Move sounds on Feed boards: the board's own sounds, with a classified
/// move's ElevenLabs sound winning over them ([ClassificationSfx.playMove]).
///
/// Every game move that lands (autoplay, a step, a scrub) and every move the
/// viewer plays on the board goes through here with its [MoveClass] — the
/// PGN's verdict or Feed's eval-swing judgement ([FeedPly.effectiveClass]) —
/// so a report's best / book / missed-win moves sound as themselves too.
///
/// Silent while the Feed speaker is off ([FeedSfx.muted]) or the board's
/// Sound setting is anything but on (loading counts as off, as on the board).
/// While scrubbing only classified moves sound, so a drag across forty moves
/// is not forty clicks. Every call stays fire-and-forget.
class FeedMoveSound {
  FeedMoveSound(this._sfx, {bool Function()? boardSoundOn})
    : _boardSoundOn = boardSoundOn ?? _alwaysOn;

  final FeedSfx _sfx;
  final bool Function() _boardSoundOn;
  final Stopwatch _clock = Stopwatch()..start();
  int? _lastMs;

  static bool _alwaysOn() => true;

  /// Closest two move sounds may sit: a notch above the audio service's own
  /// 60 ms floor, so the service never silently drops ours.
  static const int _spacingMs = 90;

  /// Plays the sound for a move written [san]. [moveClass] is the move's
  /// class when it has one; [fast] is true while scrubbing.
  void play({required String san, MoveClass? moveClass, bool fast = false}) {
    if (_sfx.muted || !_boardSoundOn()) return;
    if (fast && moveClass == null) return;
    final now = _clock.elapsedMilliseconds;
    final last = _lastMs;
    if (last != null &&
        now - last < _spacingMs &&
        (fast || moveClass == null)) {
      return;
    }
    _lastMs = now;
    // Leaving Feed cuts it if it is still ringing ([FeedSfx.hush]).
    _sfx.noteSounded();
    ClassificationSfx.playMove(san: san, moveClass: moveClass);
  }
}

/// The move-sound sink Feed boards talk to. Widget tests override it with a
/// recorder so no audio plugin is touched.
final feedMoveSoundProvider = Provider<FeedMoveSound>((ref) {
  return FeedMoveSound(
    ref.watch(feedSfxProvider),
    boardSoundOn: () =>
        ref.read(boardSettingsProviderNew).valueOrNull?.soundEnabled == true,
  );
});
