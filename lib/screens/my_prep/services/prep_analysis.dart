import 'dart:math' as math;
import 'dart:typed_data';

import 'package:chessever2/screens/gamebase/services/player_opening_tree.dart';
import 'package:chessever2/screens/my_prep/models/prep_models.dart';
import 'package:chessever2/screens/player_profile/utils/twic_event_identity.dart';
import 'package:chessever2/services/game_tree/game_tree_codec.dart';
import 'package:chessever2/services/game_tree/game_tree_store.dart';
import 'package:chessever2/utils/eco_openings.dart';
import 'package:flutter/foundation.dart';

/// How deep the device-built opening tree reaches, as the server's does.
const int kPrepTreeMaxPly = kGameTreeMaxPly;

/// The outcome of one game from the prepared player's chair.
enum PrepOutcome { win, draw, loss, unknown }

/// One downloaded game, light enough to keep tens of thousands in memory.
/// Its PGN stays in the account's file; [PrepAnalysis.pgnOf] reads it.
@immutable
class PrepGame {
  const PrepGame({
    required this.index,
    required this.source,
    required this.white,
    required this.black,
    required this.result,
    required this.plies,
    this.rowId = 0,
    this.sourcePath = '',
    this.whiteElo,
    this.blackElo,
    this.date,
    this.speed,
    this.timeControlText,
    this.eco,
    this.opening,
    this.url,
    this.event,
    this.site,
    this.round,
    this.eventName,
    this.eventId,
    this.eventSlug,
    this.eventDate,
    this.playerIsWhite,
    this.online,
  });

  /// Position in the newest-first list.
  final int index;

  /// The game's row in the profile's opening index.
  final int rowId;
  final PrepSource source;
  final String white;
  final String black;

  /// `1-0`, `0-1`, `1/2-1/2` or `*`.
  final String result;
  final int plies;
  final int? whiteElo;
  final int? blackElo;
  final DateTime? date;
  final PrepTimeControl? speed;
  final String? timeControlText;
  final String? eco;
  final String? opening;
  final String? url;

  /// The `Event` tag as written, which a broadcast fills with its round.
  final String? event;

  /// The `Site` tag: a venue, or a server's link to the game.
  final String? site;
  final String? round;

  /// What a ChessEver broadcast calls its event, with the id and slug that
  /// open it; null for a game from anywhere else.
  final String? eventName;
  final String? eventId;
  final String? eventSlug;

  /// The event's first day.
  final DateTime? eventDate;

  /// Which side the prepared player had; null when neither name matched.
  final bool? playerIsWhite;

  /// Which account file a game came from (a profile can hold two accounts
  /// on one site).
  final String sourcePath;

  factory PrepGame.fromIndex(GameTreeGame g, int index) => PrepGame(
    index: index,
    rowId: g.id,
    sourcePath: g.sourcePath,
    source: PrepSource.tryParse(g.source) ?? PrepSource.lichess,
    white: g.white,
    black: g.black,
    result: treeResultText(g.result),
    plies: g.plies,
    whiteElo: g.whiteElo,
    blackElo: g.blackElo,
    date: treeDateTime(g.date),
    speed:
        g.speed == null ||
            g.speed! < 0 ||
            g.speed! >= PrepTimeControl.values.length
        ? null
        : PrepTimeControl.values[g.speed!],
    timeControlText: g.timeControl,
    eco: g.eco,
    opening: g.opening,
    url: g.url,
    event: g.event,
    site: g.site,
    round: g.round,
    eventName: g.eventName,
    eventId: g.eventId,
    eventSlug: g.eventSlug,
    eventDate: treeDateTime(g.eventDate),
    online: g.online,
    playerIsWhite: switch (g.side) {
      1 => true,
      2 => false,
      _ => null,
    },
  );

  String get opponent => playerIsWhite == false ? white : black;
  int? get opponentElo => playerIsWhite == false ? whiteElo : blackElo;
  int? get playerElo => playerIsWhite == false ? blackElo : whiteElo;

  double? get averageElo {
    final ratings = [whiteElo, blackElo].whereType<int>().where((r) => r > 0);
    return ratings.isEmpty
        ? null
        : ratings.reduce((a, b) => a + b) / ratings.length;
  }

  /// What the index read from the game's source and `Site`; null for a
  /// game built without the index.
  final bool? online;

  /// Played on a server rather than over the board (the Format filter).
  bool get isOnline =>
      online ?? treeGameIsOnline(sourceKind: source.name, link: url);

  PrepOutcome get outcome {
    final white = playerIsWhite;
    if (white == null) return PrepOutcome.unknown;
    return switch (result) {
      '1-0' => white ? PrepOutcome.win : PrepOutcome.loss,
      '0-1' => white ? PrepOutcome.loss : PrepOutcome.win,
      '1/2-1/2' => PrepOutcome.draw,
      _ => PrepOutcome.unknown,
    };
  }

