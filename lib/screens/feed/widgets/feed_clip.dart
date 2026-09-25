import 'dart:async';
import 'dart:math' as math;

import 'package:chessever2/providers/engine_settings_provider.dart';
import 'package:chessever2/repository/liked_games/liked_games_provider.dart';
import 'package:chessever2/screens/board_editor/board_editor_screen.dart';
import 'package:chessever2/screens/chessboard/classification_fx/move_class.dart';
import 'package:chessever2/screens/chessboard/provider/chess_board_screen_provider_new.dart';
import 'package:chessever2/screens/chessboard/widgets/evaluation_bar_widget.dart';
import 'package:chessever2/screens/chessboard/widgets/heart_burst.dart';
import 'package:chessever2/screens/chessboard/widgets/player_first_row_detail_widget.dart';
import 'package:chessever2/screens/feed/logic/feed_exploration.dart';
import 'package:chessever2/screens/feed/logic/feed_opening.dart';
import 'package:chessever2/screens/feed/models/feed_entry.dart';
import 'package:chessever2/screens/feed/models/feed_models.dart';
import 'package:chessever2/screens/feed/providers/feed_eval_provider.dart';
import 'package:chessever2/screens/feed/widgets/feed_action_row.dart';
import 'package:chessever2/screens/feed/widgets/feed_board.dart';
import 'package:chessever2/screens/feed/widgets/feed_classification.dart';
import 'package:chessever2/screens/feed/widgets/feed_end_card.dart';
import 'package:chessever2/screens/feed/widgets/feed_format.dart';
import 'package:chessever2/screens/feed/widgets/feed_glyphs.dart';
import 'package:chessever2/screens/feed/widgets/feed_layout.dart';
import 'package:chessever2/screens/feed/widgets/feed_live_board.dart';
import 'package:chessever2/screens/feed/widgets/feed_move_sound.dart';
import 'package:chessever2/screens/feed/widgets/feed_move_strip.dart';
import 'package:chessever2/screens/feed/widgets/feed_playback.dart';
import 'package:chessever2/screens/feed/widgets/feed_post_header.dart';
import 'package:chessever2/screens/feed/widgets/feed_scrub.dart';
import 'package:chessever2/screens/feed/widgets/feed_sfx_provider.dart';
import 'package:chessever2/screens/feed/widgets/feed_share.dart';
import 'package:chessever2/screens/feed/widgets/feed_states.dart';
import 'package:chessever2/screens/library/twic_contents_screen.dart';
import 'package:chessever2/screens/library/widgets/library_context_menu.dart';
import 'package:chessever2/screens/my_space/actions/space_menu_action.dart';
import 'package:chessever2/screens/my_space/models/space_shortcut.dart';
import 'package:chessever2/screens/my_space/providers/space_shortcuts_provider.dart';
import 'package:chessever2/screens/my_space/widgets/pixel_flame.dart';
import 'package:chessever2/screens/player_profile/player_profile_data_source.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/event_no_spoilers_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/utils/game_space_shortcut.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/game_card_wrapper/game_card_wrapper_provider.dart';
import 'package:chessever2/services/deep_link_service.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/png_asset.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/user_error_message.dart';
import 'package:chessever2/widgets/app_snack.dart';
import 'package:chessever2/widgets/time_control_glyph.dart';
import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// One page of the Feed: a finished game replaying itself on a playable
/// board, laid out exactly like the app's game cards (the same
/// [PlayerFirstRowDetailWidget] rows over and under the board, the board
/// screen's [EvaluationBarWidget] beside it) under a one-line
/// [FeedPostHeader].
///
/// Gestures belong to the parts they sit on. The header's event and opening
/// open the event and the board editor; the player names open the scorecard
/// (long-press: the player's focus menu). Over the board and its eval bar:
/// * tap a piece of the side to move, then its square, to play a legal move.
///   Playback holds while a piece is in hand; a move that differs from the
///   game starts the viewer's own line (autoplay waits, "Back to game"
///   returns), and the game's own next move simply steps the game on. The
///   final position plays too: on a decisive ending a touch on a playable
///   piece stands the tipped king back up
/// * once the viewer has the board (paused, stepping, at the end, or in
///   their own line) pieces also drag, and the feed holds still under them
/// * tap anywhere else: pause / resume (resolved after the double-tap
///   window); once the clip has ended, it moves the result card off the
///   board and back
/// * double-tap: like, with the board screen's heart burst flying into Like
/// * hold the right third 280ms: 2x while held
/// * long-press the rest of the board: Open game / Share / My Space menu
/// * the move strip under the board: tap a move to jump there, or step
/// * drag the bottom line: scrub, with the report chart when evals exist
///
/// While the clip plays, a swipe always belongs to the feed's PageView: a
/// swipe that starts on a piece puts it back down. Holding 2x locks the feed
/// so a wobble of the thumb cannot throw the viewer onwards.
class FeedClip extends ConsumerStatefulWidget {
  const FeedClip({
    required this.item,
    required this.isCurrent,
    required this.isVisible,
    required this.onRequestNext,
    required this.onScrollLock,
    super.key,
  });

  final FeedItem item;

  /// This page is the feed's settled page.
  final bool isCurrent;

  /// Feed itself is on screen: tab selected, app resumed, no route on top.
  final bool isVisible;
  final VoidCallback onRequestNext;
  final ValueChanged<bool> onScrollLock;

  @override
  ConsumerState<FeedClip> createState() => _FeedClipState();
}

/// Where the settled Feed clip was left when its page was torn down.
@immutable
class FeedClipResume {
  const FeedClipResume({
    required this.entryKey,
    required this.ply,
    this.userPaused = false,
    this.manual = false,
    this.ended = false,
    this.line,
    this.kingUp = false,
    this.cardAside = false,
    this.countdown = 0,
  });

  /// The [FeedEntry.key] of the page it belongs to.
  final String entryKey;
  final int ply;
  final bool userPaused;
  final bool manual;
  final bool ended;
  final FeedExploration? line;
  final bool kingUp;
  final bool cardAside;

  /// How far the "Next game" fill had run.
  final double countdown;
}

/// Holds the settled clip's [FeedClipResume] across a Feed rebuild. Home
/// mounts only the selected tab, so leaving Feed disposes every clip; the
/// page comes back through `feedCurrentEntryKeyProvider`, the playback
/// through this. A plain holder, not provider state: it is written from
/// dispose and must not notify anyone.
class FeedClipResumeStore {
  FeedClipResume? _saved;

  void save(FeedClipResume resume) => _saved = resume;

  /// The saved state for [entryKey], if any. Taking it empties the store
  /// either way, so an old one never resurfaces on a later visit.
  FeedClipResume? take(String entryKey) {
    final saved = _saved;
    _saved = null;
    return saved?.entryKey == entryKey ? saved : null;
  }

  void clear() => _saved = null;
}

final feedClipResumeProvider = Provider<FeedClipResumeStore>(
  (ref) => FeedClipResumeStore(),
);

/// What the board shows right now, on the game line or the viewer's own.
@immutable
class _BoardView {
  const _BoardView({
    required this.fen,
    required this.position,
    required this.lastMove,
    this.before,
    this.badgeClass,
    this.fallenSquare,
    this.fallenSide,
  });

  /// The FEN handed to the board (the loser's king lifted off on a decisive
  /// ending, so it can be redrawn tipped over).
  final String fen;
  final Position? position;
  final Move? lastMove;

  /// The position [lastMove] was played from, so its landing square can tell
  /// castling from a rook sliding along the back rank.
  final Position? before;
  final MoveClass? badgeClass;
  final Square? fallenSquare;
  final Side? fallenSide;
}

/// The board's state at the instant a finger landed on a square, captured
/// before chessground acts on it.
class _BoardTouch {
  const _BoardTouch({
    required this.selected,
    required this.promoting,
    required this.userMoves,
  });

  final Square? selected;
  final bool promoting;
  final int userMoves;
}

