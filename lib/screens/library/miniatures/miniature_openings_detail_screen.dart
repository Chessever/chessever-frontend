import 'package:chessever2/repository/gamebase/miniatures/miniatures_models.dart';
import 'package:chessever2/screens/library/providers/miniatures_provider.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/number_format_utils.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/skeleton_widget.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// ECO volume letters spelled out, so the breakdown reads as chess rather
/// than as database codes. Mirrors `_ecoCategoryNames` in
/// miniatures_about_tab.dart (file-private there, so copied here).
const Map<String, String> _ecoCategoryNames = {
  'A': 'Flank & irregular openings',
  'B': 'Semi-open games (Sicilian, Caro-Kann…)',
  'C': 'Open games & the French',
  'D': 'Closed & semi-closed games',
  'E': 'Indian defences',
};

enum _OpeningSort {
  mostGames('Most games'),
  fewestMoves('Fewest moves');

  const _OpeningSort(this.label);

  final String label;
}

/// Full drill-down for the About tab's "Openings that keep producing them"
/// section: every opening in the active window (up to 50, as fetched by
/// [miniatureStatsProvider]), searchable by ECO or name and sortable, with an
/// ECO-volume summary up top for the big picture.
class MiniatureOpeningsDetailScreen extends ConsumerStatefulWidget {
  const MiniatureOpeningsDetailScreen({super.key, required this.window});

  final MiniatureGamesWindow window;

  @override
  ConsumerState<MiniatureOpeningsDetailScreen> createState() =>
      _MiniatureOpeningsDetailScreenState();
}

class _MiniatureOpeningsDetailScreenState
    extends ConsumerState<MiniatureOpeningsDetailScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  _OpeningSort _sort = _OpeningSort.mostGames;
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    setState(() => _query = value.trim());
  }

  void _clearSearch() {
    _searchController.clear();
    _onQueryChanged('');
  }

  void _onSortChanged(_OpeningSort sort) {
    if (sort == _sort) return;
    HapticFeedbackService.selection();
    setState(() => _sort = sort);
  }

  @override
  Widget build(BuildContext context) {
    final statsAsync = ref.watch(miniatureStatsProvider(widget.window));
    final horizontalPadding = ResponsiveHelper.adaptive(
      phone: 16.w,
      tablet: 24.w,
    );
    final padding = EdgeInsets.fromLTRB(
      horizontalPadding,
      12.h,
      horizontalPadding,
      32.h,
    );

    Widget content = statsAsync.when(
      loading:
          () =>
              ListView(padding: padding, children: const [_OpeningsSkeleton()]),
      error:
          (error, _) => ListView(
            padding: padding,
            children: [
              _OpeningsError(
                onRetry:
                    () => ref.invalidate(miniatureStatsProvider(widget.window)),
              ),
            ],
          ),
      data:
          (stats) => _OpeningsBody(
            stats: stats,
            padding: padding,
            searchController: _searchController,
            searchFocusNode: _searchFocusNode,
            query: _query,
            onQueryChanged: _onQueryChanged,
            onClearSearch: _clearSearch,
            sort: _sort,
            onSortChanged: _onSortChanged,
          ),
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

    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: AppBar(
        backgroundColor: context.colors.background,
        elevation: 0,
        title: Text(
          'Openings that produce miniatures',
          style: AppTypography.textMdMedium.copyWith(
            color: context.colors.textPrimary,
          ),
        ),
      ),
      body: SafeArea(child: content),
    );
  }
}

class _OpeningsBody extends StatelessWidget {
  const _OpeningsBody({
    required this.stats,
    required this.padding,
    required this.searchController,
    required this.searchFocusNode,
    required this.query,
    required this.onQueryChanged,
    required this.onClearSearch,
    required this.sort,
    required this.onSortChanged,
  });

  final MiniatureStats stats;
  final EdgeInsets padding;
  final TextEditingController searchController;
  final FocusNode searchFocusNode;
  final String query;
  final ValueChanged<String> onQueryChanged;
  final VoidCallback onClearSearch;
  final _OpeningSort sort;
  final ValueChanged<_OpeningSort> onSortChanged;

