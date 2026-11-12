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
import 'watch_round_wheel.dart';
import 'watch_visuals.dart';
import 'watch_widgets.dart';

/// The round an event page is showing, shared by the event page and the
/// board feed opened from it so both read, refresh and page the same boards.
class WatchRoundFeed extends ChangeNotifier {
  WatchRoundFeed(this._repository, this.eventId);
  final WatchRepository _repository;
  final String eventId;

  List<WatchTour> tours = [];
  WatchTour? tour;
  List<WatchRound> rounds = [];
  WatchRound? round;
  List<Games> games = [];
  bool busy = false;
  bool more = false;
  bool loaded = false;
  String? error;

  /// True while a board feed for this round is the visible screen; the
  /// event page keeps polling for it.
  bool feedVisible = false;
  bool _disposed = false;

  int get roundIndex =>
      round == null ? -1 : rounds.indexWhere((r) => r.id == round!.id);

  /// Team matches when this is a team round, else null.
  List<WatchTeamMatch>? get matches => watchTeamMatches(games);

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  /// Opens [round] of [tour]. Without a round, opens the latest started
  /// round that has boards (looking back up to five rounds), so an event
  /// between rounds still lands on real games.
  Future<void> select({WatchTour? tour, WatchRound? round}) async {
    if (busy) return;
    busy = true;
    error = null;
    _changed();
    try {
      if (tours.isEmpty || tour == null) {
        tours = await _repository.tours(eventId);
      }
      final selected = tour ?? tours.firstOrNull;
      if (selected == null) {
        this.tour = null;
        rounds = [];
        this.round = null;
        games = [];
        return;
      }
      final schedule = selected.id == this.tour?.id && rounds.isNotEmpty
          ? rounds
          : await _repository.rounds(selected.id);
      final now = DateTime.now();
      final started = schedule
          .where((r) => r.startsAt == null || !r.startsAt!.isAfter(now))
          .toList();
      final candidates = round != null
          ? [round]
          : (started.isEmpty
                ? schedule.take(1).toList()
                : started.reversed.take(5).toList());
      WatchRound? chosen = candidates.firstOrNull;
      List<Games> found = [];
      for (final candidate in candidates) {
        found = await _repository.games(candidate.id);
        if (found.isNotEmpty) {
          chosen = candidate;
          break;
        }
      }
      this.tour = selected;
      rounds = schedule;
      this.round = chosen;
      games = found;
      more = found.length == WatchRepository.pageSize;
    } catch (_) {
      error = 'Could not load boards. Pull to try again.';
    } finally {
      busy = false;
      loaded = true;
      _changed();
    }
  }

  /// Opens the round [step] places from the shown one.
  Future<void> step(int step) async {
    final i = roundIndex + step;
    if (i < 0 || i >= rounds.length) return;
    await select(tour: tour, round: rounds[i]);
  }

