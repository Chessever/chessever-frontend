import 'dart:async';
import 'dart:math' as math;

import 'package:chessever2/providers/board_settings_provider_new.dart';
import 'package:chessever2/screens/chessboard/classification_fx/classification_landing.dart';
import 'package:chessever2/screens/chessboard/classification_fx/move_class.dart';
import 'package:chessever2/screens/chessboard/utils/legible_ink.dart'
    show legibleHueInk;
import 'package:chessever2/screens/chessboard/widgets/chess_board_from_fen_new.dart'
    show GameCardChessboard;
import 'package:chessever2/screens/chessboard/widgets/nag_display.dart'
    show NagDisplay, getNagDisplay, nagInk;
import 'package:chessever2/screens/chessboard/widgets/player_first_row_detail_widget.dart'
    show playerNameLabel;
import 'package:chessever2/screens/collections/collections_data.dart';
import 'package:chessever2/screens/feed/puzzles/puzzle_widgets.dart'
    show PuzzleMoveBadge;
import 'package:chessever2/screens/stories/story_models.dart';
import 'package:chessever2/screens/stories/story_row.dart';
import 'package:chessever2/screens/stories/story_seen_store.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/broadcast_custom_scoring.dart'
    show boardResultLabelForSide;
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/text_scale.dart';
import 'package:chessever2/utils/user_error_message.dart';
import 'package:chessever2/widgets/federation_flag.dart';
import 'package:chessever2/widgets/press_spring.dart';
import 'package:chessever2/widgets/skeleton_widget.dart';
import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter/foundation.dart' show ValueListenable, setEquals;
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:skeletonizer/skeletonizer.dart' show Bone;

/// The page's side margin: the bars, the header, the board and everything
/// aligned to it.
double get _gutter => 16.sp;

/// [size] at the page's scale, never below its size on a portrait phone:
/// for the pieces that sit beside the page's fixed-size type (the bars, the
/// header's circle, the flags), which a phone on its side would otherwise
/// shrink to specks beside full-size words, or press against the edge.
double _atLeast(double size) => math.max(size.sp, size);

/// The share of a segment's run before its move lands on the board: the
/// position before reads for a beat, then the move slides in.
const double kStorySlideAt = 0.07;

/// The page's layout above its story, in one place for the page itself and
/// for the viewer, whose cover flies into the header's circle.
abstract final class StoryPageMetrics {
  /// From under the status bar to the bars.
  static double get barsTop => _atLeast(8);

  /// From the bars to the header.
  static double get barsGap => _atLeast(8);

  /// The header's first line: the cover circle and the close target sit in
  /// it; a title grown by a larger text setting runs below it.
  static const double headerBand = 44;

  /// The header's cover circle.
  static double get avatar => _atLeast(32);

  /// Between the story and the actions under it.
  static double get actionGap => _atLeast(10);

  /// Where the header's cover circle is on a page of [size] under [padding].
  static Rect avatarRect(
    Size size,
    EdgeInsets padding,
    TextDirection direction,
  ) {
    final top =
        padding.top +
        barsTop +
        StoryProgressBars.height +
        barsGap +
        (headerBand - avatar) / 2;
    final left = direction == TextDirection.rtl
        ? size.width - padding.right - _gutter - avatar
        : padding.left + _gutter;
    return Rect.fromLTWH(left, top, avatar, avatar);
  }
}

// ------------------------------------------------------------ the words

/// The type and room of the words under a story's board: the game's line,
/// the move, why it matters, and the book's words. One size whatever their
/// length (a larger text setting grows it up to [kDenseTextScale]); long
/// words wrap to the lines there is room for and fade at their end.
@immutable
class StoryTextMetrics {
  const StoryTextMetrics._({
    required this.scaler,
    required this.captionStyle,
    required this.moveStyle,
    required this.labelStyle,
    required this.commentStyle,
    required this.captionLine,
    required this.moveLine,
    required this.labelLine,
    required this.commentLine,
  });

  factory StoryTextMetrics.of(BuildContext context) {
    final colors = context.colors;
    final scaler = MediaQuery.textScalerOf(
      context,
    ).clamp(maxScaleFactor: kDenseTextScale);
    final captionStyle = AppTypography.textXsRegular.copyWith(
      fontSize: 12,
      color: colors.textSecondary,
      height: 1.35,
    );
    final moveStyle = AppTypography.textXlBold.copyWith(
      fontSize: 21,
      color: colors.textPrimary,
      height: 1.25,
      letterSpacing: 0.1,
    );
    final labelStyle = AppTypography.textSmSemiBold.copyWith(
      fontSize: 15,
      color: colors.textSecondary,
      height: 1.3,
    );
    final commentStyle = AppTypography.textSmRegular.copyWith(
      fontSize: 16,
      color: colors.textPrimaryMuted,
      height: 1.42,
    );
    double line(TextStyle style) =>
        (scaler.scale(style.fontSize ?? 14) * (style.height ?? 1))
            .ceilToDouble();
    return StoryTextMetrics._(
      scaler: scaler,
      captionStyle: captionStyle,
      moveStyle: moveStyle,
      labelStyle: labelStyle,
      commentStyle: commentStyle,
      captionLine: line(captionStyle),
      moveLine: line(moveStyle),
      labelLine: line(labelStyle),
      commentLine:
          scaler.scale(commentStyle.fontSize ?? 15) *
          (commentStyle.height ?? 1),
    );
  }

  final TextScaler scaler;
  final TextStyle captionStyle;
  final TextStyle moveStyle;
  final TextStyle labelStyle;
  final TextStyle commentStyle;
  final double captionLine;
  final double moveLine;
  final double labelLine;
  final double commentLine;

  /// The words take between [minLines] and [maxLines] lines, as the height
  /// allows; beside a board on its side, up to [maxLinesBeside].
  static const int minLines = 2;
  static const int maxLines = 5;
  static const int maxLinesBeside = 7;

  /// Between the board's lower row and the words.
  static double get topGap => _atLeast(14);

  /// Between the game's line and the move.
  static double get captionGap => _atLeast(6);

  /// Between why it matters and the book's words.
  static double get commentGap => _atLeast(6);

  /// The words' room with [lines] lines of comment.
  double box(int lines) =>
      captionLine +
      captionGap +
      moveLine +
      labelLine +
      commentGap +
      (lines * commentLine).ceilToDouble() +
      1;
}

/// The story area's own geometry: the board as large as the space allows,
/// the words under it always given their room, so nothing moves from one
/// position to the next.
abstract final class StoryFrameLayout {
  /// Smallest board drawn; below it the whole story scales down instead.
  static const double minBoard = 120;

  /// Between a player's row and the board. Never under its portrait size:
  /// a phone on its side scales the page's spacing down by half.
  static double get rowGap => _atLeast(8);

  /// The board's side within [constraints] (the story area), the rows and
  /// the words' least room around it.
  static double boardSize(BoxConstraints constraints, StoryTextMetrics text) {
    final across = constraints.maxWidth - 2 * _gutter;
    final fixed =
        2 * StoryPlayerRow.height +
        2 * rowGap +
        StoryTextMetrics.topGap +
        text.box(StoryTextMetrics.minLines);
    final down = constraints.hasBoundedHeight
        ? constraints.maxHeight - fixed
        : double.infinity;
    return math.max(minBoard, math.min(across, down)).floorToDouble();
  }

