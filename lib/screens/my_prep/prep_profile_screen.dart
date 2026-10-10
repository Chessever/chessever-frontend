import 'dart:async';

import 'package:chessever2/screens/my_prep/data/prep_favorites.dart';
import 'package:chessever2/screens/my_prep/models/prep_models.dart';
import 'package:chessever2/screens/my_prep/prep_access.dart';
import 'package:chessever2/screens/my_prep/prep_actions.dart';
import 'package:chessever2/screens/my_prep/providers/prep_providers.dart';
import 'package:chessever2/screens/my_prep/services/prep_analysis.dart';
import 'package:chessever2/screens/my_prep/services/prep_repository.dart';
import 'package:chessever2/screens/my_prep/tabs/prep_games_tab.dart';
import 'package:chessever2/screens/my_prep/tabs/prep_trees_tab.dart';
import 'package:chessever2/screens/my_prep/prep_sources_screen.dart';
import 'package:chessever2/screens/my_prep/widgets/prep_identity.dart';
import 'package:chessever2/screens/my_prep/tabs/prep_overview_tab.dart';
import 'package:chessever2/screens/my_prep/widgets/prep_common.dart';
import 'package:chessever2/screens/my_prep/widgets/prep_filters.dart';
import 'package:chessever2/services/game_tree/game_tree_service.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/card_context_menu.dart';
import 'package:chessever2/widgets/generic_loading_widget.dart';
import 'package:chessever2/widgets/segmented_switcher.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// One prepared person: combined About, filterable Games and source trees.
class PrepProfileScreen extends ConsumerStatefulWidget {
  const PrepProfileScreen({super.key, required this.profileId});

  final String profileId;

  static Future<void> open(BuildContext context, String profileId) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PrepProfileScreen(profileId: profileId),
      ),
    );
  }

  @override
  ConsumerState<PrepProfileScreen> createState() => _PrepProfileScreenState();
}

class _PrepProfileScreenState extends ConsumerState<PrepProfileScreen> {
  static const _tabs = ['About', 'Games', 'Build Tree'];
  int _tab = 0;
  late final PageController _pages = PageController();
  final _gamesController = PrepGamesController();
  PrepFilter _filter = const PrepFilter();
  bool _checkedFreshness = false;

  // A large account is tens of thousands of games: filter and score them
  // once per change, not on every rebuild a sync's progress line causes.
  List<PrepGame>? _filterInput;
  PrepFilter? _filterUsed;
  List<PrepGame> _filterOutput = const [];
  List<PrepGame>? _statsInput;
  PrepStats? _stats;
  bool? _statsOnline;

  List<PrepGame> _filtered(List<PrepGame> games) {
    if (!identical(games, _filterInput) || _filterUsed != _filter) {
      _filterInput = games;
      _filterUsed = _filter;
      _filterOutput = _filter.apply(games);
    }
    return _filterOutput;
  }

