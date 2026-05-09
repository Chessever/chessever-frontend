import 'package:cached_network_image/cached_network_image.dart';
import 'package:chessever2/providers/event_favorite_players_provider.dart';
import 'package:chessever2/providers/favorite_events_provider.dart';
import 'package:chessever2/screens/group_event/model/tour_event_card_model.dart';
import 'package:chessever2/services/analytics/analytics_service.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/location_service_provider.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/svg_asset.dart';
import 'package:chessever2/utils/time_utils.dart';
import 'package:chessever2/widgets/app_button.dart';
import 'package:chessever2/widgets/auth/auth_upgrade_sheet.dart';
import 'package:chessever2/widgets/event_card/event_context_menu.dart';
import 'package:chessever2/widgets/event_card/event_image_provider.dart';
import 'package:chessever2/widgets/event_card/event_next_round_provider.dart';
import 'package:chessever2/widgets/heroine/no_padding_fade_shuttle_builder.dart';
import 'package:chessever2/widgets/logo_pattern_fallback.dart';
import 'package:chessever2/widgets/svg_widget.dart';
import 'package:country_flags/country_flags.dart';
import 'package:flutter/material.dart';
import 'package:heroine/heroine.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:skeletonizer/skeletonizer.dart';

enum EventFavoritePlayersSource { automatic, cacheOnly }

class EventCard extends ConsumerWidget {
  final GroupEventCardModel tourEventCardModel;
  final VoidCallback? onTap;
  final bool showHeartIndicator;
  final EventFavoritePlayersSource favoritePlayersSource;

  /// Optional suffix to make hero tag unique when same event appears in multiple lists
  final String? heroTagSuffix;