  /// How many lines of words fit under a board of [side] upright.
  static int commentLines(
    BoxConstraints constraints,
    double side,
    StoryTextMetrics text,
  ) {
    if (!constraints.hasBoundedHeight) return StoryTextMetrics.maxLines;
    final taken =
        2 * StoryPlayerRow.height +
        2 * rowGap +
        side +
        StoryTextMetrics.topGap +
        text.box(0);
    final lines = ((constraints.maxHeight - taken) / text.commentLine).floor();
    return lines.clamp(StoryTextMetrics.minLines, StoryTextMetrics.maxLines);
  }

  /// The story's width in the area [constraints]: the board's upright, the
  /// board and the words beside it on its side. The actions under the story
  /// line up with its edges.
  static double storyWidth(BuildContext context, BoxConstraints constraints) {
    if (beside(constraints)) {
      final side = boardBeside(constraints);
      return side + sideGap + sideWidth(constraints, side);
    }
    return boardSize(constraints, StoryTextMetrics.of(context));
  }

  /// Air above and below a board beside its words, split evenly.
  static double get besideAir => _atLeast(20);

  /// Between the board and the words beside it.
  static double get sideGap => _atLeast(20);

  /// The words beside the board take at least this, and at most [maxSide].
  static const double minSide = 240;
  static const double maxSide = 340;

  /// Whether the story area [constraints] sets the words beside the board
  /// (a phone on its side).
  static bool beside(BoxConstraints constraints) {
    if (!constraints.hasBoundedHeight) return false;
    final across = constraints.maxWidth - 2 * _gutter;
    return across - sideGap - minSide >= constraints.maxHeight - besideAir;
  }

  /// The board's side when [beside]: as tall as the area, less [besideAir].
  static double boardBeside(BoxConstraints constraints) =>
      math.max(minBoard, constraints.maxHeight - besideAir).floorToDouble();

  /// The width of the words beside a board of [board].
  static double sideWidth(BoxConstraints constraints, double board) {
    final across = constraints.maxWidth - 2 * _gutter;
    return math.min(maxSide, across - board - sideGap).floorToDouble();
  }
}

/// A story position's arrangement, one for the story and its skeleton so
/// nothing moves when the games land. Upright: the players over and under
/// the board, the words below it in their full room. On its side: the
/// board as tall as the space, the players beside it level with its top and
/// bottom edges, the words between them.
class _StoryFrameScaffold extends StatelessWidget {
  const _StoryFrameScaffold({
    required this.board,
    required this.top,
    required this.bottom,
    required this.words,
  });

  final Widget Function(double side) board;

  /// The rows over and under the board.
  final Widget top;
  final Widget bottom;

  /// The words for [lines] lines of comment; [beside] when beside a board.
  final Widget Function(bool beside, int lines) words;

