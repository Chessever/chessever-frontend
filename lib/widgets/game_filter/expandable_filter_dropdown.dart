import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';

/// Custom expandable dropdown matching the dark theme design
/// Collapsed: dark background, chevron down
/// Expanded: light header, dark options list
class ExpandableFilterDropdown<T> extends StatefulWidget {
  const ExpandableFilterDropdown({
    super.key,
    required this.value,
    required this.items,
    required this.itemLabel,
    required this.onChanged,
    this.itemIcon,
    this.itemAssetPath,
  });

  final T value;
  final List<T> items;
  final String Function(T) itemLabel;
  final ValueChanged<T> onChanged;
  final IconData Function(T)? itemIcon;
  /// Asset path for image-based icons (e.g., time control icons)
  final String? Function(T)? itemAssetPath;

  @override
  State<ExpandableFilterDropdown<T>> createState() =>
      _ExpandableFilterDropdownState<T>();
}

class _ExpandableFilterDropdownState<T>
    extends State<ExpandableFilterDropdown<T>>
    with SingleTickerProviderStateMixin {
  bool _isExpanded = false;
  late AnimationController _animationController;
  late Animation<double> _expandAnimation;
  late Animation<double> _rotationAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _expandAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    );
    _rotationAnimation = Tween<double>(begin: 0, end: 0.5).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Curves.easeInOut,
      ),
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _toggleExpanded() {
    setState(() {
      _isExpanded = !_isExpanded;
      if (_isExpanded) {
        _animationController.forward();
      } else {
        _animationController.reverse();
      }
    });
  }

  void _selectItem(T item) {
    widget.onChanged(item);
    _toggleExpanded();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Header (clickable area)
        GestureDetector(
          onTap: _toggleExpanded,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
            decoration: BoxDecoration(
              color: _isExpanded ? kWhiteColor : kBlack2Color,
              borderRadius: _isExpanded
                  ? BorderRadius.vertical(top: Radius.circular(12.br))
                  : BorderRadius.circular(12.br),
              border: Border.all(
                color: _isExpanded
                    ? kWhiteColor.withValues(alpha: 0.2)
                    : kDividerColor,
              ),
            ),
            child: Row(
              children: [
                // Asset image icon (preferred)
                if (widget.itemAssetPath != null) ...[
                  if (widget.itemAssetPath!(widget.value) != null) ...[
                    Image.asset(
                      widget.itemAssetPath!(widget.value)!,
                      width: 16.sp,
                      height: 16.sp,
                      color: _isExpanded ? kBlackColor : null,
                    ),
                    SizedBox(width: 8.w),
                  ],
                ] else if (widget.itemIcon != null) ...[
                  // Fallback to IconData
                  Icon(
                    widget.itemIcon!(widget.value),
                    size: 18.ic,
                    color: _isExpanded ? kBlackColor : kWhiteColor,
                  ),
                  SizedBox(width: 8.w),
                ],
                // Selected value text
                Expanded(
                  child: Text(
                    widget.itemLabel(widget.value),
                    style: AppTypography.textSmMedium.copyWith(
                      color: _isExpanded ? kBlackColor : kWhiteColor,
                    ),
                  ),
                ),
                // Chevron with rotation
                RotationTransition(
                  turns: _rotationAnimation,
                  child: Icon(
                    Icons.keyboard_arrow_down_rounded,
                    size: 20.ic,
                    color: _isExpanded
                        ? kBlackColor.withValues(alpha: 0.7)
                        : kSecondaryTextColor,
                  ),
                ),
              ],
            ),
          ),
        ),

        // Expandable options list
        SizeTransition(
          sizeFactor: _expandAnimation,
          axisAlignment: -1,
          child: Container(
            decoration: BoxDecoration(
              color: kBlack2Color,
              borderRadius: BorderRadius.vertical(
                bottom: Radius.circular(12.br),
              ),
              border: Border(
                left: BorderSide(color: kDividerColor),
                right: BorderSide(color: kDividerColor),
                bottom: BorderSide(color: kDividerColor),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: widget.items
                  .where((item) => item != widget.value)
                  .map((item) => _buildOptionItem(item))
                  .toList(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildOptionItem(T item) {
    // Check for asset-based icon first
    final assetPath = widget.itemAssetPath?.call(item);
    final hasAssetIcon = assetPath != null;

    // Fallback to IconData
    final hasIcon = widget.itemIcon != null;
    final iconData = hasIcon ? widget.itemIcon!(item) : null;

    return GestureDetector(
      onTap: () => _selectItem(item),
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
        child: Row(
          children: [
            // Asset image icon (preferred)
            if (hasAssetIcon) ...[
              Image.asset(
                assetPath,
                width: 16.sp,
                height: 16.sp,
              ),
              SizedBox(width: 8.w),
            ] else if (hasIcon && iconData != null) ...[
              // Fallback to IconData
              Icon(
                iconData,
                size: 18.ic,
                color: kWhiteColor,
              ),
              SizedBox(width: 8.w),
            ],
            Expanded(
              child: Text(
                widget.itemLabel(item),
                style: AppTypography.textSmMedium.copyWith(
                  color: kWhiteColor,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