  /// Reloads the shown boards (keeping as many as are loaded), or loads the
  /// next page with [more]. A failure keeps the last boards on screen.
  Future<void> refresh({bool more = false}) async {
    if (busy) return;
    if (round == null) return select(tour: tour);
    busy = true;
    error = null;
    _changed();
    try {
      final loaded = <Games>[];
      final start = more ? games.length : 0;
      final end = more
          ? start + WatchRepository.pageSize
          : math.max(games.length, WatchRepository.pageSize);
      List<Games> page = [];
      for (
        var offset = start;
        offset < end;
        offset += WatchRepository.pageSize
      ) {
        page = await _repository.games(round!.id, offset: offset);
        loaded.addAll(page);
        if (page.length < WatchRepository.pageSize) break;
      }
      games = more ? [...games, ...loaded] : loaded;
      this.more = page.length == WatchRepository.pageSize;
    } catch (_) {
      error = 'Offline · showing the last boards.';
    } finally {
      busy = false;
      _changed();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// An event on the wrist: the event's own photograph as the header, one
/// round at a time under it, then the round's matches (team events) or
/// pairings (individual events), each opening the full-board feed. Every
/// part is a vertical list, so the Digital Crown reaches all of it, and the
/// round itself is one Crown turn away on the round wheel.
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
  late final WatchRoundFeed _feed = WatchRoundFeed(
    widget.controller.repository,
    widget.event.id,
  );
  bool _active = true;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WatchAlwaysOn.state.addListener(_poll);
    _feed.addListener(_poll);
    unawaited(_feed.select());
  }

  bool _polling = false;
  void _poll() {
    final want =
        _active && !WatchAlwaysOn.isActive && _feed.games.any(watchGameIsLive);
    if (want == _polling) return;
    _polling = want;
    _timer?.cancel();
    if (!want) return;
    _timer = Timer.periodic(const Duration(seconds: 15), (timer) {
      if (!watchShouldPoll(
        timer.tick,
        constrained: ChesseverWatchBridge.powerConstrained,
      )) {
        return;
      }
      final visible = ModalRoute.of(context)?.isCurrent ?? false;
      if (visible || _feed.feedVisible) unawaited(_feed.refresh());
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _active = state == AppLifecycleState.resumed;
    _poll();
    if (_active) unawaited(_feed.refresh());
  }

  void _openFeed({WatchTeamMatch? match, String? gameId}) =>
      Navigator.of(context).push(
        CupertinoPageRoute<void>(
          builder: (_) => WatchBoardsFeedPage(
            controller: widget.controller,
            feed: _feed,
            matchKey: match?.key,
            title: match == null
                ? (_feed.round?.name ?? 'Boards')
                : '${match.home} – ${match.away}',
            initialGameId: gameId,
          ),
        ),
      );

  Future<void> _chooseRound() async {
    if (_feed.rounds.isEmpty) return;
    final round = await Navigator.of(context).push<WatchRound>(
      CupertinoPageRoute(
        builder: (_) => WatchRoundWheelPage(
          rounds: _feed.rounds,
          selectedId: _feed.round?.id,
        ),
      ),
    );
    if (mounted && round != null && round.id != _feed.round?.id) {
      await _feed.select(tour: _feed.tour, round: round);
    }
  }

  Future<void> _chooseSection() async {
    final tour = await Navigator.of(context).push<WatchTour>(
      CupertinoPageRoute(
        builder: (context) => WatchPage(
          title: 'Sections',
          children: [
            for (final tour in _feed.tours)
              WatchRow(
                label: tour.name,
                detail: tour.id == _feed.tour?.id ? 'Showing now' : null,
                trailing: tour.id == _feed.tour?.id
                    ? const Icon(
                        CupertinoIcons.checkmark_alt,
                        size: 16,
                        color: WatchStyle.ink,
                      )
                    : null,
                onTap: () => Navigator.of(context).pop(tour),
              ),
          ],
        ),
      ),
    );
    if (mounted && tour != null && tour.id != _feed.tour?.id) {
      await _feed.select(tour: tour);
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _feed,
    builder: (context, _) {
      final feed = _feed;
      final matches = feed.matches;
      final inMatches = {
        for (final m in matches ?? const <WatchTeamMatch>[])
          for (final g in m.games) g.id,
      };
      final loose = feed.games.where((g) => !inMatches.contains(g.id));
      final state = watchRoundState(feed.round, feed.games, DateTime.now());
      final leader = feed.tour?.standings.firstOrNull;
      final multiSection = feed.tours.length > 1;
      return WatchPage(
        title: widget.event.name,
        boardBackLabel: 'Back to Current',
        header: _EventHero(
          repository: widget.controller.repository,
          event: widget.event,
          section: multiSection ? feed.tour?.name : null,
        ),
        onRefresh: () => feed.loaded ? feed.refresh() : feed.select(),
        refreshing: feed.busy,
        children: [
          if (feed.rounds.isNotEmpty)
            _RoundBar(
              round: feed.round,
              state: state,
              busy: feed.busy,
              hasPrevious: feed.roundIndex > 0,
              hasNext:
                  feed.roundIndex >= 0 &&
                  feed.roundIndex < feed.rounds.length - 1,
              onPrevious: () => feed.step(-1),
              onNext: () => feed.step(1),
              onChoose: _chooseRound,
            ),
          if (feed.error != null) WatchNote.status(feed.error!),
          if (feed.busy && feed.games.isEmpty)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Center(child: CupertinoActivityIndicator()),
            ),
          if (!feed.busy && feed.loaded && feed.error == null) ...[
            if (feed.tour == null)
              const WatchNote('This event has not published its sections yet.')
            else if (feed.games.isEmpty)
              WatchNote(
                state.phase == WatchRoundPhase.upcoming
                    ? 'Boards appear here when the round starts.'
                    : 'Boards have not been published for this round.',
              ),
          ],
          for (final match in matches ?? const <WatchTeamMatch>[])
            _MatchCard(
              match: match,
              onTap: () => _openFeed(match: match),
            ),
          for (final game in loose)
            WatchPairingRow(
              key: ValueKey('watch-pairing-${game.id}'),
              game: game,
              onTap: () => _openFeed(gameId: game.id),
            ),
          if (feed.more)
            WatchRow(
              label: feed.busy
                  ? 'Loading…'
                  : (matches != null ? 'More matches' : 'More boards'),
              showChevron: false,
              icon: CupertinoIcons.chevron_down,
              onTap: feed.busy ? null : () => feed.refresh(more: true),
            ),
          if (feed.tour != null)
            WatchRow(
              label: 'Standings',
              icon: CupertinoIcons.person_2,
              detail: leader?.score == null
                  ? null
                  : watchShortName(leader!.name),
              value: leader?.score == null ? null : watchScore(leader!.score),
              onTap: () => watchPush(
                context,
                watchStandingsPage(widget.controller, feed.tour!),
              ),
            ),
          if (multiSection)
            WatchRow(
              label: 'Sections',
              icon: CupertinoIcons.square_grid_2x2,
              detail: '${feed.tours.length} sections',
              onTap: feed.busy ? null : _chooseSection,
            ),
        ],
      );
    },
  );

  @override
  void dispose() {
    _timer?.cancel();
    _feed.dispose();
    WatchAlwaysOn.state.removeListener(_poll);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}

/// The event's photograph with its name set on it, the same object the
/// Current card shows, so opening an event keeps its picture.
class _EventHero extends StatelessWidget {
  const _EventHero({
    required this.repository,
    required this.event,
    this.section,
  });
  final WatchRepository repository;
  final WatchEvent event;
  final String? section;

  @override
  Widget build(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context);
    final detail = section ?? watchTimeControl(event.timeControl);
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
                    if (detail != null && detail.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        detail,
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

/// `‹  Round 5  ›` with where the round stands under its name. The arrows
/// step one round; the name opens the round wheel.
class _RoundBar extends StatelessWidget {
  const _RoundBar({
    required this.round,
    required this.state,
    required this.busy,
    required this.hasPrevious,
    required this.hasNext,
    required this.onPrevious,
    required this.onNext,
    required this.onChoose,
  });
  final WatchRound? round;
  final WatchRoundState state;
  final bool busy;
  final bool hasPrevious;
  final bool hasNext;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onChoose;

  String _status(BuildContext context) => switch (state.phase) {
    WatchRoundPhase.upcoming =>
      'Starts ${watchWhen(round!.startsAt!.toLocal(), DateTime.now(), use24h: MediaQuery.alwaysUse24HourFormatOf(context))}',
    WatchRoundPhase.live =>
      state.live == state.total
          ? '${state.live} live'
          : '${state.live} of ${state.total} live',
    WatchRoundPhase.finished => 'Finished',
    WatchRoundPhase.empty => 'No boards yet',
  };

  Widget _arrow({
    required IconData icon,
    required String label,
    required bool enabled,
    required VoidCallback onTap,
  }) => Semantics(
    label: label,
    excludeSemantics: true,
    button: true,
    enabled: enabled,
    onTap: enabled ? onTap : null,
    child: WatchPressable(
      onPressed: enabled
          ? () {
              WatchHaptics.click();
              onTap();
            }
          : null,
      // A 44 pt target whose chevron sits toward the bar's edge, clear of
      // the round name.
      builder: (context, pressed) => SizedBox(
        width: 44,
        child: Align(
          alignment: Alignment(
            icon == CupertinoIcons.chevron_back ? -0.45 : 0.45,
            0,
          ),
          child: Icon(
            icon,
            size: 17,
            color: !enabled
                ? WatchStyle.disabled
                : pressed
                ? WatchStyle.secondary
                : WatchStyle.ink,
          ),
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final status = busy && round == null ? '…' : _status(context);
    final live = state.phase == WatchRoundPhase.live;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: WatchStyle.surface,
          borderRadius: BorderRadius.circular(14),
        ),
        // The name takes the whole width and the arrows sit over its side
        // margins, so a 40 mm watch still sets "Round 7" on one line while
        // every arrow keeps a full-height tap target.
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Semantics(
                button: true,
                label: '${round?.name ?? 'Round'}. $status',
                hint: 'Choose a round',
                excludeSemantics: true,
                onTap: onChoose,
                child: WatchPressable(
                  onPressed: () {
                    WatchHaptics.click();
                    onChoose();
                  },
                  builder: (context, pressed) => Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      vertical: 8,
                      horizontal: 26,
                    ),
                    decoration: BoxDecoration(
                      color: pressed
                          ? WatchStyle.surfacePressed
                          : const Color(0x00000000),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          round?.name ?? 'Rounds',
                          key: const ValueKey('watch-round-name'),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
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
                          textAlign: TextAlign.center,
                          style: WatchStyle.figures.copyWith(
                            color: live ? WatchStyle.ink : null,
                            fontWeight: live ? FontWeight.w600 : null,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              child: _arrow(
                icon: CupertinoIcons.chevron_back,
                label: 'Previous round',
                enabled: hasPrevious && !busy,
                onTap: onPrevious,
              ),
            ),
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              child: _arrow(
                icon: CupertinoIcons.chevron_forward,
                label: 'Next round',
                enabled: hasNext && !busy,
                onTap: onNext,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One team match: both teams with their match score, and under them the
/// match read board by board from the first-named team's side, like the
/// result column of a team scoresheet (`1 ½ 0 •`, a dot for a game still
/// being played).
class _MatchCard extends StatelessWidget {
  const _MatchCard({required this.match, required this.onTap});
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
    final status = match.live
        ? 'Live'
        : match.finished
        ? 'Final'
        : '';
    final boards = match.games.map(_board).join('  ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Semantics(
        button: true,
        label:
            '${match.home} ${watchScore(match.homeScore)}, '
            '${match.away} ${watchScore(match.awayScore)}. '
            '${match.games.length} boards. $status',
        hint: 'Opens the boards',
        excludeSemantics: true,
        onTap: onTap,
        child: WatchPressable(
          onPressed: () {
            WatchHaptics.click();
            onTap();
          },
          builder: (context, pressed) => Container(
            key: ValueKey('watch-match-${match.key}'),
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
                          color: match.live ? WatchStyle.ink : null,
                          fontWeight: match.live ? FontWeight.w600 : null,
                        ),
                      ),
                    ],
                    const SizedBox(width: 4),
                    const Icon(
                      CupertinoIcons.chevron_forward,
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

/// A game as a compact pairing: White over Black, each with flag, name and
/// result or clock. Opens the full-board feed on this board.
class WatchPairingRow extends StatelessWidget {
  const WatchPairingRow({super.key, required this.game, required this.onTap});
  final Games game;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Semantics(
      button: true,
      label:
          '${game.boardNr == null ? '' : 'Board ${game.boardNr}. '}'
          '${game.players?.map((p) => p.name).join(' versus ') ?? 'Game'}. '
          '${watchResult(game.status)}.',
      hint: 'Opens the board',
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
            vertical: 9,
          ),
          decoration: BoxDecoration(
            color: pressed ? WatchStyle.surfacePressed : WatchStyle.surface,
            borderRadius: BorderRadius.circular(14),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final flags = constraints.maxWidth >= 120;
              return Column(
                children: [
                  for (final side in [0, 1]) ...[
                    if (side == 1) const SizedBox(height: 4),
                    WatchPlayerLine(
                      game: game,
                      index: side,
                      fontSize: 12.5,
                      flagWidth: 16,
                      showFlag: flags,
                    ),
                  ],
                ],
              );
            },
          ),
        ),
      ),
    ),
  );
}

/// The round's boards, one full board per watch screen, opened from the
/// event page on the board that was tapped (or on a team match's boards).
/// A wrist flick steps one board; the Crown scrolls freely; a board opens
/// its game tools.
class WatchBoardsFeedPage extends StatefulWidget {
  const WatchBoardsFeedPage({
    super.key,
    required this.controller,
    required this.feed,
    required this.title,
    this.matchKey,
    this.initialGameId,
  });
  final WatchController controller;
  final WatchRoundFeed feed;
  final String title;

  /// Shows only this team match's boards.
  final String? matchKey;
  final String? initialGameId;

  /// Test seam: replaces the CoreMotion gyroscope so a recorded flick can be
  /// replayed through the real feed off-watch.
  @visibleForTesting
  static Stream<GyroscopeEvent> Function()? debugGyroscope;

  @override
  State<WatchBoardsFeedPage> createState() => _WatchBoardsFeedPageState();
}

class _WatchBoardsFeedPageState extends State<WatchBoardsFeedPage>
    with WidgetsBindingObserver {
  final _scroll = ScrollController();
  final _tileKeys = <String, GlobalKey>{};
  final _flick = WatchWristFlick();
  final _clock = Stopwatch();
  StreamSubscription<GyroscopeEvent>? _gyro;
  bool _covered = false;
  bool _active = true;

  List<Games> get _games {
    final key = widget.matchKey;
    if (key == null) return widget.feed.games;
    return widget.feed.matches?.where((m) => m.key == key).firstOrNull?.games ??
        const [];
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WatchAlwaysOn.state.addListener(_updateFlick);
    widget.feed.addListener(_updateFlick);
    widget.feed.feedVisible = true;
    _updateFlick();
    if (widget.initialGameId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _jumpTo());
    }
  }

  void _jumpTo() {
    if (!mounted) return;
    final i = _games.indexWhere((g) => g.id == widget.initialGameId);
    if (i <= 0) return;
    final top = _topOf(i);
    if (top == null || !_scroll.hasClients) return;
    final position = _scroll.position;
    position.jumpTo(
      (position.pixels + top - _resting).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      ),
    );
  }

  double get _resting => WatchStatusBar.heightOf(context) + 4;

  double? _topOf(int i) {
    final viewport = context.findRenderObject();
    final games = _games;
    if (viewport == null || i < 0 || i >= games.length) return null;
    final box =
        _tileKeys[games[i].id]?.currentContext?.findRenderObject()
            as RenderBox?;
    if (box == null || !box.attached) return null;
    return box.localToGlobal(Offset.zero, ancestor: viewport).dy;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _active = state == AppLifecycleState.resumed;
    _updateFlick();
  }

  void _updateFlick() {
    final source = WatchBoardsFeedPage.debugGyroscope;
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
    final games = _games;
    if (!_scroll.hasClients || games.isEmpty) return;
    var current = 0;
    var best = double.infinity;
    for (var i = 0; i < games.length; i++) {
      final top = _topOf(i);
      if (top != null && (top - _resting).abs() < best) {
        best = (top - _resting).abs();
        current = i;
      }
    }
    final target = (current + direction).clamp(0, games.length - 1);
    final targetTop = _topOf(target);
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
    final to = (position.pixels + targetTop - _resting).clamp(
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

  Future<void> _openGame(Games game) async {
    setState(() => _covered = true);
    widget.feed.feedVisible = false;
    _updateFlick();
    await Navigator.of(context).push(
      CupertinoPageRoute<void>(
        builder: (_) => WatchGamePage(
          controller: widget.controller,
          game: game,
          tour: widget.feed.tour,
        ),
      ),
    );
    if (!mounted) return;
    setState(() => _covered = false);
    widget.feed.feedVisible = true;
    _updateFlick();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.feed,
    builder: (context, _) {
      final feed = widget.feed;
      final games = _games;
      return WatchPage(
        title: widget.title,
        boardFirst: games.isNotEmpty,
        boardBackLabel: 'Back to event',
        scrollController: _scroll,
        onRefresh: () => feed.refresh(),
        refreshing: feed.busy,
        children: [
          if (games.isEmpty)
            const WatchNote('These boards are no longer in this round.'),
          for (final game in games)
            KeyedSubtree(
              key: _tileKeys.putIfAbsent(game.id, GlobalKey.new),
              child: WatchBoardTile(
                key: ValueKey('watch-board-${game.id}'),
                game: game,
                onTap: () => _openGame(game),
              ),
            ),
          if (feed.error != null) WatchNote.status(feed.error!),
          if (feed.more && widget.matchKey == null)
            WatchRow(
              label: feed.busy ? 'Loading…' : 'More boards',
              showChevron: false,
              icon: CupertinoIcons.chevron_down,
              onTap: feed.busy ? null : () => feed.refresh(more: true),
            ),
        ],
      );
    },
  );

  @override
  void dispose() {
    _stopFlick();
    widget.feed.feedVisible = false;
    widget.feed.removeListener(_updateFlick);
    _scroll.dispose();
    WatchAlwaysOn.state.removeListener(_updateFlick);
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
                    WatchBoard(fen: game.fen, lastMove: game.lastMove),
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
