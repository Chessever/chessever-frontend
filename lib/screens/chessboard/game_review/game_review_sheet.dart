import 'dart:async';
import 'dart:math' as math;

import 'package:chessever2/screens/chessboard/game_review/classification_style.dart';
import 'package:chessever2/screens/chessboard/game_review/evaluation_graph_markers.dart';
import 'package:chessever2/screens/chessboard/game_review/game_analysis_report.dart';
import 'package:chessever2/screens/chessboard/game_review/game_review_provider.dart';
import 'package:chessever2/screens/player_profile/player_profile_screen.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/services/fide_photo_service.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/widgets/player_initials_avatar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:motor/motor.dart';

/// Heights for the two-step Game Analysis sheet.
///
/// Step 1 ("peek") is measured, not guessed: the host passes the pixel height
/// that puts the sheet's top edge just under the board's bottom player row, so
/// the board and both name rows stay on screen with the report. Step 2 opens to
/// [full]. Dragging below the peek snaps to [dismissFloor] and closes.
class GameReviewSheetExtents {
  /// Fully-open height, as a fraction of the sheet host.
  static const double full = 0.92;

  /// Peek height used until the board anchor has been measured.
  static const double peekFallback = 0.42;

  /// Clamp for the measured peek. Guards against a layout that would otherwise
  /// leave the sheet unusably short, or tall enough to cover the board it is
  /// supposed to sit under.
  static const double minPeek = 0.22;
  static const double maxPeek = 0.62;

  /// Collapsed floor. Reaching it dismisses the sheet.
  static const double dismissFloor = 0.0;

  /// Breathing room between the bottom player row and the sheet's top edge.
  static const double anchorGap = 6;

  static const double topRadius = 28;

  /// Every sheet transition runs off one physics-based motion, so the entry,
  /// the handle tap, the close button and the drag settle all feel like the
  /// same control rather than a set of hand-tuned easings.
  ///
  /// `smooth` is deliberate over `snappy`/`bouncy`: this sheet parks directly
  /// under the board's player row, and an overshoot would ride up over the row
  /// it is supposed to stop beneath.
  static const CupertinoMotion motion = CupertinoMotion.smooth(
    duration: Duration(milliseconds: 320),
  );

  /// Spring rendered as a [Curve], for the APIs that only accept
  /// duration + curve (`DraggableScrollableController.animateTo`). Paired with
  /// [snapDuration] so the curve is played over the motion's own timeframe.
  static final Curve snapCurve = motion.toCurve;
  static Duration get snapDuration => motion.duration;
}

/// Cadence for report step-arrow hold-to-repeat.
///
/// Matches board bottom-nav long-press scrubbing
/// (`startLongPressForward` / `startLongPressBackward` at 150ms).
const Duration kGameReviewStepRepeatInterval = Duration(milliseconds: 150);

/// Two-step, non-modal Game Analysis sheet.
///
/// Deliberately **not** a `showModalBottomSheet`: a modal route installs a
/// barrier that swallows every touch outside the sheet, which would make the
/// board a picture. Rendered in-tree instead, the area above the sheet has no
/// widget at all, so taps fall straight through to the live board — no scrim,
/// no tint, no dead zone.
///
/// The sheet and the board are two views of one cursor: [activePly] comes from
/// the board, and [onJumpToPly] drives it. Stepping through the graph moves the
/// pieces; moving the pieces slides the graph marker.
class GameReviewSheet extends StatefulWidget {
  const GameReviewSheet({
    super.key,
    required this.controller,
    required this.game,
    required this.activePly,
    required this.onJumpToPly,
    required this.onClose,
    this.peekPixels,
  });

  final MobileGameReviewController controller;
  final GamesTourModel game;

  /// Live board ply (0 = starting position). Pass `-1` while the board sits in
  /// an analysis variation the report does not cover; the marker then holds its
  /// last mainline position instead of jumping.
  final int activePly;

  final ValueChanged<int> onJumpToPly;
  final VoidCallback onClose;

  /// Height in logical pixels that lands the sheet's top edge under the board's
  /// bottom player row. Null falls back to [GameReviewSheetExtents.peekFallback].
  final double? peekPixels;

  @override
  State<GameReviewSheet> createState() => _GameReviewSheetState();
}

class _GameReviewSheetState extends State<GameReviewSheet> {
  final DraggableScrollableController _sheet = DraggableScrollableController();

  bool _dismissed = false;
  bool _revealing = false;
  double _peek = GameReviewSheetExtents.peekFallback;
  double _full = GameReviewSheetExtents.full;

  /// The peek is latched for the life of the open sheet.
  ///
  /// It is measured post-frame from the board's player row, and
  /// `DraggableScrollableSheet` compares [snapSizes] **by reference** — so
  /// letting a late re-measure through would rebuild the list and force-snap an
  /// already-open sheet. Only a change in host height (rotation, resize) is a
  /// real reason to re-derive it.
  double? _latchedPeek;
  double? _latchedForHeight;

  /// Stable list identity: `DraggableScrollableSheet` compares `snapSizes` by
  /// reference and force-snaps the sheet whenever it changes, so a fresh list
  /// per build would fight the user mid-drag.
  List<double>? _snapSizes;
  double? _snapSizesPeek;

