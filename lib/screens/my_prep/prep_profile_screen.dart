import 'dart:async';
import 'dart:math' as math;

import 'package:chessever2/screens/my_prep/data/prep_favorites.dart';
import 'package:chessever2/screens/my_prep/models/prep_models.dart';
import 'package:chessever2/screens/my_prep/prep_access.dart';
import 'package:chessever2/screens/my_prep/prep_actions.dart';
import 'package:chessever2/screens/my_prep/providers/prep_providers.dart';
import 'package:chessever2/screens/library/widgets/library_context_menu.dart'
    show LibraryMenuAction;
import 'package:chessever2/screens/my_prep/services/prep_analysis.dart';
import 'package:chessever2/screens/my_prep/services/prep_index.dart';
import 'package:chessever2/screens/my_prep/services/prep_repository.dart';
import 'package:chessever2/screens/my_prep/tabs/prep_games_tab.dart';
import 'package:chessever2/screens/my_prep/tabs/prep_trees_tab.dart';
import 'package:chessever2/screens/my_prep/prep_sources_screen.dart';
import 'package:chessever2/screens/my_prep/widgets/prep_identity.dart';
import 'package:chessever2/screens/my_prep/widgets/prep_watch_star.dart';
import 'package:chessever2/screens/my_prep/tabs/prep_overview_tab.dart';
import 'package:chessever2/screens/my_prep/widgets/prep_common.dart';
import 'package:chessever2/screens/my_prep/widgets/prep_filters.dart';
import 'package:chessever2/services/game_tree/game_tree_service.dart';
import 'package:chessever2/services/rewarded_premium/rewarded_access_provider.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/number_format_utils.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/app_snack.dart';
import 'package:chessever2/widgets/card_context_menu.dart';
import 'package:chessever2/widgets/generic_loading_widget.dart';
import 'package:chessever2/widgets/ink_fab.dart';
import 'package:chessever2/widgets/scroll_chrome.dart';
import 'package:chessever2/widgets/search_mode/search_mode.dart';
import 'package:chessever2/widgets/segmented_switcher.dart';
import 'package:chessever2/widgets/page_spring.dart';
import 'package:chessever2/widgets/home_top_bar.dart'
    show HomeTopBarMetrics, PageTitle;
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:motor/motor.dart';

/// One prepared person: About and Games over every source together or one
/// source alone, and the source trees.
/// Index of Games among a Prep profile's tabs (About, Games, Build Tree).
const prepProfileGamesTab = 1;

class PrepProfileScreen extends ConsumerStatefulWidget {
  const PrepProfileScreen({
    super.key,
    required this.profileId,
    this.accountKey,
    this.newGames,
    this.initialTab = 0,
  });

  final String profileId;

  /// Set when a "new games" push opened the profile: how many new games the
  /// push announced. The profile fetches them and says so.
  final int? newGames;

  /// The tab it opens on: About, or Games ([prepProfileGamesTab]) for a
  /// "new games" push. A tab that needs Premium or an ad asks first, as its
  /// tab does, and stays on About if the reader declines.
  final int initialTab;

  /// The source to open on alone. Without one, and for a profile with a
  /// single source, the profile opens on every source together.
  final String? accountKey;

  static Future<void> open(
    BuildContext context,
    String profileId, {
    String? accountKey,
  }) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            PrepProfileScreen(profileId: profileId, accountKey: accountKey),
      ),
    );
  }

  @override
  ConsumerState<PrepProfileScreen> createState() => _PrepProfileScreenState();
}

