import 'dart:math' as math;

import 'package:chessever2/providers/engine_settings_provider.dart';
import 'package:chessever2/screens/chessboard/provider/chess_board_screen_provider_new.dart';
import 'package:chessever2/screens/chessboard/provider/game_pgn_stream_provider.dart';
import 'package:chessever2/screens/for_you/discovery/models/discovery_models.dart';
import 'package:chessever2/screens/for_you/discovery/widgets/discovery_common.dart';
import 'package:chessever2/screens/library/widgets/library_context_menu.dart'
    show LibraryMenuAction;
import 'package:chessever2/screens/my_space/widgets/space_glyphs.dart';
import 'package:chessever2/screens/player_profile/player_profile_data_source.dart';
import 'package:chessever2/screens/streaks/widgets/wall_common.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_list_view_mode_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/game_card_wrapper/game_card_wrapper_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/game_card_wrapper/game_card_wrapper_widget.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/game_card_wrapper/grid_game_card_wrapper_widget.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/game_card_wrapper/live_game_card_provider.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/board_like_heart.dart';
import 'package:chessever2/widgets/skeleton_widget.dart';
import 'package:chessever2/widgets/time_control_glyph.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Profiles behind a game's player names: archive games resolve through the
/// Gamebase/TWIC source, broadcast games through Supabase.
PlayerProfileDataSource discoveryProfileSource(GamesTourModel game) =>
    game.source == GameSource.gamebase
    ? PlayerProfileDataSource.twic
    : PlayerProfileDataSource.supabase;

/// Opens [games] on the board at [index]. The list is kept exactly as shown
/// (a ranking, a rail), so previous/next walks the same collection instead of
/// expanding into one game's event.
void openDiscoveryGame(
  BuildContext context,
  WidgetRef ref,
  List<GamesTourModel> games,
  int index,
) {
  if (index < 0 || index >= games.length) return;
  ref
      .read(gameCardWrapperProvider)
      .navigateToChessBoard(
        context: context,
        orderedGames: games,
        gameIndex: index,
        onReturnFromChessboard: null,
        viewSource: ChessboardView.forYou,
        listPolicy: BoardNavigationListPolicy.preserve,
        playerProfileDataSource: discoveryProfileSource(games[index]),
      );
}

/// One piece of a card's meta line.
sealed class DiscoveryMetaPart {
  const DiscoveryMetaPart();

  /// A figure in full ink with an optional quiet prefix and unit: "19"
  /// " moves", "Ø " "2791" (ratings are never comma-grouped).
  const factory DiscoveryMetaPart.figure(
    String figure, {
    String prefix,
    String unit,
  }) = _MetaFigure;

  /// A like count, drawn as the heart and the figure.
  const factory DiscoveryMetaPart.likes(int likes) = _MetaLikes;

  /// Quiet text: an event, a rating, a date.
  const factory DiscoveryMetaPart.text(String text) = _MetaText;
}

class _MetaFigure extends DiscoveryMetaPart {
  const _MetaFigure(this.figure, {this.prefix = '', this.unit = ''});

  final String figure;
  final String prefix;
  final String unit;
}

class _MetaLikes extends DiscoveryMetaPart {
  const _MetaLikes(this.likes);

  final int likes;
}

class _MetaText extends DiscoveryMetaPart {
  const _MetaText(this.text);

  final String text;
}

/// The one line above a card: what the card is to this section (its rank
/// and likes, a miniature's length, a rating, a day), led by the game's
/// time-control glyph when it has one, parts set apart by " · ". Exactly
/// one line at every text size: when the line runs out of room, whole
/// trailing parts give way (a quiet text part stays, ellipsized, only while
/// a readable stub of it fits; a figure is never cut), and
/// [semanticsLabel] carries the whole sentence (the full event name too).
class DiscoveryCardMeta extends StatelessWidget {
  const DiscoveryCardMeta({
    super.key,
    required this.parts,
    required this.semanticsLabel,
    this.timeControlAsset,
  });