  /// Last mainline ply the board reported. Keeps the graph marker parked when
  /// the board wanders into a variation the report has no positions for.
  int _lastMainlinePly = 0;

  @override
  void dispose() {
    _sheet.dispose();
    super.dispose();
  }

  double _resolvePeek(double hostHeight) {
    final pixels = widget.peekPixels;
    if (pixels == null || hostHeight <= 0) {
      return GameReviewSheetExtents.peekFallback;
    }
    return (pixels / hostHeight).clamp(
      GameReviewSheetExtents.minPeek,
      GameReviewSheetExtents.maxPeek,
    );
  }

  List<double> _snapSizesFor(double peek) {
    if (_snapSizesPeek != peek || _snapSizes == null) {
      _snapSizesPeek = peek;
      _snapSizes = <double>[peek];
    }
    return _snapSizes!;
  }

  void _dismiss() {
    if (_dismissed) return;
    _dismissed = true;
    widget.onClose();
  }

  Future<void> _closeFromButton() async {
    if (_dismissed) return;
    HapticFeedback.selectionClick();
    if (_sheet.isAttached) {
      await _sheet.animateTo(
        GameReviewSheetExtents.dismissFloor,
        duration: GameReviewSheetExtents.snapDuration,
        curve: GameReviewSheetExtents.snapCurve,
      );
    }
    if (!mounted) return;
    _dismiss();
  }

  /// Drops back to step 1 so the move that was just selected is actually
  /// visible on the board. No-op when the sheet is already there.
  void _revealBoard() {
    // Scrubbing the graph fires per drag update; without the in-flight guard
    // each one would restart the collapse and the sheet would judder.
    if (_revealing || !_sheet.isAttached) return;
    if (_sheet.size <= _peek + 0.01) return;
    _revealing = true;
    unawaited(
      _sheet
          .animateTo(
            _peek,
            duration: GameReviewSheetExtents.snapDuration,
            curve: GameReviewSheetExtents.snapCurve,
          )
          .whenComplete(() => _revealing = false),
    );
  }

  /// Handle tap toggles the two steps, so reaching the full report never
  /// requires a drag.
  void _toggleStep() {
    if (!_sheet.isAttached) return;
    final midpoint = (_full + _peek) / 2;
    final target = _sheet.size >= midpoint ? _peek : _full;
    HapticFeedback.selectionClick();
    unawaited(
      _sheet.animateTo(
        target,
        duration: GameReviewSheetExtents.snapDuration,
        curve: GameReviewSheetExtents.snapCurve,
      ),
    );
  }

  /// Fully-open height, held clear of the status bar / notch so the rounded
  /// top edge never gets shaved by system chrome.
  double _resolveFull(BuildContext context, double hostHeight) {
    if (hostHeight <= 0) return GameReviewSheetExtents.full;
    final topInset = MediaQuery.paddingOf(context).top + 8;
    final clearOfChrome = (hostHeight - topInset) / hostHeight;
    return math.min(GameReviewSheetExtents.full, clearOfChrome);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.activePly >= 0) _lastMainlinePly = widget.activePly;
    return LayoutBuilder(
      builder: (context, constraints) {
        _full = _resolveFull(context, constraints.maxHeight);
        final resolvedPeek = math.min(
          _resolvePeek(constraints.maxHeight),
          _full,
        );
        if (_latchedPeek == null ||
            _latchedForHeight != constraints.maxHeight) {
          _latchedPeek = resolvedPeek;
          _latchedForHeight = constraints.maxHeight;
        }
        _peek = _latchedPeek!;
        // Back is handled by the board screen's own PopScope (it already owns
        // the route's back button for the game switcher); a second PopScope
        // here would let both handlers fire and pop the screen out from under
        // the sheet.
        // Distance the surface must travel to sit exactly off the bottom edge:
        // the sheet occupies `_peek` of the host, so that is its own height.
        final entryTravel = _peek * constraints.maxHeight;
        return NotificationListener<DraggableScrollableNotification>(
          onNotification: (notification) {
            // Settled on the floor — the user dragged the sheet away.
            if (notification.extent <= notification.minExtent + 0.004) {
              _dismiss();
            }
            return false;
          },
          // Slides the sheet up on first show. `DraggableScrollableSheet` has
          // no entry transition of its own — it renders straight at
          // `initialChildSize` — so without this the report pops into place
          // instead of rising. `from` runs this once, on the first build only.
          //
          // Translating the surface rather than animating the extent keeps the
          // drag controller, the snap sizes and the dismiss notification
          // completely out of the animation.
          child: SingleMotionBuilder(
            motion: GameReviewSheetExtents.motion,
            from: 0,
            value: 1,
            // The wrappers are unconditional: swapping the tree shape when the
            // animation ends would rebuild the sheet element underneath the
            // controller, and `DraggableScrollableController` asserts if it is
            // ever attached to two sheets at once.
            builder: (context, t, child) {
              return IgnorePointer(
                // Nothing is tappable while it is still travelling, so a tap
                // aimed at the board cannot be caught by a sheet sliding under
                // the finger.
                ignoring: t < 0.99,
                child: Transform.translate(
                  offset: Offset(0, (1 - t) * entryTravel),
                  child: child,
                ),
              );
            },
            child: DraggableScrollableSheet(
              controller: _sheet,
              expand: false,
              snap: true,
              snapSizes: _snapSizesFor(_peek),
              initialChildSize: _peek,
              minChildSize: GameReviewSheetExtents.dismissFloor,
              maxChildSize: _full,
              builder: (context, scrollController) {
                return _GameReviewSurface(
                  controller: widget.controller,
                  game: widget.game,
                  activePly: _lastMainlinePly,
                  onJumpToPly: widget.onJumpToPly,
                  onRevealBoard: _revealBoard,
                  onToggleStep: _toggleStep,
                  onClose: _closeFromButton,
                  scrollController: scrollController,
                );
              },
            ),
          ),
        );
      },
    );
  }
}

