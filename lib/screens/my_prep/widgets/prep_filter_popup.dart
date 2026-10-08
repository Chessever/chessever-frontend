import 'dart:math' as math;

import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';

/// A single, accessible entry point for filters in Games and Build Tree.
class PrepFilterButton extends StatelessWidget {
  const PrepFilterButton({
    super.key,
    required this.active,
    this.tooltip = 'Filter and sort games',
    required this.onPressed,
  });
  final bool active;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: tooltip,
    onPressed: onPressed,
    constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
    icon: Badge(
      isLabelVisible: active,
      backgroundColor: context.colors.brand,
      child: Icon(
        Icons.tune_rounded,
        color: active ? context.colors.accentText : context.colors.iconPrimary,
      ),
    ),
  );
}

/// Shared popup surface, scrollable fields and fixed actions for prep filters.
class PrepFilterPopup extends StatelessWidget {
  const PrepFilterPopup({
    super.key,
    required this.title,
    required this.children,
    required this.onReset,
    required this.onApply,
  });
  final String title;
  final List<Widget> children;
  final VoidCallback onReset;
  final VoidCallback onApply;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final availableHeight =
        MediaQuery.sizeOf(context).height -
        MediaQuery.paddingOf(context).vertical -
        32;
    return Container(
      width: 320.w,
      constraints: BoxConstraints(maxHeight: math.min(640.h, availableHeight)),
      child: Material(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16.br),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(20.w, 12.h, 12.w, 4.h),
              child: Row(
                children: [
                  Expanded(child: Text(title, style: AppTypography.textMdBold)),
                  IconButton(
                    tooltip: 'Close filters',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(
                      Icons.close_rounded,
                      color: colors.iconSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 8.h),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: children,
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.all(16.sp),
              child: Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: onReset,
                      style: TextButton.styleFrom(
                        minimumSize: const Size(0, 48),
                      ),
                      child: Text('Reset', style: AppTypography.textSmMedium),
                    ),
                  ),
                  SizedBox(width: 12.w),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: colors.brand,
                        foregroundColor: colors.inkOnAccent,
                        elevation: 0,
                        minimumSize: const Size(0, 48),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10.br),
                        ),
                      ),
                      onPressed: onApply,
                      child: Text(
                        'Apply',
                        style: AppTypography.textSmMedium.copyWith(
                          color: colors.inkOnAccent,
                        ),
                      ),
                    ),
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

class PrepFilterSelect<T> extends StatelessWidget {
  const PrepFilterSelect({
    super.key,
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });
  final String label;
  final T value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: 16.h),
    child: Container(
      padding: EdgeInsets.symmetric(horizontal: 12.w),
      decoration: BoxDecoration(
        color: context.colors.surfaceRecessed,
        borderRadius: BorderRadius.circular(10.br),
      ),
      child: Semantics(
        label: label,
        child: DropdownButtonHideUnderline(
          child: DropdownButton<T>(
            value: value,
            items: items,
            isExpanded: true,
            itemHeight: null,
            style: AppTypography.textSmRegular.copyWith(
              color: context.colors.textPrimary,
            ),
            dropdownColor: context.colors.surfaceElevated,
            onChanged: (value) {
              if (value != null) onChanged(value);
            },
          ),
        ),
      ),
    ),
  );
}
