import 'dart:async';

import 'package:chessever2/screens/my_prep/data/prep_favorites.dart';
import 'package:chessever2/screens/my_prep/models/prep_models.dart';
import 'package:chessever2/screens/my_prep/prep_access.dart';
import 'package:chessever2/screens/my_prep/prep_actions.dart';
import 'package:chessever2/screens/my_prep/providers/prep_providers.dart';
import 'package:chessever2/screens/my_prep/services/prep_analysis.dart';
import 'package:chessever2/screens/my_prep/tabs/prep_games_tab.dart';
import 'package:chessever2/screens/my_prep/tabs/prep_openings_tab.dart';
import 'package:chessever2/screens/my_prep/tabs/prep_overview_tab.dart';
import 'package:chessever2/screens/my_prep/widgets/prep_common.dart';
import 'package:chessever2/screens/my_prep/widgets/prep_filters.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
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
  static const _tabs = ['Overview', 'Games', 'Openings'];
  int _tab = 0;
  late final PageController _pages = PageController();
  PrepFilter _filter = const PrepFilter();
  bool _checkedFreshness = false;

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

  /// Opening a profile brings stale games up to date in the background.
  void _checkFreshness(PrepProfile profile) {
    if (_checkedFreshness) return;
    _checkedFreshness = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !hasPrepAccess(ref)) return;
      ref.read(prepSyncProvider.notifier).refreshStale([profile]);
    });
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
    final analysis = ref.watch(prepAnalysisProvider(profile.id));
    final games = analysis.valueOrNull?.games ?? const <PrepGame>[];
    final filtered = _filter.apply(games);
    final gutter = ResponsiveHelper.adaptive(phone: 16.w, tablet: 24.w);

    return Scaffold(
      backgroundColor: context.colors.background,
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: ResponsiveHelper.contentMaxWidth),
          child: Column(
            children: [
              SizedBox(height: MediaQuery.of(context).viewPadding.top + 4.h),
              _TopBar(profile: profile),
              _Hero(profile: profile),
              SizedBox(height: 12.h),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: gutter),
                child: SegmentedSwitcher(
                  options: _tabs,
                  initialSelection: _tab,
                  currentSelection: _tab,
                  onSelectionChanged: _select,
                ),
              ),
              PrepFilterBar(
                games: games,
                profile: profile,
                filter: _filter,
                onChanged: (f) => setState(() => _filter = f),
              ),
              Expanded(
                child: analysis.when(
                  skipLoadingOnReload: true,
                  error: (error, _) => PrepMessage(
                    title: 'Could not read these games',
                    body: '$error',
                  ),
                  loading: () => const PrepMessage(
                    title: 'Reading games…',
                    body: 'Working out results and openings.',
                    busy: true,
                  ),
                  data: (data) {
                    if (data.games.isEmpty) return _NoGames(profile: profile);
                    return PageView(
                      controller: _pages,
                      onPageChanged: (i) {
                        if (i != _tab) setState(() => _tab = i);
                      },
                      children: [
                        PrepOverviewTab(
                          profile: profile,
                          stats: PrepStats.of(filtered),
                          filter: _filter,
                        ),
                        PrepGamesTab(
                          analysis: data,
                          games: filtered,
                          filter: _filter,
                          onFilterChanged: (f) => setState(() => _filter = f),
                        ),
                        PrepOpeningsTab(
                          profile: profile,
                          analysis: data,
                          games: filtered,
                          filter: _filter,
                        ),
                      ],
                    );
                  },
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
    final syncing = ref.watch(
      prepSyncProvider.select(
        (s) => profile.accounts.any((a) => s.containsKey(a.key)),
      ),
    );
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 8.w),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Back',
            onPressed: () => Navigator.of(context).pop(),
            icon: Icon(
              Icons.arrow_back_ios_new_outlined,
              size: 22.ic,
              color: colors.textPrimary,
            ),
          ),
          const Spacer(),
          IconButton(
            tooltip: 'Refresh games',
            onPressed: syncing
                ? null
                : () {
                    HapticFeedbackService.buttonPress();
                    unawaited(prepRefreshProfile(context, ref, profile.id));
                  },
            icon: syncing
                ? SizedBox.square(
                    dimension: 18.sp,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: colors.textSecondary,
                    ),
                  )
                : Icon(Icons.refresh_rounded, size: 22.ic, color: colors.iconPrimary),
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

class _Hero extends ConsumerWidget {
  const _Hero({required this.profile});
  final PrepProfile profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final fideId = kPrepFavorites
        .where((f) => f.id == profile.favoriteId)
        .firstOrNull
        ?.fideId;
    final progress = ref.watch(
      prepSyncProvider.select((s) {
        for (final a in profile.accounts) {
          final status = s[a.key];
          if (status != null) return '${a.source.label}: ${status.message}';
        }
        return null;
      }),
    );
    final gutter = ResponsiveHelper.adaptive(phone: 16.w, tablet: 24.w);
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: gutter),
      child: Row(
        children: [
          PrepAvatar(
            name: profile.name,
            size: 64.sp,
            photoUrl: profile.avatarUrl,
            fideId: fideId,
            title: profile.title,
          ),
          SizedBox(width: 14.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    PrepFlag(country: profile.country),
                    Flexible(
                      child: Text(
                        profile.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.textXlBold.copyWith(
                          color: colors.textPrimary,
                          letterSpacing: -0.4,
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
                    for (final a in profile.accounts)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          PrepSourceMark(source: a.source, size: 16.sp),
                          SizedBox(width: 5.w),
                          Text(
                            a.bestRating == null
                                ? a.username
                                : '${a.username} ${a.bestRating}',
                            style: AppTypography.textXsMedium.copyWith(
                              color: colors.textSecondary,
                              fontFeatures: const [FontFeature.tabularFigures()],
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
                SizedBox(height: 4.h),
                Text(
                  progress ??
                      '${prepGamesLabel(profile.gameCount)} · '
                          '${prepSyncedAgo(profile.lastSyncAtMs)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.textXsRegular.copyWith(
                    color: colors.textTertiary,
                  ),
                ),
              ],
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
    final error = profile.accounts.map((a) => a.error).whereType<String>().firstOrNull;
    if (syncing) {
      return const PrepMessage(
        title: 'Downloading games',
        body: 'The first download of a large account can take a few minutes. '
            'You can leave this screen; it keeps going.',
        busy: true,
      );
    }
    return PrepMessage(
      title: error == null ? 'No games yet' : 'Download failed',
      body: error ??
          'Nothing matched this account’s download options. Try a longer '
              'period or more time controls.',
      actionLabel: 'Try again',
      onAction: () => prepRefreshProfile(context, ref, profile.id),
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
              style: AppTypography.textMdBold.copyWith(color: colors.textPrimary),
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
