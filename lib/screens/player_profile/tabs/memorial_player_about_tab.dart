import 'dart:math' as math;

import 'package:chessever2/repository/gamebase/memorial_player_about.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/country_utils.dart';
import 'package:chessever2/widgets/app_snack.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// The historical knowledge layer embedded in the regular, analytics-rich
/// About tab for a Memorial player.
class MemorialPlayerKnowledge extends StatelessWidget {
  const MemorialPlayerKnowledge({
    super.key,
    required this.overview,
    required this.fallbackName,
  });

  final MemorialPlayerOverview overview;
  final String fallbackName;

  @override
  Widget build(BuildContext context) {
    final player = overview.player;
    final about = overview.about;
    final name = memorialNaturalName(
      player.name.isEmpty ? fallbackName : player.name,
    );
    final summary =
        about?.summary.isNotEmpty == true
            ? about!.summary
            : memorialGeneratedSummary(overview: overview, name: name);
    final highlights = (about?.achievements ?? const [])
        .where((item) => !isMemorialPeakRatingAchievement(item.label))
        .toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (overview.history?.points.isNotEmpty == true) ...[
          _HistoricalRatingsCard(overview: overview),
          const SizedBox(height: 24),
        ],
        _KnowledgeCard(
          title: 'Life and career',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _LifeFacts(overview: overview),
              const SizedBox(height: 24),
              for (var index = 0; index < summary.length; index++) ...[
                Text(
                  summary[index],
                  style: AppTypography.textSmRegular.copyWith(
                    color: context.colors.textSecondary,
                    height: 1.65,
                  ),
                ),
                if (index != summary.length - 1) const SizedBox(height: 12),
              ],
              if (highlights.isNotEmpty) ...[
                const SizedBox(height: 28),
                Text(
                  'Career highlights',
                  style: AppTypography.textMdBold.copyWith(
                    color: context.colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 14),
                for (final highlight in highlights)
                  _CareerHighlight(highlight: highlight),
              ],
            ],
          ),
        ),
        if (overview.sources.isNotEmpty) ...[
          const SizedBox(height: 24),
          _SourcesCard(sources: overview.sources),
        ],
      ],
    );
  }
}

class _KnowledgeCard extends StatelessWidget {
  const _KnowledgeCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: AppTypography.textLgBold.copyWith(
              color: context.colors.textPrimary,
            ),
          ),
          const SizedBox(height: 20),
          child,
        ],
      ),
    );
  }
}

class _LifeFacts extends StatelessWidget {
  const _LifeFacts({required this.overview});

  final MemorialPlayerOverview overview;

  @override
  Widget build(BuildContext context) {
    final player = overview.player;
    final about = overview.about;
    final honoraryTitle = memorialHonoraryTitle(about);
    final titleYear =
        honoraryTitle?.year ??
        memorialTitleAwardYear(about?.achievements ?? const [], player.title);
    final federationName =
        player.fed.trim().isEmpty
            ? 'Unknown'
            : CountryUtils.getCountryName(player.fed).trim();
    final ratingSpan = overview.history?.ratingListSpan;

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 560 ? 3 : 2;
        const gap = 18.0;
        final width = (constraints.maxWidth - (gap * (columns - 1))) / columns;
        final facts = <Widget>[
          _LifeFact(
            label: 'Born',
            value: formatMemorialProfileDate(player.birthDate),
            detail: about?.birthPlace,
          ),
          _LifeFact(
            label: 'Died',
            value: formatMemorialProfileDate(player.deathDate),
            detail: about?.deathPlace,
          ),
          _LifeFact(
            label: 'Chess title',
            value: honoraryTitle?.label ?? memorialExpandedTitle(player.title),
            detail: titleYear == null ? null : 'Awarded $titleYear',
          ),
          _LifeFact(
            label: 'Federation',
            value: federationName.isEmpty ? player.fed : federationName,
            detail: player.fed.trim().isEmpty ? null : player.fed,
          ),
          _LifeFact(
            label: 'Historical FIDE ID',
            value:
                player.fideId?.trim().isNotEmpty == true
                    ? player.fideId!.trim()
                    : 'Not assigned',
            detail: memorialFideStatusLabel(player.fideIdStatus),
          ),
          if (ratingSpan != null)
            _LifeFact(
              label: 'Rating-list record',
              value:
                  '${formatMemorialPeriod(ratingSpan.firstPeriod)} to '
                  '${formatMemorialPeriod(ratingSpan.lastPeriod)}',
            ),
        ];

        return Wrap(
          spacing: gap,
          runSpacing: 20,
          children: [
            for (final fact in facts) SizedBox(width: width, child: fact),
          ],
        );
      },
    );
  }
}

