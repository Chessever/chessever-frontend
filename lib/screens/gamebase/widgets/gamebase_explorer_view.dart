import 'package:chessever2/screens/chessboard/view_model/chess_board_state_new.dart';
import 'package:chessever2/screens/gamebase/models/models.dart';
import 'package:chessever2/screens/gamebase/providers/gamebase_providers.dart';
import 'package:chessever2/screens/gamebase/providers/gamebase_explorer_state.dart';
import 'package:chessever2/screens/gamebase/widgets/gamebase_filter_panel.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:intl/intl.dart';

class GamebaseExplorerView extends HookConsumerWidget {
  const GamebaseExplorerView({
    super.key,
    required this.state,
    required this.onMoveSelected,
  });

  final ChessBoardStateNew state;
  final Function(String uci) onMoveSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentFen =
        state.position?.fen ??
        'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';

    // Sync Gamebase provider with current board FEN
    useEffect(() {
      Future.microtask(() {
        ref.read(gamebaseExplorerProvider.notifier).setPosition(currentFen);
      });
      return null;
    }, [currentFen]);

    final gamebaseState = ref.watch(gamebaseExplorerProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Horizontal PV Lines (Engine Analysis)
        if (state.showEngineAnalysis) _HorizontalPvLines(state: state),

        // Filter Panel
        const GamebaseFilterPanel(),

        // Moves Table
        Expanded(child: _buildContent(gamebaseState)),
      ],
    );
  }

  Widget _buildContent(GamebaseExplorerState gamebaseState) {
    if (gamebaseState.isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: kPrimaryColor),
      );
    }

    if (gamebaseState.error != null) {
      return Center(
        child: Text(
          'Could not load database stats',
          style: AppTypography.textSmRegular.copyWith(
            color: kWhiteColor.withValues(alpha: 0.5),
          ),
        ),
      );
    }

    return _GamebaseMovesTable(
      moves: gamebaseState.moveAggregates,
      totalGames: gamebaseState.moveAggregates.fold(
        0,
        (sum, move) => sum + move.total,
      ),
      onMoveSelected: onMoveSelected,
      currentPosition: state.analysisState.position,
    );
  }
}

class _HorizontalPvLines extends StatelessWidget {
  const _HorizontalPvLines({required this.state});

  final ChessBoardStateNew state;

  @override
  Widget build(BuildContext context) {
    final lines = state.analysisState.suggestionLines;
    if (lines.isEmpty) return const SizedBox.shrink();

    return Container(
      height: 60.h,
      decoration: BoxDecoration(
        color: kBlack2Color,
        border: Border(
          bottom: BorderSide(color: kWhiteColor.withValues(alpha: 0.05)),
        ),
      ),
      child: ListView.separated(
        padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
        scrollDirection:
            Axis.vertical, // Showing lines vertically stacked, but each line is horizontal text
        itemCount: lines.length,
        separatorBuilder: (_, __) => SizedBox(height: 4.h),
        itemBuilder: (context, index) {
          final line = lines[index];
          final eval = line.displayEval.isNotEmpty ? line.displayEval : '...';
          final moves = line.sanMoves.join(' ');

          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 2.h),
                  decoration: BoxDecoration(
                    color: kWhiteColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4.br),
                  ),
                  child: Text(
                    eval,
                    style: AppTypography.textXsBold.copyWith(
                      color: kPrimaryColor,
                    ),
                  ),
                ),
                SizedBox(width: 8.w),
                Text(
                  moves,
                  style: AppTypography.textXsRegular.copyWith(
                    color: kWhiteColor.withValues(alpha: 0.8),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _GamebaseMovesTable extends StatelessWidget {
  const _GamebaseMovesTable({
    required this.moves,
    required this.totalGames,
    required this.onMoveSelected,
    required this.currentPosition,
  });

  final List<MoveAggregate> moves;
  final int totalGames;
  final Function(String uci) onMoveSelected;
  final Position currentPosition;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Header
        Container(
          padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
          color: kBlackColor,
          child: Row(
            children: [
              Expanded(flex: 2, child: Text('Moves', style: _headerStyle)),
              Expanded(
                flex: 2,
                child: Text(
                  '#',
                  style: _headerStyle,
                  textAlign: TextAlign.right,
                ),
              ),
              Expanded(
                flex: 3,
                child: Text(
                  'Score',
                  style: _headerStyle,
                  textAlign: TextAlign.center,
                ),
              ),
              Expanded(
                flex: 3,
                child: Text(
                  'Last played',
                  style: _headerStyle,
                  textAlign: TextAlign.right,
                ),
              ),
            ],
          ),
        ),
        // List
        Expanded(
          child: ListView.builder(
            padding: EdgeInsets.zero,
            itemCount: moves.length,
            itemBuilder: (context, index) {
              final move = moves[index];
              return _MoveRow(
                move: move,
                maxTotal: moves.first.total, // For progress bar relative to max
                onPressed: () => onMoveSelected(move.uci),
                position: currentPosition,
              );
            },
          ),
        ),
      ],
    );
  }

  TextStyle get _headerStyle =>
      AppTypography.textSmMedium.copyWith(color: kWhiteColor.withValues(alpha: 0.5));
}

class _MoveRow extends ConsumerWidget {
  const _MoveRow({
    required this.move,
    required this.maxTotal,
    required this.onPressed,
    required this.position,
  });

