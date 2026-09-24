import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Where ChessEver's own puzzle service lives: the `race` Cloudflare Worker
/// (`chessever_cloudflare/apps/race`), whose `GET /v1/puzzles/feed` serves
/// the Feed's puzzles.
///
/// Resolved once per process, in this order:
///
///  1. `--dart-define=RACE_API_URL=…`, which is also what
///     `--dart-define-from-file=.env` feeds. It is the ONLY source a release
///     or profile build has, so every Codemagic workflow (ChessEver Test and
///     production) must pass `--dart-define=RACE_API_URL="$RACE_API_URL"`,
///     with the value set per flavor in that workflow's environment group.
///     `CODEMAGIC_DART_DEFINES.txt` lists it with the other build-time keys.
///  2. A `RACE_API_URL` line in the `.env` that `main.dart` loads for local
///     debug runs, read the way `GAMEBASE_API_KEY` is. Debug builds only: a
///     release build has no `.env`.
///  3. Otherwise empty. There is no default deployment and no fallback to a
///     third-party API: with no URL the Feed carries no puzzles and the
///     Puzzle Race is off.
///
/// There is no compiled-in default the way `ANALYSIS_API_BASE` has one,
/// because each flavor needs a Worker whose `SUPABASE_URL` trusts that
/// flavor's own Supabase project.
final String kRaceApiUrl = _reportIfUnbuilt(resolveRaceApiUrl());

/// Says, once per process, that a release or profile build was made without
/// the define, so a misconfigured Codemagic workflow is named in the device
/// log instead of surfacing only as an empty Feed. Debug runs without a `.env`
/// line are expected and stay quiet here; the Feed repository logs those.
String _reportIfUnbuilt(String url) {
  if (url.isEmpty && !kDebugMode) {
    debugPrint(
      '[PuzzleService] built without --dart-define=RACE_API_URL; '
      'Feed puzzles and the Puzzle Race are off in this build.',
    );
  }
  return url;
}

const String _raceApiUrlDefine = String.fromEnvironment('RACE_API_URL');

/// Applies the resolution order of [kRaceApiUrl]. Parameters exist for tests.
@visibleForTesting
String resolveRaceApiUrl({
  String define = _raceApiUrlDefine,
  String Function()? debugEnvValue,
  bool allowDebugEnv = kDebugMode,
}) {
  final defined = normalizeRaceApiUrl(define);
  if (defined.isNotEmpty) return defined;
  if (!allowDebugEnv) return '';
  return normalizeRaceApiUrl((debugEnvValue ?? _dotenvRaceApiUrl)());
}

String _dotenvRaceApiUrl() {
  try {
    return dotenv.env['RACE_API_URL'] ?? '';
  } catch (_) {
    // dotenv never loaded: a release build, a test, or a debug run started
    // without a `.env`. Not an error; the URL is simply unset.
    return '';
  }
}

/// [value] as a base that request paths can be appended to (trimmed, no
/// trailing slash), or empty when it is blank or not an http(s) URL.
///
/// A malformed value turns puzzles off rather than failing every request.
@visibleForTesting
String normalizeRaceApiUrl(String value) {
  final trimmed = value.trim().replaceFirst(RegExp(r'/+$'), '');
  if (trimmed.isEmpty) return '';
  final uri = Uri.tryParse(trimmed);
  final usable =
      uri != null &&
      (uri.scheme == 'https' || uri.scheme == 'http') &&
      uri.host.isNotEmpty;
  if (!usable) {
    debugPrint(
      '[PuzzleService] RACE_API_URL is not an http(s) URL; puzzles are off.',
    );
    return '';
  }
  return trimmed;
}