  const EventCard({
    required this.tourEventCardModel,
    this.onTap,
    this.showHeartIndicator = false,
    this.favoritePlayersSource = EventFavoritePlayersSource.automatic,
    this.heroTagSuffix,
    super.key,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (onTap == null) {
      return _buildCard(context, ref);
    }

    return TappableScale(
      onTap: () {
        HapticFeedbackService.cardTap();
        onTap!();
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onLongPressStart: (details) {
          onEventCardLongPress(
            context: context,
            ref: ref,
            model: tourEventCardModel,
            globalPosition: details.globalPosition,
          );
        },
        child: _buildCard(context, ref),
      ),
    );
  }

  Widget _buildCard(BuildContext context, WidgetRef ref) {
    // Card renders shimmer until the next-round data is resolved, so the
    // layout lands in its final shape in one pass (no two-stage grow/shrink).
    // Completed, live, and calendar events don't render the countdown line,
    // so they skip the fetch entirely.
    final needsRound =
        tourEventCardModel.eventSource == EventSource.lichessBroadcast &&
        tourEventCardModel.tourEventCategory != TourEventCategory.completed &&
        tourEventCardModel.tourEventCategory != TourEventCategory.live;
    final nextRoundLoading =
        needsRound &&
        ref.watch(eventNextRoundProvider(tourEventCardModel.id)).isLoading;

    final body =
        ResponsiveHelper.isTablet
            ? _buildTabletGridCard(context, ref)
            : _buildPhoneCard(context, ref);

    return Skeletonizer(
      enabled: nextRoundLoading,
      effect:  ShimmerEffect(
        baseColor: context.colors.surfaceRecessed,
        highlightColor: context.colors.divider,
        duration: Duration(seconds: 1),
      ),
      child: body,
    );
  }

  /// Tablet grid layout: Image as background with text overlay
  Widget _buildTabletGridCard(BuildContext context, WidgetRef ref) {
    return Container(
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(12.br),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Background image
          _TabletEventBackground(
            event: tourEventCardModel,
            heroTagSuffix: heroTagSuffix,
          ),
          // Gradient overlay for text readability
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.3),
                    Colors.black.withValues(alpha: 0.85),
                  ],
                  stops: const [0.0, 0.4, 1.0],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
          ),
          // Content overlay
          Positioned(
            left: 12.sp,
            right: 12.sp,
            bottom: 12.sp,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  tourEventCardModel.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.textSmMedium.copyWith(
                    color: context.colors.textPrimary,
                    fontSize: 15.sp,
                    height: 1.3,
                    shadows: [
                      Shadow(
                        color: Colors.black.withValues(alpha: 0.5),
                        blurRadius: 4,
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 6.h),
                // Event details row
                Row(
                  children: [
                    Expanded(
                      child: _MetaLine(
                        dates: _compactDates(tourEventCardModel),
                        timeControlSpan: _timeControlSpan(
                          AppTypography.textXsMedium.copyWith(
                            color: context.colors.textPrimary.withValues(alpha: 0.9),
                          ),
                        ),
                        showLocation: false,
                        location: null,
                        showElo: tourEventCardModel.maxAvgElo > 0,
                        elo: tourEventCardModel.maxAvgElo,
                        onLight: true,
                      ),
                    ),
                    // Star icon
                    _StarWidget(
                      tourEventCardModel: tourEventCardModel,
                      showHeartIndicator: showHeartIndicator,
                      favoritePlayersSource: favoritePlayersSource,
                    ),
                  ],
                ),
                _NextRoundLine(
                  eventId: tourEventCardModel.id,
                  category: tourEventCardModel.tourEventCategory,
                  onLight: true,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Phone layout: Horizontal row with image on left
  Widget _buildPhoneCard(BuildContext context, WidgetRef ref) {
    final imageHeight = _EventImage.phoneImageHeight(context);

    return Container(
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(8.br),
      ),
      padding: EdgeInsets.all(6.sp),
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: imageHeight),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Event Image on the left
            _EventImage(
              event: tourEventCardModel,
              heroTagSuffix: heroTagSuffix,
            ),
            SizedBox(width: 10.w),

            // Content in the middle — hard-capped at 4 lines total:
            // title (2) + meta (1) + countdown/LIVE (1). Longer values
            // ellipsize so card height stays uniform across the list.
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    tourEventCardModel.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.textSmMedium.copyWith(
                      color: context.colors.textPrimary,
                      fontSize: 14.sp,
                      height: 1.2,
                    ),
                  ),

                  SizedBox(height: 4.h),

                  // Meta (dates · time-control · location/ELO) on a single line.
                  _MetaLine(
                    dates: _compactDates(tourEventCardModel),
                    timeControlSpan: _timeControlSpan(
                      AppTypography.textXsMedium.copyWith(
                        color: context.colors.textPrimaryMuted,
                      ),
                    ),
                    showLocation:
                        tourEventCardModel.eventSource ==
                            EventSource.communityEvent &&
                        tourEventCardModel.location != null &&
                        tourEventCardModel.location!.isNotEmpty,
                    location: tourEventCardModel.location,
                    showElo:
                        tourEventCardModel.eventSource !=
                            EventSource.communityEvent &&
                        tourEventCardModel.maxAvgElo > 0,
                    elo: tourEventCardModel.maxAvgElo,
                  ),
                  _NextRoundLine(
                    eventId: tourEventCardModel.id,
                    category: tourEventCardModel.tourEventCategory,
                  ),
                ],
              ),
            ),

            // Star icon on the right — relies on its own horizontal padding
            // for spacing, which keeps more room for title/meta to breathe.
            _StarWidget(
              tourEventCardModel: tourEventCardModel,
              showHeartIndicator: showHeartIndicator,
              favoritePlayersSource: favoritePlayersSource,
            ),
          ],
        ),
      ),
    );
  }

  String _compactDates(GroupEventCardModel model) {
    if (model.startDate != null || model.endDate != null) {
      return TimeUtils.formatDateRange(model.startDate, model.endDate);
    }
    return model.dates;
  }

  /// Inline time-control glyph for the [_MetaLine] [Text.rich] — lets the
  /// icon participate in ellipsizing so meta always fits one line.
  InlineSpan _timeControlSpan(TextStyle fallbackStyle) {
    final timeControl = tourEventCardModel.timeControl.toLowerCase();
    String? assetPath;
    if (timeControl.contains('blitz')) {
      assetPath = 'assets/pngs/blitz.png';
    } else if (timeControl.contains('rapid')) {
      assetPath = 'assets/pngs/rapid.png';
    } else if (timeControl.contains('classic') ||
        timeControl.contains('standard')) {
      assetPath = 'assets/pngs/classical.png';
    }

    if (assetPath == null) {
      return TextSpan(
        text: tourEventCardModel.timeControl,
        style: fallbackStyle,
      );
    }

    return WidgetSpan(
      alignment: PlaceholderAlignment.middle,
      child: Image.asset(
        assetPath,
        width: 14.sp,
        height: 14.sp,
        fit: BoxFit.contain,
      ),
    );
  }
}