class _LifeFact extends StatelessWidget {
  const _LifeFact({required this.label, required this.value, this.detail});

  final String label;
  final String value;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTypography.textXsMedium.copyWith(
            color: context.colors.textSecondary,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          value,
          style: AppTypography.textSmBold.copyWith(
            color: context.colors.textPrimary,
          ),
        ),
        if (detail?.trim().isNotEmpty == true) ...[
          const SizedBox(height: 4),
          Text(
            detail!.trim(),
            style: AppTypography.textXsRegular.copyWith(
              color: context.colors.textSecondary,
              height: 1.35,
            ),
          ),
        ],
      ],
    );
  }
}

class _CareerHighlight extends StatelessWidget {
  const _CareerHighlight({required this.highlight});

  final MemorialPlayerAchievement highlight;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 13),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 62,
            child: Text(
              highlight.year,
              style: AppTypography.textXsBold.copyWith(
                color: context.colors.titleAccent,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          Expanded(
            child: Text(
              highlight.label,
              style: AppTypography.textSmRegular.copyWith(
                color: context.colors.textSecondary,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HistoricalRatingsCard extends StatefulWidget {
  const _HistoricalRatingsCard({required this.overview});

  final MemorialPlayerOverview overview;

  @override
  State<_HistoricalRatingsCard> createState() => _HistoricalRatingsCardState();
}

class _HistoricalRatingsCardState extends State<_HistoricalRatingsCard> {
  MemorialRatingType _selectedType = MemorialRatingType.classical;

  List<MemorialRatingType> get _availableTypes {
    final history = widget.overview.history;
    if (history == null) return const [];
    return MemorialRatingType.values
        .where((type) => history.pointsFor(type).isNotEmpty)
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final history = widget.overview.history!;
    final availableTypes = _availableTypes;
    if (availableTypes.isEmpty) return const SizedBox.shrink();
    final selected =
        availableTypes.contains(_selectedType)
            ? _selectedType
            : availableTypes.first;
    final points = history.pointsFor(selected);
    final ratings = points
        .map((point) => point.ratingFor(selected))
        .whereType<int>()
        .toList(growable: false);
    final peak = ratings.reduce(math.max);
    final peakPeriod =
        history.peakPeriodFor(selected) ??
        _periodForPoint(
          points.firstWhere((point) => point.ratingFor(selected) == peak),
        );
    final games = points.fold<int>(
      0,
      (total, point) => total + (point.gamesFor(selected) ?? 0),
    );

    return _KnowledgeCard(
      title: 'Historical ratings',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (availableTypes.length > 1) ...[
            Row(
              children: [
                for (final type in availableTypes)
                  Expanded(
                    child: _RatingTypeTab(
                      type: type,
                      selected: type == selected,
                      onTap: () => setState(() => _selectedType = type),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 22),
          ],
          Wrap(
            spacing: 28,
            runSpacing: 14,
            children: [
              _RatingFact(label: 'Peak', value: peak.toString()),
              _RatingFact(
                label: 'Peak list',
                value: formatMemorialPeriod(peakPeriod),
              ),
              _RatingFact(label: 'Published lists', value: '${points.length}'),
              if (games > 0)
                _RatingFact(label: 'Rated games', value: games.toString()),
            ],
          ),
          const SizedBox(height: 22),
          Semantics(
            label: memorialRatingHistorySemantics(
              type: selected,
              points: points,
              peak: peak,
              peakPeriod: peakPeriod,
            ),
            image: true,
            child: SizedBox(
              height: 180,
              width: double.infinity,
              child: CustomPaint(
                painter: _RatingHistoryPainter(
                  points: points,
                  type: selected,
                  lineColor: context.colors.titleAccent,
                  guideColor: context.colors.textSecondary.withValues(
                    alpha: 0.18,
                  ),
                  labelColor: context.colors.textSecondary,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '${formatMemorialPeriod(_periodForPoint(points.first))} to '
            '${formatMemorialPeriod(_periodForPoint(points.last))}',
            style: AppTypography.textXsRegular.copyWith(
              color: context.colors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _RatingTypeTab extends StatelessWidget {
  const _RatingTypeTab({
    required this.type,
    required this.selected,
    required this.onTap,
  });

  final MemorialRatingType type;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: '${memorialRatingTypeLabel(type)} rating history',
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(6, 8, 6, 10),
          child: Column(
            children: [
              Text(
                memorialRatingTypeLabel(type),
                style: AppTypography.textSmMedium.copyWith(
                  color:
                      selected
                          ? context.colors.textPrimary
                          : context.colors.textSecondary,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                height: 2,
                decoration: BoxDecoration(
                  color:
                      selected
                          ? context.colors.titleAccent
                          : Colors.transparent,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RatingFact extends StatelessWidget {
  const _RatingFact({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 100,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: AppTypography.textLgBold.copyWith(
              color: context.colors.textPrimary,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            style: AppTypography.textXsRegular.copyWith(
              color: context.colors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _RatingHistoryPainter extends CustomPainter {
  const _RatingHistoryPainter({
    required this.points,
    required this.type,
    required this.lineColor,
    required this.guideColor,
    required this.labelColor,
  });

  final List<MemorialRatingHistoryPoint> points;
  final MemorialRatingType type;
  final Color lineColor;
  final Color guideColor;
  final Color labelColor;

  @override
  void paint(Canvas canvas, Size size) {
    final values = points
        .map((point) => point.ratingFor(type))
        .whereType<int>()
        .toList(growable: false);
    if (values.isEmpty) return;

    final rawMin = values.reduce(math.min);
    final rawMax = values.reduce(math.max);
    final spread = math.max(100, rawMax - rawMin);
    final minValue = ((rawMin - spread * 0.12) / 50).floor() * 50;
    final maxValue = ((rawMax + spread * 0.12) / 50).ceil() * 50;
    const left = 2.0;
    const right = 42.0;
    const top = 8.0;
    const bottom = 12.0;
    final chartWidth = math.max(1.0, size.width - left - right);
    final chartHeight = math.max(1.0, size.height - top - bottom);
    final valueRange = math.max(1, maxValue - minValue);

    final guidePaint =
        Paint()
          ..color = guideColor
          ..strokeWidth = 1;
    for (var index = 0; index < 3; index++) {
      final fraction = index / 2;
      final y = top + chartHeight * fraction;
      canvas.drawLine(
        Offset(left, y),
        Offset(left + chartWidth, y),
        guidePaint,
      );
      final label = (maxValue - valueRange * fraction).round().toString();
      _paintLabel(canvas, label, Offset(size.width - right + 7, y - 7));
    }

    final path = Path();
    for (var index = 0; index < values.length; index++) {
      final x =
          left +
          (values.length == 1 ? 0 : chartWidth * index / (values.length - 1));
      final y =
          top + chartHeight * (1 - (values[index] - minValue) / valueRange);
      if (index == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = lineColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.25
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  void _paintLabel(Canvas canvas, String label, Offset offset) {
    final painter = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(color: labelColor, fontSize: 10),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(covariant _RatingHistoryPainter oldDelegate) =>
      oldDelegate.points != points ||
      oldDelegate.type != type ||
      oldDelegate.lineColor != lineColor ||
      oldDelegate.guideColor != guideColor ||
      oldDelegate.labelColor != labelColor;
}

class _SourcesCard extends StatelessWidget {
  const _SourcesCard({required this.sources});

  final List<MemorialPlayerSource> sources;

  @override
  Widget build(BuildContext context) {
    return _KnowledgeCard(
      title: 'Sources',
      child: Column(
        children: [
          for (var index = 0; index < sources.length; index++) ...[
            _SourceLink(source: sources[index]),
            if (index != sources.length - 1) const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}

class _SourceLink extends StatelessWidget {
  const _SourceLink({required this.source});

  final MemorialPlayerSource source;

  Future<void> _open(BuildContext context) async {
    final uri = Uri.tryParse(source.url);
    try {
      if (uri != null &&
          await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        return;
      }
    } catch (_) {
      // Fall through to the app's transient failure message.
    }
    if (!context.mounted) return;
    showAppSnack(
      context,
      'Could not open this source.',
      tone: AppSnackTone.danger,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      link: true,
      label: 'Open source: ${source.label}',
      child: InkWell(
        onTap: () => _open(context),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  source.label,
                  style: AppTypography.textSmMedium.copyWith(
                    color: context.colors.textPrimary,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Icon(
                Icons.open_in_new_rounded,
                size: 18,
                color: context.colors.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String memorialRatingTypeLabel(MemorialRatingType type) => switch (type) {
  MemorialRatingType.classical => 'Classical',
  MemorialRatingType.rapid => 'Rapid',
  MemorialRatingType.blitz => 'Blitz',
};

String memorialRatingHistorySemantics({
  required MemorialRatingType type,
  required List<MemorialRatingHistoryPoint> points,
  required int peak,
  required String peakPeriod,
}) {
  return '${memorialRatingTypeLabel(type)} rating history from '
      '${formatMemorialPeriod(_periodForPoint(points.first))} to '
      '${formatMemorialPeriod(_periodForPoint(points.last))}. '
      'Peak $peak in ${formatMemorialPeriod(peakPeriod)}.';
}

String formatMemorialProfileDate(String? value) {
  final raw = value?.trim();
  if (raw == null || raw.isEmpty) return 'Unknown';
  final match = RegExp(r'^(\d{4})(?:-(\d{2})(?:-(\d{2}))?)?$').firstMatch(raw);
  if (match == null) return raw;
  final year = int.tryParse(match.group(1) ?? '');
  final month = int.tryParse(match.group(2) ?? '');
  final day = int.tryParse(match.group(3) ?? '');
  if (year == null) return raw;
  if (month == null) return year.toString();
  const months = <String>[
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  if (month < 1 || month > 12) return raw;
  if (day == null) return '${months[month - 1]} $year';
  return '${months[month - 1]} $day, $year';
}

String formatMemorialPeriod(String value) {
  final raw = value.trim();
  final match = RegExp(r'^(\d{4})-(\d{2})$').firstMatch(raw);
  if (match == null) return raw;
  final month = int.tryParse(match.group(2) ?? '');
  if (month == null || month < 1 || month > 12) return raw;
  const shortMonths = <String>[
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${shortMonths[month - 1]} ${match.group(1)}';
}

String _periodForPoint(MemorialRatingHistoryPoint point) =>
    '${point.year.toString().padLeft(4, '0')}-'
    '${point.month.toString().padLeft(2, '0')}';

String memorialNaturalName(String value) {
  final parts = value.split(',');
  if (parts.length < 2) return value.trim();
  return '${parts.skip(1).join(' ').trim()} ${parts.first.trim()}'.trim();
}

List<String> memorialGeneratedSummary({
  required MemorialPlayerOverview overview,
  required String name,
}) {
  final player = overview.player;
  final title = memorialExpandedTitle(player.title);
  final federationName =
      player.fed.trim().isEmpty
          ? ''
          : CountryUtils.getCountryName(player.fed).trim();
  final first =
      '$name was ${RegExp(r'^[AEIOU]', caseSensitive: false).hasMatch(title) ? 'an' : 'a'} '
      '${title == 'Not recorded' ? 'titled chess player' : title}'
      '${federationName.isEmpty ? '' : ' who represented $federationName in FIDE-rated chess'}.';
  final history = overview.history;
  if (player.ratingClassical <= 0) {
    return <String>[
      first,
      'The reviewed Memorial record includes a historical rating record for this player.',
    ];
  }
  final details = <String>[
    'The reviewed rating record shows a peak Classical rating of '
        '${player.ratingClassical} in '
        '${formatMemorialPeriod(history?.peakPeriod ?? 'the reviewed rating period')}.',
    if (player.ratingRapid > 0)
      'It also shows a peak Rapid rating of ${player.ratingRapid} in '
          '${formatMemorialPeriod(history?.peakRapidPeriod ?? 'the reviewed rating period')}.',
    if (player.ratingBlitz > 0)
      'It also shows a peak Blitz rating of ${player.ratingBlitz} in '
          '${formatMemorialPeriod(history?.peakBlitzPeriod ?? 'the reviewed rating period')}.',
  ];
  return <String>[first, details.join(' ')];
}

String? memorialTitleAwardYear(
  List<MemorialPlayerAchievement> achievements,
  String? titleCode,
) {
  final title = memorialExpandedTitle(titleCode);
  if (title == 'Not recorded') return null;
  final pattern = RegExp(
    '\\b${RegExp.escape(title)} title\\b',
    caseSensitive: false,
  );
  for (final achievement in achievements) {
    if (pattern.hasMatch(achievement.label)) {
      return achievement.year;
    }
  }
  return null;
}

String memorialExpandedTitle(String? code) {
  return switch (code?.trim().toUpperCase()) {
    'GM' => 'Grandmaster',
    'IM' => 'International Master',
    'FM' => 'FIDE Master',
    'CM' => 'Candidate Master',
    'WGM' => 'Woman Grandmaster',
    'WIM' => 'Woman International Master',
    'WFM' => 'Woman FIDE Master',
    'WCM' => 'Woman Candidate Master',
    null || '' => 'Not recorded',
    _ => code!.trim(),
  };
}

({String label, String? year})? memorialHonoraryTitle(
  MemorialPlayerAbout? about,
) {
  if (about == null) return null;
  final honoraryPattern = RegExp(
    r'honorary\s+Grandmaster|Grandmaster\s+honoris causa',
    caseSensitive: false,
  );
  MemorialPlayerAchievement? matchedAchievement;
  for (final achievement in about.achievements) {
    if (honoraryPattern.hasMatch(achievement.label)) {
      matchedAchievement = achievement;
      break;
    }
  }
  final text = <String>[
    ...about.summary,
    ...about.achievements.map((item) => item.label),
  ].join(' ');
  if (matchedAchievement == null && !honoraryPattern.hasMatch(text)) {
    return null;
  }
  final year =
      RegExp(
        r'\b(?:19|20)\d{2}\b',
      ).firstMatch(matchedAchievement?.year ?? '')?.group(0) ??
      RegExp(
        r'honorary\s+Grandmaster\s+title\s+in\s+((?:19|20)\d{2})',
        caseSensitive: false,
      ).firstMatch(text)?.group(1);
  return (label: 'Grandmaster (honorary)', year: year);
}

String? memorialFideStatusLabel(String? value) {
  final normalized = value?.trim().toLowerCase();
  return switch (normalized) {
    null || '' => null,
    'valid' || 'verified' => 'Verified historical identity',
    'missing' || 'unassigned' => 'No FIDE ID was assigned',
    'reused' => 'Legacy FIDE ID was later reused',
    'ambiguous' => 'Historical identity is ambiguous',
    _ => value!.trim(),
  };
}

bool isMemorialPeakRatingAchievement(String label) {
  return RegExp(
    r'^(?:Peak\b.*\brating\b|Reached a peak\b.*\brating\b)',
    caseSensitive: false,
  ).hasMatch(label);
}