  /// The tournament this game was played in; null for a server's pool game,
  /// which belongs to none.
  String? get eventTitle =>
      prepEventTitle(broadcast: eventName, event: event, site: site);

  /// What a game card prints where its event goes: the tournament, else
  /// where and how fast the game was played (`Lichess · Blitz`).
  String get eventLabel =>
      eventTitle ??
      (speed == null
          ? source.label
          : '${source.label} · ${speed!.labelFor(source)}');

  /// Games sharing this belong under one event card. Null leaves a game
  /// out of any: an online account's games stay a plain dated list, where
  /// an arena played every hour would otherwise head a section each day.
  String? get eventKey {
    if (source.online) return null;
    final key = eventTitle?.toLowerCase().replaceAll(_notWord, ' ').trim();
    return key == null || key.isEmpty ? null : key;
  }

  /// The family name of the opening, without its variation.
  String get openingFamily {
    final name = opening;
    if (name == null || name.isEmpty) return eco ?? 'Unknown opening';
    return name.split(RegExp(r'[:,]')).first.trim();
  }
}

final RegExp _notWord = RegExp(r'[^\p{L}\p{N}]+', unicode: true);

/// What a server writes as the `Event` of a game played in no tournament:
/// Lichess's `Rated Blitz game` (older exports end in the arena's link) and
/// Chess.com's `Live Chess` and `Let's Play!`.
final RegExp _poolGame = RegExp(
  r"^(?:(?:rated|casual|unrated)\s.*\b(?:game|https?://\S+)"
  r"|live chess|let'?s play!?|daily chess|online chess)$",
  caseSensitive: false,
);

/// The name of the tournament a game belongs to, from what its PGN says.
/// [broadcast] is a ChessEver broadcast's own name for it, which wins:
/// there the `Event` tag may carry a round's dates or pairing instead.
String? prepEventTitle({String? broadcast, String? event, String? site}) {
  final named = broadcast?.trim();
  if (named != null && named.isNotEmpty) return named;
  final raw = event?.trim();
  if (raw == null || raw.isEmpty || raw == '?' || _poolGame.hasMatch(raw)) {
    return null;
  }
  // `Round 7: Carlsen - Caruana` names a pairing; its broadcast link, when
  // the game has one, still names the tournament.
  if (isTwicRoundDisplayTitle(raw)) return eventTitleFromBroadcastSite(site);
  return raw;
}

/// Everything My Prep shows for a profile: the light games list in memory,
/// the tree and every PGN on disk behind [store].
@immutable
class PrepAnalysis {
  const PrepAnalysis({
    required this.profileId,
    required this.games,
    this.store,
    this.shared = 0,
  });

  final String profileId;

  /// Games two of the profile's sources both hold. Read together they count
  /// once, so [games] is that many short of the sources' own counts.
  final int shared;

  /// Newest first.
  final List<PrepGame> games;

  /// The profile's opening index; null only for a profile with no games.
  final GameTreeStore? store;

  static PrepAnalysis empty(String profileId) =>
      PrepAnalysis(profileId: profileId, games: const []);

  PlayerOpeningTreeIndex get tree =>
      store?.tree ?? const PlayerOpeningTreeIndex.empty();

  /// The game's full PGN, read from its account's file.
  String? pgnOf(PrepGame game) => store?.pgn(game.rowId);

  String gameId(PrepGame game) => 'prep:$profileId:${game.rowId}';
}

/// The clock category of a game. Chess.com's own TimeClass is
/// authoritative; Lichess games use its estimated-duration bands.
PrepTimeControl? prepSpeedOf({
  required PrepSource source,
  String? timeControl,
  String? timeClass,
  String? event,
}) {
  final speed = classifyTreeSpeed(
    lichess: source == PrepSource.lichess,
    timeControl: timeControl,
    timeClass: timeClass,
    event: event,
    source: source.name,
  );
  return speed == null ? null : PrepTimeControl.values[speed];
}

/// What each source's games say of the player's clocks, by the name of the
/// source's games file: every clock played, with the player's rating in the
/// newest game of it that carries one, or 0 where none does. A provider's
/// own figure is fresher; this stands in where a source has none.
Map<String, Map<PrepTimeControl, int>> prepGameRatings(List<PrepGame> games) {
  final ratings = <String, Map<PrepTimeControl, int>>{};
  final dated = <String, Map<PrepTimeControl, DateTime?>>{};
  for (final g in games) {
    final speed = g.speed;
    if (speed == null) continue;
    final path = g.sourcePath;
    final file = path.substring(path.lastIndexOf('/') + 1);
    final clocks = ratings.putIfAbsent(file, () => {});
    clocks.putIfAbsent(speed, () => 0);
    // Whose rating it is is only known once the player's side is.
    final rating = g.playerIsWhite == null ? null : g.playerElo;
    if (rating == null || rating <= 0) continue;
    final when = dated.putIfAbsent(file, () => {});
    final kept = when[speed];
    // Games arrive newest first: a later one replaces the rating kept only
    // when it is dated after it, or the kept one has no date.
    if (clocks[speed]! > 0 &&
        (g.date == null || (kept != null && !g.date!.isAfter(kept)))) {
      continue;
    }
    clocks[speed] = rating;
    when[speed] = g.date;
  }
  return ratings;
}