class _FeedClipState extends ConsumerState<FeedClip>
    with SingleTickerProviderStateMixin {
  static const Duration _holdDelay = Duration(milliseconds: 280);
  static const Duration _menuDelay = Duration(milliseconds: 500);
  static const Duration _tapMaxDuration = Duration(milliseconds: 300);
  static const Duration _doubleTapWindow = Duration(milliseconds: 260);
  static const Duration _autoAdvance = Duration(seconds: 4);
  static const double _holdZoneStart = 0.62;
  static const double _moveSlop = 12;

  late final FeedPlayback _playback;
  late final FeedMoveSound _moveSound;
  late final FeedClipResumeStore _resume;
  late final ChessboardController _board;
  late final AnimationController _countdown;
  final HeartBurstController _burst = HeartBurstController();
  final GlobalKey _likeIconKey = GlobalKey();
  final GlobalKey _boardKey = GlobalKey();
  final GlobalKey _zoneKey = GlobalKey();

  /// The board's [RepaintBoundary]: Share reuses its pixels, like the board
  /// screen's share does.
  final GlobalKey _shareBoundaryKey = GlobalKey();

  // Gesture-zone state. Everything is timer-driven so it behaves identically
  // under a real clock and a test's fake one.
  int? _pointer;
  Offset _downLocal = Offset.zero;
  bool _moved = false;
  bool _holding = false;
  bool _menuTriggered = false;
  Timer? _holdTimer;
  Timer? _menuTimer;
  Timer? _tapWindow;
  Timer? _singleTap;
  Offset? _ripple;
  int _rippleSeq = 0;
  bool _menuOpen = false;
  OverlayEntry? _flight;

  // Board-play state.
  /// The viewer's own line, while they are playing one.
  FeedExploration? _line;

  /// Set by chessground's square callback, read by the zone handler that
  /// runs right after it for the same pointer-down.
  _BoardTouch? _pendingTouch;

  /// Moves the viewer has played on this board; lets the zone tell that the
  /// pointer-down it is handling was itself a (tap-tap) move.
  int _userMoves = 0;

  /// The pointer currently playing on the board, not driving the zone.
  int? _boardPointer;

  /// A piece is in hand on a board the viewer has, so it may be dragged:
  /// the feed is locked still until the finger lifts.
  bool _dragLock = false;

  /// The viewer touched a playable piece on a decisive final position: the
  /// loser's king stands back up and the board is theirs.
  bool _kingUp = false;

  /// The result card is off the board: the viewer took the final position,
  /// or tapped the card (or the board) to see what lies under it.
  bool _cardAside = false;

  String? _pushedKey;
  bool _pushingBoard = false;
  bool _boardDirty = false;
  bool _userMoveInFlight = false;
  final Map<int, Position?> _positions = {};

  // Landing animation for classified moves arriving on the game line.
  int _lastShown = 0;
  int _landingSeq = 0;
  MoveClass? _landingClass;
  Square? _landingSquare;

  List<FeedStripToken>? _tokens;

  /// The header opening's board-editor position, worked out on first use.
  String? _openingFenValue;
  bool _openingFenResolved = false;

  /// The number on the eval bar at the last build, handed to Share.
  FeedEval? _shownEval;

  /// Suppresses setState while the playback is poked from initState or
  /// didUpdateWidget, which rebuild anyway.
  bool _syncing = false;

  /// A screen reader is on: the result card waits for "Next game" instead
  /// of moving the page on mid-read.
  bool _screenReader = false;

  // Zone geometry from the last layout, in zone-local coordinates.
  double _zoneWidth = 0;
  Rect _boardRect = Rect.zero;
  double _heartSize = 150;

  FeedItem get _item => widget.item;
  GamesTourModel get _game => widget.item.game;
  String get _entryKey => FeedGameEntry(_item).key;

  @override
  void initState() {
    super.initState();
    _moveSound = ref.read(feedMoveSoundProvider);
    _resume = ref.read(feedClipResumeProvider);
    _playback = FeedPlayback(
      item: _item,
      sfx: ref.read(feedSfxProvider),
      moveSound: _moveSound,
    );
    // Back on Feed from another tab: the settled clip carries on where the
    // viewer left it, before the board is first drawn.
    final resumed = widget.isCurrent ? _resume.take(_entryKey) : null;
    if (resumed != null) _restore(resumed);
    final initial = _gameDataFor(_view());
    _board = ChessboardController(game: initial);
    _pushedKey = _keyOf(_view());
    // chessground keeps selection and promotion off its public API; the
    // board screen reads the promotion notifier the same way.
    // ignore: invalid_use_of_internal_member
    _board.highlightNotifier.addListener(_syncHeld);
    // ignore: invalid_use_of_internal_member
    _board.pendingPromotionNotifier.addListener(_syncHeld);
    _playback.addListener(_onPlayback);
    _countdown = AnimationController(vsync: this, duration: _autoAdvance)
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed && mounted) {
          widget.onRequestNext();
        }
      });
    // A spent countdown must not fire again mid-build: it starts over.
    if (resumed != null && resumed.countdown < 1) {
      _countdown.value = resumed.countdown;
    }
    _syncing = true;
    if (widget.isCurrent && resumed == null) _playback.restart();
    _syncSuspended();
    _syncing = false;
  }

  /// Puts back a [FeedClipResume]: the ply, the viewer's pause or stepping,
  /// their own line and the ending as they had it. Runs before the playback
  /// listener is attached, so nothing lands or sounds.
  void _restore(FeedClipResume resumed) {
    final line = resumed.line;
    _line = line != null && line.forkPly <= _playback.lastPly ? line : null;
    _kingUp = resumed.kingUp;
    _cardAside = resumed.cardAside;
    _playback.restoreTo(
      resumed.ply,
      userPaused: resumed.userPaused,
      manual: resumed.manual || _line != null,
      ended: resumed.ended,
    );
    _lastShown = _playback.shownPly;
  }

  /// What [_restore] needs to bring this clip back.
  FeedClipResume _snapshot() {
    final p = _playback;
    return FeedClipResume(
      entryKey: _entryKey,
      ply: p.shownPly,
      // A scrub in progress lands and plays on, as its release would.
      userPaused: p.isUserPaused && !p.isScrubbing,
      manual: p.isManual && !p.isScrubbing,
      ended: p.isEnded && !p.isScrubbing,
      line: _line,
      kingUp: _kingUp,
      cardAside: _cardAside,
      countdown: _countdown.value,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final screenReader = MediaQuery.accessibleNavigationOf(context);
    if (screenReader != _screenReader) {
      _screenReader = screenReader;
      _syncCountdown();
    }
  }

  @override
  void didUpdateWidget(covariant FeedClip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.item.plies, widget.item.plies)) _tokens = null;
    if (!identical(oldWidget.item, widget.item)) _openingFenResolved = false;
    _syncing = true;
    if (widget.isCurrent != oldWidget.isCurrent) {
      _cancelGestures();
      _line = null;
      _landingClass = null;
      _kingUp = false;
      _cardAside = false;
      if (widget.isCurrent) {
        // Swiped onto: a fresh start, and whatever an earlier Feed left
        // behind no longer applies.
        _resume.clear();
        _countdown.value = 0;
        _playback.restart();
      }
    }
    _syncSuspended();
    _pushBoard();
    _syncing = false;
  }

  @override
  void dispose() {
    // Leaving Feed (another tab) tears the settled clip down; keep its place
    // for the return. A neighbour page restarts when swiped onto anyway.
    if (widget.isCurrent) _resume.save(_snapshot());
    _cancelTimers();
    if (_holding || _dragLock) {
      _holding = false;
      _dragLock = false;
      widget.onScrollLock(false);
    }
    _flight?.remove();
    _flight = null;
    _playback
      ..removeListener(_onPlayback)
      ..dispose();
    // ignore: invalid_use_of_internal_member
    _board.highlightNotifier.removeListener(_syncHeld);
    // ignore: invalid_use_of_internal_member
    _board.pendingPromotionNotifier.removeListener(_syncHeld);
    _board.dispose();
    _countdown.dispose();
    _burst.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------- playback

  void _syncSuspended() {
    _playback.setSuspended(
      !(widget.isCurrent && widget.isVisible) || _menuOpen,
    );
    _syncCountdown();
  }

  void _onPlayback() {
    // The raised king and the card set aside belong to the ending the viewer
    // took over; anywhere else the game's own view is back.
    if (_playback.shownPly != _playback.lastPly) _kingUp = false;
    if (!_playback.isEnded) _cardAside = false;
    _syncCountdown();
    _trackLanding();
    _pushBoard();
    _rebuild();
  }

  /// setState, unless a rebuild is already coming (initState and
  /// didUpdateWidget) or a board listener fired mid-frame, where it waits
  /// for the frame to finish.
  void _rebuild() {
    if (!mounted || _syncing) return;
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
      return;
    }
    setState(() {});
  }

  /// The "Next game" fill runs only while the result card is actually seen
  /// and nobody's hand is on the board. With a screen reader on it never
  /// runs: the viewer moves on with "Next game" (WCAG 2.2.1).
  void _syncCountdown() {
    if (!_playback.isEnded) {
      if (_countdown.value != 0 || _countdown.isAnimating) {
        _countdown.stop();
        _countdown.value = 0;
      }
      return;
    }
    // The card is on the board only while the viewer has not taken it.
    final seen = !_cardAside && !_playback.isHeld && _line == null;
    final run =
        seen &&
        !_screenReader &&
        !_playback.isSuspended &&
        !_playback.isScrubbing &&
        !_playback.isManual;
    if (run) {
      if (!_countdown.isAnimating && !_countdown.isCompleted) {
        _countdown.forward();
      }
      return;
    }
    if (_countdown.isAnimating) _countdown.stop();
    // The viewer took the board: the wait for "Next game" starts over once
    // the card comes back. A screen reader gets no half-run fill either.
    if ((!seen || _screenReader) && _countdown.value != 0) {
      _countdown.value = 0;
    }
  }

  void _setCardAside(bool value) {
    if (_cardAside == value) return;
    _cardAside = value;
    _syncCountdown();
    _rebuild();
  }

  /// A classified game move that just arrived (autoplay, a step, a scrub
  /// forward, or the viewer finding it) gets its landing; anything else
  /// clears it.
  void _trackLanding() {
    final shown = _playback.shownPly;
    if (shown == _lastShown) return;
    final forward = shown > _lastShown;
    _lastShown = shown;
    final plies = _item.plies;
    if (_line != null || !forward || shown <= 0 || shown >= plies.length) {
      _landingClass = null;
      return;
    }
    final ply = plies[shown];
    final moveClass = ply.effectiveClass;
    if (moveClass == null) {
      _landingClass = null;
      return;
    }
    _landingClass = moveClass;
    _landingSquare = feedLandingSquare(_moveOf(ply), _positionAt(shown - 1));
    _landingSeq++;
  }

  // ------------------------------------------------------------------ board

  Position? _positionAt(int ply) {
    return _positions.putIfAbsent(ply, () {
      final plies = _item.plies;
      if (ply < 0 || ply >= plies.length) return null;
      try {
        return Chess.fromSetup(Setup.parseFen(plies[ply].fen));
      } catch (_) {
        return null;
      }
    });
  }

  /// The loser, when [shown] is the final position of a decisive game.
  Side? _loserAt(int shown) {
    final last = _playback.lastPly;
    if (shown != last || last <= 0) return null;
    return switch (feedResultStatus(_item)) {
      GameStatus.whiteWins => Side.black,
      GameStatus.blackWins => Side.white,
      _ => null,
    };
  }

  _BoardView _view() {
    final plies = _item.plies;
    if (plies.isEmpty) {
      return const _BoardView(fen: kInitialFEN, position: null, lastMove: null);
    }
    final line = _line;
    if (line != null) {
      final current = line.current;
      final fork = plies[line.forkPly.clamp(0, plies.length - 1)];
      return _BoardView(
        fen: line.position.fen,
        position: line.position,
        lastMove: current?.move ?? _moveOf(fork),
        before: current != null
            ? (line.cursor > 0 ? line.moves[line.cursor - 1].after : line.start)
            : _positionAt(line.forkPly - 1),
        // At the fork itself the game's move is still the one on the board.
        badgeClass: current == null && line.forkPly > 0
            ? fork.effectiveClass
            : null,
      );
    }
    final shown = _playback.shownPly.clamp(0, plies.length - 1);
    final ply = plies[shown];
    var fen = ply.fen;
    Square? fallenSquare;
    Side? fallenSide;
    final loser = _kingUp ? null : _loserAt(shown);
    if (loser != null) {
      final removed = feedWithoutKing(fen, loser);
      if (removed != null) {
        fen = removed.fen;
        fallenSquare = removed.square;
        fallenSide = loser;
      }
    }
    return _BoardView(
      fen: fen,
      position: _positionAt(shown),
      lastMove: _moveOf(ply),
      before: _positionAt(shown - 1),
      badgeClass: shown > 0 ? ply.effectiveClass : null,
      fallenSquare: fallenSquare,
      fallenSide: fallenSide,
    );
  }

  /// Whether the viewer may move pieces on [view].
  bool _interactive(_BoardView view) =>
      view.position != null &&
      view.fallenSquare == null &&
      widget.isCurrent &&
      !_menuOpen &&
      !_playback.isScrubbing;

  Square? _checkSquare(_BoardView view) {
    final position = view.position;
    if (position == null || view.fallenSquare != null) return null;
    return position.isCheck ? position.board.kingOf(position.turn) : null;
  }

  String _keyOf(_BoardView view) =>
      '${view.fen}|${view.lastMove?.uci}|${_interactive(view)}';

  GameData _gameDataFor(_BoardView view, {bool forceStatic = false}) {
    final position = view.position;
    final interactive = !forceStatic && _interactive(view);
    return GameData(
      fen: view.fen,
      playerSide: interactive
          ? (position!.turn == Side.white ? PlayerSide.white : PlayerSide.black)
          : PlayerSide.none,
      sideToMove: position?.turn ?? Side.white,
      validMoves: interactive ? makeLegalMoves(position!) : const {},
      lastMove: view.lastMove,
      kingSquareInCheck: _checkSquare(view),
    );
  }

  // ignore: invalid_use_of_internal_member
  Square? get _boardSelection => _board.highlightNotifier.selected;

  /// Brings the board in line with what should be on it. Re-entrant calls
  /// (a board listener firing mid-update) are folded into the running one.
  void _pushBoard() {
    if (_pushingBoard) {
      _boardDirty = true;
      return;
    }
    _pushingBoard = true;
    try {
      for (var pass = 0; pass < 3; pass++) {
        _boardDirty = false;
        final view = _view();
        final key = _keyOf(view);
        if (key != _pushedKey) {
          _pushedKey = key;
          final target = _gameDataFor(view);
          // A piece selected on the old position must not survive onto a new
          // one; a non-interactive beat is how chessground drops it.
          if (!_userMoveInFlight &&
              target.playerSide != PlayerSide.none &&
              target.fen != _board.fen &&
              _boardSelection != null) {
            _board.updatePosition(_gameDataFor(view, forceStatic: true));
          }
          _board.updatePosition(target, resetPremove: true);
        }
        if (!_boardDirty) break;
      }
    } finally {
      _pushingBoard = false;
    }
  }

  /// Playback holds while a piece is in hand or the promotion picker is up.
  void _syncHeld() {
    final held =
        _boardSelection != null ||
        _board.pendingPromotion != null ||
        _boardPointer != null;
    _playback.setHeld(held);
  }

  void _onTouchedSquare(Square square) {
    _pendingTouch = _BoardTouch(
      selected: _boardSelection,
      promoting: _board.pendingPromotion != null,
      userMoves: _userMoves,
    );
    _raiseKingFor(square);
  }

  /// A decisive game's final position is playable too. The loser's king lies
  /// tipped over there, which freezes the board; a touch on a piece the side
  /// to move can play stands the king back up and hands the board over, in
  /// time for chessground to pick that piece up on this same pointer-down.
  /// A mate has nothing to play, so it stays as it fell.
  void _raiseKingFor(Square square) {
    if (_kingUp || _line != null) return;
    if (!widget.isCurrent || _menuOpen || _playback.isScrubbing) return;
    final view = _view();
    final position = view.position;
    if (view.fallenSquare == null || position == null) return;
    final piece = position.board.pieceAt(square);
    if (piece == null || piece.color != position.turn) return;
    if (position.legalMovesOf(square).isEmpty) return;
    _kingUp = true;
    _pushBoard();
    _rebuild();
  }

  /// Puts a picked-up piece back down and closes the promotion picker; a
  /// non-interactive beat is how chessground drops them.
  void _dropSelection() {
    if (_boardSelection == null && _board.pendingPromotion == null) return;
    final view = _view();
    _board.updatePosition(_gameDataFor(view, forceStatic: true));
    _board.updatePosition(_gameDataFor(view), resetPremove: true);
  }

  void _onUserMove(Move move, {bool? viaDragAndDrop}) {
    _userMoves++;
    _userMoveInFlight = true;
    try {
      HapticFeedbackService.chessPieceMove();
      var line = _line;
      if (line == null) {
        final shown = _playback.shownPly;
        final from = _positionAt(shown);
        if (from == null || !from.isLegal(move)) {
          _pushedKey = null;
          _pushBoard();
          return;
        }
        final played = move is NormalMove ? from.normalizeMove(move) : move;
        final plies = _item.plies;
        if (shown < _playback.lastPly && plies[shown + 1].uci == played.uci) {
          // The viewer found the game's move: the game steps on, with that
          // move's own class sound and landing.
          _playback.stepTo(shown + 1);
          return;
        }
        line = FeedExploration(forkPly: shown, start: from);
      }
      final result = line.play(move);
      if (result == null) {
        _pushedKey = null;
        _pushBoard();
        return;
      }
      final (next, played) = result;
      _line = next;
      _landingClass = null;
      // Their own moves are unclassified: the board's ordinary sounds.
      feedSfxSafely(() => _moveSound.play(san: played.san));
      _playback.takeManual();
      _pushBoard();
      _rebuild();
    } finally {
      _userMoveInFlight = false;
    }
  }

  void _backToGame() {
    if (_line == null) return;
    HapticFeedbackService.buttonPress();
    _line = null;
    _landingClass = null;
    // A line from the final position returns to the ending as it was: the
    // king back down, the result card back up.
    _kingUp = false;
    _cardAside = false;
    _playback.resume();
    _syncCountdown();
    _pushBoard();
    _rebuild();
  }

  void _jumpInLine(int index) {
    final line = _line;
    if (line == null) return;
    HapticFeedbackService.selection();
    final forward = index > line.cursor;
    _line = line.jumpTo(index);
    if (forward && index >= 0) {
      final san = line.moves[index].san;
      feedSfxSafely(() => _moveSound.play(san: san));
    }
    _pushBoard();
    setState(() {});
  }

  void _stepTo(int ply) {
    if (_item.plies.isEmpty) return;
    HapticFeedbackService.selection();
    _playback.stepTo(ply);
  }

  void _togglePlay() {
    HapticFeedbackService.buttonPress();
    if (_playback.isEnded) {
      _countdown.value = 0;
      _playback.restart();
    } else if (_playback.isHeld) {
      // A piece in hand holds the clip and the button shows Play: the piece
      // goes back down and the game plays on.
      _dropSelection();
      _playback.resume();
    } else if (_playback.isPlaying) {
      _playback.togglePause();
    } else {
      _playback.resume();
    }
  }

  // ----------------------------------------------------------- gesture zone

  void _cancelTimers() {
    _holdTimer?.cancel();
    _menuTimer?.cancel();
    _tapWindow?.cancel();
    _singleTap?.cancel();
    _holdTimer = _menuTimer = _tapWindow = _singleTap = null;
  }

  void _cancelGestures() {
    _cancelTimers();
    _pointer = null;
    if (_boardPointer != null) {
      _boardPointer = null;
      _syncHeld();
    }
    _releaseDragLock();
    if (_holding) _endHold();
  }

  /// Whether the viewer has the board, so pieces drag as well as tap-tap:
  /// paused by them, stepping by hand, at the end, or in their own line.
  /// While the clip plays by itself the board stays tap-tap and a travelling
  /// finger is the feed's swipe.
  bool get _dragAllowed =>
      _line != null ||
      _playback.isUserPaused ||
      _playback.isManual ||
      _playback.isEnded;

  void _releaseDragLock() {
    if (!_dragLock) return;
    _dragLock = false;
    widget.onScrollLock(false);
  }

  /// Whether the pointer-down just handled by chessground was play on the
  /// board rather than a tap on it: a piece picked up, a move made, a
  /// selection dropped, the promotion picker answered.
  bool _isBoardPlay(_BoardTouch touch) {
    final moved = _userMoves != touch.userMoves;
    return moved ||
        touch.promoting ||
        _board.pendingPromotion != null ||
        touch.selected != null ||
        _boardSelection != null;
  }

  void _onZoneDown(PointerDownEvent e) {
    final touch = _pendingTouch;
    _pendingTouch = null;
    if (_pointer != null) return; // one finger drives the zone

    if (touch != null && _isBoardPlay(touch)) {
      _pointer = e.pointer;
      _boardPointer = e.pointer;
      _downLocal = e.localPosition;
      _moved = false;
      // A pause tap waiting on the double-tap window yields to play.
      _singleTap?.cancel();
      _singleTap = null;
      // Play on the final position takes the board: the result card steps
      // aside until a plain tap brings it back.
      if (_playback.isEnded) _setCardAside(true);
      // A piece in hand on a board the viewer has may be dragged: the feed
      // holds still under it, the same lock the 2x hold uses.
      if (_dragAllowed && _boardSelection != null && !_dragLock) {
        _dragLock = true;
        widget.onScrollLock(true);
      }
      _syncHeld();
      return;
    }

    _pointer = e.pointer;
    _downLocal = e.localPosition;
    _moved = false;
    _menuTriggered = false;
    _holdTimer?.cancel();
    _menuTimer?.cancel();
    _tapWindow?.cancel();
    _tapWindow = Timer(_tapMaxDuration, () => _tapWindow = null);

    if (_playback.isEnded) return;
    final inHoldZone =
        _zoneWidth > 0 && e.localPosition.dx / _zoneWidth > _holdZoneStart;
    if (inHoldZone && _line == null) {
      _holdTimer = Timer(_holdDelay, _startHold);
    } else if (_boardRect.contains(e.localPosition)) {
      _menuTimer = Timer(_menuDelay, () {
        _menuTimer = null;
        _menuTriggered = true;
        unawaited(_showMenu());
      });
    }
  }

  void _onZoneMove(PointerMoveEvent e) {
    if (e.pointer != _pointer || _holding || _moved) return;
    final onBoard = e.pointer == _boardPointer;
    final slop = onBoard ? kTouchSlop : _moveSlop;
    if ((e.localPosition - _downLocal).distance <= slop) return;
    _moved = true;
    if (onBoard) {
      // A drag on a board the viewer has carries the piece.
      if (_dragLock) return;
      // While the clip plays pieces move tap-tap, so a finger that travels
      // is the feed's swipe: the piece it picked up goes back down instead
      // of riding the page away and holding the clip. The promotion picker
      // stays up.
      if (_board.pendingPromotion == null) _dropSelection();
      return;
    }
    _holdTimer?.cancel();
    _menuTimer?.cancel();
    _holdTimer = _menuTimer = null;
  }

  void _onZoneUp(PointerUpEvent e) {
    if (e.pointer != _pointer) return;
    _pointer = null;
    if (e.pointer == _boardPointer) {
      _boardPointer = null;
      _releaseDragLock();
      _syncHeld();
      return;
    }
    _holdTimer?.cancel();
    _menuTimer?.cancel();
    _holdTimer = _menuTimer = null;
    final wasTap = _tapWindow != null;
    _tapWindow?.cancel();
    _tapWindow = null;

    if (_holding) {
      _endHold();
      return;
    }
    if (_menuTriggered || _moved || !wasTap) return;

    if (_singleTap != null) {
      // Second tap inside the window: a like, not two pauses.
      _singleTap!.cancel();
      _singleTap = null;
      _doubleTapLike(e.localPosition);
      return;
    }
    _singleTap = Timer(_doubleTapWindow, () {
      _singleTap = null;
      if (!mounted) return;
      // A stray tap never throws away the viewer's own line; that is what
      // "Back to game" is for.
      if (_line != null) return;
      if (_playback.isEnded) {
        // Nothing left to pause: the tap moves the result card off the
        // board, so the whole final position can be seen and played, or
        // brings it back over the ending as it fell (the king back down).
        HapticFeedbackService.selection();
        if (_cardAside && _kingUp) {
          _kingUp = false;
          _pushBoard();
        }
        _setCardAside(!_cardAside);
        return;
      }
      _playback.togglePause();
    });
  }

  void _onZoneCancel(PointerCancelEvent e) {
    if (e.pointer != _pointer) return;
    _pointer = null;
    if (e.pointer == _boardPointer) {
      _boardPointer = null;
      _releaseDragLock();
      _syncHeld();
      return;
    }
    _holdTimer?.cancel();
    _menuTimer?.cancel();
    _tapWindow?.cancel();
    _holdTimer = _menuTimer = _tapWindow = null;
    if (_holding) _endHold();
  }

  /// A control inside the zone (the result card or its buttons) handled this
  /// tap itself, so the zone must not also read it as pause.
  void _consumeZoneTap() {
    _singleTap?.cancel();
    _singleTap = null;
  }

  void _startHold() {
    _holdTimer = null;
    if (!mounted ||
        _playback.isEnded ||
        !widget.isCurrent ||
        _line != null ||
        _playback.isHeld) {
      return;
    }
    _holding = true;
    _ripple = _downLocal;
    _rippleSeq++;
    widget.onScrollLock(true);
    HapticFeedbackService.selection();
    _playback.setFast(true);
    setState(() {});
  }

  void _endHold() {
    _holding = false;
    _ripple = null;
    widget.onScrollLock(false);
    _playback.setFast(false);
    if (!_syncing && mounted) setState(() {});
  }

  // ------------------------------------------------------------------ likes

  void _doubleTapLike(Offset zoneLocal) {
    final liked = ref.read(isGameLikedProvider(_game.likeId));
    HapticFeedbackService.medium();
    final zoneBox = _zoneKey.currentContext?.findRenderObject() as RenderBox?;
    final from = zoneBox != null && zoneBox.hasSize
        ? zoneBox.localToGlobal(zoneLocal)
        : null;
    _burst.spawn(
      position: zoneLocal,
      onFinished: () {
        if (from != null) _flyHeart(from);
      },
    );
    // Double-tap only ever likes; unliking is the button's job.
    if (!liked) unawaited(_toggleLike(haptic: false));
  }

  void _flyHeart(Offset from) {
    if (!mounted) return;
    final target =
        _likeIconKey.currentContext?.findRenderObject() as RenderBox?;
    if (target == null || !target.hasSize) return;
    final to = target.localToGlobal(target.size.center(Offset.zero));
    _flight?.remove();
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => FlyingHeart(
        from: from,
        to: to,
        color: context.colors.danger,
        startSize: _heartSize,
        endSize: 22,
        duration: const Duration(milliseconds: 470),
        onArrived: () {
          if (_flight == entry) {
            entry.remove();
            _flight = null;
          }
          HapticFeedbackService.selection();
        },
      ),
    );
    _flight = entry;
    Overlay.of(context, rootOverlay: true).insert(entry);
  }

  Future<void> _toggleLike({bool haptic = true}) async {
    if (haptic) HapticFeedbackService.light();
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      await ref.read(likedGamesProvider.notifier).toggle(_game);
    } catch (error) {
      debugPrint('[Feed] like toggle failed: $error');
      if (messenger != null) {
        showAppSnackOn(
          messenger,
          userFacingError(error, fallback: "Couldn't update your like."),
          tone: AppSnackTone.danger,
        );
      }
    }
  }

  // --------------------------------------------------------------- actions

  SpaceShortcut? get _spaceDraft =>
      gameSpaceShortcutDraft(_game, subtitle: _item.eventLabel);

  void _openGame() {
    HapticFeedbackService.cardTap();
    final fromArchive = _game.source != GameSource.supabase;
    ref
        .read(gameCardWrapperProvider)
        .navigateToChessBoard(
          context: context,
          orderedGames: [_game],
          gameIndex: 0,
          onReturnFromChessboard: null,
          viewSource: ChessboardView.forYou,
          playerProfileDataSource: fromArchive
              ? PlayerProfileDataSource.twic
              : PlayerProfileDataSource.supabase,
          showClock: !fromArchive,
        );
  }

  /// The board screen's own share flow, pinned to the position on the
  /// board. In the viewer's own line the game is shared where the line left
  /// it (the board's pixels show the line, so they are not reused then).
  void _share() {
    HapticFeedbackService.buttonPress();
    final line = _line;
    final shown = line?.forkPly ?? _playback.shownPly;
    unawaited(
      shareFeedGame(
        context,
        ref,
        item: _item,
        shownPly: shown,
        boardBoundary: line == null ? _shareBoundaryKey : null,
        eval: line == null ? _shownEval : null,
      ),
    );
  }

  Future<void> _toggleSpace(SpaceShortcut draft) async {
    await toggleSpaceShortcut(context: context, ref: ref, draft: draft);
  }

  /// The event the game was played in: a broadcast opens its event page, an
  /// archive game (a miniature) opens the ChessEver Database on that event.
  Future<void> _openEvent() async {
    HapticFeedbackService.navigation();
    final game = _game;
    if (game.source == GameSource.supabase) {
      final opened = await DeepLinkService.instance.openEventForShortcut(
        tourId: game.tourId,
        roundId: game.roundId,
      );
      if (!opened && mounted) {
        showAppSnack(
          context,
          "Couldn't open this event",
          tone: AppSnackTone.danger,
        );
      }
      return;
    }
    // Archive rows carry the gamebase event name in tourId; "Miniatures" is
    // only the fallback label for rows with no event.
    final archiveEvent = game.tourId.trim();
    final event = archiveEvent.isNotEmpty && archiveEvent != 'Miniatures'
        ? archiveEvent
        : (_item.eventLabel?.trim() ?? '');
    if (event.isEmpty || !mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TwicContentsScreen(initialEvent: event),
      ),
    );
  }

  /// The opening's position, set up in the board editor.
  void _openOpening(String fen) {
    HapticFeedbackService.navigation();
    unawaited(
      Navigator.of(
        context,
      ).push(MaterialPageRoute<void>(builder: (_) => boardEditorAt(fen))),
    );
  }

  Future<void> _showMenu() async {
    final boardContext = _boardKey.currentContext;
    if (_menuOpen || boardContext == null || !mounted) return;
    final draft = _spaceDraft;
    final view = _view();
    final size = _boardRect.width;
    setState(() => _menuOpen = true);
    _syncSuspended();
    _pushBoard();
    try {
      await showLibraryContextMenu(
        context: boardContext,
        previewBuilder: (_) => FeedBoard(
          size: size,
          fen: view.position?.fen ?? view.fen,
          lastMove: view.lastMove,
        ),
        actions: [
          LibraryMenuAction(
            icon: Icons.north_east_rounded,
            label: 'Open game',
            onSelected: _openGame,
          ),
          LibraryMenuAction(
            icon: Icons.ios_share_rounded,
            label: 'Share',
            onSelected: _share,
          ),
          if (draft != null)
            spaceMenuAction(context: context, ref: ref, draft: draft),
        ],
      );
    } finally {
      if (mounted) {
        setState(() => _menuOpen = false);
        _syncSuspended();
        _pushBoard();
      }
    }
  }

  // ---------------------------------------------------------------- scrub

  void _onScrubStart(double f) {
    if (_item.plyCount <= 0) return;
    _cancelGestures();
    // Scrubbing is the game line; the viewer's own line gives way.
    _line = null;
    _playback.beginScrub((f * _item.plyCount).round());
  }

  void _onScrubUpdate(double f) {
    if (!_playback.isScrubbing) return;
    final target = (f * _item.plyCount).round();
    if (target == _playback.shownPly) return;
    final moment = _item.plies[target.clamp(0, _item.plyCount)].moment;
    if (feedIsChartDot(moment) || (moment?.isHeadline ?? false)) {
      HapticFeedbackService.selection();
    }
    _playback.scrubTo(target);
  }

  void _onScrubEnd() => _playback.endScrub();

  // ----------------------------------------------------------------- build

  static Move? _moveOf(FeedPly ply) {
    final uci = ply.uci;
    if (uci == null || uci.isEmpty) return null;
    try {
      return Move.parse(uci);
    } catch (_) {
      return null;
    }
  }

  /// "Start", then every game move: "1." before White's moves (and before
  /// Black's when the game starts with Black), the class on each.
  List<FeedStripToken> _gameTokens() {
    return _tokens ??= [
      const FeedStripToken(san: 'Start'),
      for (var i = 1; i < _item.plies.length; i++)
        FeedStripToken(
          number: feedMoveNumberLabel(_item, i, opensRun: i == 1),
          san: _item.plies[i].san ?? '',
          moveClass: _item.plies[i].effectiveClass,
        ),
    ];
  }

  /// "Your line" first, the way the game's own strip opens on "Start": it
  /// is the fork position the line branches from. Then the viewer's moves,
  /// so token `i` is line cursor `i - 1`.
  List<FeedStripToken> _lineTokens(FeedExploration line) => [
    const FeedStripToken(san: 'Your line'),
    for (var j = 0; j < line.moves.length; j++)
      FeedStripToken(number: line.numberAt(j), san: line.moves[j].san),
  ];

  /// [showEval] is the eval bar's own visibility: the number beside the
  /// transport is the bar's value, so it hides with it (engine off, No
  /// Spoilers, gauge off).
  Widget _buildStrip(FeedLayout l, int shown, {required bool showEval}) {
    final colors = context.colors;
    final line = _line;
    if (line != null) {
      final cursor = line.cursor;
      return FeedMoveStrip(
        tokens: _lineTokens(line),
        current: cursor + 1,
        height: l.infoHeight,
        onTokenTap: (i) => _jumpInLine(i - 1),
        trailing: [
          FeedStepButton(
            glyph: FeedGlyphs.stepBack,
            semanticsLabel: 'Previous move',
            onTap: cursor >= 0 ? () => _jumpInLine(cursor - 1) : null,
          ),
          FeedStepButton(
            glyph: FeedGlyphs.stepForward,
            semanticsLabel: 'Next move',
            onTap: cursor < line.moves.length - 1
                ? () => _jumpInLine(cursor + 1)
                : null,
          ),
          const SizedBox(width: 4),
          FeedBackToGameButton(onTap: _backToGame, height: l.infoHeight),
        ],
      );
    }

    final p = _playback;
    final evalText = showEval ? feedEvalText(_item, shown) : '';
    final playing = p.isPlaying;
    return FeedMoveStrip(
      tokens: _gameTokens(),
      current: shown,
      height: l.infoHeight,
      onTokenTap: _stepTo,
      trailing: [
        if (evalText.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 6, right: 2),
            child: Text(
              evalText,
              maxLines: 1,
              style: AppTypography.textXsBold.copyWith(
                fontSize: 13,
                height: 1.2,
                fontWeight: FontWeight.w600,
                color: colors.textPrimaryMuted,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        FeedStepButton(
          glyph: FeedGlyphs.stepBack,
          semanticsLabel: 'Previous move',
          onTap: shown > 0 ? () => _stepTo(shown - 1) : null,
        ),
        FeedStepButton(
          key: const ValueKey('feed_play_toggle'),
          glyph: playing ? FeedGlyphs.pause : FeedGlyphs.playSmall,
          semanticsLabel: playing ? 'Pause' : 'Play',
          onTap: _togglePlay,
        ),
        FeedStepButton(
          glyph: FeedGlyphs.stepForward,
          semanticsLabel: 'Next move',
          onTap: shown < p.lastPly ? () => _stepTo(shown + 1) : null,
        ),
      ],
    );
  }

  // --------------------------------------------------------------- header

  /// The header's opening as a board-editor position; worked out once per
  /// item.
  String? get _openingFen {
    if (!_openingFenResolved) {
      _openingFenResolved = true;
      _openingFenValue = feedOpeningFen(_game, _item.plies);
    }
    return _openingFenValue;
  }

  /// The one line over the board: time control, the signal that earned the
  /// game its place, the event and the opening (both tappable).
  Widget _buildHeader(FeedLayout l) {
    final game = _game;
    final parts = <FeedHeaderPart>[];

    final signal = _item.signal;
    final signalPart = signal == null ? null : _signalPart(signal);
    final signalAt = signalPart == null ? null : parts.length;
    if (signalPart != null) parts.add(signalPart);

    final event = _item.eventLabel?.trim() ?? '';
    final eventAt = event.isEmpty ? null : parts.length;
    if (event.isNotEmpty) {
      parts.add(
        FeedHeaderPart(
          id: 'event',
          pieces: [FeedHeaderPiece.text(event)],
          shrinkable: true,
          onTap: () => unawaited(_openEvent()),
          semanticsLabel: 'Open event $event',
        ),
      );
    }

    final code = feedEcoCode(game);
    final name = game.openingName?.trim() ?? '';
    final hasOpening = code != null || name.isNotEmpty;
    final openingAt = hasOpening ? parts.length : null;
    if (hasOpening) {
      final fen = _openingFen;
      final title = [?code, if (name.isNotEmpty) name].join(' ');
      parts.add(
        FeedHeaderPart(
          id: 'opening',
          pieces: [
            if (code != null)
              FeedHeaderPiece.text(code, tone: FeedHeaderTone.strong),
            if (code != null && name.isNotEmpty) const FeedHeaderPiece.gap(5),
            if (name.isNotEmpty)
              FeedHeaderPiece.text(name, tone: FeedHeaderTone.secondary),
          ],
          compact: code != null && name.isNotEmpty
              ? [FeedHeaderPiece.text(code, tone: FeedHeaderTone.strong)]
              : null,
          shrinkable: true,
          onTap: fen == null ? null : () => _openOpening(fen),
          semanticsLabel: fen == null
              ? title
              : 'Open $title in the board editor',
        ),
      );
    }

    final timeControl = feedTimeControlOf(game, event);
    return FeedPostHeader(
      key: const ValueKey('feed_post_header'),
      height: l.metaHeight,
      // The app's shared time-control mark: light mode draws its baked
      // paper twins, dark the original art.
      leading: timeControl == null
          ? null
          : TimeControlGlyph(
              timeControl.asset,
              size: 16,
              semanticLabel: timeControl.label,
            ),
      leadingWidth: 16,
      parts: parts,
      compactOrder: [?signalAt, ?openingAt],
      shrinkOrder: [?eventAt, ?openingAt, ?signalAt],
      dropOrder: [?signalAt],
    );
  }

  FeedHeaderPart? _signalPart(FeedSignal signal) {
    final colors = context.colors;
    switch (signal.kind) {
      case FeedSignalKind.favorite:
        final name = signal.name?.trim() ?? '';
        if (name.isEmpty) return null;
        final heart = FeedHeaderPiece.glyph(
          FeedGlyph(
            FeedGlyphs.heartFilled,
            width: 12,
            height: 11,
            color: colors.danger,
          ),
          width: 12,
        );
        return FeedHeaderPart(
          id: 'signal',
          pieces: [
            const FeedHeaderPiece.text(
              'Your favorite',
              tone: FeedHeaderTone.secondary,
            ),
            const FeedHeaderPiece.gap(5),
            heart,
            const FeedHeaderPiece.gap(5),
            FeedHeaderPiece.text(name, tone: FeedHeaderTone.strong),
          ],
          compact: [
            heart,
            const FeedHeaderPiece.gap(5),
            FeedHeaderPiece.text(
              feedSurname(name),
              tone: FeedHeaderTone.strong,
            ),
          ],
          shrinkable: true,
          semanticsLabel: 'Your favorite $name',
        );
      case FeedSignalKind.streak:
        final name = signal.name?.trim() ?? '';
        final count = signal.count ?? 0;
        if (name.isEmpty || count <= 0) return null;
        final flame = FeedHeaderPiece.glyph(
          PixelFlame(streak: count, size: 14),
          width: 9,
        );
        final run = FeedHeaderPiece.text(
          ' $count in a row',
          tone: FeedHeaderTone.secondary,
        );
        return FeedHeaderPart(
          id: 'signal',
          pieces: [
            flame,
            const FeedHeaderPiece.gap(6),
            FeedHeaderPiece.text(name, tone: FeedHeaderTone.strong),
            run,
          ],
          compact: [
            flame,
            const FeedHeaderPiece.gap(6),
            FeedHeaderPiece.text(
              feedSurname(name),
              tone: FeedHeaderTone.strong,
            ),
            run,
          ],
          shrinkable: true,
          semanticsLabel: '$name, $count wins in a row',
        );
      case FeedSignalKind.miniature:
        return const FeedHeaderPart(
          id: 'signal',
          pieces: [
            FeedHeaderPiece.text('Miniature', tone: FeedHeaderTone.secondary),
          ],
        );
      case FeedSignalKind.liked:
        final count = signal.count ?? 0;
        if (count <= 0) return null;
        final heart = FeedHeaderPiece.glyph(
          FeedGlyph(
            FeedGlyphs.heartOutline,
            width: 12,
            height: 11,
            color: colors.textSecondary,
          ),
          width: 12,
        );
        return FeedHeaderPart(
          id: 'signal',
          pieces: [
            heart,
            const FeedHeaderPiece.gap(5),
            FeedHeaderPiece.text('$count', tone: FeedHeaderTone.strong),
            const FeedHeaderPiece.text(
              ' today',
              tone: FeedHeaderTone.secondary,
            ),
          ],
          compact: [
            heart,
            const FeedHeaderPiece.gap(5),
            FeedHeaderPiece.text('$count', tone: FeedHeaderTone.strong),
          ],
          semanticsLabel: count == 1
              ? 'Liked once today'
              : 'Liked $count times today',
        );
      case FeedSignalKind.upset:
        final points = signal.count ?? 0;
        if (points <= 0) return null;
        return FeedHeaderPart(
          id: 'signal',
          pieces: [
            FeedHeaderPiece.text('$points-point', tone: FeedHeaderTone.strong),
            const FeedHeaderPiece.text(
              ' upset',
              tone: FeedHeaderTone.secondary,
            ),
          ],
          compact: const [
            FeedHeaderPiece.text('Upset', tone: FeedHeaderTone.secondary),
          ],
          semanticsLabel: 'Upset, the winner was rated $points points lower',
        );
    }
  }

  // ------------------------------------------------------------------ rows

  /// A player row, the game cards' own: the same widget, the same model,
  /// so titles, ratings, flags, clocks and the result match a card exactly.
  /// The result waits for [revealResult] (the replay's last move, on the
  /// game's own line) so the clip never prints the outcome up front.
  Widget _playerRow(
    FeedLayout l, {
    required bool white,
    required bool revealResult,
  }) {
    final game = _game;
    final side = white ? Side.white : Side.black;
    return SizedBox(
      height: l.rowHeight,
      child: Align(
        alignment: Alignment.centerLeft,
        child: PlayerFirstRowDetailWidget(
          key: ValueKey(white ? 'feed_row_white' : 'feed_row_black'),
          gamesTourModel: game,
          isWhitePlayer: white,
          isCurrentPlayer: game.activePlayer == side,
          playerView: PlayerView.listView,
          showClock: game.hasStarted,
          scoreCardViewSource: ChessboardView.forYou,
          scoreCardGamesContext: [game],
          playerProfileDataSource: game.source == GameSource.supabase
              ? PlayerProfileDataSource.supabase
              : PlayerProfileDataSource.twic,
          nameMenu: true,
          revealResult: revealResult,
        ),
      ),
    );
  }

  // ------------------------------------------------------------ eval bar

  /// What the clip may say about the engine, by the board screen's rules.
  /// [evals] is the engine toggle and an event's No Spoilers: it gates the
  /// report chart. [bar] adds the on-board gauge setting: it gates the eval
  /// bar and the move strip's number, which is the bar's value in words.
  /// Whether the viewer had liked the game when the post was first built,
  /// so a like or unlike here moves the loaded count by one.
  bool? _likedAtOpen;

  /// The count the Like button shows: Feed's loaded count, moved by the
  /// viewer's own like or unlike since.
  int _likesShown(bool liked) {
    final base = widget.item.likes;
    if (base <= 0) return 0;
    final delta = (liked ? 1 : 0) - ((_likedAtOpen ?? liked) ? 1 : 0);
    return (base + delta).clamp(0, 1 << 30).toInt();
  }

  ({bool bar, bool evals}) _watchEvalVisibility() {
    final gauge = ref.watch(
      engineSettingsProviderNew.select(
        (s) => s.valueOrNull?.shouldShowEngineGaugeOnBoard ?? true,
      ),
    );
    final analysis = ref.watch(
      engineSettingsProviderNew.select(
        (s) => s.valueOrNull?.showEngineAnalysis ?? true,
      ),
    );
    final game = _game;
    final hidden =
        game.source == GameSource.supabase &&
        ref.watch(
          eventNoSpoilersProvider(game.tourId).select(
            (state) => shouldHideEventEvaluation(
              isBroadcastGame: true,
              spoilerState: state,
            ),
          ),
        );
    final evals = analysis && !hidden;
    return (bar: gauge && evals, evals: evals);
  }

  /// The number for the position on the board. A finished position speaks
  /// for itself (mate, or a drawn end, as the board screen scores them); the
  /// game line uses the PGN's own evals; anything else asks
  /// [feedPositionEvalProvider]: the cache while the clip plays, the engine
  /// (the viewer's gauge settings) once the viewer has the board.
  FeedEval _watchEval(_BoardView view, {required bool exploring}) {
    final position = view.position;
    if (position == null) return FeedEval.none;
    if (position.isCheckmate) {
      return FeedEval(pawns: position.turn == Side.white ? -100 : 100);
    }
    if (position.isGameOver) return const FeedEval(pawns: 0);
    if (!exploring && _item.hasEvals) {
      final e = feedEvalAt(_item, _playback.shownPly);
      if (e != null) {
        final mate = e.mate;
        return mate != null && mate != 0
            ? FeedEval(mate: mate)
            : FeedEval(pawns: e.cp! / 100);
      }
    }
    if (!(widget.isCurrent && widget.isVisible)) return FeedEval.none;
    final request = FeedEvalRequest(
      position.fen,
      allowEngine: _dragAllowed && !_playback.isScrubbing,
    );
    final value = ref.watch(feedPositionEvalProvider(request));
    return value.valueOrNull ?? FeedEval.pending;
  }

  @override
  Widget build(BuildContext context) {
    if (_item.plies.isEmpty) {
      return FeedMessage(
        title: 'This game has no moves',
        body: 'It will play here once its moves come in.',
        actionLabel: 'Next game',
        onAction: widget.onRequestNext,
      );
    }

    final colors = context.colors;
    final liked = ref.watch(isGameLikedProvider(_game.likeId));
    _likedAtOpen ??= liked;
    final draft = _spaceDraft;
    final inSpace = draft == null
        ? null
        : ref.watch(spaceShortcutExistsProvider(draft.key));
    final evalVisibility = _watchEvalVisibility();
    final showBar = evalVisibility.bar;

    final p = _playback;
    final line = _line;
    final exploring = line != null;
    final shown = p.shownPly.clamp(0, _item.plies.length - 1);
    final ply = _item.plies[shown];
    // The rows print the result only on the game's final position.
    final revealResult = !exploring && shown >= _item.plies.length - 1;
    // The report chart is an eval curve, so it keeps to the same rules as the
    // bar's number; with evals hidden the scrub shows the move bubble.
    final showChart = p.isScrubbing && _item.hasEvals && evalVisibility.evals;
    final showBubble = p.isScrubbing && !showChart;
    // The result card steps aside while the viewer plays the final position.
    final showEndCard =
        p.isEnded && !p.isScrubbing && !exploring && !_cardAside && !p.isHeld;
    final view = _view();
    final eval = showBar
        ? _watchEval(view, exploring: exploring)
        : FeedEval.none;
    _shownEval = eval.hasValue ? eval : null;

    final moment = shown > 0 ? ply.moment : null;
    final caption =
        (moment?.isHeadline ?? false) &&
            !p.isEnded &&
            !p.isScrubbing &&
            !exploring
        ? moment
        : null;

    final String boardLabel;
    if (line != null) {
      final where = line.cursor < 0
          ? feedMoveLabel(_item, line.forkPly)
          : line.labelAt(line.cursor);
      boardLabel = 'Board, your line, $where';
    } else {
      boardLabel = 'Board, ${feedMoveLabel(_item, shown)}';
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final l = FeedLayout.resolve(
          constraints,
          MediaQuery.textScalerOf(context),
          evalWidth: showBar ? 20.w : 0,
        );
        _zoneWidth = l.contentWidth;
        _boardRect = Rect.fromLTWH(l.evalWidth, 0, l.board, l.board);
        _heartSize = l.board * 0.45;

        final n = math.max(1, _item.plyCount);
        final progress = _item.plyCount <= 0 ? 1.0 : shown / n;
        final track = l.width - 2 * l.contentLeft;
        final bubbleX = (l.contentLeft + track * progress)
            .clamp(60.0, math.max(60.0, l.width - 60))
            .toDouble();

        // The board column: eval bar, board and the player rows, centred
        // when the board is height-bound.
        Widget content(Widget child) => Padding(
          padding: EdgeInsets.only(left: l.contentLeft),
          child: Align(
            alignment: Alignment.centerLeft,
            child: SizedBox(width: l.contentWidth, child: child),
          ),
        );

        // The text rows (header, move strip, actions) keep the page gutter,
        // so a height-bound board never squeezes their words.
        Widget fullRow(Widget child) => Padding(
          padding: const EdgeInsets.only(left: FeedLayout.sidePadding),
          child: Align(
            alignment: Alignment.centerLeft,
            child: SizedBox(width: l.rowWidth, child: child),
          ),
        );

        final board = SizedBox.square(
          key: _boardKey,
          dimension: l.board,
          // The pointer zone is a raw Listener, so screen readers get the same
          // two board actions here explicitly.
          child: Semantics(
            label: boardLabel,
            onTapHint: p.isUserPaused ? 'play' : 'pause',
            onTap: p.isEnded || exploring ? null : _playback.togglePause,
            onLongPressHint: 'game actions',
            onLongPress: () => unawaited(_showMenu()),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // What Share captures: the board with its badges, as seen.
                RepaintBoundary(
                  key: _shareBoundaryKey,
                  child: FeedLiveBoard(
                    controller: _board,
                    size: l.board,
                    allowDrag: _dragAllowed,
                    onMove: _onUserMove,
                    onTouchedSquare: _onTouchedSquare,
                    badgeSquare: feedLandingSquare(view.lastMove, view.before),
                    badgeClass: view.badgeClass,
                    badgeTrigger: exploring ? 'line' : shown,
                    landingSquare: _landingSquare,
                    landingClass: _landingClass,
                    landingTrigger: _landingSeq,
                    fallenSquare: view.fallenSquare,
                    fallenSide: view.fallenSide,
                  ),
                ),
                if (caption != null)
                  Positioned(
                    left: 8,
                    right: 8,
                    top: l.board * 0.3 - 16,
                    child: Center(
                      child: FeedCaption(
                        label: caption.label,
                        color: feedJudgmentColor(caption) ?? kFeedOnBoardInk,
                      ),
                    ),
                  ),
                if (p.showsPauseGlyph && !exploring)
                  const Positioned.fill(child: FeedPausedOverlay()),
                if (p.isFast && !p.isScrubbing)
                  const Positioned.fill(child: FeedFastOverlay()),
                if (showEndCard)
                  Positioned(
                    left: 16,
                    right: 16,
                    bottom: 16,
                    // A tap on the card itself (its buttons answer their own)
                    // moves it off the board, so the pieces under it can be
                    // seen and played; a tap on the board brings it back.
                    child: GestureDetector(
                      excludeFromSemantics: true,
                      onTap: () {
                        _consumeZoneTap();
                        HapticFeedbackService.selection();
                        _setCardAside(true);
                      },
                      child: FeedEndCard(
                        result: feedResultLabel(_item),
                        detail: feedResultDetail(_item),
                        countdown: _countdown,
                        onReplay: () {
                          _consumeZoneTap();
                          HapticFeedbackService.buttonPress();
                          _countdown.value = 0;
                          _playback.restart();
                        },
                        onNext: () {
                          _consumeZoneTap();
                          HapticFeedbackService.buttonPress();
                          widget.onRequestNext();
                        },
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );

        // The board and its eval bar are the gesture zone; the header and
        // the player rows keep their own taps.
        final zone = Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: _onZoneDown,
          onPointerMove: _onZoneMove,
          onPointerUp: _onZoneUp,
          onPointerCancel: _onZoneCancel,
          child: Stack(
            key: _zoneKey,
            clipBehavior: Clip.none,
            children: [
              Row(
                children: [
                  if (showBar)
                    EvaluationBarWidget(
                      key: const ValueKey('feed_eval_bar'),
                      width: l.evalWidth,
                      height: l.board,
                      isFlipped: false,
                      evaluation: _barEvaluation(eval),
                      mate: eval.mate,
                      isEvaluating: eval.evaluating,
                      isWhiteToMove: view.position?.turn != Side.black,
                      positionKey: view.position?.fen ?? view.fen,
                      // "#", as the game card and the move strip say, not
                      // the ±100 the bar is filled with.
                      isCheckmate: view.position?.isCheckmate ?? false,
                    ),
                  board,
                ],
              ),
              Positioned.fill(
                child: HeartBurstLayer(
                  controller: _burst,
                  color: colors.danger,
                  heartSize: _heartSize,
                  reduceMotion: MediaQuery.disableAnimationsOf(context),
                ),
              ),
              if (_ripple != null)
                FeedHoldRipple(key: ValueKey(_rippleSeq), center: _ripple!),
            ],
          ),
        );

        // While the chart is up it carries the move line itself.
        final lowerOpacity = showChart ? 0.0 : 1.0;

        return Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: FeedLayout.topGap),
                fullRow(_buildHeader(l)),
                const SizedBox(height: FeedLayout.gap),
                content(
                  _playerRow(l, white: false, revealResult: revealResult),
                ),
                const SizedBox(height: FeedLayout.gap),
                content(zone),
                const SizedBox(height: FeedLayout.gap),
                content(_playerRow(l, white: true, revealResult: revealResult)),
                const SizedBox(height: FeedLayout.infoGap),
                fullRow(
                  IgnorePointer(
                    ignoring: showChart,
                    child: Opacity(
                      opacity: lowerOpacity,
                      child: RepaintBoundary(
                        child: _buildStrip(l, shown, showEval: showBar),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: FeedLayout.actionsGap),
                fullRow(
                  Opacity(
                    opacity: lowerOpacity,
                    child: FeedActionRow(
                      height: l.actionsHeight,
                      liked: liked,
                      likes: _likesShown(liked),
                      inSpace: inSpace,
                      likeIconKey: _likeIconKey,
                      onLike: () => unawaited(_toggleLike()),
                      onSpace: () {
                        if (draft != null) unawaited(_toggleSpace(draft));
                      },
                      onShare: _share,
                      onAnalyze: _openGame,
                    ),
                  ),
                ),
                const Spacer(),
                FeedScrubStrip(
                  progress: progress,
                  scrubbing: p.isScrubbing,
                  fast: p.isFast,
                  inset: l.contentLeft,
                  semanticsValue: feedPlyText(_item, shown),
                  onStart: _onScrubStart,
                  onUpdate: _onScrubUpdate,
                  onEnd: _onScrubEnd,
                ),
              ],
            ),
            if (showChart)
              Positioned(
                left: 0,
                right: 0,
                top: l.boardBottom - 10,
                bottom: FeedLayout.scrubHeight,
                child: FeedReportOverlay(
                  item: _item,
                  ply: shown,
                  chartWidth: l.contentWidth,
                ),
              ),
            if (showBubble) ...[
              if (!_item.hasEvals)
                Positioned(
                  left: l.contentLeft,
                  bottom: FeedLayout.scrubHeight + 34,
                  child: IgnorePointer(
                    child: Text(
                      'No report for this game yet',
                      style: AppTypography.textXxsMedium.copyWith(
                        fontSize: 11,
                        height: 14 / 11,
                        color: colors.textSecondary,
                      ),
                    ),
                  ),
                ),
              Positioned(
                left: bubbleX,
                bottom: FeedLayout.scrubHeight + 2,
                child: FeedMoveBubble(item: _item, ply: shown),
              ),
            ],
          ],
        );
      },
    );
  }

  /// What the bar's number is: pawns, or ±10 for a mate so the bar fills
  /// and reads "#N" the way the board screen's does.
  static double? _barEvaluation(FeedEval eval) {
    final mate = eval.mate;
    if (mate != null && mate != 0) return mate > 0 ? 10.0 : -10.0;
    return eval.pawns;
  }
}

/// The time-control mark for [game]: its recorded time control first, then
/// the event's own words ("Blitz", "Rapid", "Titled Tuesday"). Null when
/// neither says, never a guess.
({String asset, String label})? feedTimeControlOf(
  GamesTourModel game,
  String event,
) {
  final recorded = game.timeControl?.trim().toLowerCase() ?? '';
  switch (recorded) {
    case 'standard':
    case 'classical':
      return (asset: PngAsset.classicalIcon, label: 'Classical');
    case 'rapid':
      return (asset: PngAsset.rapidIcon, label: 'Rapid');
    case 'blitz':
    case 'bullet':
      return (asset: PngAsset.blitzIcon, label: 'Blitz');
  }
  final words = '$event ${game.tourSlug ?? ''}'.toLowerCase();
  if (words.contains('blitz') ||
      words.contains('bullet') ||
      words.contains('titled') ||
      words.contains('speed chess')) {
    return (asset: PngAsset.blitzIcon, label: 'Blitz');
  }
  if (words.contains('rapid')) {
    return (asset: PngAsset.rapidIcon, label: 'Rapid');
  }
  if (words.contains('classical')) {
    return (asset: PngAsset.classicalIcon, label: 'Classical');
  }
  return null;
}
