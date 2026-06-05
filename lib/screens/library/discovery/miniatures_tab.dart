import 'package:chessever2/repository/gamebase/discovery/discovery_models.dart';
import 'package:chessever2/repository/gamebase/discovery/discovery_providers.dart';
import 'package:chessever2/screens/library/discovery/discovery_filter_widgets.dart';
import 'package:chessever2/screens/chessboard/chess_board_screen_new.dart';
import 'package:chessever2/screens/chessboard/provider/chess_board_screen_provider_new.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/segmented_switcher.dart';
import 'package:chessever2/widgets/skeleton_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Discovery → Miniatures: community feed of short decisive games.
class MiniaturesTab extends ConsumerWidget {
  const MiniaturesTab({super.key});

  Future<void> _pickSort(BuildContext context, WidgetRef ref) async {
    HapticFeedback.selectionClick();
    final current = ref.read(miniaturesQueryProvider).sort;
    final picked = await showModalBottomSheet<MiniatureSort>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _MiniatureSortSheet(current: current),
    );
    if (picked != null) {
      ref.read(miniaturesQueryProvider.notifier).setSort(picked);
    }
  }

  Future<void> _pickFilters(BuildContext context, WidgetRef ref) async {
    HapticFeedback.selectionClick();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _MiniaturesFilterSheet(),
    );
  }

  void _openMiniature(
    BuildContext context,
    WidgetRef ref,
    List<Miniature> all,
    int index,
  ) {
    HapticFeedbackService.cardTap();
    final models = all.map((m) => m.toGamesTourModel()).toList();
    ref.read(chessboardViewFromProviderNew.notifier).state =
        ChessboardView.tour;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChessBoardScreenNew(
          currentIndex: index,
          games: models,
          showGamebaseButton: true,
          disableGamebaseOverlayByDefault: true,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = ref.watch(miniaturesQueryProvider);
    final listAsync = ref.watch(miniaturesListProvider);

    return Column(
      children: [
        // Window sub-tabs (Today / Week / All time).
        Padding(
          padding: EdgeInsets.fromLTRB(16.w, 4.h, 16.w, 8.h),
          child: SegmentedSwitcher(
            options: const ['Today', 'Week', 'All time'],
            currentSelection: query.window.index,
            backgroundColor: context.colors.surface,
            selectedBackgroundColor: context.colors.surfaceRecessed,
            onSelectionChanged: (i) {
              HapticFeedback.selectionClick();
              ref
                  .read(miniaturesQueryProvider.notifier)
                  .setWindow(MiniatureWindow.values[i]);
            },
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(16.w, 0, 16.w, 8.h),
          child: Row(
            children: [
              FilterButton(
                count: query.activeFilterCount,
                onTap: () => _pickFilters(context, ref),
              ),
              const Spacer(),
              _SortChip(
                label: query.sort.label,
                onTap: () => _pickSort(context, ref),
              ),
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async {
              HapticFeedbackService.medium();
              ref.invalidate(miniaturesListProvider);
              await ref.read(miniaturesListProvider.future);
            },
            color: context.colors.textPrimary,
            backgroundColor: context.colors.surface,
            child: listAsync.when(
              data: (page) {
                if (page.items.isEmpty) {
                  return const _EmptyMiniatures();
                }
                return ListView.separated(
                  primary: false,
                  physics: const AlwaysScrollableScrollPhysics(
                    parent: BouncingScrollPhysics(),
                  ),
                  padding: EdgeInsets.fromLTRB(16.w, 4.h, 16.w, 24.h),
                  itemCount: page.items.length,
                  separatorBuilder: (_, __) => SizedBox(height: 8.h),
                  itemBuilder: (context, i) => _MiniatureCard(
                    miniature: page.items[i],
                    onTap: () =>
                        _openMiniature(context, ref, page.items, i),
                  ),
                );
              },
              loading: () => _MiniaturesLoading(),
              error: (e, _) => _MiniaturesError(
                onRetry: () => ref.invalidate(miniaturesListProvider),
              ),
            ),
          ),
        ),
      ],
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
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 7.h),
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
            Icon(Icons.swap_vert_rounded, size: 15.sp, color: kPrimaryColor),
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

const List<String> _miniatureEcoCategories = ['A', 'B', 'C', 'D', 'E'];

class _MiniaturesFilterSheet extends ConsumerStatefulWidget {
  const _MiniaturesFilterSheet();

  @override
  ConsumerState<_MiniaturesFilterSheet> createState() =>
      _MiniaturesFilterSheetState();
}

class _MiniaturesFilterSheetState
    extends ConsumerState<_MiniaturesFilterSheet> {
  late Set<String> _results;
  late Set<String> _timeControls;
  late Set<String> _eco;

  @override
  void initState() {
    super.initState();
    final q = ref.read(miniaturesQueryProvider);
    _results = {...q.results};
    _timeControls = {...q.timeControls};
    _eco = {...q.ecoCategories};
  }

  void _toggle(Set<String> set, String value) {
    setState(() {
      if (!set.remove(value)) set.add(value);
    });
  }

  @override
  Widget build(BuildContext context) {
    return FilterSheetScaffold(
      title: 'Filter miniatures',
      onClear: () {
        setState(() {
          _results = {};
          _timeControls = {};
          _eco = {};
        });
      },
      onApply: () {
        ref.read(miniaturesQueryProvider.notifier).applyFilters(
              results: _results,
              timeControls: _timeControls,
              ecoCategories: _eco,
            );
        Navigator.of(context).pop();
      },
      children: [
        FilterSection(
          title: 'RESULT',
          child: Wrap(
            spacing: 8.w,
            runSpacing: 8.h,
            children: [
              FilterPill(
                label: 'White wins',
                selected: _results.contains('W'),
                onTap: () => _toggle(_results, 'W'),
              ),
              FilterPill(
                label: 'Black wins',
                selected: _results.contains('B'),
                onTap: () => _toggle(_results, 'B'),
              ),
            ],
          ),
        ),
        SizedBox(height: 20.h),
        FilterSection(
          title: 'TIME CONTROL',
          child: Wrap(
            spacing: 8.w,
            runSpacing: 8.h,
            children: [
              for (final tc in const ['CLASSICAL', 'RAPID', 'BLITZ'])
                FilterPill(
                  label: tc[0] + tc.substring(1).toLowerCase(),
                  selected: _timeControls.contains(tc),
                  onTap: () => _toggle(_timeControls, tc),
                ),
            ],
          ),
        ),
        SizedBox(height: 20.h),
        FilterSection(
          title: 'ECO CATEGORY',
          child: Wrap(
            spacing: 8.w,
            runSpacing: 8.h,
            children: [
              for (final c in _miniatureEcoCategories)
                FilterPill(
                  label: c,
                  selected: _eco.contains(c),
                  onTap: () => _toggle(_eco, c),
                ),
            ],
          ),
        ),
        SizedBox(height: 8.h),
      ],
    );
  }
}

class _MiniatureCard extends StatelessWidget {
  const _MiniatureCard({required this.miniature, required this.onTap});

  final Miniature miniature;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final white = (miniature.whiteName ?? 'White').trim();
    final black = (miniature.blackName ?? 'Black').trim();
    final whiteWins = miniature.result == 'W';

    return GestureDetector(
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
                    padding:
                        EdgeInsets.symmetric(horizontal: 8.w, vertical: 3.h),
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
                _Chip(
                  icon: Icons.bolt_rounded,
                  label: 'M${miniature.finalMoveNumber}',
                ),
                SizedBox(width: 6.w),
                if (miniature.eco != null && miniature.eco!.isNotEmpty)
                  _Chip(icon: Icons.account_tree_rounded, label: miniature.eco!),
                const Spacer(),
                if (miniature.avgRating != null)
                  _Chip(
                    icon: Icons.military_tech_rounded,
                    label: '${miniature.avgRating}',
                    accent: true,
                  ),
              ],
            ),
            if ((miniature.event ?? '').trim().isNotEmpty) ...[
              SizedBox(height: 8.h),
              Row(
                children: [
                  Icon(
                    Icons.emoji_events_outlined,
                    size: 13.sp,
                    color: context.colors.textPrimary.withValues(alpha: 0.4),
                  ),
                  SizedBox(width: 5.w),
                  Expanded(
                    child: Text(
                      miniature.event!.trim(),
                      style: AppTypography.textXsRegular.copyWith(
                        color: context.colors.textPrimary.withValues(alpha: 0.5),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
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
          name.isEmpty ? '—' : name,
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

class _Chip extends StatelessWidget {
  const _Chip({required this.icon, required this.label, this.accent = false});

  final IconData icon;
  final String label;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final color =
        accent ? kPrimaryColor : context.colors.textPrimary.withValues(alpha: 0.6);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
      decoration: BoxDecoration(
        color: accent
            ? kPrimaryColor.withValues(alpha: 0.12)
            : context.colors.textPrimary.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(8.br),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12.sp, color: color),
          SizedBox(width: 4.w),
          Text(
            label,
            style: AppTypography.textXxsMedium.copyWith(color: color),
          ),
        ],
      ),
    );
  }
}

class _MiniatureSortSheet extends StatelessWidget {
  const _MiniatureSortSheet({required this.current});

  final MiniatureSort current;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          color: context.colors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24.br)),
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
            for (final option in MiniatureSort.values)
              ListTile(
                onTap: () => Navigator.of(context).pop(option),
                title: Text(
                  option.label,
                  style: AppTypography.textSmMedium.copyWith(
                    color: context.colors.textPrimary,
                  ),
                ),
                trailing: option == current
                    ? Icon(Icons.check_rounded, color: kPrimaryColor, size: 20.sp)
                    : null,
              ),
          ],
        ),
      ),
    );
  }
}

