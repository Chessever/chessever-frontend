import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/cupertino.dart';
import 'package:flutter_watchos/flutter_watchos.dart';
import '../core/watch_replay.dart';
import 'watch_board.dart';
import 'watch_widgets.dart';

/// Crown input is exclusive only while this route is visible and active.
/// Finger scrolling and touch buttons remain available throughout review.
class WatchReplayPage extends StatefulWidget {
  const WatchReplayPage({
    super.key,
    required this.loadPgn,
    this.flipped = false,
  });
  final Future<String?> Function() loadPgn;
  final bool flipped;

  @override
  State<WatchReplayPage> createState() => _WatchReplayPageState();
}

class _WatchReplayPageState extends State<WatchReplayPage>
    with WidgetsBindingObserver {
  final _dial = WatchReplayDial();
  final _scroll = ScrollController();
  final _hapticClock = Stopwatch()..start();
  int _lastHapticMs = -100;
  StreamSubscription<CrownRotationEvent>? _crown;
  List<WatchReplayPosition> _positions = [];
  int _index = 0;
  bool _busy = false;
  bool _foreground = true;
  bool _visible = false;
  bool _crownReview = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _foreground =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    WatchAlwaysOn.state.addListener(_syncCrown);
    unawaited(_load());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _visible =
        TickerMode.valuesOf(context).enabled &&
        (ModalRoute.isCurrentOf(context) ?? true);
    _syncCrown();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _syncCrown();
  }

  void _syncCrown() {
    final enabled =
        mounted &&
        _visible &&
        _foreground &&
        !WatchAlwaysOn.isActive &&
        _positions.isNotEmpty &&
        _crownReview;
    if (enabled && _crown == null) {
      _dial.reset();
      _crown = WatchCrown.instance.rotations.listen((event) {
        if (!mounted || !_visible || !_foreground || WatchAlwaysOn.isActive) {
          return;
        }
        final next = _dial.turn(
          event.delta,
          index: _index,
          last: _positions.length - 1,
        );
        _select(next, resetDial: false);
      });
    } else if (!enabled && _crown != null) {
      unawaited(_crown!.cancel());
      _crown = null;
      _dial.reset();
    }
  }

  Future<void> _load() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final positions = watchReplayPositions(await widget.loadPgn());
      if (!mounted) return;
      setState(() {
        _positions = positions;
        _index = positions.isEmpty ? 0 : positions.length - 1;
      });
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not load moves. Try again.');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        _syncCrown();
      }
    }
  }

  void _select(int next, {bool resetDial = true}) {
    if (resetDial) _dial.reset();
    if (next == _index) return;
    setState(() => _index = next);
    final now = _hapticClock.elapsedMilliseconds;
    if (now - _lastHapticMs >= 70) {
      WatchHaptics.click();
      _lastHapticMs = now;
    }
  }

  void _toggleCrown() {
    setState(() => _crownReview = !_crownReview);
    _syncCrown();
    // Activating move review brings its board back into view. A finger swipe
    // or the scroll-mode button still reaches every control below the board.
    if (_crownReview && _scroll.hasClients) _scroll.jumpTo(0);
  }

  Widget _step(String label, IconData icon, VoidCallback? action) => Expanded(
    child: Semantics(
      label: label,
      child: CupertinoButton(
        padding: EdgeInsets.zero,
        minimumSize: const Size(44, 44),
        onPressed: action,
        child: Icon(icon, size: 23),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final ready = _positions.isNotEmpty;
    final position = ready ? _positions[_index] : null;
    final media = MediaQuery.of(context);
    // Keep the current move visible beside its board on the smallest watch.
    // Controls below stay at their full touch size and scroll with a finger.
    final boardSize = math.min(
      media.size.width - media.padding.horizontal - 10,
      math.max(
        72.0,
        media.size.height -
            WatchStatusBar.heightOf(context) -
            media.padding.bottom -
            12 -
            media.textScaler.scale(28),
      ),
    );
    return WatchPage(
      title: 'Review moves',
      boardFirst: ready,
      boardBackLabel: 'Done',
      scrollController: _scroll,
      children: [
        if (_busy)
          const Padding(
            padding: EdgeInsets.all(12),
            child: Center(child: CupertinoActivityIndicator()),
          ),
        if (_error != null) WatchNote(_error!),
        if (!_busy && !ready && _error == null)
          const WatchNote('Moves have not been published yet.'),
        if (position != null) ...[
          Semantics(
            button: true,
            label: _crownReview ? 'Crown controls moves' : 'Crown scrolls page',
            hint: 'Tap to switch Crown control',
            value: position.label,
            increasedValue: _index < _positions.length - 1
                ? _positions[_index + 1].label
                : null,
            decreasedValue: _index > 0 ? _positions[_index - 1].label : null,
            onIncrease: _index < _positions.length - 1
                ? () => _select(_index + 1)
                : null,
            onDecrease: _index > 0 ? () => _select(_index - 1) : null,
            child: GestureDetector(
              onTap: () {
                WatchHaptics.click();
                _toggleCrown();
              },
              child: Center(
                child: SizedBox(
                  width: boardSize,
                  child: WatchBoard(
                    fen: position.fen,
                    lastMove: position.lastMove,
                    flipped: widget.flipped,
                  ),
                ),
              ),
            ),
          ),
          Semantics(
            liveRegion: true,
            child: WatchNote(
              '${position.label} · $_index/${_positions.length - 1}',
            ),
          ),
          Row(
            children: [
              _step(
                'Previous move',
                CupertinoIcons.backward_end_fill,
                _index > 0 ? () => _select(_index - 1) : null,
              ),
              _step(
                'Next move',
                CupertinoIcons.forward_end_fill,
                _index < _positions.length - 1
                    ? () => _select(_index + 1)
                    : null,
              ),
              _step(
                'Last recorded move',
                CupertinoIcons.forward_fill,
                _index < _positions.length - 1
                    ? () => _select(_positions.length - 1)
                    : null,
              ),
            ],
          ),
          WatchRow(
            label: _crownReview ? 'Crown: moves' : 'Crown: scroll',
            showChevron: false,
            onTap: _toggleCrown,
          ),
          const WatchNote('Tap board: moves / scroll'),
        ],
        if (!ready && !_busy)
          WatchRow(
            label: 'Try again',
            icon: CupertinoIcons.refresh,
            onTap: _load,
          ),
      ],
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    WatchAlwaysOn.state.removeListener(_syncCrown);
    unawaited(_crown?.cancel());
    _scroll.dispose();
    super.dispose();
  }
}
