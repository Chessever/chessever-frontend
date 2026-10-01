/// Stable wire keys shared with the optional Cloudflare game-story metadata.
/// Stories can overlap; length is independent. Null means All Reports.
enum ReportGameType {
  upsideDown(
    'upside_down',
    'Upside Down',
    'Control changes sides multiple times.',
  ),
  comeback(
    'comeback',
    'Comeback',
    'The winner recovers from a clearly losing position.',
  ),
  oneBlunder(
    'one_blunder',
    'One Blunder',
    'One major mistake creates a lasting losing position.',
  ),
  greatEscape(
    'great_escape',
    'Great Escape',
    'A player saves a draw from a clearly losing position.',
  ),
  domination(
    'domination',
    'Domination',
    'The winner holds a clear advantage for much of the game.',
  ),
  squeeze(
    'squeeze',
    'Squeeze',
    'The winner gradually builds an edge and converts it.',
  ),
  deadlock('deadlock', 'Deadlock', 'A broadly balanced game ends in a draw.'),
  miniature(
    'miniature',
    'Miniature',
    'A decisive game that finishes in under 25 moves.',
  ),
  marathon(
    'marathon',
    'Marathon',
    'A completed game lasting 80 moves or more.',
  );

  const ReportGameType(this.key, this.label, this.description);
  final String key;
  final String label;
  final String description;
}

class ReportGameTypesUnavailable implements Exception {
  const ReportGameTypesUnavailable();
}
