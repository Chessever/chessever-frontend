import 'dart:math' as math;

import 'package:chessever2/screens/chessboard/game_review/game_analysis_report.dart';
import 'package:chessever2/screens/chessboard/game_review/game_review_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/widgets/federation_flag.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

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
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.68),
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
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
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
                            widthFactor: reportState.progress.clamp(0.0, 1.0),
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
                              color: enabled ? kWhiteColor : kLightGreyColor,
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
    );
  }
}

class _GameReviewSheet extends StatefulWidget {
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
  State<_GameReviewSheet> createState() => _GameReviewSheetState();
}

class _GameReviewSheetState extends State<_GameReviewSheet> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.62,
      minChildSize: 0.48,
      maxChildSize: 0.94,
      snap: true,
      snapSizes: const [0.62, 0.94],
      builder: (context, scrollController) {
        return NotificationListener<DraggableScrollableNotification>(
          onNotification: (notification) {
            final next = notification.extent >= 0.77;
            if (next != _expanded) setState(() => _expanded = next);
            return false;
          },
          child: Container(
            decoration: const BoxDecoration(
              color: kBackgroundColor,
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            ),
            clipBehavior: Clip.antiAlias,
            child: AnimatedBuilder(
              animation: widget.controller,
              builder: (context, _) {
                final state = widget.controller.state;
                return CustomScrollView(
                  controller: scrollController,
                  slivers: [
                    SliverToBoxAdapter(child: _SheetHeader(game: widget.game)),
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
                      sliver: SliverToBoxAdapter(
                        child: _body(state.reportState),
                      ),
                    ),
                  ],
                );
              },
            ),
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
            game: widget.game,
            expanded: _expanded,
            activePly: widget.activePly,
            onJumpToPly: widget.onJumpToPly,
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
          onAction: widget.controller.retry,
        );
      case GameReportStatus.cancelled:
      case GameReportStatus.idle:
        return _ReviewMessage(
          icon: Icons.analytics_outlined,
          title: 'Game analysis',
          body: state.message ?? 'Stockfish is preparing this game review.',
          actionLabel: 'Analyze Game',
          onAction: widget.controller.retry,
        );
    }
  }
}

class _SheetHeader extends StatelessWidget {
  const _SheetHeader({required this.game});

  final GamesTourModel game;

  @override
  Widget build(BuildContext context) {
    final result = game.effectiveGameStatus.displayText;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
      child: Column(
        children: [
          Container(
            width: 44,
            height: 5,
            decoration: BoxDecoration(
              color: kLightGreyColor,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Game Review',
                  style: TextStyle(
                    color: kWhiteColor,
                    fontSize: 25,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (result.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: kBlack3Color,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: kDividerColor),
                  ),
                  child: Text(
                    result,
                    style: const TextStyle(
                      color: kWhiteColor,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
        ],
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
                    '${(value * 100).round()}% · ${state.completedPositions}/${state.totalPositions}',
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
    required this.expanded,
    required this.activePly,
    required this.onJumpToPly,
  });

  final GameAnalysisReport report;
  final GamesTourModel game;
  final bool expanded;
  final int activePly;
  final ValueChanged<int> onJumpToPly;

  @override
  State<_CompletedReview> createState() => _CompletedReviewState();
}

class _CompletedReviewState extends State<_CompletedReview> {
  late int _selectedPly;

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

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        AnimatedSize(
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOut,
          child:
              widget.expanded
                  ? Column(
                    children: [
                      _EvaluationGraph(
                        report: widget.report,
                        activePly: _selectedPly,
                        onJumpToPly: _jump,
                      ),
                      const SizedBox(height: 12),
                      _GraphNavigator(
                        report: widget.report,
                        activePly: _selectedPly,
                        onJumpToPly: _jump,
                      ),
                      const SizedBox(height: 24),
                    ],
                  )
                  : const SizedBox.shrink(),
        ),
        _PlayerSummary(report: widget.report, game: widget.game),
        const SizedBox(height: 24),
        _ClassificationRecap(report: widget.report),
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
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _PlayerColumn(
            player: game.whitePlayer,
            accuracy: report.whiteAccuracy,
            white: true,
          ),
        ),
        const SizedBox(width: 18),
        Expanded(
          child: _PlayerColumn(
            player: game.blackPlayer,
            accuracy: report.blackAccuracy,
            white: false,
          ),
        ),
      ],
    );
  }
}

class _PlayerColumn extends StatelessWidget {
  const _PlayerColumn({
    required this.player,
    required this.accuracy,
    required this.white,
  });

  final PlayerCard player;
  final double accuracy;
  final bool white;

