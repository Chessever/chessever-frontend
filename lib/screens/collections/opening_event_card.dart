import 'package:chessever2/repository/gamebase/collections/collections_models.dart';
import 'package:chessever2/screens/chessboard/widgets/chess_board_from_fen_new.dart'
    show GameCardChessboard;
import 'package:chessever2/screens/collections/collection_plate_row.dart';
import 'package:chessever2/utils/eco_openings.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/card_context_menu.dart';
import 'package:chessever2/widgets/space_shortcut_drafts.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter/material.dart';

String collectionOpeningName(CollectionOpening opening) =>
    opening.name ?? EcoOpenings.getOpeningName(opening.eco) ?? opening.eco;

/// A real opening position in the event-card frame. No engine work is needed
/// for this visual index: the board reflects the reader's piece/board theme.
class OpeningEventCard extends StatelessWidget {
  const OpeningEventCard({
    super.key,
    required this.name,
    required this.onTap,
    this.eco,
    this.fen,
    this.lastMove,
    this.caption,
    this.gameCount,
    this.bookCount,
    this.menuActions,
  });

  final String name;
  final String? eco;
  final String? fen;
  final Move? lastMove;
  final String? caption;
  final int? gameCount;
  final int? bookCount;
  final VoidCallback onTap;
  final CardMenuActionsBuilder? menuActions;

  @override
  Widget build(BuildContext context) {
    final moves = eco == null
        ? const <String>[]
        : spaceEcoMovePath(eco!.split('-').first);
    final position = fen ?? spaceFenAfter(moves);
    final size = 88.w;
    final counts = [
      if (gameCount != null) '$gameCount ${gameCount == 1 ? 'game' : 'games'}',
      if (bookCount != null) '$bookCount ${bookCount == 1 ? 'book' : 'books'}',
    ].join(' · ');
    final line = [
      if (eco != null && !name.startsWith(eco!)) eco!,
      if (caption != null && caption!.isNotEmpty && caption != eco) caption!,
    ].join(' · ');
    return CollectionPlateRow(
      plate: GameCardChessboard(
        fen: position,
        lastMove: lastMove,
        boardSize: size,
        orientation: Side.white,
        showCoordinates: false,
        animateEnding: false,
      ),
      plateSize: Size.square(size),
      title: name,
      meta: line.isEmpty ? null : line,
      metaMaxLines: 2,
      tally: counts.isEmpty ? null : counts,
      semanticsLabel: [
        name,
        line,
        counts,
      ].where((s) => s.isNotEmpty).join(', '),
      onTap: onTap,
      menuActions: menuActions,
    );
  }
}
