import 'package:chessever2/screens/library/utils/gamebase_pgn_builder.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ---------------------------------------------------------------- Most Liked

/// The ranking periods of Most Liked. The current day is free; every other
/// day, and every Week, Month and Year, is Premium.
enum MostLikedPeriod { today, week, month, year }

extension MostLikedPeriodX on MostLikedPeriod {
  String get label => switch (this) {
    MostLikedPeriod.today => 'Today',
    MostLikedPeriod.week => 'Week',
    MostLikedPeriod.month => 'Month',
    MostLikedPeriod.year => 'Year',
  };

  bool get isPremium => this != MostLikedPeriod.today;
}

/// How a ranking is read: the games themselves, or the players who have
/// games in it (the way Miniatures has Games and Players). Players is
/// Premium.
enum MostLikedView { games, players }

extension MostLikedViewX on MostLikedView {
  String get label => switch (this) {
    MostLikedView.games => 'Games',
    MostLikedView.players => 'Players',
  };

  bool get isPremium => this == MostLikedView.players;
}

/// The first day there are likes to rank: the liked-games folder shipped on
/// 30 May 2026 (`20260530000000_liked_games_special_folder.sql`). The date
/// navigation stops at the period holding it instead of walking back
/// through empty years.
final DateTime kMostLikedFirstDay = DateTime(2026, 5, 30);

/// The local calendar day [t] falls on.
DateTime mostLikedDay(DateTime t) => DateTime(t.year, t.month, t.day);

/// The start of the calendar [period] holding [day], in local time: its
/// midnight, the Monday of its week, the 1st of its month, 1 January.
DateTime mostLikedPeriodStart(MostLikedPeriod period, DateTime day) {
  return switch (period) {
    MostLikedPeriod.today => DateTime(day.year, day.month, day.day),
    MostLikedPeriod.week => DateTime(
      day.year,
      day.month,
      day.day - (day.weekday - DateTime.monday),
    ),
    MostLikedPeriod.month => DateTime(day.year, day.month),
    MostLikedPeriod.year => DateTime(day.year),
  };
}

/// The start of the [period] that is [steps] periods after the one starting
/// at [start] (negative walks back). Calendar arithmetic, so a day across a
/// DST change is still one day and a month is still a month.
DateTime mostLikedShift(MostLikedPeriod period, DateTime start, int steps) {
  return switch (period) {
    MostLikedPeriod.today => DateTime(
      start.year,
      start.month,
      start.day + steps,
    ),
    MostLikedPeriod.week => DateTime(
      start.year,
      start.month,
      start.day + 7 * steps,
    ),
    MostLikedPeriod.month => DateTime(start.year, start.month + steps),
    MostLikedPeriod.year => DateTime(start.year + steps),
  };
}

/// One ranking to read: a period and which one of it (the day, week, month
/// or year holding the day it was built from). Equal queries read the same
/// window, so this is the key the ranking read is cached under.
@immutable
class MostLikedQuery {
  MostLikedQuery(this.period, DateTime day)
    : start = mostLikedPeriodStart(period, day);

  final MostLikedPeriod period;

  /// Local midnight the period starts on.
  final DateTime start;

  /// Local midnight the next period starts on (exclusive end).
  DateTime get end => mostLikedShift(period, start, 1);

  /// The `[from, to)` window the ranking RPC counts likes in. A calendar
  /// period, never a rolling one: the current week runs Monday to Monday
  /// even while it is only half over.
  ({DateTime from, DateTime to}) get window => (from: start, to: end);

  /// Whether this is the period holding [now] (the newest one there is).
  bool isCurrent(DateTime now) => start == mostLikedPeriodStart(period, now);

  /// Only the current day is free. Earlier days and every longer period sit
  /// behind the Premium boundary, the same rule the server enforces.
  bool isFree(DateTime now) =>
      period == MostLikedPeriod.today && isCurrent(now);

  /// The period before this one, or null once it would hold no day on or
  /// after [kMostLikedFirstDay].
  MostLikedQuery? get previous {
    // The period before ends where this one starts.
    if (!start.isAfter(mostLikedDay(kMostLikedFirstDay))) return null;
    return MostLikedQuery(period, mostLikedShift(period, start, -1));
  }

  /// The period after this one, or null when this is already the current
  /// one: the future has no ranking.
  MostLikedQuery? next(DateTime now) {
    if (!start.isBefore(mostLikedPeriodStart(period, now))) return null;
    return MostLikedQuery(period, end);
  }

