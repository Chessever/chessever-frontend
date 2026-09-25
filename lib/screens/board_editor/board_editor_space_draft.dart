import 'package:chessever2/screens/gamebase/utils/space_position_draft.dart';
import 'package:chessever2/screens/my_space/models/space_shortcut.dart';
import 'package:chessever2/screens/my_space/navigation/space_shortcut_navigator.dart'
    show resolveSpaceLine;
import 'package:chessever2/utils/eco_openings.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Every named line in the ECO catalogue, keyed by the position it ends on
/// (the first four FEN fields: board, side to move, castling, en passant).
/// A position two lines reach by transposition keeps the deeper line.
///
/// Built off the UI isolate: replaying ~1.8k lines is a noticeable pause on a
/// phone's main thread.
final ecoPositionIndexProvider = FutureProvider<Map<String, EcoOpeningRecord>>(
  (ref) => compute(_buildIndex, null),
);

Map<String, EcoOpeningRecord> _buildIndex(void _) => buildEcoPositionIndex();

/// Synchronous [ecoPositionIndexProvider] body, for tests and the isolate.
Map<String, EcoOpeningRecord> buildEcoPositionIndex() {
  final index = <String, EcoOpeningRecord>{};
  final depth = <String, int>{};
  for (final record in EcoOpenings.exactCatalog) {
    final tokens = EcoOpenings.moveTokens(record.moves);
    if (tokens.isEmpty) continue;
    Position position = Chess.initial;
    var legal = true;
    for (final san in tokens) {
      final move = position.parseSan(san);
      if (move == null) {
        legal = false;
        break;
      }
      position = position.play(move);
    }
    if (!legal) continue;
    final key = ecoPositionKey(position.fen);
    if ((depth[key] ?? -1) >= tokens.length) continue;
    index[key] = record;
    depth[key] = tokens.length;
  }
  return index;
}

/// The part of [fen] that names a position regardless of move counters,
/// normalized through dartchess when the position is legal (so an en
/// passant square nobody can use does not split two equal positions).
String ecoPositionKey(String fen) {
  String firstFour(String value) =>
      value.trim().split(RegExp(r'\s+')).take(4).join(' ');
  try {
    return firstFour(Chess.fromSetup(Setup.parseFen(fen)).fen);
  } catch (_) {
    return firstFour(fen);
  }
}

/// What "Add to My Space" saves for the board editor's position: the
/// position itself (kind `position`, keyed by its FEN), the same shortcut the
/// seeded defaults, the + picker and search save for a catalogue line, so the
/// added state and dedupe agree on every surface. An ECO code key would be
/// shared by every line with that code and by aggregate code pins.
///
/// When [index] names the position the draft carries that line's moves (it
/// reopens on them) and its catalogue name; otherwise it is a
/// "Custom position". [index] may be null while it is still being built:
/// the key is the same either way, only the title and line wait for it.
///
/// The FEN is rendered by dartchess first, like every replayed line, so a
/// castling right or en passant square the position cannot use does not split
/// one position into two shortcuts.
SpaceShortcut? boardEditorSpaceDraft(
  String fen,
  Map<String, EcoOpeningRecord>? index,
) {
  final trimmed = fen.trim();
  if (trimmed.isEmpty) return null;
  final target = _dartchessFen(trimmed);
  final record = index?[ecoPositionKey(target)];
  if (record == null) {
    return spacePositionDraft(fen: target, startingFen: target);
  }
  final line = resolveSpaceLine(
    fen: target,
    moves: EcoOpenings.moveTokens(record.moves),
  );
  final draft = spacePositionDraft(fen: target, ucis: line?.ucis ?? const []);
  if (draft == null) return null;
  // The subtitle leads with the code of the first catalogue row on this move
  // path, which a few duplicated paths give a different code than [record].
  final rest = (draft.subtitle ?? '').split(' · ')
    ..removeWhere((part) => part.isEmpty || part == draft.params['eco']);
  return draft.copyWith(
    title: record.name,
    subtitle: [record.code, ...rest].join(' · '),
    params: {...draft.params, 'eco': record.code, 'openingName': record.name},
  );
}

/// [fen] as dartchess writes it (move counters kept), or as given when it is
/// not a legal position.
String _dartchessFen(String fen) {
  try {
    return Chess.fromSetup(Setup.parseFen(fen)).fen;
  } catch (_) {
    return fen;
  }
}
