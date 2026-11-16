import 'package:chessever2/repository/supabase/tour/tour.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/utils/broadcast_custom_scoring.dart';

/// Utility class to detect and handle knockout tournament formats
/// where players face each other multiple times in matches
class KnockoutMatchDetector {
  /// Whether an individual knockout feed is appending replay/decider games to
  /// one source round instead of publishing a new round for every leg.
  ///
  /// This is the shape used by double-elimination/GSL feeds such as EWC: the
  /// same player pair appears again under one [GamesTourModel.roundId], and
  /// each new game receives a higher board number. Requiring both a shared
  /// source round and a repeated matchup keeps ordinary Swiss/round-robin
  /// board order out of this special path.
  static bool hasRepeatedMatchupInSingleSourceRound({
    required bool isKnockoutTournament,
    required List<GamesTourModel> games,
  }) {
    if (!isKnockoutTournament) return false;
    if (games.length < 2) return false;
    if (games.map((game) => game.roundId).toSet().length != 1) return false;

    final matches = groupByMatches(games);
    if (matches.values.fold<int>(0, (count, match) => count + match.length) !=
        games.length) {
      return false;
    }
    return matches.values.any((match) => match.length > 1);
  }

  /// The MATCH-PLAY ROUND gate: a knockout round in which at least one
  /// unordered player pair has two or more games inside the same source round.
  ///
  /// Speed Chess Championship publishes every match of a stage in one round
  /// file and keeps appending games (game 1 of every match is created up
  /// front as a 0-move shell, then game 2, ...). Only rounds of that shape get
  /// the match-play presentation (a fixed side per player, chronological
  /// anchoring, shells that are not live). Legs published as separate source
  /// rounds (World Cup game-1 / game-2 rounds) and every non-knockout event
  /// are never match-play, so they keep their existing behaviour.
  static bool isMatchPlayRound({
    required bool isKnockoutTournament,
    required Iterable<GamesTourModel> games,
  }) {
    if (!isKnockoutTournament) return false;
    final list = games.toList(growable: false);
    return _repeatingSourceRoundIds(
      list,
      _ParticipantIdentityRegistry(list),
    ).isNotEmpty;
  }

  /// The matches of a knockout display round that get the match-play
  /// presentation, keyed like [groupByMatches] over the same [games].
  ///
  /// A match is match play when every one of its games sits in a source
  /// round where some pairing repeats ([isMatchPlayRound] for that round).
  /// Speed Chess Championship keeps every match of a stage in one such round,
  /// so all of them qualify, including matches that still have one shell;
  /// Women's Speed Chess Championship gives each match a round of its own.
  /// A match with legs in rounds of their own stays on the legacy path even
  /// when its tiebreak games share a round (Lichess `Round N.Tiebreaks`), and
  /// so do the other matches of that stage.
  static Set<String> matchPlayMatchKeys({
    required bool isKnockoutTournament,
    required Iterable<GamesTourModel> games,
  }) {
    if (!isKnockoutTournament) return const <String>{};
    final list = games.toList(growable: false);
    final identities = _ParticipantIdentityRegistry(list);
    final repeating = _repeatingSourceRoundIds(list, identities);
    if (repeating.isEmpty) return const <String>{};
    final allInRepeating = <String, bool>{};
    for (final game in list) {
      final key = _getMatchupKey(
        game.whitePlayer,
        game.blackPlayer,
        identities,
      );
      if (key == null) continue;
      allInRepeating[key] =
          (allInRepeating[key] ?? true) && repeating.contains(game.roundId);
    }
    return <String>{
      for (final entry in allInRepeating.entries)
        if (entry.value) entry.key,
    };
  }

  /// Source rounds in which one pairing has two or more games.
  static Set<String> _repeatingSourceRoundIds(
    List<GamesTourModel> games,
    _ParticipantIdentityRegistry identities,
  ) {
    final keysBySourceRound = <String, Set<String>>{};
    final repeating = <String>{};
    for (final game in games) {
      final key = _getMatchupKey(
        game.whitePlayer,
        game.blackPlayer,
        identities,
      );
      if (key == null) continue;
      final keys = keysBySourceRound.putIfAbsent(
        game.roundId,
        () => <String>{},
      );
      if (!keys.add(key)) repeating.add(game.roundId);
    }
    return repeating;
  }

  /// Source rounds that hold the games of one match and no other: a round
  /// per match (Women's Speed Chess Championship). Such a round's `starts_at`
  /// is that match's own scheduled start. A round shared by several matches
  /// (Speed Chess Championship) is every match's, so it is not in this set.
  static Set<String> singleMatchSourceRoundIds(Iterable<GamesTourModel> games) {
    final list = games.toList(growable: false);
    final identities = _ParticipantIdentityRegistry(list);
    final keysBySourceRound = <String, Set<String>>{};
    final unpaired = <String>{};
    for (final game in list) {
      final key = _getMatchupKey(
        game.whitePlayer,
        game.blackPlayer,
        identities,
      );
      if (key == null) {
        unpaired.add(game.roundId);
        continue;
      }
      keysBySourceRound.putIfAbsent(game.roundId, () => <String>{}).add(key);
    }
    return <String>{
      for (final entry in keysBySourceRound.entries)
        if (entry.value.length == 1 && !unpaired.contains(entry.key))
          entry.key,
    };
  }

