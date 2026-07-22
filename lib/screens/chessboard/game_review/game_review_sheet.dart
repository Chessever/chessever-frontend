import 'dart:math' as math;

import 'package:chessever2/screens/chessboard/game_review/game_analysis_report.dart';
import 'package:chessever2/screens/chessboard/game_review/game_review_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/services/fide_photo_service.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/widgets/player_initials_avatar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Single open-height Game Analysis review sheet.
///
/// Opens already at [height] with rounded top corners, sitting under the safe
/// area so it never collides with the notch. Drag-down dismiss is coordinated
/// through [DraggableScrollableSheet] (see [minHeight]) rather than multi-step
/// snap points.
class GameReviewSheetExtents {
  /// Open / max sheet height (fraction of the modal host after safe area).
  static const double height = 0.90;

  /// How far the sheet may shrink while dragging before it closes.
  /// Must be below [height] so a downward drag from the handle (or from the
  /// top of the scroll view) can collapse and dismiss instead of only
  /// scrolling content.
  static const double minHeight = 0.45;

  static const double topRadius = 28;
}

Future<void> showMobileGameReviewSheet({
  required BuildContext context,
  required MobileGameReviewController controller,
  required GamesTourModel game,
  required int activePly,
  required ValueChanged<int> onJumpToPly,
  Future<void> Function(bool visible)? onVisibilityChanged,
}) async {
  controller.reveal();
  await onVisibilityChanged?.call(true);
  if (!context.mounted) {
    await onVisibilityChanged?.call(false);
    return;
  }
  try {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      enableDrag: true,
      isDismissible: true,
      backgroundColor: Colors.transparent,
      // Soft dim so the sheet reads as an overlay over the live board.
      barrierColor: Colors.black.withValues(alpha: 0.28),
      builder:
          (context) => _GameReviewSheet(
            controller: controller,
            game: game,
            activePly: activePly,
            onJumpToPly: onJumpToPly,
          ),
    );
  } finally {
    await onVisibilityChanged?.call(false);
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
            : 'Game Analysis';

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

class _GameReviewSheet extends StatelessWidget {
  const _GameReviewSheet({
    required this.controller,
    required this.game,
    required this.activePly,
    required this.onJumpToPly,
  });

  final MobileGameReviewController controller;
  final GamesTourModel game;
  final int activePly;
  final ValueChanged<int> onJumpToPly;

  @override
  Widget build(BuildContext context) {
    // DraggableScrollableSheet owns the primary scroll controller. Without it,
    // the CustomScrollView eats every vertical drag (including on the handle)
    // and the modal never dismisses. At scroll offset 0 a downward drag
    // shrinks the sheet and closes it at [minHeight].
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: GameReviewSheetExtents.height,
      minChildSize: GameReviewSheetExtents.minHeight,
      maxChildSize: GameReviewSheetExtents.height,
      shouldCloseOnMinExtent: true,
      builder: (context, scrollController) {
        return Material(
          key: const ValueKey('game-review-full-sheet'),
          color: kBackgroundColor,
          elevation: 12,
          shadowColor: Colors.black.withValues(alpha: 0.45),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(GameReviewSheetExtents.topRadius),
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: AnimatedBuilder(
            animation: controller,
            builder: (context, _) {
              final state = controller.state;
              return CustomScrollView(
                controller: scrollController,
                physics: const ClampingScrollPhysics(),
                slivers: [
                  // First scroll child so drag-from-top dismiss works.
                  const SliverToBoxAdapter(child: _SheetDragHandle()),
                  SliverPadding(
                    // useSafeArea keeps the top/sides clear but leaves the
                    // bottom flush to the screen edge, so pad the scrollable
                    // content past the home indicator itself.
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
      },
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
          );
        }
        return const _ReviewMessage(
          icon: Icons.error_outline_rounded,
          title: 'Report unavailable',
          body: 'The completed report could not be loaded.',
        );
      case GameReportStatus.failed:
        return _ReviewMessage(
          icon: Icons.error_outline_rounded,
          title: 'Analysis could not finish',
          body: state.message ?? 'Stockfish could not analyze this game.',
          actionLabel: 'Retry',
          onAction: controller.retry,
        );
      case GameReportStatus.cancelled:
      case GameReportStatus.idle:
        return _ReviewMessage(
          icon: Icons.analytics_outlined,
          title: 'Game analysis',
          body: state.message ?? 'Stockfish is preparing this game review.',
          actionLabel: 'Analyze Game',
          onAction: controller.retry,
        );
    }
  }
}

class _SheetDragHandle extends StatelessWidget {
  const _SheetDragHandle();

  @override
  Widget build(BuildContext context) {
    // Full-width opaque hit target so grabs near the pill still drive the
    // sheet scroll controller (and dismiss) instead of missing the handle.
    return const SizedBox(
      width: double.infinity,
      height: 36,
      child: Center(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: kLightGreyColor,
            borderRadius: BorderRadius.all(Radius.circular(999)),
          ),
          child: SizedBox(width: 44, height: 5),
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
  });

  final GameAnalysisReport report;
  final GamesTourModel game;
  final int activePly;
  final ValueChanged<int> onJumpToPly;

  @override
  State<_CompletedReview> createState() => _CompletedReviewState();
}

class _CompletedReviewState extends State<_CompletedReview> {
  late int _selectedPly;
  final Map<String, int> _recapCycle = <String, int>{};

  @override
  void initState() {
    super.initState();
    _selectedPly = widget.activePly.clamp(
      0,
      widget.report.positions.length - 1,
    );
  }

  void _jump(int ply) {
    final next = ply.clamp(0, widget.report.positions.length - 1);
    if (next == _selectedPly) return;
    setState(() => _selectedPly = next);
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
    return Column(
      children: [
        _EvaluationGraph(
          report: widget.report,
          activePly: _selectedPly,
          onJumpToPly: _jump,
        ),
        const SizedBox(height: 20),
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
          width: 88,
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
    return Column(
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
            child: Text(
              _playerTitleAndLastName(player),
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
    );
  }
}

String _playerTitleAndLastName(PlayerCard player) {
  final name = player.name.trim();
  final comma = name.indexOf(',');
  final lastName =
      comma > 0
          ? name.substring(0, comma).trim()
          : name.split(RegExp(r'\s+')).last;
  return [
    if (player.title.trim().isNotEmpty) player.title.trim(),
    lastName,
  ].join(' ');
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
                  Expanded(
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
                            textAlign: TextAlign.center,
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
  const _ClassificationIcon({required this.classification});

  final GameMoveClassification classification;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 30,
      height: 30,
      padding: const EdgeInsets.all(7),
      decoration: BoxDecoration(
        color: classificationColor(classification),
        shape: BoxShape.circle,
      ),
      child: SvgPicture.asset(classificationIconAsset(classification)),
    );
  }
}

String classificationIconAsset(GameMoveClassification classification) =>
    switch (classification) {
      GameMoveClassification.brilliant => 'assets/svgs/brilliant.svg',
      GameMoveClassification.goodMove => 'assets/svgs/good_move.svg',
      GameMoveClassification.bestMove => 'assets/svgs/best_move.svg',
      GameMoveClassification.missedWin => 'assets/svgs/missed_win.svg',
      GameMoveClassification.inaccuracy => 'assets/svgs/inaccuracy.svg',
      GameMoveClassification.mistake => 'assets/svgs/mistake.svg',
      GameMoveClassification.blunder => 'assets/svgs/blunder.svg',
    };

Color classificationColor(GameMoveClassification classification) =>
    switch (classification) {
      GameMoveClassification.brilliant => const Color(0xFF177A68),
      GameMoveClassification.goodMove => const Color(0xFF177A68),
      GameMoveClassification.bestMove => const Color(0xFF28833A),
      GameMoveClassification.missedWin => const Color(0xFF8F1E1E),
      GameMoveClassification.inaccuracy => const Color(0xFFFABE46),
      GameMoveClassification.mistake => const Color(0xFFC55A1E),
      GameMoveClassification.blunder => const Color(0xFFC9342E),
    };

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

  String _description() {
    final line = report.positions[activePly].bestLine;
    final evaluation =
        line.mate != null
            ? 'M${line.mate}'
            : ((line.centipawns ?? 0) / 100).toStringAsFixed(2);
    final parts = <String>['${activePly + 1}/${report.positions.length}'];
    if (activePly == 0) {
      parts.add('Start');
    } else {
      final move = report.moves[activePly - 1];
      final moveNumber = (activePly + 1) ~/ 2;
      final prefix = move.isWhite ? '$moveNumber.' : '$moveNumber...';
      parts.add('$prefix ${move.san}');
    }
    parts
      ..add(evaluation)
      ..add(
        '${gameReportWinPercentage(report.positions[activePly].bestLine).round()}% White',
      );
    if (activePly > 0) {
      final classification = report.moves[activePly - 1].classification;
      if (classification != null) parts.add(classification.label);
    }
    return parts.join('  ');
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _GraphStepButton(
          key: const ValueKey('game-review-previous-move'),
          icon: Icons.chevron_left_rounded,
          enabled: activePly > 0,
          onTap: () => onJumpToPly(activePly - 1),
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
          enabled: activePly < report.positions.length - 1,
          onTap: () => onJumpToPly(activePly + 1),
        ),
      ],
    );
  }
}

class _GraphStepButton extends StatelessWidget {
  const _GraphStepButton({
    super.key,
    required this.icon,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 34,
      child: IconButton(
        padding: EdgeInsets.zero,
        iconSize: 25,
        onPressed: enabled ? onTap : null,
        style: IconButton.styleFrom(
          foregroundColor: kWhiteColor,
          disabledForegroundColor: kLightGreyColor.withValues(alpha: 0.4),
          backgroundColor: kBlack3Color,
          disabledBackgroundColor: kBlack3Color.withValues(alpha: 0.45),
        ),
        icon: Icon(icon),
      ),
    );
  }
}

class _ReviewGraphPainter extends CustomPainter {
  const _ReviewGraphPainter({required this.positions, required this.activePly});

  final List<GameReportPosition> positions;
  final int activePly;

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
    final path = Path();
    for (var i = 0; i < positions.length; i++) {
      final x =
          positions.length == 1 ? 0.0 : size.width * i / (positions.length - 1);
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
    final safePly = activePly.clamp(0, positions.length - 1);
    final markerX =
        positions.length == 1
            ? 0.0
            : size.width * safePly / (positions.length - 1);
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
      oldDelegate.activePly != activePly || oldDelegate.positions != positions;
}
