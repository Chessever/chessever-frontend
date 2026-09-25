import 'dart:math' as math;

import 'package:chessever2/screens/feed/models/feed_models.dart';
import 'package:chessever2/screens/feed/widgets/feed_classification.dart';
import 'package:chessever2/screens/feed/widgets/feed_format.dart';
import 'package:chessever2/screens/feed/widgets/feed_layout.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:motor/motor.dart';

const List<FontFeature> _tabular = [FontFeature.tabularFigures()];

/// [style] resolved exactly as a [Text] in [context] resolves it: over the
/// ambient [DefaultTextStyle] (the theme's letter spacing among it) and in
/// bold when the platform asks for bold text. A label measured with this is
/// as wide as it is drawn, so a box sized to it never clips it.
TextStyle _asDrawn(BuildContext context, TextStyle style) {
  var resolved = DefaultTextStyle.of(context).style.merge(style);
  if (MediaQuery.boldTextOf(context)) {
    resolved = resolved.merge(const TextStyle(fontWeight: FontWeight.bold));
  }
  return resolved;
}

/// Where the scrub line's parts sit across a post: the track's two ends,
/// and the run the thumb's centre travels between them ([FeedScrubStrip]
/// keeps it [FeedScrubStrip.thumbInset] inside each end).
///
/// The strip lays itself out on it, and the report chart lays its x axis on
/// the same run ([FeedReportOverlay]), so the chart's cursor always stands
/// over the thumb the finger is driving.
@immutable
class FeedScrubRun {
  const FeedScrubRun({required this.trackLeft, required this.trackRight});

  /// The run on a row [width] wide: the track starts [inset] in and stops
  /// [FeedScrubStrip.counterGap] short of a counter wide enough for
  /// [counterWidest], which ends [inset] from the right edge.
  factory FeedScrubRun.resolve(
    BuildContext context, {
    required double width,
    required double inset,
    String? counterWidest,
  }) {
    final counter = counterWidest == null
        ? 0.0
        : FeedScrubStrip.counterWidthOf(context, counterWidest) +
              FeedScrubStrip.counterGap;
    return FeedScrubRun(
      trackLeft: inset,
      trackRight: math.max(
        inset + FeedScrubStrip.restThumb + 1,
        width - inset - counter,
      ),
    );
  }

  final double trackLeft;
  final double trackRight;

  /// The thumb's centre at the first and at the last move.
  double get runLeft => trackLeft + FeedScrubStrip.thumbInset;
  double get runRight =>
      math.max(runLeft + 1, trackRight - FeedScrubStrip.thumbInset);

  /// The thumb's centre at [progress] (0..1 along the game).
  double xAt(double progress) =>
      runLeft + (runRight - runLeft) * progress.clamp(0.0, 1.0);

  /// The share of the game under a finger at [x]: the thumb lands right
  /// under it.
  double fractionAt(double x) =>
      ((x - runLeft) / (runRight - runLeft)).clamp(0.0, 1.0);
}

/// The scrub line's colours in one theme.
///
/// The played part and the thumb are the page's ink. The rest of the track
/// is a step of that ink laid over the page, the lightest step that still
/// stands 3:1 off the page (the bar a control's parts must clear), so the
/// whole line reads at a glance in light and dark while the played part
/// stays clearly apart from it.
@immutable
class FeedScrubColors {
  const FeedScrubColors({
    required this.played,
    required this.track,
    required this.counter,
    required this.counterHeld,
  });

  factory FeedScrubColors.of(AppColors colors) => FeedScrubColors(
    played: colors.textPrimary,
    track: trackOn(colors.textPrimary, colors.background),
    counter: colors.textSecondary,
    counterHeld: colors.textPrimary,
  );

  /// The played part and the thumb.
  final Color played;

  /// The rest of the track.
  final Color track;

  /// The counter at rest, and under a finger (it comes up to full ink).
  final Color counter;
  final Color counterHeld;