/// Single-line meta row (dates · time-control · location/ELO). Using
/// [Text.rich] with inline widget spans lets the whole line ellipsize at the
/// end instead of wrapping and breaking the 4-line card budget.
class _MetaLine extends StatelessWidget {
  const _MetaLine({
    required this.dates,
    required this.timeControlSpan,
    required this.showLocation,
    required this.location,
    required this.showElo,
    required this.elo,
    this.onLight = false,
  });

  final String dates;
  final InlineSpan timeControlSpan;
  final bool showLocation;
  final String? location;
  final bool showElo;
  final int elo;
  final bool onLight;

  @override
  Widget build(BuildContext context) {
    final baseColor = onLight
        ? context.colors.textPrimary.withValues(alpha: 0.9)
        : context.colors.textPrimaryMuted;
    final style = AppTypography.textXsMedium.copyWith(
      color: baseColor,
      shadows: onLight
          ? [
              Shadow(
                color: Colors.black.withValues(alpha: 0.5),
                blurRadius: 3,
              ),
            ]
          : null,
    );

    final spans = <InlineSpan>[];
    if (dates.isNotEmpty) {
      spans.add(TextSpan(text: dates));
      spans.add(_dotSpan(baseColor));
    }
    spans.add(timeControlSpan);
    if (showLocation) {
      spans.add(_dotSpan(baseColor));
      spans.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Icon(
            Icons.location_on_outlined,
            size: 12.sp,
            color: baseColor,
          ),
        ),
      );
      spans.add(WidgetSpan(child: SizedBox(width: 2.w)));
      spans.add(TextSpan(text: location!));
    } else if (showElo) {
      spans.add(_dotSpan(baseColor));
      spans.add(TextSpan(text: 'Ø $elo'));
    }

    return Text.rich(
      TextSpan(style: style, children: spans),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }

  InlineSpan _dotSpan(Color color) {
    return WidgetSpan(
      alignment: PlaceholderAlignment.middle,
      child: Container(
        margin: EdgeInsets.symmetric(horizontal: 4.w),
        height: 6.h,
        width: 6.w,
        decoration: BoxDecoration(shape: BoxShape.circle, color: color),
      ),
    );
  }
}

// Event Image Widget with cached network image or country flag for community events
class _EventImage extends ConsumerWidget {
  final GroupEventCardModel event;
  final String? heroTagSuffix;

  const _EventImage({required this.event, this.heroTagSuffix});

  /// Fixed phone image sizing avoids LayoutBuilder/intrinsic sizing conflicts
  /// inside scrolling lists while keeping the image visually dominant.
  static double phoneImageWidth(BuildContext context) {
    double baseWidth = 108.w;
    if (MediaQuery.sizeOf(context).width < 360) {
      baseWidth = baseWidth.clamp(70.0, 90.0);
    }
    return baseWidth;
  }

