import 'dart:async';

import 'package:chessever2/screens/feed/audio/feed_sfx.dart';
import 'package:chessever2/screens/feed/models/feed_models.dart';
import 'package:chessever2/screens/feed/widgets/feed_move_sound.dart';
import 'package:chessever2/screens/feed/widgets/feed_sfx_provider.dart';
import 'package:flutter/foundation.dart';

/// Autoplay state for one Feed clip.
///
/// One timer drives the clip: it fires once per ply, waits longer on headline
/// moments so the viewer can see them, and runs twice as fast while the right
/// side is held. Everything that can stop playback (the viewer's tap, a scrub,
/// the tab or app going away, the end of the game, the viewer's hand on the
/// board) is a separate flag, so clearing one never restarts a clip another
/// one is holding.
///
/// Every move that lands — autoplay, scrub or a step — sounds through
/// [moveSound] with the ply's class, so a classified move plays its own sound
/// instead of the ordinary one.
class FeedPlayback extends ChangeNotifier {
  FeedPlayback({
    required this.item,
    required this.sfx,
    required this.moveSound,
  });

  final FeedItem item;

  /// Result stinger and the speaker state.
  final FeedSfx sfx;
  final FeedMoveSound moveSound;

  static const Duration firstStep = Duration(milliseconds: 450);
  static const Duration step = Duration(milliseconds: 650);
  static const Duration headlineLinger = Duration(milliseconds: 1400);

  int _ply = 0;
  int _scrubPly = 0;
  bool _userPaused = false;
  bool _suspended = true;
  bool _fast = false;
  bool _scrubbing = false;
  bool _ended = false;

  /// The viewer is driving: they stepped through the moves or are playing
  /// their own line. Autoplay waits, silently (no pause glyph over the
  /// pieces), until a tap on the board or "Back to game" hands it back.
  bool _manual = false;

  /// A piece is picked up, selected, or the promotion picker is open. Held
  /// only while the hand is on the board; releasing it resumes where it was.
  bool _held = false;

  /// True from [restart] until the first move plays, so the opening beat is
  /// short however the clip was resumed.
  bool _freshStart = false;
  Timer? _timer;
  bool _disposed = false;

  int get lastPly => item.plyCount < 0 ? 0 : item.plyCount;

  /// The ply on the board: the scrub target while scrubbing.
  int get shownPly => _scrubbing ? _scrubPly : _ply;
  int get ply => _ply;
  bool get isFast => _fast;
  bool get isScrubbing => _scrubbing;
  bool get isEnded => _ended;
  bool get isSuspended => _suspended;
  bool get isUserPaused => _userPaused;
  bool get isManual => _manual;
  bool get isHeld => _held;

  bool get isPlaying =>
      !_userPaused &&
      !_suspended &&
      !_scrubbing &&
      !_ended &&
      !_manual &&
      !_held;

  /// The play glyph shows only for a pause the viewer asked for.
  bool get showsPauseGlyph =>
      _userPaused && !_scrubbing && !_ended && !_manual && !_held;

  /// Starts the clip from its first position.
  void restart() {
    _ply = 0;
    _scrubPly = 0;
    _ended = false;
    _userPaused = false;
    _manual = false;
    _fast = false;
    _scrubbing = false;
    _freshStart = true;
    _notify();
    _reschedule();
  }

  /// Puts the clip back where the viewer left it when Feed is rebuilt (Home
  /// mounts only the selected tab): the same ply, their pause or their
  /// stepping, or the finished game. Silent: those moves already sounded.
  void restoreTo(
    int ply, {
    bool userPaused = false,
    bool manual = false,
    bool ended = false,
  }) {
    _ply = ended ? lastPly : ply.clamp(0, lastPly);
    _scrubPly = _ply;
    _ended = ended;
    _userPaused = !ended && userPaused;
    _manual = manual;
    _fast = false;
    _scrubbing = false;
    _freshStart = _ply == 0;
    _notify();
    _reschedule();
  }

  /// Held by the screen while the clip is off-screen, the tab is hidden, the
  /// app is backgrounded or a route covers Feed.
  void setSuspended(bool value) {
    if (_suspended == value) return;
    _suspended = value;
    if (value) _fast = false;
    _notify();
    _reschedule();
  }