  /// Contrast the unplayed track keeps against the page.
  static const double trackContrast = 3.2;

  static final Map<(Color, Color), Color> _tracks = {};

  /// The opaque step of [ink] over [page] the track is drawn in.
  static Color trackOn(Color ink, Color page) {
    // A theme change lerps the colours for a few frames; keep only a few.
    if (_tracks.length > 8) _tracks.clear();
    return _tracks.putIfAbsent((ink, page), () {
      var color = page;
      for (var a = 0.3; a <= 0.8; a += 0.02) {
        color = Color.alphaBlend(ink.withValues(alpha: a), page);
        if (feedContrast(color, page) >= trackContrast) break;
      }
      return color;
    });
  }
}

/// The game's timeline along the bottom of a post: a track the game fills
/// as it plays, with a thumb on the move shown and a counter ("12/31") at
/// its end. It is the way to move through the game.
///
/// * **Always there.** At rest the track, its played part and the thumb are
///   drawn in the page's ink ([FeedScrubColors]): the played part and the
///   thumb in full ink, the rest a step of it that still clears 3:1 against
///   the page, so the line reads in light and dark alike.
/// * **Easy to take.** The whole row, a full [FeedLayout.scrubHeight] tall
///   and as wide as the page, is the target. A finger down anywhere on it
///   thickens the track at once (and the thumb, when it is the thumb that
///   was touched). Anywhere on the line, a finger that moves sideways past
///   the platform's touch slop (the same slop the Feed's pages use, so a
///   swipe steeper than 45° pages the feed on every platform, however slow)
///   scrubs from right under it, and a tap on the track jumps to that move.
///   A finger resting on the thumb takes it ([FeedScrubStrip.holdToGrab])
///   the way a slider's thumb is taken, and the thumb then moves with the
///   finger from where it stood: nothing jumps. A resting finger anywhere
///   else is not a grab, so a slow or paused swipe up from the line still
///   pages and the game keeps its move. A scrub that has started owns the
///   pointer until release. The counter is a readout: a tap on it does
///   nothing.
/// * **Says where you are.** The counter follows the move shown, live while
///   scrubbing (in full ink under the finger), and [bubble] (the move) rides
///   above the thumb.
///
/// At rest the thumb travels inside the track's ends, flush with them at the
/// first and last move, so it never hangs past the board column's edge or
/// towards the counter ([FeedScrubRun]). Where the scrub lets go, the game
/// plays on from there, as a tap does.
class FeedScrubStrip extends StatefulWidget {
  const FeedScrubStrip({
    required this.progress,
    required this.scrubbing,
    required this.onStart,
    required this.onUpdate,
    required this.onEnd,
    this.onSeek,
    this.onStep,
    this.inset = FeedLayout.sidePadding,
    this.semanticsValue,
    this.semanticsIncreased,
    this.semanticsDecreased,
    this.counter,
    this.counterWidest,
    this.bubble,
    super.key,
  });

  /// 0..1 along the game.
  final double progress;
  final bool scrubbing;
  final ValueChanged<double> onStart;
  final ValueChanged<double> onUpdate;
  final VoidCallback onEnd;

  /// A tap on the row, at this fraction of the track.
  final ValueChanged<double>? onSeek;

  /// A screen reader's step: +1 for the next move, -1 for the previous.
  final ValueChanged<int>? onStep;
  final String? semanticsValue;

  /// What [semanticsValue] becomes after a step forward / back.
  final String? semanticsIncreased;
  final String? semanticsDecreased;

  /// Horizontal inset of the track and counter; they line up with the board
  /// column.
  final double inset;

  /// "12/31": the move shown over the game's moves.
  final String? counter;

  /// The widest [counter] this game can show ("31/31"), so the track keeps
  /// its length as the number changes.
  final String? counterWidest;

  /// Shown above the thumb while scrubbing (the move there), kept inside the
  /// row's insets.
  final Widget? bubble;