  @override
  Widget build(BuildContext context) {
    final text = StoryTextMetrics.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        if (StoryFrameLayout.beside(constraints)) {
          final side = StoryFrameLayout.boardBeside(constraints);
          final middle =
              side - 2 * StoryPlayerRow.height - 2 * StoryFrameLayout.rowGap;
          final room = middle - text.box(0);
          final lines = room <= 0
              ? 0
              : (room / text.commentLine).floor().clamp(
                  0,
                  StoryTextMetrics.maxLinesBeside,
                );
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              board(side),
              SizedBox(width: StoryFrameLayout.sideGap),
              SizedBox(
                width: StoryFrameLayout.sideWidth(constraints, side),
                height: side,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    top,
                    Expanded(
                      child: Center(
                        child: SizedBox(
                          height: math.min(
                            math.max(0.0, middle),
                            text.box(lines),
                          ),
                          child: words(true, lines),
                        ),
                      ),
                    ),
                    bottom,
                  ],
                ),
              ),
            ],
          );
        }
        final side = StoryFrameLayout.boardSize(constraints, text);
        final lines = StoryFrameLayout.commentLines(constraints, side, text);
        return FittedBox(
          fit: BoxFit.scaleDown,
          child: SizedBox(
            width: side,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                top,
                SizedBox(height: StoryFrameLayout.rowGap),
                board(side),
                SizedBox(height: StoryFrameLayout.rowGap),
                bottom,
                SizedBox(height: StoryTextMetrics.topGap),
                SizedBox(
                  key: const ValueKey('story_words_room'),
                  height: text.box(lines),
                  child: words(false, lines),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ------------------------------------------------------------- the page

/// What happened on a position that asked the reader for a move.
enum StoryPuzzleOutcome {
  /// They found it.
  solved,

  /// They tried another move; the answer was shown.
  missed,

  /// They asked to see it.
  shown,
}

/// The viewer's side of a position that asks for a move: what the reader
/// did on it before, the story waiting while they think, and where the
/// board that takes their move is (the viewer's taps leave it alone).
abstract class StoryPuzzleHost {
  StoryPuzzleOutcome? outcomeOf(String frameId);

  /// The position [frameId] waits for the reader's move ([waiting]): the
  /// story's bar holds until it is answered.
  void prompting(String frameId, bool waiting);

  /// The position [frameId] was answered.
  void settle(String frameId, StoryPuzzleOutcome outcome);

  /// The board taking a move, on screen; null when none does.
  ValueNotifier<Rect?> get zone;
}

/// One collection's face: its bars, its header, the position on screen and
/// the actions under it, laid out for the whole screen.
class StoryCollectionPage extends ConsumerWidget {
  const StoryCollectionPage({
    super.key,
    required this.collection,
    required this.storyIndex,
    this.storyId,
    required this.progress,
    required this.chrome,
    required this.backdrop,
    required this.onClose,
    required this.onOpenGame,
    required this.onOpenCollection,
    required this.onRetry,
    this.onOpenEvent,
    this.avatarHidden,
    this.puzzles,
    this.active = false,
  });

  final Collection collection;

  /// True while the viewer's flying cover stands in for the header's
  /// circle (on the way in and out); null on every face but the active one.
  final ValueListenable<bool>? avatarHidden;

  /// The page the viewer has this collection on; null until the reader has
  /// been here (then it is where they left off, or the first new story).
  final int? storyIndex;

  /// Which page that is ([storyIdAt]): a face whose stories were read
  /// again while it was turned away finds it where it stands now.
  final String? storyId;

  /// The page's run, 0 to 1. Still for every face but the one in view.
  final Animation<double> progress;

  /// 1 with the header, bars and actions shown; 0 while a story is held.
  final Animation<double> chrome;
  final Color backdrop;
  final VoidCallback onClose;
  final VoidCallback onOpenGame;

  /// The collection's own page (the header, View collection).
  final VoidCallback onOpenCollection;

  /// The game's event, for a story whose second action goes there (Missed
  /// chances); null opens the collection instead.
  final VoidCallback? onOpenEvent;
  final VoidCallback onRetry;

  /// The viewer's side of positions that ask for a move.
  final StoryPuzzleHost? puzzles;

  /// The face in view: only it takes a move.
  final bool active;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final read = ref.watch(storyBatchProvider(collection.slug));
    final batch = read.valueOrNull;
    // The remembered page where it stands now, clamped to the pages the
    // batch holds: a re-read can bring new games ahead of it, or fewer.
    final id = storyId;
    final index = batch == null
        ? 0
        : clampStoryIndex(
            (id == null ? null : storyIndexOf(batch, id)) ??
                storyIndex ??
                ref
                    .read(storySeenProvider.notifier)
                    .resumeIndex(collection, batch),
            batch.storyCount,
          );
    final padding = MediaQuery.paddingOf(context);
    final frame = batch?.frameAt(index);

    final Widget body;
    if (batch == null && read.hasError) {
      body = StoryRetry(error: read.error, onRetry: onRetry);
    } else if (batch == null) {
      body = const StorySkeleton();
    } else if (frame == null) {
      body = _StoryNotice(
        text: isMissedChances(collection)
            ? 'No missed chances today.'
            : 'No games here yet.',
      );
    } else {
      body = KeyedSubtree(
        key: ValueKey('story_game_${frame.game.id}'),
        child: StoryFrameView(
          key: ValueKey('story_frame_${frame.id}'),
          frame: frame,
          progress: progress,
          active: active,
          puzzles: puzzles,
        ),
      );
    }

    return ColoredBox(
      color: backdrop,
      // Clear of a notch at either side in landscape.
      child: Padding(
        padding: EdgeInsets.only(left: padding.left, right: padding.right),
        child: Column(
          children: [
            SizedBox(height: padding.top + StoryPageMetrics.barsTop),
            FadeTransition(
              opacity: chrome,
              // On the page's gutter, like the header and the board.
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: _gutter),
                child: StoryProgressBars(
                  count: batch == null || batch.storyCount == 0
                      ? 1
                      : batch.storyCount,
                  index: batch == null ? 0 : index,
                  progress: progress,
                  storyStarts: batch == null
                      ? const {}
                      : {
                          for (var i = 1; i < batch.frames.length; i++)
                            if (batch.frames[i].startsStory) i,
                        },
                ),
              ),
            ),
            SizedBox(height: StoryPageMetrics.barsGap),
            FadeTransition(
              opacity: chrome,
              child: StoryHeader(
                collection: collection,
                onClose: onClose,
                onOpen: onOpenCollection,
                avatarHidden: avatarHidden,
              ),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, area) {
                  final actions = StoryActions.heightOf(context);
                  // The story's own area, as the Center below hands it on:
                  // the actions line up with the story's edges in it.
                  final story = BoxConstraints(
                    maxWidth: area.maxWidth,
                    maxHeight: math.max(
                      0.0,
                      area.maxHeight - StoryPageMetrics.actionGap - actions,
                    ),
                  );
                  return Column(
                    children: [
                      Expanded(child: Center(child: body)),
                      SizedBox(height: StoryPageMetrics.actionGap),
                      FadeTransition(
                        opacity: chrome,
                        child: SizedBox(
                          height: actions,
                          child: frame == null
                              ? null
                              : Center(
                                  child: SizedBox(
                                    width: StoryFrameLayout.storyWidth(
                                      context,
                                      story,
                                    ),
                                    child: StoryActions(
                                      collectionLabel: storyCollectionAction(
                                        collection,
                                      ),
                                      onOpenGame: onOpenGame,
                                      onOpenCollection:
                                          onOpenEvent ?? onOpenCollection,
                                    ),
                                  ),
                                ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            SizedBox(height: padding.bottom + 8.sp),
          ],
        ),
      ),
    );
  }
}

/// The second action's words: where it goes.
String storyCollectionAction(Collection collection) {
  if (isMissedChances(collection)) return 'Go to event';
  return switch (collection.kind) {
    CollectionKind.event => 'Go to event',
    CollectionKind.book => 'View book',
    CollectionKind.analysis => 'View collection',
  };
}

/// One bar per position across the top: full for the positions before,
/// filling for the one on screen, empty for the ones after. A new story
/// (a new game) leaves a wider gap before its first bar, so the reader
/// sees how many games are left as well as how many positions. Each fill
/// is a rounded bar that grows in width, so its ends keep their round caps
/// all the way.
class StoryProgressBars extends StatelessWidget {
  const StoryProgressBars({
    super.key,
    required this.count,
    required this.index,
    required this.progress,
    this.storyStarts = const {},
  });

  final int count;
  final int index;
  final Animation<double> progress;

  /// The bars that open a story (other than the first).
  final Set<int> storyStarts;

  static double get height => _atLeast(2.5);
  static double get gap => _atLeast(3);
  static double get storyGap => _atLeast(9);

  @override
  Widget build(BuildContext context) {
    final ink = context.colors.textPrimary;
    return ExcludeSemantics(
      child: SizedBox(
        key: const ValueKey('story_bars'),
        height: height,
        width: double.infinity,
        child: CustomPaint(
          painter: _BarsPainter(
            count: count,
            index: index,
            progress: progress,
            track: ink.withValues(alpha: context.isLightTheme ? 0.16 : 0.24),
            fill: ink.withValues(alpha: context.isLightTheme ? 0.78 : 0.92),
            gap: gap,
            storyGap: storyGap,
            storyStarts: storyStarts,
          ),
        ),
      ),
    );
  }
}

class _BarsPainter extends CustomPainter {
  _BarsPainter({
    required this.count,
    required this.index,
    required this.progress,
    required this.track,
    required this.fill,
    required this.gap,
    required this.storyGap,
    required this.storyStarts,
  }) : super(repaint: progress);

  final int count;
  final int index;
  final Animation<double> progress;
  final Color track;
  final Color fill;
  final double gap;
  final double storyGap;
  final Set<int> storyStarts;

  @override
  void paint(Canvas canvas, Size size) {
    if (count <= 0 || size.width <= 0) return;
    var gaps = 0.0;
    for (var i = 1; i < count; i++) {
      gaps += storyStarts.contains(i) ? storyGap : gap;
    }
    final width = (size.width - gaps) / count;
    if (width <= 0) return;
    final radius = Radius.circular(size.height / 2);
    final trackPaint = Paint()..color = track;
    final fillPaint = Paint()..color = fill;
    var left = 0.0;
    for (var i = 0; i < count; i++) {
      if (i > 0) left += storyStarts.contains(i) ? storyGap : gap;
      final bar = RRect.fromLTRBR(left, 0, left + width, size.height, radius);
      canvas.drawRRect(bar, trackPaint);
      final share = i < index
          ? 1.0
          : i == index
          ? progress.value.clamp(0.0, 1.0)
          : 0.0;
      if (share > 0) {
        // The fill is its own rounded bar with round caps at both ends at
        // every width. Shorter than one cap, it slides out from behind the
        // track's rounded start instead of squashing its caps.
        final reach = width * share;
        final start = reach < size.height ? left + reach - size.height : left;
        canvas.save();
        canvas.clipRRect(bar);
        canvas.drawRRect(
          RRect.fromLTRBR(start, 0, left + reach, size.height, radius),
          fillPaint,
        );
        canvas.restore();
      }
      left += width;
    }
  }

  @override
  bool shouldRepaint(_BarsPainter old) =>
      old.count != count ||
      old.index != index ||
      old.progress != progress ||
      old.track != track ||
      old.fill != fill ||
      old.gap != gap ||
      old.storyGap != storyGap ||
      !setEquals(old.storyStarts, storyStarts);
}

/// The face's header: the collection's cover, title and byline, which open
/// the collection's own page, and the way out.
class StoryHeader extends StatelessWidget {
  const StoryHeader({
    super.key,
    required this.collection,
    required this.onClose,
    this.onOpen,
    this.avatarHidden,
  });

  final Collection collection;
  final VoidCallback onClose;

  /// The collection's own page, from its cover, title or byline.
  final VoidCallback? onOpen;

  /// Hides the cover circle while the viewer's flying cover stands in it.
  final ValueListenable<bool>? avatarHidden;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final byline = storyByline(collection);
    const band = StoryPageMetrics.headerBand;
    final cover = StoryCover(
      key: const ValueKey('story_header_cover'),
      collection: collection,
      diameter: StoryPageMetrics.avatar,
    );
    final hidden = avatarHidden;
    // The circle and the close target sit in the first 44pt line, where the
    // viewer's way in and out knows to find them ([StoryPageMetrics]); a
    // title grown by a larger text setting runs below it, never clipped.
    final identity = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: band,
          child: Center(
            child: hidden == null
                ? cover
                : ValueListenableBuilder<bool>(
                    valueListenable: hidden,
                    child: cover,
                    builder: (context, hide, cover) =>
                        Opacity(opacity: hide ? 0 : 1, child: cover),
                  ),
          ),
        ),
        SizedBox(width: _atLeast(10)),
        Expanded(
          child: Container(
            constraints: const BoxConstraints(minHeight: band),
            alignment: AlignmentDirectional.centerStart,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  collection.title,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.fade,
                  style: AppTypography.textSmBold.copyWith(
                    color: colors.textPrimary,
                    height: 1.25,
                  ),
                ),
                if (byline != null && byline.isNotEmpty)
                  Text(
                    byline,
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.fade,
                    style: AppTypography.textXsRegular.copyWith(
                      color: colors.textSecondary,
                      height: 1.3,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
    final open = onOpen;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: _gutter),
        Expanded(
          child: open == null
              ? identity
              : Semantics(
                  button: true,
                  label: 'Open ${collection.title}',
                  excludeSemantics: true,
                  child: GestureDetector(
                    key: const ValueKey('story_header_open'),
                    behavior: HitTestBehavior.opaque,
                    onTap: open,
                    // A press dims it, never scales it: the cover circle
                    // stays exactly where the viewer's cover lands.
                    child: PressSpring(
                      builder: (context, press, child) => Opacity(
                        opacity: 1 - 0.38 * press.clamp(0.0, 1.0),
                        child: child,
                      ),
                      child: identity,
                    ),
                  ),
                ),
        ),
        Semantics(
          button: true,
          label: 'Close stories',
          child: GestureDetector(
            key: const ValueKey('story_close'),
            behavior: HitTestBehavior.opaque,
            onTap: onClose,
            child: PressSpring(
              pressedScale: 0.86,
              child: SizedBox(
                width: 52,
                height: band,
                child: Center(
                  child: Icon(
                    Icons.close_rounded,
                    size: 26,
                    color: colors.iconPrimary,
                  ),
                ),
              ),
            ),
          ),
        ),
        SizedBox(width: 6.sp),
      ],
    );
  }
}

// ------------------------------------------------------------ a position

/// Where a puzzle position stands.
enum _Phase {
  /// Waiting for the reader's move.
  prompt,

  /// A wrong move is on the board; the answer follows.
  wrong,

  /// The answer is on the board.
  revealed,
}

/// One key position: the board at the moment (the move just played sliding
/// in, its arrows and marked squares, the verdict's badge), the players,
/// and the words under it, readable at once.
///
/// A position that asks for a move shows the position before it first, the
/// board taking the reader's move ([StoryPuzzleHost]); the story waits.
/// Found, the move lands with its badge; another move is shown briefly and
/// the answer follows; Show reveals it without a try.
class StoryFrameView extends ConsumerStatefulWidget {
  const StoryFrameView({
    super.key,
    required this.frame,
    required this.progress,
    this.active = true,
    this.puzzles,
  });

  final StoryFrame frame;
  final Animation<double> progress;

  /// The face in view: only it takes a move.
  final bool active;
  final StoryPuzzleHost? puzzles;

  @override
  ConsumerState<StoryFrameView> createState() => _StoryFrameViewState();
}

class _StoryFrameViewState extends ConsumerState<StoryFrameView> {
  static const Duration _wrongHold = Duration(milliseconds: 650);
  static const Duration _backBeat = Duration(milliseconds: 380);

  late bool _landed;

  ChessboardController? _board;
  _Phase _phase = _Phase.prompt;
  StoryPuzzleOutcome? _outcome;
  Square? _markSquare;
  MoveClass? _markClass;
  int _markSeq = 0;
  Timer? _timer;
  final GlobalKey _boardKey = GlobalKey(debugLabel: 'story_puzzle_board');

  StorySegment get _segment => widget.frame.position;
  StoryPuzzle? get _puzzle => _segment.puzzle;

  bool get _asking =>
      _puzzle != null && _phase == _Phase.prompt && widget.active;

  @override
  void initState() {
    super.initState();
    _landed = widget.progress.value >= kStorySlideAt;
    widget.progress.addListener(_onProgress);
    final puzzle = _puzzle;
    if (puzzle != null) {
      _outcome = widget.puzzles?.outcomeOf(widget.frame.id);
      _phase = _outcome == null ? _Phase.prompt : _Phase.revealed;
      _board = ChessboardController(game: _boardData());
      if (_phase == _Phase.revealed) _markAnswer(animate: false);
      _afterFrame(_report);
    }
  }

  @override
  void didUpdateWidget(covariant StoryFrameView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.progress != widget.progress) {
      oldWidget.progress.removeListener(_onProgress);
      widget.progress.addListener(_onProgress);
    }
    _landed = widget.progress.value >= kStorySlideAt;
    if (_puzzle != null && oldWidget.active != widget.active) {
      if (_phase == _Phase.prompt) {
        _board?.updatePosition(_boardData(), animate: false);
      }
      _afterFrame(_report);
    }
  }

  @override
  void dispose() {
    widget.progress.removeListener(_onProgress);
    _timer?.cancel();
    _board?.dispose();
    final zone = widget.puzzles?.zone;
    if (zone != null && _publishedZone && zone.value == _zoneRect) {
      zone.value = null;
    }
    super.dispose();
  }

  void _afterFrame(VoidCallback action) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) action();
    });
  }

  void _onProgress() {
    final landed = widget.progress.value >= kStorySlideAt;
    if (landed != _landed) setState(() => _landed = landed);
  }

  // ------------------------------------------------------------ puzzle

  bool _publishedZone = false;
  Rect? _zoneRect;

  /// Tells the viewer whether this position waits for a move, and where
  /// the board taking it is.
  void _report() {
    final host = widget.puzzles;
    if (host == null || !widget.active) return;
    host.prompting(widget.frame.id, _asking);
    final box = _boardKey.currentContext?.findRenderObject();
    if (_asking && box is RenderBox && box.attached && box.hasSize) {
      _zoneRect = box.localToGlobal(Offset.zero) & box.size;
      _publishedZone = true;
      host.zone.value = _zoneRect;
    } else if (_publishedZone) {
      if (host.zone.value == _zoneRect) host.zone.value = null;
      _publishedZone = false;
    }
  }

  Position? _before() {
    try {
      return Position.setupPosition(
        Rule.chess,
        Setup.parseFen(_segment.fenBefore),
      );
    } catch (_) {
      return null;
    }
  }

  GameData _boardData({String? fen, Move? lastMove}) {
    final puzzle = _puzzle!;
    if (fen != null) {
      final side = _turnOf(fen);
      return GameData(
        fen: fen,
        lastMove: lastMove,
        playerSide: PlayerSide.none,
        sideToMove: side,
        validMoves: const {},
      );
    }
    if (_phase == _Phase.revealed) {
      return GameData(
        fen: puzzle.answerFen,
        lastMove: puzzle.answer,
        playerSide: PlayerSide.none,
        sideToMove: puzzle.solver.opposite,
        validMoves: const {},
      );
    }
    final position = _before();
    final takes = widget.active && _phase == _Phase.prompt && position != null;
    return GameData(
      fen: _segment.fenBefore,
      lastMove: _segment.moveBefore,
      playerSide: takes
          ? (puzzle.solver == Side.white ? PlayerSide.white : PlayerSide.black)
          : PlayerSide.none,
      sideToMove: puzzle.solver,
      validMoves: takes ? makeLegalMoves(position) : const {},
      kingSquareInCheck: position != null && position.isCheck
          ? position.board.kingOf(position.turn)
          : null,
    );
  }

  static Side _turnOf(String fen) {
    final parts = fen.split(' ');
    return parts.length > 1 && parts[1] == 'b' ? Side.black : Side.white;
  }

  /// Whether [move] in [position] is the puzzle's answer, castling either
  /// way it can be entered.
  static bool _answers(Position position, Move move, StoryPuzzle puzzle) {
    Move normal(Move m) =>
        m is NormalMove && position.isLegal(m) ? position.normalizeMove(m) : m;
    return normal(move).uci == normal(puzzle.answer).uci;
  }

  void _onMove(Move move, {bool? viaDragAndDrop}) {
    final puzzle = _puzzle;
    final board = _board;
    final position = _before();
    if (puzzle == null || board == null || position == null || !_asking) {
      return;
    }
    if (!position.isLegal(move)) return;
    if (_answers(position, move, puzzle)) {
      unawaited(HapticFeedbackService.success());
      _reveal(StoryPuzzleOutcome.solved);
      return;
    }
    // Another move: it stands for a beat with its mark, slides home, and
    // the answer plays.
    final after = position.play(move);
    board.updatePosition(_boardData(fen: after.fen, lastMove: move));
    unawaited(HapticFeedbackService.medium());
    setState(() {
      _phase = _Phase.wrong;
      if (move is NormalMove) _mark(move.to, MoveClass.mistake);
    });
    _afterFrame(_report);
    _timer?.cancel();
    _timer = Timer(_wrongHold, () {
      if (!mounted) return;
      board.updatePosition(
        _boardData(fen: _segment.fenBefore, lastMove: _segment.moveBefore),
      );
      setState(_clearMark);
      _timer = Timer(_backBeat, () {
        if (mounted) _reveal(StoryPuzzleOutcome.missed);
      });
    });
  }

  /// The reader asked to see the answer.
  void _show() {
    if (!_asking) return;
    unawaited(HapticFeedbackService.buttonPress());
    _reveal(StoryPuzzleOutcome.shown);
  }

  void _reveal(StoryPuzzleOutcome outcome) {
    _timer?.cancel();
    setState(() {
      _phase = _Phase.revealed;
      _outcome = outcome;
      _markAnswer(animate: true);
    });
    _board?.updatePosition(_boardData());
    widget.puzzles?.settle(widget.frame.id, outcome);
    _afterFrame(_report);
  }

  void _markAnswer({required bool animate}) {
    final puzzle = _puzzle!;
    final answer = puzzle.answer;
    if (answer is! NormalMove || _isCastle(answer)) return;
    final moveClass = puzzle.kind == StoryPuzzleKind.findPlayed
        ? (_segment.moveClass ?? MoveClass.best)
        : MoveClass.best;
    _markSquare = answer.to;
    _markClass = moveClass;
    if (animate) _markSeq++;
  }

  void _mark(Square square, MoveClass moveClass) {
    _markSquare = square;
    _markClass = moveClass;
    _markSeq++;
  }

  void _clearMark() {
    _markSquare = null;
    _markClass = null;
  }

  /// A castling move lands its badge on no one square: none is drawn.
  bool _isCastle(NormalMove move) =>
      _before()?.board.roleAt(move.from) == Role.king &&
      (move.from.file - move.to.file).abs() > 1;

  // ------------------------------------------------------------ build

  Side get _orientation => _puzzle?.solver ?? Side.white;

  @override
  Widget build(BuildContext context) {
    final game = widget.frame.game.game;
    final orientation = _orientation;
    final revealed = _segment.finalPly && (_puzzle == null ? _landed : true);
    return _StoryFrameScaffold(
      top: StoryPlayerRow(
        game: game,
        white: orientation == Side.black,
        revealed: revealed,
      ),
      bottom: StoryPlayerRow(
        game: game,
        white: orientation == Side.white,
        revealed: revealed,
      ),
      board: (side) => _puzzle == null
          ? _stillBoard(side, game)
          : _puzzleBoard(side, orientation),
      words: (beside, lines) => StoryMomentText(
        key: const ValueKey('story_words'),
        segment: _segment,
        caption: widget.frame.game.caption,
        lines: lines,
        asking: _puzzle != null && _phase != _Phase.revealed,
        outcome: _outcome,
        onShow: _phase == _Phase.prompt && widget.active ? _show : null,
      ),
    );
  }

  /// The position as it stands, the move sliding in a beat after the page
  /// shows, its badge landing with it.
  Widget _stillBoard(double side, GamesTourModel game) {
    final segment = _segment;
    final landed = _landed || segment.isStill;
    final move = segment.move;
    final badge = landed && move is NormalMove && segment.moveClass != null
        ? segment.moveClass
        : null;
    return SizedBox.square(
      dimension: side,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          GameCardChessboard(
            key: const ValueKey('story_board'),
            fen: landed ? segment.fenAfter : segment.fenBefore,
            lastMove: landed ? move : segment.moveBefore,
            boardSize: side,
            orientation: Side.white,
            showCoordinates: false,
            gameStatus: landed && segment.finalPly ? game.gameStatus : null,
            // The board is the story's subject, set flat on its page.
            grounded: false,
            shapes: landed ? segment.shapes : const {},
          ),
          if (badge != null && move is NormalMove)
            PuzzleMoveBadge(
              key: const ValueKey('story_badge'),
              square: move.to,
              moveClass: badge,
              boardSize: side,
              orientation: Side.white,
            ),
        ],
      ),
    );
  }

  /// The board that takes the reader's move.
  Widget _puzzleBoard(double side, Side orientation) {
    final board = _board!;
    final settings =
        ref.watch(boardSettingsProviderNew).valueOrNull ??
        const BoardSettingsNew();
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final markSquare = _markSquare;
    final markClass = _markClass;
    if (_asking) _afterFrame(_report);
    return SizedBox.square(
      key: _boardKey,
      dimension: side,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Chessboard(
            key: const ValueKey('story_puzzle_board'),
            size: side,
            controller: board,
            orientation: orientation,
            settings: ChessboardSettings(
              enableCoordinates: false,
              animationDuration: reduceMotion
                  ? Duration.zero
                  : const Duration(milliseconds: 220),
              dragFeedbackScale: 1,
              dragTargetKind: DragTargetKind.none,
              pieceShiftMethod: PieceShiftMethod.tapTwoSquares,
              autoQueenPromotionOnPremove: false,
              enablePremoves: false,
              pieceOrientationBehavior: PieceOrientationBehavior.facingUser,
              colorScheme: settings.colorScheme,
              pieceAssets: settings.pieceAssets,
            ),
            shapes: _phase == _Phase.revealed ? _segment.shapes : const {},
            landingSquare: markClass != null ? markSquare : null,
            landingKey: markClass != null ? _markSeq : null,
            onMove: _onMove,
          ),
          if (markSquare != null && markClass != null)
            PuzzleMoveBadge(
              key: const ValueKey('story_badge'),
              square: markSquare,
              moveClass: markClass,
              boardSize: side,
              orientation: orientation,
            ),
          Positioned.fill(
            child: IgnorePointer(
              child: ClassificationLanding(
                square: markSquare,
                moveClass: markClass,
                orientation: orientation,
                trigger: _markSeq,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The words under a position, start-aligned on the board's edge, in a room
/// that never changes size:
///
/// * the game's line (event, opening);
/// * the move, its number a step quieter and its glyphs in the app's
///   annotation colours;
/// * why it matters, in the verdict's colour ("Brilliant", "Missed win");
/// * the book's words, wrapping to [lines] lines and fading at their end.
///
/// While a position waits for a move it asks instead ("White to move",
/// "Find the strongest move.") with a quiet Show beside the question.
class StoryMomentText extends StatelessWidget {
  const StoryMomentText({
    super.key,
    required this.segment,
    required this.lines,
    this.caption,
    this.asking = false,
    this.outcome,
    this.onShow,
  });

  final StorySegment segment;
  final String? caption;
  final int lines;

  /// The position waits for the reader's move.
  final bool asking;

  /// How the reader answered, once they did.
  final StoryPuzzleOutcome? outcome;

  /// Reveals the answer without a try; null hides Show.
  final VoidCallback? onShow;

  @override
  Widget build(BuildContext context) {
    final text = StoryTextMetrics.of(context);
    final colors = context.colors;
    final puzzle = segment.puzzle;
    final Widget moveLine;
    final Widget labelLine;
    String? comment;
    if (puzzle != null && asking) {
      final (who, ask) = puzzle.prompt;
      moveLine = Text(
        who,
        key: const ValueKey('story_prompt'),
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.fade,
        style: text.moveStyle,
      );
      labelLine = Row(
        children: [
          Flexible(
            child: Text(
              ask,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.fade,
              style: text.labelStyle,
            ),
          ),
        ],
      );
    } else {
      final (number, san, nags) = puzzle != null
          ? (
              _numberOf(segment),
              puzzle.answerSan,
              puzzle.kind == StoryPuzzleKind.findPlayed
                  ? segment.nags
                  : const <int>[],
            )
          : (
              segment.isStill ? null : _numberOf(segment),
              segment.san,
              segment.nags,
            );
      moveLine = san == null
          ? const SizedBox()
          : Text.rich(
              TextSpan(
                style: text.moveStyle,
                children: [
                  if (number != null)
                    TextSpan(
                      text: '$number ',
                      style: text.moveStyle.copyWith(
                        color: colors.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  TextSpan(text: san),
                  for (final nag in nags)
                    if (getNagDisplay(nag) case final display?)
                      TextSpan(
                        text: display.isQuality
                            ? display.symbol
                            : ' ${display.symbol}',
                        style: text.moveStyle.copyWith(
                          color: storyGlyphInk(context, display),
                        ),
                      ),
                ],
              ),
              key: const ValueKey('story_move'),
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.fade,
            );
      final label = _labelOf(segment, outcome);
      labelLine = label == null
          ? const SizedBox()
          : Text(
              label,
              key: const ValueKey('story_label'),
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.fade,
              style: text.labelStyle.copyWith(
                color: storyToneInk(context, segment, outcome),
              ),
            );
      comment = _commentOf(segment);
    }
    final hasLabel = !(puzzle == null && _labelOf(segment, outcome) == null);
    // Without a label the words begin on its line: the room stays the same.
    final commentLines = lines + (hasLabel || asking ? 0 : 1);
    final commentHeight =
        text.box(lines) -
        text.captionLine -
        StoryTextMetrics.captionGap -
        text.moveLine -
        (hasLabel || asking ? text.labelLine + StoryTextMetrics.commentGap : 0);
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: kDenseTextScale,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: text.captionLine,
            child: caption == null
                ? null
                : Text(
                    caption!,
                    key: const ValueKey('story_caption'),
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.fade,
                    style: text.captionStyle,
                  ),
          ),
          SizedBox(height: StoryTextMetrics.captionGap),
          SizedBox(
            height: text.moveLine,
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: moveLine,
            ),
          ),
          if (hasLabel || asking) ...[
            SizedBox(
              height: text.labelLine,
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: labelLine,
              ),
            ),
            SizedBox(height: StoryTextMetrics.commentGap),
          ],
          SizedBox(
            height: math.max(0.0, commentHeight),
            child: asking
                ? _StoryAsk(
                    hint: puzzle?.hint,
                    style: text.commentStyle,
                    onShow: onShow,
                    showStyle: text.labelStyle,
                  )
                : comment == null || commentLines <= 0
                ? null
                : _StoryCommentText(
                    key: const ValueKey('story_comment'),
                    text: comment,
                    lines: commentLines,
                    style: text.commentStyle,
                  ),
          ),
        ],
      ),
    );
  }

  static String _numberOf(StorySegment s) => s.number;

  /// Why it matters, and how the reader did on a puzzle.
  static String? _labelOf(StorySegment s, StoryPuzzleOutcome? outcome) {
    final puzzle = s.puzzle;
    final label = s.label;
    if (puzzle == null) return label;
    if (puzzle.kind == StoryPuzzleKind.findMissed) {
      final played = s.san == null ? null : '${s.san} was played';
      final head = outcome == StoryPuzzleOutcome.solved
          ? 'Found the win'
          : 'Missed win';
      return played == null ? head : '$head · $played';
    }
    final what = label ?? 'Strongest move';
    return switch (outcome) {
      StoryPuzzleOutcome.solved => 'Found it · $what',
      StoryPuzzleOutcome.missed => 'Not quite · $what',
      _ => what,
    };
  }

  /// The words under the label: the book's, and for a missed win the line
  /// that won when it runs past the move the line above already shows.
  static String? _commentOf(StorySegment s) {
    final line = s.puzzle?.line?.trim();
    final words = s.comment;
    // "4. Qxf7#" is the move line itself; "61. Nxa5 Re8 62. Kc5" says more.
    if (line == null || line.split(RegExp(r'\s+')).length <= 2) return words;
    final shown = 'The win: $line';
    return words == null ? shown : '$words $shown';
  }
}

/// Under a question: a word on the position when there is one, then Show,
/// set right under the words.
class _StoryAsk extends StatelessWidget {
  const _StoryAsk({
    required this.hint,
    required this.style,
    required this.onShow,
    required this.showStyle,
  });

  final String? hint;
  final TextStyle style;
  final VoidCallback? onShow;
  final TextStyle showStyle;

  @override
  Widget build(BuildContext context) {
    final hint = this.hint;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (hint != null)
          Text(
            hint,
            key: const ValueKey('story_hint'),
            maxLines: 2,
            overflow: TextOverflow.fade,
            style: style,
          ),
        if (onShow case final show?) _ShowAnswer(onTap: show, style: showStyle),
      ],
    );
  }
}