  static double phoneImageHeight(BuildContext context) {
    return phoneImageWidth(context) * 4 / 5;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Include suffix to prevent duplicate hero tags when same event appears in multiple lists
    final suffix = heroTagSuffix != null ? '-$heroTagSuffix' : '';
    final heroTag = 'event-image-${event.id}$suffix';
    final isCommunity = event.eventSource == EventSource.communityEvent;
    final shouldUseHero = heroTagSuffix == null;

    if (isCommunity) {
      final countryCode = _extractCountryCode(ref, event.location);
      final flag = _FlagEventImage(countryCode: countryCode);
      if (!shouldUseHero) return flag;
      return Heroine(
        tag: heroTag,
        flightShuttleBuilder: const NoPaddingFadeShuttleBuilder(),
        child: flag,
      );
    }

    final imageAsync = ref.watch(eventImageProvider(event.id));

    final imageWidth = phoneImageWidth(context);
    final imageHeight = phoneImageHeight(context);
    final cacheWidth =
        (imageWidth * MediaQuery.devicePixelRatioOf(context)).toInt();

    final image = SizedBox(
      width: imageWidth,
      height: imageHeight,
      child: Container(
        decoration: BoxDecoration(
          color: context.colors.surfaceRecessed,
          borderRadius: BorderRadius.circular(6.br),
        ),
        clipBehavior: Clip.antiAlias,
        child: imageAsync.when(
          data: (imageData) {
            if (imageData.hasImage) {
              return CachedNetworkImage(
                imageUrl: imageData.imageUrl!,
                fit: BoxFit.cover,
                memCacheWidth: cacheWidth,
                fadeInDuration: const Duration(milliseconds: 300),
                fadeOutDuration: const Duration(milliseconds: 200),
                placeholder:
                    (context, url) => Skeletonizer(
                      enabled: true,
                      effect:  ShimmerEffect(
                        baseColor: context.colors.surfaceRecessed,
                        highlightColor: context.colors.divider,
                        duration: Duration(seconds: 1),
                      ),
                      child: Container(color: context.colors.surfaceRecessed),
                    ),
                errorWidget:
                    (context, url, error) =>
                        _buildFallbackFlag(imageData.fallbackCountryCode),
              );
            }
            return _buildFallbackFlag(imageData.fallbackCountryCode);
          },
          loading: () => Skeletonizer(
            enabled: true,
            effect: ShimmerEffect(
              baseColor: context.colors.skeleton,
              highlightColor: context.colors.divider,
              duration: const Duration(seconds: 1),
            ),
            child: Container(color: context.colors.surfaceRecessed),
          ),
          error: (_, __) => const LogoPatternFallback(),
        ),
      ),
    );

    if (!shouldUseHero) return image;

    return Heroine(
      tag: heroTag,
      flightShuttleBuilder: const NoPaddingFadeShuttleBuilder(),
      child: image,
    );
  }

  /// Builds a fallback widget - country flag if available, otherwise generic icon
  Widget _buildFallbackFlag(String? countryCode) {
    if (countryCode != null && countryCode.isNotEmpty) {
      // Use the same flag style as community events
      return Stack(
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
          CountryFlag.fromCountryCode(
            countryCode,
            theme: ImageTheme(height: double.infinity, width: double.infinity),
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
        ],
      );
    }

    // No country code available - show logo pattern
    return const LogoPatternFallback();
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
    final imageWidth = _EventImage.phoneImageWidth(context);
    final imageHeight = _EventImage.phoneImageHeight(context);

    return SizedBox(
      width: imageWidth,
      height: imageHeight,
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
                theme: ImageTheme(
                  height: double.infinity,
                  width: double.infinity,
                ),
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
            if (countryCode == null) const LogoPatternFallback(),
          ],
        ),
      ),
    );
  }
}

/// Background image widget for tablet grid layout - fills entire card
class _TabletEventBackground extends ConsumerWidget {
  final GroupEventCardModel event;
  final String? heroTagSuffix;

  const _TabletEventBackground({required this.event, this.heroTagSuffix});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isCommunity = event.eventSource == EventSource.communityEvent;

    if (isCommunity) {
      final countryCode = _extractCountryCode(ref, event.location);
      return _buildFlagBackground(countryCode);
    }

    final imageAsync = ref.watch(eventImageProvider(event.id));

