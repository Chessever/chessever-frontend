import 'dart:async';
import 'dart:io';

import 'package:chessever2/constants/game_tags.dart';
import 'package:chessever2/repository/liked_games/liked_games_provider.dart';
import 'package:chessever2/repository/library/models/saved_analysis.dart';
import 'package:chessever2/revenue_cat_service/subscribe_state.dart';
import 'package:chessever2/screens/library/utils/folder_pgn_exporter.dart';
import 'package:chessever2/screens/library/utils/load_saved_analysis.dart';
import 'package:chessever2/screens/my_likes/provider/my_likes_provider.dart';
import 'package:chessever2/screens/my_likes/widgets/date_section_header.dart';
import 'package:chessever2/screens/my_likes/widgets/my_likes_game_card.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
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
    // Dialog opens for everyone — free users get to see what's available.
    // Premium gate fires only when a non-default filter/sort is applied,
    // so Reset (which pops a default filter) and Cancel never pop paywall.
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

    final isPremiumChange =
        result.hasActiveFilters || result.hasActiveSorts;
    if (isPremiumChange) {
      final unlocked = await requirePremiumGuard(context, ref);
      if (!unlocked || !mounted) return;
    }
    ref.read(myLikesFilterProvider.notifier).applyFilter(result);
  }

  void _toggleDateSection(String dateKey) {
    HapticFeedback.lightImpact();
    setState(() {
      if (!_collapsedDates.remove(dateKey)) _collapsedDates.add(dateKey);
    });
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
    if (!removed && mounted) {
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

    return Scaffold(
      backgroundColor: context.colors.background,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: viewAsync.when(
                data: _buildBody,
                loading: () => _buildLoadingState(),
                error: (error, _) => _buildErrorState(error.toString()),
              ),
            ),
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
          Icon(Icons.favorite_rounded, color: context.colors.danger, size: 20.sp),
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
    unawaited(controller.closed.then((_) {
      if (!completer.isCompleted) completer.complete(false);
    }));
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
      analyses = allAnalyses.where((a) {
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
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Export failed: $e',
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
      final origin = box != null
          ? box.localToGlobal(Offset.zero) & box.size
          : const Rect.fromLTWH(0, 0, 1, 1);

      await Share.shareXFiles(
        xFiles,
        subject: 'My Likes - Chessever PGN',
        sharePositionOrigin: origin,
      );
      HapticFeedbackService.success();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Share failed: $e',
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

    Widget content = CustomScrollView(
      controller: _scrollController,
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 8.h),
            child: _buildSearchBar(),
          ),
        ),
        SliverToBoxAdapter(child: _buildTagChipsRow()),
        if (data.hasNoMatches)
          SliverFillRemaining(
            hasScrollBody: false,
            child: _buildNoMatchesState(),
          )
        else
          _buildSectionsSliver(data),
        SliverToBoxAdapter(child: SizedBox(height: 24.h)),
      ],
    );

    if (ResponsiveHelper.isTablet) {
      content = Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: ResponsiveHelper.contentMaxWidth),
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

  /// Tag chips: tapping one to *filter* is premium. Attaching tags stays free
  /// and happens in the board save/edit sheet, not here.
  Future<void> _onTagChipTap(String tag) async {
    HapticFeedbackService.buttonPress();
    final isPremium = ref.read(subscriptionProvider).isSubscribed;
    if (!isPremium) {
      final unlocked = await requirePremiumGuard(context, ref);
      if (!unlocked || !mounted) return;
    }
    ref.read(myLikesFilterProvider.notifier).toggleTag(tag);
  }

  Widget _buildTagChipsRow() {
    final selected = ref.watch(
      myLikesFilterProvider.select((s) => s.selectedTags),
    );
    return SizedBox(
      height: 34.h,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.fromLTRB(16.w, 0, 16.w, 4.h),
        itemCount: kOfficialGameTags.length,
        separatorBuilder: (_, __) => SizedBox(width: 8.w),
        itemBuilder: (context, index) {
          final tag = kOfficialGameTags[index];
          final isOn = selected.contains(tag.label);
          return GestureDetector(
            onTap: () => _onTagChipTap(tag.label),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
              decoration: BoxDecoration(
                color:
                    isOn
                        ? context.colors.danger.withValues(alpha: 0.15)
                        : context.colors.textPrimary.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(20.br),
                border: Border.all(
                  color:
                      isOn
                          ? context.colors.danger.withValues(alpha: 0.5)
                          : context.colors.textPrimary.withValues(alpha: 0.1),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isOn ? Icons.check_rounded : tag.icon,
                    size: 13.sp,
                    color:
                        isOn
                            ? context.colors.danger
                            : context.colors.textPrimary.withValues(alpha: 0.55),
                  ),
                  SizedBox(width: 5.w),
                  Text(
                    tag.label,
                    style: AppTypography.textXsMedium.copyWith(
                      color:
                          isOn
                              ? context.colors.danger
                              : context.colors.textPrimary.withValues(
                                alpha: 0.7,
                              ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSectionsSliver(MyLikesData data) {
    final items = <Widget>[];

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

  Widget _buildNoMatchesState() {
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
            'Try adjusting your search or filters',
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
              onPressed:
                  () => ref.read(likedGamesProvider.notifier).refresh(),
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