  static const double restThumb = 16;
  static const double heldThumb = 24;
  static const double heldTrack = 8;

  /// The clear space between the thumb and the track either side of it.
  static const double gap = 3;

  /// Between the track's end and the counter: the held thumb, which hangs
  /// past the track's end by its growth, still clears the digits.
  static const double counterGap = 14;

  /// How far in from each end of the track the thumb's centre stops: the
  /// resting thumb sits flush with the track's round ends.
  static const double thumbInset = restThumb / 2;

  /// The bubble's foot above the track's centre line: clear of the held
  /// thumb.
  static const double bubbleLift = heldThumb / 2 + 8;

  /// A finger resting on the thumb this long takes it, with no sideways
  /// travel. Short enough to read as immediate; long enough that a swipe,
  /// which moves off at once, is still the pages' (the same wait iOS gives
  /// a scroll view before its content takes a touch). Only the thumb is
  /// taken this way: elsewhere on the line a resting finger stays free to
  /// page the feed.
  static const Duration holdToGrab = Duration(milliseconds: 150);

  /// How far either side of the thumb's centre a finger still lands on the
  /// thumb: the held thumb's full width, a 48pt target.
  static const double thumbReach = heldThumb;

  /// The counter's type, resolved exactly as it is drawn.
  static TextStyle counterStyle(BuildContext context) => _asDrawn(
    context,
    AppTypography.textXsBold.copyWith(
      fontSize: 13,
      height: 16 / 13,
      fontWeight: FontWeight.w600,
      fontFeatures: _tabular,
    ),
  );

  /// The width [text] takes as the counter in [context].
  static double counterWidthOf(BuildContext context, String text) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: counterStyle(context)),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final width = painter.width.ceilToDouble();
    painter.dispose();
    return width;
  }

  @override
  State<FeedScrubStrip> createState() => _FeedScrubStripState();
}

class _FeedScrubStripState extends State<FeedScrubStrip> {
  /// A finger is down on the row (not yet known to be a scrub, a tap or a
  /// page swipe): the track thickens at once to say it was felt.
  bool _pressed = false;

  /// ... and it landed on the thumb, which grows under it. A finger down
  /// elsewhere on the line leaves the thumb be until the scrub brings it
  /// under the finger, so nothing swells away from where the finger is.
  bool _onThumb = false;
  Offset? _downAt;

  /// While a scrub that took the thumb runs: how far the thumb stood from
  /// the finger when it came down, kept as the finger moves, so the thumb
  /// moves with the finger from where it was. 0 for a scrub started
  /// elsewhere on the line, which brings the thumb to the finger.
  double _grip = 0;

  /// The line's geometry, from the last layout.
  FeedScrubRun _run = const FeedScrubRun(trackLeft: 0, trackRight: 1);

  /// The slop the platform gives a touch, the one the Feed's pages page on.
  double _slop() =>
      MediaQuery.maybeGestureSettingsOf(context)?.touchSlop ?? kTouchSlop;

  /// Whether a finger at [local] lands on the thumb.
  bool _isOnThumb(Offset local) =>
      (local.dx - _run.xAt(widget.progress)).abs() <= FeedScrubStrip.thumbReach;

  void _onPointerDown(PointerDownEvent event) {
    _downAt = event.localPosition;
    final onThumb = _isOnThumb(event.localPosition);
    if (!mounted) return;
    setState(() {
      _pressed = true;
      _onThumb = onThumb;
    });
  }

  /// The share of the game the thumb stands at for a finger at [x].
  double _fractionFor(double x) => _run.fractionAt(x + _grip);

  /// A scrub starts with the finger at [x].
  void _begin(double x) {
    final down = _downAt;
    _grip = _onThumb && down != null ? _run.xAt(widget.progress) - down.dx : 0;
    widget.onStart(_fractionFor(x));
  }

  /// A tap at [x]: the move there, on the track. The counter past the
  /// track's end is a readout, not the last move.
  void _seek(double x) {
    if (x > _run.trackRight + FeedScrubStrip.counterGap / 2) return;
    widget.onSeek?.call(_run.fractionAt(x));
  }

