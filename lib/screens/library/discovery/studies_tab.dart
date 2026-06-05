import 'package:chessever2/repository/gamebase/discovery/discovery_models.dart';
import 'package:chessever2/repository/gamebase/discovery/discovery_providers.dart';
import 'package:chessever2/repository/gamebase/gamebase_repository.dart';
import 'package:chessever2/screens/library/discovery/discovery_filter_widgets.dart';
import 'package:chessever2/screens/library/discovery/study_chapters_screen.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/skeleton_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:intl/intl.dart';

/// The Studies tab in the Library: curated Lichess studies, quality-ranked.
class StudiesTab extends ConsumerWidget {
  const StudiesTab({super.key});

  Future<void> _refresh(WidgetRef ref) async {
    HapticFeedbackService.medium();
    // Kick a backend re-sync, then reload the (possibly updated) list.
    await ref.read(gamebaseRepositoryProvider).refreshStudies();
    ref.invalidate(studiesListProvider);
    await ref.read(studiesListProvider.future);
  }

  Future<void> _pickSort(BuildContext context, WidgetRef ref) async {
    HapticFeedback.selectionClick();
    final current = ref.read(studiesQueryProvider).sort;
    final picked = await showModalBottomSheet<StudiesSort>(
      context: context,
      backgroundColor: Colors.transparent,
      builder:
          (_) => _SortSheet<StudiesSort>(
            title: 'Sort studies',
            current: current,
            options: StudiesSort.values,
            labelOf: (s) => s.label,
          ),
    );
    if (picked != null) ref.read(studiesQueryProvider.notifier).setSort(picked);
  }

  Future<void> _pickFilters(BuildContext context, WidgetRef ref) async {
    HapticFeedback.selectionClick();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _StudiesFilterSheet(),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final listAsync = ref.watch(studiesListProvider);
    final sort = ref.watch(studiesQueryProvider.select((q) => q.sort));
    final filterCount = ref.watch(
      studiesQueryProvider.select((q) => q.activeFilterCount),
    );

    return RefreshIndicator(
      onRefresh: () => _refresh(ref),
      color: context.colors.textPrimary,
      backgroundColor: context.colors.surface,
      child: CustomScrollView(
        primary: false,
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(16.w, 4.h, 16.w, 8.h),
              child: Row(
                children: [
                  FilterButton(
                    count: filterCount,
                    onTap: () => _pickFilters(context, ref),
                  ),
                  const Spacer(),
                  _SortChip(
                    label: sort.label,
                    onTap: () => _pickSort(context, ref),
                  ),
                ],
              ),
            ),
          ),
          listAsync.when(
            data: (page) {
              if (page.items.isEmpty) {
                return const SliverFillRemaining(
                  hasScrollBody: false,
                  child: _EmptyStudies(),
                );
              }
              return SliverPadding(
                padding: EdgeInsets.fromLTRB(16.w, 4.h, 16.w, 24.h),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, i) => Padding(
                      padding: EdgeInsets.only(bottom: 8.h),
                      child: _StudyCard(study: page.items[i]),
                    ),
                    childCount: page.items.length,
                  ),
                ),
              );
            },
            loading: () => const _StudiesLoadingSliver(),
            error: (e, _) => SliverFillRemaining(
              hasScrollBody: false,
              child: _DiscoveryError(
                message: 'Could not load studies',
                onRetry: () => ref.invalidate(studiesListProvider),
              ),
            ),
          ),
        ],
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

/// ECO categories are a fixed A–E set (not facet-dependent).
const List<String> _ecoCategories = ['A', 'B', 'C', 'D', 'E'];

class _StudiesFilterSheet extends ConsumerStatefulWidget {
  const _StudiesFilterSheet();

  @override
  ConsumerState<_StudiesFilterSheet> createState() =>
      _StudiesFilterSheetState();
}

class _StudiesFilterSheetState extends ConsumerState<_StudiesFilterSheet> {
  late Set<String> _eco;
  late Set<String> _variants;
  late Set<String> _chapterModes;
  bool? _gamebook;
  bool? _hasAnnotations;

