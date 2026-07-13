import 'package:chessever2/screens/tour_detail/bracket/models/knockout_bracket.dart';
import 'package:chessever2/screens/tour_detail/bracket/widgets/bracket_graph_layout.dart';
import 'package:chessever2/screens/tour_detail/bracket/widgets/knockout_match_card.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:flutter/material.dart';

class KnockoutBracketCanvas extends StatelessWidget {
  const KnockoutBracketCanvas({
    required this.bracket,
    required this.layout,
    required this.onMatchTap,
    this.focusedMatchKey,
    super.key,
  });

  final KnockoutBracket bracket;
  final BracketGraphLayout layout;
  final String? focusedMatchKey;
  final ValueChanged<KnockoutMatch> onMatchTap;

  @override
  Widget build(BuildContext context) {
    final stages = List<KnockoutStage>.of(bracket.stages)
      ..sort((a, b) => a.order.compareTo(b.order));

    return RepaintBoundary(
      child: SizedBox.fromSize(
        key: const ValueKey('knockout-bracket-canvas'),
        size: layout.size,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _BracketConnectorPainter(
                  edges: bracket.edges,
                  matchRects: layout.matchRects,
                  focusedMatchKey: focusedMatchKey,
                  lineColor: context.colors.dividerStrong,
                  focusedColor: context.colors.brand,
                ),
              ),
            ),
            for (final stage in stages)
              if (layout.stageHeaderRects[stage.key] case final rect?)
                Positioned.fromRect(
                  rect: rect,
                  child: _StageHeader(
                    stage: stage,
                    isCurrent: bracket.currentStageKey == stage.key,
                  ),
                ),
            for (final stage in stages)
              for (final match in stage.matches)
                if (layout.matchRects[match.key] case final rect?)
                  Positioned.fromRect(
                    rect: rect,
                    child: KnockoutMatchCard(
                      match: match,
                      isFocused: focusedMatchKey == match.key,
                      onTap: () => onMatchTap(match),
                    ),
                  ),
          ],
        ),
      ),
    );
  }
}

class _StageHeader extends StatelessWidget {
  const _StageHeader({required this.stage, required this.isCurrent});

  final KnockoutStage stage;
  final bool isCurrent;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final showLive = stage.isLive;

    return Semantics(
      header: true,
      label:
          '${stage.label}, ${stage.matches.length} ${stage.matches.length == 1 ? 'match' : 'matches'}',
      child: Row(
        children: [
          Container(
            width: 3,
            height: 18,
            decoration: BoxDecoration(
              color:
                  isCurrent
                      ? colors.brand
                      : colors.dividerStrong.withValues(alpha: 0.75),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              stage.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'InterDisplay',
                color: colors.textPrimary,
                fontSize: 13,
                height: 1.1,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (showLive) ...[
            const SizedBox(width: 7),
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: colors.brand,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: colors.brand.withValues(alpha: 0.4),
                    blurRadius: 5,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 4),
            Text(
              'LIVE',
              style: TextStyle(
                fontFamily: 'InterDisplay',
                color: colors.brand,
                fontSize: 9.5,
                height: 1,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.35,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _BracketConnectorPainter extends CustomPainter {
  const _BracketConnectorPainter({
    required this.edges,
    required this.matchRects,
    required this.focusedMatchKey,
    required this.lineColor,
    required this.focusedColor,
  });

  final List<KnockoutEdge> edges;
  final Map<String, Rect> matchRects;
  final String? focusedMatchKey;
  final Color lineColor;
  final Color focusedColor;

  @override
  void paint(Canvas canvas, Size size) {
    final basePaint =
        Paint()
          ..color = lineColor.withValues(alpha: 0.62)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round;
    final focusPaint =
        Paint()
          ..color = focusedColor.withValues(alpha: 0.82)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.1
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round;

    for (final edge in edges) {
      if (_isFocused(edge)) continue;
      _paintEdge(canvas, edge, basePaint);
    }
    for (final edge in edges) {
      if (!_isFocused(edge)) continue;
      _paintEdge(canvas, edge, focusPaint);
    }
  }

  bool _isFocused(KnockoutEdge edge) =>
      focusedMatchKey != null &&
      (edge.sourceMatchKey == focusedMatchKey ||
          edge.destinationMatchKey == focusedMatchKey);

  void _paintEdge(Canvas canvas, KnockoutEdge edge, Paint paint) {
    final source = matchRects[edge.sourceMatchKey];
    final destination = matchRects[edge.destinationMatchKey];
    if (source == null || destination == null) return;

    final start = source.centerRight;
    final end = destination.centerLeft;
    final middleX = (start.dx + end.dx) / 2;
    final path =
        Path()
          ..moveTo(start.dx, start.dy)
          ..cubicTo(middleX, start.dy, middleX, end.dy, end.dx, end.dy);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _BracketConnectorPainter oldDelegate) =>
      oldDelegate.edges != edges ||
      oldDelegate.matchRects != matchRects ||
      oldDelegate.focusedMatchKey != focusedMatchKey ||
      oldDelegate.lineColor != lineColor ||
      oldDelegate.focusedColor != focusedColor;
}
