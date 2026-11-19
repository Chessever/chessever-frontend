import 'dart:async';

import 'package:chessever2/main.dart' show routeObserver;
import 'package:chessever2/providers/game_list_live_first_provider.dart';
import 'package:chessever2/providers/country_dropdown_provider.dart';
import 'package:chessever2/providers/live_game_ids_provider.dart';
import 'package:chessever2/utils/country_utils.dart';
import 'package:chessever2/screens/countrymen/provider/countrymen_mode_provider.dart';
import 'package:chessever2/screens/chessboard/provider/chess_board_screen_provider_new.dart';
import 'package:chessever2/screens/chessboard/provider/game_pgn_stream_provider.dart';
import 'package:chessever2/screens/chessboard/widgets/chess_board_from_fen_new.dart';
import 'package:chessever2/screens/countrymen/provider/countrymen_combined_games_provider.dart';
import 'package:chessever2/screens/favorites/widgets/collection_inks.dart';
import 'package:chessever2/screens/favorites/widgets/games_list_refetch_line.dart';
import 'package:chessever2/screens/favorites/widgets/settling_scroll_controller.dart';
import 'package:chessever2/screens/library/widgets/add_to_folder_sheet.dart';
import 'package:chessever2/screens/library/widgets/live_gamebase_search_game_card.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_list_view_mode_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/game_card_wrapper/game_card_wrapper_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/game_card_wrapper/grid_game_card_wrapper_widget.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/game_card_wrapper/live_game_card_provider.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/widgets/paywall/premium_game_access.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/scroll_cache.dart';
import 'package:chessever2/utils/foreground_task_scheduler.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/game_filter/game_filter.dart';
import 'package:chessever2/widgets/ink_fab.dart';
import 'package:chessever2/widgets/live_first_capsule.dart';
import 'package:chessever2/widgets/quick_list_toggles.dart';
import 'package:chessever2/widgets/search_mode/search_mode.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:chessever2/widgets/scroll_to_top_bus.dart';
import 'package:chessever2/widgets/search_no_matches.dart';
import 'package:intl/intl.dart';

/// Track animated game IDs for Countrymen to prevent re-animation
final Set<String> _countrymenAnimatedGameIds = {};

/// Day key for games with no timestamp; that bucket sorts last.
const String _unknownDayKey = '0000-00-00';

/// Groups Countrymen games into days, newest day first.
///
/// Games are bucketed by their **device-local** calendar day. `lastMoveTime`
/// is a UTC instant from Postgres; formatting it directly (without
/// `.toLocal()`) keyed games by their UTC date while the Today / Yesterday
/// headers are derived from local `DateTime.now()`. For anyone east of UTC
/// (e.g. Türkiye, UTC+3) a game finished in the local small hours (01:00
/// local is still 22:00 UTC the previous day) was filed one day off, so today
/// and yesterday intermixed and the per-day counts were wrong. Converting to
/// local before extracting the day makes the buckets agree with the header.
/// Games with no timestamp go to an explicit unknown bucket rather than
/// silently defaulting to today.
///
/// With [liveFirst] (Trello #1420) the games in play ([liveIds], the
/// server's set; by their own rows while it is unknown) lead the list,
/// gathered at the head of today ([gatherLiveGamesFirst]), keeping the
/// provider's order on both sides of the split. [now] pins today and "live"
/// for tests.
@visibleForTesting
Map<String, List<GamesTourModel>> groupCountrymenGamesByDay(
  List<GamesTourModel> games, {
  bool liveFirst = false,
  Set<String>? liveIds,
  DateTime? now,
}) {
  final grouped = <String, List<GamesTourModel>>{};

  for (final game in games) {
    final raw = game.lastMoveTime;
    final dateKey = raw == null
        ? _unknownDayKey
        : DateFormat('yyyy-MM-dd').format(raw.toLocal());
    grouped.putIfAbsent(dateKey, () => []).add(game);
  }

  // Sort keys by date descending (most recent first); unknown sinks to the end.
  final sortedKeys = grouped.keys.toList()
    ..sort((a, b) {
      if (a == _unknownDayKey) return 1;
      if (b == _unknownDayKey) return -1;
      return b.compareTo(a);
    });

  final byDay = {for (final key in sortedKeys) key: grouped[key]!};
  if (!liveFirst) return byDay;
  return gatherLiveGamesFirst(
    byDay,
    todayKey: DateFormat(
      'yyyy-MM-dd',
    ).format((now ?? DateTime.now()).toLocal()),
    unknownKey: _unknownDayKey,
    liveIds: liveIds,
    now: now,
  );
}

