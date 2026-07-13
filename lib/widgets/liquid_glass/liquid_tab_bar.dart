import 'dart:ui' show lerpDouble;

import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/widgets/liquid_glass/glass_motion.dart';
import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:motor/motor.dart';

const Color _kGlassTint = Color(0x992A2A2E);

/// One cell in a [_MorphBar].
class _Cell {
  const _Cell({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
    this.keyId,
  });

  final String label;
  final IconData? icon;
  final bool selected;
  final VoidCallback onTap;
  final Key? keyId;
}

/// The shared union/dismantle bar.
///
/// It is ONE glass container (a single [GlassContainer] — never a stack of
/// per-chip glass layers, which render black / vanish when composited on
/// Impeller). At rest the cells sit tight with thin separators between them, so
/// it reads as a single united bar. As [separated] flips true the gaps open,
/// the separators fade, and each icon reveals — a continuous motor animation,
/// so it visibly loosens on scroll-down and re-tightens on scroll-up.
class _MorphBar extends StatelessWidget {
  const _MorphBar({
    required this.cells,
    required this.separated,
    this.height = 40,
  });

  final List<_Cell> cells;
  final bool separated;
  final double height;

  @override
  Widget build(BuildContext context) {
    if (cells.isEmpty) return const SizedBox.shrink();

    return SingleMotionBuilder(
      motion: separated ? GlassMotion.widen : GlassMotion.collapse,
      value: separated ? 1.0 : 0.0,
      builder: (context, raw, _) {
        final t = raw.clamp(0.0, 1.0);
        final gap = lerpDouble(2.0, 10.0, t)!;
        final radius = lerpDouble(14.0, 18.0, t)!;

        final rowChildren = <Widget>[];
        for (var i = 0; i < cells.length; i++) {
          if (i > 0) {
            // Plain gap between cells — no separator line. (A 1px divider here
            // read as an ugly black hairline between the glued tabs.)
            rowChildren.add(SizedBox(width: gap, height: height));
          }
          rowChildren.add(
            _MorphCell(
              cell: cells[i],
              reveal: t,
              radius: radius - 4,
              height: height,
            ),
          );
        }

        // ONE glass surface for the whole bar — robust on every renderer.
        return GlassContainer(
          useOwnLayer: true,
          height: height,
          shape: LiquidRoundedSuperellipse(borderRadius: radius),
          settings: const LiquidGlassSettings(
            glassColor: _kGlassTint,
            thickness: 16,
            blur: 12,
            lightIntensity: 0,
            ambientStrength: 0,
            glowIntensity: 0,
            ambientRim: 0,
            chromaticAberration: 0,
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: rowChildren),
        );
      },
    );
  }
}

class _MorphCell extends StatelessWidget {
  const _MorphCell({
    required this.cell,
    required this.reveal,
    required this.radius,
    required this.height,
  });

  final _Cell cell;
  final double reveal;
  final double radius;
  final double height;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final selected = cell.selected;
    final fg = selected ? colors.textPrimary : colors.tabInactive;

    Widget content = DecoratedBox(
      // Brand bubble behind the selected cell (a plain color, not glass).
      decoration: BoxDecoration(
        color:
            selected ? colors.brand.withValues(alpha: 0.30) : Colors.transparent,
        borderRadius: BorderRadius.circular(radius.clamp(0.0, height / 2)),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: lerpDouble(12, 14, reveal)!,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (cell.icon != null)
              ClipRect(
                child: Align(
                  alignment: Alignment.centerLeft,
                  widthFactor: reveal,
                  child: Opacity(
                    opacity: reveal,
                    child: Padding(
                      padding: EdgeInsets.only(right: 6 * reveal),
                      child: Icon(cell.icon, size: 15, color: fg),
                    ),
                  ),
                ),
              ),
            Text(
              cell.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: fg,
                fontSize: 13,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );

    Widget cellWidget = GestureDetector(
      onTap: cell.onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(height: height, child: Center(child: content)),
    );

    if (cell.keyId != null) {
      cellWidget = KeyedSubtree(key: cell.keyId, child: cellWidget);
    }
    return cellWidget;
  }
}

/// Liquid-glass mode tabs. One glass bar (titles + separators) at the top of the
/// list; on scroll-down the cells loosen (gaps open, icons reveal).
class LiquidTabBar extends StatelessWidget {
  const LiquidTabBar({
    super.key,
    required this.options,
    required this.selectedIndex,
    required this.onSelected,
    required this.separated,
    this.icons,
    this.height = 40,
  });

  final List<String> options;
  final List<IconData>? icons;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final bool separated;
  final double height;

  @override
  Widget build(BuildContext context) {
    return _MorphBar(
      separated: separated,
      height: height,
      cells: [
        for (var i = 0; i < options.length; i++)
          _Cell(
            label: options[i],
            icon: (icons != null && i < icons!.length) ? icons![i] : null,
            selected: i == selectedIndex,
            onTap: () => onSelected(i),
          ),
      ],
    );
  }
}

/// Liquid-glass ACTION chips (icon + text) in one glass bar; each cell fires its
/// own action instead of selecting a tab.
class LiquidActionBar extends StatelessWidget {
  const LiquidActionBar({
    super.key,
    required this.actions,
    required this.separated,
    this.height = 40,
  });

  final List<LiquidAction> actions;
  final bool separated;
  final double height;

  @override
  Widget build(BuildContext context) {
    return _MorphBar(
      separated: separated,
      height: height,
      cells: [
        for (final a in actions)
          _Cell(
            label: a.label,
            icon: a.icon,
            selected: a.highlighted,
            onTap: a.onTap,
            keyId: a.keyId,
          ),
      ],
    );
  }
}

/// One action in a [LiquidActionBar].
class LiquidAction {
  const LiquidAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.highlighted = false,
    this.keyId,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool highlighted;
  final Key? keyId;
}
