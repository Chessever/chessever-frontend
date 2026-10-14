import 'dart:async';

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
import 'package:chessever2/widgets/card_context_menu.dart';
import 'package:chessever2/widgets/generic_loading_widget.dart';
import 'package:chessever2/widgets/segmented_switcher.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:motor/motor.dart';

/// One prepared person: About and Games over every source together or one
/// source alone, and the source trees.
class PrepProfileScreen extends ConsumerStatefulWidget {
  const PrepProfileScreen({
    super.key,
    required this.profileId,
    this.accountKey,
  });

  final String profileId;

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

class _PrepProfileScreenState extends ConsumerState<PrepProfileScreen> {
  static const _tabs = ['About', 'Games', 'Build Tree'];

  /// What each tab asks Premium or a watched ad for. About's summary is
  /// free; its statistics open with [_kStatistics].
  static const _tabFeatures = [null, 'prep_games', 'build_tree'];
  static const _kStatistics = 'prep_statistics';
  int _tab = 0;
  late final PageController _pages = PageController();
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

  Future<void> _select(int index) async {
    if (index == _tab) return;
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
    if (MediaQuery.disableAnimationsOf(context)) {
      _pages.jumpToPage(index);
      return;
    }
    _pages.animateToPage(
      index,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  /// Opening a profile brings stale games up to date in the background.
  void _checkFreshness(PrepProfile profile) {
    if (_checkedFreshness) return;
    _checkedFreshness = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(prepSyncProvider.notifier).refreshStale([profile]);
    });
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

    return Scaffold(
      backgroundColor: context.colors.background,
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: ResponsiveHelper.contentMaxWidth,
          ),
          child: Column(
            children: [
              SizedBox(height: MediaQuery.of(context).viewPadding.top + 4.h),
              _TopBar(
                profile: profile,
                // On Games the menu also acts on the games it shows.
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
                ),
              ),
              Expanded(
                child: Stack(
                  children: [
                    PageView(
                      controller: _pages,
                      // Without access the tabs ask before Games or Build
                      // Tree opens, so a swipe cannot slide one in.
                      physics: unlocked
                          ? null
                          : const NeverScrollableScrollPhysics(),
                      onPageChanged: (i) {
                        if (i == _tab) return;
                        setState(() {
                          _tab = i;
                          if (i == 1) _cue = false;
                        });
                      },
                      children: [
                        about,
                        analysis.when(
                          skipLoadingOnReload: true,
                          loading: () => PrepMessage(
                            title: indexing == null
                                ? 'Reading games…'
                                : 'Indexing games · $indexing%',
                            body: 'Your downloaded games are being indexed.',
                            busy: true,
                          ),
                          error: (_, _) => PrepMessage(
                            title: 'Could not read games',
                            body: 'Try reading the downloaded games again.',
                            actionLabel: 'Retry',
                            onAction: () => ref.invalidate(analysisProvider),
                          ),
                          data: (data) =>
                              data.games.isEmpty && !_filter.isActive
                              ? _NoGames(profile: profile)
                              // Listed when Games is built, not for every
                              // choice made on About before it is opened.
                              : Builder(
                                  builder: (context) => PrepGamesTab(
                                    profile: profile,
                                    analysis: data,
                                    games: _filtered(games),
                                    filter: _filter,
                                    controller: _gamesController,
                                    onFilterChanged: (f) =>
                                        setState(() => _filter = f),
                                  ),
                                ),
                        ),
                        PrepTreesTab(
                          profile: profile,
                          onSources: () =>
                              PrepSourcesScreen.open(context, profile.id),
                        ),
                      ],
                    ),
                    // Over the pages' top edge, so it takes no room of its
                    // own under the tabs.
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: _FilterLine(active: _filter.narrows),
                    ),
                  ],
                ),
              ),
            ],
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.adaptive(phone: 16.w, tablet: 24.w),
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Back',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 44, height: 44),
            onPressed: () => Navigator.of(context).pop(),
            icon: Icon(
              Icons.arrow_back_ios_new_outlined,
              size: 24.ic,
              color: colors.textPrimary,
            ),
          ),
          Expanded(
            child: Center(
              child: Row(
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
                              style: AppTypography.textMdBold.copyWith(
                                color: colors.titleAccent,
                              ),
                            ),
                          TextSpan(
                            text: profile.name,
                            style: AppTypography.textMdBold.copyWith(
                              color: colors.textPrimary,
                            ),
                          ),
                        ],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
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