  @override
  void initState() {
    super.initState();
    final q = ref.read(studiesQueryProvider);
    _eco = {...q.ecoCategories};
    _variants = {...q.variants};
    _chapterModes = {...q.chapterModes};
    _gamebook = q.gamebook;
    _hasAnnotations = q.hasAnnotations;
  }

  void _toggle(Set<String> set, String value) {
    setState(() {
      if (!set.remove(value)) set.add(value);
    });
  }

  @override
  Widget build(BuildContext context) {
    final facets = ref.watch(studyFacetsProvider).valueOrNull ?? StudyFacets.empty;

    return FilterSheetScaffold(
      title: 'Filter studies',
      onClear: () {
        setState(() {
          _eco = {};
          _variants = {};
          _chapterModes = {};
          _gamebook = null;
          _hasAnnotations = null;
        });
      },
      onApply: () {
        ref.read(studiesQueryProvider.notifier).applyFilters(
              ecoCategories: _eco,
              variants: _variants,
              chapterModes: _chapterModes,
              gamebook: _gamebook,
              hasAnnotations: _hasAnnotations,
            );
        Navigator.of(context).pop();
      },
      children: [
        FilterSection(
          title: 'ECO CATEGORY',
          child: Wrap(
            spacing: 8.w,
            runSpacing: 8.h,
            children: [
              for (final c in _ecoCategories)
                FilterPill(
                  label: c,
                  selected: _eco.contains(c),
                  onTap: () => _toggle(_eco, c),
                ),
            ],
          ),
        ),
        if (facets.variants.isNotEmpty) ...[
          SizedBox(height: 20.h),
          FilterSection(
            title: 'VARIANT',
            child: Wrap(
              spacing: 8.w,
              runSpacing: 8.h,
              children: [
                for (final v in facets.variants)
                  FilterPill(
                    label: v,
                    selected: _variants.contains(v),
                    onTap: () => _toggle(_variants, v),
                  ),
              ],
            ),
          ),
        ],
        if (facets.chapterModes.isNotEmpty) ...[
          SizedBox(height: 20.h),
          FilterSection(
            title: 'CHAPTER TYPE',
            child: Wrap(
              spacing: 8.w,
              runSpacing: 8.h,
              children: [
                for (final m in facets.chapterModes)
                  FilterPill(
                    label: m,
                    selected: _chapterModes.contains(m),
                    onTap: () => _toggle(_chapterModes, m),
                  ),
              ],
            ),
          ),
        ],
        SizedBox(height: 20.h),
        TriToggle(
          label: 'Interactive (gamebook)',
          value: _gamebook,
          onChanged: (v) => setState(() => _gamebook = v),
        ),
        SizedBox(height: 14.h),
        TriToggle(
          label: 'Has annotations',
          value: _hasAnnotations,
          onChanged: (v) => setState(() => _hasAnnotations = v),
        ),
        SizedBox(height: 8.h),
      ],
    );
  }
}

class _StudyCard extends StatelessWidget {
  const _StudyCard({required this.study});

  final LichessStudy study;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedbackService.cardTap();
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => StudyChaptersScreen(study: study),
          ),
        );
      },
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 14.h),
        decoration: BoxDecoration(
          color: context.colors.surface,
          borderRadius: BorderRadius.circular(12.br),
        ),
        child: Row(
          children: [
            Container(
              width: 44.h,
              height: 44.h,
              decoration: BoxDecoration(
                color: kPrimaryColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12.br),
              ),
              child: Icon(
                Icons.menu_book_rounded,
                color: kPrimaryColor,
                size: 22.sp,
              ),
            ),
            SizedBox(width: 12.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    study.name,
                    style: AppTypography.textSmMedium.copyWith(
                      color: context.colors.textPrimary,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  SizedBox(height: 4.h),
                  Text(
                    _subtitle(),
                    style: AppTypography.textXsRegular.copyWith(
                      color: const Color(0xFFA1A1A1),
                      height: 16 / 12,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            SizedBox(width: 8.w),
            _QualityBadge(score: study.credibilityScore),
            SizedBox(width: 4.w),
            Icon(
              Icons.chevron_right_rounded,
              size: 20.sp,
              color: context.colors.textPrimary.withValues(alpha: 0.5),
            ),
          ],
        ),
      ),
    );
  }

  String _subtitle() {
    final parts = <String>[
      study.chapterCount == 1 ? '1 chapter' : '${study.chapterCount} chapters',
    ];
    final updated = _timeAgo(study.lichessUpdatedAt);
    if (updated != null) parts.add('updated $updated');
    if (study.authorUsername != null && study.authorUsername!.isNotEmpty) {
      parts.add('by ${study.authorUsername}');
    }
    return parts.join('  ·  ');
  }
}

