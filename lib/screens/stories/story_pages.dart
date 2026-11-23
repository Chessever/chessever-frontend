import 'dart:async';
import 'dart:math' as math;

import 'package:chessever2/providers/board_settings_provider_new.dart';
import 'package:chessever2/screens/chessboard/classification_fx/classification_landing.dart';
import 'package:chessever2/screens/chessboard/classification_fx/move_class.dart';
import 'package:chessever2/screens/chessboard/utils/legible_ink.dart'
    show legibleHueInk;
import 'package:chessever2/screens/chessboard/widgets/chess_board_from_fen_new.dart'
    show GameCardChessboard;
import 'package:chessever2/screens/chessboard/widgets/evaluation_bar_widget.dart'
    show EvaluationBarWidget;
import 'package:chessever2/screens/chessboard/widgets/nag_display.dart'
    show NagDisplay, getNagDisplay, nagInk;
import 'package:chessever2/screens/chessboard/widgets/player_first_row_detail_widget.dart'
    show playerNameLabel;
import 'package:chessever2/screens/collections/collections_data.dart';
import 'package:chessever2/screens/feed/providers/feed_eval_provider.dart'
    show FeedEval, FeedEvalRequest, feedPositionEvalProvider;
import 'package:chessever2/screens/feed/puzzles/feed_puzzle.dart'
    show FeedPuzzleSounds;
import 'package:chessever2/screens/feed/puzzles/puzzle_widgets.dart'
    show PuzzleMoveBadge;
import 'package:chessever2/screens/feed/widgets/feed_sfx_provider.dart'
    show feedSfxProvider;
import 'package:chessever2/screens/feed/widgets/feed_glyphs.dart'
    show FeedGlyph, FeedGlyphs;
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
import 'package:flutter/semantics.dart' show SemanticsService;
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:motor/motor.dart';
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

  /// Between a question and its action's 44pt target (the plate inside it
  /// sits a few points lower still).
  static double get revealGap => _atLeast(4);

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

/// The story area's own geometry: the board and its eval bar as large as
/// the space allows, the words under it always given their room, so nothing
/// moves from one position to the next.
///
/// The eval bar stands left of the board at its full height, flush with it,
/// as on a Feed post: the two together take the width the board alone
/// would, and the player rows and the words line up with the bar's left
/// edge and the board's right one.
abstract final class StoryFrameLayout {
  /// Smallest board drawn; below it the whole story scales down instead.
  static const double minBoard = 120;

  /// Between a player's row and the board. Never under its portrait size:
  /// a phone on its side scales the page's spacing down by half.
  static double get rowGap => _atLeast(8);

  /// The eval bar's width beside a board block [span] long (the bar and the
  /// board): the Feed's own 20.w. Where the block is too short for that (a
  /// phone on its side, which .w scales up as a tablet) an eighteenth of
  /// it, but never under the 20pt its number needs to read as on the Feed.
  static double evalWidth(double span) =>
      math.min(20.w, math.max(20.0, span / 18));

  /// The eval bar's width in the story area [constraints], upright.
  static double barWidth(BoxConstraints constraints) =>
      evalWidth(constraints.maxWidth - 2 * _gutter);

  /// The board's side within [constraints] (the story area), the eval bar,
  /// the rows and the words' least room around it.
  static double boardSize(BoxConstraints constraints, StoryTextMetrics text) {
    final across = constraints.maxWidth - 2 * _gutter - barWidth(constraints);
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

  /// The story's width in the area [constraints]: the bar and the board
  /// upright; the bar, the board and the words beside them on its side. The
  /// actions under the story line up with its edges.
  static double storyWidth(BuildContext context, BoxConstraints constraints) {
    if (beside(constraints)) {
      final side = boardBeside(constraints);
      final bar = evalWidth(side);
      return bar + side + sideGap + sideWidth(constraints, side, bar);
    }
    return barWidth(constraints) +
        boardSize(constraints, StoryTextMetrics.of(context));
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
    final side = constraints.maxHeight - besideAir;
    return across - evalWidth(side) - sideGap - minSide >= side;
  }

  /// The board's side when [beside]: as tall as the area, less [besideAir].
  static double boardBeside(BoxConstraints constraints) =>
      math.max(minBoard, constraints.maxHeight - besideAir).floorToDouble();

  /// The width of the words beside a board of [board] and its bar [bar].
  static double sideWidth(
    BoxConstraints constraints,
    double board,
    double bar,
  ) {
    final across = constraints.maxWidth - 2 * _gutter;
    return math.min(maxSide, across - bar - board - sideGap).floorToDouble();
  }
}

/// A story position's arrangement, one for the story and its skeleton so
/// nothing moves when the games land. Upright: the players over and under
/// the board, the words below it in their full room. On its side: the
/// board as tall as the space, the players beside it level with its top and
/// bottom edges, the words between them. The eval bar is part of the board
/// block either way.
class _StoryFrameScaffold extends StatelessWidget {
  const _StoryFrameScaffold({
    required this.board,
    required this.top,
    required this.bottom,
    required this.words,
  });