    return imageAsync.when(
      data: (imageData) {
        if (imageData.hasImage) {
          final cacheWidth =
              (MediaQuery.sizeOf(context).width *
                      MediaQuery.devicePixelRatioOf(context))
                  .toInt();
          return CachedNetworkImage(
            imageUrl: imageData.imageUrl!,
            fit: BoxFit.cover,
            memCacheWidth: cacheWidth,
            fadeInDuration: const Duration(milliseconds: 300),
            fadeOutDuration: const Duration(milliseconds: 200),
            placeholder: (context, url) => _buildLoadingBackground(context),
            errorWidget:
                (context, url, error) =>
                    _buildFlagBackground(imageData.fallbackCountryCode),
          );
        }
        return _buildFlagBackground(imageData.fallbackCountryCode);
      },
      loading: () => _buildLoadingBackground(context),
      error: (_, __) =>  LogoPatternFallback(),
    );
  }

  Widget _buildLoadingBackground(BuildContext context) {
    return Skeletonizer(
      enabled: true,
      effect: const ShimmerEffect(
        baseColor: Color(0xFF2A2A2A),
        highlightColor: Color(0xFF3A3A3A),
        duration: Duration(seconds: 1),
      ),
      child: ColoredBox(color: context.colors.surface),
    );
  }

  Widget _buildFlagBackground(String? countryCode) {
    return Stack(
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
        if (countryCode != null && countryCode.isNotEmpty)
          CountryFlag.fromCountryCode(
            countryCode,
            theme: ImageTheme(height: double.infinity, width: double.infinity),
          ),
        if (countryCode == null || countryCode.isEmpty)
          const LogoPatternFallback(),
      ],
    );
  }

  String? _extractCountryCode(WidgetRef ref, String? location) {
    if (location == null || location.trim().isEmpty) return null;
    final locationService = ref.read(locationServiceProvider);

    final direct = locationService.getValidCountryCode(location.trim());
    if (direct.isNotEmpty) return direct.toUpperCase();

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

/// "LIVE" label shown on the third line of the card while an event is
/// actively running — replaces the next-round countdown for live events.
class _LiveLabel extends StatelessWidget {
  const _LiveLabel({required this.onLight});

  final bool onLight;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(top: 3.h),
      child: Text(
        'LIVE',
        style: AppTypography.textXxsMedium.copyWith(
          color: kPrimaryColor,
          fontSize: 11.sp,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
          shadows:
              onLight
                  ? [
                    Shadow(
                      color: Colors.black.withValues(alpha: 0.5),
                      blurRadius: 3,
                    ),
                  ]
                  : null,
        ),
      ),
    );
  }
}

class _StarWidget extends ConsumerWidget {
  const _StarWidget({
    required this.tourEventCardModel,
    required this.showHeartIndicator,
    required this.favoritePlayersSource,
  });

  final GroupEventCardModel tourEventCardModel;
  final bool showHeartIndicator;
  final EventFavoritePlayersSource favoritePlayersSource;

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
    final favoritesCount = favoritesAsync.valueOrNull?.length ?? 0;

    final shouldResolveFavoritePlayers =
        !isStarred &&
        (favoritePlayersSource == EventFavoritePlayersSource.automatic ||
            showHeartIndicator);
    final eventFavoritePlayers =
        shouldResolveFavoritePlayers
            ? _watchEventFavoritePlayers(context, ref)
            : const EventFavoritePlayers.empty();

    // Priority: Star icon (user favorited) ALWAYS takes precedence
    // Heart icon shows ONLY when NOT starred but has favorite players
    final bool showHeart =
        showHeartIndicator && !isStarred && eventFavoritePlayers.hasFavorites;
    final bool showFilledStar = isStarred;

