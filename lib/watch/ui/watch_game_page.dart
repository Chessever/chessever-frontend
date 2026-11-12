import 'dart:async';
import 'dart:math' as math;
import 'package:chessever_watch_bridge/chessever_watch_bridge.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_watchos/flutter_watchos.dart';
import '../../repository/supabase/game/games.dart';
import '../core/watch_eval.dart';
import '../core/watch_models.dart';
import '../core/watch_replay.dart';
import '../core/watch_sound.dart';
import '../watch_controller.dart';
import 'watch_board.dart';
import 'watch_event_boards_page.dart' show WatchPlayerLine;
import 'watch_event_pages.dart';
import 'watch_visuals.dart';
import 'watch_widgets.dart';

/// The hero tag a board carries from a list into its game page.
String watchBoardHeroTag(String gameId) => 'watch-board-$gameId';

/// A game on the wrist as the board itself: it grows out of its tile into
/// the first screen between the clock band and the display's rounded
/// bottom, with the engine's bar beside it. Black's line sits above the
/// board, White's below, both on the board's edges. The Digital Crown steps
/// through the moves from the moment the page opens (it scrolls until the
/// moves arrive); two arrows rest in the gutters beside the board, bright
/// for a moment and then quieter. A sideways swipe changes games within the
/// list the game came from. Everything else is one finger scroll below.
class WatchGamePage extends StatefulWidget {
  const WatchGamePage({
    super.key,
    required this.controller,
    required this.game,
    this.tour,
    this.games = const [],
    this.tours = const [],
  });
  final WatchController controller;
  final Games game;

  /// The section of [game], for its players' scorecards.
  final WatchTour? tour;

  /// The boards a sideways swipe moves between, in list order. Empty: only
  /// [game].
  final List<Games> games;

  /// Sections of [games], so a swiped-to board finds its scorecards.
  final List<WatchTour> tours;

  /// Label of the row that closes the page.
  static const backLabel = 'Back to boards';

  /// The engine bar and its gap, to the left of the board.
  static const evalBarWidth = 6.0;
  static const evalBarGap = 4.0;

  /// Space between a player line and the board.
  static const lineGap = 3.0;

  /// The narrowest gutter beside the board and its bar: room for an arrow
  /// glyph, and clear of the display's rounded corners.
  static const minGutter = 24.0;

  @override
  State<WatchGamePage> createState() => _WatchGamePageState();
}

