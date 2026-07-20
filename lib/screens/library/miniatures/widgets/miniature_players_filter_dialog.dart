import 'package:chessever2/repository/gamebase/miniatures/miniatures_models.dart';
import 'package:chessever2/screens/library/providers/miniatures_provider.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/alert_dialog/alert_modal.dart';
import 'package:flutter/material.dart';

/// Filter + sort dialog for the Miniatures Players tab: title chips (GM / IM /
/// FM) and a sort picker, behind the single filter icon next to the search
/// field — the same shape as the Games tab dialog and the Favorites /
/// Countrymen games tabs. No separate dropdown chip, no bottom sheet.
Future<MiniaturePlayersQuery?> showMiniaturePlayersFilterDialog({
  required BuildContext context,
  required MiniaturePlayersQuery currentQuery,
}) {
  return showAlertModal<MiniaturePlayersQuery>(
    context: context,
    horizontalPadding: 0,
    child: MiniaturePlayersFilterDialog(initialQuery: currentQuery),
  );
}

class MiniaturePlayersFilterDialog extends StatefulWidget {
  const MiniaturePlayersFilterDialog({super.key, required this.initialQuery});

  final MiniaturePlayersQuery initialQuery;

  @override
  State<MiniaturePlayersFilterDialog> createState() =>
      _MiniaturePlayersFilterDialogState();
}

