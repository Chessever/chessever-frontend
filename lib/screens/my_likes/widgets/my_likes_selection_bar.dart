import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/app_button.dart' show TappableScale;
import 'package:flutter/material.dart';

/// The bar My Likes shows while choosing games to remove, under the search:
/// leave, how many are chosen, choose all (or none), and Remove.
class MyLikesSelectionBar extends StatelessWidget {
  const MyLikesSelectionBar({
    super.key,
    required this.selectedCount,
    required this.allSelected,
    required this.removing,
    required this.onClose,
    required this.onToggleAll,
    required this.onRemove,
  });

  final int selectedCount;
  final bool allSelected;
  final bool removing;
  final VoidCallback onClose;
  final VoidCallback onToggleAll;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final canRemove = selectedCount > 0 && !removing;
    final title = selectedCount == 0
        ? 'None selected'
        : '$selectedCount selected';
    return Container(
      height: 52.h,
      padding: EdgeInsets.only(left: 4.w, right: 6.w),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(12.br),
        border: Border.all(color: colors.surfaceRecessed),
      ),
      child: Row(
        children: [
          IconButton(
            key: const ValueKey('my_likes_selection_close'),
            tooltip: 'Done selecting',
            onPressed: removing ? null : onClose,
            icon: Icon(
              Icons.close_rounded,
              size: 20.sp,
              color: colors.textPrimary,
            ),
          ),
          Expanded(
            flex: 2,
            child: Semantics(
              liveRegion: true,
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.textSmMedium.copyWith(
                  color: selectedCount == 0
                      ? colors.textSecondary
                      : colors.textPrimary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ),
          // The actions keep their size and scale down together, never
          // overflow, at large text or on a narrow phone.
          Flexible(
            flex: 3,
            child: Align(
              alignment: AlignmentDirectional.centerEnd,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextButton(
                      key: const ValueKey('my_likes_select_all'),
                      onPressed: removing ? null : onToggleAll,
                      style: TextButton.styleFrom(
                        foregroundColor: colors.accentText,
                        padding: EdgeInsets.symmetric(horizontal: 10.w),
                        minimumSize: Size(0, 40.h),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text(
                        allSelected ? 'Deselect all' : 'Select all',
                        style: AppTypography.textSmMedium.copyWith(
                          color: colors.accentText,
                        ),
                      ),
                    ),
                    SizedBox(width: 4.w),
                    _RemoveButton(
                      enabled: canRemove,
                      busy: removing,
                      onTap: onRemove,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RemoveButton extends StatelessWidget {
  const _RemoveButton({
    required this.enabled,
    required this.busy,
    required this.onTap,
  });

  final bool enabled;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final fill = enabled || busy
        ? colors.danger
        : colors.textPrimary.withValues(alpha: 0.08);
    final ink = enabled || busy
        ? const Color(0xFFFFFFFF)
        : colors.textPrimary.withValues(alpha: 0.4);
    final button = AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      height: 38.h,
      padding: EdgeInsets.symmetric(horizontal: 14.w),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(10.br),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (busy)
            SizedBox.square(
              dimension: 14.sp,
              child: CircularProgressIndicator(strokeWidth: 2, color: ink),
            )
          else
            Icon(Icons.heart_broken_rounded, size: 16.sp, color: ink),
          SizedBox(width: 6.w),
          Text(
            'Remove',
            style: AppTypography.textSmMedium.copyWith(
              color: ink,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
    return Semantics(
      button: true,
      enabled: enabled,
      label: 'Remove selected likes',
      excludeSemantics: true,
      onTap: enabled ? onTap : null,
      child: enabled
          ? TappableScale(
              key: const ValueKey('my_likes_remove_selected'),
              onTap: onTap,
              child: button,
            )
          : KeyedSubtree(
              key: const ValueKey('my_likes_remove_selected'),
              child: button,
            ),
    );
  }
}
