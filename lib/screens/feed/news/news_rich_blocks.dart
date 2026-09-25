import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:chessever2/config/app_environment.dart';
import 'package:chessever2/screens/feed/news/news_content.dart';
import 'package:chessever2/screens/feed/news/news_cover.dart';
import 'package:chessever2/screens/feed/news/news_models.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/widgets/federation_flag.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:motor/motor.dart';

/// Opens a resolved article link; the reader decides in-app vs browser.
typedef NewsLinkHandler = void Function(Uri uri);

const double _radius = 4;

// -----------------------------------------------------------------------------
// Markdown prose
// -----------------------------------------------------------------------------

/// One run of article prose, rendered as markdown in the app's type.
class NewsMarkdown extends StatelessWidget {
  const NewsMarkdown({super.key, required this.markdown, required this.onLink});

  final String markdown;
  final NewsLinkHandler onLink;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final body = AppTypography.textMdRegular.copyWith(
      color: colors.textPrimary,
      height: 1.6,
    );
    final small = AppTypography.textSmRegular.copyWith(
      color: colors.textPrimary,
      height: 1.45,
    );
    final base = MarkdownStyleSheet.fromTheme(Theme.of(context));
    return MarkdownBody(
      data: markdown,
      onTapLink: (text, href, title) {
        final uri = resolveNewsHref(href);
        if (uri != null) onLink(uri);
      },
      imageBuilder: (uri, title, alt) =>
          _MarkdownImage(uri: uri, alt: alt, onLink: onLink),
      styleSheet: base.copyWith(
        p: body,
        a: body.copyWith(
          decoration: TextDecoration.underline,
          decorationColor: colors.textTertiary,
        ),
        strong: body.copyWith(fontWeight: FontWeight.w700),
        em: body.copyWith(fontStyle: FontStyle.italic),
        del: body.copyWith(decoration: TextDecoration.lineThrough),
        h1: AppTypography.textXlBold.copyWith(
          color: colors.textPrimary,
          height: 1.3,
        ),
        h2: AppTypography.textLgBold.copyWith(
          color: colors.textPrimary,
          height: 1.35,
        ),
        h3: AppTypography.textMdBold.copyWith(
          color: colors.textPrimary,
          height: 1.4,
        ),
        h4: AppTypography.textMdBold.copyWith(color: colors.textPrimary),
        h5: AppTypography.textMdBold.copyWith(color: colors.textPrimary),
        h6: AppTypography.textMdBold.copyWith(color: colors.textPrimary),
        h1Padding: const EdgeInsets.only(top: 12),
        h2Padding: const EdgeInsets.only(top: 10),
        h3Padding: const EdgeInsets.only(top: 8),
        // Paragraphs breathe (8 + 8); list items stay a tight 8 apart.
        blockSpacing: 8,
        pPadding: const EdgeInsets.only(bottom: 8),
        listIndent: 22,
        listBullet: body.copyWith(color: colors.textSecondary),
        blockquote: body.copyWith(color: colors.textSecondary),
        blockquotePadding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        blockquoteDecoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(_radius),
        ),
        code: small.copyWith(
          fontFamily: 'monospace',
          backgroundColor: colors.surface,
        ),
        codeblockPadding: const EdgeInsets.all(14),
        codeblockDecoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(_radius),
        ),
        tableHead: small.copyWith(fontWeight: FontWeight.w700),
        tableBody: small,
        tableHeadAlign: TextAlign.left,
        tableColumnWidth: const IntrinsicColumnWidth(),
        tableCellsPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 8,
        ),
        tableHeadCellsDecoration: BoxDecoration(color: colors.surface),
        tableBorder: TableBorder(
          horizontalInside: BorderSide(color: colors.divider),
          bottom: BorderSide(color: colors.divider),
        ),
        tableScrollbarThumbVisibility: false,
        horizontalRuleDecoration: BoxDecoration(
          color: colors.divider,
          borderRadius: BorderRadius.circular(1),
        ),
      ),
    );
  }
}

/// Hosts an article's inline pictures may load from on their own: the
/// ChessEver site, Supabase Storage of either app flavour (a test build can
/// read rows copied from production) and YouTube's thumbnail CDN.
///
/// A picture anywhere else would be fetched the moment the article opens,
/// handing each reader's IP address and user agent to that host (a tracking
/// pixel) at whatever size it likes; it shows as a link instead.
const Set<String> _newsImageHosts = {
  'chessever.com',
  'www.chessever.com',
  'i.ytimg.com',
  '${AppEnvironment.productionSupabaseProjectRef}.supabase.co',
  '${AppEnvironment.testSupabaseProjectRef}.supabase.co',
};

