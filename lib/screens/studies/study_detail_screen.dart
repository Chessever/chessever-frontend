import 'dart:async';

import 'package:chessever2/repository/gamebase/gamebase_repository.dart';
import 'package:chessever2/screens/studies/providers/studies_provider.dart';
import 'package:chessever2/screens/studies/widgets/study_metadata.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/widgets/liquid_glass/glass_back_button.dart';
import 'package:chessever2/widgets/liquid_glass/glass_feedback.dart';
import 'package:chessever2/widgets/liquid_glass/glass_full_screen_page.dart';
import 'package:chessever2/widgets/liquid_glass/glass_island_top_bar.dart';
import 'package:chessever2/widgets/liquid_glass/glass_motion.dart';
import 'package:chessever2/widgets/liquid_glass/glass_title_chip.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:url_launcher/url_launcher.dart';

typedef StudyExternalLinkOpener = Future<bool> Function(Uri uri);

@visibleForTesting
Future<bool> openCanonicalLichessStudyUrl(Uri uri) async {
  final canonicalStudyPath =
      uri.scheme == 'https' &&
      uri.host == 'lichess.org' &&
      uri.pathSegments.length >= 2 &&
      uri.pathSegments.length <= 3 &&
      uri.pathSegments.first == 'study' &&
      uri.pathSegments.skip(1).every((segment) => segment.trim().isNotEmpty);
  if (!canonicalStudyPath || !await canLaunchUrl(uri)) return false;
  return launchUrl(uri, mode: LaunchMode.externalApplication);
}

class StudyDetailScreen extends ConsumerStatefulWidget {
  const StudyDetailScreen({
    required this.lichessStudyId,
    super.key,
    this.openExternalLink,
    this.onBack,
  });

  final String lichessStudyId;
  final StudyExternalLinkOpener? openExternalLink;
  final VoidCallback? onBack;

  @override
  ConsumerState<StudyDetailScreen> createState() => _StudyDetailScreenState();
}

class _StudyDetailScreenState extends ConsumerState<StudyDetailScreen> {
  Uri? _openingUri;

  @override
  Widget build(BuildContext context) {
    final detail = ref.watch(studyDetailProvider(widget.lichessStudyId));
    final duration = GlassMotion.resolveDuration(
      context,
      const Duration(milliseconds: 180),
    );

    return GlassFullScreenPage(
      key: const ValueKey<String>('study-detail-full-screen-page'),
      backgroundColor: context.colors.background,
      contentPadding: const EdgeInsets.only(top: 72, bottom: 24),
      topOverlayPadding: const EdgeInsets.only(top: 4),
      topOverlay: GlassIslandTopBar(
        key: const ValueKey<String>('study-detail-floating-controls'),
        topPadding: 0,
        height: 48,
        leading: GlassBackButton(onPressed: widget.onBack),
        title: const GlassTitleChip(label: 'Study detail', maxWidth: 170),
        trailing: [
          _RefreshDetailControl(
            isLoading: detail.isLoading,
            onPressed:
                detail.isLoading
                    ? null
                    : () => ref.invalidate(
                      studyDetailProvider(widget.lichessStudyId),
                    ),
          ),
        ],
      ),
      content: AnimatedSwitcher(
        key: const ValueKey<String>('study-detail-state-switcher'),
        duration: duration,
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeOutCubic,
        child: detail.when(
          data:
              (value) => _StudyDetailContent(
                key: const ValueKey<String>('study-detail-data-state'),
                detail: value,
                openingUri: _openingUri,
                onOpenStudy: () => unawaited(_openExternal(value.sourceUrl)),
                onOpenChapter:
                    (chapter) =>
                        unawaited(_openExternal(chapter.canonicalSourceUrl)),
              ),
          loading:
              () => const _StudyDetailLoading(
                key: ValueKey<String>('study-detail-loading-state'),
              ),
          error:
              (error, _) => _StudyDetailError(
                key: const ValueKey<String>('study-detail-error-state'),
                error: error,
                onRetry:
                    () => ref.invalidate(
                      studyDetailProvider(widget.lichessStudyId),
                    ),
              ),
        ),
      ),
    );
  }

  Future<void> _openExternal(Uri uri) async {
    if (_openingUri != null) return;
    setState(() => _openingUri = uri);
    try {
      final opener = widget.openExternalLink ?? openCanonicalLichessStudyUrl;
      final opened = await opener(uri);
      if (!opened && mounted) {
        showGlassSnack(
          context,
          message: 'Lichess could not be opened on this device.',
        );
      }
    } catch (_) {
      if (mounted) {
        showGlassSnack(
          context,
          message: 'Lichess could not be opened on this device.',
        );
      }
    } finally {
      if (mounted) setState(() => _openingUri = null);
    }
  }
}

