import 'package:chessever2/screens/for_you/discovery/models/report_game_type.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/home_top_bar.dart';
import 'package:flutter/material.dart';

/// One content-sized row, using the same rounded marks as the Reports header.
/// The marks are bare, with no secondary tile or independent accent palette.
class ReportTypeChips extends StatelessWidget {
  const ReportTypeChips({
    super.key,
    required this.selected,
    required this.onSelected,
  });
  final ReportGameType? selected;
  final ValueChanged<ReportGameType?> onSelected;

  static IconData iconFor(ReportGameType? type) => switch (type) {
    null => Icons.assessment_rounded,
    ReportGameType.upsideDown => Icons.swap_vert_rounded,
    ReportGameType.comeback => Icons.u_turn_right_rounded,
    ReportGameType.oneBlunder => Icons.priority_high_rounded,
    ReportGameType.greatEscape => Icons.directions_run_rounded,
    ReportGameType.domination => Icons.castle_rounded,
    ReportGameType.squeeze => Icons.compress_rounded,
    ReportGameType.deadlock => Icons.balance_rounded,
    ReportGameType.miniature => Icons.bolt_rounded,
    ReportGameType.marathon => Icons.route_rounded,
  };

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    primary: false,
    padding: EdgeInsets.symmetric(
      horizontal: HomeTopBarMetrics.horizontalPadding,
    ),
    child: Row(
      children: [
        for (final type in <ReportGameType?>[
          null,
          ...ReportGameType.values,
        ]) ...[
          if (type != null) SizedBox(width: 8.w),
          Tooltip(
            message:
                type?.description ??
                'Every saved report, including unclassified games.',
            child: ChoiceChip(
              key: ValueKey('report_type_${type?.key ?? 'all'}'),
              selected: selected == type,
              // Tapping the active type again clears it back to All.
              onSelected: (_) => onSelected(selected == type ? null : type),
              showCheckmark: false,
              avatar: Icon(
                iconFor(type),
                size: 20.ic,
                color: selected == type
                    ? context.colors.background
                    : context.colors.textPrimary,
              ),
              label: Text(type?.label ?? 'All', softWrap: false),
              labelStyle: AppTypography.textSmMedium.copyWith(
                color: selected == type
                    ? context.colors.background
                    : context.colors.textPrimary,
              ),
              selectedColor: context.colors.textPrimary,
              backgroundColor: context.colors.surfaceRecessed,
              surfaceTintColor: Colors.transparent,
              elevation: 0,
              pressElevation: 0,
              side: BorderSide.none,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8.br),
              ),
              padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 8.h),
              materialTapTargetSize: MaterialTapTargetSize.padded,
              visualDensity: VisualDensity.standard,
            ),
          ),
        ],
      ],
    ),
  );
}
