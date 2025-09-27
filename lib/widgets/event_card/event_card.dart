import 'dart:developer';

import 'package:chessever2/screens/group_event/model/tour_event_card_model.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/svg_asset.dart';
import 'package:chessever2/widgets/event_card/starred_provider.dart';
import 'package:chessever2/repository/local_storage/unified_favorites/unified_favorites_provider.dart';
import 'package:chessever2/widgets/svg_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
      onLongPressStart: (detail) {
        HapticFeedback.lightImpact();
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
                  Row(
                    children: [
                      if (tourEventCardModel.dates.trim().isNotEmpty) ...[
                        Text(
                          tourEventCardModel.dates,
                          style: AppTypography.textXsMedium.copyWith(
                            color: kWhiteColor70,
                          ),
                        ),
                        _buildDotWidget(),
                      ],
                      _buildTimeControlIcon(),
                      if (tourEventCardModel.maxAvgElo > 0) ...[
                        _buildDotWidget(),
                        Text(
                          "Ø ${tourEventCardModel.maxAvgElo}",
                          style: AppTypography.textXsMedium.copyWith(
                            color: kWhiteColor70,
                          ),
                        ),
                      ],
                    ],
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

  Widget _buildDotWidget() {
    return Container(
      margin: EdgeInsets.symmetric(horizontal: 4.w),
      height: 6.h,
      width: 6.w,
      decoration: BoxDecoration(shape: BoxShape.circle, color: kWhiteColor70),
    );
  }

  Widget _buildTimeControlIcon() {
    final timeControl = tourEventCardModel.timeControl.toLowerCase();
    IconData icon;
    Color iconColor;

    if (timeControl.contains('blitz')) {
      icon = Icons.bolt;
      iconColor = kRedColor;
    } else if (timeControl.contains('rapid')) {
      icon = Icons.flash_on;
      iconColor = Colors.orange;
    } else if (timeControl.contains('classic') ||
        timeControl.contains('standard')) {
      icon = Icons.access_time;
      iconColor = kWhiteColor;
    } else {
      // Default fallback - show text if unknown format
      return Text(
        tourEventCardModel.timeControl,
        style: AppTypography.textXsMedium.copyWith(
          color: kWhiteColor70,
        ),
      );
    }

    return Icon(
      icon,
      size: 14.sp,
      color: iconColor,
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
        return _StarWidget(tourEventCardModel: tourEventCardModel);

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
    // Check both old system (for backward compatibility) and new system
    final starredList = ref.watch(starredProvider);
    final isEventFavoriteAsync = ref.watch(
      isEventFavoriteProvider(widget.tourEventCardModel.id),
    );

    final isStarredOld = starredList.contains(widget.tourEventCardModel.id);
    final isStarredNew = isEventFavoriteAsync.maybeWhen(
      data: (isFavorite) => isFavorite,
      orElse: () => false,
    );

    final isStarred = isStarredOld || isStarredNew;
    isFav = isStarred;

    return InkWell(
      onTap: () async {
        setState(() {
          isFav = !isFav;
        });

        // Toggle in both old and new systems for compatibility
        ref
            .read(starredProvider.notifier)
            .toggleStarred(widget.tourEventCardModel.id);
        await ref.toggleEventFavorite(widget.tourEventCardModel);
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
  const _CountrymenStarWidget();

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
