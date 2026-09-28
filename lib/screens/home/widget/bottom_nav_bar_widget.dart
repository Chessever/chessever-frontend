import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/svg_widget.dart';
import 'package:flutter/material.dart';
import 'package:motor/motor.dart';

/// An icon-only phone navigation target. Labels remain available to assistive
/// technology and through a tooltip, with reduced-motion-aware press feedback.
class BottomNavBarWidget extends StatefulWidget {
  const BottomNavBarWidget({
    required this.isSelected,
    required this.onTap,
    required this.svgIcon,
    required this.title,
    required this.width,
    this.icon,
    super.key,
  });

  final bool isSelected;
  final VoidCallback onTap;
  final String svgIcon;
  final String title;
  final double width;
  final IconData? icon;

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
        label: widget.title,
        child: Tooltip(
          message: widget.title,
          excludeFromSemantics: true,
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
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: SingleMotionBuilder(
                  motion: _press,
                  value: _pressed ? 0.97 : 1.0,
                  active: !MediaQuery.disableAnimationsOf(context),
                  builder: (context, scale, child) =>
                      Transform.scale(scale: scale, child: child),
                  child: SizedBox(
                    height: 44,
                    child: Center(
                      child: widget.icon != null
                          ? Icon(widget.icon, size: iconSide + 4, color: ink)
                          : SvgWidget(
                              widget.svgIcon,
                              height: iconSide,
                              width: iconSide,
                              colorFilter: ColorFilter.mode(
                                ink,
                                BlendMode.srcIn,
                              ),
                            ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
