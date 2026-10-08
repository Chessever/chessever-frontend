import 'package:chessever2/screens/my_prep/data/prep_favorites.dart';
import 'package:chessever2/screens/my_prep/models/prep_models.dart';
import 'package:chessever2/screens/my_prep/prep_access.dart';
import 'package:chessever2/screens/my_prep/prep_actions.dart';
import 'package:chessever2/screens/my_prep/prep_profile_screen.dart';
import 'package:chessever2/screens/my_prep/prep_sources_screen.dart';
import 'package:chessever2/screens/my_prep/providers/prep_providers.dart';
import 'package:chessever2/screens/my_prep/widgets/prep_common.dart';
import 'package:chessever2/screens/my_prep/widgets/prep_profile_card.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
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

  String get _addLabel => switch (_tab) {
    0 => 'Attach your username',
    1 => 'Add opponent',
    _ => 'Add favorite',
  };

  void _add() {
    switch (_tab) {
      case 0:
        prepAddMine(context, ref);
      case 1:
        prepAddOpponent(context, ref);
      default:
        prepAddFavorite(context, ref);
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

  @override
  Widget build(BuildContext context) {
    final profiles = ref.watch(prepProfilesProvider).valueOrNull;
    if (profiles != null) _refreshOnce(profiles);
    final gutter = ResponsiveHelper.adaptive(phone: 20.sp, tablet: 32.sp);

    return Scaffold(
      backgroundColor: context.colors.background,
      floatingActionButton: FloatingActionButton(
        key: const ValueKey('prep_add_floating'),
        tooltip: _addLabel,
        onPressed: profiles == null ? null : _add,
        backgroundColor: context.colors.textPrimary,
        foregroundColor: context.colors.textInverse,
        elevation: 0,
        child: const Icon(Icons.add_rounded),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: ResponsiveHelper.contentMaxWidth,
          ),
          child: Column(
            children: [
              SizedBox(height: MediaQuery.of(context).viewPadding.top + 4.h),
              _AppBar(
                addLabel: _addLabel,
                onAdd: profiles == null ? null : _add,
              ),
              SizedBox(height: 8.h),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: gutter),
                child: SegmentedSwitcher(
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
  const _AppBar({required this.addLabel, required this.onAdd});

  final String addLabel;
  final VoidCallback? onAdd;
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
          IconButton(
            key: const ValueKey('prep_add_top'),
            tooltip: addLabel,
            onPressed: onAdd,
            icon: Icon(
              Icons.add_rounded,
              size: 24.ic,
              color: context.colors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

double get _gutter => ResponsiveHelper.adaptive(phone: 16.w, tablet: 24.w);

/// A tab's count line.
class _TabHeader extends StatelessWidget {
  const _TabHeader({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(_gutter, 16.h, _gutter, 10.h),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.textSmRegular.copyWith(
                color: context.colors.textSecondary,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------ my games

class _MyGamesTab extends ConsumerWidget {
  const _MyGamesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mine = ref.watch(prepProfilesOfKindProvider(PrepKind.mine));
    if (mine == null) return const _ListSkeleton();
    final profile = mine.firstOrNull;
    if (profile == null) {
      return _EmptyState(
        title: 'Attach your own usernames',
        body:
            'Add your Lichess and Chess.com accounts here. Their games stay together. You can also attach your ChessEver player record.',
        sources: PrepSource.playerSources,
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
          bottom: MediaQuery.viewPaddingOf(context).bottom + 96.h,
        ),
        children: [
          _TabHeader(text: 'Your accounts'),
          for (final account in profile.accounts)
            Padding(
              padding: EdgeInsets.symmetric(horizontal: _gutter),
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: PrepSourceMark(source: account.source, size: 24.sp),
                title: Text(
                  account.source.online
                      ? account.username
                      : account.displayName ?? account.username,
                  style: AppTypography.textMdMedium,
                ),
                subtitle: Text(account.source.label),
                onTap: () => PrepSourcesScreen.open(context, profile.id),
              ),
            ),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: _gutter),
            child: Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () {
                  HapticFeedbackService.cardTap();
                  PrepProfileScreen.open(context, profile.id);
                },
                child: Text(
                  'View games · ${prepGamesLabel(profile.gameCount)}',
                ),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: _gutter),
            child: Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => PrepSourcesScreen.open(context, profile.id),
                child: Text(
                  'Manage my accounts',
                  style: AppTypography.textSmMedium.copyWith(
                    color: context.colors.textPrimary,
                  ),
                ),
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
      );
    }
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewPaddingOf(context).bottom + 96.h,
      ),
      itemCount: opponents.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return _TabHeader(
            text: opponents.length == 1
                ? '1 opponent'
                : '${opponents.length} opponents',
          );
        }
        final profile = opponents[index - 1];
        return Padding(
          key: ValueKey(profile.id),
          padding: EdgeInsets.symmetric(horizontal: 4.w),
          child: PrepProfileCard(
            profile: profile,
            fideId: _favoriteFide(profile),
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

String? _favoriteFide(PrepProfile profile) {
  final id = profile.favoriteId;
  if (profile.fideId != null) return profile.fideId;
  if (id == null) return null;
  return kPrepFavorites.where((f) => f.id == id).firstOrNull?.fideId;
}

// ------------------------------------------------------------------ favorites

class _FavoritesTab extends ConsumerStatefulWidget {
  const _FavoritesTab();

  @override
  ConsumerState<_FavoritesTab> createState() => _FavoritesTabState();
}

class _FavoritesTabState extends ConsumerState<_FavoritesTab> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final profiles = ref.watch(prepProfilesProvider).valueOrNull ?? const [];
    final byFavorite = {
      for (final p in profiles)
        if (p.favoriteId != null) p.favoriteId!: p,
    };
    final query = _search.text.trim().toLowerCase();
    final custom = [
      for (final profile in profiles)
        if (profile.kind == PrepKind.favorite &&
            profile.favoriteId == null &&
            (query.isEmpty ||
                profile.name.toLowerCase().contains(query) ||
                profile.accounts.any(
                  (a) => a.username.toLowerCase().contains(query),
                )))
          profile,
    ];
    final list = [
      for (final f in kPrepFavorites)
        if (query.isEmpty ||
            f.name.toLowerCase().contains(query) ||
            (f.chesscom?.toLowerCase().contains(query) ?? false) ||
            (f.lichess?.toLowerCase().contains(query) ?? false))
          f,
    ];
    return ListView.builder(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewPaddingOf(context).bottom + 96.h,
      ),
      itemCount: custom.length + list.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(
            padding: EdgeInsets.fromLTRB(_gutter, 16.h, _gutter, 12.h),
            child: _SearchField(
              controller: _search,
              onChanged: () => setState(() {}),
            ),
          );
        }
        if (index <= custom.length) {
          final profile = custom[index - 1];
          return Padding(
            key: ValueKey(profile.id),
            padding: EdgeInsets.symmetric(horizontal: 4.w),
            child: PrepProfileCard(
              profile: profile,
              onTap: () => PrepProfileScreen.open(context, profile.id),
            ),
          );
        }
        final favorite = list[index - custom.length - 1];
        return Padding(
          key: ValueKey(favorite.id),
          padding: EdgeInsets.symmetric(horizontal: 4.w),
          child: _FavoriteCard(
            favorite: favorite,
            profile: byFavorite[favorite.id],
          ),
        );
      },
    );
  }
}

class _FavoriteCard extends ConsumerWidget {
  const _FavoriteCard({required this.favorite, this.profile});
  final PrepFavorite favorite;
  final PrepProfile? profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) => PrepProfileCard(
    profile:
        profile ??
        PrepProfile(
          id: 'preview-${favorite.id}',
          kind: PrepKind.favorite,
          name: favorite.name,
          createdAtMs: 0,
          favoriteId: favorite.id,
          accounts: [
            for (final (source, username) in favorite.accounts)
              PrepAccount(
                source: source,
                username: username,
                title: favorite.title,
                country: favorite.country,
              ),
          ],
        ),
    fideId: favorite.fideId,
    preview: profile == null,
    onTap: () => prepOpenFavorite(context, ref, favorite),
  );
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
  });

  final String title;
  final String body;
  final List<PrepSource> sources;

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
      ],
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
