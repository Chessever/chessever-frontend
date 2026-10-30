import 'dart:async';
import 'dart:math' as math;

import 'package:chessever2/screens/feed/news/news_content.dart';
import 'package:chessever2/screens/feed/news/news_cover.dart';
import 'package:chessever2/screens/feed/news/news_models.dart';
import 'package:chessever2/screens/feed/news/news_reader_screen.dart';
import 'package:chessever2/screens/feed/news/news_repository.dart';
import 'package:chessever2/screens/feed/widgets/feed_action_row.dart';
import 'package:chessever2/screens/feed/widgets/feed_glyphs.dart';
import 'package:chessever2/screens/feed/feed_visibility.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:motor/motor.dart';

export 'package:chessever2/screens/feed/news/news_models.dart' show FeedNews;

/// Latest published news for the Feed, newest first.
///
/// Paints from the SQLite copy at once; a copy older than
/// [FeedNewsRepository.maxAge] is shown while the network refreshes it
/// behind, and the provider rebuilds only if the list actually changed
/// (unchanged items keep their instances, so Feed pages do not remount).
/// Never errors: a failed first fetch is an empty list, retried shortly.
///
/// Later refreshes run only while the Feed can be seen (its page open, the
/// app in the foreground): the provider outlives the Feed page, and a list
/// nobody is looking at is not worth the network. One that falls due while
/// the Feed is closed runs as soon as it is back.
final feedNewsProvider = FutureProvider<List<FeedNews>>((ref) async {
  final repository = ref.watch(feedNewsRepositoryProvider);
  final schedule = _FeedNewsRefreshSchedule(
    now: repository.now,
    onDue: ref.invalidateSelf,
  );
  ref.onDispose(schedule.dispose);
  ref.listen<bool>(
    feedScreenOpenProvider,
    (_, open) => schedule.feedTabSelected = open,
    fireImmediately: true,
  );

  final cached = await repository.readCached();
  if (cached != null) {
    if (repository.isFresh(cached)) {
      schedule.dueIn(repository.freshFor(cached));
      return cached.items;
    }
    unawaited(
      repository.refresh().then((fresh) {
        if (schedule.disposed) return;
        if (fresh == null) {
          schedule.dueIn(FeedNewsRepository.retryAfter);
        } else if (!identical(fresh.items, cached.items)) {
          ref.invalidateSelf();
        } else {
          schedule.dueIn(FeedNewsRepository.maxAge);
        }
      }),
    );
    return cached.items;
  }

  final fresh = await repository.refresh();
  if (fresh == null) {
    schedule.dueIn(FeedNewsRepository.retryAfter);
    return const [];
  }
  schedule.dueIn(FeedNewsRepository.maxAge);
  return fresh.items;
});

/// Fires [onDue] once a refresh falls due, but only while the Feed can be
/// seen: [feedTabSelected] and the app resumed. Hidden, nothing ticks; a
/// refresh that fell due meanwhile fires as soon as the Feed is back.
class _FeedNewsRefreshSchedule with WidgetsBindingObserver {
  _FeedNewsRefreshSchedule({required this.now, required this.onDue}) {
    final binding = WidgetsBinding.instance;
    final state = binding.lifecycleState;
    _foreground = state == null || state == AppLifecycleState.resumed;
    binding.addObserver(this);
  }

  final DateTime Function() now;
  final VoidCallback onDue;

  DateTime? _dueAt;
  Timer? _timer;
  bool _feedTab = false;
  late bool _foreground;
  bool _disposed = false;

  bool get disposed => _disposed;

  set feedTabSelected(bool value) {
    if (_feedTab == value) return;
    _feedTab = value;
    _arm();
  }

  /// Schedules the next refresh [delay] from now, replacing any earlier one.
  void dueIn(Duration delay) {
    if (_disposed) return;
    _dueAt = now().add(delay);
    _arm();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final foreground = state == AppLifecycleState.resumed;
    if (foreground == _foreground) return;
    _foreground = foreground;
    _arm();
  }

  void _arm() {
    _timer?.cancel();
    _timer = null;
    final dueAt = _dueAt;
    if (_disposed || dueAt == null || !_feedTab || !_foreground) return;
    // Measured against the clock each time: a Timer does not advance while
    // the app is suspended, the clock does.
    final left = dueAt.difference(now());
    _timer = Timer(left.isNegative ? Duration.zero : left, () {
      _timer = null;
      _dueAt = null;
      if (!_disposed) onDue();
    });
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _timer?.cancel();
    _timer = null;
    WidgetsBinding.instance.removeObserver(this);
  }
}

