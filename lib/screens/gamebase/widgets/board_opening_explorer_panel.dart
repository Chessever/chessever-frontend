import 'package:chessever2/screens/chessboard/view_model/chess_board_state_new.dart';
import 'package:chessever2/screens/gamebase/providers/gamebase_providers.dart';
import 'package:chessever2/screens/gamebase/widgets/move_statistics_panel.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Opening explorer panel for the chess board screen's swipeable bottom area.
///
/// Mirrors the bottom-panel page 0 of the standalone gamebase explorer
/// screen (`MoveStatisticsPanel` — the table with figurine moves, win/draw/
/// loss bar, game count, list-icon → games bottom sheet, last-played date)
/// so the two contexts stay visually identical.
///
/// The wrapper is responsible for pumping the chess board's current FEN +
/// playline into `gamebaseExplorerProvider` so the table reflects the user's
/// position, and for routing taps back into the chess board's analysis state
/// instead of advancing the explorer's standalone exploration cursor.
class BoardOpeningExplorerPanel extends HookConsumerWidget {
  const BoardOpeningExplorerPanel({
    super.key,
    required this.state,
    required this.onMoveSelected,
  });

  final ChessBoardStateNew state;
  final void Function(String uci) onMoveSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentPosition = state.analysisState.position;
    final currentFen = currentPosition.fen;
    final startingFen = state.analysisState.startingPosition?.fen;
    final combinedMoves = state.analysisState.combinedMoves;
    final currentMoveIndex = state.analysisState.currentMoveIndex;
    final movesToCurrentCount = currentMoveIndex < 0
        ? 0
        : (currentMoveIndex + 1).clamp(0, combinedMoves.length);
    final lineToCurrent = combinedMoves
        .take(movesToCurrentCount)
        .map((m) => m.uci.trim().toLowerCase())
        .where((uci) => RegExp(r'^[a-h][1-8][a-h][1-8][qrbn]?$').hasMatch(uci))
        .toList(growable: false);
    final lineKey = lineToCurrent.join(' ');

    useEffect(() {
      Future.microtask(() {
        ref
            .read(gamebaseExplorerProvider.notifier)
            .setPositionWithMoves(
              currentFen,
              lineToCurrent,
              startingFen: startingFen,
            );
      });
      return null;
    }, [currentFen, lineKey, startingFen]);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _InlineFormatChips(),
        Expanded(child: MoveStatisticsPanel(onMove: onMoveSelected)),
      ],
    );
  }
}

/// Compact Online / OTB toggle row for the board-level explorer panel.
///
/// The full `GamebaseFilterPanel` (with time control, rating range, etc.)
/// is suppressed in this context because the swipeable bottom area is
/// short on vertical space. Format is the one filter that's genuinely
/// useful here — flipping between OTB and Online repertoires is a
/// common mid-analysis action — so we expose just those two chips.
/// Tapping the currently-selected chip clears back to "all formats",
/// matching the behavior of the standalone filter panel's
/// `_FormatChips` / `toggleFormat` handler.
class _InlineFormatChips extends ConsumerWidget {
  const _InlineFormatChips();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedIsOnline = ref.watch(
      gamebaseExplorerProvider.select((s) => s.filters.isOnline),
    );

    return Padding(
      padding: EdgeInsets.fromLTRB(12.sp, 6.sp, 12.sp, 4.sp),
      child: Row(
        children: [
          _InlineFormatChip(
            label: 'OTB',
            icon: Icons.location_on_outlined,
            isSelected: selectedIsOnline == false,
            onTap: () {
              ref.read(gamebaseExplorerProvider.notifier).toggleFormat(false);
            },
          ),
          SizedBox(width: 6.w),
          _InlineFormatChip(
            label: 'Online',
            icon: Icons.language_rounded,
            isSelected: selectedIsOnline == true,
            onTap: () {
              ref.read(gamebaseExplorerProvider.notifier).toggleFormat(true);
            },
          ),
        ],
      ),
    );
  }
}

class _InlineFormatChip extends StatelessWidget {
  const _InlineFormatChip({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 5.h),
        decoration: BoxDecoration(
          color: isSelected ? kWhiteColor.withOpacity(0.12) : kBlack3Color,
          borderRadius: BorderRadius.circular(6.br),
          border: Border.all(
            color:
                isSelected ? kWhiteColor.withOpacity(0.25) : Colors.transparent,
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 13.sp,
              color: isSelected ? kWhiteColor : kSecondaryTextColor,
            ),
            SizedBox(width: 4.w),
            Text(
              label,
              style: AppTypography.textXsMedium.copyWith(color: kWhiteColor),
            ),
          ],
        ),
      ),
    );
  }
}
