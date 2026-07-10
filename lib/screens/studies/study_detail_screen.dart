import 'dart:async';

import 'package:chessever2/repository/gamebase/gamebase_repository.dart';
import 'package:chessever2/screens/studies/providers/studies_provider.dart';
import 'package:chessever2/screens/studies/study_public_link.dart';
import 'package:chessever2/screens/studies/widgets/study_metadata.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/widgets/liquid_glass/glass_back_button.dart';
import 'package:chessever2/widgets/liquid_glass/glass_feedback.dart';
import 'package:chessever2/widgets/liquid_glass/glass_full_screen_page.dart';
import 'package:chessever2/widgets/liquid_glass/glass_island_top_bar.dart';
import 'package:chessever2/widgets/liquid_glass/glass_motion.dart';
import 'package:chessever2/widgets/liquid_glass/glass_title_chip.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

typedef StudyExternalLinkOpener = Future<bool> Function(Uri uri);
typedef StudyLinkSharer =
    Future<void> Function(BuildContext context, String text);
typedef StudyLinkCopier = Future<void> Function(String text);

@visibleForTesting
Future<void> shareStudyPublicLink(BuildContext context, String text) async {
  final renderBox = context.findRenderObject();
  final origin =
      renderBox is RenderBox && renderBox.hasSize
          ? renderBox.localToGlobal(Offset.zero) & renderBox.size
          : null;
  await Share.share(
    text,
    subject: 'ChessEver Study',
    sharePositionOrigin: origin,
  );
}

@visibleForTesting
Future<void> copyStudyPublicLink(String text) {
  return Clipboard.setData(ClipboardData(text: text));
}

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
    this.chapterId,
    this.contentVersion,
    this.ply,
    this.shareLink,
    this.copyLink,
  });

  final String lichessStudyId;
  final StudyExternalLinkOpener? openExternalLink;
  final VoidCallback? onBack;
  final String? chapterId;
  final String? contentVersion;
  final int? ply;
  final StudyLinkSharer? shareLink;
  final StudyLinkCopier? copyLink;

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
                requestedChapterId: widget.chapterId,
                requestedContentVersion: widget.contentVersion,
                requestedPly: widget.ply,
                onOpenStudy: () => unawaited(_openExternal(value.sourceUrl)),
                onOpenChapter:
                    (chapter) =>
                        unawaited(_openExternal(chapter.canonicalSourceUrl)),
                onShare: _share,
                onCopy: _copy,
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

  Future<void> _share(
    BuildContext actionContext,
    StudyPublicLink link,
    String title, {
    String? chapterName,
  }) async {
    final text = studyShareText(
      link: link,
      title: title,
      chapterName: chapterName,
    );
    try {
      await (widget.shareLink ?? shareStudyPublicLink)(actionContext, text);
    } catch (_) {
      if (mounted) {
        showGlassSnack(context, message: 'This Study could not be shared.');
      }
    }
  }

  Future<void> _copy(
    StudyPublicLink link,
    String title, {
    String? chapterName,
  }) async {
    final text = studyShareText(
      link: link,
      title: title,
      chapterName: chapterName,
    );
    try {
      await (widget.copyLink ?? copyStudyPublicLink)(text);
      if (mounted) {
        showGlassSnack(context, message: 'Study share text copied.');
      }
    } catch (_) {
      if (mounted) {
        showGlassSnack(
          context,
          message: 'This Study link could not be copied.',
        );
      }
    }
  }
}

typedef _StudyShareCallback =
    Future<void> Function(
      BuildContext context,
      StudyPublicLink link,
      String title, {
      String? chapterName,
    });
typedef _StudyCopyCallback =
    Future<void> Function(
      StudyPublicLink link,
      String title, {
      String? chapterName,
    });

class _StudyDetailContent extends StatefulWidget {
  const _StudyDetailContent({
    required this.detail,
    required this.openingUri,
    required this.onOpenStudy,
    required this.onOpenChapter,
    required this.onShare,
    required this.onCopy,
    this.requestedChapterId,
    this.requestedContentVersion,
    this.requestedPly,
    super.key,
  });