class _MiniaturePlayersFilterDialogState
    extends State<MiniaturePlayersFilterDialog> {
  late MiniaturePlayerSort _sort;
  late Set<MiniaturePlayerTitle> _titles;

  @override
  void initState() {
    super.initState();
    _sort = widget.initialQuery.sort;
    _titles = Set<MiniaturePlayerTitle>.of(widget.initialQuery.titles);
  }

  void _toggleTitle(MiniaturePlayerTitle title) {
    HapticFeedbackService.selection();
    setState(() {
      if (!_titles.remove(title)) _titles.add(title);
    });
  }

  @override
  Widget build(BuildContext context) {
    final dialogWidth = 320.w;
    return Container(
      width: dialogWidth,
      constraints: BoxConstraints(maxHeight: 480.h),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(16.br),
        border: Border.all(
          color: context.colors.textPrimary.withValues(alpha: 0.1),
          width: 1,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildHeader(),
          Flexible(
            child: SingleChildScrollView(
              padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 8.h),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _sectionLabel('Sort'),
                  SizedBox(height: 8.h),
                  _chipGrid<MiniaturePlayerSort>(
                    values: MiniaturePlayerSort.values,
                    selected: _sort,
                    label: (v) => v.label,
                    onTap: (v) {
                      HapticFeedbackService.selection();
                      setState(() => _sort = v);
                    },
                  ),
                  SizedBox(height: 20.h),

                  _sectionLabel('Title'),
                  SizedBox(height: 8.h),
                  Wrap(
                    spacing: 8.w,
                    runSpacing: 8.h,
                    children: [
                      for (final title in MiniaturePlayerTitle.values)
                        GestureDetector(
                          onTap: () => _toggleTitle(title),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            padding: EdgeInsets.symmetric(
                              horizontal: 14.w,
                              vertical: 10.h,
                            ),
                            decoration: BoxDecoration(
                              color:
                                  _titles.contains(title)
                                      ? kPrimaryColor
                                      : context.colors.surfaceRecessed,
                              borderRadius: BorderRadius.circular(8.br),
                            ),
                            child: Text(
                              title.label,
                              style: AppTypography.textXsMedium.copyWith(
                                color:
                                    _titles.contains(title)
                                        ? kBlackColor
                                        : context.colors.textPrimary,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  SizedBox(height: 12.h),
                ],
              ),
            ),
          ),
          _buildButtons(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final activeChipWidgets = <Widget>[];

    Widget buildChip(String label, VoidCallback onRemove) {
      return GestureDetector(
        onTap: () {
          HapticFeedbackService.buttonPress();
          onRemove();
        },
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
          decoration: BoxDecoration(
            color: kPrimaryColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(4.br),
            border: Border.all(color: kPrimaryColor.withValues(alpha: 0.4)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: AppTypography.textXsMedium.copyWith(
                  color: kPrimaryColor,
                ),
              ),
              SizedBox(width: 4.w),
              Icon(Icons.close_rounded, color: kPrimaryColor, size: 14.ic),
            ],
          ),
        ),
      );
    }

    if (_sort != MiniaturePlayerSort.games) {
      activeChipWidgets.add(
        buildChip('Sort: ${_sort.label}', () {
          setState(() => _sort = MiniaturePlayerSort.games);
        }),
      );
    }
    for (final title in _titles) {
      activeChipWidgets.add(
        buildChip('Title: ${title.label}', () {
          setState(() => _titles.remove(title));
        }),
      );
    }

    return Padding(
      padding: EdgeInsets.fromLTRB(20.w, 18.h, 12.w, 6.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Filters',
                style: AppTypography.textMdBold.copyWith(
                  color: context.colors.textPrimary,
                ),
              ),
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: Icon(
                  Icons.close_rounded,
                  color: context.colors.textPrimary.withValues(alpha: 0.6),
                  size: 20.ic,
                ),
              ),
            ],
          ),
          if (activeChipWidgets.isNotEmpty) ...[
            SizedBox(height: 8.h),
            Wrap(spacing: 6.w, runSpacing: 6.h, children: activeChipWidgets),
            SizedBox(height: 4.h),
          ],
        ],
      ),
    );
  }

  Widget _buildButtons() {
    return Padding(
      padding: EdgeInsets.fromLTRB(20.w, 12.h, 20.w, 16.h),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () {
                HapticFeedbackService.buttonPress();
                Navigator.of(context).pop(
                  MiniaturePlayersQuery(search: widget.initialQuery.search),
                );
              },
              child: Container(
                height: 40.h,
                decoration: BoxDecoration(
                  color: context.colors.surface,
                  borderRadius: BorderRadius.circular(4.br),
                ),
                alignment: Alignment.center,
                child: Text(
                  'Reset',
                  style: AppTypography.textSmBold.copyWith(
                    color: context.colors.textPrimary,
                  ),
                ),
              ),
            ),
          ),
          SizedBox(width: 16.w),
          Expanded(
            child: GestureDetector(
              onTap: () {
                HapticFeedbackService.buttonPress();
                Navigator.of(context).pop(
                  MiniaturePlayersQuery(
                    titles: _titles,
                    sort: _sort,
                    search: widget.initialQuery.search,
                  ),
                );
              },
              child: Container(
                height: 40.h,
                decoration: BoxDecoration(
                  color: context.colors.textPrimary,
                  borderRadius: BorderRadius.circular(4.br),
                ),
                alignment: Alignment.center,
                child: Text(
                  'Apply Filters',
                  style: AppTypography.textSmBold.copyWith(
                    color: context.colors.textInverse,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Text(
      text,
      style: AppTypography.textSmMedium.copyWith(
        color: context.colors.textPrimary,
        letterSpacing: 0.3,
      ),
    );
  }

  Widget _chipGrid<T>({
    required List<T> values,
    required T selected,
    required String Function(T) label,
    required ValueChanged<T> onTap,
  }) {
    return Wrap(
      spacing: 8.w,
      runSpacing: 8.h,
      children:
          values.map((v) {
            final isSelected = v == selected;
            return GestureDetector(
              onTap: () => onTap(v),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 10.h),
                decoration: BoxDecoration(
                  color:
                      isSelected
                          ? kPrimaryColor
                          : context.colors.surfaceRecessed,
                  borderRadius: BorderRadius.circular(8.br),
                ),
                child: Text(
                  label(v),
                  style: AppTypography.textXsMedium.copyWith(
                    color:
                        isSelected ? kBlackColor : context.colors.textPrimary,
                  ),
                ),
              ),
            );
          }).toList(),
    );
  }
}
