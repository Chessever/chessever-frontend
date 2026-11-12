import 'dart:async';
import 'dart:math' as math;
import 'package:chessever_watch_bridge/chessever_watch_bridge.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/physics.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:flutter_watchos/flutter_watchos.dart';
import '../../repository/supabase/game/games.dart';
import '../core/watch_models.dart';
import '../core/watch_wrist_flick.dart';
import '../core/watch_repository.dart';
import '../watch_controller.dart';
import 'watch_board.dart';
import 'watch_event_pages.dart';
import 'watch_game_page.dart';
import 'watch_visuals.dart';
import 'watch_widgets.dart';

class WatchEventBoardsPage extends StatefulWidget {
  const WatchEventBoardsPage({
    super.key,
    required this.controller,
    required this.event,
  });
  final WatchController controller;
  final WatchEvent event;

  /// Test seam: replaces the CoreMotion gyroscope so a recorded flick can be
  /// replayed through the real feed off-watch.
  @visibleForTesting
  static Stream<GyroscopeEvent> Function()? debugGyroscope;

  @override
  State<WatchEventBoardsPage> createState() => _WatchEventBoardsPageState();
}

class _WatchEventBoardsPageState extends State<WatchEventBoardsPage>
    with WidgetsBindingObserver {
  WatchTour? _tour;
  List<WatchRound> _rounds = [];
  WatchRound? _round;
  List<Games> _games = [];
  bool _busy = false;
  bool _more = false;
  bool _active = true;
  String? _error;
  Timer? _timer;
  final _scroll = ScrollController();
  final _tileKeys = <String, GlobalKey>{};

  // Wrist flick: the gyroscope runs only while this feed is the visible
  // screen, the app is active and Always On is not dimming it.
  final _flick = WatchWristFlick();
  final _clock = Stopwatch();
  StreamSubscription<GyroscopeEvent>? _gyro;
  bool _covered = false;

  WatchRepository get _repository => widget.controller.repository;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WatchAlwaysOn.state.addListener(_poll);
    unawaited(_select());
  }

  void _poll() {
    _updateFlick();
    _timer?.cancel();
    if (_active && !WatchAlwaysOn.isActive && _games.any(watchGameIsLive)) {
      _timer = Timer.periodic(const Duration(seconds: 15), (timer) {
        if (!watchShouldPoll(
          timer.tick,
          constrained: ChesseverWatchBridge.powerConstrained,
        )) {
          return;
        }
        if (ModalRoute.of(context)?.isCurrent ?? false) unawaited(_refresh());
      });
    }
  }

  void _updateFlick() {
    final source = WatchEventBoardsPage.debugGyroscope;
    final want =
        (FlutterWatchosPlatform.isWatch || source != null) &&
        _active &&
        !_covered &&
        !WatchAlwaysOn.isActive &&
        _games.length > 1;
    if (want && _gyro == null) {
      _flick.reset();
      _clock
        ..reset()
        ..start();
      final stream =
          source?.call() ??
          gyroscopeEventStream(samplingPeriod: SensorInterval.gameInterval);
      _gyro = stream.listen(
        (e) {
          final step = _flick.add(e.x, e.y, e.z, _clock.elapsed);
          if (step != 0) _stepBoard(step);
        },
        onError: (_) => _stopFlick(),
        cancelOnError: true,
      );
    } else if (!want) {
      _stopFlick();
    }
  }

  void _stopFlick() {
    unawaited(_gyro?.cancel());
    _gyro = null;
    _clock.stop();
  }

  /// Moves the feed one board forward or back, landing the next board in
  /// the same resting slot under the clock that the first board occupies,
  /// with a haptic so the move is felt.
  void _stepBoard(int direction) {
    final viewport = context.findRenderObject();
    if (!_scroll.hasClients || _games.isEmpty || viewport == null) return;
    final resting = WatchStatusBar.heightOf(context) + 4;
    double? topOf(int i) {
      final box =
          _tileKeys[_games[i].id]?.currentContext?.findRenderObject()
              as RenderBox?;
      if (box == null || !box.attached) return null;
      return box.localToGlobal(Offset.zero, ancestor: viewport).dy;
    }

    var current = 0;
    var best = double.infinity;
    for (var i = 0; i < _games.length; i++) {
      final top = topOf(i);
      if (top != null && (top - resting).abs() < best) {
        best = (top - resting).abs();
        current = i;
      }
    }
    final target = (current + direction).clamp(0, _games.length - 1);
    final targetTop = topOf(target);
    if (target == current || targetTop == null) {
      WatchHaptics.play(WatchHapticType.failure);
      return;
    }
    WatchHaptics.play(
      direction > 0
          ? WatchHapticType.directionDown
          : WatchHapticType.directionUp,
    );
    final position = _scroll.position;
    final to = (position.pixels + targetTop - resting).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if (MediaQuery.disableAnimationsOf(context)) {
      _scroll.jumpTo(to);
    } else {
      unawaited(
        _scroll.animateTo(
          to,
          duration: const Duration(milliseconds: 420),
          curve: const _SpringCurve(),
        ),
      );
    }
  }

  Future<void> _openGame(int index) async {
    setState(() => _covered = true);
    _updateFlick();
    await Navigator.of(context).push(
      CupertinoPageRoute<void>(
        builder: (_) => WatchGamePage(
          controller: widget.controller,
          game: _games[index],
          tour: _tour,
        ),
      ),
    );
    if (!mounted) return;
    setState(() => _covered = false);
    _updateFlick();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _active = state == AppLifecycleState.resumed;
    _poll();
    if (_active) unawaited(_refresh());
  }

  Future<void> _select({WatchTour? tour, WatchRound? round}) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final selected =
          tour ?? (await _repository.tours(widget.event.id)).firstOrNull;
      if (selected == null) {
        if (mounted) {
          setState(() {
            _tour = null;
            _games = [];
          });
        }
        return;
      }
      final rounds = await _repository.rounds(selected.id);
      final now = DateTime.now();
      final started = rounds
          .where((r) => r.startsAt == null || !r.startsAt!.isAfter(now))
          .toList();
      final candidates = round != null
          ? [round]
          : (started.isEmpty
                ? rounds.take(1).toList()
                : started.reversed.take(5).toList());
      WatchRound? chosen = candidates.firstOrNull;
      List<Games> games = [];
      for (final candidate in candidates) {
        games = await _repository.games(candidate.id);
        if (games.isNotEmpty) {
          chosen = candidate;
          break;
        }
      }
      if (!mounted) return;
      setState(() {
        _tour = selected;
        _rounds = rounds;
        _round = chosen;
        _games = games;
        _more = games.length == WatchRepository.pageSize;
      });
      if (_scroll.hasClients) _scroll.jumpTo(0);
      _poll();
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not load boards. Pull to try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _refresh({bool more = false}) async {
    if (_busy) return;
    if (_round == null) return _select();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final games = <Games>[];
      final start = more ? _games.length : 0;
      final end = more
          ? start + WatchRepository.pageSize
          : math.max(_games.length, WatchRepository.pageSize);
      List<Games> page = [];
      for (
        var offset = start;
        offset < end;
        offset += WatchRepository.pageSize
      ) {
        page = await _repository.games(_round!.id, offset: offset);
        games.addAll(page);
        if (page.length < WatchRepository.pageSize) break;
      }
      if (!mounted) return;
      setState(() {
        _games = more ? [..._games, ...games] : games;
        _more = page.length == WatchRepository.pageSize;
      });
      _poll();
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Offline · showing the last boards.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _choose() async {
    final choice = await Navigator.of(context).push<(WatchTour, WatchRound)>(
      CupertinoPageRoute(
        builder: (context) => WatchDataPage<WatchTour>(
          title: 'Sections',
          load: (_) => _repository.tours(widget.event.id),
          items: (context, tours) => [
            for (final tour in tours)
              WatchRow(
                label: tour.name,
                icon: CupertinoIcons.square_grid_2x2,
                onTap: () async {
                  final round = await Navigator.of(context).push<WatchRound>(
                    CupertinoPageRoute(
                      builder: (context) => WatchDataPage<WatchRound>(
                        title: 'Rounds',
                        load: (_) => _repository.rounds(tour.id),
                        items: (context, rounds) => [
                          for (final round in rounds.reversed)
                            WatchRow(
                              label: round.name,
                              icon: CupertinoIcons.calendar,
                              onTap: () => Navigator.of(context).pop(round),
                            ),
                        ],
                      ),
                    ),
                  );
                  if (context.mounted && round != null) {
                    Navigator.of(context).pop((tour, round));
                  }
                },
              ),
          ],
        ),
      ),
    );
    if (mounted && choice != null) {
      await _select(tour: choice.$1, round: choice.$2);
    }
  }

  Widget _roundInfo() => Column(
    children: [
      WatchRow(
        label: _round?.name ?? widget.event.name,
        detail: _tour?.name == widget.event.name
            ? 'Change round'
            : _tour?.name ?? 'Choose a section',
        onTap: _busy ? null : _choose,
      ),
      if (_tour != null)
        WatchRow(
          label: 'Standings',
          icon: CupertinoIcons.person_2,
          onTap: () =>
              watchPush(context, watchStandingsPage(widget.controller, _tour!)),
        ),
      if (_error != null) WatchNote.status(_error!),
    ],
  );

  @override
  Widget build(BuildContext context) => WatchPage(
    title: 'Boards',
    boardFirst: _games.isNotEmpty,
    boardBackLabel: 'Back to Current',
    scrollController: _scroll,
    onRefresh: _refresh,
    refreshing: _busy,
    children: [
      if (_games.isEmpty) ...[
        if (_busy)
          const Padding(
            padding: EdgeInsets.all(12),
            child: Center(child: CupertinoActivityIndicator()),
          ),
        if (!_busy)
          const WatchNote('Boards have not been published for this round.'),
        if (!_busy || _tour != null) _roundInfo(),
      ],
      for (var index = 0; index < _games.length; index++) ...[
        KeyedSubtree(
          key: _tileKeys.putIfAbsent(_games[index].id, GlobalKey.new),
          child: WatchBoardTile(
            key: ValueKey('watch-board-${_games[index].id}'),
            game: _games[index],
            onTap: () => _openGame(index),
          ),
        ),
        if (index == 0) _roundInfo(),
      ],
      if (_more)
        WatchRow(
          label: _busy ? 'Loading…' : 'More boards',
          onTap: _busy ? null : () => _refresh(more: true),
        ),
      if (_round != null && _rounds.indexWhere((r) => r.id == _round!.id) > 0)
        WatchRow(
          label: 'Earlier round',
          icon: CupertinoIcons.chevron_back,
          onTap: _busy
              ? null
              : () => _select(
                  tour: _tour,
                  round:
                      _rounds[_rounds.indexWhere((r) => r.id == _round!.id) -
                          1],
                ),
        ),
    ],
  );

  @override
  void dispose() {
    _stopFlick();
    _timer?.cancel();
    _scroll.dispose();
    WatchAlwaysOn.state.removeListener(_poll);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}

/// One position per watch viewport. Player strips use the same colors and
/// federation marks as the phone; the board itself opens its full game tools.
class WatchBoardTile extends StatelessWidget {
  const WatchBoardTile({super.key, required this.game, required this.onTap});
  final Games game;
  final VoidCallback onTap;

  Widget _player(int index) {
    final player = game.players != null && game.players!.length > index
        ? game.players![index]
        : null;
    final flag = watchFederation(player?.fed);
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
    // Scoresheet emphasis: the winner, or the side whose clock is running,
    // sits in ink; everyone else steps back to the secondary tone.
    final lit =
        won ??
        (watchIsLive(game.status) && watchWhiteToMove(game.fen) == white);
    final tone = lit ? WatchStyle.ink : WatchStyle.secondary;
    return Row(
      key: ValueKey('watch-player-strip-$index'),
      children: [
        if (flag != null) ...[
          ExcludeSemantics(child: flag),
          const SizedBox(width: 5),
        ],
        Expanded(
          child: Text(
            player?.name ?? (white ? 'White' : 'Black'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: WatchStyle.caption.copyWith(
              color: won == false ? WatchStyle.secondary : WatchStyle.ink,
            ),
          ),
        ),
        if (value.isNotEmpty) ...[
          const SizedBox(width: 5),
          Text(
            value,
            style: WatchStyle.figures.copyWith(
              color: tone,
              fontWeight: lit ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ],
      ],
    );
  }

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
                    _player(1),
                    const SizedBox(height: 4),
                    WatchBoard(fen: game.fen, lastMove: game.lastMove),
                    const SizedBox(height: 4),
                    _player(0),
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

/// A critically damped spring expressed as a curve, so the flick step moves
/// like the rest of ChessEver's physics-based motion rather than an easing.
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