  final GamebaseStudyDetail detail;
  final Uri? openingUri;
  final VoidCallback onOpenStudy;
  final ValueChanged<GamebaseStudyChapterMetadata> onOpenChapter;
  final _StudyShareCallback onShare;
  final _StudyCopyCallback onCopy;
  final String? requestedChapterId;
  final String? requestedContentVersion;
  final int? requestedPly;

  @override
  State<_StudyDetailContent> createState() => _StudyDetailContentState();
}

class _StudyDetailContentState extends State<_StudyDetailContent> {
  final Map<String, GlobalKey> _chapterKeys = <String, GlobalKey>{};
  final ScrollController _scrollController = ScrollController();
  bool _didRevealRequestedContext = false;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _StudyDetailContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.requestedChapterId != widget.requestedChapterId ||
        oldWidget.requestedContentVersion != widget.requestedContentVersion ||
        oldWidget.requestedPly != widget.requestedPly ||
        oldWidget.detail.contentVersion != widget.detail.contentVersion) {
      _didRevealRequestedContext = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final chapters = widget.detail.chapters.toList(growable: false)
      ..sort((left, right) => left.orderIndex.compareTo(right.orderIndex));
    final study = widget.detail.study;
    final requestedChapter = _chapterById(chapters, widget.requestedChapterId);
    _revealRequestedContext(requestedChapter);
    final author = study.authorUsername?.trim();
    final attribution =
        study.sourceMetadata?.attribution ??
        (author == null || author.isEmpty
            ? 'Original source: Lichess'
            : 'By $author on Lichess');

    final studyLink = StudyPublicLink(
      studyId: study.canonicalStudyId,
      contentVersion: study.contentVersion,
    );

    return ListView(
      key: const PageStorageKey<String>('study-detail-content'),
      controller: _scrollController,
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
                attribution,
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
                    widget.openingUri == study.sourceUrl
                        ? 'Opening Lichess…'
                        : 'Open Study on Lichess',
                onPressed:
                    widget.openingUri == null ? widget.onOpenStudy : null,
              ),
              const SizedBox(height: 10),
              _PublicLinkActions(
                key: const ValueKey<String>('share-study-actions'),
                shareLabel: 'Share Study',
                copyLabel: 'Copy Study share text',
                onShare:
                    (actionContext) =>
                        widget.onShare(actionContext, studyLink, study.name),
                onCopy: () => widget.onCopy(studyLink, study.name),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        StudySourceNotice(study: study),
        if (widget.requestedChapterId != null ||
            widget.requestedContentVersion != null ||
            widget.requestedPly != null) ...[
          const SizedBox(height: 12),
          _SharedContextNotice(
            detail: widget.detail,
            requestedChapterId: widget.requestedChapterId,
            requestedChapter: requestedChapter,
            requestedContentVersion: widget.requestedContentVersion,
            requestedPly: widget.requestedPly,
          ),
        ],
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
              chapterKey: _chapterKeys.putIfAbsent(
                chapters[index].canonicalChapterId,
                GlobalKey.new,
              ),
              key: ValueKey<String>(
                'study-chapter-${chapters[index].canonicalChapterId}',
              ),
              chapter: chapters[index],
              displayIndex: index + 1,
              isOpening:
                  widget.openingUri == chapters[index].canonicalSourceUrl,
              interactionsEnabled: widget.openingUri == null,
              isRequested:
                  requestedChapter?.canonicalChapterId ==
                  chapters[index].canonicalChapterId,
              onOpen: () => widget.onOpenChapter(chapters[index]),
              onShare: (actionContext) {
                final chapter = chapters[index];
                final requestedPly =
                    chapter.canonicalChapterId ==
                            requestedChapter?.canonicalChapterId
                        ? _nearestPly(widget.requestedPly, chapter.plyCount)
                        : null;
                final link = StudyPublicLink(
                  studyId: study.canonicalStudyId,
                  chapterId: chapter.canonicalChapterId,
                  ply: requestedPly,
                  contentVersion: study.contentVersion,
                );
                return widget.onShare(
                  actionContext,
                  link,
                  study.name,
                  chapterName: chapter.name,
                );
              },
              onCopy: () {
                final chapter = chapters[index];
                final link = StudyPublicLink(
                  studyId: study.canonicalStudyId,
                  chapterId: chapter.canonicalChapterId,
                  ply:
                      chapter.canonicalChapterId ==
                              requestedChapter?.canonicalChapterId
                          ? _nearestPly(widget.requestedPly, chapter.plyCount)
                          : null,
                  contentVersion: study.contentVersion,
                );
                return widget.onCopy(
                  link,
                  study.name,
                  chapterName: chapter.name,
                );
              },
            ),
            if (index != chapters.length - 1) const SizedBox(height: 10),
          ],
      ],
    );
  }

  void _revealRequestedContext(GamebaseStudyChapterMetadata? chapter) {
    if (_didRevealRequestedContext || chapter == null) return;
    _didRevealRequestedContext = true;
    _scrollToChapter(chapter);
  }

  void _scrollToChapter(
    GamebaseStudyChapterMetadata chapter, {
    int attempt = 0,
  }) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final chapterContext =
          _chapterKeys[chapter.canonicalChapterId]?.currentContext;
      if (chapterContext != null) {
        unawaited(
          Scrollable.ensureVisible(
            chapterContext,
            alignment: 0.18,
            duration: GlassMotion.resolveDuration(
              context,
              const Duration(milliseconds: 320),
            ),
            curve: Curves.easeOutCubic,
          ),
        );
        return;
      }
      if (!_scrollController.hasClients || attempt >= 3) return;

      final ordered = widget.detail.chapters.toList(growable: false)
        ..sort((left, right) => left.orderIndex.compareTo(right.orderIndex));
      final index = ordered.indexWhere(
        (candidate) =>
            candidate.canonicalChapterId == chapter.canonicalChapterId,
      );
      if (index < 0) return;
      // Metadata cards can grow substantially with Dynamic Type. Overshoot
      // toward the requested index, then let ensureVisible perform the precise
      // reduced-motion-aware alignment once the lazy child is mounted.
      final target = (600.0 + index * 560).clamp(
        0.0,
        _scrollController.position.maxScrollExtent,
      );
      _scrollController.jumpTo(target);
      _scrollToChapter(chapter, attempt: attempt + 1);
    });
  }
}