  final List<DiscoveryMetaPart> parts;
  final String semanticsLabel;

  /// One of the time-control PNGs ([TimeControlGlyph.assetForLabel]).
  final String? timeControlAsset;

  /// The fewest characters a trailing text part keeps before it is dropped
  /// whole instead of ellipsized.
  static const int _minTextStub = 8;

  @override
  Widget build(BuildContext context) {
    // Tabular figures only on the figures: Inter's tabular set also widens
    // the hyphen and the full stop inside event names.
    final quiet = discoveryType(context, DiscoveryType.meta);
    final strong = discoveryType(
      context,
      DiscoveryType.meta,
      tabular: true,
    ).copyWith(fontWeight: FontWeight.w700, color: context.colors.textPrimary);
    final glyphSide = 12.w;
    final tcGap = 5.w;
    final heartGap = 3.w;
    WidgetSpan glyph(Widget child, {double gap = 0}) => WidgetSpan(
      alignment: PlaceholderAlignment.middle,
      child: Padding(
        padding: EdgeInsets.only(right: gap),
        child: child,
      ),
    );

    final asset = timeControlAsset;

    /// The spans for the first [count] parts. With [measure] the glyphs are
    /// left out (their fixed widths are added by [widthOf]).
    List<InlineSpan> spansFor(int count, {bool measure = false}) {
      final spans = <InlineSpan>[];
      if (asset != null && !measure) {
        spans.add(glyph(TimeControlGlyph(asset, size: glyphSide), gap: tcGap));
      }
      for (var i = 0; i < count; i++) {
        if (i > 0) spans.add(const TextSpan(text: ' · '));
        switch (parts[i]) {
          case _MetaFigure(:final figure, :final prefix, :final unit):
            if (prefix.isNotEmpty) spans.add(TextSpan(text: prefix));
            spans.add(TextSpan(text: figure, style: strong));
            if (unit.isNotEmpty) spans.add(TextSpan(text: unit));
          case _MetaLikes(:final likes):
            if (!measure) {
              spans.add(
                glyph(
                  SpaceGlyph(
                    SpaceGlyphKind.heart,
                    size: glyphSide,
                    ink: discoveryHeartInk(context),
                  ),
                  gap: heartGap,
                ),
              );
            }
            spans.add(TextSpan(text: wallCount(likes), style: strong));
          case _MetaText(:final text):
            spans.add(TextSpan(text: text));
        }
      }
      return spans;
    }

    final base = DefaultTextStyle.of(context).style.merge(quiet);
    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);

    double widthOf(int count, {String? stub}) {
      var glyphs = asset != null ? glyphSide + tcGap : 0.0;
      for (var i = 0; i < count; i++) {
        if (parts[i] is _MetaLikes) glyphs += glyphSide + heartGap;
      }
      final painter = TextPainter(
        text: TextSpan(
          style: base,
          children: [
            ...spansFor(count, measure: true),
            if (stub != null) TextSpan(text: '${count > 0 ? ' · ' : ''}$stub'),
          ],
        ),
        textDirection: direction,
        textScaler: scaler,
        maxLines: 1,
      )..layout();
      final width = painter.width;
      painter.dispose();
      return width + glyphs;
    }

    return Semantics(
      container: true,
      label: semanticsLabel,
      excludeSemantics: true,
      child: LayoutBuilder(
        builder: (context, constraints) {
          var count = parts.length;
          final max = constraints.maxWidth;
          if (max.isFinite) {
            while (count > 1 && widthOf(count) > max) {
              count--;
            }
            // The first part that no longer fits: a text part may stay,
            // ellipsized, while a readable stub of it still fits.
            if (count < parts.length) {
              final next = parts[count];
              if (next is _MetaText &&
                  next.text.length > _minTextStub &&
                  widthOf(
                        count,
                        stub: '${next.text.substring(0, _minTextStub)}…',
                      ) <=
                      max) {
                count++;
              }
            }
          }
          return Text.rich(
            TextSpan(children: spansFor(count)),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: quiet,
          );
        },
      ),
    );
  }
}

