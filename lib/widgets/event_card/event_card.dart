import 'package:cached_network_image/cached_network_image.dart';
import 'package:chessever2/providers/event_favorite_players_provider.dart';
import 'package:chessever2/providers/favorite_events_provider.dart';
import 'package:chessever2/screens/group_event/model/tour_event_card_model.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/svg_asset.dart';
import 'package:chessever2/widgets/event_card/event_image_provider.dart';
import 'package:chessever2/widgets/svg_widget.dart';
import 'package:flutter/material.dart';
import 'package:heroine/heroine.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:skeletonizer/skeletonizer.dart';

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
          borderRadius: BorderRadius.circular(8.br),
        ),
        padding: EdgeInsets.all(6.sp),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Event Image on the left
            _EventImage(groupBroadcastId: tourEventCardModel.id),
            SizedBox(width: 12.w),

            // Content in the middle
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // LIVE status or time until start (prominently displayed)
                  _StatusDisplay(tourEventCardModel: tourEventCardModel),

                  SizedBox(height: 4.h),

                  // Event details (dates, time control, ELO)
                  Row(
                    children: [
                      if (tourEventCardModel.dates.trim().isNotEmpty) ...[
                        Flexible(
                          child: Text(
                            tourEventCardModel.dates,
                            style: AppTypography.textXsMedium.copyWith(
                              color: kWhiteColor70,
                            ),
                            overflow: TextOverflow.ellipsis,
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

            SizedBox(width: 8.w),

            // Star icon on the right
            _StarWidget(tourEventCardModel: tourEventCardModel),
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

// Event Image Widget with cached network image
class _EventImage extends ConsumerWidget {
  final String groupBroadcastId;

  const _EventImage({required this.groupBroadcastId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final imageAsync = ref.watch(eventImageProvider(groupBroadcastId));
    final heroTag = 'event-image-$groupBroadcastId';

    return Heroine(
      tag: heroTag,
      child: Container(
        width: 80.w,
        height: 60.h,
        decoration: BoxDecoration(
          color: kLightBlack,
          borderRadius: BorderRadius.circular(6.br),
        ),
        clipBehavior: Clip.antiAlias,
        child: imageAsync.when(
          data: (imageUrl) {
            if (imageUrl != null && imageUrl.isNotEmpty) {
              return CachedNetworkImage(
                imageUrl: imageUrl,
                fit: BoxFit.cover,
                fadeInDuration: const Duration(milliseconds: 300),
                fadeOutDuration: const Duration(milliseconds: 200),
                memCacheWidth: (80 * MediaQuery.of(context).devicePixelRatio).round(),
                memCacheHeight: (60 * MediaQuery.of(context).devicePixelRatio).round(),
                placeholder: (context, url) => Skeletonizer(
                  enabled: true,
                  ignoreContainers: true,
                  effect: const ShimmerEffect(
                    baseColor: Color(0xFF2A2A2A),
                    highlightColor: Color(0xFF3A3A3A),
                    duration: Duration(seconds: 1),
                  ),
                  child: Container(
                    color: kLightBlack,
                  ),
                ),
                errorWidget: (context, url, error) => Center(
                  child: Icon(
                    Icons.image_not_supported_outlined,
                    color: kWhiteColor.withValues(alpha: 0.3),
                    size: 24.sp,
                  ),
                ),
              );
            }
            // No image available
            return Center(
              child: Icon(
                Icons.image_outlined,
                color: kWhiteColor.withValues(alpha: 0.3),
                size: 24.sp,
              ),
            );
          },
          loading: () => Skeletonizer(
            enabled: true,
            ignoreContainers: true,
            effect: const ShimmerEffect(
              baseColor: Color(0xFF2A2A2A),
              highlightColor: Color(0xFF3A3A3A),
              duration: Duration(seconds: 1),
            ),
            child: Container(
              color: kLightBlack,
            ),
          ),
          error: (_, __) => Center(
            child: Icon(
              Icons.image_not_supported_outlined,
              color: kWhiteColor.withValues(alpha: 0.3),
              size: 24.sp,
            ),
          ),
        ),
      ),
    );
  }
}

// Status Display - LIVE or time until start
class _StatusDisplay extends ConsumerWidget {
  const _StatusDisplay({required this.tourEventCardModel});

  final GroupEventCardModel tourEventCardModel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    switch (tourEventCardModel.tourEventCategory) {
      case TourEventCategory.live:
        return _LiveStatus();
      case TourEventCategory.upcoming:
        return _UpcomingStatus(timeUntilStart: tourEventCardModel.timeUntilStart);
      case TourEventCategory.completed:
        return _CompletedStatus();
      case TourEventCategory.ongoing:
        return _OngoingStatus();
    }
  }
}

class _LiveStatus extends StatelessWidget {
  const _LiveStatus();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
          decoration: BoxDecoration(
            color: Colors.red,
            borderRadius: BorderRadius.circular(4.br),
          ),
          child: Text(
            'LIVE',
            style: AppTypography.textSmBold.copyWith(
              color: kWhiteColor,
              fontSize: 12.sp,
              letterSpacing: 0.5,
            ),
          ),
        ),
      ],
    );
  }
}

class _UpcomingStatus extends StatelessWidget {
  final String timeUntilStart;

  const _UpcomingStatus({required this.timeUntilStart});

  @override
  Widget build(BuildContext context) {
    return Text(
      timeUntilStart,
      style: AppTypography.textSmMedium.copyWith(
        color: kWhiteColor,
        fontSize: 14.sp,
      ),
    );
  }
}

class _CompletedStatus extends StatelessWidget {
  const _CompletedStatus();

  @override
  Widget build(BuildContext context) {
    return Text(
      "Completed",
      style: AppTypography.textSmMedium.copyWith(
        color: kWhiteColor70,
        fontSize: 14.sp,
      ),
    );
  }
}

class _OngoingStatus extends StatelessWidget {
  const _OngoingStatus();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
      decoration: BoxDecoration(
        color: kPrimaryColor.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(4.br),
        border: Border.all(color: kPrimaryColor, width: 1),
      ),
      child: Text(
        'ONGOING',
        style: AppTypography.textSmBold.copyWith(
          color: kPrimaryColor,
          fontSize: 12.sp,
          letterSpacing: 0.5,
        ),
      ),
    );
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
