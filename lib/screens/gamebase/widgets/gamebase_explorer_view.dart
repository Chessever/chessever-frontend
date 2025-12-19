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
    this.onGameSelected,
  });

  final ChessBoardStateNew state;
  final Function(String uci) onMoveSelected;
  final void Function(String gameId)? onGameSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Always use analysisState.position - it's non-nullable and tracks the
    // actual displayed position on the board regardless of mode (analysis,
    // library game, live game, etc.).
    final currentPosition = state.analysisState.position;
    final currentFen = currentPosition.fen;

    // Sync Gamebase provider with current board FEN
    useEffect(() {
      debugPrint('[GamebaseExplorerView] FEN changed: ${currentFen.split(' ').take(2).join(' ')}...');
      Future.microtask(() {
        ref.read(gamebaseExplorerProvider.notifier).setPosition(currentFen);
      });
      return null;
    }, [currentFen]);

    final gamebaseState = ref.watch(gamebaseExplorerProvider);

    return LayoutBuilder(
      builder: (context, constraints) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Horizontal PV Lines (Engine Analysis)
            if (state.showEngineAnalysis)
              _HorizontalPvLines(state: state, onMoveSelected: onMoveSelected),

            // Filter Panel - scrollable when expanded to prevent overflow
            Flexible(
              flex: 0,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: constraints.maxHeight * 0.6,
                ),
                child: const SingleChildScrollView(
                  child: GamebaseFilterPanel(),
                ),
              ),
            ),

            // Moves Table
            Expanded(child: _buildContent(ref, gamebaseState, currentPosition)),
          ],
        );
      },
    );
  }

  Widget _buildContent(
    WidgetRef ref,
    GamebaseExplorerState gamebaseState,
    Position currentPosition,
  ) {
    if (gamebaseState.isLoading) {
      return const Center(child: CircularProgressIndicator(color: kWhiteColor));
    }

    // While the overlay is mounting, there is a brief moment where the provider
    // has no FEN set yet. Avoid showing a "blank table" flash.
    if (gamebaseState.currentFen.trim().isEmpty) {
      return const _GamebaseEmptyState(
        icon: Icons.menu_book_rounded,
        title: 'Loading position…',
        subtitle: 'Fetching database moves for this position.',
      );
    }

    if (gamebaseState.error != null) {
      return Center(
        child: _GamebaseEmptyState(
          icon: Icons.wifi_off_rounded,
          title: 'Could not load database moves',
          subtitle: 'Check your connection and try again.',
          primaryAction: _GamebaseEmptyStateAction(
            label: 'Retry',
            icon: Icons.refresh_rounded,
            onPressed: () => ref.read(gamebaseExplorerProvider.notifier).refresh(),
          ),
        ),
      );
    }

    if (gamebaseState.moveAggregates.isEmpty) {
      return Center(
        child: _GamebaseEmptyState(
          icon: Icons.travel_explore_rounded,
          title: 'No database games for this position',
          subtitle:
              gamebaseState.hasActiveFilters
                  ? 'Try clearing filters or go back a move.'
                  : 'Try going back a move or explore a different line.',
          primaryAction:
              gamebaseState.hasActiveFilters
                  ? _GamebaseEmptyStateAction(
                    label: 'Clear filters',
                    icon: Icons.filter_alt_off_rounded,
                    onPressed:
                        () =>
                            ref
                                .read(gamebaseExplorerProvider.notifier)
                                .clearFilters(),
                  )
                  : _GamebaseEmptyStateAction(
                    label: 'Refresh',
                    icon: Icons.refresh_rounded,
                    onPressed:
                        () =>
                            ref
                                .read(gamebaseExplorerProvider.notifier)
                                .refresh(),
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
      onGameSelected: onGameSelected,
      currentPosition: currentPosition,
    );
  }
}

class _HorizontalPvLines extends StatelessWidget {
  const _HorizontalPvLines({
    required this.state,
    required this.onMoveSelected,
  });

  final ChessBoardStateNew state;
  final Function(String uci) onMoveSelected;

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

          final firstUci =
              line.moves.isNotEmpty ? line.moves.first.uci : null;

          return InkWell(
            onTap:
                firstUci == null
                    ? null
                    : () => onMoveSelected(firstUci),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 2.h),
                child: Row(
                  children: [
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: 6.w,
                        vertical: 2.h,
                      ),
                      decoration: BoxDecoration(
                        color: kWhiteColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4.br),
                      ),
                      child: Text(
                        eval,
                        style: AppTypography.textXsBold.copyWith(
                          color: kWhiteColor,
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
              ),
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
    required this.onGameSelected,
    required this.currentPosition,
  });

  final List<MoveAggregate> moves;
  final int totalGames;
  final Function(String uci) onMoveSelected;
  final void Function(String gameId)? onGameSelected;
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
                onOpenGame:
                    (move.gameId != null && onGameSelected != null)
                        ? () => onGameSelected!(move.gameId!)
                        : null,
                position: currentPosition,
              );
            },
          ),
        ),
      ],
    );
  }

  TextStyle get _headerStyle => AppTypography.textSmMedium.copyWith(
    color: kWhiteColor.withValues(alpha: 0.5),
  );
}