  /// A match game's position inside its match, read from the PGN `[Round]`
  /// tag: `S.NN` gives game NN of stage S, `S.SET.G` gives game G of set SET.
  /// Null when the PGN is absent (deferred) or the tag is not of that shape.
  ///
  /// Board numbers cannot identify a game: the broadcast ingest renumbers
  /// `board_nr` every cycle to follow the source file's order, and the source
  /// inserts new games mid-file. `[Board]` tags are ignored on purpose.
  ///
  /// Lichess and organizer feeds write `round.board` in the same shape ('5.3'
  /// is round 5, board 3), so an index is only trusted for a whole match
  /// whose indexed games share one stage (see
  /// [orderMatchPlayGamesChronologically]).
  static ({int stage, int set, int game})? matchPlayGameIndexFromPgn(
    String? pgn,
  ) {
    if (pgn == null || pgn.isEmpty) return null;
    // Tags sit at the top; never scan a long movetext for a missing tag.
    final head = pgn.length > 4096 ? pgn.substring(0, 4096) : pgn;
    final value = _pgnRoundTagPattern.firstMatch(head)?.group(1)?.trim();
    if (value == null || value.isEmpty) return null;
    final parts = value.split('.');
    if (parts.length != 2 && parts.length != 3) return null;
    final numbers = <int>[];
    for (final part in parts) {
      final number = int.tryParse(part.trim());
      if (number == null || number < 0) return null;
      numbers.add(number);
    }
    return parts.length == 2
        ? (stage: numbers[0], set: 0, game: numbers[1])
        : (stage: numbers[0], set: numbers[1], game: numbers[2]);
  }

  /// Game indexes of one match, or every index null when they cannot be
  /// trusted: the indexed games must share one stage and no two may claim the
  /// same game. Decided from the indexed games alone, so a game whose PGN is
  /// deferred once it finishes never turns a rejected index into an accepted
  /// one (or the reverse) for the rest of the match.
  static Map<String, _GameIndex?> _trustedGameIndexes(
    List<GamesTourModel> games,
  ) {
    final indexById = <String, _GameIndex?>{
      for (final game in games)
        game.gameId: matchPlayGameIndexFromPgn(game.pgn),
    };
    final indexed = indexById.values.whereType<_GameIndex>().toList(
      growable: false,
    );
    final stages = indexed.map((index) => index.stage).toSet();
    final claimed = indexed.map((index) => (index.set, index.game)).toSet();
    if (stages.length > 1 || claimed.length != indexed.length) {
      return <String, _GameIndex?>{for (final game in games) game.gameId: null};
    }
    return indexById;
  }

  static final RegExp _pgnRoundTagPattern = RegExp(
    r'^\s*\[Round\s+"([^"]*)"\s*\]',
    multiLine: true,
  );

  /// Whether a match-play game has been started: a move exists. A 0-move
  /// shell is not started, whatever its `*` status says.
  static bool matchPlayGameHasMoves(GamesTourModel game) {
    if (game.hasStarted) return true;
    final board = game.fen?.trim().split(RegExp(r'\s+')).first;
    return board != null &&
        board.isNotEmpty &&
        board != 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR';
  }

  /// A match-play game is live only once it has a move and is not finished.
  static bool isMatchPlayGameLive(GamesTourModel game) =>
      !game.effectiveGameStatus.isFinished && matchPlayGameHasMoves(game);

  /// Total chronological order of one match's games (game 1 first).
  ///
  /// When every game carries a trusted PGN game index, that index decides,
  /// then `board_nr` ascending, then game id. Lean rows defer the PGN of
  /// finished games, so with any index missing the order falls back to what
  /// a match guarantees: games are played one after another, so finished
  /// games come first (by index when all of them have one, else by last move
  /// time), then the game in play, then the unplayed shells (by index, else
  /// `board_nr`). Every tier ends on `board_nr` then game id, so the order is
  /// total and never depends on the input order. Indexes that disagree on
  /// the stage, or claim one game twice, are round.board tags and are not
  /// used at all.
  static List<GamesTourModel> orderMatchPlayGamesChronologically(
    List<GamesTourModel> games,
  ) {
    if (games.length < 2) return games.toList();
    final indexById = _trustedGameIndexes(games);
    int byIndex(GamesTourModel a, GamesTourModel b) {
      final aIndex = indexById[a.gameId]!;
      final bIndex = indexById[b.gameId]!;
      final bySet = aIndex.set.compareTo(bIndex.set);
      return bySet != 0 ? bySet : aIndex.game.compareTo(bIndex.game);
    }

    bool allIndexed(Iterable<GamesTourModel> list) =>
        list.every((game) => indexById[game.gameId] != null);

    if (allIndexed(games)) {
      return games.toList()..sort((a, b) {
        final index = byIndex(a, b);
        return index != 0 ? index : _compareBoardThenId(a, b);
      });
    }

    final finished = <GamesTourModel>[];
    final live = <GamesTourModel>[];
    final unstarted = <GamesTourModel>[];
    for (final game in games) {
      if (game.effectiveGameStatus.isFinished) {
        finished.add(game);
      } else if (matchPlayGameHasMoves(game)) {
        live.add(game);
      } else {
        unstarted.add(game);
      }
    }

    void sortTier(
      List<GamesTourModel> tier, {
      bool byLastMoveTime = false,
    }) {
      final indexed = allIndexed(tier);
      tier.sort((a, b) {
        if (indexed) {
          final index = byIndex(a, b);
          if (index != 0) return index;
        } else if (byLastMoveTime) {
          final aTime = a.lastMoveTime;
          final bTime = b.lastMoveTime;
          if (aTime != null && bTime != null) {
            final byTime = aTime.compareTo(bTime);
            if (byTime != 0) return byTime;
          } else if (aTime != null) {
            return -1;
          } else if (bTime != null) {
            return 1;
          }
        }
        return _compareBoardThenId(a, b);
      });
    }

    sortTier(finished, byLastMoveTime: true);
    sortTier(live);
    sortTier(unstarted);
    return [...finished, ...live, ...unstarted];
  }