/// "Show": the answer without a try. The page's ink, a whole 44pt target
/// whose word sits at its top, right under the question.
class _ShowAnswer extends StatelessWidget {
  const _ShowAnswer({required this.onTap, required this.style});

  final VoidCallback onTap;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Show the answer',
      excludeSemantics: true,
      child: GestureDetector(
        key: const ValueKey('story_show_answer'),
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: PressSpring(
          pressedScale: 0.96,
          builder: (context, press, child) =>
              Opacity(opacity: 1 - 0.4 * press.clamp(0.0, 1.0), child: child),
          child: Container(
            constraints: const BoxConstraints(minHeight: 44, minWidth: 64),
            padding: EdgeInsets.only(top: _atLeast(4)),
            alignment: AlignmentDirectional.topStart,
            child: Text(
              'Show',
              style: style.copyWith(
                color: context.colors.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// An annotator's glyph ([display]) as ink on the story's page: on paper
/// the app's own legible annotation colour ([nagInk]); on the dark page its
/// hue lifted until it reads there, since the board palette's deep hues
/// (the good move's blue) sit at about 2:1 on near-black.
Color storyGlyphInk(BuildContext context, NagDisplay display) {
  if (context.isLightTheme) return nagInk(context, display);
  return _liftedInk(display.color, context.colors.background);
}

/// The label's ink: the verdict's colour, legible on the page; the quiet
/// secondary ink when the position carries none.
Color storyToneInk(
  BuildContext context,
  StorySegment segment,
  StoryPuzzleOutcome? outcome,
) {
  final colors = context.colors;
  final MoveClass? moveClass = switch (segment.puzzle?.kind) {
    StoryPuzzleKind.findMissed =>
      outcome == StoryPuzzleOutcome.solved
          ? MoveClass.best
          : MoveClass.missedWin,
    _ => segment.moveClass,
  };
  final hue = moveClass == null ? null : PuzzleMoveBadge.colorOf(moveClass);
  if (hue == null) return colors.textSecondary;
  if (context.isLightTheme) return legibleHueInk(context, hue);
  return _liftedInk(hue, colors.background);
}

final Map<(int, int), Color> _liftedInks = {};

/// [hue] with its lightness raised in 0.01 steps until it reaches 4.5:1 on
/// [on]: the same hue and saturation, only lighter.
Color _liftedInk(Color hue, Color on) {
  final key = (hue.toARGB32(), on.toARGB32());
  final cached = _liftedInks[key];
  if (cached != null) return cached;
  final solidOn = on.withValues(alpha: 1);
  var hsl = HSLColor.fromColor(hue.withValues(alpha: 1));
  var ink = hsl.toColor();
  while (wcagContrast(ink, solidOn) < 4.5 && hsl.lightness < 1) {
    hsl = hsl.withLightness(math.min(1.0, hsl.lightness + 0.01));
    ink = hsl.toColor();
  }
  if (_liftedInks.length > 64) _liftedInks.clear();
  return _liftedInks[key] = ink;
}

/// The annotator's words, wrapping to [lines] lines at one size. Words that
/// run longer stay one paragraph, its last line fading downward, so the
/// shape of the paragraph holds to its end; never cut with dots or shrunk.
///
/// Whether the words run over is measured with exactly what they are drawn
/// with, and the fade sits on the last line as drawn.
class _StoryCommentText extends StatelessWidget {
  const _StoryCommentText({
    super.key,
    required this.text,
    required this.lines,
    required this.style,
  });

  final String text;
  final int lines;
  final TextStyle style;

  /// The last line's fade, from its top (whole) to its foot (gone), eased
  /// over several steps so it never reads as a band.
  static const List<double> _fadeStops = [0, 0.2, 0.4, 0.6, 0.8, 1];
  static const List<double> _fadeAlphas = [1, 0.86, 0.62, 0.36, 0.14, 0];

  @override
  Widget build(BuildContext context) {
    const align = TextAlign.start;
    final defaults = DefaultTextStyle.of(context);
    final drawn = defaults.style.merge(style);
    final direction = Directionality.of(context);
    final scaler = MediaQuery.textScalerOf(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final painter = TextPainter(
          text: TextSpan(text: text, style: drawn),
          textAlign: align,
          textDirection: direction,
          textScaler: scaler,
          maxLines: lines,
          textWidthBasis: defaults.textWidthBasis,
          textHeightBehavior: defaults.textHeightBehavior,
        )..layout(maxWidth: constraints.maxWidth);
        final runsOver = painter.didExceedMaxLines;
        final shown = runsOver ? painter.computeLineMetrics() : null;
        painter.dispose();
        final paragraph = Text(
          text,
          maxLines: lines,
          textAlign: align,
          overflow: TextOverflow.clip,
          style: drawn,
        );
        if (shown == null || shown.isEmpty) return paragraph;
        final last = shown.last;
        final lineTop = last.baseline - last.ascent;
        final lineFoot = last.baseline + last.descent;
        return ShaderMask(
          key: const ValueKey('story_comment_fade'),
          blendMode: BlendMode.dstIn,
          shaderCallback: (bounds) {
            final height = bounds.height <= 0 ? 1.0 : bounds.height;
            final top = (lineTop / height).clamp(0.0, 1.0);
            final foot = (lineFoot / height).clamp(top, 1.0);
            const ink = Color(0xFF000000);
            return LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                ink,
                for (final alpha in _fadeAlphas) ink.withValues(alpha: alpha),
              ],
              stops: [
                0,
                for (final stop in _fadeStops) top + (foot - top) * stop,
              ],
            ).createShader(bounds);
          },
          child: paragraph,
        );
      },
    );
  }
}

// ----------------------------------------------------------- the rows

/// A player's row over or under the story's board, in the board rows' own
/// style: the flag, the title in its accent, the name at one fixed size
/// fading at its end (never shrunk, never cut with dots), the rating beside
/// it, and the game's result at the row's end on the game's last move.
class StoryPlayerRow extends StatelessWidget {
  const StoryPlayerRow({
    super.key,
    required this.game,
    required this.white,
    required this.revealed,
  });

  final GamesTourModel game;
  final bool white;
  final bool revealed;

  /// Never shorter than its one line of fixed-size type, even where the
  /// page's scale runs small (a phone on its side).
  static double get height => math.max(26.sp, 24.0);

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final player = white ? game.whitePlayer : game.blackPlayer;
    final federation = player.countryCode.trim().isNotEmpty
        ? player.countryCode
        : player.federation;
    final title = player.title.trim();
    final base = AppTypography.textSmMedium.copyWith(height: 1.2);
    final status = game.gameStatus;
    final result = revealed && status.isFinished
        ? boardResultLabelForSide(game, isWhite: white)
        : null;
    final won =
        (status == GameStatus.whiteWins && white) ||
        (status == GameStatus.blackWins && !white);
    // The result reads by tone, never a bright colour: the win in the ink,
    // the draw a step quieter, the loss quieter still.
    final draw = status == GameStatus.draw;
    final resultColor = won
        ? colors.textPrimary
        : draw
        ? colors.textPrimaryMuted
        : colors.textSecondary;
    return SizedBox(
      height: height,
      child: Row(
        children: [
          if (FederationFlag.hasVisibleFlag(federation)) ...[
            FederationFlag(
              federation: federation,
              width: _atLeast(16),
              height: _atLeast(12),
              borderRadius: BorderRadius.circular(2),
            ),
            SizedBox(width: _atLeast(8)),
          ],
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: playerNameLabel(
                titlePrefix: title.isEmpty ? '' : '$title ',
                surname: player.name.trim(),
                firstName: '',
                rating: player.rating > 0 ? ' ${player.rating}' : '',
                titleStyle: base.copyWith(
                  color: colors.titleAccent,
                  fontWeight: FontWeight.w700,
                ),
                nameStyle: base.copyWith(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
                ratingStyle: base.copyWith(color: colors.textPrimaryMuted),
                textScaler: TextScaler.noScaling,
                fits: false,
                keepRating: player.rating > 0,
              ),
            ),
          ),
          SizedBox(width: _atLeast(12)),
          SizedBox(
            width: _atLeast(22),
            child: result == null
                ? null
                : Text(
                    result,
                    key: ValueKey(
                      white ? 'story_result_white' : 'story_result_black',
                    ),
                    textAlign: TextAlign.right,
                    textScaler: TextScaler.noScaling,
                    style: base.copyWith(
                      fontSize: 16.f,
                      fontWeight: won ? FontWeight.w700 : FontWeight.w600,
                      color: resultColor,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------- the actions

/// The two actions under a story, on the story's own edges: the game at
/// this position at the start, the collection (or the game's event) at the
/// end. Two words told apart by their ink, each with the same small drawn
/// arrow out, never a filled and an outlined button. Each a whole 48pt
/// target.
class StoryActions extends StatelessWidget {
  const StoryActions({
    super.key,
    required this.collectionLabel,
    required this.onOpenGame,
    required this.onOpenCollection,
  });

  final String collectionLabel;
  final VoidCallback onOpenGame;
  final VoidCallback onOpenCollection;

  /// The actions' line at the reader's text size, never under 48pt.
  static double heightOf(BuildContext context) =>
      math.max(48.0, context.textExtent(15) * 1.3 + 22);

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      children: [
        Expanded(
          child: _StoryAction(
            key: const ValueKey('story_open_game'),
            label: 'Open game',
            ink: colors.textPrimary,
            alignEnd: false,
            onTap: onOpenGame,
          ),
        ),
        SizedBox(width: _gutter),
        Expanded(
          child: _StoryAction(
            key: const ValueKey('story_view_collection'),
            label: collectionLabel,
            ink: colors.textSecondary,
            alignEnd: true,
            onTap: onOpenCollection,
          ),
        ),
      ],
    );
  }
}

class _StoryAction extends StatelessWidget {
  const _StoryAction({
    super.key,
    required this.label,
    required this.ink,
    required this.alignEnd,
    required this.onTap,
  });

  final String label;
  final Color ink;
  final bool alignEnd;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final style = AppTypography.textSmBold.copyWith(
      fontSize: 15,
      color: ink,
      height: 1.3,
    );
    final arrow = math.max(11.0, 11.sp);
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: PressSpring(
          pressedScale: 1,
          builder: (context, press, child) =>
              Opacity(opacity: 1 - 0.42 * press.clamp(0.0, 1.0), child: child),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Align(
              alignment: alignEnd
                  ? AlignmentDirectional.centerEnd
                  : AlignmentDirectional.centerStart,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.fade,
                      style: style,
                    ),
                  ),
                  SizedBox(width: math.max(6.0, 6.sp)),
                  CustomPaint(
                    size: Size.square(arrow),
                    painter: StoryArrowPainter(color: ink),
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

/// The stories' arrow out: up and to the right, its stroke and its head's
/// two arms with round caps and joins, the head a touch open.
class StoryArrowPainter extends CustomPainter {
  const StoryArrowPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.6, s * 0.15)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final inset = stroke.strokeWidth / 2 + s * 0.04;
    final tip = Offset(s - inset, inset);
    canvas.drawLine(Offset(inset, s - inset), tip, stroke);
    final head = Path()
      ..moveTo(s * 0.34, inset)
      ..lineTo(tip.dx, tip.dy)
      ..lineTo(s - inset, s * 0.66);
    canvas.drawPath(head, stroke);
  }

  @override
  bool shouldRepaint(StoryArrowPainter old) => old.color != color;
}

// ------------------------------------------------------- the other pages

/// The end of the stories when every circle has been watched: one quiet
/// line where the board stood. It holds a moment, then the viewer goes.
class StoryCaughtUp extends StatelessWidget {
  const StoryCaughtUp({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      liveRegion: true,
      child: Center(
        key: const ValueKey('story_caught_up'),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: _gutter * 2),
          child: Text(
            "You're all caught up",
            textAlign: TextAlign.center,
            style: AppTypography.textLgMedium.copyWith(
              fontSize: 19,
              color: colors.textPrimary,
              height: 1.3,
            ),
          ),
        ),
      ),
    );
  }
}

/// A story while its collection's games load: the rows, the board and the
/// words, as quiet bones in their exact places.
class StorySkeleton extends StatelessWidget {
  const StorySkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    Widget row() => SizedBox(
      height: StoryPlayerRow.height,
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: FractionallySizedBox(
          widthFactor: 0.46,
          child: Bone(height: 12.sp, borderRadius: BorderRadius.circular(6.sp)),
        ),
      ),
    );
    Widget bar(double width, double height) => Align(
      alignment: AlignmentDirectional.centerStart,
      child: FractionallySizedBox(
        widthFactor: width,
        child: Bone(
          height: height,
          borderRadius: BorderRadius.circular(height / 2),
        ),
      ),
    );
    return SkeletonWidget(
      key: const ValueKey('story_skeleton'),
      child: _StoryFrameScaffold(
        top: row(),
        bottom: row(),
        board: (side) => Bone(
          width: side,
          height: side,
          borderRadius: BorderRadius.circular(4.sp),
        ),
        words: (beside, lines) {
          final text = StoryTextMetrics.of(context);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(height: text.captionLine, child: bar(0.42, 9.sp)),
              SizedBox(height: StoryTextMetrics.captionGap),
              SizedBox(height: text.moveLine, child: bar(0.28, 14.sp)),
              SizedBox(height: text.labelLine, child: bar(0.2, 10.sp)),
            ],
          );
        },
      ),
    );
  }
}

/// The games could not be read: one short line, and a retry.
class StoryRetry extends StatelessWidget {
  const StoryRetry({super.key, required this.error, required this.onRetry});

  final Object? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      key: const ValueKey('story_retry'),
      padding: EdgeInsets.symmetric(horizontal: _gutter * 2),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            userFacingError(error, fallback: "Couldn't load these games."),
            textAlign: TextAlign.center,
            style: AppTypography.textSmMedium.copyWith(
              color: colors.textSecondary,
            ),
          ),
          SizedBox(height: 6.sp),
          GestureDetector(
            key: const ValueKey('story_retry_button'),
            behavior: HitTestBehavior.opaque,
            onTap: onRetry,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 88, minHeight: 44),
              child: Center(
                widthFactor: 1,
                child: Text(
                  'Try again',
                  style: AppTypography.textSmBold.copyWith(
                    color: colors.accentText,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StoryNotice extends StatelessWidget {
  const _StoryNotice({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    textAlign: TextAlign.center,
    style: AppTypography.textSmMedium.copyWith(
      color: context.colors.textSecondary,
    ),
  );
}
