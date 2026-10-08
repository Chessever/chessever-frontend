import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';

/// The adaptive choice chips used by the player-profile Games filter dialog.
class GameFilterChoiceChips<T> extends StatelessWidget {
  const GameFilterChoiceChips({
    super.key,
    required this.values,
    required this.selected,
    required this.label,
    required this.onTap,
    this.isEnabled,
  });
  final List<T> values;
  final T selected;
  final String Function(T) label;
  final ValueChanged<T> onTap;
  final bool Function(T)? isEnabled;

  @override
  Widget build(BuildContext context) {
    return _adaptiveChipLayout(
      measureLabels: values.map(label).toList(),
      chipsBuilder: (expanded) => values.map((v) {
        final isSelected = v == selected;
        final enabled = isEnabled?.call(v) ?? true;
        return Semantics(
          button: true,
          enabled: enabled,
          selected: isSelected,
          child: GestureDetector(
            onTap: enabled ? () => onTap(v) : null,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              constraints: const BoxConstraints(minHeight: 44),
              padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 10.h),
              // Equal-width grid cells center their label; row chips
              // hug their content as before.
              alignment: expanded ? Alignment.center : null,
              decoration: BoxDecoration(
                color: isSelected
                    ? kPrimaryColor
                    : context.colors.surfaceRecessed,
                borderRadius: BorderRadius.circular(8.br),
              ),
              child: Text(
                label(v),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.textXsMedium.copyWith(
                  color: isSelected
                      ? kBlackColor
                      : enabled
                      ? context.colors.textPrimary
                      : context.colors.textSecondary,
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _adaptiveChipLayout({
    required List<String> measureLabels,
    required List<Widget> Function(bool expanded) chipsBuilder,
    double extraPerChip = 0,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final textScaler = MediaQuery.textScalerOf(context);
        var total = 8.w * (measureLabels.length - 1);
        double widest = 0;
        for (final label in measureLabels) {
          final painter = TextPainter(
            text: TextSpan(text: label, style: AppTypography.textXsMedium),
            textDirection: TextDirection.ltr,
            textScaler: textScaler,
          )..layout();
          final width = painter.width + 28.w + extraPerChip;
          total += width;
          if (width > widest) widest = width;
        }

        if (total <= constraints.maxWidth) {
          return Wrap(
            spacing: 8.w,
            runSpacing: 8.h,
            children: chipsBuilder(false),
          );
        }

        final chips = chipsBuilder(true);
        if (widest > (constraints.maxWidth - 8.w) / 2) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < chips.length; i++) ...[
                if (i > 0) SizedBox(height: 8.h),
                chips[i],
              ],
            ],
          );
        }
        return Column(
          children: [
            for (var i = 0; i < chips.length; i += 2) ...[
              if (i > 0) SizedBox(height: 8.h),
              Row(
                children: [
                  Expanded(child: chips[i]),
                  SizedBox(width: 8.w),
                  Expanded(
                    child: i + 1 < chips.length
                        ? chips[i + 1]
                        : const SizedBox.shrink(),
                  ),
                ],
              ),
            ],
          ],
        );
      },
    );
  }
}