/// `September 23, 2026`, like the web's `formatNewsDate`.
String formatNewsDate(DateTime date) =>
    DateFormat('MMMM d, y').format(date.toLocal());

/// Whose article this is, and when: `ChessEver News · September 23, 2026`,
/// or for a partner its own mark before its name. The first thing on every
/// article, in the Feed and in the reader.
class NewsPublisherLine extends StatelessWidget {
  const NewsPublisherLine({
    super.key,
    required this.news,
    required this.style,
    this.maxLines,
  });

  final FeedNews news;
  final TextStyle style;
  final int? maxLines;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final publisher = news.publisher;
    final text = Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: publisher.name,
            style: TextStyle(
              color: colors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
          TextSpan(
            text: '  \u00b7  ${formatNewsDate(news.publishedAt)}',
            style: TextStyle(color: colors.textSecondary),
          ),
        ],
      ),
      maxLines: maxLines,
      overflow: maxLines == null ? null : TextOverflow.ellipsis,
      style: style,
    );
    final mark = publisher.mark;
    if (mark == null) return text;

    // The mark stands as tall as the line's capitals plus a little, centred
    // on the line box, so it reads as part of the words beside it.
    final scaler = MediaQuery.textScalerOf(context);
    final markHeight = scaler.scale(style.fontSize ?? 14) * 1.3;
    return Row(
      children: [
        Image.asset(
          mark,
          height: markHeight,
          width: markHeight * publisher.markAspectRatio,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.medium,
          excludeFromSemantics: true,
        ),
        SizedBox(width: markHeight * 0.45),
        Flexible(child: text),
      ],
    );
  }
}

/// One Feed page: a news article card that opens the in-app reader.
///
/// Full bleed: the cover sits at the top and dissolves into the Feed's dark
/// surface; the headline block is anchored to the bottom, where the thumb
/// is. When the page becomes the current one the cover settles into place.
class FeedNewsPage extends ConsumerStatefulWidget {
  const FeedNewsPage({
    super.key,
    required this.news,
    required this.isCurrent,
    required this.isVisible,
    required this.onRequestNext,
  });

  final FeedNews news;
  final bool isCurrent;
  final bool isVisible;
  final VoidCallback onRequestNext;

  static const double _gutter = 16;

  @override
  ConsumerState<FeedNewsPage> createState() => _FeedNewsPageState();
}