class _StudyDetailContent extends StatelessWidget {
  const _StudyDetailContent({
    required this.detail,
    required this.openingUri,
    required this.onOpenStudy,
    required this.onOpenChapter,
    super.key,
  });

  final GamebaseStudyDetail detail;
  final Uri? openingUri;
  final VoidCallback onOpenStudy;
  final ValueChanged<GamebaseStudyChapterMetadata> onOpenChapter;

  @override
  Widget build(BuildContext context) {
    final chapters = detail.chapters.toList(growable: false)
      ..sort((left, right) => left.orderIndex.compareTo(right.orderIndex));
    final study = detail.study;
    final author = study.authorUsername?.trim();

    return ListView(
      key: const PageStorageKey<String>('study-detail-content'),
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: context.colors.surface,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                study.name,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: context.colors.textPrimary,
                  fontWeight: FontWeight.w800,
                  height: 1.16,
                ),
              ),
              const SizedBox(height: 7),
              Text(
                author == null || author.isEmpty
                    ? 'Original source: Lichess'
                    : 'By $author on Lichess',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: context.colors.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 16),
              _CredibilityDetail(score: study.credibilityScore),
              const SizedBox(height: 14),
              StudyQualityMetrics(study: study),
              if (study.openings.isNotEmpty ||
                  study.ecos.isNotEmpty ||
                  study.players.isNotEmpty) ...[
                const SizedBox(height: 16),
                StudySignalSummary(study: study),
              ],
              const SizedBox(height: 18),
              StudyExternalButton(
                key: const ValueKey<String>('open-study-on-lichess'),
                label:
                    openingUri == study.sourceUrl
                        ? 'Opening Lichess…'
                        : 'Open Study on Lichess',
                onPressed: openingUri == null ? onOpenStudy : null,
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        const StudySourceNotice(),
        const SizedBox(height: 24),
        StudySectionTitle(
          title: 'Chapters',
          subtitle:
              '${chapters.length} ${chapters.length == 1 ? 'chapter' : 'chapters'} in source order. Metadata is shown here; reading opens on Lichess.',
        ),
        const SizedBox(height: 12),
        if (chapters.isEmpty)
          const _NoChapterMetadata()
        else
          for (var index = 0; index < chapters.length; index++) ...[
            _ChapterMetadataCard(
              key: ValueKey<String>(
                'study-chapter-${chapters[index].canonicalChapterId}',
              ),
              chapter: chapters[index],
              displayIndex: index + 1,
              isOpening: openingUri == chapters[index].canonicalSourceUrl,
              interactionsEnabled: openingUri == null,
              onOpen: () => onOpenChapter(chapters[index]),
            ),
            if (index != chapters.length - 1) const SizedBox(height: 10),
          ],
      ],
    );
  }
}

class _CredibilityDetail extends StatelessWidget {
  const _CredibilityDetail({required this.score});

  final double score;

