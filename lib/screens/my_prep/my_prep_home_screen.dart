import 'package:chessever2/repository/supabase/chess_player/chess_player_repository.dart'
    show ChessPlayer;
import 'package:chessever2/screens/my_prep/data/prep_favorites.dart';
import 'package:chessever2/screens/my_prep/models/prep_models.dart';
import 'package:chessever2/screens/my_prep/prep_access.dart';
import 'package:chessever2/screens/my_prep/prep_actions.dart';
import 'package:chessever2/screens/my_prep/prep_profile_screen.dart';
import 'package:chessever2/screens/my_prep/prep_sources_screen.dart';
import 'package:chessever2/screens/my_prep/providers/prep_favorites_provider.dart';
import 'package:chessever2/screens/my_prep/providers/prep_providers.dart';
import 'package:chessever2/screens/my_prep/widgets/prep_common.dart';
import 'package:chessever2/screens/my_prep/widgets/prep_profile_card.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/generic_loading_widget.dart';
import 'package:chessever2/widgets/popover_add_fab.dart';
import 'package:chessever2/widgets/segmented_switcher.dart';
import 'package:chessever2/widgets/skeleton_widget.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// My Prep: the reader's own games, the opponents they prepare for, and
/// players to study, with database, online and PGN sources.
class MyPrepHomeScreen extends ConsumerStatefulWidget {
  const MyPrepHomeScreen({super.key, this.initialTab = 0});

  final int initialTab;

  static const List<String> tabs = ['My games', 'Opponents', 'Favorites'];

  @override
  ConsumerState<MyPrepHomeScreen> createState() => _MyPrepHomeScreenState();
}

class _MyPrepHomeScreenState extends ConsumerState<MyPrepHomeScreen> {
  late int _tab = widget.initialTab.clamp(0, MyPrepHomeScreen.tabs.length - 1);
  late final PageController _pages = PageController(initialPage: _tab);
  bool _refreshedOnOpen = false;

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

  String get _addLabel => _tab == 0 ? 'Attach your username' : 'Add opponent';

  /// [source] is the one picked from the floating button's popover; the
  /// other adds leave the choice to the dialog.
  void _add([PrepSource? source]) {
    if (_tab == 0) {
      prepAddMine(context, ref, source: source);
    } else {
      prepAddOpponent(context, ref, source: source);
    }
  }

