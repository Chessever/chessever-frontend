import 'dart:async';

import 'package:chessever2/widgets/star_notifications.dart';
import 'package:chessever2/providers/favorite_players_provider.dart';
import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/screens/collections/collections_data.dart'
    show Collection;
import 'package:chessever2/screens/feed/news/news_models.dart' show FeedNews;
import 'package:chessever2/screens/for_you/discovery/widgets/discovery_common.dart'
    show DiscoverySectionHeader;
import 'package:chessever2/screens/group_event/model/tour_event_card_model.dart';
import 'package:chessever2/screens/group_event/smart_event/smart_aggregate_event_provider.dart'
    show SmartEventRequest;
import 'package:chessever2/screens/library/widgets/library_context_menu.dart';
import 'package:chessever2/screens/player_profile/utils/player_menu_actions.dart';
import 'package:chessever2/screens/player_profile/widgets/lifted_row_menu.dart';
import 'package:chessever2/screens/standings/player_standing_model.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/favorite_constants.dart';
import 'package:chessever2/utils/favorite_limit_guard.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/user_error_message.dart';
import 'package:chessever2/widgets/app_snack.dart';
import 'package:chessever2/widgets/auth/auth_upgrade_sheet.dart';
import 'package:chessever2/widgets/event_card/event_card.dart';
import 'package:chessever2/widgets/event_card/smart_event_card.dart'
    show SmartCardLead;
import 'package:chessever2/widgets/event_card/smart_event_request_card.dart';
import 'package:chessever2/widgets/figma_player_card.dart';
import 'package:chessever2/widgets/home_top_bar.dart';
import 'package:chessever2/widgets/paywall/premium_paywall_sheet.dart';
import 'package:chessever2/widgets/search/opening_search_suggestion.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

// The Search tab's page is built only from cards the app already draws
// elsewhere: event cards as the Events list draws them, the Events page's
// player cards, the Rankings row, My Space's smart event cards. These are
// the few pieces that lay them out as one page: one gutter (the field's),
// one heading (the hub pages'), one gap between cards, one between
// sections.

/// The page's side gutter: the field's own, so the field, every heading and
/// every card start and end on the same two lines.
double get searchPageGutter => HomeTopBarMetrics.horizontalPadding;

/// Between two cards of a section, down a column or across a grid: the
/// Events list's own gap.
double get searchCardGap =>
    ResponsiveHelper.adaptive(phone: 12.sp, tablet: 16.sp);

/// Under a heading, before its first card.
double get searchHeadingGap => 4.sp;

/// After a section's last card, before the next heading.
double get searchSectionGap => 20.sp;

/// What a pick from the page does: each remembers the pick as a recent
/// search, then opens it, as a result of the same search does.
///
/// [event], [player], [opening] and [smartEvent] open what they are given.
/// A collection and a story open themselves (their cards push their own
/// pages); [collection] and [news] only hear that they were opened.
@immutable
class SearchPicks {
  const SearchPicks({
    required this.event,
    this.player,
    this.opening,
    this.smartEvent,
    this.collection,
    this.news,
  });

  final ValueChanged<GroupEventCardModel> event;
  final ValueChanged<SearchPlayer>? player;
  final ValueChanged<OpeningSearchSelection>? opening;
  final ValueChanged<SmartEventRequest>? smartEvent;
  final ValueChanged<Collection>? collection;
  final ValueChanged<FeedNews>? news;
}

/// One section of the page: the hub pages' heading on the gutter
/// ([DiscoverySectionHeader]: one 17pt line, the count in quiet ink after
/// it, at most one action on the far side), then [body] inside the gutter.
/// No kicker and no glyph: the heading's words are the whole label.
class SearchSection extends StatelessWidget {
  const SearchSection({
    super.key,
    required this.title,
    required this.body,
    this.count,
    this.trailing,
    this.onTitleTap,
  });

