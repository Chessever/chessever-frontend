import 'dart:async';
import 'dart:math' as math;
import 'package:chessever_watch_bridge/chessever_watch_bridge.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/physics.dart';
import 'package:flutter_watchos/flutter_watchos.dart';
import 'package:sensors_plus/sensors_plus.dart';
import '../../repository/supabase/game/games.dart';
import '../core/watch_event_layout.dart';
import '../core/watch_models.dart';
import '../core/watch_replay.dart';
import '../core/watch_repository.dart';
import '../core/watch_wrist_flick.dart';
import '../watch_controller.dart';
import 'watch_board.dart';
import 'watch_event_pages.dart';
import 'watch_game_page.dart';
import 'watch_round_wheel.dart';
import 'watch_visuals.dart';
import 'watch_widgets.dart';

/// An empty board, drawn under the names of a board whose position has not
/// arrived yet, so the list keeps its height while details load.
const watchEmptyFen = '8/8/8/8/8/8/8/8 w - - 0 1';

/// Everything an event page shows, loaded the way the wrist can afford it.
///
/// One round trip lays the whole event out: every section, every round and
/// every board, without positions. The positions and clocks of a board come
/// separately, by id, as the board nears the screen ([need]), and live ones
/// are refreshed in place every poll. The layout itself only changes on
/// [load] or [refresh], never under the reader's finger.
class WatchEventFeed extends ChangeNotifier {
  WatchEventFeed(this._repository, this.event, {DateTime Function()? now})
    : _now = now ?? DateTime.now;
  final WatchRepository _repository;
  final WatchEvent event;
  final DateTime Function() _now;

  List<WatchTour> tours = [];
  List<WatchSection> sections = [];
  List<WatchFeedItem> items = [];

  /// Full rows by game id, for the boards that have been near the screen.
  final details = <String, Games>{};
  bool busy = false;
  bool loaded = false;
  String? error;

  final _wanted = <String>[];
  final _requested = <String>{};
  Timer? _flush;
  bool _fetching = false;
  DateTime? _detailFailure;
  bool _disposed = false;

  /// The sections' tours, strongest first, each once.
  List<WatchTour> get rankedTours {
    final seen = <String>{};
    return [
      for (final section in sections)
        if (seen.add(section.tour.id)) section.tour,
    ];
  }

  bool get multiSection => rankedTours.length > 1;

  /// The board as the list should draw it: its full row when loaded, else
  /// the layout row (names and status, no position).
  Games gameOf(Games board) => details[board.id] ?? board;

  bool get anyLive =>
      sections.any((s) => s.playing > 0) || details.values.any(watchGameIsLive);

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  Future<void> load() async {
    if (busy) return;
    busy = true;
    error = null;
    _changed();
    try {
      tours = await _repository.tours(event.id);
      final ids = [for (final tour in tours) tour.id];
      final (rounds, boards) = await (
        _repository.eventRounds(ids),
        _repository.eventBoards(ids),
      ).wait;
      sections = watchEventSections(
        tours: tours,
        rounds: rounds,
        games: boards,
        now: _now(),
        eventName: event.name,
      );
      items = watchFeedItems(sections);
      // Live boards already on screen refresh with the new layout; finished
      // ones keep their position, which cannot change.
      final live = [
        for (final game in details.values)
          if (watchGameIsLive(game)) game.id,
      ];
      _requested.removeAll(live);
      _wanted.addAll(live);
      _scheduleFlush();
    } catch (_) {
      error = loaded && items.isNotEmpty
          ? 'Offline · showing the last boards.'
          : 'Could not load boards. Pull to try again.';
    } finally {
      busy = false;
      loaded = true;
      _changed();
    }
  }

  Future<void> refresh() => load();

  /// Asks for the full row of [gameId] (position, clocks). Called from the
  /// list as a board is built, which the list does only near the screen.
  void need(String gameId) {
    if (details.containsKey(gameId) || _requested.contains(gameId)) return;
    final failed = _detailFailure;
    if (failed != null &&
        _now().difference(failed) < const Duration(seconds: 8)) {
      return;
    }
    _requested.add(gameId);
    _wanted.add(gameId);
    _scheduleFlush();
  }

  void _scheduleFlush() {
    _flush ??= Timer(const Duration(milliseconds: 40), () {
      _flush = null;
      unawaited(_fetchWanted());
    });
  }

  Future<void> _fetchWanted() async {
    if (_fetching) return;
    _fetching = true;
    try {
      while (_wanted.isNotEmpty && !_disposed) {
        final chunk = _wanted.take(WatchRepository.pageSize).toSet().toList();
        _wanted.removeRange(0, math.min(_wanted.length, chunk.length));
        try {
          for (final game in await _repository.gamesByIds(chunk)) {
            details[game.id] = game;
          }
          _changed();
        } catch (_) {
          _requested.removeAll(chunk);
          _detailFailure = _now();
          _wanted.clear();
        }
      }
    } finally {
      _fetching = false;
    }
  }

