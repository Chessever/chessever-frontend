import 'package:chessever2/services/rewarded_premium/rewarded_access_provider.dart';
import 'package:chessever2/screens/collections/collection_author_screen.dart';
import 'package:chessever2/screens/collections/opening_event_card.dart'
    show collectionOpeningName, OpeningEventCard;
import 'package:chessever2/screens/tour_detail/widgets/event_search_bar.dart'
    show EventSearchBarFrame;
import 'package:chessever2/screens/collections/collection_catalog_views.dart';
import 'package:chessever2/repository/gamebase/collections/collection_search_query.dart';
import 'package:chessever2/screens/collections/collection_search_filters.dart';
import 'package:chessever2/widgets/simple_search_bar.dart';
import 'package:chessever2/widgets/search/search_motion.dart';
import 'package:chessever2/widgets/home_top_bar.dart';
import 'dart:async';
import 'dart:math' as math;
import 'package:chessever2/e2e/e2e_ids.dart';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:chessever2/providers/favorite_events_provider.dart';
import 'package:chessever2/repository/favorites/models/favorite_event.dart';
import 'package:chessever2/screens/chessboard/chess_board_screen_new.dart';
import 'package:chessever2/screens/chessboard/provider/chess_board_screen_provider_new.dart';
import 'package:chessever2/screens/collections/collection_bindings.dart';
import 'package:chessever2/screens/collections/collection_plate_row.dart';
export 'package:chessever2/screens/collections/collection_plate_row.dart';
import 'package:chessever2/screens/collections/collections_data.dart';
import 'package:chessever2/screens/collections/event_view_shell.dart';
import 'package:chessever2/screens/home/widget/bottom_nav_bar.dart';
import 'package:chessever2/screens/for_you/discovery/widgets/discovery_common.dart'
    show
        DiscoveryAction,
        DiscoveryInkFloor,
        DiscoveryPadlock,
        DiscoveryType,
        discoveryGutter,
        discoveryType;
import 'package:chessever2/screens/streaks/widgets/wall_common.dart'
    show WallPressable;
import 'package:chessever2/screens/for_you/discovery/widgets/discovery_game_cards.dart';
import 'package:chessever2/screens/my_space/models/space_shortcut.dart';
import 'package:chessever2/screens/my_space/widgets/pixel_art.dart';
import 'package:chessever2/screens/my_space/widgets/space_database.dart'
    show spacePlateArtBox;
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_list_view_mode_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/round_header_widget.dart';
import 'package:chessever2/screens/tour_detail/widget/text_dropdown_widget.dart';
import 'package:chessever2/screens/tour_detail/about_tour_screen.dart';
import 'package:chessever2/screens/standings/player_standing_model.dart';
import 'package:chessever2/widgets/figma_player_card.dart';
import 'package:chessever2/utils/svg_asset.dart';
import 'package:chessever2/utils/png_asset.dart';
import 'package:chessever2/widgets/svg_widget.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/user_error_message.dart';
import 'package:chessever2/screens/group_event/widget/appbar_icons_widget.dart';
import 'package:chessever2/screens/library/widgets/library_context_menu.dart'
    show LibraryMenuAction, showLibraryContextMenu;
import 'package:chessever2/screens/my_space/actions/space_menu_action.dart';
import 'package:chessever2/screens/player_profile/utils/player_menu_actions.dart'
    show playerMenuActions;
import 'package:chessever2/services/analytics/analytics_service.dart';
import 'package:chessever2/widgets/auth/auth_upgrade_sheet.dart';
import 'package:chessever2/widgets/hub_tile.dart';
import 'package:chessever2/widgets/card_context_menu.dart';
import 'package:chessever2/widgets/skeleton_widget.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:intl/intl.dart';

/// The primary Collections destination: About, published collections and
/// authors in the established event-card language.
class CollectionsScreen extends ConsumerStatefulWidget {
  const CollectionsScreen({super.key, this.embedded = false});

  final bool embedded;

  static Future<void> open(BuildContext context) {
    HapticFeedbackService.cardTap();
    return Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const CollectionsScreen()));
  }

  @override
  ConsumerState<CollectionsScreen> createState() => _CollectionsScreenState();
}

class _CollectionsScreenState extends ConsumerState<CollectionsScreen> {
  final _search = TextEditingController();
  final _focus = FocusNode();
  Timer? _debounce;
  CollectionSearchQuery _query = const CollectionSearchQuery();
  bool get embedded => widget.embedded;
  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _searchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) setState(() => _query = _query.withText(value));
    });
  }

  Future<void> _filters() async {
    _focus.unfocus();
    _debounce?.cancel();
    setState(() => _query = _query.withText(_search.text));
    final result = await showCollectionSearchFilters(
      context,
      _query,
      loadAuthors: ref.read(collectionsRepositoryProvider).fetchAuthors,
      showResult: false,
    );
    if (mounted && result != null) setState(() => _query = result);
  }

  @override
  Widget build(BuildContext context) {
    final query = _query;
    return EventViewShell(
      key: e2eKey(E2eIds.collectionsRoot),
      title: 'Collections',
      header: HomeTopBarFrame(
        child: HomeTopBarRow(
          showAvatar: embedded,
          leading: embedded
              ? null
              : IconButton(
                  tooltip: 'Back',
                  onPressed: () => Navigator.maybePop(context),
                  icon: const Icon(Icons.arrow_back_ios_new_outlined),
                ),
          onAvatarTap:
              embedded && (Scaffold.maybeOf(context)?.hasDrawer ?? false)
              ? () => Scaffold.maybeOf(context)?.openDrawer()
              : null,
          focusNode: _focus,
          content: ListenableBuilder(
            listenable: _focus,
            child: SimpleSearchBar(
              controller: _search,
              focusNode: _focus,
              hintText: 'Search collections',
              textFieldKey: const ValueKey('collections_search'),
              filterButtonKey: const ValueKey('collections_filters'),
              onChanged: _searchChanged,
              onOpenFilter: _filters,
              filterBadgeCount: _query.filterCount,
              onCloseTap: () {
                _debounce?.cancel();
                _search.clear();
                setState(() => _query = _query.withText(''));
                _focus.unfocus();
              },
            ),
            builder: (context, child) => ParkedMotionBuilder(
              value: _focus.hasFocus ? 1.0 : 0.0,
              motion: SearchMotion.morph,
              child: child,
              builder: (context, lift, child) => HomeSearchFieldSurface(
                lift: lift,
                child: RepaintBoundary(child: child),
              ),
            ),
          ),
        ),
      ),
      // Opening discovery is paused; retain its catalog and wiring below.
      // tabs: const ['Openings', 'Collections', 'Authors'],
      tabs: const ['About', 'Collections', 'Authors'],
      initialTab: 1,
      showBackButton: !embedded,
      homeTab: embedded,
      onOpenSidebar: embedded && (Scaffold.maybeOf(context)?.hasDrawer ?? false)
          ? () => Scaffold.maybeOf(context)?.openDrawer()
          : null,
      scrollToTopSequence: embedded
          ? ref.watch(
              bottomNavBarReTapRequestProvider.select(
                (request) => request.item == BottomNavBarItem.collections
                    ? request.sequence
                    : null,
              ),
            )
          : null,
      pageBuilder: (context, index) => switch (index) {
        // 0 => CollectionOpeningCatalog(
        //   query: query,
        //   bottomPadding: embedded ? 72 : 0,
        // ),
        0 => _CollectionsAboutPage(bottomPadding: embedded ? 72 : 0),
        1 => CollectionBooksCatalog(
          query: query,
          bottomPadding: embedded ? 72 : 0,
        ),
        _ => CollectionAuthorsCatalog(
          query: query,
          bottomPadding: embedded ? 72 : 0,
        ),
      },
    );
  }
}

class _CollectionsAboutPage extends StatelessWidget {
  const _CollectionsAboutPage({this.bottomPadding = 0});

  final double bottomPadding;

  @override
  Widget build(BuildContext context) => ListView(
    key: const PageStorageKey('collections_about'),
    padding: _tabListPadding(
      context,
    ).add(EdgeInsets.only(bottom: bottomPadding)),
    children: [
      Text('About collections', style: _aboutHeadingStyle(context)),
      SizedBox(height: 12.sp),
      Text(
        'Explore curated chess games with their original PGN annotations '
        'and variations.',
        style: AppTypography.textSmRegular.copyWith(
          color: context.colors.textPrimary,
          height: 1.5,
        ),
      ),
      SizedBox(height: 16.sp),
      Text(
        'Open a collection to read about it, replay its games, or browse its '
        'players. Search and filters help you find games; Authors lets you '
        'explore each author\'s collections.',
        style: AppTypography.textSmRegular.copyWith(
          color: context.colors.textSecondary,
          height: 1.5,
        ),
      ),
    ],
  );
}

/// The favorites identity of a collection. A starred collection is a plain
/// favorite-events row, like a starred event, so it sorts and syncs the
/// same way; `metadata.kind` tells it apart when it opens.
String collectionFavoriteId(Collection c) => 'collection:${c.slug}';

bool collectionIsFavorited(Iterable<FavoriteEvent> favorites, Collection c) {
  final id = collectionFavoriteId(c);
  return favorites.any(
    (e) =>
        e.eventId == id ||
        (e.metadata['kind'] == 'collection' && e.metadata['slug'] == c.slug),
  );
}

/// Stars or unstars [c]: the one path behind every collection star, so each
/// writes the same row and the same analytics event.
Future<void> toggleCollectionFavorite({
  required BuildContext context,
  required WidgetRef ref,
  required Collection collection,
}) async {
  final allowed = await requireFullAuthGuard(context);
  if (!allowed) return;

  HapticFeedbackService.pin();

  try {
    final isFavorited = await ref
        .read(favoriteEventsProvider.notifier)
        .toggleFavorite(
          eventId: collectionFavoriteId(collection),
          eventName: collection.title,
          extraMetadata: {
            'kind': 'collection',
            'slug': collection.slug,
            'collectionKind': collection.kind.name,
          },
        );
    unawaited(syncCollectionStar(ref, collection, isFavorited));
    AnalyticsService.instance.trackEventDetached(
      'Collection Favorite Toggled',
      properties: {
        'collection_id': collection.id,
        'slug': collection.slug,
        'is_favorited': isFavorited,
      },
    );
  } catch (e) {
    debugPrint('[CollectionCard] Error toggling favorite: $e');
  }
}

/// [c] as a My Space shortcut: it sits with the databases and opens the
/// collection again from there.
SpaceShortcut collectionSpaceDraft(Collection c) {
  final games = c.gameCount == 1 ? '1 game' : '${c.gameCount} games';
  return SpaceShortcut.draft(
    kind: SpaceShortcutKind.collection,
    targetId: c.id,
    title: c.title,
    subtitle: games,
    params: {
      'slug': c.slug,
      'collectionKind': c.kind.name,
      'gameCount': c.gameCount,
      if (c.subtitle != null) 'subtitle': c.subtitle,
      if (c.author != null) 'author': c.author,
      if (c.annotator != null) 'annotator': c.annotator,
      if (c.location != null) 'location': c.location,
      if (c.dateStart != null) 'dateStart': c.dateStart!.toIso8601String(),
      if (c.dateEnd != null) 'dateEnd': c.dateEnd!.toIso8601String(),
      if (c.publishedYear != null) 'publishedYear': c.publishedYear,
      'access': c.access.name,
      'viewCount': c.viewCount,
      'starCount': c.starCount,
      'eventCount': c.eventCount,
      if (c.bookCount != null) 'bookCount': c.bookCount,
      if (c.coverUrl != null) 'coverUrl': c.coverUrl,
    },
  );
}

/// A collection as the Events list draws an event: its cover (or its pixel
/// object) on the left, the title, who wrote it (a book) or where and when
/// it was played (an event), and how many games it holds with what it is
/// bound to ("91 games · 2 books"; a book names its events when its row
/// carries them). Held, it lifts into the focus menu with Open and My
/// Space.
///
/// Books and events share the landscape plate in lists; a book's About
/// page preserves its complete jacket. A Premium collection the viewer cannot read yet
/// carries the padlock after its game count (the page's one lock
/// placement); it still opens, on its preview. [note] is the team's caption
/// when the card is listed for an event ("Chapter 7 is this match's
/// decisive game").
class CollectionCard extends ConsumerWidget {
  const CollectionCard({
    super.key,
    required this.collection,
    this.note,
    this.opening,
  });

  final Collection collection;
  final String? note;
  final CollectionOpening? opening;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = collection;
    final engagement = ref.watch(collectionEngagementCountsProvider(c.slug));
    final views = (engagement?['viewCount'] as num?)?.toInt() ?? c.viewCount;
    final stars = (engagement?['starCount'] as num?)?.toInt() ?? c.starCount;