const List<String> _supabaseImagePaths = [
  '/storage/v1/object/public/',
  '/storage/v1/render/image/public/',
];

/// Whether an inline article image at [uri] (already resolved by
/// [resolveNewsHref]) may load automatically: https on the default port, no
/// user info, an allow-listed host, and on Supabase only a public Storage
/// object.
bool isNewsImageSourceAllowed(Uri uri) {
  if (uri.scheme != 'https' || uri.userInfo.isNotEmpty || uri.port != 443) {
    return false;
  }
  final host = uri.host.toLowerCase();
  if (!_newsImageHosts.contains(host)) return false;
  if (host.endsWith('.supabase.co')) {
    return _supabaseImagePaths.any(uri.path.startsWith);
  }
  return true;
}

class _MarkdownImage extends StatelessWidget {
  const _MarkdownImage({
    required this.uri,
    required this.alt,
    required this.onLink,
  });

  final Uri uri;
  final String? alt;
  final NewsLinkHandler onLink;

  @override
  Widget build(BuildContext context) {
    final resolved = resolveNewsHref(uri.toString());
    if (resolved == null) return const SizedBox.shrink();
    if (!isNewsImageSourceAllowed(resolved)) {
      return _ImageLink(uri: resolved, alt: alt, onLink: onLink);
    }
    // Never wider than the screen; no LayoutBuilder, since a markdown table
    // measures its cells' intrinsic sizes.
    final pixelWidth =
        (MediaQuery.sizeOf(context).width *
                MediaQuery.devicePixelRatioOf(context))
            .round();
    return Semantics(
      image: true,
      label: alt,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(_radius),
        child: NewsNetworkImage(
          url: resolved.toString(),
          pixelWidth: pixelWidth > 0 ? pixelWidth : null,
          fit: BoxFit.fitWidth,
          width: double.infinity,
          placeholder: (context, _) => AspectRatio(
            aspectRatio: 16 / 9,
            child: ColoredBox(color: context.colors.surface),
          ),
          errorWidget: (context, _, _) => const SizedBox.shrink(),
        ),
      ),
    );
  }
}

/// A picture from a host outside [_newsImageHosts]: nothing is fetched until
/// the reader taps, which opens it outside the app.
class _ImageLink extends StatelessWidget {
  const _ImageLink({
    required this.uri,
    required this.alt,
    required this.onLink,
  });

  final Uri uri;
  final String? alt;
  final NewsLinkHandler onLink;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final caption = alt?.trim() ?? '';
    final label = caption.isEmpty ? 'Image' : caption;
    return Semantics(
      link: true,
      label: '$label, image on ${uri.host}',
      excludeSemantics: true,
      child: NewsPressable(
        onTap: () => onLink(uri),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: label,
                        style: AppTypography.textSmMedium.copyWith(
                          color: colors.textPrimary,
                        ),
                      ),
                      TextSpan(
                        text: '  ${uri.host}',
                        style: AppTypography.textSmRegular.copyWith(
                          color: colors.textTertiary,
                        ),
                      ),
                    ],
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 6),
              NewsOutArrow(color: colors.textSecondary, size: 12),
            ],
          ),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Section heading, YouTube
// -----------------------------------------------------------------------------

class NewsSectionHeading extends StatelessWidget {
  const NewsSectionHeading({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      header: true,
      child: Text(
        text,
        style: AppTypography.textXlBold.copyWith(
          color: context.colors.textPrimary,
          height: 1.3,
        ),
      ),
    );
  }
}

/// The web embeds the video; the app shows its frame and hands the tap to
/// YouTube.
class NewsYoutubeCard extends StatelessWidget {
  const NewsYoutubeCard({
    super.key,
    required this.videoId,
    required this.onLink,
  });

  final String videoId;
  final NewsLinkHandler onLink;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      button: true,
      label: 'Play video on YouTube',
      excludeSemantics: true,
      child: NewsPressable(
        onTap: () => onLink(Uri.parse('https://youtu.be/$videoId')),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(_radius),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(_radius),
                ),
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: CachedNetworkImage(
                    imageUrl: 'https://i.ytimg.com/vi/$videoId/hqdefault.jpg',
                    fit: BoxFit.cover,
                    placeholder: (context, _) =>
                        ColoredBox(color: colors.surface),
                    errorWidget: (context, _, _) =>
                        ColoredBox(color: colors.surface),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Play on YouTube',
                        style: AppTypography.textSmSemiBold.copyWith(
                          color: colors.textPrimary,
                        ),
                      ),
                    ),
                    NewsOutArrow(color: colors.textSecondary),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The up-and-out arrow used for every link that leaves the app.
