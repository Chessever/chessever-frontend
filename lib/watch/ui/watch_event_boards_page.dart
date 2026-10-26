import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/cupertino.dart';
import 'package:flutter_watchos/flutter_watchos.dart';
import '../../repository/supabase/game/games.dart';
import '../core/watch_models.dart';
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

  WatchRepository get _repository => widget.controller.repository;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WatchAlwaysOn.state.addListener(_poll);
    unawaited(_select());
  }

  void _poll() {
    _timer?.cancel();
    if (_active && !WatchAlwaysOn.isActive && _games.any(watchGameIsLive)) {
      _timer = Timer.periodic(const Duration(seconds: 15), (_) {
        if (ModalRoute.of(context)?.isCurrent ?? false) unawaited(_refresh());
      });
    }
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
        visual: WatchEventArtwork(
          repository: _repository,
          eventId: widget.event.id,
        ),
        onTap: _busy ? null : _choose,
      ),
      if (_tour != null)
        WatchRow(
          label: 'Standings',
          icon: CupertinoIcons.person_2,
          onTap: () =>
              watchPush(context, watchStandingsPage(widget.controller, _tour!)),
        ),
      if (_error != null) WatchNote(_error!),
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
        WatchBoardTile(
          key: ValueKey('watch-board-${_games[index].id}'),
          game: _games[index],
          onTap: () => watchPush(
            context,
            WatchGamePage(
              controller: widget.controller,
              game: _games[index],
              tour: _tour,
            ),
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
    final value = switch (game.status) {
      '1-0' => index == 0 ? '1' : '0',
      '0-1' => index == 0 ? '0' : '1',
      '1/2-1/2' => '½',
      _ => clock == null ? '' : watchClock(clock),
    };
    return Row(
      key: ValueKey('watch-player-strip-$index'),
      children: [
        if (flag != null) ...[
          ExcludeSemantics(child: flag),
          const SizedBox(width: 5),
        ],
        Expanded(
          child: Text(
            player?.name ?? (index == 0 ? 'White' : 'Black'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: WatchStyle.caption.copyWith(color: WatchStyle.ink),
          ),
        ),
        if (value.isNotEmpty) ...[
          const SizedBox(width: 5),
          Text(
            value,
            style: WatchStyle.caption.copyWith(color: WatchStyle.ink),
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
              'Board ${game.boardNr ?? ''}. ${game.players?.map((p) => p.name).join(' versus ') ?? 'Game'}. ${watchResult(game.status)}. Open game.',
          excludeSemantics: true,
          child: CupertinoButton(
            padding: EdgeInsets.zero,
            minimumSize: const Size(44, 44),
            onPressed: onTap,
            child: Center(
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
