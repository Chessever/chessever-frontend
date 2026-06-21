import 'dart:async';
import 'dart:io';

import 'package:chessever2/repository/liked_games/liked_games_provider.dart';
import 'package:chessever2/repository/library/models/saved_analysis.dart';
import 'package:chessever2/revenue_cat_service/subscribe_state.dart';
import 'package:chessever2/screens/chessboard/models/like_tag.dart';
import 'package:chessever2/screens/library/utils/folder_pgn_exporter.dart';
import 'package:chessever2/screens/library/utils/load_saved_analysis.dart';
import 'package:chessever2/screens/my_likes/provider/my_likes_provider.dart';
import 'package:chessever2/screens/my_likes/widgets/date_section_header.dart';
import 'package:chessever2/screens/my_likes/widgets/my_likes_game_card.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/logger/logger.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/user_error_message.dart';
import 'package:chessever2/widgets/game_filter/game_filter.dart';
import 'package:chessever2/widgets/game_filter/game_search_filter_bar.dart';
import 'package:chessever2/widgets/paywall/premium_paywall_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Standalone "My Likes" screen — the For You → Favorites → Games view without
/// the tab bar, sourced from the user's liked games. Same search + filter +
/// date sections + game cards; sections are bucketed by when each game was
/// liked, and free users can only open games liked in the last 7 days.
class MyLikesScreen extends ConsumerStatefulWidget {
  const MyLikesScreen({super.key});

  @override
  ConsumerState<MyLikesScreen> createState() => _MyLikesScreenState();
}