  /// The board block: the eval bar [bar] wide and the board [side] square,
  /// side by side, [side] tall.
  final Widget Function(double side, double bar) board;

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
          final bar = StoryFrameLayout.evalWidth(side);
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
              SizedBox(
                width: bar + side,
                height: side,
                child: board(side, bar),
              ),
              SizedBox(width: StoryFrameLayout.sideGap),
              SizedBox(
                width: StoryFrameLayout.sideWidth(constraints, side, bar),
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
        final bar = StoryFrameLayout.barWidth(constraints);
        final lines = StoryFrameLayout.commentLines(constraints, side, text);
        return FittedBox(
          fit: BoxFit.scaleDown,
          child: SizedBox(
            width: bar + side,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                top,
                SizedBox(height: StoryFrameLayout.rowGap),
                SizedBox(height: side, child: board(side, bar)),
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

  /// They asked to see it, after a try or two or none.
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

  /// The position [frameId] was answered: the story runs on, over [hold]
  /// when it is longer than the position's own reading time (the answer
  /// landing and the line after it playing out), so the reader enjoys it
  /// before it moves on; a tap moves on sooner.
  void settle(String frameId, StoryPuzzleOutcome outcome, {Duration? hold});

  /// The board taking a move, on screen; null when none does.
  ValueNotifier<Rect?> get zone;

  /// A finger came down on [frameId]'s board: [takes] when the touch is the
  /// board's ([storyBoardTap]), false when it is the story's, a tap that
  /// moves on like one anywhere else on the page. The board hears a touch
  /// before the viewer does, so this arrives first.
  void boardTouch(String frameId, {required bool takes});
}

/// What a touch on [square] of a board asking for a move is, as the board
/// itself handles it (tap two squares, no premoves):
///
/// * the board's when it picks up a piece of the side to move; with a
///   piece up ([selected]), any touch is the board's: it plays the piece to
///   a legal square, puts it down, or picks up another; so is the touch
///   that answers a promotion's choice ([promoting]);
/// * the story's otherwise: an empty square or an opponent's piece with
///   nothing picked up moves the story on, exactly as a tap anywhere else.
///
/// Returns that, and what is picked up and whether a promotion's choice is
/// open after the touch, for the next one.
({bool takes, Square? selected, bool promoting}) storyBoardTap(
  Square square, {
  required Position position,
  required ValidMoves validMoves,
  Square? selected,
  bool promoting = false,
}) {
  if (promoting) return (takes: true, selected: null, promoting: false);
  final piece = position.board.pieceAt(square);
  final own = piece != null && piece.color == position.turn;
  if (selected != null) {
    if (square == selected) {
      return (takes: true, selected: null, promoting: false);
    }
    if (validMoves[selected]?.contains(square) ?? false) {
      final pawn = position.board.roleAt(selected) == Role.pawn;
      final last = square.rank == Rank.first || square.rank == Rank.eighth;
      return (takes: true, selected: null, promoting: pawn && last);
    }
    return (takes: true, selected: own ? square : null, promoting: false);
  }
  if (own) return (takes: true, selected: square, promoting: false);
  return (takes: false, selected: null, promoting: false);
}

/// A story puzzle's sounds: the Feed puzzle's own ([FeedPuzzleSounds]: the
/// board's move sounds, the classified move's sound in their place when the
/// move is judged), so a puzzle sounds the same in a story as in the Feed,
/// and a warm-up of the classified sounds before the first answer. Every
/// call is fire-and-forget.
class StoryPuzzleSounds extends FeedPuzzleSounds {
  StoryPuzzleSounds({bool Function()? silent, Future<void> Function()? warmUp})
    : _silent = silent,
      _warm = warmUp,
      super(isSilent: silent);

  final bool Function()? _silent;
  final Future<void> Function()? _warm;

  /// Loads the classified sounds, unless silent, so the first answer's
  /// sound never waits on a decode.
  void warmUp() {
    final warm = _warm;
    if (warm == null || (_silent?.call() ?? false)) return;
    unawaited(warm().catchError((Object _) {}));
  }
}

/// Where a story puzzle's sounds go. Silent when the board's Sound setting
/// is off, read here (stories open from Today, where the Feed's own copy of
/// it may not be read yet), or the Feed's speaker is muted. Tests hand in a
/// recorder.
final storyPuzzleSoundsProvider = Provider<StoryPuzzleSounds>(
  (ref) => StoryPuzzleSounds(
    silent: () {
      final on =
          ref.read(boardSettingsProviderNew).valueOrNull?.soundEnabled == true;
      return !on || ref.read(feedSfxProvider).muted;
    },
    warmUp: () => ref.read(feedSfxProvider).warmUp(),
  ),
);

/// The eval bar's number for [position] as a Feed post reads its board,
/// before any cache is asked: a finished position speaks for itself (mate,
/// or a drawn end, scored as the board screen scores them), then what the
/// game's PGN records for it ([recorded]). Null when neither says: the bar
/// then asks the eval cache, as the Feed does while a clip plays, and never
/// the engine.
FeedEval? storyRecordedEval(Position? position, StoryEval? recorded) {
  if (position == null) return FeedEval.none;
  if (position.isCheckmate) {
    return FeedEval(pawns: position.turn == Side.white ? -100 : 100);
  }
  if (position.isGameOver) return const FeedEval(pawns: 0);
  if (recorded == null) return null;
  final mate = recorded.mate;
  if (mate != null && mate != 0) return FeedEval(mate: mate);
  final cp = recorded.cp;
  return cp == null ? null : FeedEval(pawns: cp / 100);
}

/// What the bar is filled with for [eval], as the Feed's post fills it:
/// pawns, or ±10 for a mate so the bar fills and reads "#N".
double? storyBarEvaluation(FeedEval eval) {
  final mate = eval.mate;
  if (mate != null && mate != 0) return mate > 0 ? 10.0 : -10.0;
  return eval.pawns;
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
    CollectionKind.book || CollectionKind.analysis => 'View collection',
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
  /// Waiting for the reader's move: the question, the reader thinking (a
  /// piece in hand, the story's bar held), and again once a miss has gone
  /// back.
  prompt,

  /// A move that was not it stands for a beat with its mark, then goes
  /// back, and the reader tries again.
  wrong,

  /// The reader found it.
  found,

  /// The answer was shown.
  revealed,
}

/// How a position that asks for a move reads at a glance: the words under
/// it follow this.
enum StoryPuzzleState {
  /// The question: who is to move, or what was missed. The reader thinks
  /// on it while the story waits.
  prompt,

  /// A move that was not it; the reader tries again.
  missed,

  /// The reader found it.
  found,

  /// The answer, shown.
  revealed,
}

/// How the reader's move marks the board: the board's own last-move
/// highlight, in a tone.
enum _Tint { none, found, missed }

/// One key position: the board at the moment (the move just played sliding
/// in, its arrows and marked squares, the verdict's badge), the players,
/// and the words under it, readable at once.
///
/// A position that asks for a move shows the position before it first, the
/// board taking the reader's move ([StoryPuzzleHost]); the story waits.
/// Found, the move lands with the Feed puzzle's solve (its sound and
/// haptic), its square in the found tone and its badge, the words say so
/// and the board plays on through the line that follows. Another move lands
/// in the missed tone with the Feed puzzle's miss, goes back, and the
/// reader tries again; after two, Show is the way on. Show reveals the
/// answer the same way, as shown.
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
  /// A move that was not it stands this long, then goes back: the Feed
  /// puzzle's beat (its `_wrongHold`, 520ms).
  static const Duration _wrongHold = Duration(milliseconds: 520);

  /// From the answer landing to the first move of the line after it: long
  /// enough for the answer's mark to land and be read.
  static const Duration _lineLead = Duration(milliseconds: 1000);

  /// Between the line's moves: the story's own pace, a step quicker than
  /// the Feed puzzle's reveal (750ms), since the story's bar runs meanwhile
  /// and holds the position for the whole line ([_answerHold]).
  static const Duration _lineStep = Duration(milliseconds: 700);

  /// What the story adds to a position's reading time once it is answered,
  /// so the find (or the answer) is enjoyed before it moves on.
  static const Duration _answerBeat = Duration(milliseconds: 1200);

  late bool _landed;

  ChessboardController? _board;
  _Phase _phase = _Phase.prompt;
  StoryPuzzleOutcome? _outcome;
  _Tint _tint = _Tint.none;
  Square? _markSquare;
  MoveClass? _markClass;

  /// Changes once per piece landing on [_markSquare]: the board settles it.
  int _markSeq = 0;

  /// Changes once per landing worth the class's own gesture
  /// ([ClassificationLanding]): a find or a miss, never a shown answer.
  int _landingSeq = 0;
  Timer? _timer;
  final GlobalKey _boardKey = GlobalKey(debugLabel: 'story_puzzle_board');

  /// What the board has picked up, and whether a promotion's choice is
  /// open, as [storyBoardTap] follows it from touch to touch.
  Square? _selected;
  bool _promoting = false;

  /// Moves tried that were not it.
  int _misses = 0;

  /// The last of them was the move the game played (a missed win's): the
  /// words say so and the bar shows what the game recorded for it.
  bool _missedPlayed = false;

  /// The move that was not it, while it stands on the board.
  String? _wrongFen;
  Move? _wrongMove;

  /// How many moves of the line after the answer are on the board, and
  /// whether more are still to play.
  int _linePly = 0;
  bool _linePending = false;

  StorySegment get _segment => widget.frame.position;
  StoryPuzzle? get _puzzle => _segment.puzzle;

  /// The board takes a move.
  bool get _asking =>
      _puzzle != null && _phase == _Phase.prompt && widget.active;

  /// The story waits on the reader: a question not yet answered, a miss
  /// standing included.
  bool get _waiting =>
      _puzzle != null &&
      (_phase == _Phase.prompt || _phase == _Phase.wrong) &&
      widget.active;

  bool get _answered => _phase == _Phase.found || _phase == _Phase.revealed;

  @override
  void initState() {
    super.initState();
    _landed = widget.progress.value >= kStorySlideAt;
    widget.progress.addListener(_onProgress);
    final puzzle = _puzzle;
    if (puzzle != null) {
      // Back on a position answered before: its answer, as it was found or
      // shown, at rest.
      _outcome = widget.puzzles?.outcomeOf(widget.frame.id);
      _phase = switch (_outcome) {
        StoryPuzzleOutcome.solved => _Phase.found,
        StoryPuzzleOutcome.shown => _Phase.revealed,
        null => _Phase.prompt,
      };
      if (_phase == _Phase.found) _tint = _Tint.found;
      _board = ChessboardController(game: _boardData());
      if (_answered) _markAnswer(settle: false, celebrate: false);
      _afterFrame(_report);
      if (_asking) _warmSounds();
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
      _selected = null;
      _promoting = false;
      widget.active ? _resumeBeats() : _pauseBeats();
      if (_asking) _warmSounds();
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
    host.prompting(widget.frame.id, _waiting);
    final box = _boardKey.currentContext?.findRenderObject();
    if (_waiting && box is RenderBox && box.attached && box.hasSize) {
      _zoneRect = box.localToGlobal(Offset.zero) & box.size;
      _publishedZone = true;
      host.zone.value = _zoneRect;
    } else if (_publishedZone) {
      if (host.zone.value == _zoneRect) host.zone.value = null;
      _publishedZone = false;
    }
  }

  /// The face turned away: a beat that is running (a miss standing, the
  /// line after an answer) holds where it stands, since a face turning
  /// away keeps its frame while it is still on screen, and picks up again
  /// once the face is back in view.
  void _pauseBeats() {
    _timer?.cancel();
    _timer = null;
  }

  void _resumeBeats() {
    if (_timer != null) return;
    if (_phase == _Phase.wrong) {
      _timer = Timer(_wrongHold, _takeBack);
    } else if (_answered && _linePending) {
      _timer = Timer(_linePly == 0 ? _lineLead : _lineStep, _playLine);
    }
  }

  Position? _before() => _positionOf(_segment.fenBefore);

  /// The board at [fen] after [lastMove], taking nothing.
  GameData _still(String fen, Move? lastMove) {
    final position = _positionOf(fen);
    return GameData(
      fen: fen,
      lastMove: lastMove,
      playerSide: PlayerSide.none,
      sideToMove: position?.turn ?? _turnOf(fen),
      validMoves: const {},
      kingSquareInCheck: position != null && position.isCheck
          ? position.board.kingOf(position.turn)
          : null,
    );
  }

  /// What the board shows for where the position stands: the question
  /// (taking the reader's move while it is theirs), a miss standing, the
  /// answer, or the line after it as far as it has played.
  GameData _boardData() {
    final puzzle = _puzzle!;
    switch (_phase) {
      case _Phase.found:
      case _Phase.revealed:
        if (_linePly > 0 && _linePly <= puzzle.followUp.length) {
          final ply = puzzle.followUp[_linePly - 1];
          return _still(ply.fenAfter, ply.move);
        }
        return _still(puzzle.answerFen, puzzle.answer);
      case _Phase.wrong:
        final fen = _wrongFen;
        if (fen != null) return _still(fen, _wrongMove);
      case _Phase.prompt:
        break;
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
  static bool _answers(Position position, Move move, StoryPuzzle puzzle) =>
      _sameMove(position, move, puzzle.answer);

  /// Whether [a] and [b] are one move in [position], castling either way it
  /// can be entered.
  static bool _sameMove(Position position, Move a, Move b) {
    Move normal(Move m) =>
        m is NormalMove && position.isLegal(m) ? position.normalizeMove(m) : m;
    return normal(a).uci == normal(b).uci;
  }

  /// A finger on the board: the board's when it plays the puzzle, the
  /// story's otherwise ([storyBoardTap]). Told to the viewer, which hears
  /// the same touch next. A finger back on the board while a miss stands
  /// takes it back at once, so a quick second try is never held up, and
  /// never moves the story on.
  void _onTouchedSquare(Square square) {
    final host = widget.puzzles;
    if (_phase == _Phase.wrong && widget.active) {
      _takeBack();
      // The board goes on to handle this same touch on the position given
      // back, so a piece of the reader's under the finger is now picked up:
      // follow it as the board does, or the next touch (the piece's move)
      // would read as the story's and move it on.
      final position = _before();
      if (_asking && position != null) {
        final tap = storyBoardTap(
          square,
          position: position,
          validMoves: makeLegalMoves(position),
        );
        _selected = tap.selected;
        _promoting = tap.promoting;
      }
      host?.boardTouch(widget.frame.id, takes: true);
      return;
    }
    final position = _before();
    if (!_asking || position == null) {
      host?.boardTouch(widget.frame.id, takes: false);
      return;
    }
    final tap = storyBoardTap(
      square,
      position: position,
      validMoves: makeLegalMoves(position),
      selected: _selected,
      promoting: _promoting,
    );
    _selected = tap.selected;
    _promoting = tap.promoting;
    host?.boardTouch(widget.frame.id, takes: tap.takes);
  }

  void _onMove(Move move, {bool? viaDragAndDrop}) {
    _selected = null;
    _promoting = false;
    final puzzle = _puzzle;
    final position = _before();
    if (puzzle == null || _board == null || position == null || !_asking) {
      return;
    }
    if (!position.isLegal(move)) return;
    if (_answers(position, move, puzzle)) {
      _find();
    } else {
      _miss(position, move);
    }
  }

  /// The reader found it: the Feed puzzle's solve, the square in the found
  /// tone with the move's badge, the words saying so, then the line.
  void _find() {
    final puzzle = _puzzle!;
    _timer?.cancel();
    setState(() {
      _phase = _Phase.found;
      _outcome = StoryPuzzleOutcome.solved;
      _tint = _Tint.found;
      _linePly = 0;
      _markAnswer(settle: true, celebrate: true);
    });
    _board?.updatePosition(_boardData());
    _sound(puzzle.answerSan, MoveClass.brilliant);
    unawaited(HapticFeedbackService.success());
    widget.puzzles?.settle(
      widget.frame.id,
      StoryPuzzleOutcome.solved,
      hold: _answerHold(),
    );
    _announce('You found it: $_spokenAnswer.');
    _afterFrame(_report);
    _scheduleLine();
  }

  /// A move that was not it: it lands in the missed tone with the Feed
  /// puzzle's miss, stands a beat, and goes back for another try. The move
  /// the game played is named as that.
  void _miss(Position position, Move move) {
    final puzzle = _puzzle!;
    final (after, san) = position.makeSan(move);
    final played = _segment.move;
    final isPlayed =
        puzzle.kind == StoryPuzzleKind.findMissed &&
        played != null &&
        _sameMove(position, move, played);
    _timer?.cancel();
    setState(() {
      _phase = _Phase.wrong;
      _misses++;
      _missedPlayed = isPlayed;
      _wrongFen = after.fen;
      _wrongMove = move;
      _tint = _Tint.missed;
      if (move is NormalMove && !_isCastle(move)) {
        _markSquare = move.to;
        _markClass = isPlayed ? MoveClass.missedWin : MoveClass.mistake;
        _markSeq++;
        _landingSeq++;
      } else {
        _clearMark();
      }
    });
    _board?.updatePosition(_boardData());
    _sound(san, MoveClass.mistake);
    unawaited(HapticFeedbackService.medium());
    _announce(
      isPlayed
          ? 'That was played in the game. Try again.'
          : 'Not this one. Try again.',
    );
    _afterFrame(_report);
    _timer = Timer(_wrongHold, _takeBack);
  }

  /// The miss goes back: the board is the reader's again.
  void _takeBack() {
    _timer?.cancel();
    _timer = null;
    if (!mounted || _phase != _Phase.wrong) return;
    setState(() {
      _phase = _Phase.prompt;
      _tint = _Tint.none;
      _wrongFen = null;
      _wrongMove = null;
      _clearMark();
    });
    _board?.updatePosition(_boardData());
    _afterFrame(_report);
  }

  /// The reader asked to see the answer: it lands as a find does, as shown.
  void _show() {
    if (!_waiting) return;
    final puzzle = _puzzle!;
    unawaited(HapticFeedbackService.buttonPress());
    _timer?.cancel();
    _selected = null;
    _promoting = false;
    setState(() {
      _phase = _Phase.revealed;
      _outcome = StoryPuzzleOutcome.shown;
      _tint = _Tint.none;
      _linePly = 0;
      _wrongFen = null;
      _wrongMove = null;
      _markAnswer(settle: true, celebrate: false);
    });
    _board?.updatePosition(_boardData());
    _sound(puzzle.answerSan);
    widget.puzzles?.settle(
      widget.frame.id,
      StoryPuzzleOutcome.shown,
      hold: _answerHold(),
    );
    _announce('${puzzle.answerNoun}: $_spokenAnswer.');
    _afterFrame(_report);
    _scheduleLine();
  }

  /// How long the story holds an answered position: its reading time, a
  /// beat to enjoy the answer, and the line playing out.
  Duration _answerHold() {
    final plies = _puzzle?.followUp.length ?? 0;
    final line = plies == 0
        ? Duration.zero
        : _lineLead + _lineStep * (plies - 1);
    return storySegmentDuration(_segment) + _answerBeat + line;
  }

  /// The line after the answer, a move at a time, once the answer has
  /// landed and been read.
  void _scheduleLine() {
    _linePending = false;
    if (_puzzle?.followUp.isEmpty ?? true) return;
    _linePending = true;
    _timer?.cancel();
    _timer = Timer(_lineLead, _playLine);
  }

  void _playLine() {
    _timer = null;
    final plies = _puzzle?.followUp ?? const <StoryLinePly>[];
    if (!mounted || !_answered || _linePly >= plies.length) {
      _linePending = false;
      return;
    }
    final ply = plies[_linePly];
    setState(() {
      _linePly++;
      // The mark is the answer's: the line plays on the board's own
      // highlight.
      _tint = _Tint.none;
      _clearMark();
    });
    _board?.updatePosition(_boardData());
    _sound(ply.san);
    if (_linePly < plies.length) {
      _timer = Timer(_lineStep, _playLine);
    } else {
      _linePending = false;
    }
  }

  /// The answer's square and badge: the move's own verdict for a strong
  /// move found or shown, the best move for a missed win's. [settle] lets
  /// the piece settle on it; [celebrate] plays its class's landing.
  void _markAnswer({required bool settle, required bool celebrate}) {
    final puzzle = _puzzle!;
    final answer = puzzle.answer;
    if (answer is! NormalMove || _isCastle(answer)) {
      _clearMark();
      return;
    }
    _markSquare = answer.to;
    _markClass = puzzle.kind == StoryPuzzleKind.findPlayed
        ? (_segment.moveClass ?? MoveClass.best)
        : MoveClass.best;
    if (settle) _markSeq++;
    if (celebrate) _landingSeq++;
  }

  void _clearMark() {
    _markSquare = null;
    _markClass = null;
  }

  /// A castling move lands its badge on no one square: none is drawn.
  bool _isCastle(NormalMove move) =>
      _before()?.board.roleAt(move.from) == Role.king &&
      (move.from.file - move.to.file).abs() > 1;

  /// The answer as a screen reader says it ("5… Qxg2").
  String get _spokenAnswer => '${_segment.number} ${_puzzle!.answerSan}';

  /// The classified sounds loaded while the reader thinks, once.
  void _warmSounds() {
    if (_soundsWarmed) return;
    _soundsWarmed = true;
    try {
      ref.read(storyPuzzleSoundsProvider).warmUp();
    } catch (error) {
      debugPrint('[Stories] sound warm-up failed: $error');
    }
  }

  bool _soundsWarmed = false;

  /// A puzzle sound, for the face in view only; a failure never reaches
  /// the board.
  void _sound(String san, [MoveClass? moveClass]) {
    if (!widget.active) return;
    try {
      ref.read(storyPuzzleSoundsProvider).move(san: san, moveClass: moveClass);
    } catch (error) {
      debugPrint('[Stories] sound failed: $error');
    }
  }

  /// Tells a screen reader what just happened, where the platform takes an
  /// announcement; elsewhere the words' headline is a live region
  /// ([StoryMomentText]) and speaks for itself.
  void _announce(String message) {
    if (!mounted || !widget.active) return;
    if (!(MediaQuery.maybeSupportsAnnounceOf(context) ?? false)) return;
    final view = View.maybeOf(context);
    if (view == null) return;
    unawaited(
      SemanticsService.sendAnnouncement(
        view,
        message,
        Directionality.of(context),
      ).catchError((Object _) {}),
    );
  }

  StoryPuzzleState? get _puzzleState {
    if (_puzzle == null) return null;
    return switch (_phase) {
      _Phase.prompt =>
        _misses > 0 ? StoryPuzzleState.missed : StoryPuzzleState.prompt,
      _Phase.wrong => StoryPuzzleState.missed,
      _Phase.found => StoryPuzzleState.found,
      _Phase.revealed => StoryPuzzleState.revealed,
    };
  }

  // ------------------------------------------------------------ build

  Side get _orientation => _puzzle?.solver ?? Side.white;

  @override
  Widget build(BuildContext context) {
    final game = widget.frame.game.game;
    final orientation = _orientation;
    final shown = _watchShownEval();
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
      board: (side, bar) => Row(
        children: [
          _evalBar(bar, side, orientation, shown),
          if (_puzzle == null)
            _stillBoard(side, game)
          else
            _puzzleBoard(side, orientation),
        ],
      ),
      words: (beside, lines) => StoryMomentText(
        key: const ValueKey('story_words'),
        segment: _segment,
        caption: widget.frame.game.caption,
        lines: lines,
        puzzleState: _puzzleState,
        misses: _misses,
        missedPlayed: _missedPlayed,
        onShow: _waiting ? _show : null,
      ),
    );
  }

  // ------------------------------------------------------------ eval bar

  /// The position the board shows and what the game records for it: before
  /// the move, then after it once it has slid in; for a question, the
  /// position asked, then the answer (held while the line after it plays).
  /// A miss stands for a beat only: the bar keeps to the question unless
  /// the miss is the move the game played, whose evaluation it recorded.
  (String, StoryEval?) _shownPosition() {
    final segment = _segment;
    final puzzle = _puzzle;
    if (puzzle == null) {
      return _landed || segment.isStill
          ? (segment.fenAfter, segment.evalAfter)
          : (segment.fenBefore, segment.evalBefore);
    }
    return switch (_phase) {
      _Phase.found || _Phase.revealed => (puzzle.answerFen, puzzle.answerEval),
      _Phase.wrong when _missedPlayed => (segment.fenAfter, segment.evalAfter),
      _ => (segment.fenBefore, segment.evalBefore),
    };
  }

  String? _parsedFen;
  Position? _parsed;

  Position? _positionOf(String fen) {
    if (fen == _parsedFen) return _parsed;
    _parsedFen = fen;
    try {
      return _parsed = Position.setupPosition(Rule.chess, Setup.parseFen(fen));
    } catch (_) {
      return _parsed = null;
    }
  }

  /// The number for the position on the board, as a Feed post at rest
  /// reads it: what the game recorded for it; else, for the face in view
  /// only, the eval cache and then the engine (a story position stands
  /// still, like a paused post, so a won position never shows a false
  /// level bar; the engine stays off in debug builds by its own switch).
  /// Faces out of view ask nothing, as on the Feed. Read in [build], never
  /// in the layout callback the bar is placed from, so the subscription
  /// lives with the page.
  ({String fen, Position? position, FeedEval eval}) _watchShownEval() {
    final (fen, recorded) = _shownPosition();
    final position = _positionOf(fen);
    final eval =
        storyRecordedEval(position, recorded) ??
        (!widget.active
            ? FeedEval.none
            : ref
                      .watch(
                        feedPositionEvalProvider(
                          FeedEvalRequest(fen, allowEngine: true),
                        ),
                      )
                      .valueOrNull ??
                  FeedEval.pending);
    return (fen: fen, position: position, eval: eval);
  }

  /// The Feed post's eval bar, left of the board at its full height: the
  /// same widget, size and spring, filled from White's side (flipped with
  /// a board turned for Black), showing [shown] ([_watchShownEval]).
  Widget _evalBar(
    double width,
    double side,
    Side orientation,
    ({String fen, Position? position, FeedEval eval}) shown,
  ) {
    final (:fen, :position, :eval) = shown;
    return EvaluationBarWidget(
      key: const ValueKey('story_eval_bar'),
      width: width,
      height: side,
      isFlipped: orientation == Side.black,
      evaluation: storyBarEvaluation(eval),
      mate: eval.mate,
      isEvaluating: eval.evaluating,
      isWhiteToMove: position?.turn != Side.black,
      positionKey: position?.fen ?? fen,
      // "#", as the Feed's bar says, not the ±100 it is filled with.
      isCheckmate: position?.isCheckmate ?? false,
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

  /// The board's colours with the reader's move in its tone: the board's
  /// own last-move highlight, found in the best move's green, missed in the
  /// mistake's amber, each see-through so the square's own light or dark
  /// still reads under it. No glow: a square, as the board marks squares.
  static final Map<(ChessboardColorScheme, _Tint), ChessboardColorScheme>
  _tintedSchemes = {};

  static ChessboardColorScheme _tinted(
    ChessboardColorScheme scheme,
    _Tint tint,
  ) {
    if (tint == _Tint.none) return scheme;
    if (_tintedSchemes.length > 32) _tintedSchemes.clear();
    return _tintedSchemes.putIfAbsent(
      (scheme, tint),
      () => scheme.copyWith(
        lastMove: HighlightDetails(
          solidColor: storyTintOf(tint == _Tint.found),
        ),
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
    if (_waiting) _afterFrame(_report);
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
              colorScheme: _tinted(settings.colorScheme, _tint),
              pieceAssets: settings.pieceAssets,
            ),
            // The annotator's arrows are the answer's: they go once the
            // line after it plays on.
            shapes: _answered && _linePly == 0 ? _segment.shapes : const {},
            landingSquare: markClass != null ? markSquare : null,
            landingKey: markClass != null ? _markSeq : null,
            onMove: _onMove,
            onTouchedSquare: _onTouchedSquare,
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
                trigger: _landingSeq,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The see-through tone a puzzle's move marks its squares with, over the
/// board's own last-move highlight: [found] in the best move's green, else
/// the mistake's amber, a step quieter.
Color storyTintOf(bool found) => found
    ? PuzzleMoveBadge.colorOf(MoveClass.best)!.withValues(alpha: 0.55)
    : PuzzleMoveBadge.colorOf(MoveClass.mistake)!.withValues(alpha: 0.45);

/// The words under a position, start-aligned on the board block's edge, in
/// a room that never changes size:
///
/// * the game's line (event, opening);
/// * the move, its number a step quieter and its glyphs in the app's
///   annotation colours;
/// * why it matters, in the verdict's colour ("Brilliant", "Missed win");
/// * the book's words, wrapping to [lines] lines and fading at their end.
///
/// No evaluation is put in words: the eval bar beside the board carries it.
///
/// A position that asks for a move reads by where it stands
/// ([puzzleState]), its headline springing up into its line at each step:
///
/// * the question in one line ("White to move", "Black missed a win
///   here"), its one action right under it ([StoryRevealButton], "Show the
///   win");
/// * a miss: "Not this one · try again", or "Played in the game · try
///   again" for the move the game played ([storyMissWords]); after
///   [showAfterMisses] misses Show turns solid, the way on;
/// * found: "You found it · 5… Qxg2", what the game did under it, then the
///   line after it;
/// * shown: "The win · 5… Qxg2", read the same way.
class StoryMomentText extends StatelessWidget {
  const StoryMomentText({
    super.key,
    required this.segment,
    required this.lines,
    this.caption,
    this.puzzleState,
    this.misses = 0,
    this.missedPlayed = false,
    this.onShow,
  });

  final StorySegment segment;
  final String? caption;
  final int lines;

  /// Where the position's question stands; null reads as the question on a
  /// position that asks one.
  final StoryPuzzleState? puzzleState;

  /// Moves tried that were not it.
  final int misses;

  /// The last of them was the move the game played.
  final bool missedPlayed;

  /// Reveals the answer without (another) try; null hides the action.
  final VoidCallback? onShow;

  /// After this many misses Show is the emphasised next step.
  static const int showAfterMisses = 2;

  @override
  Widget build(BuildContext context) {
    final text = StoryTextMetrics.of(context);
    final puzzle = segment.puzzle;
    final state = puzzle == null
        ? null
        : (puzzleState ?? StoryPuzzleState.prompt);
    final asking =
        state == StoryPuzzleState.prompt || state == StoryPuzzleState.missed;
    final Widget moveLine;
    Widget labelLine = const SizedBox();
    String? comment;
    String? label;
    if (puzzle != null && asking) {
      moveLine = _askLine(context, text, puzzle, state!);
    } else {
      moveLine = _moveLine(context, text, puzzle, state);
      label = _labelOf(segment, state);
      if (label != null) {
        labelLine = Text(
          label,
          key: const ValueKey('story_label'),
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.fade,
          style: text.labelStyle.copyWith(
            color: storyToneInk(context, segment, state),
          ),
        );
      }
      comment = _commentOf(segment);
    }
    // A question has no label line: its action stands under it instead.
    final hasLabel = !asking && (puzzle != null || label != null);
    // Without a label the words begin on its line: the room stays the same.
    final commentLines = lines + (hasLabel ? 0 : 1);
    final commentHeight =
        text.box(lines) -
        text.captionLine -
        StoryTextMetrics.captionGap -
        text.moveLine -
        (hasLabel ? text.labelLine + StoryTextMetrics.commentGap : 0);
    final show = onShow;
    // Where the platform takes no announcement, the headline is a live
    // region: each step of a question speaks as it lands.
    final live =
        puzzle != null &&
        !(MediaQuery.maybeSupportsAnnounceOf(context) ?? false);
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
            child: Semantics(
              liveRegion: live,
              child: StorySpringIn(
                id: (state, misses, missedPlayed),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: moveLine,
                ),
              ),
            ),
          ),
          if (hasLabel) ...[
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
            child: puzzle != null && asking
                ? (show == null
                      ? null
                      : Align(
                          alignment: AlignmentDirectional.topStart,
                          child: Padding(
                            padding: EdgeInsets.only(
                              top: StoryTextMetrics.revealGap,
                            ),
                            child: StoryRevealButton(
                              label: puzzle.reveal,
                              onTap: show,
                              emphasised: misses >= showAfterMisses,
                            ),
                          ),
                        ))
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

  /// The question's line: the question, or a miss in the missed tone.
  Widget _askLine(
    BuildContext context,
    StoryTextMetrics text,
    StoryPuzzle puzzle,
    StoryPuzzleState state,
  ) {
    if (state == StoryPuzzleState.prompt) {
      return Text(
        puzzle.prompt,
        key: const ValueKey('story_prompt'),
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.fade,
        style: text.moveStyle,
      );
    }
    final (lead, rest) = storyMissWords(misses: misses, played: missedPlayed);
    return Text.rich(
      TextSpan(
        style: text.moveStyle,
        children: [
          TextSpan(
            text: lead,
            style: text.moveStyle.copyWith(
              color: storyStateInk(context, found: false),
            ),
          ),
          if (rest != null)
            TextSpan(
              text: rest,
              style: text.moveStyle.copyWith(
                color: context.colors.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
        ],
      ),
      key: const ValueKey('story_missed'),
      maxLines: 1,
      softWrap: false,
      overflow: TextOverflow.fade,
    );
  }

  /// The move: the one played, or a question's answer once it is found
  /// ("You found it · 5… Qxg2", in the found tone) or shown ("The win ·
  /// 5… Qxg2", quiet).
  Widget _moveLine(
    BuildContext context,
    StoryTextMetrics text,
    StoryPuzzle? puzzle,
    StoryPuzzleState? state,
  ) {
    final colors = context.colors;
    final quiet = text.moveStyle.copyWith(
      color: colors.textSecondary,
      fontWeight: FontWeight.w600,
    );
    final (number, san, nags) = puzzle != null
        ? (
            segment.number,
            puzzle.answerSan,
            puzzle.kind == StoryPuzzleKind.findPlayed
                ? storyAnswerNags(segment)
                : const <int>[],
          )
        : (segment.isStill ? null : segment.number, segment.san, segment.nags);
    if (san == null) return const SizedBox();
    final found = state == StoryPuzzleState.found;
    final lead = switch (state) {
      StoryPuzzleState.found => 'You found it',
      StoryPuzzleState.revealed => puzzle?.answerNoun,
      _ => null,
    };
    return Text.rich(
      TextSpan(
        style: text.moveStyle,
        children: [
          if (lead != null) ...[
            TextSpan(
              text: lead,
              style: found
                  ? text.moveStyle.copyWith(
                      color: storyStateInk(context, found: true),
                    )
                  : quiet,
            ),
            TextSpan(text: ' · ', style: quiet),
          ],
          if (number != null) TextSpan(text: '$number ', style: quiet),
          TextSpan(text: san),
          for (final nag in nags)
            if (getNagDisplay(nag) case final display?)
              TextSpan(
                text: display.isQuality ? display.symbol : ' ${display.symbol}',
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
  }

  /// Why it matters; for a question once answered, what the game did (a
  /// missed win's move) or what the move is ("Brilliant").
  static String? _labelOf(StorySegment s, StoryPuzzleState? state) {
    final puzzle = s.puzzle;
    if (puzzle == null) return s.label;
    final san = s.san;
    if (puzzle.kind == StoryPuzzleKind.findMissed) {
      if (state == StoryPuzzleState.found) {
        return san == null
            ? 'The game missed it'
            : '$san was played in the game';
      }
      return san == null ? 'Missed win' : 'Missed win · $san was played';
    }
    return s.label ?? 'Strongest move';
  }

  /// The words under the label: the book's, and for a missed win how the
  /// win goes on past the move the headline already shows ("Then 61… Re8
  /// 62. Kc5"), as the board plays it.
  static String? _commentOf(StorySegment s) {
    final rest = s.puzzle?.continuation?.trim();
    final words = s.comment;
    if (rest == null || rest.isEmpty) return words;
    final shown = 'Then $rest';
    return words == null ? shown : '$words $shown';
  }
}

/// What a miss says: the move the game played named as that, ties the try
/// to the story; else a gentle "Not this one". While the board still asks
/// for a try (before [StoryMomentText.showAfterMisses] misses) each carries
/// the nudge to try again, the game's move as much as any; after that Show
/// is the way on, and the words just say what it was ("either").
(String, String?) storyMissWords({required int misses, required bool played}) {
  final nudge = misses < StoryMomentText.showAfterMisses;
  if (played) {
    return nudge
        ? ('Played in the game', ' · try again')
        : ('That was played in the game', null);
  }
  if (!nudge) return ('Not this one either', null);
  return ('Not this one', ' · try again');
}

/// The glyphs a strong move's answer reads with: the annotator's, else its
/// verdict's own ("!!" for a brilliancy, "!" for a great move).
List<int> storyAnswerNags(StorySegment segment) {
  final nags = segment.nags;
  if (nags.any((n) => getNagDisplay(n)?.isQuality ?? false)) return nags;
  return switch (segment.moveClass) {
    MoveClass.brilliant => [3, ...nags],
    MoveClass.great => [1, ...nags],
    _ => nags,
  };
}

/// [child] springing up into its line each time [id] changes: a few points
/// below, settling on a snappy spring. Only its place moves, never its ink,
/// so it reads in full from the first frame, and nothing waits on it. The
/// first build sits still: arriving at a position is not a change.
class StorySpringIn extends StatefulWidget {
  const StorySpringIn({super.key, required this.id, required this.child});

  final Object? id;
  final Widget child;

  /// How far below its line a new headline starts.
  static const double rise = 8;

  @override
  State<StorySpringIn> createState() => _StorySpringInState();
}

class _StorySpringInState extends State<StorySpringIn>
    with SingleTickerProviderStateMixin {
  late final SingleMotionController _offset = SingleMotionController(
    motion: const CupertinoMotion.snappy(
      duration: Duration(milliseconds: 380),
      snapToEnd: true,
    ),
    vsync: this,
  );

  @override
  void didUpdateWidget(covariant StorySpringIn oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.id == widget.id) return;
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) return;
    _offset.value = StorySpringIn.rise;
    unawaited(_offset.animateTo(0));
  }

  @override
  void dispose() {
    _offset.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _offset,
      child: widget.child,
      builder: (context, child) =>
          Transform.translate(offset: Offset(0, _offset.value), child: child),
    );
  }
}

/// Of [a] and [b], the ink that stands clearer of [fill] ([wcagContrast]):
/// a plate whose fill springs from one to the other keeps its label
/// readable on every frame.
Color storyClearerInk(Color fill, Color a, Color b) =>
    wcagContrast(a, fill) >= wcagContrast(b, fill) ? a : b;

/// The question's one action: the answer, without a try. A plate on a
/// whole 44pt target right under the question, the Feed puzzle's Solution
/// glyph and what there is to find ("Show the win", "Show the mate"). A
/// quiet plate a step off the page (the actions' own) while the reader
/// tries; [emphasised], once tries have not found it, it springs to the
/// page's solid ink, the way on. The board still takes the reader's own
/// try meanwhile.
class StoryRevealButton extends StatelessWidget {
  const StoryRevealButton({
    super.key,
    required this.label,
    required this.onTap,
    this.emphasised = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool emphasised;

  /// The plate's height, centred in its 44pt target.
  static const double plateHeight = 36;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final target = emphasised ? 1.0 : 0.0;
    Widget plate(double t) {
      final fill = Color.lerp(colors.surfaceRecessed, colors.textPrimary, t)!;
      // The fill springs; the ink never does. A lerped ink would cross the
      // fill's own value mid-way and the label would vanish into its plate
      // for a frame or two: it takes whichever of the two inks stands
      // clearer of the fill at that instant instead.
      final ink = storyClearerInk(fill, colors.textPrimary, colors.background);
      return Container(
        key: const ValueKey('story_show_plate'),
        height: plateHeight,
        // The glyph carries its own margin inside its box: a shorter
        // start leaves its edge as clear as the label's end.
        padding: const EdgeInsetsDirectional.only(start: 8, end: 14),
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            FeedGlyph(FeedGlyphs.solution, width: 18, height: 18, color: ink),
            const SizedBox(width: 6),
            Text(
              label,
              maxLines: 1,
              softWrap: false,
              style: AppTypography.textSmBold.copyWith(
                fontSize: 15,
                height: 1.2,
                fontWeight: FontWeight.w600,
                color: ink,
              ),
            ),
          ],
        ),
      );
    }

    final face = MediaQuery.disableAnimationsOf(context)
        ? plate(target)
        : SingleMotionBuilder(
            value: target,
            motion: const CupertinoMotion.smooth(
              duration: Duration(milliseconds: 320),
              snapToEnd: true,
            ),
            builder: (context, t, _) => plate(t.clamp(0.0, 1.0)),
          );
    return Semantics(
      button: true,
      label: label,
      hint: 'Or play it on the board',
      onTap: onTap,
      excludeSemantics: true,
      child: GestureDetector(
        key: const ValueKey('story_show_answer'),
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: PressSpring(
          pressedScale: 0.95,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              widthFactor: 1,
              heightFactor: 1,
              child: face,
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
/// secondary ink when the position carries none, and under a find, where
/// the found headline is the one tone.
Color storyToneInk(
  BuildContext context,
  StorySegment segment,
  StoryPuzzleState? state,
) {
  final colors = context.colors;
  if (segment.puzzle != null && state == StoryPuzzleState.found) {
    return colors.textSecondary;
  }
  final MoveClass? moveClass = switch (segment.puzzle?.kind) {
    StoryPuzzleKind.findMissed => MoveClass.missedWin,
    _ => segment.moveClass,
  };
  final hue = moveClass == null ? null : PuzzleMoveBadge.colorOf(moveClass);
  if (hue == null) return colors.textSecondary;
  if (context.isLightTheme) return legibleHueInk(context, hue);
  return _liftedInk(hue, colors.background);
}

/// A question's step as ink on the page: [found] in the best move's green
/// (the Feed puzzle's "Solved"), a miss in the mistake's amber (its "Not
/// quite"), each legible on paper; on the dark page lifted until it reads,
/// then eased a step toward the page's own ink, a tone rather than a
/// poster-bright pop. A miss is never shouted.
Color storyStateInk(BuildContext context, {required bool found}) {
  final hue = PuzzleMoveBadge.colorOf(
    found ? MoveClass.best : MoveClass.mistake,
  )!;
  if (context.isLightTheme) return legibleHueInk(context, hue);
  final colors = context.colors;
  return Color.lerp(
    _liftedInk(hue, colors.background),
    colors.textPrimary,
    found ? 0.18 : 0.3,
  )!;
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

/// The two actions under a story, across the story's own width: the game
/// at this position, and the collection (or the game's event). Two equal
/// buttons, one treatment: a plate a step off the page in its own ink (the
/// Feed end card's Replay plate), a glyph that says where it goes, the
/// label. Never a filled and an outlined pair. Each a whole 48pt target.
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

  /// Between the two buttons.
  static double get gap => _atLeast(10);

  @override
  Widget build(BuildContext context) {
    final ink = context.colors.textPrimary;
    return Row(
      children: [
        Expanded(
          child: _StoryAction(
            key: const ValueKey('story_open_game'),
            label: 'Open game',
            hint: 'On the board, at this position',
            // The Feed rail's Analyze: the game on the board.
            glyph: FeedGlyph(
              FeedGlyphs.analyze,
              width: 18,
              height: 18,
              color: ink,
            ),
            onTap: onOpenGame,
          ),
        ),
        SizedBox(width: gap),
        Expanded(
          child: _StoryAction(
            key: const ValueKey('story_view_collection'),
            label: collectionLabel,
            // The stories' own arrow out: to the page it came from.
            glyph: CustomPaint(
              size: const Size.square(15),
              painter: StoryArrowPainter(color: ink, weight: 1.6),
            ),
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
    required this.glyph,
    required this.onTap,
    this.hint,
  });

  final String label;
  final String? hint;
  final Widget glyph;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final style = AppTypography.textSmBold.copyWith(
      fontSize: 15,
      height: 1.2,
      fontWeight: FontWeight.w600,
      color: colors.textPrimary,
    );
    return Semantics(
      button: true,
      label: label,
      hint: hint,
      onTap: onTap,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: PressSpring(
          pressedScale: 0.97,
          child: Container(
            constraints: const BoxConstraints(minHeight: 48),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: colors.surfaceRecessed,
              borderRadius: BorderRadius.circular(4),
            ),
            alignment: Alignment.center,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox.square(dimension: 18, child: Center(child: glyph)),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.fade,
                    style: style,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The stories' arrow out: up and to the right, its stroke and its head's
/// two arms with round caps and joins, the head a touch open. [weight] sets
/// the stroke in points; by default it grows with the arrow.
class StoryArrowPainter extends CustomPainter {
  const StoryArrowPainter({required this.color, this.weight});

  final Color color;
  final double? weight;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = weight ?? math.max(1.6, s * 0.15)
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
  bool shouldRepaint(StoryArrowPainter old) =>
      old.color != color || old.weight != weight;
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
        // The bar and the board as one quiet block, where both will stand.
        board: (side, bar) => Bone(
          width: bar + side,
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