/// "Sicilian Defense · Sep 23": an archive game's opening (or its ECO code)
/// and its day, the compact card's footer where a game has no clock and no
/// last move, so the strip never sits blank.
String? _defaultFooterDetail(GamesTourModel game) {
  // Archive rows mark a missing opening as '?' or 'Unknown'.
  String? known(String? value) {
    final v = value?.trim();
    if (v == null || v.isEmpty || v == '?' || v == 'Unknown') return null;
    return v;
  }

  final opening = known(game.openingName);
  final eco = known(game.eco);
  final day = discoveryGameDay(game);
  final parts = [
    if (opening != null) opening else if (eco != null) eco,
    if (day != null) discoveryDay(day),
  ];
  return parts.isEmpty ? null : parts.join(' · ');
}

/// How many games every preview of games draws (Most liked, Miniatures, My
/// Space's saved games, a saved event's live boards, saved players' games):
/// two rows of the grid, four list rows. One rule for every section.
const int kDiscoveryPreviewCards = 4;

/// How many a preview draws in board view, where a card is a whole screen
/// wide.
const int kDiscoveryPreviewBoards = 2;

/// One line of [DiscoveryType.meta] at the viewer's text size: the slot a
/// [DiscoveryGameList.labelFor] label sits in. Every card of a labelled list
/// gets the same slot (a card without a label keeps it empty), so cards set
/// side by side keep one top edge whatever their labels say.
double _labelSlotHeight(BuildContext context) {
  final painter = TextPainter(
    text: TextSpan(
      text: 'Ag',
      style: DefaultTextStyle.of(
        context,
      ).style.merge(discoveryType(context, DiscoveryType.meta)),
    ),
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
    maxLines: 1,
  )..layout();
  final height = painter.height;
  painter.dispose();
  return height;
}

/// Between a label and the card under it.
double get _labelGap => 8.w;

/// A board card's own side inset: `ChessBoardFromFENNew` pads its rows and
/// board 24.sp in from each side, so a label over it starts on that edge.
double get _boardCardInset => 24.sp;

/// A list row's own side inset: `GameCard` sets its players 16.sp in, so a
/// label over it starts where the names do.
double get _rowInset => 16.sp;

/// Between two cards in a row and between rows.
double get _cardGap => 12.sp;

/// [label] in its fixed one-line slot over [card]. [inset] lines the label
/// up with a card whose content sits inside its own box.
Widget _labelled({
  required double slot,
  required Widget? label,
  required Widget card,
  double inset = 0,
}) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [
      Padding(
        padding: EdgeInsets.symmetric(horizontal: inset),
        child: SizedBox(
          height: slot,
          child:
              label == null
                  ? null
                  : Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: label,
                  ),
        ),
      ),
      SizedBox(height: _labelGap),
      card,
    ],
  );
}