  PrepStats _statsOf(List<PrepGame> games, PrepProfile profile) {
    final online = profile.accounts.any((a) => a.source.online);
    if (!identical(games, _statsInput) ||
        _statsOnline != online ||
        _stats == null) {
      _statsInput = games;
      _statsOnline = online;
      // The rating history follows the ladder desktop prefers: blitz for an
      // online player, classical for an over-the-board one.
      _stats = PrepStats.of(
        games,
        preferredRating: online
            ? PrepTimeControl.blitz
            : PrepTimeControl.classical,
      );
    }
    return _stats!;
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _select(int index) {
    if (index == _tab) return;
    setState(() => _tab = index);
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
      if (!mounted || !hasPrepAccess(ref)) return;
      ref.read(prepSyncProvider.notifier).refreshStale([profile]);
    });
  }

  Widget _identity(PrepProfile profile, {bool inset = true}) => PrepIdentity(
    profile: profile,
    inset: inset,
    fideId: kPrepFavorites
        .where((f) => f.id == profile.favoriteId)
        .firstOrNull
        ?.fideId,
    onRating: (account, speed) {
      setState(
        () => _filter = PrepFilter(
          source: account.source,
          speed: speed,
          accountKey: account.key,
          accountFile: PrepRepository.gamesFileName(account),
        ),
      );
      _select(1);
    },
  );

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
    final analysisProvider = _filter.accountKey == null
        ? prepAnalysisProvider(profile.id)
        : prepSourceAnalysisProvider((
            profileId: profile.id,
            accountKey: _filter.accountKey,
          ));
    final analysis = ref.watch(analysisProvider);
    final overviewAnalysis = ref.watch(prepAnalysisProvider(profile.id));
    final indexing = ref.watch(
      gameTreeStatusProvider.select((s) => s[profile.id]?.percent),
    );
    final games = analysis.valueOrNull?.games ?? const <PrepGame>[];
    final filtered = _filtered(games);

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
                  height: prepSegmentHeight(context, wrapLabels: true),
                  backgroundColor: context.colors.popup,
                  selectedBackgroundColor: context.colors.popup,
                  options: _tabs,
                  optionLabels: [
                    for (final tab in _tabs)
                      Text(tab, maxLines: 2, textAlign: TextAlign.center),
                  ],
                  initialSelection: _tab,
                  currentSelection: _tab,
                  onSelectionChanged: _select,
                ),
              ),
              Expanded(
                child: PageView(
                  controller: _pages,
                  onPageChanged: (i) {
                    if (i != _tab) setState(() => _tab = i);
                  },
                  children: [
                    overviewAnalysis.when(
                      skipLoadingOnReload: true,
                      loading: () => ListView(
                        children: [
                          _identity(profile),
                          Padding(
                            padding: EdgeInsets.symmetric(vertical: 24.h),
                            child: PrepMessage(
                              title: indexing == null
                                  ? 'Reading games…'
                                  : 'Indexing games · $indexing%',
                              body: 'Your downloaded games are being indexed.',
                              busy: true,
                            ),
                          ),
                        ],
                      ),
                      error: (error, _) => ListView(
                        children: [
                          _identity(profile),
                          PrepMessage(
                            title: 'Could not read these games',
                            body: 'Try reading the downloaded games again.',
                            actionLabel: 'Retry',
                            onAction: () => ref.invalidate(
                              prepAnalysisProvider(profile.id),
                            ),
                          ),
                        ],
                      ),
                      data: (data) => data.games.isEmpty
                          ? ListView(
                              children: [
                                _identity(profile),
                                SizedBox(height: 24.h),
                                _NoGames(profile: profile),
                              ],
                            )
                          : PrepOverviewTab(
                              profile: profile,
                              stats: _statsOf(data.games, profile),
                              filter: const PrepFilter(),
                              header: _identity(profile, inset: false),
                              onSources: () =>
                                  PrepSourcesScreen.open(context, profile.id),
                              onOpenGames: (filter) {
                                setState(() => _filter = filter);
                                _select(1);
                              },
                            ),
                    ),
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
                      data: (data) => data.games.isEmpty && !_filter.isActive
                          ? _NoGames(profile: profile)
                          : PrepGamesTab(
                              profile: profile,
                              analysis: data,
                              games: filtered,
                              filter: _filter,
                              controller: _gamesController,
                              onFilterChanged: (f) =>
                                  setState(() => _filter = f),
                            ),
                    ),
                    PrepTreesTab(
                      profile: profile,
                      onSources: () =>
                          PrepSourcesScreen.open(context, profile.id),
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

class _TopBar extends ConsumerWidget {
  const _TopBar({required this.profile, this.games});
  final PrepProfile profile;
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
              ...prepProfileMenu(context, ref, profile),
            ],
          ),
        ],
      ),
    );
  }
}

class _NoGames extends ConsumerWidget {
  const _NoGames({required this.profile});
  final PrepProfile profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final syncing = ref.watch(
      prepSyncProvider.select(
        (s) => profile.accounts.any((a) => s.containsKey(a.key)),
      ),
    );
    final error = profile.accounts
        .map((a) => a.error)
        .whereType<String>()
        .firstOrNull;
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
