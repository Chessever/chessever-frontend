import 'dart:math' as math;

import 'package:chessever2/screens/chessboard/widgets/chess_board_from_fen_new.dart'
    show GameCardChessboard;
import 'package:chessever2/screens/chessboard/widgets/player_first_row_detail_widget.dart'
    show playerNameLabel;
import 'package:chessever2/screens/collections/collections_data.dart';
import 'package:chessever2/screens/stories/story_models.dart';
import 'package:chessever2/screens/stories/story_replay.dart';
import 'package:chessever2/screens/stories/story_row.dart';
import 'package:chessever2/screens/stories/story_seen_store.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/broadcast_custom_scoring.dart'
    show boardResultLabelForSide;
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/text_scale.dart';
import 'package:chessever2/utils/user_error_message.dart';
import 'package:chessever2/widgets/federation_flag.dart';
import 'package:chessever2/widgets/press_spring.dart';
import 'package:chessever2/widgets/skeleton_widget.dart';
import 'package:dartchess/dartchess.dart' show Side;
import 'package:flutter/foundation.dart' show ValueListenable;
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

  /// Between the story and the action under it.
  static double get actionGap => _atLeast(12);

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

/// The story area's own geometry: the board as large as the space allows,
/// never larger than the page's width or the height left under the header.
abstract final class StoryGameLayout {
  /// Smallest board drawn; below it the whole story scales down instead.
  static const double minBoard = 120;

  /// Between a player's row and the board. Never under its portrait size:
  /// a phone on its side scales the page's spacing down by half.
  static double get rowGap => _atLeast(8);

  /// Between the lower row and the line under it.
  static double get captionGap => _atLeast(14);

  /// The line under the board may run wider than a board drawn small (a
  /// phone on its side), centred under it, up to this or the page's width.
  static const double maxLineWidth = 440;

  /// The width of the line under a board of side [board] in [constraints].
  static double lineWidth(BoxConstraints constraints, double board) {
    final across = constraints.maxWidth - 2 * _gutter;
    return math.max(board, math.min(across, maxLineWidth));
  }

  /// The line under the board.
  static TextStyle captionStyle(BuildContext context) => AppTypography
      .textXsRegular
      .copyWith(color: context.colors.textSecondary, height: 1.4);

  /// The line's box: room for one line at the reader's text size, so a
  /// larger setting grows the box instead of cutting the letters.
  static double captionBox(BuildContext context) {
    final style = captionStyle(context);
    final line =
        MediaQuery.textScalerOf(context).scale(style.fontSize ?? 12) *
        (style.height ?? 1.4);
    return math.max(20.sp, line.ceilToDouble() + 1);
  }

  /// The board's side within [constraints] (the story area), the rows and
  /// the line taking [captionBox] around it.
  static double boardSize(BoxConstraints constraints, double captionBox) {
    final across = constraints.maxWidth - 2 * _gutter;
    final fixed =
        2 * StoryPlayerRow.height + 2 * rowGap + captionGap + captionBox;
    final down = constraints.hasBoundedHeight
        ? constraints.maxHeight - fixed
        : double.infinity;
    return math.max(minBoard, math.min(across, down)).floorToDouble();
  }

  /// Between the board and the players beside it.
  static double get sideGap => _atLeast(20);

  /// The players and the line beside the board take at least this, and at
  /// most [maxSide]: a name reads whole there.
  static const double minSide = 220;
  static const double maxSide = 320;

  /// Whether the story area [constraints] sets the players and the line
  /// beside the board (a phone on its side): there a board as tall as the
  /// space still leaves them [minSide], where over and under it the board
  /// would shrink to a stamp and the names would fade early.
  static bool beside(BoxConstraints constraints) {
    if (!constraints.hasBoundedHeight) return false;
    final across = constraints.maxWidth - 2 * _gutter;
    return across - sideGap - minSide >= constraints.maxHeight - besideAir;
  }

  /// Air above and below a board [beside] its players, split evenly: it
  /// never sits hard under the header.
  static double get besideAir => _atLeast(20);

  /// The board's side when [beside]: as tall as the area, less [besideAir].
  static double boardBeside(BoxConstraints constraints) =>
      math.max(minBoard, constraints.maxHeight - besideAir).floorToDouble();

  /// The width of the players and the line beside a board of [board].
  static double sideWidth(BoxConstraints constraints, double board) {
    final across = constraints.maxWidth - 2 * _gutter;
    return math.min(maxSide, across - board - sideGap).floorToDouble();
  }
}

