import 'dart:async';

import 'package:chessever2/screens/for_you/discovery/widgets/discovery_common.dart'
    show DiscoveryAction, DiscoveryActionLead;
import 'package:chessever2/screens/my_prep/data/prep_favorites.dart';
import 'package:chessever2/screens/my_prep/models/prep_models.dart';
import 'package:chessever2/screens/my_prep/prep_access.dart';
import 'package:chessever2/screens/my_prep/prep_actions.dart';
import 'package:chessever2/screens/my_prep/prep_profile_screen.dart';
import 'package:chessever2/screens/my_prep/providers/prep_providers.dart';
import 'package:chessever2/screens/my_prep/widgets/prep_common.dart';
import 'package:chessever2/screens/my_prep/widgets/prep_profile_card.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/app_button.dart' show TappableScale;
import 'package:chessever2/widgets/segmented_switcher.dart';
import 'package:chessever2/widgets/skeleton_widget.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// My Prep: the reader's own games, the opponents they prepare for, and
/// famous players to study, each read from Lichess and Chess.com.
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
    _pages.animateToPage(
      index,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
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
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: ResponsiveHelper.contentMaxWidth,
          ),
          child: Column(
            children: [
              SizedBox(height: MediaQuery.of(context).viewPadding.top + 4.h),
              _AppBar(),
              SizedBox(height: 8.h),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: gutter),
                child: SegmentedSwitcher(
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
          SizedBox(width: 48.w),
        ],
      ),
    );
  }
}

double get _gutter => ResponsiveHelper.adaptive(phone: 16.w, tablet: 24.w);

/// A tab's count line with its action at the end.
class _TabHeader extends StatelessWidget {
  const _TabHeader({required this.text, this.action});

  final String text;
  final Widget? action;

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
          ?action,
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
    if (profile == null || profile.accounts.isEmpty) {
      return _EmptyState(
        title: 'Bring in your own games',
        body:
            'Add your Lichess and Chess.com usernames to see your results, '
            'your openings and every game you played. They stay up to date '
            'three times a day.',
        actionLabel: 'Add your accounts',
        onAction: () => prepAddMine(context, ref),
        sources: PrepSource.values,
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
        padding: EdgeInsets.only(bottom: 32.h),
        children: [
          _TabHeader(
            text: prepGamesLabel(profile.gameCount),
            action: DiscoveryAction(
              label: 'Add account',
              lead: DiscoveryActionLead.plus,
              onTap: () => prepAddAccountTo(context, ref, profile),
            ),
          ),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: _gutter),
            child: _OpenPrepCard(profile: profile),
          ),
          SizedBox(height: 20.h),
          Padding(
            padding: EdgeInsets.fromLTRB(_gutter, 0, _gutter, 10.h),
            child: Text(
              'Accounts',
              style: AppTypography.textMdBold.copyWith(
                color: context.colors.textPrimary,
              ),
            ),
          ),
          for (final account in profile.accounts)
            Padding(
              padding: EdgeInsets.fromLTRB(_gutter, 0, _gutter, 10.h),
              child: PrepAccountRow(profile: profile, account: account),
            ),
        ],
      ),
    );
  }
}

/// The way into the reader's own Overview, Games and Openings.
class _OpenPrepCard extends StatelessWidget {
  const _OpenPrepCard({required this.profile});
  final PrepProfile profile;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return TappableScale(
      scaleDown: 0.98,
      onTap: () {
        HapticFeedbackService.cardTap();
        PrepProfileScreen.open(context, profile.id);
      },
      child: Container(
        padding: EdgeInsets.all(16.sp),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(12.br),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Study your games',
                    style: AppTypography.textMdBold.copyWith(
                      color: colors.textPrimary,
                    ),
                  ),
                  SizedBox(height: 4.h),
                  Text(
                    'Results, openings and the full game list, '
                    'from every account together.',
                    style: AppTypography.textXsRegular.copyWith(
                      color: colors.textSecondary,
                      height: 16 / 12,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(width: 12.w),
            Icon(
              Icons.arrow_forward_ios_rounded,
              size: 16.sp,
              color: colors.iconSecondary,
            ),
          ],
        ),
      ),
    );
  }
}

/// One account: its provider, rating, game count and freshness, with its
/// own refresh.
class PrepAccountRow extends ConsumerWidget {
  const PrepAccountRow({super.key, required this.profile, required this.account});

