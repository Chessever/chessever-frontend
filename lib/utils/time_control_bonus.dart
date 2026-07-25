import 'package:chessever2/utils/pgn_clock_utils.dart';

/// Secondary ("40-move") period of a classical tournament time control.
///
/// FIDE classical events are usually played at something like
/// `90 min / 40 moves + 30 min + 30 sec / move`: each player receives an extra
/// block of time the moment they *complete* their 40th move.
///
/// Broadcast relays credit that block late and inconsistently. The `[%clk]`
/// value recorded on move 40 is almost always the pre-bonus reading, and the
/// jump only surfaces on move 41 — sometimes as late as move 43, when an
/// arbiter adds it by hand. See [secondaryBonusOffsetSeconds] for how that is
/// reconciled.
class TimeControlSecondaryPeriod {
  const TimeControlSecondaryPeriod({
    required this.afterMoves,
    required this.bonusSeconds,
  });

  /// Move number a player must complete to be credited (typically 40).
  final int afterMoves;

  /// Extra time credited on completing [afterMoves] moves, in seconds.
  final int bonusSeconds;

  @override
  bool operator ==(Object other) =>
      other is TimeControlSecondaryPeriod &&
      other.afterMoves == afterMoves &&
      other.bonusSeconds == bonusSeconds;

  @override
  int get hashCode => Object.hash(afterMoves, bonusSeconds);

  @override
  String toString() =>
      'TimeControlSecondaryPeriod(afterMoves: $afterMoves, '
      'bonusSeconds: $bonusSeconds)';
}

/// Lower bound for a credible secondary block. Anything shorter is almost
/// certainly a misread increment ("+ 30 sec / move") rather than a time bonus.
const int _minBonusSeconds = 60;

/// Upper bound for a credible secondary block (2 hours).
const int _maxBonusSeconds = 7200;

const int _minAfterMoves = 10;
const int _maxAfterMoves = 80;

enum _TcUnit { minutes, seconds, moves }

class _TcToken {
  const _TcToken(this.value, this.unit);
  final int value;
  final _TcUnit unit;

  bool get isTime => unit == _TcUnit.minutes || unit == _TcUnit.seconds;
  int get seconds => unit == _TcUnit.minutes ? value * 60 : value;
}

/// Matches a number followed by a unit word. Longer spellings come first so the
/// alternation does not stop early (`minutes` before `min`, `seconds` before
/// `sec` before a bare `s`).
///
/// The trailing alternative covers the abbreviated `90'/40 + 30' + 30''` shape,
/// where the move count is a bare number behind a slash. It is guarded so it
/// never swallows a time period (`90 min / 40 moves` still reads as moves, and
/// `60 min / 30 min` is not mistaken for a move count).
final RegExp _tcTokenRegex = RegExp(
  r'(\d+)\s*'
  r'(minutes|minuten|minutos|minuti|mins|min|mn'
  r'|hours|hour|hrs|hr|h'
  r'|seconds|segundos|secondi|sekunden|seconds|secs|sec|segs|seg|s'
  r'|moves|move|movimenti|movimientos|movs|mov|mvs'
  r'|jugadas|coups|zuege|züge|zug|lepes|lépés|drag'
  r')(?![a-zà-ÿ])'
  r'|/\s*(\d{2})(?![0-9])(?!\s*(?:min|hour|hr|h\b|sec|seg|s\b))',
  caseSensitive: false,
);

/// Prose form of the secondary period, where the bonus is stated first and the
/// qualifying move last: `+30 min after move 40`, `15 minutes added after move
/// 40`, `30 min at move 40`.
///
/// The `[^0-9]{0,25}` bridge is deliberately digit-free so unrelated pairings
/// such as `120 min + 10 sec / move from move 41` (an increment start, not a
/// bonus) cannot be joined up.
/// US "sudden death" notation: `40/90, SD/30; +30`, `40/80/d30, SD30/d30`.
/// `SD` is unambiguous — it always names the final period's minutes — so the
/// numbers can be read positionally with no risk of confusing them for a base.
final RegExp _suddenDeathRegex = RegExp(
  r'^\s*(\d{1,2})\s*/\s*\d+[^;,]*[;,]\s*sd\s*/?\s*(\d+)',
  caseSensitive: false,
);

final RegExp _bonusAfterMoveRegex = RegExp(
  r'(\d+)\s*(minutes|minuten|minutos|minuti|mins|min|hours|hour|hrs|hr)\b'
  r'[^0-9]{0,25}\b(?:after|at|on|from)\s+move\s*(?:no\.?\s*)?(\d+)',
  caseSensitive: false,
);

