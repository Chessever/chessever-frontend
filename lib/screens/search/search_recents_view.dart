import 'dart:async';
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/screens/collections/collections_screen.dart'
    show CollectionBookPlate, CollectionScreen;
import 'package:chessever2/screens/favorites/tabs/favorites_players_tab.dart'
    show playerPhotoProvider;
import 'package:chessever2/screens/feed/news/news_cover.dart';
import 'package:chessever2/screens/feed/news/news_reader_pager.dart';
import 'package:chessever2/screens/for_you/discovery/widgets/discovery_common.dart'
    show DiscoverySectionHeader;
import 'package:chessever2/screens/group_event/model/tour_event_card_model.dart';
import 'package:chessever2/screens/group_event/smart_event/smart_aggregate_event_provider.dart'
    show SmartEventRequest;
import 'package:chessever2/screens/my_space/widgets/space_avatar.dart';
import 'package:chessever2/screens/my_space/widgets/space_player_strip.dart'
    show spaceSurname;
import 'package:chessever2/screens/search/search_landing.dart';
import 'package:chessever2/screens/search/search_page_sections.dart';
import 'package:chessever2/screens/search/search_recents_store.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/app_button.dart' show TappableScale;
import 'package:chessever2/widgets/app_snack.dart';
import 'package:chessever2/widgets/dismiss_keyboard.dart';
import 'package:chessever2/widgets/event_card/event_card.dart'
    show EventFallbackArtwork;
import 'package:chessever2/widgets/event_card/event_image_provider.dart';
import 'package:chessever2/widgets/event_card/smart_event_card.dart'
    show SmartEventPlate;
import 'package:chessever2/widgets/event_card/smart_event_request_card.dart'
    show smartPlateLineFor;
import 'package:chessever2/widgets/search/recent_searches_provider.dart'
    show resolveRecentSearchPlayer;
import 'package:country_flags/country_flags.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// The Search tab's recent searches, while the field has the cursor and
/// nothing is typed yet, as X shows them: a "Recent" heading with a clear
/// all, a row of the things last opened from Search (a face for a player, a
/// plate for everything else, each with its short name), then the queries
/// last committed, each with a way to put it back in the field.
///
/// The view belongs to the field: a tap on it never drops the keyboard
/// before the tap lands (it is in the field's tap region and excluded from
/// the app's tap-outside dismissal), and dragging it keeps the keyboard. A
/// thing opened, or a query run, drops it.
class SearchRecentsView extends ConsumerWidget {
  const SearchRecentsView({
    super.key,
    required this.recents,
    required this.picks,
    required this.focusNode,
    required this.onRunQuery,
    required this.onFillQuery,
  });

  final SearchRecents recents;

  /// Opens a thing as its card does (the tab remembers it again, in front).
  final SearchPicks picks;
  final FocusNode focusNode;

  /// Searches the query (a row's tap).
  final ValueChanged<String> onRunQuery;

  /// Puts the query back in the field to go on typing (the row's arrow).
  final ValueChanged<String> onFillQuery;