/// Games listed the way an event's Games tab lists them: the app's own game
/// card per game, a board or a list row by the viewer's games view setting,
/// two boards a row in grid view. A game with no real position to draw keeps
/// the list row rather than a made-up board. Every list of games on the hub
/// pages and their destinations goes through this one path, so no section
/// picks its own card.
///
/// [limit] (and [boardLimit] in board view, where a card is a whole screen
/// wide) caps how many cards are drawn, from [start], but opening any card
/// still hands the board the whole of [games], so previous/next walks past
/// the preview. In grid view the list rows of games without a position count
/// toward the cap. A long list is drawn lazily as one [DiscoveryGameList]
/// per row, each with its own [start].
///
/// [badgeFor] sets a mark on a game's board ([BoardCornerBadge]); [footerFor]
/// adds a line under a list row whose strip has no clock or move to show (a
/// row with a [rowLabelFor] line takes the opening and the day there);
/// [labelFor] sets one line (a [DiscoveryCardMeta]) over a grid or board
/// card, in a slot every card of the list keeps, so paired cards stay level;
/// [rowLabelFor] sets that line over a list row (a row has no board for a
/// badge and its strip shows the clocks, so a section whose cards say
/// something of their own says it here). [onOpen] replaces the card's own
/// opening (Miniatures fetch their PGN first); by default a card opens the
/// board on this list, kept exactly as shown.
///
/// [menuActionsFor] replaces a card's long-press rows, [wrapCard] wraps a
/// card (a swipe to remove), and [lockedFor] greys a card and sets the
/// padlock after its label (its tap goes through [onOpen], which raises the
/// paywall).
///
/// Streaming: with [liveBatchKeyFor], only games that can stream (unfinished
/// Supabase games, [shouldSubscribeToLiveGame]) subscribe, each on the batch
/// key the caller hands it, so one channel serves one group. Build that key
/// over the drawn games only ([shownFor]). No card runs the on-device engine
/// unless [allowStockfishFallback] says so.
class DiscoveryGameList extends ConsumerWidget {
  const DiscoveryGameList({
    super.key,
    required this.games,
    this.badgeFor,
    this.footerFor,
    this.onOpen,
    this.streamEnabled = true,
    this.limit,
    this.boardLimit,
    this.start = 0,
    this.padded = true,
    this.labelFor,
    this.rowLabelFor,
    this.liveBatchKeyFor,
    this.allowStockfishFallback = false,
    this.menuActionsFor,
    this.wrapCard,
    this.lockedFor,
  });

  final List<GamesTourModel> games;
  final Widget Function(int index, double boardSize)? badgeFor;
  final String? Function(int index)? footerFor;
  final void Function(List<GamesTourModel> games, int index)? onOpen;

  /// False for archive games, which never stream.
  final bool streamEnabled;

  /// At most this many cards (all when null).
  final int? limit;

  /// At most this many cards in board view; [limit] when null.
  final int? boardLimit;

  /// The index of the first game drawn.
  final int start;

  /// Sets the list in [discoveryGutter]; false inside a parent that already
  /// holds the page's gutter.
  final bool padded;

  /// One line over a grid or board card.
  final Widget? Function(int index)? labelFor;

  /// One line over a list row. Rows without it carry [footerFor] instead.
  final Widget? Function(int index)? rowLabelFor;

  /// The live batch a streaming game subscribes on. Asked only for games
  /// that can stream.
  final LiveGamesBatchKey? Function(int index)? liveBatchKeyFor;

  /// Whether a card may run the on-device engine for a position the eval
  /// caches do not have. Off on the hub pages: a preview of boards must not
  /// spin up an analysis per card.
  final bool allowStockfishFallback;

  /// A card's own long-press rows, in place of Pin, Share and My Space.
  final List<LibraryMenuAction> Function(BuildContext context, int index)?
  menuActionsFor;

  /// Wraps a card, its label included.
  final Widget Function(int index, Widget card)? wrapCard;

  /// Whether a card is behind the paywall.
  final bool Function(int index)? lockedFor;

  /// How many games a list of [length] draws in [mode] from [start].
  static int shownFor(
    GamesListViewMode mode,
    int length, {
    int? limit,
    int? boardLimit,
    int start = 0,
  }) {
    final left = math.max(0, length - start);
    final cap =
        mode == GamesListViewMode.chessBoard ? (boardLimit ?? limit) : limit;
    if (cap == null) return left;
    return cap.clamp(0, left);
  }

