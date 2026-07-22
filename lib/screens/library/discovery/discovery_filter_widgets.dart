import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A selectable pill used across the Discovery filter sheets.
class FilterPill extends StatelessWidget {
  const FilterPill({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
        decoration: BoxDecoration(
          color:
              selected
                  ? kPrimaryColor.withValues(alpha: 0.15)
                  : context.colors.textPrimary.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(20.br),
          border: Border.all(
            color:
                selected
                    ? kPrimaryColor.withValues(alpha: 0.45)
                    : context.colors.textPrimary.withValues(alpha: 0.1),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: 13.sp,
                color:
                    selected
                        ? kPrimaryColor
                        : context.colors.textPrimary.withValues(alpha: 0.55),
              ),
              SizedBox(width: 5.w),
            ],
            Text(
              label,
              style: AppTypography.textXsMedium.copyWith(
                color:
                    selected
                        ? kPrimaryColor
                        : context.colors.textPrimary.withValues(alpha: 0.75),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Any / Yes / No tri-state selector for nullable-bool filters.
class TriToggle extends StatelessWidget {
  const TriToggle({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool? value;
  final ValueChanged<bool?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: AppTypography.textSmMedium.copyWith(
              color: context.colors.textPrimary.withValues(alpha: 0.85),
            ),
          ),
        ),
        _seg('Any', value == null, () => onChanged(null)),
        SizedBox(width: 6.w),
        _seg('Yes', value == true, () => onChanged(true)),
        SizedBox(width: 6.w),
        _seg('No', value == false, () => onChanged(false)),
      ],
    );
  }

  Widget _seg(String text, bool selected, VoidCallback onTap) {
    return Builder(
      builder: (context) => GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
          decoration: BoxDecoration(
            color:
                selected
                    ? kPrimaryColor.withValues(alpha: 0.15)
                    : context.colors.textPrimary.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(8.br),
            border: Border.all(
              color:
                  selected
                      ? kPrimaryColor.withValues(alpha: 0.45)
                      : context.colors.textPrimary.withValues(alpha: 0.1),
            ),
          ),
          child: Text(
            text,
            style: AppTypography.textXsMedium.copyWith(
              color:
                  selected
                      ? kPrimaryColor
                      : context.colors.textPrimary.withValues(alpha: 0.7),
            ),
          ),
        ),
      ),
    );
  }
}

/// Labeled section wrapper for a group of filter pills.
class FilterSection extends StatelessWidget {
  const FilterSection({super.key, required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: AppTypography.textXsMedium.copyWith(
            color: context.colors.textPrimary.withValues(alpha: 0.5),
            letterSpacing: 0.4,
          ),
        ),
        SizedBox(height: 10.h),
        child,
      ],
    );
  }
}

/// Shared bottom-sheet shell: drag handle, title, scrollable body, and a
/// Clear / Apply footer.
class FilterSheetScaffold extends StatelessWidget {
  const FilterSheetScaffold({
    super.key,
    required this.title,
    required this.onClear,
    required this.onApply,
    required this.children,
  });

  final String title;
  final VoidCallback onClear;
  final VoidCallback onApply;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.8,
        ),
        decoration: BoxDecoration(
          color: context.colors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24.br)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: EdgeInsets.symmetric(vertical: 12.h),
              width: 40.w,
              height: 4.h,
              decoration: BoxDecoration(
                color: context.colors.textPrimary.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(2.br),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(20.w, 0, 20.w, 8.h),
              child: Row(
                children: [
                  Text(
                    title,
                    style: AppTypography.textMdBold.copyWith(
                      color: context.colors.textPrimary,
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: () {
                      HapticFeedback.lightImpact();
                      onClear();
                    },
                    child: Text(
                      'Clear',
                      style: AppTypography.textSmMedium.copyWith(
                        color: kRedColor.withValues(alpha: 0.9),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(20.w, 8.h, 20.w, 8.h),
                physics: const BouncingScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: children,
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(20.w, 8.h, 20.w, 16.h),
              child: GestureDetector(
                onTap: () {
                  HapticFeedback.mediumImpact();
                  onApply();
                },
                child: Container(
                  width: double.infinity,
                  padding: EdgeInsets.symmetric(vertical: 14.h),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        kPrimaryColor,
                        kPrimaryColor.withValues(alpha: 0.8),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(14.br),
                  ),
                  child: Center(
                    child: Text(
                      'Apply',
                      style: AppTypography.textSmBold.copyWith(
                        color: context.colors.textPrimary,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Small filter button with an active-count badge, used in the tab headers.
class FilterButton extends StatelessWidget {
  const FilterButton({super.key, required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final active = count > 0;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 7.h),
        decoration: BoxDecoration(
          color:
              active
                  ? kPrimaryColor.withValues(alpha: 0.14)
                  : context.colors.surface,
          borderRadius: BorderRadius.circular(20.br),
          border: Border.all(
            color:
                active
                    ? kPrimaryColor.withValues(alpha: 0.4)
                    : context.colors.textPrimary.withValues(alpha: 0.1),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.tune_rounded,
              size: 15.sp,
              color:
                  active
                      ? kPrimaryColor
                      : context.colors.textPrimary.withValues(alpha: 0.7),
            ),
            SizedBox(width: 6.w),
            Text(
              active ? 'Filters · $count' : 'Filters',
              style: AppTypography.textXsMedium.copyWith(
                color:
                    active
                        ? kPrimaryColor
                        : context.colors.textPrimary.withValues(alpha: 0.85),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