  @override
  Widget build(BuildContext context) {
    final words = player.name.trim().split(RegExp(r'\s+'));
    final initials = words.take(2).map((word) => word[0].toUpperCase()).join();
    final federation =
        player.countryCode.isNotEmpty ? player.countryCode : player.federation;
    return Column(
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            CircleAvatar(
              radius: 28,
              backgroundColor: white ? kBlack3Color : const Color(0xFF303034),
              child: Text(
                initials,
                style: const TextStyle(
                  color: kWhiteColor,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            if (federation.trim().isNotEmpty)
              Positioned(
                right: -5,
                bottom: -2,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: FederationFlag(
                    federation: federation,
                    width: 20,
                    height: 14,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 14),
        Text(
          player.name,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: kWhiteColor,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          player.rating > 0 ? '${player.rating}' : 'Unrated',
          style: const TextStyle(color: kWhiteColor70, fontSize: 14),
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: white ? kBlack3Color : const Color(0xFFD0D0D2),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: white ? kLightGreyColor : kDividerColor),
          ),
          child: Text(
            '${accuracy.toStringAsFixed(1)}%',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: white ? kWhiteColor : const Color(0xFF222222),
              fontSize: 23,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }
}

class _ClassificationRecap extends StatelessWidget {
  const _ClassificationRecap({required this.report});

  final GameAnalysisReport report;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final classification in GameMoveClassification.values)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${report.count(classification, white: true)}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: kWhiteColor, fontSize: 16),
                  ),
                ),
                SizedBox(
                  width: 170,
                  child: Row(
                    children: [
                      _ClassificationIcon(classification: classification),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          classification.label,
                          style: const TextStyle(
                            color: kWhiteColor,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Text(
                    '${report.count(classification, white: false)}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: kWhiteColor, fontSize: 16),
                  ),
                ),
              ],
            ),
          ),
      ],
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
      GameMoveClassification.forced => 'assets/svgs/forced_move.svg',
      GameMoveClassification.inaccuracy => 'assets/svgs/inaccuracy.svg',
      GameMoveClassification.mistake => 'assets/svgs/mistake.svg',
      GameMoveClassification.blunder => 'assets/svgs/blunder.svg',
      GameMoveClassification.missedWin => 'assets/svgs/missed_win.svg',
    };

Color classificationColor(GameMoveClassification classification) =>
    switch (classification) {
      GameMoveClassification.brilliant => const Color(0xFF177A68),
      GameMoveClassification.goodMove => const Color(0xFF177A68),
      GameMoveClassification.bestMove => const Color(0xFF28833A),
      GameMoveClassification.forced => const Color(0xFF6B7A8A),
      GameMoveClassification.inaccuracy => const Color(0xFFFABE46),
      GameMoveClassification.mistake => const Color(0xFFC55A1E),
      GameMoveClassification.blunder => const Color(0xFFC9342E),
      GameMoveClassification.missedWin => const Color(0xFF8F1E1E),
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

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            Text('OPENING', style: _phaseStyle),
            Text('MIDDLEGAME', style: _phaseStyle),
            Text('ENDGAME', style: _phaseStyle),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 150,
          child: LayoutBuilder(
            builder: (context, constraints) {
              void jump(Offset position) =>
                  onJumpToPly(_plyAt(position.dx, constraints.maxWidth));
              return GestureDetector(
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
              );
            },
          ),
        ),
      ],
    );
  }
}

const _phaseStyle = TextStyle(
  color: kLightGreyColor,
  fontSize: 11,
  fontWeight: FontWeight.w700,
  letterSpacing: 0.8,
);

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

class _GraphNavigator extends StatelessWidget {
  const _GraphNavigator({
    required this.report,
    required this.activePly,
    required this.onJumpToPly,
  });

  final GameAnalysisReport report;
  final int activePly;
  final ValueChanged<int> onJumpToPly;

  @override
  Widget build(BuildContext context) {
    final line = report.positions[activePly].bestLine;
    final evaluation =
        line.mate != null
            ? 'M${line.mate}'
            : '${(line.centipawns ?? 0) >= 0 ? '+' : ''}${((line.centipawns ?? 0) / 100).toStringAsFixed(1)}';
    return Row(
      children: [
        _navButton(
          icon: Icons.chevron_left_rounded,
          enabled: activePly > 0,
          onTap: () => onJumpToPly(activePly - 1),
        ),
        Expanded(
          child: Text(
            '$activePly/${report.positions.length - 1}  $evaluation',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: kWhiteColor,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        _navButton(
          icon: Icons.chevron_right_rounded,
          enabled: activePly < report.positions.length - 1,
          onTap: () => onJumpToPly(activePly + 1),
        ),
      ],
    );
  }

  Widget _navButton({
    required IconData icon,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    return IconButton.filled(
      onPressed: enabled ? onTap : null,
      style: IconButton.styleFrom(
        backgroundColor: kBlack3Color,
        disabledBackgroundColor: kBlack3Color.withValues(alpha: 0.45),
      ),
      icon: Icon(icon),
    );
  }
}