  /// Display order inside one match-play match: the game in play first, then
  /// finished games newest first, then unplayed shells in game order.
  /// [chronologicalGames] must come from [orderMatchPlayGamesChronologically].
  static List<GamesTourModel> orderMatchPlayGamesForDisplay(
    List<GamesTourModel> chronologicalGames,
  ) {
    final live = <GamesTourModel>[];
    final finished = <GamesTourModel>[];
    final unstarted = <GamesTourModel>[];
    for (final game in chronologicalGames) {
      if (game.effectiveGameStatus.isFinished) {
        finished.add(game);
      } else if (matchPlayGameHasMoves(game)) {
        live.add(game);
      } else {
        unstarted.add(game);
      }
    }
    return [...live.reversed, ...finished.reversed, ...unstarted];
  }

  /// Per game id, whether the match's side A plays White in that game.
  ///
  /// Side A is White of the match's first game ([chronologicalGames] must
  /// come from [orderMatchPlayGamesChronologically]): game 1 belongs to the
  /// higher seed. Players are matched by FIDE id first, then by name. A stays
  /// on the left of every card, the top of the header and the bottom of every
  /// board, whatever the score.
  static Map<String, bool> matchPlayAnchorIsWhiteByGameId(
    List<GamesTourModel> chronologicalGames,
  ) {
    if (chronologicalGames.isEmpty) return const <String, bool>{};
    final identities = _ParticipantIdentityRegistry(chronologicalGames);
    final anchorId = identities.idFor(chronologicalGames.first.whitePlayer);
    return <String, bool>{
      for (final game in chronologicalGames)
        game.gameId:
            anchorId == null || identities.idFor(game.blackPlayer) != anchorId,
    };
  }

  /// When a match-play match was last played: the latest last-move time of
  /// its started or finished games, and the `starts_at` of any source round
  /// that holds this match alone ([ownRoundStartsById], keyed by source round
  /// id). Bulk-imported finished games carry only their game day (midnight),
  /// so a round of its own is the one precise time two matches of one day
  /// can be told apart by (Women's Speed Chess Championship). Null for a
  /// match whose games are all unplayed shells, which never borrow a
  /// scheduled start.
  static DateTime? matchPlayRecency(
    Iterable<GamesTourModel> games, {
    Map<String, DateTime?> ownRoundStartsById = const <String, DateTime?>{},
  }) {
    DateTime? latest;
    void consider(DateTime? candidate) {
      if (candidate == null) return;
      final current = latest;
      if (current == null || candidate.isAfter(current)) latest = candidate;
    }

    var played = false;
    for (final game in games) {
      if (!game.effectiveGameStatus.isFinished &&
          !matchPlayGameHasMoves(game)) {
        continue;
      }
      played = true;
      consider(game.lastMoveTime);
    }
    if (!played) return null;
    for (final game in games) {
      consider(ownRoundStartsById[game.roundId]);
    }
    return latest;
  }