class NewsOutArrow extends StatelessWidget {
  const NewsOutArrow({super.key, required this.color, this.size = 14});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _OutArrowPainter(color),
    );
  }
}

class _OutArrowPainter extends CustomPainter {
  _OutArrowPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.12
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    // Shaft, then a head whose arms are a touch longer than usual.
    canvas.drawLine(Offset(s * 0.2, s * 0.8), Offset(s * 0.8, s * 0.2), paint);
    canvas.drawPath(
      Path()
        ..moveTo(s * 0.3, s * 0.2)
        ..lineTo(s * 0.8, s * 0.2)
        ..lineTo(s * 0.8, s * 0.7),
      paint,
    );
  }

  @override
  bool shouldRepaint(_OutArrowPainter oldDelegate) =>
      oldDelegate.color != color;
}

// -----------------------------------------------------------------------------
// Team results and pairings
// -----------------------------------------------------------------------------

/// Official team results: one row per match, tap for its four boards.
class NewsResultsView extends StatelessWidget {
  const NewsResultsView({
    super.key,
    required this.snapshot,
    required this.onLink,
  });

  final NewsResultsSnapshot snapshot;
  final NewsLinkHandler onLink;

  @override
  Widget build(BuildContext context) {
    return _StructuredFrame(
      title: snapshot.title,
      hint: 'Tap a match for all four boards.',
      sourceUrl: snapshot.sourceUrl,
      lastUpdate: snapshot.lastUpdate,
      onLink: onLink,
      matches: [
        for (var i = 0; i < snapshot.matches.length; i++)
          _ResultsMatchTile(number: i + 1, match: snapshot.matches[i]),
      ],
      groups: [
        if (snapshot.notPaired.isNotEmpty)
          _TeamGroup(
            title: 'Not paired',
            note: 'No opponent and no match score this round.',
            teams: snapshot.notPaired,
          ),
      ],
    );
  }
}

/// Official team pairings: one row per match, tap for its boards.
class NewsPairingsView extends StatelessWidget {
  const NewsPairingsView({
    super.key,
    required this.snapshot,
    required this.onLink,
  });

  final NewsPairingsSnapshot snapshot;
  final NewsLinkHandler onLink;

  @override
  Widget build(BuildContext context) {
    return _StructuredFrame(
      title: snapshot.title,
      hint: 'Tap a match for its board pairings.',
      sourceUrl: snapshot.sourceUrl,
      lastUpdate: snapshot.lastUpdate,
      onLink: onLink,
      matches: [
        for (var i = 0; i < snapshot.matches.length; i++)
          _PairingsMatchTile(number: i + 1, match: snapshot.matches[i]),
      ],
      groups: [
        if (snapshot.notPaired.isNotEmpty)
          _TeamGroup(
            title: 'Not paired',
            note: 'No opponent this round.',
            teams: snapshot.notPaired,
          ),
        if (snapshot.byes.isNotEmpty)
          _TeamGroup(title: 'Bye', note: null, teams: snapshot.byes),
      ],
    );
  }
}

class _StructuredFrame extends StatelessWidget {
  const _StructuredFrame({
    required this.title,
    required this.hint,
    required this.matches,
    required this.groups,
    required this.sourceUrl,
    required this.lastUpdate,
    required this.onLink,
  });

