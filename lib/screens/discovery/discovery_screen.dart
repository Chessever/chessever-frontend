import 'dart:async';
import 'dart:math' as math;

import 'package:chessever2/e2e/e2e_ids.dart';
import 'package:chessever2/repository/gamebase/gamebase_repository.dart';
import 'package:chessever2/screens/board_editor/board_editor_screen.dart';
import 'package:chessever2/screens/gamebase/gamebase_explorer_screen.dart';
import 'package:chessever2/screens/miniatures/miniatures_screen.dart';
import 'package:chessever2/screens/miniatures/providers/miniatures_provider.dart';
import 'package:chessever2/screens/studies/providers/studies_provider.dart';
import 'package:chessever2/screens/studies/studies_browse_screen.dart';
import 'package:chessever2/screens/studies/study_detail_screen.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/widgets/auth/auth_upgrade_sheet.dart';
import 'package:chessever2/widgets/liquid_glass/glass_kit.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

typedef DiscoveryAction = FutureOr<void> Function();
typedef DiscoveryStudyAction =
    FutureOr<void> Function(GamebaseStudySummary study);
typedef DiscoveryMiniatureAction =
    FutureOr<void> Function(GamebaseMiniature miniature);

/// The mobile discovery destination: useful chess content first, with tools
/// close by. Content remains opaque while navigation and refresh controls
/// float above one full-screen canvas.
class DiscoveryScreen extends ConsumerWidget {
  const DiscoveryScreen({
    super.key,
    this.onAccountTap,
    this.onOpenStudies,
    this.onOpenStudy,
    this.onOpenMiniatures,
    this.onOpenMiniature,
    this.onOpenExplorer,
    this.onOpenAnalysisBoard,
    this.onOpenPlayers,
  });

  final DiscoveryAction? onAccountTap;
  final DiscoveryAction? onOpenStudies;
  final DiscoveryStudyAction? onOpenStudy;
  final DiscoveryAction? onOpenMiniatures;
  final DiscoveryMiniatureAction? onOpenMiniature;
  final DiscoveryAction? onOpenExplorer;
  final DiscoveryAction? onOpenAnalysisBoard;
  final DiscoveryAction? onOpenPlayers;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final studies = ref.watch(studiesProvider);
    final miniatures = ref.watch(miniaturesProvider);
    final parentScaffold = Scaffold.maybeOf(context);
    final reduceMotion = GlassMotion.reduceMotion(context);

