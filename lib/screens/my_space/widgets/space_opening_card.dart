import 'package:chessever2/screens/chessboard/widgets/chess_board_from_fen_new.dart'
    show PositionCardBoard, gameBoardCardPadding, gameGridCardPhoneWidth;
import 'package:chessever2/screens/chessboard/widgets/player_first_row_detail_widget.dart'
    show PlayerView;
import 'package:chessever2/screens/library/widgets/library_context_menu.dart';
import 'package:chessever2/screens/my_space/actions/space_menu_action.dart';
import 'package:chessever2/screens/my_space/models/space_shortcut.dart';
import 'package:chessever2/screens/my_space/navigation/space_shortcut_navigator.dart';
import 'package:chessever2/screens/my_space/widgets/space_tile_content.dart'
    show spaceOpeningFace;
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_list_view_mode_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/game_card.dart'
    show GameCardFrame;
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/app_button.dart' show TappableScale;
import 'package:chessever2/widgets/card_context_menu.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// A saved opening, position or player line, drawn as the game card of the
/// viewer's games view setting, with the opening where the players stand:
/// on the grid and board cards the real board (the viewer's board theme and
/// piece set, the engine gauge in its lane, both through
/// [PositionCardBoard]) at the line's indicative position with its last move
/// marked, the opening's name and ECO over it and the line under it ("After
/// 4.Nf3"); on the compact row, which draws no board for a game either, the
/// name, ECO and line in the row's own slots. Tap opens the line in the
/// explorer; a long press lifts it into the focus menu with Open and My
/// Space.
class SpaceOpeningCard extends ConsumerWidget {
  const SpaceOpeningCard({super.key, required this.shortcut});

  final SpaceShortcut shortcut;

  void _open(BuildContext context, WidgetRef ref) {
    HapticFeedbackService.cardTap();
    openSpaceShortcut(context, ref, shortcut);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(gamesListViewModeProvider);
    final face = spaceOpeningFace(shortcut);
    final body = switch (mode) {
      GamesListViewMode.chessBoardGrid => _GridFace(face: face),
      GamesListViewMode.gamesCard => _RowFace(
        face: face,
        kind: _kindLabel(shortcut.kind),
      ),
      GamesListViewMode.chessBoard => _BoardFace(face: face),
    };
    final said = [
      face.name,
      if (face.eco != null) face.eco!,
      if (face.caption.isNotEmpty) face.caption,
    ].join(', ');
    return Semantics(
      button: true,
      label: said,
      excludeSemantics: true,
      onTap: () => _open(context, ref),
      child: TappableScale(
        onTap: () => _open(context, ref),
        child: CardContextMenu(
          onPreviewTap: () => _open(context, ref),
          actions: (menuContext) => [
            LibraryMenuAction(
              icon: Icons.open_in_new_rounded,
              label: 'Open',
              onSelected: () => _open(context, ref),
            ),
            spaceMenuAction(context: menuContext, ref: ref, draft: shortcut),
          ],
          child: ColoredBox(color: Colors.transparent, child: body),
        ),
      ),
    );
  }
}

/// What a saved line is, on the row's second line.
String _kindLabel(SpaceShortcutKind kind) => switch (kind) {
  SpaceShortcutKind.playerOpenings => 'Player line',
  SpaceShortcutKind.position => 'Position',
  _ => 'Opening',
};

typedef _Face = ({
  String name,
  String? eco,
  String? fen,
  Move? lastMove,
  String caption,
});

/// The name line: the opening in full ink, its ECO after it in quiet ink
/// unless the name already starts with it. The code always stays whole; a
/// long name gives way with an ellipsis before it, and the code follows the
/// ellipsis at the same gap it keeps after a whole name.
class _NameLine extends StatelessWidget {
  const _NameLine({required this.face, required this.style});