  final String title;
  final int? count;
  final Widget? trailing;
  final VoidCallback? onTitleTap;

  /// A sliver.
  final Widget body;

  @override
  Widget build(BuildContext context) {
    final gutter = searchPageGutter;
    return SliverMainAxisGroup(
      slivers: [
        SliverToBoxAdapter(
          child: DiscoverySectionHeader(
            title: title,
            count: count,
            trailing: trailing,
            onTitleTap: onTitleTap,
            gutter: gutter,
          ),
        ),
        SliverPadding(
          padding: EdgeInsets.fromLTRB(
            gutter,
            searchHeadingGap,
            gutter,
            searchSectionGap,
          ),
          sliver: body,
        ),
      ],
    );
  }
}

/// Event cards as the Events list draws them: a column of compact cards on
/// a phone, the image grid on a tablet ([EventCard.gridMainAxisExtent]).
/// [pending] slots after them hold the room of cards still on their way
/// ([SearchPendingEventCard]), so the sections below never move down when
/// they land.
class SearchEventCards extends StatelessWidget {
  const SearchEventCards({
    super.key,
    required this.events,
    required this.onOpen,
    required this.keyPrefix,
    this.pending = 0,
  });

  final List<GroupEventCardModel> events;
  final ValueChanged<GroupEventCardModel> onOpen;

  /// Keys each card `<keyPrefix>-<event id>`.
  final String keyPrefix;
  final int pending;

  Widget _card(GroupEventCardModel event, {required bool grid}) =>
      searchEventCard(event, keyPrefix: keyPrefix, grid: grid, onOpen: onOpen);

  @override
  Widget build(BuildContext context) {
    final total = events.length + pending;
    if (!ResponsiveHelper.isTablet) {
      return SliverList.builder(
        itemCount: total,
        itemBuilder: (context, index) {
          final last = index == total - 1;
          final Widget child = index < events.length
              ? _card(events[index], grid: false)
              : SearchPendingEventCard(
                  key: index == events.length
                      ? ValueKey('$keyPrefix-pending')
                      : null,
                  spinner: index == events.length,
                );
          return Padding(
            padding: EdgeInsets.only(bottom: last ? 0 : searchCardGap),
            child: child,
          );
        },
      );
    }
    return SliverLayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.crossAxisExtent;
        final gap = searchCardGap;
        final columns = ResponsiveHelper.columnsForWidth(width, spacing: gap);
        final cardWidth = (width - gap * (columns - 1)) / columns;
        return SliverGrid(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: gap,
            mainAxisSpacing: gap,
            mainAxisExtent: EventCard.gridMainAxisExtent(context, cardWidth),
          ),
          delegate: SliverChildBuilderDelegate(
            (context, index) => index < events.length
                ? _card(events[index], grid: true)
                : ExcludeSemantics(
                    key: index == events.length
                        ? ValueKey('$keyPrefix-pending')
                        : null,
                    child: index == events.length
                        ? const Center(child: _QuietSpinner())
                        : const SizedBox.shrink(),
                  ),
            childCount: total,
          ),
        );
      },
    );
  }
}

/// [event] as the Events list draws it, keyed `<keyPrefix>-<event id>`: the
/// compact card, or the image card of a tablet grid ([grid]); its tap opens
/// it through [onOpen], its long-press is the event card's own menu.
Widget searchEventCard(
  GroupEventCardModel event, {
  required String keyPrefix,
  required bool grid,
  required ValueChanged<GroupEventCardModel> onOpen,
}) {
  return Semantics(
    key: ValueKey('$keyPrefix-${event.id}'),
    container: true,
    child: EventCard(
      tourEventCardModel: event,
      forceCompactLayout: !grid,
      // A suffix keeps the card off Heroine: the same event can be listed
      // twice on this page (a recent search, and the same event coming up
      // on the landing under it).
      heroTagSuffix: 'search-${event.id}',
      favoritePlayersSource: EventFavoritePlayersSource.cacheOnly,
      onTap: () => onOpen(event),
    ),
  );
}

