import 'package:chessever2/screens/feed/race/race_protocol.dart';

/// Words for Puzzle Race. Calm and short: a failure says what happened and
/// what to do, never a raw code.

/// What went wrong, for a player, by the room's (or the client's) code.
String raceErrorMessage(String? code) => switch (code) {
  'not_configured' => "Puzzle Race isn't switched on in this version yet.",
  'network' || 'connection_lost' =>
    "Couldn't reach Puzzle Race. Check your connection and try again.",
  'authentication_required' ||
  'invalid_token' => 'Sign in to race with friends.',
  'room_not_found' => 'No race has that code. Check it and try again.',
  'room_closed' => 'That race has already started or is full.',
  'room_full' => 'That room is full.',
  'already_started' => 'That race has already started.',
  'race_finished' => 'That race has already finished.',
  'forbidden' => 'That race belongs to someone else.',
  'rate_limited' ||
  'too_many_connections' => 'Too many tries at once. Give it a minute.',
  'replaced' => 'This race is open on another device now.',
  'puzzle_source_unavailable' =>
    "Puzzles aren't answering right now. Try again in a moment.",
  'invalid_code' => 'A room code is 6 letters and numbers.',
  'stop_queued' => 'Your run ends as soon as the connection is back.',
  'puzzle_source_gave_up' =>
    'Puzzles stopped answering, so your run ended here.',
  _ => 'Something went wrong on our side. Try again.',
};

/// Under the finish line when the room never confirmed the result (the
/// connection ended first): the figures are this device's own.
const String kRaceUnconfirmedLine =
    'The connection dropped before the race server confirmed this';

/// Why a run ended, as a short line under the score.
String raceFinishLine(RaceFinishReason? reason) => switch (reason) {
  RaceFinishReason.stopped => 'You ended the run',
  RaceFinishReason.lives => 'Out of lives',
  RaceFinishReason.idle => 'The race went quiet and closed',
  RaceFinishReason.timeLimit => 'Three hours: the longest a race runs',
  RaceFinishReason.exhausted => 'No puzzles left at this level',
  RaceFinishReason.puzzleLimit => 'A thousand puzzles: the most in one race',
  RaceFinishReason.unknown || null => 'Race over',
};

String raceModeName(RaceMode mode) =>
    mode == RaceMode.survival ? 'Survival' : 'Infinite';

/// Where a room's ladder starts, as the room reports it: "starts at 1000",
/// or null when the room has not said (an older race service). A race climbs
/// from its start, so a ceiling an older room still carries is not shown.
String? raceStartLine(int? startRating) =>
    startRating == null ? null : 'starts at $startRating';

/// The race clock: `mm:ss.t`, or `h:mm:ss.t` past an hour.
String formatRaceClock(int ms) {
  final safe = ms < 0 ? 0 : ms;
  final tenths = (safe ~/ 100) % 10;
  final seconds = (safe ~/ 1000) % 60;
  final minutes = (safe ~/ 60000) % 60;
  final hours = safe ~/ 3600000;
  String two(int n) => n.toString().padLeft(2, '0');
  if (hours > 0) return '$hours:${two(minutes)}:${two(seconds)}.$tenths';
  return '${two(minutes)}:${two(seconds)}.$tenths';
}

/// A puzzle's time: `7.4s` under a minute, else the clock without tenths.
String formatPuzzleTime(int ms) {
  final safe = ms < 0 ? 0 : ms;
  if (safe < 60000) {
    return '${(safe / 1000).toStringAsFixed(1)}s';
  }
  final minutes = safe ~/ 60000;
  final seconds = (safe ~/ 1000) % 60;
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}

/// The text shared from the results screen.
String raceShareText({
  required RaceMode mode,
  required bool multiplayer,
  required int score,
  required int elapsedMs,
  required int displayLevel,
  required int bestStreak,
  int? rank,
  int? players,
}) {
  final place = multiplayer && rank != null && players != null && players > 1
      ? ' Finished $rank of $players.'
      : '';
  final solved = score == 1 ? '1 puzzle' : '$score puzzles';
  return 'ChessEver Puzzle Race, ${raceModeName(mode)}: '
      '$solved in ${formatRaceClock(elapsedMs)}, reached level $displayLevel. '
      'Best streak $bestStreak.$place';
}

/// The text of a room invite.
String raceInviteText(String code) => 'Join my ChessEver Puzzle Race: $code';