  List<MiniatureOpeningStat> _filter() {
    final normalized = query.toLowerCase();
    final list =
        normalized.isEmpty
            ? List<MiniatureOpeningStat>.from(stats.byOpening)
            : stats.byOpening
                .where((opening) {
                  final eco = (opening.eco ?? '').toLowerCase();
                  final name = opening.displayName.toLowerCase();
                  return eco.contains(normalized) || name.contains(normalized);
                })
                .toList(growable: false);

    list.sort((a, b) {
      return switch (sort) {
        _OpeningSort.mostGames => b.games.compareTo(a.games),
        _OpeningSort.fewestMoves => a.avgMoves.compareTo(b.avgMoves),
      };
    });
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filter();
    final peak = stats.byOpening.fold<int>(
      1,
      (max, opening) => opening.games > max ? opening.games : max,
    );

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      padding: padding,
      children: [
        if (stats.byEcoCategory.isNotEmpty) ...[
          _EcoVolumeBreakdown(stats: stats),
          SizedBox(height: 24.h),
        ],
        _SearchField(
          controller: searchController,
          focusNode: searchFocusNode,
          onChanged: onQueryChanged,
          onClear: onClearSearch,
        ),
        SizedBox(height: 12.h),
        _SortChips(sort: sort, onChanged: onSortChanged),
        SizedBox(height: 16.h),
        if (stats.byOpening.isEmpty)
          const _EmptyMessage(text: 'No opening data in this window yet.')
        else if (filtered.isEmpty)
          _EmptyMessage(text: 'No openings match "$query".')
        else ...[
          Text(
            query.isEmpty
                ? '${stats.byOpening.length} openings, sorted by '
                    '${sort.label.toLowerCase()}.'
                : '${filtered.length} match "$query".',
            style: AppTypography.textXsRegular.copyWith(
              color: context.colors.textTertiary,
            ),
          ),
          SizedBox(height: 10.h),
          for (final opening in filtered)
            Padding(
              padding: EdgeInsets.only(bottom: 8.h),
              child: _OpeningCard(opening: opening, peak: peak),
            ),
        ],
      ],
    );
  }
}

class _EcoVolumeBreakdown extends StatelessWidget {
  const _EcoVolumeBreakdown({required this.stats});

  final MiniatureStats stats;

  @override
  Widget build(BuildContext context) {
    final peak = stats.byEcoCategory.fold<int>(
      1,
      (max, bucket) => bucket.games > max ? bucket.games : max,
    );
    final totalEco = stats.byEcoCategory.fold<int>(
      0,
      (sum, bucket) => sum + bucket.games,
    );
    final leader = stats.byEcoCategory.reduce(
      (a, b) => a.games >= b.games ? a : b,
    );
    final leaderPercent = totalEco == 0 ? 0.0 : leader.games / totalEco * 100;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Where they come from',
          style: AppTypography.textMdMedium.copyWith(
            color: context.colors.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
        SizedBox(height: 6.h),
        Text(
          '${formatCompactCount(totalEco)} miniatures split across '
          '${stats.byEcoCategory.length} ECO volumes. Volume '
          '${leader.value ?? "–"} leads with ${_trimDecimal(leaderPercent)}%.',
          style: AppTypography.textXsRegular.copyWith(
            color: context.colors.textSecondary,
            height: 1.45,
          ),
        ),
        SizedBox(height: 12.h),
        for (final bucket in stats.byEcoCategory)
          Padding(
            padding: EdgeInsets.only(bottom: 12.h),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    SizedBox(
                      width: 18.w,
                      child: Text(
                        bucket.value ?? '–',
                        style: AppTypography.textSmMedium.copyWith(
                          color: kPrimaryColor,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        _ecoCategoryNames[bucket.value] ?? 'Unclassified',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.textXsRegular.copyWith(
                          color: context.colors.textPrimary,
                        ),
                      ),
                    ),
                    SizedBox(width: 8.w),
                    Text(
                      '${formatCompactCount(bucket.games)} · '
                      '${_trimDecimal(bucket.whiteWinRate)}% W',
                      style: AppTypography.textXsRegular.copyWith(
                        color: context.colors.textSecondary,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 6.h),
                _ProportionBar(fraction: bucket.games / peak),
              ],
            ),
          ),
      ],
    );
  }
}

class _ProportionBar extends StatelessWidget {
  const _ProportionBar({required this.fraction});

  final double fraction;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(3.br),
      child: SizedBox(
        height: 6.h,
        child: Stack(
          children: [
            Positioned.fill(
              child: ColoredBox(color: context.colors.surfaceRecessed),
            ),
            FractionallySizedBox(
              widthFactor: fraction.clamp(0.02, 1.0),
              heightFactor: 1,
              alignment: Alignment.centerLeft,
              child: ColoredBox(color: kPrimaryColor.withValues(alpha: 0.75)),
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.onClear,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48.h,
      child: Container(
        decoration: BoxDecoration(
          color: context.colors.background,
          borderRadius: BorderRadius.circular(12.br),
          border: Border.all(color: context.colors.surfaceRecessed),
        ),
        child: Row(
          children: [
            SizedBox(width: 12.w),
            Icon(
              Icons.search,
              size: 20.sp,
              color: context.colors.textSecondary,
            ),
            SizedBox(width: 8.w),
            Expanded(
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                style: AppTypography.textSmRegular.copyWith(
                  color: context.colors.textPrimary,
                ),
                onChanged: onChanged,
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Search opening or ECO code',
                  hintStyle: AppTypography.textSmRegular.copyWith(
                    color: context.colors.textSecondary,
                  ),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(vertical: 14.h),
                ),
              ),
            ),
            if (controller.text.isNotEmpty) ...[
              GestureDetector(
                onTap: onClear,
                child: Icon(
                  Icons.close,
                  size: 20.sp,
                  color: context.colors.textSecondary,
                ),
              ),
              SizedBox(width: 8.w),
            ],
            SizedBox(width: 8.w),
          ],
        ),
      ),
    );
  }
}