/// The room of one compact event card still being looked up: a real card's
/// build, never painted, so it is exactly a card tall at any text size (a
/// two-line title, the tallest a card gets). The first carries one small
/// spinner. A community-sourced placeholder, so it asks the network for no
/// photo, and LIVE, so it holds the LIVE line a live card has.
class SearchPendingEventCard extends StatelessWidget {
  const SearchPendingEventCard({super.key, this.spinner = false});

  final bool spinner;

  static const _model = GroupEventCardModel(
    id: 'search-pending',
    title: '\u00A0\n\u00A0',
    dates: '',
    maxAvgElo: 0,
    timeUntilStart: '',
    tourEventCategory: TourEventCategory.live,
    timeControl: '',
    endDate: null,
    startDate: null,
    eventSource: EventSource.communityEvent,
  );

  @override
  Widget build(BuildContext context) {
    const slot = IgnorePointer(
      child: Visibility(
        visible: false,
        maintainSize: true,
        maintainAnimation: true,
        maintainState: true,
        child: EventCard(
          tourEventCardModel: _model,
          forceCompactLayout: true,
          heroTagSuffix: 'search-pending',
          favoritePlayersSource: EventFavoritePlayersSource.cacheOnly,
        ),
      ),
    );
    return ExcludeSemantics(
      child: spinner
          ? const Stack(
              alignment: Alignment.center,
              children: [slot, _QuietSpinner()],
            )
          : slot,
    );
  }
}

class _QuietSpinner extends StatelessWidget {
  const _QuietSpinner();

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 18.ic,
      child: CircularProgressIndicator(
        strokeWidth: 2,
        color: context.colors.textSecondary,
      ),
    );
  }
}

/// How many half cards a row of smart events holds across [width]: two on a
/// phone, as My Space sets them; more on a tablet, none under 200 wide.
int searchSmartEventColumns(double width) {
  if (!ResponsiveHelper.isTablet) return 2;
  return ResponsiveHelper.columnsForWidth(
    width,
    minItemWidth: 200,
    spacing: searchCardGap,
    maxColumns: 4,
    minColumns: 2,
  );
}

/// One smart event card of a grid: [requests]`[index]` in its slot's key,
/// opening through [onTap] when that gives one. Every grid here is on the
/// Search tab, so the smart event it opens shows no Filters. A half card
/// lays its plate across its width: every half card of a row here is a
/// smart event, so the rows still line up. [lead] sets a row card on the
/// grid it leads ([SearchSmartEventGrid.leadFullWidth]).
Widget _smartEventCard(
  List<SmartEventRequest> requests,
  int index, {
  required bool stacked,
  SmartCardLead? lead,
  VoidCallback? Function(int index)? onTap,
  Key? Function(int index)? keyFor,
}) => KeyedSubtree(
  key: keyFor?.call(index),
  child: SmartEventRequestCard(
    request: requests[index],
    stacked: stacked,
    fillPlate: stacked,
    lead: lead,
    onTap: onTap?.call(index),
    showFilters: false,
  ),
);

/// The row of half cards starting at [start], [columns] wide; a short last
/// row keeps its empty slots, so its cards stand where the rows above do.
/// Each card opens through [onTap] (its own open when that gives none) and
/// keeps its own long-press.
Widget searchSmartEventRow(
  List<SmartEventRequest> requests,
  int start,
  int columns, {
  VoidCallback? Function(int index)? onTap,
  Key? Function(int index)? keyFor,
}) {
  final gap = searchCardGap;
  return Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (var c = 0; c < columns; c++) ...[
        if (c > 0) SizedBox(width: gap),
        Expanded(
          child: start + c < requests.length
              ? _smartEventCard(
                  requests,
                  start + c,
                  stacked: true,
                  onTap: onTap,
                  keyFor: keyFor,
                )
              : const SizedBox.shrink(),
        ),
      ],
    ],
  );
}