  /// Match order for a match-play stage: matches with a game in play first,
  /// in bracket order (two matches played at once must not swap places on
  /// every move); then matches that have been played, most recent activity
  /// first; then matches not started yet in bracket order. Bracket order is
  /// the board of the match's first game, then the scheduled start of a
  /// round of its own, then the match key. Values must be chronological
  /// match game lists.
  ///
  /// [matchPlayKeys] names the match-play matches when a stage mixes them
  /// with legacy ones (null: every match). A legacy match keeps its legacy
  /// reading: any unfinished board makes it live, and [legacyRecency] dates
  /// it.
  static Map<String, List<GamesTourModel>> orderMatchPlayMatches(
    Map<String, List<GamesTourModel>> chronologicalMatches, {
    Map<String, DateTime?> ownRoundStartsById = const <String, DateTime?>{},
    Set<String>? matchPlayKeys,
    DateTime? Function(List<GamesTourModel> games)? legacyRecency,
  }) {
    if (chronologicalMatches.length <= 1) return chronologicalMatches;
    final keys = chronologicalMatches.keys.toList();
    final tierByKey = <String, int>{};
    final recency = <String, DateTime?>{};
    final bracketBoard = <String, int>{};
    final scheduledAt = <String, DateTime?>{};
    for (final key in keys) {
      final games = chronologicalMatches[key]!;
      final isMatchPlay = matchPlayKeys?.contains(key) ?? true;
      if (isMatchPlay) {
        tierByKey[key] =
            games.any(isMatchPlayGameLive)
                ? 0
                : games.any(
                  (game) =>
                      game.effectiveGameStatus.isFinished ||
                      matchPlayGameHasMoves(game),
                )
                ? 1
                : 2;
        recency[key] = matchPlayRecency(
          games,
          ownRoundStartsById: ownRoundStartsById,
        );
      } else {
        tierByKey[key] =
            games.any((game) => !game.effectiveGameStatus.isFinished) ? 0 : 1;
        recency[key] = legacyRecency?.call(games);
      }
      bracketBoard[key] =
          games.isEmpty ? _noBoard : (games.first.boardNr ?? _noBoard);
      DateTime? scheduled;
      for (final game in games) {
        final start = ownRoundStartsById[game.roundId];
        if (start != null && (scheduled == null || start.isBefore(scheduled))) {
          scheduled = start;
        }
      }
      scheduledAt[key] = scheduled;
    }
    int byBracket(String a, String b) {
      final byBoard = bracketBoard[a]!.compareTo(bracketBoard[b]!);
      if (byBoard != 0) return byBoard;
      final aScheduled = scheduledAt[a];
      final bScheduled = scheduledAt[b];
      if (aScheduled != null && bScheduled != null) {
        final byScheduled = aScheduled.compareTo(bScheduled);
        if (byScheduled != 0) return byScheduled;
      } else if (aScheduled != null) {
        return -1;
      } else if (bScheduled != null) {
        return 1;
      }
      return a.compareTo(b);
    }

    keys.sort((a, b) {
      final aTier = tierByKey[a]!;
      final bTier = tierByKey[b]!;
      if (aTier != bTier) return aTier.compareTo(bTier);
      if (aTier == 1) {
        final aTime = recency[a];
        final bTime = recency[b];
        if (aTime != null && bTime != null) {
          final byTime = bTime.compareTo(aTime);
          if (byTime != 0) return byTime;
        } else if (aTime != null) {
          return -1;
        } else if (bTime != null) {
          return 1;
        }
      }
      return byBracket(a, b);
    });
    return <String, List<GamesTourModel>>{
      for (final key in keys) key: chronologicalMatches[key]!,
    };
  }

  static const int _noBoard = 0x7fffffff;

  static int _compareBoardThenId(GamesTourModel a, GamesTourModel b) {
    final byBoard = (a.boardNr ?? _noBoard).compareTo(b.boardNr ?? _noBoard);
    return byBoard != 0 ? byBoard : a.gameId.compareTo(b.gameId);
  }

  /// Whether one source round holds two or more games that are all the same
  /// pairing, i.e. an open-ended head-to-head that keeps appending games.
  ///
  /// Dubov vs BulletGrandpa (2026-11-07) put all 100 games into one round,
  /// board 1..100 in play order; "play until someone leads by two" matches
  /// have the same shape. Such a round is not a knockout, so
  /// [hasRepeatedMatchupInSingleSourceRound] skips it and the live game sank
  /// to the bottom. A Swiss, round-robin or team round always has several
  /// pairings, so this never matches them.
  static bool isSinglePairingAppendRound(List<GamesTourModel> games) {
    if (games.length < 2) return false;
    if (games.map((game) => game.roundId).toSet().length != 1) return false;

    final matches = groupByMatches(games);
    return matches.length == 1 && matches.values.single.length == games.length;
  }

  /// Detects if this is a 1v1 match format event (e.g., "12-game Match").
  ///
  /// Returns true when the tour format string contains "match"
  /// (case-insensitive) AND there are exactly 2 unique players.
  static bool isMatchFormat(String? formatString, List<GamesTourModel> games) {
    if (formatString == null || formatString.isEmpty || games.isEmpty) {
      return false;
    }

    if (!formatString.toLowerCase().contains('match')) return false;

    final identities = _ParticipantIdentityRegistry(games);
    // Count unique players
    final players = <String>{};
    for (final game in games) {
      final whiteId = identities.idFor(game.whitePlayer);
      final blackId = identities.idFor(game.blackPlayer);
      if (whiteId == null || blackId == null) continue;
      players.add(whiteId);
      players.add(blackId);
      if (players.length > 2) return false; // early exit
    }

    return players.length == 2;
  }

