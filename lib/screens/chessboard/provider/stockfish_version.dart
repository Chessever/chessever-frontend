/// The Stockfish version the bundled `stockfish` pub package embeds
/// (`stockfish` 1.8.1 ships Stockfish 18). Used until the running engine
/// reports its own version through UCI, and whenever it cannot (debug builds,
/// where local Stockfish is deliberately off).
///
/// Update this together with the `stockfish` dependency in `pubspec.yaml`.
const String kBundledStockfishVersion = '18';

/// Reads the Stockfish version from one line of engine output.
///
/// Accepts the UCI reply (`id name Stockfish 19`) and the startup banner
/// (`Stockfish 18 by the Stockfish developers (see AUTHORS file)`). Release
/// numbers are kept as written (`17.1`); development builds
/// (`dev-20240928-abcdef12`, or the old `280924` date stamps) read as `dev`.
/// Returns null for every other line.
String? stockfishVersionFromUciLine(String line) {
  final match = _stockfishNamePattern.firstMatch(line);
  if (match == null) return null;
  final token = match.group(1)!;
  if (token.toLowerCase().startsWith('dev')) return 'dev';
  final release = _releasePattern.firstMatch(token);
  if (release == null) return null;
  final number = release.group(0)!;
  // Pre-16 development builds were named by date: `Stockfish 280924`.
  if (_dateStampPattern.hasMatch(number)) return 'dev';
  return number;
}

/// The engine label Lichess uses: `SF 19`, `SF 17.1`, `SF dev`.
String stockfishShortLabel([String? version]) {
  final resolved = (version == null || version.trim().isEmpty)
      ? kBundledStockfishVersion
      : version.trim();
  return 'SF $resolved';
}

final RegExp _stockfishNamePattern = RegExp(
  r'^\s*(?:id\s+name\s+)?Stockfish\s+(\S+)',
);
final RegExp _releasePattern = RegExp(r'^\d+(?:\.\d+)*');
final RegExp _dateStampPattern = RegExp(r'^\d{6}$');