/// Smart events as My Space sets them: one alone is the full-width card;
/// two or more are half cards, the plate over the words, side by side (more
/// to a row on a tablet). Every half card reserves two title lines, so the
/// rows line up whatever the names. With [leadFullWidth], an odd count on
/// a phone leads with the full-width card (Super GM over GM and IM), so no
/// row is left half empty. The lead sits on the grid under it: its plate
/// the half cards' own over the first column, its words and star where the
/// second column's stand, so the card that leads never draws the smallest
/// board of the section.
class SearchSmartEventGrid extends StatelessWidget {
  const SearchSmartEventGrid({
    super.key,
    required this.requests,
    this.onTap,
    this.keyFor,
    this.leadFullWidth = false,
  });

  final List<SmartEventRequest> requests;

  /// The first card takes a row of its own when the rest pair up. Off for
  /// openings, whose room is held for an even grid before they land.
  final bool leadFullWidth;

  /// Replaces the card's own open, per card.
  final VoidCallback? Function(int index)? onTap;

  /// Keys each card's slot.
  final Key? Function(int index)? keyFor;

  @override
  Widget build(BuildContext context) {
    if (requests.isEmpty) return const SizedBox.shrink();
    if (requests.length == 1) {
      return _smartEventCard(
        requests,
        0,
        stacked: false,
        onTap: onTap,
        keyFor: keyFor,
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = searchSmartEventColumns(constraints.maxWidth);
        final lead = leadFullWidth && columns == 2 && requests.length.isOdd
            ? 1
            : 0;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (lead == 1)
              _smartEventCard(
                requests,
                0,
                stacked: false,
                lead: SmartCardLead(
                  column: (constraints.maxWidth - searchCardGap) / 2,
                  gap: searchCardGap,
                ),
                onTap: onTap,
                keyFor: keyFor,
              ),
            for (
              var start = lead;
              start < requests.length;
              start += columns
            ) ...[
              if (start > 0) SizedBox(height: searchCardGap),
              searchSmartEventRow(
                requests,
                start,
                columns,
                onTap: onTap,
                keyFor: keyFor,
              ),
            ],
          ],
        );
      },
    );
  }
}

/// [SearchSmartEventGrid] as a sliver, [columns] to a row, built a row at a
/// time as it scrolls in: for a list that can run long (every opening one
/// search matched).
class SearchSmartEventRows extends StatelessWidget {
  const SearchSmartEventRows({
    super.key,
    required this.requests,
    required this.columns,
    this.onTap,
    this.keyFor,
  });

  final List<SmartEventRequest> requests;
  final int columns;

  /// Replaces the card's own open, per card.
  final VoidCallback? Function(int index)? onTap;

  /// Keys each card's slot.
  final Key? Function(int index)? keyFor;

  @override
  Widget build(BuildContext context) {
    if (requests.isEmpty) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }
    if (requests.length == 1) {
      return SliverToBoxAdapter(
        child: _smartEventCard(
          requests,
          0,
          stacked: false,
          onTap: onTap,
          keyFor: keyFor,
        ),
      );
    }
    final rows = (requests.length + columns - 1) ~/ columns;
    return SliverList.builder(
      itemCount: rows,
      itemBuilder: (context, row) => Padding(
        padding: EdgeInsets.only(top: row == 0 ? 0 : searchCardGap),
        child: searchSmartEventRow(
          requests,
          row * columns,
          columns,
          onTap: onTap,
          keyFor: keyFor,
        ),
      ),
    );
  }
}

/// [player] as the player rows (Rankings, Favorites) model one.
PlayerStandingModel searchPlayerStanding(SearchPlayer player) {
  final rating = player.rating;
  return PlayerStandingModel(
    name: player.name,
    countryCode: player.fed ?? '',
    title: player.title,
    score: rating ?? 0,
    hasRating: rating != null && rating > 0,
    scoreChange: 0,
    matchScore: null,
    fideId: player.fideId,
    gamebasePlayerId: player.gamebasePlayerId,
    memorialSourceIdentity: player.memorialSourceIdentity,
    memorialRouteId: player.memorialRouteId,
  );
}