  /// What the date control reads, month first like every Discovery date:
  /// "Wed, Sep 23", "Sep 21–27", "Sep 28 – Oct 4", "September", "2026".
  /// The year is added only when the period is not in [now]'s year ("Tue,
  /// Sep 23, 2025", "Sep 21–27, 2025", "August 2025"); a week across New
  /// Year carries both ("Dec 28, 2026 – Jan 3, 2027").
  String label(DateTime now) {
    final thisYear = start.year == now.year;
    switch (period) {
      case MostLikedPeriod.today:
        return discoveryWeekday(start, now: now);
      case MostLikedPeriod.week:
        final last = DateTime(start.year, start.month, start.day + 6);
        if (last.year != start.year) {
          return '${DateFormat.yMMMd().format(start)} – '
              '${DateFormat.yMMMd().format(last)}';
        }
        final first = DateFormat.MMMd().format(start);
        final range = start.month == last.month
            ? '$first–${last.day}'
            : '$first – ${DateFormat.MMMd().format(last)}';
        return thisYear ? range : '$range, ${last.year}';
      case MostLikedPeriod.month:
        return thisYear
            ? DateFormat.MMMM().format(start)
            : DateFormat.yMMMM().format(start);
      case MostLikedPeriod.year:
        return '${start.year}';
    }
  }

  @override
  bool operator ==(Object other) =>
      other is MostLikedQuery && other.period == period && other.start == start;

  @override
  int get hashCode => Object.hash(period, start);

  @override
  String toString() => 'MostLikedQuery(${period.name}, $start)';
}

/// The `[from, to)` window of the [period] holding [day]: see
/// [MostLikedQuery.window].
({DateTime from, DateTime to}) mostLikedWindow(
  MostLikedPeriod period,
  DateTime day,
) => MostLikedQuery(period, day).window;

/// One ranked row as the backend returns it: a game id and its like count.
@immutable
class MostLikedCount {
  const MostLikedCount({required this.gameId, required this.likes});

  final String gameId;
  final int likes;

  @override
  bool operator ==(Object other) =>
      other is MostLikedCount && other.gameId == gameId && other.likes == likes;

  @override
  int get hashCode => Object.hash(gameId, likes);
}

/// Parses `most_liked_games` rows. Rows are untrusted: a row without an id or
/// a positive count is dropped rather than shown with a made-up number, and
/// a repeated id keeps its first (highest) count.
///
/// The order is re-applied here (count desc, id asc) so the ranking stays
/// deterministic even if a proxy or a future backend change loses it.
List<MostLikedCount> parseMostLikedRows(Object? data) {
  if (data is! List) return const [];
  final seen = <String>{};
  final out = <MostLikedCount>[];
  for (final raw in data) {
    if (raw is! Map) continue;
    final id = raw['source_game_id']?.toString().trim() ?? '';
    final likes = _asInt(raw['like_count']);
    if (id.isEmpty || likes == null || likes <= 0) continue;
    if (!seen.add(id)) continue;
    out.add(MostLikedCount(gameId: id, likes: likes));
  }
  out.sort((a, b) {
    final byLikes = b.likes.compareTo(a.likes);
    return byLikes != 0 ? byLikes : a.gameId.compareTo(b.gameId);
  });
  return out;
}

int? _asInt(Object? v) {
  if (v is int) return v;
  if (v is num) return v.isFinite ? v.toInt() : null;
  if (v is String) return int.tryParse(v.trim());
  return null;
}

/// One Most Liked row ready to draw: its place in the ranking, the like
/// count, the resolved game and the event it was played in (when known).
@immutable
class MostLikedEntry {
  const MostLikedEntry({
    required this.rank,
    required this.likes,
    required this.game,
    this.eventName,
  });

  /// 1-based position in the backend ranking. A game that could not be
  /// resolved keeps its place empty instead of shifting everyone up, so the
  /// number beside a game is always its true rank.
  final int rank;
  final int likes;
  final GamesTourModel game;
  final String? eventName;
}

/// Joins the backend ranking with the games that resolved. Unresolved ids are
/// skipped (never replaced by a placeholder game).
List<MostLikedEntry> assembleMostLikedEntries({
  required List<MostLikedCount> counts,
  required Map<String, GamesTourModel> gamesById,
  Map<String, String> eventNamesByTourId = const {},
}) {
  final entries = <MostLikedEntry>[];
  for (var i = 0; i < counts.length; i++) {
    final count = counts[i];
    final game = gamesById[count.gameId];
    if (game == null) continue;
    final event =
        eventNamesByTourId[game.tourId]?.trim() ??
        (game.source == GameSource.gamebase ? game.tourId.trim() : null);
    entries.add(
      MostLikedEntry(
        rank: i + 1,
        likes: count.likes,
        game: game,
        eventName: (event == null || event.isEmpty) ? null : event,
      ),
    );
  }
  return entries;
}