    // Heart icon is NOT tappable - it's just informational
    if (showHeart) {
      return Padding(
        padding: EdgeInsets.symmetric(horizontal: 5.w),
        child: _HeartIconWithCount(count: eventFavoritePlayers.count),
      );
    }
    return InkWell(
      onTap: () async {
        final allowed = await requireFullAuthGuard(context);
        if (!allowed) return;

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
            .then((isFavorited) {
              final nextCount =
                  isFavorited
                      ? favoritesCount + 1
                      : (favoritesCount - 1).clamp(0, favoritesCount);
              AnalyticsService.instance.trackEventDetached(
                'Event Favorite Toggled',
                properties: {
                  'event_id': tourEventCardModel.id,
                  'event_name': tourEventCardModel.title,
                  'time_control': tourEventCardModel.timeControl,
                  'event_source': tourEventCardModel.eventSource.name,
                  'tour_category': tourEventCardModel.tourEventCategory.name,
                  'is_favorited': isFavorited,
                  'new_favorites_total': nextCount,
                  if (tourEventCardModel.location != null &&
                      tourEventCardModel.location!.isNotEmpty)
                    'location': tourEventCardModel.location,
                  if (tourEventCardModel.maxAvgElo > 0)
                    'max_avg_elo': tourEventCardModel.maxAvgElo,
                },
              );
              return isFavorited;
            })
            .catchError((e) {
              debugPrint('[EventCard] Error toggling favorite: $e');
              // Silently handle error - state will be corrected on next refresh
              return false;
            });
      },
      child: Padding(
        padding: EdgeInsets.fromLTRB(6.w, 6.h, 2.w, 6.h),
        child: SvgWidget(
          showFilledStar ? SvgAsset.starFilledIcon : SvgAsset.starIcon,
          semanticsLabel: 'Favorite Icon',
          height: 20.h,
          width: 20.w,
        ),
      ),
    );
  }

  EventFavoritePlayers _watchEventFavoritePlayers(
    BuildContext context,
    WidgetRef ref,
  ) {
    final cached = ref.watch(
      eventFavoritePlayersCacheProvider.select(
        (cache) => cache[tourEventCardModel.id],
      ),
    );

    if (cached != null ||
        favoritePlayersSource == EventFavoritePlayersSource.cacheOnly) {
      return cached ?? const EventFavoritePlayers.empty();
    }

    final eventFavoritePlayersAsync = ref.watch(
      eventFavoritePlayersProvider(tourEventCardModel.id),
    );

    return eventFavoritePlayersAsync.maybeWhen(
      data: (data) {
        Future.microtask(() {
          if (!context.mounted) return;
          ref
              .read(eventFavoritePlayersCacheProvider.notifier)
              .updateCache(tourEventCardModel.id, data);
        });
        return data;
      },
      orElse: () => const EventFavoritePlayers.empty(),
    );
  }
}

class _HeartIconWithCount extends StatelessWidget {
  const _HeartIconWithCount({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Stack(
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
              color: context.colors.textPrimary,
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
    );
  }
}

/// Shared 1Hz ticker that drives sub-24h round countdowns. Using a single
/// periodic stream across every visible card avoids spawning N timers in a
/// long event list.
final _eventCountdownTickProvider = StreamProvider.autoDispose<DateTime>((ref) {
  return Stream<DateTime>.periodic(
    const Duration(seconds: 1),
    (_) => DateTime.now(),
  );
});

/// Third line of the event card: "Round N · {when}" for the nearest upcoming
/// round. Hidden for completed events, community/calendar events, and when no
/// round has a known future `starts_at`.
class _NextRoundLine extends ConsumerWidget {
  const _NextRoundLine({
    required this.eventId,
    required this.category,
    this.onLight = false,
  });

  final String eventId;
  final TourEventCategory category;

  /// True when rendering over the tablet image background (bumps contrast
  /// with a soft shadow and higher-alpha text).
  final bool onLight;

  static const Duration _countdownThreshold = Duration(hours: 24);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (category == TourEventCategory.completed) {
      return const SizedBox.shrink();
    }
    if (eventId.startsWith('cal_event_')) {
      return const SizedBox.shrink();
    }

    if (category == TourEventCategory.live) {
      return _LiveLabel(onLight: onLight);
    }

    final nextRoundAsync = ref.watch(eventNextRoundProvider(eventId));
    final nextRound = nextRoundAsync.valueOrNull;
    final isLoading = nextRoundAsync.isLoading;