  final MoveAggregate move;
  final int maxTotal;
  final VoidCallback onPressed;
  final Position position;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Calculate percentages
    final total = move.total;
    final whitePct = (move.white / total * 100).round();
    final drawPct = (move.draws / total * 100).round();

    final lastPlayedAsync =
        move.gameId != null
            ? ref.watch(gameByIdProvider(move.gameId!))
            : const AsyncValue<GamebaseGame?>.data(null);

    final lastPlayedText = lastPlayedAsync.when(
      data: (game) =>
          game != null ? DateFormat('MM-yyyy').format(game.date) : '—',
      loading: () => '…',
      error: (_, __) => '—',
    );

    // Convert UCI to SAN
    String san = move.uci;
    try {
      if (move.uci.length >= 4) {
        final from = Square.fromName(move.uci.substring(0, 2));
        final to = Square.fromName(move.uci.substring(2, 4));
        Role? promotion;
        if (move.uci.length > 4) {
          promotion = Role.fromChar(move.uci[4]);
        }
        final moveObj = NormalMove(from: from, to: to, promotion: promotion);
        final result = position.makeSan(moveObj);
        san = result.$2;
      }
    } catch (e) {
      // Fallback to UCI
    }

    return InkWell(
      onTap: onPressed,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: kWhiteColor.withValues(alpha: 0.05)),
          ),
        ),
        child: Row(
          children: [
            // Move SAN
            Expanded(
              flex: 2,
              child: Row(
                children: [
                  Text(
                    san,
                    style: AppTypography.textSmBold.copyWith(
                      color: kWhiteColor,
                    ),
                  ),
                  if (move.gameId != null) // Indicator for single game
                    Padding(
                      padding: EdgeInsets.only(left: 4.w),
                      child: Icon(
                        Icons.person,
                        size: 12.sp,
                        color: kPrimaryColor,
                      ),
                    ),
                ],
              ),
            ),

            // Count
            Expanded(
              flex: 2,
              child: Text(
                NumberFormat.compact().format(total),
                style: AppTypography.textSmRegular.copyWith(
                  color: kWhiteColor.withValues(alpha: 0.7),
                ),
                textAlign: TextAlign.right,
              ),
            ),

            // Score Bar
            Expanded(
              flex: 3,
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 8.w),
                child: Row(
                  children: [
                    Text(
                      '${whitePct + drawPct}%',
                      style: AppTypography.textXsMedium.copyWith(
                        color: kWhiteColor.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                  mainAxisAlignment: MainAxisAlignment.center,
                ),
              ),
            ),

            // Last Played / Date
            Expanded(
              flex: 3,
              child: Text(
                lastPlayedText,
                style: AppTypography.textSmRegular.copyWith(
                  color: kWhiteColor.withValues(alpha: 0.7),
                ),
                textAlign: TextAlign.right,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
