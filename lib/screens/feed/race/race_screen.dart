import 'dart:async';
import 'dart:math' as math;

import 'package:chessever2/providers/board_settings_provider_new.dart';
import 'package:chessever2/screens/feed/race/race_board.dart';
import 'package:chessever2/screens/feed/race/race_controller.dart';
import 'package:chessever2/screens/feed/race/race_copy.dart';
import 'package:chessever2/screens/feed/race/race_widgets.dart';
import 'package:chessever2/screens/feed/widgets/feed_glyphs.dart';
import 'package:chessever2/screens/feed/widgets/feed_sfx_provider.dart';
import 'package:chessever2/screens/my_space/widgets/pixel_flame.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/widgets/app_snack.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:motor/motor.dart';

/// Lives a Survival run starts with, the room's `SURVIVAL_LIVES`. The race
/// shows them from the first frame; the room's own count replaces this as
/// soon as its first snapshot lands.
const int kRaceSurvivalLives = 3;

/// The lives this run started with: the room's count once it has said so,
/// the mode's until then (a solo race is on screen from the moment it is
/// created, before the room answers). Null in Infinite.
int? raceStartLives(RaceState state) =>
    state.startLives ??
    (state.mode == RaceMode.survival ? kRaceSurvivalLives : null);

/// Asks before ending a run. True when the player chose to end it.
Future<bool> confirmRaceStop(
  BuildContext context, {
  required bool others,
}) async {
  unawaited(HapticFeedbackService.buttonPress());
  final result = await showDialog<bool>(
    context: context,
    barrierColor: context.colors.scrim,
    builder: (dialogContext) {
      final colors = dialogContext.colors;
      return Dialog(
        backgroundColor: colors.surface,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'End this run?',
                style: AppTypography.textLgBold.copyWith(
                  fontSize: 20,
                  height: 26 / 20,
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                others
                    ? 'Your score counts. The others race on.'
                    : 'Your score counts.',
                style: AppTypography.textSmRegular.copyWith(
                  fontSize: 15,
                  height: 21 / 15,
                  color: colors.textSecondary,
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: RaceButton(
                      label: 'Keep racing',
                      onTap: () => Navigator.of(dialogContext).pop(false),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: RaceButton(
                      label: 'End run',
                      tone: RaceButtonTone.primary,
                      onTap: () => Navigator.of(dialogContext).pop(true),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
  return result ?? false;
}

/// The race itself: an outer frame that closes in as the level climbs, the
/// room's clock counting up, level, score, streak, lives, the other racers,
/// and the stream of puzzle boards that moves on after every verdict.
class RaceScreen extends ConsumerStatefulWidget {
  const RaceScreen({super.key});

  /// How long a verdict shows before the stream moves on.
  static const Duration verdictHold = Duration(milliseconds: 320);

  @override
  ConsumerState<RaceScreen> createState() => _RaceScreenState();
}

class _RaceScreenState extends ConsumerState<RaceScreen> {
  late final PageController _pages;
  int _shown = 0;
  Timer? _advance;
  DateTime _holdUntil = DateTime.fromMillisecondsSinceEpoch(0);

  static final Curve _scrollCurve = const CupertinoMotion.snappy(
    duration: Duration(milliseconds: 420),
  ).toCurve;

  @override
  void initState() {
    super.initState();
    _shown = ref.read(raceControllerProvider).puzzle?.index ?? 0;
    _pages = PageController(initialPage: _shown);
  }

  @override
  void dispose() {
    _advance?.cancel();
    _pages.dispose();
    super.dispose();
  }

  void _onState(RaceState? previous, RaceState next) {
    final move = next.lastMove;
    if (move != null && move.seq != previous?.lastMove?.seq && move.complete) {
      _holdUntil = DateTime.now().add(RaceScreen.verdictHold);
    }
    final target = next.puzzle?.index;
    if (target != null && target > _shown) _scheduleAdvance(target);
  }

  /// Moves the stream to [target] once the verdict has had its moment.
  void _scheduleAdvance(int target) {
    _advance?.cancel();
    final wait = _holdUntil.difference(DateTime.now());
    _advance = Timer(wait.isNegative ? Duration.zero : wait, () {
      _advance = null;
      if (!mounted) return;
      setState(() => _shown = target);
      if (!_pages.hasClients) return;
      if (MediaQuery.disableAnimationsOf(context)) {
        _pages.jumpToPage(target);
      } else {
        unawaited(
          _pages.animateToPage(
            target,
            duration: const Duration(milliseconds: 420),
            curve: _scrollCurve,
          ),
        );
      }
    });
  }

  Future<void> _stop() async {
    final state = ref.read(raceControllerProvider);
    final started =
        state.phase == RacePhase.running ||
        (state.phase == RacePhase.countdown && state.multiplayer);
    if (!started) {
      unawaited(HapticFeedbackService.navigation());
      ref.read(raceControllerProvider.notifier).stop();
      return;
    }
    final others = state.multiplayer && state.opponents.isNotEmpty;
    final end = await confirmRaceStop(context, others: others);
    if (!mounted || !end) return;
    ref.read(raceControllerProvider.notifier).stop();
  }

  static const String _boardSoundOffHint = 'Sound is off in board settings';

  /// The Feed's speaker, here too. With the board's Sound setting off every
  /// race sound is silent whatever the speaker says, so the tap offers to
  /// turn that setting on instead, exactly as the Feed does.
  void _toggleSound({required bool boardSoundOn}) {
    unawaited(HapticFeedbackService.toggle());
    if (!boardSoundOn) {
      showAppSnack(
        context,
        _boardSoundOffHint,
        actionLabel: 'Turn on',
        onAction: _turnOnBoardSound,
      );
      return;
    }
    final feed = ref.read(feedSfxProvider);
    setState(() => feed.muted = !feed.muted);
    _followSpeaker();
  }

  Future<void> _turnOnBoardSound() async {
    if (!mounted) return;
    setState(() => ref.read(feedSfxProvider).muted = false);
    await ref.read(boardSettingsProviderNew.notifier).toggleSound(true);
    if (!mounted) return;
    _followSpeaker();
  }

  /// The race re-reads the Feed's speaker on a warm-up: a mute breathes the
  /// tension bed out at once, an unmute brings it back at the current
  /// tension and loads the race set if it never was.
  void _followSpeaker() => ref.read(raceDepsProvider).audio.warmUp();

  @override
  Widget build(BuildContext context) {
    ref.listen<RaceState>(raceControllerProvider, _onState);
    final state = ref.watch(raceControllerProvider);
    // What the speaker shows is what the player will hear: the board's
    // Sound setting silences the race too. Until the setting loads, the last
    // value the Feed was told about stands in.
    final feedSfx = ref.read(feedSfxProvider);
    final boardSoundOn =
        ref.watch(
          boardSettingsProviderNew.select(
            (settings) => settings.valueOrNull?.soundEnabled,
          ),
        ) ??
        feedSfx.boardSoundEnabled;
    final colors = context.colors;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final level = state.displayLevel;
    final lastLife = state.livesLeft == 1;
    final baseTone = lastLife
        ? colors.danger.withValues(alpha: 0.85)
        : raceFrameTone(colors, level, paper: context.isLightTheme);
    final wrongSeq = state.lastMove != null && !state.lastMove!.correct
        ? state.lastMove!.seq
        : 0;

    final reach = raceFrameReach(level);

    // The level-up accent and the miss flash are keyed by their own event,
    // so each plays once from full to nothing and neither replays the other.
    final accentLayer = SingleMotionBuilder(
      key: ValueKey('accent-${state.levelUpSeq}'),
      from: state.levelUpSeq == 0 ? 0 : 1,
      value: 0,
      motion: const CupertinoMotion.smooth(
        duration: Duration(milliseconds: 700),
        snapToEnd: true,
      ),
      builder: (context, accent, _) {
        final a = reduceMotion ? 0.0 : accent.clamp(0.0, 1.0);
        return CustomPaint(
          painter: RaceFramePainter(
            reach: math.min(1, reach + a * 0.06),
            color: Color.lerp(baseTone, colors.titleAccent, a)!,
          ),
        );
      },
    );
    final flashLayer = SingleMotionBuilder(
      key: ValueKey('flash-$wrongSeq'),
      from: wrongSeq == 0 ? 0 : 1,
      value: 0,
      motion: const CupertinoMotion.smooth(
        duration: Duration(milliseconds: 360),
        snapToEnd: true,
      ),
      builder: (context, flash, _) {
        final f = flash.clamp(0.0, 1.0);
        if (f <= 0.004) return const SizedBox.expand();
        return CustomPaint(
          painter: RaceFramePainter(
            // A miss closes the whole frame for a beat.
            reach: 1,
            color: colors.danger.withValues(alpha: 0.9 * f),
            strokeWidth: 3,
          ),
        );
      },
    );
    final frameLayer = Stack(
      fit: StackFit.expand,
      children: [accentLayer, flashLayer],
    );

    // The frame stays clear of the home indicator.
    final insets = EdgeInsets.fromLTRB(
      8,
      4,
      8,
      math.max(8, MediaQuery.paddingOf(context).bottom),
    );
    return Stack(
      children: [
        Positioned.fill(
          child: Padding(
            padding: insets,
            child: IgnorePointer(child: RepaintBoundary(child: frameLayer)),
          ),
        ),
        Padding(
          padding: insets,
          child: Column(
            children: [
              _TopBar(
                state: state,
                onStop: _stop,
                soundOn: boardSoundOn && !feedSfx.muted,
                soundHint: boardSoundOn ? null : _boardSoundOffHint,
                onToggleSound: () => _toggleSound(boardSoundOn: boardSoundOn),
                now: ref.read(raceDepsProvider).now,
              ),
              if (state.multiplayer && state.opponents.isNotEmpty)
                _Opponents(state: state),
              Expanded(child: _stream(state)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _stream(RaceState state) {
    final puzzle = state.puzzle;
    final controller = ref.read(raceControllerProvider.notifier);
    final canMove =
        state.phase == RacePhase.running &&
        state.link == RaceLinkStatus.open &&
        !state.awaitingVerdict;

    Widget body;
    if (puzzle == null) {
      body = const SizedBox.expand();
    } else {
      final count = puzzle.index + 1;
      final byIndex = {for (final r in state.records) r.puzzle.index: r};
      body = LayoutBuilder(
        builder: (context, constraints) {
          final boardSize = math
              .min(
                constraints.maxWidth - 24,
                constraints.maxHeight -
                    RacePuzzleBoard.statusHeight -
                    RacePuzzleBoard.statusGap -
                    24,
              )
              .clamp(96.0, 720.0)
              .floorToDouble();
          return PageView.builder(
            key: const ValueKey('race_stream'),
            controller: _pages,
            scrollDirection: Axis.vertical,
            // The race moves the stream; a finger never does, so a drag on
            // the board is always a piece drag.
            physics: const NeverScrollableScrollPhysics(),
            allowImplicitScrolling: true,
            itemCount: count,
            itemBuilder: (context, i) {
              final record = byIndex[i];
              final RacePuzzle? shown = i == puzzle.index
                  ? puzzle
                  : record?.puzzle;
              if (shown == null) {
                return const SizedBox.expand();
              }
              final move = state.lastMove?.index == i ? state.lastMove : null;
              final reject = state.lastReject?.index == i
                  ? state.lastReject
                  : null;
              // Scales down only where a very short screen could not fit the
              // board and its status line.
              return Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: RacePuzzleBoard(
                    key: ValueKey('race_board_$i'),
                    puzzle: shown,
                    record: i == puzzle.index ? null : record,
                    isCurrent: i == _shown,
                    canMove: canMove && i == puzzle.index,
                    moveEvent: move,
                    rejectEvent: reject,
                    onMove: controller.submitMove,
                    boardSize: boardSize,
                  ),
                ),
              );
            },
          );
        },
      );
    }

    final showCountdown =
        state.phase == RacePhase.countdown ||
        (!state.multiplayer &&
            puzzle == null &&
            state.phase != RacePhase.running);
    return Stack(
      children: [
        Positioned.fill(child: body),
        if (showCountdown)
          Positioned.fill(
            child: _Countdown(
              state: state,
              now: ref.read(raceDepsProvider).now,
            ),
          ),
      ],
    );
  }
}

/// End and the speaker, the mode (or the connection's state) and the lives;
/// then the clock with the score; then the level with the streak.
class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.state,
    required this.onStop,
    required this.soundOn,
    required this.onToggleSound,
    required this.now,
    this.soundHint,
  });

  final RaceState state;
  final VoidCallback onStop;

  /// Whether the race will actually make a sound: the Feed's speaker is on
  /// AND the board's Sound setting is on.
  final bool soundOn;
  final VoidCallback onToggleSound;

  /// Why the speaker reads off when its own mute is not the reason.
  final String? soundHint;
  final int Function() now;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final reconnecting = state.link == RaceLinkStatus.reconnecting;
    final lives = raceStartLives(state);
    final level = state.displayLevel;
    final label = AppTypography.textSmMedium.copyWith(
      fontSize: 14,
      height: 18 / 14,
      color: colors.textSecondary,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    // The rating lives once, under the board beside the puzzle's number.
    final levelLine = 'Level $level';
    final quiet = raceQuietInk(colors);
    final status = reconnecting
        ? (state.you == null ? 'Connecting' : 'Reconnecting')
        : raceModeName(state.mode);
    final statusStyle = label.copyWith(
      color: reconnecting ? colors.titleAccent : quiet,
    );
    // End plus the speaker on the left, the lives' 88 on the right: the
    // status is nudged back to the bar's true centre whenever it has room.
    final leftWidth = RaceBackControl.widthFor(context, _endLabel) + 44;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        children: [
          SizedBox(
            height: 44,
            child: Row(
              children: [
                RaceBackControl(
                  key: const ValueKey('race_stop'),
                  glyph: RaceGlyphs.close,
                  label: _endLabel,
                  semanticsLabel: 'End the run',
                  onTap: onStop,
                ),
                // The Feed header's speaker, the same bare glyph: the
                // tension bed can be silenced without ending the run.
                RaceIconButton(
                  key: const ValueKey('race_sound'),
                  glyph: soundOn ? FeedGlyphs.soundOn : FeedGlyphs.soundOff,
                  label: 'Race sounds',
                  toggled: soundOn,
                  hint: soundHint,
                  onTap: onToggleSound,
                ),
                Expanded(
                  child: _CentredStatus(
                    text: status,
                    style: statusStyle,
                    lean: leftWidth - _livesWidth,
                  ),
                ),
                SizedBox(
                  width: _livesWidth,
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: lives == null
                        ? Text('No limit', style: label)
                        : RaceHearts(
                            total: lives,
                            left: math.max(0, lives - state.mistakes),
                          ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 2),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: _RaceClock(state: state, pulse: level > 10, now: now),
              ),
              const SizedBox(width: 12),
              Semantics(
                label: '${state.score} solved',
                excludeSemantics: true,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${state.score}',
                      key: const ValueKey('race_score'),
                      style: AppTypography.displaySmBold.copyWith(
                        fontSize: 34,
                        height: 40 / 34,
                        color: colors.textPrimary,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    Text(
                      'solved',
                      style: label.copyWith(
                        fontSize: 12,
                        height: 14 / 12,
                        color: quiet,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          SizedBox(
            height: 24,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    levelLine,
                    key: const ValueKey('race_level'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: label.copyWith(
                      color: colors.textPrimaryMuted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (state.streak > 0) ...[
                  if (state.streak >= 3) ...[
                    // Never below the flame's first heat: its cooler outer
                    // tone falls under 3:1 on paper.
                    PixelFlame(streak: math.max(5, state.streak), size: 16),
                    const SizedBox(width: 6),
                  ],
                  Text('${state.streak} in a row', style: label),
                ],
              ],
            ),
          ),
          const SizedBox(height: 6),
        ],
      ),
    );
  }
}

const String _endLabel = 'End';
const double _livesWidth = 88;

/// One line centred on the whole bar rather than on the gap it sits in:
/// [lean] is how much wider the bar's left side is than its right, and the
/// text shifts back by it as far as its own slack allows. Too long for the
/// gap, it scales down instead of being cut.
class _CentredStatus extends StatelessWidget {
  const _CentredStatus({
    required this.text,
    required this.style,
    required this.lean,
  });

  final String text;
  final TextStyle style;
  final double lean;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final painter = TextPainter(
          text: TextSpan(
            text: text,
            style: DefaultTextStyle.of(context).style.merge(style),
          ),
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
          maxLines: 1,
        )..layout();
        final width = painter.width.ceilToDouble();
        painter.dispose();
        final slack = math.max(0.0, constraints.maxWidth - width);
        final shift = lean.clamp(-slack, slack);
        return Padding(
          padding: EdgeInsets.only(
            left: shift < 0 ? -shift : 0,
            right: shift > 0 ? shift : 0,
          ),
          child: Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                text,
                key: const ValueKey('race_status'),
                maxLines: 1,
                softWrap: false,
                style: style,
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The big count-up clock. It is the room's clock: the start and the offset
/// come from the room, and this only redraws it between messages. Past
/// level 10 its ink breathes slowly toward the accent tone.
class _RaceClock extends StatefulWidget {
  const _RaceClock({
    required this.state,
    required this.pulse,
    required this.now,
  });

  final RaceState state;
  final bool pulse;

  /// The device clock the offset was measured against.
  final int Function() now;

  @override
  State<_RaceClock> createState() => _RaceClockState();
}

class _RaceClockState extends State<_RaceClock>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_onTick);
  int _tenths = -1;
  double _breath = 0;

  bool get _ticking =>
      widget.state.phase == RacePhase.running &&
      widget.state.finalElapsedMs == null &&
      widget.state.startedAt != null;

  @override
  void initState() {
    super.initState();
    _syncTicker();
  }

  @override
  void didUpdateWidget(covariant _RaceClock oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncTicker();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _syncTicker() {
    final run = _ticking;
    if (run && !_ticker.isActive) {
      _ticker.start();
    } else if (!run && _ticker.isActive) {
      _ticker.stop();
    }
  }

  void _onTick(Duration elapsed) {
    final ms = widget.state.elapsedAt(widget.now());
    final tenths = ms ~/ 100;
    final breath = widget.pulse
        ? (math.sin(elapsed.inMilliseconds / 1800 * 2 * math.pi) + 1) / 2
        : 0.0;
    if (tenths != _tenths || (breath - _breath).abs() > 0.02) {
      setState(() {
        _tenths = tenths;
        _breath = breath;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final ms = widget.state.elapsedAt(widget.now());
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final breath = widget.pulse && !reduceMotion && _ticking ? _breath : 0.0;
    final ink = Color.lerp(
      colors.textPrimary,
      colors.titleAccent,
      breath * 0.7,
    )!;
    final text = formatRaceClock(ms);
    return Semantics(
      label: 'Race clock $text',
      excludeSemantics: true,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Text(
          text,
          key: const ValueKey('race_clock'),
          maxLines: 1,
          style: AppTypography.displayMdBold.copyWith(
            fontSize: 46,
            height: 54 / 46,
            letterSpacing: 0.5,
            color: ink,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ),
    );
  }
}

/// "1st", "2nd", "3rd", "4th", "11th", "22nd".
String raceOrdinal(int n) {
  final hundreds = n % 100;
  if (hundreds >= 11 && hundreds <= 13) return '${n}th';
  return switch (n % 10) {
    1 => '${n}st',
    2 => '${n}nd',
    3 => '${n}rd',
    _ => '${n}th',
  };
}

/// Everyone else in the room, live: the leaders that fit whole (name, score,
/// lives or "done"), a count of the rest, and this player's own place.
///
/// The player is solving on the board and never scrolls this, so it does not
/// scroll: an entry that would not fit whole folds into the count instead of
/// being sliced at an edge, and the strip keeps the top bar's 12pt gutter so
/// nothing is drawn across the frame.
class _Opponents extends StatelessWidget {
  const _Opponents({required this.state});

  final RaceState state;

  static const double _nameMax = 110;
  static const double _innerGap = 6;
  static const double _entryGap = 18;
  static const double _countGap = 12;
  static const double _placeGap = 16;
  static const double _heartSize = 9;
  static const double _heartGap = 2;

  /// Ahead of this player: more solved, or as many with fewer misses.
  bool _ahead(RacePlayer p) =>
      p.score > state.score ||
      (p.score == state.score && p.mistakes < state.mistakes);

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final others = [...state.opponents]
      ..sort((a, b) {
        final byScore = b.score.compareTo(a.score);
        return byScore != 0 ? byScore : a.mistakes.compareTo(b.mistakes);
      });
    final lives = raceStartLives(state);
    final styles = _OpponentStyles(
      name: AppTypography.textSmMedium.copyWith(
        fontSize: 13,
        height: 18 / 13,
        color: colors.textSecondary,
      ),
      score: AppTypography.textSmMedium.copyWith(
        fontSize: 13,
        height: 18 / 13,
        fontWeight: FontWeight.w700,
        color: colors.textPrimary,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
      quiet: AppTypography.textSmMedium.copyWith(
        fontSize: 13,
        height: 18 / 13,
        color: raceQuietInk(colors),
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
      dimScore: AppTypography.textSmMedium.copyWith(
        fontSize: 13,
        height: 18 / 13,
        fontWeight: FontWeight.w600,
        color: colors.textSecondary,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );

    // Before anyone has solved or missed, everyone shares first: no place
    // to report yet.
    final underway =
        state.score > 0 ||
        state.mistakes > 0 ||
        others.any((p) => p.score > 0 || p.mistakes > 0);
    final place = raceOrdinal(1 + others.where(_ahead).length);
    final field = others.length + 1;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: SizedBox(
        key: const ValueKey('race_opponents'),
        height: 30,
        child: Row(
          children: [
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) => _leaders(
                  context,
                  maxWidth: constraints.maxWidth,
                  others: others,
                  lives: lives,
                  styles: styles,
                ),
              ),
            ),
            if (underway) ...[
              const SizedBox(width: _placeGap),
              Semantics(
                label: 'You are $place of $field',
                excludeSemantics: true,
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(text: place, style: styles.score),
                      TextSpan(text: ' of $field', style: styles.quiet),
                    ],
                  ),
                  key: const ValueKey('race_place'),
                  maxLines: 1,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// As many leaders as fit whole in [maxWidth], then "+N" for the rest.
  Widget _leaders(
    BuildContext context, {
    required double maxWidth,
    required List<RacePlayer> others,
    required int? lives,
    required _OpponentStyles styles,
  }) {
    final base = DefaultTextStyle.of(context).style;
    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);
    double measure(String text, TextStyle style) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: base.merge(style)),
        textDirection: direction,
        textScaler: scaler,
        maxLines: 1,
      )..layout();
      final width = painter.width.ceilToDouble();
      painter.dispose();
      return width;
    }

    double entryWidth(RacePlayer p) {
      var width =
          math.min(_nameMax, measure(p.name, styles.name)) +
          _innerGap +
          measure('${p.score}', styles.score);
      if (p.finished) {
        width += _innerGap + measure('done', styles.quiet);
      } else if (lives != null && lives > 0) {
        width += _innerGap + lives * _heartSize + (lives - 1) * _heartGap;
      }
      return width;
    }

    var shown = 0;
    var used = 0.0;
    for (var i = 0; i < others.length; i++) {
      final next = used + (i > 0 ? _entryGap : 0) + entryWidth(others[i]);
      final rest = others.length - (i + 1);
      final count = rest > 0
          ? _countGap + measure('+$rest', styles.quiet)
          : 0.0;
      if (next + count > maxWidth) break;
      used = next;
      shown = i + 1;
    }
    // A leader too wide to fit even alone still shows, its name shortened.
    if (shown == 0 && others.isNotEmpty) shown = 1;
    final hidden = others.length - shown;

    return Row(
      children: [
        for (var i = 0; i < shown; i++) ...[
          if (i > 0) const SizedBox(width: _entryGap),
          // The last one shown gives way by a letter rather than overflow
          // should a measurement round against it.
          if (i == shown - 1)
            Flexible(
              child: _entry(others[i], lives, styles, flexibleName: true),
            )
          else
            _entry(others[i], lives, styles, flexibleName: false),
        ],
        if (hidden > 0) ...[
          if (shown > 0) const SizedBox(width: _countGap),
          Semantics(
            label: '$hidden more racing',
            excludeSemantics: true,
            child: Text(
              '+$hidden',
              key: const ValueKey('race_opponents_more'),
              maxLines: 1,
              style: styles.quiet,
            ),
          ),
        ],
      ],
    );
  }

  Widget _entry(
    RacePlayer p,
    int? lives,
    _OpponentStyles styles, {
    required bool flexibleName,
  }) {
    // Away or done reads quieter by tone, never by fading: every ink here
    // still clears AA on the page.
    final dim = !p.connected || p.finished;
    final left = lives == null ? null : math.max(0, lives - p.mistakes);
    final name = ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: _nameMax),
      child: Text(
        p.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: dim ? styles.quiet : styles.name,
      ),
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (flexibleName) Flexible(child: name) else name,
        const SizedBox(width: _innerGap),
        Text(
          '${p.score}',
          maxLines: 1,
          style: dim ? styles.dimScore : styles.score,
        ),
        if (p.finished) ...[
          const SizedBox(width: _innerGap),
          Text('done', maxLines: 1, style: styles.quiet),
        ] else if (left != null && lives != null && lives > 0) ...[
          const SizedBox(width: _innerGap),
          RaceHearts(total: lives, left: left, size: _heartSize, gap: _heartGap),
        ],
      ],
    );
  }
}

/// The opponents strip's inks: a name, a score, the quiet ones ("done",
/// "+3", "of 6"), and a racer who is away or done.
class _OpponentStyles {
  const _OpponentStyles({
    required this.name,
    required this.score,
    required this.quiet,
    required this.dimScore,
  });

  final TextStyle name;
  final TextStyle score;
  final TextStyle quiet;
  final TextStyle dimScore;
}

/// 3, 2, 1 over the stream, from the room's countdown (or the solo one).
/// Before a solo room is ready it says so instead.
class _Countdown extends StatefulWidget {
  const _Countdown({required this.state, required this.now});

  final RaceState state;
  final int Function() now;

  @override
  State<_Countdown> createState() => _CountdownState();
}

class _CountdownState extends State<_Countdown>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_onTick)..start();
  int _beat = -1;

  int? _beatNow() {
    final left = widget.state.countdownLeftAt(widget.now());
    if (left == null) return null;
    return (left / 1000).ceil();
  }

  void _onTick(Duration _) {
    final beat = _beatNow() ?? -1;
    if (beat != _beat) setState(() => _beat = beat);
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final beat = _beatNow();
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (beat == null) {
      return Center(
        child: Text(
          'Setting up your race',
          style: AppTypography.textMdMedium.copyWith(
            fontSize: 16,
            height: 22 / 16,
            color: colors.textSecondary,
          ),
        ),
      );
    }
    final text = beat > 0 ? '$beat' : 'Go';
    final number = Text(
      text,
      key: const ValueKey('race_countdown'),
      style: AppTypography.displayXlBold.copyWith(
        fontSize: 112,
        height: 1.1,
        color: colors.textPrimary,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
    return Semantics(
      liveRegion: true,
      label: beat > 0 ? 'Starting in $beat' : 'Go',
      excludeSemantics: true,
      child: Center(
        child: reduceMotion
            ? number
            : SingleMotionBuilder(
                key: ValueKey('beat-$text'),
                from: 1.18,
                value: 1,
                motion: const CupertinoMotion.snappy(
                  duration: Duration(milliseconds: 380),
                ),
                builder: (context, scale, child) =>
                    Transform.scale(scale: scale, child: child),
                child: number,
              ),
      ),
    );
  }
}