    // Once the fetch has settled with no future round, hide the line.
    if (!isLoading && nextRound == null) return const SizedBox.shrink();

    // Placeholder values keep the shimmer skeleton the same shape/size as the
    // eventually-rendered line so the card doesn't reflow when data lands.
    final now = DateTime.now();
    final resolvedStartsAt =
        nextRound?.startsAt ?? now.add(const Duration(hours: 4));
    final remaining = resolvedStartsAt.difference(now);

    if (nextRound != null) {
      if (!remaining.isNegative && remaining.inSeconds == 0) {
        return const SizedBox.shrink();
      }
      if (remaining.isNegative) return const SizedBox.shrink();
    }

    final isCountdown = remaining < _countdownThreshold;

    // Only subscribe to the 1Hz ticker when we're actually rendering a real
    // live countdown — far-out rounds and placeholder/shimmer states don't
    // need per-second rebuilds.
    if (isCountdown && nextRound != null) {
      ref.watch(_eventCountdownTickProvider);
    }

    final label = _formatTrailing(resolvedStartsAt, isCountdown);
    final roundName = (nextRound?.name ?? 'Round 1').trim();
    final showName = roundName.isNotEmpty;

    final baseColor = onLight
        ? context.colors.textPrimary.withValues(alpha: 0.9)
        : context.colors.textPrimaryMuted;

    final textStyle = AppTypography.textXxsMedium.copyWith(
      color: baseColor,
      fontSize: 11.sp,
      letterSpacing: 0.1,
      shadows:
          onLight
              ? [
                Shadow(
                  color: Colors.black.withValues(alpha: 0.5),
                  blurRadius: 3,
                ),
              ]
              : null,
    );

    return Padding(
      padding: EdgeInsets.only(top: 3.h),
      child:
          showName
              ? Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Flexible(
                    child: Text(
                      roundName,
                      style: textStyle.copyWith(fontWeight: FontWeight.w600),
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text('  ·  ', style: textStyle),
                  Text(label, style: textStyle, maxLines: 1, softWrap: false),
                ],
              )
              : Text(
                label,
                style: textStyle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
    );
  }

  String _formatTrailing(DateTime startsAt, bool isCountdown) {
    if (isCountdown) {
      final remaining = startsAt.difference(DateTime.now());
      return 'starts in ${_formatCountdown(remaining)}';
    }
    return 'starts ${_formatAbsolute(startsAt)}';
  }

  /// Countdown formatter. Shows at most two units so the line stays scannable:
  /// - ≥ 1h → "Xh Ym"    (drop seconds — noise at that scale)
  /// - ≥ 1m → "Xm Ys"
  /// - < 1m → "Ys"
  String _formatCountdown(Duration d) {
    final total = d.inSeconds.clamp(0, 24 * 3600);
    final hours = total ~/ 3600;
    final minutes = (total % 3600) ~/ 60;
    final seconds = total % 60;

    if (hours > 0) {
      return '${hours}h ${minutes}m';
    }
    if (minutes > 0) {
      return '${minutes}m ${seconds}s';
    }
    return '${seconds}s';
  }

  String _formatAbsolute(DateTime startsAt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final startDay = DateTime(startsAt.year, startsAt.month, startsAt.day);
    final dayDelta = startDay.difference(today).inDays;

    final time = '${_twoDigit(startsAt.hour)}:${_twoDigit(startsAt.minute)}';

    if (dayDelta == 1) return 'tomorrow $time';

    final weekday = _weekdayShort(startsAt.weekday);
    final month = _monthShort(startsAt.month);
    if (startsAt.year == now.year) {
      return '$weekday $month ${startsAt.day}, $time';
    }
    return '$weekday $month ${startsAt.day}, ${startsAt.year}';
  }

  static String _twoDigit(int n) => n.toString().padLeft(2, '0');

  static String _weekdayShort(int weekday) {
    const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return names[(weekday - 1).clamp(0, 6)];
  }

  static String _monthShort(int month) {
    const names = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return names[(month - 1).clamp(0, 11)];
  }
}
