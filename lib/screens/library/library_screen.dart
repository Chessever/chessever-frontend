import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/svg_asset.dart';
import 'package:chessever2/widgets/screen_wrapper.dart';
import 'package:chessever2/widgets/svg_widget.dart';
import 'package:flutter/material.dart';

class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ScreenWrapper(
      child: Center(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(height: 24.h + MediaQuery.of(context).viewPadding.top),
            Spacer(),
            _ComingSoonWidget(),
            Spacer(),
          ],
        ),
      ),
    );
  }
}

class _ComingSoonWidget extends StatelessWidget {
  const _ComingSoonWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SvgWidget(SvgAsset.bookIcon, width: 64.w, height: 64.h),
        SizedBox(height: 12.h),
        Text(
          'Library Coming Soon',
          style: AppTypography.textLgMedium.copyWith(color: kWhiteColor),
        ),
        SizedBox(width: 20.w),
        Text(
          'Your personal library will be\navailable in a future update.',
          style: AppTypography.textMdRegular.copyWith(color: kInactiveTabColor),
        ),
      ],
    );
  }
}

final _boxDecoration = BoxDecoration(
  color: kBlack2Color,
  borderRadius: BorderRadius.circular(2.br),
);

class _PlusIcon extends StatelessWidget {
  const _PlusIcon({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(8.sp),
      decoration: _boxDecoration,
      child: Icon(Icons.add_rounded, color: Colors.white, size: 24.ic),
    );
  }
}