  /// Refreshes the loaded boards that are still being played, in place.
  Future<void> pollLive() async {
    final live = [
      for (final game in details.values)
        if (watchGameIsLive(game)) game.id,
    ];
    for (var i = 0; i < live.length; i += WatchRepository.pageSize) {
      final chunk = live.sublist(
        i,
        math.min(live.length, i + WatchRepository.pageSize),
      );
      try {
        for (final game in await _repository.gamesByIds(chunk)) {
          details[game.id] = game;
        }
      } catch (_) {
        return;
      }
    }
    _changed();
  }

  @override
  void dispose() {
    _disposed = true;
    _flush?.cancel();
    super.dispose();
  }
}

/// An event on the wrist as one list: every section, strongest first, every
/// round inside it, latest first, every board as a full board, the way the
/// phone's Combined view lays it out. The event's photograph heads the list.
///
/// The Digital Crown steps one item at a time (a heading, a team match, a
/// board), a wrist flick steps board to board, and a finger scrolls freely.
/// An index by the Crown shows the boards of the round being read and which
/// one is in view; the band under the clock names it. A round heading opens
/// the round wheel to jump anywhere in the event.
class WatchEventBoardsPage extends StatefulWidget {
  const WatchEventBoardsPage({
    super.key,
    required this.controller,
    required this.event,
  });
  final WatchController controller;
  final WatchEvent event;

  /// Test seam: replaces the CoreMotion gyroscope so a recorded flick can be
  /// replayed through the real list off-watch.
  @visibleForTesting
  static Stream<GyroscopeEvent> Function()? debugGyroscope;

  @override
  State<WatchEventBoardsPage> createState() => _WatchEventBoardsPageState();
}