/// Opens the Countrymen games filter and applies the result.
///
/// Every filter is applied server-side, so a changed filter refetches the
/// list ([CountrymenCombinedGamesNotifier.applyFilter]).
Future<void> showCountrymenGameFilterDialog(
  BuildContext context,
  WidgetRef ref,
) async {
  HapticFeedbackService.buttonPress();
  final result = await showGameFilterDialog(
    context: context,
    currentFilter: ref.read(countrymenCombinedGamesProvider).filter,
    showFormatFilter: false,
  );
  if (result == null || !context.mounted) return;
  await ref.read(countrymenCombinedGamesProvider.notifier).applyFilter(result);
}

/// Whose live games the Countrymen Games list asks about: the federation it
/// lists (its FIDE code, as the list queries it), under the list's rating
/// floor (none: every rating, as the list) and filter. Null with no country.
final countrymenGamesLiveScopeProvider =
    Provider.autoDispose<CountrymenLiveGamesScope?>((ref) {
      final countryCode = ref.watch(
        countrymenCombinedGamesProvider.select((state) => state.countryCode),
      );
      final filter = ref.watch(
        countrymenCombinedGamesProvider.select((state) => state.filter),
      );
      if (countryCode == null || countryCode.trim().isEmpty) return null;
      return CountrymenLiveGamesScope(
        countryCode: CountryUtils.toFideCode(countryCode),
        filter: filter,
      );
    });

/// The games in play with a player of the Countrymen list's federation, by
/// the server ([countrymenLiveGameIdsProvider]): null until it answers. No
/// country has nothing in play.
final countrymenGamesServerLiveIdsProvider = Provider.autoDispose<Set<String>?>(
  (ref) {
    final scope = ref.watch(countrymenGamesLiveScopeProvider);
    if (scope == null) return const <String>{};
    return ref.watch(countrymenLiveGameIdsProvider(scope));
  },
);

/// What the Countrymen Games list counts as in play and what its Live first
/// lifts: the server's set, less any game the list already shows as
/// finished ([listedLiveGameIds]). Null while the server has not answered.
final countrymenGamesLiveIdsProvider = Provider.autoDispose<Set<String>?>(
  (ref) => listedLiveGameIds(
    ref.watch(countrymenGamesServerLiveIdsProvider),
    ref.watch(countrymenCombinedGamesProvider.select((state) => state.games)),
  ),
);

/// How many games of the Countrymen Games list are in play, read on Live
/// first's capsule ("See 3 live"). Null while unknown ("See live").
final countrymenGamesLiveCountProvider = Provider.autoDispose<int?>(
  (ref) => ref.watch(countrymenGamesLiveIdsProvider)?.length,
);

/// Whether a game of the Countrymen Games list is in play. Live first floats
/// over the list only while this holds (Trello #1420): with nothing live it
/// has nothing to do. Until the server answers, the list's own rows decide,
/// so a backend that cannot say keeps the capsule (with no number).
final countrymenGamesAnyLiveProvider = Provider.autoDispose<bool>((ref) {
  final live = ref.watch(countrymenGamesLiveIdsProvider);
  if (live != null) return live.isNotEmpty;
  return ref.watch(
    countrymenCombinedGamesProvider.select(
      (state) => state.filteredGames.any(GameFilterHelper.isInPlay),
    ),
  );
});

/// The Countrymen Games list's live-game poll, when it is running: for the
/// page to pause it while covered and ask again on its way back.
LiveGameIdsNotifier? _countrymenLiveIdsPoll(WidgetRef ref) {
  // Only a poll already running: nothing is started from here.
  if (!ref.exists(countrymenGamesLiveScopeProvider)) return null;
  final scope = ref.read(countrymenGamesLiveScopeProvider);
  if (scope == null) return null;
  final provider = countrymenLiveGameIdsProvider(scope);
  return ref.exists(provider) ? ref.read(provider.notifier) : null;
}