/// A game story's arrangement, one for the story and its skeleton so
/// nothing moves when the games land. Upright: the players over and under
/// the board, the line centred below. On its side ([StoryGameLayout.beside]):
/// the board as tall as the space, the players beside it level with its top
/// and bottom edges, the line between them; the whole centred.
class _StoryGameFrame extends StatelessWidget {
  const _StoryGameFrame({
    required this.board,
    required this.top,
    required this.bottom,
    required this.line,
  });

  final Widget Function(double side) board;

  /// Black's row and White's.
  final Widget top;
  final Widget bottom;

  /// The event and opening line; [beside] when it sits beside the board,
  /// where it may take two lines.
  final Widget? Function(bool beside) line;

  @override
  Widget build(BuildContext context) {
    final captionBox = StoryGameLayout.captionBox(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        if (StoryGameLayout.beside(constraints)) {
          final side = StoryGameLayout.boardBeside(constraints);
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              board(side),
              SizedBox(width: StoryGameLayout.sideGap),
              SizedBox(
                width: StoryGameLayout.sideWidth(constraints, side),
                height: side,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [top, line(true) ?? const SizedBox(), bottom],
                ),
              ),
            ],
          );
        }
        // As wide as the page allows and no taller than the space under
        // the header: the rows keep to the board's width.
        final side = StoryGameLayout.boardSize(constraints, captionBox);
        return FittedBox(
          fit: BoxFit.scaleDown,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: side,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    top,
                    SizedBox(height: StoryGameLayout.rowGap),
                    board(side),
                    SizedBox(height: StoryGameLayout.rowGap),
                    bottom,
                  ],
                ),
              ),
              SizedBox(height: StoryGameLayout.captionGap),
              // Centred under the board; wider than a board drawn small.
              SizedBox(
                width: StoryGameLayout.lineWidth(constraints, side),
                height: captionBox,
                child: line(false),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// One collection's face: its bars, its header, the story on screen and the
/// story's action, laid out for the whole screen.
class StoryCollectionPage extends ConsumerWidget {
  const StoryCollectionPage({
    super.key,
    required this.collection,
    required this.storyIndex,
    required this.progress,
    required this.chrome,
    required this.backdrop,
    required this.onClose,
    required this.onOpenGame,
    required this.onOpenAll,
    required this.onRetry,
    this.avatarHidden,
  });

  final Collection collection;

  /// True while the viewer's flying cover stands in for the header's
  /// circle (on the way in and out); null on every face but the active one.
  final ValueListenable<bool>? avatarHidden;

  /// The story the viewer has this collection on; null until the reader has
  /// been here (then it is where they left off, or the first new one).
  final int? storyIndex;

  /// The story's run, 0 to 1. Still for every face but the one in view.
  final Animation<double> progress;

  /// 1 with the header, bars and action shown; 0 while a story is held.
  final Animation<double> chrome;
  final Color backdrop;
  final VoidCallback onClose;
  final VoidCallback onOpenGame;
  final VoidCallback onOpenAll;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final read = ref.watch(storyBatchProvider(collection.slug));
    final batch = read.valueOrNull;
    // Clamped to the stories the batch holds now: a re-read can bring a
    // shorter list than the one the remembered place was counted on.
    final index = batch == null
        ? 0
        : clampStoryIndex(
            storyIndex ??
                ref
                    .read(storySeenProvider.notifier)
                    .resumeIndex(
                      collection.slug,
                      storySignature(collection),
                      batch.storyCount,
                    ),
            batch.storyCount,
          );
    final padding = MediaQuery.paddingOf(context);
    final isGame =
        batch != null &&
        batch.storyCount > 0 &&
        !batch.isSeeAll(index) &&
        index < batch.games.length;

    final Widget body;
    if (batch == null && read.hasError) {
      body = StoryRetry(error: read.error, onRetry: onRetry);
    } else if (batch == null) {
      body = const StorySkeleton();
    } else if (batch.storyCount == 0) {
      body = const _StoryNotice(text: 'No games here yet.');
    } else if (batch.isSeeAll(index)) {
      body = StorySeeAll(
        collection: collection,
        total: batch.total,
        onOpen: onOpenAll,
      );
    } else if (index >= batch.games.length) {
      body = const StorySkeleton();
    } else {
      final story = batch.games[index];
      body = StoryGameView(
        key: ValueKey('story_game_${story.id}'),
        story: story,
        progress: progress,
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
                ),
              ),
            ),
            SizedBox(height: StoryPageMetrics.barsGap),
            FadeTransition(
              opacity: chrome,
              child: StoryHeader(
                collection: collection,
                onClose: onClose,
                avatarHidden: avatarHidden,
              ),
            ),
            Expanded(child: Center(child: body)),
            // Air between the story and its action, kept where the story
            // fills the height (a phone on its side).
            SizedBox(height: StoryPageMetrics.actionGap),
            FadeTransition(
              opacity: chrome,
              child: SizedBox(
                height: StoryOpenGameButton.heightOf(context),
                child: isGame
                    ? Center(child: StoryOpenGameButton(onTap: onOpenGame))
                    : null,
              ),
            ),
            SizedBox(height: padding.bottom + 8.sp),
          ],
        ),
      ),
    );
  }
}