  /// Detects if games follow a knockout match format
  ///
  /// A knockout match format is identified by:
  /// 1. Multiple games between the same player pairs
  /// 2. Round slugs following patterns like "game-1", "game-2", "tiebreak-*"
  /// 3. Sequential games (game-1, game-2, etc.) for same players
  static bool isKnockoutMatchFormat(List<GamesTourModel> games) {
    if (games.length < 4) return false; // Need at least 2 matches of 2 games

    // Check for game-N pattern in round slugs
    final gamePatternCount =
        games.where((g) {
          final slug = g.roundSlug?.toLowerCase() ?? '';
          return RegExp(r'game-\d+').hasMatch(slug);
        }).length;

    // Check for tiebreak pattern
    final tiebreakPatternCount =
        games.where((g) {
          final slug = g.roundSlug?.toLowerCase() ?? '';
          return slug.contains('tiebreak');
        }).length;

    // If more than 30% of games follow these patterns, likely a knockout format
    final patternRatio =
        (gamePatternCount + tiebreakPatternCount) / games.length;
    if (patternRatio < 0.3) return false;

    // Check for repeated player matchups
    final matchups = <String, int>{};
    final identities = _ParticipantIdentityRegistry(games);
    for (final game in games) {
      final key = _getMatchupKey(
        game.whitePlayer,
        game.blackPlayer,
        identities,
      );
      if (key == null) continue;
      matchups[key] = (matchups[key] ?? 0) + 1;
    }

    // A single unique matchup means a 1v1 match (e.g., World Championship,
    // Gurel vs Van Foreest), NOT a knockout bracket. Knockouts require
    // multiple distinct matchups (e.g., Player A vs B, Player C vs D).
    if (matchups.length <= 1) return false;

    // Count matchups with 2+ games (actual matches)
    final multiGameMatchups =
        matchups.values.where((count) => count >= 2).length;
    final matchupRatio = multiGameMatchups / matchups.length;

    // If more than 50% of matchups have multiple games, it's a knockout format
    return matchupRatio > 0.5;
  }

  /// Groups games by matches (same player pairs) within the SAME round
  /// This ensures matches from different rounds (e.g., Round 1 vs Round 2) are separate
  /// Returns a map of match key -> list of games in that match
  static Map<String, List<GamesTourModel>> groupByMatches(
    List<GamesTourModel> games,
  ) {
    final matches = <String, List<GamesTourModel>>{};
    final identities = _ParticipantIdentityRegistry(games);

    for (final game in games) {
      final key = _getMatchupKey(
        game.whitePlayer,
        game.blackPlayer,
        identities,
      );
      if (key == null) continue;
      matches.putIfAbsent(key, () => []).add(game);
    }

    // Sort games within each match by round slug (game-1, game-2, tiebreak-1, etc.)
    for (final matchGames in matches.values) {
      matchGames.sort((a, b) => _compareRoundSlugs(a.roundSlug, b.roundSlug));
    }

    return matches;
  }

  /// Groups games by MATCHES first (same player pairs across ALL rounds/games)
  /// This is the correct structure for knockout tournaments where:
  /// - Adams vs Alrehaili play Game 1 (round_id: t8DzIZPc)
  /// - Same match Game 2 (round_id: NUcmLDqC)
  /// - Same match Tiebreaks (round_id: xyz)
  /// Returns a map of match key -> all games in that match (across all rounds)
  static Map<String, List<GamesTourModel>> groupByMatchesAcrossAllRounds(
    List<GamesTourModel> allGames,
  ) {
    final matches = <String, List<GamesTourModel>>{};
    final identities = _ParticipantIdentityRegistry(allGames);

    for (final game in allGames) {
      final key = _getMatchupKey(
        game.whitePlayer,
        game.blackPlayer,
        identities,
      );
      if (key == null) continue;
      matches.putIfAbsent(key, () => []).add(game);
    }

    // Sort games within each match by round slug (game-1, game-2, tiebreak-1, etc.)
    for (final matchGames in matches.values) {
      matchGames.sort((a, b) => _compareRoundSlugs(a.roundSlug, b.roundSlug));
    }

    return matches;
  }

  /// Display order for one matchup's boards: boards still being played
  /// first, then latest-played first. Board numbers do not exist in a
  /// knockout — the same two players meet again and again — and on
  /// matchup-labeled feeds every game shares one round slug, so the
  /// chronological slug sort ties everywhere and Dart's unstable sort
  /// strands the live board among finished ones. Live boards outrank
  /// everything (a long think must not let a just-finished board leapfrog
  /// the game in progress); finished boards follow by actual play time,
  /// with the chronological slug order reversed as the undated fallback,
  /// descending append board number when source metadata ties, and gameId
  /// keeping the order total.
  static List<GamesTourModel> orderMatchGamesLatestFirst(
    List<GamesTourModel> games,
  ) {
    if (games.length < 2) return games;
    // effectiveGameStatus parses the FEN for clock-flagged boards; resolve it
    // once per game instead of once per comparison.
    final sortKeyByGameId = <String, ({bool isLive, DateTime? playedAt})>{
      for (final game in games)
        game.gameId: (
          isLive: !game.effectiveGameStatus.isFinished,
          playedAt: game.lastMoveTime ?? game.bucketDate,
        ),
    };
    return games.toList()..sort((a, b) {
      final aKey = sortKeyByGameId[a.gameId]!;
      final bKey = sortKeyByGameId[b.gameId]!;
      if (aKey.isLive != bKey.isLive) return aKey.isLive ? -1 : 1;
      final aPlayedAt = aKey.playedAt;
      final bPlayedAt = bKey.playedAt;
      if (aPlayedAt != null && bPlayedAt != null) {
        final byPlayedAt = bPlayedAt.compareTo(aPlayedAt);
        if (byPlayedAt != 0) return byPlayedAt;
      } else if (aPlayedAt != null) {
        return -1;
      } else if (bPlayedAt != null) {
        return 1;
      }
      final bySlug = _compareRoundSlugs(b.roundSlug, a.roundSlug);
      if (bySlug != 0) return bySlug;
      // Some live-PGN feeds stamp every game in a round with the same sync
      // time and round slug. In those feeds board_nr is the only authoritative
      // append sequence: a higher number is a newer decider.
      final aBoard = a.boardNr;
      final bBoard = b.boardNr;
      if (aBoard != null && bBoard != null) {
        final byBoard = bBoard.compareTo(aBoard);
        if (byBoard != 0) return byBoard;
      } else if (aBoard != null) {
        return -1;
      } else if (bBoard != null) {
        return 1;
      }
      return a.gameId.compareTo(b.gameId);
    });
  }