  void _release() {
    _downAt = null;
    if ((_pressed || _onThumb) && mounted) {
      setState(() {
        _pressed = false;
        _onThumb = false;
      });
    }
  }

  void _onPointerMove(PointerMoveEvent event) {
    final down = _downAt;
    if (down == null || widget.scrubbing || !_pressed) return;
    final d = event.localPosition - down;
    // The pages took it: a vertical swipe is not a hold on the line.
    if (d.dy.abs() > _slop() && d.dy.abs() > d.dx.abs()) _release();
  }

  @override
  Widget build(BuildContext context) {
    final palette = FeedScrubColors.of(context.colors);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    // The pages' own slop, so a steep swipe from the line is theirs and a
    // flat one is the scrub's, split at 45° on every platform.
    final gestureSettings = MediaQuery.maybeGestureSettingsOf(context);
    final counter = widget.counter;
    final style = FeedScrubStrip.counterStyle(context);
    final onStep = widget.onStep;
    final value = widget.semanticsValue;
    final canStep = onStep != null && value != null;

    return Semantics(
      label: 'Move through the game',
      value: value,
      slider: true,
      increasedValue: canStep ? widget.semanticsIncreased ?? value : null,
      decreasedValue: canStep ? widget.semanticsDecreased ?? value : null,
      onIncrease: canStep ? () => onStep(1) : null,
      onDecrease: canStep ? () => onStep(-1) : null,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final widest = counter == null
              ? null
              : widget.counterWidest ?? counter;
          final run = _run = FeedScrubRun.resolve(
            context,
            width: width,
            inset: widget.inset,
            counterWidest: widest,
          );
          final counterWidth = widest == null
              ? 0.0
              : FeedScrubStrip.counterWidthOf(context, widest);

          return Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: _onPointerDown,
            onPointerMove: _onPointerMove,
            onPointerUp: (_) => _release(),
            onPointerCancel: (_) => _release(),
            child: RawGestureDetector(
              behavior: HitTestBehavior.opaque,
              // The synthesized scroll actions would report a zero position
              // and jump the game to its start; the slider's own actions
              // step a move at a time instead.
              excludeFromSemantics: true,
              gestures: {
                // First, so a touch that neither drags, rests nor swipes is
                // a tap.
                if (widget.onSeek != null)
                  TapGestureRecognizer:
                      GestureRecognizerFactoryWithHandlers<
                        TapGestureRecognizer
                      >(
                        () => TapGestureRecognizer(debugOwner: this),
                        (recognizer) => recognizer.onTapUp = ((d) =>
                            _seek(d.localPosition.dx)),
                      ),
                HorizontalDragGestureRecognizer:
                    GestureRecognizerFactoryWithHandlers<
                      HorizontalDragGestureRecognizer
                    >(
                      () => HorizontalDragGestureRecognizer(debugOwner: this),
                      (recognizer) => recognizer
                        // Winning the arena by default (no competitor) must
                        // not start a scrub on touch-down: wait for the slop.
                        ..onlyAcceptDragOnThreshold = true
                        ..gestureSettings = gestureSettings
                        // Start where the finger is once the slop is past,
                        // not where it first landed.
                        ..dragStartBehavior = DragStartBehavior.start
                        // Parenthesised: an unwrapped arrow body swallows the
                        // following cascade sections.
                        ..onStart = ((d) => _begin(d.localPosition.dx))
                        ..onUpdate = ((d) => widget.onUpdate(
                          _fractionFor(d.localPosition.dx),
                        ))
                        ..onEnd = ((_) => widget.onEnd())
                        ..onCancel = (() {
                          if (widget.scrubbing) widget.onEnd();
                        }),
                    ),
                // A finger that rests on the thumb takes it and owns the
                // pointer from then on, whichever way it moves. Anywhere
                // else a resting finger is not watched at all.
                _ThumbHoldRecognizer:
                    GestureRecognizerFactoryWithHandlers<_ThumbHoldRecognizer>(
                      () => _ThumbHoldRecognizer(
                        onThumb: _isOnThumb,
                        duration: FeedScrubStrip.holdToGrab,
                        debugOwner: this,
                      ),
                      (recognizer) => recognizer
                        ..gestureSettings = gestureSettings
                        ..onLongPressStart = ((d) =>
                            _begin(d.localPosition.dx))
                        ..onLongPressMoveUpdate = ((d) => widget.onUpdate(
                          _fractionFor(d.localPosition.dx),
                        ))
                        ..onLongPressEnd = ((_) => widget.onEnd())
                        // Only a pointer cancelled mid-scrub lands here with
                        // a scrub to end.
                        ..onLongPressCancel = (() {
                          if (widget.scrubbing) widget.onEnd();
                        }),
                    ),
              },
              child: SizedBox(
                height: FeedLayout.scrubHeight,
                width: width,
                child: SingleMotionBuilder(
                  value: _pressed || widget.scrubbing ? 1 : 0,
                  active: !reduceMotion,
                  motion: const CupertinoMotion.snappy(),
                  builder: (context, felt, _) {
                    return SingleMotionBuilder(
                      value: (_pressed && _onThumb) || widget.scrubbing ? 1 : 0,
                      active: !reduceMotion,
                      motion: const CupertinoMotion.snappy(),
                      builder: (context, taken, _) {
                        return SingleMotionBuilder(
                          value: widget.progress.clamp(0.0, 1.0),
                          // The fill follows a finger exactly; it glides
                          // only as the game plays.
                          active: !widget.scrubbing && !reduceMotion,
                          motion: const CupertinoMotion.smooth(),
                          builder: (context, p, _) {
                            final t = felt.clamp(0.0, 1.0);
                            final grow = taken.clamp(0.0, 1.0);
                            final thumbX = run.xAt(p);
                            return Stack(
                              clipBehavior: Clip.none,
                              children: [
                                Positioned.fill(
                                  child: CustomPaint(
                                    painter: _ScrubPainter(
                                      left: run.trackLeft,
                                      right: run.trackRight,
                                      thumbX: thumbX,
                                      track:
                                          FeedLayout.scrubTrack +
                                          (FeedScrubStrip.heldTrack -
                                                  FeedLayout.scrubTrack) *
                                              t,
                                      thumb:
                                          FeedScrubStrip.restThumb +
                                          (FeedScrubStrip.heldThumb -
                                                  FeedScrubStrip.restThumb) *
                                              grow,
                                      palette: palette,
                                    ),
                                  ),
                                ),
                                if (counter != null)
                                  Positioned(
                                    right: widget.inset,
                                    // Centred on the track's line, whatever
                                    // height the text scale gives it.
                                    top: FeedLayout.scrubTrackCenter - 20,
                                    height: 40,
                                    width: counterWidth,
                                    child: Align(
                                      alignment: Alignment.centerRight,
                                      child: ExcludeSemantics(
                                        child: Text(
                                          counter,
                                          key: const ValueKey(
                                            'feed_scrub_counter',
                                          ),
                                          maxLines: 1,
                                          softWrap: false,
                                          style: style.copyWith(
                                            color: Color.lerp(
                                              palette.counter,
                                              palette.counterHeld,
                                              t,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                if (widget.bubble case final bubble?
                                    when widget.scrubbing)
                                  Positioned(
                                    left: 0,
                                    right: 0,
                                    bottom:
                                        FeedLayout.scrubHeight -
                                        FeedLayout.scrubTrackCenter +
                                        FeedScrubStrip.bubbleLift,
                                    height: 64,
                                    child: IgnorePointer(
                                      child: CustomSingleChildLayout(
                                        delegate: _BubbleLayout(
                                          x: thumbX,
                                          min: widget.inset,
                                          max: width - widget.inset,
                                        ),
                                        child: bubble,
                                      ),
                                    ),
                                  ),
                              ],
                            );
                          },
                        );
                      },
                    );
                  },
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// The hold that takes the thumb: it watches only a finger that comes down
/// on the thumb ([onThumb]), so a finger resting anywhere else on the line
/// is left to the tap, the sideways drag and the pages.
class _ThumbHoldRecognizer extends LongPressGestureRecognizer {
  _ThumbHoldRecognizer({
    required this.onThumb,
    super.duration,
    super.debugOwner,
  });

  final bool Function(Offset local) onThumb;

  @override
  bool isPointerAllowed(PointerDownEvent event) =>
      onThumb(event.localPosition) && super.isPointerAllowed(event);
}

/// The track, its played part and the thumb, all centred on the track's
/// line ([FeedLayout.scrubTrackCenter]).
///
/// The played part runs in under the thumb, so the two read as one filled
/// stroke ending in the knob (never a loose bead beside it near the start).
/// The rest of the track starts [FeedScrubStrip.gap] clear of the thumb
/// with a round cap of its own. Every end is a half-circle of the track's
/// thickness at every thickness; a part shorter than that thickness shrinks
/// to a dot rather than being cut into a sliver, so nothing squares off or
/// slices as the thumb nears an end.
class _ScrubPainter extends CustomPainter {
  _ScrubPainter({
    required this.left,
    required this.right,
    required this.thumbX,
    required this.track,
    required this.thumb,
    required this.palette,
  });

  final double left;
  final double right;
  final double thumbX;
  final double track;
  final double thumb;
  final FeedScrubColors palette;

  void _segment(Canvas canvas, double from, double to, Color color) {
    final length = to - from;
    if (length <= 0.5) return;
    final h = math.min(track, length);
    const cy = FeedLayout.scrubTrackCenter;
    canvas.drawRRect(
      RRect.fromLTRBR(from, cy - h / 2, to, cy + h / 2, Radius.circular(h / 2)),
      Paint()..color = color,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    _segment(canvas, left, math.min(right, thumbX), palette.played);
    _segment(
      canvas,
      math.max(left, thumbX + thumb / 2 + FeedScrubStrip.gap),
      right,
      palette.track,
    );
    canvas.drawCircle(
      Offset(thumbX, FeedLayout.scrubTrackCenter),
      thumb / 2,
      Paint()..color = palette.played,
    );
  }

  @override
  bool shouldRepaint(_ScrubPainter old) =>
      old.left != left ||
      old.right != right ||
      old.thumbX != thumbX ||
      old.track != track ||
      old.thumb != thumb ||
      old.palette.played != palette.played ||
      old.palette.track != palette.track;
}

/// Centres the bubble over the thumb, kept between [min] and [max] by its
/// real width, its foot on the box's bottom edge.
class _BubbleLayout extends SingleChildLayoutDelegate {
  _BubbleLayout({required this.x, required this.min, required this.max});

  final double x;
  final double min;
  final double max;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      constraints.loosen();

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final left = (x - childSize.width / 2)
        .clamp(min, math.max(min, max - childSize.width))
        .toDouble();
    return Offset(left, size.height - childSize.height);
  }

  @override
  bool shouldRelayout(_BubbleLayout old) =>
      old.x != x || old.min != min || old.max != max;
}

/// Report chart that rises over the lower half of a clip while scrubbing a
/// game that has evals: the eval curve, the error dots and a cursor on the
/// scrubbed ply, under one line that says the move, its class and the eval.
///
/// It stands right over the scrub track ([run]) and lays its x axis on the
/// thumb's run, so the cursor is always straight above the thumb the finger
/// drives. Each fact is said once: the move and its eval here, where it
/// sits in the game in the counter under it.
class FeedReportOverlay extends StatelessWidget {
  const FeedReportOverlay({
    required this.item,
    required this.ply,
    required this.run,
    super.key,
  });

  final FeedItem item;
  final int ply;

  /// The post's scrub line, in this overlay's own coordinates (both span
  /// the post's full width).
  final FeedScrubRun run;

  static const double chartHeight = 75;

  /// The move line over the chart: its 18/24 label's line at [scaler]'s
  /// size, never less than 24pt. A fixed 24pt box shaved the label's
  /// descenders at large text, so "Ng5" read "Na5".
  static double infoHeightFor(TextScaler scaler) =>
      math.max(24.0, scaler.scale(18) * 24 / 18).ceilToDouble();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final bg = colors.background;
    final chartWidth = run.trackRight - run.trackLeft;
    final infoHeight = infoHeightFor(MediaQuery.textScalerOf(context));

    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [
              bg.withValues(alpha: 0.98),
              bg.withValues(alpha: 0.96),
              bg.withValues(alpha: 0.7),
              bg.withValues(alpha: 0.25),
              bg.withValues(alpha: 0),
            ],
            stops: const [0, 0.58, 0.78, 0.92, 1],
          ),
        ),
        child: Align(
          alignment: Alignment.bottomLeft,
          child: Padding(
            padding: EdgeInsets.only(left: run.trackLeft),
            child: SizedBox(
              key: const ValueKey('feed_report_chart'),
              width: chartWidth,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FeedMoveInfoRow(
                    item: item,
                    ply: ply,
                    trailing: feedEvalText(item, ply),
                    height: infoHeight,
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: chartWidth,
                    height: chartHeight,
                    child: CustomPaint(
                      painter: _ReportChartPainter(
                        item: item,
                        ply: ply,
                        // The thumb's centre stops this far inside the
                        // track's ends; so does the curve.
                        inset: run.runLeft - run.trackLeft,
                        surface: colors.surfaceRecessed,
                        grid: colors.divider,
                        ink: colors.textPrimary,
                        // The text accent, not raw brand cyan: the cursor
                        // must clear 3:1 on the light chart.
                        cursor: colors.accentText,
                      ),
                    ),
                  ),
                  const SizedBox(height: 9),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ReportChartPainter extends CustomPainter {
  _ReportChartPainter({
    required this.item,
    required this.ply,
    required this.inset,
    required this.surface,
    required this.grid,
    required this.ink,
    required this.cursor,
  });

  final FeedItem item;
  final int ply;

  /// How far inside each end the curve starts and stops: the scrub thumb's
  /// own inset, so ply i sits right over the thumb at ply i.
  final double inset;
  final Color surface;
  final Color grid;
  final Color ink;
  final Color cursor;

  double _y(int i, double h) {
    final share = feedWhiteShare(item, i) ?? 0.5;
    return h - share * h;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(14),
    );
    canvas.drawRRect(rrect, Paint()..color = surface);
    canvas.save();
    canvas.clipRRect(rrect);

    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    canvas.drawLine(Offset(0, h / 2), Offset(w, h / 2), gridPaint);
    for (final x in [w / 3, 2 * w / 3]) {
      for (var y = 0.0; y < h; y += 7) {
        canvas.drawLine(Offset(x, y), Offset(x, math.min(h, y + 3)), gridPaint);
      }
    }

    final n = item.plyCount;
    if (n > 0) {
      final span = math.max(1.0, w - 2 * inset);
      double x(int i) => inset + span * i / n;
      // The curve runs flat out to the chart's edges (the opening eval
      // before the first move, the final one after the last), so the fill
      // has no edge of its own inside the chart.
      final line = Path()..moveTo(0, _y(0, h));
      final area = Path()
        ..moveTo(0, h)
        ..lineTo(0, _y(0, h));
      for (var i = 0; i <= n; i++) {
        final at = Offset(x(i), _y(i, h));
        line.lineTo(at.dx, at.dy);
        area.lineTo(at.dx, at.dy);
      }
      line.lineTo(w, _y(n, h));
      area
        ..lineTo(w, _y(n, h))
        ..lineTo(w, h)
        ..close();
      canvas.drawPath(area, Paint()..color = ink.withValues(alpha: 0.08));
      canvas.drawPath(
        line,
        Paint()
          ..color = ink.withValues(alpha: 0.7)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeJoin = StrokeJoin.round,
      );

      final ring = Paint()
        ..color = surface.withValues(alpha: 0.55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1;
      for (var i = 1; i <= n; i++) {
        final moment = item.plies[i].moment;
        if (!feedIsChartDot(moment)) continue;
        final c = Offset(x(i), _y(i, h));
        // Error dots are marks on the chart: 3:1 against its surface in
        // either theme, hue kept.
        final dot = feedReadableOn(
          feedJudgmentColor(moment)!,
          surface,
          target: 3,
        );
        canvas.drawCircle(c, 3.5, Paint()..color = dot);
        canvas.drawCircle(c, 3.5, ring);
      }

      final cx = x(ply);
      canvas.drawLine(
        Offset(cx, 0),
        Offset(cx, h),
        Paint()
          ..color = cursor.withValues(alpha: 0.8)
          ..strokeWidth = 2,
      );
      canvas.drawCircle(Offset(cx, _y(ply, h)), 5, Paint()..color = ink);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ReportChartPainter old) =>
      old.ply != ply ||
      old.item != item ||
      old.inset != inset ||
      old.surface != surface;
}

/// "15. Nf3  [badge] Blunder ……… +1.2": the move label, its classification
/// (the board's own badge and word) and a right-aligned trailing figure.
class FeedMoveInfoRow extends StatelessWidget {
  const FeedMoveInfoRow({
    required this.item,
    required this.ply,
    required this.trailing,
    required this.height,
    super.key,
  });

  final FeedItem item;
  final int ply;
  final String trailing;
  final double height;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final moveClass = ply > 0 ? item.plies[ply].effectiveClass : null;
    return SizedBox(
      height: height,
      child: Row(
        children: [
          // The move and its class take what they need from the left; the
          // trailing figure keeps to the row's right edge.
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    feedMoveLabel(item, ply),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.textLgBold.copyWith(
                      fontSize: 18,
                      height: 24 / 18,
                      color: colors.textPrimary,
                      fontFeatures: _tabular,
                    ),
                  ),
                ),
                if (moveClass != null) ...[
                  const SizedBox(width: 10),
                  FeedClassMark(moveClass: moveClass, size: 16),
                  const SizedBox(width: 5),
                  Text(
                    feedClassLabel(moveClass),
                    maxLines: 1,
                    style: AppTypography.textXsBold.copyWith(
                      fontSize: 12,
                      height: 1.2,
                      fontWeight: FontWeight.w600,
                      color: feedClassTextColorFor(context, moveClass),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            trailing,
            maxLines: 1,
            style: AppTypography.textXsBold.copyWith(
              fontSize: 13,
              height: 1.2,
              fontWeight: FontWeight.w600,
              color: colors.textPrimaryMuted,
              fontFeatures: _tabular,
            ),
          ),
        ],
      ),
    );
  }
}

/// Move bubble riding the scrub thumb on games with no report yet; the
/// strip places it ([FeedScrubStrip.bubble]). Just the move, set in the
/// page's colour on the thumb's own ink, so it reads as the thumb's label
/// in either theme with no edge drawn around it. Where the move sits in the
/// game is the counter's job, at the line's end.
class FeedMoveBubble extends StatelessWidget {
  const FeedMoveBubble({required this.item, required this.ply, super.key});

  final FeedItem item;
  final int ply;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.textPrimary,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          child: Text(
            feedMoveLabel(item, ply),
            maxLines: 1,
            softWrap: false,
            style: AppTypography.textSmBold.copyWith(
              fontSize: 14,
              height: 18 / 14,
              color: colors.background,
              fontFeatures: _tabular,
            ),
          ),
        ),
      ),
    );
  }
}