/// The explorer's three clock filters, which fold the fast and slow ends in.
String? prepExplorerTimeControl(PrepTimeControl? speed) =>
    switch (TreeSpeed.explorerClock(speed?.index)) {
      1 => 'blitz',
      2 => 'rapid',
      3 => 'classical',
      _ => null,
    };

// ------------------------------------------------------------------ stats

/// Wins, draws and losses for some slice of the games.
@immutable
class PrepTally {
  const PrepTally({this.wins = 0, this.draws = 0, this.losses = 0});

  final int wins;
  final int draws;
  final int losses;

  int get total => wins + draws + losses;

  /// Points per game, 0..1.
  double? get score => total == 0 ? null : (wins + draws / 2) / total;

  PrepTally operator +(PrepOutcome outcome) => switch (outcome) {
    PrepOutcome.win => PrepTally(wins: wins + 1, draws: draws, losses: losses),
    PrepOutcome.draw => PrepTally(wins: wins, draws: draws + 1, losses: losses),
    PrepOutcome.loss => PrepTally(wins: wins, draws: draws, losses: losses + 1),
    PrepOutcome.unknown => this,
  };
}

@immutable
class PrepOpeningLine {
  const PrepOpeningLine(this.name, this.eco, this.tally, this.games);
  final String name;
  final String? eco;
  final PrepTally tally;

  /// Every game in the line, unfinished ones too: what its row opens.
  final int games;
}

@immutable
class PrepOpponentLine {
  const PrepOpponentLine(this.name, this.rating, this.tally, this.games);
  final String name;

  /// Their average rating across the games against them.
  final int? rating;
  final PrepTally tally;

  /// Every game against them, unfinished ones too: what their row opens.
  final int games;
}

/// One year of games: every game played in it, and the results among them.
/// The difference is the games with no result to count.
@immutable
class PrepYearLine {
  const PrepYearLine(this.year, this.total, this.tally);
  final int year;
  final int total;
  final PrepTally tally;
}

/// The About numbers for a slice of games, defined as the desktop app's
/// Prepare dashboard defines them. Results count only games whose side and
/// outcome are known. Every count that opens a list of games counts what
/// that list will hold.
@immutable
class PrepStats {
  const PrepStats({
    required this.games,
    required this.matching,
    required this.overall,
    required this.asWhite,
    required this.asBlack,
    this.whiteGames = 0,
    this.blackGames = 0,
    this.accounts = 1,
    this.ratingPath,
    required this.whiteOpenings,
    required this.blackOpenings,
    required this.opponents,
    required this.byYear,
    required this.lengths,
    this.clocks = const [],
    this.peakRating,
    this.currentRating,
    this.ratingSpeed,
    this.ratingSource,
    this.performance,
    this.averageOpponent,
    this.ratingHistory = const [],
  });

  /// Every game the results are counted among, including those left out of
  /// them. A chosen result does not narrow this or [overall]: they are what
  /// it is chosen from.
  final int games;

  /// The games every choice together leaves: what the Games tab lists.
  final int matching;
  final PrepTally overall;
  final PrepTally asWhite;
  final PrepTally asBlack;

  /// Every game with each colour, unfinished ones too. A chosen colour does
  /// not narrow these or the two tallies above.
  final int whiteGames;
  final int blackGames;

  /// How many sources the slice's games come from.
  final int accounts;

  /// The file of the source every rating figure is on the scale of: the
  /// history, the peak, the opponents' average and the performance. Ratings
  /// from two sources are different scales, so a slice of several follows
  /// one of them and none is ever averaged with another.
  final String? ratingPath;

  /// The ten most played ECO codes with each colour, and after them a
  /// chosen one that is not among the ten.
  final List<PrepOpeningLine> whiteOpenings;
  final List<PrepOpeningLine> blackOpenings;
  final List<PrepOpponentLine> opponents;
  final List<PrepYearLine> byYear;

  /// Games by length in moves: 0–20, 21–30, 31–40, 41–50, 50+.
  final List<int> lengths;
  static const lengthLabels = ['0–20', '21–30', '31–40', '41–50', '50+'];