/// The Games list's toolbar: board view, Classical only and Filters, bare
/// glyphs, ending the app bar. The full-page search header ends with the same
/// row less the board view ([withBoardView] false): Classical and Filters
/// stay at the same spot in both, and the board view gives way to the field
/// along with the title, leaving the field room to type in on any phone.
///
/// It watches the same auto-dispose games provider as the Games tab, so the
/// filter dialog's route cannot drop the notifier it applies to.
class CountrymenGamesToolbar extends ConsumerWidget {
  const CountrymenGamesToolbar({super.key, this.withBoardView = true});

  /// Leads with the board view (the page's header); the search header's
  /// row leaves it out.
  final bool withBoardView;

  /// What the search matches, cycled once after "Search" in its field.
  static const List<String> searchHints = ['player', 'opening', 'ECO code'];

  /// The full row's width: three 44pt targets.
  static const double width = 3 * SearchModeFilterButton.target;

  /// The search header's row: Classical and Filters, held still through the
  /// morph where the page's header has them ([SearchModeShared]).
  static const Widget inSearch = SearchModeShared(
    id: CountrymenGamesToolbar,
    child: CountrymenGamesToolbar(withBoardView: false),
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(
      countrymenCombinedGamesProvider.select((state) => state.filter),
    );
    final classicalOnly = filter.timeControl == GameTimeControlFilter.classical;

    final shared = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ClassicalToggleButton(
          pressed: classicalOnly,
          onTap: () {
            HapticFeedbackService.toggle();
            final current = ref.read(countrymenCombinedGamesProvider).filter;
            final isClassical =
                current.timeControl == GameTimeControlFilter.classical;
            unawaited(
              ref
                  .read(countrymenCombinedGamesProvider.notifier)
                  .applyFilter(
                    current.copyWith(
                      timeControl: isClassical
                          ? GameTimeControlFilter.all
                          : GameTimeControlFilter.classical,
                    ),
                  ),
            );
          },
        ),
        SearchModeFilterButton(
          count: filter.activeFilterCount,
          onTap: () => showCountrymenGameFilterDialog(context, ref),
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
        SearchModeShared(id: CountrymenGamesToolbar, child: shared),
      ],
    );
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
class CountrymenGamesFabs extends ConsumerWidget {
  const CountrymenGamesFabs({super.key});

  static const _surface = GameListLiveFirstSurface.countrymen;

  /// How far up from the bottom the buttons reach: the search with Live
  /// first above it ([InkFabStack.reach]). The Games list ends this far
  /// clear, so no button covers its last game. Live first counts whether it
  /// floats or not, so the end of the list never jumps as games start and
  /// finish. Countrymen is a pushed page, with no bottom bar under it. Read
  /// it from the list's context: inside the button slot the Scaffold has
  /// already taken the inset away.
  static double reach(BuildContext context) =>
      InkFabStack.reach(context, smallAbove: 1);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final liveFirst = ref.watch(gameListLiveFirstProvider(_surface));
    final anyLive = ref.watch(countrymenGamesAnyLiveProvider);
    // Just after a search closes the list may still hold its hits: what is
    // live among them says nothing of the whole list.
    final holdsHits = ref.watch(
      countrymenCombinedGamesProvider.select((state) => state.isSearching),
    );
    // Only while a game is in play (Trello #1420), or while it is on, so a
    // Live first left on can always be seen and turned off. With nothing
    // live and nothing to undo it is not on screen.
    final offered = (anyLive || liveFirst) && !holdsHits;
    return InkFabStack(
      children: [
        if (offered)
          LiveFirstCapsule(
            key: const ValueKey('countrymen_live_first_fab'),
            on: liveFirst,
            liveCount: ref.watch(countrymenGamesLiveCountProvider),
            onTap: () {
              final liveIds = ref.read(countrymenGamesLiveIdsProvider);
              final press = pressGameListLiveFirst(
                context: context,
                ref: ref,
                surface: _surface,
                games: ref.read(countrymenCombinedGamesProvider).filteredGames,
                liveIds: liveIds,
              );
              // What it lifts is what it counted: the live games the loaded
              // days do not hold yet join today.
              if (press == GameListLiveFirstPress.turnedOn && liveIds != null) {
                unawaited(
                  ref
                      .read(countrymenCombinedGamesProvider.notifier)
                      .ensureListed(liveIds),
                );
              }
            },
          ),
        const SearchInkFab(
          key: ValueKey('countrymen_search_fab'),
          label: 'Search games',
        ),
      ],
    );
  }
}