class _QualityBadge extends StatelessWidget {
  const _QualityBadge({required this.score});

  final double score;

  @override
  Widget build(BuildContext context) {
    final value = score.clamp(0, 100).round();
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
      decoration: BoxDecoration(
        color: kPrimaryColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8.br),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.star_rounded, size: 12.sp, color: kPrimaryColor),
          SizedBox(width: 3.w),
          Text(
            '$value',
            style: AppTypography.textXxsBold.copyWith(color: kPrimaryColor),
          ),
        ],
      ),
    );
  }
}

String? _timeAgo(DateTime? date) {
  if (date == null) return null;
  final now = DateTime.now();
  final diff = now.difference(date.toLocal());
  if (diff.inDays == 0) return 'today';
  if (diff.inDays == 1) return 'yesterday';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  if (diff.inDays < 30) return '${(diff.inDays / 7).floor()}w ago';
  return DateFormat('MMM yyyy').format(date.toLocal());
}

/// Reusable single-select sort sheet.
class _SortSheet<T> extends StatelessWidget {
  const _SortSheet({
    required this.title,
    required this.current,
    required this.options,
    required this.labelOf,
  });

  final String title;
  final T current;
  final List<T> options;
  final String Function(T) labelOf;

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
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 4.h),
              child: Row(
                children: [
                  Text(
                    title,
                    style: AppTypography.textMdBold.copyWith(
                      color: context.colors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
            for (final option in options)
              ListTile(
                onTap: () => Navigator.of(context).pop(option),
                title: Text(
                  labelOf(option),
                  style: AppTypography.textSmMedium.copyWith(
                    color: context.colors.textPrimary,
                  ),
                ),
                trailing:
                    option == current
                        ? Icon(Icons.check_rounded, color: kPrimaryColor, size: 20.sp)
                        : null,
              ),
          ],
        ),
      ),
    );
  }
}

class _StudiesLoadingSliver extends StatelessWidget {
  const _StudiesLoadingSliver();

  @override
  Widget build(BuildContext context) {
    return SliverPadding(
      padding: EdgeInsets.fromLTRB(16.w, 4.h, 16.w, 24.h),
      sliver: SliverToBoxAdapter(
        child: SkeletonWidget(
          child: Column(
            children: [
              for (var i = 0; i < 6; i++) ...[
                Container(
                  height: 72.h,
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
      ),
    );
  }
}

class _EmptyStudies extends StatelessWidget {
  const _EmptyStudies();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.menu_book_outlined,
            size: 56.sp,
            color: context.colors.textPrimary.withValues(alpha: 0.4),
          ),
          SizedBox(height: 12.h),
          Text(
            'No studies yet',
            style: AppTypography.textMdMedium.copyWith(
              color: context.colors.textPrimary.withValues(alpha: 0.8),
            ),
          ),
          SizedBox(height: 6.h),
          Text(
            'Pull to refresh',
            style: AppTypography.textSmRegular.copyWith(
              color: context.colors.textPrimary.withValues(alpha: 0.5),
            ),
          ),
        ],
      ),
    );
  }
}

class _DiscoveryError extends StatelessWidget {
  const _DiscoveryError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.cloud_off_rounded, size: 48.sp, color: kRedColor.withValues(alpha: 0.7)),
          SizedBox(height: 12.h),
          Text(
            message,
            style: AppTypography.textMdMedium.copyWith(
              color: context.colors.textPrimary,
            ),
          ),
          SizedBox(height: 12.h),
          TextButton(
            onPressed: onRetry,
            child: Text(
              'Retry',
              style: AppTypography.textSmMedium.copyWith(color: kPrimaryColor),
            ),
          ),
        ],
      ),
    );
  }
}