    final subscription = ref.watch(featureAccessStateProvider);
    final locked = isCollectionLocked(
      c,
      isSubscribed: subscription.isSubscribed,
      subscriptionLoading: subscription.isLoading,
    );
    final isBook = c.kind == CollectionKind.book;
    // Who wrote it, or where and when it was played: what tells this one
    // from its neighbours (two Sinquefield Cups differ by their year), on a
    // line of its own so the count never pushes the year off the end. An
    // event reads like an event card: the author instead of dates, ratings
    // and rounds, and just the year — never a date range.
    final byline = c.author ?? c.annotator;
    final eventYear = c.publishedYear ?? c.dateStart?.year ?? c.dateEnd?.year;
    final eventParts = [
      if (byline != null && byline.trim().isNotEmpty) 'by $byline',
      if (eventYear != null) '$eventYear',
      if (c.location != null && c.location!.trim().isNotEmpty)
        c.location!.trim(),
    ];
    final identity = c.kind == CollectionKind.event
        ? (eventParts.isEmpty ? c.subtitle : eventParts.join(' · '))
        : byline == null
        ? c.subtitle
        : 'by $byline';
    // A book names the events it covers when its row carries them; counted
    // otherwise, as an event counts the books written about it.
    final named = isBook && note == null
        ? collectionEventsLine(c.events)
        : null;
    final bindings = isBook
        ? (named == null && c.eventCount > 0
              ? _plural(c.eventCount, 'event')
              : null)
        : ((c.bookCount ?? 0) > 0 ? _plural(c.bookCount!, 'collection') : null);
    final tally = opening == null
        ? [_plural(c.gameCount, 'game'), ?bindings].join(' · ')
        : [
            if (c.matchedGameCount != null)
              _plural(c.matchedGameCount!, 'game'),
            opening!.eco,
          ].join(' · ');
    final caption = note ?? named;

    void open() {
      HapticFeedbackService.cardTap();
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => CollectionScreen(collection: c, opening: opening),
        ),
      );
    }

    return CollectionPlateRow(
      plate: _Cover(collection: c),
      plateSize: CollectionPlateRow.eventPlate,
      compactDetails: isBook,
      detailItems: isBook
          ? [
              Text.rich(
                TextSpan(
                  children: [
                    WidgetSpan(
                      alignment: PlaceholderAlignment.middle,
                      child: Padding(
                        padding: EdgeInsetsDirectional.only(end: 4.sp),
                        child: Icon(
                          Icons.visibility_outlined,
                          size: 14.ic,
                          color: context.colors.textSecondary,
                        ),
                      ),
                    ),
                    TextSpan(text: '$views'),
                  ],
                ),
                key: const ValueKey('collection_card_views'),
                style: AppTypography.textXsRegular.copyWith(
                  color: context.colors.textSecondary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ]
          : const [],
      title: c.title,
      meta: identity,
      metaMaxLines: 2,
      tally: tally,
      locked: locked,
      note: caption,
      semanticsLabel: [
        c.title,
        ?identity,
        tally,
        if (locked) 'Premium',
        if (isBook) _plural(views, 'view'),
        if (isBook && stars > 0) _plural(stars, 'star'),
        ?caption,
      ].join(', '),
      onTap: open,
      trailing: _CollectionStar(collection: c, count: isBook ? stars : null),
      menuActions: (menuContext) => [
        LibraryMenuAction(
          icon: Icons.open_in_new_rounded,
          label: 'Open',
          onSelected: open,
        ),
        spaceMenuAction(
          context: menuContext,
          ref: ref,
          draft: collectionSpaceDraft(c),
        ),
      ],
    );
  }
}

/// A collection's star, the event card's star in the same place: filled
/// gold while starred, an outline otherwise.
class _CollectionStar extends ConsumerWidget {
  const _CollectionStar({required this.collection, this.count});

  final int? count;

  final Collection collection;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favorites = ref.watch(favoriteEventsProvider).valueOrNull;
    final starred =
        favorites != null && collectionIsFavorited(favorites, collection);
    final icon = SvgWidget(
      starred ? SvgAsset.starFilledIcon : SvgAsset.starIcon,
      semanticsLabel: 'Favorite Icon',
      height: 20.h,
      width: 20.w,
      preserveOriginalColors: starred,
    );
    return Semantics(
      button: true,
      label: starred
          ? 'Unstar ${collection.title}'
          : 'Star ${collection.title}',
      child: InkWell(
        onTap: () => toggleCollectionFavorite(
          context: context,
          ref: ref,
          collection: collection,
        ),
        child: collection.kind == CollectionKind.book
            ? SizedBox(
                width: 48,
                height: 64,
                child: ExcludeSemantics(
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      icon,
                      if ((count ?? 0) > 0)
                        Positioned(
                          bottom: 0,
                          left: 0,
                          right: 0,
                          height: 18,
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              '$count',
                              key: const ValueKey('collection_card_star_count'),
                              style: AppTypography.textXsRegular.copyWith(
                                color: context.colors.textSecondary,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              )
            : Padding(
                padding: EdgeInsets.fromLTRB(6.w, 6.h, 2.w, 6.h),
                child: ExcludeSemantics(child: icon),
              ),
      ),
    );
  }
}

/// A collection's cover, or its pixel object (the trophy for an event, the
/// stacked boards for a book) when it has none.
class _Cover extends StatelessWidget {
  const _Cover({required this.collection, this.fit = BoxFit.cover});

  final Collection collection;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final plate = _PixelPlate(
      section: collection.kind == CollectionKind.event
          ? SpaceSection.events
          : SpaceSection.library,
    );
    final url = collection.coverUrl;
    if (url == null) return plate;
    return CachedNetworkImage(
      imageUrl: url,
      fit: fit,
      placeholder: (_, __) => plate,
      errorWidget: (_, __, ___) => plate,
    );
  }
}

/// The stacked-boards plate a book shows in place of a missing cover, for
/// surfaces outside this file that draw a book before it exists (the
/// publishing preview).
class CollectionBookPlate extends StatelessWidget {
  const CollectionBookPlate({super.key});

  @override
  Widget build(BuildContext context) =>
      const _PixelPlate(section: SpaceSection.library);
}

/// The pixel object on the hub's plate: the stacked boards for a book, the
/// trophy for an event.
class _PixelPlate extends StatelessWidget {
  const _PixelPlate({required this.section});

  final SpaceSection section;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: context.isLightTheme
          ? context.colors.surfaceRecessed
          : kHubTileInk,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = constraints.biggest;
          if (!size.isFinite || size.isEmpty) return const SizedBox.shrink();
          // A standing (book) plate is narrow: the object takes more of its
          // width, so it reads at the size it does on a landscape plate.
          final box = size.height > size.width
              ? Rect.fromCenter(
                  center: size.center(Offset.zero),
                  width: size.width * 0.76,
                  height: size.height * 0.56,
                )
              : spacePlateArtBox(size);
          return PixelArtView(
            scene: PixelScene.inBox(
              PixelArt.door(section, tone: PixelTone.of(context)),
              size,
              box,
            ),
          );
        },
      ),
    );
  }
}

/// "Wijk aan Zee · Jan 13-28, 2024": where and when an event was played,
/// as every event line in the collections reads it, or null when it has
/// neither. The place comes first; each date holds together, so a line that
/// wraps breaks after the place or at a range's dash ("Sep 10, 1984 -" over
/// "Feb 15, 1985"), never inside a date.
String? collectionEventLine(String? location, DateTime? start, DateTime? end) {
  final dates = collectionDateRange(
    start,
    end,
  )?.split(' - ').map((d) => d.replaceAll(' ', '\u00a0')).join(' - ');
  final parts = [?location, ?dates];
  return parts.isEmpty ? null : parts.join(' · ');
}

/// "1 game", "55 games".
String _plural(int n, String one) => n == 1 ? '1 $one' : '$n ${one}s';

/// "World Championship 1985", or "World Championship 1984 and 1 more": the
/// events a book covers, as its card names them; null when it names none.
String? collectionEventsLine(List<CollectionEventRef> events) {
  if (events.isEmpty) return null;
  final first = events.first.title;
  final more = events.length - 1;
  return more == 0 ? first : '$first and $more more';
}

/// "Saint Louis · Oct 2-14, 2025": an event's place and dates, or null when
/// it has neither.
String? collectionPlaceAndDates(Collection c) {
  final dates = collectionDateRange(c.dateStart, c.dateEnd);
  final parts = [?c.location, ?dates];
  return parts.isEmpty ? null : parts.join(' · ');
}

/// "Oct 2, 2025", "Oct 2-14, 2025", "Sep 28 - Oct 3, 2025".
String? collectionDateRange(DateTime? start, DateTime? end) {
  final from = start ?? end;
  if (from == null) return null;
  final to = start == null ? null : end;
  final full = DateFormat('MMM d, yyyy');
  if (to == null ||
      (from.year == to.year && from.month == to.month && from.day == to.day)) {
    return full.format(from);
  }
  if (from.year == to.year && from.month == to.month) {
    return '${DateFormat('MMM d').format(from)}-${to.day}, ${to.year}';
  }
  if (from.year == to.year) {
    return '${DateFormat('MMM d').format(from)} - ${full.format(to)}';
  }
  return '${full.format(from)} - ${full.format(to)}';
}

/// Where section headers and the player line start: the game cards' edge.
double get _headerInset => discoveryGutter + 4.sp;

/// Every collection shares About, Games and Players. Credits, related
/// events and books, and the player filter remain available from About.
class CollectionScreen extends ConsumerStatefulWidget {
  const CollectionScreen({super.key, required this.collection, this.opening});

  /// The list row it was opened from; the detail read fills in the rest.
  final Collection collection;
  final CollectionOpening? opening;

  @override
  ConsumerState<CollectionScreen> createState() => _CollectionScreenState();
}

class _CollectionScreenState extends ConsumerState<CollectionScreen> {
  static const int _aboutTab = 0;
  // int get _gamesTab => _isBook ? 2 : 1;
  static const int _gamesTab = 1;

  // List<String> get _collectionTabs => _isBook
  //     ? const ['About', 'Openings', 'Games', 'Players']
  //     : const ['About', 'Games', 'Players'];
  List<String> get _collectionTabs => const ['About', 'Games', 'Players'];
  late CollectionOpening? _opening = widget.opening;

  /// Fixed by the kind the page opened as, so the tab strip never changes
  /// under the viewer.
  late final bool _isBook = widget.collection.kind == CollectionKind.book;

  final EventViewController _tabs = EventViewController();
  final _bookGameSearch = _CollectionGamesSearchState();

  // A book opens on the compact tournament list, even if another screen was
  // left on a board grid. Switching this page never changes other screens.
  GamesListViewMode _gamesViewMode = GamesListViewMode.gamesCard;

  void _toggleGamesView() {
    HapticFeedbackService.buttonPress();
    setState(() {
      _gamesViewMode = GamesListViewMode
          .values[(_gamesViewMode.index + 1) % GamesListViewMode.values.length];
    });
  }

  /// A preview opens on About (the cover and the credits sell it; the
  /// contents wait on Games); a collection the viewer reads opens on its
  /// games. Decided once, from what is known on the first frame.
  late final int _initialTab = _isLocked(widget.collection)
      ? _aboutTab
      : _gamesTab;

  /// Where the way in stands: offered, or the page confirming the viewer's
  /// Premium with the server, or that confirm having run out.
  CollectionUnlockPhase _phase = CollectionUnlockPhase.offer;
  final _confirmationChanges = ValueNotifier(0);

  /// A subscriber the server still has as locked is confirmed once on its
  /// own; after that only a tap asks again.
  bool _autoConfirmed = false;

  /// The confirm was asked for from About's "Read all N games": once the
  /// server opens the collection, the page turns to those games.
  bool _openGamesOnConfirm = false;

  late final CollectionPremiumConfirm _confirm = CollectionPremiumConfirm(
    check: _checkAccess,
    onPhase: _onConfirmPhase,
  );