  Widget _badged(int index, Widget card) {
    final badge = badgeFor;
    if (badge == null) return card;
    return BoardCornerBadge(
      builder: (boardSize) => badge(index, boardSize),
      child: card,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final viewMode = ref.watch(gamesListViewModeProvider);
    final shown = shownFor(
      viewMode,
      games.length,
      limit: limit,
      boardLimit: boardLimit,
      start: start,
    );
    final end = start + shown;

    // Which cards subscribe, and on which batch. A caller's batch serves
    // its group; without one, a capped list keys a batch over the games it
    // shows, so the cards past the cap never join a channel.
    final batchFor = liveBatchKeyFor;
    final shownBatch =
        batchFor == null && streamEnabled && shown < games.length
            ? liveBatchKeysForGames(
              games: games.sublist(start, end),
              scopePrefix: 'discovery_list',
            )
            : null;
    bool streams(GamesTourModel game) =>
        streamEnabled &&
        (batchFor == null || shouldSubscribeToLiveGame(game));
    LiveGamesBatchKey? batch(int index) {
      final game = games[index];
      if (!streams(game) || !shouldSubscribeToLiveGame(game)) return null;
      return batchFor != null ? batchFor(index) : shownBatch?[game.gameId];
    }

    final rows = viewMode == GamesListViewMode.gamesCard;
    final label = rows ? rowLabelFor : labelFor;
    final labelled = label != null || lockedFor != null;
    final slot = labelled ? _labelSlotHeight(context) : 0.0;
    final menu = menuActionsFor;

    bool locked(int index) => lockedFor?.call(index) ?? false;

    Widget? labelOf(int index) {
      final line = label?.call(index);
      if (!locked(index)) return line;
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (line != null) ...[
            Flexible(child: line),
            SizedBox(width: DiscoveryPadlock.gap),
          ],
          const DiscoveryPadlock(),
        ],
      );
    }

    Widget finish(int index, Widget card) {
      var out = card;
      if (locked(index)) {
        out = Semantics(
          label: 'Premium game',
          child: ColorFiltered(colorFilter: _greyscale, child: out),
        );
      }
      final wrap = wrapCard;
      return wrap == null ? out : wrap(index, out);
    }

    Widget listCard(int index, {required bool board}) {
      final game = games[index];
      final open = onOpen;
      final rowLabelled = !board && labelled;
      final card = _badged(
        index,
        GameCardWrapperWidget(
          key: ValueKey('discovery_${board ? 'board' : 'row'}_${game.gameId}'),
          game: game,
          gamesData: GamesScreenModel(
            gamesTourModels: games,
            pinnedGamedIs: const [],
          ),
          gameIndex: index,
          isChessBoardVisible: board,
          viewSource: ChessboardView.forYou,
          navigationListPolicy: BoardNavigationListPolicy.preserve,
          playerProfileDataSource: discoveryProfileSource(game),
          streamEnabled: streams(game),
          liveBatchKey: batch(index),
          allowStockfishFallback: allowStockfishFallback,
          // The strip's own line for a game with no clock or move to show.
          // A row that says its piece over itself fills it with the opening
          // and the day rather than leaving it blank.
          footerDetail:
              footerFor?.call(index) ??
              (rowLabelled
                  ? _defaultFooterDetail(game)
                  : null),
          // No tour scope to pin into, so the menu drops the row.
          showPin: false,
          onPinToggle: (_) async {},
          menuActions:
              menu == null ? null : (menuContext) => menu(menuContext, index),
          onBeforeOpen:
              open == null
                  ? null
                  : () async {
                    open(games, index);
                    return false;
                  },
          onReturnFromChessboard: (_) {},
        ),
      );
      if (!labelled) return finish(index, card);
      return finish(
        index,
        _labelled(
          slot: slot,
          label: labelOf(index),
          card: card,
          inset: board ? _boardCardInset : _rowInset,
        ),
      );
    }

    Widget gridCard(int index) {
      final game = games[index];
      final card = _badged(
        index,
        GridGameCardWrapperWidget(
          key: ValueKey('discovery_grid_${game.gameId}'),
          game: game,
          orderedGames: games,
          gameIndex: index,
          streamEnabled: streams(game),
          liveBatchKey: batch(index),
          allowStockfishFallback: allowStockfishFallback,
          viewSource: ChessboardView.forYou,
          playerProfileDataSource: discoveryProfileSource(game),
          pinnedIds: const [],
          showPin: false,
          onPinToggle: (_) {},
          menuActions:
              menu == null ? null : (menuContext) => menu(menuContext, index),
          onChangedWithLiveGames: (updated) {
            final open = onOpen;
            if (open != null) {
              open(updated, index);
            } else {
              openDiscoveryGame(context, ref, updated, index);
            }
          },
        ),
      );
      if (!labelled) return finish(index, card);
      return finish(
        index,
        _labelled(slot: slot, label: labelOf(index), card: card),
      );
    }