  /// Opening My Prep is when stale games are brought up to date: the
  /// reader's own every eight hours, opponents daily.
  void _refreshOnce(List<PrepProfile> profiles) {
    if (_refreshedOnOpen) return;
    _refreshedOnOpen = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !hasPrepAccess(ref)) return;
      ref
          .read(prepSyncProvider.notifier)
          .refreshStale(profiles.where((p) => p.kind != PrepKind.favorite));
    });
  }

  /// An empty tab asks for its first player in the page itself, so the
  /// floating button only joins once the reader has added one. Favorites is
  /// a fixed ranking with nothing to add, so it never has one.
  bool _hasAdd(List<PrepProfile> profiles) {
    final kind = switch (_tab) {
      0 => PrepKind.mine,
      1 => PrepKind.opponent,
      _ => null,
    };
    if (kind == null) return false;
    // My games lists sources, so a profile with none attached is empty.
    return profiles.any(
      (p) => p.kind == kind && (kind != PrepKind.mine || p.accounts.isNotEmpty),
    );
  }

  @override
  Widget build(BuildContext context) {
    final profiles = ref.watch(prepProfilesProvider).valueOrNull;
    if (profiles != null) _refreshOnce(profiles);
    final gutter = ResponsiveHelper.adaptive(phone: 20.sp, tablet: 32.sp);

    return Scaffold(
      backgroundColor: context.colors.background,
      floatingActionButton: profiles == null || !_hasAdd(profiles)
          ? null
          : PopoverAddFab<PrepSource>(
              key: const ValueKey('prep_add_floating'),
              label: _addLabel,
              choices: [
                for (final source in PrepSource.playerSources)
                  PopoverAddChoice(
                    leading: PrepSourceMark(source: source, size: 22),
                    label: source.label,
                    value: source,
                  ),
              ],
              onPicked: _add,
            ),
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: ResponsiveHelper.contentMaxWidth,
          ),
          child: Column(
            children: [
              SizedBox(height: MediaQuery.of(context).viewPadding.top + 4.h),
              const _AppBar(),
              SizedBox(height: 8.h),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: gutter),
                child: SegmentedSwitcher(
                  dotScope: 'prep.tab',
                  height: prepSegmentHeight(context),
                  options: MyPrepHomeScreen.tabs,
                  initialSelection: _tab,
                  currentSelection: _tab,
                  onSelectionChanged: _select,
                  notifyOnReselect: true,
                ),
              ),
              Expanded(
                child: PageView(
                  controller: _pages,
                  onPageChanged: (index) {
                    if (index != _tab) setState(() => _tab = index);
                  },
                  children: const [
                    _MyGamesTab(),
                    _OpponentsTab(),
                    _FavoritesTab(),
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

class _AppBar extends StatelessWidget {
  const _AppBar();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 16.w),
      child: Row(
        children: [
          IconButton(
            iconSize: 24.ic,
            padding: EdgeInsets.zero,
            tooltip: 'Back',
            onPressed: () => Navigator.of(context).pop(),
            icon: Icon(
              Icons.arrow_back_ios_new_outlined,
              size: 24.ic,
              color: context.colors.textPrimary,
            ),
          ),
          Expanded(
            child: Center(
              child: Text(
                'My Prep',
                style: AppTypography.textLgBold.copyWith(
                  color: context.colors.textPrimary,
                ),
              ),
            ),
          ),
          // Balances the back button so the title stays centred.
          const SizedBox(width: kMinInteractiveDimension),
        ],
      ),
    );
  }
}

double get _gutter => ResponsiveHelper.adaptive(phone: 16.w, tablet: 24.w);

// ------------------------------------------------------------------ my games

class _MyGamesTab extends ConsumerWidget {
  const _MyGamesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mine = ref.watch(prepProfilesOfKindProvider(PrepKind.mine));
    if (mine == null) return const _ListSkeleton();
    final profile = mine.firstOrNull;
    // A profile whose every source was detached asks again like a new one.
    if (profile == null || profile.accounts.isEmpty) {
      return _EmptyState(
        title: 'Attach your own usernames',
        body:
            'Add your Lichess and Chess.com accounts here. Their games stay together. You can also attach your ChessEver player record.',
        sources: PrepSource.playerSources,
        actionLabel: 'Attach your username',
        onAction: () => prepAddMine(context, ref),
      );
    }
    return RefreshIndicator(
      color: context.colors.textPrimary,
      backgroundColor: context.colors.surface,
      onRefresh: () => prepRefreshProfile(context, ref, profile.id),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        padding: EdgeInsets.only(
          top: 8.h,
          bottom: MediaQuery.viewPaddingOf(context).bottom + 96.h,
        ),
        children: [
          // My games is one person, so the tab lists their sources rather
          // than a player card.
          for (final source in PrepSource.values)
            for (final account in profile.accounts.where(
              (a) => a.source == source,
            ))
              Padding(
                padding: EdgeInsets.fromLTRB(_gutter, 0, _gutter, 8.h),
                child: Material(
                  color: context.colors.surface,
                  borderRadius: BorderRadius.circular(12.br),
                  clipBehavior: Clip.antiAlias,
                  child: PrepAccountRow(profile: profile, account: account),
                ),
              ),
          if (profile.gameCount > 0)
            Padding(
              padding: EdgeInsets.fromLTRB(_gutter, 8.h, _gutter, 0),
              child: FilledButton(
                key: const ValueKey('prep_mine_open'),
                onPressed: () {
                  HapticFeedbackService.cardTap();
                  PrepProfileScreen.open(context, profile.id);
                },
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  backgroundColor: context.colors.textPrimary,
                  foregroundColor: context.colors.textInverse,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12.br),
                  ),
                ),
                child: Text(
                  'Open ${prepGamesLabel(profile.gameCount)}',
                  style: AppTypography.textSmBold,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------ opponents

class _OpponentsTab extends ConsumerWidget {
  const _OpponentsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final opponents = ref.watch(prepProfilesOfKindProvider(PrepKind.opponent));
    if (opponents == null) return const _ListSkeleton();
    if (opponents.isEmpty) {
      return _EmptyState(
        title: 'Prepare for your next opponent',
        body:
            'Find them in ChessEver or start with a Lichess or Chess.com username. Attach all their sources to one profile.',
        sources: PrepSource.playerSources,
        actionLabel: 'Add opponent',
        onAction: () => prepAddOpponent(context, ref),
      );
    }
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      padding: EdgeInsets.only(
        top: 8.h,
        bottom: MediaQuery.viewPaddingOf(context).bottom + 96.h,
      ),
      itemCount: opponents.length,
      itemBuilder: (context, index) {
        final profile = opponents[index];
        return Padding(
          key: ValueKey(profile.id),
          padding: EdgeInsets.symmetric(horizontal: _gutter),
          child: PrepProfileCard(
            profile: profile,
            fideId: prepFavoriteFide(profile),
            onTap: () {
              HapticFeedbackService.cardTap();
              PrepProfileScreen.open(context, profile.id);
            },
          ),
        );
      },
    );
  }
}

// ------------------------------------------------------------------ favorites

class _FavoritesTab extends ConsumerStatefulWidget {
  const _FavoritesTab();

  @override
  ConsumerState<_FavoritesTab> createState() => _FavoritesTabState();
}

class _FavoritesTabState extends ConsumerState<_FavoritesTab> {
  final _search = TextEditingController();

  /// The player whose ChessEver source is being resolved for a first open.
  int? _opening;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _open(ChessPlayer player) async {
    if (_opening != null) return;
    setState(() => _opening = player.fideid);
    void resolved() {
      if (mounted && _opening != null) setState(() => _opening = null);
    }

    try {
      // The row stops reading "Opening…" once the add sheet covers it.
      await prepOpenFavorite(context, ref, player, onResolved: resolved);
    } finally {
      resolved();
    }
  }

  @override
  Widget build(BuildContext context) {
    final loaded = ref.watch(prepProfilesProvider).valueOrNull;
    final profiles = loaded ?? const <PrepProfile>[];
    final ranked = ref.watch(prepRankedPlayersProvider);
    final ranking = ref.read(prepRankedPlayersProvider.notifier);
    const lead = 1;
    final byFide = {
      for (final p in profiles)
        if (prepFavoriteFide(p) case final fide?) fide: p,
    };
    final query = _search.text.trim().toLowerCase();
    // Only a favorite with no FIDE player leads the list, since the ranking
    // cannot place it. Everyone else keeps their ranking slot, added or
    // not, so tapping a row never moves it.
    final custom = [
      for (final profile in profiles)
        if (profile.kind == PrepKind.favorite &&
            prepFavoriteFide(profile) == null &&
            (query.isEmpty ||
                profile.name.toLowerCase().contains(query) ||
                profile.accounts.any(
                  (a) => a.username.toLowerCase().contains(query),
                )))
          profile,
    ];
    final players = ranked.players;
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification.metrics.extentAfter < 600) ranking.loadMore();
        return false;
      },
      child: ListView.builder(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewPaddingOf(context).bottom + 96.h,
        ),
        itemCount: lead + custom.length + players.length + 1,
        itemBuilder: (context, index) {
          if (index == 0) {
            return Padding(
              padding: EdgeInsets.fromLTRB(_gutter, 16.h, _gutter, 12.h),
              child: _SearchField(
                controller: _search,
                onChanged: () {
                  setState(() {});
                  ranking.search(_search.text);
                },
              ),
            );
          }
          if (index < lead + custom.length) {
            final profile = custom[index - lead];
            return Padding(
              key: ValueKey(profile.id),
              padding: EdgeInsets.symmetric(horizontal: _gutter),
              child: PrepProfileCard(
                profile: profile,
                moreButton: false,
                onTap: () {
                  HapticFeedbackService.cardTap();
                  PrepProfileScreen.open(context, profile.id);
                },
              ),
            );
          }
          if (index == lead + custom.length + players.length) {
            return _RankingFooter(state: ranked, onRetry: ranking.retry);
          }
          final player = players[index - custom.length - lead];
          return Padding(
            key: ValueKey(player.fideid),
            padding: EdgeInsets.symmetric(horizontal: _gutter),
            child: _RankedCard(
              player: player,
              profile: byFide['${player.fideid}'],
              opening: _opening == player.fideid,
              onTap: () => _open(player),
            ),
          );
        },
      ),
    );
  }
}