  Future<void> _clearAll(BuildContext context, WidgetRef ref) async {
    unawaited(HapticFeedbackService.selection());
    final messenger = ScaffoldMessenger.maybeOf(context);
    final store = ref.read(searchRecentsProvider.notifier);
    final before = await store.clear();
    if (messenger == null || before.isEmpty) return;
    showAppSnackOn(
      messenger,
      'Recent searches cleared',
      actionLabel: 'Undo',
      onAction: () => unawaited(store.restore(before)),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gutter = searchPageGutter;
    final liveKey = ref.watch(searchLiveIdsKeyProvider);
    final liveIds = liveKey.isEmpty ? const <String>[] : liveKey.split('\n');
    final queries = recents.queries;
    return TextFieldTapRegion(
      child: KeyboardDismissExclusion(
        focusNode: focusNode,
        child: CustomScrollView(
          key: const ValueKey('search_recents'),
          // The landing under it keeps the tab's scroll controller.
          primary: false,
          slivers: [
            SliverToBoxAdapter(
              child: DiscoverySectionHeader(
                title: 'Recent',
                gutter: gutter,
                trailing: _ClearAllButton(
                  onTap: () => unawaited(_clearAll(context, ref)),
                ),
              ),
            ),
            if (recents.picks.isNotEmpty)
              SliverPadding(
                padding: EdgeInsets.only(
                  top: searchHeadingGap,
                  bottom: queries.isEmpty ? 0 : 12.h,
                ),
                sliver: SliverToBoxAdapter(
                  child: SingleChildScrollView(
                    key: const ValueKey('search_recent_picks'),
                    scrollDirection: Axis.horizontal,
                    padding: EdgeInsets.symmetric(horizontal: gutter),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final (index, pick) in recents.picks.indexed) ...[
                          if (index > 0) SizedBox(width: SearchRecentTile.gap),
                          SearchRecentTile(
                            key: ValueKey(
                              'search-recent-pick-${pick.identity}',
                            ),
                            pick: pick,
                            onTap: () => unawaited(
                              openSearchRecentPick(
                                context,
                                pick,
                                picks,
                                liveIds: liveIds,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            SliverList.builder(
              itemCount: queries.length,
              itemBuilder: (context, index) => SearchRecentQueryRow(
                key: ValueKey('search-recent-query-$index'),
                query: queries[index],
                onRun: () => onRunQuery(queries[index]),
                onFill: () => onFillQuery(queries[index]),
              ),
            ),
            // Clear of the floating dock the page scrolls under.
            SliverToBoxAdapter(
              child: SizedBox(
                height: 24.h + MediaQuery.paddingOf(context).bottom,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Opens [pick] exactly as its card on the page opens it, through [picks]
/// (which remember it again, in front). A collection and a story open their
/// own pages here, as their cards do, after [picks] hears of them.
Future<void> openSearchRecentPick(
  BuildContext context,
  SearchRecentPick pick,
  SearchPicks picks, {
  List<String> liveIds = const [],
}) async {
  switch (pick.kind) {
    case SearchRecentKind.player:
      final entry = pick.entry;
      if (entry == null) return;
      final player = await resolveRecentSearchPlayer(entry);
      if (player != null) picks.player?.call(player);
    case SearchRecentKind.event:
      final event = pick.event;
      if (event != null) picks.event(searchRecentEvent(event, liveIds));
    case SearchRecentKind.opening:
      final opening = pick.opening;
      if (opening != null) picks.opening?.call(opening);
    case SearchRecentKind.smartEvent:
      final request = pick.smartEvent;
      if (request != null) picks.smartEvent?.call(request);
    case SearchRecentKind.collection:
      final collection = pick.collection;
      if (collection == null) return;
      picks.collection?.call(collection);
      if (!context.mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => CollectionScreen(collection: collection),
        ),
      );
    case SearchRecentKind.news:
      final news = pick.news;
      if (news == null) return;
      picks.news?.call(news);
      if (!context.mounted) return;
      await NewsReaderPager.open(
        context,
        articles: [news],
        initialIndex: 0,
        heroScope: _recentNewsHeroes,
      );
  }
}

/// A recent story's cover flies to the reader from its own scope.
final Object _recentNewsHeroes = Object();

/// The heading's clear all: the bare cross in quiet ink, its glyph on the
/// gutter, a 44pt target reaching in from it.
class _ClearAllButton extends StatelessWidget {
  const _ClearAllButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final target = math.max(44.0, 44.w);
    return Semantics(
      container: true,
      button: true,
      label: 'Clear all recent searches',
      onTap: onTap,
      excludeSemantics: true,
      child: GestureDetector(
        key: const ValueKey('search-recent-clear-all'),
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          width: target,
          height: target,
          child: Align(
            alignment: AlignmentDirectional.centerEnd,
            child: Icon(
              Icons.close_rounded,
              size: 20.ic,
              color: context.colors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

/// One thing opened from Search, compact: the player's face
/// ([SpacePlayerAvatar], photo, flag and title as My Space draws them), or
/// the plate its card leads with (an event's picture, a smart event's or an
/// opening's board, a book's cover, a story's picture), its short name
/// under it. Every tile is as wide, its picture as tall, so the names start
/// on one line.
class SearchRecentTile extends StatelessWidget {
  const SearchRecentTile({super.key, required this.pick, required this.onTap});

  final SearchRecentPick pick;
  final VoidCallback onTap;

  /// One tile's width.
  static double get width => 76.w;

  /// Between two tiles.
  static double get gap => 8.w;

  /// The picture's height: a face's diameter, a plate's height.
  static double get visual => 56.w;

  /// A plate's width: the 5:4 of every card plate.
  static double get plateWidth => visual * 5 / 4;

  /// What the tile is called under its picture: a player's surname, an
  /// event's name before its section ("Norway Chess 2027 | Open" reads
  /// "Norway Chess 2027"), an opening's own line, a smart event's level.
  static String shortName(SearchRecentPick pick) {
    final name = pick.name.trim();
    switch (pick.kind) {
      case SearchRecentKind.player:
        final surname = spaceSurname(name);
        return surname.isEmpty ? name : surname;
      case SearchRecentKind.event:
        return name.split('|').first.trim();
      case SearchRecentKind.opening:
        return name.split(':').last.trim();
      case SearchRecentKind.smartEvent:
        return pick.smartEvent?.tierLabel ?? name;
      case SearchRecentKind.collection:
      case SearchRecentKind.news:
        return name;
    }
  }

  @override
  Widget build(BuildContext context) {
    final label = shortName(pick);
    return Semantics(
      container: true,
      button: true,
      label: pick.name,
      onTap: onTap,
      excludeSemantics: true,
      child: TappableScale(
        onTap: () {
          // A story's reader gives the card-tap haptic itself.
          if (pick.kind != SearchRecentKind.news) {
            unawaited(HapticFeedbackService.cardTap());
          }
          onTap();
        },
        child: SizedBox(
          width: width,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: visual,
                child: Center(child: _RecentVisual(pick: pick)),
              ),
              SizedBox(height: 6.h),
              Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: AppTypography.textXsMedium.copyWith(
                  color: context.colors.textPrimary,
                  height: 1.25,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A tile's picture, from the building blocks its card draws.
class _RecentVisual extends ConsumerWidget {
  const _RecentVisual({required this.pick});

  final SearchRecentPick pick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final size = SearchRecentTile.visual;
    switch (pick.kind) {
      case SearchRecentKind.player:
        final player = pick.player;
        if (player == null) return const SizedBox.shrink();
        return _PlayerFace(player: player, size: size);
      case SearchRecentKind.event:
        final event = pick.event;
        if (event == null) return const SizedBox.shrink();
        return _Plate(child: _EventPicture(event: event));
      case SearchRecentKind.opening:
        final opening = pick.opening;
        if (opening == null) return const SizedBox.shrink();
        return _smartPlate(SmartEventRequest.forOpeningSelection(opening));
      case SearchRecentKind.smartEvent:
        final request = pick.smartEvent;
        if (request == null) return const SizedBox.shrink();
        return _smartPlate(request);
      case SearchRecentKind.collection:
        final cover = pick.collection?.coverUrl;
        return _Plate(
          child: cover == null
              ? const CollectionBookPlate()
              : CachedNetworkImage(
                  imageUrl: cover,
                  fit: BoxFit.cover,
                  placeholder: (_, _) => const CollectionBookPlate(),
                  errorWidget: (_, _, _) => const CollectionBookPlate(),
                ),
        );
      case SearchRecentKind.news:
        return _Plate(
          child: NewsCover(imageUrl: pick.news?.imageUrl, fadeBottom: 0),
        );
    }
  }

  /// A smart event's plate (an opening's board, a level's piece, a time
  /// control's deck), as its card draws it.
  Widget _smartPlate(SmartEventRequest request) => SmartEventPlate(
    width: SearchRecentTile.plateWidth,
    height: SearchRecentTile.visual,
    minElo: request.minElo,
    formatsAndStates: request.formatsAndStates,
    opening: smartPlateLineFor(request),
  );
}

/// A player's face as My Space draws one, with their FIDE photo when there
/// is one.
class _PlayerFace extends ConsumerWidget {
  const _PlayerFace({required this.player, required this.size});

  final SearchPlayer player;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fideId = player.fideId;
    final photo = fideId == null || fideId <= 0
        ? null
        : ref.watch(playerPhotoProvider(fideId)).valueOrNull;
    return SpacePlayerAvatar(
      size: size,
      name: player.name,
      photoUrl: photo,
      title: player.title,
      federation: player.fed,
      ring: context.colors.background,
    );
  }
}

/// The plate a picture sits in: a card plate's corners, and on paper the
/// event card's hairline so a pale picture keeps its edge.
class _Plate extends StatelessWidget {
  const _Plate({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: SearchRecentTile.plateWidth,
      height: SearchRecentTile.visual,
      child: DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6.br),
          border: context.isLightTheme
              ? Border.all(color: Colors.black.withValues(alpha: 0.1))
              : null,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(6.br),
          child: ColoredBox(
            color: context.colors.surfaceRecessed,
            child: child,
          ),
        ),
      ),
    );
  }
}

/// An event's picture as its card shows it: the event's photo, else its
/// country's flag, else its initials on the neutral plate.
class _EventPicture extends ConsumerWidget {
  const _EventPicture({required this.event});

  final GroupEventCardModel event;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fallback = EventFallbackArtwork(title: event.title);
    if (event.eventSource == EventSource.communityEvent) return fallback;
    final image = ref.watch(eventImageProvider(event.id)).valueOrNull;
    if (image == null) return fallback;
    final url = image.imageUrl;
    if (url != null && url.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: url,
        fit: BoxFit.cover,
        memCacheWidth:
            (SearchRecentTile.plateWidth *
                    MediaQuery.devicePixelRatioOf(context))
                .round(),
        placeholder: (_, _) => const SizedBox.expand(),
        errorWidget: (_, _, _) => fallback,
      );
    }
    final country = image.fallbackCountryCode;
    if (country != null && country.isNotEmpty) {
      return CountryFlag.fromCountryCode(
        country,
        theme: const ImageTheme(
          height: double.infinity,
          width: double.infinity,
        ),
      );
    }
    return fallback;
  }
}

/// One committed query: a tap searches it again; the arrow at its end puts
/// it back in the field to go on typing (the keyboard stays up). A 48pt
/// row on the page's gutter, the arrow's glyph on the far gutter.
class SearchRecentQueryRow extends StatelessWidget {
  const SearchRecentQueryRow({
    super.key,
    required this.query,
    required this.onRun,
    required this.onFill,
  });

  final String query;
  final VoidCallback onRun;
  final VoidCallback onFill;

  @override
  Widget build(BuildContext context) {
    final gutter = searchPageGutter;
    final target = math.max(44.0, 44.w);
    return Row(
      children: [
        Expanded(
          child: Semantics(
            container: true,
            button: true,
            label: query,
            hint: 'Search',
            onTap: onRun,
            excludeSemantics: true,
            child: InkWell(
              onTap: onRun,
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: math.max(48.0, 48.h)),
                child: Padding(
                  padding: EdgeInsetsDirectional.only(start: gutter, end: 8.w),
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(
                      query,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.textMdRegular.copyWith(
                        color: context.colors.textPrimary,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        Semantics(
          container: true,
          button: true,
          label: 'Put $query in the search field',
          onTap: onFill,
          excludeSemantics: true,
          child: GestureDetector(
            key: ValueKey('search-recent-fill-$query'),
            behavior: HitTestBehavior.opaque,
            onTap: onFill,
            child: SizedBox(
              width: target,
              height: target,
              child: Align(
                alignment: AlignmentDirectional.centerEnd,
                // Up and toward the start: back up into the field.
                child: Icon(
                  Directionality.of(context) == TextDirection.rtl
                      ? Icons.north_east_rounded
                      : Icons.north_west_rounded,
                  size: 20.ic,
                  color: context.colors.textSecondary,
                ),
              ),
            ),
          ),
        ),
        SizedBox(width: gutter),
      ],
    );
  }
}
