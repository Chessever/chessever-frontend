import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/discovery_dot.dart';
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
    this.onLongPress,
    this.dotId,
    super.key,
  });

  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final String svgIcon;
  final String title;
  final double width;
  final IconData? icon;

  /// Discovery-dot anchor id, so the admin console can point at this tab.
  final String? dotId;

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
        onLongPress: widget.onLongPress,
        onLongPressHint: widget.onLongPress == null
            ? null
            : 'Make ${widget.title} the start screen',
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
            onLongPress: widget.onLongPress,
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
                  child: DiscoveryDotAnchor(
                    id: widget.dotId,
                    selected: widget.isSelected,
                    alignment: Alignment.center,
                    // Off the icon's top-right shoulder, clear of the glyph.
                    offset: Offset(iconSide / 2 + 3, -(iconSide / 2 + 3)),
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
      ),
    );
  }
}
