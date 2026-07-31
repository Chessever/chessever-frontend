/// PGN `[TimeControl "…"]` tag values.
///
/// The tag is a *machine* field, not a label: the PGN standard defines it as
/// one or more periods — `600` (sudden death), `40/5400` (moves/seconds),
/// `300+3` (increment), `*180` (sandclock), joined by `:` — plus `?` for
/// unknown and `-` for none. A category word like `standard` is not a value.
///
/// This matters beyond pedantry. ChessBase does not store time *remaining*; on
/// import it converts each `[%clk]` into its own elapsed-time annotation, and
/// that conversion needs the time control to work from. Given an unparseable
/// tag it silently drops every clock in the game — which is exactly what
/// shipping `[TimeControl "standard"]` did to our shared PGNs.
library;

/// A single period of a time control, e.g. `40/5400+30`.
class PgnTimeControlPeriod {
  const PgnTimeControlPeriod({
    required this.seconds,
    this.moves,
    this.incrementSeconds,
  });

  /// Base time for the period, in seconds.
  final int seconds;

  /// Moves that must be completed in [seconds], or null for sudden death.
  final int? moves;

  /// Per-move increment in seconds, or null when there is none.
  final int? incrementSeconds;

  String format() {
    final buffer = StringBuffer();
    if (moves != null) buffer.write('$moves/');
    buffer.write(seconds);
    if (incrementSeconds != null) buffer.write('+$incrementSeconds');
    return buffer.toString();
  }
}

/// Whether [value] is already a valid PGN TimeControl field.
///
/// Accepts every form in the standard so a legal tag we did not write (an
/// imported game, a library row) is passed through untouched.
bool isValidPgnTimeControl(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) return false;
  if (trimmed == '?' || trimmed == '-') return true;
  return trimmed
      .split(':')
      .every((period) => _periodPattern.hasMatch(period.trim()));
}

final RegExp _periodPattern = RegExp(
  r'^(?:'
  r'\*\d+' // sandclock: *180
  r'|\d+/\d+(?:\+\d+)?' // moves/seconds(+increment): 40/5400+30
  r'|\d+(?:\+\d+)?' // sudden death(+increment): 300+3
  r')$',
);

/// Build a PGN TimeControl field from a tournament's raw time-control text.
///
/// Handles the shapes broadcast feeds actually publish:
/// `90 min / 40 moves + 30 min + 30 sec / move` → `40/5400+30:1800+30`,
/// `90 min + 30 sec` → `5400+30`, `15 min` → `900`, `3+2` → `180+2`,
/// `90'/40 + 30' + 30''` → `40/5400+30:1800+30`.
///
/// Returns null when the text carries no usable time — a category word
/// (`standard`, `blitz`), an empty string, nonsense. Callers must then omit
/// the tag rather than invent one: a wrong TimeControl is worse than none,
/// because it makes readers compute wrong times instead of showing none.
String? pgnTimeControlField(String? rawText) {
  final text = rawText?.trim();
  if (text == null || text.isEmpty) return null;
  // A field we did not write (imported game, our own re-export) is returned
  // verbatim: re-rendering it could only lose something, such as the `*` of a
  // sandclock control.
  if (_minutesShorthand(text) == null && isValidPgnTimeControl(text)) {
    return text;
  }
  final periods = parsePgnTimeControlPeriods(text);
  if (periods.isEmpty) return null;
  return periods.map((period) => period.format()).join(':');
}

/// `5+3` / `90+30` written by a human, where the base is *minutes*.
///
/// Bounded so a real PGN field is not mangled: `300+3` is a properly written
/// 5-minute blitz control in seconds, not a 300-minute game.
({int minutes, int increment})? _minutesShorthand(String text) {
  final match = RegExp(r'^(\d{1,3})\s*\+\s*(\d{1,3})$').firstMatch(text);
  if (match == null) return null;
  final minutes = int.parse(match.group(1)!);
  final increment = int.parse(match.group(2)!);
  if (minutes <= 0 || minutes > _maxShorthandMinutes) return null;
  if (increment > _maxShorthandIncrement) return null;
  return (minutes: minutes, increment: increment);
}

