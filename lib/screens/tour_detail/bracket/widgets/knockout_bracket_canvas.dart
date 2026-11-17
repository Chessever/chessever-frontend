import 'package:chessever2/screens/tour_detail/bracket/models/knockout_bracket.dart';
import 'package:chessever2/screens/tour_detail/bracket/widgets/bracket_graph_layout.dart';
import 'package:chessever2/screens/tour_detail/bracket/widgets/knockout_match_card.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'bracket_connector_painter.dart';

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

    final hasSeededRoutes = stages.any(
      (s) => s.matches.any((m) => m.feederMatchKeys.isNotEmpty),
    );
    final connections = layout.connections.isNotEmpty
        ? layout.connections
        : [
            for (final edge in bracket.edges)
              BracketConnection(
                sourceMatchKey: edge.sourceMatchKey,
                destinationMatchKey: edge.destinationMatchKey,
                isConfirmed: true,
              ),
          ];
    final plannedSources = connections
        .where((c) => !c.isConfirmed)
        .map((c) => c.sourceMatchKey)
        .toSet();
    return RepaintBoundary(
      child: SizedBox.fromSize(
        key: const ValueKey('knockout-bracket-canvas'),
        size: layout.size,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: BracketConnectorPainter(
                  connections: connections,
                  arrowheads: hasSeededRoutes,
                  matchRects: layout.matchRects,
                  focusedMatchKey: focusedMatchKey,
                  futureColor: context.colors.textSecondary.withValues(
                    alpha: context.isLightTheme ? 0.72 : 0.65,
                  ),
                  confirmedColor: hasSeededRoutes || context.isLightTheme
                      ? context.colors.textSecondary.withValues(alpha: 0.8)
                      : context.colors.dividerStrong.withValues(alpha: 0.62),
                  focusedColor: context.colors.accentText.withValues(
                    alpha: hasSeededRoutes ? 0.9 : 0.82,
                  ),
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
                    isPlacement: rect.top > BracketGraphMetrics.headerTop,
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
                      isUpcoming:
                          match.isUpcoming &&
                          (match.isProjected ||
                              match.feederMatchKeys.isNotEmpty ||
                              plannedSources.contains(match.key)),
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
  const _StageHeader({
    required this.stage,
    required this.isCurrent,
    this.isPlacement = false,
  });

  final KnockoutStage stage;
  final bool isCurrent;
  final bool isPlacement;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final showLive = stage.isLive;

    return Semantics(
      header: true,
      label:
          '${stage.label}${isPlacement ? ', semifinal losers' : ''}, ${stage.matches.length} ${stage.matches.length == 1 ? 'match' : 'matches'}',
      child: Row(
        children: [
          Container(
            width: 3,
            height: 18,
            decoration: BoxDecoration(
              color: isCurrent
                  ? colors.accentText
                  : colors.dividerStrong.withValues(alpha: 0.75),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              isPlacement ? '${stage.label} (losers)' : stage.label,
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
                color: colors.accentText,
                shape: BoxShape.circle,
                boxShadow: context.isLightTheme
                    ? null
                    : [
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
                color: context.colors.accentText,
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