  /// How the games divide by clock, most played first, every game counted.
  /// A chosen clock does not narrow it, so the others stay beside it.
  final List<(PrepTimeControl?, int)> clocks;

  /// The highest and the latest point of [ratingHistory].
  final int? peakRating;
  final int? currentRating;

  /// The clock [ratingHistory] follows; null when it spans every clock.
  final PrepTimeControl? ratingSpeed;

  /// The provider whose scale [ratingHistory] is on.
  final PrepSource? ratingSource;
  final int? performance;
  final int? averageOpponent;
  final List<(DateTime, int)> ratingHistory;

  int get decisive => overall.wins + overall.losses;

  /// The share of decided games that had a winner, 0..1.
  double? get decisiveRate =>
      overall.total == 0 ? null : decisive / overall.total;

  /// Which of [lengthLabels] a game of [plies] half-moves falls under; null
  /// when its moves are not known.
  static int? lengthOf(int plies) => plies <= 0
      ? null
      : plies <= 40
      ? 0
      : plies <= 60
      ? 1
      : plies <= 80
      ? 2
      : plies <= 100
      ? 3
      : 4;

  /// The numbers for [games] as they are, nothing chosen among them.
  /// [preferredRating] is the ladder the rating history follows: left out,
  /// blitz on a site's own scale and classical on FIDE's. [ratingAccount] is
  /// the file of the source whose scale a slice of several sources should
  /// follow, when that source has rated games.
  static PrepStats of(
    Iterable<PrepGame> games, {
    PrepTimeControl? preferredRating,
    String? ratingAccount,
  }) => PrepFacets(
    games is List<PrepGame> ? games : games.toList(),
  ).stats(preferredRating: preferredRating, ratingAccount: ratingAccount);

  static String? _openingName(String? raw) {
    final name = raw?.trim();
    return switch (name?.toLowerCase()) {
      null || '' || '?' || '-' || 'unknown' || 'unknown opening' => null,
      _ => name,
    };
  }

  /// One rating per day on a single ladder of one source: the scoped clock,
  /// else the preferred one when it was played, else the most played of
  /// classical, rapid and blitz, else the most played clock of all. A
  /// classical preference follows every rated game when the rated history
  /// begins before the classical games do.
  ///
  /// [rated] is one source's games: ratings from two accounts or providers
  /// are separate scales and are never drawn as one line.
  static (List<(DateTime, int)>, PrepTimeControl?) _ratingSeries(
    List<PrepGame> rated, {
    required PrepTimeControl? scoped,
    required PrepTimeControl preferred,
  }) {
    if (rated.isEmpty) return (const [], null);
    var candidates = rated;
    var selected = scoped;
    if (scoped == null) {
      const order = [
        PrepTimeControl.classical,
        PrepTimeControl.rapid,
        PrepTimeControl.blitz,
      ];
      final counts = <PrepTimeControl, int>{};
      for (final g in rated) {
        final speed = g.speed;
        if (speed != null && order.contains(speed)) {
          counts[speed] = (counts[speed] ?? 0) + 1;
        }
      }
      if (counts.containsKey(preferred)) {
        selected = preferred;
      } else if (counts.isNotEmpty) {
        selected = order
            .where(counts.containsKey)
            .reduce((a, b) => counts[a]! >= counts[b]! ? a : b);
      } else {
        // Only the fastest or the slowest clocks: still one ladder, the
        // most played, not bullet and daily drawn as one line.
        for (final g in rated) {
          if (g.speed case final speed?) {
            counts[speed] = (counts[speed] ?? 0) + 1;
          }
        }
        if (counts.isNotEmpty) {
          selected = counts.keys.reduce(
            (a, b) => counts[a]! >= counts[b]! ? a : b,
          );
        }
      }
      if (selected != null) {
        final own = [
          for (final g in rated)
            if (g.speed == selected) g,
        ];
        DateTime first(List<PrepGame> list) =>
            list.map((g) => g.date!).reduce((a, b) => a.isBefore(b) ? a : b);
        if (preferred == PrepTimeControl.classical &&
            own.isNotEmpty &&
            first(rated).isBefore(first(own))) {
          selected = null;
        } else {
          candidates = own;
        }
      }
    }
    // Games arrive newest first, so the first seen on a day is its last.
    final byDay = <int, (DateTime, int)>{};
    for (final g in candidates) {
      final date = g.date!;
      byDay.putIfAbsent(
        date.year * 10000 + date.month * 100 + date.day,
        () => (date, g.playerElo!),
      );
    }
    final spots = byDay.values.toList()..sort((a, b) => a.$1.compareTo(b.$1));
    const most = 400;
    if (spots.length <= most) return (spots, selected);
    final step = spots.length / most;
    final out = [for (var i = 0; i < most; i++) spots[(i * step).floor()]];
    if (out.last != spots.last) out.add(spots.last);
    return (out, selected);
  }
}