  final String title;
  final String hint;
  final List<Widget> matches;
  final List<Widget> groups;
  final String? sourceUrl;
  final String? lastUpdate;
  final NewsLinkHandler onLink;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final source = sourceUrl == null ? null : Uri.tryParse(sourceUrl!);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text(
            title,
            style: AppTypography.textLgBold.copyWith(
              color: colors.textPrimary,
              height: 1.3,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          hint,
          style: AppTypography.textSmRegular.copyWith(
            color: colors.textSecondary,
          ),
        ),
        const SizedBox(height: 12),
        for (var i = 0; i < matches.length; i++) ...[
          if (i > 0) const SizedBox(height: 2),
          matches[i],
        ],
        for (final group in groups) ...[const SizedBox(height: 20), group],
        if (source != null) ...[
          const SizedBox(height: 14),
          Semantics(
            link: true,
            label: 'Official data on chess-results.com',
            excludeSemantics: true,
            child: NewsPressable(
              onTap: () => onLink(source),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        [
                          'Official data: chess-results.com',
                          if (lastUpdate != null) 'updated $lastUpdate',
                        ].join(', '),
                        style: AppTypography.textXsRegular.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    NewsOutArrow(color: colors.textSecondary, size: 11),
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// A match row that opens to show its boards; the reveal and the chevron run
/// on one spring.
class _ExpandableMatch extends StatefulWidget {
  const _ExpandableMatch({
    required this.semanticsLabel,
    required this.header,
    required this.body,
  });

  final String semanticsLabel;
  final Widget header;
  final WidgetBuilder body;

  @override
  State<_ExpandableMatch> createState() => _ExpandableMatchState();
}

class _ExpandableMatchState extends State<_ExpandableMatch> {
  bool _open = false;

  void _toggle() {
    HapticFeedbackService.dropdownSelect();
    setState(() => _open = !_open);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    Widget reveal(double t) {
      final chevron = Transform.rotate(
        angle: t * math.pi,
        child: _Chevron(color: colors.textSecondary),
      );
      final header = Row(
        children: [
          Expanded(child: widget.header),
          SizedBox(width: 28, child: Center(child: chevron)),
        ],
      );
      final factor = t.clamp(0.0, 1.0);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            button: true,
            expanded: _open,
            label: widget.semanticsLabel,
            excludeSemantics: true,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _toggle,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 56),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
                  child: header,
                ),
              ),
            ),
          ),
          if (factor > 0.001)
            ClipRect(
              child: Align(
                alignment: Alignment.topCenter,
                heightFactor: factor,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  child: widget.body(context),
                ),
              ),
            ),
        ],
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(_radius),
      ),
      child: reduceMotion
          ? reveal(_open ? 1 : 0)
          : SingleMotionBuilder(
              value: _open ? 1 : 0,
              motion: const CupertinoMotion.smooth(
                duration: Duration(milliseconds: 380),
              ),
              builder: (context, t, _) => reveal(t),
            ),
    );
  }
}

class _Chevron extends StatelessWidget {
  const _Chevron({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(12, 8),
      painter: _ChevronPainter(color),
    );
  }
}

class _ChevronPainter extends CustomPainter {
  _ChevronPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(
      Path()
        ..moveTo(1, 1.5)
        ..lineTo(size.width / 2, size.height - 1.5)
        ..lineTo(size.width - 1, 1.5),
      paint,
    );
  }

  @override
  bool shouldRepaint(_ChevronPainter oldDelegate) => oldDelegate.color != color;
}

/// `2.5` → `2½`, `0.5` → `½`: chess scores read in halves.
String newsScoreLabel(String score) {
  final value = double.tryParse(score.startsWith('.') ? '0$score' : score);
  if (value == null) return score;
  final whole = value.floor();
  final half = value - whole >= 0.5;
  if (!half) return '$whole';
  return whole == 0 ? '½' : '$whole½';
}

enum _Outcome { win, loss, draw }

_Outcome _outcome(String mine, String theirs) {
  final a = double.tryParse(mine.startsWith('.') ? '0$mine' : mine) ?? 0;
  final b = double.tryParse(theirs.startsWith('.') ? '0$theirs' : theirs) ?? 0;
  if (a > b) return _Outcome.win;
  if (a < b) return _Outcome.loss;
  return _Outcome.draw;
}

TextStyle _scoreStyle(BuildContext context, _Outcome outcome, double size) {
  final colors = context.colors;
  return AppTypography.textMdBold.copyWith(
    fontSize: size,
    height: 1.2,
    fontFeatures: const [FontFeature.tabularFigures()],
    color: switch (outcome) {
      _Outcome.win => colors.textPrimary,
      _Outcome.loss => colors.textTertiary,
      _Outcome.draw => colors.textSecondary,
    },
    fontWeight: outcome == _Outcome.win ? FontWeight.w700 : FontWeight.w500,
  );
}

class _TeamName extends StatelessWidget {
  const _TeamName({required this.team, this.end = false});

  final NewsTeam team;
  final bool end;