    return KeyedSubtree(
      key: e2eKey(E2eIds.discoveryRoot),
      child: GlassFullScreenPage(
        key: const ValueKey<String>('discovery-full-screen-page'),
        backgroundColor: context.colors.background,
        contentPadding: const EdgeInsets.only(top: 72, bottom: 104),
        topOverlayPadding: const EdgeInsets.only(top: 4),
        topOverlay: GlassIslandTopBar(
          key: const ValueKey<String>('discovery-floating-controls'),
          topPadding: 0,
          height: 48,
          leading: _DiscoveryGlassControl(
            key: const ValueKey<String>('discovery-account-button'),
            semanticLabel: 'Open account menu',
            icon: CupertinoIcons.person_crop_circle,
            onPressed:
                () => unawaited(
                  _run(
                    context,
                    onAccountTap ??
                        () {
                          parentScaffold?.openDrawer();
                        },
                  ),
                ),
          ),
          title: const GlassTitleChip(label: 'Discover', maxWidth: 142),
          trailing: [
            _DiscoveryGlassControl(
              key: const ValueKey<String>('discovery-refresh-button'),
              semanticLabel: 'Refresh discovery',
              icon: CupertinoIcons.refresh,
              onPressed:
                  studies.isRefreshing || miniatures.isRefreshing
                      ? null
                      : () => unawaited(_refresh(context, ref)),
            ),
          ],
        ),
        content: RefreshIndicator(
          onRefresh: () => _refresh(context, ref),
          child: ListView(
            key: const PageStorageKey<String>('discovery-scroll-view'),
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
            children: [
              _DiscoveryHero(
                reduceMotion: reduceMotion,
                onOpenStudies:
                    () => unawaited(
                      _run(
                        context,
                        onOpenStudies ?? () => _openStudies(context),
                      ),
                    ),
                onOpenMiniatures:
                    () => unawaited(
                      _run(
                        context,
                        onOpenMiniatures ?? () => _openMiniatures(context),
                      ),
                    ),
              ),
              const SizedBox(height: 28),
              _StudiesPreview(
                studies: studies,
                reduceMotion: reduceMotion,
                onSeeAll:
                    () => unawaited(
                      _run(
                        context,
                        onOpenStudies ?? () => _openStudies(context),
                      ),
                    ),
                onOpen:
                    (study) => unawaited(
                      _run(
                        context,
                        () =>
                            onOpenStudy?.call(study) ??
                            _openStudy(context, study),
                      ),
                    ),
                onRetry: () => ref.invalidate(studiesProvider),
              ),
              const SizedBox(height: 28),
              _MiniaturesPreview(
                miniatures: miniatures,
                reduceMotion: reduceMotion,
                onSeeAll:
                    () => unawaited(
                      _run(
                        context,
                        onOpenMiniatures ?? () => _openMiniatures(context),
                      ),
                    ),
                onOpen:
                    (miniature) => unawaited(
                      _run(
                        context,
                        () =>
                            onOpenMiniature?.call(miniature) ??
                            _openMiniatures(context),
                      ),
                    ),
                onRetry: () => ref.invalidate(miniaturesProvider),
              ),
              const SizedBox(height: 28),
              _DiscoveryTools(
                onOpenExplorer:
                    () => unawaited(
                      _run(
                        context,
                        onOpenExplorer ?? () => _openExplorer(context),
                      ),
                    ),
                onOpenAnalysisBoard:
                    () => unawaited(
                      _run(
                        context,
                        onOpenAnalysisBoard ??
                            () => _openAnalysisBoard(context),
                      ),
                    ),
                onOpenPlayers:
                    () => unawaited(
                      _run(
                        context,
                        onOpenPlayers ?? () => _openPlayers(context),
                      ),
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _refresh(BuildContext context, WidgetRef ref) async {
    final results = await Future.wait<Object?>(
      [
        ref.read(studiesProvider.notifier).refresh().then<Object?>((_) => null),
        ref
            .read(miniaturesProvider.notifier)
            .refresh()
            .then<Object?>((_) => null),
      ].map((operation) => operation.catchError((Object error) => error)),
    );
    if (!context.mounted || results.every((result) => result == null)) return;
    showGlassSnack(
      context,
      message:
          'Some discovery shelves could not refresh. Existing items remain available.',
    );
  }

  Future<void> _run(BuildContext context, DiscoveryAction action) async {
    try {
      await Future<void>.sync(action);
    } catch (_) {
      if (!context.mounted) return;
      showGlassSnack(
        context,
        message: 'That discovery item is unavailable right now.',
      );
    }
  }

  Future<void> _openStudies(BuildContext context) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => const StudiesBrowseScreen()),
    );
  }

  Future<void> _openStudy(BuildContext context, GamebaseStudySummary study) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder:
            (_) => StudyDetailScreen(lichessStudyId: study.canonicalStudyId),
      ),
    );
  }

  Future<void> _openMiniatures(BuildContext context) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => const MiniaturesScreen()),
    );
  }

  Future<void> _openExplorer(BuildContext context) async {
    final allowed = await requireFullAuthGuard(context);
    if (!allowed || !context.mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => GamebaseExplorerScreen.scoped()),
    );
  }

  Future<void> _openAnalysisBoard(BuildContext context) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => const BoardEditorScreen()),
    );
  }

  Future<void> _openPlayers(BuildContext context) =>
      Navigator.of(context).pushNamed<void>('/player_list_screen');
}

class _DiscoveryHero extends StatelessWidget {
  const _DiscoveryHero({
    required this.reduceMotion,
    required this.onOpenStudies,
    required this.onOpenMiniatures,
  });

