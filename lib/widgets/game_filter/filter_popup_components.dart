import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:flutter/material.dart';

/// The Home filter popup's shared panel, spacing and Reset/Apply controls.
class FilterPopupFrame extends StatelessWidget {
  const FilterPopupFrame({
    super.key,
    required this.sections,
    required this.onReset,
    required this.onApply,
  });
  final List<Widget> sections;
  final VoidCallback onReset;
  final VoidCallback onApply;

  @override
  Widget build(BuildContext context) => Container(
    width: 280.w,
    constraints: BoxConstraints(maxHeight: 600.h),
    decoration: BoxDecoration(
      color: context.colors.surface,
      borderRadius: BorderRadius.circular(16.br),
      border: Border.all(
        color: context.colors.textPrimary.withValues(alpha: 0.1),
        width: 1,
      ),
    ),
    child: Material(
      type: MaterialType.transparency,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(20.w, 16.h, 20.w, 0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: sections,
              ),
            ),
            Padding(
              padding: EdgeInsets.all(20.sp),
              child: Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 48.h,
                      child: OutlinedButton(
                        onPressed: onReset,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: context.colors.textPrimary,
                          backgroundColor: context.colors.surface,
                          side: BorderSide.none,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10.br),
                          ),
                          padding: EdgeInsets.zero,
                        ),
                        child: Text(
                          'Reset',
                          style: AppTypography.textSmMedium.copyWith(
                            color: context.colors.textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: 12.w),
                  Expanded(
                    child: SizedBox(
                      height: 48.h,
                      child: ElevatedButton(
                        onPressed: onApply,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: kPrimaryColor,
                          foregroundColor: kBlackColor,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10.br),
                          ),
                          padding: EdgeInsets.zero,
                        ),
                        child: Text(
                          'Apply Filters',
                          style: AppTypography.textSmMedium,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
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
    ),
  );
}

class FilterSectionLabel extends StatelessWidget {
  const FilterSectionLabel(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Text(
    text,
    style: AppTypography.textSmMedium.copyWith(
      color: context.colors.textPrimary,
      letterSpacing: 0.3,
    ),
  );
}

/// Home's two-column selectable boxes, with a context-specific set of values.
class FilterChoiceGrid<T> extends StatelessWidget {
  const FilterChoiceGrid({
    super.key,
    required this.values,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });
  final List<T> values;
  final String Function(T) label;
  final bool Function(T) isSelected;
  final ValueChanged<T> onTap;
  @override
  Widget build(BuildContext context) => GridView.builder(
    shrinkWrap: true,
    padding: EdgeInsets.zero,
    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: 2,
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: 3,
    ),
    itemCount: values.length,
    itemBuilder: (context, index) {
      final value = values[index];
      final selected = isSelected(value);
      return Semantics(
        button: true,
        selected: selected,
        child: GestureDetector(
          onTap: () => onTap(value),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? kPrimaryColor : context.colors.surfaceRecessed,
              borderRadius: BorderRadius.circular(8.br),
            ),
            child: Text(
              label(value),
              style: AppTypography.textXsMedium.copyWith(
                color: selected ? kBlackColor : context.colors.textPrimary,
              ),
            ),
          ),
        ),
      );
    },
  );
}