class _SharedContextNotice extends StatelessWidget {
  const _SharedContextNotice({
    required this.detail,
    required this.requestedChapterId,
    required this.requestedChapter,
    required this.requestedContentVersion,
    required this.requestedPly,
  });

  final GamebaseStudyDetail detail;
  final String? requestedChapterId;
  final GamebaseStudyChapterMetadata? requestedChapter;
  final String? requestedContentVersion;
  final int? requestedPly;

  @override
  Widget build(BuildContext context) {
    final messages = <String>[];
    if (requestedContentVersion != null &&
        requestedContentVersion != detail.contentVersion) {
      messages.add(
        detail.contentVersion == null
            ? 'The exact shared content version cannot be verified. Showing the nearest current Study context.'
            : 'This Study has changed since the link was shared. Showing the nearest current context.',
      );
    }
    if (requestedChapterId != null && requestedChapter == null) {
      messages.add(
        'The shared chapter is no longer available. Showing the current Study instead.',
      );
    } else if (requestedChapter != null) {
      final nearestPly = _nearestPly(requestedPly, requestedChapter!.plyCount);
      if (requestedPly != null && nearestPly != requestedPly) {
        messages.add(
          'The shared ply $requestedPly is beyond the current chapter. Chapter ${requestedChapter!.orderIndex + 1} is highlighted at the nearest available ply $nearestPly.',
        );
      } else if (requestedPly != null) {
        messages.add(
          'Shared chapter ${requestedChapter!.orderIndex + 1} is highlighted at ply $requestedPly.',
        );
      } else {
        messages.add(
          'Shared chapter ${requestedChapter!.orderIndex + 1} is highlighted below.',
        );
      }
    }
    if (messages.isEmpty) {
      messages.add('This public link matches the current Study metadata.');
    }

    return Semantics(
      container: true,
      liveRegion: true,
      label: messages.join(' '),
      child: Container(
        key: const ValueKey<String>('study-shared-context-notice'),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: context.colors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: context.colors.brand.withValues(alpha: 0.5),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.link_rounded, size: 21, color: context.colors.brand),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                messages.join(' '),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: context.colors.textPrimary,
                  height: 1.4,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PublicLinkActions extends StatelessWidget {
  const _PublicLinkActions({
    required this.shareLabel,
    required this.copyLabel,
    required this.onShare,
    required this.onCopy,
    super.key,
  });

  final String shareLabel;
  final String copyLabel;
  final Future<void> Function(BuildContext context) onShare;
  final Future<void> Function() onCopy;

  @override
  Widget build(BuildContext context) {
    final style = OutlinedButton.styleFrom(
      minimumSize: const Size(0, 48),
      foregroundColor: context.colors.textPrimary,
      side: BorderSide(color: context.colors.divider),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked =
            constraints.maxWidth < 320 ||
            MediaQuery.textScalerOf(context).scale(16) > 22;
        final share = Builder(
          builder:
              (actionContext) => Semantics(
                button: true,
                label: shareLabel,
                child: ExcludeSemantics(
                  child: OutlinedButton.icon(
                    key: const ValueKey<String>('study-share-button'),
                    onPressed: () => unawaited(onShare(actionContext)),
                    style: style,
                    icon: const Icon(Icons.ios_share_rounded, size: 20),
                    label: Text(shareLabel),
                  ),
                ),
              ),
        );
        final copy = Semantics(
          button: true,
          label: copyLabel,
          child: ExcludeSemantics(
            child: OutlinedButton.icon(
              key: const ValueKey<String>('study-copy-link-button'),
              onPressed: () => unawaited(onCopy()),
              style: style,
              icon: const Icon(Icons.link_rounded, size: 20),
              label: Text(copyLabel),
            ),
          ),
        );
        if (stacked) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [share, const SizedBox(height: 8), copy],
          );
        }
        return Row(
          children: [
            Expanded(child: share),
            const SizedBox(width: 8),
            Expanded(child: copy),
          ],
        );
      },
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
    required this.chapterKey,
    required this.chapter,
    required this.displayIndex,
    required this.isOpening,
    required this.interactionsEnabled,
    required this.isRequested,
    required this.onOpen,
    required this.onShare,
    required this.onCopy,
    super.key,
  });