  /// Extracts the tournament round name from tour name
  /// Examples:
  /// - "FIDE World Cup 2025 | Quarterfinals" → "Quarterfinals"
  /// - "Tournament Name | Round 1" → "Round 1"
  /// - "Tournament Name | Semifinals" → "Semifinals"
  /// - "Tournament Name" → "Round 1" (default if no separator found)
  static String extractTournamentRoundName(String tourName) {
    // Look for pipe separator
    if (tourName.contains('|')) {
      final parts = tourName.split('|');
      if (parts.length >= 2) {
        // Return the part after the last pipe, trimmed
        return parts.last.trim();
      }
    }

    // Check if the tour name itself contains round indicators
    final roundMatch = RegExp(
      r'round\s+(\d+)',
      caseSensitive: false,
    ).firstMatch(tourName);
    if (roundMatch != null) {
      return 'Round ${roundMatch.group(1)}';
    }

    // Check for common stage names in the tour name
    final lowerName = tourName.toLowerCase();
    if (lowerName.contains('final') && !lowerName.contains('semifinal')) {
      return 'Finals';
    } else if (lowerName.contains('semifinal')) {
      return 'Semifinals';
    } else if (lowerName.contains('quarterfinal')) {
      return 'Quarterfinals';
    }

    // Default fallback
    return 'Round 1';
  }

  /// Determines the actual tournament round/stage for a match
  /// (e.g., "Round 1", "Quarterfinals", "Semifinals", "Finals")
  /// Currently extracts from roundId, but could be enhanced to detect stage from number of players
  static String getTournamentStage(List<GamesTourModel> matchGames) {
    if (matchGames.isEmpty) return 'Unknown';

    // Try to extract round number from first game's roundId
    final firstGame = matchGames.first;
    final roundId = firstGame.roundId;

    // Check if there's a round number in the roundId
    final match = RegExp(
      r'round[\s-]*(\d+)',
      caseSensitive: false,
    ).firstMatch(roundId);
    if (match != null) {
      return 'Round ${match.group(1)}';
    }

    // Default: return "Round 1" for simplicity
    return 'Round 1';
  }

  /// Creates a match header model for displaying match information
  static MatchHeaderModel createMatchHeader(
    String matchKey,
    List<GamesTourModel> matchGames, {
    DateTime? playedAt,
    Map<String, List<TournamentPlayer>> sourceStandingsByTourId = const {},
    bool isMatchPlay = false,
  }) {
    if (matchGames.isEmpty) {
      throw ArgumentError('Match must have at least one game');
    }

    final firstGame = matchGames.first;
    final player1 = firstGame.whitePlayer.name;
    final player2 = firstGame.blackPlayer.name;

    // Calculate match score
    var score = _calculateMatchScore(matchGames);
    final matchTourIds = matchGames.map((game) => game.tourId).toSet();
    final sourceStandings =
        matchTourIds.length == 1
            ? sourceStandingsByTourId[matchTourIds.single]
            : null;
    if (sourceStandings != null && sourceStandings.isNotEmpty) {
      final officialScore = resolveOfficialMatchScoreFromStandings(
        standings: sourceStandings,
        firstName: player1,
        firstFideId: firstGame.whitePlayer.fideId,
        secondName: player2,
        secondFideId: firstGame.blackPlayer.fideId,
        completedGames:
            matchGames
                .where((game) => game.effectiveGameStatus.isFinished)
                .length,
      );
      if (officialScore != null) {
        score = (
          player1Score: officialScore.first,
          player2Score: officialScore.second,
        );
      }
    }

    // Extract base round name (e.g., "Round 1" from "game-1")
    final roundName = _extractBaseRoundName(matchGames);

    return MatchHeaderModel(
      matchKey: matchKey,
      player1: player1,
      player2: player2,
      player1Score: score.player1Score,
      player2Score: score.player2Score,
      games: matchGames,
      roundName: roundName,
      isComplete: _isMatchComplete(matchGames),
      playedAt: playedAt,
      isMatchPlay: isMatchPlay,
    );
  }

