import 'package:chessever2/providers/engine_settings_provider.dart';
import 'package:chessever2/screens/feed/providers/feed_provider.dart';
import 'package:chessever2/screens/feed/widgets/feed_action_row.dart';
import 'package:chessever2/screens/feed/widgets/feed_layout.dart';
import 'package:chessever2/screens/feed/widgets/feed_scrub.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// First-load placeholder: one skeleton post on the whole page, exactly as
/// Feed's pages stand, so the first board drops into the space the skeleton
/// board already occupies.
///
/// [puzzles] is for the Puzzle tab, whose boards always have the progress
/// rail beside them; Feed's game posts show the eval bar only when the
/// viewer's engine settings do.
class FeedSkeleton extends StatelessWidget {
  const FeedSkeleton({this.puzzles = false, super.key});

  final bool puzzles;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Loading Feed',
      child: ExcludeSemantics(child: FeedSkeletonPost(evalColumn: puzzles)),
    );
  }
}

/// One post's skeleton, on the exact [FeedLayout] geometry of a real post:
/// the header line, both player rows around the board, the move strip, the
/// actions and the scrub line at the foot.
///
/// The column left of the board is drawn only where the post it stands for
/// will have one: always with [evalColumn], otherwise when the viewer's
/// engine settings show the eval bar, as [FeedClip] decides it. So the
/// board lands where the skeleton board was, eval bar or not.
class FeedSkeletonPost extends ConsumerWidget {
  const FeedSkeletonPost({this.evalColumn = false, super.key});

  final bool evalColumn;

  /// The counter the skeleton keeps room for: a game's own counter is as
  /// wide as its widest ("14/14"), and in tabular figures every two-digit
  /// game's is this wide, so the track ends where the real one will.
  static const String counterWidest = '88/88';

  /// ... and the width it draws at rest, where a new post starts ("0/14").
  static const String counterAtRest = '0/88';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final tone = colors.skeleton;
    final toneDeep = colors.surface;
    final showBar =
        evalColumn ||
        (ref.watch(
              engineSettingsProviderNew.select(
                (s) => s.valueOrNull?.shouldShowEngineGaugeOnBoard ?? true,
              ),
            ) &&
            ref.watch(
              engineSettingsProviderNew.select(
                (s) => s.valueOrNull?.showEngineAnalysis ?? true,
              ),
            ));
    return LayoutBuilder(
      builder: (context, constraints) {
        final l = FeedLayout.resolve(
          constraints,
          MediaQuery.textScalerOf(context),
          evalWidth: showBar ? 20.w : 0,
        );
        Widget bar(double width, double height, {double radius = 3}) =>
            Container(
              width: width,
              height: height,
              decoration: BoxDecoration(
                color: tone,
                borderRadius: BorderRadius.circular(radius),
              ),
            );
        // The real rows keep the result's 20.w column before the flag
        // whether or not the eval bar shows (a finished game's score).
        Widget playerRow(double nameWidth) => SizedBox(
          height: l.rowHeight,
          child: Row(
            children: [
              SizedBox(width: 20.w + 5),
              bar(12, 10),
              const SizedBox(width: 8),
              bar(nameWidth, 10),
            ],
          ),
        );
        // The board column (eval bar, board, player rows) and the text rows
        // (header, move strip, actions) keep their own left edges, as in a
        // real post.
        Widget content(Widget child) => Padding(
          padding: EdgeInsets.only(left: l.contentLeft),
          child: SizedBox(width: l.contentWidth, child: child),
        );
        Widget fullRow(Widget child) => Padding(
          padding: const EdgeInsets.only(left: FeedLayout.sidePadding),
          child: SizedBox(width: l.rowWidth, child: child),
        );
        // Each action: the glyph over its word.
        Widget action() => Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              bar(20, 20, radius: 5),
              const SizedBox(height: 7),
              bar(34, 8),
            ],
          ),
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(height: l.top),
            fullRow(
              SizedBox(
                height: l.metaHeight,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: bar(180, 10),
                ),
              ),
            ),
            const SizedBox(height: FeedLayout.gap),
            content(playerRow(150)),
            const SizedBox(height: FeedLayout.gap),
            content(
              Row(
                children: [
                  if (showBar)
                    Container(
                      width: l.evalWidth,
                      height: l.board,
                      color: toneDeep,
                    ),
                  SizedBox.square(
                    key: const ValueKey('feed_skeleton_board'),
                    dimension: l.board,
                    child: CustomPaint(
                      painter: _SkeletonBoardPainter(
                        light: tone,
                        dark: toneDeep,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: FeedLayout.gap),
            content(playerRow(170)),
            SizedBox(height: l.infoSpace),
            fullRow(
              SizedBox(
                height: l.infoHeight,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: bar(72, 14),
                ),
              ),
            ),
            SizedBox(height: l.actionsSpace),
            fullRow(
              SizedBox(
                height: l.actionsHeight,
                // Analyze · My Space · Share · Save · Like.
                child: Row(children: [for (var i = 0; i < 5; i++) action()]),
              ),
            ),
            // [FeedLayout.scrubSpace], as on a post.
            const Spacer(),
            // The scrub line at rest, laid out on the real line's run
            // ([FeedScrubRun]): its track, round-capped, ending where the
            // real track ends, and the counter's digits where they stand.
            SizedBox(
              height: FeedLayout.scrubHeight,
              width: constraints.maxWidth,
              child: Builder(
                builder: (context) {
                  final run = FeedScrubRun.resolve(
                    context,
                    width: constraints.maxWidth,
                    inset: l.contentLeft,
                    counterWidest: counterWidest,
                  );
                  final digits = FeedScrubStrip.counterWidthOf(
                    context,
                    counterAtRest,
                  );
                  return Stack(
                    children: [
                      Positioned(
                        left: run.trackLeft,
                        width: run.trackRight - run.trackLeft,
                        top:
                            FeedLayout.scrubTrackCenter -
                            FeedLayout.scrubTrack / 2,
                        child: bar(
                          run.trackRight - run.trackLeft,
                          FeedLayout.scrubTrack,
                          radius: FeedLayout.scrubTrack / 2,
                        ),
                      ),
                      Positioned(
                        right: l.contentLeft,
                        width: digits,
                        top: FeedLayout.scrubTrackCenter - 5,
                        child: bar(digits, 10),
                      ),
                    ],
                  );
                },
              ),
            ),
            SizedBox(height: l.foot),
          ],
        );
      },
    );
  }
}