/// One bar per story across the top: full for the stories before, filling
/// for the one on screen, empty for the ones after. Each fill is a rounded
/// bar that grows in width, so its ends keep their round caps all the way.
class StoryProgressBars extends StatelessWidget {
  const StoryProgressBars({
    super.key,
    required this.count,
    required this.index,
    required this.progress,
  });

  final int count;
  final int index;
  final Animation<double> progress;

  static double get height => _atLeast(2.5);
  static double get gap => _atLeast(3);

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
  }) : super(repaint: progress);

  final int count;
  final int index;
  final Animation<double> progress;
  final Color track;
  final Color fill;
  final double gap;

  @override
  void paint(Canvas canvas, Size size) {
    if (count <= 0 || size.width <= 0) return;
    final width = (size.width - gap * (count - 1)) / count;
    if (width <= 0) return;
    final radius = Radius.circular(size.height / 2);
    final trackPaint = Paint()..color = track;
    final fillPaint = Paint()..color = fill;
    for (var i = 0; i < count; i++) {
      final left = i * (width + gap);
      final bar = RRect.fromLTRBR(left, 0, left + width, size.height, radius);
      canvas.drawRRect(bar, trackPaint);
      final share = i < index
          ? 1.0
          : i == index
          ? progress.value.clamp(0.0, 1.0)
          : 0.0;
      if (share <= 0) continue;
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
  }

  @override
  bool shouldRepaint(_BarsPainter old) =>
      old.count != count ||
      old.index != index ||
      old.progress != progress ||
      old.track != track ||
      old.fill != fill ||
      old.gap != gap;
}

/// The face's header: the collection's cover, title and byline, and the way
/// out.
class StoryHeader extends StatelessWidget {
  const StoryHeader({
    super.key,
    required this.collection,
    required this.onClose,
    this.avatarHidden,
  });

  final Collection collection;
  final VoidCallback onClose;

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
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: _gutter),
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

/// A game story: the players, the board replaying the game in the story's
/// time, the event and the opening.
///
/// Every frame is read from the story's [progress]: a held story holds its
/// board, and the bar and the board always agree.
class StoryGameView extends StatefulWidget {
  const StoryGameView({super.key, required this.story, required this.progress});

  final StoryGame story;
  final Animation<double> progress;

  @override
  State<StoryGameView> createState() => _StoryGameViewState();
}

class _StoryGameViewState extends State<StoryGameView> {
  late int _step;
  late bool _revealed;

  StoryReplay get _replay => widget.story.replay;

  @override
  void initState() {
    super.initState();
    _read();
    widget.progress.addListener(_onProgress);
  }

  @override
  void didUpdateWidget(covariant StoryGameView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.progress != widget.progress) {
      oldWidget.progress.removeListener(_onProgress);
      widget.progress.addListener(_onProgress);
    }
    _read();
  }

  @override
  void dispose() {
    widget.progress.removeListener(_onProgress);
    super.dispose();
  }

  void _read() {
    final t = widget.progress.value;
    _step = _replay.stepAt(t);
    _revealed = _replay.revealedAt(t);
  }

  void _onProgress() {
    final t = widget.progress.value;
    final step = _replay.stepAt(t);
    final revealed = _replay.revealedAt(t);
    if (step == _step && revealed == _revealed) return;
    setState(() {
      _step = step;
      _revealed = revealed;
    });
  }

  @override
  Widget build(BuildContext context) {
    final game = widget.story.game;
    final caption = widget.story.caption;
    final captionStyle = StoryGameLayout.captionStyle(context);
    return _StoryGameFrame(
      top: StoryPlayerRow(game: game, white: false, revealed: _revealed),
      bottom: StoryPlayerRow(game: game, white: true, revealed: _revealed),
      board: (side) => GameCardChessboard(
        key: const ValueKey('story_board'),
        fen: _replay.fens[_step],
        lastMove: _replay.lastMoves[_step],
        boardSize: side,
        orientation: Side.white,
        showCoordinates: false,
        gameStatus: _revealed ? game.gameStatus : null,
        // The board is the story's subject, set flat on its page.
        grounded: false,
      ),
      line: (beside) {
        if (caption == null) return null;
        final text = Text(
          caption,
          key: const ValueKey('story_caption'),
          maxLines: beside ? 2 : 1,
          softWrap: beside,
          overflow: TextOverflow.fade,
          textAlign: beside ? TextAlign.start : TextAlign.center,
          style: captionStyle,
        );
        return beside ? text : Center(child: text);
      },
    );
  }
}

