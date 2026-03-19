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
        (s) => s.valueOrNull?.useFigurine ?? false,
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
              width: 86.w,
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
            // Game count + list button — natural width, never truncates
            Text(
              aggregate.formattedTotal,
              style: TextStyle(color: kSecondaryTextColor, fontSize: 12.f),
            ),
            SizedBox(width: 2.sp),
            IconButton(
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: BoxConstraints.tightFor(width: 22.w, height: 22.h),
              icon: Icon(
                Icons.list_alt_rounded,
                color: kSecondaryTextColor,
                size: 16.ic,
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
                        title: 'Games for $sanMove',
                      ),
                );
              },
            ),
            // Date — most recent game date for this move, shown for all moves
            SizedBox(width: 4.sp),
            _MoveDateDisplay(
              query: GamebasePositionGamesQuery(
                fen: currentFen,
                moves: exploredMoves,
                uci: aggregate.uci,
                timeControl:
                    filters.timeControls.isNotEmpty
                        ? filters.timeControls.first
                        : null,
                playerId:
                    filters.playerIds.isNotEmpty
                        ? filters.playerIds.first
                        : null,
                color: filters.playerColor?.name,
                result: filters.gameResult?.apiValue,
                minRating: filters.minRating,
                maxRating: filters.maxRating,
                pageSize: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Displays the most recent game date for a move row.
///
/// Watches [moveLastGameDateProvider] which fetches 1 game sorted by date desc,
/// so it always shows the latest game date regardless of how many games exist.
class _MoveDateDisplay extends ConsumerWidget {
  const _MoveDateDisplay({required this.query});

  final GamebasePositionGamesQuery query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final date = ref.watch(moveLastGameDateProvider(query)).valueOrNull;
    if (date == null) return const SizedBox.shrink();
    return Text(
      DateFormat('MM/yyyy').format(date),
      style: TextStyle(color: kSecondaryTextColor, fontSize: 11.f),
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
      borderRadius: BorderRadius.circular(16.br),
      child: SizedBox(
        height: 16.h,
        child: Row(
          children: [
            // White wins
            if (whiteRate > 0)
              Expanded(
                flex: (whiteRate * 100).round(),
                child: Container(
                  color: kMoveStatWhiteColor,
                  alignment: Alignment.center,
                  child:
                      whiteRate >= 0.08
                          ? Text(
                            '${(whiteRate * 100).toStringAsFixed(0)}%',
                            style: TextStyle(
                              color: kMoveStatBlackColor,
                              fontSize: 10.f,
                              fontWeight: FontWeight.w600,
                            ),
                          )
                          : null,
                ),
              ),
            // Draws
            if (drawRate > 0)
              Expanded(
                flex: (drawRate * 100).round(),
                child: Container(
                  color: kMoveStatDrawColor,
                  alignment: Alignment.center,
                  child:
                      drawRate >= 0.08
                          ? Text(
                            '${(drawRate * 100).toStringAsFixed(0)}%',
                            style: TextStyle(
                              color: kMoveStatWhiteColor,
                              fontSize: 10.f,
                              fontWeight: FontWeight.w600,
                            ),
                          )
                          : null,
                ),
              ),
            // Black wins
            if (blackRate > 0)
              Expanded(
                flex: (blackRate * 100).round(),
                child: Container(
                  color: kMoveStatBlackColor,
                  alignment: Alignment.center,
                  child:
                      blackRate >= 0.08
                          ? Text(
                            '${(blackRate * 100).toStringAsFixed(0)}%',
                            style: TextStyle(
                              color: kMoveStatWhiteColor,
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