/// What About's own controls narrow a profile's games by: one choice from
/// each group of them on the page.
@immutable
class PrepPick {
  const PrepPick({
    this.white,
    this.outcome,
    this.speed,
    this.year,
    this.eco,
    this.opponent,
    this.length,
  });

  /// The player's colour; null for both.
  final bool? white;
  final PrepOutcome? outcome;
  final PrepTimeControl? speed;
  final int? year;
  final String? eco;
  final String? opponent;

  /// An index into [PrepStats.lengthLabels].
  final int? length;
}

/// A profile's games as columns of small numbers, read once, so that every
/// About figure is counted again in one pass each time a choice changes: a
/// source of tens of thousands of games answers a tap within the frame.
///
/// A choice narrows every figure but those of its own group. With Blitz
/// chosen the openings, opponents and years are the blitz ones, while the
/// clocks still list every clock beside it. A group is therefore counted
/// over the games that pass every choice except its own.
class PrepFacets {
  PrepFacets(this.games)
    : _side = Uint8List(games.length),
      _outcome = Uint8List(games.length),
      _clock = Uint8List(games.length),
      _year = Int16List(games.length),
      _length = Int8List(games.length),
      _eco = Int32List(games.length),
      _opponent = Int32List(games.length),
      _theirElo = Int16List(games.length),
      _scale = Uint16List(games.length) {
    PrepSource? lastSource;
    String? lastPath;
    var lastScale = 0;
    for (var i = 0; i < games.length; i++) {
      final g = games[i];
      final white = g.playerIsWhite;
      final side = white == null
          ? 0
          : white
          ? 1
          : 2;
      _side[i] = side;
      _outcome[i] = g.outcome.index;
      final clock = g.speed == null ? 0 : g.speed!.index + 1;
      _clock[i] = clock;
      if (!_clockSeen[clock]) {
        _clockSeen[clock] = true;
        _clockOrder.add(clock);
      }
      final year = g.date?.year ?? 0;
      if (year > 0 && year <= 0x7fff) {
        _year[i] = year;
        if (_lastYear == 0 || year < _firstYear) _firstYear = year;
        if (year > _lastYear) _lastYear = year;
      }
      _length[i] = PrepStats.lengthOf(g.plies) ?? -1;

      final code = g.eco?.trim().toUpperCase() ?? '';
      if (code.isEmpty) {
        _eco[i] = -1;
      } else {
        var id = _ecoIds[code];
        if (id == null) {
          id = _ecoIds[code] = _ecoCodes.length;
          _ecoCodes.add(code);
          _ecoNames
            ..add(null)
            ..add(null);
          _ecoPlayed
            ..add(false)
            ..add(false);
        }
        _eco[i] = id;
        if (side != 0) {
          final slot = id * 2 + side - 1;
          _ecoPlayed[slot] = true;
          // The game's own name for the opening, from the newest that has
          // one, so a line reads the same whatever is chosen around it.
          _ecoNames[slot] ??= PrepStats._openingName(g.opening);
        }
      }

      // Who the opponent was is only known once the player's side is.
      _opponent[i] = -1;
      if (side != 0) {
        final name = g.opponent.trim();
        if (name.isNotEmpty && name != '?') {
          final key = name.toLowerCase();
          var id = _opponentIds[key];
          if (id == null) {
            id = _opponentIds[key] = _opponentNames.length;
            _opponentNames.add(name);
          }
          _opponent[i] = id;
        }
        final theirs = g.opponentElo ?? 0;
        if (theirs > 0) _theirElo[i] = math.min(theirs, 0x7fff);
      }

      // Each source rates on its own scale. Games arrive a source at a
      // time, so the last one seen is nearly always this one's too.
      if (g.source != lastSource || g.sourcePath != lastPath) {
        lastSource = g.source;
        lastPath = g.sourcePath;
        final key = '${g.source.name}|${g.sourcePath}';
        var id = _scaleIds[key];
        if (id == null) {
          id = _scaleIds[key] = _scales.length;
          _scales.add((g.source, g.sourcePath));
        }
        lastScale = id;
      }
      _scale[i] = lastScale;
    }
  }

  /// Newest first, as [PrepAnalysis.games] holds them.
  final List<PrepGame> games;

  /// 0 unknown, 1 White, 2 Black.
  final Uint8List _side;

  /// A [PrepOutcome]'s index.
  final Uint8List _outcome;

  /// A [PrepTimeControl]'s index + 1; 0 for a game of no known clock.
  final Uint8List _clock;

  /// 0 for an undated game.
  final Int16List _year;

  /// An index into [PrepStats.lengthLabels]; -1 for unknown moves.
  final Int8List _length;

  /// An index into [_ecoCodes]; -1 for a game without a code.
  final Int32List _eco;

