import 'dart:async';

import 'package:chessever2/repository/gamebase/gamebase_repository.dart';
import 'package:chessever2/screens/studies/providers/studies_provider.dart';
import 'package:chessever2/screens/studies/study_detail_screen.dart';
import 'package:chessever2/screens/studies/widgets/study_metadata.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/widgets/liquid_glass/glass_back_button.dart';
import 'package:chessever2/widgets/liquid_glass/glass_feedback.dart';
import 'package:chessever2/widgets/liquid_glass/glass_full_screen_page.dart';
import 'package:chessever2/widgets/liquid_glass/glass_island_top_bar.dart';
import 'package:chessever2/widgets/liquid_glass/glass_loading.dart';
import 'package:chessever2/widgets/liquid_glass/glass_motion.dart';
import 'package:chessever2/widgets/liquid_glass/glass_title_chip.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

typedef StudySelectedCallback =
    FutureOr<void> Function(GamebaseStudySummary study);

class StudiesBrowseScreen extends ConsumerStatefulWidget {
  const StudiesBrowseScreen({
    super.key,
    this.onOpenStudy,
    this.onBack,
    this.showBackButton = true,
  });

  final StudySelectedCallback? onOpenStudy;
  final VoidCallback? onBack;
  final bool showBackButton;

  @override
  ConsumerState<StudiesBrowseScreen> createState() =>
      _StudiesBrowseScreenState();
}

class _StudiesBrowseScreenState extends ConsumerState<StudiesBrowseScreen> {
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController()..addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients ||
        _scrollController.position.extentAfter > 520) {
      return;
    }
    unawaited(ref.read(studiesProvider.notifier).loadMore());
  }

  @override
  Widget build(BuildContext context) {
    final studies = ref.watch(studiesProvider);
    final duration = GlassMotion.resolveDuration(
      context,
      const Duration(milliseconds: 180),
    );

    return GlassFullScreenPage(
      key: const ValueKey<String>('studies-browse-full-screen-page'),
      backgroundColor: context.colors.background,
      contentPadding: const EdgeInsets.only(top: 72, bottom: 24),
      topOverlayPadding: const EdgeInsets.only(top: 4),
      topOverlay: GlassIslandTopBar(
        key: const ValueKey<String>('studies-browse-floating-controls'),
        topPadding: 0,
        height: 48,
        leading:
            widget.showBackButton
                ? GlassBackButton(onPressed: widget.onBack)
                : null,
        title: const GlassTitleChip(label: 'Studies', maxWidth: 150),
        trailing: [
          _RefreshStudiesControl(
            isLoading: studies.isLoading,
            onPressed:
                studies.isLoading
                    ? null
                    : () =>
                        unawaited(ref.read(studiesProvider.notifier).refresh()),
          ),
        ],
      ),
      content: AnimatedSwitcher(
        key: const ValueKey<String>('studies-state-switcher'),
        duration: duration,
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeOutCubic,
        child: studies.when(
          data:
              (state) =>
                  state.isEmpty
                      ? _StudiesEmptyState(
                        key: const ValueKey<String>('studies-empty-state'),
                        onRefresh:
                            () => ref.read(studiesProvider.notifier).refresh(),
                      )
                      : _StudiesFeed(
                        key: const ValueKey<String>('studies-data-state'),
                        controller: _scrollController,
                        state: state,
                        onRefresh:
                            () => ref.read(studiesProvider.notifier).refresh(),
                        onOpenStudy: _openStudy,
                        onRetryLoadMore:
                            () => unawaited(
                              ref.read(studiesProvider.notifier).loadMore(),
                            ),
                      ),
          loading:
              () => const _StudiesLoadingState(
                key: ValueKey<String>('studies-loading-state'),
              ),
          error:
              (error, _) => _StudiesErrorState(
                key: const ValueKey<String>('studies-error-state'),
                error: error,
                onRetry: () => ref.invalidate(studiesProvider),
              ),
        ),
      ),
    );
  }

  Future<void> _openStudy(GamebaseStudySummary study) async {
    try {
      final injected = widget.onOpenStudy;
      if (injected != null) {
        await Future<void>.sync(() => injected(study));
        return;
      }
      if (!mounted) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder:
              (_) => StudyDetailScreen(lichessStudyId: study.canonicalStudyId),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      showGlassSnack(
        context,
        message: 'This Study is unavailable right now. Please try again.',
      );
    }
  }
}

class _StudiesFeed extends StatelessWidget {
  const _StudiesFeed({
    required this.controller,
    required this.state,
    required this.onRefresh,
    required this.onOpenStudy,
    required this.onRetryLoadMore,
    super.key,
  });

  final ScrollController controller;
  final StudiesState state;
  final RefreshCallback onRefresh;
  final ValueChanged<GamebaseStudySummary> onOpenStudy;
  final VoidCallback onRetryLoadMore;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      color: context.colors.brandMuted,
      backgroundColor: context.colors.surfaceElevated,
      child: ListView.separated(
        key: const PageStorageKey<String>('studies-browse-feed'),
        controller: controller,
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        itemCount:
            state.items.length +
            1 +
            (state.isLoadingMore || state.loadMoreFailure != null ? 1 : 0),
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          if (index == 0) {
            return _StudiesFeedIntro(total: state.total);
          }
          final studyIndex = index - 1;
          if (studyIndex < state.items.length) {
            final study = state.items[studyIndex];
            return StudySummaryCard(
              key: ValueKey<String>('study-card-${study.canonicalStudyId}'),
              study: study,
              onPressed: () => onOpenStudy(study),
            );
          }
          if (state.loadMoreFailure != null) {
            return _LoadMoreError(onRetry: onRetryLoadMore);
          }
          return const _LoadMoreProgress();
        },
      ),
    );
  }
}