  @override
  void initState() {
    super.initState();
    _bookGameSearch.addListener(_bookSearchChanged);
    if (_isBook) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          unawaited(trackCollectionRead(ref, widget.collection));
        }
      });
    }
  }

  void _bookSearchChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _bookGameSearch.removeListener(_bookSearchChanged);
    _confirm.cancel();
    _confirmationChanges.dispose();
    _tabs.dispose();
    _bookGameSearch.dispose();
    super.dispose();
  }

  bool _isLocked(Collection c) {
    final subscription = ref.read(featureAccessStateProvider);
    return isCollectionLocked(
      c,
      isSubscribed: subscription.isSubscribed,
      subscriptionLoading: subscription.isLoading,
    );
  }

  /// One try of the confirm: the server asked again for its verdict (anew,
  /// past the "not Premium" it keeps a few seconds) and, when that opens
  /// the collection (or the server could not say), for the games
  /// themselves, which are the proof.
  Future<CollectionAccessCheck> _checkAccess() async {
    final slug = widget.collection.slug;
    final release = ref
        .read(collectionsRepositoryProvider)
        .holdFreshAccess(slug);
    try {
      refreshCollectionAccess(ref, slug);
      if (_opening != null) {
        ref.invalidate(
          collectionOpeningContentsProvider((slug: slug, eco: _opening!.eco)),
        );
      }
      final detail = await ref.read(collectionDetailProvider(slug).future);
      // The page closed while the server answered: the run is over.
      if (!mounted) return CollectionAccessCheck.locked;
      if (!detail.isPremium) return CollectionAccessCheck.open;
      if (detail.contentLocked == true) {
        return detail.lockedForSignIn
            ? CollectionAccessCheck.signInRefused
            : CollectionAccessCheck.locked;
      }
      // Held while it is read: the page itself watches the games only once
      // it has drawn the verdict.
      final keep = ref.listenManual(collectionGamesProvider(slug), (_, __) {});
      try {
        await ref.read(collectionGamesProvider(slug).future);
        return CollectionAccessCheck.open;
      } catch (e) {
        if (e is CollectionsRequestException && e.isPremiumGate) {
          return e.isSignInGate
              ? CollectionAccessCheck.signInRefused
              : CollectionAccessCheck.locked;
        }
        // The verdict opened it: the games' own failure is the Games tab's
        // to show, with its own retry.
        if (detail.contentLocked == false) return CollectionAccessCheck.open;
        // No verdict and no games (offline, the check out of reach): no
        // answer, so never a success. The confirm asks again.
        rethrow;
      } finally {
        keep.close();
      }
    } finally {
      release();
    }
  }

  void _onConfirmPhase(CollectionUnlockPhase phase) {
    if (!mounted) return;
    final failedAt = ref.read(collectionConfirmFailedAtProvider.notifier);
    switch (phase) {
      case CollectionUnlockPhase.failed:
      case CollectionUnlockPhase.signIn:
        failedAt.state = DateTime.now();
      case CollectionUnlockPhase.offer:
        // The server opened it: whatever failed before is behind us.
        failedAt.state = null;
        HapticFeedbackService.success();
        if (_openGamesOnConfirm) _tabs.showTab(_gamesTab);
        _openGamesOnConfirm = false;
      case CollectionUnlockPhase.confirming:
        break;
    }
    setState(() => _phase = phase);
    // Related Players is a pushed route, so this page's setState cannot
    // redraw its confirming, retry or sign-in state.
    _confirmationChanges.value++;
  }

  /// Confirms the viewer's Premium with the server.
  void _startConfirm() {
    if (!mounted) return;
    unawaited(_confirm.start());
  }

  /// The server refused the session: the account sheet, and once the
  /// viewer is back signed in, the confirm again on the new session.
  Future<void> _signInAgain() async {
    final signedIn = await ref.read(collectionSignInProvider)(context);
    if (!mounted || !signedIn) return;
    _startConfirm();
  }

  /// The way in, tapped. A subscriber (or a retry after a confirm ran out)
  /// confirms with the server; a refused session signs in again; anyone
  /// else gets the paywall, and a purchase there confirms the same way.
  /// [openGames]: the tap came from About, so the opened collection shows
  /// its games.
  void _unlock(Collection c, {bool openGames = false}) {
    if (_phase == CollectionUnlockPhase.confirming) return;
    _openGamesOnConfirm = openGames;
    if (_phase == CollectionUnlockPhase.signIn) {
      HapticFeedbackService.buttonPress();
      unawaited(_signInAgain());
      return;
    }
    if (_phase == CollectionUnlockPhase.failed ||
        ref.read(featureAccessStateProvider).isSubscribed) {
      HapticFeedbackService.buttonPress();
      _startConfirm();
      return;
    }
    unawaited(unlockCollection(context, ref, c, onEntitled: _startConfirm));
  }

  void _showPlayer(CollectionPlayer? player) {
    if (player == null) return;
    HapticFeedbackService.cardTap();
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _CollectionScopedGamesScreen(
          collection: widget.collection,
          player: player,
        ),
      ),
    );
  }

  void _showOpeningGames(Collection collection, CollectionOpening opening) {
    HapticFeedbackService.cardTap();
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _CollectionScopedGamesScreen(
          collection: collection,
          opening: opening,
        ),
      ),
    );
  }

  void _showRelated(String label) {
    HapticFeedbackService.navigation();
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ListenableBuilder(
          listenable: _confirmationChanges,
          builder: (context, _) => Consumer(
            builder: (context, ref, _) {
              final slug = widget.collection.slug;
              final detail = ref.watch(collectionDetailProvider(slug));
              final c = detail.valueOrNull ?? widget.collection;
              final subscription = ref.watch(featureAccessStateProvider);
              final locked = isCollectionLocked(
                c,
                isSubscribed: subscription.isSubscribed,
                subscriptionLoading: subscription.isLoading,
              );
              final pending = detail.isLoading && !detail.hasValue;
              final error = detail.hasError && !detail.hasValue && !pending
                  ? detail.error
                  : null;
              void retry() => ref.invalidate(collectionDetailProvider(slug));
              final players = label == 'Players' && !locked
                  ? ref.watch(collectionPlayersProvider(slug))
                  : null;
              return EventViewShell(
                title: c.title,
                tabs: [label],
                pageBuilder: (context, _) => switch (label) {
                  'Events' => _EventsPage(
                    events: c.events,
                    pending: pending,
                    error: error,
                    onRetry: retry,
                  ),
                  'Collections' => _BooksPage(
                    collectionId: c.id,
                    pending: pending,
                    error: error,
                    onRetry: retry,
                  ),
                  _ =>
                    players == null
                        ? _LockedPlayers(
                            collection: c,
                            phase: _phase,
                            onUnlock: () => _unlock(c),
                          )
                        : players.when(
                            skipLoadingOnReload: isCollectionPremiumGate(
                              players.error,
                            ),
                            data: (list) => _PlayersPage(
                              players: list,
                              numbered: _isBook,
                              onPick: _showPlayer,
                            ),
                            loading: () => const _CardsSkeleton(),
                            error: (error, _) => isCollectionPremiumGate(error)
                                ? _LockedPlayers(
                                    collection: c,
                                    phase: _phase,
                                    onUnlock: () => _unlock(c),
                                  )
                                : _Notice(
                                    text: _collectionErrorText(
                                      error,
                                      fallback: "Couldn't load the players.",
                                    ),
                                    actionLabel: 'Try again',
                                    onAction: () => ref.invalidate(
                                      collectionPlayersProvider(slug),
                                    ),
                                  ),
                          ),
                },
              );
            },
          ),
        ),
      ),
    );
  }

  /// Collection games carry their whole PGN, so the board replays them as it
  /// replays an imported file. [games] is the whole list in the order shown,
  /// so prev/next walks the collection.
  void _openGame(List<GamesTourModel> games, int index) {
    HapticFeedbackService.cardTap();
    ref.read(chessboardViewFromProviderNew.notifier).state =
        ChessboardView.tour;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ChessBoardScreenNew(
          currentIndex: index,
          games: games,
          viewSource: ChessboardView.tour,
          showGamebaseButton: false,
          disableGamebaseOverlayByDefault: true,
          // Licensed book/event content: no save, no Copy PGN.
          allowGameExport: false,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final slug = widget.collection.slug;
    final detail = ref.watch(collectionDetailProvider(slug));
    final c = detail.valueOrNull ?? widget.collection;
    final subscription = ref.watch(featureAccessStateProvider);
    final starred = collectionIsFavorited(
      ref.watch(favoriteEventsProvider).valueOrNull ?? const <FavoriteEvent>[],
      c,
    );
    final locked = isCollectionLocked(
      c,
      isSubscribed: subscription.isSubscribed,
      subscriptionLoading: subscription.isLoading,
    );
    // Nothing behind the paywall is asked for while it stands: the games
    // and players are read only once the viewer may see them.
    final contents = locked
        ? null
        : _opening == null
        ? ref.watch(collectionContentsProvider(slug))
        : ref.watch(
            collectionOpeningContentsProvider((slug: slug, eco: _opening!.eco)),
          );
    final players = locked ? null : ref.watch(collectionPlayersProvider(slug));
    // The server keeps the games from a viewer the app knows as a
    // subscriber (a purchase it has not seen yet, a session it refused, a
    // check that was down): the page confirms on its own, once, instead of
    // offering a subscriber the paywall.
    final serverLocked =
        c.isPremium &&
        (c.contentLocked == true ||
            isCollectionPremiumGate(contents?.error) ||
            isCollectionPremiumGate(players?.error));
    if (serverLocked &&
        subscription.isSubscribed &&
        !_autoConfirmed &&
        _phase == CollectionUnlockPhase.offer) {
      _autoConfirmed = true;
      // Decided before this frame draws, so a subscriber never sees the
      // offer (nor About's facts shift) for the frame before the confirm.
      final failedAt = ref.read(collectionConfirmFailedAtProvider);
      if (failedAt != null &&
          DateTime.now().difference(failedAt) <
              kCollectionConfirmFailureMemory) {
        // A confirm ran out a moment ago: said again at once, with its way
        // on, instead of confirming for the whole window again.
        final refused =
            c.lockedForSignIn ||
            _isSignInGate(contents?.error) ||
            _isSignInGate(players?.error);
        _phase = refused
            ? CollectionUnlockPhase.signIn
            : CollectionUnlockPhase.failed;
      } else {
        _phase = CollectionUnlockPhase.confirming;
        WidgetsBinding.instance.addPostFrameCallback((_) => _startConfirm());
      }
    }
    final phase = _phase;
    void unlock() => _unlock(c);
    // While the page confirms, the locked lines wait with it.
    final VoidCallback? lineTap = phase == CollectionUnlockPhase.confirming
        ? null
        : unlock;

    // The detail read, when it has nothing better than the list row to show
    // yet: the Events tab waits on it, the Books tab when it opened by slug.
    final detailError = detail.hasError && !detail.hasValue && !detail.isLoading
        ? detail.error
        : null;
    void retryDetail() => ref.invalidate(collectionDetailProvider(slug));
    // Held for the page's life, as its games and players are: the tabs'
    // pages come and go as the viewer swipes, and the Books tab should not
    // ask again (nor flash its skeleton) each time it comes back.
    if (c.kind == CollectionKind.event && c.id.isNotEmpty) {
      ref.watch(collectionBooksOfEventCollectionProvider(c.id));
    }

    return EventViewShell(
      title: c.title,
      tabs: _collectionTabs,
      // scrollableTabs: _isBook,
      initialTab: _initialTab,
      controller: _tabs,
      beforeTabsBuilder: _isBook
          ? (context, selectedTab) => _CollectionGamesSearchBar(
              state: _bookGameSearch,
              opening: _opening,
              onClearOpening: () => setState(() => _opening = null),
              pinned: true,
              hintText: 'Search collection',
            )
          : null,
      contentOverride: _isBook && _bookGameSearch.query.isActive
          ? locked || serverLocked
                ? _LockedContents(
                    collection: c,
                    phase: phase,
                    onUnlock: unlock,
                    onLineTap: lineTap,
                  )
                : _BookSearchResults(
                    slug: slug,
                    query: _bookGameSearch.query,
                    opening: _opening,
                    viewMode: _gamesViewMode,
                    onOpening: (opening) => _showOpeningGames(c, opening),
                    onPlayer: _showPlayer,
                    onGame: _openGame,
                  )
          : null,
      actions: [
        Semantics(
          label: 'Toggle chessboard view',
          child: AppBarIcons(
            image: SvgAsset.chase_grid,
            onTap: _toggleGamesView,
          ),
        ),
        SizedBox(width: 18.w),
        Builder(
          builder: (menuContext) => AppBarIcons(
            image: SvgAsset.threeDots,
            onTap: () {
              HapticFeedbackService.cardTap();
              unawaited(
                showLibraryContextMenu(
                  context: menuContext,
                  actions: [
                    LibraryMenuAction(
                      icon: starred
                          ? Icons.star_rounded
                          : Icons.star_outline_rounded,
                      label: starred ? 'Unstar' : 'Star',
                      onSelected: () => toggleCollectionFavorite(
                        context: context,
                        ref: ref,
                        collection: c,
                      ),
                    ),
                    spaceMenuAction(
                      context: menuContext,
                      ref: ref,
                      draft: collectionSpaceDraft(c),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
      pageBuilder: (context, index) {
        // Book opening discovery is paused, with the full implementation kept.
        // if (_isBook && index == 1) {
        //   return CollectionOpeningCatalog(
        //     query: const CollectionSearchQuery(),
        //     slug: slug,
        //     onPick: (opening) => _showOpeningGames(c, opening),
        //   );
        // }
        // final contentIndex = _isBook && index > 1 ? index - 1 : index;
        return switch (index) {
          0 => _AboutPage(
            collection: c,
            playerCount: players?.valueOrNull?.length,
            // A refusal of the games is the server's verdict too.
            locked:
                locked ||
                isCollectionPremiumGate(contents?.error) ||
                isCollectionPremiumGate(players?.error),
            phase: phase,
            onUnlock: () => _unlock(c, openGames: true),
            // Only when there is nothing better than the list row to show;
            // hidden while a retry is in flight so the tap reads as taken.
            error: detailError,
            onRetry: retryDetail,
            onShowEvents: _isBook ? () => _showRelated('Events') : null,
            onShowBooks: c.kind == CollectionKind.event
                ? () => _showRelated('Collections')
                : null,
            onShowPlayers: _isBook ? null : () => _showRelated('Players'),
          ),
          1 =>
            contents == null
                ? _LockedContents(
                    collection: c,
                    phase: phase,
                    onUnlock: unlock,
                    onLineTap: lineTap,
                  )
                : contents.when(
                    // A re-check reloads the games: a refusal on screen
                    // stays until the server's new answer, never a flash
                    // of the skeleton on every try.
                    skipLoadingOnReload: isCollectionPremiumGate(
                      contents.error,
                    ),
                    data: (data) => _GamesPage(
                      slug: slug,
                      searchState: _isBook ? _bookGameSearch : null,
                      contents: data,
                      showSelector: c.kind != CollectionKind.book,
                      // Book chapters/rounds are paused; _groupedBody retains
                      // the shared layout for events and scoped game routes.
                      flatList: _isBook,
                      player: null,
                      onClearPlayer: () => _showPlayer(null),
                      onOpen: _openGame,
                      viewMode: _gamesViewMode,
                      opening: _opening,
                      onClearOpening: () => setState(() => _opening = null),
                    ),
                    loading: () => ListView(
                      padding: EdgeInsets.symmetric(vertical: 16.sp),
                      children: [
                        DiscoveryGameListSkeleton(
                          count: 4,
                          viewMode: _gamesViewMode,
                        ),
                      ],
                    ),
                    error: (error, _) => isCollectionPremiumGate(error)
                        // The server knows better than the app's subscription
                        // state (a purchase it has not seen yet): the preview.
                        ? _LockedContents(
                            collection: c,
                            phase: phase,
                            onUnlock: unlock,
                            onLineTap: lineTap,
                          )
                        : _Notice(
                            text: _collectionErrorText(
                              error,
                              fallback: "Couldn't load the games.",
                            ),
                            actionLabel: 'Try again',
                            onAction: () {
                              ref.invalidate(collectionDetailProvider(slug));
                              ref.invalidate(collectionGamesProvider(slug));
                              if (_opening != null) {
                                ref.invalidate(
                                  collectionOpeningContentsProvider((
                                    slug: slug,
                                    eco: _opening!.eco,
                                  )),
                                );
                              }
                            },
                          ),
                  ),
          _ =>
            players == null
                ? _LockedPlayers(
                    collection: c,
                    phase: phase,
                    onUnlock: () => _unlock(c),
                  )
                : players.when(
                    skipLoadingOnReload: isCollectionPremiumGate(players.error),
                    data: (list) => _PlayersPage(
                      players: list,
                      numbered: _isBook,
                      onPick: _showPlayer,
                    ),
                    loading: () => const _CardsSkeleton(),
                    error: (error, _) => isCollectionPremiumGate(error)
                        ? _LockedPlayers(
                            collection: c,
                            phase: phase,
                            onUnlock: () => _unlock(c),
                          )
                        : _Notice(
                            text: _collectionErrorText(
                              error,
                              fallback: "Couldn't load the players.",
                            ),
                            actionLabel: 'Try again',
                            onAction: () =>
                                ref.invalidate(collectionPlayersProvider(slug)),
                          ),
                  ),
        };
      },
    );
  }
}

bool _isSignInGate(Object? error) =>
    error is CollectionsRequestException && error.isSignInGate;

/// [error] as the reader sees it. The Premium check being out of reach is
/// said as such: the reader may well be entitled, so it is a retry, never
/// a paywall and never "your session has expired".
String _collectionErrorText(Object? error, {required String fallback}) {
  if (error is CollectionsRequestException && error.isAccessCheckUnavailable) {
    return "Couldn't check your Premium access just now.";
  }
  return userFacingError(error, fallback: fallback);
}

/// The Premium outcome a locked collection sells, the same sentence on every
/// tab: what the reader gets, not the word "Premium".
String _unlockLabel(Collection c) {
  final n = c.gameCount;
  if (c.kind == CollectionKind.book) {
    return switch (n) {
      0 => 'Read this collection',
      1 => 'Read the game in this collection',
      _ => 'Read all $n games in this collection',
    };
  }
  return switch (n) {
    0 => 'Replay these games',
    1 => 'Replay the game',
    _ => 'Replay all $n games',
  };
}

/// The one way into a locked collection, in the phase the page is in.
///
/// Offered: its outcome in accent ink with the Premium padlock after it
/// (the locked action's one mark), a 44 target, the paywall behind it.
/// Confirming: a quiet line saying the page is checking the viewer's
/// Premium with the server, no target. Failed: that the check did not go
/// through, and a retry. Sign in: that the server no longer takes the
/// viewer's sign-in, and the way to sign in again. Every phase stands on
/// the same 44 floor, so the page never shifts as one gives way to the
/// next.
class _UnlockAction extends StatelessWidget {
  const _UnlockAction({
    required this.collection,
    required this.phase,
    required this.onUnlock,
  });

  final Collection collection;
  final CollectionUnlockPhase phase;

  /// The way in for every phase: the page routes it (paywall, confirm,
  /// sign in) by the phase it is in.
  final VoidCallback onUnlock;

  // No cross-fade between phases: each one is on screen the frame it
  // applies, never waiting on an animation to be readable.
  @override
  Widget build(BuildContext context) => switch (phase) {
    CollectionUnlockPhase.offer => _offer(),
    CollectionUnlockPhase.confirming => const _ConfirmingLine(),
    CollectionUnlockPhase.failed => _UnlockStatusLine(
      text: _UnlockStatusLine.failedText,
      actionLabel: 'Try again',
      actionKey: const ValueKey('collection_unlock_retry'),
      onAction: onUnlock,
    ),
    CollectionUnlockPhase.signIn => _UnlockStatusLine(
      text: _UnlockStatusLine.signInText,
      actionLabel: 'Sign in again',
      actionKey: const ValueKey('collection_unlock_sign_in'),
      onAction: onUnlock,
    ),
  };

  Widget _offer() {
    final label = _unlockLabel(collection);
    return Align(
      alignment: Alignment.centerLeft,
      child: DiscoveryAction(
        key: const ValueKey('collection_unlock'),
        label: label,
        onTap: onUnlock,
        trailingPadlock: true,
        wraps: true,
        semanticsLabel: '$label, Premium',
      ),
    );
  }
}

/// The confirm under way: a small turning ring and the sentence, in
/// secondary ink, announced to a screen reader as it appears.
class _ConfirmingLine extends StatelessWidget {
  const _ConfirmingLine();

  static const String text = 'Confirming your Premium…';

  @override
  Widget build(BuildContext context) {
    final ink = context.colors.textSecondary;
    final style = discoveryType(context, DiscoveryType.label, color: ink);
    final line = MediaQuery.textScalerOf(context).scale(13.f) * 18 / 13;
    final ring = 12.w;
    return Semantics(
      key: const ValueKey('collection_unlock_status'),
      container: true,
      liveRegion: true,
      label: 'Confirming your Premium',
      excludeSemantics: true,
      child: DiscoveryInkFloor(
        minHeight: 44.w,
        inset: math.max(0, (44.w - line) / 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // On the first line's centre, beside the words it belongs to.
            SizedBox(
              height: line,
              child: Center(
                child: _TurningRing(size: ring, color: ink),
              ),
            ),
            SizedBox(width: 8.w),
            Flexible(child: Text(text, style: style)),
          ],
        ),
      ),
    );
  }
}

/// A quarter arc turning on a faint track: work under way, the same
/// length in every frame. Still (the arc at rest) when the system asks for
/// less motion.
class _TurningRing extends StatefulWidget {
  const _TurningRing({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  State<_TurningRing> createState() => _TurningRingState();
}

class _TurningRingState extends State<_TurningRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _turn = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _turn.stop();
    } else if (!_turn.isAnimating) {
      _turn.repeat();
    }
  }

  @override
  void dispose() {
    _turn.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RotationTransition(
      turns: _turn,
      child: SizedBox.square(
        dimension: widget.size,
        child: CircularProgressIndicator(
          value: 0.28,
          strokeWidth: 1.5,
          strokeCap: StrokeCap.round,
          color: widget.color,
          backgroundColor: widget.color.withValues(alpha: 0.2),
        ),
      ),
    );
  }
}

/// The confirm ended without the server opening the collection: what
/// happened, in secondary ink, and the way on beside it (a retry, or
/// signing in again).
class _UnlockStatusLine extends StatelessWidget {
  const _UnlockStatusLine({
    required this.text,
    required this.actionLabel,
    required this.actionKey,
    required this.onAction,
  });

  static const String failedText = "Couldn't confirm your Premium just now.";
  static const String signInText = 'Your sign-in has expired.';

  final String text;
  final String actionLabel;
  final Key actionKey;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final line = MediaQuery.textScalerOf(context).scale(13.f) * 18 / 13;
    return Semantics(
      key: const ValueKey('collection_unlock_status'),
      container: true,
      liveRegion: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Flexible(
            child: DiscoveryInkFloor(
              minHeight: 44.w,
              inset: math.max(0, (44.w - line) / 2),
              child: Text(
                text,
                style: discoveryType(
                  context,
                  DiscoveryType.label,
                  color: context.colors.textSecondary,
                ),
              ),
            ),
          ),
          SizedBox(width: 12.w),
          DiscoveryAction(key: actionKey, label: actionLabel, onTap: onAction),
        ],
      ),
    );
  }
}

class _AboutPage extends ConsumerWidget {
  const _AboutPage({
    required this.collection,
    required this.playerCount,
    required this.locked,
    required this.phase,
    required this.onUnlock,
    this.error,
    this.onRetry,
    this.onShowEvents,
    this.onShowBooks,
    this.onShowPlayers,
  });

  final Collection collection;

  /// Null until the Players read lands (and while the collection is locked).
  final int? playerCount;

  /// The viewer sees the preview: the credits, the contents and the way in.
  final bool locked;
  final CollectionUnlockPhase phase;
  final VoidCallback onUnlock;

  /// Why the detail read failed, when [collection] is still just the list
  /// row (no About text, credits or edition).
  final Object? error;
  final VoidCallback? onRetry;
  final VoidCallback? onShowEvents;
  final VoidCallback? onShowBooks;
  final VoidCallback? onShowPlayers;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final c = collection;
    final paragraphs = _paragraphs(c.about);
    final summary = collectionContentsSummary(c);
    final foreword = _paragraphs(c.foreword);
    final players = playerCount;
    // The offered way in says how many games wait behind it ("Read all 55
    // games in this book"), so the facts do not say it again right above.
    final offersCount = locked && phase == CollectionUnlockPhase.offer;
    final facts = [
      if (!offersCount) c.gameCount == 1 ? '1 game' : '${c.gameCount} games',
      if (players != null && players > 0)
        players == 1 ? '1 player' : '$players players',
    ].join(' · ');
    final isBook = c.kind == CollectionKind.book;
    final credit = c.author ?? c.annotator;
    final annotator = c.author != null && c.annotator != c.author
        ? c.annotator
        : null;
    final edition = isBook
        ? [?c.publisher, if (c.publishedYear != null) '${c.publishedYear}']
        : [?collectionPlaceAndDates(c)];
    final body = AppTypography.textSmRegular.copyWith(
      color: colors.textPrimary,
      fontSize: 15.f,
      height: 22 / 15,
    );
    final secondary = AppTypography.textSmRegular.copyWith(
      color: colors.textSecondary,
    );
    if (isBook) {
      return _BookAboutPage(
        collection: c,
        facts: facts,
        locked: locked,
        phase: phase,
        onUnlock: onUnlock,
        error: error,
        onRetry: onRetry,
        onShowEvents: onShowEvents,
      );
    }
    return ListView(
      padding: EdgeInsets.fromLTRB(
        20.sp,
        20.sp,
        20.sp,
        32.sp + MediaQuery.viewPaddingOf(context).bottom,
      ),
      children: [
        if (c.coverUrl != null) ...[
          if (isBook)
            _BookCover(collection: c)
          else
            ClipRRect(
              borderRadius: BorderRadius.circular(8.br),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: _Cover(collection: c),
              ),
            ),
          SizedBox(height: isBook ? 20.sp : 16.sp),
        ],
        Text(
          c.title,
          style: AppTypography.textSmMedium.copyWith(
            color: colors.textPrimary,
            fontSize: 20.f,
            height: 26 / 20,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.2,
          ),
        ),
        if (credit != null) ...[
          SizedBox(height: 4.sp),
          _CollectionAuthorCredit(
            collection: c,
            label: c.author != null ? 'by $credit' : 'Annotated by $credit',
            style: AppTypography.textSmMedium.copyWith(
              color: colors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
        if (annotator != null) ...[
          SizedBox(height: 4.sp),
          Text('Annotated by $annotator', style: secondary),
        ],
        if (c.authorBio != null) ...[
          SizedBox(height: 12.sp),
          for (final paragraph in _paragraphs(c.authorBio))
            Padding(
              padding: EdgeInsets.only(bottom: 8.sp),
              child: Text(paragraph, style: body),
            ),
        ],
        if (c.annotatorBio != null && c.annotatorBio != c.authorBio) ...[
          SizedBox(height: 12.sp),
          for (final paragraph in _paragraphs(c.annotatorBio))
            Padding(
              padding: EdgeInsets.only(bottom: 8.sp),
              child: Text(paragraph, style: body),
            ),
        ],
        if (c.subtitle != null) ...[
          SizedBox(height: 4.sp),
          Text(c.subtitle!, style: secondary),
        ],
        if (edition.isNotEmpty) ...[
          SizedBox(height: 4.sp),
          TournamentAboutField(
            title: isBook ? 'Edition' : 'Event',
            icon: isBook ? Icons.menu_book_outlined : Icons.event_outlined,
            description: edition.join(' · '),
          ),
        ],
        if (facts.isNotEmpty) ...[
          SizedBox(height: 4.sp),
          TournamentAboutField(
            title: 'Contents',
            description: facts,
            icon: Icons.collections_bookmark_outlined,
          ),
        ],
        if (locked) ...[
          SizedBox(height: 4.sp),
          _UnlockAction(collection: c, phase: phase, onUnlock: onUnlock),
        ],
        if (error != null) ...[
          SizedBox(height: 16.sp),
          Row(
            children: [
              Expanded(
                child: Text(
                  userFacingError(
                    error,
                    fallback: "Couldn't load the rest of this collection.",
                  ),
                  style: secondary,
                ),
              ),
              if (onRetry != null)
                TextButton(
                  onPressed: onRetry,
                  child: Text(
                    'Try again',
                    style: AppTypography.textSmMedium.copyWith(
                      color: colors.accentText,
                    ),
                  ),
                ),
            ],
          ),
        ],
        SizedBox(height: 16.sp),
        Text(summary, style: body),
        for (final p in paragraphs) ...[
          SizedBox(height: 16.sp),
          Text(p, style: body),
        ],
        // The author's own foreword, when the book has one: after the
        // description, under a heading of the page's own voice.
        if (foreword.isNotEmpty) ...[
          SizedBox(height: 28.sp),
          Semantics(
            header: true,
            child: Text('Foreword', style: _aboutHeadingStyle(context)),
          ),
          for (var i = 0; i < foreword.length; i++) ...[
            SizedBox(height: i == 0 ? 10.sp : 16.sp),
            Text(
              foreword[i],
              key: i == 0 ? const ValueKey('collection_foreword') : null,
              style: body,
            ),
          ],
        ],
        SizedBox(height: 20.sp),
        Wrap(
          spacing: 8.sp,
          runSpacing: 4.sp,
          children: [
            if (onShowEvents != null)
              TextButton(onPressed: onShowEvents, child: const Text('Events')),
            if (onShowBooks != null)
              TextButton(
                onPressed: onShowBooks,
                child: const Text('Collections'),
              ),
            if (onShowPlayers != null)
              TextButton(
                onPressed: onShowPlayers,
                child: const Text('Players'),
              ),
          ],
        ),
      ],
    );
  }
}

/// What the reader is opening, even when the editorial description has
/// not been supplied. This describes the collection, never the full event.
String collectionContentsSummary(Collection c) => switch (c.kind) {
  CollectionKind.event => 'Selected games from ${c.title}.',
  CollectionKind.book => 'The games collected in ${c.title}.',
  CollectionKind.analysis => 'Selected game analysis from ${c.title}.',
};

/// Author credits open the shared profile on About. An annotator-only credit
/// remains editorial text rather than guessing an author identity.
class _CollectionAuthorCredit extends StatelessWidget {
  const _CollectionAuthorCredit({
    required this.collection,
    required this.label,
    required this.style,
  });
  final Collection collection;
  final String label;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final name = collection.author?.trim();
    if (name == null || name.isEmpty) return Text(label, style: style);
    return TextButton(
      key: ValueKey('collection_author_credit_${collection.slug}'),
      onPressed: () => CollectionAuthorScreen.open(
        context,
        author: CollectionAuthor(id: collection.authorId ?? name, name: name),
        collectionSlug: collection.slug,
        about: true,
      ),
      style: TextButton.styleFrom(
        foregroundColor: style.color,
        padding: EdgeInsets.zero,
        minimumSize: const Size(44, 44),
        alignment: AlignmentDirectional.centerStart,
      ),
      child: Text(label, style: style),
    );
  }
}

/// A compact jacket and bibliographic identity, then the editor's own text.
/// Missing editorial fields leave no empty headings or invented description.
class _BookAboutPage extends StatelessWidget {
  const _BookAboutPage({
    required this.collection,
    required this.facts,
    required this.locked,
    required this.phase,
    required this.onUnlock,
    this.error,
    this.onRetry,
    this.onShowEvents,
  });

  final Collection collection;
  final String facts;
  final bool locked;
  final CollectionUnlockPhase phase;
  final VoidCallback onUnlock;
  final Object? error;
  final VoidCallback? onRetry;
  final VoidCallback? onShowEvents;

  @override
  Widget build(BuildContext context) {
    final c = collection;
    final colors = context.colors;
    final body = AppTypography.textSmRegular.copyWith(
      color: colors.textPrimary,
      fontSize: 15.f,
      height: 22 / 15,
    );
    final secondary = AppTypography.textSmRegular.copyWith(
      color: colors.textSecondary,
      height: 20 / 14,
    );
    final credit = c.author ?? c.annotator;
    final edition = [
      ?c.publisher,
      if (c.publishedYear != null) '${c.publishedYear}',
    ];
    final description = _paragraphs(c.about);
    final foreword = _paragraphs(c.foreword);
    final authorBio = _paragraphs(c.authorBio);
    final annotatorBio = c.annotatorBio == c.authorBio
        ? <String>[]
        : _paragraphs(c.annotatorBio);

    List<Widget> section(
      String title,
      List<String> paragraphs, {
      Key? firstKey,
    }) => [
      if (paragraphs.isNotEmpty) ...[
        SizedBox(height: 24.sp),
        Semantics(
          header: true,
          child: Text(title, style: _aboutHeadingStyle(context)),
        ),
        for (var i = 0; i < paragraphs.length; i++) ...[
          SizedBox(height: i == 0 ? 8.sp : 12.sp),
          Text(paragraphs[i], key: i == 0 ? firstKey : null, style: body),
        ],
      ],
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final gutter = math.max(20.sp, (constraints.maxWidth - 640) / 2);
        return ListView(
          key: const ValueKey('book_about_content'),
          padding: EdgeInsets.fromLTRB(
            gutter,
            20.sp,
            gutter,
            32.sp + MediaQuery.viewPaddingOf(context).bottom,
          ),
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (c.coverUrl != null) ...[
                  _BookCover(collection: c),
                  SizedBox(width: 16.sp),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Semantics(
                        header: true,
                        child: Text(
                          c.title,
                          style: AppTypography.textSmMedium.copyWith(
                            color: colors.textPrimary,
                            fontSize: 20.f,
                            height: 26 / 20,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (c.subtitle != null &&
                          c.subtitle!.trim().isNotEmpty) ...[
                        SizedBox(height: 4.sp),
                        Text(c.subtitle!, style: secondary),
                      ],
                      if (credit != null && credit.trim().isNotEmpty) ...[
                        SizedBox(height: 8.sp),
                        _CollectionAuthorCredit(
                          collection: c,
                          label: c.author != null
                              ? 'by $credit'
                              : 'Annotated by $credit',
                          style: AppTypography.textSmMedium.copyWith(
                            color: colors.textPrimary,
                          ),
                        ),
                      ],
                      if (c.author != null &&
                          c.annotator != null &&
                          c.annotator != c.author) ...[
                        SizedBox(height: 4.sp),
                        Text('Annotated by ${c.annotator}', style: secondary),
                      ],
                      if (edition.isNotEmpty) ...[
                        SizedBox(height: 8.sp),
                        Text(edition.join(' · '), style: secondary),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            if (facts.isNotEmpty) ...[
              SizedBox(height: 16.sp),
              Text(
                facts,
                style: secondary.copyWith(
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
            if (locked) ...[
              SizedBox(height: 8.sp),
              _UnlockAction(collection: c, phase: phase, onUnlock: onUnlock),
            ],
            if (error != null) ...[
              SizedBox(height: 16.sp),
              Text(
                userFacingError(
                  error,
                  fallback: "Couldn't load the rest of this collection.",
                ),
                style: secondary,
              ),
              if (onRetry != null)
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton(
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(48, 48),
                      alignment: AlignmentDirectional.centerStart,
                    ),
                    onPressed: onRetry,
                    child: const Text('Try again'),
                  ),
                ),
            ],
            ...section('About this collection', description),
            ...section(
              'Foreword',
              foreword,
              firstKey: const ValueKey('collection_foreword'),
            ),
            ...section('About the author', authorBio),
            ...section('About the annotator', annotatorBio),
            if (onShowEvents != null) ...[
              SizedBox(height: 24.sp),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton(
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(48, 48),
                    alignment: AlignmentDirectional.centerStart,
                  ),
                  onPressed: onShowEvents,
                  child: const Text('Events'),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

/// Keep the complete jacket visible beside the book's identity.
class _BookCover extends StatelessWidget {
  const _BookCover({required this.collection});

  final Collection collection;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(4.br),
    child: SizedBox(
      width: 80.w,
      height: 120.w,
      child: _Cover(collection: collection, fit: BoxFit.contain),
    ),
  );
}

/// A heading inside the About page: the page's own ink and weight, no
/// label above it and no rule beside it.
TextStyle _aboutHeadingStyle(BuildContext context) =>
    AppTypography.textSmMedium.copyWith(
      color: context.colors.textPrimary,
      fontSize: 15.f,
      height: 20 / 15,
      fontWeight: FontWeight.w600,
    );

/// A book's Events tab: the events it covers, each drawn as the Collection
/// list draws an event (its image or the trophy, the name, the place and
/// dates) with the team's note under it. A tap opens the event wherever it
/// lives: its broadcast, its database page, or its annotated collection.
/// The events arrive with the detail read, so the tab waits on it (or says
/// it failed, with a retry) while it has none from the list row.
class _EventsPage extends StatelessWidget {
  const _EventsPage({
    required this.events,
    required this.pending,
    required this.error,
    required this.onRetry,
  });

  final List<CollectionEventRef> events;
  final bool pending;
  final Object? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (events.isEmpty) {
      if (pending) return const _CardsSkeleton();
      final failed = error;
      if (failed != null) {
        return _Notice(
          text: userFacingError(
            failed,
            fallback: "Couldn't load this collection's events.",
          ),
          actionLabel: 'Try again',
          onAction: onRetry,
        );
      }
      return const _Notice(text: 'No events for this collection yet.');
    }
    return ListView.builder(
      key: const PageStorageKey<String>('collection_events'),
      padding: _tabListPadding(context),
      itemCount: events.length,
      itemBuilder: (context, i) => Padding(
        padding: EdgeInsets.only(bottom: 12.sp),
        child: _EventRefRow(
          key: ValueKey<String>('collection_event_${events[i].linkId}'),
          event: events[i],
        ),
      ),
    );
  }
}

/// An event collection's Books tab: the books written about it, each drawn
/// as the Books list draws a book, with the team's note on why it belongs
/// here. A book opens on its own page (its preview, for a viewer without
/// Premium). [collectionId] is empty while a page opened by slug (from a
/// book's event) waits on its detail read.
class _BooksPage extends ConsumerWidget {
  const _BooksPage({
    required this.collectionId,
    required this.pending,
    required this.error,
    required this.onRetry,
  });

  final String collectionId;
  final bool pending;

  /// The detail read's failure, when the page still has no id to ask with.
  final Object? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (collectionId.isEmpty) {
      final failed = error;
      if (failed != null && !pending) {
        return _Notice(
          text: userFacingError(
            failed,
            fallback: "Couldn't load the collections about this event.",
          ),
          actionLabel: 'Try again',
          onAction: onRetry,
        );
      }
      return const _CardsSkeleton();
    }
    final books = ref.watch(
      collectionBooksOfEventCollectionProvider(collectionId),
    );
    return books.when(
      data: (list) => list.isEmpty
          ? const _Notice(text: 'No collections about this event yet.')
          : ListView.builder(
              key: const PageStorageKey<String>('collection_books'),
              padding: _tabListPadding(context),
              itemCount: list.length,
              itemBuilder: (context, i) => Padding(
                padding: EdgeInsets.only(bottom: 12.sp),
                child: CollectionCard(
                  key: ValueKey<String>('event_book_${list[i].id}'),
                  collection: list[i],
                  note: list[i].note,
                ),
              ),
            ),
      loading: () => const _CardsSkeleton(),
      error: (error, _) => _Notice(
        text: userFacingError(
          error,
          fallback: "Couldn't load the collections about this event.",
        ),
        actionLabel: 'Try again',
        onAction: () => ref.invalidate(
          collectionBooksOfEventCollectionProvider(collectionId),
        ),
      ),
    );
  }
}

/// A card list on a collection's tab: the Collection list's own gutters.
EdgeInsets _tabListPadding(BuildContext context) => EdgeInsets.fromLTRB(
  16.sp,
  16.sp,
  16.sp,
  12.sp + MediaQuery.viewPaddingOf(context).bottom,
);

class _EventRefRow extends ConsumerWidget {
  const _EventRefRow({super.key, required this.event});

  final CollectionEventRef event;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final e = event;
    // Room for the dates on a second line: a range across two years fills
    // one line alone.
    final line = collectionEventLine(e.location, e.dateStart, e.dateEnd);
    final canOpen = e.open != null;
    return CollectionPlateRow(
      plate: _EventPlate(imageUrl: e.imageUrl),
      title: e.title,
      meta: line,
      metaMaxLines: 2,
      note: e.note,
      semanticsLabel: [
        e.title,
        ?line,
        ?e.note,
        if (canOpen) 'Open event',
      ].join(', '),
      onTap: canOpen ? () => openCollectionEvent(context, ref, e) : null,
    );
  }
}

/// An event's picture, or the trophy the Collection list gives events
/// without one.
class _EventPlate extends StatelessWidget {
  const _EventPlate({required this.imageUrl});

  final String? imageUrl;

  @override
  Widget build(BuildContext context) {
    final plate = _PixelPlate(section: SpaceSection.events);
    final url = imageUrl;
    if (url == null) return plate;
    return CachedNetworkImage(
      imageUrl: url,
      fit: BoxFit.cover,
      placeholder: (_, __) => plate,
      errorWidget: (_, __, ___) => plate,
    );
  }
}

/// A locked collection's Games tab: its contents as the book prints them
/// (parts, then their chapters with how many games each holds), every entry
/// a way to the paywall, and the outcome line leading them.
class _LockedContents extends StatelessWidget {
  const _LockedContents({
    required this.collection,
    required this.phase,
    required this.onUnlock,
    required this.onLineTap,
  });

  final Collection collection;
  final CollectionUnlockPhase phase;
  final VoidCallback onUnlock;

  /// A chapter's tap; null while the page confirms the viewer's Premium.
  final VoidCallback? onLineTap;

  @override
  Widget build(BuildContext context) {
    final rows = <({CollectionSection section, int depth})>[];
    void walk(List<CollectionSection> nodes, int depth) {
      for (final s in nodes) {
        rows.add((section: s, depth: depth));
        walk(s.children, depth + 1);
      }
    }

    walk(collection.sections, 0);
    // A book kept without parts or chapters has no contents to show: the
    // preview says who plays in it instead, as its Players tab does, so the
    // way in never stands alone on an empty page.
    if (rows.isEmpty) {
      return _LockedPlayers(
        key: const PageStorageKey<String>('collection_locked_contents'),
        collection: collection,
        phase: phase,
        onUnlock: onUnlock,
      );
    }
    final leadWidth = _contentsLeadWidth(context, [
      for (final r in rows) r.section,
    ]);
    return ListView.builder(
      key: const PageStorageKey<String>('collection_locked_contents'),
      padding: EdgeInsets.only(
        top: 8.sp,
        bottom: 24.sp + MediaQuery.viewPaddingOf(context).bottom,
      ),
      itemCount: rows.length + 1,
      itemBuilder: (context, i) {
        if (i == 0) {
          return Padding(
            padding: EdgeInsets.fromLTRB(_headerInset, 0, _headerInset, 4.sp),
            child: _UnlockAction(
              collection: collection,
              phase: phase,
              onUnlock: onUnlock,
            ),
          );
        }
        final row = rows[i - 1];
        return _ContentsRow(
          key: ValueKey<String>('collection_contents_${row.section.id}'),
          section: row.section,
          depth: row.depth,
          first: i == 1,
          leadWidth: leadWidth,
          onTap: onLineTap,
        );
      },
    );
  }
}

/// What a contents line says: its number or label in quiet ink ([lead],
/// when the section has a title of its own) and its title.
({String? lead, String title}) _contentsLabel(CollectionSection s) {
  final named = s.title != null && s.title != s.label;
  final ({String? lead, String title}) label = switch (s.kind) {
    CollectionSectionKind.part => (
      lead: named ? s.label : null,
      title: named ? s.title! : s.label,
    ),
    CollectionSectionKind.chapter => (
      lead: named ? s.number ?? s.label : null,
      title: named ? s.title! : s.label,
    ),
    CollectionSectionKind.round ||
    CollectionSectionKind.stage ||
    CollectionSectionKind.other => (
      lead: null,
      title: named ? '${s.label} · ${s.title}' : s.label,
    ),
  };
  if (label.title.isNotEmpty) return label;
  return (lead: label.lead, title: s.number ?? 'Games');
}

/// A chapter or round line of a locked collection's contents.
TextStyle _contentsLineStyle(BuildContext context) => AppTypography.textSmMedium
    .copyWith(color: context.colors.textPrimary, fontWeight: FontWeight.w500);

double get _contentsLeadGap => 8.sp;

/// The width of the widest chapter number among [rows], as the contents
/// set it, so every chapter title starts on one line down the list.
double _contentsLeadWidth(
  BuildContext context,
  Iterable<CollectionSection> rows,
) {
  final style = _contentsLineStyle(
    context,
  ).copyWith(fontFeatures: const [FontFeature.tabularFigures()]);
  final scaler = MediaQuery.textScalerOf(context);
  var widest = 0.0;
  for (final s in rows) {
    if (s.kind == CollectionSectionKind.part) continue;
    final lead = _contentsLabel(s).lead;
    if (lead == null) continue;
    final painter = TextPainter(
      text: TextSpan(text: lead, style: style),
      textDirection: Directionality.of(context),
      textScaler: scaler,
      maxLines: 1,
    )..layout();
    widest = math.max(widest, painter.width);
    painter.dispose();
  }
  return widest.ceilToDouble();
}

/// One entry of a locked collection's contents. A part is a heading; a
/// chapter or round is a 44-high line with its number in quiet ink, its
/// title, and on the right its game count and the padlock.
class _ContentsRow extends StatelessWidget {
  const _ContentsRow({
    super.key,
    required this.section,
    required this.depth,
    required this.first,
    required this.leadWidth,
    required this.onTap,
  });

  final CollectionSection section;
  final int depth;
  final bool first;

  /// The width of the list's number column (its widest chapter number),
  /// 0 when no chapter carries one.
  final double leadWidth;

  /// Null while the page confirms the viewer's Premium.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final s = section;
    final isPart = s.kind == CollectionSectionKind.part;
    final (:lead, :title) = _contentsLabel(s);
    final main = isPart
        ? AppTypography.textSmMedium.copyWith(
            color: colors.textPrimary,
            fontSize: 17.f,
            height: 22 / 17,
            fontWeight: FontWeight.w700,
          )
        : _contentsLineStyle(context);
    final muted = main.copyWith(
      color: colors.textSecondary,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    // A chapter's title is what sells the book: two lines, as a part's.
    // Its number stands in the list's own column, so a title that wraps
    // hangs clear of the numbers, as a printed table of contents does.
    final Widget heading = !isPart && lead != null && leadWidth > 0
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              SizedBox(
                width: leadWidth,
                child: Text(
                  lead,
                  maxLines: 1,
                  softWrap: false,
                  textAlign: TextAlign.right,
                  style: muted,
                ),
              ),
              SizedBox(width: _contentsLeadGap),
              Expanded(
                child: Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: main,
                ),
              ),
            ],
          )
        : Text.rich(
            TextSpan(
              children: [
                if (lead != null) TextSpan(text: '$lead  ', style: muted),
                TextSpan(text: title),
              ],
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: main,
          );

    if (isPart) {
      return Semantics(
        header: true,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            _headerInset,
            first ? 8.sp : 24.sp,
            _headerInset,
            4.sp,
          ),
          child: heading,
        ),
      );
    }

    final count = s.gameCount == 1 ? '1 game' : '${s.gameCount} games';
    final tap = onTap;
    final line = Container(
      constraints: BoxConstraints(minHeight: 44.sp),
      // A title that wraps keeps clear of the next line's.
      padding: EdgeInsets.fromLTRB(
        _headerInset + (depth > 0 ? 12.sp : 0),
        8.sp,
        _headerInset,
        8.sp,
      ),
      alignment: Alignment.centerLeft,
      child: Row(
        children: [
          Expanded(child: heading),
          if (s.gameCount > 0) ...[
            SizedBox(width: 12.sp),
            Text(
              count,
              style: AppTypography.textXsMedium.copyWith(
                color: colors.textSecondary,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
          SizedBox(width: DiscoveryPadlock.gap + 2.sp),
          DiscoveryPadlock(color: colors.textSecondary),
        ],
      ),
    );
    return Semantics(
      button: tap != null,
      label: '${lead == null ? '' : '$lead '}$title, $count, Premium',
      excludeSemantics: true,
      onTap: tap,
      // A list line answers a press with a wash of the card surface, the
      // way a table row does; it does not shrink. No press while the page
      // is confirming the viewer's Premium: the line at the top says so.
      child: tap == null
          ? line
          : WallPressable(wash: colors.surface, onTap: tap, child: line),
    );
  }
}

/// A locked collection's Players tab: who is in it stays behind the same
/// boundary as their games.
class _LockedPlayers extends StatelessWidget {
  const _LockedPlayers({
    super.key,
    required this.collection,
    required this.phase,
    required this.onUnlock,
  });

  final Collection collection;
  final CollectionUnlockPhase phase;
  final VoidCallback onUnlock;

  @override
  Widget build(BuildContext context) {
    final names = collection.players.take(6).toList();
    final more = collection.players.length - names.length;
    return ListView(
      padding: EdgeInsets.fromLTRB(
        _headerInset,
        8.sp,
        _headerInset,
        24.sp + MediaQuery.viewPaddingOf(context).bottom,
      ),
      children: [
        _UnlockAction(collection: collection, phase: phase, onUnlock: onUnlock),
        if (names.isNotEmpty) ...[
          SizedBox(height: 8.sp),
          Text(
            // Names read "Last, First", so a comma cannot also part them.
            [...names, if (more > 0) '$more more'].join(' · '),
            style: AppTypography.textSmRegular.copyWith(
              color: context.colors.textSecondary,
              height: 20 / 14,
            ),
          ),
        ],
      ],
    );
  }
}

/// [text]'s paragraphs: blank lines separate them.
List<String> _paragraphs(String? text) => [
  for (final p in (text ?? '').split(RegExp(r'\n\s*\n')))
    if (p.trim().isNotEmpty) p.trim(),
];

class _CollectionScopedGamesScreen extends ConsumerStatefulWidget {
  const _CollectionScopedGamesScreen({
    required this.collection,
    this.player,
    this.opening,
  }) : assert(player != null || opening != null);
  final Collection collection;
  final CollectionPlayer? player;
  final CollectionOpening? opening;
  @override
  ConsumerState<_CollectionScopedGamesScreen> createState() =>
      _CollectionScopedGamesScreenState();
}

class _CollectionScopedGamesScreenState
    extends ConsumerState<_CollectionScopedGamesScreen> {
  GamesListViewMode _mode = GamesListViewMode.gamesCard;
  @override
  Widget build(BuildContext context) => EventViewShell(
    title: widget.player?.name ?? collectionOpeningName(widget.opening!),
    tabs: const ['Games'],
    tabStripOverride: const SizedBox.shrink(),
    actions: [
      IconButton(
        tooltip: 'Change games layout',
        icon: Icon(
          _mode == GamesListViewMode.gamesCard
              ? Icons.grid_view_rounded
              : Icons.view_list_rounded,
        ),
        onPressed: () => setState(
          () => _mode = GamesListViewMode
              .values[(_mode.index + 1) % GamesListViewMode.values.length],
        ),
      ),
    ],
    pageBuilder: (_, __) => _GamesPage(
      slug: widget.collection.slug,
      contents: const CollectionContents(sections: [], games: []),
      player: widget.player,
      opening: widget.opening,
      groupByDate: true,
      showSelector: false,
      onClearPlayer: () {},
      viewMode: _mode,
      onOpen: (games, index) {
        ref.read(chessboardViewFromProviderNew.notifier).state =
            ChessboardView.tour;
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => ChessBoardScreenNew(
              currentIndex: index,
              games: games,
              viewSource: ChessboardView.tour,
              showGamebaseButton: false,
              disableGamebaseOverlayByDefault: true,
              allowGameExport: false,
            ),
          ),
        );
      },
    ),
  );
}

/// One book-scoped result list, using the same cards as the original tabs.
class _BookSearchResults extends ConsumerWidget {
  const _BookSearchResults({
    required this.slug,
    required this.query,
    required this.opening,
    required this.viewMode,
    required this.onOpening,
    required this.onPlayer,
    required this.onGame,
  });

  final String slug;
  final CollectionSearchQuery query;
  final CollectionOpening? opening;
  final GamesListViewMode viewMode;
  final ValueChanged<CollectionOpening> onOpening;
  final ValueChanged<CollectionPlayer> onPlayer;
  final void Function(List<GamesTourModel>, int) onGame;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final effective = query.eco.isEmpty && opening != null
        ? CollectionSearchQuery(
            text: query.text,
            eco: opening!.eco,
            result: query.result,
            year: query.year,
            minYear: query.minYear,
            maxYear: query.maxYear,
            annotated: query.annotated,
            sort: query.sort,
          )
        : query;
    final gameKey = (slug: slug, query: effective, player: null as String?);
    final games = ref.watch(collectionFilteredContentsProvider(gameKey));
    // Game filters constrain openings and players too, without requiring their
    // names to occur in a game's PGN text. Each section matches text itself.
    final scopeQuery = effective.withText('');
    final scopeKey = (slug: slug, query: scopeQuery, player: null as String?);
    final scope = scopeQuery.isActive
        ? ref.watch(collectionFilteredContentsProvider(scopeKey))
        : null;
    final openings = ref.watch(collectionOpeningsProvider(slug));
    final players = ref.watch(collectionPlayersProvider(slug));
    final text = query.text.trim().toLowerCase();
    bool matches(String value) => value.toLowerCase().contains(text);
    final scopedGames = scope?.valueOrNull?.games;
    final openingItems = [
      for (final item in openings.valueOrNull ?? const <CollectionOpening>[])
        if ((matches(item.eco) || matches(collectionOpeningName(item))) &&
            (scope == null ||
                scopedGames?.any((game) => game.card.eco == item.eco) == true))
          item,
    ];
    final playerItems = [
      for (final item in players.valueOrNull ?? const <CollectionPlayer>[])
        if (matches('${item.title ?? ''} ${item.name} ${item.fed ?? ''}') &&
            (scope == null ||
                scopedGames?.any(
                      (game) =>
                          game.card.involves(item.key) ||
                          item.aliasKeys.any(game.card.involves),
                    ) ==
                    true))
          item,
    ];
    final gameItems = games.valueOrNull?.games ?? const <CollectionGame>[];
    final ordered = [for (final game in gameItems) game.game];
    final perRow = viewMode == GamesListViewMode.chessBoardGrid ? 2 : 1;
    Widget heading(String title, int count) => Padding(
      padding: EdgeInsets.fromLTRB(16.sp, 16.sp, 16.sp, 12.sp),
      child: Text(
        '$title ($count)',
        style: AppTypography.textSmMedium.copyWith(
          color: context.colors.textPrimary,
        ),
      ),
    );
    Widget status(AsyncValue<Object?> value, String empty, VoidCallback retry) {
      if (value.isLoading) {
        return Padding(
          padding: EdgeInsets.all(16.sp),
          child: const Center(child: CircularProgressIndicator()),
        );
      }
      return Padding(
        padding: EdgeInsets.symmetric(horizontal: 16.sp, vertical: 8.sp),
        child: value.hasError
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    userFacingError(
                      value.error!,
                      fallback: "Couldn't load results.",
                    ),
                  ),
                  TextButton(onPressed: retry, child: const Text('Try again')),
                ],
              )
            : Text(
                empty,
                style: AppTypography.textSmRegular.copyWith(
                  color: context.colors.textSecondary,
                ),
              ),
      );
    }

    final openingStatus = scope != null && (scope.isLoading || scope.hasError)
        ? scope
        : openings;
    final playerStatus = scope != null && (scope.isLoading || scope.hasError)
        ? scope
        : players;
    void retryScope() {
      ref.invalidate(collectionFilteredContentsProvider(scopeKey));
    }

    return CustomScrollView(
      key: const ValueKey('book_search_results'),
      slivers: [
        SliverToBoxAdapter(child: heading('Openings', openingItems.length)),
        if (openingItems.isEmpty)
          SliverToBoxAdapter(
            child: status(openingStatus, 'No openings match this search.', () {
              ref.invalidate(collectionOpeningsProvider(slug));
              retryScope();
            }),
          ),
        SliverList.builder(
          itemCount: openingItems.length,
          itemBuilder: (_, index) {
            final item = openingItems[index];
            return Padding(
              padding: EdgeInsets.fromLTRB(16.sp, 0, 16.sp, 8.sp),
              child: OpeningEventCard(
                key: ValueKey('book_search_opening_${item.eco}'),
                name: collectionOpeningName(item),
                eco: item.eco,
                fen: item.fen,
                gameCount: item.gameCount,
                useEventImageFrame: true,
                onTap: () => onOpening(item),
              ),
            );
          },
        ),
        SliverToBoxAdapter(child: heading('Games', ordered.length)),
        if (ordered.isEmpty)
          SliverToBoxAdapter(
            child: status(
              games,
              'No games match this search.',
              () => ref.invalidate(collectionFilteredContentsProvider(gameKey)),
            ),
          ),
        SliverList.builder(
          itemCount: (ordered.length / perRow).ceil(),
          itemBuilder: (_, index) => Padding(
            padding: EdgeInsets.only(bottom: 12.sp),
            child: DiscoveryGameList(
              games: ordered,
              start: index * perRow,
              limit: perRow,
              viewMode: viewMode,
              streamEnabled: false,
              onOpen: (_, local) => onGame(ordered, local),
            ),
          ),
        ),
        SliverToBoxAdapter(child: heading('Players', playerItems.length)),
        if (playerItems.isEmpty)
          SliverToBoxAdapter(
            child: status(playerStatus, 'No players match this search.', () {
              ref.invalidate(collectionPlayersProvider(slug));
              retryScope();
            }),
          ),
        SliverList.builder(
          itemCount: playerItems.length,
          itemBuilder: (_, index) => Padding(
            padding: EdgeInsets.fromLTRB(16.sp, 0, 16.sp, 8.sp),
            child: _CollectionPlayerRow(
              player: playerItems[index],
              rank: index + 1,
              onPick: onPlayer,
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: SizedBox(
            height: 24.sp + MediaQuery.viewPaddingOf(context).bottom,
          ),
        ),
      ],
    );
  }
}

class _CollectionGamesSearchState extends ChangeNotifier {
  final controller = TextEditingController();
  final focus = FocusNode();
  Timer? _debounce;
  CollectionSearchQuery query = const CollectionSearchQuery();

  void setQuery(CollectionSearchQuery value) {
    query = value;
    notifyListeners();
  }

  void changed(String text) {
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 200),
      () => setQuery(query.withText(text)),
    );
  }

  void flush() {
    _debounce?.cancel();
    setQuery(query.withText(controller.text));
  }

  void clear() {
    _debounce?.cancel();
    controller.clear();
    focus.unfocus();
    setQuery(query.withText(''));
  }

  @override
  void dispose() {
    _debounce?.cancel();
    controller.dispose();
    focus.dispose();
    super.dispose();
  }
}

class _CollectionGamesSearchBar extends StatelessWidget {
  const _CollectionGamesSearchBar({
    required this.state,
    this.opening,
    this.onClearOpening,
    this.pinned = false,
    this.hintText = 'Search collection games',
  });
  final String hintText;
  final _CollectionGamesSearchState state;
  final CollectionOpening? opening;
  final VoidCallback? onClearOpening;
  final bool pinned;

  Future<void> _filters(BuildContext context) async {
    state.focus.unfocus();
    state.flush();
    final incomingEco = opening?.eco ?? '';
    final query = state.query;
    final current = query.eco.isEmpty && incomingEco.isNotEmpty
        ? CollectionSearchQuery(
            text: query.text,
            eco: incomingEco,
            result: query.result,
            year: query.year,
            minYear: query.minYear,
            maxYear: query.maxYear,
            annotated: query.annotated,
            sort: query.sort,
          )
        : query;
    final result = await showCollectionSearchFilters(context, current);
    if (context.mounted && result != null) {
      if (incomingEco.isNotEmpty && result.eco != incomingEco) {
        onClearOpening?.call();
      }
      state.setQuery(result);
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: state,
    builder: (context, _) => EventSearchBarFrame(
      horizontalPadding: pinned
          ? ResponsiveHelper.adaptive(phone: 20.sp, tablet: 32.sp)
          : 16.sp,
      child: SimpleSearchBar(
        controller: state.controller,
        compactFilter: pinned,
        focusNode: state.focus,
        hintText: hintText,
        textFieldKey: const ValueKey('collection_games_search'),
        filterButtonKey: const ValueKey('collection_games_filters'),
        filterBadgeCount:
            state.query.filterCount +
            (state.query.eco.isEmpty && opening != null ? 1 : 0),
        onChanged: state.changed,
        onOpenFilter: () => _filters(context),
        onCloseTap: state.clear,
      ),
    ),
  );
}

class _GamesPage extends ConsumerStatefulWidget {
  const _GamesPage({
    required this.contents,
    this.showSelector = true,
    required this.player,
    required this.onClearPlayer,
    required this.onOpen,
    required this.viewMode,
    this.opening,
    this.onClearOpening,
    required this.slug,
    this.groupByDate = false,
    this.flatList = false,
    this.searchState,
  });
  final String slug;
  final bool groupByDate;
  final bool flatList;
  final _CollectionGamesSearchState? searchState;
  final CollectionContents contents;
  final bool showSelector;
  final CollectionPlayer? player;
  final VoidCallback onClearPlayer;
  final void Function(List<GamesTourModel> games, int index) onOpen;
  final GamesListViewMode viewMode;
  final CollectionOpening? opening;
  final VoidCallback? onClearOpening;

  @override
  ConsumerState<_GamesPage> createState() => _GamesPageState();
}

class _GamesPageState extends ConsumerState<_GamesPage>
    with AutomaticKeepAliveClientMixin {
  final Set<String> _collapsed = {};
  String _selected = 'all';
  late final _searchState = widget.searchState ?? _CollectionGamesSearchState();
  CollectionSearchQuery get _query => _searchState.query;

  @override
  void initState() {
    super.initState();
    _searchState.addListener(_queryChanged);
  }

  void _queryChanged() {
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final scroll = PrimaryScrollController.maybeOf(context);
      if (scroll != null && scroll.hasClients) scroll.jumpTo(0);
    });
  }

  @override
  void dispose() {
    _searchState.removeListener(_queryChanged);
    if (widget.searchState == null) _searchState.dispose();
    super.dispose();
  }

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final query = CollectionSearchQuery(
      text: _query.text,
      eco: _query.eco.isEmpty ? (widget.opening?.eco ?? '') : _query.eco,
      result: _query.result,
      year: _query.year,
      minYear: _query.minYear,
      maxYear: _query.maxYear,
      annotated: _query.annotated,
      sort: _query.sort,
    );
    final key = (slug: widget.slug, query: query, player: widget.player?.key);
    final filtered = query.isActive || widget.player != null
        ? ref.watch(collectionFilteredContentsProvider(key))
        : null;
    return Column(
      children: [
        if (widget.searchState == null)
          _CollectionGamesSearchBar(
            state: _searchState,
            opening: widget.opening,
            onClearOpening: widget.onClearOpening,
          ),
        Expanded(
          child: filtered == null
              ? _body(widget.contents)
              : filtered.when(
                  skipLoadingOnReload: false,
                  data: _body,
                  loading: () => const _CardsSkeleton(),
                  error: (error, _) => _Notice(
                    text: _collectionErrorText(
                      error,
                      fallback: "Couldn't load the games.",
                    ),
                    actionLabel: 'Try again',
                    onAction: () =>
                        ref.invalidate(collectionFilteredContentsProvider(key)),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _body(CollectionContents contents) {
    final opening = widget.opening;
    if (contents.games.isEmpty) {
      return _Notice(
        text: _query.isActive
            ? 'No games match this search.'
            : opening == null
            ? 'No games in this collection yet.'
            : 'No games study ${opening.eco} in this collection yet.',
        actionLabel: opening == null || widget.onClearOpening == null
            ? null
            : 'All games',
        onAction: widget.onClearOpening,
      );
    }
    // Prior book chapter/round rendering: return _groupedBody(contents);
    if (widget.flatList) return _flatBody(contents);
    return _groupedBody(contents);
  }

  /// Keep the API's sequence intact for both the list and board previous/next.
  Widget _flatBody(CollectionContents contents) {
    final ordered = [for (final game in contents.games) game.game];
    final perRow = widget.viewMode == GamesListViewMode.chessBoardGrid ? 2 : 1;
    final opening = widget.opening;
    final showOpeningLine = opening != null && widget.onClearOpening != null;
    final lead = showOpeningLine ? 1 : 0;
    return ListView.builder(
      key: const PageStorageKey('collection_games'),
      padding: EdgeInsets.only(
        top: 12.sp,
        bottom: 24.sp + MediaQuery.viewPaddingOf(context).bottom,
      ),
      itemCount: lead + (ordered.length / perRow).ceil(),
      itemBuilder: (context, index) {
        if (showOpeningLine && index == 0) {
          return _PlayerLine(
            name: '${opening.eco} · ${opening.name ?? 'Opening'}',
            isOpening: true,
            onClear: widget.onClearOpening!,
          );
        }
        return Padding(
          padding: EdgeInsets.only(bottom: 12.sp),
          child: DiscoveryGameList(
            games: ordered,
            start: (index - lead) * perRow,
            limit: perRow,
            viewMode: widget.viewMode,
            streamEnabled: false,
            onOpen: (_, local) => widget.onOpen(ordered, local),
          ),
        );
      },
    );
  }

  /// Retained section layout for event collections and scoped game routes.
  Widget _groupedBody(CollectionContents contents) {
    final picked = widget.player;
    final opening = widget.opening;
    final viewMode = widget.viewMode;
    final groups = groupCollectionGames(
      widget.groupByDate ? const [] : contents.sections,
      [
        for (final g in contents.games)
          if (picked == null ||
              g.card.involves(picked.key) ||
              picked.aliasKeys.any(g.card.involves))
            g,
      ],
      preserveGameOrder: _query.sort != 'default',
    );
    final selectionGroups = widget.showSelector && _query.isActive
        ? groupCollectionGames(widget.contents.sections, widget.contents.games)
        : groups;
    final selected = selectionGroups.any((g) => g.section?.id == _selected)
        ? _selected
        : 'all';
    final selectedGroups =
        selected != 'all' && !groups.any((g) => g.section?.id == selected)
        ? <CollectionGameGroup>[]
        : selectCollectionGameGroups(groups, selected);
    final ordered = [
      for (final group in selectedGroups)
        for (final g in group.games) g.game,
    ];
    final showOpeningLine = opening != null && !widget.groupByDate;
    final lead =
        (widget.showSelector ? 1 : 0) +
        (picked == null || widget.groupByDate ? 0 : 1) +
        (showOpeningLine ? 1 : 0);
    final perRow = viewMode == GamesListViewMode.chessBoardGrid ? 2 : 1;
    final rows = <({int group, int? start})>[];
    final hiddenParents = <String>{};
    for (var index = 0; index < selectedGroups.length; index++) {
      final group = selectedGroups[index];
      final section = group.section;
      if (section?.parentId != null &&
          hiddenParents.contains(section!.parentId)) {
        hiddenParents.add(section.id);
        continue;
      }
      rows.add((group: index, start: null));
      if (_collapsed.contains(section?.id)) {
        if (section?.kind == CollectionSectionKind.part) {
          hiddenParents.add(section!.id);
        }
        continue;
      }
      for (var start = 0; start < group.games.length; start += perRow) {
        rows.add((group: index, start: start));
      }
    }
    return ListView.builder(
      key: const PageStorageKey('collection_games'),
      padding: EdgeInsets.only(
        top: 12.sp,
        bottom: 24.sp + MediaQuery.viewPaddingOf(context).bottom,
      ),
      itemCount: lead + (selectedGroups.isEmpty ? 1 : rows.length),
      itemBuilder: (context, i) {
        if (widget.showSelector && i == 0) {
          return Padding(
            padding: EdgeInsets.fromLTRB(_headerInset, 0, _headerInset, 8.sp),
            child: Semantics(
              label: 'Select chapter or round',
              child: TextDropDownWidget(
                multiline: true,
                selectedId: selected,
                items: [
                  {'key': 'all', 'value': 'All games', 'status': 'completed'},
                  for (final group in selectionGroups)
                    if (group.section != null)
                      {
                        'key': group.section!.id,
                        'value': collectionGroupTitle(group.section!),
                        'status': 'completed',
                      },
                ],
                onChanged: (id) => setState(() {
                  _selected = id;
                  _collapsed.remove(id);
                  final parent = groups
                      .where((g) => g.section?.id == id)
                      .firstOrNull
                      ?.section
                      ?.parentId;
                  if (parent != null) _collapsed.remove(parent);
                }),
              ),
            ),
          );
        }
        if (showOpeningLine && i == (widget.showSelector ? 1 : 0)) {
          return _PlayerLine(
            name: '${opening.eco} · ${opening.name ?? 'Opening'}',
            isOpening: true,
            onClear: widget.onClearOpening!,
          );
        }
        if (picked != null &&
            !widget.groupByDate &&
            i == (widget.showSelector ? 1 : 0) + (opening == null ? 0 : 1)) {
          return _PlayerLine(name: picked.name, onClear: widget.onClearPlayer);
        }
        if (selectedGroups.isEmpty) {
          return Padding(
            padding: EdgeInsets.all(24.sp),
            child: Text(
              _query.isActive
                  ? 'No games match this search.'
                  : 'No games in this chapter or round.',
            ),
          );
        }
        final row = rows[i - lead];
        final group = selectedGroups[row.group];
        final start = row.start;
        if (start == null) {
          final section = group.section;
          final expanded = !_collapsed.contains(section?.id);
          return Padding(
            padding: EdgeInsets.fromLTRB(
              16.sp,
              row.group == 0 ? 0 : 12.sp,
              16.sp,
              12.sp,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TournamentRoundHeader(
                  multiline: true,
                  key: ValueKey(
                    _query.sort == 'default'
                        ? 'collection_round_${section?.id}'
                        : 'collection_round_${section?.id}_${row.group}',
                  ),
                  title: section == null
                      ? 'Other games'
                      : collectionGroupTitle(section),
                  subtitle: section?.startsAt != null
                      ? '${DateFormat('d MMM yyyy, HH:mm').format(section!.startsAt!.toUtc())} UTC'
                      : section?.startsOn == null
                      ? null
                      : DateFormat('d MMM yyyy').format(section!.startsOn!),
                  isExpanded: expanded,
                  onToggle: () => setState(() {
                    if (!_collapsed.add(section?.id ?? 'unsorted')) {
                      _collapsed.remove(section?.id ?? 'unsorted');
                    }
                  }),
                ),
                if (expanded && _paragraphs(section?.intro).isNotEmpty)
                  _SectionIntro(paragraphs: _paragraphs(section?.intro)),
              ],
            ),
          );
        }
        return Padding(
          padding: EdgeInsets.only(
            bottom: start + perRow < group.games.length ? 12.sp : 4.sp,
          ),
          child: DiscoveryGameList(
            games: [for (final g in group.games) g.game],
            start: start,
            limit: perRow,
            viewMode: viewMode,
            streamEnabled: false,
            onOpen: (_, local) => widget.onOpen(ordered, group.offset + local),
          ),
        );
      },
    );
  }
}

String collectionGroupTitle(CollectionSection section) {
  final title = section.title?.trim();
  return title == null || title.isEmpty || title == section.label
      ? section.label
      : '${section.label}: $title';
}

/// The picked player's name over their games, and the way back to all.
class _PlayerLine extends StatelessWidget {
  const _PlayerLine({
    required this.name,
    required this.onClear,
    this.isOpening = false,
  });

  final String name;
  final VoidCallback onClear;
  final bool isOpening;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(_headerInset, 0, 8.sp, 8.sp),
      child: Row(
        children: [
          Expanded(
            child: Text(
              isOpening ? name : 'Games of $name',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.textSmMedium.copyWith(
                color: context.colors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          TextButton(
            onPressed: onClear,
            child: Text(
              'Show all',
              style: AppTypography.textSmMedium.copyWith(
                color: context.colors.accentText,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A chapter's introduction, read before its games.
class _SectionIntro extends StatelessWidget {
  const _SectionIntro({required this.paragraphs});

  final List<String> paragraphs;

  @override
  Widget build(BuildContext context) {
    final style = AppTypography.textSmRegular.copyWith(
      color: context.colors.textSecondary,
      height: 20 / 14,
    );
    return Padding(
      padding: EdgeInsets.fromLTRB(_headerInset, 0, _headerInset, 12.sp),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < paragraphs.length; i++) ...[
            if (i > 0) SizedBox(height: 8.sp),
            Text(paragraphs[i], style: style),
          ],
        ],
      ),
    );
  }
}

class _PlayersPage extends StatelessWidget {
  const _PlayersPage({
    required this.players,
    required this.onPick,
    this.numbered = false,
  });

  final bool numbered;

  final List<CollectionPlayer> players;
  final ValueChanged<CollectionPlayer> onPick;

  @override
  Widget build(BuildContext context) {
    if (players.isEmpty) {
      return const _Notice(text: 'No players in this collection yet.');
    }
    return ListView.separated(
      padding: EdgeInsets.fromLTRB(
        16.sp,
        12.sp,
        16.sp,
        24.sp + MediaQuery.viewPaddingOf(context).bottom,
      ),
      itemCount: players.length,
      separatorBuilder: (_, __) => SizedBox(height: 8.sp),
      itemBuilder: (context, i) => _CollectionPlayerRow(
        key: ValueKey<String>('collection_player_${players[i].key}'),
        player: players[i],
        rank: numbered ? i + 1 : null,
        onPick: onPick,
      ),
    );
  }
}

/// One of a collection's players: their profile circle (photo, flag and
/// title, as every person on these pages wears it), the name and best
/// rating, and how many of the collection's games they play. Tap shows
/// their games here; a long press lifts the row into the player focus menu
/// (their games, My Space for the player and their Games tab, share).
class _CollectionPlayerRow extends ConsumerWidget {
  const _CollectionPlayerRow({
    super.key,
    required this.player,
    required this.onPick,
    this.rank,
  });

  final int? rank;

  final CollectionPlayer player;
  final ValueChanged<CollectionPlayer> onPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = player;
    final fideId = int.tryParse(p.fideId ?? '');
    final title = p.title?.trim();
    final fed = p.fed?.trim();
    final count = p.games == 1 ? '1 game' : '${p.games} games';
    void pick() => onPick(p);
    return CardContextMenu(
      onPreviewTap: pick,
      actions: (menuContext) => playerMenuActions(
        menuContext,
        ref,
        playerName: p.name,
        fideId: fideId != null && fideId > 0 ? fideId : null,
        title: title,
        federation: fed,
        rating: p.bestElo,
        gamebasePlayerId: p.playerId,
        onOpen: pick,
        openLabel: 'Show their games',
        openIcon: Icons.open_in_new_rounded,
      ),
      child: FigmaPlayerCard(
        player: PlayerStandingModel(
          name: p.name,
          countryCode: fed ?? '',
          title: title,
          fideId: fideId,
          gamebasePlayerId: p.playerId,
          score: p.bestElo ?? 0,
          scoreChange: 0,
          hasRatingDiff: false,
          matchScore: '',
        ),
        rank: rank,
        showRank: rank != null,
        showFavoriteButton: false,
        hideMissingRating: true,
        trailing: Semantics(
          label: count,
          excludeSemantics: true,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _CollectionGameMark(color: context.colors.textSecondary),
              SizedBox(width: 6.w),
              Text(
                '${p.games}',
                style: AppTypography.textMdMedium.copyWith(
                  color: context.colors.textPrimary,
                ),
              ),
            ],
          ),
        ),
        onTap: pick,
      ),
    );
  }
}

/// The real ChessEver mark, with the dark canvas removed through the same
/// luminance-to-alpha treatment used by the news cover's monochrome logo.
class _CollectionGameMark extends StatelessWidget {
  const _CollectionGameMark({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    final side = 20.ic;
    // The artwork spans 52% of its canvas. Leave a little breathing room
    // around that silhouette while cropping only the transparent canvas.
    final canvas = side / 0.55;
    return SizedBox.square(
      dimension: side,
      child: ClipRect(
        child: OverflowBox(
          minWidth: canvas,
          maxWidth: canvas,
          minHeight: canvas,
          maxHeight: canvas,
          child: ColorFiltered(
            colorFilter: ColorFilter.matrix([
              0, 0, 0, 0, color.r * 255,
              0, 0, 0, 0, color.g * 255,
              0, 0, 0, 0, color.b * 255,
              0.4252, 1.4304, 0.1444, 0, -25.5,
            ]),
            child: Image.asset(
              PngAsset.newAppLogo,
              width: canvas,
              height: canvas,
              fit: BoxFit.contain,
              excludeFromSemantics: true,
            ),
          ),
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.text, this.actionLabel, this.onAction});

  final String text;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(20.sp, 32.sp, 20.sp, 32.sp),
      children: [
        Text(
          text,
          textAlign: TextAlign.center,
          style: AppTypography.textSmRegular.copyWith(
            color: context.colors.textSecondary,
          ),
        ),
        if (actionLabel != null && onAction != null) ...[
          SizedBox(height: 8.sp),
          Center(
            child: TextButton(
              onPressed: onAction,
              child: Text(
                actionLabel!,
                style: AppTypography.textSmMedium.copyWith(
                  color: context.colors.accentText,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _CardsSkeleton extends StatelessWidget {
  const _CardsSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.all(16.sp),
      children: [
        for (var i = 0; i < 4; i++)
          Padding(
            padding: EdgeInsets.only(bottom: 12.sp),
            child: SkeletonWidget(
              ignoreContainers: true,
              child: Container(
                height: 84.sp,
                decoration: BoxDecoration(
                  color: context.colors.surfaceRecessed,
                  borderRadius: BorderRadius.circular(8.br),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
