import 'package:chessever2/providers/event_favorite_players_provider.dart';
import 'package:chessever2/providers/favorite_events_provider.dart';
import 'package:chessever2/screens/group_event/model/tour_event_card_model.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/svg_asset.dart';
import 'package:chessever2/widgets/svg_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class EventCard extends ConsumerWidget {
  final GroupEventCardModel tourEventCardModel;
  final VoidCallback? onTap;

  const EventCard({required this.tourEventCardModel, this.onTap, super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      onTap: onTap != null
          ? () {
              HapticFeedbackService.cardTap();
              onTap!();
            }
          : null,
      onLongPressStart: (detail) {
        HapticFeedbackService.contextMenu();
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
              child: _StarWidget(tourEventCardModel: tourEventCardModel),
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
    String? assetPath;

    if (timeControl.contains('blitz')) {
      assetPath = 'assets/pngs/blitz.png';
    } else if (timeControl.contains('rapid')) {
      assetPath = 'assets/pngs/rapid.png';
    } else if (timeControl.contains('classic') ||
        timeControl.contains('standard')) {
      assetPath = 'assets/pngs/classical.png';
    } else {
      // Default fallback - show text if unknown format
      return Text(
        tourEventCardModel.timeControl,
        style: AppTypography.textXsMedium.copyWith(color: kWhiteColor70),
      );
    }

    return Image.asset(
      assetPath,
      width: 14.sp,
      height: 14.sp,
      fit: BoxFit.contain,
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

class _StarWidget extends ConsumerWidget {
  const _StarWidget({required this.tourEventCardModel});

  final GroupEventCardModel tourEventCardModel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Use new unified favorites system with Supabase + local cache
    // skipLoadingOnRefresh prevents flickering when refreshing from Supabase
    final favoritesAsync = ref.watch(favoriteEventsProvider);

    final isStarred = favoritesAsync.maybeWhen(
      data: (events) => events.any((e) => e.eventId == tourEventCardModel.id),
      orElse: () => false,
      skipLoadingOnRefresh: true,
      skipLoadingOnReload: true,
    );

    // Check if event has favorite players
    final eventFavoritePlayersAsync =
        ref.watch(eventFavoritePlayersProvider(tourEventCardModel.id));

    // Get current value and check if already cached
    final currentCache = ref.watch(eventFavoritePlayersCacheProvider);
    final eventFavoritePlayers = eventFavoritePlayersAsync.maybeWhen(
      data: (data) {
        // Update cache if data has changed (do this after build with microtask)
        if (currentCache[tourEventCardModel.id] != data) {
          Future.microtask(() {
            ref
                .read(eventFavoritePlayersCacheProvider.notifier)
                .updateCache(tourEventCardModel.id, data);
          });
        }
        return data;
      },
      orElse: () =>
          currentCache[tourEventCardModel.id] ??
          const EventFavoritePlayers.empty(),
    );

    // Priority: Star icon (user favorited) ALWAYS takes precedence
    // Heart icon shows ONLY when NOT starred but has favorite players
    final bool showHeart = !isStarred && eventFavoritePlayers.hasFavorites;
    final bool showFilledStar = isStarred;

    // Heart icon is NOT tappable - it's just informational
    if (showHeart) {
      return Container(
        alignment: Alignment.centerRight,
        width: 30.w,
        height: 40.h,
        child: _HeartIconWithCount(count: eventFavoritePlayers.count),
      );
    }

    // Star icon is tappable - user can favorite/unfavorite
    return InkWell(
      onTap: () {
        HapticFeedbackService.pin();

        ref.read(favoriteEventsProvider.notifier).toggleFavorite(
          eventId: tourEventCardModel.id,
          eventName: tourEventCardModel.title,
          timeControl: tourEventCardModel.timeControl,
          maxAvgElo: tourEventCardModel.maxAvgElo > 0
              ? tourEventCardModel.maxAvgElo
              : null,
          dates: tourEventCardModel.dates.isNotEmpty
              ? tourEventCardModel.dates
              : null,
        ).catchError((e) {
          debugPrint('[EventCard] Error toggling favorite: $e');
          // Silently handle error - state will be corrected on next refresh
          return false;
        });
      },
      child: Container(
        alignment: Alignment.centerRight,
        width: 30.w,
        height: 40.h,
        child: SvgWidget(
          showFilledStar ? SvgAsset.starFilledIcon : SvgAsset.starIcon,
          semanticsLabel: 'Favorite Icon',
          height: 20.h,
          width: 20.w,
        ),
      ),
    );
  }
}

class _HeartIconWithCount extends StatelessWidget {
  const _HeartIconWithCount({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 24.w,
      height: 24.h,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Heart icon
          SvgWidget(
            SvgAsset.favouriteRedIcon,
            semanticsLabel: 'Has Favorite Players',
            height: 20.h,
            width: 20.w,
          ),
          // Count text centered in the middle (only show if > 1)
          if (count > 1)
            Text(
              count > 9 ? '9+' : count.toString(),
              style: AppTypography.textXsBold.copyWith(
                color: kWhiteColor,
                fontSize: 10.sp,
                height: 1,
                fontWeight: FontWeight.w900,
                shadows: [
                  Shadow(
                    offset: Offset(0.5, 0.5),
                    blurRadius: 1.5,
                    color: kBlackColor.withValues(alpha: 0.7),
                  ),
                  Shadow(
                    offset: Offset(-0.5, -0.5),
                    blurRadius: 1.5,
                    color: kBlackColor.withValues(alpha: 0.7),
                  ),
                ],
              ),
            ),
        ],
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