  /// An index into [_opponentNames]; -1 where the opponent is not known.
  final Int32List _opponent;

  /// The opponent's rating; 0 where it is unknown.
  final Int16List _theirElo;

  /// An index into [_scales].
  final Uint16List _scale;

  final Map<String, int> _ecoIds = {};
  final List<String> _ecoCodes = [];

  /// Two per code, White then Black: the name the games give the opening,
  /// and whether the player ever had it with that colour.
  final List<String?> _ecoNames = [];
  final List<bool> _ecoPlayed = [];

  final Map<String, int> _opponentIds = {};
  final List<String> _opponentNames = [];
  final Map<String, int> _scaleIds = {};
  final List<(PrepSource, String)> _scales = [];

  /// The clocks in the order the games first show them.
  final List<int> _clockOrder = [];
  final List<bool> _clockSeen = List.filled(
    PrepTimeControl.values.length + 1,
    false,
  );
  int _firstYear = 0;
  int _lastYear = 0;

  Object? _scopeKey;
  Uint8List? _scopeMask;

  /// The games a filter's other narrowings leave, as one byte a game: 1 for
  /// a game left in. The one read last is kept under [key], as choices
  /// change far more often than what they are made within.
  Uint8List scoped(Object key, bool Function(PrepGame game) holds) {
    final kept = _scopeMask;
    if (kept != null && _scopeKey == key) return kept;
    final mask = Uint8List(games.length);
    for (var i = 0; i < games.length; i++) {
      if (holds(games[i])) mask[i] = 1;
    }
    _scopeKey = key;
    return _scopeMask = mask;
  }

  static const int _bySide = 1;
  static const int _byOutcome = 2;
  static const int _byClock = 4;
  static const int _byYear = 8;
  static const int _byEco = 16;
  static const int _byOpponent = 32;
  static const int _byLength = 64;

  /// No game holds this id: a choice the games here never had.
  static const int _absent = -2;