  final GlobalKey chapterKey;
  final GamebaseStudyChapterMetadata chapter;
  final int displayIndex;
  final bool isOpening;
  final bool interactionsEnabled;
  final bool isRequested;
  final VoidCallback onOpen;
  final Future<void> Function(BuildContext context) onShare;
  final Future<void> Function() onCopy;

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
          '${isRequested ? 'Shared context, ' : ''}Chapter $displayIndex, ${name == null || name.isEmpty ? 'untitled' : name}',
      child: Container(
        key: chapterKey,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: context.colors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isRequested ? context.colors.brand : context.colors.divider,
            width: isRequested ? 2 : 1,
          ),
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
            const SizedBox(height: 10),
            _PublicLinkActions(
              key: ValueKey<String>(
                'share-chapter-actions-${chapter.canonicalChapterId}',
              ),
              shareLabel: 'Share chapter',
              copyLabel: 'Copy chapter share text',
              onShare: onShare,
              onCopy: onCopy,
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

GamebaseStudyChapterMetadata? _chapterById(
  Iterable<GamebaseStudyChapterMetadata> chapters,
  String? chapterId,
) {
  if (chapterId == null) return null;
  for (final chapter in chapters) {
    if (chapter.canonicalChapterId == chapterId) return chapter;
  }
  return null;
}

int? _nearestPly(int? requestedPly, int chapterPlyCount) {
  if (requestedPly == null) return null;
  return requestedPly.clamp(0, chapterPlyCount);
}