/// A ranked player in their ranking slot: their own profile once added,
/// otherwise ChessEver plus the Lichess and Chess.com accounts known for
/// them. Both read alike, so adding a player changes only their status.
class _RankedCard extends StatelessWidget {
  const _RankedCard({
    required this.player,
    required this.opening,
    required this.onTap,
    this.profile,
  });
  final ChessPlayer player;
  final PrepProfile? profile;
  final bool opening;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fide = '${player.fideid}';
    final profile = this.profile;
    return PrepProfileCard(
      profile:
          profile ??
          PrepProfile(
            id: 'preview-$fide',
            kind: PrepKind.favorite,
            name: player.name,
            createdAtMs: 0,
            accounts: [
              PrepAccount(
                source: PrepSource.chessever,
                username: player.name,
                fideId: fide,
                title: player.title,
                country: player.country,
                ratings: {
                  if (player.rating case final rating?) 'classical': rating,
                },
              ),
              for (final (source, username)
                  in kPrepFavoritesByFide[fide]?.accounts ??
                      const <(PrepSource, String)>[])
                PrepAccount(source: source, username: username),
            ],
          ),
      fideId: fide,
      name: player.name,
      preview: profile == null,
      moreButton: false,
      pendingSources: profile != null && prepFavoriteLacksDatabase(profile)
          ? const [PrepSource.chessever]
          : const [],
      status: opening ? 'Opening…' : null,
      onTap: onTap,
    );
  }
}

