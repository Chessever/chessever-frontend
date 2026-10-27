import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter_watchos/flutter_watchos.dart';
import '../../repository/supabase/game/games.dart';
import '../core/watch_models.dart';
import '../watch_controller.dart';
import 'watch_board.dart';
import 'watch_event_pages.dart';
import 'watch_widgets.dart';
import 'watch_visuals.dart';
import 'watch_replay_page.dart';

class WatchGamePage extends StatefulWidget {
  const WatchGamePage({
    super.key,
    required this.controller,
    required this.game,
    this.tour,
  });
  final WatchController controller;
  final Games game;
  final WatchTour? tour;
  @override
  State<WatchGamePage> createState() => _WatchGamePageState();
}

class _WatchGamePageState extends State<WatchGamePage>
    with WidgetsBindingObserver {
  late Games _game;
  DateTime? _fetchedAt;
  bool _busy = false;
  bool _flipped = false;
  String? _error;
  String? _handoff;
  bool _sending = false;
  bool _active = true;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _game = widget.game;
    WidgetsBinding.instance.addObserver(this);
    WatchAlwaysOn.state.addListener(_updatePolling);
    _updatePolling();
    unawaited(_refresh());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _active = state == AppLifecycleState.resumed;
    _updatePolling();
    if (_active) unawaited(_refresh());
  }

  void _updatePolling() {
    _timer?.cancel();
    if (_active && !WatchAlwaysOn.isActive && watchGameIsLive(_game)) {
      _timer = Timer.periodic(const Duration(seconds: 15), (_) {
        if (ModalRoute.of(context)?.isCurrent ?? false) unawaited(_refresh());
      });
    }
  }

  Future<void> _refresh() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final game = await widget.controller.repository.game(_game.id);
      if (!mounted) return;
      setState(() {
        if (game != null) _game = game;
        _error = game == null ? 'Game no longer available.' : null;
        if (game != null) _fetchedAt = DateTime.now();
      });
      _updatePolling();
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Offline · showing the last position.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sendToPhone() async {
    if (_sending) return;
    setState(() => _sending = true);
    final accepted = await widget.controller.openOnPhone(_game.id);
    if (mounted) {
      setState(() {
        _sending = false;
        _handoff = accepted
            ? 'Sent to iPhone.'
            : 'Open ChessEver on your iPhone, then try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) => WatchPage(
    title: 'Board ${_game.boardNr ?? '—'}',
    boardFirst: true,
    onRefresh: _refresh,
    refreshing: _busy,
    children: [
      WatchBoard(fen: _game.fen, lastMove: _game.lastMove, flipped: _flipped),
      const SizedBox(height: 8),
      WatchNote('Board ${_game.boardNr ?? '—'}'),
      if (_game.players?.isNotEmpty ?? false) _player(_game.players![0], true),
      if (_game.players != null && _game.players!.length >= 2)
        _player(_game.players![1], false),
      WatchNote(
        '${watchResult(_game.status)}'
        '${_game.lastMove == null ? '' : ' · ${_game.lastMove}'}',
      ),
      if (_fetchedAt != null)
        WatchNote(
          'Relay clocks · fetched '
          '${_fetchedAt!.hour.toString().padLeft(2, '0')}:'
          '${_fetchedAt!.minute.toString().padLeft(2, '0')}:'
          '${_fetchedAt!.second.toString().padLeft(2, '0')}',
        ),
      if (_error != null) WatchNote(_error!),
      WatchRow(
        label: 'Review moves',
        icon: CupertinoIcons.gobackward,
        detail: 'Turn the Crown through the game',
        onTap: () => watchPush(
          context,
          WatchReplayPage(
            loadPgn: () => widget.controller.repository.gamePgn(_game.id),
            flipped: _flipped,
          ),
        ),
      ),
      WatchRow(
        label: _flipped ? 'White at bottom' : 'Black at bottom',
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
      if (_handoff != null) WatchNote(_handoff!),
    ],
  );

  Widget _player(Player player, bool white) {
    final clock = white ? _game.lastClockWhite : _game.lastClockBlack;
    final seconds = clock ?? (player.clock > 0 ? player.clock ~/ 100 : null);
    final tour = widget.tour;
    WatchStanding? standing;
    if (tour != null) {
      standing = tour.players
          .where((p) => watchPlayerMatches(player, p))
          .firstOrNull;
    }
    final selected = standing;
    return WatchRow(
      label: player.name,
      visual: watchFederation(player.fed),
      detail:
          '${white ? 'White' : 'Black'}'
          '${player.rating > 0 ? ' · ${player.rating}' : ''}'
          '${seconds == null ? '' : ' · ${watchClock(seconds)}'}',
      onTap: tour == null || selected == null
          ? null
          : () => watchPush(
              context,
              watchScorecardPage(widget.controller, tour, selected),
            ),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    WatchAlwaysOn.state.removeListener(_updatePolling);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}

String watchClock(int seconds) {
  final safe = seconds < 0 ? 0 : seconds;
  final minutes = safe ~/ 60;
  final remainder = (safe % 60).toString().padLeft(2, '0');
  return '$minutes:$remainder';
}
