import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:chessever2/providers/event_favorite_players_provider.dart';
import 'package:chessever2/providers/favorite_events_provider.dart';
import 'package:chessever2/screens/group_event/model/tour_event_card_model.dart';
import 'package:chessever2/screens/group_event/providers/live_group_broadcast_id_provider.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/location_service_provider.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/svg_asset.dart';
import 'package:chessever2/utils/time_utils.dart';
import 'package:chessever2/widgets/app_button.dart';
import 'package:chessever2/widgets/card_context_menu.dart';
import 'package:chessever2/widgets/event_card/event_context_menu.dart';
import 'package:chessever2/widgets/event_card/event_image_provider.dart';
import 'package:chessever2/widgets/event_card/event_next_round_provider.dart';
import 'package:chessever2/widgets/heroine/no_padding_fade_shuttle_builder.dart';
import 'package:chessever2/widgets/svg_widget.dart';
import 'package:chessever2/widgets/time_control_glyph.dart';
import 'package:country_flags/country_flags.dart';
import 'package:flutter/gestures.dart' show LongPressDownDetails;
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

  /// Overrides the right-side star affordance for surfaces that use EventCard
  /// as a section header rather than an event-favorite entry point.
  final Widget? trailingWidget;

  /// Optional suffix to make hero tag unique when same event appears in multiple lists
  final String? heroTagSuffix;

  /// Forces the phone (compact) layout regardless of tablet detection.
  /// The tablet layout uses `Stack(fit: StackFit.expand)` which needs a
  /// bounded height — passing this card into a SliverList (e.g. as a section
  /// header) leaves height unbounded and crashes layout. Call sites that
  /// embed the card inside a vertical list must set this to true.
  final bool forceCompactLayout;

  const EventCard({
    required this.tourEventCardModel,
    this.onTap,
    this.showHeartIndicator = false,
    this.favoritePlayersSource = EventFavoritePlayersSource.automatic,
    this.trailingWidget,
    this.heroTagSuffix,
    this.forceCompactLayout = false,
    super.key,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (onTap == null) {
      return _buildCard(context, ref);
    }

    // The long-press sits inside the press-scale: the menu measures the card
    // as it is painted, mid-squeeze, and the lifted copy rises from exactly
    // that size instead of jumping back to rest first.
    return TappableScale(
      onTap: () {
        HapticFeedbackService.cardTap();
        onTap!();
      },
      child: _EventCardMenuTrigger(
        model: tourEventCardModel,
        onOpen: onTap!,
        previewBuilder:
            (size) => SizedBox.fromSize(
              size: size,
              // A second, inert copy of this card: no gestures (onTap null)
              // and no Heroine (a suffix switches the hero off), so the
              // menu's copy can never fly or claim this card's hero tag.
              child: EventCard(
                tourEventCardModel: tourEventCardModel,
                showHeartIndicator: showHeartIndicator,
                favoritePlayersSource: favoritePlayersSource,
                trailingWidget: trailingWidget,
                heroTagSuffix: '${heroTagSuffix ?? 'card'}-menu',
                forceCompactLayout: forceCompactLayout,
              ),
            ),
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
    // Shimmer only while the FIRST resolve is in flight. Invalidations (the
    // For You feed re-resolves the round line on its refresh paths) keep the
    // previous value via AsyncValue.copyWithPrevious, so a refresh must not
    // flip an already-rendered card back to its skeleton.
    final nextRoundAsync =
        needsRound
            ? ref.watch(eventNextRoundProvider(tourEventCardModel.id))
            : null;
    final nextRoundLoading =
        nextRoundAsync != null &&
        nextRoundAsync.isLoading &&
        !nextRoundAsync.hasValue;

    final body =
        (ResponsiveHelper.isTablet && !forceCompactLayout)
            ? _buildTabletGridCard(context, ref)
            : _buildPhoneCard(context, ref);

    return Skeletonizer(
      enabled: nextRoundLoading,
      effect: ShimmerEffect(
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
                    color: Colors.white,
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
                            color: Colors.white.withValues(alpha: 0.9),
                          ),
                          overImage: true,
                        ),
                        showLocation: false,
                        location: null,
                        showElo: tourEventCardModel.maxAvgElo > 0,
                        elo: tourEventCardModel.maxAvgElo,
                        onLight: true,
                      ),
                    ),
                    // Right-side action (favorite star by default).
                    trailingWidget ??
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
        // Light theme adds a faint border + subtle drop shadow so the white
        // card pops off the light-grey scaffold (matches the settings-page
        // _SettingCard look). Dark theme is unchanged.
        border:
            context.isLightTheme
                ? Border.all(
                  color: context.colors.divider.withValues(alpha: 0.4),
                )
                : null,
        boxShadow:
            context.isLightTheme
                ? [
                  BoxShadow(
                    color: context.colors.shadow,
                    blurRadius: 8,
                    offset: const Offset(0, 1),
                  ),
                ]
                : null,
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

            // Right-side action (favorite star by default). The player Games
            // tab overrides this with a smaller collapse affordance so the
            // title/meta line keeps more breathing room.
            trailingWidget ??
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
  /// [overImage] marks the tablet card, whose meta sits on a black photo
  /// scrim in both themes and so keeps the original (dark-stage) art.
  InlineSpan _timeControlSpan(
    TextStyle fallbackStyle, {
    bool overImage = false,
  }) {
    final assetPath = TimeControlGlyph.assetForLabel(
      tourEventCardModel.timeControl,
    );

    if (assetPath == null) {
      return TextSpan(
        text: tourEventCardModel.timeControl,
        style: fallbackStyle,
      );
    }

    return WidgetSpan(
      alignment: PlaceholderAlignment.middle,
      child: TimeControlGlyph(
        assetPath,
        size: 14.sp,
        onDark: overImage ? true : null,
      ),
    );
  }
}

/// Owns an event card's long-press: the card lifts in place into the shared
/// focus menu ([CardContextMenu.open]) with Open, favorite, No Spoilers,
/// Share, Copy PGN and My Space.
///
/// The menu opens the instant the long-press fires; nothing waits on the
/// network, so the press is always answered (haptic, lift, veil) on time.
///
/// The No Spoilers row needs the event's tours, a network lookup. It starts
/// once a finger has rested on the card past any ordinary tap
/// ([_kWarmAfter]), so the answer is usually in hand by the long-press and the
/// row carries its real label. If it is still in flight, the row opens in its
/// default "Turn on" form and settles the tours when chosen
/// ([eventMenuActions]' `pendingTourIds`), so it is never dropped. A scroll
/// never rests, so scrolling a list costs no lookups. Tour ids are kept for
/// the life of this card; No Spoilers states are read live at every open, so
/// the label is never stale.
class _EventCardMenuTrigger extends ConsumerStatefulWidget {
  const _EventCardMenuTrigger({
    required this.model,
    required this.onOpen,
    required this.previewBuilder,
    required this.child,
  });

  final GroupEventCardModel model;
  final VoidCallback onOpen;

  /// The lifted copy of the card, sized to the card as it sits on screen.
  final Widget Function(Size size) previewBuilder;
  final Widget child;

  @override
  ConsumerState<_EventCardMenuTrigger> createState() =>
      _EventCardMenuTriggerState();
}

/// How long a finger must rest before the tour lookup starts: past any
/// ordinary tap (so taps never reach the backend), and still ~220ms ahead of
/// the 500ms long-press deadline, so the answer is usually in hand when the
/// menu opens.
const Duration _kWarmAfter = Duration(milliseconds: 280);

class _EventCardMenuTriggerState extends ConsumerState<_EventCardMenuTrigger> {
  Timer? _warmTimer;

  /// The lookup for [widget.model], in flight or landed. Cleared when it
  /// lands empty (possibly a failure), so the next press asks again.
  Future<List<String>>? _tourIds;

  /// The tours once a lookup has landed with some: what the menu labels the
  /// No Spoilers row from without waiting.
  List<String>? _knownTourIds;

  @override
  void didUpdateWidget(covariant _EventCardMenuTrigger oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A recycled list slot can now hold a different event. An answer still in
    // flight for the old one is ignored when it lands (see [_loadTourIds]).
    if (oldWidget.model.id != widget.model.id) {
      _warmTimer?.cancel();
      _tourIds = null;
      _knownTourIds = null;
    }
  }

  @override
  void dispose() {
    _warmTimer?.cancel();
    super.dispose();
  }

  Future<List<String>> _loadTourIds() {
    final pending = _tourIds;
    if (pending != null) return pending;
    late final Future<List<String>> future;
    future = loadEventMenuTourIds(ref, widget.model)
        // Belt and braces: the loader never throws, but a stored failed
        // future would break every later press on this card.
        .catchError((Object _) => const <String>[])
        .then((ids) {
          // Only this card's current lookup may write back.
          if (mounted && identical(_tourIds, future)) {
            if (ids.isEmpty) {
              _tourIds = null;
            } else {
              _knownTourIds = ids;
            }
          }
          return ids;
        });
    _tourIds = future;
    return future;
  }

  void _onPressDown(LongPressDownDetails _) {
    _warmTimer?.cancel();
    if (!hasBroadcastActions(widget.model) || _knownTourIds != null) return;
    _warmTimer = Timer(_kWarmAfter, () {
      if (mounted) _loadTourIds();
    });
  }

  void _onPressCancel() => _warmTimer?.cancel();

  void _openMenu(LongPressStartDetails details) {
    _warmTimer?.cancel();
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return;
    final model = widget.model;
    final knownTourIds = _knownTourIds;
    // Tours not in hand yet keep loading behind the open menu (a screen
    // reader's long-press starts the lookup here); the No Spoilers row
    // settles them if it is chosen first.
    final pendingTourIds =
        hasBroadcastActions(model) && knownTourIds == null
            ? _loadTourIds()
            : null;
    unawaited(
      CardContextMenu.open(
        context,
        actions:
            (menuContext) => eventMenuActions(
              context: menuContext,
              ref: ref,
              model: model,
              tourIds: knownTourIds ?? const <String>[],
              pendingTourIds: pendingTourIds,
              onOpen: widget.onOpen,
            ),
        preview: widget.previewBuilder(box.size),
        onPreviewTap: widget.onOpen,
        // A press on the card's right half opens the menu against that edge.
        // A screen reader's long-press action reports no position.
        origin:
            details.globalPosition == Offset.zero
                ? null
                : details.globalPosition,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPressDown: _onPressDown,
      onLongPressCancel: _onPressCancel,
      onLongPressStart: _openMenu,
      child: widget.child,
    );
  }
}

/// Single-line meta row (dates · time-control · location/ELO). Dates (and
/// location when present) may ellipsize under width pressure; avg Elo is kept
/// outside that overflow so trailing digits never clip on long cross-month
/// ranges.
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
    // `onLight` is misnamed — it really means "rendered over the dark image
    // gradient on the tablet card," so the text always needs to be a light
    // ink with a soft shadow regardless of theme.
    final baseColor =
        onLight
            ? Colors.white.withValues(alpha: 0.9)
            : context.colors.textPrimaryMuted;
    final style = AppTypography.textXsMedium.copyWith(
      color: baseColor,
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

    // When Elo is shown, pin it outside the flexible/ellipsizing prefix so
    // long multi-month date strings cannot eat the trailing digits.
    if (showElo) {
      final prefix = <InlineSpan>[];
      if (dates.isNotEmpty) {
        prefix.add(TextSpan(text: dates));
      }
      // Layout is the shipped one, deliberately: dot, glyph and the
      // dot + Elo tail are separate paragraphs. Merging them into one line
      // box moved the title, glyph, dots and the LIVE/next-round line by
      // ~1px, which the no-layout-shift rule forbids.
      return Row(
        children: [
          Flexible(
            child: Text.rich(
              TextSpan(style: style, children: prefix),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              softWrap: false,
            ),
          ),
          if (dates.isNotEmpty)
            Text.rich(TextSpan(style: style, children: [_dotSpan(baseColor)])),
          Text.rich(TextSpan(style: style, children: [timeControlSpan])),
          Text.rich(
            TextSpan(
              style: style,
              children: [
                _dotSpan(baseColor),
                TextSpan(text: 'Ø $elo'),
              ],
            ),
          ),
        ],
      );
    }

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
      final flag = _FlagEventImage(
        countryCode: countryCode,
        fallbackTitle: event.title,
      );
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
          // Subtle 1px image outline so the photo edge reads cleanly on the
          // white card in light theme. Pure black-at-0.1 is the convention
          // (avoid tinted neutrals — they look like dirt at the edge).
          // Dark theme keeps no border to preserve the original look.
          border:
              context.isLightTheme
                  ? Border.all(color: Colors.black.withValues(alpha: 0.1))
                  : null,
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
                      effect: ShimmerEffect(
                        baseColor: context.colors.surfaceRecessed,
                        highlightColor: context.colors.divider,
                        duration: Duration(seconds: 1),
                      ),
                      child: Container(color: context.colors.surfaceRecessed),
                    ),
                errorWidget:
                    (context, url, error) =>
                        _buildFallbackFlag(
                          context,
                          imageData.fallbackCountryCode,
                        ),
              );
            }
            return _buildFallbackFlag(
              context,
              imageData.fallbackCountryCode,
            );
          },
          loading:
              () => Skeletonizer(
                enabled: true,
                effect: ShimmerEffect(
                  baseColor: context.colors.skeleton,
                  highlightColor: context.colors.divider,
                  duration: const Duration(seconds: 1),
                ),
                child: Container(color: context.colors.surfaceRecessed),
              ),
          error: (_, __) => _EventFallbackArtwork(title: event.title),
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
  Widget _buildFallbackFlag(BuildContext context, String? countryCode) {
    if (countryCode != null && countryCode.isNotEmpty) {
      // Use the same flag style as community events
      return Stack(
        fit: StackFit.expand,
        children: [
          Container(
            decoration: BoxDecoration(
              gradient: _thumbnailGround(context),
            ),
          ),
          CountryFlag.fromCountryCode(
            countryCode,
            theme: ImageTheme(height: double.infinity, width: double.infinity),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(gradient: _thumbnailScrim(context)),
            ),
          ),
        ],
      );
    }

    return _EventFallbackArtwork(title: event.title);
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
  const _FlagEventImage({
    required this.countryCode,
    required this.fallbackTitle,
  });

  final String? countryCode;
  final String fallbackTitle;

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
              decoration: BoxDecoration(gradient: _thumbnailGround(context)),
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
                decoration: BoxDecoration(gradient: _thumbnailScrim(context)),
              ),
            ),
            if (countryCode == null)
              _EventFallbackArtwork(title: fallbackTitle),
          ],
        ),
      ),
    );
  }
}

