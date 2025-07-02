import 'package:chessever2/screens/tournaments/model/tour_event_card_model.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/svg_asset.dart';
import 'package:chessever2/widgets/event_card/starred_provider.dart';
import 'package:chessever2/widgets/svg_widget.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class EventCard extends StatelessWidget {
  final TourEventCardModel tourEventCardModel;
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
  Widget build(BuildContext context) {
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
        child: Stack(
          alignment: Alignment.centerRight,
          children: [
            Row(
              crossAxisAlignment:
                  CrossAxisAlignment
                      .center, // Center vertically in the entire container
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Flexible(
                            child: Text(
                              tourEventCardModel.title,
                              style: AppTypography.textXsBold.copyWith(
                                color: kWhiteColor,
                              ),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                          ),
                          SizedBox(width: 4.w),
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
                            TextSpan(text: tourEventCardModel.dates),
                            _buildDot(),
                            TextSpan(text: tourEventCardModel.location),
                            _buildDot(),
                            TextSpan(
                              text: "${tourEventCardModel.playerCount} players",
                            ),
                            _buildDot(),
                            TextSpan(text: "ELO ${tourEventCardModel.elo}"),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            Align(
              alignment: Alignment.centerRight,
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
    final fontStyle = TextStyle(fontWeight: FontWeight.w900, fontSize: 12.f);
    return WidgetSpan(
      alignment: PlaceholderAlignment.middle,
      child: Text(" ● ", style: fontStyle.copyWith(color: kWhiteColor70)),
    );
  }
}

class _ShowStatus extends StatelessWidget {
  const _ShowStatus({required this.tourEventCardModel, super.key});

  final TourEventCardModel tourEventCardModel;

  @override
  Widget build(BuildContext context) {
    switch (tourEventCardModel.tourEventCategory) {
      case TourEventCategory.live:
        return _LiveTag();
      case TourEventCategory.upcoming:
        return _UpcomingTag(tourEventCardModel: tourEventCardModel);
      case TourEventCategory.completed:
        return _CompletedTag();
      case TourEventCategory.countrymen:
        return _CountryMen();
    }
  }
}

class _UpcomingTag extends StatelessWidget {
  const _UpcomingTag({required this.tourEventCardModel, super.key});

  final TourEventCardModel tourEventCardModel;

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

class _CountryMen extends StatelessWidget {
  const _CountryMen({super.key});

  @override
  Widget build(BuildContext context) {
    return Text(
      'Countrymen',
      style: AppTypography.textXsBold.copyWith(color: kWhiteColor),
    );
  }
}

class _CompletedTag extends StatelessWidget {
  const _CompletedTag({super.key});

  @override
  Widget build(BuildContext context) {
    return Text(
      "Completed",
      style: AppTypography.textXsMedium.copyWith(color: Colors.grey),
    );
  }
}

class _LiveTag extends StatelessWidget {
  const _LiveTag({super.key});

  @override
  Widget build(BuildContext context) {
    return Text(
      'LIVE',
      style: AppTypography.textXsBold.copyWith(
        color: kPrimaryColor,
        fontFamily: 'InterDisplay',
      ),
    );
  }
}

class _BuildTrailingButton extends StatelessWidget {
  const _BuildTrailingButton({
    required this.tourEventCardModel,
    this.onMorePressed,
    super.key,
  });

  final TourEventCardModel tourEventCardModel;
  final VoidCallback? onMorePressed;

  @override
  Widget build(BuildContext context) {
    switch (tourEventCardModel.tourEventCategory) {
      case TourEventCategory.upcoming:
        return _StarWidget(tourEventCardModel: tourEventCardModel);

      case TourEventCategory.live:
        return _StarWidget(tourEventCardModel: tourEventCardModel);

      case TourEventCategory.countrymen:
        return _CountrymenStarWidget();
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
    }
  }
}

class _StarWidget extends ConsumerStatefulWidget {
  const _StarWidget({required this.tourEventCardModel, super.key});

  final TourEventCardModel tourEventCardModel;

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
  _CountrymenStarWidget({super.key});

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
