import 'dart:async';

import 'package:chessever2/widgets/star_notifications.dart';
import 'package:chessever2/e2e/e2e_ids.dart';
import 'package:chessever2/main.dart' show routeObserver;
import 'package:chessever2/providers/game_list_live_first_provider.dart';
import 'package:chessever2/providers/favorite_players_provider.dart';
import 'package:chessever2/providers/live_game_ids_provider.dart';
import 'package:chessever2/repository/favorites/models/favorite_player.dart';
import 'package:chessever2/screens/favorites/favorite_players_provider.dart';
import 'package:chessever2/screens/favorites/provider/favorites_mode_provider.dart';
import 'package:chessever2/screens/favorites/widgets/collection_inks.dart';
import 'package:chessever2/screens/favorites/widgets/favorite_player_search_suggestion.dart';
import 'package:chessever2/screens/favorites/widgets/games_list_refetch_line.dart';
import 'package:chessever2/screens/favorites/widgets/settling_scroll_controller.dart';
import 'package:chessever2/screens/player_profile/player_profile_screen.dart';
import 'package:chessever2/screens/standings/player_standing_model.dart';
import 'package:chessever2/screens/favorites/player_games/provider/favorites_combined_games_provider.dart';
import 'package:chessever2/screens/library/widgets/add_to_folder_sheet.dart';
import 'package:chessever2/screens/library/widgets/live_gamebase_search_game_card.dart';
import 'package:chessever2/screens/chessboard/provider/chess_board_screen_provider_new.dart';
import 'package:chessever2/screens/chessboard/provider/game_pgn_stream_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_list_view_mode_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/game_card_wrapper/board_game_card_wrapper_widget.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/game_card_wrapper/game_card_wrapper_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/game_card_wrapper/grid_game_card_wrapper_widget.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/scroll_cache.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/foreground_task_scheduler.dart';
import 'package:chessever2/utils/favorite_constants.dart';
import 'package:chessever2/utils/user_error_message.dart';
import 'package:chessever2/utils/favorite_limit_guard.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/text_scale.dart';
import 'package:chessever2/widgets/federation_flag.dart';
import 'package:chessever2/widgets/game_filter/game_filter.dart';
import 'package:chessever2/widgets/app_snack.dart';
import 'package:chessever2/widgets/auth/auth_upgrade_sheet.dart';
import 'package:chessever2/widgets/paywall/premium_paywall_sheet.dart';
import 'package:chessever2/widgets/paywall/premium_game_access.dart';
import 'package:chessever2/widgets/ink_fab.dart';
import 'package:chessever2/widgets/live_first_capsule.dart';
import 'package:chessever2/widgets/quick_list_toggles.dart';
import 'package:chessever2/widgets/search_mode/search_mode.dart';
import 'package:chessever2/widgets/search_no_matches.dart';
import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:chessever2/widgets/scroll_to_top_bus.dart';
import 'package:intl/intl.dart';

/// Track animated game IDs for Favorites to prevent re-animation
final Set<String> _favoritesAnimatedGameIds = {};

/// Day key for games with no usable date; sorts after every real day.
const String _unknownFavoriteDayKey = '0000-00-00';

/// [games] bucketed into days (`yyyy-MM-dd`), newest day first, games with no
/// date last. Inside a day the given order is kept. With [liveFirst]
/// (Trello #1420) the games in play ([liveIds], the server's set; by their
/// own rows while it is unknown) lead the list, gathered at the head of
/// today ([gatherLiveGamesFirst]). [now] pins today and "live" for tests.
@visibleForTesting
Map<String, List<GamesTourModel>> groupFavoriteGamesByDay(
  List<GamesTourModel> games, {
  bool liveFirst = false,
  Set<String>? liveIds,
  DateTime? now,
}) {
  final grouped = <String, List<GamesTourModel>>{};
  for (final game in games) {
    // Bucket by the stable scheduled day when available: last_move_time can be
    // clobbered by sync refreshes and misreport old games as "today".
    final date = game.bucketDate;
    final dateKey = date != null
        ? DateFormat('yyyy-MM-dd').format(date)
        : _unknownFavoriteDayKey;
    grouped.putIfAbsent(dateKey, () => []).add(game);
  }

  final sortedKeys = grouped.keys.toList()..sort((a, b) => b.compareTo(a));
  final byDay = {for (final key in sortedKeys) key: grouped[key]!};
  if (!liveFirst) return byDay;
  return gatherLiveGamesFirst(
    byDay,
    todayKey: DateFormat('yyyy-MM-dd').format(now ?? DateTime.now()),
    unknownKey: _unknownFavoriteDayKey,
    liveIds: liveIds,
    now: now,
  );
}

/// Who the Favorites Games list's live games are asked about: the followed
/// players it lists (the chips' selection, when there is one) under its
/// filter. Null with no player to ask about.
final favoritesGamesLiveScopeProvider =
    Provider.autoDispose<FavoritesLiveGamesScope?>((ref) {
      final players =
          ref.watch(
            favoritePlayersNotifierProvider.select(
              (state) => state.valueOrNull?.players,
            ),
          ) ??
          const <PlayerStandingModel>[];
      final selected = ref.watch(
        favoritesCombinedGamesProvider.select((state) => state.selectedFideIds),
      );
      final filter = ref.watch(
        favoritesCombinedGamesProvider.select((state) => state.filter),
      );
      final fideIds = [
        for (final player in players)
          if (player.fideId case final id?)
            if (selected.isEmpty || selected.contains('$id')) '$id',
      ];
      if (fideIds.isEmpty) return null;
      return FavoritesLiveGamesScope(fideIds: fideIds, filter: filter);
    });

/// The games in play among the Favorites list's players, by the server
/// ([favoritesLiveGameIdsProvider]): null until it answers. Nobody to ask
/// about has nothing in play.
final favoritesGamesServerLiveIdsProvider = Provider.autoDispose<Set<String>?>((
  ref,
) {
  final scope = ref.watch(favoritesGamesLiveScopeProvider);
  if (scope == null) return const <String>{};
  return ref.watch(favoritesLiveGameIdsProvider(scope));
});

/// What the Favorites Games list counts as in play and what its Live first
/// lifts: the server's set, less any game the list already shows as
/// finished ([listedLiveGameIds]). Null while the server has not answered.
final favoritesGamesLiveIdsProvider = Provider.autoDispose<Set<String>?>(
  (ref) => listedLiveGameIds(
    ref.watch(favoritesGamesServerLiveIdsProvider),
    ref.watch(favoritesCombinedGamesProvider.select((state) => state.games)),
  ),
);

/// How many games of the Favorites Games list are in play, read on Live
/// first's capsule ("See 3 live"). Null while unknown ("See live").
final favoritesGamesLiveCountProvider = Provider.autoDispose<int?>(
  (ref) => ref.watch(favoritesGamesLiveIdsProvider)?.length,
);

/// Whether a game of the Favorites Games list is in play. Live first floats
/// over the list only while this holds (Trello #1420): with nothing live it
/// has nothing to do. Until the server answers, the list's own rows decide,
/// so a backend that cannot say keeps the capsule (with no number).
final favoritesGamesAnyLiveProvider = Provider.autoDispose<bool>((ref) {
  final live = ref.watch(favoritesGamesLiveIdsProvider);
  if (live != null) return live.isNotEmpty;
  return ref.watch(
    favoritesCombinedGamesProvider.select(
      (state) => state.filteredGames.any(GameFilterHelper.isInPlay),
    ),
  );
});