  /// The About numbers with [pick] chosen, among the games [scope] leaves
  /// in (every game without one). [preferredRating] and [ratingAccount] are
  /// those of [PrepStats.of].
  PrepStats stats({
    PrepPick pick = const PrepPick(),
    Uint8List? scope,
    PrepTimeControl? preferredRating,
    String? ratingAccount,
  }) {
    final wantSide = switch (pick.white) {
      null => 0,
      true => 1,
      false => 2,
    };
    final wantOutcome = pick.outcome?.index ?? -1;
    final wantClock = pick.speed == null ? -1 : pick.speed!.index + 1;
    final wantYear = pick.year ?? 0;
    final chosenEco = pick.eco?.trim().toUpperCase();
    final wantEco = chosenEco == null ? -1 : _ecoIds[chosenEco] ?? _absent;
    final chosenOpponent = pick.opponent?.trim().toLowerCase();
    final wantOpponent = chosenOpponent == null
        ? -1
        : _opponentIds[chosenOpponent] ?? _absent;
    final wantLength = pick.length ?? -1;

    var matching = 0;
    var counted = 0;
    final results = Int32List(4);
    final colours = Int32List(8);
    final lines = Int32List(_ecoCodes.length * 8);
    final clocks = Int32List(_clockSeen.length);
    final span = _lastYear == 0 ? 0 : _lastYear - _firstYear + 1;
    final years = Int32List(span * 4);
    final opponents = Int32List(_opponentNames.length * 4);
    final theirSum = Float64List(_opponentNames.length);
    final theirCount = Int32List(_opponentNames.length);
    final lengths = List<int>.filled(PrepStats.lengthLabels.length, 0);
    final scales = List<_Scale?>.filled(_scales.length, null);

    for (var i = 0; i < games.length; i++) {
      if (scope != null && scope[i] == 0) continue;
      final side = _side[i];
      final outcome = _outcome[i];
      final eco = _eco[i];
      final opponent = _opponent[i];
      // Which choices this game does not meet.
      var miss = 0;
      if (wantSide != 0 && side != wantSide) miss |= _bySide;
      if (wantOutcome >= 0 && outcome != wantOutcome) miss |= _byOutcome;
      if (wantClock >= 0 && _clock[i] != wantClock) miss |= _byClock;
      if (wantYear != 0 && _year[i] != wantYear) miss |= _byYear;
      if (wantEco != -1 && eco != wantEco) miss |= _byEco;
      if (wantOpponent != -1 && opponent != wantOpponent) miss |= _byOpponent;
      if (wantLength >= 0 && _length[i] != wantLength) miss |= _byLength;

      if (miss & ~_byOutcome == 0) {
        counted++;
        if (side != 0) results[outcome]++;
      }
      if (miss & ~_bySide == 0 && side != 0) {
        colours[(side - 1) * 4 + outcome]++;
      }
      // A line is of one colour by its place on the page, so the colour
      // chosen narrows the lines no more than the line chosen does.
      if (miss & ~(_byEco | _bySide) == 0 && side != 0 && eco >= 0) {
        lines[eco * 8 + (side - 1) * 4 + outcome]++;
      }
      if (miss & ~_byClock == 0) clocks[_clock[i]]++;
      if (miss & ~_byYear == 0 && _year[i] != 0) {
        years[(_year[i] - _firstYear) * 4 + outcome]++;
      }
      if (miss & ~_byOpponent == 0 && opponent >= 0) {
        opponents[opponent * 4 + outcome]++;
        final theirs = _theirElo[i];
        if (theirs > 0) {
          theirSum[opponent] += theirs;
          theirCount[opponent]++;
        }
      }
      if (miss & ~_byLength == 0 && _length[i] >= 0) lengths[_length[i]]++;

      if (miss != 0) continue;
      matching++;
      // What ratings say is kept apart by source until one is chosen.
      final at = _scale[i];
      final scale = scales[at] ??= _Scale(_scales[at].$1, _scales[at].$2);
      if (side == 0) continue;
      scale.results[outcome]++;
      final theirs = _theirElo[i];
      if (theirs > 0) {
        scale.opponentSum += theirs;
        scale.opponentCount++;
      }
      final g = games[i];
      if ((g.playerElo ?? 0) > 0 && g.date != null) scale.rated.add(g);
    }

    PrepTally tally(Int32List counts, int at) => PrepTally(
      wins: counts[at],
      draws: counts[at + 1],
      losses: counts[at + 2],
    );
    int every(Int32List counts, int at) =>
        counts[at] + counts[at + 1] + counts[at + 2] + counts[at + 3];

    List<PrepOpeningLine> top(int colour) {
      PrepOpeningLine line(int id) {
        final code = _ecoCodes[id];
        final at = id * 8 + colour * 4;
        return PrepOpeningLine(
          // The game's own opening name, else the code's catalogue name.
          _ecoNames[id * 2 + colour] ?? EcoOpenings.codeToName[code] ?? code,
          code,
          tally(lines, at),
          every(lines, at),
        );
      }

      final ranked =
          [
            for (var id = 0; id < _ecoCodes.length; id++)
              // A line is a result to show: one never finished is not one.
              if (tally(lines, id * 8 + colour * 4).total > 0) line(id),
          ]..sort((a, b) {
            final byGames = b.tally.total.compareTo(a.tally.total);
            return byGames != 0 ? byGames : a.eco!.compareTo(b.eco!);
          });
      final out = ranked.take(10).toList();
      if (chosenEco == null || chosenEco.isEmpty) return out;
      // The chosen line keeps its row where the other choices leave it few
      // games or none: it is given up by the tap that took it.
      bool played(int c) => wantEco >= 0 && _ecoPlayed[wantEco * 2 + c];
      final here =
          wantSide == colour + 1 ||
          (wantSide == 0 &&
              (played(colour) || (colour == 0 && !played(1 - colour))));
      if (!here || out.any((l) => l.eco == chosenEco)) return out;
      return out..add(
        wantEco >= 0
            ? line(wantEco)
            : PrepOpeningLine(
                EcoOpenings.codeToName[chosenEco] ?? chosenEco,
                chosenEco,
                const PrepTally(),
                0,
              ),
      );
    }

    PrepOpponentLine against(int id) => PrepOpponentLine(
      _opponentNames[id],
      theirCount[id] == 0 ? null : (theirSum[id] / theirCount[id]).round(),
      tally(opponents, id * 4),
      every(opponents, id * 4),
    );
    // An online account meets tens of thousands of opponents, so the ten
    // most played are picked out as they are passed rather than sorted out
    // of all of them: most games first, then most wins, then first met.
    final most = <int>[];
    for (var id = 0; id < _opponentNames.length; id++) {
      final at = id * 4;
      final total = opponents[at] + opponents[at + 1] + opponents[at + 2];
      if (total == 0) continue;
      var place = most.length;
      while (place > 0) {
        final above = most[place - 1] * 4;
        final theirs =
            opponents[above] + opponents[above + 1] + opponents[above + 2];
        if (theirs > total ||
            (theirs == total && opponents[above] >= opponents[at])) {
          break;
        }
        place--;
      }
      if (place >= 10) continue;
      most.insert(place, id);
      if (most.length > 10) most.removeLast();
    }
    final opponentLines = [for (final id in most) against(id)];
    if (chosenOpponent != null &&
        chosenOpponent.isNotEmpty &&
        !opponentLines.any((o) => o.name.toLowerCase() == chosenOpponent)) {
      opponentLines.add(
        wantOpponent >= 0
            ? against(wantOpponent)
            : PrepOpponentLine(
                pick.opponent!.trim(),
                null,
                const PrepTally(),
                0,
              ),
      );
    }

    final byYear = [
      for (var y = 0; y < span; y++)
        if (every(years, y * 4) > 0 || _firstYear + y == wantYear)
          PrepYearLine(
            _firstYear + y,
            every(years, y * 4),
            tally(years, y * 4),
          ),
    ];
    if (wantYear != 0 && !byYear.any((y) => y.year == wantYear)) {
      byYear
        ..add(PrepYearLine(wantYear, 0, const PrepTally()))
        ..sort((a, b) => a.year.compareTo(b.year));
    }

    final clockLines = [
      for (final clock in _clockOrder)
        if (clocks[clock] > 0 || clock == wantClock)
          (
            clock == 0 ? null : PrepTimeControl.values[clock - 1],
            clocks[clock],
          ),
    ]..sort((a, b) => b.$2.compareTo(a.$2));
    if (wantClock >= 0 && !_clockSeen[wantClock]) {
      clockLines.add((pick.speed, 0));
    }

    // One source's scale for every rating figure: the one asked for when it
    // has rated games, else the one with most of them, else the one with
    // most rated opponents.
    final read = scales.whereType<_Scale>().toList();
    _Scale? scale;
    for (final candidate in read) {
      if (ratingAccount != null &&
          candidate.rated.isNotEmpty &&
          candidate.path.endsWith(ratingAccount)) {
        scale = candidate;
        break;
      }
      if (scale == null ||
          candidate.rated.length > scale.rated.length ||
          (candidate.rated.length == scale.rated.length &&
              candidate.opponentCount > scale.opponentCount)) {
        scale = candidate;
      }
    }
    final rating = scale == null
        ? (const <(DateTime, int)>[], null)
        : PrepStats._ratingSeries(
            scale.rated,
            scoped: pick.speed,
            preferred:
                preferredRating ??
                (scale.source.online
                    ? PrepTimeControl.blitz
                    : PrepTimeControl.classical),
          );
    final average = scale == null || scale.opponentCount == 0
        ? null
        : (scale.opponentSum / scale.opponentCount).round();
    final scored = scale == null ? null : tally(scale.results, 0).score;

    return PrepStats(
      games: counted,
      matching: matching,
      overall: tally(results, 0),
      asWhite: tally(colours, 0),
      asBlack: tally(colours, 4),
      whiteGames: every(colours, 0),
      blackGames: every(colours, 4),
      accounts: read.length,
      // Named only where there is a rating figure for it to explain.
      ratingPath: rating.$1.isNotEmpty || average != null ? scale?.path : null,
      whiteOpenings: top(0),
      blackOpenings: top(1),
      opponents: opponentLines,
      byYear: byYear,
      lengths: lengths,
      clocks: clockLines,
      peakRating: rating.$1.isEmpty
          ? null
          : rating.$1.map((p) => p.$2).reduce((a, b) => a > b ? a : b),
      currentRating: rating.$1.isEmpty ? null : rating.$1.last.$2,
      ratingSpeed: rating.$2,
      ratingSource: rating.$1.isEmpty ? null : scale?.source,
      // The opposition's average and the score against it, both from the
      // one source whose scale they are on. Games of one result alone score
      // all or nothing, which measures no performance.
      performance: average == null || scored == null || pick.outcome != null
          ? null
          : average + _fideDp[(scored * 100).round().clamp(0, 100)],
      averageOpponent: average,
      ratingHistory: rating.$1,
    );
  }
}

