import 'dart:async';

import 'package:chessever2/repository/gamebase/gamebase_repository.dart';
import 'package:chessever2/repository/gamebase/miniatures/miniatures_models.dart';
import 'package:chessever2/revenue_cat_service/subscribe_state.dart';
import 'package:chessever2/screens/chessboard/chess_board_screen_new.dart';
import 'package:chessever2/screens/chessboard/provider/chess_board_screen_provider_new.dart';
import 'package:chessever2/screens/library/providers/miniatures_provider.dart';
import 'package:chessever2/screens/library/utils/gamebase_pgn_builder.dart';
import 'package:chessever2/screens/library/widgets/library_search_bar.dart';
import 'package:chessever2/screens/library/widgets/miniatures_filter_dialog.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/logger/logger.dart';
import 'package:chessever2/utils/number_format_utils.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/alert_dialog/alert_modal.dart';
import 'package:chessever2/widgets/app_button.dart';
import 'package:chessever2/widgets/paywall/premium_paywall_sheet.dart';
import 'package:chessever2/widgets/screen_wrapper.dart';
import 'package:chessever2/widgets/segmented_switcher.dart';
import 'package:chessever2/widgets/skeleton_widget.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:intl/intl.dart';

/// Miniatures community database: short decisive master games ending by
/// move 25, served by the gamebase `/api/miniatures` index.
///
/// Mirrors the desktop implementation's capabilities: Today/Week/All window,
/// server-side sort (strongest / fewest moves / most recent), free-text
/// search, the full filter set, and offset pagination. Browsing and opening
/// games is free; search, filters and sorting are premium (ticket #699).
class MiniaturesScreen extends ConsumerStatefulWidget {
  const MiniaturesScreen({super.key});

  @override
  ConsumerState<MiniaturesScreen> createState() => _MiniaturesScreenState();
}