/// The Favorites Games list's live-game poll, when it is running: for the
/// page to pause it while covered and ask again on its way back.
LiveGameIdsNotifier? _favoritesLiveIdsPoll(WidgetRef ref) {
  // Only a poll already running: nothing is started from here.
  if (!ref.exists(favoritesGamesLiveScopeProvider)) return null;
  final scope = ref.read(favoritesGamesLiveScopeProvider);
  if (scope == null) return null;
  final provider = favoritesLiveGameIdsProvider(scope);
  return ref.exists(provider) ? ref.read(provider.notifier) : null;
}

/// The Games list's toolbar: board view, Classical only and Filters, bare
/// glyphs, ending the title row. The full-page search header ends with the same
/// row less the board view ([withBoardView] false): Classical and Filters
/// stay at the same spot in both, and the board view gives way to the field
/// along with the title, leaving the field room to type in on any phone.
///
/// It watches the same auto-dispose games provider as the Games tab, so the
/// filter dialog's route cannot drop the notifier it applies to.
class FavoritesGamesToolbar extends ConsumerWidget {
  const FavoritesGamesToolbar({super.key, this.withBoardView = true});

  /// Leads with the board view (the page's header); the search header's
  /// row leaves it out.
  final bool withBoardView;

  /// What the search matches, cycled once after "Search" in its field.
  static const List<String> searchHints = ['player', 'opening', 'ECO code'];

  /// The full row's width: two 44pt targets (the board view and Filters;
  /// Classical only lives in the filter popup since 2026-11-20).
  static const double width = 2 * SearchModeFilterButton.target;

  /// The search header's row: Filters, held still through the morph where
  /// the page's header has it ([SearchModeShared]).
  static const Widget inSearch = SearchModeShared(
    id: FavoritesGamesToolbar,
    child: FavoritesGamesToolbar(withBoardView: false),
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(
      favoritesCombinedGamesProvider.select((state) => state.filter),
    );
    // The page's header stays mounted (paused) under an open search: only
    // the row in reach carries the Filters' test id, so it is found once.
    final searching = SearchModeScope.maybeOf(context)?.isSearching ?? false;
    final inReach = withBoardView != searching;

    final shared = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SearchModeFilterButton(
          key: inReach ? e2eKey(E2eIds.favoritesGamesFilterButton) : null,
          count: filter.activeFilterCount,
          onTap: () => _showFilterDialog(context, ref),
        ),
      ],
    );
    if (!withBoardView) return shared;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        BoardViewToggleButton(
          onTap: () => ref.read(gamesListViewModeSwitcher).toggleViewMode(),
        ),
        SearchModeShared(id: FavoritesGamesToolbar, child: shared),
      ],
    );
  }

  Future<void> _showFilterDialog(BuildContext context, WidgetRef ref) async {
    HapticFeedbackService.buttonPress();
    final result = await showGameFilterDialog(
      context: context,
      currentFilter: ref.read(favoritesCombinedGamesProvider).filter,
      showFormatFilter: false,
    );
    if (result != null && context.mounted) {
      await ref
          .read(favoritesCombinedGamesProvider.notifier)
          .applyFilter(result);
    }
  }
}

/// The Games page's floating buttons (Trello #1420): the search and, above
/// it while a game is in play (or while it is on), Live first, saying how
/// many are live by the server's count. Pressed with nothing in play, Live
/// first stays off and says so; turned on, it lists the live games the
/// loaded days miss and the list goes up to them.
///
/// Under the screen's [SearchModeHost] the search hands its tap to the host,
/// which flies the search button's glass into the field and back.
class FavoritesGamesFabs extends ConsumerWidget {
  const FavoritesGamesFabs({super.key});

  static const _surface = GameListLiveFirstSurface.favorites;

  /// How far up from the bottom the buttons reach: the search with Live
  /// first above it ([InkFabStack.reach]). The Games list ends this far
  /// clear, so no button covers its last game. Live first counts whether it
  /// floats or not, so the end of the list never jumps as games start and
  /// finish. Favorites is a pushed page, with no bottom bar under it. Read
  /// it from the list's context: inside the button slot the Scaffold has
  /// already taken the inset away.
  static double reach(BuildContext context) =>
      InkFabStack.reach(context, regularAbove: 1);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final liveFirst = ref.watch(gameListLiveFirstProvider(_surface));
    final anyLive = ref.watch(favoritesGamesAnyLiveProvider);
    // Just after a search closes the list may still hold its hits: what is
    // live among them says nothing of the whole list.
    final holdsHits = ref.watch(
      favoritesCombinedGamesProvider.select((state) => state.isSearching),
    );
    // Only while a game is in play (Trello #1420), or while it is on, so a
    // Live first left on can always be seen and turned off. With nothing
    // live and nothing to undo it is not on screen.
    final offered = (anyLive || liveFirst) && !holdsHits;
    return InkFabStack(
      children: [
        if (offered)
          LiveFirstCapsule(
            key: const ValueKey('favorites_live_first_fab'),
            on: liveFirst,
            liveCount: ref.watch(favoritesGamesLiveCountProvider),
            onTap: () {
              final liveIds = ref.read(favoritesGamesLiveIdsProvider);
              final press = pressGameListLiveFirst(
                context: context,
                ref: ref,
                surface: _surface,
                games: ref.read(favoritesCombinedGamesProvider).filteredGames,
                liveIds: liveIds,
              );
              // What it lifts is what it counted: the live games the loaded
              // days do not hold yet join today.
              if (press == GameListLiveFirstPress.turnedOn && liveIds != null) {
                unawaited(
                  ref
                      .read(favoritesCombinedGamesProvider.notifier)
                      .ensureListed(liveIds),
                );
              }
            },
          ),
        SearchInkFab(
          key: e2eKey(E2eIds.favoritesSearchFab),
          label: 'Search games',
        ),
      ],
    );
  }
}

class FavoritesGamesTab extends ConsumerStatefulWidget {
  const FavoritesGamesTab({super.key});

  @override
  ConsumerState<FavoritesGamesTab> createState() => _FavoritesGamesTabState();
}