class _WatchEventBoardsPageState extends State<WatchEventBoardsPage>
    with WidgetsBindingObserver {
  late final WatchEventFeed _feed = WatchEventFeed(
    widget.controller.repository,
    widget.event,
  );
  final _scroll = ScrollController();
  final _keys = <String, GlobalKey>{};
  static const _heroKey = 'hero';

  /// The item in the resting slot under the clock: -1 is the event header.
  final _current = ValueNotifier<int>(-1);
  final _dial = WatchReplayDial();
  StreamSubscription<CrownRotationEvent>? _crown;
  final _flick = WatchWristFlick();
  final _flickClock = Stopwatch();
  StreamSubscription<GyroscopeEvent>? _gyro;
  final _hapticClock = Stopwatch()..start();
  int _lastHapticMs = -100;
  Timer? _timer;
  bool _polling = false;
  bool _foreground = true;
  bool _visible = false;
  bool _covered = false;

  @override
  void initState() {
    super.initState();
    _foreground =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    WatchAlwaysOn.state.addListener(_syncInputs);
    _feed.addListener(_syncInputs);
    _feed.addListener(_queueMeasure);
    _scroll.addListener(_queueMeasure);
    unawaited(_feed.load());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _visible =
        TickerMode.valuesOf(context).enabled &&
        (ModalRoute.isCurrentOf(context) ?? true);
    _syncInputs();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _syncInputs();
    if (_foreground && _feed.loaded) unawaited(_feed.pollLive());
  }

  bool get _reading =>
      mounted &&
      _visible &&
      _foreground &&
      !_covered &&
      !WatchAlwaysOn.isActive;

  /// Starts and stops the Crown, the gyroscope and live polling together,
  /// from one reading of the page's state.
  void _syncInputs() {
    final reading = _reading;
    final items = _feed.items;

    // Digital Crown: one detent, one item. Listening takes the Crown off
    // page scrolling, so the finger still scrolls freely.
    final crown = reading && items.isNotEmpty;
    if (crown && _crown == null) {
      _dial.reset();
      _crown = WatchCrown.instance.rotations.listen((event) {
        if (!_reading) return;
        final next = _dial.turn(
          event.delta,
          index: _current.value + 1,
          last: _feed.items.length,
        );
        if (next != _current.value + 1) _goTo(next - 1, haptic: true);
      });
    } else if (!crown && _crown != null) {
      unawaited(_crown!.cancel());
      _crown = null;
      _dial.reset();
    }

    // Wrist flick: the next board, past whatever headings sit between.
    final source = WatchEventBoardsPage.debugGyroscope;
    final flick =
        reading &&
        (FlutterWatchosPlatform.isWatch || source != null) &&
        items.whereType<WatchBoardItem>().length > 1;
    if (flick && _gyro == null) {
      _flick.reset();
      _flickClock
        ..reset()
        ..start();
      _gyro =
          (source?.call() ??
                  gyroscopeEventStream(
                    samplingPeriod: SensorInterval.gameInterval,
                  ))
              .listen(
                (e) {
                  final step = _flick.add(e.x, e.y, e.z, _flickClock.elapsed);
                  if (step != 0) _stepBoard(step);
                },
                onError: (_) => _stopFlick(),
                cancelOnError: true,
              );
    } else if (!flick) {
      _stopFlick();
    }

    // Live boards: refresh the loaded ones in place every 15 s, every 60 s
    // when watchOS asks for restraint.
    final poll = reading && _feed.anyLive;
    if (poll != _polling) {
      _polling = poll;
      _timer?.cancel();
      _timer = !poll
          ? null
          : Timer.periodic(const Duration(seconds: 15), (timer) {
              if (!_reading) return;
              if (!watchShouldPoll(
                timer.tick,
                constrained: ChesseverWatchBridge.powerConstrained,
              )) {
                return;
              }
              unawaited(_feed.pollLive());
            });
    }
  }

  void _stopFlick() {
    unawaited(_gyro?.cancel());
    _gyro = null;
    _flickClock.stop();
  }

  double get _resting => WatchStatusBar.heightOf(context) + 4;

  double? _topOf(String id) {
    final viewport = context.findRenderObject();
    final box = _keys[id]?.currentContext?.findRenderObject() as RenderBox?;
    if (viewport == null || box == null || !box.attached) return null;
    return box.localToGlobal(Offset.zero, ancestor: viewport).dy;
  }

  String _idAt(int index) => index < 0 ? _heroKey : _feed.items[index].id;

  bool _measureQueued = false;

  /// Measures once the frame has laid the list out: a scroll notification
  /// arrives before layout, when the boxes still hold their old positions.
  void _queueMeasure() {
    if (_measureQueued) return;
    _measureQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _measureQueued = false;
      if (mounted) _measure();
    });
  }

  /// Which item sits in the resting slot. Only built items have a position;
  /// the rest are far off screen and cannot be the one.
  void _measure() {
    final items = _feed.items;
    var best = -1;
    var distance = double.infinity;
    for (var i = -1; i < items.length; i++) {
      final top = _topOf(_idAt(i));
      if (top == null) continue;
      final d = (top - _resting).abs();
      if (d < distance) {
        distance = d;
        best = i;
      }
    }
    if (best != _current.value) _current.value = best;
  }

  void _haptic(WatchHapticType type) {
    final now = _hapticClock.elapsedMilliseconds;
    if (now - _lastHapticMs < 70) return;
    _lastHapticMs = now;
    WatchHaptics.play(type);
  }

  /// Rough height of an item that is not built yet, for a first jump that
  /// the next frame corrects (see [_goTo]).
  double _estimate(WatchFeedItem item) {
    final scale = MediaQuery.textScalerOf(context);
    return switch (item) {
      WatchBoardItem() => _tileHeight(context) + 16,
      WatchMatchItem() => scale.scale(96),
      WatchRoundItem() => scale.scale(58),
      WatchCategoryItem() => scale.scale(56),
    };
  }

  /// Brings item [index] (-1: the header) into the resting slot.
  ///
  /// A built item is measured and reached with a short spring. An item far
  /// off screen is reached in two moves: a jump to where it should be, then
  /// a correction once it is built and measured.
  void _goTo(int index, {required bool haptic, int passes = 3}) {
    if (!_scroll.hasClients) return;
    final items = _feed.items;
    final target = index.clamp(-1, items.length - 1);
    if (haptic) {
      _haptic(
        target == _current.value
            ? WatchHapticType.failure
            : target > _current.value
            ? WatchHapticType.directionDown
            : WatchHapticType.directionUp,
      );
    }
    final position = _scroll.position;
    final top = _topOf(_idAt(target));
    if (top != null) {
      final to = (position.pixels + top - _resting).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      );
      if (passes < 3 || MediaQuery.disableAnimationsOf(context)) {
        position.jumpTo(to);
      } else {
        unawaited(
          _scroll.animateTo(
            to,
            duration: const Duration(milliseconds: 300),
            curve: const _SpringCurve(),
          ),
        );
      }
      _current.value = target;
      return;
    }
    if (passes == 0 || target < 0) return;
    var estimate = (_topOf(_heroKey) ?? 0) + position.pixels;
    final heroBox =
        _keys[_heroKey]?.currentContext?.findRenderObject() as RenderBox?;
    estimate += heroBox?.size.height ?? 90;
    for (var i = 0; i < target; i++) {
      estimate += _estimate(items[i]);
    }
    position.jumpTo(
      estimate.clamp(position.minScrollExtent, position.maxScrollExtent),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _goTo(target, haptic: false, passes: passes - 1);
    });
  }

  /// The next board in [direction], past any headings or match cards.
  void _stepBoard(int direction) {
    final items = _feed.items;
    var i = _current.value;
    while (true) {
      i += direction;
      if (i < 0 || i >= items.length) {
        _haptic(WatchHapticType.failure);
        return;
      }
      if (items[i] is WatchBoardItem) break;
    }
    _goTo(i, haptic: true);
  }

  Future<void> _openGame(WatchSection section, Games game) async {
    setState(() => _covered = true);
    _syncInputs();
    await Navigator.of(context).push(
      CupertinoPageRoute<void>(
        builder: (_) => WatchGamePage(
          controller: widget.controller,
          game: _feed.gameOf(game),
          tour: section.tour,
        ),
      ),
    );
    if (!mounted) return;
    setState(() => _covered = false);
    _syncInputs();
    if (_feed.loaded) unawaited(_feed.pollLive());
  }

  Future<void> _chooseRound(WatchSection shown) async {
    final multi = _feed.multiSection;
    final rounds = [
      for (final section in _feed.sections)
        WatchRound(
          id: section.id,
          name: multi
              ? '${section.label} · ${section.round.name}'
              : section.round.name,
          startsAt: section.startsAt,
          tourId: section.tour.id,
        ),
    ];
    setState(() => _covered = true);
    _syncInputs();
    final chosen = await Navigator.of(context).push<WatchRound>(
      CupertinoPageRoute(
        builder: (_) =>
            WatchRoundWheelPage(rounds: rounds, selectedId: shown.id),
      ),
    );
    if (!mounted) return;
    setState(() => _covered = false);
    _syncInputs();
    if (chosen == null) return;
    final index = _feed.items.indexWhere(
      (item) => item is WatchRoundItem && item.section.id == chosen.id,
    );
    if (index >= 0) _goTo(index, haptic: false);
  }

  Future<void> _openStandings() async {
    final tours = _feed.rankedTours;
    if (tours.length == 1) {
      return watchPush(
        context,
        watchStandingsPage(widget.controller, tours.single),
      );
    }
    final labels = {
      for (final section in _feed.sections) section.tour.id: section.label,
    };
    watchPush(
      context,
      WatchPage(
        title: 'Standings',
        children: [
          for (final tour in tours)
            WatchRow(
              label: labels[tour.id] ?? tour.name,
              icon: CupertinoIcons.person_2,
              onTap: () => watchPush(
                context,
                watchStandingsPage(widget.controller, tour),
              ),
            ),
        ],
      ),
    );
  }

  Widget _item(WatchFeedItem item, DateTime now, bool use24h) => switch (item) {
    WatchCategoryItem(:final section, :final rounds) => _CategoryHeading(
      key: ValueKey('watch-category-${section.tour.id}'),
      section: section,
      rounds: rounds,
    ),
    WatchRoundItem(:final section) => _RoundHeading(
      key: ValueKey('watch-round-${section.id}'),
      section: section,
      now: now,
      use24h: use24h,
      onTap: () => _chooseRound(section),
    ),
    WatchMatchItem(:final section, :final match) => _MatchCard(
      key: ValueKey('watch-match-${section.id}-${match.key}'),
      match: match,
      onTap: () {
        final first = _feed.items.indexWhere(
          (i) =>
              i is WatchBoardItem &&
              i.section.id == section.id &&
              i.match?.key == match.key,
        );
        if (first >= 0) _goTo(first, haptic: false);
      },
    ),
    WatchBoardItem(:final section, :final game) => _LazyBoard(
      key: ValueKey('watch-board-${game.id}'),
      feed: _feed,
      game: game,
      onTap: () => _openGame(section, game),
    ),
  };

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _feed,
    builder: (context, _) {
      final feed = _feed;
      final items = feed.items;
      final now = DateTime.now();
      final use24h = MediaQuery.alwaysUse24HourFormatOf(context);
      final insets = MediaQuery.paddingOf(context);
      final band = WatchStatusBar.heightOf(context);
      final width = MediaQuery.sizeOf(context).width;
      return Stack(
        children: [
          WatchPage(
            title: widget.event.name,
            boardBackLabel: 'Back to Current',
            scrollController: _scroll,
            header: KeyedSubtree(
              key: _keys.putIfAbsent(_heroKey, GlobalKey.new),
              child: _EventHero(
                repository: widget.controller.repository,
                event: widget.event,
                detail: feed.multiSection
                    ? '${feed.rankedTours.length} sections'
                    : null,
              ),
            ),
            onRefresh: feed.refresh,
            refreshing: feed.busy,
            children: [
              if (feed.error != null) WatchNote.status(feed.error!),
              if (feed.busy && items.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: Center(child: CupertinoActivityIndicator()),
                ),
              if (!feed.busy && feed.loaded && feed.error == null) ...[
                if (feed.tours.isEmpty)
                  const WatchNote(
                    'This event has not published its sections yet.',
                  )
                else if (items.isEmpty)
                  const WatchNote('Boards have not been published yet.'),
              ],
              for (final item in items)
                KeyedSubtree(
                  key: _keys.putIfAbsent(item.id, GlobalKey.new),
                  child: _item(item, now, use24h),
                ),
              if (feed.sections.isNotEmpty)
                WatchRow(
                  label: 'Standings',
                  icon: CupertinoIcons.person_2,
                  detail: feed.multiSection
                      ? '${feed.rankedTours.length} sections'
                      : null,
                  onTap: _openStandings,
                ),
            ],
          ),
          Positioned(
            right: insets.right + 1,
            top: band + 4,
            bottom: insets.bottom + 10,
            width: 10,
            // Overlays only: a tap on the edge or the band still reaches
            // the list under them.
            child: IgnorePointer(
              child: ExcludeSemantics(
                child: ValueListenableBuilder<int>(
                  valueListenable: _current,
                  builder: (context, current, _) =>
                      _Spine(items: items, current: current),
                ),
              ),
            ),
          ),
          Positioned(
            left: insets.left + 7,
            top: 0,
            height: band,
            width: width * 0.56,
            child: IgnorePointer(
              child: ExcludeSemantics(
                child: ValueListenableBuilder<int>(
                  valueListenable: _current,
                  builder: (context, current, _) => _Marker(
                    text: current < 0 || current >= items.length
                        ? ''
                        : _markerText(items[current], feed.multiSection),
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    },
  );

  @override
  void dispose() {
    unawaited(_crown?.cancel());
    _stopFlick();
    _timer?.cancel();
    _scroll
      ..removeListener(_queueMeasure)
      ..dispose();
    _current.dispose();
    _feed
      ..removeListener(_syncInputs)
      ..removeListener(_queueMeasure)
      ..dispose();
    WatchAlwaysOn.state.removeListener(_syncInputs);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}

/// "R3 · B2" or, with several sections, "Group A · R3 · B2": where the list
/// is, set in the band under the clock as the list scrolls.
String _markerText(WatchFeedItem item, bool multi) {
  final section = item.section;
  final round = _shortRound(section.round.name);
  final parts = [if (multi) section.label, round];
  switch (item) {
    case WatchBoardItem(:final game):
      if (game.boardNr != null) parts.add('B${game.boardNr}');
    case WatchMatchItem(:final match):
      parts.add('${_firstWord(match.home)}–${_firstWord(match.away)}');
    case WatchRoundItem():
    case WatchCategoryItem():
      break;
  }
  return parts.join(' · ');
}

final RegExp _roundNumber = RegExp(r'^round\s+(\d+)\b', caseSensitive: false);
String _shortRound(String name) {
  final match = _roundNumber.firstMatch(name.trim());
  return match == null ? name.trim() : 'R${match.group(1)}';
}

String _firstWord(String name) => name.trim().split(RegExp(r'\s+')).first;

/// The height of a board tile, the same sum the tile lays out, so a jump to
/// an unbuilt board lands close before it is measured.
double _tileHeight(BuildContext context) {
  final media = MediaQuery.of(context);
  final height =
      media.size.height -
      WatchStatusBar.heightOf(context) -
      media.padding.bottom -
      6;
  final line = media.textScaler.scale(12) * 1.3;
  final width =
      media.size.width - media.padding.left - media.padding.right - 10;
  final board = math.min(width, math.max(72.0, height - line * 2 - 8));
  return board + line * 2 + 8;
}

/// A board tile that asks the feed for its position as it is built: the
/// list builds only what is near the screen, so that is the moment to load.
class _LazyBoard extends StatelessWidget {
  const _LazyBoard({
    super.key,
    required this.feed,
    required this.game,
    required this.onTap,
  });
  final WatchEventFeed feed;
  final Games game;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    feed.need(game.id);
    return WatchBoardTile(game: feed.gameOf(game), onTap: onTap);
  }
}

/// The index by the Crown: one mark per board of the round being read, the
/// live ones lit, the one in view drawn in ink and wider. Four hundred
/// boards still fit: marks shrink to two points before they overlap.
class _Spine extends StatelessWidget {
  const _Spine({required this.items, required this.current});
  final List<WatchFeedItem> items;
  final int current;

  @override
  Widget build(BuildContext context) {
    if (current < 0 || current >= items.length) return const SizedBox();
    final section = items[current].section;
    final boards = <(bool live, bool here)>[];
    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      if (item is WatchBoardItem && item.section.id == section.id) {
        boards.add((watchGameIsPlaying(item.game), i == current));
      }
    }
    if (boards.length < 2) return const SizedBox();
    return CustomPaint(painter: _SpinePainter(boards));
  }
}

class _SpinePainter extends CustomPainter {
  const _SpinePainter(this.boards);
  final List<(bool live, bool here)> boards;
  static const _rest = Color(0xFF3A4237);
  static const _live = Color(0xFF6F8A5B);

  @override
  void paint(Canvas canvas, Size size) {
    final n = boards.length;
    final gap = n > 40 ? 1.0 : 2.0;
    final tick = ((size.height - gap * (n - 1)) / n).clamp(2.0, 7.0);
    final total = tick * n + gap * (n - 1);
    var y = (size.height - total) / 2;
    final paint = Paint();
    for (final (live, here) in boards) {
      final width = here ? 8.0 : 4.0;
      paint.color = here
          ? WatchStyle.ink
          : live
          ? _live
          : _rest;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(size.width - width, y, width, tick),
          Radius.circular(tick / 2),
        ),
        paint,
      );
      y += tick + gap;
    }
  }

  @override
  bool shouldRepaint(_SpinePainter old) => old.boards != boards;
}

/// Where the list is, in the band beside the clock. It appears once the
/// header has scrolled away and leaves when the list is back at its top.
class _Marker extends StatelessWidget {
  const _Marker({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => AnimatedOpacity(
    opacity: text.isEmpty ? 0 : 1,
    duration: const Duration(milliseconds: 150),
    curve: Curves.easeOut,
    child: Align(
      alignment: Alignment.centerLeft,
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: WatchStyle.figures.copyWith(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: WatchStyle.ink,
        ),
      ),
    ),
  );
}

/// The event's photograph with its name set on it, the same object the
/// Current card shows, so opening an event keeps its picture.
class _EventHero extends StatelessWidget {
  const _EventHero({
    required this.repository,
    required this.event,
    this.detail,
  });
  final WatchRepository repository;
  final WatchEvent event;

  /// Replaces the time control under the name.
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context);
    final line = detail ?? watchTimeControl(event.timeControl);
    const shade = [Shadow(color: Color(0xB3000000), blurRadius: 4)];
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: scale.scale(64)),
          child: Stack(
            children: [
              Positioned.fill(
                child: ColoredBox(
                  color: WatchStyle.surface,
                  child: WatchEventPhoto(
                    repository: repository,
                    eventId: event.id,
                  ),
                ),
              ),
              const Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [
                        Color(0xF0000000),
                        Color(0xC7000000),
                        Color(0x8C000000),
                        Color(0x14000000),
                      ],
                      stops: [0, 0.4, 0.68, 1],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(
                  WatchStyle.contentInset,
                  scale.scale(14),
                  WatchStyle.contentInset,
                  9,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      event.name,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: WatchStyle.body.copyWith(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        height: 1.18,
                        shadows: shade,
                      ),
                    ),
                    if (line != null && line.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        line,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: WatchStyle.figures.copyWith(
                          color: const Color(0xFFDCE3D7),
                          shadows: shade,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A section's heading where the list moves into it: its label large, its
/// strength and length under it. Only events with several sections have it.
class _CategoryHeading extends StatelessWidget {
  const _CategoryHeading({
    super.key,
    required this.section,
    required this.rounds,
  });
  final WatchSection section;
  final int rounds;

  @override
  Widget build(BuildContext context) {
    final elo = section.tour.avgElo;
    final caption = [
      if (elo != null) 'Avg $elo',
      '$rounds ${rounds == 1 ? 'round' : 'rounds'}',
    ].join(' · ');
    return Semantics(
      header: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          WatchStyle.contentInset,
          10,
          WatchStyle.contentInset,
          8,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              section.label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: WatchStyle.heading.copyWith(fontSize: 19),
            ),
            Text(caption, maxLines: 1, style: WatchStyle.figures),
          ],
        ),
      ),
    );
  }
}

/// A round's heading: its name, where it stands, and a wheel glyph, since
/// tapping it opens the round wheel over every round of the event.
class _RoundHeading extends StatelessWidget {
  const _RoundHeading({
    super.key,
    required this.section,
    required this.now,
    required this.use24h,
    required this.onTap,
  });
  final WatchSection section;
  final DateTime now;
  final bool use24h;
  final VoidCallback onTap;

  String get _status {
    final playing = section.playing;
    final total = section.games.length;
    final start = section.startsAt?.toLocal();
    if (!section.hasStarted) {
      return start == null
          ? 'Pairings'
          : 'Starts ${watchWhen(start, now, use24h: use24h)}';
    }
    if (playing > 0) {
      return playing == total ? '$playing live' : '$playing of $total live';
    }
    if (section.isFullyPlayed) return 'Finished';
    final done = section.games.where(watchGameIsFinished).length;
    return '$done of $total finished';
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    final live = section.playing > 0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Semantics(
        button: true,
        header: true,
        label: '${section.round.name}. $status',
        hint: 'Choose a round',
        excludeSemantics: true,
        onTap: onTap,
        child: WatchPressable(
          onPressed: () {
            WatchHaptics.click();
            onTap();
          },
          builder: (context, pressed) => Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(
              horizontal: WatchStyle.contentInset,
              vertical: 8,
            ),
            decoration: BoxDecoration(
              color: pressed ? WatchStyle.surfacePressed : WatchStyle.surface,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        section.round.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: WatchStyle.body.copyWith(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          height: 1.18,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        status,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: WatchStyle.figures.copyWith(
                          color: live ? WatchStyle.ink : null,
                          fontWeight: live ? FontWeight.w600 : null,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                const Icon(
                  CupertinoIcons.chevron_up_chevron_down,
                  size: 15,
                  color: WatchStyle.secondary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One team match: both teams with their match score, and under them the
/// match read board by board from the first-named team's side, like the
/// result column of a team scoresheet (`1 ½ 0 •`, a dot for a game still
/// being played). Its boards follow it in the list; tapping it goes there.
class _MatchCard extends StatelessWidget {
  const _MatchCard({super.key, required this.match, required this.onTap});
  final WatchTeamMatch match;
  final VoidCallback onTap;

  String _board(Games game) {
    final whiteIsHome =
        game.players![0].team.trim().toLowerCase() ==
        match.home.trim().toLowerCase();
    return switch (game.status?.trim()) {
      '1-0' => whiteIsHome ? '1' : '0',
      '0-1' => whiteIsHome ? '0' : '1',
      '1/2-1/2' => '½',
      _ => '•',
    };
  }

  Widget _team(String name, double score, bool lead) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        child: Text(
          name,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: WatchStyle.body.copyWith(
            fontSize: 14,
            height: 1.18,
            fontWeight: lead ? FontWeight.w700 : FontWeight.w500,
            color: lead ? WatchStyle.ink : WatchStyle.secondary,
          ),
        ),
      ),
      const SizedBox(width: 8),
      Text(
        watchScore(score),
        style: WatchStyle.figures.copyWith(
          fontSize: 14,
          height: 1.18,
          fontWeight: lead ? FontWeight.w700 : FontWeight.w500,
          color: lead ? WatchStyle.ink : WatchStyle.secondary,
        ),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final even = match.homeScore == match.awayScore;
    final playing = match.games.any(watchGameIsPlaying);
    final status = playing
        ? 'Live'
        : match.finished
        ? 'Final'
        : '';
    // Thin spaces: the figures read as one line of a scoresheet.
    final boards = match.games.map(_board).join('\u2009\u2009');
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Semantics(
        button: true,
        label:
            '${match.home} ${watchScore(match.homeScore)}, '
            '${match.away} ${watchScore(match.awayScore)}. '
            '${match.games.length} boards. $status',
        hint: 'Goes to its boards',
        excludeSemantics: true,
        onTap: onTap,
        child: WatchPressable(
          onPressed: () {
            WatchHaptics.click();
            onTap();
          },
          builder: (context, pressed) => Container(
            width: double.infinity,
            padding: const EdgeInsets.all(WatchStyle.contentInset),
            decoration: BoxDecoration(
              color: pressed ? WatchStyle.surfacePressed : WatchStyle.surface,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _team(
                  match.home,
                  match.homeScore,
                  even || match.homeScore > match.awayScore,
                ),
                const SizedBox(height: 3),
                _team(
                  match.away,
                  match.awayScore,
                  even || match.awayScore > match.homeScore,
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        boards,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: WatchStyle.figures,
                      ),
                    ),
                    if (status.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Text(
                        status,
                        style: WatchStyle.figures.copyWith(
                          color: playing ? WatchStyle.ink : null,
                          fontWeight: playing ? FontWeight.w600 : null,
                        ),
                      ),
                    ],
                    const SizedBox(width: 4),
                    const Icon(
                      CupertinoIcons.chevron_down,
                      size: 13,
                      color: WatchStyle.secondary,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One side of a game on one line: flag, name (shortened only when it does
/// not fit), and the result or clock in tabular figures. The winner, or the
/// side whose clock is running, sits in ink; the other steps back.
class WatchPlayerLine extends StatelessWidget {
  const WatchPlayerLine({
    super.key,
    required this.game,
    required this.index,
    this.fontSize = 12,
    this.flagWidth = 21,
    this.showFlag = true,
  });

  /// False on rows too narrow for flag, name and clock together: the name
  /// wins, since the flag repeats on the full board.
  final bool showFlag;
  final Games game;

  /// 0 for White, 1 for Black.
  final int index;
  final double fontSize;
  final double flagWidth;

  @override
  Widget build(BuildContext context) {
    final player = game.players != null && game.players!.length > index
        ? game.players![index]
        : null;
    final flag = showFlag
        ? watchFederation(player?.fed, width: flagWidth)
        : null;
    final clock = index == 0 ? game.lastClockWhite : game.lastClockBlack;
    final white = index == 0;
    final won = switch (game.status) {
      '1-0' => white,
      '0-1' => !white,
      _ => null,
    };
    final value = switch (game.status) {
      '1-0' => white ? '1' : '0',
      '0-1' => white ? '0' : '1',
      '1/2-1/2' => '½',
      _ => clock == null ? '' : watchClock(clock),
    };
    final lit =
        won ??
        (watchIsLive(game.status) && watchWhiteToMove(game.fen) == white);
    final tone = lit ? WatchStyle.ink : WatchStyle.secondary;
    final name = player?.name.trim();
    return Row(
      key: ValueKey('watch-player-strip-$index'),
      children: [
        if (flag != null) ...[
          ExcludeSemantics(child: flag),
          SizedBox(width: fontSize >= 12.5 ? 6 : 5),
        ],
        Expanded(
          child: WatchFittedName(
            name == null || name.isEmpty ? (white ? 'White' : 'Black') : name,
            style: WatchStyle.caption.copyWith(
              fontSize: fontSize,
              color: won == false ? WatchStyle.secondary : WatchStyle.ink,
              fontWeight: fontSize >= 12.5 ? FontWeight.w500 : null,
            ),
          ),
        ),
        if (value.isNotEmpty) ...[
          const SizedBox(width: 5),
          Text(
            value,
            style: WatchStyle.figures.copyWith(
              fontSize: fontSize,
              color: tone,
              fontWeight: lit ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ],
      ],
    );
  }
}

/// One position per watch viewport. Player strips use the same colors and
/// federation marks as the phone; the board itself opens its full game
/// tools. A board whose position has not arrived shows its names over an
/// empty board of the same size, so the list never shifts under a finger.
class WatchBoardTile extends StatelessWidget {
  const WatchBoardTile({super.key, required this.game, required this.onTap});
  final Games game;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final height =
          MediaQuery.sizeOf(context).height -
          WatchStatusBar.heightOf(context) -
          MediaQuery.paddingOf(context).bottom -
          6;
      final line = MediaQuery.textScalerOf(context).scale(12) * 1.3;
      final board = math.min(
        constraints.maxWidth,
        math.max(72.0, height - line * 2 - 8),
      );
      return Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Semantics(
          button: true,
          label:
              'Board ${game.boardNr ?? ''}. ${game.players?.map((p) => p.name).join(' versus ') ?? 'Game'}. ${watchResult(game.status)}.',
          hint: 'Opens game tools',
          // excludeSemantics drops the CupertinoButton's own tap action, so
          // the merged node must carry it or VoiceOver cannot activate it.
          onTap: onTap,
          excludeSemantics: true,
          child: WatchPressable(
            onPressed: () {
              WatchHaptics.click();
              onTap();
            },
            builder: (context, _) => Center(
              child: SizedBox(
                width: board,
                child: Column(
                  children: [
                    WatchPlayerLine(game: game, index: 1),
                    const SizedBox(height: 4),
                    WatchBoard(
                      fen: game.fen ?? watchEmptyFen,
                      lastMove: game.fen == null ? null : game.lastMove,
                    ),
                    const SizedBox(height: 4),
                    WatchPlayerLine(game: game, index: 0),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}

/// A critically damped spring expressed as a curve, so a Crown or flick step
/// moves like the rest of ChessEver's physics-based motion, not an easing.
class _SpringCurve extends Curve {
  const _SpringCurve();
  static final _spring = SpringSimulation(
    SpringDescription.withDampingRatio(mass: 1, stiffness: 300),
    0,
    1,
    0,
  );

  // 0.42 s of spring time: within 0.4 % of rest, so the end is seamless.
  @override
  double transformInternal(double t) => _spring.x(t * 0.42);
}