  @override
  Widget build(BuildContext context) {
    final display = score.toStringAsFixed(score % 1 == 0 ? 0 : 1);
    return Semantics(
      label: 'Credibility score $display out of 100',
      child: Row(
        children: [
          Container(
            constraints: const BoxConstraints(minWidth: 56, minHeight: 48),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: context.colors.surfaceRecessed,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              display,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: context.colors.textPrimary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Credibility score',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: context.colors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Current Gamebase ranking signal',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: context.colors.textSecondary,
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

class _ChapterMetadataCard extends StatelessWidget {
  const _ChapterMetadataCard({
    required this.chapter,
    required this.displayIndex,
    required this.isOpening,
    required this.interactionsEnabled,
    required this.onOpen,
    super.key,
  });

  final GamebaseStudyChapterMetadata chapter;
  final int displayIndex;
  final bool isOpening;
  final bool interactionsEnabled;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final name = chapter.name?.trim();
    final playerLine = _chapterPlayerLine(chapter);
    final openingLine = <String>[
      if (chapter.eco?.trim().isNotEmpty ?? false) chapter.eco!.trim(),
      if (chapter.opening?.trim().isNotEmpty ?? false) chapter.opening!.trim(),
    ].join(' · ');

    return Semantics(
      container: true,
      label:
          'Chapter $displayIndex, ${name == null || name.isEmpty ? 'untitled' : name}',
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: context.colors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: context.colors.divider),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  constraints: const BoxConstraints(
                    minWidth: 36,
                    minHeight: 36,
                  ),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: context.colors.surfaceRecessed,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$displayIndex',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: context.colors.textPrimary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name == null || name.isEmpty
                            ? 'Untitled chapter'
                            : name,
                        style: Theme.of(
                          context,
                        ).textTheme.titleMedium?.copyWith(
                          color: context.colors.textPrimary,
                          fontWeight: FontWeight.w700,
                          height: 1.25,
                        ),
                      ),
                      if (openingLine.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          openingLine,
                          style: Theme.of(
                            context,
                          ).textTheme.bodySmall?.copyWith(
                            color: context.colors.textSecondary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            if (playerLine.isNotEmpty) ...[
              const SizedBox(height: 12),
              _ChapterInfoLine(
                icon: Icons.people_outline_rounded,
                label: playerLine,
              ),
            ],
            const SizedBox(height: 8),
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: [
                _ChapterTag(label: '${chapter.plyCount} plies'),
                if (chapter.variant?.trim().isNotEmpty ?? false)
                  _ChapterTag(label: chapter.variant!.trim()),
                if (chapter.result?.trim().isNotEmpty ?? false)
                  _ChapterTag(label: 'Result ${chapter.result!.trim()}'),
                if (chapter.chapterMode?.trim().isNotEmpty ?? false)
                  _ChapterTag(label: chapter.chapterMode!.trim()),
                if (chapter.hasAnnotations)
                  const _ChapterTag(label: 'Annotated'),
                if (chapter.isSetup) const _ChapterTag(label: 'Custom setup'),
              ],
            ),
            const SizedBox(height: 14),
            StudyExternalButton(
              key: ValueKey<String>(
                'open-chapter-${chapter.canonicalChapterId}',
              ),
              label: isOpening ? 'Opening Lichess…' : 'Open chapter on Lichess',
              onPressed: interactionsEnabled ? onOpen : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _ChapterInfoLine extends StatelessWidget {
  const _ChapterInfoLine({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 17, color: context.colors.iconSecondary),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: context.colors.textPrimaryMuted,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}

class _ChapterTag extends StatelessWidget {
  const _ChapterTag({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: context.colors.surfaceRecessed,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: context.colors.textPrimaryMuted,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _NoChapterMetadata extends StatelessWidget {
  const _NoChapterMetadata();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        'No chapter metadata is available from the source right now.',
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: context.colors.textSecondary,
          height: 1.4,
        ),
      ),
    );
  }
}

class _RefreshDetailControl extends StatelessWidget {
  const _RefreshDetailControl({
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
      label: isLoading ? 'Loading Study detail' : 'Refresh Study detail',
      child: ExcludeSemantics(
        child: Tooltip(
          message: 'Refresh Study detail',
          child: GlassIconButton(
            key: const ValueKey<String>('study-detail-refresh-button'),
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

class _StudyDetailLoading extends StatelessWidget {
  const _StudyDetailLoading({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        Semantics(
          label: 'Loading Study detail',
          child: Container(
            height: 310,
            decoration: BoxDecoration(
              color: context.colors.surface,
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
        const SizedBox(height: 24),
        Container(
          height: 38,
          width: 150,
          decoration: BoxDecoration(
            color: context.colors.skeleton,
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        const SizedBox(height: 12),
        for (var index = 0; index < 2; index++) ...[
          Container(
            height: 220,
            decoration: BoxDecoration(
              color: context.colors.surface,
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          if (index == 0) const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class _StudyDetailError extends StatelessWidget {
  const _StudyDetailError({
    required this.error,
    required this.onRetry,
    super.key,
  });

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final missing =
        error is GamebaseStudyRequestException &&
        (error as GamebaseStudyRequestException).isNotFound;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              missing ? Icons.menu_book_outlined : Icons.cloud_off_outlined,
              size: 40,
              color: context.colors.iconSecondary,
            ),
            const SizedBox(height: 16),
            Text(
              missing
                  ? 'This Study is no longer available'
                  : 'Study could not load',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: context.colors.textPrimary,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              missing
                  ? 'It may have been removed or made private at the source.'
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
              label: const Text('Retry Study'),
            ),
          ],
        ),
      ),
    );
  }
}

String _chapterPlayerLine(GamebaseStudyChapterMetadata chapter) {
  String side(String? name, int? elo) {
    final normalized = name?.trim();
    if (normalized == null || normalized.isEmpty) return '';
    return elo == null ? normalized : '$normalized ($elo)';
  }

  final white = side(chapter.whiteName, chapter.whiteElo);
  final black = side(chapter.blackName, chapter.blackElo);
  if (white.isNotEmpty && black.isNotEmpty) return '$white vs $black';
  return white.isNotEmpty ? white : black;
}