class _StudiesFeedIntro extends StatelessWidget {
  const _StudiesFeedIntro({required this.total});

  final int total;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: StudySectionTitle(
        title: 'Credibility-ranked Studies',
        subtitle:
            '$total ${total == 1 ? 'Study' : 'Studies'} with source views, chapter depth, annotations, openings, and player signals.',
      ),
    );
  }
}

class _RefreshStudiesControl extends StatelessWidget {
  const _RefreshStudiesControl({
    required this.isLoading,
    required this.onPressed,
  });

  final bool isLoading;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      button: true,
      enabled: onPressed != null,
      label: isLoading ? 'Loading Studies' : 'Refresh Studies',
      child: ExcludeSemantics(
        child: Tooltip(
          message: 'Refresh Studies',
          child: GlassIconButton(
            key: const ValueKey<String>('studies-refresh-button'),
            icon: Icon(
              Icons.refresh_rounded,
              color: context.colors.iconPrimary,
            ),
            onPressed: onPressed,
            size: 48,
            iconSize: 22,
            useOwnLayer: true,
          ),
        ),
      ),
    );
  }
}

class _StudiesLoadingState extends StatelessWidget {
  const _StudiesLoadingState({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: 4,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder:
          (_, index) => Semantics(
            label: index == 0 ? 'Loading Studies' : null,
            child: Container(
              height: index == 0 ? 88 : 196,
              decoration: BoxDecoration(
                color: context.colors.surface,
                borderRadius: BorderRadius.circular(16),
              ),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SkeletonLine(
                    widthFactor: index == 0 ? .62 : .78,
                    height: 16,
                  ),
                  const SizedBox(height: 10),
                  const _SkeletonLine(widthFactor: .46, height: 12),
                  if (index > 0) ...[
                    const Spacer(),
                    const _SkeletonLine(widthFactor: .9, height: 30),
                    const SizedBox(height: 10),
                    const _SkeletonLine(widthFactor: .68, height: 13),
                  ],
                ],
              ),
            ),
          ),
    );
  }
}

class _SkeletonLine extends StatelessWidget {
  const _SkeletonLine({required this.widthFactor, required this.height});

  final double widthFactor;
  final double height;

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      widthFactor: widthFactor,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: context.colors.skeleton,
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }
}

class _StudiesEmptyState extends StatelessWidget {
  const _StudiesEmptyState({required this.onRefresh, super.key});

  final RefreshCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(24, 80, 24, 32),
      children: [
        Icon(
          Icons.menu_book_outlined,
          size: 40,
          color: context.colors.iconSecondary,
        ),
        const SizedBox(height: 16),
        Text(
          'No quality-gated Studies yet',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            color: context.colors.textPrimary,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Pull to refresh. ChessEver only lists Studies that pass the current source checks.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: context.colors.textSecondary,
            height: 1.45,
          ),
        ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: () => unawaited(onRefresh()),
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
            backgroundColor: context.colors.brand,
            foregroundColor: context.colors.textInverse,
          ),
          child: const Text('Refresh Studies'),
        ),
      ],
    );
  }
}

class _StudiesErrorState extends StatelessWidget {
  const _StudiesErrorState({
    required this.error,
    required this.onRetry,
    super.key,
  });

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final contractFailure = error is GamebaseStudyContractException;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              contractFailure
                  ? Icons.data_object_rounded
                  : Icons.cloud_off_outlined,
              size: 40,
              color: context.colors.iconSecondary,
            ),
            const SizedBox(height: 16),
            Text(
              contractFailure
                  ? 'Studies data needs attention'
                  : 'Studies could not load',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: context.colors.textPrimary,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              contractFailure
                  ? 'The response did not match the trusted Study format.'
                  : 'Check your connection and try again.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: context.colors.textSecondary,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onRetry,
              style: FilledButton.styleFrom(
                minimumSize: const Size(180, 48),
                backgroundColor: context.colors.brand,
                foregroundColor: context.colors.textInverse,
              ),
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry Studies'),
            ),
          ],
        ),
      ),
    );
  }
}

class _LoadMoreProgress extends StatelessWidget {
  const _LoadMoreProgress();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Loading more Studies',
      liveRegion: true,
      child: const SizedBox(
        height: 56,
        child: Center(child: GlassLoading.circular(size: 26)),
      ),
    );
  }
}

class _LoadMoreError extends StatelessWidget {
  const _LoadMoreError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      liveRegion: true,
      label:
          'More Studies could not load. Previously loaded Studies remain available.',
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: context.colors.surface,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                'More Studies could not load. Your current list is still available.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: context.colors.textPrimaryMuted,
                  height: 1.4,
                ),
              ),
            ),
            const SizedBox(width: 10),
            TextButton(
              key: const ValueKey<String>('studies-load-more-retry'),
              onPressed: onRetry,
              style: TextButton.styleFrom(
                minimumSize: const Size(72, 48),
                foregroundColor: context.colors.brandMuted,
              ),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
