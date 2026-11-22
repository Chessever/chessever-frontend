import 'package:chessever2/screens/collections/collection_author_screen.dart';
import 'package:chessever2/screens/collections/collections_root.dart';
import 'package:chessever2/widgets/home_top_bar.dart' show HomeTopBarMetrics;
import 'package:chessever2/screens/home/start_screen.dart';
import 'package:chessever2/screens/home/widget/bottom_nav_bar.dart'
    show BottomNavBarItem;
import 'package:chessever2/screens/collections/opening_event_card.dart'
    show collectionOpeningName;
import 'package:chessever2/screens/collections/collection_catalog_views.dart';
import 'package:chessever2/screens/collections/collection_counts_refresher.dart';
import 'package:chessever2/repository/gamebase/collections/collection_search_query.dart';
import 'package:chessever2/screens/collections/collection_search_filters.dart';
import 'package:chessever2/widgets/search_mode/search_mode.dart';
import 'package:chessever2/widgets/search_no_matches.dart';
import 'dart:async';
import 'dart:math' as math;
import 'package:chessever2/e2e/e2e_ids.dart';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:chessever2/providers/favorite_events_provider.dart';
import 'package:chessever2/repository/favorites/models/favorite_event.dart';
import 'package:chessever2/screens/collections/collection_bindings.dart';
import 'package:chessever2/screens/collections/collection_plate_row.dart';
import 'package:chessever2/screens/collections/collection_share.dart';
export 'package:chessever2/screens/collections/collection_plate_row.dart';
import 'package:chessever2/screens/collections/collections_data.dart';
import 'package:chessever2/screens/collections/open_collection_game.dart';
import 'package:chessever2/screens/collections/collections_tab_provider.dart';
import 'package:chessever2/screens/collections/event_view_shell.dart';
import 'package:chessever2/screens/for_you/discovery/widgets/discovery_common.dart'
    show discoveryGutter;
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
import 'package:chessever2/widgets/star_notifications.dart';
import 'package:chessever2/widgets/quick_list_toggles.dart';
// import 'package:chessever2/screens/library/game_tree/library_game_tree_targets.dart';
// import 'package:chessever2/widgets/game_tree/build_tree_button.dart';
// import 'package:chessever2/widgets/paywall/premium_game_access.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:intl/intl.dart';

/// The primary Collections destination: About, published collections and
/// authors in the established event-card language.
///
/// Two ways in: the dock's Collections tab ([embedded], a root:
/// [CollectionsRoot], the bar every root wears with the pages as its tabs,
/// no way back) and [open] (a page pushed over another, from Discovery's
/// tile or Search: back and a centred title over the page tabs).
class CollectionsScreen extends ConsumerStatefulWidget {
  const CollectionsScreen({super.key, this.embedded = false});

  /// The dock's Collections tab: a root page in the home shell.
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
  /// The catalog's search, typed in the header's place once its floating
  /// button opens it.
  final SearchModeController _search = SearchModeController();
  CollectionSearchQuery _query = const CollectionSearchQuery();
  bool get embedded => widget.embedded;
  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _rememberTab(int index) {
    ref.read(selectedCollectionsTabProvider.notifier).state =
        CollectionsTab.values[index];
  }

  void _searchFor(String text) {
    final next = _query.withText(text);
    if (next != _query) setState(() => _query = next);
  }

  /// A catalog's no-hits line's way back: the words when the query has
  /// any (the field empties, heard as typed), else the filters.
  void _clearNarrowing() {
    if (_query.text.trim().isNotEmpty) {
      _search.text.clear();
      // A field emptied while the search is closed reaches no listener.
      _searchFor('');
      return;
    }
    setState(() => _query = const CollectionSearchQuery());
  }

  Future<void> _filters() async {
    _search.focusNode.unfocus();
    // What was typed counts before the sheet, not once the typing pause
    // ends.
    _searchFor(_search.query);
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
    return CollectionCountsRefresher(child: _shell(context, query));
  }

  /// The catalog's search: its floating button over Collections and Authors
  /// opens it in the header's place; About has nothing to search. Its
  /// filters stand beside the field.
  EventViewSearch _catalogSearch() => EventViewSearch(
    controller: _search,
    label: 'Search collections',
    hintText: 'Search collections',
    textFieldKey: const ValueKey('collections_search'),
    filterKey: const ValueKey('collections_filters'),
    tabs: {CollectionsTab.collections.index, CollectionsTab.authors.index},
    badgeCount: _query.filterCount,
    onFilters: _filters,
    onQuery: _searchFor,
    // An emptied field empties the query at once, words the filter sheet
    // took early included.
    onChanged: (text) {
      if (text.trim().isEmpty) _searchFor('');
    },
    // Filters stay, counted on their glyph.
    onClose: () => _searchFor(''),
  );