class _MyLikesScreenState extends ConsumerState<MyLikesScreen>
    with WidgetsBindingObserver {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  Timer? _debounceTimer;

  /// Collapsed liked-at date sections, keyed by `yyyy-MM-dd`.
  final Set<String> _collapsedDates = {};

  /// Last successfully-loaded view + tag counts. Kept so a reload (e.g. after
  /// swipe-to-remove invalidates the providers) keeps rendering the current
  /// content instead of flashing the full-page spinner and collapsing the
  /// chip row. The removed card has already animated itself out (keyed
  /// [SwipeActionCard]); the fresh data just omits it.
  MyLikesData? _lastData;
  Map<String, int> _lastTagCounts = const <String, int>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // Recompute the view on resume so the liked-at date headers and the lock
    // state reflect the current day (both derive from DateTime.now() at build).
    if (state == AppLifecycleState.resumed && mounted) {
      ref.invalidate(myLikesViewProvider);
      ref.invalidate(myLikesTagCountsProvider);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _debounceTimer?.cancel();
    _scrollController.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 400), () {
      ref.read(myLikesFilterProvider.notifier).searchGames(value);
    });
  }

  void _clearSearch() {
    HapticFeedback.lightImpact();
    _debounceTimer?.cancel();
    _searchController.clear();
    _searchFocusNode.unfocus();
    ref.read(myLikesFilterProvider.notifier).clearSearch();
  }

  Future<void> _showFilterDialog() async {
    HapticFeedbackService.buttonPress();
    // Search + filter + sort inside My Likes are free for everyone. The only
    // free-tier restriction left is the 7-day read window (locked cards can't
    // be opened), enforced in [_openAnalysis] / [myLikesViewProvider] — not
    // here. So no paywall on applying a filter or sort.
    final result = await showGameFilterDialog(
      context: context,
      currentFilter: ref.read(myLikesFilterProvider).filter,
      // Saved likes are never live broadcasts and never OTB rows, so the
      // Status + Format sections are meaningless here. Sort takes the
      // Status slot.
      showFormatFilter: false,
      showLiveFilter: false,
      showSortSection: true,
      // Color filter removed for the likes database; multi-key sort with
      // per-key direction stays enabled.
      showColorFilter: false,
      showSortDirection: true,
    );
    if (result == null || !mounted) return;

    ref.read(myLikesFilterProvider.notifier).applyFilter(result);
  }

  void _toggleDateSection(String dateKey) {
    HapticFeedback.lightImpact();
    setState(() {
      if (!_collapsedDates.remove(dateKey)) _collapsedDates.add(dateKey);
    });
  }

  void _toggleTagFilter(String tag) {
    final trimmed = tag.trim();
    if (trimmed.isEmpty) return;
    HapticFeedback.selectionClick();
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
    ref.read(myLikesFilterProvider.notifier).toggleTag(trimmed);
  }

  Future<void> _openAnalysis(SavedAnalysis analysis) async {
    // Re-validate the lock at tap time. entry.isLocked is computed once when the
    // view builds and can go stale if the app sits open across local midnight,
    // so this is the authoritative gate before opening a liked game.
    final subscription = ref.read(subscriptionProvider);
    final locked = isLikedGameLocked(
      analysis.createdAt.toLocal(),
      isSubscribed: subscription.isSubscribed,
      subscriptionLoading: subscription.isLoading,
    );
    if (locked) {
      final unlocked = await requirePremiumGuard(context, ref);
      if (!unlocked || !mounted) return;
    }

    final openable =
        ref.read(myLikesViewProvider).valueOrNull?.openableAnalyses ??
        const <SavedAnalysis>[];
    final index = openable.indexWhere((a) => a.id == analysis.id);
    if (index >= 0) {
      loadSavedAnalysisWithSwiping(context, openable, index);
    } else {
      // Not in the openable list yet (e.g. just unlocked via the paywall before
      // the list recomputed) — open this single game directly.
      loadSavedAnalysis(context, analysis);
    }
  }

  Future<void> _removeAnalysis(SavedAnalysis analysis) async {
    final removed = await ref
        .read(likedGamesProvider.notifier)
        .removeAnalysis(analysis);
    if (removed) {
      ref.invalidate(myLikesViewProvider);
      ref.invalidate(myLikesTagCountsProvider);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "Couldn't remove this like. Please try again.",
            style: AppTypography.textSmMedium.copyWith(
              color: context.colors.textPrimary,
            ),
          ),
          backgroundColor: context.colors.surface.withValues(alpha: 0.95),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final viewAsync = ref.watch(myLikesViewProvider);
    // Keep the last good data across reloads: a swipe-remove invalidates the
    // view, and dropping to the spinner here is what made the whole page (chip
    // row included) blink out and back. Once we have data we keep showing it;
    // only a cold first load (or an error with nothing cached) leaves it.
    final data = viewAsync.valueOrNull ?? _lastData;
    if (viewAsync.valueOrNull != null) {
      _lastData = viewAsync.valueOrNull;
    }

    final Widget body;
    if (data != null) {
      body = _buildBody(data);
    } else if (viewAsync.hasError) {
      body = _buildErrorState(userFacingError(viewAsync.error));
    } else {
      body = _buildLoadingState();
    }

    return Scaffold(
      backgroundColor: context.colors.background,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _buildHeader(),
            Expanded(child: body),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final totalLiked =
        ref.watch(myLikesViewProvider).valueOrNull?.totalLiked ?? 0;
    return Padding(
      padding: EdgeInsets.fromLTRB(8.w, 8.h, 16.w, 4.h),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            icon: Icon(
              Icons.arrow_back_ios_new_rounded,
              color: context.colors.textPrimary,
              size: 20.sp,
            ),
          ),
          Icon(
            Icons.favorite_rounded,
            color: context.colors.danger,
            size: 20.sp,
          ),
          SizedBox(width: 8.w),
          Text(
            'My Likes',
            style: AppTypography.textLgBold.copyWith(
              color: context.colors.textPrimary,
            ),
          ),
          const Spacer(),
          if (totalLiked > 0)
            IconButton(
              onPressed: _handleExportPgn,
              tooltip: 'Export as PGN',
              icon: Icon(
                Icons.ios_share_rounded,
                color: context.colors.textPrimary,
                size: 20.sp,
              ),
            ),
        ],
      ),
    );
  }

  /// Returns true if the user accepted the upgrade and actually subscribed.
  /// Renders a non-blocking soft-wall snackbar with an Upgrade action; we
  /// use this instead of immediately raising the paywall so the user can
  /// also tap "Export 7-day window" by ignoring the snackbar's action.
  Future<bool> _promptExportUpgrade(int lockedCount) async {
    if (!mounted) return false;
    final completer = Completer<bool>();
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    final controller = messenger.showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 6),
        behavior: SnackBarBehavior.floating,
        backgroundColor: context.colors.surface.withValues(alpha: 0.95),
        content: Text(
          'Upgrade to export $lockedCount more game${lockedCount == 1 ? '' : 's'}',
          style: AppTypography.textSmMedium.copyWith(
            color: context.colors.textPrimary,
          ),
        ),
        action: SnackBarAction(
          label: 'Upgrade',
          textColor: const Color(0xFFFFB300),
          onPressed: () async {
            if (completer.isCompleted) return;
            final unlocked = await requirePremiumGuard(context, ref);
            if (!completer.isCompleted) completer.complete(unlocked);
          },
        ),
      ),
    );
    // Resolve to false when the snackbar dismisses without the Upgrade
    // action being tapped — caller proceeds with the unlocked slice.
    unawaited(
      controller.closed.then((_) {
        if (!completer.isCompleted) completer.complete(false);
      }),
    );
    return completer.future;
  }

  Future<void> _handleExportPgn() async {
    HapticFeedbackService.medium();

    final allAnalyses =
        ref.read(likedGamesProvider).valueOrNull ?? const <SavedAnalysis>[];
    if (allAnalyses.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Nothing to export yet',
            style: AppTypography.textSmMedium.copyWith(
              color: context.colors.textPrimary,
            ),
          ),
          backgroundColor: context.colors.surface.withValues(alpha: 0.95),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    // Policy C: free users get the same 7-day window they can read; premium
    // gets everything. Slice the list at tap time so a sub picked up mid-
    // session takes effect immediately.
    final subscription = ref.read(subscriptionProvider);
    List<SavedAnalysis> analyses;
    if (subscription.isSubscribed || subscription.isLoading) {
      analyses = allAnalyses;
    } else {
      analyses =
          allAnalyses.where((a) {
            return !isLikedGameLocked(
              a.createdAt.toLocal(),
              isSubscribed: subscription.isSubscribed,
              subscriptionLoading: subscription.isLoading,
            );
          }).toList();
      final lockedCount = allAnalyses.length - analyses.length;
      if (lockedCount > 0) {
        final proceed = await _promptExportUpgrade(lockedCount);
        if (!mounted) return;
        if (proceed) {
          // User just subscribed via the upgrade prompt — re-read state
          // and export everything.
          final refreshed = ref.read(subscriptionProvider);
          if (refreshed.isSubscribed) {
            analyses = allAnalyses;
          }
        } else if (analyses.isEmpty) {
          // Nothing unlocked AND user declined upgrade — bail out cleanly.
          return;
        }
      }
    }

    List<FolderPgnFile> files;
    try {
      files = exportSavedAnalysesAsPgnFiles(
        analyses: analyses,
        databaseName: 'My Likes',
      );
    } catch (e, st) {
      talker.handle(e, st);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            userFacingError(e, fallback: 'Export failed. Please try again.'),
            style: AppTypography.textSmMedium.copyWith(
              color: context.colors.textPrimary,
            ),
          ),
          backgroundColor: const Color(0xFFEF4444),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    if (!mounted) return;
    if (files.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Nothing to export yet',
            style: AppTypography.textSmMedium.copyWith(
              color: context.colors.textPrimary,
            ),
          ),
          backgroundColor: context.colors.surface.withValues(alpha: 0.95),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    try {
      final tempDir = await getTemporaryDirectory();
      final xFiles = <XFile>[];
      for (final entry in files) {
        final file = File('${tempDir.path}/${entry.filename}');
        await file.writeAsString(entry.pgn);
        xFiles.add(XFile(file.path, mimeType: 'application/x-chess-pgn'));
      }

      if (!mounted) return;
      final box = context.findRenderObject() as RenderBox?;
      final origin =
          box != null
              ? box.localToGlobal(Offset.zero) & box.size
              : const Rect.fromLTWH(0, 0, 1, 1);

      await Share.shareXFiles(
        xFiles,
        subject: 'My Likes - Chessever PGN',
        sharePositionOrigin: origin,
      );
      HapticFeedbackService.success();
    } catch (e, st) {
      talker.handle(e, st);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            userFacingError(e, fallback: 'Could not share this. Please try again.'),
            style: AppTypography.textSmMedium.copyWith(
              color: context.colors.textPrimary,
            ),
          ),
          backgroundColor: const Color(0xFFEF4444),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Widget _buildBody(MyLikesData data) {
    if (data.isEmpty) return _buildEmptyState();

    final selectedTags = ref.watch(myLikesFilterProvider).selectedTags;

    Widget content = CustomScrollView(
      controller: _scrollController,
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(0, 12.h, 0, 8.h),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16.w),
                  child: _buildSearchBar(),
                ),
                // Filter row is edge-to-edge so the horizontal scroll runs
                // under the screen edges instead of being clipped by parent
                // padding.
                _buildTagQuickFilters(),
              ],
            ),
          ),
        ),
        if (data.hasNoMatches)
          SliverFillRemaining(
            hasScrollBody: false,
            child: _buildNoMatchesState(
              subtitle:
                  selectedTags.isEmpty
                      ? 'Try adjusting your search or filters'
                      : 'Try another tag or clear the tag filter',
            ),
          )
        else
          _buildSectionsSliver(data),
        SliverToBoxAdapter(child: SizedBox(height: 24.h)),
      ],
    );

    if (ResponsiveHelper.isTablet) {
      content = Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: ResponsiveHelper.contentMaxWidth,
          ),
          child: content,
        ),
      );
    }

    return content;
  }

  Widget _buildSearchBar() {
    return GameSearchFilterBar(
      controller: _searchController,
      focusNode: _searchFocusNode,
      currentFilter: ref.watch(myLikesFilterProvider).filter,
      onChanged: _onSearchChanged,
      onClear: _clearSearch,
      onFilterTap: _showFilterDialog,
    );
  }

  Widget _buildTagQuickFilters() {
    final selectedTags = ref.watch(myLikesFilterProvider).selectedTags;
    // Retain the last counts through a reload so the chip row doesn't collapse
    // and snap back when a swipe-remove re-derives the tag counts.
    final liveCounts = ref.watch(myLikesTagCountsProvider).valueOrNull;
    if (liveCounts != null) {
      _lastTagCounts = liveCounts;
    }
    final counts = liveCounts ?? _lastTagCounts;
    if (counts.isEmpty && selectedTags.isEmpty) {
      return const SizedBox.shrink();
    }

    // No "All" chip — empty selection IS "all" (PM removed it). Total-liked
    // count remains visible via the date headers / sticky title.
    final chips = <Widget>[];

    for (final tag in kLikeTags) {
      final count = counts[tag.label] ?? 0;
      final isSelected = selectedTags.contains(tag.label);
      if (count == 0 && !isSelected) continue;
      chips.add(
        _LikeTagFilterChip(
          label: tag.label,
          count: count,
          selected: isSelected,
          color: tag.color,
          onTap: () => _toggleTagFilter(tag.label),
        ),
      );
    }

    // 48h gives the chip's 40h pill room for the selected-state 1.03 scale
    // without vertical clipping. ListView eats the horizontal padding so the
    // strip itself can run from screen edge to screen edge.
    return Padding(
      padding: EdgeInsets.only(top: 12.h),
      child: SizedBox(
        height: 48.h,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: EdgeInsets.symmetric(horizontal: 16.w),
          physics: const BouncingScrollPhysics(),
          itemCount: chips.length,
          separatorBuilder: (_, __) => SizedBox(width: 8.w),
          itemBuilder: (_, i) => Center(child: chips[i]),
        ),
      ),
    );
  }

  Widget _buildSectionsSliver(MyLikesData data) {
    final items = <Widget>[];

    // Library-wide tag → game-count map. Reuses the cached counts that drive
    // the filter chip row so cards can render the dominant tag first.
    final liveCounts = ref.watch(myLikesTagCountsProvider).valueOrNull;
    if (liveCounts != null) {
      _lastTagCounts = liveCounts;
    }
    final tagCounts = liveCounts ?? _lastTagCounts;

    for (final section in data.sections) {
      final dateKey = section.key;
      final entries = section.value;
      final isCollapsed = _collapsedDates.contains(dateKey);
      // Sort override flattens everything into one synthetic bucket; skip
      // the date header in that case so the screen reads as a plain sorted
      // list instead of a one-day fake group.
      final isSortedBucket = dateKey.startsWith('__');

      if (!isSortedBucket) {
        items.add(
          Padding(
            padding: EdgeInsets.only(bottom: 12.h),
            child: DateSectionHeader(
              dateLabel: formatLikedDateHeader(dateKey),
              gameCount: entries.length,
              isExpanded: !isCollapsed,
              onToggle: () => _toggleDateSection(dateKey),
            ),
          ),
        );
      }

      if (isSortedBucket || !isCollapsed) {
        for (int i = 0; i < entries.length; i++) {
          final entry = entries[i];
          final isLast = i == entries.length - 1;
          items.add(
            Padding(
              padding: EdgeInsets.only(bottom: isLast ? 16.h : 12.h),
              child: MyLikesGameCard(
                key: ValueKey('mylikes_${entry.analysis.id}'),
                analysis: entry.analysis,
                game: entry.game,
                isLocked: entry.isLocked,
                tagCounts: tagCounts,
                onOpen: () => _openAnalysis(entry.analysis),
                onRemove: () => _removeAnalysis(entry.analysis),
              ),
            ),
          );
        }
      }
    }

    return SliverPadding(
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) => items[index],
          childCount: items.length,
          addAutomaticKeepAlives: false,
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80.w,
            height: 80.h,
            decoration: BoxDecoration(
              color: context.colors.danger.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20.br),
            ),
            child: Icon(
              Icons.favorite_rounded,
              color: context.colors.danger.withValues(alpha: 0.8),
              size: 40.ic,
            ),
          ),
          SizedBox(height: 20.h),
          Text(
            'No likes yet',
            style: AppTypography.textMdMedium.copyWith(
              color: context.colors.textPrimary,
            ),
          ),
          SizedBox(height: 8.h),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 40.w),
            child: Text(
              'Double-tap a game on the board to add it to your likes.',
              style: AppTypography.textSmRegular.copyWith(
                color: context.colors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 300.ms).scale(begin: const Offset(0.95, 0.95));
  }

  Widget _buildNoMatchesState({String? subtitle}) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.filter_alt_off_outlined,
            size: 56.sp,
            color: context.colors.textPrimary.withValues(alpha: 0.4),
          ),
          SizedBox(height: 12.h),
          Text(
            'No matching games',
            style: AppTypography.textMdMedium.copyWith(
              color: context.colors.textPrimary.withValues(alpha: 0.85),
            ),
          ),
          SizedBox(height: 6.h),
          Text(
            subtitle ?? 'Try adjusting your search or filters',
            style: AppTypography.textSmRegular.copyWith(
              color: context.colors.textPrimary.withValues(alpha: 0.55),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    ).animate().fadeIn(duration: 300.ms);
  }

  Widget _buildLoadingState() {
    return Center(
      child: SizedBox(
        width: 40.w,
        height: 40.h,
        child: CircularProgressIndicator(
          color: context.colors.textPrimary,
          strokeWidth: 2.5,
        ),
      ),
    );
  }

  Widget _buildErrorState(String error) {
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 32.w),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline_rounded,
              color: const Color(0xFFEF4444),
              size: 32.ic,
            ),
            SizedBox(height: 12.h),
            Text(
              'Failed to load your likes',
              style: AppTypography.textMdMedium.copyWith(
                color: context.colors.textPrimary,
              ),
            ),
            SizedBox(height: 8.h),
            Text(
              error,
              style: AppTypography.textSmRegular.copyWith(
                color: context.colors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 20.h),
            TextButton(
              onPressed: () {
                ref.invalidate(myLikesViewProvider);
                ref.invalidate(myLikesTagCountsProvider);
                ref.read(likedGamesProvider.notifier).refresh();
              },
              child: Text(
                'Retry',
                style: AppTypography.textSmMedium.copyWith(
                  color: context.colors.textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LikeTagFilterChip extends StatelessWidget {
  const _LikeTagFilterChip({
    required this.label,
    required this.count,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final t = selected ? 1.0 : 0.0;
    // No dot anymore — chip carries its tag identity via a low-key tinted
    // fill + colored border. Unselected sits quiet; selected pops with a
    // brighter fill and a stronger border.
    final background =
        Color.lerp(
          color.withValues(alpha: 0.08),
          color.withValues(alpha: 0.22),
          t,
        )!;
    final borderColor =
        Color.lerp(
          color.withValues(alpha: 0.32),
          color.withValues(alpha: 0.85),
          t,
        )!;

    return AnimatedScale(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOutCubic,
      scale: selected ? 1.03 : 1,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20.br),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            height: 40.h,
            padding: EdgeInsets.symmetric(horizontal: 12.w),
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(20.br),
              border: Border.all(color: borderColor),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.textXsMedium.copyWith(
                    color:
                        selected
                            ? colors.textPrimary
                            : colors.textPrimary.withValues(alpha: 0.72),
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
                SizedBox(width: 7.w),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 2.h),
                  decoration: BoxDecoration(
                    color:
                        selected
                            ? color.withValues(alpha: 0.18)
                            : colors.textPrimary.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(999.br),
                  ),
                  child: Text(
                    count.toString(),
                    style: AppTypography.textXsMedium.copyWith(
                      color:
                          selected
                              ? colors.textPrimary
                              : colors.textPrimary.withValues(alpha: 0.55),
                      fontSize: 10.sp,
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
