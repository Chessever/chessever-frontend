import 'package:chessever2/screens/chessboard/provider/chess_board_screen_provider_new.dart';
import 'package:chessever2/screens/for_you/discovery/models/discovery_models.dart';
import 'package:chessever2/screens/for_you/discovery/widgets/discovery_common.dart';
import 'package:chessever2/screens/my_space/widgets/space_glyphs.dart';
import 'package:chessever2/screens/player_profile/player_profile_data_source.dart';
import 'package:chessever2/screens/streaks/widgets/wall_common.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/game_card_wrapper/game_card_wrapper_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/game_card_wrapper/game_card_wrapper_widget.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/game_card_wrapper/grid_game_card_wrapper_widget.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/responsive_helper.dart';
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

/// One game on a Discovery rail: the app's grid game card at its own width,
/// with an optional label above it and, when [locked], the Premium padlock
/// after that label. The board itself is never covered: a notch over h8
/// would hide a castled king.
class DiscoveryGridGame extends ConsumerWidget {
  const DiscoveryGridGame({
    super.key,
    required this.games,
    required this.index,
    required this.onOpen,
    this.label,
    this.locked = false,
  });

  /// The whole rail, in order: the board walks it with previous/next.
  final List<GamesTourModel> games;
  final int index;
  final void Function(List<GamesTourModel> games, int index) onOpen;
  final Widget? label;
  final bool locked;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final game = games[index];
    final width = discoveryGridCardWidth(context);

    final card = GridGameCardWrapperWidget(
      game: game,
      orderedGames: games,
      gameIndex: index,
      // Archive rails: no realtime subscription and no on-device engine
      // fill-in, so a page of boards never spins up a dozen analyses.
      streamEnabled: false,
      allowStockfishFallback: false,
      showPin: false,
      pinnedIds: const [],
      onPinToggle: (_) {},
      viewSource: ChessboardView.forYou,
      playerProfileDataSource: discoveryProfileSource(game),
      onChangedWithLiveGames: (updated) => onOpen(updated, index),
    );

    return SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (locked)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (label != null) ...[
                  Flexible(child: label!),
                  SizedBox(width: 5.w),
                ],
                const DiscoveryPadlock(),
              ],
            )
          else if (label != null)
            label!,
          if (label != null || locked) SizedBox(height: 8.w),
          Semantics(label: locked ? 'Premium game review' : null, child: card),
        ],
      ),
    );
  }
}

/// A full-width game: the app's board card when the game has a real position
/// to draw, else its compact card (players and result, no board).
class DiscoveryWideGame extends ConsumerWidget {
  const DiscoveryWideGame({
    super.key,
    required this.games,
    required this.index,
    required this.showBoard,
    this.label,
    this.footerDetail,
  });

  final List<GamesTourModel> games;
  final int index;
  final bool showBoard;
  final Widget? label;

  /// The compact card's footer line. Defaults to [_defaultFooterDetail]:
  /// these games have no clock and no last move, so the strip would
  /// otherwise sit blank.
  final String? footerDetail;

  /// "Sicilian Defense · Sep 23": the opening (or its ECO code) and the day.
  static String? _defaultFooterDetail(GamesTourModel game) {
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final game = games[index];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (label != null) ...[label!, SizedBox(height: 8.w)],
        GameCardWrapperWidget(
          game: game,
          gamesData: GamesScreenModel(
            gamesTourModels: games,
            pinnedGamedIs: const [],
          ),
          gameIndex: index,
          isChessBoardVisible: showBoard,
          viewSource: ChessboardView.forYou,
          navigationListPolicy: BoardNavigationListPolicy.preserve,
          playerProfileDataSource: discoveryProfileSource(game),
          streamEnabled: false,
          allowStockfishFallback: false,
          showPin: false,
          footerDetail: footerDetail ?? _defaultFooterDetail(game),
        ),
      ],
    );
  }
}