  /// A tap on the board. While the viewer is driving it hands playback back;
  /// otherwise it pauses or resumes.
  void togglePause() {
    if (_ended || _scrubbing) return;
    if (_manual) {
      _manual = false;
      _userPaused = false;
    } else {
      _userPaused = !_userPaused;
    }
    _notify();
    _reschedule();
  }

  /// Hands playback back after [takeManual]: plays on from the shown ply.
  void resume() {
    if (!_manual && !_userPaused) return;
    _manual = false;
    _userPaused = false;
    _notify();
    _reschedule();
  }

  /// The viewer starts driving (their own line on the board).
  void takeManual() {
    if (_manual) return;
    _manual = true;
    _fast = false;
    _notify();
    _reschedule();
  }

  /// The viewer's hand is on a piece (selected, dragged, promoting).
  void setHeld(bool value) {
    if (_held == value) return;
    _held = value;
    if (value) _fast = false;
    _notify();
    _reschedule();
  }

  /// Shows [target] and hands the clip to the viewer. A step forward sounds
  /// the move that lands; a step back is silent.
  void stepTo(int target) {
    if (_scrubbing) return;
    final next = target.clamp(0, lastPly);
    final forward = next > _ply;
    _ply = next;
    _ended = false;
    _manual = true;
    _userPaused = false;
    _fast = false;
    _freshStart = false;
    if (forward) _playPly(next);
    _notify();
    _reschedule();
  }

  /// 2x while the right side is held. Holding also resumes a paused clip.
  void setFast(bool value) {
    if (_ended || _fast == value) return;
    if (value && _held) return;
    _fast = value;
    if (value) {
      _userPaused = false;
      _manual = false;
    }
    _notify();
    _reschedule();
  }

  void beginScrub(int ply) {
    _scrubbing = true;
    _ended = false;
    _fast = false;
    _scrubPly = ply.clamp(0, lastPly);
    _timer?.cancel();
    _timer = null;
    _notify();
  }

  void scrubTo(int ply) {
    if (!_scrubbing) return;
    final next = ply.clamp(0, lastPly);
    if (next == _scrubPly) return;
    final forward = next > _scrubPly;
    _scrubPly = next;
    if (forward && next > 0) _playPly(next, fast: true);
    _notify();
  }

  /// Lands playback on the scrubbed ply and plays on from there.
  void endScrub() {
    if (!_scrubbing) return;
    _scrubbing = false;
    _ply = _scrubPly;
    _freshStart = false;
    _userPaused = false;
    _manual = false;
    _notify();
    _reschedule();
  }

  Duration _delayFor(int ply, {required bool first}) {
    Duration d;
    if (first) {
      d = firstStep;
    } else if (ply > 0 && (item.plies[ply].moment?.isHeadline ?? false)) {
      d = headlineLinger;
    } else {
      d = step;
    }
    return _fast ? d ~/ 2 : d;
  }

  void _reschedule() {
    _timer?.cancel();
    _timer = null;
    if (_disposed || !isPlaying) return;
    final delay = _delayFor(_ply, first: _freshStart && _ply == 0);
    _timer = Timer(delay, _ply >= lastPly ? _finish : _advance);
  }

  void _advance() {
    _timer = null;
    if (_disposed || !isPlaying) return;
    final next = _ply + 1;
    if (next > lastPly) {
      _finish();
      return;
    }
    _ply = next;
    _freshStart = false;
    _playPly(next);
    _notify();
    _reschedule();
  }

  /// The move that produced ply [index], with its class.
  void _playPly(int index, {bool fast = false}) {
    if (index <= 0 || index >= item.plies.length) return;
    final ply = item.plies[index];
    final san = ply.san;
    if (san == null) return;
    feedSfxSafely(
      () => moveSound.play(san: san, moveClass: ply.effectiveClass, fast: fast),
    );
  }

  /// The last ply has had its beat: show the result.
  void _finish() {
    _timer = null;
    if (_disposed || _scrubbing) return;
    _ply = lastPly;
    _ended = true;
    _fast = false;
    feedSfxSafely(() => sfx.playGameEnd(item));
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
    super.dispose();
  }
}