  /// Formats round slug for display
  /// Examples:
  /// - "game-1" -> "Game 1"
  /// - "game-2" -> "Game 2"
  /// - "tiebreak-1-rapid-1" -> "Tiebreak 1 - Rapid 1"
  /// - "tiebreak-2-blitz-1" -> "Tiebreak 2 - Blitz 1"
  static String formatRoundSlug(String? slug) {
    if (slug == null || slug.isEmpty) return '';

    final lower = slug.toLowerCase();

    // Handle standard game format
    if (lower.startsWith('game-')) {
      final num = lower.replaceAll('game-', '');
      return 'Game $num';
    }

    // Handle tiebreak formats
    if (lower.contains('tiebreak')) {
      // Extract tiebreak number and type
      final tiebreakMatch = RegExp(r'tiebreak-(\d+)').firstMatch(lower);
      final rapidMatch = RegExp(r'rapid-(\d+)').firstMatch(lower);
      final blitzMatch = RegExp(r'blitz-(\d+)').firstMatch(lower);
      final armageddonMatch = RegExp(r'armageddon').hasMatch(lower);

      final parts = <String>[];

      if (tiebreakMatch != null) {
        final tbNum = tiebreakMatch.group(1);
        parts.add('Tiebreak $tbNum');
      } else {
        parts.add('Tiebreak');
      }

      if (rapidMatch != null) {
        parts.add('Rapid ${rapidMatch.group(1)}');
      } else if (blitzMatch != null) {
        parts.add('Blitz ${blitzMatch.group(1)}');
      } else if (armageddonMatch) {
        parts.add('Armageddon');
      }

      return parts.join(' - ');
    }

    // Fallback: capitalize first letter of each word
    return slug
        .split(RegExp(r'[-_\s]'))
        .where((s) => s.isNotEmpty)
        .map((s) => s[0].toUpperCase() + s.substring(1))
        .join(' ');
  }

  /// Groups matches by their base round (e.g., all "game-1" matches together)
  static Map<String, List<MatchHeaderModel>> groupMatchesByRound(
    List<MatchHeaderModel> matches,
  ) {
    final grouped = <String, List<MatchHeaderModel>>{};

    for (final match in matches) {
      grouped.putIfAbsent(match.roundName, () => []).add(match);
    }

    return grouped;
  }

  // Private helper methods

  static String? _getMatchupKey(
    PlayerCard player1,
    PlayerCard player2,
    _ParticipantIdentityRegistry identities,
  ) {
    final player1Id = identities.idFor(player1);
    final player2Id = identities.idFor(player2);
    if (player1Id == null || player2Id == null) return null;
    final sorted = [player1Id, player2Id]..sort();
    return '${sorted[0]}|${sorted[1]}';
  }

  static int _compareRoundSlugs(String? a, String? b) {
    if (a == null && b == null) return 0;
    if (a == null) return 1;
    if (b == null) return -1;

    // Extract numbers and types for sorting
    final aInfo = _parseRoundSlugInfo(a);
    final bInfo = _parseRoundSlugInfo(b);

    // First compare by type priority (game < tiebreak)
    if (aInfo.typePriority != bInfo.typePriority) {
      return aInfo.typePriority.compareTo(bInfo.typePriority);
    }

    // Then compare by main number
    if (aInfo.mainNumber != bInfo.mainNumber) {
      return aInfo.mainNumber.compareTo(bInfo.mainNumber);
    }

    // Then compare by sub number
    return aInfo.subNumber.compareTo(bInfo.subNumber);
  }

  static _RoundSlugInfo _parseRoundSlugInfo(String slug) {
    final lower = slug.toLowerCase();

    // Check if it's a regular game
    if (lower.startsWith('game-')) {
      final num = int.tryParse(lower.replaceAll('game-', '')) ?? 0;
      return _RoundSlugInfo(typePriority: 0, mainNumber: num, subNumber: 0);
    }

    // Check if it's a tiebreak
    if (lower.contains('tiebreak')) {
      final tiebreakMatch = RegExp(r'tiebreak-(\d+)').firstMatch(lower);
      final rapidMatch = RegExp(r'rapid-(\d+)').firstMatch(lower);
      final blitzMatch = RegExp(r'blitz-(\d+)').firstMatch(lower);

      final tiebreakNum = int.tryParse(tiebreakMatch?.group(1) ?? '1') ?? 1;
      final subNum =
          int.tryParse(rapidMatch?.group(1) ?? blitzMatch?.group(1) ?? '1') ??
          1;

      // Priority: 10 for rapid, 20 for blitz, 30 for armageddon
      int typePriority = 10;
      if (blitzMatch != null) typePriority = 20;
      if (lower.contains('armageddon')) typePriority = 30;

      return _RoundSlugInfo(
        typePriority: typePriority + tiebreakNum,
        mainNumber: tiebreakNum,
        subNumber: subNum,
      );
    }

    // Fallback
    return _RoundSlugInfo(typePriority: 999, mainNumber: 0, subNumber: 0);
  }

  static ({double player1Score, double player2Score}) _calculateMatchScore(
    List<GamesTourModel> games,
  ) {
    double player1Score = 0.0;
    double player2Score = 0.0;

    if (games.isEmpty) return (player1Score: 0.0, player2Score: 0.0);

    // Use first game to determine which player is player1 and player2
    final identities = _ParticipantIdentityRegistry(games);
    final player1Id = identities.idFor(games.first.whitePlayer);

    for (final game in games) {
      final status = game.effectiveGameStatus;
      final isPlayer1White = identities.idFor(game.whitePlayer) == player1Id;
      double standardWhitePoints;
      double standardBlackPoints;
      switch (status) {
        case GameStatus.whiteWins:
          standardWhitePoints = 1;
          standardBlackPoints = 0;
          break;
        case GameStatus.blackWins:
          standardWhitePoints = 0;
          standardBlackPoints = 1;
          break;
        case GameStatus.draw:
          standardWhitePoints = 0.5;
          standardBlackPoints = 0.5;
          break;
        default:
          continue;
      }
      final points = aggregateBroadcastResultPoints(
        standardWhitePoints: standardWhitePoints,
        standardBlackPoints: standardBlackPoints,
        whiteCustomPoints: game.whitePlayer.customPoints,
        blackCustomPoints: game.blackPlayer.customPoints,
      );
      if (isPlayer1White) {
        player1Score += points.white;
        player2Score += points.black;
      } else {
        player1Score += points.black;
        player2Score += points.white;
      }
    }

    return (player1Score: player1Score, player2Score: player2Score);
  }