class _WatchGamePageState extends State<WatchGamePage>
    with WidgetsBindingObserver {
  late final List<Games> _games = widget.games.isEmpty
      ? [widget.game]
      : List.of(widget.games);
  late int _index = math.max(
    0,
    _games.indexWhere((g) => g.id == widget.game.id),
  );
  late Games _game = _games[_index];
  DateTime? _fetchedAt;
  bool _busy = false;
  bool _flipped = false;
  String? _error;
  String? _handoff;
  bool _sending = false;
  Timer? _timer;

  // Move review.
  final _dial = WatchReplayDial();
  final _wheel = WatchReplayDial();
  final _scroll = ScrollController();
  final _hapticClock = Stopwatch()..start();
  int _lastHapticMs = -100;
  StreamSubscription<CrownRotationEvent>? _crown;
  List<WatchReplayPosition> _positions = [];
  int _move = 0;

  /// At the last move: a new move from the relay is shown as it lands.
  bool _following = true;
  bool _revealReplay = false;
  String? _pgnFor;
  bool _foreground = true;
  bool _visible = false;
  bool _covered = false;

  // The engine's bar.
  WatchEval? _eval;
  String? _evalFor;
  Timer? _evalDebounce;

  // The arrows on the board: lit when the page opens or a hand touches
  // them, faded otherwise.
  bool _arrowsLit = true;
  Timer? _arrowsTimer;

  WatchTour? get _tour {
    if (_game.id == widget.game.id && widget.tour != null) return widget.tour;
    return widget.tours.where((t) => t.id == _game.tourId).firstOrNull ??
        widget.tour;
  }

  @override
  void initState() {
    super.initState();
    _foreground =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    WatchAlwaysOn.state.addListener(_sync);
    unawaited(WatchSounds.shared.warmUp());
    unawaited(_open());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _visible =
        TickerMode.valuesOf(context).enabled &&
        (ModalRoute.isCurrentOf(context) ?? true);
    _sync();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _sync();
    if (_foreground) unawaited(_refresh());
  }

  bool get _reading =>
      mounted &&
      _visible &&
      _foreground &&
      !_covered &&
      !WatchAlwaysOn.isActive;

  /// The Crown and live polling follow the page's state together.
  void _sync() {
    if (!_reading) WatchSounds.shared.stop();
    final crown = _reading && _positions.length > 1;
    if (crown && _crown == null) {
      // History can arrive after Crown scrolling took the board offscreen.
      // Bring it back once when move review first becomes available.
      if (_revealReplay) {
        _revealReplay = false;
        if (_scroll.hasClients) _scroll.jumpTo(0);
      }
      _dial.reset();
      _wheel.reset();
      _crown = WatchCrown.instance.rotations.listen((event) {
        if (!_reading) return;
        _wheel.reset();
        _select(
          _dial.turn(event.delta, index: _move, last: _positions.length - 1),
          resetDial: false,
        );
      });
    } else if (!crown && _crown != null) {
      unawaited(_crown!.cancel());
      _crown = null;
      _dial.reset();
      _wheel.reset();
    }
    _timer?.cancel();
    _timer = null;
    if (_reading && watchGameIsLive(_game)) {
      _timer = Timer.periodic(const Duration(seconds: 15), (timer) {
        if (!_reading) return;
        if (!watchShouldPoll(
          timer.tick,
          constrained: ChesseverWatchBridge.powerConstrained,
        )) {
          return;
        }
        unawaited(_refresh());
      });
    }
  }

  /// Shows the game at [_index]: its stored row at once, then its moves and
  /// its latest row from the feed.
  Future<void> _open() async {
    _evalDebounce?.cancel();
    _dial.reset();
    _wheel.reset();
    _game = _games[_index];
    _positions = [];
    _move = 0;
    _following = true;
    _revealReplay = false;
    _pgnFor = null;
    _error = null;
    _handoff = null;
    _fetchedAt = null;
    _eval = null;
    _evalFor = null;
    _lightArrows();
    if (mounted) setState(() {});
    _sync();
    _askEval();
    await Future.wait([_loadMoves(), _refresh()]);
  }

  Future<void> _loadMoves() async {
    final id = _game.id;
    try {
      final pgn = await widget.controller.repository.gamePgn(id);
      if (!mounted || id != _game.id) return;
      final positions = watchReplayPositions(pgn);
      // A move that just landed on the game being followed sounds as it
      // would on the phone; the first load of the moves stays quiet.
      final landed =
          _following &&
          _positions.length > 1 &&
          positions.length > _positions.length;
      setState(() {
        if (_positions.length < 2 && positions.length > 1) {
          _revealReplay = true;
        }
        _pgnFor = _game.lastMove;
        _positions = positions;
        if (positions.isEmpty) {
          _move = 0;
        } else if (_following || _move >= positions.length) {
          _move = positions.length - 1;
        }
      });
      if (landed && _reading) {
        WatchSounds.shared.play(watchSoundForSan(positions.last.san));
      }
      _sync();
      _askEval();
    } catch (_) {
      // The live position still shows; the moves come with the next poll.
    }
  }

  Future<void> _refresh() async {
    if (_busy) return;
    final id = _game.id;
    setState(() => _busy = true);
    try {
      final game = await widget.controller.repository.game(id);
      if (!mounted || id != _game.id) return;
      // A game you are watching just ended: tap the wrist once, the way a
      // finished timer does, so the result is felt without looking.
      if (game != null &&
          watchGameIsLive(_game) &&
          !watchGameIsLive(game) &&
          watchResult(game.status) != 'Scheduled') {
        WatchHaptics.play(WatchHapticType.notification);
        if (game.status?.trim() == '1/2-1/2' && _following && _reading) {
          WatchSounds.shared.play(WatchSound.draw);
        }
      }
      final moved = game != null && game.lastMove != _pgnFor;
      setState(() {
        if (game != null) {
          _game = game;
          _games[_index] = game;
          _fetchedAt = DateTime.now();
        }
        _error = game == null ? 'Game no longer available.' : null;
      });
      _sync();
      if (moved) {
        unawaited(_loadMoves());
      } else {
        _askEval();
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Offline · showing the last position.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Asks the engine cloud about the shown position, a moment after the
  /// Crown settles, so a fast turn through the game asks once.
  void _askEval() {
    final fen = _shown.$1;
    if (_evalFor == fen) return;
    _evalDebounce?.cancel();
    final cached = fen == null ? null : WatchEvalSource.shared.cached(fen);
    setState(() {
      // A new position must never borrow the previous position's score while
      // its cloud request is waiting for the Crown to settle.
      _eval = cached;
      _evalFor = fen;
    });
    if (fen == null || cached != null) return;
    _evalDebounce = Timer(const Duration(milliseconds: 250), () async {
      final eval = await WatchEvalSource.shared.eval(fen);
      if (!mounted || _shown.$1 != fen) return;
      setState(() {
        _eval = eval;
        _evalFor = fen;
      });
    });
  }

  void _lightArrows() {
    _arrowsTimer?.cancel();
    if (!_arrowsLit) setState(() => _arrowsLit = true);
    _arrowsTimer = Timer(const Duration(milliseconds: 1800), () {
      if (mounted) setState(() => _arrowsLit = false);
    });
  }

  void _select(int next, {bool resetDial = true}) {
    if (!_reading || _positions.length < 2) return;
    if (resetDial) {
      _dial.reset();
      _wheel.reset();
    }
    final last = _positions.length - 1;
    final clamped = next.clamp(0, math.max(0, last)).toInt();
    if (clamped == _move) return;
    // Forward plays the move's own sound, as on the phone; back, the plain
    // move sound.
    final sound = clamped > _move
        ? watchSoundForSan(_positions[clamped].san)
        : WatchSound.move;
    setState(() {
      _move = clamped;
      _following = clamped == last;
    });
    WatchSounds.shared.play(sound);
    _askEval();
    final now = _hapticClock.elapsedMilliseconds;
    if (now - _lastHapticMs >= 70) {
      WatchHaptics.click();
      _lastHapticMs = now;
    }
  }

  void _onWheel(PointerSignalEvent event) {
    if (!_reading || _positions.length < 2) return;
    if (event is! PointerScrollEvent || event.scrollDelta.dy == 0) return;
    GestureBinding.instance.pointerSignalResolver.register(event, (_) {
      _dial.reset();
      // Forty logical pixels form one detent. Trackpad fractions accumulate;
      // the resolver prevents the same wheel event scrolling the page as well.
      _select(
        _wheel.turn(
          event.scrollDelta.dy / 160,
          index: _move,
          last: _positions.length - 1,
        ),
        resetDial: false,
      );
    });
  }

  /// The next or previous board of the list, from a sideways swipe.
  void _swipe(int direction) {
    final next = _index + direction;
    if (next < 0 || next >= _games.length) {
      WatchHaptics.play(WatchHapticType.failure);
      return;
    }
    WatchHaptics.click();
    _index = next;
    if (_scroll.hasClients) _scroll.jumpTo(0);
    unawaited(_open());
  }

  Future<void> _sendToPhone() async {
    if (_sending) return;
    setState(() => _sending = true);
    final accepted = await widget.controller.openOnPhone(_game.id);
    if (mounted) {
      setState(() {
        _sending = false;
        // A signed-out iPhone accepts the game but shows sign-in first, so
        // say so instead of promising a game that will not appear yet.
        _handoff = !accepted
            ? 'Open ChessEver on your iPhone, then try again.'
            : widget.controller.account.signedIn
            ? 'Sent to iPhone.'
            : 'Sent. Sign in on iPhone to see it.';
      });
    }
  }

  Future<void> _push(Widget page) async {
    setState(() => _covered = true);
    _sync();
    await Navigator.of(
      context,
    ).push(CupertinoPageRoute<void>(builder: (_) => page));
    if (!mounted) return;
    setState(() => _covered = false);
    _sync();
  }

  void _close() => Navigator.of(context).maybePop(_game.id);

  /// The position on the board: the reviewed move, or the relay's latest
  /// when the moves have not arrived.
  (String? fen, String? lastMove) get _shown => _positions.isEmpty
      ? (_game.fen, _game.lastMove)
      : (_positions[_move].fen, _positions[_move].lastMove);

  String get _caption {
    final result = watchResult(_game.status);
    final last = _positions.length - 1;
    final eval = _eval;
    if (_positions.isEmpty) {
      final move = watchLastMoveLabel(_game.fen, _game.lastMove);
      return [result, if (move != null) move, ?eval?.label].join(' · ');
    }
    final at = _move == 0 ? 'Start' : _positions[_move].label;
    final live = watchGameIsLive(_game) && _move == last;
    return [
      if (!watchGameIsLive(_game) && _move == last) result,
      at,
      if (!live) '$_move/$last' else 'Live',
      ?eval?.label,
    ].join(' · ');
  }

  Widget _playerRow(Player player, bool white) {
    final clock = white ? _game.lastClockWhite : _game.lastClockBlack;
    final seconds = clock ?? (player.clock > 0 ? player.clock ~/ 100 : null);
    final tour = _tour;
    final standing = tour?.players
        .where((p) => watchPlayerMatches(player, p))
        .firstOrNull;
    return WatchRow(
      label: player.name,
      semanticLabel: white ? 'White' : 'Black',
      visual: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          WatchSideMark(white: white),
          if (watchFederation(player.fed) case final flag?) ...[
            const SizedBox(width: 5),
            flag,
          ],
        ],
      ),
      detail: player.rating > 0 ? '${player.rating}' : null,
      value: seconds == null ? null : watchClock(seconds),
      valueLit:
          watchIsLive(_game.status) && watchWhiteToMove(_game.fen) == white,
      onTap: tour == null || standing == null
          ? null
          : () => _push(watchScorecardPage(widget.controller, tour, standing)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final insets = media.padding;
    final band = math.max(WatchStatusBar.heightOf(context), insets.top);
    final width = media.size.width;
    final line = (media.textScaler.scale(12) * 1.3).ceilToDouble();
    const barSpace = WatchGamePage.evalBarWidth + WatchGamePage.evalBarGap;
    const lineGap = WatchGamePage.lineGap;
    // The first screen is the game whole: Black's line, the board and
    // White's line fit between the clock band and the display's rounded
    // bottom, never under it. The square board sits centred with its engine
    // bar so gutters hold the move arrows clear of the rounded corners.
    final bottomInset = math.max(insets.bottom + 4, 12.0);
    final room =
        media.size.height - band - bottomInset - line * 2 - lineGap * 2 - 4;
    final minGutter = math.max(
      WatchGamePage.minGutter,
      math.max(insets.left, insets.right) + 12,
    );
    final widest = width - minGutter * 2 - barSpace;
    final boardHeight = math.min(widest, math.max(88.0, room));
    final boardWidth = boardHeight;
    final gutter = math.max(0.0, (width - barSpace - boardWidth) / 2);
    final boardLeft = gutter + barSpace;
    final arrowWidth = math.max(44.0, gutter + 22);
    final (fen, lastMove) = _shown;
    final last = _positions.length - 1;
    final players = _game.players ?? const <Player>[];
    final top = players.length > 1 ? (_flipped ? 0 : 1) : null;
    final bottom = players.length > 1
        ? (_flipped ? 1 : 0)
        : (players.isNotEmpty ? 0 : null);
    final many = _games.length > 1;
    final sideInset = math.max(insets.left, insets.right) + 12;
    final playerInset = media.textScaler.scale(12) >= 18
        ? math.max(insets.left, insets.right) + 12
        : gutter;
    return CupertinoPageScaffold(
      backgroundColor: WatchStyle.background,
      child: Stack(
        children: [
          // The Crown steps through the moves once they arrive; until then
          // (or when a game has no recorded moves) it scrolls the page.
          WatchCrownScroll(
            enabled: _crown == null,
            child: CustomScrollView(
              controller: _scroll,
              physics: const WatchScrollPhysics(
                parent: AlwaysScrollableScrollPhysics(),
              ),
              slivers: [
                SliverPadding(
                  padding: EdgeInsets.only(
                    top: band + 2,
                    bottom: media.padding.bottom + 16,
                  ),
                  sliver: SliverList.list(
                    children: [
                      Listener(
                        onPointerSignal: _onWheel,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onHorizontalDragEnd: !many
                              ? null
                              : (details) {
                                  final v = details.primaryVelocity ?? 0;
                                  if (v.abs() < 120) return;
                                  _swipe(v < 0 ? 1 : -1);
                                },
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              minHeight: media.size.height - band - 2,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                // Names start at the engine bar, clocks end at
                                // the board's right edge: one axis for the game.
                                if (top != null)
                                  Padding(
                                    padding: EdgeInsets.fromLTRB(
                                      playerInset,
                                      2,
                                      playerInset,
                                      lineGap,
                                    ),
                                    child: WatchPlayerLine(
                                      game: _game,
                                      index: top,
                                      flagWidth: 16,
                                      showFlag:
                                          width >= 184 &&
                                          media.textScaler.scale(12) < 18,
                                    ),
                                  ),
                                SizedBox(
                                  height: boardHeight,
                                  child: Stack(
                                    children: [
                                      Positioned(
                                        left: gutter,
                                        top: 0,
                                        bottom: 0,
                                        child: _EvalBar(
                                          eval: _eval,
                                          flipped: _flipped,
                                          height: boardHeight,
                                        ),
                                      ),
                                      Positioned(
                                        left: boardLeft,
                                        top: 0,
                                        width: boardWidth,
                                        height: boardHeight,
                                        child: Semantics(
                                          label: 'Board ${_game.boardNr ?? ''}',
                                          value: _caption,
                                          increasedValue: _move < last
                                              ? _positions[_move + 1].label
                                              : null,
                                          decreasedValue: _move > 0
                                              ? (_move == 1
                                                    ? 'Start'
                                                    : _positions[_move - 1]
                                                          .label)
                                              : null,
                                          onIncrease: _move < last
                                              ? () => _select(_move + 1)
                                              : null,
                                          onDecrease: _move > 0
                                              ? () => _select(_move - 1)
                                              : null,
                                          hint: many
                                              ? 'Swipe sideways for the next board'
                                              : null,
                                          child: Hero(
                                            tag: watchBoardHeroTag(_game.id),
                                            child: WatchBoard(
                                              fen: fen,
                                              lastMove: lastMove,
                                              flipped: _flipped,
                                              fill: true,
                                            ),
                                          ),
                                        ),
                                      ),
                                      // The arrows rest in the gutters beside the
                                      // board, covering no square; each target
                                      // reaches over the board's edge to 44pt.
                                      Positioned(
                                        left: 0,
                                        top: 0,
                                        bottom: 0,
                                        width: arrowWidth,
                                        child: _BoardArrow(
                                          label: 'Previous move',
                                          icon: CupertinoIcons.chevron_left,
                                          glyphCenter: gutter / 2,
                                          lit: _arrowsLit,
                                          onTap: _move > 0
                                              ? () => _select(_move - 1)
                                              : null,
                                          onLongPress: _move > 0
                                              ? () => _select(0)
                                              : null,
                                          onTouch: _lightArrows,
                                        ),
                                      ),
                                      Positioned(
                                        right: 0,
                                        top: 0,
                                        bottom: 0,
                                        width: arrowWidth,
                                        child: _BoardArrow(
                                          label: 'Next move',
                                          icon: CupertinoIcons.chevron_right,
                                          glyphCenter: gutter / 2,
                                          lit: _arrowsLit,
                                          onTap: _move < last
                                              ? () => _select(_move + 1)
                                              : null,
                                          onLongPress: _move < last
                                              ? () => _select(last)
                                              : null,
                                          onTouch: _lightArrows,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (bottom != null)
                                  Padding(
                                    padding: EdgeInsets.fromLTRB(
                                      playerInset,
                                      lineGap,
                                      playerInset,
                                      0,
                                    ),
                                    child: WatchPlayerLine(
                                      game: _game,
                                      index: bottom,
                                      flagWidth: 16,
                                      showFlag:
                                          width >= 184 &&
                                          media.textScaler.scale(12) < 18,
                                    ),
                                  ),
                                SizedBox(height: bottomInset),
                              ],
                            ),
                          ),
                        ),
                      ),
                      Padding(
                        padding: EdgeInsets.fromLTRB(
                          sideInset,
                          2,
                          sideInset,
                          6,
                        ),
                        child: Semantics(
                          liveRegion: true,
                          child: Text(
                            _caption,
                            key: const ValueKey('watch-game-caption'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: WatchStyle.figures.copyWith(
                              color: WatchStyle.ink,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: sideInset),
                        child: Column(
                          children: [
                            if (_error != null) WatchNote.status(_error!),
                            if (many)
                              WatchNote(
                                'Board ${_index + 1} of ${_games.length} · '
                                'swipe the board sideways',
                              ),
                            if (top != null) _playerRow(players[top], top == 0),
                            if (bottom != null)
                              _playerRow(players[bottom], bottom == 0),
                            WatchRow(
                              label: _flipped
                                  ? 'White at bottom'
                                  : 'Black at bottom',
                              showChevron: false,
                              icon: CupertinoIcons.arrow_up_arrow_down,
                              onTap: () => setState(() => _flipped = !_flipped),
                            ),
                            WatchRow(
                              label: _sending ? 'Sending…' : 'Open on iPhone',
                              showChevron: false,
                              icon: CupertinoIcons.device_phone_portrait,
                              onTap: _sending ? null : _sendToPhone,
                            ),
                            if (_handoff != null) WatchNote.status(_handoff!),
                            if (_fetchedAt != null)
                              WatchNote(
                                'Relay clocks · fetched '
                                '${_fetchedAt!.hour.toString().padLeft(2, '0')}:'
                                '${_fetchedAt!.minute.toString().padLeft(2, '0')}:'
                                '${_fetchedAt!.second.toString().padLeft(2, '0')}'
                                '${_eval == null ? '' : ' · engine depth ${_eval!.depth}'}',
                              ),
                            WatchRow(
                              label: 'Refresh',
                              showChevron: false,
                              icon: CupertinoIcons.refresh,
                              onTap: _busy ? null : _refresh,
                              trailing: _busy
                                  ? const CupertinoActivityIndicator(radius: 7)
                                  : null,
                            ),
                            WatchRow(
                              label: WatchGamePage.backLabel,
                              showChevron: false,
                              icon: CupertinoIcons.chevron_back,
                              onTap: _close,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // The clock band: a veil keeps the names and board from running
          // into the time as the page scrolls.
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            height: band,
            child: IgnorePointer(
              child: _Band(scroll: _scroll, child: const SizedBox()),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    WatchSounds.shared.stop();
    _timer?.cancel();
    _evalDebounce?.cancel();
    _arrowsTimer?.cancel();
    unawaited(_crown?.cancel());
    _scroll.dispose();
    WatchAlwaysOn.state.removeListener(_sync);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}

/// A move arrow beside the board: a bare chevron centred in the gutter
/// between the screen's edge and the board, so it covers no square and no
/// rounded corner. Bright while the page is new or a hand is on it, then
/// settled to a quieter tone; dim at the first or last move. The target is
/// the whole strip, gutter plus the board's edge, at least 44 points wide.
class _BoardArrow extends StatelessWidget {
  const _BoardArrow({
    required this.label,
    required this.icon,
    required this.glyphCenter,
    required this.lit,
    required this.onTap,
    required this.onLongPress,
    required this.onTouch,
  });
  final String label;
  final IconData icon;

  /// Distance from the screen's edge to the chevron's centre.
  final double glyphCenter;
  final bool lit;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final VoidCallback onTouch;

  static const glyphSize = 20.0;

  @override
  Widget build(BuildContext context) {
    final leading = icon == CupertinoIcons.chevron_left;
    final offset = math.max(0.0, glyphCenter - glyphSize / 2);
    return Semantics(
      label: label,
      button: true,
      enabled: onTap != null,
      excludeSemantics: true,
      onTap: onTap,
      onLongPress: onLongPress,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => onTouch(),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Stack(
          children: [
            Positioned(
              left: leading ? offset : null,
              right: leading ? null : offset,
              top: 0,
              bottom: 0,
              width: glyphSize,
              child: Center(
                child: AnimatedOpacity(
                  opacity: onTap == null ? 0.3 : (lit ? 1 : 0.8),
                  duration: MediaQuery.disableAnimationsOf(context)
                      ? Duration.zero
                      : const Duration(milliseconds: 200),
                  curve: Curves.easeOut,
                  child: Icon(icon, size: glyphSize, color: WatchStyle.ink),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The engine's bar beside the board, the board's full height with round
/// caps: White's share from the bottom (the top when the board is flipped),
/// the move of the share eased. A notch marks equality so a small edge
/// reads at a glance. Unknown positions show a neutral track.
class _EvalBar extends StatelessWidget {
  const _EvalBar({
    required this.eval,
    required this.flipped,
    required this.height,
  });
  final WatchEval? eval;
  final bool flipped;
  final double height;

  @override
  Widget build(BuildContext context) {
    final share = eval?.whiteShare ?? 0.5;
    final known = eval != null;
    return Semantics(
      label: 'Engine',
      value: known ? eval!.label : 'Unknown',
      child: ExcludeSemantics(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: SizedBox(
            width: WatchGamePage.evalBarWidth,
            height: height,
            child: Stack(
              children: [
                const Positioned.fill(
                  child: ColoredBox(color: Color(0xFF36402F)),
                ),
                if (known)
                  AnimatedPositioned(
                    duration: MediaQuery.disableAnimationsOf(context)
                        ? Duration.zero
                        : const Duration(milliseconds: 200),
                    curve: Curves.easeOutCubic,
                    left: 0,
                    right: 0,
                    top: flipped ? 0 : null,
                    bottom: flipped ? null : 0,
                    height: height * share,
                    child: const ColoredBox(color: Color(0xFFDCE3D7)),
                  ),
                if (known)
                  Positioned(
                    left: 0,
                    right: 0,
                    top: (height - 1) / 2,
                    height: 1,
                    child: const ColoredBox(color: Color(0xFF7D8778)),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The band under the clock: black at rest only where the top line sits,
/// darkening fully as the page scrolls so the board fades out under the
/// time instead of colliding with it.
class _Band extends StatefulWidget {
  const _Band({required this.scroll, required this.child});
  final ScrollController scroll;
  final Widget child;
  @override
  State<_Band> createState() => _BandState();
}

class _BandState extends State<_Band> {
  double _veil = 0;

  @override
  void initState() {
    super.initState();
    widget.scroll.addListener(_onScroll);
  }

  void _onScroll() {
    if (!widget.scroll.hasClients) return;
    final next = (widget.scroll.position.pixels / 24).clamp(0.0, 1.0);
    if (next != _veil) setState(() => _veil = next);
  }

  @override
  void dispose() {
    widget.scroll.removeListener(_onScroll);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          WatchStyle.background,
          WatchStyle.background,
          WatchStyle.background.withValues(alpha: _veil),
        ],
        stops: const [0, 0.55, 1],
      ),
    ),
    child: widget.child,
  );
}

String watchClock(int seconds) {
  final safe = seconds < 0 ? 0 : seconds;
  final minutes = safe ~/ 60;
  final remainder = (safe % 60).toString().padLeft(2, '0');
  return '$minutes:$remainder';
}