  final bool reduceMotion;
  final VoidCallback onOpenStudies;
  final VoidCallback onOpenMiniatures;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: 'Chess discovery highlights',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: context.colors.surface,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: context.colors.divider),
          boxShadow: [
            BoxShadow(
              color: context.colors.shadow.withValues(
                alpha: context.isLightTheme ? 0.08 : 0.22,
              ),
              blurRadius: 28,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _DiscoveryEyebrow(
                icon: CupertinoIcons.sparkles,
                label: 'CURATED FOR CHESS STUDY',
              ),
              const SizedBox(height: 14),
              Text(
                'Short games. Deep ideas.',
                style: AppTypography.displayXsBold.copyWith(
                  color: context.colors.textPrimary,
                  height: 1.06,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Replay decisive miniatures or open credibility-ranked Studies with their source and quality signals intact.',
                style: AppTypography.textSmRegular.copyWith(
                  color: context.colors.textSecondary,
                ),
              ),
              const SizedBox(height: 20),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _OpaqueActionButton(
                    key: const ValueKey<String>('discovery-hero-studies'),
                    label: 'Explore Studies',
                    icon: CupertinoIcons.book,
                    prominent: true,
                    reduceMotion: reduceMotion,
                    onPressed: onOpenStudies,
                  ),
                  _OpaqueActionButton(
                    key: const ValueKey<String>('discovery-hero-miniatures'),
                    label: 'Watch Miniatures',
                    icon: CupertinoIcons.play_rectangle,
                    reduceMotion: reduceMotion,
                    onPressed: onOpenMiniatures,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StudiesPreview extends StatelessWidget {
  const _StudiesPreview({
    required this.studies,
    required this.reduceMotion,
    required this.onSeeAll,
    required this.onOpen,
    required this.onRetry,
  });

  final AsyncValue<StudiesState> studies;
  final bool reduceMotion;
  final VoidCallback onSeeAll;
  final ValueChanged<GamebaseStudySummary> onOpen;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return _DiscoverySection(
      key: const ValueKey<String>('discovery-studies-section'),
      title: 'Studies worth your time',
      subtitle: 'Quality-gated and credibility-ranked',
      onSeeAll: onSeeAll,
      child: AnimatedSwitcher(
        duration:
            reduceMotion ? Duration.zero : const Duration(milliseconds: 180),
        child: studies.when(
          loading:
              () => const _PreviewLoading(
                key: ValueKey<String>('discovery-studies-loading'),
                semanticLabel: 'Loading Study previews',
              ),
          error:
              (_, _) => _PreviewFailure(
                key: const ValueKey<String>('discovery-studies-error'),
                message: 'Study previews could not load.',
                onRetry: onRetry,
              ),
          data:
              (state) =>
                  state.items.isEmpty
                      ? _PreviewEmpty(
                        key: const ValueKey<String>('discovery-studies-empty'),
                        message:
                            'No quality-gated Study previews are available yet.',
                        actionLabel: 'Open Studies',
                        onPressed: onSeeAll,
                      )
                      : _HorizontalPreviewRail(
                        key: const ValueKey<String>('discovery-studies-data'),
                        children: [
                          for (final study in state.items.take(6))
                            _StudyPreviewCard(
                              key: ValueKey<String>(
                                'discovery-study-${study.canonicalStudyId}',
                              ),
                              study: study,
                              onPressed: () => onOpen(study),
                            ),
                        ],
                      ),
        ),
      ),
    );
  }
}

class _MiniaturesPreview extends StatelessWidget {
  const _MiniaturesPreview({
    required this.miniatures,
    required this.reduceMotion,
    required this.onSeeAll,
    required this.onOpen,
    required this.onRetry,
  });

  final AsyncValue<MiniaturesState> miniatures;
  final bool reduceMotion;
  final VoidCallback onSeeAll;
  final ValueChanged<GamebaseMiniature> onOpen;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return _DiscoverySection(
      key: const ValueKey<String>('discovery-miniatures-section'),
      title: 'Miniatures',
      subtitle: 'Complete decisive games in 25 moves or fewer',
      onSeeAll: onSeeAll,
      child: AnimatedSwitcher(
        duration:
            reduceMotion ? Duration.zero : const Duration(milliseconds: 180),
        child: miniatures.when(
          loading:
              () => const _PreviewLoading(
                key: ValueKey<String>('discovery-miniatures-loading'),
                semanticLabel: 'Loading miniature previews',
              ),
          error:
              (_, _) => _PreviewFailure(
                key: const ValueKey<String>('discovery-miniatures-error'),
                message: 'Miniature previews could not load.',
                onRetry: onRetry,
              ),
          data:
              (state) =>
                  state.items.isEmpty
                      ? _PreviewEmpty(
                        key: const ValueKey<String>(
                          'discovery-miniatures-empty',
                        ),
                        message:
                            'No complete miniature games are available for this window.',
                        actionLabel: 'Open Miniatures',
                        onPressed: onSeeAll,
                      )
                      : _HorizontalPreviewRail(
                        key: const ValueKey<String>(
                          'discovery-miniatures-data',
                        ),
                        children: [
                          for (final miniature in state.items.take(6))
                            _MiniaturePreviewCard(
                              key: ValueKey<String>(
                                'discovery-miniature-${miniature.canonicalGameId}',
                              ),
                              miniature: miniature,
                              onPressed: () => onOpen(miniature),
                            ),
                        ],
                      ),
        ),
      ),
    );
  }
}

class _DiscoverySection extends StatelessWidget {
  const _DiscoverySection({
    required this.title,
    required this.subtitle,
    required this.onSeeAll,
    required this.child,
    super.key,
  });

  final String title;
  final String subtitle;
  final VoidCallback onSeeAll;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AppTypography.textLgBold.copyWith(
                      color: context.colors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: AppTypography.textXsRegular.copyWith(
                      color: context.colors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Semantics(
              button: true,
              label: 'See all $title',
              child: TextButton(
                key: ValueKey<String>(
                  'discovery-see-all-${title.toLowerCase().replaceAll(' ', '-')}',
                ),
                onPressed: onSeeAll,
                style: TextButton.styleFrom(
                  minimumSize: const Size(48, 48),
                  foregroundColor: context.colors.brand,
                ),
                child: const Text('See all'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        child,
      ],
    );
  }
}

class _HorizontalPreviewRail extends StatelessWidget {
  const _HorizontalPreviewRail({required this.children, super.key});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var index = 0; index < children.length; index++) ...[
            children[index],
            if (index != children.length - 1) const SizedBox(width: 12),
          ],
        ],
      ),
    );
  }
}