/// `40 moves in 2 hours followed by 1 hour` puts the *base* period after the
/// move count, so the first time token behind the move count must be skipped.
final RegExp _movesInPhraseRegex = RegExp(
  r'\d+\s*(?:moves|move)\s+(?:in|en)\b',
  caseSensitive: false,
);

/// Some organisers stuff several per-round time controls into one string
/// (`Round 1-3: 25 min + 10 sec | Round 4-7: 90 min / 40 moves + 15 min`).
/// A single parse cannot describe those, so they are rejected outright rather
/// than misapplied to every round.
final RegExp _roundScopedRegex = RegExp(
  r'rounds?\s*\d+\s*[-–—]\s*\d+',
  caseSensitive: false,
);

/// Parses the secondary period out of a free-text tournament time control
/// (`tours.info->>'tc'`).
///
/// Returns `null` whenever the string does not *clearly* describe an extra
/// block of time granted after a move count. Guessing here would move clocks on
/// events that never had a second period, so every ambiguous shape is declined.
TimeControlSecondaryPeriod? parseSecondaryTimePeriod(String? tcText) {
  final raw = tcText?.trim();
  if (raw == null || raw.isEmpty) return null;

  // Per-round time controls cannot be represented by one period.
  if (raw.contains('|') || _roundScopedRegex.hasMatch(raw)) return null;

  final normalized = _normalizeTcText(raw);

  final suddenDeath = _suddenDeathRegex.firstMatch(normalized);
  if (suddenDeath != null) {
    final moves = int.tryParse(suddenDeath.group(1)!);
    final minutes = int.tryParse(suddenDeath.group(2)!);
    if (moves != null &&
        minutes != null &&
        moves >= _minAfterMoves &&
        moves <= _maxAfterMoves) {
      final period = _buildPeriod(
        afterMoves: moves,
        bonusSeconds: minutes * 60,
      );
      if (period != null) return period;
    }
  }

  final tokens = _tokenize(normalized);
  if (tokens.isEmpty) return null;

  final movesIndex = tokens.indexWhere(
    (t) =>
        t.unit == _TcUnit.moves &&
        t.value >= _minAfterMoves &&
        t.value <= _maxAfterMoves,
  );

  if (movesIndex >= 0) {
    final afterMoves = tokens[movesIndex].value;

    // Primary shape: the bonus follows the move count.
    //   "90 min / 40 moves + 30 min + 30 sec / move"
    var skip = _movesInPhraseRegex.hasMatch(normalized) ? 1 : 0;
    for (var i = movesIndex + 1; i < tokens.length; i++) {
      final token = tokens[i];
      if (token.unit != _TcUnit.minutes) continue;
      if (skip > 0) {
        skip--;
        continue;
      }
      final period = _buildPeriod(
        afterMoves: afterMoves,
        bonusSeconds: token.seconds,
      );
      if (period != null) return period;
      break;
    }

    // Secondary shape: the bonus precedes the move count.
    //   "90 min + 30 sec, +15 min after 40 moves"
    //   "90min/all + 30s/move + 30min/40moves"
    //
    // Only trusted when another time token sits further left, which is what
    // separates a real bonus from the *base* period in "90 min / 40 moves +
    // 30 sec / move" (where no bonus exists at all).
    if (movesIndex >= 2) {
      final candidate = tokens[movesIndex - 1];
      final hasEarlierTime = tokens.take(movesIndex - 1).any((t) => t.isTime);
      if (candidate.unit == _TcUnit.minutes && hasEarlierTime) {
        final period = _buildPeriod(
          afterMoves: afterMoves,
          bonusSeconds: candidate.seconds,
        );
        if (period != null) return period;
      }
    }
  }

  // Fallback shape: prose that names the move instead of a move count.
  //   "90+30 (15 minutes added after move 40)"
  //   "90 min + 30 sec/move, 30 min after move 40"
  //   "90 min + 30 sec for first 40 moves + 30 mins from move no 41"
  final prose = _bonusAfterMoveRegex.firstMatch(normalized);
  if (prose != null) {
    final value = int.tryParse(prose.group(1)!);
    final moveNumber = int.tryParse(prose.group(3)!);
    if (value != null && moveNumber != null) {
      final unit = prose.group(2)!;
      final bonusSeconds = unit.startsWith('h') ? value * 3600 : value * 60;
      // "after/at/on move 40" credits on move 40; "from move 41" describes the
      // same instant from the other side, so it qualifies one move earlier.
      final keyword = prose.group(0)!.contains('from') ? 1 : 0;
      final afterMoves = moveNumber - keyword;
      if (afterMoves >= _minAfterMoves && afterMoves <= _maxAfterMoves) {
        return _buildPeriod(afterMoves: afterMoves, bonusSeconds: bonusSeconds);
      }
    }
  }

  return null;
}