class _RankingFooter extends StatelessWidget {
  const _RankingFooter({required this.state, required this.onRetry});
  final PrepRankedPlayers state;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final message = state.failed
        ? 'Could not load players.'
        : !state.loading && state.players.isEmpty
        ? 'No player matches "${state.query}".'
        : null;
    if (message == null) {
      return state.loading
          ? Padding(
              padding: EdgeInsets.symmetric(vertical: 24.h),
              child: GenericLoadingWidget(size: 20.sp, centered: true),
            )
          : const SizedBox.shrink();
    }
    return Padding(
      padding: EdgeInsets.fromLTRB(_gutter, 24.h, _gutter, 0),
      child: Column(
        children: [
          Text(
            message,
            textAlign: TextAlign.center,
            style: AppTypography.textSmRegular.copyWith(
              color: colors.textSecondary,
            ),
          ),
          if (state.failed)
            TextButton(
              onPressed: onRetry,
              child: Text(
                'Retry',
                style: AppTypography.textSmBold.copyWith(
                  color: colors.textPrimary,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      height: 40.h,
      decoration: BoxDecoration(
        color: colors.textPrimary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10.br),
      ),
      child: Row(
        children: [
          SizedBox(width: 12.w),
          Icon(Icons.search_rounded, size: 18.sp, color: colors.iconSecondary),
          SizedBox(width: 8.w),
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: (_) => onChanged(),
              style: AppTypography.textSmRegular.copyWith(
                color: colors.textPrimary,
              ),
              cursorColor: colors.accentText,
              decoration: InputDecoration(
                hintText: 'Search players',
                hintStyle: AppTypography.textSmRegular.copyWith(
                  color: colors.textSecondary,
                ),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
          if (controller.text.isNotEmpty)
            IconButton(
              tooltip: 'Clear search',
              onPressed: () {
                controller.clear();
                onChanged();
              },
              icon: Icon(Icons.close, size: 18.sp, color: colors.iconSecondary),
            )
          else
            SizedBox(width: 12.w),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------ states

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.title,
    required this.body,
    required this.sources,
    required this.actionLabel,
    required this.onAction,
  });

  final String title;
  final String body;
  final List<PrepSource> sources;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      padding: EdgeInsets.fromLTRB(
        _gutter,
        48.h,
        _gutter,
        MediaQuery.viewPaddingOf(context).bottom + 96.h,
      ),
      children: [
        Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final source in sources) ...[
                PrepSourceMark(source: source, size: 48.sp),
                if (source != sources.last) SizedBox(width: 12.w),
              ],
            ],
          ),
        ),
        SizedBox(height: 24.h),
        Text(
          title,
          textAlign: TextAlign.center,
          style: AppTypography.textLgBold.copyWith(color: colors.textPrimary),
        ),
        SizedBox(height: 8.h),
        Text(
          body,
          textAlign: TextAlign.center,
          style: AppTypography.textSmRegular.copyWith(
            color: colors.textSecondary,
            height: 20 / 14,
          ),
        ),
        SizedBox(height: 24.h),
        Center(
          child: _AddButton(label: actionLabel, onPressed: onAction),
        ),
      ],
    );
  }
}

/// A tab's add, in the page while the tab has nothing added yet.
class _AddButton extends StatelessWidget {
  const _AddButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return ElevatedButton.icon(
      key: const ValueKey('prep_add_empty'),
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: colors.textPrimary,
        foregroundColor: colors.textInverse,
        padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 14.h),
        minimumSize: const Size(0, 44),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12.br),
        ),
      ),
      icon: Icon(Icons.add_rounded, size: 18.sp),
      label: Text(label, style: AppTypography.textSmBold),
    );
  }
}

class _ListSkeleton extends StatelessWidget {
  const _ListSkeleton();

  @override
  Widget build(BuildContext context) {
    return SkeletonWidget(
      ignoreContainers: true,
      child: ListView(
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(_gutter, 48.h, _gutter, 0),
        children: [
          for (var i = 0; i < 4; i++)
            Container(
              height: 76.h,
              margin: EdgeInsets.only(bottom: 10.h),
              decoration: BoxDecoration(
                color: context.colors.surfaceRecessed,
                borderRadius: BorderRadius.circular(12.br),
              ),
            ),
        ],
      ),
    );
  }
}
