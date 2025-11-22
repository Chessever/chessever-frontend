import 'package:cached_network_image/cached_network_image.dart';
import 'package:chessever2/providers/event_favorite_players_provider.dart';
import 'package:chessever2/providers/favorite_events_provider.dart';
import 'package:chessever2/screens/group_event/model/tour_event_card_model.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/location_service_provider.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/svg_asset.dart';
import 'package:chessever2/widgets/event_card/event_image_provider.dart';
import 'package:chessever2/widgets/heroine/no_padding_fade_shuttle_builder.dart';
import 'package:chessever2/widgets/svg_widget.dart';
import 'package:country_flags/country_flags.dart';
import 'package:flutter/material.dart';
import 'package:heroine/heroine.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:skeletonizer/skeletonizer.dart';

class EventCard extends ConsumerWidget {
  final GroupEventCardModel tourEventCardModel;
  final VoidCallback? onTap;
  /// Optional suffix to make hero tag unique when same event appears in multiple lists
  final String? heroTagSuffix;

  const EventCard({
    required this.tourEventCardModel,
    this.onTap,
    this.heroTagSuffix,
    super.key,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      onTap:
          onTap != null
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
            _EventImage(event: tourEventCardModel, heroTagSuffix: heroTagSuffix),
            SizedBox(width: 12.w),

            // Content in the middle
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Event name with live indicator
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Flexible(
                        child: Text(
                          tourEventCardModel.title,
                          style: AppTypography.textSmMedium.copyWith(
                            color: kWhiteColor,
                            fontSize: 14.sp,
                            height: 1.2,
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ),
                      _StatusIndicator(
                        tourEventCardModel: tourEventCardModel,
                      ),
                    ],
                  ),

                  SizedBox(height: 4.h),

                  // Event details (dates, time control, location/ELO)
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
                      // Show location for community events, ELO for broadcasts
                      if (tourEventCardModel.eventSource ==
                          EventSource.communityEvent) ...[
                        if (tourEventCardModel.location != null &&
                            tourEventCardModel.location!.isNotEmpty) ...[
                          _buildDotWidget(),
                          Flexible(
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.location_on_outlined,
                                  size: 12.sp,
                                  color: kWhiteColor70,
                                ),
                                SizedBox(width: 2.w),
                                Flexible(
                                  child: Text(
                                    tourEventCardModel.location!,
                                    style: AppTypography.textXsMedium.copyWith(
                                      color: kWhiteColor70,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ] else ...[
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

// Event Image Widget with cached network image or country flag for community events
class _EventImage extends ConsumerWidget {
  final GroupEventCardModel event;
  final String? heroTagSuffix;

  const _EventImage({required this.event, this.heroTagSuffix});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Include suffix to prevent duplicate hero tags when same event appears in multiple lists
    final suffix = heroTagSuffix != null ? '-$heroTagSuffix' : '';
    final heroTag = 'event-image-${event.id}$suffix';
    final isCommunity = event.eventSource == EventSource.communityEvent;

    if (isCommunity) {
      final countryCode = _extractCountryCode(ref, event.location);
      return Heroine(
        tag: heroTag,
        flightShuttleBuilder: const NoPaddingFadeShuttleBuilder(),
        child: _FlagEventImage(countryCode: countryCode),
      );
    }

    final imageAsync = ref.watch(eventImageProvider(event.id));

    return Heroine(
      tag: heroTag,
      flightShuttleBuilder: const NoPaddingFadeShuttleBuilder(),
      child: SizedBox(
        width: 90.w, // Give width constraint for AspectRatio to work in Row
        child: AspectRatio(
          aspectRatio: 3 / 2, // AspectRatio calculates height from width
          child: Container(
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
                    placeholder:
                        (context, url) => Skeletonizer(
                          enabled: true,
                          ignoreContainers: true,
                          effect: const ShimmerEffect(
                            baseColor: Color(0xFF2A2A2A),
                            highlightColor: Color(0xFF3A3A3A),
                            duration: Duration(seconds: 1),
                          ),
                          child: Container(color: kLightBlack),
                        ),
                    errorWidget:
                        (context, url, error) => Center(
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
              loading:
                  () => Skeletonizer(
                    enabled: true,
                    ignoreContainers: true,
                    effect: const ShimmerEffect(
                      baseColor: Color(0xFF2A2A2A),
                      highlightColor: Color(0xFF3A3A3A),
                      duration: Duration(seconds: 1),
                    ),
                    child: Container(color: kLightBlack),
                  ),
              error:
                  (_, __) => Center(
                    child: Icon(
                      Icons.image_not_supported_outlined,
                      color: kWhiteColor.withValues(alpha: 0.3),
                      size: 24.sp,
                    ),
                  ),
            ),
          ),
        ),
      ),
    );
  }

  String? _extractCountryCode(WidgetRef ref, String? location) {
    if (location == null || location.trim().isEmpty) return null;
    final locationService = ref.read(locationServiceProvider);

    // Try direct matches first
    final direct = locationService.getValidCountryCode(location.trim());
    if (direct.isNotEmpty) return direct.toUpperCase();

    // Try breaking down the location parts
    for (final part in location.split(RegExp(r'[,|/]'))) {
      final trimmed = part.trim();
      if (trimmed.isEmpty) continue;

      final fromCode = locationService.getValidCountryCode(trimmed);
      if (fromCode.isNotEmpty) return fromCode.toUpperCase();

      final fromName = locationService.getValidCountryCodeFromName(trimmed);
      if (fromName.isNotEmpty) return fromName.toUpperCase();
    }

    return null;
  }
}

class _FlagEventImage extends StatelessWidget {
  const _FlagEventImage({required this.countryCode});

  final String? countryCode;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 90.w, // Give width constraint for AspectRatio to work in Row
      child: AspectRatio(
        aspectRatio: 3 / 2,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(6.br),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF1F1C2C), Color(0xFF2C5364)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
              ),
              if (countryCode != null)
                CountryFlag.fromCountryCode(
                  countryCode!,
                  height: double.infinity,
                  width: double.infinity,
                ),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.black.withValues(alpha: 0.35),
                        Colors.black.withValues(alpha: 0.6),
                      ],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                ),
              ),
              if (countryCode == null)
                Center(
                  child: Icon(
                    Icons.flag_outlined,
                    color: kWhiteColor.withValues(alpha: 0.3),
                    size: 24.sp,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// Status Indicator - Subtle indicators next to event name
class _StatusIndicator extends ConsumerWidget {
  const _StatusIndicator({required this.tourEventCardModel});

  final GroupEventCardModel tourEventCardModel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    switch (tourEventCardModel.tourEventCategory) {
      case TourEventCategory.live:
        return _LiveIndicator();
      case TourEventCategory.upcoming:
        return _UpcomingIndicator(
          timeUntilStart: tourEventCardModel.timeUntilStart,
        );
      case TourEventCategory.completed:
        return _CompletedIndicator();
      case TourEventCategory.ongoing:
        return _OngoingIndicator();
    }
  }
}

class _LiveIndicator extends StatelessWidget {
  const _LiveIndicator();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(left: 6.w),
      child: Container(
        width: 8.w,
        height: 8.h,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: kPrimaryColor,
          boxShadow: [
            BoxShadow(
              color: kPrimaryColor.withValues(alpha: 0.4),
              blurRadius: 4,
              spreadRadius: 1,
            ),
          ],
        ),
      ),
    );
  }
}

class _OngoingIndicator extends StatelessWidget {
  const _OngoingIndicator();

  @override
  Widget build(BuildContext context) {
    // No dot indicator for ongoing - just nothing
    return SizedBox.shrink();
  }
}

class _UpcomingIndicator extends StatelessWidget {
  final String timeUntilStart;

  const _UpcomingIndicator({required this.timeUntilStart});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(left: 6.w),
      child: Text(
        timeUntilStart,
        style: AppTypography.textXsMedium.copyWith(
          color: kWhiteColor.withValues(alpha: 0.6),
          fontSize: 11.sp,
        ),
      ),
    );
  }
}

class _CompletedIndicator extends StatelessWidget {
  const _CompletedIndicator();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(left: 6.w),
      child: Text(
        "Completed",
        style: AppTypography.textXsMedium.copyWith(
          color: kWhiteColor.withValues(alpha: 0.5),
          fontSize: 11.sp,
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
    final eventFavoritePlayersAsync = ref.watch(
      eventFavoritePlayersProvider(tourEventCardModel.id),
    );

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
      orElse:
          () =>
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

        ref
            .read(favoriteEventsProvider.notifier)
            .toggleFavorite(
              eventId: tourEventCardModel.id,
              eventName: tourEventCardModel.title,
              timeControl: tourEventCardModel.timeControl,
              maxAvgElo:
                  tourEventCardModel.maxAvgElo > 0
                      ? tourEventCardModel.maxAvgElo
                      : null,
              dates:
                  tourEventCardModel.dates.isNotEmpty
                      ? tourEventCardModel.dates
                      : null,
            )
            .catchError((e) {
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