class GameAnalysisButton extends StatelessWidget {
  const GameAnalysisButton({
    super.key,
    required this.state,
    required this.onPressed,
  });

  final MobileGameReviewState state;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final reportState = state.reportState;
    final running = reportState.isRunning;
    final completed = reportState.status == GameReportStatus.completed;
    final retry =
        reportState.status == GameReportStatus.failed ||
        reportState.status == GameReportStatus.cancelled;
    final percentage = (reportState.progress.clamp(0.0, 1.0) * 100).round();
    final enabled = state.isEligible || running || completed || retry;
    final label =
        !enabled
            ? (state.unavailableMessage ?? 'Game Analysis unavailable')
            : running
            ? 'Game Analysis · $percentage%'
            : retry
            ? 'Retry Game Analysis'
            : completed
            ? 'Show report'
            : 'Generate Report';

    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 10),
      child: Align(
        alignment: Alignment.center,
        child: FractionallySizedBox(
          widthFactor: 0.75,
          child: Semantics(
            button: true,
            enabled: enabled,
            value: running ? '$percentage percent' : null,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: enabled ? onPressed : null,
                borderRadius: BorderRadius.circular(12),
                child: Ink(
                  height: 46,
                  decoration: BoxDecoration(
                    color:
                        enabled
                            ? kBlack3Color
                            : kBlack3Color.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color:
                          completed
                              ? const Color(0xFF28833A)
                              : running
                              ? kPrimaryColor.withValues(alpha: 0.7)
                              : kDividerColor,
                    ),
                  ),
                  child: Stack(
                    children: [
                      if (running)
                        Positioned.fill(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(11),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: AnimatedFractionallySizedBox(
                                duration: const Duration(milliseconds: 220),
                                curve: Curves.easeOut,
                                widthFactor: reportState.progress.clamp(
                                  0.0,
                                  1.0,
                                ),
                                heightFactor: 1,
                                child: ColoredBox(
                                  color: kPrimaryColor.withValues(alpha: 0.16),
                                ),
                              ),
                            ),
                          ),
                        ),
                      Center(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              completed
                                  ? Icons.check_circle_outline_rounded
                                  : retry
                                  ? Icons.refresh_rounded
                                  : Icons.analytics_outlined,
                              size: 19,
                              color:
                                  enabled
                                      ? completed
                                          ? const Color(0xFF45C86E)
                                          : kPrimaryColor
                                      : kLightGreyColor,
                            ),
                            const SizedBox(width: 9),
                            Flexible(
                              child: Text(
                                label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color:
                                      enabled ? kWhiteColor : kLightGreyColor,
                                  fontSize: enabled ? 14 : 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GameReviewSurface extends StatelessWidget {
  const _GameReviewSurface({
    required this.controller,
    required this.game,
    required this.activePly,
    required this.onJumpToPly,
    required this.onRevealBoard,
    required this.onToggleStep,
    required this.onClose,
    required this.scrollController,
  });

  final MobileGameReviewController controller;
  final GamesTourModel game;
  final int activePly;
  final ValueChanged<int> onJumpToPly;
  final VoidCallback onRevealBoard;
  final VoidCallback onToggleStep;
  final VoidCallback onClose;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context) {
    // The sheet floats over a live board, so its lift has to come from one
    // direction (the edge that meets the board) rather than a halo bloomed on
    // every side. Tight offset, small blur, negative spread: a lip of shade
    // under the player row, nothing pooling out at the sides.
    //
    // Surface is one step above the board's own background rather than the
    // same ink — on a page this dark an identical fill would leave the sheet's
    // top edge invisible and the whole panel reading as part of the board.
    const radius = BorderRadius.vertical(
      top: Radius.circular(GameReviewSheetExtents.topRadius),
    );
    return DecoratedBox(
      key: const ValueKey('game-review-full-sheet'),
      decoration: BoxDecoration(
        color: kBlack2Color,
        borderRadius: radius,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.34),
            blurRadius: 16,
            spreadRadius: -6,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: ClipRRect(
        clipBehavior: Clip.antiAlias,
        borderRadius: radius,
        child: Stack(
          children: [
            _surfaceContent(context),
            // A lip of light along the one edge that meets the board, in the
            // sheet's own colour rather than a contrasting outline: the top
            // edge reads as a raised surface catching light, not as a drawn
            // border boxing the panel in.
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 1,
              child: IgnorePointer(
                child: ColoredBox(color: kWhiteColor.withValues(alpha: 0.07)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _surfaceContent(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: AnimatedBuilder(
        // Controller is a StateNotifier; sheet listens via [listenable].
        animation: controller.listenable,
        builder: (context, _) {
          final state = controller.reviewState;
          return CustomScrollView(
            controller: scrollController,
            physics: const ClampingScrollPhysics(),
            slivers: [
              // First scroll child so drag-from-top dismiss works.
              SliverToBoxAdapter(
                child: _SheetHeader(
                  onToggleStep: onToggleStep,
                  onClose: onClose,
                ),
              ),
              SliverPadding(
                // The sheet is bottom-flush to the screen, so pad the
                // scrollable content past the home indicator itself.
                padding: EdgeInsets.fromLTRB(
                  20,
                  4,
                  20,
                  28 + MediaQuery.paddingOf(context).bottom,
                ),
                sliver: SliverToBoxAdapter(child: _body(state.reportState)),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _body(GameReportState state) {
    switch (state.status) {
      case GameReportStatus.running:
        return _ReviewProgress(state: state);
      case GameReportStatus.completed:
        final report = state.report;
        if (report != null) {
          return _CompletedReview(
            report: report,
            game: game,
            activePly: activePly,
            onJumpToPly: onJumpToPly,
            onRevealBoard: onRevealBoard,
          );
        }
        return const _ReviewMessage(
          icon: Icons.error_outline_rounded,
          title: 'Report unavailable',
          body: 'The completed report could not be loaded.',
        );
      case GameReportStatus.failed:
        return Builder(
          builder:
              (context) => _ReviewMessage(
                icon: Icons.error_outline_rounded,
                title: 'Analysis could not finish',
                body: state.message ?? 'Stockfish could not analyze this game.',
                actionLabel: 'Retry',
                onAction: () => controller.retry(context),
              ),
        );
      case GameReportStatus.cancelled:
      case GameReportStatus.idle:
        return Builder(
          builder:
              (context) => _ReviewMessage(
                icon: Icons.analytics_outlined,
                title: 'Game analysis',
                body:
                    state.message ??
                    'Tap Analyze to generate this game review.',
                actionLabel: 'Analyze Game',
                onAction: () => controller.retry(context),
              ),
        );
    }
  }
}

class _SheetHeader extends StatelessWidget {
  const _SheetHeader({required this.onToggleStep, required this.onClose});

  final VoidCallback onToggleStep;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    // Full-width opaque hit target so grabs near the pill still drive the
    // sheet scroll controller (and the drag-to-dismiss) instead of missing the
    // handle. A tap on the same target steps between peek and full.
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onToggleStep,
      child: SizedBox(
        width: double.infinity,
        height: 38,
        child: Stack(
          children: [
            const Center(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: kLightGreyColor,
                  borderRadius: BorderRadius.all(Radius.circular(999)),
                ),
                child: SizedBox(width: 44, height: 5),
              ),
            ),
            Positioned(
              right: 6,
              top: 0,
              bottom: 0,
              child: Center(
                child: IconButton(
                  key: const ValueKey('game-review-close'),
                  onPressed: onClose,
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints.tightFor(
                    width: 38,
                    height: 38,
                  ),
                  iconSize: 20,
                  tooltip: 'Close game analysis',
                  color: kWhiteColor70,
                  icon: const Icon(Icons.close_rounded),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReviewProgress extends StatelessWidget {
  const _ReviewProgress({required this.state});

  final GameReportState state;

  @override
  Widget build(BuildContext context) {
    final progress = state.progress.clamp(0.0, 1.0);
    final analyzedPlies = math.max(0, (state.totalPositions - 1) ~/ 2);
    final totalMoves = (analyzedPlies + 1) ~/ 2;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 56),
      child: Column(
        children: [
          const Icon(Icons.memory_rounded, color: kPrimaryColor, size: 34),
          const SizedBox(height: 16),
          Text(
            state.message ?? 'Analyzing game…',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: kWhiteColor,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 18),
          TweenAnimationBuilder<double>(
            tween: Tween(end: progress),
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            builder: (context, value, _) {
              return Column(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      minHeight: 8,
                      value: value,
                      color: kPrimaryColor,
                      backgroundColor: kBlack3Color,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '${(value * 100).round()}% · $totalMoves moves',
                    style: const TextStyle(color: kWhiteColor70, fontSize: 13),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _ReviewMessage extends StatelessWidget {
  const _ReviewMessage({
    required this.icon,
    required this.title,
    required this.body,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String body;
  final String? actionLabel;
  final Future<void> Function()? onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 44),
      child: Column(
        children: [
          Icon(icon, color: kPrimaryColor, size: 34),
          const SizedBox(height: 14),
          Text(
            title,
            style: const TextStyle(
              color: kWhiteColor,
              fontSize: 17,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            body,
            textAlign: TextAlign.center,
            style: const TextStyle(color: kWhiteColor70, height: 1.4),
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: () => onAction!(),
              icon: const Icon(Icons.refresh_rounded),
              label: Text(actionLabel!),
            ),
          ],
        ],
      ),
    );
  }
}

class _CompletedReview extends StatefulWidget {
  const _CompletedReview({
    required this.report,
    required this.game,
    required this.activePly,
    required this.onJumpToPly,
    required this.onRevealBoard,
  });

  final GameAnalysisReport report;
  final GamesTourModel game;
  final int activePly;
  final ValueChanged<int> onJumpToPly;
  final VoidCallback onRevealBoard;

  @override
  State<_CompletedReview> createState() => _CompletedReviewState();
}

class _CompletedReviewState extends State<_CompletedReview> {
  final Map<String, int> _recapCycle = <String, int>{};

  /// The board owns the cursor. The graph marker is derived from it rather
  /// than held locally, so a move played on the board (arrows, notation, a
  /// piece drag) slides the marker, and a tap on the graph moves the board —
  /// one position, two views of it.
  int get _selectedPly {
    final lastPly = widget.report.positions.length - 1;
    if (lastPly < 0) return 0;
    return widget.activePly.clamp(0, lastPly);
  }

  void _jump(int ply) {
    final lastPly = widget.report.positions.length - 1;
    if (lastPly < 0) return;
    // Every navigation from the report — the graph, the step arrows, a
    // classification count buried down in the recap — drops the sheet back to
    // step 1. Picking a move you then can't see would be a dead end.
    widget.onRevealBoard();
    final next = ply.clamp(0, lastPly);
    if (next == _selectedPly) return;
    widget.onJumpToPly(next);
  }

  void _jumpToClassification(
    GameMoveClassification classification,
    bool white,
  ) {
    final matches = widget.report.moves
        .where(
          (move) =>
              move.isWhite == white && move.classification == classification,
        )
        .toList(growable: false);
    if (matches.isEmpty) return;
    final key = '${classification.name}:$white';
    final current = _recapCycle[key] ?? 0;
    _recapCycle[key] = current + 1;
    _jump(matches[current % matches.length].ply);
  }

  @override
  Widget build(BuildContext context) {
    final hasPositions = widget.report.positions.isNotEmpty;
    return Column(
      children: [
        if (hasPositions) ...[
          _EvaluationGraph(
            report: widget.report,
            activePly: _selectedPly,
            onJumpToPly: _jump,
          ),
          const SizedBox(height: 20),
        ],
        _PlayerSummary(report: widget.report, game: widget.game),
        const SizedBox(height: 24),
        _ClassificationRecap(
          report: widget.report,
          onScoreTap: _jumpToClassification,
        ),
      ],
    );
  }
}

class _PlayerSummary extends StatelessWidget {
  const _PlayerSummary({required this.report, required this.game});

  final GameAnalysisReport report;
  final GamesTourModel game;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _PlayerColumn(player: game.whitePlayer)),
            const SizedBox(width: 18),
            Expanded(child: _PlayerColumn(player: game.blackPlayer)),
          ],
        ),
        const SizedBox(height: 14),
        _SummaryMetricRow(
          label: 'Accuracy',
          left: report.whiteAccuracy.toStringAsFixed(1),
          right: report.blackAccuracy.toStringAsFixed(1),
          suffix: '%',
          cardValues: true,
        ),
        const SizedBox(height: 10),
        _SummaryMetricRow(
          label: 'Game Rating',
          left: report.whiteEstimatedRating?.toString() ?? '—',
          right: report.blackEstimatedRating?.toString() ?? '—',
        ),
      ],
    );
  }
}

/// Shared width of the centre label column in every white-vs-black row.
///
/// One value for the accuracy/rating rows and the classification recap so all
/// the white numbers sit on one axis and all the black numbers on another —
/// and wide enough that the longest label ("Missed Win") is never shaved to an
/// ellipsis.
const double _kMetricLabelColumnWidth = 132;

class _SummaryMetricRow extends StatelessWidget {
  const _SummaryMetricRow({
    required this.label,
    required this.left,
    required this.right,
    this.suffix = '',
    this.cardValues = false,
  });

  final String label;
  final String left;
  final String right;
  final String suffix;
  final bool cardValues;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: _metricValue(left, lightBackground: cardValues)),
        SizedBox(
          width: _kMetricLabelColumnWidth,
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: kWhiteColor70,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Expanded(child: _metricValue(right, lightBackground: false)),
      ],
    );
  }

  Widget _metricValue(String value, {required bool lightBackground}) {
    final content = Text.rich(
      TextSpan(
        children: [
          TextSpan(text: value),
          if (suffix.isNotEmpty)
            TextSpan(
              text: suffix,
              style: TextStyle(
                color:
                    lightBackground ? const Color(0xFF77777A) : kWhiteColor70,
                fontSize: 15,
              ),
            ),
        ],
      ),
      textAlign: TextAlign.center,
      style: TextStyle(
        color: lightBackground ? const Color(0xFF222222) : kWhiteColor,
        fontSize: cardValues ? 24 : 17,
        fontWeight: FontWeight.w800,
      ),
    );
    if (!cardValues) {
      return SizedBox(height: 24, child: Center(child: content));
    }
    return Align(
      alignment: Alignment.center,
      child: FractionallySizedBox(
        widthFactor: 0.82,
        child: Container(
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: lightBackground ? const Color(0xFFD0D0D2) : kBlack3Color,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: lightBackground ? kDividerColor : kLightGreyColor,
            ),
          ),
          child: content,
        ),
      ),
    );
  }
}

class _PlayerColumn extends StatefulWidget {
  const _PlayerColumn({required this.player});

  final PlayerCard player;

  @override
  State<_PlayerColumn> createState() => _PlayerColumnState();
}

class _PlayerColumnState extends State<_PlayerColumn> {
  late Future<String?> _photoFuture;

  @override
  void initState() {
    super.initState();
    _photoFuture = _loadPhoto(widget.player.fideId);
  }

  @override
  void didUpdateWidget(covariant _PlayerColumn oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.player.fideId != widget.player.fideId) {
      _photoFuture = _loadPhoto(widget.player.fideId);
    }
  }

  Future<String?> _loadPhoto(int? fideId) =>
      fideId == null
          ? Future<String?>.value()
          : FidePhotoService.getPhotoUrlOrNull(fideId.toString());

  @override
  Widget build(BuildContext context) {
    final player = widget.player;
    final canOpenProfile = player.name.trim().isNotEmpty;
    return InkWell(
      onTap: canOpenProfile ? () => _openPlayerProfile(context, player) : null,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        child: Column(
          children: [
            FutureBuilder<String?>(
              future: _photoFuture,
              builder:
                  (context, snapshot) => PlayerInitialsAvatar(
                    photoUrl: snapshot.data,
                    initials: _playerInitials(player.name),
                    size: 52,
                    borderRadius: 26,
                  ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 24,
              child: Center(
                // Federation title (GM, IM, FM…) is tinted apart from the name,
                // matching the player profile header.
                child: Text.rich(
                  TextSpan(
                    children: [
                      if (player.title.trim().isNotEmpty)
                        TextSpan(
                          text: '${player.title.trim()} ',
                          style: const TextStyle(color: kLightYellowColor),
                        ),
                      TextSpan(text: _playerLastName(player)),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: kWhiteColor,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Open the tapped player's profile without dismissing the review sheet.
/// Profile is pushed on top of the modal route so system/app back returns to
/// the still-open Game Analysis report (not a bare board).
void _openPlayerProfile(BuildContext context, PlayerCard player) {
  final title = player.title.trim();
  final federation = player.countryCode.trim();
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder:
          (_) => PlayerProfileScreen(
            fideId: player.fideId,
            playerName: player.name,
            title: title.isEmpty ? null : title,
            federation: federation.isEmpty ? null : federation,
            rating: player.rating > 0 ? player.rating : null,
            gamebasePlayerId: player.gamebasePlayerId,
          ),
    ),
  );
}

String _playerLastName(PlayerCard player) {
  final name = player.name.trim();
  final comma = name.indexOf(',');
  return comma > 0
      ? name.substring(0, comma).trim()
      : name.split(RegExp(r'\s+')).last;
}

String _playerInitials(String name) {
  final normalized = name.trim();
  if (normalized.isEmpty) return '';
  final commaParts = normalized.split(',');
  if (commaParts.length > 1 &&
      commaParts.first.trim().isNotEmpty &&
      commaParts[1].trim().isNotEmpty) {
    return '${commaParts.first.trim()[0]}${commaParts[1].trim()[0]}'
        .toUpperCase();
  }
  final words = normalized.split(RegExp(r'\s+'));
  return words.take(2).map((word) => word[0]).join().toUpperCase();
}

class _ClassificationRecap extends StatelessWidget {
  const _ClassificationRecap({required this.report, required this.onScoreTap});

  final GameAnalysisReport report;
  final void Function(GameMoveClassification classification, bool white)
  onScoreTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final classification in GameMoveClassification.values)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: SizedBox(
              height: 30,
              child: Row(
                children: [
                  Expanded(
                    child: _ClassificationScore(
                      classification: classification,
                      count: report.count(classification, white: true),
                      white: true,
                      onTap: () => onScoreTap(classification, true),
                    ),
                  ),
                  SizedBox(
                    width: _kMetricLabelColumnWidth,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.start,
                      children: [
                        _ClassificationIcon(classification: classification),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            classification.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: classificationColor(classification),
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: _ClassificationScore(
                      classification: classification,
                      count: report.count(classification, white: false),
                      white: false,
                      onTap: () => onScoreTap(classification, false),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _ClassificationScore extends StatelessWidget {
  const _ClassificationScore({
    required this.classification,
    required this.count,
    required this.white,
    required this.onTap,
  });

  final GameMoveClassification classification;
  final int count;
  final bool white;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: count > 0,
      enabled: count > 0,
      label:
          '${white ? 'White' : 'Black'} ${classification.label}: $count moves',
      child: InkWell(
        key: ValueKey(
          'game-review-${classification.name}-${white ? 'white' : 'black'}-score',
        ),
        onTap: count > 0 ? onTap : null,
        borderRadius: BorderRadius.circular(8),
        child: Center(
          child: Text(
            '$count',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: classificationColor(classification),
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

class _ClassificationIcon extends StatelessWidget {
  const _ClassificationIcon({required this.classification, this.size = 30});

  final GameMoveClassification classification;
  final double size;

  @override
  Widget build(BuildContext context) {
    // The badge SVG already carries its own coloured disc — render it at size
    // with no container fill or padding.
    return SizedBox(
      width: size,
      height: size,
      child: SvgPicture.asset(
        classificationIconAsset(classification),
        fit: BoxFit.contain,
      ),
    );
  }
}

class _EvaluationGraph extends StatelessWidget {
  const _EvaluationGraph({
    required this.report,
    required this.activePly,
    required this.onJumpToPly,
  });

  final GameAnalysisReport report;
  final int activePly;
  final ValueChanged<int> onJumpToPly;

  int _plyAt(double dx, double width) {
    final maxPly = report.positions.length - 1;
    if (maxPly <= 0 || width <= 0) return 0;
    return ((dx / width).clamp(0.0, 1.0) * maxPly).round();
  }

  /// Classification of the move that produced the position now on the board,
  /// or null at the start position.
  GameMoveClassification? get _activeClassification =>
      activePly > 0 && activePly - 1 < report.moves.length
          ? report.moves[activePly - 1].classification
          : null;

  String _description() {
    final line = report.positions[activePly].bestLine;
    final evaluation =
        line.mate != null
            ? 'M${line.mate}'
            : ((line.centipawns ?? 0) / 100).toStringAsFixed(2);
    // Reads as a move, not as telemetry: the move itself, the engine score,
    // and the verdict. The raw half-move index and the win-percentage restated
    // the graph the reader is already looking at.
    final parts = <String>[];
    if (activePly == 0) {
      parts.add('Start');
    } else {
      final move = report.moves[activePly - 1];
      final moveNumber = (activePly + 1) ~/ 2;
      final prefix = move.isWhite ? '$moveNumber.' : '$moveNumber...';
      parts.add('$prefix ${move.san}');
    }
    parts.add(evaluation);
    final classification = _activeClassification;
    if (classification != null) parts.add(classification.label);
    return parts.join('  ');
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _GraphStepButton(
          key: const ValueKey('game-review-previous-move'),
          icon: Icons.chevron_left_rounded,
          activePly: activePly,
          minPly: 0,
          maxPly: report.positions.length - 1,
          direction: -1,
          onJumpToPly: onJumpToPly,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: SizedBox(
            key: const ValueKey('game-review-evaluation-graph'),
            height: 75,
            child: LayoutBuilder(
              builder: (context, constraints) {
                void jump(Offset position) =>
                    onJumpToPly(_plyAt(position.dx, constraints.maxWidth));
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTapDown: (details) => jump(details.localPosition),
                      onHorizontalDragUpdate:
                          (details) => jump(details.localPosition),
                      child: CustomPaint(
                        painter: _ReviewGraphPainter(
                          positions: report.positions,
                          moves: report.moves,
                          activePly: activePly,
                        ),
                        child: const SizedBox.expand(),
                      ),
                    ),
                    Positioned(
                      top: 5,
                      left: 5,
                      right: 5,
                      child: IgnorePointer(
                        child: Center(
                          child: Container(
                            key: const ValueKey('game-review-graph-info'),
                            constraints: const BoxConstraints(maxWidth: 260),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(
                                0xFF303034,
                              ).withValues(alpha: 0.92),
                              borderRadius: BorderRadius.circular(6),
                              boxShadow: const [
                                BoxShadow(
                                  color: Colors.black38,
                                  blurRadius: 4,
                                  offset: Offset(0, 1),
                                ),
                              ],
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (_activeClassification != null) ...[
                                  _ClassificationIcon(
                                    classification: _activeClassification!,
                                    size: 13,
                                  ),
                                  const SizedBox(width: 5),
                                ],
                                Flexible(
                                  child: Text(
                                    _description(),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      color: kWhiteColor,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
        const SizedBox(width: 8),
        _GraphStepButton(
          key: const ValueKey('game-review-next-move'),
          icon: Icons.chevron_right_rounded,
          activePly: activePly,
          minPly: 0,
          maxPly: report.positions.length - 1,
          direction: 1,
          onJumpToPly: onJumpToPly,
        ),
      ],
    );
  }
}

/// Step arrow beside the eval graph.
///
/// Short tap advances one ply. Hold (long-press) auto-repeats at
/// [kGameReviewStepRepeatInterval], matching board bottom-nav scrubbing
/// (`ChessSvgBottomNavbarWithLongPress` + `startLongPressForward` /
/// `startLongPressBackward`).
class _GraphStepButton extends StatefulWidget {
  const _GraphStepButton({
    super.key,
    required this.icon,
    required this.activePly,
    required this.minPly,
    required this.maxPly,
    required this.direction,
    required this.onJumpToPly,
  });

  final IconData icon;
  final int activePly;
  final int minPly;
  final int maxPly;

  /// `-1` previous, `+1` next.
  final int direction;
  final ValueChanged<int> onJumpToPly;

  bool get enabled {
    final next = activePly + direction;
    return next >= minPly && next <= maxPly;
  }

  @override
  State<_GraphStepButton> createState() => _GraphStepButtonState();
}

class _GraphStepButtonState extends State<_GraphStepButton> {
  Timer? _repeatTimer;

  /// Ply cursor while a hold is active. Same idea as the board provider
  /// reading live state each tick: do not wait for parent rebuilds between
  /// 150ms steps or scrubbing stalls when navigation is async.
  int? _holdPly;

  bool get _canStepFrom {
    final ply = _holdPly ?? widget.activePly;
    final next = ply + widget.direction;
    return next >= widget.minPly && next <= widget.maxPly;
  }

  void _stepOnce() {
    final ply = _holdPly ?? widget.activePly;
    final next = ply + widget.direction;
    if (next < widget.minPly || next > widget.maxPly) return;
    _holdPly = next;
    widget.onJumpToPly(next);
  }

  void _handleTap() {
    if (!widget.enabled) return;
    HapticFeedback.selectionClick();
    _holdPly = null;
    _stepOnce();
    _holdPly = null;
  }

  void _startRepeat() {
    if (!widget.enabled) return;
    // Seed from the board-owned ply at long-press start (bottom-nav style).
    _holdPly = widget.activePly;
    HapticFeedback.mediumImpact();
    _repeatTimer?.cancel();
    // Same cadence as [ChessBoardScreenProviderNew.startLongPressForward]:
    // first step after one interval, then every interval while held.
    _repeatTimer = Timer.periodic(kGameReviewStepRepeatInterval, (_) {
      if (!mounted || !_canStepFrom) {
        if (mounted) HapticFeedback.lightImpact();
        _stopRepeat();
        return;
      }
      HapticFeedback.selectionClick();
      _stepOnce();
    });
  }

  void _stopRepeat() {
    _repeatTimer?.cancel();
    _repeatTimer = null;
    _holdPly = null;
  }

  @override
  void dispose() {
    _stopRepeat();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.enabled;
    final foreground =
        enabled ? kWhiteColor : kLightGreyColor.withValues(alpha: 0.4);
    final background =
        enabled ? kBlack3Color : kBlack3Color.withValues(alpha: 0.45);

    // Mirror [ChessSvgBottomNavbarWithLongPress]: GestureDetector with
    // onTap + onLongPressStart/End/Cancel. Opaque hit target so the sheet's
    // CustomScrollView does not steal the hold.
    return SizedBox.square(
      dimension: 34,
      child: Material(
        color: background,
        shape: const CircleBorder(),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: enabled ? _handleTap : null,
          onLongPressStart: enabled ? (_) => _startRepeat() : null,
          onLongPressEnd: (_) => _stopRepeat(),
          onLongPressCancel: _stopRepeat,
          child: Center(
            child: Icon(widget.icon, size: 25, color: foreground),
          ),
        ),
      ),
    );
  }
}

class _ReviewGraphPainter extends CustomPainter {
  const _ReviewGraphPainter({
    required this.positions,
    required this.moves,
    required this.activePly,
  });

  final List<GameReportPosition> positions;
  final List<GameReportMove> moves;
  final int activePly;

  /// Radius of classification dots on the win% curve (chess.com-style).
  static const double _classificationDotRadius = 3.5;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(14)),
      Paint()..color = kBlack3Color,
    );
    final grid =
        Paint()
          ..color = kDividerColor
          ..strokeWidth = 1;
    canvas.drawLine(
      Offset(0, size.height / 2),
      Offset(size.width, size.height / 2),
      grid,
    );
    for (final fraction in const [1 / 3, 2 / 3]) {
      final x = size.width * fraction;
      for (double y = 0; y < size.height; y += 7) {
        canvas.drawLine(
          Offset(x, y),
          Offset(x, math.min(y + 3, size.height)),
          grid,
        );
      }
    }
    if (positions.isEmpty) return;
    final maxIndex = positions.length - 1;
    final path = Path();
    for (var i = 0; i < positions.length; i++) {
      final x = maxIndex <= 0 ? 0.0 : size.width * i / maxIndex;
      final y =
          size.height -
          gameReportWinPercentage(positions[i].bestLine) / 100 * size.height;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    final fill =
        Path.from(path)
          ..lineTo(size.width, size.height)
          ..lineTo(0, size.height)
          ..close();
    canvas.drawPath(fill, Paint()..color = kWhiteColor.withValues(alpha: 0.08));
    canvas.drawPath(
      path,
      Paint()
        ..color = kWhiteColor70
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    // Classification markers sit on the curve (chess.com-style). Paint before
    // the active scrubber so the white active point stays readable on top.
    final classificationMarkers = buildEvaluationGraphClassificationMarkers(
      moves: moves,
      positions: positions,
    );
    final outline =
        Paint()
          ..color = kBlack3Color.withValues(alpha: 0.55)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1;
    for (final marker in classificationMarkers) {
      final x = maxIndex <= 0 ? 0.0 : size.width * marker.ply / maxIndex;
      final y = size.height - marker.winPercentage / 100 * size.height;
      final center = Offset(x, y);
      canvas.drawCircle(
        center,
        _classificationDotRadius,
        Paint()..color = marker.color,
      );
      canvas.drawCircle(center, _classificationDotRadius, outline);
    }

    final safePly = activePly.clamp(0, maxIndex);
    final markerX = maxIndex <= 0 ? 0.0 : size.width * safePly / maxIndex;
    canvas.drawLine(
      Offset(markerX, 0),
      Offset(markerX, size.height),
      Paint()
        ..color = kPrimaryColor.withValues(alpha: 0.8)
        ..strokeWidth = 2,
    );
    final markerY =
        size.height -
        gameReportWinPercentage(positions[safePly].bestLine) /
            100 *
            size.height;
    canvas.drawCircle(
      Offset(markerX, markerY),
      5,
      Paint()..color = kWhiteColor,
    );
  }

  @override
  bool shouldRepaint(covariant _ReviewGraphPainter oldDelegate) =>
      oldDelegate.activePly != activePly ||
      oldDelegate.positions != positions ||
      oldDelegate.moves != moves;
}
