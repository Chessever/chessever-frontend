import 'dart:async';

import 'package:chessever2/screens/my_prep/data/prep_favorites.dart';
import 'package:chessever2/screens/my_prep/models/prep_models.dart';
import 'package:chessever2/screens/my_prep/prep_access.dart';
import 'package:chessever2/screens/my_prep/prep_actions.dart';
import 'package:chessever2/screens/my_prep/providers/prep_providers.dart';
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
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/card_context_menu.dart';
import 'package:chessever2/widgets/segmented_switcher.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// One prepared person: Overview, Games and Openings, read from every
/// account they have, with the filters shared across the three tabs.
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
  PrepFilter _filter = const PrepFilter();
  bool _checkedFreshness = false;

  // A large account is tens of thousands of games: filter and score them
  // once per change, not on every rebuild a sync's progress line causes.
  List<PrepGame>? _filterInput;
  PrepFilter? _filterUsed;
  List<PrepGame> _filterOutput = const [];
  List<PrepGame>? _statsInput;
  PrepStats? _stats;

  List<PrepGame> _filtered(List<PrepGame> games) {
    if (!identical(games, _filterInput) || _filterUsed != _filter) {
      _filterInput = games;
      _filterUsed = _filter;
      _filterOutput = _filter.apply(games);
    }
    return _filterOutput;
  }

  PrepStats _statsOf(List<PrepGame> games) {
    if (!identical(games, _statsInput) || _stats == null) {
      _statsInput = games;
      _stats = PrepStats.of(games);
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
    source: _filter.source,
    accountKey: _filter.accountKey,
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
    final selectedAccount = profile.accounts
        .where((a) => a.key == _filter.accountKey)
        .firstOrNull;
    final scope = selectedAccount == null
        ? profile.id
        : PrepIndex.accountScope(selectedAccount);
    final indexing = ref.watch(
      gameTreeStatusProvider.select((s) => s[scope]?.percent),
    );
    final games = analysis.valueOrNull?.games ?? const <PrepGame>[];
    final filtered = _filtered(games);
    final gutter = ResponsiveHelper.adaptive(phone: 16.w, tablet: 24.w);

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
              _TopBar(profile: profile),
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
              _SourcesRow(profile: profile),
              if (_tab != 2)
                PrepFilterBar(
                  games: games,
                  profile: profile,
                  filter: _filter,
                  onChanged: (f) => setState(() => _filter = f),
                ),
              Expanded(
                child: PageView(
                  controller: _pages,
                  onPageChanged: (i) {
                    if (i != _tab) setState(() => _tab = i);
                  },
                  children: [
                    analysis.when(
                      skipLoadingOnReload: true,
                      loading: () => ListView(
                        children: [
                          _identity(profile),
                          Padding(
                            padding: EdgeInsets.all(gutter),
                            child: Text(
                              indexing == null
                                  ? 'Reading games…'
                                  : 'Indexing games · $indexing%',
                              style: AppTypography.textSmRegular.copyWith(
                                color: context.colors.textSecondary,
                              ),
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
                            onAction: () => ref.invalidate(analysisProvider),
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
                              stats: _statsOf(filtered),
                              filter: _filter,
                              header: _identity(profile, inset: false),
                              onOpenGames: (filter) {
                                setState(() => _filter = filter);
                                _select(1);
                              },
                            ),
                    ),
                    analysis.when(
                      skipLoadingOnReload: true,
                      loading: () => const PrepMessage(
                        title: 'Reading games…',
                        body: 'Your downloaded games are being indexed.',
                        busy: true,
                      ),
                      error: (_, _) => PrepMessage(
                        title: 'Could not read games',
                        body: 'Try reading the downloaded games again.',
                        actionLabel: 'Retry',
                        onAction: () => ref.invalidate(analysisProvider),
                      ),
                      data: (data) => data.games.isEmpty
                          ? _NoGames(profile: profile)
                          : PrepGamesTab(
                              analysis: data,
                              games: filtered,
                              filter: _filter,
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
  const _TopBar({required this.profile});
  final PrepProfile profile;

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
            actions: (_) => prepProfileMenu(context, ref, profile),
          ),
        ],
      ),
    );
  }
}

class _SourcesRow extends ConsumerWidget {
  const _SourcesRow({required this.profile});
  final PrepProfile profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statuses = ref.watch(prepSyncProvider);
    final downloading = profile.accounts.any(
      (a) => statuses.containsKey(a.key),
    );
    final sources = profile.accounts.map((a) => a.source).toSet();
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.adaptive(phone: 20.sp, tablet: 32.sp),
      ),
      child: Row(
        children: [
          PrepSourceMarks(sources: sources, size: 16.sp),
          if (sources.isNotEmpty) SizedBox(width: 8.w),
          Expanded(
            child: Text(
              downloading
                  ? 'Downloading games…'
                  : sources.isEmpty
                  ? 'No sources attached'
                  : '${sources.length} ${sources.length == 1 ? 'source' : 'sources'}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.textXsRegular.copyWith(
                color: context.colors.textSecondary,
              ),
            ),
          ),
          TextButton(
            key: const ValueKey('prep_manage_sources'),
            onPressed: () => PrepSourcesScreen.open(context, profile.id),
            child: Text(
              'Sources',
              style: AppTypography.textSmMedium.copyWith(
                color: context.colors.textPrimary,
              ),
            ),
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
              SizedBox.square(
                dimension: 22.sp,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: colors.textSecondary,
                ),
              ),
              SizedBox(height: 16.h),
            ],
            Text(
              title,
              textAlign: TextAlign.center,
              style: AppTypography.textMdBold.copyWith(
                color: colors.textPrimary,
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