/// One row of the Players view: a player with games in the ranking, how
/// many of the ranked games are theirs, and the likes those games drew.
@immutable
class MostLikedPlayer {
  const MostLikedPlayer({
    required this.rank,
    required this.player,
    required this.games,
    required this.likes,
  });

  /// 1-based place in the Players view.
  final int rank;
  final PlayerCard player;
  final int games;
  final int likes;
}

/// The players who have games in [entries], each credited with the likes of
/// every ranked game they played (both sides of a game get its likes).
///
/// A player is one FIDE id, else one Gamebase id, else one name, so the same
/// person under two event spellings still folds together when an id is
/// known. A side with no usable name is left out rather than shown as "?".
/// Ranked by likes desc, then games desc, then name, so ties never swap.
List<MostLikedPlayer> aggregateMostLikedPlayers(List<MostLikedEntry> entries) {
  final byKey = <String, ({PlayerCard player, int games, int likes})>{};
  for (final entry in entries) {
    final seenInGame = <String>{};
    for (final side in [entry.game.whitePlayer, entry.game.blackPlayer]) {
      final name = side.name.trim();
      if (name.isEmpty || name == '?') continue;
      final key = _playerKey(side);
      if (!seenInGame.add(key)) continue;
      final prior = byKey[key];
      if (prior == null) {
        byKey[key] = (player: side, games: 1, likes: entry.likes);
        continue;
      }
      byKey[key] = (
        // Keep the richest card seen: a rating, title or flag another event
        // carried fills in what this one lacked.
        player: _richer(prior.player, side),
        games: prior.games + 1,
        likes: prior.likes + entry.likes,
      );
    }
  }
  final rows = byKey.values.toList()
    ..sort((a, b) {
      final byLikes = b.likes.compareTo(a.likes);
      if (byLikes != 0) return byLikes;
      final byGames = b.games.compareTo(a.games);
      if (byGames != 0) return byGames;
      return a.player.name.toLowerCase().compareTo(b.player.name.toLowerCase());
    });
  return [
    for (var i = 0; i < rows.length; i++)
      MostLikedPlayer(
        rank: i + 1,
        player: rows[i].player,
        games: rows[i].games,
        likes: rows[i].likes,
      ),
  ];
}

String _playerKey(PlayerCard p) {
  final fide = p.fideId;
  if (fide != null && fide > 0) return 'fide:$fide';
  final gamebase = p.gamebasePlayerId?.trim() ?? '';
  if (gamebase.isNotEmpty) return 'gamebase:$gamebase';
  return 'name:${p.name.trim().toLowerCase()}';
}

PlayerCard _richer(PlayerCard a, PlayerCard b) {
  return a.copyWith(
    title: a.title.trim().isEmpty ? b.title : null,
    rating: b.rating > a.rating ? b.rating : null,
    countryCode: a.countryCode.trim().isEmpty ? b.countryCode : null,
    federation: a.federation.trim().isEmpty ? b.federation : null,
    fideId: a.fideId ?? b.fideId,
    gamebasePlayerId: a.gamebasePlayerId ?? b.gamebasePlayerId,
  );
}

enum MostLikedStatus {
  /// The ranking answered (possibly with no games yet).
  ranked,

  /// The ranking function is not deployed on this backend yet.
  notLive,

  /// The backend refused a Premium window for this account.
  premiumRequired,
}

@immutable
class MostLikedResult {
  const MostLikedResult.ranked(this.entries) : status = MostLikedStatus.ranked;

  const MostLikedResult.notLive()
    : entries = const <MostLikedEntry>[],
      status = MostLikedStatus.notLive;

  const MostLikedResult.premiumRequired()
    : entries = const <MostLikedEntry>[],
      status = MostLikedStatus.premiumRequired;

  final MostLikedStatus status;
  final List<MostLikedEntry> entries;
}

/// Why the ranking RPC failed, as far as the page needs to know.
enum MostLikedFailure { missingFunction, premiumRequired, other }

/// PostgREST answers `PGRST202` when the function is not in its schema cache;
/// Postgres answers `42883` (undefined_function) when called another way.
MostLikedFailure classifyMostLikedError(Object error) {
  if (error is PostgrestException) {
    final code = error.code?.trim();
    if (code == 'PGRST202' || code == '42883') {
      return MostLikedFailure.missingFunction;
    }
    if (error.message.contains('premium_required')) {
      return MostLikedFailure.premiumRequired;
    }
  }
  return MostLikedFailure.other;
}

// ---------------------------------------------------------------- card meta

final RegExp _standaloneYear = RegExp(r'\b(19|20)\d{2}\b');
final RegExp _chessTournament = RegExp(
  r'\bchess\s+tournament\b',
  caseSensitive: false,
);
final RegExp _edgePunctuation = RegExp(r'^[\s,\-–:]+|[\s,\-–:]+$');