/// Dark ground under a flag (phone thumbnail and tablet background): the
/// shipped dark-mode colours, unchanged.
const List<Color> _kDarkFlagGround = [Color(0xFF1F1C2C), Color(0xFF2C5364)];

/// Dark ground under the initials fallback artwork: the shipped dark-mode
/// colours, unchanged.
const List<Color> _kDarkFallbackGround = [
  Color(0xFF202329),
  Color(0xFF303846),
];

/// Ground behind a phone thumbnail's flag: the shipped ground in dark, a
/// recessed mint step on paper so a flag-less card is not a dark hole.
LinearGradient _thumbnailGround(BuildContext context) {
  final colors = context.colors;
  return LinearGradient(
    colors:
        context.isLightTheme
            ? [colors.surfaceRecessed, colors.background]
            : _kDarkFlagGround,
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

/// Dim over a phone thumbnail's flag. Nothing is written on it, so paper
/// only needs a whisper of ink to seat the flag; the black 0.35–0.6 wash
/// turned every flag muddy on the light card.
LinearGradient _thumbnailScrim(BuildContext context) {
  final ink = context.colors.textPrimary;
  return LinearGradient(
    colors:
        context.isLightTheme
            ? [ink.withValues(alpha: 0.04), ink.withValues(alpha: 0.12)]
            : [
              Colors.black.withValues(alpha: 0.35),
              Colors.black.withValues(alpha: 0.6),
            ],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );
}

class _EventFallbackArtwork extends StatelessWidget {
  const _EventFallbackArtwork({required this.title, this.overImage = false});

  final String title;

  /// Tablet cards write white titles over this artwork under a black scrim,
  /// so there it stays the dark slab in both themes.
  final bool overImage;

  @override
  Widget build(BuildContext context) {
    final paper = context.isLightTheme && !overImage;
    final colors = context.colors;
    final ink = paper ? colors.textPrimary : Colors.white;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors:
              paper
                  ? [colors.surfaceRecessed, colors.background]
                  : _kDarkFallbackGround,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Container(
          width: 42.w,
          height: 42.w,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: ink.withValues(alpha: paper ? 0.06 : 0.12),
            shape: BoxShape.circle,
            border: Border.all(
              color: ink.withValues(alpha: paper ? 0.16 : 0.22),
            ),
          ),
          child: Text(
            _eventInitials(title),
            maxLines: 1,
            overflow: TextOverflow.clip,
            style: AppTypography.textSmSemiBold.copyWith(
              color: ink,
              fontSize: 15.sp,
            ),
          ),
        ),
      ),
    );
  }

  static String _eventInitials(String title) {
    final tokens = title
        .split('|')
        .first
        .replaceAll(RegExp(r'[^A-Za-z0-9]+'), ' ')
        .split(RegExp(r'\s+'))
        .map((token) => token.trim())
        .where((token) => token.isNotEmpty && int.tryParse(token) == null)
        .toList(growable: false);
    if (tokens.isEmpty) return '?';
    return tokens.take(2).map((token) => token[0].toUpperCase()).join();
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
      return _buildFlagBackground(countryCode, fallbackTitle: event.title);
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
                (context, url, error) => _buildFlagBackground(
                  imageData.fallbackCountryCode,
                  fallbackTitle: event.title,
                ),
          );
        }
        return _buildFlagBackground(
          imageData.fallbackCountryCode,
          fallbackTitle: event.title,
        );
      },
      loading: () => _buildLoadingBackground(context),
      error:
          (_, __) => _EventFallbackArtwork(title: event.title, overImage: true),
    );
  }

  Widget _buildLoadingBackground(BuildContext context) {
    return Skeletonizer(
      enabled: true,
      // Dark theme keeps the original tuned greys; only light theme swaps to
      // theme-aware tokens so the shimmer doesn't paint as a dark patch.
      effect:
          context.isLightTheme
              ? ShimmerEffect(
                baseColor: context.colors.skeleton,
                highlightColor: context.colors.divider,
                duration: const Duration(seconds: 1),
              )
              : const ShimmerEffect(
                baseColor: Color(0xFF2A2A2A),
                highlightColor: Color(0xFF3A3A3A),
                duration: Duration(seconds: 1),
              ),
      child: ColoredBox(color: context.colors.surface),
    );
  }

  Widget _buildFlagBackground(
    String? countryCode, {
    required String fallbackTitle,
  }) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: _kDarkFlagGround,
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
          _EventFallbackArtwork(title: fallbackTitle, overImage: true),
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
          // Over the dark image keep raw brand cyan; on the theme surface use
          // the contrast-safe accent ink (identical to cyan in dark mode).
          color: onLight ? kPrimaryColor : context.colors.accentText,
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
      data: (events) => eventIsFavorited(events, tourEventCardModel),
      orElse: () => false,
      skipLoadingOnRefresh: true,
      skipLoadingOnReload: true,
    );

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
      // Same path as the focus menu's "Add to favorites" row.
      onTap:
          () => toggleEventFavorite(
            context: context,
            ref: ref,
            model: tourEventCardModel,
          ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(6.w, 6.h, 2.w, 6.h),
        child: SvgWidget(
          showFilledStar ? SvgAsset.starFilledIcon : SvgAsset.starIcon,
          semanticsLabel: 'Favorite Icon',
          height: 20.h,
          width: 20.w,
          // Filled star is gold; outline star looks fine when re-tinted by
          // the SvgWidget light-mode default. We only need to preserve when
          // showing the filled (yellow) variant.
          preserveOriginalColors: showFilledStar,
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
        // Heart icon — keep the red fill in both themes.
        SvgWidget(
          SvgAsset.favouriteRedIcon,
          semanticsLabel: 'Has Favorite Players',
          height: 20.h,
          width: 20.w,
          preserveOriginalColors: true,
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

    // The category prop only re-derives on feed refreshes, so it can lag
    // right as a round starts; the strict live-ids stream is the authority.
    // Never render a stale "starts in X" countdown for an event that is
    // actually live — prefer the LIVE label.
    final isLiveNow =
        category == TourEventCategory.live ||
        ref.watch(
          liveGroupBroadcastIdsProvider.select(
            (liveIds) => liveIds.valueOrNull?.contains(eventId) ?? false,
          ),
        );
    if (isLiveNow) {
      return _LiveLabel(onLight: onLight);
    }

    final nextRoundAsync = ref.watch(eventNextRoundProvider(eventId));
    final nextRound = nextRoundAsync.valueOrNull;
    // Invalidations keep the previous value, so only the very first resolve
    // renders the placeholder skeleton shape below.
    final isInitialLoading =
        nextRoundAsync.isLoading && !nextRoundAsync.hasValue;

    // Once the fetch has settled (or is re-resolving) with no future round,
    // hide the line.
    if (!isInitialLoading && nextRound == null) return const SizedBox.shrink();

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

    // Tablet image background path always needs light ink; the rest of the
    // card uses theme-aware muted text.
    final baseColor =
        onLight
            ? Colors.white.withValues(alpha: 0.9)
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
