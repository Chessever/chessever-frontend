import 'dart:async';

import 'package:chessever2/screens/home/start_screen.dart';
import 'package:chessever2/screens/home/widget/bottom_nav_bar.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/widgets/discovery_dot.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:motor/motor.dart';

/// The tablet's navigation rail: the phone dock's sections in the dock's
/// order (Home, Events, Botvinnik, Feed, Profile; no Botvinnik when it is
/// switched off), stood on end, each with its name under its mark.
class TabletNavRail extends ConsumerWidget {
  const TabletNavRail({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedItem = ref.watch(selectedBottomNavBarItemProvider);
    final items = ref.watch(visibleBottomNavItemsProvider);

    final isLandscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    final railWidth = isLandscape ? 110.0 : 90.0;

    return Container(
      width: railWidth,
      color: context.colors.background,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(top: 16.0),
          child: SingleChildScrollView(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                for (final item in items)
                  _NavRailItem(
                    key: bottomNavBarItemKey(item),
                    item: item,
                    isSelected: selectedItem == item,
                    onLongPress: () => unawaited(
                      makeStartScreenDefault(context, ref, section: item),
                    ),
                    onTap: () => selectBottomNavBarItem(
                      ref,
                      item,
                      navigationType: 'rail',
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One rail slot, in the phone bar's language: the selected slot in full ink
/// with a heavier label, the rest in secondary ink (both clear 4.5:1 on the
/// rail in either theme). A press settles the slot to 0.97 on a spring and
/// lets go the same way; reduced motion snaps instead.
class _NavRailItem extends StatefulWidget {
  final BottomNavBarItem item;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const _NavRailItem({
    super.key,
    required this.item,
    required this.isSelected,
    required this.onTap,
    this.onLongPress,
  });

  @override
  State<_NavRailItem> createState() => _NavRailItemState();
}

class _NavRailItemState extends State<_NavRailItem> {
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
    final title = namesBottomNavBarIcons[widget.item]!;

    final roomyRail =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    final iconSize = roomyRail ? 28.0 : 24.0;
    final colors = context.colors;
    final ink = widget.isSelected ? colors.textPrimary : colors.textSecondary;
    final verticalPadding = roomyRail ? 16.0 : 12.0;

    return MergeSemantics(
      child: Semantics(
        button: true,
        selected: widget.isSelected,
        onLongPress: widget.onLongPress,
        child: GestureDetector(
          onTapDown: (_) => _setPressed(true),
          onTapUp: (_) => _setPressed(false),
          onTapCancel: () => _setPressed(false),
          onTap: widget.onTap,
          onLongPress: widget.onLongPress,
          behavior: HitTestBehavior.opaque,
          child: DiscoveryDotAnchor(
            id: bottomNavBarDotIds[widget.item],
            selected: widget.isSelected,
            alignment: Alignment.topCenter,
            // Off the icon's top-right shoulder, clear of the glyph.
            offset: Offset(iconSize / 2 + 3, verticalPadding + 4),
            child: Container(
              width: double.infinity,
              padding: EdgeInsets.symmetric(
                vertical: verticalPadding,
                horizontal: 8.0,
              ),
              child: SingleMotionBuilder(
                motion: _press,
                value: _pressed ? 0.97 : 1.0,
                active: !MediaQuery.disableAnimationsOf(context),
                builder: (context, scale, child) =>
                    Transform.scale(scale: scale, child: child),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8.0),
                      child: bottomNavBarGlyph(
                        widget.item,
                        ink: ink,
                        side: iconSize,
                        selected: widget.isSelected,
                      ),
                    ),
                    const SizedBox(height: 4.0),
                    // Label
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 11.0,
                        fontWeight: widget.isSelected
                            ? FontWeight.w600
                            : FontWeight.w400,
                        color: ink,
                      ),
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
