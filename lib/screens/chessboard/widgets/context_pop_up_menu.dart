import 'dart:ui';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/svg_asset.dart';
import 'package:chessever2/widgets/back_drop_filter_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class ContextPopupMenu extends StatelessWidget {
  const ContextPopupMenu({
    super.key,
    required this.isPinned,
    required this.onPinToggle,
    required this.onShare,
    this.width = 120,
  });

  final bool isPinned;
  final VoidCallback onPinToggle;
  final VoidCallback onShare;
  final double width;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        width: width.w,
        decoration: _buildMenuDecoration(),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            InkWell(
              onTap: onPinToggle,
              child: Container(
                width: 120.w,
                height: 40.h,
                padding: EdgeInsets.symmetric(
                  horizontal: 12.sp,
                  vertical: 8.sp,
                ),
                child: MenuItemContent(
                  text: isPinned ? "Unpin" : "Pin",
                  iconAsset: SvgAsset.pin,
                ),
              ),
            ),

            const MenuDivider(),
            InkWell(
              onTap: onShare,
              child: Container(
                width: 120.w,
                height: 40.h,
                padding: EdgeInsets.symmetric(
                  horizontal: 12.sp,
                  vertical: 8.sp,
                ),
                child: const MenuItemContent(
                  text: "Share",
                  iconAsset: SvgAsset.share,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  BoxDecoration _buildMenuDecoration() {
    return BoxDecoration(
      color: kDarkGreyColor,
      borderRadius: BorderRadius.circular(12.br),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.3),
          blurRadius: 10,
          offset: const Offset(0, 5),
        ),
      ],
    );
  }
}

class PopupMenuItem extends StatelessWidget {
  const PopupMenuItem({super.key, required this.onTap, required this.child});

  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12.br),
      child: Container(
        width: 120.w,
        height: 40.h,
        padding: EdgeInsets.symmetric(horizontal: 12.sp, vertical: 8.sp),
        child: child,
      ),
    );
  }
}

class MenuItemContent extends StatelessWidget {
  const MenuItemContent({
    super.key,
    required this.text,
    required this.iconAsset,
  });

  final String text;
  final String iconAsset;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Text(
            text,
            style: AppTypography.textXsMedium.copyWith(color: kWhiteColor),
          ),
        ),
        SizedBox(width: 8.w),
        SvgPicture.asset(iconAsset, height: 13.h, width: 13.w),
      ],
    );
  }
}

class MenuDivider extends StatelessWidget {
  const MenuDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 1.h,
      width: double.infinity,
      margin: EdgeInsets.symmetric(horizontal: 12.sp),
      color: kDividerColor,
    );
  }
}

class PinIconOverlay extends StatelessWidget {
  const PinIconOverlay({
    super.key,
    this.left,
    this.right,
    this.top,
    this.bottom,
  });

  final double? left;
  final double? right;
  final double? top;
  final double? bottom;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: left,
      right: right,
      top: top,
      bottom: bottom,
      child: SvgPicture.asset(
        SvgAsset.pin,
        color: kpinColor,
        height: 12.h,
        width: 12.w,
      ),
    );
  }
}

class SelectiveBlurBackground extends StatelessWidget {
  const SelectiveBlurBackground({
    super.key,
    required this.clearPosition,
    required this.clearSize,
    this.borderRadius = 12,
  });

  final Offset clearPosition;
  final Size clearSize;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const BackDropFilterWidget(),
        Positioned(
          left: clearPosition.dx,
          top: clearPosition.dy,
          child: Container(
            width: clearSize.width,
            height: clearSize.height,
            decoration: BoxDecoration(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(borderRadius.br),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(borderRadius.br),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 0, sigmaY: 0),
                child: Container(color: Colors.transparent),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