  @override
  Widget build(BuildContext context) {
    final name = Flexible(
      child: Text(
        team.name,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        textAlign: end ? TextAlign.right : TextAlign.left,
        style: AppTypography.textSmMedium.copyWith(
          color: context.colors.textPrimary,
          height: 1.25,
        ),
      ),
    );
    final hasFlag = FederationFlag.hasVisibleFlag(team.federation);
    final flag = hasFlag
        ? FederationFlag(
            federation: team.federation,
            width: 18,
            height: 12,
            borderRadius: BorderRadius.circular(2),
          )
        : null;
    return Row(
      mainAxisAlignment: end ? MainAxisAlignment.end : MainAxisAlignment.start,
      children: [
        if (!end && flag != null) ...[flag, const SizedBox(width: 6)],
        name,
        if (end && flag != null) ...[const SizedBox(width: 6), flag],
      ],
    );
  }
}

class _MatchNumber extends StatelessWidget {
  const _MatchNumber(this.number);

  final int number;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 26,
      child: Text(
        '$number',
        style: AppTypography.textXsMedium.copyWith(
          color: context.colors.textTertiary,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

class _ResultsMatchTile extends StatelessWidget {
  const _ResultsMatchTile({required this.number, required this.match});

  final int number;
  final NewsResultsMatch match;

  @override
  Widget build(BuildContext context) {
    final parts = match.score.split('-');
    final scoreA = parts.first;
    final scoreB = parts.length > 1 ? parts[1] : '';
    final labelA = newsScoreLabel(scoreA);
    final labelB = newsScoreLabel(scoreB);
    return _ExpandableMatch(
      semanticsLabel:
          'Match $number: ${match.teamA.name} $labelA, '
          '${match.teamB.name} $labelB. Boards',
      header: Row(
        children: [
          _MatchNumber(number),
          Expanded(child: _TeamName(team: match.teamA)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: labelA,
                    style: _scoreStyle(context, _outcome(scoreA, scoreB), 15),
                  ),
                  TextSpan(
                    text: '  –  ',
                    style: _scoreStyle(context, _Outcome.loss, 15),
                  ),
                  TextSpan(
                    text: labelB,
                    style: _scoreStyle(context, _outcome(scoreB, scoreA), 15),
                  ),
                ],
              ),
            ),
          ),
          Expanded(child: _TeamName(team: match.teamB, end: true)),
        ],
      ),
      body: (context) => Column(
        children: [for (final game in match.games) _ResultBoardRow(game: game)],
      ),
    );
  }
}

class _PairingsMatchTile extends StatelessWidget {
  const _PairingsMatchTile({required this.number, required this.match});

  final int number;
  final NewsPairingsMatch match;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return _ExpandableMatch(
      semanticsLabel:
          'Match $number: ${match.teamA.name} versus ${match.teamB.name}. '
          '${match.games.isEmpty ? 'Boards pending' : 'Boards'}',
      header: Row(
        children: [
          _MatchNumber(number),
          Expanded(child: _TeamName(team: match.teamA)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(
              'vs',
              style: AppTypography.textXsMedium.copyWith(
                color: colors.textTertiary,
              ),
            ),
          ),
          Expanded(child: _TeamName(team: match.teamB, end: true)),
        ],
      ),
      body: (context) => match.games.isEmpty
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text(
                'Boards pending',
                textAlign: TextAlign.center,
                style: AppTypography.textSmMedium.copyWith(
                  color: colors.textSecondary,
                ),
              ),
            )
          : Column(
              children: [
                for (final game in match.games) _PairingBoardRow(game: game),
              ],
            ),
    );
  }
}

String? _playerDetails(String? color, String? title, int? rating) {
  final parts = [
    if (color == 'w') 'White',
    if (color == 'b') 'Black',
    if (title != null && title.isNotEmpty) title,
    if (rating != null && rating > 0) '$rating',
  ];
  return parts.isEmpty ? null : parts.join(' · ');
}

String? _opposite(String color) => switch (color) {
  'w' => 'b',
  'b' => 'w',
  _ => null,
};

class _PlayerCell extends StatelessWidget {
  const _PlayerCell({
    required this.name,
    required this.details,
    this.end = false,
  });

  final String name;
  final String? details;
  final bool end;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final align = end ? TextAlign.right : TextAlign.left;
    return Column(
      crossAxisAlignment: end
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        Text(
          name,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: align,
          style: AppTypography.textSmMedium.copyWith(
            color: colors.textPrimary,
            height: 1.25,
          ),
        ),
        if (details != null) ...[
          const SizedBox(height: 2),
          Text(
            details!,
            textAlign: align,
            style: AppTypography.textXsRegular.copyWith(
              color: colors.textSecondary,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ],
    );
  }
}

class _BoardFrame extends StatelessWidget {
  const _BoardFrame({
    required this.board,
    required this.left,
    required this.middle,
    required this.right,
  });