class _GamebaseEmptyStateAction {
  const _GamebaseEmptyStateAction({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;
}

class _GamebaseEmptyState extends StatelessWidget {
  const _GamebaseEmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.primaryAction,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final _GamebaseEmptyStateAction? primaryAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 20.w),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: EdgeInsets.all(14.sp),
            decoration: BoxDecoration(
              color: kWhiteColor.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(14.br),
              border: Border.all(color: kWhiteColor.withValues(alpha: 0.10)),
            ),
            child: Icon(
              icon,
              size: 22.sp,
              color: kWhiteColor.withValues(alpha: 0.85),
            ),
          ),
          SizedBox(height: 12.h),
          Text(
            title,
            textAlign: TextAlign.center,
            style: AppTypography.textSmBold.copyWith(color: kWhiteColor),
          ),
          SizedBox(height: 6.h),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: AppTypography.textSmRegular.copyWith(
              color: kWhiteColor.withValues(alpha: 0.6),
            ),
          ),
          if (primaryAction != null) ...[
            SizedBox(height: 14.h),
            TextButton.icon(
              onPressed: primaryAction!.onPressed,
              icon: Icon(
                primaryAction!.icon,
                size: 18.sp,
                color: kWhiteColor,
              ),
              label: Text(
                primaryAction!.label,
                style: AppTypography.textSmMedium.copyWith(color: kWhiteColor),
              ),
              style: TextButton.styleFrom(
                backgroundColor: kWhiteColor.withValues(alpha: 0.08),
                padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 10.h),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12.br),
                  side: BorderSide(
                    color: kWhiteColor.withValues(alpha: 0.12),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MoveRow extends ConsumerWidget {
  const _MoveRow({
    required this.move,
    required this.maxTotal,
    required this.onPressed,
    required this.onOpenGame,
    required this.position,
  });

  final MoveAggregate move;
  final int maxTotal;
  final VoidCallback onPressed;
  final VoidCallback? onOpenGame;
  final Position position;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Calculate percentages
    final total = move.total;
    final whitePct = (move.white / total * 100).round();
    final drawPct = (move.draws / total * 100).round();

    final lastPlayedAsync =
        move.gameId != null
            ? ref.watch(gamePreviewByIdProvider(move.gameId!))
            : const AsyncValue<Map<String, dynamic>?>.data(null);

    final lastPlayedText = lastPlayedAsync.when(
      data: (row) {
        final raw = row?['date']?.toString();
        final date = raw != null ? DateTime.tryParse(raw) : null;
        return date != null ? DateFormat('MM-yyyy').format(date) : '—';
      },
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
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '${whitePct + drawPct}%',
                      style: AppTypography.textXsMedium.copyWith(
                        color: kWhiteColor.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
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
            if (onOpenGame != null) ...[
              SizedBox(width: 10.w),
              GestureDetector(
                onTap: onOpenGame,
                behavior: HitTestBehavior.opaque,
                child: Container(
                  padding: EdgeInsets.all(6.sp),
                  decoration: BoxDecoration(
                    color: kWhiteColor.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8.br),
                    border: Border.all(
                      color: kWhiteColor.withValues(alpha: 0.10),
                    ),
                  ),
                  child: Icon(
                    Icons.open_in_new_rounded,
                    size: 16.sp,
                    color: kWhiteColor.withValues(alpha: 0.8),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