class _StudyPreviewCard extends StatelessWidget {
  const _StudyPreviewCard({
    required this.study,
    required this.onPressed,
    super.key,
  });

  final GamebaseStudySummary study;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final opening =
        study.openings.isEmpty ? 'General study' : study.openings.first;
    final author = study.authorUsername?.trim();
    final score = study.credibilityScore.toStringAsFixed(1);
    final semanticLabel = <String>[
      'Study',
      study.name,
      '$score credibility',
      '${study.chapterCount} chapters',
      '${study.views} views',
      'Open Study details',
    ].join(', ');

    return _OpaquePreviewCard(
      semanticLabel: semanticLabel,
      onPressed: onPressed,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _MetricPill(label: score, icon: CupertinoIcons.checkmark_seal),
              const Spacer(),
              Icon(
                CupertinoIcons.arrow_up_right,
                size: 18,
                color: context.colors.iconSecondary,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            study.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.textMdBold.copyWith(
              color: context.colors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            opening,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.textXsMedium.copyWith(
              color: context.colors.brandMuted,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '${study.chapterCount} chapters · ${study.views} views${author == null || author.isEmpty ? '' : ' · @$author'}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.textXsRegular.copyWith(
              color: context.colors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniaturePreviewCard extends StatelessWidget {
  const _MiniaturePreviewCard({
    required this.miniature,
    required this.onPressed,
    super.key,
  });

  final GamebaseMiniature miniature;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final white = _nonBlank(miniature.whiteName, fallback: 'White');
    final black = _nonBlank(miniature.blackName, fallback: 'Black');
    final opening = _nonBlank(miniature.opening, fallback: 'Opening unknown');
    final result =
        miniature.result == MiniatureGameResult.whiteWins ? '1–0' : '0–1';
    final rating =
        miniature.avgRating == null ? 'Unrated' : '${miniature.avgRating} avg';

    return _OpaquePreviewCard(
      semanticLabel:
          'Miniature game, $white versus $black, $result, ${miniature.finalMoveNumber} moves, Open Miniatures',
      onPressed: onPressed,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _MetricPill(label: result, icon: CupertinoIcons.bolt_fill),
              const Spacer(),
              Text(
                rating,
                style: AppTypography.textXsMedium.copyWith(
                  color: context.colors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            '$white — $black',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.textMdBold.copyWith(
              color: context.colors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            opening,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.textXsMedium.copyWith(
              color: context.colors.brandMuted,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '${miniature.finalMoveNumber} moves · ${miniature.timeControl.name}',
            style: AppTypography.textXsRegular.copyWith(
              color: context.colors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _OpaquePreviewCard extends StatelessWidget {
  const _OpaquePreviewCard({
    required this.semanticLabel,
    required this.onPressed,
    required this.child,
  });

  final String semanticLabel;
  final VoidCallback onPressed;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: math.min(MediaQuery.sizeOf(context).width * 0.72, 286),
      child: Semantics(
        button: true,
        label: semanticLabel,
        child: Material(
          color: context.colors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
            side: BorderSide(color: context.colors.divider),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onPressed,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 178),
              child: Padding(padding: const EdgeInsets.all(16), child: child),
            ),
          ),
        ),
      ),
    );
  }
}

class _DiscoveryTools extends StatelessWidget {
  const _DiscoveryTools({
    required this.onOpenExplorer,
    required this.onOpenAnalysisBoard,
    required this.onOpenPlayers,
  });

  final VoidCallback onOpenExplorer;
  final VoidCallback onOpenAnalysisBoard;
  final VoidCallback onOpenPlayers;

  @override
  Widget build(BuildContext context) {
    final tools =
        <({String label, String detail, IconData icon, VoidCallback onTap})>[
          (
            label: 'Opening Explorer',
            detail: 'Inspect plans from real games',
            icon: CupertinoIcons.tree,
            onTap: onOpenExplorer,
          ),
          (
            label: 'Analysis Board',
            detail: 'Start from any position',
            icon: CupertinoIcons.square_grid_2x2,
            onTap: onOpenAnalysisBoard,
          ),
          (
            label: 'Players',
            detail: 'Find profiles and preparation',
            icon: CupertinoIcons.person_2,
            onTap: onOpenPlayers,
          ),
        ];

    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 12.0;
        final columns = constraints.maxWidth >= 720 ? 3 : 1;
        final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Prepare and explore',
              style: AppTypography.textLgBold.copyWith(
                color: context.colors.textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final tool in tools)
                  SizedBox(
                    width: width,
                    child: _ToolCard(
                      label: tool.label,
                      detail: tool.detail,
                      icon: tool.icon,
                      onPressed: tool.onTap,
                    ),
                  ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _ToolCard extends StatelessWidget {
  const _ToolCard({
    required this.label,
    required this.detail,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final String detail;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '$label, $detail',
      child: Material(
        color: context.colors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: context.colors.divider),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: ValueKey<String>(
            'discovery-tool-${label.toLowerCase().replaceAll(' ', '-')}',
          ),
          onTap: onPressed,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 96),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: context.colors.brand.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: SizedBox.square(
                      dimension: 48,
                      child: Icon(icon, color: context.colors.brand, size: 22),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          label,
                          style: AppTypography.textSmBold.copyWith(
                            color: context.colors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          detail,
                          style: AppTypography.textXsRegular.copyWith(
                            color: context.colors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    CupertinoIcons.chevron_forward,
                    color: context.colors.iconSecondary,
                    size: 17,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MetricPill extends StatelessWidget {
  const _MetricPill({required this.label, required this.icon});

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.colors.brand.withValues(alpha: 0.11),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: context.colors.brand),
            const SizedBox(width: 5),
            Text(
              label,
              style: AppTypography.textXsBold.copyWith(
                color: context.colors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DiscoveryEyebrow extends StatelessWidget {
  const _DiscoveryEyebrow({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: context.colors.brand),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            label,
            style: AppTypography.textXxsBold.copyWith(
              color: context.colors.brandMuted,
              letterSpacing: 0.7,
            ),
          ),
        ),
      ],
    );
  }
}

class _OpaqueActionButton extends StatelessWidget {
  const _OpaqueActionButton({
    required this.label,
    required this.icon,
    required this.reduceMotion,
    required this.onPressed,
    this.prominent = false,
    super.key,
  });

  final String label;
  final IconData icon;
  final bool reduceMotion;
  final VoidCallback onPressed;
  final bool prominent;

  @override
  Widget build(BuildContext context) {
    final foreground =
        prominent ? context.colors.textInverse : context.colors.textPrimary;
    return Semantics(
      button: true,
      label: label,
      child: FilledButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
        label: Text(label),
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 48),
          backgroundColor:
              prominent ? context.colors.brand : context.colors.surfaceRecessed,
          foregroundColor: foreground,
          animationDuration:
              reduceMotion ? Duration.zero : const Duration(milliseconds: 160),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    );
  }
}

class _PreviewLoading extends StatelessWidget {
  const _PreviewLoading({required this.semanticLabel, super.key});

  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticLabel,
      child: SizedBox(
        height: 178,
        child: Row(
          children: [
            for (var index = 0; index < 2; index++) ...[
              Expanded(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: context.colors.skeleton,
                    borderRadius: BorderRadius.circular(22),
                  ),
                ),
              ),
              if (index == 0) const SizedBox(width: 12),
            ],
          ],
        ),
      ),
    );
  }
}

class _PreviewFailure extends StatelessWidget {
  const _PreviewFailure({
    required this.message,
    required this.onRetry,
    super.key,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return _PreviewMessage(
      icon: CupertinoIcons.exclamationmark_triangle,
      message: message,
      actionLabel: 'Try again',
      onPressed: onRetry,
    );
  }
}

class _PreviewEmpty extends StatelessWidget {
  const _PreviewEmpty({
    required this.message,
    required this.actionLabel,
    required this.onPressed,
    super.key,
  });

  final String message;
  final String actionLabel;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return _PreviewMessage(
      icon: CupertinoIcons.tray,
      message: message,
      actionLabel: actionLabel,
      onPressed: onPressed,
    );
  }
}

class _PreviewMessage extends StatelessWidget {
  const _PreviewMessage({
    required this.icon,
    required this.message,
    required this.actionLabel,
    required this.onPressed,
  });

  final IconData icon;
  final String message;
  final String actionLabel;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: context.colors.divider),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(icon, color: context.colors.iconSecondary),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: AppTypography.textSmRegular.copyWith(
                  color: context.colors.textSecondary,
                ),
              ),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: onPressed,
              style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
              child: Text(actionLabel),
            ),
          ],
        ),
      ),
    );
  }
}

class _DiscoveryGlassControl extends StatelessWidget {
  const _DiscoveryGlassControl({
    required this.semanticLabel,
    required this.icon,
    required this.onPressed,
    super.key,
  });

  final String semanticLabel;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = GlassMotion.reduceMotion(context);
    return Tooltip(
      message: semanticLabel,
      child: Semantics(
        label: semanticLabel,
        button: true,
        enabled: onPressed != null,
        onTap: onPressed,
        child: ExcludeSemantics(
          child: GlassIconButton(
            icon: Icon(icon, color: context.colors.iconPrimary),
            onPressed: onPressed,
            size: 48,
            iconSize: 21,
            interactionScale: reduceMotion ? 1 : 0.95,
            anchorStretch: !reduceMotion,
            useOwnLayer: true,
          ),
        ),
      ),
    );
  }
}

String _nonBlank(String? value, {required String fallback}) {
  final normalized = value?.trim();
  return normalized == null || normalized.isEmpty ? fallback : normalized;
}
