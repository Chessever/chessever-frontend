import 'package:dartchess/dartchess.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../theme/app_theme.dart';
import '../../../utils/responsive_helper.dart';
import '../models/models.dart';
import '../providers/gamebase_providers.dart';

/// Panel displaying move statistics for the current position.
/// Shows each possible move with game count and win/draw/loss bar.
class MoveStatisticsPanel extends ConsumerWidget {
  const MoveStatisticsPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(gamebaseExplorerProvider);

    if (state.isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: kPrimaryColor, strokeWidth: 2),
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
              Text(
                '${_formatNumber(state.totalGames)} games',
                style: TextStyle(color: kSecondaryTextColor, fontSize: 12.f),
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
                onTap: () {
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
    required this.onTap,
  });

  final MoveAggregate aggregate;
  final String currentFen;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final sanMove = _uciToSan(aggregate.uci, currentFen);

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
              width: 44.w,
              child: Text(
                aggregate.formattedTotal,
                style: TextStyle(color: kSecondaryTextColor, fontSize: 12.f),
                textAlign: TextAlign.right,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Convert UCI move notation to SAN (Standard Algebraic Notation).
  String _uciToSan(String uci, String fen) {
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
    } catch (e) {
      // Fallback to UCI if conversion fails
      return uci;
    }
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