TimeControlSecondaryPeriod? _buildPeriod({
  required int afterMoves,
  required int bonusSeconds,
}) {
  if (bonusSeconds < _minBonusSeconds || bonusSeconds > _maxBonusSeconds) {
    return null;
  }
  return TimeControlSecondaryPeriod(
    afterMoves: afterMoves,
    bonusSeconds: bonusSeconds,
  );
}

String _normalizeTcText(String raw) {
  var text = raw.toLowerCase();
  // Curly quotes and primes → ASCII, so the prime rules below see one shape.
  text = text.replaceAll(RegExp('[‘’ʹ′]'), "'");
  text = text.replaceAll(RegExp('[“”ʺ″]'), '"');
  // Double prime is seconds, single prime is minutes. Order matters.
  text = text.replaceAll('"', ' sec ');
  text = text.replaceAll("''", ' sec ');
  text = text.replaceAll("'", ' min ');
  // "1h40" spells 100 minutes; expand so the tokenizer sees both halves.
  text = text.replaceAllMapped(
    RegExp(r'(\d+)\s*h\s*(\d{1,2})\b'),
    (m) => '${(int.parse(m.group(1)!) * 60) + int.parse(m.group(2)!)} min ',
  );
  return text;
}

const Set<String> _moveUnits = {
  'moves',
  'move',
  'movimenti',
  'movimientos',
  'movs',
  'mov',
  'mvs',
  'jugadas',
  'coups',
  'zuege',
  'züge',
  'zug',
  'lepes',
  'lépés',
  'drag',
};

const Set<String> _minuteUnits = {
  'minutes',
  'minuten',
  'minutos',
  'minuti',
  'mins',
  'min',
  'mn',
};

const Set<String> _hourUnits = {'hours', 'hour', 'hrs', 'hr', 'h'};

List<_TcToken> _tokenize(String normalized) {
  final tokens = <_TcToken>[];
  for (final match in _tcTokenRegex.allMatches(normalized)) {
    // Bare `/40` move count from the abbreviated `90'/40 + 30'` shape.
    final slashMoves = match.group(3);
    if (slashMoves != null) {
      final value = int.tryParse(slashMoves);
      if (value != null) tokens.add(_TcToken(value, _TcUnit.moves));
      continue;
    }

    final value = int.tryParse(match.group(1) ?? '');
    final unitText = match.group(2)?.toLowerCase();
    if (value == null || unitText == null) continue;

    if (_moveUnits.contains(unitText)) {
      tokens.add(_TcToken(value, _TcUnit.moves));
    } else if (_hourUnits.contains(unitText)) {
      // Hours fold into minutes so downstream logic has one time scale.
      tokens.add(_TcToken(value * 60, _TcUnit.minutes));
    } else if (_minuteUnits.contains(unitText)) {
      tokens.add(_TcToken(value, _TcUnit.minutes));
    } else {
      tokens.add(_TcToken(value, _TcUnit.seconds));
    }
  }
  return tokens;
}

/// Index in [playerClocks] at which the broadcast source already credited the
/// secondary bonus, or `null` when it never did.
///
/// [playerClocks] holds one side's remaining seconds after each of *their* own
/// moves, so `playerClocks[i]` is the clock after that player's move `i + 1`.
/// A player can never gain more than the per-move increment, so a rise of half
/// the bonus or more can only be the secondary block landing.
int? _sourceCreditIndex(
  List<int?> playerClocks,
  TimeControlSecondaryPeriod period,
) {
  // The credit can never precede the qualifying move.
  final earliestIndex = period.afterMoves - 1;
  final threshold = period.bonusSeconds ~/ 2;

  int? previous;
  for (var i = 0; i < playerClocks.length; i++) {
    final current = playerClocks[i];
    if (current == null) continue;
    if (previous != null && i >= earliestIndex) {
      if (current - previous >= threshold) return i;
    }
    previous = current;
  }
  return null;
}