/// A player as Rankings lists one: the canonical row ([FigmaPlayerCard]),
/// its heart and its long-press (the shared player menu plus the favorite
/// row), lifted on the page's own surface. No rank: a search result holds
/// none. A tap gives no haptic, as a Rankings row's does not.
class SearchPlayerRow extends ConsumerWidget {
  const SearchPlayerRow({
    super.key,
    required this.player,
    required this.onOpen,
  });

  final SearchPlayer player;
  final ValueChanged<SearchPlayer> onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final model = searchPlayerStanding(player);
    final isFavorite =
        ref
            .watch(favoritePlayersProviderNew)
            .valueOrNull
            ?.any(
              (favorite) => favoritePlayerMatchesIdentity(
                favorite,
                fideId: player.fideId?.toString(),
                playerName: player.name,
                memorialSourceIdentity: player.memorialSourceIdentity,
              ),
            ) ??
        false;
    void open() => onOpen(player);
    void toggle() => unawaited(
      toggleSearchPlayerFavorite(context, ref, model, isFavorite: isFavorite),
    );
    return LiftedRowMenu(
      onPreviewTap: open,
      actions: (rowContext) => playerStandingMenuActions(
        rowContext,
        ref,
        model,
        onOpen: open,
        extra: [
          LibraryMenuAction(
            icon: isFavorite
                ? Icons.favorite_rounded
                : Icons.favorite_border_rounded,
            label: isFavorite ? 'Remove from favorites' : 'Add to favorites',
            onSelected: toggle,
          ),
        ],
      ),
      child: FigmaPlayerCard(
        player: model,
        rank: null,
        showRank: false,
        reserveRankSpace: false,
        isFavorite: isFavorite,
        showFavoriteButton: true,
        onTap: open,
        onToggleFavorite: toggle,
      ),
    );
  }
}

/// Follows or unfollows [player], as Rankings' heart does: a full account
/// first, the free limit before an add (the paywall past it). A write that
/// fails says so, once, in the app's snack.
Future<void> toggleSearchPlayerFavorite(
  BuildContext context,
  WidgetRef ref,
  PlayerStandingModel player, {
  required bool isFavorite,
}) async {
  final allowed = await requireFullAuthGuard(context);
  if (!allowed || !context.mounted) return;
  if (!isFavorite) {
    final canAdd = await canAddMoreFavorites(context, ref);
    if (!canAdd || !context.mounted) return;
  }
  HapticFeedbackService.medium();
  final favorites = ref.read(favoritePlayersProviderNew.notifier);
  try {
    if (isFavorite) {
      await favorites.removeFavorite(
        player.name,
        fideId: player.fideId?.toString(),
        memorialSourceIdentity: player.memorialSourceIdentity,
      );
    } else {
      await favorites.addFavorite(
        starFlow: playerStarNotificationFlow(context),
        fideId: player.fideId?.toString(),
        playerName: player.name,
        countryCode: player.countryCode,
        rating: player.score,
        title: player.title,
        gamebasePlayerId: player.gamebasePlayerId,
        memorialSourceIdentity: player.memorialSourceIdentity,
        memorialRouteId: player.memorialRouteId,
      );
    }
  } on FavoriteLimitExceededException {
    if (context.mounted) {
      await showPremiumPaywallSheet(
        context: context,
        allowRewarded: false,
        trigger: PaywallTrigger.favorites,
      );
    }
  } catch (error) {
    debugPrint('[Search] favorite toggle failed: $error');
    if (context.mounted) {
      showAppSnack(
        context,
        userFacingError(error, fallback: "Couldn't update your favorites."),
        tone: AppSnackTone.danger,
      );
    }
  }
}