/// What one source's games say on that source's own rating scale.
class _Scale {
  _Scale(this.source, this.path);
  final PrepSource source;
  final String path;

  /// The games carrying the player's own rating and a date.
  final List<PrepGame> rated = [];

  /// Games by [PrepOutcome], among those whose side is known.
  final Int32List results = Int32List(4);
  int opponentSum = 0;
  int opponentCount = 0;
}

/// FIDE's rating difference for a score percentage, 0..100.
const List<int> _fideDp = [
  -800, -677, -589, -538, -501, -470, -444, -422, -401, -383, -366, -351, //
  -336, -322, -309, -296, -284, -273, -262, -251, -240, -230, -220, -211, //
  -202, -193, -184, -175, -166, -158, -149, -141, -133, -125, -117, -110, //
  -102, -95, -87, -80, -72, -65, -57, -50, -43, -36, -29, -21, -14, -7, 0, //
  7, 14, 21, 29, 36, 43, 50, 57, 65, 72, 80, 87, 95, 102, 110, 117, 125, 133, //
  141, 149, 158, 166, 175, 184, 193, 202, 211, 220, 230, 240, 251, 262, 273, //
  284, 296, 309, 322, 336, 351, 366, 383, 401, 422, 444, 470, 501, 538, 589, //
  677, 800,
];
