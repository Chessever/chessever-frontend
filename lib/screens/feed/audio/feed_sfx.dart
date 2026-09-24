import 'dart:async';

import 'package:chessever2/screens/chessboard/classification_fx/classification_fx.dart';
import 'package:chessever2/screens/chessboard/classification_fx/move_class.dart';
import 'package:chessever2/screens/feed/models/feed_models.dart';
import 'package:chessever2/utils/audio_player_service.dart';
import 'package:flutter/foundation.dart';

/// The classification a Feed moment carries, or null when the moment is not a
/// move verdict (checkmate, sacrifice, check, capture, ... are just moves, and
/// sound like the board's own move sounds). One mapping for sound, badge and
/// landing: this is [feedMomentClass].
MoveClass? moveClassForFeedMoment(FeedMoment? moment) =>
    feedMomentClass(moment);

/// Sound design for Feed: exactly the board's own sounds for ordinary moves,
/// the classification sound for classified moves ([ClassificationSfx] — it
/// wins over the ordinary one, never both), the board's draw chime when a
/// drawn game ends, and a soft swipe between games.
///
/// Every call is fire-and-forget; this class only decides *which* sound and
/// whether it should sound at all.
class FeedSfx {
  FeedSfx._() : boardSoundEnabled = false;
  static final FeedSfx instance = FeedSfx._();

  /// For a silent test double: `class _Silent extends FeedSfx` can override
  /// the play methods without touching the audio engine. Starts as if the
  /// board settings had loaded with Sound on, unless told otherwise.
  @visibleForTesting
  FeedSfx.forTesting({this.boardSoundEnabled = true});

  /// Any two Feed move sounds at least this far apart — a notch above the
  /// audio service's own 60 ms floor so the service never silently drops ours.
  static const Duration _minSpacing = Duration(milliseconds: 90);

  /// After a headline classification sound (brilliant, blunder), ordinary
  /// move sounds stay quiet this long so its tail is heard instead of being
  /// stepped on at 2x.
  static const Duration _headlineHold = Duration(milliseconds: 450);

  /// The draw chime waits this long after the last-ply sound.
  static const Duration _resultDelay = Duration(milliseconds: 420);

  final Stopwatch _clock = Stopwatch()..start();
  int? _lastPlayMs;
  int? _lastHeadlineMs;
  Timer? _pendingResult;
  Future<void>? _warming;

  /// Mutes/unmutes Feed sounds (the speaker toggle on the Feed screen).
  bool get muted => _muted;
  set muted(bool value) {
    _muted = value;
    if (value) _cancelPendingResult();
  }

  bool _muted = false;

  /// Mirrors the board's "Sound" setting (`BoardSettingsNew.soundEnabled`).
  /// The Feed provider keeps it in sync on every settings emission. Gated
  /// exactly like the board and `FeedMoveSound`: off until the settings have
  /// loaded with Sound on, and off when they fail to load. A user who
  /// silenced the board does not get a talking feed, and nothing in the Feed
  /// sounds while the Feed's own game moves are still silent.
  bool boardSoundEnabled;

  bool get _silent => _muted || !boardSoundEnabled;

  /// Loads the classification and swipe sounds. Idempotent; call when the
  /// Feed tab first shows.
  Future<void> warmUp() => _warming ??= ClassificationSfx.warmUp()
      .catchError((Object err) {
        debugPrint('⚠️ FeedSfx warm-up failed: $err');
      })
      .whenComplete(() => _warming = null);

  /// Plays the right sound for [ply]. [fast] is true during 2x playback or
  /// scrubbing: only moments of severity 2+ sound then.
  ///
  /// The Feed player itself sounds its moves through `FeedMoveSound`; this
  /// stays for callers that only hold a [FeedPly], and classifies the move the
  /// same way ([FeedPly.effectiveClass]: the PGN's verdict first, then the
  /// eval-swing moment).
  void playForPly(FeedPly ply, {bool fast = false}) {
    if (_silent) return;
    final san = ply.san;
    if (san == null) return; // start position: nothing was played

    final moment = ply.moment;
    final severity = moment?.severity ?? 0;
    // At speed only the beats that matter (severity 2+) make a sound.
    if (fast && severity < 2) return;

    final moveClass = ply.effectiveClass;
    final headline = moveClass != null && severity >= 3;
    // A headline classification sound's tail is not stepped on by lesser
    // sounds.
    if (!headline && _withinHeadlineHold()) return;

    final now = _clock.elapsedMilliseconds;
    final last = _lastPlayMs;
    // Classified moves always sound; ordinary ones keep their spacing.
    if (moveClass == null &&
        last != null &&
        now - last < _minSpacing.inMilliseconds) {
      return;
    }
    _lastPlayMs = now;
    if (headline) _lastHeadlineMs = now;
    ClassificationSfx.playMove(san: san, moveClass: moveClass);
  }

  /// When a clip reaches its last ply: the board's draw chime for a drawn
  /// game. A decisive game already ended on its own move sound (the mate, or
  /// the last move before a resignation), exactly as on the board.
  void playGameEnd(FeedItem item) {
    if (_silent) return;
    final drawn = item.result == '½-½' || item.result == '1/2-1/2';
    if (!drawn) return;

    _cancelPendingResult();
    final sinceLast = _msSince(_lastPlayMs);
    final wait = sinceLast == null
        ? 0
        : _resultDelay.inMilliseconds - sinceLast;
    if (wait <= 0) {
      ClassificationSfx.playSfx(SfxType.draw);
      return;
    }
    // Lets the last move's sound land first. A delay, not a queue: it is
    // cancelled by a swipe or mute, and still plays fire-and-forget.
    _pendingResult = Timer(Duration(milliseconds: wait), () {
      _pendingResult = null;
      if (!_silent) ClassificationSfx.playSfx(SfxType.draw);
    });
  }

  /// Soft whoosh when the feed moves to the next or previous game. It
  /// replaces no board sound.
  void playSwipe() {
    _cancelPendingResult();
    _lastHeadlineMs = null;
    if (_silent) return;
    ClassificationSfx.playSfx(SfxType.feedSwipe);
  }

  // -------------------------------------------------------------------------

  bool _withinHeadlineHold() {
    final since = _msSince(_lastHeadlineMs);
    return since != null && since < _headlineHold.inMilliseconds;
  }

  int? _msSince(int? stamp) =>
      stamp == null ? null : _clock.elapsedMilliseconds - stamp;

  void _cancelPendingResult() {
    _pendingResult?.cancel();
    _pendingResult = null;
  }
}