  /// Page [index]. As the dock's tab ([root]) every page opens on the
  /// roots' one lead-in under the bar ([HomeTopBarMetrics.contentGap]), so
  /// its first card starts on the line Home's, Botvinnik's and Profile's
  /// first content does; pushed, under the page tabs, the catalogs keep
  /// their own tighter lead-ins.
  Widget _page(
    BuildContext context,
    CollectionSearchQuery query,
    int index, {
    double bottomPadding = 0,
    bool root = false,
  }) {
    final top = root ? HomeTopBarMetrics.contentGap : null;
    return switch (index) {
      // 0 => CollectionOpeningCatalog(query: query, bottomPadding: ...),
      0 => _CollectionsAboutPage(bottomPadding: bottomPadding, topPadding: top),
      // Each catalog is searched in place, and ends clear of the floating
      // search button while it is there (CollectionCatalogList; the root
      // hands the button's room in [bottomPadding]).
      1 => CollectionBooksCatalog(
        query: query,
        onClear: _clearNarrowing,
        bottomPadding: bottomPadding,
        topPadding: top,
      ),
      _ => CollectionAuthorsCatalog(
        query: query,
        onClear: _clearNarrowing,
        bottomPadding: bottomPadding,
        topPadding: top,
      ),
    };
  }

  /// The dock's tab: the root composition, remembering its page for the
  /// session, a held tab title making it the start screen's page.
  Widget _root(BuildContext context, CollectionSearchQuery query) {
    StartPage page(int index) =>
        collectionsStartPage(CollectionsTab.values[index]);
    return CollectionsRoot(
      tabs: [for (final tab in CollectionsTab.values) tab.label],
      initialTab: ref.read(selectedCollectionsTabProvider).index,
      onTabChanged: _rememberTab,
      onHoldTab: (index) => unawaited(
        makeStartScreenDefault(
          context,
          ref,
          section: BottomNavBarItem.collections,
          page: page(index),
        ),
      ),
      holdHint: (index) =>
          startScreenHint(BottomNavBarItem.collections, page(index)),
      search: _catalogSearch(),
      pageBuilder: (context, index, bottomPadding) => _page(
        context,
        query,
        index,
        bottomPadding: bottomPadding,
        root: true,
      ),
    );
  }

  Widget _shell(BuildContext context, CollectionSearchQuery query) {
    if (embedded) return _root(context, query);
    return EventViewShell(
      dotScope: 'collections.tab',
      key: e2eKey(E2eIds.collectionsRoot),
      title: 'Collections',
      // The catalog's search floats over Collections and Authors and opens
      // in the header's place; its filters stand in the header too, with
      // the search closed.
      search: _catalogSearch(),
      // Opening discovery is paused; retain its catalog and wiring below.
      // tabs: const ['Openings', 'Collections', 'Authors'],
      tabs: [for (final tab in CollectionsTab.values) tab.label],
      // Only the dock's tab remembers its page; a pushed copy always opens
      // on the catalog.
      initialTab: CollectionsTab.collections.index,
      pageBuilder: (context, index) => _page(context, query, index),
    );
  }
}

class _CollectionsAboutPage extends StatelessWidget {
  const _CollectionsAboutPage({this.bottomPadding = 0, this.topPadding});

  final double bottomPadding;

  /// Where the heading starts: the tab lists' own lead-in unless given.
  final double? topPadding;

