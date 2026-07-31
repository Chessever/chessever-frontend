/// Restores the `N...` indicator before a black move that follows a comment.
///
/// PGN's export format requires a move-number indicator whenever a black move
/// does not directly follow its white counterpart — after a comment, a NAG, or
/// a closing variation. `dartchess` emits one after NAGs and variations but not
/// after comments, so a game with clocks exports as
///
///     1. b3 { [%clk 1:30:53] } d6 { [%clk 1:29:21] } 2. Bb2 …
///
/// where the standard (and every other producer) writes `1... d6`. Lenient
/// readers cope; strict ones misalign the comments that follow onto the wrong
/// ply, which loses annotations rather than failing loudly.
///
/// The pass is text-level on purpose — it is the last step before the PGN
/// leaves the app, so it protects every export path at once.
String restoreBlackMoveNumbers(String movetext) {
  if (movetext.isEmpty) return movetext;

  final out = StringBuffer();
  // Ply parity per nesting level: variations restore the parent's counters on
  // close. dartchess always writes an explicit number after `(`, so a frame
  // only ever needs to carry what its own tokens established.
  final stack = <_Frame>[_Frame()];
  var index = 0;
  // Whether the next SAN would sit directly beside its white counterpart or a
  // move number. Anything else in between — a comment, a NAG, a variation —
  // breaks that adjacency, and the export format then wants the indicator.
  var adjacent = false;

  while (index < movetext.length) {
    final char = movetext[index];

    if (_isSpace(char)) {
      out.write(char);
      index++;
      continue;
    }

    if (char == '{') {
      final end = movetext.indexOf('}', index);
      final stop = end == -1 ? movetext.length : end + 1;
      out.write(movetext.substring(index, stop));
      index = stop;
      adjacent = false;
      continue;
    }

    if (char == ';') {
      // Rest-of-line comment.
      final end = movetext.indexOf('\n', index);
      final stop = end == -1 ? movetext.length : end;
      out.write(movetext.substring(index, stop));
      index = stop;
      adjacent = false;
      continue;
    }

    if (char == '(') {
      stack.add(_Frame());
      adjacent = false;
      out.write(char);
      index++;
      continue;
    }

    if (char == ')') {
      if (stack.length > 1) stack.removeLast();
      adjacent = false;
      out.write(char);
      index++;
      continue;
    }

    if (char == r'$') {
      final end = _scanToken(movetext, index);
      out.write(movetext.substring(index, end));
      index = end;
      adjacent = false;
      continue;
    }

    final end = _scanToken(movetext, index);
    final token = movetext.substring(index, end);
    final frame = stack.last;

    final number = _moveNumberToken(token);
    if (number != null) {
      frame.moveNumber = number.moveNumber;
      frame.blackToMove = number.blackToMove;
      frame.seenMove = true;
      adjacent = true;
      out.write(token);
      index = end;
      continue;
    }

    if (_isResultToken(token) || !_looksLikeSan(token)) {
      out.write(token);
      index = end;
      continue;
    }

    // A SAN. If it is black's and no number token introduced it, the reader
    // has nothing tying it to a move number — write the `N...` the standard
    // asks for.
    if (frame.seenMove && frame.blackToMove && !adjacent) {
      out.write('${frame.moveNumber}... ');
    }
    out.write(token);
    index = end;
    adjacent = true;

    if (!frame.seenMove) {
      // A movetext that opened without any number token (rare, but never
      // guess): assume white to move at move 1.
      frame.seenMove = true;
      frame.blackToMove = true;
    } else if (frame.blackToMove) {
      frame.blackToMove = false;
      frame.moveNumber += 1;
    } else {
      frame.blackToMove = true;
    }
  }

  return out.toString();
}

class _Frame {
  int moveNumber = 1;
  bool blackToMove = false;
  bool seenMove = false;
}

bool _isSpace(String char) =>
    char == ' ' || char == '\n' || char == '\r' || char == '\t';

int _scanToken(String text, int start) {
  var index = start;
  while (index < text.length) {
    final char = text[index];
    if (_isSpace(char) ||
        char == '{' ||
        char == '}' ||
        char == '(' ||
        char == ')' ||
        char == ';') {
      break;
    }
    index++;
  }
  return index == start ? start + 1 : index;
}

final RegExp _moveNumberPattern = RegExp(r'^(\d+)(\.+)(.*)$');
final RegExp _sanPattern = RegExp(
  r'^(?:[KQRBN][a-h1-8]{0,2}x?[a-h][1-8]'
  r'|[a-h]x?[a-h][1-8](?:=[QRBN])?'
  r'|[a-h][1-8](?:=[QRBN])?'
  r'|O-O(?:-O)?|0-0(?:-0)?)[+#]?[!?]*$',
);

({int moveNumber, bool blackToMove})? _moveNumberToken(String token) {
  final match = _moveNumberPattern.firstMatch(token);
  if (match == null) return null;
  final number = int.tryParse(match.group(1)!);
  if (number == null) return null;
  // `1.` introduces white, `1...` black. Trailing text (`1.e4`) counts as the
  // same move: dartchess never writes it, but an imported movetext might.
  return (moveNumber: number, blackToMove: match.group(2)!.length > 1);
}

bool _isResultToken(String token) =>
    token == '1-0' || token == '0-1' || token == '1/2-1/2' || token == '*';

bool _looksLikeSan(String token) => _sanPattern.hasMatch(token);