class _FavoritesGamesTabState extends ConsumerState<FavoritesGamesTab>
    with
        WidgetsBindingObserver,
        RouteAware,
        AutomaticKeepAliveClientMixin,
        ScrollToTopListenerMixin {
  /// Lands a search's place changes in the frame the games change in.
  final SettlingScrollController _scrollController = SettlingScrollController();

  @override
  void onScrollToTopRequested() {
    animateScrollControllerToTop(_scrollController);
  }

  Timer? _scrollIdleTimer;
  bool _routeSubscribed = false;
  bool _routeIsCurrent = true;

  /// The live count's poll, paused while a board covers the list.
  final CoveredLiveGamesPoll _livePoll = CoveredLiveGamesPoll();
  bool _appIsResumed = true;
  bool _liveCardsPausedForScroll = false;
  late final StateController<Set<String>> _liveGameCardsPauseReasons;
  static const Duration _scrollIdleDelay = Duration(milliseconds: 180);

  String get _liveCardsPauseReason => 'favorites_games_scroll_$hashCode';
  // Keep rendering while backgrounded so the OS app-switcher snapshot is not
  // blank. Route coverage removes the expensive card tree while the provider
  // watches stay alive long enough for modal results to update this tab.
  bool get _isActiveOnScreen => _routeIsCurrent;

  /// Days folded on the plain list.
  final Set<String> _collapsedDates = {};

  /// Days folded among a search's hits. Every day opens as hits land, so
  /// none hides behind a fold; the plain list's folds come back with it.
  final Set<String> _searchCollapsedDates = {};

  /// The page's search is open over this list.
  bool _searchOpen = false;

  /// The list on screen is a search's hits.
  bool _showingHits = false;

  /// Where the plain list was when the search opened (or where the reader
  /// took it since, when the hits land): it comes back there as the search
  /// closes, whatever the hits or the header did to the scroll meanwhile.
  double? _offsetBeforeSearch;

  /// Ends [SettlingScrollController.holdAt] once the header has sprung.
  Timer? _holdTimer;

  /// A filter or player change is on its way: its list starts at the top.
  bool _toTopOnLanding = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _liveGameCardsPauseReasons = ref.read(
      liveGameCardsPauseReasonsProvider.notifier,
    );
    WidgetsBinding.instance.addObserver(this);
    _scrollController.addListener(_onScroll);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _followSearch(SearchModeScope.maybeOf(context)?.isSearching ?? false);
    if (_routeSubscribed) return;
    final route = ModalRoute.of(context);
    if (route == null) return;
    routeObserver.subscribe(this, route);
    _routeSubscribed = true;
    _routeIsCurrent = route.isCurrent;
  }

  @override
  void dispose() {
    if (_routeSubscribed) {
      routeObserver.unsubscribe(this);
    }
    WidgetsBinding.instance.removeObserver(this);
    ForegroundTaskScheduler.cancel('favorites_games_resume_$hashCode');
    _scrollController.removeListener(_onScroll);
    _scrollIdleTimer?.cancel();
    _holdTimer?.cancel();
    _setLiveCardsPausedForScroll(false);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didPush() {
    _setRouteActive(true);
  }

  @override
  void didPopNext() {
    // Back from a board: games may have started or ended meanwhile.
    _setRouteActive(true, backFromBoard: true);
  }

  @override
  void didPushNext() {
    _setRouteActive(false);
  }

  @override
  void didPop() {
    _setRouteActive(false);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state != AppLifecycleState.resumed) {
      ForegroundTaskScheduler.cancel('favorites_games_resume_$hashCode');
      _setAppResumed(false);
      return;
    }
    if (!mounted) return;

    _setAppResumed(true);
    ForegroundTaskScheduler.schedule(
      key: 'favorites_games_resume_$hashCode',
      task: () {
        if (!mounted) return;
        final route = ModalRoute.of(context);
        if (route?.isCurrent != true) return;
        if (ref.read(selectedFavoritesModeProvider) !=
            FavoritesScreenMode.games) {
          return;
        }

        ref.invalidate(gameUpdatesStreamProvider);
        ref.invalidate(liveGameUpdateStreamProvider);
        ref.invalidate(gameUpdatesBatchStreamProvider);
        unawaited(
          ref.read(favoritesCombinedGamesProvider.notifier).refreshGames(),
        );
      },
    );
  }

  void _setRouteActive(bool isActive, {bool backFromBoard = false}) {
    if (!mounted) return;
    if (_routeIsCurrent != isActive) {
      setState(() => _routeIsCurrent = isActive);
    }
    // Covered by a board, the live count waits instead of polling; back
    // from it, the server is asked once.
    final poll = _favoritesLiveIdsPoll(ref);
    if (isActive) {
      _livePoll.uncover(ref, poll, ask: backFromBoard);
    } else {
      _livePoll.cover(ref, poll);
    }
    if (!isActive) {
      ForegroundTaskScheduler.cancel('favorites_games_resume_$hashCode');
      _stopLiveCardsForHiddenTab();
    }
  }

  /// With Live first on, the live games the loaded days miss join the list
  /// (see [FavoritesCombinedGamesNotifier.ensureListed]), so it lifts what
  /// its capsule counts.
  void _listLiveGames() {
    if (!mounted) return;
    if (!ref.read(
      gameListLiveFirstProvider(GameListLiveFirstSurface.favorites),
    )) {
      return;
    }
    final liveIds = ref.read(favoritesGamesLiveIdsProvider);
    if (liveIds == null || liveIds.isEmpty) return;
    unawaited(
      ref.read(favoritesCombinedGamesProvider.notifier).ensureListed(liveIds),
    );
  }

  void _setAppResumed(bool isResumed) {
    if (!mounted) return;
    if (_appIsResumed != isResumed) {
      setState(() => _appIsResumed = isResumed);
    }
    if (!isResumed) {
      _stopLiveCardsForHiddenTab();
    }
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    _markLiveCardsScrolling();
    _loadMoreNearEnd(_scrollController.position);
  }

  /// The next days, once the reader is within 200pt of the last card (which
  /// sits above the floating buttons' clearance at the list's end). Asked
  /// on every scroll and whenever the list's size changes under a still
  /// reader ([ScrollMetricsNotification]): a page landing short, a day
  /// folding, the header folding away and growing the viewport.
  void _loadMoreNearEnd(ScrollMetrics metrics) {
    if (!mounted || !metrics.hasContentDimensions) return;
    final threshold = 200.0 + FavoritesGamesFabs.reach(context);
    if (metrics.maxScrollExtent - metrics.pixels > threshold) return;
    final state = ref.read(favoritesCombinedGamesProvider);
    if (state.hasMore && !state.isLoading && state.games.isNotEmpty) {
      _loadMoreDays();
    }
  }

  bool _onScrollMetrics(ScrollMetricsNotification notification) {
    if (notification.depth == 0 && notification.metrics.axis == Axis.vertical) {
      _loadMoreNearEnd(notification.metrics);
    }
    return false;
  }

  void _markLiveCardsScrolling() {
    _setLiveCardsPausedForScroll(true);
    _scrollIdleTimer?.cancel();
    _scrollIdleTimer = Timer(_scrollIdleDelay, _markLiveCardsIdle);
  }

  void _markLiveCardsIdle() {
    _setLiveCardsPausedForScroll(false);
  }

  void _stopLiveCardsForHiddenTab() {
    _scrollIdleTimer?.cancel();
    _setLiveCardsPausedForScroll(false);
  }

  void _setLiveCardsPausedForScroll(bool paused) {
    if (_liveCardsPausedForScroll == paused) return;
    _liveCardsPausedForScroll = paused;
    setLiveGameCardsPausedWithNotifier(
      _liveGameCardsPauseReasons,
      reason: _liveCardsPauseReason,
      paused: paused,
    );
  }

  void _loadMoreDays() {
    HapticFeedback.mediumImpact();
    final state = ref.read(favoritesCombinedGamesProvider);
    if (state.isSearching) {
      ref.read(favoritesCombinedGamesProvider.notifier).loadMoreSearchResults();
    } else {
      ref.read(favoritesCombinedGamesProvider.notifier).loadMoreGames();
    }
  }

  String _formatDateHeader(String dateKey) {
    // Handle unknown date case
    if (dateKey == _unknownFavoriteDayKey) {
      return 'Unknown date';
    }

    final date = DateTime.parse(dateKey);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final gameDate = DateTime(date.year, date.month, date.day);

    if (gameDate == today) {
      return 'Today';
    } else if (gameDate == yesterday) {
      return 'Yesterday';
    } else {
      return DateFormat('EEEE, MMM d').format(date);
    }
  }

  void _toggleDateSection(String dateKey) {
    HapticFeedback.lightImpact();
    final folds = ref.read(favoritesCombinedGamesProvider).isSearching
        ? _searchCollapsedDates
        : _collapsedDates;
    setState(() {
      if (!folds.remove(dateKey)) folds.add(dateKey);
    });
    // After collapsing sections, check if we need to load more content
    // This handles the case where collapsing reduces content height
    // and the user is suddenly at/near the end of the list
    _checkScrollAfterLayoutChange();
  }

  /// Keeps the reader's place as the list is replaced under them: a
  /// search's hits start at the top, the plain list comes back where it was
  /// left, a new filter's list starts at the top. Nothing moves while a
  /// fetch is still on its way; the list it replaces stays put.
  void _onGamesChanged(
    FavoritesCombinedGamesState? previous,
    FavoritesCombinedGamesState next,
  ) {
    if (previous == null) return;
    if (previous.searchQuery != next.searchQuery) {
      _toTopOnLanding = false;
      _showingHits = next.isSearching;
      if (next.isSearching) {
        if (!previous.isSearching) {
          // Kept as the search opened, unless the reader has moved the
          // plain list since: then where they left it.
          _offsetBeforeSearch ??= _scrollController.hasClients
              ? _scrollController.offset
              : null;
        }
        _searchCollapsedDates.clear();
        _settleListAt(0);
      } else {
        // The plain list as it was left comes back to its place; one
        // fetched again starts at its top.
        final back = previous.isReplacing ? null : _offsetBeforeSearch;
        // While the search stays open (its field emptied), its close puts
        // the list there again: the header's height changes under it.
        if (!_searchOpen) _offsetBeforeSearch = null;
        _settleListAt(back ?? 0);
      }
      return;
    }
    if (previous.filter != next.filter ||
        !setEquals(previous.selectedFideIds, next.selectedFideIds)) {
      _toTopOnLanding = true;
      // Another list: the place kept for the old one means nothing to it.
      if (!_showingHits) _offsetBeforeSearch = null;
    }
    if (_toTopOnLanding && previous.isLoading && !next.isLoading) {
      _toTopOnLanding = false;
      _settleListAt(0);
    }
    // A list that lands while Live first is on (a refresh, a filter, the
    // plain list back after a search) gets the live games it misses.
    if (previous.isLoading && !next.isLoading && !next.isSearching) {
      _listLiveGames();
    }
  }

  /// Moves the list to [offset] in the layout that puts its new rows on
  /// screen, before that frame paints: no frame shows them at the old place.
  void _settleListAt(double offset) => _scrollController.settleAt(offset);

  /// The page's search opened or closed over this list. The list stays
  /// mounted either way; only its place is kept. Opening keeps where the
  /// reader is; closing on the plain list puts it back there, held while
  /// the header springs back so its end does not bounce. Hits still on
  /// screen as it closes give way to the plain list fetched again, which
  /// starts at its top.
  void _followSearch(bool open) {
    if (open == _searchOpen) return;
    _searchOpen = open;
    if (open) {
      final offset = _scrollController.hasClients
          ? _scrollController.offset
          : null;
      _offsetBeforeSearch = offset;
      if (offset != null) _holdThroughMorph(offset);
      return;
    }
    final back = _offsetBeforeSearch;
    _offsetBeforeSearch = null;
    if (back == null || _showingHits) return;
    _holdThroughMorph(back);
  }

  /// The header's spring, with room to settle: the list holds its place
  /// this long after the search opens or closes.
  static const Duration _morphHold = Duration(milliseconds: 600);

  void _holdThroughMorph(double offset) {
    _scrollController.holdAt(offset);
    _holdTimer?.cancel();
    _holdTimer = Timer(_morphHold, () {
      _holdTimer = null;
      _scrollController.release();
    });
  }

  /// The reader moved the plain list while the search is open (before any
  /// hits): the list stays where they leave it.
  bool _onScrollStart(ScrollStartNotification notification) {
    if (notification.depth == 0 &&
        notification.dragDetails != null &&
        _searchOpen &&
        !_showingHits) {
      _offsetBeforeSearch = null;
    }
    return false;
  }

  /// Check if we need to load more content after a layout change
  /// (e.g., collapsing date sections reduces content height)
  void _checkScrollAfterLayoutChange() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;

      final position = _scrollController.position;
      final maxScroll = position.maxScrollExtent;
      final currentScroll = position.pixels;
      final viewportHeight = position.viewportDimension;

      // If content is shorter than viewport, or we're near the end, load more
      // We use a larger threshold here since collapsing can dramatically reduce height
      final needsMore =
          maxScroll <= 0 || // Content fits in viewport
          maxScroll - currentScroll <=
              viewportHeight; // Within one screen of end

      if (needsMore) {
        final state = ref.read(favoritesCombinedGamesProvider);
        if (state.hasMore && !state.isLoading) {
          _loadMoreDays();
        }
      }
    });
  }

  void _togglePlayerFilter(String fideId) {
    HapticFeedback.lightImpact();
    // Trigger Supabase re-query with the selected player filter
    ref
        .read(favoritesCombinedGamesProvider.notifier)
        .togglePlayerFilter(fideId);
  }

  void _clearAllFilters() {
    HapticFeedback.mediumImpact();
    // Clear filters and re-query all favorites from Supabase
    ref.read(favoritesCombinedGamesProvider.notifier).clearPlayerFilters();
  }

  String? _extractFederation(FavoritePlayer player) {
    final metadata = player.metadata;
    if (metadata.containsKey('federation')) {
      return metadata['federation']?.toString();
    }
    if (metadata.containsKey('fed')) {
      return metadata['fed']?.toString();
    }
    if (metadata.containsKey('country')) {
      return metadata['country']?.toString();
    }
    if (metadata.containsKey('countryCode')) {
      return metadata['countryCode']?.toString();
    }
    return null;
  }

  String _getDisplayName(String fullName) {
    final parts = fullName.split(',');
    if (parts.length > 1) {
      return parts[0].trim();
    }
    final words = fullName.trim().split(' ');
    if (words.length > 1) {
      return words.last;
    }
    return fullName.length > 12 ? '${fullName.substring(0, 10)}...' : fullName;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    ref.listen<FavoritesScreenMode>(selectedFavoritesModeProvider, (_, next) {
      if (next != FavoritesScreenMode.games) {
        _stopLiveCardsForHiddenTab();
      }
    });

    final selectedMode = ref.watch(selectedFavoritesModeProvider);
    if (selectedMode != FavoritesScreenMode.games) {
      return const SizedBox.shrink();
    }

    // A filter dialog is a route, so RouteAware marks this tab as covered while
    // the modal is open. Keep both auto-dispose inputs watched during that
    // interval: otherwise Apply writes to a short-lived replacement notifier
    // and the visible tab rebuilds from the default filter (no results change,
    // no badge). The expensive widget tree can still stay out of the covered
    // route.
    final state = ref.watch(favoritesCombinedGamesProvider);
    final favoritesState = ref.watch(favoritePlayersNotifierProvider);
    ref.listen(favoritesCombinedGamesProvider, _onGamesChanged);
    // Live first brings the games in play to the top of the list; the list
    // goes up to them.
    ref.listen<bool>(
      gameListLiveFirstProvider(GameListLiveFirstSurface.favorites),
      (previous, next) {
        if (next && previous != true) {
          animateScrollControllerToTop(_scrollController);
        }
      },
    );
    final liveFirst = ref.watch(
      gameListLiveFirstProvider(GameListLiveFirstSurface.favorites),
    );
    // Only Live first reorders by the live set, so only then does the list
    // follow it; while on, a game that starts joins the list as the count
    // takes it in.
    final liveIds = liveFirst ? ref.watch(favoritesGamesLiveIdsProvider) : null;
    if (liveFirst) {
      ref.listen<Set<String>?>(
        favoritesGamesLiveIdsProvider,
        (_, _) => _listLiveGames(),
      );
    }
    if (!_isActiveOnScreen) {
      return const SizedBox.shrink();
    }

    final viewMode = ref.watch(gamesListViewModeProvider);
    // Watch the notifier provider for optimistic updates when favorites change
    final playerModels = favoritesState.valueOrNull?.players ?? [];

    // Convert PlayerStandingModel to FavoritePlayer for chip display
    final now = DateTime.now();
    final favorites = playerModels
        .map(
          (p) => FavoritePlayer(
            id: p.fideId?.toString() ?? p.name,
            userId: '', // Not needed for display
            playerName: p.name,
            fideId: p.fideId?.toString(),
            metadata: {
              'countryCode': p.countryCode,
              'federation': p.countryCode,
            },
            createdAt: now,
            updatedAt: now,
          ),
        )
        .toList();

    // Refresh games when favorites list changes
    ref.listen(favoritePlayersNotifierProvider, (prev, next) {
      final prevCount = prev?.valueOrNull?.players.length ?? 0;
      final nextCount = next.valueOrNull?.players.length ?? 0;
      if (prevCount != nextCount) {
        // Favorites changed, refresh games
        Future.microtask(() {
          ref.read(favoritesCombinedGamesProvider.notifier).refreshGames();
        });
      }
    });

    final content = RefreshIndicator(
      onRefresh: () async {
        HapticFeedbackService.medium();
        // The count of games in play comes along with the list.
        unawaited(_favoritesLiveIdsPoll(ref)?.refresh());
        await ref.read(favoritesCombinedGamesProvider.notifier).refreshGames();
      },
      color: context.colors.textPrimary,
      backgroundColor: context.colors.surface,
      child: NotificationListener<ScrollMetricsNotification>(
        onNotification: _onScrollMetrics,
        child: NotificationListener<ScrollStartNotification>(
          onNotification: _onScrollStart,
          child: CustomScrollView(
            key: PageStorageKey<String>(
              'favorites_games_list_${viewMode.index}',
            ),
            controller: _scrollController,
            scrollCacheExtent: kListScrollCacheExtent,
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            slivers: [
              // Favorite-player chips. The search field lives in the screen's
              // full-page search header (Trello #1420), above this same list.
              // Player selection and text search are independent AND filters,
              // so keep the player chips available while a search is active.
              if (favorites.length > 1)
                SliverToBoxAdapter(child: _buildFilterChips(state, favorites)),

              // Content
              SliverLayoutBuilder(
                builder: (context, constraints) => _buildContentSliver(
                  state,
                  favorites,
                  viewMode,
                  constraints.crossAxisExtent,
                  liveFirst: liveFirst,
                  liveIds: liveIds,
                ),
              ),

              // Bottom padding
              SliverToBoxAdapter(child: SizedBox(height: 24.h)),
            ],
          ),
        ),
      ),
    );

    // Cap the width on tablets (contentMaxWidth is unbounded on phones). The
    // wrapper is always present so folding or unfolding an iPhone Duo between
    // phone and tablet widths keeps the same tree, and the list keeps its
    // scroll position instead of remounting at the top.
    //
    // No scroll-to-top button (Trello #1420): tapping the Games tab again
    // already scrolls up, and the floating slot holds the search.
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: ResponsiveHelper.contentMaxWidth),
        child: SizedBox.expand(
          child: Stack(
            children: [
              Positioned.fill(child: content),
              // A search, its close or a filter on its way: the list it
              // replaces stays, with this quiet line over its top.
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: GamesListRefetchLine(
                  active: state.isReplacing && !_showsFirstLoad(state),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Nothing listed yet and nothing to keep on screen: the first load's
  /// spinner. An answer already on screen (no games, or no hits) stays
  /// while a search or a filter replaces it, under the quiet line.
  static bool _showsFirstLoad(FavoritesCombinedGamesState state) =>
      state.isLoading && state.games.isEmpty && !state.isReplacing;

  Widget _buildFilterChips(
    FavoritesCombinedGamesState state,
    List<FavoritePlayer> favorites,
  ) {
    final hasSelection = state.selectedFideIds.isNotEmpty;

    return SizedBox(
      height: 48.h * context.textGrowth,
      child: ShaderMask(
        shaderCallback: (Rect bounds) {
          return LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [
              Colors.transparent,
              Colors.white,
              Colors.white,
              Colors.transparent,
            ],
            stops: const [0.0, 0.03, 0.97, 1.0],
          ).createShader(bounds);
        },
        blendMode: BlendMode.dstIn,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 6.h),
          itemCount: favorites.length + (hasSelection ? 1 : 0),
          itemBuilder: (context, index) {
            if (hasSelection && index == favorites.length) {
              return Padding(
                padding: EdgeInsets.only(right: 8.w),
                child: GestureDetector(
                  onTap: _clearAllFilters,
                  child: Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: 12.w,
                      vertical: 8.h,
                    ),
                    decoration: BoxDecoration(
                      color: context.colors.surfaceRecessed,
                      borderRadius: BorderRadius.circular(16.br),
                      border: Border.all(
                        color: context.colors.divider,
                        width: 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.close_rounded,
                          size: 14.sp,
                          color: context.colors.textSecondary,
                        ),
                        SizedBox(width: 4.w),
                        Text(
                          'Clear',
                          style: TextStyle(
                            fontSize: 13.sp,
                            fontWeight: FontWeight.w500,
                            color: context.colors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }

            final player = favorites[index];
            final fideId = player.fideId ?? '';
            final isSelected = state.selectedFideIds.contains(fideId);
            final federation = _extractFederation(player);
            final displayName = _getDisplayName(player.playerName);

            // Skip players without FIDE ID (can't filter by them)
            if (fideId.isEmpty) {
              return const SizedBox.shrink();
            }

            return Padding(
              padding: EdgeInsets.only(right: 8.w),
              child: GestureDetector(
                onTap: () => _togglePlayerFilter(fideId),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: EdgeInsets.symmetric(
                    horizontal: 10.w,
                    vertical: 8.h,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? const Color(0xFFEF4444)
                        : context.colors.surfaceRecessed,
                    borderRadius: BorderRadius.circular(16.br),
                    border: Border.all(
                      color: isSelected
                          ? const Color(0xFFEF4444)
                          : context.colors.divider,
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FederationFlag(
                        federation: federation,
                        width: 16.w,
                        height: 12.h,
                        borderRadius: BorderRadius.circular(2.br),
                      ),
                      SizedBox(width: 6.w),
                      Text(
                        displayName,
                        style: TextStyle(
                          fontSize: 13.sp,
                          fontWeight: isSelected
                              ? FontWeight.w600
                              : FontWeight.w500,
                          color: context.colors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildContentSliver(
    FavoritesCombinedGamesState state,
    List<FavoritePlayer> favorites,
    GamesListViewMode viewMode,
    double availableWidth, {
    required bool liveFirst,
    Set<String>? liveIds,
  }) {
    if (_showsFirstLoad(state)) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: _buildLoadingState(),
      );
    }

    if (state.error != null && state.games.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: _buildErrorState(state.error!),
      );
    }

    if (state.games.isEmpty) {
      if (state.filter.hasActiveFilters) {
        return _buildNoFilterResultsSliver(state);
      }
      if (state.isSearching) {
        // The Games search matched no game from a followed player. Offer the
        // matching players themselves, so the search still leads somewhere.
        return SliverToBoxAdapter(
          child: FavoritePlayerSearchSuggestion(
            query: state.searchQuery,
            favorites: favorites.map(_asStandingModel).toList(growable: false),
            surface: FavoritePlayerSearchSurface.games,
            onAdd: _addFavoritePlayer,
            onOpenPlayer: _openPlayer,
          ),
        );
      }
      return SliverFillRemaining(
        hasScrollBody: false,
        child: _buildEmptyState(),
      );
    }

    // Use filtered games based on filter settings
    final listedGames = state.filteredGames;

    // Show empty state if filter excludes all games
    if (listedGames.isEmpty && state.filter.hasActiveFilters) {
      return _buildNoFilterResultsSliver(state);
    }

    final gamesByDate = groupFavoriteGamesByDay(
      listedGames,
      liveFirst: liveFirst,
      liveIds: liveIds,
    );
    // With Live first on, the board swipes through the games in the order the
    // list shows them, live ones leading.
    final games = liveFirst
        ? [for (final dayGames in gamesByDate.values) ...dayGames]
        : listedGames;

    // Build cheap row descriptors only. The actual cards are created lazily
    // for visible rows by SliverChildBuilderDelegate.
    final listEntries = <_FavoritesGamesListEntry>[];
    bool isFirstGameCard = true;
    final isGrid = viewMode == GamesListViewMode.chessBoardGrid;
    final isChessBoardVisible = viewMode == GamesListViewMode.chessBoard;

    // Create GamesScreenModel for GameCardWrapperWidget
    final gamesData = GamesScreenModel(
      gamesTourModels: games,
      pinnedGamedIs: const [],
    );

    // Build a mapping of game IDs to their indices for reliable lookup
    final gameIdToIndex = <String, int>{};
    for (int i = 0; i < games.length; i++) {
      gameIdToIndex[games[i].gameId] = i;
    }

    final folds = state.isSearching ? _searchCollapsedDates : _collapsedDates;
    for (final entry in gamesByDate.entries) {
      final dateKey = entry.key;
      final dateGames = entry.value;
      final isCollapsed = folds.contains(dateKey);

      // Date header
      listEntries.add(
        _FavoritesDateHeaderEntry(
          dateKey: dateKey,
          gameCount: dateGames.length,
          isExpanded: !isCollapsed,
        ),
      );

      // Games under this date (only if expanded)
      if (!isCollapsed) {
        if (isGrid) {
          // Grid mode: dynamic columns based on device/orientation
          // Tablet landscape: 4 columns, Tablet portrait: 2 columns, Phone: 2 columns
          final int gridColumns = ResponsiveHelper.columnsForWidth(
            availableWidth -
                2 * ResponsiveHelper.adaptive(phone: 16.w, tablet: 24.w),
            minItemWidth: 220,
            spacing: 16.sp,
            minColumns: 2,
            maxColumns: 4,
          );

          for (int i = 0; i < dateGames.length; i += gridColumns) {
            final isLast = i + gridColumns >= dateGames.length;

            // Gather games for this row
            final rowGames = <GamesTourModel>[];
            for (int j = 0; j < gridColumns && i + j < dateGames.length; j++) {
              rowGames.add(dateGames[i + j]);
            }

            listEntries.add(
              _FavoritesGridRowEntry(
                games: rowGames,
                gridColumns: gridColumns,
                isLast: isLast,
                listIndex: listEntries.length,
              ),
            );
          }
        } else {
          // Card mode or Board mode
          for (int i = 0; i < dateGames.length; i++) {
            final game = dateGames[i];
            final gameIndex = gameIdToIndex[game.gameId] ?? 0;
            final isLast = i == dateGames.length - 1;
            final showHint =
                isFirstGameCard && viewMode == GamesListViewMode.gamesCard;
            if (isFirstGameCard) isFirstGameCard = false;

            if (isChessBoardVisible) {
              // Board mode: use GameCardWrapperWidget with chessboard visible
              listEntries.add(
                _FavoritesBoardGameEntry(
                  game: game,
                  gameIndex: gameIndex,
                  listIndex: listEntries.length,
                  isLast: isLast,
                ),
              );
            } else {
              // Card mode: use LiveGamebaseSearchGameCard for live position updates
              listEntries.add(
                _FavoritesCardGameEntry(
                  game: game,
                  gameIndex: gameIndex,
                  animationIndex: listEntries.length,
                  showHint: showHint,
                  isLast: isLast,
                ),
              );
            }
          }
        }
      }
    }

    // The list's end, one slot of one height whatever it holds: the next
    // days loading (a list being replaced has its quiet line at the top
    // instead), room to scroll on into them, or the end. The list's length
    // never changes as a page starts or lands, so nothing under the
    // reader's finger jumps at the paging point.
    if (state.games.isNotEmpty) {
      listEntries.add(
        _FavoritesFooterEntry(
          state.isLoading && !state.isReplacing
              ? _FavoritesFooterType.loading
              : state.hasMore
              ? _FavoritesFooterType.spacer
              : _FavoritesFooterType.end,
        ),
      );
    }

    return SliverMainAxisGroup(
      slivers: [
        SliverPadding(
          padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 0),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) => _buildListEntry(
                listEntries[index],
                games: games,
                gamesData: gamesData,
                gameIdToIndex: gameIdToIndex,
                viewMode: viewMode,
              ),
              childCount: listEntries.length,
              addAutomaticKeepAlives: false,
            ),
          ),
        ),
        // The last game ends clear of the floating buttons over the list.
        // They step away while the search is open: the room gives way on
        // the search's own timeline, as on every Games list.
        SearchModeListEnd.sliver(
          base: 8.h,
          buttons: FavoritesGamesFabs.reach(context),
        ),
      ],
    );
  }

  Widget _buildListEntry(
    _FavoritesGamesListEntry entry, {
    required List<GamesTourModel> games,
    required GamesScreenModel gamesData,
    required Map<String, int> gameIdToIndex,
    required GamesListViewMode viewMode,
  }) {
    if (entry is _FavoritesDateHeaderEntry) {
      return Padding(
        padding: EdgeInsets.only(bottom: 12.h),
        child: _DateHeader(
          dateLabel: _formatDateHeader(entry.dateKey),
          gameCount: entry.gameCount,
          isExpanded: entry.isExpanded,
          onToggle: () => _toggleDateSection(entry.dateKey),
        ),
      );
    }

    if (entry is _FavoritesGridRowEntry) {
      return Padding(
        padding: EdgeInsets.only(bottom: entry.isLast ? 16.h : 12.h),
        child: Row(
          children: [
            for (int j = 0; j < entry.gridColumns; j++) ...[
              if (j > 0) SizedBox(width: 12.sp),
              Expanded(
                child: j < entry.games.length
                    ? _buildGridGame(
                        entry.games[j],
                        gameIdToIndex[entry.games[j].gameId] ?? 0,
                        games,
                        entry.listIndex,
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ],
        ),
      );
    }

    if (entry is _FavoritesBoardGameEntry) {
      return _FavoritesLiveBoardGameCard(
        key: ValueKey('fav_game_${entry.game.gameId}_${viewMode.index}'),
        game: entry.game,
        gamesData: gamesData,
        gameIndex: entry.gameIndex,
        listIndex: entry.listIndex,
        allGames: games,
        isChessBoardVisible: true,
        isLast: entry.isLast,
        streamEnabled: true,
        onNavigateToChessBoard: _navigateToChessBoard,
      );
    }

    if (entry is _FavoritesCardGameEntry) {
      return Padding(
        padding: EdgeInsets.only(bottom: entry.isLast ? 16.h : 12.h),
        child: LiveGamebaseSearchGameCard(
          game: entry.game,
          allGames: games,
          gameIndex: entry.gameIndex,
          animationIndex: entry.animationIndex,
          showRound: true,
          showSwipeHint: entry.showHint,
          showGamebaseButton: false,
          streamEnabled: true,
          viewSource: ChessboardView.favorites,
          onAdd: () => _showAddToFolderSheet(context, entry.game),
          onLiveAdd: (liveGame) => _showAddToFolderSheet(context, liveGame),
          onLiveTap: (liveGame, updatedGames, liveIndex) {
            _navigateToChessBoard(liveGame, updatedGames, liveIndex);
          },
        ),
      );
    }

    if (entry is _FavoritesFooterEntry) {
      return SizedBox(
        key: const ValueKey('favorites_games_list_end_slot'),
        height: _FavoritesFooterEntry.height,
        child: Center(
          child: switch (entry.type) {
            _FavoritesFooterType.loading => SizedBox(
              width: 24.w,
              height: 24.h,
              child: CircularProgressIndicator(
                color: context.colors.textPrimary,
                strokeWidth: 2,
              ),
            ),
            _FavoritesFooterType.spacer => const SizedBox.shrink(),
            _FavoritesFooterType.end => Text(
              'No more games',
              maxLines: 1,
              style: AppTypography.textXsRegular.copyWith(
                color: context.collectionSubtleInk,
              ),
            ),
          },
        ),
      );
    }

    return const SizedBox.shrink();
  }

  Widget _buildGridGame(
    GamesTourModel game,
    int gameIndex,
    List<GamesTourModel> allGames,
    int listIndex,
  ) {
    return GridGameCardWrapperWidget(
      key: ValueKey('fav_grid_game_${game.gameId}'),
      game: game,
      orderedGames: allGames,
      gameIndex: gameIndex,
      allowStockfishFallback: true,
      streamEnabled: true,
      // Carried for the player-name tap, which opens the score card straight
      // from the card without going through [_navigateToChessBoard].
      viewSource: ChessboardView.favorites,
      onChangedWithLiveGames: (updatedGames) {
        if (!mounted) return;
        _navigateToChessBoard(updatedGames[gameIndex], updatedGames, gameIndex);
      },
      pinnedIds: const [],
      // Favorites has no tour scope to pin into, so the menu drops the item
      // rather than offering a tap that does nothing.
      showPin: false,
      onPinToggle: (_) {},
    );
  }

  Widget _buildLoadingState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 48.w,
            height: 48.h,
            child: CircularProgressIndicator(
              color: context.colors.textPrimary,
              strokeWidth: 2.5,
            ),
          ),
          SizedBox(height: 16.h),
          Text(
            'Loading games...',
            style: AppTypography.textSmRegular.copyWith(
              color: context.colors.textSecondary,
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 300.ms);
  }

  Widget _buildErrorState(String error) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.error_outline_rounded,
            color: context.collectionAlertInk,
            size: 48.ic,
          ),
          SizedBox(height: 16.h),
          Text(
            'Failed to load games',
            style: AppTypography.textMdMedium.copyWith(
              color: context.colors.textPrimary,
            ),
          ),
          SizedBox(height: 8.h),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 32.w),
            child: Text(
              error,
              style: AppTypography.textSmRegular.copyWith(
                color: context.colors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          SizedBox(height: 24.h),
          TextButton(
            onPressed: () => ref
                .read(favoritesCombinedGamesProvider.notifier)
                .refreshGames(),
            style: TextButton.styleFrom(
              backgroundColor: context.colors.textPrimary.withValues(
                alpha: 0.1,
              ),
              padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 12.h),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8.br),
              ),
            ),
            child: Text(
              'Retry',
              style: AppTypography.textSmMedium.copyWith(
                color: context.colors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.sports_esports_outlined,
            color: context.textInk(0.4),
            size: 56.sp,
          ),
          SizedBox(height: 20.h),
          Text(
            'No games found',
            style: AppTypography.textMdMedium.copyWith(
              color: context.colors.textPrimary,
            ),
          ),
          SizedBox(height: 8.h),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 40.w),
            child: Text(
              'Your favorite players haven\'t played any games yet.',
              style: AppTypography.textSmRegular.copyWith(
                color: context.colors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  /// The followed players, in the shape the shared suggestion widget compares
  /// against, so a player already followed is never offered again.
  PlayerStandingModel _asStandingModel(FavoritePlayer player) {
    return PlayerStandingModel(
      countryCode: _extractFederation(player) ?? '',
      title: player.metadata['title']?.toString(),
      name: player.playerName,
      score: (player.metadata['rating'] as num?)?.toInt() ?? 0,
      scoreChange: 0,
      matchScore: null,
      fideId: int.tryParse(player.fideId ?? ''),
    );
  }

  /// Adds a player surfaced by the global-search fallback. Same gates as every
  /// other add: a full account first, then the free-tier limit.
  Future<void> _addFavoritePlayer(PlayerStandingModel player) async {
    final allowed = await requireFullAuthGuard(context);
    if (!allowed || !mounted) return;

    final canAdd = await canAddMoreFavorites(context, ref);
    if (!canAdd || !mounted) return;

    HapticFeedbackService.medium();
    try {
      await ref
          .read(favoritePlayersProviderNew.notifier)
          .addFavorite(
            starFlow: playerStarNotificationFlow(context),
            fideId: player.fideId?.toString(),
            playerName: player.name,
            countryCode: player.countryCode,
            rating: player.score,
            title: player.title,
          );
    } on FavoriteLimitExceededException {
      if (mounted) {
        await showPremiumPaywallSheet(
          context: context,
          allowRewarded: false,
          trigger: PaywallTrigger.favorites,
        );
      }
    } catch (error) {
      if (mounted) {
        showAppSnack(
          context,
          userFacingError(error),
          tone: AppSnackTone.danger,
        );
      }
    }
  }

  Future<void> _openPlayer(PlayerStandingModel player) async {
    if (!await ensureFavoritesGameAccess(context) || !mounted) return;
    // The search field is the screen's; drop its keyboard on the way out.
    FocusManager.instance.primaryFocus?.unfocus();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PlayerProfileScreen(
          fideId: player.fideId,
          playerName: player.name,
          title: player.title,
          federation: player.countryCode,
          rating: player.score,
        ),
      ),
    );
  }

  /// The filters (with the search's words, if any) leave no game: the one
  /// no-matches line every Games list shows, where the first game would be,
  /// with the way back to every game. Its action plays the button haptic.
  Widget _buildNoFilterResultsSliver(FavoritesCombinedGamesState state) {
    return SearchNoMatches.sliver(
      query: state.isSearching ? state.searchQuery : null,
      filtered: true,
      onClear: () =>
          ref.read(favoritesCombinedGamesProvider.notifier).clearFilter(),
    );
  }

  void _showAddToFolderSheet(BuildContext context, GamesTourModel game) {
    showAddToFolderSheet(context: context, game: game);
  }

  /// Navigate to chess board screen for the selected game.
  Future<void> _navigateToChessBoard(
    GamesTourModel game,
    List<GamesTourModel> allGames,
    int gameIndex,
  ) async {
    if (!mounted) return;
    final allowed = await ensureFavoritesGameAccess(context);
    if (!allowed || !mounted) return;
    ref
        .read(gameCardWrapperProvider)
        .navigateToChessBoard(
          context: context,
          orderedGames: allGames,
          gameIndex: gameIndex,
          onReturnFromChessboard: (_) {},
          viewSource: ChessboardView.favorites,
        );
  }
}

abstract class _FavoritesGamesListEntry {
  const _FavoritesGamesListEntry();
}

class _FavoritesDateHeaderEntry extends _FavoritesGamesListEntry {
  const _FavoritesDateHeaderEntry({
    required this.dateKey,
    required this.gameCount,
    required this.isExpanded,
  });

  final String dateKey;
  final int gameCount;
  final bool isExpanded;
}

class _FavoritesGridRowEntry extends _FavoritesGamesListEntry {
  const _FavoritesGridRowEntry({
    required this.games,
    required this.gridColumns,
    required this.isLast,
    required this.listIndex,
  });

  final List<GamesTourModel> games;
  final int gridColumns;
  final bool isLast;
  final int listIndex;
}

class _FavoritesBoardGameEntry extends _FavoritesGamesListEntry {
  const _FavoritesBoardGameEntry({
    required this.game,
    required this.gameIndex,
    required this.listIndex,
    required this.isLast,
  });

  final GamesTourModel game;
  final int gameIndex;
  final int listIndex;
  final bool isLast;
}

class _FavoritesCardGameEntry extends _FavoritesGamesListEntry {
  const _FavoritesCardGameEntry({
    required this.game,
    required this.gameIndex,
    required this.animationIndex,
    required this.showHint,
    required this.isLast,
  });

  final GamesTourModel game;
  final int gameIndex;
  final int animationIndex;
  final bool showHint;
  final bool isLast;
}

enum _FavoritesFooterType { loading, spacer, end }

class _FavoritesFooterEntry extends _FavoritesGamesListEntry {
  const _FavoritesFooterEntry(this.type);

  /// The slot's one height: the tallest of what it can hold (the spinner
  /// with its room above and below).
  static double get height => 72.h;

  final _FavoritesFooterType type;
}

/// Date section header - similar to RoundHeader
class _DateHeader extends StatelessWidget {
  final String dateLabel;
  final int gameCount;
  final bool isExpanded;
  final VoidCallback? onToggle;

  const _DateHeader({
    required this.dateLabel,
    required this.gameCount,
    required this.isExpanded,
    this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onToggle,
      borderRadius: BorderRadius.circular(12.br),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 16.sp, vertical: 14.sp),
        decoration: BoxDecoration(
          color: context.colors.surfaceRecessed,
          borderRadius: BorderRadius.circular(12.br),
          border: Border.all(
            color: context.colors.textPrimary.withValues(alpha: 0.1),
          ),
          boxShadow: [
            BoxShadow(
              color: context.isLightTheme
                  ? context.colors.shadow
                  : Colors.black.withValues(alpha: 0.1),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 4.w,
              height: 20.h,
              decoration: BoxDecoration(
                color: context.colors.accentText,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            SizedBox(width: 12.w),
            Expanded(
              child: Text(
                '$dateLabel • $gameCount ${gameCount == 1 ? 'game' : 'games'}',
                style: TextStyle(
                  color: context.colors.textPrimary,
                  fontSize: 16.sp,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (onToggle != null) ...[
              SizedBox(width: 12.w),
              Icon(
                isExpanded
                    ? Icons.keyboard_arrow_up_rounded
                    : Icons.keyboard_arrow_down_rounded,
                color: context.textInk(0.5),
                size: 20.sp,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Checks event access for navigation while allowing offscreen live streams to
/// auto-dispose.
class _FavoritesLiveBoardGameCard extends ConsumerStatefulWidget {
  const _FavoritesLiveBoardGameCard({
    super.key,
    required this.game,
    required this.gamesData,
    required this.gameIndex,
    required this.listIndex,
    required this.allGames,
    required this.isChessBoardVisible,
    required this.isLast,
    required this.streamEnabled,
    required this.onNavigateToChessBoard,
  });

  final GamesTourModel game;
  final GamesScreenModel gamesData;
  final int gameIndex;
  final int listIndex;
  final List<GamesTourModel> allGames;
  final bool isChessBoardVisible;
  final bool isLast;
  final bool streamEnabled;
  final void Function(
    GamesTourModel game,
    List<GamesTourModel> games,
    int index,
  )
  onNavigateToChessBoard;

  @override
  ConsumerState<_FavoritesLiveBoardGameCard> createState() =>
      _FavoritesLiveBoardGameCardState();
}

class _FavoritesLiveBoardGameCardState
    extends ConsumerState<_FavoritesLiveBoardGameCard> {
  void _handleNavigate(List<GamesTourModel> updatedGames) {
    if (!mounted) return;
    widget.onNavigateToChessBoard(
      updatedGames[widget.gameIndex],
      updatedGames,
      widget.gameIndex,
    );
  }

  @override
  Widget build(BuildContext context) {
    final gameId = widget.game.gameId;

    // Use BoardGameCardWrapperWidget for live position updates
    final card = Padding(
      padding: EdgeInsets.only(bottom: widget.isLast ? 16.h : 12.h),
      child: BoardGameCardWrapperWidget(
        key: ValueKey('fav_board_game_${widget.game.gameId}'),
        game: widget.game,
        orderedGames: widget.allGames,
        gameIndex: widget.gameIndex,
        viewSource: ChessboardView.favorites,
        onChangedWithLiveGames: _handleNavigate,
        pinnedIds: widget.gamesData.pinnedGamedIs,
        allowStockfishFallback: widget.streamEnabled,
        streamEnabled: widget.streamEnabled,
        // Favorites has no tour scope to pin into, so the menu drops the item
        // rather than offering a tap that does nothing.
        showPin: false,
        onPinToggle: (_) {},
      ),
    );

    // Use global set to track animations - survives tab switches and rebuilds
    if (!_favoritesAnimatedGameIds.contains(gameId)) {
      _favoritesAnimatedGameIds.add(gameId);
      // It slides into place, drawn from its first frame: a card is never
      // hidden behind its entrance.
      return card
          .animate(delay: Duration(milliseconds: (widget.listIndex % 10) * 30))
          .slideY(begin: 0.05, end: 0, duration: 200.ms, curve: Curves.easeOut);
    }

    return card;
  }
}