  @override
  Widget build(BuildContext context) {
    final list = _tabListPadding(context);
    return ListView(
      key: const PageStorageKey('collections_about'),
      padding: list.copyWith(
        top: topPadding ?? list.top,
        bottom: list.bottom + bottomPadding,
      ),
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
}

/// The favorites identity of a collection. A starred collection is a plain
/// favorite-events row, like a starred event, so it sorts and syncs the
/// same way; `metadata.kind` tells it apart when it opens.
String collectionFavoriteId(Collection c) => 'collection:${c.slug}';

/// The favorites row that stars [c], or null when it is not starred.
FavoriteEvent? collectionFavorite(
  Iterable<FavoriteEvent> favorites,
  Collection c,
) {
  final id = collectionFavoriteId(c);
  for (final e in favorites) {
    if (e.eventId == id ||
        (e.metadata['kind'] == 'collection' && e.metadata['slug'] == c.slug)) {
      return e;
    }
  }
  return null;
}

bool collectionIsFavorited(Iterable<FavoriteEvent> favorites, Collection c) =>
    collectionFavorite(favorites, c) != null;

/// Stars or unstars [collection]: the one path behind every collection
/// star, so each writes the same row and the same analytics event.
///
Future<void> toggleCollectionFavorite({
  required BuildContext context,
  required Collection collection,
}) async {
  final allowed = await requireFullAuthGuard(context);
  if (!allowed || !context.mounted) return;

  // Resolved now: the card may be gone by the time the dialog closes.
  final container = ProviderScope.containerOf(context, listen: false);
  final messenger = ScaffoldMessenger.maybeOf(context);
  final notifier = container.read(favoriteEventsProvider.notifier);
  final saved = collectionFavorite(
    container.read(favoriteEventsProvider).valueOrNull ??
        const <FavoriteEvent>[],
    collection,
  );

  HapticFeedbackService.pin();

  void settled(bool isFavorited) {
    unawaited(
      container
          .read(collectionEngagementProvider)
          .setStar(collection.slug, isFavorited),
    );
    AnalyticsService.instance.trackEventDetached(
      'Collection Favorite Toggled',
      properties: {
        'collection_id': collection.id,
        'slug': collection.slug,
        'is_favorited': isFavorited,
      },
    );
  }

  if (saved != null) {
    try {
      await notifier.removeFavorite(saved.eventId);
      settled(false);
    } catch (e) {
      debugPrint('[CollectionCard] Error removing favorite: $e');
    }
    return;
  }

  final eventId = collectionFavoriteId(collection);
  final wantsAlerts = await askStarNotifications(
    context,
    subject: StarNotificationSubject.collection,
  );
  try {
    await notifier.addFavorite(
      eventId: eventId,
      eventName: collection.title,
      extraMetadata: {
        'kind': 'collection',
        'slug': collection.slug,
        'collectionKind': collection.kind.name,
        kStarNotificationsKey: wantsAlerts,
      },
    );
  } catch (e) {
    debugPrint('[CollectionCard] Error adding favorite: $e');
    return;
  }
  settled(true);
  if (wantsAlerts) {
    await activateEventStarNotifications(
      container: container,
      messenger: messenger,
    );
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
/// page preserves its complete jacket. A Premium collection is drawn like any
/// other and opens on its preview; its games ask for access when one is
/// opened. [note] is the team's caption
/// when the card is listed for an event ("Chapter 7 is this match's
/// decisive game").
class CollectionCard extends ConsumerWidget {
  const CollectionCard({
    super.key,
    required this.collection,
    this.note,
    this.opening,
    this.stacked = false,
    this.showStar = true,
    this.onOpened,
  });

  final Collection collection;
  final bool stacked;

  /// Every open of the collection, however it came: a tap, a screen
  /// reader's tap, the menu's Open, the lifted copy. My Space records its
  /// opens here.
  final VoidCallback? onOpened;

  /// False in My Space, where the card ends in a chevron: its star is the
  /// collection's favorite, and My Space never adds or removes one.
  final bool showStar;
  final String? note;
  final CollectionOpening? opening;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = collection;
    final engagement = ref.watch(collectionEngagementCountsProvider(c.slug));
    final views = (engagement?['viewCount'] as num?)?.toInt() ?? c.viewCount;
    final stars = (engagement?['starCount'] as num?)?.toInt() ?? c.starCount;

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

    void push() {
      onOpened?.call();
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => CollectionScreen(collection: c, opening: opening),
        ),
      );
    }

    // A tap on the card plays the card-tap haptic; the menu's Open row
    // already plays the menu's own, and the lifted copy none, as on every
    // card with a focus menu.
    void open() {
      HapticFeedbackService.cardTap();
      push();
    }

    return CollectionPlateRow(
      stacked: stacked,
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
      note: caption,
      semanticsLabel: [
        c.title,
        ?identity,
        tally,
        if (isBook) _plural(views, 'view'),
        if (isBook && stars > 0) _plural(stars, 'star'),
        ?caption,
      ].join(', '),
      onTap: open,
      onPreviewTap: push,
      trailing: showStar
          ? _CollectionStar(collection: c, count: isBook ? stars : null)
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(width: 4.w),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 20.ic,
                  color: context.colors.iconSecondary,
                ),
                SizedBox(width: 4.w),
              ],
            ),
      menuActions: (menuContext) =>
          collectionMenuActions(context, menuContext, ref, c, onOpen: push),
    );
  }
}

/// The focus menu a collection lifts into wherever it is held: Open, Share,
/// its star's notifications and My Space. [onOpen] opens the collection's
/// page the way the held surface does; [context] is the held surface's own.
List<LibraryMenuAction> collectionMenuActions(
  BuildContext context,
  BuildContext menuContext,
  WidgetRef ref,
  Collection c, {
  required VoidCallback onOpen,
}) => [
  LibraryMenuAction(
    icon: Icons.open_in_new_rounded,
    label: 'Open',
    onSelected: onOpen,
  ),
  if (buildCollectionShareUrl(c.slug) != null)
    LibraryMenuAction(
      icon: Icons.ios_share_rounded,
      label: 'Share',
      onSelected: () => shareCollection(context, c),
    ),
  starNotificationsMenuAction(
    context: menuContext,
    favorite: collectionFavorite(
      ref.read(favoriteEventsProvider).valueOrNull ?? const <FavoriteEvent>[],
      c,
    ),
    surface: 'collection',
  ),
  spaceMenuAction(
    context: menuContext,
    ref: ref,
    draft: collectionSpaceDraft(c),
  ),
];

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
        onTap: () =>
            toggleCollectionFavorite(context: context, collection: collection),
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

/// A collection's cover as its cards draw it, for surfaces outside this
/// file (the Today stories): the cover, or the pixel object when it has
/// none. [cacheWidth] decodes it at that many pixels wide, for a small
/// picture that need not hold the whole cover in memory.
class CollectionCover extends StatelessWidget {
  const CollectionCover({
    super.key,
    required this.collection,
    this.fit = BoxFit.cover,
    this.cacheWidth,
  });

  final Collection collection;
  final BoxFit fit;
  final int? cacheWidth;

  @override
  Widget build(BuildContext context) =>
      _Cover(collection: collection, fit: fit, cacheWidth: cacheWidth);
}

/// A collection's cover, or its pixel object (the trophy for an event, the
/// stacked boards for a book) when it has none.
class _Cover extends StatelessWidget {
  const _Cover({
    required this.collection,
    this.fit = BoxFit.cover,
    this.cacheWidth,
  });

  final Collection collection;
  final BoxFit fit;
  final int? cacheWidth;

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
      memCacheWidth: cacheWidth,
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
  // int get _gamesTab => _isBook ? 2 : 1;
  static const int _gamesTab = 1;
  static const int _playersTab = 2;