class _FeedNewsPageState extends ConsumerState<FeedNewsPage> {
  static const _gutter = FeedNewsPage._gutter;
  @override
  Widget build(BuildContext context) {
    final news = widget.news;
    final colors = context.colors;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final settled = reduceMotion || (widget.isCurrent && widget.isVisible);

    if (news.publisher.coverAspectRatio != null) {
      return GestureDetector(
        key: ValueKey('feed_news_${news.key}'),
        behavior: HitTestBehavior.opaque,
        onTap: () => NewsReaderScreen.open(context, news),
        child: _PartnerNewsLayout(
          news: news,
          settled: settled,
          reduceMotion: reduceMotion,
        ),
      );
    }

    return GestureDetector(
      key: ValueKey('feed_news_${news.key}'),
      behavior: HitTestBehavior.opaque,
      onTap: () => NewsReaderScreen.open(context, news),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final height = constraints.maxHeight;
          // Snapped to whole physical pixels: a fractional cover edge
          // rasterises as a grey seam through the meta line in light mode.
          final dpr = MediaQuery.devicePixelRatioOf(context);
          final coverHeight =
              (math.min(height * 0.66, width * 1.3) * dpr).floorToDouble() /
              dpr;
          final cover = SizedBox(
            height: coverHeight,
            child: reduceMotion
                ? NewsCover(
                    imageUrl: news.imageUrl,
                    fadeTop: 0.1,
                    fadeBottom: 0.5,
                  )
                : SingleMotionBuilder(
                    value: settled ? 1.0 : 1.05,
                    motion: const CupertinoMotion.smooth(
                      duration: Duration(milliseconds: 900),
                    ),
                    builder: (context, scale, _) => NewsCover(
                      imageUrl: news.imageUrl,
                      fadeTop: 0.1,
                      fadeBottom: 0.5,
                      scale: scale,
                    ),
                  ),
          );

          return Stack(
            children: [
              Positioned(top: 0, left: 0, right: 0, child: cover),
              Positioned.fill(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(_gutter, 0, _gutter, 22),
                  child: Align(
                    alignment: Alignment.bottomLeft,
                    // Scales the block down rather than cutting it on a
                    // screen too short for the headline and summary.
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.bottomLeft,
                      child: SizedBox(
                        width: math.max(0, width - 2 * _gutter),
                        child: _Headline(
                          news: news,
                          summaryLines: height < 520 ? 2 : 3,
                          shadowColor: colors.background,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Headline extends StatelessWidget {
  const _Headline({
    required this.news,
    required this.summaryLines,
    required this.shadowColor,
  });

  final FeedNews news;
  final int summaryLines;
  final Color shadowColor;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    // Tight, surface-tinted: keeps type crisp where it overlaps the fade.
    final shadows = [
      Shadow(
        color: shadowColor.withValues(alpha: 0.85),
        blurRadius: 10,
        offset: const Offset(0, 1),
      ),
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        NewsPublisherLine(
          news: news,
          maxLines: 1,
          style: AppTypography.textSmMedium.copyWith(
            fontSize: 13,
            height: 18 / 13,
            shadows: shadows,
          ),
        ),
        const SizedBox(height: 10),
        Semantics(
          header: true,
          child: NewsFittedTitle(
            title: news.title,
            style: AppTypography.displaySmBold.copyWith(
              color: colors.textPrimary,
              letterSpacing: -0.2,
              shadows: shadows,
            ),
            sizes: const [30, 28, 26, 24, 22, 20],
            lineHeight: 1.14,
            // A headline is one or two lines, never a stacked staircase.
            maxLines: 2,
          ),
        ),
        if (news.summary.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(
            news.summary,
            maxLines: summaryLines,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.textMdRegular.copyWith(
              fontSize: 15,
              height: 22 / 15,
              color: colors.textPrimaryMuted,
              shadows: shadows,
            ),
          ),
        ],
        const SizedBox(height: 18),
        _NewsActions(news: news),
      ],
    );
  }
}

/// Read and Share, at the foot of every article page.
class _NewsActions extends StatelessWidget {
  const _NewsActions({required this.news});

  final FeedNews news;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      children: [
        _ReadButton(onTap: () => NewsReaderScreen.open(context, news)),
        const SizedBox(width: 6),
        Builder(
          builder: (buttonContext) => Semantics(
            button: true,
            label: 'Share article',
            excludeSemantics: true,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => shareNews(buttonContext, news),
              child: SizedBox.square(
                dimension: 44,
                child: Center(
                  child: FeedGlyph(
                    FeedGlyphs.share,
                    width: 22,
                    height: 22,
                    color: colors.textPrimary,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// A partner's article as a Feed page.
///
/// Partners' covers are small and wide (RookReview's are 675x300), so the
/// page does not stretch one over the screen, which would blow it up five
/// times and crop people out of it. The cover runs edge to edge at its own
/// shape, feathered into the Feed's surface like ChessEver's; the partner's
/// mark, the headline and the article's opening words follow, the words
/// filling whatever height the screen has and fading where they run out of
/// room. Read and Share sit at the foot, where they sit on every article.
class _PartnerNewsLayout extends StatelessWidget {
  const _PartnerNewsLayout({
    required this.news,
    required this.settled,
    required this.reduceMotion,
  });

  final FeedNews news;
  final bool settled;
  final bool reduceMotion;

  static const double _gutter = FeedNewsPage._gutter;

  /// Where the words start, as a share of the cover's height: on its
  /// feathered foot, the way ChessEver's headlines rise out of theirs.
  static const double _textStart = 0.84;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final shadows = [
      Shadow(
        color: colors.background.withValues(alpha: 0.85),
        blurRadius: 10,
        offset: const Offset(0, 1),
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;
        final hasCover = news.imageUrl != null;
        final dpr = MediaQuery.devicePixelRatioOf(context);
        final coverHeight = hasCover
            ? (math.min(
                            width / news.publisher.coverAspectRatio!,
                            height * 0.42,
                          ) *
                          dpr)
                      .floorToDouble() /
                  dpr
            : 0.0;
        const quiet = SizedBox.shrink();
        final cover = reduceMotion
            ? NewsCover(
                imageUrl: news.imageUrl,
                fadeTop: 0.12,
                fadeBottom: 0.4,
                fallback: quiet,
              )
            : SingleMotionBuilder(
                value: settled ? 1.0 : 1.05,
                motion: const CupertinoMotion.smooth(
                  duration: Duration(milliseconds: 900),
                ),
                builder: (context, scale, _) => NewsCover(
                  imageUrl: news.imageUrl,
                  fadeTop: 0.12,
                  fadeBottom: 0.4,
                  fallback: quiet,
                  scale: scale,
                ),
              );

        return Stack(
          children: [
            if (hasCover)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: coverHeight,
                child: cover,
              ),
            Positioned(
              top: hasCover ? coverHeight * _textStart : 24,
              left: _gutter,
              right: _gutter,
              bottom: 22,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  NewsPublisherLine(
                    news: news,
                    maxLines: 1,
                    style: AppTypography.textSmMedium.copyWith(
                      fontSize: 13,
                      height: 18 / 13,
                      shadows: shadows,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Semantics(
                    header: true,
                    child: NewsFittedTitle(
                      title: news.title,
                      style: AppTypography.displaySmBold.copyWith(
                        color: colors.textPrimary,
                        letterSpacing: -0.2,
                        shadows: shadows,
                      ),
                      sizes: const [28, 26, 24, 22, 20],
                      lineHeight: 1.16,
                      maxLines: 2,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Expanded(child: _PartnerExcerpt(news: news)),
                  const SizedBox(height: 18),
                  _NewsActions(news: news),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// The partner article's opening words, as many whole lines as the space
/// holds. When the article goes on, the last line fades out (the Read button
/// is right below); a gap of under two lines shows nothing at all.
class _PartnerExcerpt extends StatelessWidget {
  const _PartnerExcerpt({required this.news});

  final FeedNews news;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final paragraphs = [
      if (news.summary.isNotEmpty &&
          !newsSummaryRepeatsBody(news.summary, news.content))
        news.summary,
      ...newsPlainParagraphs(news.content).take(8),
    ];
    if (paragraphs.isEmpty) return const SizedBox.shrink();
    final style = AppTypography.textMdRegular.copyWith(
      fontSize: 15,
      height: 22 / 15,
      color: colors.textPrimaryMuted,
    );
    final line = MediaQuery.textScalerOf(context).scale(15) * (22 / 15);
    return LayoutBuilder(
      builder: (context, constraints) {
        final lines = ((constraints.maxHeight + 0.5) / line).floor();
        if (lines < 2) return const SizedBox.shrink();
        return Align(
          alignment: Alignment.topLeft,
          child: Text(
            paragraphs.join('\n\n'),
            maxLines: lines,
            overflow: TextOverflow.fade,
            style: style,
          ),
        );
      },
    );
  }
}

/// A headline that steps its size down until it fits [maxLines], so a long
/// title shrinks instead of being cut; only at the smallest size does it
/// fall back to an ellipsis.
class NewsFittedTitle extends StatelessWidget {
  const NewsFittedTitle({
    super.key,
    required this.title,
    required this.style,
    required this.sizes,
    required this.lineHeight,
    required this.maxLines,
  });

  final String title;
  final TextStyle style;

  /// Candidate font sizes, largest first.
  final List<double> sizes;
  final double lineHeight;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        var chosen = style.copyWith(fontSize: sizes.last, height: lineHeight);
        for (final size in sizes) {
          final candidate = style.copyWith(fontSize: size, height: lineHeight);
          final painter = TextPainter(
            text: TextSpan(text: title, style: candidate),
            maxLines: maxLines,
            textDirection: direction,
            textScaler: scaler,
          )..layout(maxWidth: constraints.maxWidth);
          final fits = !painter.didExceedMaxLines;
          painter.dispose();
          if (fits) {
            chosen = candidate;
            break;
          }
        }
        return Text(
          title,
          maxLines: maxLines,
          overflow: TextOverflow.ellipsis,
          style: chosen,
        );
      },
    );
  }
}

/// "Read": the article's one action. Its press is [FeedPressable]'s, the one
/// every Feed button shares: it gives a little and dims, on a spring.
class _ReadButton extends StatelessWidget {
  const _ReadButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return FeedPressable(
      semanticsLabel: 'Read',
      semanticsHint: 'Open the article',
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44, minWidth: 96),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.textPrimary,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 11),
            child: Center(
              widthFactor: 1,
              heightFactor: 1,
              child: Text(
                'Read',
                style: AppTypography.textMdBold.copyWith(
                  fontSize: 15,
                  height: 20 / 15,
                  color: colors.textInverse,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
