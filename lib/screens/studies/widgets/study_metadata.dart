import 'package:chessever2/repository/gamebase/gamebase_repository.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/number_format_utils.dart';
import 'package:flutter/material.dart';

class StudySummaryCard extends StatelessWidget {
  const StudySummaryCard({
    required this.study,
    required this.onPressed,
    super.key,
  });

  final GamebaseStudySummary study;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final author = study.authorUsername?.trim();
    final sourceCopy =
        author == null || author.isEmpty
            ? 'Lichess Study'
            : 'Lichess Study by $author';

    return Semantics(
      container: true,
      button: true,
      label: _studyCardSemantics(study),
      child: ExcludeSemantics(
        child: Material(
          color: context.colors.surface,
          borderRadius: BorderRadius.circular(16),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onPressed,
            child: Container(
              constraints: const BoxConstraints(minHeight: 190),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border.all(color: context.colors.divider),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              study.name,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(
                                context,
                              ).textTheme.titleMedium?.copyWith(
                                color: context.colors.textPrimary,
                                fontWeight: FontWeight.w700,
                                height: 1.22,
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              sourceCopy,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(
                                context,
                              ).textTheme.bodySmall?.copyWith(
                                color: context.colors.textSecondary,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      _CredibilityMark(score: study.credibilityScore),
                    ],
                  ),
                  const SizedBox(height: 14),
                  StudyQualityMetrics(study: study),
                  if (_hasSignals(study)) ...[
                    const SizedBox(height: 13),
                    StudySignalSummary(study: study, compact: true),
                  ],
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'View Study metadata',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(
                            context,
                          ).textTheme.labelLarge?.copyWith(
                            color: context.colors.brandMuted,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        Icons.chevron_right_rounded,
                        color: context.colors.brandMuted,
                        size: 22,
                      ),
                    ],
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

class StudyQualityMetrics extends StatelessWidget {
  const StudyQualityMetrics({required this.study, super.key});

  final GamebaseStudySummary study;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 7,
      runSpacing: 7,
      children: [
        _MetricPill(
          icon: Icons.visibility_outlined,
          label: '${formatCompactCount(study.views)} views',
        ),
        _MetricPill(
          icon: Icons.format_list_numbered_rounded,
          label:
              '${study.chapterCount} ${study.chapterCount == 1 ? 'chapter' : 'chapters'}',
        ),
        if (study.hasAnnotations)
          const _MetricPill(
            icon: Icons.rate_review_outlined,
            label: 'Annotated',
          ),
        if (study.isGamebook)
          const _MetricPill(icon: Icons.touch_app_outlined, label: 'Gamebook'),
      ],
    );
  }
}

class StudySignalSummary extends StatelessWidget {
  const StudySignalSummary({
    required this.study,
    super.key,
    this.compact = false,
  });

  final GamebaseStudySummary study;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    void addRow(IconData icon, String label, List<String> values) {
      final cleaned = values
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty)
          .toSet()
          .take(compact ? 2 : 4)
          .toList(growable: false);
      if (cleaned.isEmpty) return;
      rows.add(
        _SignalLine(icon: icon, label: label, value: cleaned.join(' · ')),
      );
    }

    addRow(Icons.auto_stories_outlined, 'Openings', study.openings);
    addRow(Icons.tag_rounded, 'ECO', study.ecos);
    addRow(Icons.people_outline_rounded, 'Players', study.players);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var index = 0; index < rows.length; index++) ...[
          if (index > 0) const SizedBox(height: 6),
          rows[index],
        ],
      ],
    );
  }
}

class StudySourceNotice extends StatelessWidget {
  const StudySourceNotice({super.key});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label:
          'Source safety. Study and chapter actions open the original content on Lichess.',
      child: ExcludeSemantics(
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: context.colors.surfaceRecessed,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.verified_user_outlined,
                color: context.colors.brandMuted,
                size: 21,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Study and chapter actions open the original content on Lichess.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: context.colors.textPrimaryMuted,
                    height: 1.4,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class StudyExternalButton extends StatelessWidget {
  const StudyExternalButton({
    required this.label,
    required this.onPressed,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(48),
        backgroundColor: context.colors.brand,
        foregroundColor: context.colors.textInverse,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.open_in_new_rounded, size: 19),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}

class StudySectionTitle extends StatelessWidget {
  const StudySectionTitle({required this.title, super.key, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            color: context.colors.textPrimary,
            fontWeight: FontWeight.w800,
            height: 1.18,
          ),
        ),
        if (subtitle case final subtitle?) ...[
          const SizedBox(height: 5),
          Text(
            subtitle,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: context.colors.textSecondary,
              height: 1.4,
            ),
          ),
        ],
      ],
    );
  }
}

class _CredibilityMark extends StatelessWidget {
  const _CredibilityMark({required this.score});

  final double score;

  @override
  Widget build(BuildContext context) {
    final display = score.toStringAsFixed(score % 1 == 0 ? 0 : 1);
    return Semantics(
      label: 'Credibility score $display out of 100',
      child: Container(
        constraints: const BoxConstraints(minWidth: 52, minHeight: 48),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: context.colors.surfaceRecessed,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              display,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: context.colors.textPrimary,
                fontWeight: FontWeight.w800,
                height: 1,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              'quality',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: context.colors.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MetricPill extends StatelessWidget {
  const _MetricPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 32),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: context.colors.surfaceRecessed,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: context.colors.iconSecondary, size: 15),
          const SizedBox(width: 5),
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: context.colors.textPrimaryMuted,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _SignalLine extends StatelessWidget {
  const _SignalLine({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(icon, size: 16, color: context.colors.iconSecondary),
        ),
        const SizedBox(width: 7),
        Text(
          '$label: ',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: context.colors.textSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
        Expanded(
          child: Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
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

bool _hasSignals(GamebaseStudySummary study) {
  return study.openings.isNotEmpty ||
      study.ecos.isNotEmpty ||
      study.players.isNotEmpty;
}

String _studyCardSemantics(GamebaseStudySummary study) {
  final score = study.credibilityScore.toStringAsFixed(
    study.credibilityScore % 1 == 0 ? 0 : 1,
  );
  final annotations = study.hasAnnotations ? ' Annotated.' : '';
  return 'Open Study details for ${study.name}. '
      'Credibility score $score out of 100. '
      '${study.views} views. '
      '${study.chapterCount} ${study.chapterCount == 1 ? 'chapter' : 'chapters'}.'
      '$annotations';
}
