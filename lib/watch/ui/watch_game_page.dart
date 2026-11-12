import 'dart:async';
import 'dart:math' as math;
import 'package:chessever_watch_bridge/chessever_watch_bridge.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_watchos/flutter_watchos.dart';
import '../../repository/supabase/game/games.dart';
import '../core/watch_models.dart';
import '../core/watch_replay.dart';
import '../watch_controller.dart';
import 'watch_board.dart';
import 'watch_event_boards_page.dart' show WatchPlayerLine;
import 'watch_event_pages.dart';
import 'watch_visuals.dart';
import 'watch_widgets.dart';

/// A game on the wrist: the board as large as the screen allows, under the
/// clock band, with Black's name and clock in the band and White's under
/// the board. The Digital Crown steps through the moves from the moment the
/// page opens; a live game follows the relay until the Crown turns back.
/// Swiping the board sideways moves to the next or previous board of the
/// list it was opened from. Arrows and the rest sit under the board, one
/// finger scroll away.
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
  final _scroll = ScrollController();
  final _hapticClock = Stopwatch()..start();
  int _lastHapticMs = -100;
  StreamSubscription<CrownRotationEvent>? _crown;
  List<WatchReplayPosition> _positions = [];
  int _move = 0;

  /// At the last move: a new move from the relay is shown as it lands.
  bool _following = true;
  String? _pgnFor;
  bool _foreground = true;
  bool _visible = false;
  bool _covered = false;

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
    final crown = _reading && _positions.length > 1;
    if (crown && _crown == null) {
      _dial.reset();
      _crown = WatchCrown.instance.rotations.listen((event) {
        if (!_reading) return;
        _select(
          _dial.turn(event.delta, index: _move, last: _positions.length - 1),
          resetDial: false,
        );
      });
    } else if (!crown && _crown != null) {
      unawaited(_crown!.cancel());
      _crown = null;
      _dial.reset();
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
    _game = _games[_index];
    _positions = [];
    _move = 0;
    _following = true;
    _pgnFor = null;
    _error = null;
    _handoff = null;
    _fetchedAt = null;
    if (mounted) setState(() {});
    _sync();
    await Future.wait([_loadMoves(), _refresh()]);
  }

  Future<void> _loadMoves() async {
    final id = _game.id;
    try {
      final pgn = await widget.controller.repository.gamePgn(id);
      if (!mounted || id != _game.id) return;
      final positions = watchReplayPositions(pgn);
      setState(() {
        _pgnFor = _game.lastMove;
        _positions = positions;
        if (positions.isEmpty) {
          _move = 0;
        } else if (_following || _move >= positions.length) {
          _move = positions.length - 1;
        }
      });
      _sync();
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
      if (moved) unawaited(_loadMoves());
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Offline · showing the last position.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _select(int next, {bool resetDial = true}) {
    if (resetDial) _dial.reset();
    final last = _positions.length - 1;
    final clamped = next.clamp(0, math.max(0, last)).toInt();
    if (clamped == _move) return;
    setState(() {
      _move = clamped;
      _following = clamped == last;
    });
    final now = _hapticClock.elapsedMilliseconds;
    if (now - _lastHapticMs >= 70) {
      WatchHaptics.click();
      _lastHapticMs = now;
    }
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
    if (_positions.isEmpty) {
      final move = watchLastMoveLabel(_game.fen, _game.lastMove);
      return [result, if (move != null) move].join(' · ');
    }
    final at = _move == 0 ? 'Start' : _positions[_move].label;
    final live = watchGameIsLive(_game) && _move == last;
    return [
      if (!watchGameIsLive(_game) && _move == last) result,
      at,
      if (!live) '$_move/$last' else 'Live',
    ].join(' · ');
  }

  Widget _arrow(String label, IconData icon, VoidCallback? action) => Expanded(
    child: Semantics(
      label: label,
      button: true,
      enabled: action != null,
      excludeSemantics: true,
      onTap: action,
      child: WatchPressable(
        onPressed: action == null
            ? null
            : () {
                WatchHaptics.click();
                action();
              },
        builder: (context, pressed) => Container(
          height: 46,
          decoration: BoxDecoration(
            color: pressed ? WatchStyle.surfacePressed : WatchStyle.surface,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(
            icon,
            size: 21,
            color: action == null
                ? WatchStyle.disabled
                : pressed
                ? WatchStyle.secondary
                : WatchStyle.ink,
          ),
        ),
      ),
    ),
  );

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
    final band = WatchStatusBar.heightOf(context);
    final width = media.size.width;
    final line = media.textScaler.scale(12) * 1.3;
    // Edge to edge when the height allows: the band above, one name line
    // below, nothing else between the board and the glass.
    final board = math.min(width, media.size.height - band - line - 6);
    final (fen, lastMove) = _shown;
    final last = _positions.length - 1;
    final players = _game.players ?? const <Player>[];
    final top = players.length > 1 ? (_flipped ? 0 : 1) : null;
    final bottom = players.isNotEmpty ? (_flipped ? 1 : 0) : null;
    final many = _games.length > 1;
    return CupertinoPageScaffold(
      backgroundColor: WatchStyle.background,
      child: Stack(
        children: [
          CustomScrollView(
            controller: _scroll,
            physics: const WatchScrollPhysics(
              parent: AlwaysScrollableScrollPhysics(),
            ),
            slivers: [
              SliverPadding(
                padding: EdgeInsets.only(
                  top: band,
                  bottom: media.padding.bottom + 16,
                ),
                sliver: SliverList.list(
                  children: [
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onHorizontalDragEnd: !many
                          ? null
                          : (details) {
                              final v = details.primaryVelocity ?? 0;
                              if (v.abs() < 120) return;
                              _swipe(v < 0 ? 1 : -1);
                            },
                      child: Column(
                        children: [
                          Semantics(
                            label: 'Board ${_game.boardNr ?? ''}',
                            value: _caption,
                            increasedValue: _move < last
                                ? _positions[_move + 1].label
                                : null,
                            decreasedValue: _move > 0
                                ? (_move == 1
                                      ? 'Start'
                                      : _positions[_move - 1].label)
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
                            child: Center(
                              child: SizedBox(
                                width: board,
                                child: WatchBoard(
                                  fen: fen,
                                  lastMove: lastMove,
                                  flipped: _flipped,
                                ),
                              ),
                            ),
                          ),
                          if (bottom != null)
                            Padding(
                              padding: EdgeInsets.fromLTRB(
                                (width - board) / 2 + 4,
                                2,
                                (width - board) / 2 + 4,
                                0,
                              ),
                              child: WatchPlayerLine(
                                game: _game,
                                index: bottom,
                                flagWidth: 16,
                              ),
                            ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
                      child: Semantics(
                        liveRegion: true,
                        child: Text(
                          _caption,
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
                      padding: EdgeInsets.fromLTRB(
                        media.padding.left + 5,
                        0,
                        media.padding.right + 5,
                        6,
                      ),
                      child: Row(
                        spacing: 5,
                        children: [
                          _arrow(
                            'Previous move',
                            CupertinoIcons.arrowtriangle_left_fill,
                            _move > 0 ? () => _select(_move - 1) : null,
                          ),
                          _arrow(
                            'Next move',
                            CupertinoIcons.arrowtriangle_right_fill,
                            _move < last ? () => _select(_move + 1) : null,
                          ),
                          _arrow(
                            'Last move',
                            CupertinoIcons.forward_end_fill,
                            _move < last ? () => _select(last) : null,
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: media.padding.left + 5,
                      ),
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
                              '${_fetchedAt!.second.toString().padLeft(2, '0')}',
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
          // The clock band: the top player's name and clock sit in it beside
          // the system clock, and a veil keeps the board from running into
          // the time as the page scrolls.
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            height: band,
            child: IgnorePointer(
              child: _Band(
                scroll: _scroll,
                child: top == null
                    ? const SizedBox()
                    : Padding(
                        padding: EdgeInsets.fromLTRB(
                          (width - board) / 2 + 4,
                          0,
                          width * 0.38,
                          2,
                        ),
                        child: Align(
                          alignment: Alignment.bottomLeft,
                          child: WatchPlayerLine(
                            game: _game,
                            index: top,
                            flagWidth: 16,
                          ),
                        ),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    unawaited(_crown?.cancel());
    _scroll.dispose();
    WatchAlwaysOn.state.removeListener(_sync);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
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