class _MiniaturesLoading extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(16.w, 4.h, 16.w, 24.h),
      child: SkeletonWidget(
        child: Column(
          children: [
            for (var i = 0; i < 6; i++) ...[
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

class _EmptyMiniatures extends StatelessWidget {
  const _EmptyMiniatures();

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        SizedBox(height: 120.h),
        Icon(
          Icons.bolt_outlined,
          size: 56.sp,
          color: context.colors.textPrimary.withValues(alpha: 0.4),
        ),
        SizedBox(height: 12.h),
        Center(
          child: Text(
            'No miniatures in this window',
            style: AppTypography.textMdMedium.copyWith(
              color: context.colors.textPrimary.withValues(alpha: 0.8),
            ),
          ),
        ),
        SizedBox(height: 6.h),
        Center(
          child: Text(
            'Try a wider time window',
            style: AppTypography.textSmRegular.copyWith(
              color: context.colors.textPrimary.withValues(alpha: 0.5),
            ),
          ),
        ),
      ],
    );
  }
}

class _MiniaturesError extends StatelessWidget {
  const _MiniaturesError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        SizedBox(height: 120.h),
        Icon(Icons.cloud_off_rounded, size: 48.sp, color: kRedColor.withValues(alpha: 0.7)),
        SizedBox(height: 12.h),
        Center(
          child: Text(
            'Could not load miniatures',
            style: AppTypography.textMdMedium.copyWith(
              color: context.colors.textPrimary,
            ),
          ),
        ),
        SizedBox(height: 12.h),
        Center(
          child: TextButton(
            onPressed: onRetry,
            child: Text(
              'Retry',
              style: AppTypography.textSmMedium.copyWith(color: kPrimaryColor),
            ),
          ),
        ),
      ],
    );
  }
}
