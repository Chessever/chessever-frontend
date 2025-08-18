import 'package:chessever2/screens/tournaments/model/about_tour_model.dart';
import 'package:chessever2/screens/tournaments/providers/tour_detail_screen_provider.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/location_service_provider.dart';
import 'package:chessever2/utils/png_asset.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/svg_asset.dart';
import 'package:chessever2/utils/url_launcher_provider.dart';
import 'package:chessever2/widgets/network_image_widget.dart';
import 'package:chessever2/widgets/skeleton_widget.dart';
import 'package:chessever2/widgets/svg_widget.dart';
import 'package:country_flags/country_flags.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class AboutTourScreen extends ConsumerWidget {
  const AboutTourScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref
        .watch(tourDetailScreenProvider)
        .when(
          data: (data) {
            final countryCode = ref
                .read(locationServiceProvider)
                .getCountryCode(data.aboutTourModel.location);
            return Scaffold(
              bottomNavigationBar: Container(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.of(context).viewPadding.bottom,
                ),
                child:
                    data.aboutTourModel.extractDomain().isEmpty
                        ? SizedBox.shrink()
                        : GestureDetector(
                          onTap:
                              () => ref
                                  .read(urlLauncherProvider)
                                  .launchCustomUrl(
                                    data.aboutTourModel.websiteUrl,
                                  ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              SvgWidget(
                                SvgAsset.websiteIcon,
                                height: 12.h,
                                width: 12.h,
                              ),
                              SizedBox(width: 4.w),
                              Text(
                                data.aboutTourModel.extractDomain(),
                                maxLines: 1,
                                style: AppTypography.textXsMedium.copyWith(
                                  color: kPrimaryColor,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
              ),
              body: Container(
                margin: EdgeInsets.symmetric(horizontal: 20.sp),
                child: SingleChildScrollView(
                  padding: EdgeInsets.zero,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.start,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(height: 16.h),
                      ClipRRect(
                        borderRadius: BorderRadius.only(
                          topLeft: Radius.circular(12.br),
                          topRight: Radius.circular(12.br),
                        ),
                        child: NetworkImageWidget(
                          height: 240.h,
                          imageUrl: data.aboutTourModel.imageUrl,
                          placeHolder: PngAsset.premiumIcon,
                        ),
                      ),
                      SizedBox(height: 12.h),
                      Text(
                        data.aboutTourModel.description,
                        style: AppTypography.textSmMedium.copyWith(
                          color: kWhiteColor70,
                        ),
                      ),
                      SizedBox(height: 12.h),
                      _TitleDescWidget(
                        title: 'Players',
                        description: data.aboutTourModel.players.join(', '),
                      ),
                      SizedBox(height: 12),
                      _TitleDescWidget(
                        title: 'Time Control',
                        description: data.aboutTourModel.timeControl,
                      ),
                      SizedBox(height: 12.h),
                      _TitleDescWidget(
                        title: 'Date',
                        description: data.aboutTourModel.date,
                      ),
                      SizedBox(height: 12.h),
                      _CountryFlag(
                        title: 'Location',
                        flag:
                            countryCode.isNotEmpty
                                ? CountryFlag.fromCountryCode(
                                  countryCode,
                                  width: 16.w,
                                  height: 12.h,
                                )
                                : null,
                        description: data.aboutTourModel.location,
                      ),
                      // Row(
                      //   mainAxisAlignment: MainAxisAlignment.end,
                      //   children: [
                      //     InkWell(
                      //       onTap: () {},
                      //       child: Container(
                      //         decoration: BoxDecoration(
                      //           color: Colors.white,
                      //           shape: BoxShape.circle,
                      //         ),
                      //         padding: EdgeInsets.symmetric(
                      //           horizontal: 10.sp,
                      //           vertical: 10.sp,
                      //         ),
                      //         child: SvgWidget(
                      //           SvgAsset.boat,
                      //           height: 32.h,
                      //           width: 32.w,
                      //         ),
                      //       ),
                      //     ),
                      //   ],
                      // ),
                      SizedBox(
                        height: MediaQuery.of(context).viewPadding.bottom,
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
          error: (e, _) {
            return _DummyView();
          },
          loading: () {
            return _DummyView();
          },
        );
  }
}

class _DummyView extends ConsumerWidget {
  const _DummyView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dummyAboutModel = AboutTourModel(
      id: 'Chessever',
      name: 'Chessever',
      description: 'Chessever',
      imageUrl: 'Chessever',
      players: ['Chessever'],
      timeControl: 'Chessever',
      date: 'Chessever',
      location: 'US',
      websiteUrl: 'https://www.chessever.com/',
    );
    return Scaffold(
      bottomNavigationBar: SkeletonWidget(
        child: Container(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewPadding.bottom,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SvgWidget(SvgAsset.websiteIcon, height: 12, width: 12),
              SizedBox(width: 4),
              Text(
                dummyAboutModel.extractDomain(),
                maxLines: 1,
                style: AppTypography.textXsMedium.copyWith(
                  color: kPrimaryColor,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
      body: SkeletonWidget(
        child: Container(
          margin: EdgeInsets.symmetric(horizontal: 20),
          child: SingleChildScrollView(
            padding: EdgeInsets.zero,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(12),
                    topRight: Radius.circular(12),
                  ),
                  child: NetworkImageWidget(
                    height: 240,
                    imageUrl: dummyAboutModel.imageUrl,
                    placeHolder: PngAsset.premiumIcon,
                  ),
                ),
                SizedBox(height: 12),
                Text(
                  dummyAboutModel.description,
                  style: AppTypography.textSmMedium.copyWith(
                    color: kWhiteColor70,
                  ),
                ),
                SizedBox(height: 12),
                _TitleDescWidget(
                  title: 'Players',
                  description: dummyAboutModel.players.join(', '),
                ),
                SizedBox(height: 12),
                _TitleDescWidget(
                  title: 'Time Control',
                  description: dummyAboutModel.timeControl,
                ),
                SizedBox(height: 12),
                _TitleDescWidget(
                  title: 'Date',
                  description: dummyAboutModel.date,
                ),
                SizedBox(height: 12),
                _CountryFlag(
                  title: 'Location',
                  flag: CountryFlag.fromCountryCode(
                    ref
                        .read(locationServiceProvider)
                        .getCountryCode(dummyAboutModel.location),
                    width: 16,
                    height: 12,
                  ),
                  description: dummyAboutModel.location,
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    InkWell(
                      onTap: () {},
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                        padding: EdgeInsets.symmetric(
                          horizontal: 10.sp,
                          vertical: 10.sp,
                        ),
                        child: SvgWidget(
                          SvgAsset.boat,
                          height: 32.h,
                          width: 32.w,
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: MediaQuery.of(context).viewPadding.bottom),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TitleDescWidget extends StatelessWidget {
  const _TitleDescWidget({
    required this.title,
    required this.description,
    super.key,
  });

  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: AppTypography.textXsMedium.copyWith(color: kWhiteColor70),
        ),
        SizedBox(height: 8),
        Text(
          description,
          style: AppTypography.textXsMedium.copyWith(color: kWhiteColor),
        ),
      ],
    );
  }
}

class _CountryFlag extends StatelessWidget {
  const _CountryFlag({
    required this.title,
    required this.flag,
    required this.description,
    super.key,
  });

  final String title;
  final Widget? flag;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: AppTypography.textXsMedium.copyWith(color: kWhiteColor70),
        ),
        SizedBox(height: 8.w),
        Row(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            if (flag != null) ...[flag!, SizedBox(width: 4.w)],
            Flexible(
              child: Text(
                description,
                maxLines: 1,
                style: AppTypography.textXsMedium.copyWith(color: kWhiteColor),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
