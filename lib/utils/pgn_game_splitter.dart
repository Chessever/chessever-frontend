final _tagLine = RegExp(r'^\s*\[\s*([A-Za-z0-9_]+)\s+"');

/// Splits a PGN database into its games (trimmed), as the standard reads it:
/// a game is a tag section and the movetext after it, so a new one starts at
/// the first tag line once movetext has begun. No tag is required: files
/// whose games open with `[Date` or `[White` and never name an `[Event` are
/// common, and splitting at `[Event` alone read such a file as one game.
///
/// Brace comments may run over lines and `;` comments to the end of one;
/// neither starts a game. `%` lines are escapes and are left out.
///
/// Two cases the rule above does not reach, both at a tag line that follows a
/// blank line:
/// - the game already has that tag: the game before it had no movetext at
///   all, not even a result;
/// - a comment is still open: its `}` is missing, and the rest of the file
///   is not that comment.
List<String> splitPgnGames(String text) {
  final games = <String>[];
  final current = StringBuffer();
  final tags = <String>{};
  var moves = false;
  var inComment = false;
  var afterBlank = false;

  void close() {
    final game = current.toString().trim();
    current.clear();
    tags.clear();
    moves = false;
    if (game.isNotEmpty) games.add(game);
  }

  final source = text.startsWith('\uFEFF') ? text.substring(1) : text;
  final lines = source.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  for (final line in lines.split('\n')) {
    final blank = line.trim().isEmpty;
    final tag = inComment && !afterBlank
        ? null
        : _tagLine.firstMatch(line)?.group(1);
    if (tag != null) {
      inComment = false;
      if (moves || (afterBlank && tags.contains(tag))) close();
      tags.add(tag);
      current.writeln(line);
      afterBlank = false;
      continue;
    }
    afterBlank = blank;
    if (!inComment && line.startsWith('%')) continue;
    for (var i = 0; i < line.length; i++) {
      final c = line[i];
      if (inComment) {
        if (c == '}') inComment = false;
      } else if (c == '{') {
        inComment = true;
      } else if (c == ';') {
        break;
      } else if (c.trim().isNotEmpty) {
        moves = true;
      }
    }
    current.writeln(line);
  }
  close();
  return games;
}