/// An event name short enough for a card's one meta line: the part before
/// the first "|" (the section or round), without the year and without the
/// words "Chess Tournament", which every such name carries.
///
/// "FIDE World Rapid & Blitz Championships 2026 | Open Blitz Round 14" reads
/// "FIDE World Rapid & Blitz Championships"; "Tata Steel Chess Tournament
/// 2026 | Masters" reads "Tata Steel". The full name stays on the card's
/// announcement and on the board the card opens. Null for a blank name; a
/// name that trims to nothing keeps its first segment as written.
String? discoveryShortEventName(String? raw) {
  final name = raw?.trim() ?? '';
  if (name.isEmpty) return null;
  final first = name.split('|').first.trim();
  final short = first
      .replaceAll(_standaloneYear, ' ')
      .replaceAll(_chessTournament, ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAll(_edgePunctuation, '');
  if (short.isNotEmpty) return short;
  return first.isEmpty ? name : first;
}

/// The two players' average rating: both when both are rated, else the one
/// that is, else null. The same rule orders Analyzed games.
int? discoveryAverageRating(GamesTourModel game) {
  final w = game.whitePlayer.rating;
  final b = game.blackPlayer.rating;
  if (w > 0 && b > 0) return (w + b) ~/ 2;
  if (w > 0) return w;
  if (b > 0) return b;
  return null;
}

/// The day a game was played, for a card's meta line: its last move, else
/// its game day, else the day it was scheduled.
DateTime? discoveryGameDay(GamesTourModel game) =>
    game.lastMoveTime ?? game.gameDay ?? game.dateStart;

// ---------------------------------------------------------------- dates

/// Every Discovery date, written the way the streak card writes its days:
/// month first, "Sep 23", with the year ("Sep 23, 2025") only when [day]
/// is not in [now]'s year.
String discoveryDay(DateTime day, {DateTime? now}) {
  final thisYear = day.year == (now ?? DateTime.now()).year;
  return thisYear
      ? DateFormat.MMMd().format(day)
      : DateFormat.yMMMd().format(day);
}

/// [discoveryDay] with the weekday, for the day steppers: "Wed, Sep 23",
/// "Tue, Sep 23, 2025".
String discoveryWeekday(DateTime day, {DateTime? now}) {
  final thisYear = day.year == (now ?? DateTime.now()).year;
  return thisYear
      ? DateFormat.MMMEd().format(day)
      : DateFormat.yMMMEd().format(day);
}

// ---------------------------------------------------------------- positions

const String _kStartBoard = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR';

/// Whether [game] carries a real position to draw. A board preview is shown
/// only then: a game known only by its header would otherwise render as the
/// starting position, which is not a position from that game.
bool discoveryHasRealPosition(GamesTourModel game) {
  final fen = game.fen?.trim() ?? '';
  if (fen.isNotEmpty && fen.split(' ').first != _kStartBoard) return true;
  if (game.hasStarted) return true;
  return pgnHasMoves(game.pgn);
}

// ---------------------------------------------------------------- reviews

/// `[%eval 0.35]`, `[%eval -1.20,24]`, `[%eval #-3]`.
final RegExp _evalDirective = RegExp(
  r'\[%eval\s+(#)?([+-]?\d+(?:\.\d+)?)(?:,\d+)?\s*\]',
);

/// Mate scores are drawn at this many centipawns, far enough out that the
/// win-chance curve is pinned to its edge.
const int kDiscoveryMateCentipawns = 1000;

/// The engine evaluation after every annotated move of [pgn], in centipawns
/// from White's side, in move order. Empty when the PGN carries no `[%eval]`.
List<int> parseEvalCurve(String? pgn) {
  if (pgn == null || pgn.isEmpty) return const [];
  final out = <int>[];
  for (final match in _evalDirective.allMatches(pgn)) {
    final value = double.tryParse(match.group(2) ?? '');
    if (value == null) continue;
    if (match.group(1) != null) {
      out.add(value < 0 ? -kDiscoveryMateCentipawns : kDiscoveryMateCentipawns);
    } else {
      out.add(
        (value * 100).round().clamp(
          -kDiscoveryMateCentipawns,
          kDiscoveryMateCentipawns,
        ),
      );
    }
  }
  return out;
}

// ---------------------------------------------------------------- miniatures

/// A miniature on the Discovery rail: the board-ready game plus the move it
/// ended on ("12 moves").
@immutable
class DiscoveryMiniature {
  const DiscoveryMiniature({required this.game, required this.moves});

  final GamesTourModel game;
  final int moves;
}
