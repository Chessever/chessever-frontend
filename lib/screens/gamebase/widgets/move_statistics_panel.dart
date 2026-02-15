import 'package:dartchess/dartchess.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../theme/app_theme.dart';
import '../../../utils/responsive_helper.dart';
import '../models/models.dart';
import '../providers/gamebase_explorer_state.dart';
import '../providers/gamebase_providers.dart';
import 'position_games_sheet.dart';

/// Panel displaying move statistics for the current position.
/// Shows each possible move with game count and win/draw/loss bar.
class MoveStatisticsPanel extends ConsumerWidget {
  const MoveStatisticsPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(gamebaseExplorerProvider);

    if (state.isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: kWhiteColor, strokeWidth: 2),
      );
    }

    if (state.error != null) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(16.sp),
          child: Text(
            state.error!,
            style: TextStyle(color: kRedColor, fontSize: 14.f),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    if (state.moveAggregates.isEmpty) {
      // The backend only indexes the first N plies for the opening explorer.
      // If the user navigates beyond that, aggregates will be empty even though
      // games exist. Make this explicit so it doesn't look like missing data.
      if (state.currentMoveNumber > GamebaseExplorerState.maxIndexedMoveNumber) {
        return Center(
          child: Padding(
            padding: EdgeInsets.all(16.sp),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Opening Explorer covers the first ${GamebaseExplorerState.maxIndexedMoveNumber} plies.',
                  style: TextStyle(color: kSecondaryTextColor, fontSize: 14.f),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 10.h),
                Text(
                  'Open a game from this line to continue.',
                  style: TextStyle(color: kSecondaryTextColor, fontSize: 12.f),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        );
      }

      return Center(
        child: Padding(
          padding: EdgeInsets.all(16.sp),
          child: Text(
            'No games found for this position',
            style: TextStyle(color: kSecondaryTextColor, fontSize: 14.f),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header with total games
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 12.sp, vertical: 8.sp),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Moves',
                style: TextStyle(
                  color: kWhiteColor,
                  fontSize: 14.f,
                  fontWeight: FontWeight.w600,
                ),
              ),
              InkWell(
                borderRadius: BorderRadius.circular(6.br),
                onTap: () {
                  showModalBottomSheet(
                    context: context,
                    backgroundColor: Colors.transparent,
                    isScrollControlled: true,
                    builder: (_) => PositionGamesSheet(
                      fen: state.currentFen,
                      filters: state.filters,
                      title: 'Games in this position',
                    ),
                  );
                },
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 4.h),
                  child: Row(
                    children: [
                      Text(
                        '${_formatNumber(state.totalGames)} games',
                        style: TextStyle(
                          color: kSecondaryTextColor,
                          fontSize: 12.f,
                        ),
                      ),
                      SizedBox(width: 6.sp),
                      Icon(
                        Icons.list_alt_rounded,
                        color: kSecondaryTextColor,
                        size: 16.ic,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        Divider(color: kDividerColor, height: 1),
        // Move list
        Expanded(
          child: ListView.separated(
            padding: EdgeInsets.zero,
            itemCount: state.moveAggregates.length,
            separatorBuilder:
                (_, __) =>
                    Divider(color: kDividerColor, height: 1, indent: 12.sp),
            itemBuilder: (context, index) {
              final aggregate = state.moveAggregates[index];
              return _MoveStatisticsRow(
                aggregate: aggregate,
                currentFen: state.currentFen,
                filters: state.filters,
                onTap: () {
                  // When we reach the indexed depth limit, don't "advance" into
                  // a position we cannot aggregate. Instead, offer example games
                  // for that move so the user can continue in a real game view.
                  if (state.isAtIndexedDepthLimit) {
                    final sanMove = uciToSan(aggregate.uci, state.currentFen);

                    showModalBottomSheet(
                      context: context,
                      backgroundColor: Colors.transparent,
                      isScrollControlled: true,
                      builder: (_) => PositionGamesSheet(
                        fen: state.currentFen,
                        uci: aggregate.uci,
                        filters: state.filters,
                        title: 'Continue with $sanMove',
                      ),
                    );
                    return;
                  }

                  ref
                      .read(gamebaseExplorerProvider.notifier)
                      .makeMove(aggregate.uci);
                },
              );
            },
          ),
        ),
      ],
    );
  }

  String _formatNumber(int number) {
    if (number >= 1000000) {
      return '${(number / 1000000).toStringAsFixed(1)}M';
    } else if (number >= 1000) {
      return '${(number / 1000).toStringAsFixed(1)}K';
    }
    return number.toString();
  }
}

/// Individual row showing move statistics.
class _MoveStatisticsRow extends StatelessWidget {
  const _MoveStatisticsRow({
    required this.aggregate,
    required this.currentFen,
    required this.filters,
    required this.onTap,
  });

  final MoveAggregate aggregate;
  final String currentFen;
  final GamebaseFilters filters;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final sanMove = uciToSan(aggregate.uci, currentFen);

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 12.sp, vertical: 10.sp),
        child: Row(
          children: [
            // Move name
            SizedBox(
              width: 48.w,
              child: Text(
                sanMove,
                style: TextStyle(
                  color: kWhiteColor,
                  fontSize: 14.f,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            SizedBox(width: 8.sp),
            // Statistics bar
            Expanded(
              child: _StatisticsBar(
                whiteRate: aggregate.whiteWinRate,
                drawRate: aggregate.drawRate,
                blackRate: aggregate.blackWinRate,
              ),
            ),
            SizedBox(width: 8.sp),
            // Game count
            SizedBox(
              width: 84.w,
              child: Row(
                children: [
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        aggregate.formattedTotal,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        softWrap: false,
                        style: TextStyle(
                          color: kSecondaryTextColor,
                          fontSize: 12.f,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: 4.sp),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: BoxConstraints.tightFor(width: 24.w, height: 24.h),
                    icon: Icon(
                      Icons.list_alt_rounded,
                      color: kSecondaryTextColor,
                      size: 18.ic,
                    ),
                    tooltip: 'Games',
                    onPressed: () {
                      showModalBottomSheet(
                        context: context,
                        backgroundColor: Colors.transparent,
                        isScrollControlled: true,
                        builder: (_) => PositionGamesSheet(
                          fen: currentFen,
                          uci: aggregate.uci,
                          filters: filters,
                          title: 'Games for $sanMove',
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Convert UCI move notation to SAN (Standard Algebraic Notation) for display.
String uciToSan(String uci, String fen) {
  try {
    final position = Chess.fromSetup(Setup.parseFen(fen));

    final from = Square.fromName(uci.substring(0, 2));
    final to = Square.fromName(uci.substring(2, 4));
    Role? promotion;
    if (uci.length > 4) {
      promotion = Role.fromChar(uci[4]);
    }

    final move = NormalMove(from: from, to: to, promotion: promotion);
    final result = position.makeSan(move);
    return result.$2;
  } catch (_) {
    return uci;
  }
}

/// Horizontal bar showing win/draw/loss distribution.
class _StatisticsBar extends StatelessWidget {
  const _StatisticsBar({
    required this.whiteRate,
    required this.drawRate,
    required this.blackRate,
  });

  final double whiteRate;
  final double drawRate;
  final double blackRate;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(2.br),
      child: SizedBox(
        height: 16.h,
        child: Row(
          children: [
            // White wins (green)
            if (whiteRate > 0)
              Expanded(
                flex: (whiteRate * 100).round(),
                child: Container(
                  color: kGreenColor,
                  alignment: Alignment.center,
                  child:
                      whiteRate >= 0.15
                          ? Text(
                            '${(whiteRate * 100).toStringAsFixed(0)}%',
                            style: TextStyle(
                              color: kWhiteColor,
                              fontSize: 10.f,
                              fontWeight: FontWeight.w600,
                            ),
                          )
                          : null,
                ),
              ),
            // Draws (grey)
            if (drawRate > 0)
              Expanded(
                flex: (drawRate * 100).round(),
                child: Container(
                  color: kSecondaryTextColor,
                  alignment: Alignment.center,
                  child:
                      drawRate >= 0.15
                          ? Text(
                            '${(drawRate * 100).toStringAsFixed(0)}%',
                            style: TextStyle(
                              color: kWhiteColor,
                              fontSize: 10.f,
                              fontWeight: FontWeight.w600,
                            ),
                          )
                          : null,
                ),
              ),
            // Black wins (red)
            if (blackRate > 0)
              Expanded(
                flex: (blackRate * 100).round(),
                child: Container(
                  color: kRedColor,
                  alignment: Alignment.center,
                  child:
                      blackRate >= 0.15
                          ? Text(
                            '${(blackRate * 100).toStringAsFixed(0)}%',
                            style: TextStyle(
                              color: kWhiteColor,
                              fontSize: 10.f,
                              fontWeight: FontWeight.w600,
                            ),
                          )
                          : null,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