class _MiniaturesScreenState extends ConsumerState<MiniaturesScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();

  Timer? _debounceTimer;
  static const _debounceDuration = Duration(milliseconds: 350);

  /// Set once [requirePremiumGuard] passes, so the search bar unwraps from its
  /// paywall interceptor even before the subscription provider re-emits.
  bool _premiumUnlocked = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _searchFocusNode.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      final state = ref.read(miniaturesPaginatedProvider);
      if (!state.isLoading && state.hasMore) {
        ref.read(miniaturesPaginatedProvider.notifier).loadNextPage();
      }
    }
  }

  bool get _isPremium =>
      _premiumUnlocked || ref.read(subscriptionProvider).isSubscribed;

  /// Free users browse and open games; search/filter/sort require premium.
  Future<bool> _ensurePremium() async {
    if (_isPremium) return true;
    final ok = await requirePremiumGuard(context, ref);
    if (ok && mounted) setState(() => _premiumUnlocked = true);
    return ok;
  }

  Future<void> _handleLockedSearchTap() async {
    HapticFeedbackService.light();
    final ok = await _ensurePremium();
    if (ok && mounted) _searchFocusNode.requestFocus();
  }

  void _onSearchChanged(String query) {
    final trimmed = query.trim();
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_debounceDuration, () {
      if (!mounted) return;
      final current = ref.read(miniaturesFilterProvider);
      ref.read(miniaturesFilterProvider.notifier).state = current.copyWith(
        search: trimmed.isEmpty ? null : trimmed,
        clearSearch: trimmed.isEmpty,
      );
    });
  }

  void _onWindowChanged(int index) {
    HapticFeedbackService.selection();
    final current = ref.read(miniaturesFilterProvider);
    ref.read(miniaturesFilterProvider.notifier).state = current.copyWith(
      window: MiniatureGamesWindow.values[index],
    );
  }

  Future<void> _openFilters() async {
    HapticFeedbackService.light();
    if (!await _ensurePremium()) return;
    if (!mounted) return;

    final currentFilter = ref.read(miniaturesFilterProvider);
    final newFilter = await showMiniaturesFilterDialog(
      context: context,
      currentFilter: currentFilter,
    );
    if (newFilter != null && mounted) {
      ref.read(miniaturesFilterProvider.notifier).state = newFilter;
    }
  }

  Future<void> _openSortSheet() async {
    HapticFeedbackService.light();
    if (!await _ensurePremium()) return;
    if (!mounted) return;

    final current = ref.read(miniaturesFilterProvider).sort;
    final picked = await showModalBottomSheet<MiniatureGamesSort>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _MiniatureSortSheet(current: current),
    );
    if (picked != null && mounted) {
      final filter = ref.read(miniaturesFilterProvider);
      ref.read(miniaturesFilterProvider.notifier).state = filter.copyWith(
        sort: picked,
        // "Fewest moves" reads ascending; the rest read best/newest first.
        order:
            picked == MiniatureGamesSort.moves
                ? MiniatureGamesSortOrder.asc
                : MiniatureGamesSortOrder.desc,
      );
    }
  }

  Future<void> _openMiniature(List<GamebaseMiniature> items, int index) async {
    HapticFeedbackService.cardTap();

    // Board renders this as a tour-style game view.
    ref.read(chessboardViewFromProviderNew.notifier).state =
        ChessboardView.tour;

    showAlertModal<void>(
      context: context,
      barrierDismissible: false,
      child: Container(
        padding: EdgeInsets.all(20.sp),
        decoration: BoxDecoration(
          color: context.colors.surface,
          borderRadius: BorderRadius.circular(16.br),
          border: Border.all(
            color: context.colors.textPrimary.withValues(alpha: 0.1),
            width: 1,
          ),
        ),
        child: CircularProgressIndicator(color: context.colors.textPrimary),
      ),
    );

    try {
      final tapped = items[index];
      final repo = ref.read(gamebaseRepositoryProvider);
      final gameWithPgn = await repo.getGameWithPgn(tapped.gameId);

      String? pgn;
      if (gameWithPgn != null) {
        final raw = gameWithPgn.pgn;
        if (raw != null && raw.trim().isNotEmpty && pgnHasMoves(raw)) {
          pgn = raw;
        }
        if (pgn == null && gameWithPgn.data != null) {
          final built = buildPgnFromGamebaseData(gameWithPgn.data);
          if (built != null && pgnHasMoves(built)) pgn = built;
        }
      }

      if (!mounted) return;
      Navigator.of(context).pop(); // loading

      final models =
          items.map((m) => m.toGamesTourModel()).toList(growable: false);
      final boardGames =
          pgn == null
              ? models
              : [
                for (var i = 0; i < models.length; i++)
                  i == index ? models[i].copyWith(pgn: pgn) : models[i],
              ];

      Navigator.of(context).push(
        MaterialPageRoute(
          builder:
              (_) => ChessBoardScreenNew(
                games: boardGames,
                currentIndex: index,
                showGamebaseButton: true,
                disableGamebaseOverlayByDefault: true,
              ),
        ),
      );
    } catch (e, st) {
      talker.handle(e, st);
      if (!mounted) return;
      Navigator.of(context).pop(); // loading
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Failed to open game')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.background,
      body: ScreenWrapper(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth:
                  ResponsiveHelper.isTablet
                      ? ResponsiveHelper.contentMaxWidth
                      : double.infinity,
            ),
            child: Column(
              children: [_buildTopArea(), Expanded(child: _buildList())],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTopArea() {
    final topPadding = MediaQuery.of(context).viewPadding.top;

    return Container(
      padding: EdgeInsets.only(top: topPadding + 8.h, bottom: 6.h),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            context.colors.background,
            context.colors.background.withValues(alpha: 0),
          ],
        ),
      ),
      child: Column(
        children: [
          _buildHeader(),
          _buildSearchRow(),
          _buildWindowSwitcher(),
          _buildCountSortRow(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final horizontalPadding = ResponsiveHelper.adaptive(
      phone: 8.w,
      tablet: 16.w,
    );
    return Padding(
      padding: EdgeInsets.fromLTRB(horizontalPadding, 0, horizontalPadding, 8.h),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: IconButton(
              onPressed: () {
                HapticFeedbackService.light();
                Navigator.of(context).pop();
              },
              icon: Icon(
                Icons.arrow_back_ios_new_rounded,
                color: context.colors.textPrimary.withValues(alpha: 0.7),
                size: 20.ic,
              ),
            ),
          ),
          Opacity(
            opacity: 0.8,
            child: Text(
              'Miniatures',
              style: AppTypography.textMdMedium.copyWith(
                fontWeight: FontWeight.w600,
                color: context.colors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchRow() {
    final horizontalPadding = ResponsiveHelper.adaptive(
      phone: 16.w,
      tablet: 24.w,
    );
    final filter = ref.watch(miniaturesFilterProvider);
    final isSubscribed = ref.watch(
      subscriptionProvider.select((s) => s.isSubscribed),
    );
    final unlocked = _premiumUnlocked || isSubscribed;

    final searchBar = LibrarySearchBar(
      controller: _searchController,
      focusNode: _searchFocusNode,
      enableOverlay: false,
      hintText: 'Search',
      rotatingHints: const ['player', 'event', 'opening', 'ECO'],
      onChanged: _onSearchChanged,
      onFilterTap: _openFilters,
      filterBadgeCount: filter.dialogFilterCount,
    );

    return Padding(
      padding: EdgeInsets.fromLTRB(
        horizontalPadding,
        0,
        horizontalPadding,
        8.h,
      ),
      child:
          unlocked
              ? searchBar
              // Free tier: browsing stays open, search/filters sit behind the
              // paywall. The whole row routes through the premium guard.
              : GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _handleLockedSearchTap,
                child: AbsorbPointer(child: searchBar),
              ),
    );
  }

  Widget _buildWindowSwitcher() {
    final horizontalPadding = ResponsiveHelper.adaptive(
      phone: 16.w,
      tablet: 24.w,
    );
    final window = ref.watch(
      miniaturesFilterProvider.select((f) => f.window),
    );

    return Padding(
      padding: EdgeInsets.fromLTRB(
        horizontalPadding,
        0,
        horizontalPadding,
        8.h,
      ),
      child: SegmentedSwitcher(
        options:
            MiniatureGamesWindow.values.map((w) => w.label).toList(),
        currentSelection: window.index,
        backgroundColor: context.colors.surface,
        selectedBackgroundColor: context.colors.surfaceRecessed,
        onSelectionChanged: _onWindowChanged,
      ),
    );
  }

  Widget _buildCountSortRow() {
    final horizontalPadding = ResponsiveHelper.adaptive(
      phone: 16.w,
      tablet: 24.w,
    );
    final paginationState = ref.watch(miniaturesPaginatedProvider);
    final sort = ref.watch(miniaturesFilterProvider.select((f) => f.sort));

    return Padding(
      padding: EdgeInsets.fromLTRB(
        horizontalPadding,
        0,
        horizontalPadding,
        4.h,
      ),
      child: Row(
        children: [
          if (paginationState.totalCount > 0)
            Text(
              '${formatCompactCount(paginationState.totalCount)} miniatures',
              style: AppTypography.textXsRegular.copyWith(
                color: context.colors.textPrimary.withValues(alpha: 0.4),
              ),
            ),
          const Spacer(),
          _SortChip(label: sort.label, onTap: _openSortSheet),
        ],
      ),
    );
  }

  Widget _buildList() {
    final paginationState = ref.watch(miniaturesPaginatedProvider);
    final items = paginationState.items;
    final horizontalPadding = ResponsiveHelper.adaptive(
      phone: 16.w,
      tablet: 24.w,
    );

    if (paginationState.error != null && items.isEmpty) {
      return _MiniaturesMessage(
        icon: Icons.cloud_off_rounded,
        title: 'Could not load miniatures',
        actionLabel: 'Retry',
        onAction:
            () => ref.read(miniaturesPaginatedProvider.notifier).refresh(),
      );
    }

    if (items.isEmpty && paginationState.isLoading) {
      return _buildSkeletonList(horizontalPadding);
    }

    if (items.isEmpty) {
      final filter = ref.read(miniaturesFilterProvider);
      return _MiniaturesMessage(
        icon: Icons.bolt_outlined,
        title: 'No miniatures found',
        subtitle:
            filter.hasActiveFilters || (filter.search?.isNotEmpty ?? false)
                ? 'Try a wider time window or fewer filters'
                : null,
      );
    }

    final itemCount = items.length + (paginationState.hasMore ? 1 : 0);

    return RefreshIndicator(
      onRefresh: () async {
        HapticFeedbackService.medium();
        await ref.read(miniaturesPaginatedProvider.notifier).refresh();
      },
      color: context.colors.textPrimary,
      backgroundColor: context.colors.surface,
      child: ListView.separated(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        padding: EdgeInsets.fromLTRB(
          horizontalPadding,
          4.h,
          horizontalPadding,
          24.h,
        ),
        itemCount: itemCount,
        separatorBuilder: (_, __) => SizedBox(height: 8.h),
        itemBuilder: (context, index) {
          if (index >= items.length) {
            return Padding(
              padding: EdgeInsets.symmetric(vertical: 16.h),
              child: Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    color: context.colors.textPrimary,
                    strokeWidth: 2,
                  ),
                ),
              ),
            );
          }
          return _MiniatureCard(
            miniature: items[index],
            onTap: () => _openMiniature(items, index),
          );
        },
      ),
    );
  }

  Widget _buildSkeletonList(double horizontalPadding) {
    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(
        horizontalPadding,
        4.h,
        horizontalPadding,
        24.h,
      ),
      child: SkeletonWidget(
        child: Column(
          children: [
            for (var i = 0; i < 8; i++) ...[
              Container(
                height: 92.h,
                decoration: BoxDecoration(
                  color: context.colors.surface,
                  borderRadius: BorderRadius.circular(12.br),
                ),
              ),
              SizedBox(height: 8.h),
            ],
          ],
        ),
      ),
    );
  }
}

class _SortChip extends StatelessWidget {
  const _SortChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
        decoration: BoxDecoration(
          color: context.colors.surface,
          borderRadius: BorderRadius.circular(20.br),
          border: Border.all(
            color: context.colors.textPrimary.withValues(alpha: 0.1),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.swap_vert_rounded,
              size: 15.ic,
              color: context.colors.textPrimary.withValues(alpha: 0.7),
            ),
            SizedBox(width: 6.w),
            Text(
              label,
              style: AppTypography.textXsMedium.copyWith(
                color: context.colors.textPrimary.withValues(alpha: 0.85),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniatureSortSheet extends StatelessWidget {
  const _MiniatureSortSheet({required this.current});

  final MiniatureGamesSort current;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          color: context.colors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20.br)),
        ),
        padding: EdgeInsets.only(bottom: 8.h),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: EdgeInsets.symmetric(vertical: 12.h),
              width: 40.w,
              height: 4.h,
              decoration: BoxDecoration(
                color: context.colors.textPrimary.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(2.br),
              ),
            ),
            for (final option in MiniatureGamesSort.values)
              // Transparent Material gives the ListTile an ink ancestor; the
              // colored sheet Container would otherwise hide it.
              Material(
                type: MaterialType.transparency,
                child: ListTile(
                  onTap: () {
                    HapticFeedbackService.selection();
                    Navigator.of(context).pop(option);
                  },
                  title: Text(
                    option.label,
                    style: AppTypography.textSmMedium.copyWith(
                      color: context.colors.textPrimary,
                    ),
                  ),
                  trailing:
                      option == current
                          ? Icon(
                            Icons.check_rounded,
                            color: kPrimaryColor,
                            size: 20.ic,
                          )
                          : null,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _MiniatureCard extends StatelessWidget {
  const _MiniatureCard({required this.miniature, required this.onTap});

  final GamebaseMiniature miniature;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final white = (miniature.whiteName ?? 'White').trim();
    final black = (miniature.blackName ?? 'Black').trim();
    final whiteWins = miniature.result != 'B';
    final event = (miniature.event ?? '').trim();
    final date = miniature.date;

    return TappableScale(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 12.h),
        decoration: BoxDecoration(
          color: context.colors.surface,
          borderRadius: BorderRadius.circular(12.br),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: _PlayerLine(
                    name: white,
                    elo: miniature.whiteElo,
                    isWinner: whiteWins,
                    alignEnd: false,
                  ),
                ),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8.w),
                  child: Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: 8.w,
                      vertical: 3.h,
                    ),
                    decoration: BoxDecoration(
                      color: context.colors.surfaceRecessed,
                      borderRadius: BorderRadius.circular(6.br),
                    ),
                    child: Text(
                      whiteWins ? '1-0' : '0-1',
                      style: AppTypography.textXsBold.copyWith(
                        color: context.colors.textPrimary,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: _PlayerLine(
                    name: black,
                    elo: miniature.blackElo,
                    isWinner: !whiteWins,
                    alignEnd: true,
                  ),
                ),
              ],
            ),
            SizedBox(height: 10.h),
            Row(
              children: [
                _MetaChip(
                  icon: Icons.bolt_rounded,
                  label: '${miniature.finalMoveNumber} moves',
                ),
                if (miniature.eco != null && miniature.eco!.isNotEmpty) ...[
                  SizedBox(width: 6.w),
                  _MetaChip(
                    icon: Icons.account_tree_rounded,
                    label: miniature.eco!,
                  ),
                ],
                const Spacer(),
                if (miniature.avgRating != null && miniature.avgRating! > 0)
                  _MetaChip(
                    icon: Icons.military_tech_rounded,
                    label: '${miniature.avgRating}',
                    accent: true,
                  ),
              ],
            ),
            if (event.isNotEmpty || date != null) ...[
              SizedBox(height: 8.h),
              Row(
                children: [
                  if (event.isNotEmpty) ...[
                    Icon(
                      Icons.emoji_events_outlined,
                      size: 13.ic,
                      color: context.colors.textPrimary.withValues(alpha: 0.4),
                    ),
                    SizedBox(width: 5.w),
                    Expanded(
                      child: Text(
                        event,
                        style: AppTypography.textXsRegular.copyWith(
                          color: context.colors.textPrimary.withValues(
                            alpha: 0.5,
                          ),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ] else
                    const Spacer(),
                  if (date != null) ...[
                    SizedBox(width: 8.w),
                    Text(
                      DateFormat('d MMM yyyy').format(date),
                      style: AppTypography.textXsRegular.copyWith(
                        color: context.colors.textPrimary.withValues(
                          alpha: 0.4,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PlayerLine extends StatelessWidget {
  const _PlayerLine({
    required this.name,
    required this.elo,
    required this.isWinner,
    required this.alignEnd,
  });

  final String name;
  final int? elo;
  final bool isWinner;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment:
          alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Text(
          name.isEmpty ? '-' : name,
          style: AppTypography.textSmMedium.copyWith(
            color: context.colors.textPrimary,
            fontWeight: isWinner ? FontWeight.w700 : FontWeight.w500,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        if (elo != null && elo! > 0) ...[
          SizedBox(height: 2.h),
          Text(
            '$elo',
            style: AppTypography.textXsRegular.copyWith(
              color: context.colors.textSecondary,
            ),
          ),
        ],
      ],
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({
    required this.icon,
    required this.label,
    this.accent = false,
  });

  final IconData icon;
  final String label;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final color =
        accent
            ? kPrimaryColor
            : context.colors.textPrimary.withValues(alpha: 0.6);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
      decoration: BoxDecoration(
        color:
            accent
                ? kPrimaryColor.withValues(alpha: 0.12)
                : context.colors.textPrimary.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(8.br),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12.ic, color: color),
          SizedBox(width: 4.w),
          Text(label, style: AppTypography.textXxsMedium.copyWith(color: color)),
        ],
      ),
    );
  }
}

class _MiniaturesMessage extends StatelessWidget {
  const _MiniaturesMessage({
    required this.icon,
    required this.title,
    this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      children: [
        SizedBox(height: 100.h),
        Icon(
          icon,
          size: 56.sp,
          color: context.colors.textPrimary.withValues(alpha: 0.4),
        ),
        SizedBox(height: 12.h),
        Center(
          child: Text(
            title,
            style: AppTypography.textMdMedium.copyWith(
              color: context.colors.textPrimary.withValues(alpha: 0.8),
            ),
          ),
        ),
        if (subtitle != null) ...[
          SizedBox(height: 6.h),
          Center(
            child: Text(
              subtitle!,
              style: AppTypography.textSmRegular.copyWith(
                color: context.colors.textPrimary.withValues(alpha: 0.5),
              ),
            ),
          ),
        ],
        if (actionLabel != null && onAction != null) ...[
          SizedBox(height: 12.h),
          Center(
            child: TextButton(
              onPressed: onAction,
              child: Text(
                actionLabel!,
                style: AppTypography.textSmMedium.copyWith(
                  color: kPrimaryColor,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