  final int board;
  final Widget left;
  final Widget middle;
  final Widget right;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      container: true,
      label: 'Board $board',
      child: Padding(
        padding: const EdgeInsets.only(top: 8),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.surfaceRecessed,
            borderRadius: BorderRadius.circular(_radius),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: left),
                SizedBox(width: 76, child: middle),
                Expanded(child: right),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ResultBoardRow extends StatelessWidget {
  const _ResultBoardRow({required this.game});

  final NewsResultGame game;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final parts = game.result.split('-');
    final a = parts.first;
    final b = parts.length > 1 ? parts[1] : '';
    final notPlayed = game.status == NewsBoardStatus.notPlayed;
    final status = switch (game.status) {
      NewsBoardStatus.forfeit => 'Forfeit',
      NewsBoardStatus.notPlayed => 'Not played',
      NewsBoardStatus.played => null,
    };
    return _BoardFrame(
      board: game.board,
      left: _PlayerCell(
        name: game.playerA,
        details: _playerDetails(game.colorA, game.titleA, game.ratingA),
      ),
      middle: Column(
        children: [
          Text.rich(
            notPlayed
                ? TextSpan(
                    text: '–',
                    style: _scoreStyle(context, _Outcome.draw, 14),
                  )
                : TextSpan(
                    children: [
                      TextSpan(
                        text: newsScoreLabel(a),
                        style: _scoreStyle(context, _outcome(a, b), 14),
                      ),
                      TextSpan(
                        text: ' – ',
                        style: _scoreStyle(context, _Outcome.loss, 14),
                      ),
                      TextSpan(
                        text: newsScoreLabel(b),
                        style: _scoreStyle(context, _outcome(b, a), 14),
                      ),
                    ],
                  ),
            textAlign: TextAlign.center,
          ),
          if (status != null) ...[
            const SizedBox(height: 2),
            Text(
              status,
              textAlign: TextAlign.center,
              style: AppTypography.textXxsMedium.copyWith(
                color: colors.textSecondary,
              ),
            ),
          ],
        ],
      ),
      right: _PlayerCell(
        name: game.playerB,
        details: _playerDetails(
          _opposite(game.colorA),
          game.titleB,
          game.ratingB,
        ),
        end: true,
      ),
    );
  }
}

class _PairingBoardRow extends StatelessWidget {
  const _PairingBoardRow({required this.game});

  final NewsPairingGame game;

  @override
  Widget build(BuildContext context) {
    return _BoardFrame(
      board: game.board,
      left: _PlayerCell(
        name: game.playerA,
        details: _playerDetails(game.colorA, game.titleA, game.ratingA),
      ),
      middle: Text(
        'vs',
        textAlign: TextAlign.center,
        style: AppTypography.textXsMedium.copyWith(
          color: context.colors.textTertiary,
        ),
      ),
      right: _PlayerCell(
        name: game.playerB,
        details: _playerDetails(
          _opposite(game.colorA),
          game.titleB,
          game.ratingB,
        ),
        end: true,
      ),
    );
  }
}

class _TeamGroup extends StatelessWidget {
  const _TeamGroup({
    required this.title,
    required this.note,
    required this.teams,
  });

  final String title;
  final String? note;
  final List<NewsTeam> teams;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: AppTypography.textMdBold.copyWith(color: colors.textPrimary),
        ),
        if (note != null) ...[
          const SizedBox(height: 2),
          Text(
            note!,
            style: AppTypography.textXsRegular.copyWith(
              color: colors.textSecondary,
            ),
          ),
        ],
        const SizedBox(height: 8),
        for (final team in teams)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(
              children: [
                Expanded(child: _TeamName(team: team)),
                if (team.seed != null)
                  Text(
                    'Seed ${team.seed}',
                    style: AppTypography.textXsRegular.copyWith(
                      color: colors.textTertiary,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Dims a step while pressed; nothing moves.
class NewsPressable extends StatefulWidget {
  const NewsPressable({super.key, required this.onTap, required this.child});

  final VoidCallback onTap;
  final Widget child;

  @override
  State<NewsPressable> createState() => NewsPressableState();
}

class NewsPressableState extends State<NewsPressable> {
  bool _pressed = false;

  void _set(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _set(true),
      onTapCancel: () => _set(false),
      onTapUp: (_) => _set(false),
      onTap: widget.onTap,
      child: Opacity(opacity: _pressed ? 0.6 : 1, child: widget.child),
    );
  }
}