const int _maxShorthandMinutes = 180;
const int _maxShorthandIncrement = 60;

/// Longest value still read as a per-move increment rather than a period.
const int _maxIncrementSeconds = 60;

/// Periods behind [pgnTimeControlField], exposed for tests and callers that
/// need the numbers (base time, increment) rather than the rendered field.
List<PgnTimeControlPeriod> parsePgnTimeControlPeriods(String? rawText) {
  final text = rawText?.trim();
  if (text == null || text.isEmpty) return const [];

  // Bare `base+increment` shorthand, where the base is minutes: `5+3`, `90+30`.
  // Checked before the field passthrough, which would read `3+2` as three
  // seconds.
  final shorthand = _minutesShorthand(text);
  if (shorthand != null) {
    return [
      PgnTimeControlPeriod(
        seconds: shorthand.minutes * 60,
        incrementSeconds:
            shorthand.increment == 0 ? null : shorthand.increment,
      ),
    ];
  }

  // Already a PGN field (an imported game's tag, or our own re-export).
  if (isValidPgnTimeControl(text) && text != '?' && text != '-') {
    return _parseFormattedField(text);
  }

  var tokens = _tokenize(text);
  if (tokens.isEmpty) return const [];

  // A short seconds value is the per-move increment, not a period: "… + 30 sec
  // / move". It is not always written last — "90min + 30sec / 40move + 30min"
  // puts it in the middle — so pull every such token out before the periods are
  // built, rather than only checking the tail. No real period is a minute or
  // less, and `perMove` marks the ones written with an explicit "/ move".
  int? increment;
  if (tokens.length > 1) {
    final remaining = <_TcToken>[];
    for (final token in tokens) {
      final isIncrement =
          token.unit == _TcUnit.seconds &&
          (token.perMove || token.value <= _maxIncrementSeconds);
      if (isIncrement) {
        if (token.value > 0) increment = token.value;
        continue;
      }
      remaining.add(token);
    }
    tokens = remaining;
  }

  final periods = <PgnTimeControlPeriod>[];
  int? pendingMoves;
  for (final token in tokens) {
    if (token.unit == _TcUnit.moves) {
      if (token.value < _minMoves || token.value > _maxMoves) continue;
      // "90 min / 40 moves": the count belongs to the period just read.
      if (periods.isNotEmpty && periods.last.moves == null) {
        final period = periods.removeLast();
        periods.add(
          PgnTimeControlPeriod(seconds: period.seconds, moves: token.value),
        );
      } else {
        // "40 moves / 90 min": it belongs to the period still to come.
        pendingMoves = token.value;
      }
      continue;
    }

    final seconds = token.seconds;
    if (seconds <= 0 || seconds > _maxPeriodSeconds) continue;
    periods.add(
      PgnTimeControlPeriod(seconds: seconds, moves: pendingMoves),
    );
    pendingMoves = null;
  }

  if (periods.isEmpty) return const [];
  if (increment == null) return periods;

  // The increment is credited on every move of the game, so it belongs on
  // every period — `40/5400+30:1800+30`, the form published FIDE PGNs use.
  return [
    for (final period in periods)
      PgnTimeControlPeriod(
        seconds: period.seconds,
        moves: period.moves,
        incrementSeconds: increment,
      ),
  ];
}

const int _minMoves = 1;
const int _maxMoves = 200;
const int _maxPeriodSeconds = 24 * 3600;

enum _TcUnit { hours, minutes, seconds, moves }

class _TcToken {
  const _TcToken(this.value, this.unit, {this.perMove = false});
  final int value;
  final _TcUnit unit;

  /// The value was written with a per-move suffix ("30 sec / move", `30''`).
  final bool perMove;

  int get seconds => switch (unit) {
    _TcUnit.hours => value * 3600,
    _TcUnit.minutes => value * 60,
    _ => value,
  };
}