class _SortChips extends StatelessWidget {
  const _SortChips({required this.sort, required this.onChanged});

  final _OpeningSort sort;
  final ValueChanged<_OpeningSort> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8.w,
      runSpacing: 8.h,
      children: [
        for (final option in _OpeningSort.values)
          _SortChip(
            label: option.label,
            isSelected: option == sort,
            onTap: () => onChanged(option),
          ),
      ],
    );
  }
}

class _SortChip extends StatelessWidget {
  const _SortChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 10.h),
        decoration: BoxDecoration(
          color: isSelected ? kPrimaryColor : context.colors.surfaceRecessed,
          borderRadius: BorderRadius.circular(8.br),
        ),
        child: Text(
          label,
          style: AppTypography.textXsMedium.copyWith(
            color: isSelected ? kBlackColor : context.colors.textPrimary,
          ),
        ),
      ),
    );
  }
}

class _OpeningCard extends StatelessWidget {
  const _OpeningCard({required this.opening, required this.peak});

  final MiniatureOpeningStat opening;
  final int peak;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 12.h),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(12.br),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 40.w,
                child: Text(
                  opening.eco ?? '–',
                  style: AppTypography.textSmBold.copyWith(
                    color: kPrimaryColor,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  opening.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.textSmRegular.copyWith(
                    color: context.colors.textPrimary,
                  ),
                ),
              ),
              SizedBox(width: 8.w),
              Text(
                '${formatCompactCount(opening.games)} · '
                '${_trimDecimal(opening.avgMoves)} mv',
                style: AppTypography.textXsRegular.copyWith(
                  color: context.colors.textSecondary,
                ),
              ),
            ],
          ),
          SizedBox(height: 8.h),
          _ProportionBar(fraction: opening.games / peak),
        ],
      ),
    );
  }
}

class _EmptyMessage extends StatelessWidget {
  const _EmptyMessage({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 40.h),
      child: Center(
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: AppTypography.textSmRegular.copyWith(
            color: context.colors.textSecondary,
          ),
        ),
      ),
    );
  }
}

class _OpeningsSkeleton extends StatelessWidget {
  const _OpeningsSkeleton();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SkeletonWidget(
          child: Container(
            height: 190.h,
            decoration: BoxDecoration(
              color: context.colors.surface,
              borderRadius: BorderRadius.circular(12.br),
            ),
          ),
        ),
        SizedBox(height: 24.h),
        SkeletonWidget(
          child: Container(
            height: 48.h,
            decoration: BoxDecoration(
              color: context.colors.surface,
              borderRadius: BorderRadius.circular(12.br),
            ),
          ),
        ),
        SizedBox(height: 12.h),
        SkeletonWidget(
          child: Container(
            height: 36.h,
            width: 180.w,
            decoration: BoxDecoration(
              color: context.colors.surface,
              borderRadius: BorderRadius.circular(8.br),
            ),
          ),
        ),
        SizedBox(height: 16.h),
        for (var i = 0; i < 5; i++)
          Padding(
            padding: EdgeInsets.only(bottom: 8.h),
            child: SkeletonWidget(
              child: Container(
                height: 64.h,
                decoration: BoxDecoration(
                  color: context.colors.surface,
                  borderRadius: BorderRadius.circular(12.br),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _OpeningsError extends StatelessWidget {
  const _OpeningsError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 40.h),
      child: Column(
        children: [
          Icon(
            Icons.cloud_off_rounded,
            size: 36.sp,
            color: context.colors.textSecondary,
          ),
          SizedBox(height: 14.h),
          Text(
            'Could not load the numbers',
            style: AppTypography.textSmMedium.copyWith(
              color: context.colors.textPrimary,
            ),
          ),
          SizedBox(height: 16.h),
          GestureDetector(
            onTap: onRetry,
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 10.h),
              decoration: BoxDecoration(
                color: context.colors.surfaceRecessed,
                borderRadius: BorderRadius.circular(10.br),
              ),
              child: Text(
                'Retry',
                style: AppTypography.textXsMedium.copyWith(
                  color: context.colors.textPrimary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// `20.0` reads as noise next to `20.2`, so whole numbers drop the decimal.
String _trimDecimal(double value) {
  if (value == value.roundToDouble()) return value.round().toString();
  return value.toStringAsFixed(1);
}