  // List<String> get _collectionTabs => _isBook
  //     ? const ['About', 'Openings', 'Games', 'Players']
  //     : const ['About', 'Games', 'Players'];
  List<String> get _collectionTabs => const ['About', 'Games', 'Players'];
  late CollectionOpening? _opening = widget.opening;

  /// Fixed by the kind the page opened as, so the tab strip never changes
  /// under the viewer.
  late final bool _isBook = widget.collection.kind == CollectionKind.book;

  final EventViewController _tabs = EventViewController();

  /// The page's search, run by the shell's search mode: it narrows the tab
  /// it opens on in place (a book's Games or Players, an event's Games).
  final _gameSearch = _CollectionGamesSearchState();

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
  final int _initialTab = _gamesTab;

  @override
  void initState() {
    super.initState();
    _gameSearch.addListener(_gameSearchChanged);
    if (_isBook) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          unawaited(trackCollectionRead(ref, widget.collection));
        }
      });
    }
  }

  void _gameSearchChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _gameSearch.removeListener(_gameSearchChanged);
    _tabs.dispose();
    _gameSearch.dispose();
    super.dispose();
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

  void _showRelated(String label) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Consumer(
          builder: (context, ref, _) {
            final slug = widget.collection.slug;
            final detail = ref.watch(collectionDetailProvider(slug));
            final c = detail.valueOrNull ?? widget.collection;
            final pending = detail.isLoading && !detail.hasValue;
            final error = detail.hasError && !detail.hasValue
                ? detail.error
                : null;
            void retry() => ref.invalidate(collectionDetailProvider(slug));
            final players = label == 'Players'
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
                _ => players!.when(
                  data: (list) => _PlayersPage(
                    players: list,
                    numbered: _isBook,
                    onPick: _showPlayer,
                  ),
                  loading: () => const _CardsSkeleton(),
                  error: (error, _) => _Notice(
                    text: _collectionMetadataError(error, players: true),
                    actionLabel: 'Try again',
                    onAction: () =>
                        ref.invalidate(collectionPlayersProvider(slug)),
                  ),
                ),
              },
            );
          },
        ),
      ),
    );
  }

  bool _openingGame = false;
  Future<void> _openGame(List<GamesTourModel> games, int index) async {
    if (_openingGame) return;
    _openingGame = true;
    try {
      await openCollectionGame(
        context,
        ref,
        slug: widget.collection.slug,
        previews: games,
        index: index,
      );
    } finally {
      _openingGame = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final slug = widget.collection.slug;
    final detail = ref.watch(collectionDetailProvider(slug));
    final c = detail.valueOrNull ?? widget.collection;
    final starred = collectionIsFavorited(
      ref.watch(favoriteEventsProvider).valueOrNull ?? const <FavoriteEvent>[],
      c,
    );
    // Metadata only, for everyone. A denied metadata request is not permission
    // to fetch PGNs or reconstruct identities from a collection summary.
    final contents = _opening == null
        ? ref.watch(collectionContentsProvider(slug))
        : ref.watch(
            collectionOpeningContentsProvider((slug: slug, eco: _opening!.eco)),
          );
    final players = ref.watch(collectionPlayersProvider(slug));
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
      dotScope: 'collection.tab',
      title: c.title,
      tabs: _collectionTabs,
      // scrollableTabs: _isBook,
      initialTab: _initialTab,
      controller: _tabs,
      // The search floats over the lists it covers and opens in the header's
      // place, over the same list filtered as the reader types: a book's
      // searches its Games and its Players, an event's its Games.
      search: EventViewSearch(
        controller: _gameSearch.mode,
        label: _isBook ? 'Search collection' : 'Search games',
        hintText: _isBook ? 'Search collection' : 'Search collection games',
        textFieldKey: const ValueKey('collection_games_search'),
        filterKey: const ValueKey('collection_games_filters'),
        tabs: {_gamesTab, if (_isBook) _playersTab},
        badgeCount: _gameSearch.filterBadgeCount(_opening),
        debounce: const Duration(milliseconds: 200),
        onQuery: _gameSearch.typed,
        onChanged: _gameSearch.edited,
        onClose: _gameSearch.closed,
        onFilters: () => _gameSearch.openFilters(
          context,
          opening: _opening,
          onClearOpening: () => setState(() => _opening = null),
        ),
      ),
      actions: [
        // Build Tree is off here: opening trees belong to My Prep, where they
        // track one player's preparation. Restore with the imports above.
        // if ((contents.valueOrNull?.games.length ?? 0) > 0) ...[
        //   BuildTreeButton(
        //     compact: true,
        //     target: CollectionTreeTarget(
        //       repository: ref.read(collectionsRepositoryProvider),
        //       slug: slug,
        //       title: c.title,
        //       knownGameCount: contents.valueOrNull?.games.length,
        //       requestAccess: (collection) => ensurePremiumGameAccess(
        //         context,
        //         featureId: collectionPaywallFeatureId(collection.kind),
        //         returnTo: kCollectionPaywallReturnTo,
        //       ),
        //     ),
        //   ),
        //   SizedBox(width: 6.w),
        // ],
        // Bare glyphs, as on an event's Games header: no tile behind the
        // view toggle or the menu.
        _CollectionViewToggle(onTap: _toggleGamesView),
        SizedBox(width: EventViewShell.headerGlyphGap),
        Builder(
          builder: (menuContext) => Semantics(
            container: true,
            button: true,
            label: 'More options',
            child: AppBarIcons(
              image: SvgAsset.threeDots,
              boxed: false,
              onTap: () {
                HapticFeedbackService.cardTap();
                unawaited(
                  showLibraryContextMenu(
                    context: menuContext,
                    actions: [
                      if (buildCollectionShareUrl(c.slug) != null)
                        LibraryMenuAction(
                          icon: Icons.ios_share_rounded,
                          label: 'Share',
                          onSelected: () => shareCollection(menuContext, c),
                        ),
                      LibraryMenuAction(
                        icon: starred
                            ? Icons.star_rounded
                            : Icons.star_outline_rounded,
                        label: starred ? 'Unstar' : 'Star',
                        onSelected: () => toggleCollectionFavorite(
                          context: context,
                          collection: c,
                        ),
                      ),
                      starNotificationsMenuAction(
                        context: context,
                        favorite: collectionFavorite(
                          ref.read(favoriteEventsProvider).valueOrNull ??
                              const <FavoriteEvent>[],
                          c,
                        ),
                        surface: 'collection',
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
            playerCount: players.valueOrNull?.length,
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
          1 => contents.when(
            // A refresh keeps the list on screen rather than flashing the
            // skeleton over it.
            skipLoadingOnReload: true,
            data: (data) => _GamesPage(
              slug: slug,
              searchState: _gameSearch,
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
                DiscoveryGameListSkeleton(count: 4, viewMode: _gamesViewMode),
              ],
            ),
            error: (error, _) => _Notice(
              text: _collectionMetadataError(error),
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
          _ => players.when(
            skipLoadingOnReload: true,
            // A book's players are searched in place; an event's Players
            // has no search.
            data: (list) => _isBook
                ? _SearchedPlayers(
                    slug: slug,
                    players: list,
                    query: _gameSearch.query,
                    opening: _opening,
                    onPick: _showPlayer,
                    onClear: _gameSearch.clearNarrowing,
                  )
                : _PlayersPage(players: list, onPick: _showPlayer),
            loading: () => const _CardsSkeleton(),
            error: (error, _) => _Notice(
              text: _collectionMetadataError(error, players: true),
              actionLabel: 'Try again',
              onAction: () => ref.invalidate(collectionPlayersProvider(slug)),
            ),
          ),
        };
      },
    );
  }
}

/// [error] as the reader sees it. The Premium check being out of reach is
/// said as such: the reader may well be entitled, so it is a retry, never
/// a paywall and never "your session has expired".
String _collectionErrorText(Object? error, {required String fallback}) {
  if (error is CollectionsRequestException && error.isAccessCheckUnavailable) {
    return "Couldn't check your Premium access just now.";
  }
  return userFacingError(error, fallback: fallback);
}

String _collectionMetadataError(Object? error, {bool players = false}) =>
    isCollectionPremiumGate(error)
    ? (players
          ? "Player previews aren't available from this server yet."
          : "Game previews aren't available from this server yet.")
    : _collectionErrorText(
        error,
        fallback: players
            ? "Couldn't load the players."
            : "Couldn't load the games.",
      );

class _AboutPage extends ConsumerWidget {
  const _AboutPage({
    required this.collection,
    required this.playerCount,
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
    final facts = [
      c.gameCount == 1 ? '1 game' : '${c.gameCount} games',
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
    this.error,
    this.onRetry,
    this.onShowEvents,
  });

  final Collection collection;
  final String facts;
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
  /// The list's search, opened from its floating button in the header's
  /// place.
  final _search = _CollectionGamesSearchState();

  @override
  void initState() {
    super.initState();
    _search.addListener(_searchChanged);
  }

  void _searchChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _search
      ..removeListener(_searchChanged)
      ..dispose();
    super.dispose();
  }

  bool _openingGame = false;
  Future<void> _openScoped(List<GamesTourModel> games, int index) async {
    if (_openingGame) return;
    _openingGame = true;
    try {
      await openCollectionGame(
        context,
        ref,
        slug: widget.collection.slug,
        previews: games,
        index: index,
      );
    } finally {
      _openingGame = false;
    }
  }

  GamesListViewMode _mode = GamesListViewMode.gamesCard;

  void _toggleView() {
    HapticFeedbackService.buttonPress();
    setState(
      () => _mode = GamesListViewMode
          .values[(_mode.index + 1) % GamesListViewMode.values.length],
    );
  }

  @override
  Widget build(BuildContext context) => EventViewShell(
    title: widget.player?.name ?? collectionOpeningName(widget.opening!),
    tabs: const ['Games'],
    tabStripOverride: const SizedBox.shrink(),
    search: EventViewSearch(
      controller: _search.mode,
      label: 'Search games',
      hintText: 'Search collection games',
      textFieldKey: const ValueKey('collection_games_search'),
      filterKey: const ValueKey('collection_games_filters'),
      badgeCount: _search.filterBadgeCount(widget.opening),
      debounce: const Duration(milliseconds: 200),
      onQuery: _search.typed,
      onChanged: _search.edited,
      onClose: _search.closed,
      onFilters: () => _search.openFilters(context, opening: widget.opening),
    ),
    // The list's layout, as every Games header toggles it.
    actions: [_CollectionViewToggle(onTap: _toggleView)],
    pageBuilder: (_, _) => _GamesPage(
      slug: widget.collection.slug,
      searchState: _search,
      contents: const CollectionContents(sections: [], games: []),
      player: widget.player,
      opening: widget.opening,
      groupByDate: true,
      showSelector: false,
      onClearPlayer: () {},
      viewMode: _mode,
      onOpen: (games, index) => _openScoped(games, index),
    ),
  );
}

/// The list's layout toggle in a collection's header: every Games list's
/// own board-view button ([BoardViewToggleButton]), a button node of its own
/// so a screen reader does not fold it into the title.
class _CollectionViewToggle extends StatelessWidget {
  const _CollectionViewToggle({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) =>
      Semantics(container: true, child: BoardViewToggleButton(onTap: onTap));
}

/// A book's players searched in place: the Players list itself, narrowed to
/// the names that match what is typed and, with filters on, to the players
/// of the games those filters keep. Each keeps the rank it has in the full
/// list. While the filtered games load, the last list stays on screen under
/// a quiet progress line.
class _SearchedPlayers extends ConsumerStatefulWidget {
  const _SearchedPlayers({
    required this.slug,
    required this.players,
    required this.query,
    required this.opening,
    required this.onPick,
    this.onClear,
  });

  final String slug;
  final List<CollectionPlayer> players;
  final CollectionSearchQuery query;
  final CollectionOpening? opening;
  final ValueChanged<CollectionPlayer> onPick;

  /// Clears what leaves no player: the words, else the filters.
  final VoidCallback? onClear;

  @override
  ConsumerState<_SearchedPlayers> createState() => _SearchedPlayersState();
}

class _SearchedPlayersState extends ConsumerState<_SearchedPlayers> {
  final EventViewSearchPlace _place = EventViewSearchPlace();

  /// The scoped games last drawn from, kept while the next scope loads.
  List<CollectionGame>? _lastScope;

  @override
  void didUpdateWidget(_SearchedPlayers oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.query != widget.query) {
      _place.queryChanged(context, widget.query.text);
    }
  }

  @override
  Widget build(BuildContext context) {
    final query = widget.query;
    final opening = widget.opening;
    final full = widget.players;
    if (!query.isActive) {
      _lastScope = null;
      _place.settle(context);
      return EventViewSearchList(
        busy: false,
        child: _PlayersPage(
          players: full,
          numbered: true,
          onPick: widget.onPick,
        ),
      );
    }
    // The filters, the opening the page opened on included, without the
    // words: the players must play in the games they keep.
    final scopeQuery = CollectionSearchQuery(
      text: '',
      eco: query.eco.isEmpty ? (opening?.eco ?? '') : query.eco,
      result: query.result,
      year: query.year,
      minYear: query.minYear,
      maxYear: query.maxYear,
      annotated: query.annotated,
      sort: query.sort,
    );
    final scopeKey = (
      slug: widget.slug,
      query: scopeQuery,
      player: null as String?,
    );
    final scope = scopeQuery.isActive
        ? ref.watch(collectionFilteredContentsProvider(scopeKey))
        : null;
    if (scope != null && scope.hasError && !scope.isLoading) {
      return _Notice(
        text: _collectionErrorText(
          scope.error,
          fallback: "Couldn't load the players.",
        ),
        actionLabel: 'Try again',
        onAction: () =>
            ref.invalidate(collectionFilteredContentsProvider(scopeKey)),
      );
    }
    final busy = scope != null && scope.isLoading;
    final fresh = scope?.valueOrNull?.games;
    if (fresh != null && !busy) _lastScope = fresh;
    final games = scope == null ? null : (busy ? _lastScope : fresh);
    final words = query.text.trim().toLowerCase();
    final shown = <CollectionPlayer>[];
    final ranks = <int>[];
    for (var i = 0; i < full.length; i++) {
      final player = full[i];
      final named =
          words.isEmpty ||
          '${player.title ?? ''} ${player.name} ${player.fed ?? ''}'
              .toLowerCase()
              .contains(words);
      final plays =
          games == null ||
          games.any(
            (game) =>
                game.card.involves(player.key) ||
                player.aliasKeys.any(game.card.involves),
          );
      if (named && plays) {
        shown.add(player);
        ranks.add(i + 1);
      }
    }
    if (!busy) _place.settle(context);
    return EventViewSearchList(
      busy: busy,
      child: _PlayersPage(
        players: shown,
        ranks: ranks,
        numbered: true,
        noMatches: _SearchNoHits(
          key: const ValueKey('collection_players_no_matches'),
          query: query.text,
          subject: 'players',
          filtered: query.text.trim().isEmpty,
          onClear: widget.onClear,
        ),
        onPick: widget.onPick,
      ),
    );
  }
}

/// A collection page's search: the words typed in its header's field (held
/// by [mode], which the shell's search mode runs) and the filters, as one
/// query the lists under it read.
class _CollectionGamesSearchState extends ChangeNotifier {
  final SearchModeController mode = SearchModeController();
  CollectionSearchQuery query = const CollectionSearchQuery();

  void setQuery(CollectionSearchQuery value) {
    if (value == query) return;
    query = value;
    notifyListeners();
  }

  /// The words once typing settles; '' as the field empties.
  void typed(String text) => setQuery(query.withText(text));

  /// Every keystroke: an emptied field empties the query at once, words
  /// the filter sheet took before the typing pause ended included.
  void edited(String text) {
    if (text.trim().isEmpty) typed('');
  }

  /// The search closed: the words go, the filters stay (counted on their
  /// glyph).
  void closed() => typed('');

  /// Words narrow the list, so its no-hits line offers to clear them
  /// rather than the filters.
  bool get hasWords => query.text.trim().isNotEmpty;

  /// The no-hits line's way back: the words when there are any (the field
  /// empties, and the list hears it as typed), else the filters.
  void clearNarrowing() {
    if (hasWords) {
      mode.text.clear();
      // A field emptied while the search is closed reaches no listener.
      typed('');
      return;
    }
    setQuery(const CollectionSearchQuery());
  }

  /// The filters on, counting an opening the page was opened on as one.
  int filterBadgeCount(CollectionOpening? opening) =>
      query.filterCount + (query.eco.isEmpty && opening != null ? 1 : 0);

  /// The filter sheet over what is searched now: the words typed so far
  /// (not once the typing pause ends) and the [opening] the page opened
  /// on, which [onClearOpening] lets go of once another is picked.
  Future<void> openFilters(
    BuildContext context, {
    CollectionOpening? opening,
    VoidCallback? onClearOpening,
  }) async {
    mode.focusNode.unfocus();
    typed(mode.query);
    final incomingEco = opening?.eco ?? '';
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
      setQuery(result);
    }
  }

  @override
  void dispose() {
    mode.dispose();
    super.dispose();
  }
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
    required this.searchState,
  });
  final String slug;
  final bool groupByDate;
  final bool flatList;

  /// The page's search, typed in the screen's search header.
  final _CollectionGamesSearchState searchState;
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
  /// Sections the reader folded.
  final Set<String> _collapsed = {};

  /// Sections folded while words are searched: every one opens as a search
  /// starts, so its hits are in view, and the reader's own folds come back
  /// once the words are gone.
  final Set<String> _searchCollapsed = {};
  String _selected = 'all';
  _CollectionGamesSearchState get _searchState => widget.searchState;
  CollectionSearchQuery get _query => _searchState.query;
  bool get _searchingWords => _query.text.trim().isNotEmpty;
  Set<String> get _folds => _searchingWords ? _searchCollapsed : _collapsed;

  /// The last list drawn, kept on screen while the next query loads.
  CollectionContents? _shown;
  final EventViewSearchPlace _place = EventViewSearchPlace();

  @override
  void initState() {
    super.initState();
    _searchState.addListener(_queryChanged);
  }

  void _queryChanged() {
    if (!_searchingWords) _searchCollapsed.clear();
    _place.queryChanged(context, _query.text);
    setState(() {});
  }

  @override
  void didUpdateWidget(_GamesPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.searchState, widget.searchState)) return;
    oldWidget.searchState.removeListener(_queryChanged);
    widget.searchState.addListener(_queryChanged);
  }

  @override
  void dispose() {
    _searchState.removeListener(_queryChanged);
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
    // The search is typed in the screen's search header; the list is all
    // this page draws.
    if (filtered == null) return _show(widget.contents);
    final data = filtered.valueOrNull;
    if (!filtered.isLoading) {
      if (filtered.hasError) {
        return EventViewSearchList(
          busy: false,
          child: _Notice(
            text: _collectionErrorText(
              filtered.error,
              fallback: "Couldn't load the games.",
            ),
            actionLabel: 'Try again',
            onAction: () =>
                ref.invalidate(collectionFilteredContentsProvider(key)),
          ),
        );
      }
      if (data != null) return _show(data);
    }
    // The next query is on its way: the last list stays where it is, the
    // line along its top says so. Only a first load has nothing to keep.
    final last = _shown;
    if (last == null) return const _CardsSkeleton();
    return EventViewSearchList(busy: true, child: _body(last));
  }

  /// [contents], the answer to the query asked: drawn, kept for the next
  /// query to load over, and the list put in its place for it.
  Widget _show(CollectionContents contents) {
    _shown = contents;
    _place.settle(context);
    return EventViewSearchList(busy: false, child: _body(contents));
  }

  /// The space after the last row, clear of the home indicator. The list's
  /// last child keeps it clear of the floating search button
  /// ([EventViewSearchButtonGap]).
  double _listEnd(BuildContext context) =>
      24.sp + MediaQuery.viewPaddingOf(context).bottom;

  Widget _body(CollectionContents contents) {
    final opening = widget.opening;
    if (contents.games.isEmpty && _query.isActive) {
      return _SearchNoHits(
        key: const ValueKey('collection_games_no_matches'),
        query: _query.text,
        filtered: !_searchState.hasWords,
        onClear: _searchState.clearNarrowing,
      );
    }
    if (contents.games.isEmpty) {
      return _Notice(
        text: opening == null
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

  /// One sequence for both the list and board previous/next: the latest game
  /// first, or the server's order once the reader picks a sort.
  Widget _flatBody(CollectionContents contents) {
    // Hits keep the list's own order, so a search reads as the same list
    // narrowed: newest first, or the server's once the reader picks a sort.
    final games = _query.sort == 'default'
        ? collectionGamesNewestFirst(contents.games)
        : contents.games;
    final ordered = [for (final game in games) game.game];
    final perRow = widget.viewMode == GamesListViewMode.chessBoardGrid ? 2 : 1;
    final opening = widget.opening;
    final showOpeningLine = opening != null && widget.onClearOpening != null;
    final lead = showOpeningLine ? 1 : 0;
    final count = lead + (ordered.length / perRow).ceil();
    return ListView.builder(
      key: const PageStorageKey('collection_games'),
      padding: EdgeInsets.only(top: 12.sp, bottom: _listEnd(context)),
      itemCount: count + 1,
      itemBuilder: (context, index) {
        if (index == count) return const EventViewSearchButtonGap();
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
            menuActionsFor: (_, local) =>
                _collectionGameActions(() => widget.onOpen(ordered, local)),
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
      if (_folds.contains(section?.id)) {
        if (section?.kind == CollectionSectionKind.part) {
          hiddenParents.add(section!.id);
        }
        continue;
      }
      for (var start = 0; start < group.games.length; start += perRow) {
        rows.add((group: index, start: start));
      }
    }
    final count = lead + (selectedGroups.isEmpty ? 1 : rows.length);
    return ListView.builder(
      key: const PageStorageKey('collection_games'),
      padding: EdgeInsets.only(top: 12.sp, bottom: _listEnd(context)),
      itemCount: count + 1,
      itemBuilder: (context, i) {
        if (i == count) return const EventViewSearchButtonGap();
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
                  _folds.remove(id);
                  final parent = groups
                      .where((g) => g.section?.id == id)
                      .firstOrNull
                      ?.section
                      ?.parentId;
                  if (parent != null) _folds.remove(parent);
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
          if (_query.isActive) {
            return SearchNoMatches(
              key: const ValueKey('collection_games_no_matches'),
              query: _query.text,
              filtered: !_searchState.hasWords,
              onClear: _searchState.clearNarrowing,
            );
          }
          return Padding(
            padding: EdgeInsets.all(24.sp),
            child: const Text('No games in this chapter or round.'),
          );
        }
        final row = rows[i - lead];
        final group = selectedGroups[row.group];
        final start = row.start;
        if (start == null) {
          final section = group.section;
          final expanded = !_folds.contains(section?.id);
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
                    if (!_folds.add(section?.id ?? 'unsorted')) {
                      _folds.remove(section?.id ?? 'unsorted');
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
            menuActionsFor: (_, local) => _collectionGameActions(
              () => widget.onOpen(ordered, group.offset + local),
            ),
          ),
        );
      },
    );
  }
}

List<LibraryMenuAction> _collectionGameActions(VoidCallback open) => [
  LibraryMenuAction(
    icon: Icons.open_in_new_rounded,
    label: 'Open game',
    onSelected: open,
  ),
];

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
    this.ranks,
    this.noMatches,
  });

  final bool numbered;

  final List<CollectionPlayer> players;

  /// Each player's rank when [numbered], for a list narrowed from the full
  /// one (a search): their place in that. Null counts from one.
  final List<int>? ranks;

  /// Shown instead of the empty list's notice when a search left no player.
  final Widget? noMatches;
  final ValueChanged<CollectionPlayer> onPick;

  @override
  Widget build(BuildContext context) {
    if (players.isEmpty) {
      return noMatches ??
          const _Notice(text: 'No players in this collection yet.');
    }
    return ListView.separated(
      padding: EdgeInsets.fromLTRB(
        16.sp,
        12.sp,
        16.sp,
        24.sp + MediaQuery.viewPaddingOf(context).bottom,
      ),
      // Last, the room the floating search button needs while it floats
      // over this tab.
      itemCount: players.length + 1,
      separatorBuilder: (_, i) => i < players.length - 1
          ? SizedBox(height: 8.sp)
          : const SizedBox.shrink(),
      itemBuilder: (context, i) => i == players.length
          ? const EventViewSearchButtonGap()
          : _CollectionPlayerRow(
              key: ValueKey<String>('collection_player_${players[i].key}'),
              player: players[i],
              rank: numbered ? (ranks?[i] ?? i + 1) : null,
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
              0,
              0,
              0,
              0,
              color.r * 255,
              0,
              0,
              0,
              0,
              color.g * 255,
              0,
              0,
              0,
              0,
              color.b * 255,
              0.4252,
              1.4304,
              0.1444,
              0,
              -25.5,
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

/// A search (or its filters) that leaves a tab's list empty: the one
/// no-hits line every searched list shows ([SearchNoMatches]), on the
/// list's gutter where its first row would be. It stays a scrollable list,
/// so the pull and the header's scroll-away keep working over it.
class _SearchNoHits extends StatelessWidget {
  const _SearchNoHits({
    super.key,
    required this.query,
    this.subject = 'games',
    this.filtered = false,
    this.onClear,
  });

  final String query;
  final String subject;
  final bool filtered;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) => ListView(
    physics: const AlwaysScrollableScrollPhysics(),
    padding: EdgeInsets.zero,
    children: [
      SearchNoMatches(
        query: query,
        subject: subject,
        filtered: filtered,
        onClear: onClear,
      ),
    ],
  );
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