class CountrymenGamesTab extends ConsumerStatefulWidget {
  const CountrymenGamesTab({super.key});

  @override
  ConsumerState<CountrymenGamesTab> createState() => _CountrymenGamesTabState();
}

class _CountrymenGamesTabState extends ConsumerState<CountrymenGamesTab>
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

  String get _liveCardsPauseReason => 'countrymen_games_scroll_$hashCode';
  // Keep the scrollable subtree mounted while a game route covers this tab so
  // the ScrollController and provider state survive returning from the board.
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

  /// A filter or country change is on its way: its list starts at the top.
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
    ForegroundTaskScheduler.cancel('countrymen_games_resume_$hashCode');
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
      ForegroundTaskScheduler.cancel('countrymen_games_resume_$hashCode');
      _setAppResumed(false);
      return;
    }
    if (!mounted) return;

    _setAppResumed(true);
    ForegroundTaskScheduler.schedule(
      key: 'countrymen_games_resume_$hashCode',
      task: () {
        if (!mounted) return;
        final route = ModalRoute.of(context);
        if (route?.isCurrent != true) return;
        if (ref.read(selectedCountrymenModeProvider) !=
            CountrymenScreenMode.games) {
          return;
        }

        ref.invalidate(gameUpdatesStreamProvider);
        ref.invalidate(liveGameUpdateStreamProvider);
        ref.invalidate(gameUpdatesBatchStreamProvider);
        unawaited(
          ref.read(countrymenCombinedGamesProvider.notifier).refreshGames(),
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
    final poll = _countrymenLiveIdsPoll(ref);
    if (isActive) {
      _livePoll.uncover(ref, poll, ask: backFromBoard);
    } else {
      _livePoll.cover(ref, poll);
    }
    if (!isActive) {
      ForegroundTaskScheduler.cancel('countrymen_games_resume_$hashCode');
      _stopLiveCardsForHiddenTab();
    }
  }

  /// With Live first on, the live games the loaded days miss join the list
  /// (see [CountrymenCombinedGamesNotifier.ensureListed]), so it lifts what
  /// its capsule counts.
  void _listLiveGames() {
    if (!mounted) return;
    if (!ref.read(
      gameListLiveFirstProvider(GameListLiveFirstSurface.countrymen),
    )) {
      return;
    }
    final liveIds = ref.read(countrymenGamesLiveIdsProvider);
    if (liveIds == null || liveIds.isEmpty) return;
    unawaited(
      ref.read(countrymenCombinedGamesProvider.notifier).ensureListed(liveIds),
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
    final threshold = 200.0 + CountrymenGamesFabs.reach(context);
    if (metrics.maxScrollExtent - metrics.pixels > threshold) return;
    final state = ref.read(countrymenCombinedGamesProvider);
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
    final state = ref.read(countrymenCombinedGamesProvider);
    if (state.isSearching) {
      ref
          .read(countrymenCombinedGamesProvider.notifier)
          .loadMoreSearchResults();
    } else {
      ref.read(countrymenCombinedGamesProvider.notifier).loadMoreGames();
    }
  }

  String _formatDateHeader(String dateKey) {
    if (dateKey == _unknownDayKey) return 'Unknown date';
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
    final folds = ref.read(countrymenCombinedGamesProvider).isSearching
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
  /// left, a new filter's or country's list starts at the top. Nothing moves
  /// while a fetch is still on its way; the list it replaces stays put.
  void _onGamesChanged(
    CountrymenCombinedGamesState? previous,
    CountrymenCombinedGamesState next,
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
        previous.countryCode != next.countryCode) {
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
        final state = ref.read(countrymenCombinedGamesProvider);
        if (state.hasMore && !state.isLoading) {
          _loadMoreDays();
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    ref.listen<CountrymenScreenMode>(selectedCountrymenModeProvider, (_, next) {
      if (next != CountrymenScreenMode.games) {
        _stopLiveCardsForHiddenTab();
      }
    });

    final selectedMode = ref.watch(selectedCountrymenModeProvider);
    if (selectedMode != CountrymenScreenMode.games) {
      return const SizedBox.shrink();
    }

    final state = ref.watch(countrymenCombinedGamesProvider);
    ref.listen(countrymenCombinedGamesProvider, _onGamesChanged);
    // Live first brings the games in play to the top of the list; the list
    // goes up to them.
    ref.listen<bool>(
      gameListLiveFirstProvider(GameListLiveFirstSurface.countrymen),
      (previous, next) {
        if (next && previous != true) {
          animateScrollControllerToTop(_scrollController);
        }
      },
    );
    final viewMode = ref.watch(gamesListViewModeProvider);
    final liveFirst = ref.watch(
      gameListLiveFirstProvider(GameListLiveFirstSurface.countrymen),
    );
    // Only Live first reorders by the live set, so only then does the list
    // follow it; while on, a game that starts joins the list as the count
    // takes it in.
    final liveIds = liveFirst
        ? ref.watch(countrymenGamesLiveIdsProvider)
        : null;
    if (liveFirst) {
      ref.listen<Set<String>?>(
        countrymenGamesLiveIdsProvider,
        (_, _) => _listLiveGames(),
      );
    }
    final streamEnabled = _isActiveOnScreen && _appIsResumed;

    final content = RefreshIndicator(
      onRefresh: () async {
        HapticFeedbackService.medium();
        // The count of games in play comes along with the list.
        unawaited(_countrymenLiveIdsPoll(ref)?.refresh());
        await ref.read(countrymenCombinedGamesProvider.notifier).refreshGames();
      },
      color: context.colors.textPrimary,
      backgroundColor: context.colors.surface,
      child: NotificationListener<ScrollMetricsNotification>(
        onNotification: _onScrollMetrics,
        child: NotificationListener<ScrollStartNotification>(
          onNotification: _onScrollStart,
          child: CustomScrollView(
            key: PageStorageKey<String>(
              'countrymen_games_list_${viewMode.index}',
            ),
            controller: _scrollController,
            scrollCacheExtent: kListScrollCacheExtent,
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            slivers: [
              // Content. The search field lives in the screen's full-page
              // search header (Trello #1420), above this same list.
              SliverLayoutBuilder(
                builder: (context, constraints) => _buildContentSliver(
                  state,
                  viewMode,
                  streamEnabled,
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
  static bool _showsFirstLoad(CountrymenCombinedGamesState state) =>
      state.isLoading && state.games.isEmpty && !state.isReplacing;

  Widget _buildContentSliver(
    CountrymenCombinedGamesState state,
    GamesListViewMode viewMode,
    bool streamEnabled,
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
        return _buildNoSearchResultsSliver(state);
      }
      return SliverFillRemaining(
        hasScrollBody: false,
        child: _buildEmptyState(),
      );
    }

    // Use filtered games based on filter settings
    final filteredGames = state.filteredGames;

    // Show empty state if filter excludes all games
    if (filteredGames.isEmpty && state.filter.hasActiveFilters) {
      return _buildNoFilterResultsSliver(state);
    }

    // Group games by date; with Live first, the live games lead the list.
    final gamesByDate = groupCountrymenGamesByDay(
      filteredGames,
      liveFirst: liveFirst,
      liveIds: liveIds,
    );

    // The order a board opened from this list swipes through. With Live
    // first it follows the list as shown; otherwise it stays the provider's.
    final games = liveFirst
        ? [for (final dayGames in gamesByDate.values) ...dayGames]
        : filteredGames;

    // Build a mapping of game IDs to their indices for reliable lookup
    final gameIdToIndex = <String, int>{};
    for (int i = 0; i < games.length; i++) {
      gameIdToIndex[games[i].gameId] = i;
    }

    // Build cheap row descriptors only. The actual cards are created lazily
    // for visible rows by SliverChildBuilderDelegate.
    final listEntries = <_CountrymenGamesListEntry>[];
    bool isFirstGameCard = true;
    final isGrid = viewMode == GamesListViewMode.chessBoardGrid;
    final isChessBoardVisible = viewMode == GamesListViewMode.chessBoard;

    // Create GamesScreenModel for GameCardWrapperWidget
    final gamesData = GamesScreenModel(
      gamesTourModels: games,
      pinnedGamedIs: const [],
    );

    final folds = state.isSearching ? _searchCollapsedDates : _collapsedDates;
    for (final entry in gamesByDate.entries) {
      final dateKey = entry.key;
      final dateGames = entry.value;
      final isCollapsed = folds.contains(dateKey);

      // Date header
      listEntries.add(
        _CountrymenDateHeaderEntry(
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
              _CountrymenGridRowEntry(
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
            // Use reliable index lookup by game ID
            final gameIndex = gameIdToIndex[game.gameId] ?? 0;
            final isLast = i == dateGames.length - 1;
            final showHint =
                isFirstGameCard && viewMode == GamesListViewMode.gamesCard;
            if (isFirstGameCard) isFirstGameCard = false;

            if (isChessBoardVisible) {
              // Board mode: use GameCardWrapperWidget with chessboard visible
              listEntries.add(
                _CountrymenBoardGameEntry(
                  game: game,
                  gameIndex: gameIndex,
                  listIndex: listEntries.length,
                  isLast: isLast,
                ),
              );
            } else {
              // Card mode: use LiveGamebaseSearchGameCard for live position updates
              listEntries.add(
                _CountrymenCardGameEntry(
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
        _CountrymenFooterEntry(
          state.isLoading && !state.isReplacing
              ? _CountrymenFooterType.loading
              : state.hasMore
              ? _CountrymenFooterType.spacer
              : _CountrymenFooterType.end,
        ),
      );
    }

    final horizontalPadding = ResponsiveHelper.adaptive(
      phone: 16.w,
      tablet: 24.w,
    );
    return SliverMainAxisGroup(
      slivers: [
        SliverPadding(
          padding: EdgeInsets.fromLTRB(
            horizontalPadding,
            8.h,
            horizontalPadding,
            0,
          ),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) => _buildListEntry(
                listEntries[index],
                games: games,
                gamesData: gamesData,
                gameIdToIndex: gameIdToIndex,
                viewMode: viewMode,
                streamEnabled: streamEnabled,
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
          buttons: CountrymenGamesFabs.reach(context),
        ),
      ],
    );
  }

  Widget _buildListEntry(
    _CountrymenGamesListEntry entry, {
    required List<GamesTourModel> games,
    required GamesScreenModel gamesData,
    required Map<String, int> gameIdToIndex,
    required GamesListViewMode viewMode,
    required bool streamEnabled,
  }) {
    if (entry is _CountrymenDateHeaderEntry) {
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

    if (entry is _CountrymenGridRowEntry) {
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
                        streamEnabled,
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ],
        ),
      );
    }

    if (entry is _CountrymenBoardGameEntry) {
      return _CountrymenLiveBoardGameCard(
        key: ValueKey('cmen_game_${entry.game.gameId}_${viewMode.index}'),
        game: entry.game,
        gamesData: gamesData,
        gameIndex: entry.gameIndex,
        listIndex: entry.listIndex,
        allGames: games,
        isChessBoardVisible: true,
        isLast: entry.isLast,
        streamEnabled: streamEnabled,
      );
    }

    if (entry is _CountrymenCardGameEntry) {
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
          streamEnabled: streamEnabled,
          viewSource: ChessboardView.countryman,
          onAdd: () => _showAddToFolderSheet(context, entry.game),
          onLiveAdd: (liveGame) => _showAddToFolderSheet(context, liveGame),
          onLiveTap: (liveGame, updatedGames, liveIndex) async {
            final allowed = await ensureCountrymenGameAccess(context);
            if (!allowed || !mounted) return;
            _navigateToChessBoard(liveGame, updatedGames, liveIndex);
          },
        ),
      );
    }

    if (entry is _CountrymenFooterEntry) {
      return SizedBox(
        key: const ValueKey('countrymen_games_list_end_slot'),
        height: _CountrymenFooterEntry.height,
        child: Center(
          child: switch (entry.type) {
            _CountrymenFooterType.loading => SizedBox(
              width: 24.w,
              height: 24.h,
              child: CircularProgressIndicator(
                color: context.colors.textPrimary,
                strokeWidth: 2,
              ),
            ),
            _CountrymenFooterType.spacer => const SizedBox.shrink(),
            _CountrymenFooterType.end => Text(
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
    bool streamEnabled,
  ) {
    return GridGameCardWrapperWidget(
      key: ValueKey('cmen_grid_game_${game.gameId}'),
      game: game,
      orderedGames: allGames,
      gameIndex: gameIndex,
      allowStockfishFallback: true,
      streamEnabled: streamEnabled,
      // Carried for the player-name tap, which opens the score card straight
      // from the card without going through [navigateToChessBoard].
      viewSource: ChessboardView.countryman,
      onChangedWithLiveGames: (updatedGames) async {
        final allowed = await ensureCountrymenGameAccess(context);
        if (!allowed || !mounted) return;

        ref
            .read(gameCardWrapperProvider)
            .navigateToChessBoard(
              context: context,
              orderedGames: updatedGames,
              gameIndex: gameIndex,
              onReturnFromChessboard: (_) {},
              viewSource: ChessboardView.countryman,
            );
      },
      pinnedIds: const [],
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
            size: 56.sp,
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
                .read(countrymenCombinedGamesProvider.notifier)
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
    final countryAsync = ref.watch(effectiveCountryProvider);
    final countryName = countryAsync.valueOrNull?.name ?? 'your country';

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.public_outlined, color: context.textInk(0.4), size: 56.sp),
          SizedBox(height: 12.h),
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
              'No recent games found for players from $countryName',
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

  /// The search's words match no game: the one no-matches line every Games
  /// list shows, where the first game would be, with the way back to every
  /// game (the field empties; the search stays open to type again).
  Widget _buildNoSearchResultsSliver(CountrymenCombinedGamesState state) {
    final search = SearchModeScope.maybeOf(context)?.controller;
    return SearchNoMatches.sliver(
      query: state.searchQuery,
      onClear: search?.text.clear,
    );
  }

  /// The filters (with the search's words, if any) leave no game: the same
  /// line, its action clearing the filters. It plays the button haptic.
  Widget _buildNoFilterResultsSliver(CountrymenCombinedGamesState state) {
    return SearchNoMatches.sliver(
      query: state.isSearching ? state.searchQuery : null,
      filtered: true,
      onClear: () =>
          ref.read(countrymenCombinedGamesProvider.notifier).clearFilter(),
    );
  }

  void _showAddToFolderSheet(BuildContext context, GamesTourModel game) {
    showAddToFolderSheet(context: context, game: game);
  }

  void _navigateToChessBoard(
    GamesTourModel game,
    List<GamesTourModel> allGames,
    int gameIndex,
  ) {
    if (!mounted) return;
    ref
        .read(gameCardWrapperProvider)
        .navigateToChessBoard(
          context: context,
          orderedGames: allGames,
          gameIndex: gameIndex,
          onReturnFromChessboard: (_) {},
          viewSource: ChessboardView.countryman,
        );
  }
}

abstract class _CountrymenGamesListEntry {
  const _CountrymenGamesListEntry();
}

class _CountrymenDateHeaderEntry extends _CountrymenGamesListEntry {
  const _CountrymenDateHeaderEntry({
    required this.dateKey,
    required this.gameCount,
    required this.isExpanded,
  });

  final String dateKey;
  final int gameCount;
  final bool isExpanded;
}

class _CountrymenGridRowEntry extends _CountrymenGamesListEntry {
  const _CountrymenGridRowEntry({
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

class _CountrymenBoardGameEntry extends _CountrymenGamesListEntry {
  const _CountrymenBoardGameEntry({
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

class _CountrymenCardGameEntry extends _CountrymenGamesListEntry {
  const _CountrymenCardGameEntry({
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

enum _CountrymenFooterType { loading, spacer, end }

class _CountrymenFooterEntry extends _CountrymenGamesListEntry {
  const _CountrymenFooterEntry(this.type);

  /// The slot's one height: the tallest of what it can hold (the spinner
  /// with its room above and below).
  static double get height => 72.h;

  final _CountrymenFooterType type;
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

/// Opens through [ensureCountrymenGameAccess] while allowing offscreen live
/// streams to auto-dispose.
class _CountrymenLiveBoardGameCard extends ConsumerStatefulWidget {
  const _CountrymenLiveBoardGameCard({
    super.key,
    required this.game,
    required this.gamesData,
    required this.gameIndex,
    required this.listIndex,
    required this.allGames,
    required this.isChessBoardVisible,
    required this.isLast,
    required this.streamEnabled,
  });

  final GamesTourModel game;
  final GamesScreenModel gamesData;
  final int gameIndex;
  final int listIndex;
  final List<GamesTourModel> allGames;
  final bool isChessBoardVisible;
  final bool isLast;
  final bool streamEnabled;

  @override
  ConsumerState<_CountrymenLiveBoardGameCard> createState() =>
      _CountrymenLiveBoardGameCardState();
}

class _CountrymenLiveBoardGameCardState
    extends ConsumerState<_CountrymenLiveBoardGameCard> {
  Future<void> _handleNavigate(List<GamesTourModel> updatedGames) async {
    final allowed = await ensureCountrymenGameAccess(context);
    if (!allowed || !mounted) return;

    ref
        .read(gameCardWrapperProvider)
        .navigateToChessBoard(
          context: context,
          orderedGames: updatedGames,
          gameIndex: widget.gameIndex,
          onReturnFromChessboard: (_) {},
          viewSource: ChessboardView.countryman,
        );
  }

  @override
  Widget build(BuildContext context) {
    // Watch live game updates for ongoing games
    // Use gameId as the stable key to prevent provider recreation
    final liveBatchKey = liveContextBatchKeyForGame(
      game: widget.game,
      contextGames: widget.allGames,
      scopePrefix: 'countrymen_tab_board',
    );
    final liveGame = watchLiveGame(
      ref,
      widget.game,
      batchKey: liveBatchKey,
      streamEnabled: widget.streamEnabled,
    );
    final gameId = liveGame.gameId;
    final updatedGames = List<GamesTourModel>.from(widget.allGames);
    if (widget.gameIndex >= 0 && widget.gameIndex < updatedGames.length) {
      updatedGames[widget.gameIndex] = liveGame;
    }

    // Use ChessBoardFromFENNew directly with Premium checked on navigation.
    final card = Padding(
      padding: EdgeInsets.only(bottom: widget.isLast ? 16.h : 12.h),
      child: ChessBoardFromFENNew(
        key: ValueKey('cmen_board_game_${liveGame.gameId}'),
        gamesTourModel: liveGame,
        onChanged: () => _handleNavigate(updatedGames),
        pinnedIds: widget.gamesData.pinnedGamedIs,
        allowStockfishFallback:
            widget.streamEnabled &&
            !ref.watch(liveGameCardsPausedProvider) &&
            ref.watch(shouldStreamProvider),
        onPinToggle: (_) {},
        scoreCardViewSource: ChessboardView.countryman,
        scoreCardGamesContext: updatedGames,
      ),
    );

    // Use global set to track animations - survives tab switches and rebuilds
    if (!_countrymenAnimatedGameIds.contains(gameId)) {
      _countrymenAnimatedGameIds.add(gameId);
      // It slides into place, drawn from its first frame: a card is never
      // hidden behind its entrance.
      return card
          .animate(delay: Duration(milliseconds: (widget.listIndex % 10) * 30))
          .slideY(begin: 0.05, end: 0, duration: 200.ms, curve: Curves.easeOut);
    }

    return card;
  }
}