class _SkeletonBoardPainter extends CustomPainter {
  _SkeletonBoardPainter({required this.light, required this.dark});

  final Color light;
  final Color dark;

  @override
  void paint(Canvas canvas, Size size) {
    final sq = size.width / 8;
    final lightPaint = Paint()..color = light;
    final darkPaint = Paint()..color = dark;
    for (var r = 0; r < 8; r++) {
      for (var f = 0; f < 8; f++) {
        canvas.drawRect(
          Rect.fromLTWH(f * sq, r * sq, sq, sq),
          (r + f).isEven ? lightPaint : darkPaint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_SkeletonBoardPainter old) =>
      old.light != light || old.dark != dark;
}

/// The page after the last post: every post is a page of its own, and so
/// is this one.
///
/// * While more can load ([FeedMore.open]) it is the next post's skeleton on
///   the post's own geometry; when the post arrives it takes this place.
/// * When the feed has ended ([FeedMore.exhausted]) it is one quiet line and
///   one action, a refresh; when the last load failed ([FeedMore.stalled]),
///   one line and "Try again". Centred on the page.
class FeedTail extends StatelessWidget {
  const FeedTail({
    required this.more,
    required this.onFreshDraw,
    required this.onRetry,
    super.key,
  });

  final FeedMore more;
  final VoidCallback onFreshDraw;
  final VoidCallback onRetry;

  static const double _gap = 8;
  static const double _actionHeight = 44;

  @override
  Widget build(BuildContext context) {
    if (more == FeedMore.open) {
      return Semantics(
        label: 'Loading the next game',
        child: const ExcludeSemantics(child: FeedSkeletonPost()),
      );
    }
    final ended = more == FeedMore.exhausted;
    final line = ended ? 'No more games for now.' : "More games didn't load.";
    final actionLabel = ended ? 'Refresh' : 'Try again';
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: FeedLayout.sidePadding),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _FeedNoteLine(line, textAlign: TextAlign.center, maxLines: 2),
            const SizedBox(height: _gap),
            FeedPressable(
              key: ValueKey(ended ? 'feed_end_refresh' : 'feed_end_retry'),
              semanticsLabel: actionLabel,
              onTap: ended ? onFreshDraw : onRetry,
              child: _FeedNoteAction(label: actionLabel),
            ),
          ],
        ),
      ),
    );
  }
}

class _FeedNoteLine extends StatelessWidget {
  const _FeedNoteLine(
    this.text, {
    this.textAlign = TextAlign.start,
    this.maxLines = 1,
  });

  final String text;
  final TextAlign textAlign;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      key: const ValueKey('feed_end_line'),
      textAlign: textAlign,
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
      style: AppTypography.textSmRegular.copyWith(
        fontSize: 14,
        height: 20 / 14,
        color: context.colors.textSecondary,
      ),
    );
  }
}

/// A quiet 44pt action as wide as its label (plus its padding) wherever it
/// stands: in a row, a column or a page of its own, never a bar across the
/// screen.
class _FeedNoteAction extends StatelessWidget {
  const _FeedNoteAction({required this.label, this.style});

  final String label;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceRecessed,
        borderRadius: BorderRadius.circular(4),
      ),
      child: SizedBox(
        height: FeedTail._actionHeight,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          // Centred on the height, the label's own width across.
          child: Center(
            widthFactor: 1,
            child: Text(
              label,
              maxLines: 1,
              style:
                  (style ?? AppTypography.textSmMedium.copyWith(fontSize: 14))
                      .copyWith(height: 1.2, color: colors.textPrimary),
            ),
          ),
        ),
      ),
    );
  }
}

/// Calm full-page message for an empty feed or a failed load.
class FeedMessage extends StatelessWidget {
  const FeedMessage({
    required this.title,
    required this.body,
    required this.actionLabel,
    required this.onAction,
    super.key,
  });

  final String title;
  final String body;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              textAlign: TextAlign.center,
              style: AppTypography.textLgBold.copyWith(
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              body,
              textAlign: TextAlign.center,
              style: AppTypography.textSmRegular.copyWith(
                color: colors.textSecondary,
              ),
            ),
            const SizedBox(height: 20),
            FeedPressable(
              semanticsLabel: actionLabel,
              onTap: onAction,
              child: _FeedNoteAction(
                label: actionLabel,
                style: AppTypography.textSmMedium,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
