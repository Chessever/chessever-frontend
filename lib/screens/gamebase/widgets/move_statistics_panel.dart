import 'package:chessever2/providers/board_settings_provider_new.dart';
import 'package:chessever2/utils/figurine_notation.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../theme/app_theme.dart';
import '../../../utils/responsive_helper.dart';
import '../models/models.dart';
import '../providers/gamebase_explorer_state.dart';
import '../providers/gamebase_providers.dart';
import 'position_games_sheet.dart';

const double _kMoveColumnBaseWidth = 82;
const double _kGamesColumnBaseWidth = 52;
const double _kLastColumnBaseWidth = 62;
const double _kExplorerColumnGap = 6;

/// Panel displaying move statistics for the current position.
/// Shows each possible move with game count and win/draw/loss bar.
class MoveStatisticsPanel extends ConsumerWidget {
  const MoveStatisticsPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(gamebaseExplorerProvider);
    final hasStaleData = state.moveAggregates.isNotEmpty;

    if (state.isLoading && !hasStaleData) {
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
        if (state.isLoading)
          const LinearProgressIndicator(
            minHeight: 2,
            color: kWhiteColor,
            backgroundColor: Colors.transparent,
          ),
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
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.of(context).size.height * 0.88,
                    ),
                    builder:
                        (_) => PositionGamesSheet(
                          fen: state.currentFen,
                          moves: state.exploredMoves,
                          filters: state.filters,
                          title: 'Games in this position',
                        ),
                  );
                },
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 4.h),
                  child: Text(
                    '${_formatNumber(state.totalGames)} games',
                    style: TextStyle(
                      color: kSecondaryTextColor,
                      fontSize: 12.f,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        Divider(color: kDividerColor, height: 1),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 12.sp, vertical: 6.sp),
          child: Row(
            children: [
              SizedBox(
                width: _kMoveColumnBaseWidth.w,
                child: Text(
                  'Move',
                  style: TextStyle(
                    color: kSecondaryTextColor,
                    fontSize: 11.f,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              SizedBox(width: _kExplorerColumnGap.sp),
              Expanded(
                child: Text(
                  'Score',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: kSecondaryTextColor,
                    fontSize: 11.f,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              SizedBox(width: _kExplorerColumnGap.sp),
              SizedBox(
                width: _kGamesColumnBaseWidth.w,
                child: Text(
                  'Games',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    color: kSecondaryTextColor,
                    fontSize: 11.f,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              SizedBox(
                width: _kLastColumnBaseWidth.w,
                child: Text(
                  'Last',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    color: kSecondaryTextColor,
                    fontSize: 11.f,
                    fontWeight: FontWeight.w600,
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
                exploredMoves: state.exploredMoves,
                filters: state.filters,
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
class _MoveStatisticsRow extends ConsumerWidget {
  const _MoveStatisticsRow({
    required this.aggregate,
    required this.currentFen,
    required this.exploredMoves,
    required this.filters,
    required this.onTap,
  });

  final MoveAggregate aggregate;
  final String currentFen;
  final List<String> exploredMoves;
  final GamebaseFilters filters;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (sanMove, _) = uciToSanAndFen(aggregate.uci, currentFen);
    final moveNumberLabel =
        currentFen.split(' ')[1] == 'w'
            ? '${_fullMoveNumberFromFen(currentFen)}.'
            : '${_fullMoveNumberFromFen(currentFen)}...';

    final useFigurine = ref.watch(
      boardSettingsProviderNew.select(
        (s) =>
            s.valueOrNull?.useFigurine ?? const BoardSettingsNew().useFigurine,
      ),
    );
    final pieceAssets = ref.watch(
      boardSettingsProviderNew.select(
        (s) =>
            s.valueOrNull?.pieceAssets ?? const BoardSettingsNew().pieceAssets,
      ),
    );

    final moveStyle = TextStyle(
      color: kWhiteColor,
      fontSize: 14.f,
      fontWeight: FontWeight.w500,
    );

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 12.sp, vertical: 10.sp),
        child: Row(
          children: [
            // Move name
            SizedBox(
              width: _kMoveColumnBaseWidth.w,
              child: Row(
                children: [
                  Text(
                    moveNumberLabel,
                    style: TextStyle(
                      color: kSecondaryTextColor,
                      fontSize: 12.f,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  SizedBox(width: 4.w),
                  Expanded(
                    child:
                        useFigurine
                            ? RichText(
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                              text: TextSpan(
                                children: buildFigurineSpans(
                                  text: sanMove,
                                  pieceAssets: pieceAssets,
                                  style: moveStyle,
                                  pieceSize: 16.f,
                                ),
                              ),
                            )
                            : Text(
                              sanMove,
                              style: moveStyle,
                              overflow: TextOverflow.ellipsis,
                            ),
                  ),
                ],
              ),
            ),
            SizedBox(width: _kExplorerColumnGap.sp),
            // Fixed W/D/L score cells so values remain readable at any percentage.
            Expanded(
              child: _StatisticsBreakdown(
                whitePercent: aggregate.whiteWinPercent,
                drawPercent: aggregate.drawPercent,
                blackPercent: aggregate.blackWinPercent,
              ),
            ),
            SizedBox(width: _kExplorerColumnGap.sp),
            SizedBox(
              width: _kGamesColumnBaseWidth.w,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Flexible(
                    child: Text(
                      aggregate.formattedTotal,
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        color: kSecondaryTextColor,
                        fontSize: 12.f,
                      ),
                    ),
                  ),
                  SizedBox(width: 1.sp),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: BoxConstraints.tightFor(
                      width: 20.w,
                      height: 20.h,
                    ),
                    icon: Icon(
                      Icons.list_alt_rounded,
                      color: kSecondaryTextColor,
                      size: 15.ic,
                    ),
                    tooltip: 'Games',
                    onPressed: () {
                      showModalBottomSheet(
                        context: context,
                        backgroundColor: Colors.transparent,
                        isScrollControlled: true,
                        constraints: BoxConstraints(
                          maxHeight: MediaQuery.of(context).size.height * 0.88,
                        ),
                        builder:
                            (_) => PositionGamesSheet(
                              fen: currentFen,
                              moves: exploredMoves,
                              uci: aggregate.uci,
                              filters: filters,
                              title: 'Games for $moveNumberLabel$sanMove',
                            ),
                      );
                    },
                  ),
                ],
              ),
            ),
            SizedBox(
              width: _kLastColumnBaseWidth.w,
              child: Text(
                _formatLastPlayed(aggregate.lastPlayed),
                textAlign: TextAlign.right,
                style: TextStyle(color: kSecondaryTextColor, fontSize: 12.f),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _formatLastPlayed(DateTime? date) {
  if (date == null) return '—';
  return DateFormat('MMM yyyy').format(date);
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

int _fullMoveNumberFromFen(String fen) {
  final parts = fen.trim().split(RegExp(r'\s+'));
  if (parts.length < 6) return 1;
  return int.tryParse(parts[5]) ?? 1;
}

/// Like [uciToSan] but also returns the resulting FEN after the move.
/// Returns `(san, resultingFen)`. `resultingFen` is null on parse failure.
(String san, String? resultingFen) uciToSanAndFen(String uci, String fen) {
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
    // result.$1 is the new Position, result.$2 is the SAN string
    return (result.$2, result.$1.fen);
  } catch (_) {
    return (uci, null);
  }
}

/// Equal-width score cells for white, draw, and black outcomes.
class _StatisticsBreakdown extends StatelessWidget {
  const _StatisticsBreakdown({
    required this.whitePercent,
    required this.drawPercent,
    required this.blackPercent,
  });

  final String whitePercent;
  final String drawPercent;
  final String blackPercent;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 22.h,
      child: Row(
        children: [
          Expanded(
            child: _ScoreCell(
              label: 'W',
              value: whitePercent,
              backgroundColor: kMoveStatWhiteColor,
              textColor: kMoveStatBlackColor,
            ),
          ),
          SizedBox(width: 2.sp),
          Expanded(
            child: _ScoreCell(
              label: 'D',
              value: drawPercent,
              backgroundColor: kMoveStatDrawColor,
              textColor: kMoveStatWhiteColor,
            ),
          ),
          SizedBox(width: 2.sp),
          Expanded(
            child: _ScoreCell(
              label: 'L',
              value: blackPercent,
              backgroundColor: kMoveStatBlackColor,
              textColor: kMoveStatWhiteColor,
            ),
          ),
        ],
      ),
    );
  }
}

class _ScoreCell extends StatelessWidget {
  const _ScoreCell({
    required this.label,
    required this.value,
    required this.backgroundColor,
    required this.textColor,
  });

  final String label;
  final String value;
  final Color backgroundColor;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.center,
      padding: EdgeInsets.symmetric(horizontal: 4.w),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(12.br),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          '$label $value',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: textColor,
            fontSize: 10.f,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