  static String _extractBaseRoundName(List<GamesTourModel> games) {
    if (games.isEmpty) return 'Round';

    // Try to find the base round from the first game's round slug
    final firstSlug = games.first.roundSlug?.toLowerCase() ?? '';

    // If it's a "game-N" pattern, extract the round number
    if (firstSlug.startsWith('game-')) {
      return 'Round 1'; // All games in same knockout round are "Round 1"
    }

    // For tournaments with actual round numbers in roundId
    final roundId = games.first.roundId;
    final match = RegExp(
      r'round[\s-]*(\d+)',
      caseSensitive: false,
    ).firstMatch(roundId);
    if (match != null) {
      return 'Round ${match.group(1)}';
    }

    return 'Round 1';
  }

  static bool _isMatchComplete(List<GamesTourModel> games) {
    // A match is complete if all games are finished
    return games.every((g) => g.effectiveGameStatus.isFinished);
  }
}

typedef _GameIndex = ({int stage, int set, int game});

class _ParticipantIdentityRegistry {
  _ParticipantIdentityRegistry(Iterable<GamesTourModel> games) {
    final fideIdsByName = <String, Set<int>>{};
    for (final game in games) {
      for (final player in [game.whitePlayer, game.blackPlayer]) {
        final name = _normalizedPlayerName(player.name);
        final fideId = player.fideId;
        if (name.isEmpty || fideId == null || fideId <= 0) continue;
        fideIdsByName.putIfAbsent(name, () => <int>{}).add(fideId);
      }
    }
    for (final entry in fideIdsByName.entries) {
      if (entry.value.length == 1) {
        _fideIdByName[entry.key] = entry.value.single;
      }
    }
  }

  final Map<String, int> _fideIdByName = <String, int>{};

  String? idFor(PlayerCard player) {
    final name = _normalizedPlayerName(player.name);
    if (_isPlaceholderPlayerName(name)) return null;
    final fideId =
        (player.fideId != null && player.fideId! > 0)
            ? player.fideId
            : _fideIdByName[name];
    return fideId == null ? 'name:$name' : 'fide:$fideId';
  }
}

bool _isPlaceholderPlayerName(String name) {
  final normalized =
      name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9?]+'), ' ').trim();
  return normalized.isEmpty ||
      normalized == '?' ||
      normalized == 'tbd' ||
      normalized == 'tba' ||
      normalized == 'unknown' ||
      normalized == 'unknown player' ||
      normalized == 'to be determined' ||
      normalized.startsWith('winner of ') ||
      normalized.startsWith('loser of ');
}

String _normalizedPlayerName(String name) =>
    name
        .trim()
        .replaceFirst(
          RegExp(
            r'^(?:(?:GM|IM|FM|CM|WGM|WIM|WFM|WCM|NM|WNM)\.?\s+)+',
            caseSensitive: false,
          ),
          '',
        )
        .toLowerCase()
        .replaceAll('’', "'")
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

/// Information parsed from a round slug for sorting
class _RoundSlugInfo {
  final int typePriority;
  final int mainNumber;
  final int subNumber;

  _RoundSlugInfo({
    required this.typePriority,
    required this.mainNumber,
    required this.subNumber,
  });
}

/// Model representing a match header with player information and score
class MatchHeaderModel {
  final String matchKey;
  final String player1;
  final String player2;
  final double player1Score;
  final double player2Score;
  final List<GamesTourModel> games;
  final String roundName;
  final bool isComplete;

  /// When this matchup was (or is scheduled to be) played — the same recency
  /// signal the collapsed-stage ordering sorts by, surfaced so the card makes
  /// the latest-first order verifiable at a glance.
  final DateTime? playedAt;

  /// Built for a match-play round ([KnockoutMatchDetector.isMatchPlayRound]):
  /// [player1] is side A and a 0-move shell never makes the match live.
  final bool isMatchPlay;

  const MatchHeaderModel({
    required this.matchKey,
    required this.player1,
    required this.player2,
    required this.player1Score,
    required this.player2Score,
    required this.games,
    required this.roundName,
    required this.isComplete,
    this.playedAt,
    this.isMatchPlay = false,
  });

  /// Whether the match is being played now. Outside match play any unfinished
  /// board counts, as before; in match play only a game that has a move.
  bool get hasLiveGame =>
      isMatchPlay
          ? games.any(KnockoutMatchDetector.isMatchPlayGameLive)
          : games.any((game) => !game.effectiveGameStatus.isFinished);

  String get matchTitle => '$player1 vs $player2';

  String get scoreDisplay => '$player1Score - $player2Score';

  String get fullTitle => '$roundName: $matchTitle';
}
