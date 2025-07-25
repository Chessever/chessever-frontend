import 'package:chessever2/providers/country_dropdown_provider.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/extensioms/string_extensions.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/svg_asset.dart';
import 'package:chessever2/widgets/svg_widget.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class CountrymenCardWidget extends ConsumerWidget {
  const CountrymenCardWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dropDownSelectedCountry =
        ref.watch(countryDropdownProvider).value?.name.toLowerCase() ?? '';

    return GestureDetector(
      onTap: () {
        Navigator.pushNamed(context, '/countryman_games_screen');
      },
      child: Container(
        decoration: BoxDecoration(
          color: kBlack2Color,
          borderRadius: BorderRadius.only(
            topRight: Radius.circular(8.br),
            topLeft: Radius.circular(8.br),
          ),
        ),
        padding: EdgeInsets.only(
          top: 8.sp,
          bottom: 8.sp,
          left: 8.sp,
          right: 8.sp,
        ),
        child: Row(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    'Countrymen',
                    style: AppTypography.textSmMedium.copyWith(
                      color: kGreenColor2,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
                SizedBox(height: 2.h),

                // Second row with details
                RichText(
                  maxLines: 1,
                  text: TextSpan(
                    style: AppTypography.textXsMedium.copyWith(
                      color: kWhiteColor70,
                    ),
                    children: [
                      TextSpan(
                        text: dropDownSelectedCountry.capitalizeEachWord(),
                      ),
                      _buildDot(),
                      // TODO: Replace with actual value
                      TextSpan(text: "Ø 2700"),
                    ],
                  ),
                ),
              ],
            ),
            Spacer(),
            SizedBox(
              width: 32.w,
              height: 32.h,
              child: SvgWidget(
                SvgAsset.countryMan,
                semanticsLabel: 'Country Man',
                height: 32.h,
                width: 32.w,
              ),
            ),
          ],
        ),
      ),
    );
  }

  WidgetSpan _buildDot() {
    return WidgetSpan(
      alignment: PlaceholderAlignment.middle,
      child: Container(
        margin: EdgeInsets.symmetric(horizontal: 6),
        height: 6.h,
        width: 6.w,
        decoration: BoxDecoration(shape: BoxShape.circle, color: kWhiteColor70),
      ),
    );
  }
}