/// Seconds to add to one side's clock so the secondary bonus shows as soon as
/// that side completes [TimeControlSecondaryPeriod.afterMoves] moves.
///
/// Returns `0` when the bonus is not due yet, or when the broadcast source has
/// already baked it into the reading — which is what keeps the correction from
/// double-counting once the relay catches up.
///
/// [playerClocks] is that side's own clock series parsed from the PGN.
/// [completedMoves] is how many moves that side has actually completed, which
/// can run one ahead of the series when a live snapshot arrives before the PGN.
int secondaryBonusOffsetSeconds({
  required TimeControlSecondaryPeriod? period,
  required List<int?> playerClocks,
  required int completedMoves,
}) {
  if (period == null) return 0;
  if (completedMoves < period.afterMoves) return 0;

  final creditIndex = _sourceCreditIndex(playerClocks, period);
  if (creditIndex != null && completedMoves >= creditIndex + 1) return 0;

  return period.bonusSeconds;
}

/// Per-ply clock displays with the secondary bonus filled in for the moves the
/// broadcast source has not credited yet.
///
/// [moveClockDisplays] is indexed by ply (`0` = White's first move) and may
/// contain the `-:--:--` placeholder used for moves without a `[%clk]` tag;
/// placeholders are passed through untouched.
List<String> applySecondaryBonusToMoveClocks(
  List<String> moveClockDisplays,
  TimeControlSecondaryPeriod? period,
) {
  if (period == null || moveClockDisplays.isEmpty) return moveClockDisplays;

  final adjusted = List<String>.of(moveClockDisplays);
  var changed = false;

  for (var side = 0; side < 2; side++) {
    final plyIndices = <int>[];
    final clocks = <int?>[];
    for (var ply = side; ply < moveClockDisplays.length; ply += 2) {
      plyIndices.add(ply);
      clocks.add(
        hasUsableClockDisplay(moveClockDisplays[ply])
            ? parsePgnClockToSeconds(moveClockDisplays[ply])
            : null,
      );
    }
    if (clocks.isEmpty) continue;

    final creditIndex = _sourceCreditIndex(clocks, period);
    for (var i = period.afterMoves - 1; i < clocks.length; i++) {
      if (creditIndex != null && i >= creditIndex) break;
      final seconds = clocks[i];
      if (seconds == null) continue;
      adjusted[plyIndices[i]] = formatClockDisplayFromSeconds(
        seconds + period.bonusSeconds,
      );
      changed = true;
    }
  }

  return changed ? adjusted : moveClockDisplays;
}

/// One side's `[%clk]` series in seconds, parsed straight from the PGN movetext.
///
/// [side] is `0` for White and `1` for Black. Entries are `null` for moves whose
/// clock is missing, which keeps indices aligned with the side's move numbers.
List<int?> playerClockSeriesFromPgn(String? pgn, int side) {
  if (pgn == null || pgn.isEmpty) return const <int?>[];
  final all = extractPgnClockStringsFromText(pgn);
  final series = <int?>[];
  for (var ply = side; ply < all.length; ply += 2) {
    series.add(parsePgnClockToSeconds(all[ply]));
  }
  return series;
}

/// Number of moves a side has completed, given the total ply count.
///
/// White completes a move on every even ply, Black on every odd one.
int completedMovesForSide(int totalPlies, int side) {
  if (totalPlies <= 0) return 0;
  return side == 0 ? (totalPlies + 1) ~/ 2 : totalPlies ~/ 2;
}

/// Both sides' live clocks with the secondary bonus applied where it is due.
///
/// This is the entry point for the `last_clock_white` / `last_clock_black`
/// snapshots that drive every card and countdown. The PGN is only used to work
/// out whether the source already credited the bonus — the returned values stay
/// anchored to the raw snapshots.
({int? white, int? black}) applySecondaryBonusToLiveClocks({
  required String? pgn,
  required int? whiteSeconds,
  required int? blackSeconds,
  required TimeControlSecondaryPeriod? period,
}) {
  if (period == null) return (white: whiteSeconds, black: blackSeconds);

  final plyClocks = extractPgnClockStringsFromText(pgn ?? '');
  if (plyClocks.isEmpty) return (white: whiteSeconds, black: blackSeconds);

  int? adjust(int? seconds, int side) {
    if (seconds == null || seconds <= 0) return seconds;
    final series = <int?>[];
    for (var ply = side; ply < plyClocks.length; ply += 2) {
      series.add(parsePgnClockToSeconds(plyClocks[ply]));
    }
    final offset = secondaryBonusOffsetSeconds(
      period: period,
      playerClocks: series,
      completedMoves: completedMovesForSide(plyClocks.length, side),
    );
    return seconds + offset;
  }

  return (white: adjust(whiteSeconds, 0), black: adjust(blackSeconds, 1));
}