    final out = <Widget>[];
    if (viewMode == GamesListViewMode.chessBoardGrid) {
      // In the list's own order, the order previous/next walks: boards two
      // to a row, every game the same grid card as the event Games tab
      // draws it (a game that has not started shows its starting board),
      // so the user's chosen card type is the only one on screen.
      final pending = <int>[];
      void flush() {
        if (pending.isEmpty) return;
        final left = pending[0];
        final right = pending.length > 1 ? pending[1] : null;
        out.add(
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: gridCard(left)),
              SizedBox(width: _cardGap),
              Expanded(
                child: right == null ? const SizedBox.shrink() : gridCard(right),
              ),
            ],
          ),
        );
        pending.clear();
      }

      for (var i = start; i < end; i++) {
        pending.add(i);
        if (pending.length == 2) flush();
      }
      flush();
    } else {
      // List rows or full boards, exactly as chosen, for every game.
      final boardView = viewMode == GamesListViewMode.chessBoard;
      for (var i = start; i < end; i++) {
        out.add(listCard(i, board: boardView));
      }
    }
    final column = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < out.length; i++) ...[
          if (i > 0) SizedBox(height: _cardGap),
          out[i],
        ],
      ],
    );
    if (!padded) return column;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: discoveryGutter),
      child: column,
    );
  }
}

/// Greyscale for a card behind the paywall.
const ColorFilter _greyscale = ColorFilter.matrix(<double>[
  0.2126, 0.7152, 0.0722, 0, 0, //
  0.2126, 0.7152, 0.0722, 0, 0, //
  0.2126, 0.7152, 0.0722, 0, 0, //
  0, 0, 0, 0.6, 0, //
]);

/// [DiscoveryGameList] while its games load: the same cards in the same
/// view, as plates of their loaded size, so nothing moves when the games
/// land.
///
/// Grid view: two cards a row, each its two player lines and its board
/// (with the eval bar's width when the viewer shows it). List view: the
/// compact row. Board view: [boardCount] (else [count]) boards. [labels]
/// keeps the one-line label slot over each grid and board card; [padded]
/// matches the list's.
///
/// The plates assume every game has a position, as a preview's games do; a
/// board-view card whose players have running clocks lands a couple of
/// pixels taller than its plate.
class DiscoveryGameListSkeleton extends ConsumerWidget {
  const DiscoveryGameListSkeleton({
    super.key,
    required this.count,
    this.boardCount,
    this.labels = false,
    this.rowLabels = false,
    this.padded = true,
  });

  /// Cards in list and grid view.
  final int count;

  /// Cards in board view; [count] when null.
  final int? boardCount;

  /// The label slot over grid and board cards ([DiscoveryGameList.labelFor]).
  final bool labels;

  /// The label slot over list rows ([DiscoveryGameList.rowLabelFor]).
  final bool rowLabels;
  final bool padded;

  /// The compact row: its 60.h player strip over its 24.h footer
  /// (`GameCard`).
  static double get _rowHeight => 60.h + 24.h;

  /// A grid card's player line (`PlayerFirstRowDetailWidget` in grid view)
  /// and the gap between it and the board.
  static double get _gridLine => 20.h;
  static double get _lineGap => 4.h;