  final _Face face;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final eco = face.eco;
    final showEco = eco != null && !face.name.startsWith(eco);
    return Row(
      children: [
        Flexible(
          child: Text(
            face.name,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
            // A cut name measures to its ellipsis, not to the room it was
            // given, so the ECO sits right after the visible text.
            textWidthBasis: TextWidthBasis.longestLine,
            style: style,
          ),
        ),
        if (showEco) ...[
          SizedBox(width: 6.w),
          Text(
            eco,
            maxLines: 1,
            softWrap: false,
            style: style.copyWith(
              fontWeight: FontWeight.w600,
              color: context.colors.textSecondary,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ],
    );
  }
}

/// The line ("After 5...a6"), where a game card has its second player.
class _CaptionLine extends StatelessWidget {
  const _CaptionLine({required this.face, required this.style});

  final _Face face;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    return Text(
      face.caption,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: style,
    );
  }
}

/// Grid view: the grid game card's anatomy and size, with the opening where
/// the players stand: its name over the board, the line under it, and the
/// board beside the engine gauge exactly as a grid game card sets it
/// ([PositionCardBoard]), so an opening sits level with the games around it.
/// The two lines start on the board's edge.
class _GridFace extends ConsumerWidget {
  const _GridFace({required this.face});

  final _Face face;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lane = PositionCardBoard.laneOf(ref, PlayerView.gridView);
    final strong = AppTypography.textXsMedium.copyWith(
      fontSize: 12.f,
      height: 16 / 12,
      fontWeight: FontWeight.w700,
      color: context.colors.textPrimary,
    );
    final quiet = strong.copyWith(
      fontWeight: FontWeight.w500,
      color: context.colors.textSecondary,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = ResponsiveHelper.isPhone
            ? gameGridCardPhoneWidth(context).clamp(0.0, constraints.maxWidth)
            : constraints.maxWidth;
        Widget line(Widget child) => SizedBox(
          height: 20.h,
          child: Padding(
            padding: EdgeInsets.only(left: lane),
            child: Align(alignment: Alignment.centerLeft, child: child),
          ),
        );
        return Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: width,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                line(_NameLine(face: face, style: strong)),
                SizedBox(height: 4.h),
                PositionCardBoard(
                  fen: face.fen,
                  lastMove: face.lastMove,
                  width: width,
                  view: PlayerView.gridView,
                ),
                SizedBox(height: 4.h),
                line(_CaptionLine(face: face, style: quiet)),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// List view: the compact game row itself ([GameCardFrame]). A game row
/// draws no board, and neither does this one: the opening's name where the
/// first player's name stands, its ECO and kind where the rating goes, and
/// the line ("After 5...a6") where a game's last move sits.
class _RowFace extends StatelessWidget {
  const _RowFace({required this.face, required this.kind});

  final _Face face;
  final String kind;

  @override
  Widget build(BuildContext context) {
    return GameCardFrame(
      start: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            face.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GameCardFrame.nameStyle(context),
          ),
          Text(
            face.eco == null ? kind : '${face.eco} · $kind',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GameCardFrame.detailStyle(
              context,
            ).copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
          ),
        ],
      ),
      footer: Text(
        face.caption,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: GameCardFrame.footerStyle(context),
      ),
    );
  }
}

/// Board view: the full board card's inset and anatomy ([gameBoardCardPadding]),
/// the board beside the engine gauge as a full board game card sets it
/// ([PositionCardBoard]), and the name and line on the board's edge, where
/// a game's player rows start.
class _BoardFace extends ConsumerWidget {
  const _BoardFace({required this.face});

  final _Face face;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final lane = PositionCardBoard.laneOf(ref, PlayerView.listView);
    final strong = AppTypography.textSmMedium.copyWith(
      fontSize: 13.f,
      height: 18 / 13,
      fontWeight: FontWeight.w700,
      color: colors.textPrimary,
    );
    final quiet = AppTypography.textXsMedium.copyWith(
      color: colors.textSecondary,
    );
    return Padding(
      padding: gameBoardCardPadding,
      child: LayoutBuilder(
        builder: (context, constraints) {
          Widget line(Widget child) => Padding(
            padding: EdgeInsets.only(left: lane),
            child: child,
          );
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              line(_NameLine(face: face, style: strong)),
              SizedBox(height: 6.h),
              PositionCardBoard(
                fen: face.fen,
                lastMove: face.lastMove,
                width: constraints.maxWidth,
                view: PlayerView.listView,
              ),
              SizedBox(height: 6.h),
              line(_CaptionLine(face: face, style: quiet)),
            ],
          );
        },
      ),
    );
  }
}
