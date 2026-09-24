import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/svg_widget.dart';
import 'package:flutter/material.dart';
import 'package:motor/motor.dart';

/// One slot of the phone bottom bar: icon over label, the selected slot in
/// full ink and a bold label, the rest in secondary ink at medium weight (both
/// inks clear 4.5:1 on the bar in either theme). Ink alone is only 2.6:1
/// between the two states in light mode, so the weight step is what marks the
/// active slot there, not colour. A press settles the slot to 0.97 on a spring
/// and lets go the same way; reduced motion snaps instead.
class BottomNavBarWidget extends StatefulWidget {
  const BottomNavBarWidget({
    required this.isSelected,
    required this.onTap,
    required this.svgIcon,
    required this.title,
    required this.width,
    super.key,
  });

  final bool isSelected;
  final VoidCallback onTap;
  final String svgIcon;
  final String title;
  final double width;

  @override
  State<BottomNavBarWidget> createState() => _BottomNavBarWidgetState();
}

class _BottomNavBarWidgetState extends State<BottomNavBarWidget> {
  static const _press = CupertinoMotion.snappy(
    duration: Duration(milliseconds: 260),
  );

  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final ink = widget.isSelected ? colors.textPrimary : colors.textSecondary;
    // Square on every phone: `20.h` by `20.w` went 15 by 18 on short ones.
    final iconSide = 20.ic.clamp(18.0, 24.0);

    return MergeSemantics(
      child: Semantics(
        button: true,
        selected: widget.isSelected,
        child: InkWell(
          splashColor: colors.surfaceRecessed,
          highlightColor: Colors.transparent,
          onTapDown: (_) => _setPressed(true),
          onTapUp: (_) => _setPressed(false),
          onTapCancel: () => _setPressed(false),
          onTap: widget.onTap,
          child: SizedBox(
            width: widget.width,
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 8.sp),
              child: SingleMotionBuilder(
                motion: _press,
                value: _pressed ? 0.97 : 1.0,
                active: !MediaQuery.disableAnimationsOf(context),
                builder:
                    (context, scale, child) =>
                        Transform.scale(scale: scale, child: child),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SvgWidget(
                      widget.svgIcon,
                      height: iconSide,
                      width: iconSide,
                      colorFilter: ColorFilter.mode(ink, BlendMode.srcIn),
                    ),
                    SizedBox(height: 4.h),
                    Text(
                      widget.title,
                      textAlign: TextAlign.center,
                      // Same size and line height in both styles, so the
                      // weight step never moves the label.
                      style:
                          (widget.isSelected
                                  ? AppTypography.textXsBold
                                  : AppTypography.textXsMedium)
                              .copyWith(color: ink),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
