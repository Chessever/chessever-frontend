import 'package:chessever2/screens/gamebase/models/models.dart';
import 'package:chessever2/screens/my_space/models/space_shortcut.dart';
import 'package:chessever2/screens/my_space/navigation/space_shortcut_navigator.dart';
import 'package:dartchess/dartchess.dart';

/// One explorer position as a My Space `position` shortcut: the FEN as the
/// identity, the UCI line that reaches it, the deepest named opening on that
/// line, and the player the tree is scoped to.
///
/// Shared by the explorer's own menu and the board's notation long-press, so
/// "Add position" on 12...Nf6 in a game and the same line in the explorer
/// dedupe to one shortcut.
///
/// [ucis] are only trusted when the line starts from the standard position
/// ([startingFen] null or the initial board). A Board Editor setup has no line
/// from the start; it saves as a bare FEN and reopens by FEN alone.
///
/// Returns null when [fen] is empty.
SpaceShortcut? spacePositionDraft({
  required String fen,
  List<String> ucis = const <String>[],
  String? startingFen,
  GamebasePlayer? player,
}) {
  final targetFen = fen.trim();
  if (targetFen.isEmpty) return null;

  final fromStart =
      startingFen == null ||
      startingFen.split(' ').first == Chess.initial.fen.split(' ').first;
  final line = fromStart ? ucis : const <String>[];
  final sans = spaceSansForUcis(line);
  final opening = spaceOpeningForSans(sans);

  final ply = sans.length;
  final moveNumber = ply > 0 ? (ply + 1) ~/ 2 : _fullmoveNumber(targetFen);
  final String title;
  if (opening != null) {
    title = opening.name;
  } else if (ply > 0) {
    final separator = ply.isOdd ? '. ' : '...';
    title = 'Position after $moveNumber$separator${sans.last}';
  } else if (!fromStart) {
    title = 'Custom position';
  } else {
    title =
        targetFen.split(' ').first == Chess.initial.fen.split(' ').first
            ? 'Starting position'
            : 'Position';
  }
  final subtitle = [
    opening?.code,
    'Move $moveNumber',
    if (player != null) player.displayName,
  ].whereType<String>().join(' · ');

  return SpaceShortcut.draft(
    kind: SpaceShortcutKind.position,
    targetId: targetFen,
    title: title,
    subtitle: subtitle,
    params: {
      if (line.isNotEmpty) 'moves': line,
      if (sans.isNotEmpty) 'sans': sans,
      if (opening != null) 'eco': opening.code,
      if (opening != null) 'openingName': opening.name,
      if (player != null) 'playerId': player.id,
      if (player != null) 'playerName': player.name,
      if (player != null && player.fideId.isNotEmpty)
        'playerFideId': player.fideId,
    },
  );
}

int _fullmoveNumber(String fen) {
  final parts = fen.trim().split(RegExp(r'\s+'));
  return parts.length >= 6 ? (int.tryParse(parts[5]) ?? 1) : 1;
}
