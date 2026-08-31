import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';

enum ExplorerBoardMenuAction { copyPgn, boardSettings, share }

const int boardWorkspaceDefaultPage = 0;
const String boardWorkspaceViewsCoachmarkMessage =
    'One board, two views\nSwitch between Explorer and Notation anytime.';
const String boardWorkspaceEditorCoachmarkMessage =
    'Edit any position\nSet up a position, then continue here.';

class ExplorerBoardMenuItem {
  const ExplorerBoardMenuItem({
    required this.action,
    required this.label,
    required this.icon,
  });

  final ExplorerBoardMenuAction action;
  final String label;
  final IconData icon;
}

const explorerBoardMenuItems = <ExplorerBoardMenuItem>[
  ExplorerBoardMenuItem(
    action: ExplorerBoardMenuAction.copyPgn,
    label: 'Copy PGN',
    icon: Icons.copy_rounded,
  ),
  ExplorerBoardMenuItem(
    action: ExplorerBoardMenuAction.boardSettings,
    label: 'Board Settings',
    icon: Icons.settings_outlined,
  ),
  ExplorerBoardMenuItem(
    action: ExplorerBoardMenuAction.share,
    label: 'Share',
    icon: Icons.share_outlined,
  ),
];

class ExplorerBoardEditorIcon extends StatelessWidget {
  const ExplorerBoardEditorIcon({super.key});

  @override
  Widget build(BuildContext context) {
    // Material glyphs (save_outlined, more_vert at 22.ic) keep ~2-3px of
    // built-in padding inside their viewbox, so their drawn content reads at
    // ~18pt. The checkerboard paints full-bleed; matching the drawn area to
    // the neighbours' optical size keeps the three header icons even.
    return SizedBox(
      width: 24.ic,
      height: 24.ic,
      child: Stack(
        children: [
          Positioned(
            left: 2.5.ic,
            top: 2.5.ic,
            width: 17.ic,
            height: 17.ic,
            child: CustomPaint(
              key: const ValueKey<String>(
                'opening_explorer_editor_checkerboard',
              ),
              painter: _ExplorerCheckerboardPainter(
                color: context.colors.textPrimary,
              ),
            ),
          ),
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              padding: EdgeInsets.all(1.2.sp),
              decoration: BoxDecoration(
                color: context.colors.surface,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.edit_rounded, size: 9.ic),
            ),
          ),
        ],
      ),
    );
  }
}

class _ExplorerCheckerboardPainter extends CustomPainter {
  const _ExplorerCheckerboardPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final squareWidth = size.width / 8;
    final squareHeight = size.height / 8;
    final squarePaint = Paint()..color = color.withValues(alpha: 0.72);
    for (var rank = 0; rank < 8; rank++) {
      for (var file = 0; file < 8; file++) {
        if ((rank + file).isEven) continue;
        canvas.drawRect(
          Rect.fromLTWH(
            file * squareWidth,
            rank * squareHeight,
            squareWidth,
            squareHeight,
          ),
          squarePaint,
        );
      }
    }
    final borderPaint =
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2;
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(1.5)),
      borderPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _ExplorerCheckerboardPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

class ExplorerViewToggle extends StatelessWidget {
  const ExplorerViewToggle({
    required this.currentPage,
    required this.onSelected,
    this.compact = false,
    super.key,
  });

  final int currentPage;
  final ValueChanged<int> onSelected;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Board workspace view',
      child: Container(
        height: compact ? 34.sp : 38.sp,
        constraints: BoxConstraints(maxWidth: compact ? 150.w : 176.w),
        padding: EdgeInsets.all(3.sp),
        decoration: BoxDecoration(
          color: context.colors.surfaceRecessed,
          borderRadius: BorderRadius.circular(12.br),
          border: Border.all(color: context.colors.divider),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Expanded(
              child: _ExplorerViewTab(
                label: 'Explorer',
                selected: currentPage == 0,
                onTap: () => onSelected(0),
                compact: compact,
              ),
            ),
            SizedBox(width: 3.sp),
            Expanded(
              child: _ExplorerViewTab(
                label: 'Notation',
                selected: currentPage == 1,
                onTap: () => onSelected(1),
                compact: compact,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ExplorerViewTab extends StatelessWidget {
  const _ExplorerViewTab({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.compact,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      key: ValueKey<String>('opening_explorer_tab_${label.toLowerCase()}'),
      selected: selected,
      button: true,
      label: '$label view',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(9.br),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? context.colors.surface : Colors.transparent,
              borderRadius: BorderRadius.circular(9.br),
            ),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color:
                    selected
                        ? context.colors.textPrimary
                        : context.colors.textSecondary,
                fontSize: compact ? 11.f : 13.f,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.2,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