  /// A board card's player line (`PlayerFirstRowDetailWidget` in list
  /// view): the tallest of the finished game's result (set on a fixed
  /// 14-point strut), the 10.h flag and the unscaled 8.5 name line.
  static double get _boardLine =>
      math.max(14.0, math.max(10.h, 8.5.f * 1.15));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(gamesListViewModeProvider);
    // The cards read the same setting to decide on their eval bar.
    final gauge = ref.watch(
      engineSettingsProviderNew.select(
        (s) => s.valueOrNull?.shouldShowEngineGaugeInGrid ?? true,
      ),
    );
    final n =
        mode == GamesListViewMode.chessBoard ? (boardCount ?? count) : count;
    final labelled =
        mode == GamesListViewMode.gamesCard ? rowLabels : labels;
    final slot = labelled ? _labelSlotHeight(context) : 0.0;
    final ink = context.colors.surfaceRecessed;

    Widget plate({
      required double width,
      required double height,
      required double radius,
    }) {
      return SizedBox(
        width: width,
        height: height,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: ink,
            borderRadius: BorderRadius.circular(radius),
          ),
        ),
      );
    }

    /// A line of text as a bar, set at the start of its [height].
    Widget line(double width, double height) {
      return SizedBox(
        height: height,
        child: Align(
          alignment: AlignmentDirectional.centerStart,
          child: plate(width: width, height: 8.w, radius: 2.br),
        ),
      );
    }

    Widget labelledPlate(Widget card, double width, {double inset = 0}) {
      if (!labelled) return card;
      return _labelled(
        slot: slot,
        label: plate(width: width * 0.55, height: slot * 0.6, radius: 3.br),
        card: card,
        inset: inset,
      );
    }

    final body = LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final rows = <Widget>[];
        switch (mode) {
          case GamesListViewMode.gamesCard:
            for (var i = 0; i < n; i++) {
              rows.add(
                labelledPlate(
                  plate(width: width, height: _rowHeight, radius: 12.br),
                  width - 2 * _rowInset,
                  inset: _rowInset,
                ),
              );
            }
          case GamesListViewMode.chessBoardGrid:
            final cell = (width - _cardGap) / 2;
            // On phones the grid card sizes itself from the screen, whatever
            // its slot ([discoveryGridCardWidth]); on tablets it fills it.
            final cardWidth =
                ResponsiveHelper.isPhone
                    ? discoveryGridCardWidth(context)
                    : cell;
            final board = cardWidth - (gauge ? 10.w : 0);
            final shown = cardWidth.clamp(0.0, cell);
            Widget card() => labelledPlate(
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  line(shown * 0.6, _gridLine),
                  SizedBox(height: _lineGap),
                  plate(width: shown, height: board, radius: 4.br),
                  SizedBox(height: _lineGap),
                  line(shown * 0.6, _gridLine),
                ],
              ),
              shown,
            );
            for (var r = 0; r < n; r += 2) {
              rows.add(
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: card()),
                    SizedBox(width: _cardGap),
                    Expanded(
                      child: r + 1 < n ? card() : const SizedBox.shrink(),
                    ),
                  ],
                ),
              );
            }
          case GamesListViewMode.chessBoard:
            final inner = width - 2 * _boardCardInset;
            final board = inner - (gauge ? 20.w : 0);
            for (var i = 0; i < n; i++) {
              rows.add(
                labelledPlate(
                  Padding(
                    padding: EdgeInsets.only(
                      left: _boardCardInset,
                      right: _boardCardInset,
                      bottom: 8.sp,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        line(inner * 0.45, _boardLine),
                        SizedBox(height: _lineGap),
                        plate(width: inner, height: board, radius: 4.br),
                        SizedBox(height: _lineGap),
                        line(inner * 0.45, _boardLine),
                      ],
                    ),
                  ),
                  inner,
                  inset: _boardCardInset,
                ),
              );
            }
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < rows.length; i++) ...[
              if (i > 0) SizedBox(height: _cardGap),
              rows[i],
            ],
          ],
        );
      },
    );

    final skeleton = Semantics(
      container: true,
      label: 'Loading games',
      child: ExcludeSemantics(child: SkeletonWidget(child: body)),
    );
    if (!padded) return skeleton;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: discoveryGutter),
      child: skeleton,
    );
  }
}