/// A player's row over or under the story's board, in the board rows' own
/// style: the flag, the title in its accent, the name at one fixed size
/// fading at its end (never shrunk, never cut with dots), the rating beside
/// it, and the game's result at the row's end once the replay has landed.
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
                    // One size with the name beside it, as the board rows.
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

/// The last story of a collection with more games than its stories: its
/// cover (the header above already names it) and the door to all of them.
class StorySeeAll extends StatelessWidget {
  const StorySeeAll({
    super.key,
    required this.collection,
    required this.total,
    required this.onOpen,
  });

  final Collection collection;
  final int total;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final book = collection.kind == CollectionKind.book;
    final label = 'See all $total games';
    final gap = 28.sp;
    final buttonHeight = math.max(50.sp, 44 * context.textGrowth);
    return LayoutBuilder(
      builder: (context, constraints) {
        final across = constraints.maxWidth - 2 * _gutter;
        final down = constraints.hasBoundedHeight
            ? constraints.maxHeight - gap - buttonHeight
            : double.infinity;
        // A book's jacket stands; an event's plate lies down. Either fits
        // the width and the height left to it.
        final coverWidth = book
            ? math.min(across * 0.56, down / 1.5)
            : math.min(across, down / 0.6);
        final coverSize = book
            ? Size(coverWidth, coverWidth * 1.5)
            : Size(coverWidth, coverWidth * 0.6);
        return FittedBox(
          fit: BoxFit.scaleDown,
          child: Column(
            key: const ValueKey('story_see_all'),
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(14.sp),
                child: SizedBox.fromSize(
                  size: Size(
                    math.max(1, coverSize.width),
                    math.max(1, coverSize.height),
                  ),
                  child: StoryCoverImage(collection: collection, full: true),
                ),
              ),
              SizedBox(height: gap),
              Semantics(
                button: true,
                label: label,
                excludeSemantics: true,
                child: GestureDetector(
                  key: const ValueKey('story_see_all_button'),
                  behavior: HitTestBehavior.opaque,
                  onTap: onOpen,
                  child: PressSpring(
                    pressedScale: 0.96,
                    child: Container(
                      height: buttonHeight,
                      padding: EdgeInsets.symmetric(horizontal: 22.sp),
                      decoration: BoxDecoration(
                        color: colors.textPrimary,
                        borderRadius: BorderRadius.circular(14.sp),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            label,
                            style: AppTypography.textMdBold.copyWith(
                              color: colors.textInverse,
                              height: 1.2,
                            ),
                          ),
                          SizedBox(width: 8.sp),
                          Icon(
                            Icons.north_east_rounded,
                            size: 18.sp,
                            color: colors.textInverse,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// The quiet action under a game story: open the game on the board. A swipe
/// up does the same; the chevron says so.
class StoryOpenGameButton extends StatelessWidget {
  const StoryOpenGameButton({super.key, required this.onTap});

  final VoidCallback onTap;

  /// The action's line: the chevron and the label at the reader's text
  /// size, never under a 48pt target.
  static double heightOf(BuildContext context) =>
      math.max(48.0, math.max(56.sp, chevron + context.textExtent(17) + 8));

  /// The swipe-up chevron, never a speck on a phone on its side.
  static double get chevron => _atLeast(20);

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      button: true,
      label: 'Open game',
      excludeSemantics: true,
      child: GestureDetector(
        key: const ValueKey('story_open_game'),
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: PressSpring(
          pressedScale: 0.94,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 120, minHeight: 44),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.keyboard_arrow_up_rounded,
                  size: chevron,
                  color: colors.textSecondary,
                ),
                Text(
                  'Open game',
                  style: AppTypography.textSmBold.copyWith(
                    color: colors.textPrimary,
                    height: 1.2,
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

/// A story while its collection's games load: the rows, the board and the
/// line, as quiet bones in their exact places.
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
    return SkeletonWidget(
      key: const ValueKey('story_skeleton'),
      child: _StoryGameFrame(
        top: row(),
        bottom: row(),
        board: (side) => Bone(
          width: side,
          height: side,
          borderRadius: BorderRadius.circular(4.sp),
        ),
        line: (beside) => Align(
          alignment: beside
              ? AlignmentDirectional.centerStart
              : Alignment.center,
          child: FractionallySizedBox(
            widthFactor: beside ? 0.7 : 0.5,
            child: Bone(
              height: 10.sp,
              borderRadius: BorderRadius.circular(5.sp),
            ),
          ),
        ),
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
