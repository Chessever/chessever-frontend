import 'package:chessever2/screens/tournaments/model/tour_event_card_model.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/svg_asset.dart';
import 'package:chessever2/widgets/event_card/starred_provider.dart';
import 'package:chessever2/widgets/svg_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class EventCard extends ConsumerWidget {
  final GroupEventCardModel tourEventCardModel;
  final VoidCallback? onTap;
  final bool isFavorite;
  final VoidCallback? onFavoritePressed;
  final VoidCallback? onMorePressed;

  const EventCard({
    required this.tourEventCardModel,
    this.onTap,
    this.isFavorite = false,
    this.onFavoritePressed,
    this.onMorePressed,
    super.key,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: kBlack2Color,
          borderRadius: BorderRadius.only(
            topRight: Radius.circular(8.br),
            topLeft: Radius.circular(8.br),
          ),
        ),
        padding: EdgeInsets.only(
          top: 6.sp,
          bottom: 6.sp,
          left: 8.sp,
          right: 8.sp,
        ),
        child: Row(
          crossAxisAlignment:
              CrossAxisAlignment
                  .center, // Center vertically in the entire container
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            Expanded(
              flex: 9,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Flexible(
                        child: Text(
                          tourEventCardModel.title,
                          style: AppTypography.textSmMedium.copyWith(
                            color: kWhiteColor,
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ),
                      SizedBox(width: 8.w),
                      _ShowStatus(tourEventCardModel: tourEventCardModel),
                    ],
                  ),

                  // Small vertical spacing
                  SizedBox(height: 2.h),

                  // Second row with details
                  RichText(
                    maxLines: 1,
                    text: TextSpan(
                      style: AppTypography.textXsMedium.copyWith(
                        color: kWhiteColor70,
                      ),
                      children: [
                        if (tourEventCardModel.dates.trim().isNotEmpty) ...[
                          TextSpan(text: tourEventCardModel.dates),
                          _buildDot(),
                        ],
                        TextSpan(text: tourEventCardModel.timeControl),
                        _buildDot(),
                        TextSpan(text: "Ø ${tourEventCardModel.maxAvgElo}"),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              flex: 1,
              child: _BuildTrailingButton(
                tourEventCardModel: tourEventCardModel,
                onMorePressed: onMorePressed,
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
        margin: EdgeInsets.symmetric(horizontal: 4),
        height: 6.h,
        width: 6.w,
        decoration: BoxDecoration(shape: BoxShape.circle, color: kWhiteColor70),
      ),
    );
  }
}

class _ShowStatus extends ConsumerWidget {
  const _ShowStatus({required this.tourEventCardModel});

  final GroupEventCardModel tourEventCardModel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    switch (tourEventCardModel.tourEventCategory) {
      case TourEventCategory.live:
        return _LiveTag();
      case TourEventCategory.upcoming:
        return _UpcomingTag(tourEventCardModel: tourEventCardModel);
      case TourEventCategory.completed:
        return _CompletedTag();
      case TourEventCategory.ongoing:
        return SizedBox.shrink();
    }
  }
}

class _UpcomingTag extends StatelessWidget {
  const _UpcomingTag({required this.tourEventCardModel});

  final GroupEventCardModel tourEventCardModel;

  @override
  Widget build(BuildContext context) {
    return Text(
      tourEventCardModel.timeUntilStart,
      style: AppTypography.textXsMedium.copyWith(
        color: kWhiteColor.withOpacity(0.7),
      ),
    );
  }
}

class _OngoingTag extends StatelessWidget {
  const _OngoingTag();

  @override
  Widget build(BuildContext context) {
    return Text(
      'Ongoing',
      style: AppTypography.textXsBold.copyWith(
        color: kPrimaryColor.withOpacity(0.4),
      ),
    );
  }
}

class _CompletedTag extends StatelessWidget {
  const _CompletedTag();

  @override
  Widget build(BuildContext context) {
    return Text(
      "Completed",
      style: AppTypography.textXsMedium.copyWith(color: kWhiteColor70),
    );
  }
}

class _LiveTag extends StatelessWidget {
  const _LiveTag();

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(SvgAsset.selectedSvg, width: 16.w, height: 16.h);
  }
}

class _BuildTrailingButton extends ConsumerWidget {
  const _BuildTrailingButton({
    required this.tourEventCardModel,
    this.onMorePressed,
  });

  final GroupEventCardModel tourEventCardModel;
  final VoidCallback? onMorePressed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // final currentLocation =
    //     ref
    //         .read(locationServiceProvider)
    //         .getCountryName(tourEventCardModel.location)
    //         .toLowerCase();

    // final dropDownSelectedCountry =
    //     ref.watch(countryDropdownProvider).value?.name.toLowerCase() ?? '';

    // if (currentLocation.isNotEmpty &&
    //     dropDownSelectedCountry.isNotEmpty &&
    //     currentLocation.contains(dropDownSelectedCountry)) {
    //   return _CountrymenStarWidget();
    // }

    switch (tourEventCardModel.tourEventCategory) {
      case TourEventCategory.upcoming:
        return _StarWidget(tourEventCardModel: tourEventCardModel);

      case TourEventCategory.live:
        return _StarWidget(tourEventCardModel: tourEventCardModel);

      case TourEventCategory.completed:
        return InkWell(
          onTap: onMorePressed,
          child: Container(
            alignment: Alignment.centerRight,
            width: 30.w,
            height: 40.h,
            child: SvgWidget(
              SvgAsset.threeDots,
              semanticsLabel: 'More Options',
              height: 24.h,
              width: 24.w,
            ),
          ),
        );
      case TourEventCategory.ongoing:
        return _StarWidget(tourEventCardModel: tourEventCardModel);
    }
  }
}

class _StarWidget extends ConsumerStatefulWidget {
  const _StarWidget({required this.tourEventCardModel});

  final GroupEventCardModel tourEventCardModel;

  @override
  ConsumerState<_StarWidget> createState() => _StarWidgetState();
}

class _StarWidgetState extends ConsumerState<_StarWidget> {
  var isFav = false;

  @override
  Widget build(BuildContext context) {
    final starredList = ref.watch(starredProvider);

    final isStarred = starredList.contains(widget.tourEventCardModel.id);

    isFav = isStarred;

    return InkWell(
      onTap: () {
        setState(() {
          isFav = !isFav;
        });
        ref
            .read(starredProvider.notifier)
            .toggleStarred(widget.tourEventCardModel.id);
      },
      child: Container(
        alignment: Alignment.centerRight,
        width: 30.w,
        height: 40.h,
        child: SvgWidget(
          isStarred ? SvgAsset.starFilledIcon : SvgAsset.starIcon,
          semanticsLabel: 'Favorite Icon',
          height: 20.h,
          width: 20.w,
        ),
      ),
    );
  }
}

class _CountrymenStarWidget extends ConsumerStatefulWidget {
  _CountrymenStarWidget();

  @override
  ConsumerState<_CountrymenStarWidget> createState() =>
      _CountrymenStarWidgetState();
}

class _CountrymenStarWidgetState extends ConsumerState<_CountrymenStarWidget> {
  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {},
      child: Container(
        alignment: Alignment.centerRight,
        width: 32.w,
        height: 40.h,
        child: SvgWidget(
          SvgAsset.countryMan,
          semanticsLabel: 'Country Man',
          height: 32.h,
          width: 32.w,
        ),
      ),
    );
  }
}