class _PrepProfileScreenState extends ConsumerState<PrepProfileScreen>
    with SingleTickerProviderStateMixin {
  static const _tabs = ['About', 'Games', 'Build Tree'];

  /// The top bar and the tabs, pushed away by the pages' scrolls and back
  /// as they scroll up (X style).
  late final ScrollChromeController _chrome = ScrollChromeController(
    vsync: this,
  );

  /// Games' full-page search: the search button's glass becomes the field
  /// in the header's place, over the same list, narrowing as the reader
  /// types. Back from it clears what was typed; the filters stay, counted on
  /// the list's own line (and on the search header's Filters while it is
  /// open).
  final SearchModeController _search = SearchModeController();

  /// What Games is narrowed to, as typed: '' the moment the search closes.
  final ValueNotifier<String> _query = ValueNotifier('');

  void _onSearchMode() {
    if (mounted) setState(() {});
  }

  /// What each tab asks Premium or a watched ad for. About's summary is
  /// free; its statistics open with [_kStatistics].
  static const _tabFeatures = [null, 'prep_games', 'build_tree'];
  static const _kStatistics = 'prep_statistics';
  int _tab = 0;
  late final PageController _pages = PageController(initialPage: _tab);
  final _gamesController = PrepGamesController();
  PrepFilter _filter = const PrepFilter();
  bool _checkedFreshness = false;

  /// The source About reads alone, or null for every source together.
  String? _account;
  bool _openedOnAccount = false;

  /// The games About last had statistics for, and the source they are from
  /// (empty for every source together). They stay on screen while another
  /// source's games are read, so choosing a source moves nothing.
  PrepAnalysis? _shown;
  String? _shownKey;

  /// What Games last listed: the read it came from and the games it showed.
  /// While a newly chosen source's games are read they stay on screen, the
  /// same list under the Games lists' quiet line, so choosing a source never
  /// empties Games into a message, remounts it or loses its place.
  ({PrepAnalysis analysis, List<PrepGame> games})? _listed;

  /// Whether the Games tab names how many games About's choices leave. A
  /// choice on About raises it; opening Games, where they are, lowers it.
  bool _cue = false;

  /// How many games About's statistics are narrowed to.
  int _matching = 0;

  // A large account is tens of thousands of games: filter and score them
  // once per change, not on every rebuild a sync's progress line causes.
  List<PrepGame>? _filterInput;
  PrepFilter? _filterUsed;
  List<PrepGame> _filterOutput = const [];
  PrepFacets? _facets;
  PrepFilter? _statsFilter;
  PrepStats? _stats;
  String? _statsRating;

  /// What the games About last read say of each source's clocks, read once
  /// per games list: the ratings the identity falls back on.
  List<PrepGame>? _ratedFrom;
  Map<String, Map<PrepTimeControl, int>> _gameRatings = const {};

  Map<String, Map<PrepTimeControl, int>> _gameRatingsOf(List<PrepGame> games) {
    if (!identical(games, _ratedFrom)) {
      _ratedFrom = games;
      _gameRatings = prepGameRatings(games);
    }
    return _gameRatings;
  }

  /// [_filter] as About reads it, within the source its statistics are of.
  PrepFilter? _aboutFrom;
  String? _aboutKey;
  PrepFilter _aboutFilter = const PrepFilter();

  List<PrepGame> _filtered(List<PrepGame> games) {
    if (!identical(games, _filterInput) || _filterUsed != _filter) {
      _filterInput = games;
      _filterUsed = _filter;
      _filterOutput = _filter.apply(games);
    }
    return _filterOutput;
  }

  /// About's numbers for [games] narrowed by [filter]. The games are read
  /// into columns once; a choice then only counts them again. [rating] is
  /// the file of the source whose scale the rating figures of several
  /// sources read together follow.
  PrepStats _statsOf(
    List<PrepGame> games,
    PrepFilter filter, {
    required String? rating,
  }) {
    var facets = _facets;
    if (facets == null || !identical(games, facets.games)) {
      facets = _facets = PrepFacets(games);
      _stats = null;
    }
    if (_stats == null ||
        !identical(filter, _statsFilter) ||
        _statsRating != rating) {
      _statsFilter = filter;
      _statsRating = rating;
      _stats = filter.stats(facets, ratingAccount: rating);
    }
    return _stats!;
  }

  /// [_filter] within [account], or every source's games for null: the same
  /// instance until either changes, so what is counted from it is kept.
  PrepFilter _aboutWithin(PrepAccount? account) {
    final key = account?.key ?? '';
    if (!identical(_aboutFrom, _filter) || _aboutKey != key) {
      _aboutFrom = _filter;
      _aboutKey = key;
      _aboutFilter = _within(_filter, account);
    }
    return _aboutFilter;
  }

  /// Takes a choice made on About. It stays on About, which narrows to it;
  /// Games follows, and its tab says how many games that is. Narrowing is
  /// reading the statistics, so it asks for access; giving the last choice
  /// up never does.
  Future<void> _choose(PrepFilter filter) async {
    if (filter.narrows &&
        !await ensurePrepAccess(context, feature: _kStatistics)) {
      return;
    }
    if (!mounted) return;
    setState(() {
      _filter = filter;
      _cue = true;
    });
  }

  /// Opens About's statistics panels, or null once they may simply open.
  Future<bool> Function()? _unlockStatistics(bool unlocked) =>
      unlocked ? null : () => ensurePrepAccess(context, feature: _kStatistics);

  @override
  void dispose() {
    _pages.dispose();
    _search
      ..removeListener(_onSearchMode)
      ..dispose();
    _query.dispose();
    _gamesController.dispose();
    _chrome.dispose();
    super.dispose();
  }

  /// Reads one source alone, or every source together for null. Games
  /// follows, so a source's profile shows that source's games; its other
  /// filters stay as they were.
  void _chooseAccount(PrepProfile profile, String? key) {
    final account = profile.accounts.length < 2
        ? null
        : profile.accounts.where((a) => a.key == key).firstOrNull;
    _account = account?.key;
    _filter = _within(_filter, account);
  }

  /// [filter] narrowed to one source's games, or widened to every source's.
  static PrepFilter _within(PrepFilter filter, PrepAccount? account) =>
      filter.copyWith(
        source: account?.source,
        accountKey: account?.key,
        accountFile: account == null
            ? null
            : PrepRepository.gamesFileName(account),
      );

  @override
  void initState() {
    super.initState();
    _search.addListener(_onSearchMode);
    final wanted = widget.initialTab.clamp(0, _tabs.length - 1);
    if (wanted == 0) return;
    if (_tabFeatures[wanted] == null || hasPrepAccess(ref)) {
      _tab = wanted;
      return;
    }
    // Without access, opening on a gated tab asks the way its tab does.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_select(wanted));
    });
  }

  Future<void> _select(int index) async {
    if (index == _tab) {
      // Games tapped again takes its list back to the top: with the search
      // in the header the list keeps no up arrow of its own.
      if (index == 1) _gamesController.scrollToTop();
      return;
    }
    final feature = _tabFeatures[index];
    if (feature != null && !hasPrepAccess(ref)) {
      // The tabs stay on the current one while access is asked for.
      setState(() {});
      if (!await ensurePrepAccess(context, feature: feature)) return;
      if (!mounted || index == _tab) return;
    }
    setState(() {
      _tab = index;
      if (index == 1) _cue = false;
    });
    // Another tab opens with its header in place.
    _chrome.show();
    _pages.springTo(index, context: context);
  }

  /// Opening a profile brings stale games and the sources' details up to
  /// date in the background.
  void _checkFreshness(PrepProfile profile) {
    if (_checkedFreshness) return;
    _checkedFreshness = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Ratings, titles and photos as the sources have them today.
      prepReadDetails(ref, profile);
      final added = widget.newGames;
      if (added == null || added < 1) {
        ref.read(prepSyncProvider.notifier).refreshStale([profile]);
        return;
      }
      showAppSnack(
        context,
        added == 1
            ? '${profile.name} played 1 new game.'
            : '${profile.name} played $added new games.',
      );
      unawaited(_fetchNewGames(profile));
    });
  }

  /// The push's games are newer than a daily freshness rule would fetch:
  /// every downloaded online source checks now, one after another.
  Future<void> _fetchNewGames(PrepProfile profile) async {
    final sync = ref.read(prepSyncProvider.notifier);
    for (final account in profile.accounts) {
      if (!account.source.online || account.lastSyncAtMs == null) continue;
      if (!mounted) return;
      await sync.syncAccount(profile.id, account, background: true);
    }
  }

  /// [filter] is About's own. While another source's games are read there
  /// is nothing yet to choose among, so the ratings wait as the statistics
  /// do.
  Widget _identity(
    PrepProfile profile,
    PrepFilter filter, {
    required bool waiting,
  }) => PrepIdentity(
    profile: profile,
    accountKey: _account,
    gameRatings: _gameRatingsOf(_shown?.games ?? const []),
    fideId: kPrepFavorites
        .where((f) => f.id == profile.favoriteId)
        .firstOrNull
        ?.fideId,
    chosen: filter.speed,
    onRating: waiting ? null : (speed) => _choose(filter.toggleSpeed(speed)),
  );

  /// About for the source being read. Its identity and heading are there in
  /// every state, and statistics give way only to other statistics: while a
  /// newly chosen source's games are read, the ones on screen wait faint
  /// under a heading that says so.
  Widget _about(
    PrepProfile profile,
    PrepAccount? account,
    AutoDisposeFutureProvider<PrepAnalysis> provider,
    int? indexing, {
    required bool unlocked,
  }) {
    final analysis = ref.watch(provider);
    // A refresh keeps what it had on screen; only a first read waits.
    final reading =
        analysis.isLoading && !analysis.isRefreshing && !analysis.isReloading;
    final failed = !reading && analysis.hasError;
    final fresh = reading || failed ? null : analysis.requireValue;
    var arriving = false;
    if (fresh != null && fresh.games.isNotEmpty) {
      final key = account?.key ?? '';
      arriving = _shown != null && _shownKey != key;
      _shown = fresh;
      _shownKey = key;
    } else if (!reading) {
      // Nothing to show, or a failure: neither is kept for the next source.
      _shown = null;
      _shownKey = null;
    }
    final shown = _shown;
    final stale = reading && shown != null;
    // Read together, the sources' rating figures follow the one whose
    // ratings head the page: the database player's, else the first source's.
    final main = profile.databaseAccount ?? profile.accounts.firstOrNull;
    final progress = indexing == null
        ? 'Reading games…'
        : 'Indexing games · $indexing%';
    // What About narrows to stays within the source its statistics are
    // from, and so does what Games then lists.
    final filter = _aboutWithin(
      profile.accounts.where((a) => a.key == _shownKey).firstOrNull,
    );
    final stats = shown == null
        ? null
        : _statsOf(
            shown.games,
            filter,
            rating: main == null ? null : PrepRepository.gamesFileName(main),
          );
    _matching = stats?.matching ?? 0;
    return PrepOverviewTab(
      profile: profile,
      stats: stats,
      total: shown?.games.length,
      stale: stale,
      arriving: arriving,
      filter: filter,
      header: _identity(profile, filter, waiting: stale),
      // With one source there is nothing to switch, so only statistics
      // carry a heading.
      heading: shown == null && profile.accounts.length < 2
          ? null
          : PrepPerformanceHeader(
              profile: profile,
              accountKey: _account,
              progress: stale ? progress : null,
              onAccount: (key) => setState(() => _chooseAccount(profile, key)),
              onSources: () => PrepSourcesScreen.open(context, profile.id),
            ),
      message: reading
          ? Padding(
              padding: EdgeInsets.symmetric(vertical: 24.h),
              child: PrepMessage(
                title: progress,
                body: 'Your downloaded games are being indexed.',
                busy: true,
              ),
            )
          : failed
          ? PrepMessage(
              title: 'Could not read these games',
              body: 'Try reading the downloaded games again.',
              actionLabel: 'Retry',
              onAction: () => ref.invalidate(provider),
            )
          : Padding(
              padding: EdgeInsets.only(top: 24.h),
              child: _NoGames(profile: profile, account: account),
            ),
      onSources: () => PrepSourcesScreen.open(context, profile.id),
      onFilterChanged: _choose,
      onUnlockDetails: _unlockStatistics(unlocked),
    );
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(prepProfileProvider(widget.profileId));
    if (profile == null) {
      // Removed from its own menu: leave once this frame settles.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
      });
      return Scaffold(backgroundColor: context.colors.background);
    }
    _checkFreshness(profile);
    if (!_openedOnAccount) {
      _openedOnAccount = true;
      _chooseAccount(profile, widget.accountKey);
    }
    if (_filter.accountKey != null &&
        !profile.accounts.any((a) => a.key == _filter.accountKey)) {
      _filter = _filter.copyWith(
        accountKey: null,
        accountFile: null,
        source: null,
      );
    } else if (_filter.source != null &&
        !profile.accounts.any((a) => a.source == _filter.source)) {
      _filter = _filter.copyWith(source: null);
    }
    // A detached source, or the last one left, reads as every source again.
    final account = profile.accounts.length < 2
        ? null
        : profile.accounts.where((a) => a.key == _account).firstOrNull;
    _account = account?.key;
    AutoDisposeFutureProvider<PrepAnalysis> analysisOf(String? accountKey) =>
        accountKey == null
        ? prepAnalysisProvider(profile.id)
        : prepSourceAnalysisProvider((
            profileId: profile.id,
            accountKey: accountKey,
          ));
    // A source's own index reports its progress under its own scope.
    int? indexingOf(String? accountKey) {
      final source = profile.accounts
          .where((a) => a.key == accountKey)
          .firstOrNull;
      final scope = source == null
          ? profile.id
          : PrepIndex.accountScope(source);
      return ref.watch(gameTreeStatusProvider.select((s) => s[scope]?.percent));
    }

    final analysisProvider = analysisOf(_filter.accountKey);
    final analysis = ref.watch(analysisProvider);
    final indexing = indexingOf(_filter.accountKey);
    final games = analysis.valueOrNull?.games ?? const <PrepGame>[];
    final unlocked = ref.watch(premiumAccessProvider);
    // Built first: the Games tab names what About's choices come to.
    final about = _about(
      profile,
      account,
      analysisOf(account?.key),
      indexingOf(account?.key),
      unlocked: unlocked,
    );
    final cue = _cue && _tab != 1 && _filter.narrows && _matching > 0
        ? _matching
        : null;

    // A newly chosen source's games are being read for the first time (a
    // read the page has never had, not a refresh): Games keeps the list it
    // showed until they land.
    final held = analysis.isLoading && !analysis.hasValue && !analysis.hasError
        ? _listed
        : null;
    // Games lists the downloaded games (not a message): it has a search.
    final gamesListed =
        held != null ||
        (analysis.hasValue &&
            !analysis.hasError &&
            (games.isNotEmpty || _filter.isActive));
    // The games gave way to a message (a read failed, the last game
    // went): the search goes with them, back to the page. A source still
    // being read keeps it: its games are on their way.
    final gamesGone =
        analysis.hasError ||
        (analysis.hasValue && games.isEmpty && !_filter.isActive);
    if (_search.isSearching && (_tab != 1 || gamesGone)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _search.close();
      });
    }

    final bars = SizedBox(
      width: double.infinity,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _TopBar(
            profile: profile,
            // On Games the menu also acts on the games it shows; their
            // count, filters and layout are on the list's own line.
            games: _tab == 1 ? _gamesController : null,
            onSources: () => PrepSourcesScreen.open(context, profile.id),
          ),
          SizedBox(height: 8.h),
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: ResponsiveHelper.adaptive(
                phone: 20.sp,
                tablet: 32.sp,
              ),
            ),
            child: SegmentedSwitcher(
              dotScope: 'prep_profile.tab',
              height: prepSegmentHeight(context, wrapLabels: true),
              backgroundColor: context.colors.popup,
              selectedBackgroundColor: context.colors.popup,
              options: _tabs,
              optionLabels: [
                for (final (i, tab) in _tabs.indexed)
                  Text(
                    i == 1 && cue != null
                        ? '$tab ${formatCompactCount(cue)}'
                        : tab,
                    maxLines: 2,
                    textAlign: TextAlign.center,
                  ),
              ],
              initialSelection: _tab,
              currentSelection: _tab,
              onSelectionChanged: _select,
              notifyOnReselect: true,
            ),
          ),
          SizedBox(height: SearchHeaderMetrics.bottomGap),
        ],
      ),
    );
    // The list's board view and Filters, as every Games search header ends;
    // its line under the header keeps the count.
    final search = SearchModeHeader(
      hintText: 'Search games',
      textFieldKey: const ValueKey('prep_games_search'),
      closeKey: const ValueKey('prep_search_close'),
      trailing: [
        PrepGamesSearchControls(
          filterCount: _filter.activeCount,
          games: _gamesController,
        ),
      ],
    );

    // The one Games list, whichever read it shows: the same widget in every
    // state that lists games, so its folds and place survive a source
    // switch. [shown] is the list still on screen while another read runs;
    // without it the list is the read's own games, filtered. Listed when
    // Games is built, not for every choice made on About before it is
    // opened.
    Widget gamesList(
      PrepAnalysis data, {
      ({PrepAnalysis analysis, List<PrepGame> games})? shown,
    }) => Builder(
      builder: (context) {
        final listed = shown ?? (analysis: data, games: _filtered(data.games));
        _listed = listed;
        return PrepGamesTab(
          profile: profile,
          analysis: listed.analysis,
          games: listed.games,
          filter: _filter,
          controller: _gamesController,
          busy: shown != null,
          // Typed in the search header.
          search: _query,
          onClearSearch: _search.text.clear,
          filterButtonKey: const ValueKey('prep_games_filters'),
          onFilterChanged: (f) => setState(() => _filter = f),
        );
      },
    );
    final Widget gamesPage = held != null
        ? gamesList(held.analysis, shown: held)
        : analysis.when(
            skipLoadingOnReload: true,
            loading: () => PrepMessage(
              title: indexing == null
                  ? 'Reading games…'
                  : 'Indexing games · $indexing%',
              body: 'Your downloaded games are being indexed.',
              busy: true,
            ),
            error: (_, _) {
              // Nothing is kept for the next read once a read fails.
              _listed = null;
              return PrepMessage(
                title: 'Could not read games',
                body: 'Try reading the downloaded games again.',
                actionLabel: 'Retry',
                onAction: () => ref.invalidate(analysisProvider),
              );
            },
            data: (data) {
              if (data.games.isEmpty && !_filter.isActive) {
                _listed = null;
                return _NoGames(profile: profile);
              }
              return gamesList(data);
            },
          );

    return SearchModeHost(
      controller: _search,
      chrome: _chrome,
      // The list narrows on the phone as each letter is typed.
      debounce: Duration.zero,
      onChanged: (query) => _query.value = query,
      child: Scaffold(
        backgroundColor: context.colors.background,
        // Kept while searching: the search's glass flies back into it.
        floatingActionButton: SlidingFabs(
          controller: _chrome,
          child: _tab == 1 && (gamesListed || _search.isSearching)
              // The list's line counts its filters, and it is in view
              // whenever this button is (both come back as the list scrolls
              // up); while searching the search header's Filters count them.
              // So the button carries no count.
              ? const InkFabStack(
                  children: [
                    SearchInkFab(
                      key: ValueKey('prep_search_fab'),
                      label: 'Search games',
                    ),
                  ],
                )
              : const SizedBox.shrink(),
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: ResponsiveHelper.contentMaxWidth,
            ),
            child: Column(
              children: [
                // The status bar's inset stays put: the bars fold up to it,
                // never into it.
                SizedBox(height: MediaQuery.viewPaddingOf(context).top + 4.h),
                CollapsingChrome(
                  controller: _chrome,
                  child: SearchModeHeaderSlot(header: bars, search: search),
                ),
                Expanded(
                  child: ScrollChromeRegion(
                    controller: _chrome,
                    child: Stack(
                      children: [
                        ListenableBuilder(
                          listenable: _search,
                          builder: (context, _) => PageView(
                            controller: _pages,
                            // Without access the tabs ask before Games or
                            // Build Tree opens, so a swipe cannot slide one
                            // in; searching holds Games, whose search it is.
                            physics: _search.pagePhysics(
                              unlocked
                                  ? null
                                  : const NeverScrollableScrollPhysics(),
                            ),
                            onPageChanged: (i) {
                              if (i == _tab) return;
                              _chrome.show();
                              setState(() {
                                _tab = i;
                                if (i == 1) _cue = false;
                              });
                            },
                            children: [
                              about,
                              gamesPage,
                              PrepTreesTab(
                                profile: profile,
                                onSources: () =>
                                    PrepSourcesScreen.open(context, profile.id),
                              ),
                            ],
                          ),
                        ),
                        // Over the pages' top edge, so it takes no room of
                        // its own under the tabs.
                        // While Games holds its list for another source's
                        // read, the quiet line in its place says so instead.
                        Positioned(
                          top: 0,
                          left: 0,
                          right: 0,
                          child: _FilterLine(
                            active:
                                _filter.narrows && (held == null || _tab != 1),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The line a player's profile draws under its tabs while a filter is on.
class _FilterLine extends StatelessWidget {
  const _FilterLine({required this.active});
  final bool active;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: ExcludeSemantics(
      child: RepaintBoundary(
        child: SizedBox(
          height: 2.h,
          child: SingleMotionBuilder(
            motion: const CupertinoMotion.snappy(),
            value: active ? 1.0 : 0.0,
            active: !MediaQuery.disableAnimationsOf(context),
            builder: (context, shown, _) {
              if (shown < 0.01) return const SizedBox.shrink();
              final t = shown.clamp(0.0, 1.0);
              return Align(
                alignment: Alignment.topCenter,
                child: Container(
                  height: 2.h * t,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        kPrimaryColor.withValues(alpha: 0.0),
                        kPrimaryColor.withValues(alpha: 0.8 * t),
                        kPrimaryColor.withValues(alpha: 0.8 * t),
                        kPrimaryColor.withValues(alpha: 0.0),
                      ],
                      stops: const [0.0, 0.2, 0.8, 1.0],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    ),
  );
}

class _TopBar extends ConsumerWidget {
  const _TopBar({required this.profile, required this.onSources, this.games});
  final PrepProfile profile;
  final VoidCallback onSources;
  final PrepGamesController? games;

  /// The menu's square target.
  static const double _menuTarget = 44;

  /// The flag, the title in its accent and the name, as one line.
  Widget _identity(BuildContext context, AppColors colors) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      PrepFlag(country: profile.country),
      Flexible(
        child: Text.rich(
          TextSpan(
            children: [
              if (profile.title case final title?)
                TextSpan(
                  text: '$title ',
                  style: PageTitle.style(
                    context,
                  ).copyWith(color: colors.titleAccent),
                ),
              TextSpan(text: profile.name, style: PageTitle.style(context)),
            ],
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    ],
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    // The menu's glyph ends on the gutter, as a search header's last glyph
    // does; the chevron sits where the search header's does.
    final end = math.max(
      0.0,
      SearchHeaderMetrics.gutter - SearchHeaderMetrics.trailingReach,
    );
    final ends = end + kPrepWatchStarSlot + _menuTarget;
    final starts =
        SearchHeaderMetrics.leadingInset + SearchHeaderMetrics.backTarget;
    return Padding(
      padding: EdgeInsetsDirectional.only(
        start: SearchHeaderMetrics.leadingInset,
        end: end,
      ),
      child: Row(
        children: [
          const PageBackButton(),
          // Balances the star and the menu on the right, so the name stays
          // centred on the screen.
          SizedBox(width: math.max(0.0, ends - starts)),
          // Named as every pushed page is ([PageTitle]): the one title
          // voice, a heading, its words growing no further than the bar's.
          Expanded(
            child: Center(
              child: MediaQuery.withClampedTextScaling(
                maxScaleFactor: HomeTopBarMetrics.maxTextScale,
                child: Semantics(
                  header: true,
                  child: _identity(context, colors),
                ),
              ),
            ),
          ),
          PrepWatchStar(profileId: profile.id),
          CardMoreButton(
            vertical: true,
            color: colors.iconPrimary,
            actions: (_) => [
              ...prepGamesMenu(games),
              LibraryMenuAction(
                icon: Icons.tune_rounded,
                label: 'Manage sources',
                onSelected: onSources,
              ),
              ...prepProfileMenu(context, ref, profile),
            ],
          ),
        ],
      ),
    );
  }
}

class _NoGames extends ConsumerWidget {
  const _NoGames({required this.profile, this.account});
  final PrepProfile profile;

  /// The one source being read, when it is not all of them.
  final PrepAccount? account;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accounts = account == null ? profile.accounts : [account!];
    final syncing = ref.watch(
      prepSyncProvider.select((s) => accounts.any((a) => s.containsKey(a.key))),
    );
    final error = accounts.map((a) => a.error).whereType<String>().firstOrNull;
    if (syncing) {
      return const PrepMessage(
        title: 'Downloading games',
        body:
            'The first download of a large account can take a few minutes. '
            'You can leave this screen; it keeps going.',
        busy: true,
      );
    }
    return PrepMessage(
      title: error == null ? 'No games yet' : 'Download failed',
      body:
          error ??
          (profile.accounts.isEmpty
              ? 'Start with ChessEver, Lichess or Chess.com. Attach the other sources whenever you like.'
              : 'Download games from your sources, or choose a longer period in download options.'),
      actionLabel: 'Manage sources',
      onAction: () => PrepSourcesScreen.open(context, profile.id),
    );
  }
}

/// A centred message for empty, loading and failed states.
class PrepMessage extends StatelessWidget {
  const PrepMessage({
    super.key,
    required this.title,
    required this.body,
    this.busy = false,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String body;
  final bool busy;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 32.w),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (busy) ...[
              GenericLoadingWidget(size: 32.w),
              SizedBox(height: 16.h),
            ],
            Text(
              title,
              textAlign: TextAlign.center,
              style: AppTypography.textMdBold.copyWith(
                color: colors.textPrimary,
                fontFeatures: busy
                    ? const [FontFeature.tabularFigures()]
                    : null,
              ),
            ),
            SizedBox(height: 6.h),
            Text(
              body,
              textAlign: TextAlign.center,
              style: AppTypography.textSmRegular.copyWith(
                color: colors.textSecondary,
                height: 20 / 14,
              ),
            ),
            if (actionLabel != null) ...[
              SizedBox(height: 16.h),
              TextButton(
                onPressed: onAction,
                child: Text(
                  actionLabel!,
                  style: AppTypography.textSmBold.copyWith(
                    color: colors.accentText,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