  final PrepProfile profile;
  final PrepAccount account;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final status = ref.watch(
      prepSyncProvider.select((s) => s[account.key]?.message),
    );
    final syncing = status != null;
    final rating = account.bestRating;
    final line = syncing
        ? status
        : account.error ??
              '${prepGamesLabel(account.gameCount)} · ${prepSyncedAgo(account.lastSyncAtMs)}';
    return Container(
      padding: EdgeInsets.fromLTRB(12.sp, 10.sp, 4.sp, 10.sp),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(12.br),
      ),
      child: Row(
        children: [
          PrepSourceMark(source: account.source, size: 32.sp),
          SizedBox(width: 12.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        account.username,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.textSmBold.copyWith(
                          color: colors.textPrimary,
                        ),
                      ),
                    ),
                    if (rating != null) ...[
                      SizedBox(width: 6.w),
                      Text(
                        '$rating',
                        style: AppTypography.textXsMedium.copyWith(
                          color: colors.textSecondary,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ],
                ),
                SizedBox(height: 2.h),
                Text(
                  line,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.textXsRegular.copyWith(
                    color: account.error != null && !syncing
                        ? colors.danger
                        : colors.textTertiary,
                  ),
                ),
                Text(
                  account.preferences.describe(account.source),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.textXxsRegular.copyWith(
                    color: colors.textTertiary,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 44,
            height: 44,
            child: syncing
                ? IconButton(
                    tooltip: 'Stop download',
                    onPressed: () =>
                        ref.read(prepSyncProvider.notifier).cancel(account),
                    icon: SizedBox.square(
                      dimension: 18.sp,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: colors.textSecondary,
                      ),
                    ),
                  )
                : IconButton(
                    tooltip: 'Refresh ${account.username}',
                    onPressed: () => unawaited(
                      prepRefreshAccount(context, ref, profile.id, account),
                    ),
                    icon: Icon(
                      Icons.refresh_rounded,
                      size: 20.sp,
                      color: colors.iconPrimary,
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
            'Add their Lichess or Chess.com username to see what they play, '
            'how they score with each opening and how their games go.',
        actionLabel: 'Add an opponent',
        onAction: () => prepAddOpponent(context, ref),
        sources: PrepSource.values,
      );
    }
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      padding: EdgeInsets.only(bottom: 32.h),
      itemCount: opponents.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return _TabHeader(
            text: opponents.length == 1
                ? '1 opponent'
                : '${opponents.length} opponents',
            action: DiscoveryAction(
              label: 'Add opponent',
              lead: DiscoveryActionLead.plus,
              onTap: () => prepAddOpponent(context, ref),
            ),
          );
        }
        final profile = opponents[index - 1];
        return Padding(
          key: ValueKey(profile.id),
          padding: EdgeInsets.fromLTRB(_gutter, 0, _gutter, 10.h),
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
      padding: EdgeInsets.only(bottom: 32.h),
      itemCount: list.length + 1,
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
        final favorite = list[index - 1];
        return Padding(
          key: ValueKey(favorite.id),
          padding: EdgeInsets.fromLTRB(_gutter, 0, _gutter, 10.h),
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
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final kept = profile;
    final syncing = ref.watch(
      prepSyncProvider.select(
        (s) => kept?.accounts.any((a) => s.containsKey(a.key)) ?? false,
      ),
    );
    final downloaded = kept != null && kept.lastSyncAtMs != null;
    return Semantics(
      button: true,
      label: '${favorite.title} ${favorite.name}',
      child: TappableScale(
        scaleDown: 0.98,
        onTap: () => prepOpenFavorite(context, ref, favorite),
        child: Container(
          padding: EdgeInsets.all(12.sp),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(12.br),
          ),
          child: Row(
            children: [
              PrepAvatar(
                name: favorite.name,
                size: 48.sp,
                fideId: favorite.fideId,
                title: favorite.title,
              ),
              SizedBox(width: 12.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        PrepFlag(country: favorite.country),
                        Flexible(
                          child: Text(
                            favorite.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.textMdBold.copyWith(
                              color: colors.textPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 6.h),
                    Wrap(
                      spacing: 10.w,
                      runSpacing: 4.h,
                      children: [
                        for (final (source, username) in favorite.accounts)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              PrepSourceMark(source: source, size: 16.sp),
                              SizedBox(width: 5.w),
                              Text(
                                username,
                                style: AppTypography.textXsRegular.copyWith(
                                  color: colors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              SizedBox(width: 8.w),
              if (syncing)
                SizedBox.square(
                  dimension: 14.sp,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    color: colors.textSecondary,
                  ),
                )
              else if (downloaded)
                Tooltip(
                  message: '${prepGamesLabel(kept.gameCount)} downloaded',
                  child: Icon(
                    Icons.download_done_rounded,
                    size: 18.sp,
                    color: colors.textSecondary,
                  ),
                )
              else
                Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 14.sp,
                  color: colors.iconSecondary,
                ),
            ],
          ),
        ),
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
    required this.actionLabel,
    required this.onAction,
    required this.sources,
  });

  final String title;
  final String body;
  final String actionLabel;
  final VoidCallback onAction;
  final List<PrepSource> sources;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      padding: EdgeInsets.fromLTRB(_gutter, 48.h, _gutter, 32.h),
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
          child: ElevatedButton.icon(
            onPressed: onAction,
            icon: Icon(Icons.add_rounded, size: 18.sp),
            label: Text(actionLabel, style: AppTypography.textSmBold),
            style: ElevatedButton.styleFrom(
              backgroundColor: colors.textPrimary,
              foregroundColor: colors.textInverse,
              elevation: 0,
              padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 14.h),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12.br),
              ),
            ),
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