/// Number + unit, longest spellings first so the alternation cannot stop early.
/// Mirrors the tokenizer in `time_control_bonus.dart`, plus the abbreviated
/// `90'` / `30''` forms broadcast sheets use.
final RegExp _tokenPattern = RegExp(
  '(\\d+)\\s*(\'\'|"|\u2019\u2019|\u201d|\'|\u2019)'
  r"|(\d+)\s*"
  r'(minutes|minuten|minutos|minuti|mins|min|mn'
  r'|hours|hour|hrs|hr|h'
  r'|seconds|segundos|secondi|sekunden|secs|sec|segs|seg|s'
  r'|moves|move|movimenti|movimientos|movs|mov|mvs'
  r'|jugadas|coups|zuege|züge|zug|lepes|lépés|drag'
  r')(?![a-zà-ÿ])'
  r'|/\s*(\d{1,3})(?![0-9])(?!\s*(?:min|hour|hr|h\b|sec|seg|s\b|mn))',
  caseSensitive: false,
);

final RegExp _perMoveSuffix = RegExp(
  r'^\s*(?:/|per\b|a\b|pro\b)?\s*(?:move|moves|mv|zug|coup|jugada)',
  caseSensitive: false,
);

List<_TcToken> _tokenize(String text) {
  final tokens = <_TcToken>[];
  for (final match in _tokenPattern.allMatches(text)) {
    final rest = text.substring(match.end);
    if (match.group(1) != null) {
      // `90'` (minutes) / `30''`, `30"` (seconds). Feeds use both the doubled
      // prime and a plain double quote, in straight and typographic forms.
      final value = int.parse(match.group(1)!);
      final isSeconds = const {"''", '"', '’’', '”'} //
          .contains(match.group(2));
      tokens.add(
        _TcToken(
          value,
          isSeconds ? _TcUnit.seconds : _TcUnit.minutes,
          perMove: isSeconds,
        ),
      );
      continue;
    }
    if (match.group(3) != null) {
      final value = int.parse(match.group(3)!);
      final unit = _unitFor(match.group(4)!);
      if (unit == null) continue;
      tokens.add(
        _TcToken(
          value,
          unit,
          perMove: unit == _TcUnit.seconds && _perMoveSuffix.hasMatch(rest),
        ),
      );
      continue;
    }
    final moves = match.group(5);
    if (moves != null) tokens.add(_TcToken(int.parse(moves), _TcUnit.moves));
  }
  return tokens;
}

_TcUnit? _unitFor(String unit) {
  final normalized = unit.toLowerCase();
  if (normalized.startsWith('h')) return _TcUnit.hours;
  if (normalized.startsWith('m')) {
    // `min`/`minutes` vs `move`/`moves` — both start with "m".
    return normalized.startsWith('mo') || normalized.startsWith('mv')
        ? _TcUnit.moves
        : _TcUnit.minutes;
  }
  if (normalized.startsWith('s') ||
      normalized.startsWith('se') ||
      normalized.startsWith('sek')) {
    return _TcUnit.seconds;
  }
  if (normalized.startsWith('j') ||
      normalized.startsWith('c') ||
      normalized.startsWith('z') ||
      normalized.startsWith('l') ||
      normalized.startsWith('d')) {
    return _TcUnit.moves;
  }
  return null;
}

List<PgnTimeControlPeriod> _parseFormattedField(String field) {
  final periods = <PgnTimeControlPeriod>[];
  for (final raw in field.split(':')) {
    final period = raw.trim();
    if (period.startsWith('*')) {
      final seconds = int.tryParse(period.substring(1));
      if (seconds != null) periods.add(PgnTimeControlPeriod(seconds: seconds));
      continue;
    }
    final match = RegExp(r'^(?:(\d+)/)?(\d+)(?:\+(\d+))?$').firstMatch(period);
    if (match == null) continue;
    periods.add(
      PgnTimeControlPeriod(
        seconds: int.parse(match.group(2)!),
        moves:
            match.group(1) == null ? null : int.parse(match.group(1)!),
        incrementSeconds:
            match.group(3) == null ? null : int.parse(match.group(3)!),
      ),
    );
  }
  return periods;
}
