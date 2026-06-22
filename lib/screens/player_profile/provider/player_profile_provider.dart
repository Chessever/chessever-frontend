import 'dart:async';

import 'package:chessever2/repository/gamebase/gamebase_repository.dart';
import 'package:chessever2/repository/gamebase/search/gamebase_search_models_extra.dart';
import 'package:chessever2/repository/supabase/chess_player/chess_player_repository.dart';
import 'package:chessever2/repository/supabase/game/game_repository.dart';
import 'package:chessever2/repository/supabase/game/games.dart' show Games;
import 'package:chessever2/screens/gamebase/models/models.dart'
    show GamebasePlayer;
import 'package:dio/dio.dart';
import 'package:chessever2/screens/group_event/model/tour_event_card_model.dart';
import 'package:chessever2/screens/library/utils/gamebase_pgn_builder.dart';
import 'package:chessever2/screens/player_profile/player_profile_data_source.dart';
import 'package:chessever2/screens/player_profile/utils/twic_event_identity.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/utils/chess_title_utils.dart';
import 'package:chessever2/utils/time_utils.dart';
import 'package:chessever2/widgets/game_filter/game_filter_model.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:chessever2/utils/twic_player_enrichment.dart';

final playerGamesSelectionModeProvider =
    StateProvider.family<bool, PlayerProfileKey>((ref, key) => false);

/// Key to identify a player - can use either fideId OR playerName
/// This allows viewing player profiles even without a FIDE ID
class PlayerProfileKey {
  final int? fideId;
  final String playerName;
  final PlayerProfileDataSource source;
  final String? gamebasePlayerId;

  const PlayerProfileKey({
    this.fideId,
    required this.playerName,
    this.source = PlayerProfileDataSource.supabase,
    this.gamebasePlayerId,
  });

  /// Whether this player has a valid FIDE ID
  bool get hasFideId => fideId != null && fideId! > 0;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PlayerProfileKey &&
          fideId == other.fideId &&
          playerName == other.playerName &&
          source == other.source &&
          gamebasePlayerId == other.gamebasePlayerId;

  @override
  int get hashCode =>
      fideId.hashCode ^
      playerName.hashCode ^
      source.hashCode ^
      gamebasePlayerId.hashCode;

  @override
  String toString() =>
      'PlayerProfileKey(fideId: $fideId, name: $playerName, source: $source, gamebasePlayerId: $gamebasePlayerId)';
}

/// Model for comprehensive player profile data
class PlayerProfileData {
  const PlayerProfileData({
    required this.fideId,
    required this.name,
    this.title,
    this.federation,
    this.classicalRating,
    this.rapidRating,
    this.blitzRating,
    this.classicalGames,
    this.rapidGames,
    this.blitzGames,
    this.birthday,
    this.sex,
    this.openingStats = const [],
    this.colorStats,
    this.resultStats,
    this.recentPerformance,
  });

  final int fideId;
  final String name;
  final String? title;
  final String? federation;
  final int? classicalRating;
  final int? rapidRating;
  final int? blitzRating;
  final int? classicalGames;
  final int? rapidGames;
  final int? blitzGames;
  final String? birthday;
  final String? sex;
  final List<OpeningStatistic> openingStats;
  final ColorStatistics? colorStats;
  final ResultStatistics? resultStats;
  final RecentPerformance? recentPerformance;
}

/// Opening statistics for a player
class OpeningStatistic {
  const OpeningStatistic({
    required this.eco,
    this.openingName,
    required this.count,
    required this.wins,
    required this.draws,
    required this.losses,
  });

  final String eco;
  final String? openingName;
  final int count;
  final int wins;
  final int draws;
  final int losses;

  double get winRate => count > 0 ? wins / count : 0.0;
  double get score => count > 0 ? (wins + draws * 0.5) / count : 0.0;
}

/// Statistics for playing as white vs black
class ColorStatistics {
  const ColorStatistics({
    required this.whiteGames,
    required this.whiteWins,
    required this.whiteDraws,
    required this.whiteLosses,
    required this.blackGames,
    required this.blackWins,
    required this.blackDraws,
    required this.blackLosses,
  });

  final int whiteGames;
  final int whiteWins;
  final int whiteDraws;
  final int whiteLosses;
  final int blackGames;
  final int blackWins;
  final int blackDraws;
  final int blackLosses;

  double get whiteScore =>
      whiteGames > 0 ? (whiteWins + whiteDraws * 0.5) / whiteGames : 0.0;
  double get blackScore =>
      blackGames > 0 ? (blackWins + blackDraws * 0.5) / blackGames : 0.0;
}

/// Overall result statistics
class ResultStatistics {
  const ResultStatistics({
    required this.totalGames,
    required this.wins,
    required this.draws,
    required this.losses,
  });

  final int totalGames;
  final int wins;
  final int draws;
  final int losses;

  double get winRate => totalGames > 0 ? wins / totalGames : 0.0;
  double get drawRate => totalGames > 0 ? draws / totalGames : 0.0;
  double get lossRate => totalGames > 0 ? losses / totalGames : 0.0;
  double get score => totalGames > 0 ? (wins + draws * 0.5) / totalGames : 0.0;
}

/// Recent performance metrics
class RecentPerformance {
  const RecentPerformance({
    required this.performanceRating,
    required this.ratingChange,
    required this.form,
  });

  final int performanceRating;
  final int ratingChange;
  final List<double> form; // Last N game results (1.0, 0.5, 0.0)
}

/// Event/tournament data for a player
class PlayerEventData {
  const PlayerEventData({
    required this.tourId,
    required this.tourName,
    this.tourSlug,
    required this.gamesPlayed,
    this.score,
    this.startDate,
    this.endDate,
    this.site,
    this.dominantTimeControl,
    this.avgElo,
    this.maxElo,
  });

  final String tourId;
  final String tourName;
  final String? tourSlug;
  final int gamesPlayed;
  final double? score;
  final DateTime? startDate;
  final DateTime? endDate;
  final String? site;
  final String? dominantTimeControl;
  final int? avgElo;
  final int? maxElo;
}

/// Provider to fetch basic player profile from chess_players table
final playerProfileDataProvider = FutureProvider.family
    .autoDispose<PlayerProfileData?, int>((ref, fideId) async {
      try {
        final supabase = Supabase.instance.client;

        // Fetch from chess_players table
        final response =
            await supabase
                .from('chess_players')
                .select()
                .eq('fideid', fideId)
                .maybeSingle();

        if (response == null) return null;

        // Handle birthday as int (year) and convert to string
        final birthdayInt = response['birthday'] as int?;
        final birthdayStr = birthdayInt?.toString();

        return PlayerProfileData(
          fideId: fideId,
          name: response['name'] as String? ?? 'Unknown',
          title: response['title'] as String?,
          federation: response['country']?.toString().trim(),
          classicalRating: response['rating'] as int?,
          rapidRating: response['rapid_rating'] as int?,
          blitzRating: response['blitz_rating'] as int?,
          classicalGames: response['games'] as int?,
          rapidGames: response['rapid_games'] as int?,
          blitzGames: response['blitz_games'] as int?,
          birthday: birthdayStr,
          sex: response['sex']?.toString().trim(),
        );
      } catch (e) {
        debugPrint('[playerProfileDataProvider] Error: $e');
        return null;
      }
    });

/// Provider to fetch all games for a player by FIDE ID
final playerGamesDataProvider = FutureProvider.family
    .autoDispose<List<GamesTourModel>, int>((ref, fideId) async {
      try {
        final gameRepo = ref.read(gameRepositoryProvider);
        final games = await gameRepo.getGamesByFideId(
          fideId.toString(),
          limit: 500,
        );

        final allGames =
            games
                .map((game) => GamesTourModel.fromGame(game))
                .where((game) => !_isVariantEvent(game.tourSlug))
                .toList();

        // Sort by date descending
        final epochFallback = DateTime.fromMillisecondsSinceEpoch(0);
        allGames.sort((a, b) {
          final aTime = a.lastMoveTime ?? epochFallback;
          final bTime = b.lastMoveTime ?? epochFallback;
          return bTime.compareTo(aTime);
        });

        return allGames;
      } catch (e) {
        debugPrint('[playerGamesDataProvider] Error: $e');
        return [];
      }
    });

/// Slug patterns for non-standard chess variants (Fischer Random, etc.)
/// These events are excluded from player profile stats and game lists.
const _variantSlugPatterns = [
  'freestyle',
  'chess960',
  'fischer-random',
  'king-of-the-hill',
  '3check',
  'three-check',
  'antichess',
  'atomic',
  'crazyhouse',
  'horde',
  'racing-kings',
  'bughouse',
];

/// Check if a tour slug belongs to a non-standard chess variant
bool _isVariantEvent(String? tourSlug) {
  if (tourSlug == null || tourSlug.isEmpty) return false;
  final lower = tourSlug.toLowerCase();
  return _variantSlugPatterns.any((p) => lower.contains(p));
}

/// Provider to fetch games for a player using PlayerProfileKey (supports both fideId and name lookup)
final playerGamesDataKeyProvider = FutureProvider.family
    .autoDispose<List<GamesTourModel>, PlayerProfileKey>((
      ref,
      playerKey,
    ) async {
      try {
        if (playerKey.source == PlayerProfileDataSource.twic) {
          final pid = playerKey.gamebasePlayerId?.trim();
          if (pid != null && pid.isNotEmpty) {
            try {
              return _getTwicGamesViaPlayerEndpoint(ref, pid);
            } on DioException catch (e) {
              if (e.response?.statusCode != 404) rethrow;
            }
          }
          return _getTwicGamesFromGamebase(ref, playerKey);
        }

        final gameRepo = ref.read(gameRepositoryProvider);
        List<Games> games;

        if (playerKey.hasFideId) {
          games = await gameRepo.getGamesByFideId(
            playerKey.fideId.toString(),
            limit: 500,
          );
        } else {
          games = await gameRepo.getGamesByPlayerName(
            playerKey.playerName,
            limit: 500,
          );
        }

        final allGames =
            games
                .map((game) => GamesTourModel.fromGame(game))
                .where((game) => !_isVariantEvent(game.tourSlug))
                .toList();

        // Sort by date descending
        final epochFallback = DateTime.fromMillisecondsSinceEpoch(0);
        allGames.sort((a, b) {
          final aTime = a.lastMoveTime ?? epochFallback;
          final bTime = b.lastMoveTime ?? epochFallback;
          return bTime.compareTo(aTime);
        });

        return allGames;
      } catch (e) {
        debugPrint('[playerGamesDataKeyProvider] Error: $e');
        return [];
      }
    });

String _normalizeGamebaseName(String name) {
  return name
      .toLowerCase()
      .replaceAll(',', ' ')
      .replaceAll('.', ' ')
      .replaceAll('-', ' ')
      .split(' ')
      .where((s) => s.isNotEmpty)
      .join(' ')
      .trim();
}

bool _gamebaseNameMatches(String candidate, String target) {
  final a = _normalizeGamebaseName(candidate);
  final b = _normalizeGamebaseName(target);
  if (a.isEmpty || b.isEmpty) return false;
  return a.contains(b) || b.contains(a);
}

int _twicPlayerMatchScore(
  GamebasePlayer candidate,
  PlayerProfileKey playerKey,
) {
  var score = 0;
  final candidateFide = candidate.fideId.trim();
  if (playerKey.hasFideId && candidateFide == playerKey.fideId.toString()) {
    score += 1000;
  }

  final candidateName = _normalizeGamebaseName(candidate.name);
  final targetName = _normalizeGamebaseName(playerKey.playerName);
  if (candidateName.isNotEmpty && targetName.isNotEmpty) {
    if (candidateName == targetName) {
      score += 200;
    } else if (candidateName.contains(targetName) ||
        targetName.contains(candidateName)) {
      score += 50;
    }
  }

  final candidateTitle = (candidate.title ?? '').trim();
  if (candidateTitle.isNotEmpty) score += 5;
  final highestRating = candidate.highestRating ?? 0;
  score += highestRating.clamp(0, 4000) ~/ 100;
  return score;
}

@visibleForTesting
GamebasePlayer? pickBestTwicPlayerMatchForProfile(
  List<GamebasePlayer> players,
  PlayerProfileKey playerKey,
) {
  if (players.isEmpty) return null;

  final ranked = [...players]..sort((a, b) {
    final byScore = _twicPlayerMatchScore(
      b,
      playerKey,
    ).compareTo(_twicPlayerMatchScore(a, playerKey));
    if (byScore != 0) return byScore;
    final byRating = (b.highestRating ?? 0).compareTo(a.highestRating ?? 0);
    if (byRating != 0) return byRating;
    return a.name.compareTo(b.name);
  });

  final best = ranked.first;
  if (_twicPlayerMatchScore(best, playerKey) <= 0) return null;
  return best;
}

bool _gamebasePlayerMatchesKey(
  GamebasePlayer candidate,
  PlayerProfileKey playerKey,
) {
  if (playerKey.hasFideId &&
      candidate.fideId.trim() == playerKey.fideId.toString()) {
    return true;
  }
  return _gamebaseNameMatches(candidate.name, playerKey.playerName);
}

@visibleForTesting
int? extractTwicPlayerGamesTotalCount(Map<String, dynamic> response) {
  final metadata = response['metadata'];
  if (metadata is! Map) return null;
  return (metadata['totalCount'] as num?)?.toInt();
}

class TwicProfileSummary {
  const TwicProfileSummary({
    required this.gamebasePlayerId,
    required this.totalGames,
    required this.totalEvents,
  });

  final String gamebasePlayerId;
  final int totalGames;
  final int totalEvents;
}

bool _looksLikeUuid(String? raw) {
  final value = raw?.trim();
  if (value == null || value.isEmpty) return false;
  final uuidRegex = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
  );
  return uuidRegex.hasMatch(value);
}

Future<String?> _resolveTwicPlayerId(
  Ref ref,
  PlayerProfileKey playerKey, {
  bool preferProvidedId = true,
}) async {
  final repo = ref.read(gamebaseRepositoryProvider);

  final providedId = playerKey.gamebasePlayerId?.trim();
  if (preferProvidedId && _looksLikeUuid(providedId)) {
    final providedPlayer = await repo.getPlayerById(providedId!);
    if (providedPlayer != null &&
        _gamebasePlayerMatchesKey(providedPlayer, playerKey)) {
      return providedId;
    }
  }

  if (playerKey.hasFideId) {
    final targetFideId = playerKey.fideId.toString();
    final players = await repo.getPlayers(
      fideId: targetFideId,
      pageNumber: 0,
      pageSize: 100,
    );
    final exactMatch = players
        .where((p) => p.fideId.trim() == targetFideId && _looksLikeUuid(p.id))
        .toList(growable: false);
    if (exactMatch.isNotEmpty) {
      return exactMatch.first.id.trim();
    }
  }

  final name = playerKey.playerName.trim();
  if (name.isEmpty) return null;
  final candidates = await repo.getPlayers(
    name: name,
    pageNumber: 0,
    pageSize: 100,
  );
  final match = pickBestTwicPlayerMatchForProfile(candidates, playerKey);
  final matchId = match?.id.trim();
  return _looksLikeUuid(matchId) ? matchId : null;
}

final twicPlayerIdProvider = FutureProvider.family
    .autoDispose<String?, PlayerProfileKey>((ref, playerKey) async {
      final keepAliveLink = ref.keepAlive();
      final timer = Timer(const Duration(minutes: 5), keepAliveLink.close);
      ref.onDispose(timer.cancel);
      return _resolveTwicPlayerId(ref, playerKey);
    });

final twicProfileSummaryProvider = FutureProvider.family
    .autoDispose<TwicProfileSummary?, PlayerProfileKey>((ref, playerKey) async {
      final repo = ref.read(gamebaseRepositoryProvider);

      try {
        final playerId = await ref.watch(
          twicPlayerIdProvider(playerKey).future,
        );
        if (playerId == null || playerId.isEmpty) return null;

        int? totalGames;

        try {
          final gamesResponse = await repo.getPlayerGames(
            playerId: playerId,
            pageNumber: 0,
            pageSize: 1,
          );
          totalGames = extractTwicPlayerGamesTotalCount(gamesResponse);
        } catch (_) {
          // Fall through to stats.
        }

        if (totalGames == null || totalGames <= 0) {
          final statsResponse = await repo.getPlayerStats(playerId: playerId);
          final data = statsResponse['data'];
          if (data is! Map) return null;
          final totals = Map<String, dynamic>.from(
            data['totals'] as Map? ?? const {},
          );
          totalGames = (totals['games'] as num?)?.toInt() ?? 0;
        }

        if (totalGames <= 0) return null;

        int totalEvents = 0;
        try {
          final eventsResponse = await repo.getPlayerEvents(
            playerId: playerId,
            pageNumber: 0,
            pageSize: 1,
          );
          totalEvents = eventsResponse.metadata.totalCount ?? 0;
        } catch (_) {
          // Best-effort; banner falls back to '--' when zero.
        }

        return TwicProfileSummary(
          gamebasePlayerId: playerId,
          totalGames: totalGames,
          totalEvents: totalEvents,
        );
      } catch (_) {
        return null;
      }
    });

/// Fetch TWIC games via the dedicated player-games endpoint (unfiltered).
/// Used by [playerGamesDataKeyProvider] for base analytics when
/// [gamebasePlayerId] is available — avoids the globalSearch path entirely.
Future<List<GamesTourModel>> _getTwicGamesViaPlayerEndpoint(
  Ref ref,
  String playerId,
) async {
  final repo = ref.read(gamebaseRepositoryProvider);
  final allRows = <Map<String, dynamic>>[];

  var page = 0;
  while (true) {
    final response = await repo.getPlayerGames(
      playerId: playerId,
      pageNumber: page,
      pageSize: 100,
    );

    final data = response['data'];
    if (data is List) {
      for (final item in data) {
        allRows.add(Map<String, dynamic>.from(item as Map));
      }
    }

    final metadata = response['metadata'];
    final hasMore = metadata is Map ? (metadata['hasMore'] == true) : false;
    if (!hasMore) break;
    if (data is! List || data.isEmpty) break;
    page += 1;
    if (page >= 1000) break;
  }

  var games = allRows
      .map((row) {
        final id = (row['id']?.toString().trim());
        final safeId = (id != null && id.isNotEmpty) ? id : 'unknown';
        final result = row['result']?.toString() ?? '*';
        final timeControl = row['timeControl']?.toString();
        final date =
            row['date'] != null
                ? DateTime.tryParse(row['date'].toString())
                : null;
        final eco = row['eco']?.toString();
        final opening = row['opening']?.toString();
        final variation = row['variation']?.toString();
        final event = (row['event']?.toString() ?? 'Gamebase').trim();
        final canonicalEvent = preferredTwicEventTitle(
          pgnEvent: event,
          tourSlug: row['tourSlug']?.toString(),
          tourId:
              row['tour_id']?.toString() ?? row['tournament_id']?.toString(),
          site: row['site']?.toString(),
          fallback: event.isNotEmpty ? event : 'Gamebase',
        );

        final whiteName = (row['white']?.toString() ?? 'White').trim();
        final blackName = (row['black']?.toString() ?? 'Black').trim();

        final pgn = buildHeaderOnlyPgn(
          whiteName: whiteName,
          blackName: blackName,
          result: result,
          event: canonicalEvent,
          date: date,
          eco: eco,
          opening: opening,
          variation: variation,
        );

        final whiteCard = PlayerCard(
          name: whiteName,
          federation: '',
          title: ChessTitleUtils.normalize(row['whiteTitle']?.toString() ?? ''),
          rating: (row['whiteElo'] as num?)?.toInt() ?? 0,
          countryCode: row['whiteFed']?.toString() ?? '',
          team: null,
          fideId: int.tryParse(row['whiteFideId']?.toString() ?? ''),
          gamebasePlayerId: row['whitePlayerId']?.toString().trim(),
        );

        final blackCard = PlayerCard(
          name: blackName,
          federation: '',
          title: ChessTitleUtils.normalize(row['blackTitle']?.toString() ?? ''),
          rating: (row['blackElo'] as num?)?.toInt() ?? 0,
          countryCode: row['blackFed']?.toString() ?? '',
          team: null,
          fideId: int.tryParse(row['blackFideId']?.toString() ?? ''),
          gamebasePlayerId: row['blackPlayerId']?.toString().trim(),
        );

        final tourId =
            (row['tour_id']?.toString() ??
                    row['tournament_id']?.toString() ??
                    canonicalEvent)
                .trim();

        return GamesTourModel(
          gameId: safeId,
          source: GameSource.twic,
          whitePlayer: whiteCard,
          blackPlayer: blackCard,
          whiteTimeDisplay: '--:--',
          blackTimeDisplay: '--:--',
          whiteClockCentiseconds: 0,
          blackClockCentiseconds: 0,
          gameStatus: GameStatus.fromString(result),
          roundId: 'twic_profile',
          roundSlug:
              (eco != null && eco.trim().isNotEmpty)
                  ? eco.trim()
                  : (timeControl ?? ''),
          tourId: tourId.isNotEmpty ? tourId : canonicalEvent,
          tourSlug: canonicalEvent,
          pgn: pgn,
          lastMoveTime: date,
          eco: (eco != null && eco.trim().isNotEmpty) ? eco.trim() : null,
          openingName:
              (opening != null && opening.trim().isNotEmpty)
                  ? opening.trim()
                  : null,
          timeControl: timeControl,
        );
      })
      .toList(growable: false);

  final fideIds = collectFideIdsFromGames(games);
  if (fideIds.isNotEmpty) {
    final playersByFideId = await ref
        .read(chessPlayerRepositoryProvider)
        .getPlayersByFideIds(fideIds);
    games = enrichGamesWithChessPlayers(games, playersByFideId);
  }

  final epochFallback = DateTime.fromMillisecondsSinceEpoch(0);
  games.sort((a, b) {
    final aTime = a.lastMoveTime ?? epochFallback;
    final bTime = b.lastMoveTime ?? epochFallback;
    return bTime.compareTo(aTime);
  });

  return games;
}

Future<List<GamesTourModel>> _getTwicGamesFromGamebase(
  Ref ref,
  PlayerProfileKey playerKey,
) async {
  final repo = ref.read(gamebaseRepositoryProvider);
  final playerName = playerKey.playerName.trim();
  if (playerName.isEmpty) return const [];

  // Use surname only for the search query to avoid 400 errors from commas
  // in FIDE-format names ("Surname, Firstname"). Post-filtering by playerId
  // or fideId ensures accurate results.
  final searchQuery =
      playerName.contains(',')
          ? playerName.split(',').first.trim()
          : playerName;

  final playerId = playerKey.gamebasePlayerId?.trim();
  final fideIdStr = playerKey.hasFideId ? playerKey.fideId.toString() : null;
  final rows = <Map<String, dynamic>>[];
  var page = 1;
  while (true) {
    final response = await repo.globalSearch(
      query: searchQuery,
      resources: const ['game'],
      pageNumber: page,
      pageSize: 100,
    );

    final pageRows = response.results
        .where((r) => r.resource == 'game')
        .map((r) {
          final preview = r.preview ?? const <String, dynamic>{};
          final id = (preview['id']?.toString() ?? r.id).trim();
          return <String, dynamic>{'id': id, ...preview};
        })
        .where((row) {
          if (playerId != null && playerId.isNotEmpty) {
            final w = row['whitePlayerId']?.toString().trim();
            final b = row['blackPlayerId']?.toString().trim();
            if (w == playerId || b == playerId) return true;
          }

          if (fideIdStr != null) {
            final wFide = row['whiteFideId']?.toString();
            final bFide = row['blackFideId']?.toString();
            if (wFide == fideIdStr || bFide == fideIdStr) return true;
          }

          final white =
              (row['white']?.toString() ?? row['whiteName']?.toString() ?? '');
          final black =
              (row['black']?.toString() ?? row['blackName']?.toString() ?? '');
          return _gamebaseNameMatches(white, playerName) ||
              _gamebaseNameMatches(black, playerName);
        })
        .toList(growable: false);
    rows.addAll(pageRows);

    if (!response.metadata.hasMore) break;
    if (response.results.isEmpty) break;
    page += 1;
    if (page > 200) break;
  }

  DateTime? parseDate(Object? raw) {
    if (raw == null) return null;
    return DateTime.tryParse(raw.toString());
  }

  int? parseFide(Object? raw) {
    if (raw == null) return null;
    return int.tryParse(raw.toString());
  }

  String normalizeTitle(Object? raw) {
    final text = raw?.toString();
    if (text == null || text.trim().isEmpty) return '';
    return ChessTitleUtils.normalize(text);
  }

  var games = rows
      .map((row) {
        final id = row['id']?.toString().trim();
        final safeId = (id != null && id.isNotEmpty) ? id : 'unknown';
        final result = row['result']?.toString() ?? '*';
        final timeControl = row['timeControl']?.toString();
        final date = parseDate(row['date']);

        final whiteName =
            (row['white']?.toString() ??
                    row['whiteName']?.toString() ??
                    'White')
                .trim();
        final blackName =
            (row['black']?.toString() ??
                    row['blackName']?.toString() ??
                    'Black')
                .trim();

        final event = (row['event']?.toString() ?? 'Gamebase').trim();
        final site = row['site']?.toString();
        final canonicalEvent = preferredTwicEventTitle(
          pgnEvent: event,
          tourSlug: row['tourSlug']?.toString(),
          tourId:
              row['tour_id']?.toString() ?? row['tournament_id']?.toString(),
          site: site,
          fallback: event.isNotEmpty ? event : 'Gamebase',
        );
        final eco = row['eco']?.toString();
        final opening = row['opening']?.toString();
        final variation = row['variation']?.toString();

        final pgn = buildHeaderOnlyPgn(
          whiteName: whiteName,
          blackName: blackName,
          result: result,
          event: canonicalEvent,
          site: site,
          date: date,
          eco: eco,
          opening: opening,
          variation: variation,
        );

        final whiteCard = PlayerCard(
          name: whiteName,
          federation: '',
          title: normalizeTitle(row['whiteTitle']),
          rating: (row['whiteElo'] as num?)?.toInt() ?? 0,
          countryCode: row['whiteFed']?.toString() ?? '',
          team: null,
          fideId: parseFide(row['whiteFideId']),
          gamebasePlayerId: row['whitePlayerId']?.toString().trim(),
        );

        final blackCard = PlayerCard(
          name: blackName,
          federation: '',
          title: normalizeTitle(row['blackTitle']),
          rating: (row['blackElo'] as num?)?.toInt() ?? 0,
          countryCode: row['blackFed']?.toString() ?? '',
          team: null,
          fideId: parseFide(row['blackFideId']),
          gamebasePlayerId: row['blackPlayerId']?.toString().trim(),
        );

        final tourId =
            (row['tour_id']?.toString() ??
                    row['tournament_id']?.toString() ??
                    canonicalEvent)
                .trim();

        return GamesTourModel(
          gameId: safeId,
          source: GameSource.twic,
          whitePlayer: whiteCard,
          blackPlayer: blackCard,
          whiteTimeDisplay: '--:--',
          blackTimeDisplay: '--:--',
          whiteClockCentiseconds: 0,
          blackClockCentiseconds: 0,
          gameStatus: GameStatus.fromString(result),
          roundId: 'twic_profile',
          roundSlug:
              (eco != null && eco.trim().isNotEmpty)
                  ? eco.trim()
                  : (timeControl ?? ''),
          tourId: tourId.isNotEmpty ? tourId : canonicalEvent,
          tourSlug: canonicalEvent,
          pgn: pgn,
          lastMoveTime: date,
          eco: (eco != null && eco.trim().isNotEmpty) ? eco.trim() : null,
          openingName:
              (opening != null && opening.trim().isNotEmpty)
                  ? opening.trim()
                  : null,
          timeControl: timeControl,
        );
      })
      .toList(growable: false);

  final fideIds = collectFideIdsFromGames(games);
  if (fideIds.isNotEmpty) {
    final playersByFideId = await ref
        .read(chessPlayerRepositoryProvider)
        .getPlayersByFideIds(fideIds);
    games = enrichGamesWithChessPlayers(games, playersByFideId);
  }

  final epochFallback = DateTime.fromMillisecondsSinceEpoch(0);
  games.sort((a, b) {
    final aTime = a.lastMoveTime ?? epochFallback;
    final bTime = b.lastMoveTime ?? epochFallback;
    return bTime.compareTo(aTime);
  });

  return games;
}

/// Request for player analytics with fideId and name context
class PlayerAnalyticsRequest {
  final int? fideId;
  final String playerName;
  final List<GamesTourModel> games;

  const PlayerAnalyticsRequest({
    required this.fideId,
    required this.playerName,
    required this.games,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PlayerAnalyticsRequest &&
          fideId == other.fideId &&
          playerName == other.playerName &&
          games.length == other.games.length;

  @override
  int get hashCode =>
      fideId.hashCode ^ playerName.hashCode ^ games.length.hashCode;
}

/// Provider to compute player analytics from their games
final playerAnalyticsProvider = Provider.family
    .autoDispose<PlayerAnalytics, PlayerAnalyticsRequest>((ref, request) {
      return PlayerAnalytics.fromGames(
        request.games,
        request.fideId,
        request.playerName,
      );
    });

/// Computed analytics from player games
class PlayerAnalytics {
  const PlayerAnalytics({
    required this.openingStats,
    this.openingStatsWhite = const [],
    this.openingStatsBlack = const [],
    required this.colorStats,
    required this.resultStats,
    required this.recentForm,
    required this.avgOpponentRating,
  });

  final List<OpeningStatistic> openingStats;
  final List<OpeningStatistic> openingStatsWhite;
  final List<OpeningStatistic> openingStatsBlack;
  final ColorStatistics colorStats;
  final ResultStatistics resultStats;
  final List<double> recentForm;
  final int avgOpponentRating;

  factory PlayerAnalytics.fromGames(
    List<GamesTourModel> games,
    int? targetFideId,
    String targetPlayerName,
  ) {
    if (games.isEmpty) {
      return const PlayerAnalytics(
        openingStats: [],
        openingStatsWhite: [],
        openingStatsBlack: [],
        colorStats: ColorStatistics(
          whiteGames: 0,
          whiteWins: 0,
          whiteDraws: 0,
          whiteLosses: 0,
          blackGames: 0,
          blackWins: 0,
          blackDraws: 0,
          blackLosses: 0,
        ),
        resultStats: ResultStatistics(
          totalGames: 0,
          wins: 0,
          draws: 0,
          losses: 0,
        ),
        recentForm: [],
        avgOpponentRating: 0,
      );
    }

    // Normalize target player name for matching
    final normalizedTargetName = _normalizeName(targetPlayerName);

    // Opening statistics (tracked from target player's perspective)
    final openingMapAll = <String, Map<String, dynamic>>{};
    final openingMapWhite = <String, Map<String, dynamic>>{};
    final openingMapBlack = <String, Map<String, dynamic>>{};

    // Color statistics
    int whiteGames = 0, whiteWins = 0, whiteDraws = 0, whiteLosses = 0;
    int blackGames = 0, blackWins = 0, blackDraws = 0, blackLosses = 0;

    // Result statistics
    int totalWins = 0, totalDraws = 0, totalLosses = 0;

    // Recent form (last 10 completed games)
    final form = <double>[];

    // Opponent ratings
    int totalOpponentRating = 0;
    int ratingCount = 0;

    void updateOpeningStats(
      Map<String, Map<String, dynamic>> map,
      String eco,
      String? openingName,
      bool targetWon,
      bool targetDrew,
      bool targetLost,
    ) {
      if (!map.containsKey(eco)) {
        map[eco] = {
          'eco': eco,
          'openingName': openingName,
          'count': 0,
          'wins': 0,
          'draws': 0,
          'losses': 0,
        };
      } else if (map[eco]!['openingName'] == null && openingName != null) {
        map[eco]!['openingName'] = openingName;
      }

      map[eco]!['count'] = (map[eco]!['count'] as int) + 1;

      if (targetWon) {
        map[eco]!['wins'] = (map[eco]!['wins'] as int) + 1;
      } else if (targetLost) {
        map[eco]!['losses'] = (map[eco]!['losses'] as int) + 1;
      } else if (targetDrew) {
        map[eco]!['draws'] = (map[eco]!['draws'] as int) + 1;
      }
    }

    for (int i = 0; i < games.length; i++) {
      final game = games[i];
      // Normalize ECO: treat null or '?' as 'Unknown'
      final eco = (game.eco == null || game.eco == '?') ? 'Unknown' : game.eco!;
      final openingName =
          (game.openingName == null || game.openingName == '?')
              ? null
              : game.openingName;

      // Determine if target player is white or black
      // First try fideId matching, then fall back to name matching
      bool isTargetWhite = game.whitePlayer.fideId == targetFideId;
      bool isTargetBlack = game.blackPlayer.fideId == targetFideId;

      // If fideId matching failed, try name matching
      if (!isTargetWhite && !isTargetBlack) {
        final whiteNameNormalized = _normalizeName(game.whitePlayer.name);
        final blackNameNormalized = _normalizeName(game.blackPlayer.name);

        isTargetWhite = whiteNameNormalized == normalizedTargetName;
        isTargetBlack = blackNameNormalized == normalizedTargetName;
      }

      // Skip games where target player is not found
      if (!isTargetWhite && !isTargetBlack) continue;

      // Determine game result - only process completed games
      final isWhiteWin = game.gameStatus == GameStatus.whiteWins;
      final isBlackWin = game.gameStatus == GameStatus.blackWins;
      final isDraw = game.gameStatus == GameStatus.draw;
      final isCompleted = isWhiteWin || isBlackWin || isDraw;

      // Determine target player's result
      final targetWon =
          (isTargetWhite && isWhiteWin) || (isTargetBlack && isBlackWin);
      final targetLost =
          (isTargetWhite && isBlackWin) || (isTargetBlack && isWhiteWin);
      final targetDrew = isDraw;

      // Get opponent
      final opponent = isTargetWhite ? game.blackPlayer : game.whitePlayer;

      // Only count completed games for statistics
      if (isCompleted) {
        // Update opening stats
        updateOpeningStats(
          openingMapAll,
          eco,
          openingName,
          targetWon,
          targetDrew,
          targetLost,
        );
        if (isTargetWhite) {
          updateOpeningStats(
            openingMapWhite,
            eco,
            openingName,
            targetWon,
            targetDrew,
            targetLost,
          );
        }
        if (isTargetBlack) {
          updateOpeningStats(
            openingMapBlack,
            eco,
            openingName,
            targetWon,
            targetDrew,
            targetLost,
          );
        }

        // Track overall results (regardless of ECO availability)
        if (targetWon) {
          totalWins++;
          if (form.length < 10) form.add(1.0);
        } else if (targetLost) {
          totalLosses++;
          if (form.length < 10) form.add(0.0);
        } else if (targetDrew) {
          totalDraws++;
          if (form.length < 10) form.add(0.5);
        }

        // Color statistics
        if (isTargetWhite) {
          whiteGames++;
          if (targetWon) {
            whiteWins++;
          } else if (targetDrew) {
            whiteDraws++;
          } else if (targetLost) {
            whiteLosses++;
          }
        } else {
          blackGames++;
          if (targetWon) {
            blackWins++;
          } else if (targetDrew) {
            blackDraws++;
          } else if (targetLost) {
            blackLosses++;
          }
        }

        // Track opponent rating
        if (opponent.rating > 0) {
          totalOpponentRating += opponent.rating;
          ratingCount++;
        }
      }
    }

    final totalGames = whiteGames + blackGames;

    List<OpeningStatistic> buildOpeningStats(
      Map<String, Map<String, dynamic>> map,
    ) {
      final stats =
          map.entries.map((e) {
            final data = e.value;
            return OpeningStatistic(
              eco: data['eco'] as String,
              openingName: data['openingName'] as String?,
              count: data['count'] as int,
              wins: data['wins'] as int,
              draws: data['draws'] as int,
              losses: data['losses'] as int,
            );
          }).toList();

      stats.sort((a, b) => b.count.compareTo(a.count));
      return stats;
    }

    final openingStatsAll = buildOpeningStats(openingMapAll).take(20).toList();
    final openingStatsWhite =
        buildOpeningStats(openingMapWhite).take(20).toList();
    final openingStatsBlack =
        buildOpeningStats(openingMapBlack).take(20).toList();

    return PlayerAnalytics(
      openingStats: openingStatsAll,
      openingStatsWhite: openingStatsWhite,
      openingStatsBlack: openingStatsBlack,
      colorStats: ColorStatistics(
        whiteGames: whiteGames,
        whiteWins: whiteWins,
        whiteDraws: whiteDraws,
        whiteLosses: whiteLosses,
        blackGames: blackGames,
        blackWins: blackWins,
        blackDraws: blackDraws,
        blackLosses: blackLosses,
      ),
      resultStats: ResultStatistics(
        totalGames: totalGames,
        wins: totalWins,
        draws: totalDraws,
        losses: totalLosses,
      ),
      recentForm: form,
      avgOpponentRating:
          ratingCount > 0 ? totalOpponentRating ~/ ratingCount : 0,
    );
  }

  /// Normalize player name for comparison
  /// Handles "Lastname, Firstname" vs "Firstname Lastname" formats
  static String _normalizeName(String name) {
    final trimmed = name.trim().toLowerCase();
    if (trimmed.contains(',')) {
      // Convert "Lastname, Firstname" to "firstname lastname"
      final parts = trimmed.split(',');
      if (parts.length >= 2) {
        return '${parts[1].trim()} ${parts[0].trim()}';
      }
    }
    return trimmed;
  }
}

/// Provider to fetch events/tournaments for a player
final playerEventsProvider = FutureProvider.family
    .autoDispose<List<PlayerEventData>, int>((ref, fideId) async {
      try {
        final supabase = Supabase.instance.client;
        return await _getPlayerEventsFromGames(supabase, fideId);
      } catch (e) {
        debugPrint('[playerEventsProvider] Error: $e');
        return [];
      }
    });

/// Provider to fetch events using PlayerProfileKey (supports both fideId and name lookup)
final playerEventsKeyProvider = FutureProvider.family
    .autoDispose<List<PlayerEventData>, PlayerProfileKey>((
      ref,
      playerKey,
    ) async {
      try {
        if (playerKey.source == PlayerProfileDataSource.twic) {
          return _getTwicPlayerEvents(ref, playerKey);
        }

        final supabase = Supabase.instance.client;
        return await _getPlayerEventsFromGamesWithKey(supabase, playerKey);
      } catch (e) {
        debugPrint('[playerEventsKeyProvider] Error: $e');
        return [];
      }
    });

Future<List<PlayerEventData>> _getTwicPlayerEvents(
  Ref ref,
  PlayerProfileKey playerKey,
) async {
  final games = await ref.watch(playerGamesDataKeyProvider(playerKey).future);
  if (games.isNotEmpty) {
    return _buildTwicPlayerEventsFromGames(games);
  }

  final repo = ref.read(gamebaseRepositoryProvider);
  final playerId = await _resolveTwicPlayerId(ref, playerKey);
  if (playerId == null || playerId.isEmpty) return const [];

  final response = await repo.getPlayerEvents(
    playerId: playerId,
    pageNumber: 0,
    pageSize: 100,
  );

  return mergePlayerEventsByCanonical(
    response.events
        .where((item) => item.event.trim().isNotEmpty)
        .map(playerEventDataFromGamebaseEvent),
  );
}

PlayerEventData playerEventDataFromGamebaseEvent(GamebaseEventSearchItem item) {
  final rawEvent = item.event.trim();
  // The /events endpoint groups by raw `g.event`, which for broadcast-ingested
  // games is a per-pairing label ("Round 10: A - B"). Recover the canonical
  // parent event (from the Lichess `Site` slug) so pairings collapse into one
  // event, matching what the Games tab does.
  final title = preferredTwicEventTitle(
    pgnEvent: rawEvent,
    site: item.site,
    fallback: rawEvent.isNotEmpty ? rawEvent : 'Gamebase',
  );
  return PlayerEventData(
    tourId: title,
    tourName: title,
    tourSlug: title,
    gamesPlayed: item.gameCount,
    score: item.score,
    startDate: item.startDate,
    endDate: item.endDate,
    site: item.site,
    dominantTimeControl: item.dominantTimeControl,
    avgElo: item.avgElo,
    maxElo: item.maxElo,
  );
}

/// Merge events that share a canonical [PlayerEventData.tourId] (e.g. every
/// "Round N: ..." pairing of one broadcast collapses to a single event).
/// Sums games/score, widens the date span, keeps the richest metadata.
/// Insertion order of first appearance is preserved.
List<PlayerEventData> mergePlayerEventsByCanonical(
  Iterable<PlayerEventData> events,
) {
  final byKey = <String, PlayerEventData>{};
  for (final e in events) {
    final existing = byKey[e.tourId];
    if (existing == null) {
      byKey[e.tourId] = e;
      continue;
    }
    byKey[e.tourId] = PlayerEventData(
      tourId: existing.tourId,
      tourName: existing.tourName,
      tourSlug: existing.tourSlug,
      gamesPlayed: existing.gamesPlayed + e.gamesPlayed,
      score:
          (existing.score == null && e.score == null)
              ? null
              : (existing.score ?? 0) + (e.score ?? 0),
      startDate: _earlierDate(existing.startDate, e.startDate),
      endDate: _laterDate(existing.endDate, e.endDate),
      site: existing.site ?? e.site,
      dominantTimeControl:
          existing.dominantTimeControl ?? e.dominantTimeControl,
      avgElo: _largerInt(existing.avgElo, e.avgElo),
      maxElo: _largerInt(existing.maxElo, e.maxElo),
    );
  }
  return byKey.values.toList(growable: false);
}

DateTime? _earlierDate(DateTime? a, DateTime? b) {
  if (a == null) return b;
  if (b == null) return a;
  return a.isBefore(b) ? a : b;
}

DateTime? _laterDate(DateTime? a, DateTime? b) {
  if (a == null) return b;
  if (b == null) return a;
  return a.isAfter(b) ? a : b;
}

int? _largerInt(int? a, int? b) {
  if (a == null) return b;
  if (b == null) return a;
  return a > b ? a : b;
}

List<PlayerEventData> _buildTwicPlayerEventsFromGames(
  List<GamesTourModel> games,
) {
  final byKey = <String, List<GamesTourModel>>{};
  for (final game in games) {
    final key = twicCanonicalEventKeyForGame(game);
    if (key.isEmpty) continue;
    byKey.putIfAbsent(key, () => <GamesTourModel>[]).add(game);
  }

  final events = <PlayerEventData>[];
  for (final entry in byKey.entries) {
    final eventGames = entry.value;
    eventGames.sort((a, b) {
      final aDate = a.lastMoveTime ?? DateTime(1900);
      final bDate = b.lastMoveTime ?? DateTime(1900);
      return aDate.compareTo(bDate);
    });

    final first = eventGames.first;
    final title = preferredTwicEventTitle(
      tourSlug: first.tourSlug,
      tourId: first.tourId,
      fallback: 'Gamebase',
    );
    final ratings = <int>[];
    for (final game in eventGames) {
      if (game.whitePlayer.rating > 0) ratings.add(game.whitePlayer.rating);
      if (game.blackPlayer.rating > 0) ratings.add(game.blackPlayer.rating);
    }
    final avgElo =
        ratings.isEmpty
            ? null
            : ratings.reduce((a, b) => a + b) ~/ ratings.length;
    final maxElo =
        ratings.isEmpty ? null : ratings.reduce((a, b) => a > b ? a : b);

    events.add(
      PlayerEventData(
        tourId: title,
        tourName: title,
        tourSlug: title,
        gamesPlayed: eventGames.length,
        startDate: eventGames.first.lastMoveTime,
        endDate: eventGames.last.lastMoveTime,
        site: _siteFromPgn(first.pgn),
        dominantTimeControl: first.timeControl,
        avgElo: avgElo,
        maxElo: maxElo,
      ),
    );
  }

  events.sort((a, b) {
    final aDate = a.endDate ?? a.startDate ?? DateTime(1900);
    final bDate = b.endDate ?? b.startDate ?? DateTime(1900);
    return bDate.compareTo(aDate);
  });
  return events;
}

String? _siteFromPgn(String? pgn) {
  if (pgn == null) return null;
  final match = RegExp(r'^\[Site\s+"(.*)"\]$', multiLine: true).firstMatch(pgn);
  final site = match?.group(1)?.trim();
  return site == null || site.isEmpty || site == '?' ? null : site;
}

String _formatEventTimeControl(String? raw) {
  final normalized = raw?.trim().toUpperCase();
  switch (normalized) {
    case 'CLASSICAL':
      return 'Standard';
    case 'RAPID':
      return 'Rapid';
    case 'BLITZ':
      return 'Blitz';
    default:
      return 'Standard';
  }
}

final playerTwicEventCardsProvider = FutureProvider.family
    .autoDispose<Map<String, GroupEventCardModel>, PlayerProfileKey>((
      ref,
      playerKey,
    ) async {
      final events = await ref.watch(playerEventsKeyProvider(playerKey).future);
      final eventCards = <String, GroupEventCardModel>{};

      for (final event in events) {
        final id = 'twic_event_${event.tourId}';
        eventCards[event.tourId] = GroupEventCardModel(
          id: id,
          title: event.tourName,
          dates: TimeUtils.formatDateRange(event.startDate, event.endDate),
          maxAvgElo: event.avgElo ?? event.maxElo ?? 0,
          timeUntilStart: TimeUtils.timeUntilStart(event.startDate),
          tourEventCategory: GroupEventCardModel.getCategory(
            groupId: id,
            groupName: event.tourName,
            startDate: event.startDate,
            endDate: event.endDate,
            liveGroupIds: const [],
          ),
          timeControl: _formatEventTimeControl(event.dominantTimeControl),
          endDate: event.endDate,
          startDate: event.startDate,
          location: event.site,
          searchTerms: [event.tourName],
          eventSource: EventSource.communityEvent,
        );
      }

      return eventCards;
    });

final playerProfileDataKeyProvider = FutureProvider.family
    .autoDispose<PlayerProfileData?, PlayerProfileKey>((ref, playerKey) async {
      final chessPlayerRepo = ref.read(chessPlayerRepositoryProvider);

      if (playerKey.source == PlayerProfileDataSource.twic) {
        final repo = ref.read(gamebaseRepositoryProvider);
        final playerId = await _resolveTwicPlayerId(ref, playerKey);

        if (playerId != null && playerId.isNotEmpty) {
          final player = await repo.getPlayerById(playerId);
          if (player != null) {
            final fideInt = int.tryParse(player.fideId);
            final resolvedFideId =
                (fideInt != null && fideInt > 0)
                    ? fideInt
                    : (playerKey.hasFideId ? playerKey.fideId : null);
            final supabasePlayer =
                (resolvedFideId != null && resolvedFideId > 0)
                    ? await chessPlayerRepo.getPlayerByFideId(resolvedFideId)
                    : null;
            return PlayerProfileData(
              fideId: resolvedFideId ?? 0,
              name: player.name,
              title: ChessTitleUtils.normalize(
                (supabasePlayer?.title?.trim().isNotEmpty ?? false)
                    ? supabasePlayer!.title
                    : player.title,
              ),
              federation:
                  (supabasePlayer?.country?.trim().isNotEmpty ?? false)
                      ? supabasePlayer!.country
                      : player.fed,
              classicalRating: player.ratingClassical ?? supabasePlayer?.rating,
              rapidRating: player.ratingRapid,
              blitzRating: player.ratingBlitz,
            );
          }
        }

        if (playerKey.hasFideId) {
          final fallbackSupabase = await chessPlayerRepo.getPlayerByFideId(
            playerKey.fideId!,
          );
          return PlayerProfileData(
            fideId: playerKey.fideId!,
            name:
                fallbackSupabase?.name.trim().isNotEmpty == true
                    ? fallbackSupabase!.name
                    : playerKey.playerName,
            title: ChessTitleUtils.normalize(fallbackSupabase?.title),
            federation: fallbackSupabase?.country,
            classicalRating: fallbackSupabase?.rating,
          );
        }
        return null;
      }

      if (!playerKey.hasFideId) return null;
      return ref.watch(playerProfileDataProvider(playerKey.fideId!).future);
    });

/// Get player events from games table - supports both fideId and name-based lookup
Future<List<PlayerEventData>> _getPlayerEventsFromGamesWithKey(
  SupabaseClient supabase,
  PlayerProfileKey playerKey,
) async {
  try {
    List<dynamic> response;

    if (playerKey.hasFideId) {
      // Query by fideId in players JSONB array
      response = await supabase
          .from('games')
          .select(
            'tour_id, tour_slug, status, players, date_start, player_white, player_black',
          )
          .contains('player_fide_ids', [playerKey.fideId])
          .order('date_start', ascending: false)
          .limit(500);
    } else {
      // Query by player name in player_white or player_black columns
      response = await supabase
          .from('games')
          .select(
            'tour_id, tour_slug, status, players, date_start, player_white, player_black',
          )
          .or(
            'player_white.eq."${playerKey.playerName}",player_black.eq."${playerKey.playerName}"',
          )
          .order('date_start', ascending: false)
          .limit(500);
    }

    if (response.isEmpty) {
      return [];
    }

    // Group by tour_id and calculate stats (skip variant events)
    final tourMap = <String, Map<String, dynamic>>{};
    for (final row in response) {
      final tourId = row['tour_id'] as String?;
      if (tourId == null) continue;

      // Skip non-standard chess variants
      final tourSlug = row['tour_slug'] as String?;
      if (_isVariantEvent(tourSlug)) continue;

      if (!tourMap.containsKey(tourId)) {
        tourMap[tourId] = {
          'tour_id': tourId,
          'tour_slug': tourSlug,
          'count': 0,
          'wins': 0,
          'draws': 0,
          'losses': 0,
          'latest_date': row['date_start'],
        };
      }
      tourMap[tourId]!['count'] = (tourMap[tourId]!['count'] as int) + 1;

      // Calculate score based on game result
      final status = row['status'] as String?;
      final playerWhite = row['player_white'] as String?;
      final playerBlack = row['player_black'] as String?;
      final players = row['players'] as List<dynamic>?;

      bool isWhite = false;
      bool isBlack = false;

      if (playerKey.hasFideId && players != null && players.length >= 2) {
        final whitePlayer = players[0] as Map<String, dynamic>?;
        final blackPlayer =
            players.length > 1 ? players[1] as Map<String, dynamic>? : null;
        isWhite = whitePlayer?['fideId'] == playerKey.fideId;
        isBlack = blackPlayer?['fideId'] == playerKey.fideId;
      } else {
        // Name-based matching
        isWhite = playerWhite == playerKey.playerName;
        isBlack = playerBlack == playerKey.playerName;
      }

      if (status != null && (isWhite || isBlack)) {
        final isWhiteWin = status == 'whiteWins' || status == '1-0';
        final isBlackWin = status == 'blackWins' || status == '0-1';
        final isDraw =
            status == 'draw' || status == '1/2-1/2' || status == '½-½';

        if ((isWhite && isWhiteWin) || (isBlack && isBlackWin)) {
          tourMap[tourId]!['wins'] = (tourMap[tourId]!['wins'] as int) + 1;
        } else if ((isWhite && isBlackWin) || (isBlack && isWhiteWin)) {
          tourMap[tourId]!['losses'] = (tourMap[tourId]!['losses'] as int) + 1;
        } else if (isDraw) {
          tourMap[tourId]!['draws'] = (tourMap[tourId]!['draws'] as int) + 1;
        }
      }
    }

    // Get tour details including group_broadcast info
    final tourIds = tourMap.keys.toList();
    if (tourIds.isEmpty) return [];

    final toursResponse = await supabase
        .from('tours')
        .select('id, name, slug, group_broadcast_id, dates')
        .inFilter('id', tourIds);

    // Also get group_broadcast details for dates
    final groupBroadcastIds = <String>{};
    final tourDetails = <String, Map<String, dynamic>>{};

    for (final tour in toursResponse as List) {
      final tourId = tour['id'] as String;
      tourDetails[tourId] = tour;
      final gbId = tour['group_broadcast_id'] as String?;
      if (gbId != null && gbId.isNotEmpty) {
        groupBroadcastIds.add(gbId);
      }
    }

    // Fetch group_broadcast dates
    final groupBroadcastDates = <String, Map<String, DateTime?>>{};
    if (groupBroadcastIds.isNotEmpty) {
      final gbResponse = await supabase
          .from('group_broadcasts')
          .select('id, date_start, date_end')
          .inFilter('id', groupBroadcastIds.toList());

      for (final gb in gbResponse as List) {
        final gbId = gb['id'] as String;
        groupBroadcastDates[gbId] = {
          'start':
              gb['date_start'] != null
                  ? DateTime.tryParse(gb['date_start'] as String)
                  : null,
          'end':
              gb['date_end'] != null
                  ? DateTime.tryParse(gb['date_end'] as String)
                  : null,
        };
      }
    }

    // Build event list
    final events = <PlayerEventData>[];
    for (final entry in tourMap.entries) {
      final tourId = entry.key;
      final data = entry.value;
      final tour = tourDetails[tourId];
      final gbId = tour?['group_broadcast_id'] as String?;
      final gbDates = gbId != null ? groupBroadcastDates[gbId] : null;

      // Calculate score (wins + 0.5 * draws)
      final wins = data['wins'] as int;
      final draws = data['draws'] as int;
      final score = wins + (draws * 0.5);

      // Get dates from tour or group_broadcast
      DateTime? startDate;
      DateTime? endDate;

      if (gbDates != null) {
        startDate = gbDates['start'];
        endDate = gbDates['end'];
      } else if (tour != null) {
        final dates = tour['dates'] as List<dynamic>?;
        if (dates != null && dates.isNotEmpty) {
          startDate = DateTime.tryParse(dates.first as String);
          if (dates.length > 1) {
            endDate = DateTime.tryParse(dates.last as String);
          }
        }
      }

      // Fallback to latest game date
      if (startDate == null && data['latest_date'] != null) {
        startDate = DateTime.tryParse(data['latest_date'] as String);
      }

      events.add(
        PlayerEventData(
          tourId: tourId,
          tourName:
              tour?['name'] as String? ??
              data['tour_slug'] as String? ??
              'Unknown Tournament',
          tourSlug: tour?['slug'] as String? ?? data['tour_slug'] as String?,
          gamesPlayed: data['count'] as int,
          score: score,
          startDate: startDate,
          endDate: endDate,
        ),
      );
    }

    // Sort by start date descending (most recent first)
    events.sort((a, b) {
      final aDate = a.startDate ?? DateTime(1900);
      final bDate = b.startDate ?? DateTime(1900);
      return bDate.compareTo(aDate);
    });

    return events;
  } catch (e) {
    debugPrint('[_getPlayerEventsFromGamesWithKey] Error: $e');
    return [];
  }
}

/// Get player events from games table by querying the players JSONB array
Future<List<PlayerEventData>> _getPlayerEventsFromGames(
  SupabaseClient supabase,
  int fideId,
) async {
  try {
    // Query games with this player's FIDE ID in players JSONB array
    // Use the same format as getGamesByFideId in game_repository.dart
    final response = await supabase
        .from('games')
        .select('tour_id, tour_slug, status, players, date_start')
        .contains('player_fide_ids', [fideId])
        .order('date_start', ascending: false)
        .limit(500);
    final responseList = response as List;

    if (responseList.isEmpty) {
      return [];
    }

    // Group by tour_id and calculate stats (skip variant events)
    final tourMap = <String, Map<String, dynamic>>{};
    for (final row in responseList) {
      final tourId = row['tour_id'] as String?;
      if (tourId == null) continue;

      // Skip non-standard chess variants
      final tourSlug = row['tour_slug'] as String?;
      if (_isVariantEvent(tourSlug)) continue;

      if (!tourMap.containsKey(tourId)) {
        tourMap[tourId] = {
          'tour_id': tourId,
          'tour_slug': tourSlug,
          'count': 0,
          'wins': 0,
          'draws': 0,
          'losses': 0,
          'latest_date': row['date_start'],
        };
      }
      tourMap[tourId]!['count'] = (tourMap[tourId]!['count'] as int) + 1;

      // Calculate score based on game result
      final status = row['status'] as String?;
      final players = row['players'] as List<dynamic>?;
      if (status != null && players != null && players.length >= 2) {
        // Determine if player is white or black
        final whitePlayer = players[0] as Map<String, dynamic>?;
        final blackPlayer =
            players.length > 1 ? players[1] as Map<String, dynamic>? : null;
        final isWhite = whitePlayer?['fideId'] == fideId;
        final isBlack = blackPlayer?['fideId'] == fideId;

        if (isWhite || isBlack) {
          final isWhiteWin = status == 'whiteWins' || status == '1-0';
          final isBlackWin = status == 'blackWins' || status == '0-1';
          final isDraw =
              status == 'draw' || status == '1/2-1/2' || status == '½-½';

          if ((isWhite && isWhiteWin) || (isBlack && isBlackWin)) {
            tourMap[tourId]!['wins'] = (tourMap[tourId]!['wins'] as int) + 1;
          } else if ((isWhite && isBlackWin) || (isBlack && isWhiteWin)) {
            tourMap[tourId]!['losses'] =
                (tourMap[tourId]!['losses'] as int) + 1;
          } else if (isDraw) {
            tourMap[tourId]!['draws'] = (tourMap[tourId]!['draws'] as int) + 1;
          }
        }
      }
    }

    // Get tour details including group_broadcast info
    final tourIds = tourMap.keys.toList();
    if (tourIds.isEmpty) return [];

    final toursResponse = await supabase
        .from('tours')
        .select('id, name, slug, group_broadcast_id, dates')
        .inFilter('id', tourIds);

    // Also get group_broadcast details for dates
    final groupBroadcastIds = <String>{};
    final tourDetails = <String, Map<String, dynamic>>{};

    for (final tour in toursResponse as List) {
      final tourId = tour['id'] as String;
      tourDetails[tourId] = tour;
      final gbId = tour['group_broadcast_id'] as String?;
      if (gbId != null && gbId.isNotEmpty) {
        groupBroadcastIds.add(gbId);
      }
    }

    // Fetch group_broadcast dates
    final groupBroadcastDates = <String, Map<String, DateTime?>>{};
    if (groupBroadcastIds.isNotEmpty) {
      final gbResponse = await supabase
          .from('group_broadcasts')
          .select('id, date_start, date_end')
          .inFilter('id', groupBroadcastIds.toList());

      for (final gb in gbResponse as List) {
        final gbId = gb['id'] as String;
        groupBroadcastDates[gbId] = {
          'start':
              gb['date_start'] != null
                  ? DateTime.tryParse(gb['date_start'] as String)
                  : null,
          'end':
              gb['date_end'] != null
                  ? DateTime.tryParse(gb['date_end'] as String)
                  : null,
        };
      }
    }

    // Build event list
    final events = <PlayerEventData>[];
    for (final entry in tourMap.entries) {
      final tourId = entry.key;
      final data = entry.value;
      final tour = tourDetails[tourId];
      final gbId = tour?['group_broadcast_id'] as String?;
      final gbDates = gbId != null ? groupBroadcastDates[gbId] : null;

      // Calculate score (wins + 0.5 * draws)
      final wins = data['wins'] as int;
      final draws = data['draws'] as int;
      final score = wins + (draws * 0.5);

      // Get dates from tour or group_broadcast
      DateTime? startDate;
      DateTime? endDate;

      if (gbDates != null) {
        startDate = gbDates['start'];
        endDate = gbDates['end'];
      } else if (tour != null) {
        final dates = tour['dates'] as List<dynamic>?;
        if (dates != null && dates.isNotEmpty) {
          startDate = DateTime.tryParse(dates.first as String);
          if (dates.length > 1) {
            endDate = DateTime.tryParse(dates.last as String);
          }
        }
      }

      // Fallback to latest game date
      if (startDate == null && data['latest_date'] != null) {
        startDate = DateTime.tryParse(data['latest_date'] as String);
      }

      events.add(
        PlayerEventData(
          tourId: tourId,
          tourName:
              tour?['name'] as String? ??
              data['tour_slug'] as String? ??
              'Unknown Tournament',
          tourSlug: tour?['slug'] as String? ?? data['tour_slug'] as String?,
          gamesPlayed: data['count'] as int,
          score: score,
          startDate: startDate,
          endDate: endDate,
        ),
      );
    }

    // Sort by start date descending (most recent first)
    events.sort((a, b) {
      final aDate = a.startDate ?? DateTime(1900);
      final bDate = b.startDate ?? DateTime(1900);
      return bDate.compareTo(aDate);
    });

    return events;
  } catch (e) {
    debugPrint('[_getPlayerEventsFromGames] Error: $e');
    return [];
  }
}

/// State for player profile games with filtering
enum PlayerResultFilter { all, win, draw, loss }

extension PlayerResultFilterX on PlayerResultFilter {
  String get label {
    switch (this) {
      case PlayerResultFilter.all:
        return 'All Results';
      case PlayerResultFilter.win:
        return 'Wins';
      case PlayerResultFilter.draw:
        return 'Draws';
      case PlayerResultFilter.loss:
        return 'Losses';
    }
  }
}

class _SearchClauseTerm {
  const _SearchClauseTerm({required this.term, required this.negated});

  final String term;
  final bool negated;
}

GameFilter playerProfileEffectiveFilter(GameFilter filter) {
  return filter.copyWith(
    minYear:
        filter.minYear == GameFilter.defaultMinYear
            ? GameFilter.absoluteMinYear
            : filter.minYear,
    minRating:
        filter.minRating == GameFilter.defaultMinRating
            ? GameFilter.absoluteMinRating
            : filter.minRating,
  );
}

bool playerProfileHasStructuredFilters(GameFilter filter) {
  final effective = playerProfileEffectiveFilter(filter);
  return effective.result != GameResultFilter.all ||
      effective.color != GameColorFilter.all ||
      effective.timeControl != GameTimeControlFilter.all ||
      effective.live != GameLiveFilter.all ||
      !effective.eco.isAll ||
      effective.minYear != GameFilter.absoluteMinYear ||
      effective.maxYear != DateTime.now().year ||
      effective.minRating != GameFilter.absoluteMinRating ||
      effective.maxRating != GameFilter.absoluteMaxRating;
}

class PlayerProfileGamesState {
  static const Object _unset = Object();

  PlayerProfileGamesState({
    required this.playerKey,
    this.allGames = const [],
    GameFilter? filter,
    this.playerResultFilter = PlayerResultFilter.all,
    this.isLoading = false,
    this.isLoadingMore = false,
    this.hasMorePages = false,
    this.nextPageNumber = 0,
    this.totalCount,
    this.error,
    this.searchQuery = '',
  }) : filter = filter ?? GameFilter();

  final PlayerProfileKey playerKey;
  final List<GamesTourModel> allGames;
  final GameFilter filter;
  final PlayerResultFilter playerResultFilter;
  final bool isLoading;
  final bool isLoadingMore;
  final bool hasMorePages;
  final int nextPageNumber;
  final int? totalCount;
  final String? error;
  final String searchQuery;

  /// For backwards compatibility
  int get targetFideId => playerKey.fideId ?? 0;

  List<GamesTourModel> get filteredGames {
    var games = allGames;

    if (playerKey.source == PlayerProfileDataSource.twic) {
      if (filter.live == GameLiveFilter.all) return games;

      // TWIC handles most filters server-side, but lifecycle status is a local
      // app concept and must still obey the shared Live/Completed semantics.
      return GameFilterHelper.applyFilter(
        games,
        GameFilter(live: filter.live),
        targetFideId: playerKey.fideId,
        playerNameQuery: playerKey.hasFideId ? null : playerKey.playerName,
      );
    }

    // Apply search query (supports chained AND / OR / NOT terms).
    if (searchQuery.trim().isNotEmpty) {
      games = games
          .where((game) => _matchesSearchQuery(game, searchQuery))
          .toList(growable: false);
    }

    // Apply player-result filter (from player's perspective)
    if (playerResultFilter != PlayerResultFilter.all) {
      games = games.where(_matchesPlayerResultFilter).toList();
    }

    if (!playerProfileHasStructuredFilters(filter)) {
      return games;
    }

    // Apply filter with targetFideId for accurate color filtering.
    // Player profile treats untouched year/rating sliders as neutral bounds.
    return GameFilterHelper.applyFilter(
      games,
      playerProfileEffectiveFilter(filter),
      targetFideId: playerKey.fideId,
      playerNameQuery: playerKey.hasFideId ? null : playerKey.playerName,
    );
  }

  static final RegExp _searchTokenPattern = RegExp(r'"([^"]+)"|(\S+)');
  static final RegExp _siteTagPattern = RegExp(
    r'\[Site\s+"([^"]+)"\]',
    caseSensitive: false,
  );

  bool _matchesSearchQuery(GamesTourModel game, String rawQuery) {
    final query = rawQuery.trim();
    if (query.isEmpty) return true;

    final clauses = query.split(
      RegExp(r'\s+(?:or|\|)\s+', caseSensitive: false),
    );
    for (final clause in clauses) {
      final terms = _parseClauseTerms(clause);
      if (terms.isEmpty) continue;

      var clauseMatch = true;
      for (final term in terms) {
        final termMatch = _matchesSearchTerm(game, term.term);
        if (term.negated ? termMatch : !termMatch) {
          clauseMatch = false;
          break;
        }
      }

      if (clauseMatch) return true;
    }

    return false;
  }

  List<_SearchClauseTerm> _parseClauseTerms(String clause) {
    final terms = <_SearchClauseTerm>[];
    var negateNext = false;

    for (final match in _searchTokenPattern.allMatches(clause)) {
      var token = (match.group(1) ?? match.group(2) ?? '').trim();
      if (token.isEmpty) continue;

      token = token.replaceAll(RegExp(r'^[()]+|[()]+$'), '');
      if (token.isEmpty) continue;

      final lowered = token.toLowerCase();
      if (lowered == 'and' || token == '&&') {
        continue;
      }
      if (lowered == 'not' || token == '!') {
        negateNext = !negateNext;
        continue;
      }

      var isNegated = negateNext;
      negateNext = false;
      if (token.startsWith('-')) {
        token = token.substring(1).trim();
        if (token.isEmpty) continue;
        isNegated = !isNegated;
      }

      terms.add(_SearchClauseTerm(term: token, negated: isNegated));
    }

    return terms;
  }

  bool _matchesSearchTerm(GamesTourModel game, String rawTerm) {
    final term = _normalizeSearchText(rawTerm);
    if (term.isEmpty) return true;

    final separator = term.indexOf(':');
    if (separator > 0) {
      final field = term.substring(0, separator).trim();
      final value = term.substring(separator + 1).trim();
      if (value.isEmpty) return true;
      return _matchesSearchField(game, field, value);
    }

    return _containsNormalized(_buildSearchCorpus(game), term);
  }

  bool _matchesSearchField(GamesTourModel game, String field, String value) {
    final normalizedValue =
        value.endsWith('*') ? value.substring(0, value.length - 1) : value;
    if (normalizedValue.isEmpty) return true;

    switch (field) {
      case 'white':
        return _containsNormalized(
          _normalizeSearchText(
            '${game.whitePlayer.title} ${game.whitePlayer.name}',
          ),
          normalizedValue,
        );
      case 'black':
        return _containsNormalized(
          _normalizeSearchText(
            '${game.blackPlayer.title} ${game.blackPlayer.name}',
          ),
          normalizedValue,
        );
      case 'player':
      case 'players':
      case 'name':
      case 'opponent':
        return _containsNormalized(
          _normalizeSearchText(
            '${game.whitePlayer.title} ${game.whitePlayer.name} ${game.blackPlayer.title} ${game.blackPlayer.name}',
          ),
          normalizedValue,
        );
      case 'title':
      case 'titles':
        return _containsNormalized(
          _normalizeSearchText(
            '${game.whitePlayer.title} ${game.blackPlayer.title}',
          ),
          normalizedValue,
        );
      case 'fed':
      case 'federation':
      case 'country':
      case 'flag':
        return _containsNormalized(
          _normalizeSearchText(
            '${game.whitePlayer.countryCode} ${game.blackPlayer.countryCode} ${game.whitePlayer.federation} ${game.blackPlayer.federation}',
          ),
          normalizedValue,
        );
      case 'event':
      case 'tournament':
      case 'tour':
        return _containsNormalized(
          _normalizeSearchText('${game.tourId} ${game.tourSlug ?? ''}'),
          normalizedValue,
        );
      case 'opening':
      case 'variation':
      case 'eco':
        return _containsNormalized(
          _normalizeSearchText(
            '${game.openingName ?? ''} ${game.eco ?? ''} ${game.roundSlug ?? ''}',
          ),
          normalizedValue,
        );
      case 'time':
      case 'tc':
      case 'timecontrol':
        return _containsNormalized(
          _normalizeSearchText(game.timeControl ?? ''),
          normalizedValue,
        );
      case 'result':
      case 'outcome':
      case 'status':
        return _containsNormalized(
          _normalizeSearchText(_resultSearchTerms(game.gameStatus)),
          normalizedValue,
        );
      case 'date':
      case 'year':
        return _containsNormalized(
          _normalizeSearchText(_dateSearchTerms(game.lastMoveTime)),
          normalizedValue,
        );
      case 'site':
        return _containsNormalized(
          _normalizeSearchText(_extractSiteFromPgn(game.pgn)),
          normalizedValue,
        );
      case 'id':
      case 'game':
        return _containsNormalized(
          _normalizeSearchText(game.gameId),
          normalizedValue,
        );
      default:
        return _containsNormalized(_buildSearchCorpus(game), normalizedValue);
    }
  }

  String _buildSearchCorpus(GamesTourModel game) {
    return _normalizeSearchText(
      [
        game.gameId,
        game.whitePlayer.name,
        game.whitePlayer.title,
        game.whitePlayer.countryCode,
        game.whitePlayer.federation,
        game.blackPlayer.name,
        game.blackPlayer.title,
        game.blackPlayer.countryCode,
        game.blackPlayer.federation,
        game.openingName ?? '',
        game.eco ?? '',
        game.roundSlug ?? '',
        game.tourId,
        game.tourSlug ?? '',
        _extractSiteFromPgn(game.pgn),
        game.timeControl ?? '',
        _resultSearchTerms(game.gameStatus),
        _dateSearchTerms(game.lastMoveTime),
      ].where((part) => part.trim().isNotEmpty).join(' '),
    );
  }

  static String _extractSiteFromPgn(String? pgn) {
    if (pgn == null || pgn.isEmpty) return '';
    final match = _siteTagPattern.firstMatch(pgn);
    return match?.group(1)?.trim() ?? '';
  }

  static String _resultSearchTerms(GameStatus status) {
    switch (status) {
      case GameStatus.whiteWins:
        return 'white win wins 1-0 w';
      case GameStatus.blackWins:
        return 'black win wins 0-1 b';
      case GameStatus.draw:
        return 'draw drawn 1/2-1/2 d';
      case GameStatus.ongoing:
        return 'ongoing live inprogress *';
      case GameStatus.unknown:
        return 'unknown';
    }
  }

  static String _dateSearchTerms(DateTime? date) {
    if (date == null) return '';
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year} ${date.year}-$month-$day';
  }

  static String _normalizeSearchText(String input) {
    return input
        .toLowerCase()
        .replaceAll(RegExp(r'[_-]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static bool _containsNormalized(String haystack, String needle) {
    if (needle.isEmpty) return true;
    return haystack.contains(needle);
  }

  bool _matchesPlayerResultFilter(GamesTourModel game) {
    final isWhiteWin = game.gameStatus == GameStatus.whiteWins;
    final isBlackWin = game.gameStatus == GameStatus.blackWins;
    final isDraw = game.gameStatus == GameStatus.draw;
    final isCompleted = isWhiteWin || isBlackWin || isDraw;

    if (!isCompleted) return false;

    bool isTargetWhite = false;
    bool isTargetBlack = false;

    if (playerKey.fideId != null) {
      isTargetWhite = game.whitePlayer.fideId == playerKey.fideId;
      isTargetBlack = game.blackPlayer.fideId == playerKey.fideId;
    } else {
      final targetName = playerKey.playerName.trim().toLowerCase();
      if (targetName.isNotEmpty) {
        isTargetWhite = game.whitePlayer.name.toLowerCase().contains(
          targetName,
        );
        isTargetBlack = game.blackPlayer.name.toLowerCase().contains(
          targetName,
        );
      }
    }

    if (!isTargetWhite && !isTargetBlack) {
      return true;
    }

    switch (playerResultFilter) {
      case PlayerResultFilter.win:
        return (isTargetWhite && isWhiteWin) || (isTargetBlack && isBlackWin);
      case PlayerResultFilter.draw:
        return isDraw;
      case PlayerResultFilter.loss:
        return (isTargetWhite && isBlackWin) || (isTargetBlack && isWhiteWin);
      case PlayerResultFilter.all:
        return true;
    }
  }

  bool get hasActiveFilters =>
      filter.hasActiveFilters ||
      playerResultFilter != PlayerResultFilter.all ||
      searchQuery.isNotEmpty;

  int get activeFilterCount =>
      filter.activeFilterCount +
      (playerResultFilter != PlayerResultFilter.all ? 1 : 0) +
      (searchQuery.isNotEmpty ? 1 : 0);

  PlayerProfileGamesState copyWith({
    PlayerProfileKey? playerKey,
    List<GamesTourModel>? allGames,
    GameFilter? filter,
    PlayerResultFilter? playerResultFilter,
    bool? isLoading,
    bool? isLoadingMore,
    bool? hasMorePages,
    int? nextPageNumber,
    Object? totalCount = _unset,
    String? error,
    String? searchQuery,
  }) {
    return PlayerProfileGamesState(
      playerKey: playerKey ?? this.playerKey,
      allGames: allGames ?? this.allGames,
      filter: filter ?? this.filter,
      playerResultFilter: playerResultFilter ?? this.playerResultFilter,
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      hasMorePages: hasMorePages ?? this.hasMorePages,
      nextPageNumber: nextPageNumber ?? this.nextPageNumber,
      totalCount:
          identical(totalCount, _unset) ? this.totalCount : totalCount as int?,
      error: error,
      searchQuery: searchQuery ?? this.searchQuery,
    );
  }
}

// ---------------------------------------------------------------------------
// Filter mapping helpers (TWIC → Gamebase API params)
// ---------------------------------------------------------------------------

String? _playerResultToOutcome(PlayerResultFilter f) => switch (f) {
  PlayerResultFilter.all => null,
  PlayerResultFilter.win => 'win',
  PlayerResultFilter.loss => 'loss',
  PlayerResultFilter.draw => 'draw',
};

String? _gameFilterResultToApi(GameResultFilter r) => switch (r) {
  GameResultFilter.all => null,
  GameResultFilter.whiteWins => 'W',
  GameResultFilter.blackWins => 'B',
  GameResultFilter.draw => 'D',
};

String? _colorToApi(GameColorFilter c) => switch (c) {
  GameColorFilter.all => null,
  GameColorFilter.white => 'white',
  GameColorFilter.black => 'black',
};

String? _timeControlToApi(GameTimeControlFilter tc) => switch (tc) {
  GameTimeControlFilter.all => null,
  GameTimeControlFilter.classical => 'CLASSICAL',
  GameTimeControlFilter.rapid => 'RAPID',
  GameTimeControlFilter.blitz => 'BLITZ',
};

bool? _onlineToApi(GameOnlineFilter o) => switch (o) {
  GameOnlineFilter.all => null,
  GameOnlineFilter.online => true,
  GameOnlineFilter.otb => false,
};

String? _outcomeFromAbsoluteResult(
  GameResultFilter resultFilter,
  GameColorFilter colorFilter,
) {
  if (resultFilter == GameResultFilter.all) return null;
  if (resultFilter == GameResultFilter.draw) return 'draw';
  if (colorFilter == GameColorFilter.all) return null;

  if (resultFilter == GameResultFilter.whiteWins) {
    return colorFilter == GameColorFilter.white ? 'win' : 'loss';
  }

  // black wins
  return colorFilter == GameColorFilter.black ? 'win' : 'loss';
}

String? _resolvePlayerOutcome({
  required PlayerResultFilter playerResultFilter,
  required GameResultFilter resultFilter,
  required GameColorFilter colorFilter,
}) {
  return _playerResultToOutcome(playerResultFilter) ??
      _outcomeFromAbsoluteResult(resultFilter, colorFilter);
}

String? _yearMinToDateFrom(GameFilter filter) {
  if (filter.minYear <= GameFilter.absoluteMinYear) return null;
  return '${filter.minYear}-01-01';
}

String? _yearMaxToExclusiveDateTo(GameFilter filter) {
  final defaultFilter = GameFilter.defaultFilter();
  if (filter.maxYear == defaultFilter.maxYear) return null;
  // Backend expects dateTo as exclusive bound.
  return '${filter.maxYear + 1}-01-01';
}

enum TwicStatsScope { allGames, filtered, filteredIgnoringEco }

class TwicPlayerStatsRequest {
  const TwicPlayerStatsRequest({required this.playerKey, required this.scope});

  final PlayerProfileKey playerKey;
  final TwicStatsScope scope;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TwicPlayerStatsRequest &&
          other.playerKey == playerKey &&
          other.scope == scope;

  @override
  int get hashCode => Object.hash(playerKey, scope);
}

/// Server-backed TWIC analytics. Uses exact `/api/player/{id}/stats`.
final twicPlayerStatsProvider = FutureProvider.family.autoDispose<
  PlayerAnalytics?,
  TwicPlayerStatsRequest
>((ref, request) async {
  final playerKey = request.playerKey;
  if (playerKey.source != PlayerProfileDataSource.twic) return null;

  Future<PlayerAnalytics?> fallbackFromLoadedGames() async {
    final gamesState = ref.read(playerProfileGamesKeyProvider(playerKey));
    if (gamesState.allGames.isEmpty) return null;
    if (gamesState.hasMorePages) return null;
    final totalCount = gamesState.totalCount;
    if (totalCount != null && gamesState.allGames.length < totalCount) {
      return null;
    }

    var filter = gamesState.filter;
    if (request.scope == TwicStatsScope.allGames) {
      filter = GameFilter.defaultFilter();
    } else if (request.scope == TwicStatsScope.filteredIgnoringEco) {
      filter = filter.copyWith(eco: GameEcoFilter.all);
    }
    final effectiveFilter = playerProfileEffectiveFilter(filter);

    final filteredGames =
        playerProfileHasStructuredFilters(filter)
            ? GameFilterHelper.applyFilter(
              gamesState.allGames,
              effectiveFilter,
              targetFideId: playerKey.fideId,
              playerNameQuery:
                  playerKey.hasFideId ? null : playerKey.playerName,
            )
            : gamesState.allGames;

    return ref.read(
      playerAnalyticsProvider(
        PlayerAnalyticsRequest(
          fideId: playerKey.fideId,
          playerName: playerKey.playerName,
          games: filteredGames,
        ),
      ),
    );
  }

  var playerId = await ref.watch(twicPlayerIdProvider(playerKey).future);
  if (playerId == null || playerId.isEmpty) return null;

  final filterSnapshot = ref.watch(
    playerProfileGamesKeyProvider(playerKey).select(
      (state) => (state.filter, state.playerResultFilter, state.searchQuery),
    ),
  );
  var filter = filterSnapshot.$1;
  final searchQuery = filterSnapshot.$3.trim();

  if (request.scope == TwicStatsScope.allGames) {
    filter = GameFilter.defaultFilter();
  } else if (request.scope == TwicStatsScope.filteredIgnoringEco) {
    filter = filter.copyWith(eco: GameEcoFilter.all);
  }
  final effectiveFilter = playerProfileEffectiveFilter(filter);

  final color = _colorToApi(effectiveFilter.color) ?? 'all';
  final timeControl = _timeControlToApi(effectiveFilter.timeControl);
  final eco = effectiveFilter.eco.isAll ? null : effectiveFilter.eco.code;
  final outcome = _resolvePlayerOutcome(
    playerResultFilter:
        request.scope == TwicStatsScope.allGames
            ? PlayerResultFilter.all
            : filterSnapshot.$2,
    resultFilter:
        request.scope == TwicStatsScope.allGames
            ? GameResultFilter.all
            : effectiveFilter.result,
    colorFilter: effectiveFilter.color,
  );
  final ratingFrom =
      effectiveFilter.minRating != GameFilter.absoluteMinRating
          ? effectiveFilter.minRating
          : null;
  final ratingTo =
      effectiveFilter.maxRating != GameFilter.absoluteMaxRating
          ? effectiveFilter.maxRating
          : null;

  final repo = ref.read(gamebaseRepositoryProvider);
  Map<String, dynamic> response;
  try {
    response = await repo.getPlayerStats(
      playerId: playerId,
      q: searchQuery.isNotEmpty ? searchQuery : null,
      color: color,
      timeControl: timeControl,
      outcome: outcome,
      eco: request.scope == TwicStatsScope.filteredIgnoringEco ? null : eco,
      dateFrom: _yearMinToDateFrom(effectiveFilter),
      dateTo: _yearMaxToExclusiveDateTo(effectiveFilter),
      ratingFrom: ratingFrom,
      ratingTo: ratingTo,
      isOnline: _onlineToApi(effectiveFilter.online),
    );
  } on DioException catch (e) {
    if (e.response?.statusCode == 404) {
      final refreshedId = await _resolveTwicPlayerId(
        ref,
        playerKey,
        preferProvidedId: false,
      );
      if (refreshedId != null &&
          refreshedId.isNotEmpty &&
          refreshedId != playerId) {
        ref.invalidate(twicPlayerIdProvider(playerKey));
        try {
          response = await repo.getPlayerStats(
            playerId: refreshedId,
            q: searchQuery.isNotEmpty ? searchQuery : null,
            color: color,
            timeControl: timeControl,
            outcome: outcome,
            eco:
                request.scope == TwicStatsScope.filteredIgnoringEco
                    ? null
                    : eco,
            dateFrom: _yearMinToDateFrom(effectiveFilter),
            dateTo: _yearMaxToExclusiveDateTo(effectiveFilter),
            ratingFrom: ratingFrom,
            ratingTo: ratingTo,
            isOnline: _onlineToApi(effectiveFilter.online),
          );
        } on DioException catch (retryError) {
          if (retryError.response?.statusCode == 404) {
            return fallbackFromLoadedGames();
          }
          rethrow;
        }
      } else {
        return fallbackFromLoadedGames();
      }
    } else {
      rethrow;
    }
  }

  final payload = response['data'];
  if (payload is! Map) return null;
  final data = Map<String, dynamic>.from(payload);

  int asInt(dynamic v) => (v as num?)?.toInt() ?? 0;

  final totals = Map<String, dynamic>.from(data['totals'] as Map? ?? const {});
  final colorData = Map<String, dynamic>.from(
    data['color'] as Map? ?? const {},
  );
  final white = Map<String, dynamic>.from(
    colorData['white'] as Map? ?? const {},
  );
  final black = Map<String, dynamic>.from(
    colorData['black'] as Map? ?? const {},
  );
  final openings = Map<String, dynamic>.from(
    data['openings'] as Map? ?? const {},
  );

  List<OpeningStatistic> parseOpeningList(dynamic rawList) {
    if (rawList is! List) return const [];
    final stats = <OpeningStatistic>[];
    for (final item in rawList) {
      if (item is! Map) continue;
      final row = Map<String, dynamic>.from(item);
      final ecoCode = (row['eco']?.toString().trim() ?? '');
      if (ecoCode.isEmpty) continue;
      stats.add(
        OpeningStatistic(
          eco: ecoCode,
          openingName: row['openingName']?.toString(),
          count: asInt(row['games']),
          wins: asInt(row['wins']),
          draws: asInt(row['draws']),
          losses: asInt(row['losses']),
        ),
      );
    }
    return stats;
  }

  return PlayerAnalytics(
    openingStats: parseOpeningList(openings['all']),
    openingStatsWhite: parseOpeningList(openings['white']),
    openingStatsBlack: parseOpeningList(openings['black']),
    colorStats: ColorStatistics(
      whiteGames: asInt(white['games']),
      whiteWins: asInt(white['wins']),
      whiteDraws: asInt(white['draws']),
      whiteLosses: asInt(white['losses']),
      blackGames: asInt(black['games']),
      blackWins: asInt(black['wins']),
      blackDraws: asInt(black['draws']),
      blackLosses: asInt(black['losses']),
    ),
    resultStats: ResultStatistics(
      totalGames: asInt(totals['games']),
      wins: asInt(totals['wins']),
      draws: asInt(totals['draws']),
      losses: asInt(totals['losses']),
    ),
    recentForm: const [],
    avgOpponentRating: asInt(data['avgOpponentRating']),
  );
});

/// Notifier for player profile games state
class _TwicGamesPageResult {
  const _TwicGamesPageResult({
    required this.games,
    required this.hasMore,
    required this.nextPageNumber,
    this.totalCount,
  });

  final List<GamesTourModel> games;
  final bool hasMore;
  final int nextPageNumber;
  final int? totalCount;
}

class PlayerProfileGamesNotifier
    extends StateNotifier<PlayerProfileGamesState> {
  PlayerProfileGamesNotifier(this._ref, this._playerKey)
    : super(PlayerProfileGamesState(playerKey: _playerKey)) {
    _loadGames();
  }

  final Ref _ref;
  final PlayerProfileKey _playerKey;
  int _loadToken = 0;
  static const int _supabasePageSize = 1000;
  static const int _twicPageSize = 60;
  List<GamesTourModel>? _globalSearchFallbackCache;

  List<GamesTourModel> _mergeGames(
    List<GamesTourModel> base,
    List<GamesTourModel> incoming,
  ) {
    final merged = <String, GamesTourModel>{};
    for (final game in base) {
      merged[game.gameId] = game;
    }
    for (final game in incoming) {
      merged[game.gameId] = game;
    }
    return merged.values.toList(growable: false);
  }

  Future<List<Games>> _loadAllSupabaseGames(GameRepository gameRepo) async {
    final seenIds = <String>{};
    final allGames = <Games>[];

    for (var page = 0; page < 200; page++) {
      final offset = page * _supabasePageSize;
      final batch =
          _playerKey.hasFideId
              ? await gameRepo.getGamesByFideIdPaginated(
                _playerKey.fideId.toString(),
                limit: _supabasePageSize,
                offset: offset,
              )
              : await gameRepo.getGamesByPlayerNamePaginated(
                _playerKey.playerName,
                limit: _supabasePageSize,
                offset: offset,
              );

      if (batch.isEmpty) break;

      final before = seenIds.length;
      for (final game in batch) {
        if (seenIds.add(game.id)) {
          allGames.add(game);
        }
      }

      if (batch.length < _supabasePageSize || seenIds.length == before) {
        break;
      }
    }

    return allGames;
  }

  Future<void> _loadGames() async {
    final token = ++_loadToken;
    _globalSearchFallbackCache = null;
    state = state.copyWith(
      isLoading: true,
      isLoadingMore: false,
      hasMorePages: false,
      nextPageNumber: 0,
      totalCount: null,
      error: null,
      allGames:
          _playerKey.source == PlayerProfileDataSource.twic ? const [] : null,
    );

    try {
      List<GamesTourModel> allGames;
      bool hasMorePages = false;
      int nextPageNumber = 0;
      int? totalCount;

      if (_playerKey.source == PlayerProfileDataSource.twic) {
        final page = await _loadTwicGamesFilteredPage(
          pageNumber: 0,
          pageSize: _twicPageSize,
        );
        allGames = page.games;
        hasMorePages = page.hasMore;
        nextPageNumber = page.nextPageNumber;
        totalCount = page.totalCount;
      } else {
        final gameRepo = _ref.read(gameRepositoryProvider);
        final games = await _loadAllSupabaseGames(gameRepo);

        allGames =
            games
                .map((game) => GamesTourModel.fromGame(game))
                .where((game) => !_isVariantEvent(game.tourSlug))
                .toList();
        totalCount = allGames.length;
      }

      // Sort by date descending
      final epochFallback = DateTime.fromMillisecondsSinceEpoch(0);
      allGames.sort((a, b) {
        final aTime = a.lastMoveTime ?? epochFallback;
        final bTime = b.lastMoveTime ?? epochFallback;
        return bTime.compareTo(aTime);
      });

      if (!mounted || token != _loadToken) return;
      state = state.copyWith(
        allGames: allGames,
        isLoading: false,
        hasMorePages: hasMorePages,
        nextPageNumber: nextPageNumber,
        totalCount: totalCount,
      );
    } catch (e) {
      if (!mounted || token != _loadToken) return;
      state = state.copyWith(
        error: e.toString(),
        isLoading: false,
        isLoadingMore: false,
      );
    }
  }

  // ---------------------------------------------------------------------------
  // TWIC: Pure server-side filtered loading
  // ---------------------------------------------------------------------------

  Future<_TwicGamesPageResult> _loadTwicGamesFilteredPage({
    required int pageNumber,
    required int pageSize,
  }) async {
    final repo = _ref.read(gamebaseRepositoryProvider);
    final pid = await _ref.read(twicPlayerIdProvider(_playerKey).future);

    if (pid != null && pid.isNotEmpty) {
      try {
        return _fetchViaPlayerGamesEndpointPage(
          repo,
          pid,
          pageNumber: pageNumber,
          pageSize: pageSize,
        );
      } on DioException catch (e) {
        if (e.response?.statusCode != 404) rethrow;
        final refreshed = await _resolveTwicPlayerId(
          _ref,
          _playerKey,
          preferProvidedId: false,
        );
        if (refreshed != null && refreshed.isNotEmpty && refreshed != pid) {
          _ref.invalidate(twicPlayerIdProvider(_playerKey));
          return _fetchViaPlayerGamesEndpointPage(
            repo,
            refreshed,
            pageNumber: pageNumber,
            pageSize: pageSize,
          );
        }
      }
    }
    return _fetchViaGlobalSearchPage(
      repo,
      pageNumber: pageNumber,
      pageSize: pageSize,
    );
  }

  /// Path A: Has gamebasePlayerId → GET /api/player/{id}/games with filters.
  Future<_TwicGamesPageResult> _fetchViaPlayerGamesEndpointPage(
    GamebaseRepository repo,
    String playerId, {
    required int pageNumber,
    required int pageSize,
  }) async {
    final effectiveFilter = playerProfileEffectiveFilter(state.filter);
    final color = _colorToApi(effectiveFilter.color) ?? 'all';
    final timeControl = _timeControlToApi(effectiveFilter.timeControl);
    final eco = effectiveFilter.eco.isAll ? null : effectiveFilter.eco.code;
    final outcome = _resolvePlayerOutcome(
      playerResultFilter: state.playerResultFilter,
      resultFilter: effectiveFilter.result,
      colorFilter: effectiveFilter.color,
    );

    // Year UI is inclusive; backend dateTo is exclusive.
    final dateFrom = _yearMinToDateFrom(effectiveFilter);
    final dateTo = _yearMaxToExclusiveDateTo(effectiveFilter);

    final ratingFrom =
        effectiveFilter.minRating != GameFilter.absoluteMinRating
            ? effectiveFilter.minRating
            : null;
    final ratingTo =
        effectiveFilter.maxRating != GameFilter.absoluteMaxRating
            ? effectiveFilter.maxRating
            : null;

    final response = await repo.getPlayerGames(
      playerId: playerId,
      q: state.searchQuery.trim().isNotEmpty ? state.searchQuery.trim() : null,
      color: color,
      timeControl: timeControl,
      outcome: outcome,
      eco: eco,
      opening: null,
      variation: null,
      dateFrom: dateFrom,
      dateTo: dateTo,
      ratingFrom: ratingFrom,
      ratingTo: ratingTo,
      isOnline: _onlineToApi(effectiveFilter.online),
      pageNumber: pageNumber,
      pageSize: pageSize,
    );

    final rows = <Map<String, dynamic>>[];
    final data = response['data'];
    if (data is List) {
      for (final item in data.whereType<Map>()) {
        rows.add(Map<String, dynamic>.from(item));
      }
    }

    final metadata = response['metadata'];
    final hasMore = metadata is Map ? (metadata['hasMore'] == true) : false;
    final totalCount =
        metadata is Map ? (metadata['totalCount'] as num?)?.toInt() : null;

    final gamebasePlayersById = await _fetchGamebasePlayersByIds(rows, repo);
    var games = rows
        .map((row) => _gamePreviewRowToModel(row, gamebasePlayersById))
        .toList(growable: false);
    final fideIds = collectFideIdsFromGames(games);
    if (fideIds.isNotEmpty) {
      final playersByFideId = await _ref
          .read(chessPlayerRepositoryProvider)
          .getPlayersByFideIds(fideIds);
      games = enrichGamesWithChessPlayers(games, playersByFideId);
    }
    return _TwicGamesPageResult(
      games: games,
      hasMore: hasMore,
      nextPageNumber: pageNumber + 1,
      totalCount: totalCount,
    );
  }

  Future<_TwicGamesPageResult> _fetchViaGlobalSearchPage(
    GamebaseRepository repo, {
    required int pageNumber,
    required int pageSize,
  }) async {
    final cached = _globalSearchFallbackCache;
    if (cached == null) {
      _globalSearchFallbackCache = await _fetchViaGlobalSearch(repo);
    }
    final all = _globalSearchFallbackCache ?? const <GamesTourModel>[];
    if (all.isEmpty) {
      return const _TwicGamesPageResult(
        games: [],
        hasMore: false,
        nextPageNumber: 0,
        totalCount: 0,
      );
    }

    final start = pageNumber * pageSize;
    if (start >= all.length) {
      return _TwicGamesPageResult(
        games: const [],
        hasMore: false,
        nextPageNumber: pageNumber + 1,
        totalCount: all.length,
      );
    }
    final end = (start + pageSize).clamp(0, all.length).toInt();
    final hasMore = end < all.length;

    return _TwicGamesPageResult(
      games: all.sublist(start, end),
      hasMore: hasMore,
      nextPageNumber: pageNumber + 1,
      totalCount: all.length,
    );
  }

  /// Path B: No gamebasePlayerId → globalSearch fallback with filters.
  Future<List<GamesTourModel>> _fetchViaGlobalSearch(
    GamebaseRepository repo,
  ) async {
    final playerName = _playerKey.playerName.trim();
    if (playerName.isEmpty) return const [];

    final effectiveFilter = playerProfileEffectiveFilter(state.filter);

    final escapedPlayerName = playerName.replaceAll('"', r'\"');
    var searchQuery = 'player:"$escapedPlayerName"';

    final extraSearchQuery = state.searchQuery.trim();
    if (extraSearchQuery.isNotEmpty) {
      searchQuery = '$searchQuery $extraSearchQuery';
    }

    // Append ECO fielded token if active
    if (!effectiveFilter.eco.isAll && effectiveFilter.eco.code != null) {
      searchQuery = '$searchQuery eco:${effectiveFilter.eco.code}';
    }

    final result = _gameFilterResultToApi(effectiveFilter.result);
    final color = _colorToApi(effectiveFilter.color);
    final timeControl = _timeControlToApi(effectiveFilter.timeControl);
    final yearFrom =
        effectiveFilter.minYear != GameFilter.absoluteMinYear
            ? effectiveFilter.minYear
            : null;
    final yearTo =
        effectiveFilter.maxYear != DateTime.now().year
            ? effectiveFilter.maxYear
            : null;
    final ratingFrom =
        effectiveFilter.minRating != GameFilter.absoluteMinRating
            ? effectiveFilter.minRating
            : null;
    final ratingTo =
        effectiveFilter.maxRating != GameFilter.absoluteMaxRating
            ? effectiveFilter.maxRating
            : null;

    final playerId = _playerKey.gamebasePlayerId?.trim();
    final fideIdStr =
        _playerKey.hasFideId ? _playerKey.fideId.toString() : null;
    final rows = <Map<String, dynamic>>[];
    var page = 1;
    while (true) {
      final response = await repo.globalSearch(
        query: searchQuery,
        resources: const ['game'],
        pageNumber: page,
        pageSize: 100,
        result: result,
        color: color,
        timeControl: timeControl,
        yearFrom: yearFrom,
        yearTo: yearTo,
        ratingFrom: ratingFrom,
        ratingTo: ratingTo,
        isOnline: _onlineToApi(effectiveFilter.online),
      );

      final pageRows = response.results
          .where((r) => r.resource == 'game')
          .map((r) {
            final preview = r.preview ?? const <String, dynamic>{};
            final id = (preview['id']?.toString() ?? r.id).trim();
            return <String, dynamic>{'id': id, ...preview};
          })
          .where((row) {
            if (playerId != null && playerId.isNotEmpty) {
              final w = row['whitePlayerId']?.toString().trim();
              final b = row['blackPlayerId']?.toString().trim();
              if (w == playerId || b == playerId) return true;
            }
            if (fideIdStr != null) {
              final wFide = row['whiteFideId']?.toString();
              final bFide = row['blackFideId']?.toString();
              if (wFide == fideIdStr || bFide == fideIdStr) return true;
            }
            final white =
                (row['white']?.toString() ??
                    row['whiteName']?.toString() ??
                    '');
            final black =
                (row['black']?.toString() ??
                    row['blackName']?.toString() ??
                    '');
            return _gamebaseNameMatches(white, playerName) ||
                _gamebaseNameMatches(black, playerName);
          })
          .toList(growable: false);
      rows.addAll(pageRows);

      if (!response.metadata.hasMore) break;
      if (response.results.isEmpty) break;
      page += 1;
      if (page > 200) break;
    }

    final gamebasePlayersById = await _fetchGamebasePlayersByIds(rows, repo);
    var games = rows
        .map((row) => _globalSearchRowToModel(row, gamebasePlayersById))
        .toList(growable: false);
    final fideIds = collectFideIdsFromGames(games);
    if (fideIds.isNotEmpty) {
      final playersByFideId = await _ref
          .read(chessPlayerRepositoryProvider)
          .getPlayersByFideIds(fideIds);
      games = enrichGamesWithChessPlayers(games, playersByFideId);
    }
    return games;
  }

  // ---------------------------------------------------------------------------
  // Row → GamesTourModel converters
  // ---------------------------------------------------------------------------

  /// Convert a player-games endpoint row to GamesTourModel.
  GamesTourModel _gamePreviewRowToModel(
    Map<String, dynamic> row, [
    Map<String, GamebasePlayer> gamebasePlayersById = const {},
  ]) {
    final id = (row['id']?.toString().trim());
    final safeId = (id != null && id.isNotEmpty) ? id : 'unknown';
    final result = row['result']?.toString() ?? '*';
    final timeControl = row['timeControl']?.toString();
    final date = _parseDate(row['date']);
    final eco = row['eco']?.toString();
    final opening = row['opening']?.toString();
    final variation = row['variation']?.toString();
    final event = (row['event']?.toString() ?? 'Gamebase').trim();

    final whiteName =
        (row['white']?.toString() ?? row['whiteName']?.toString() ?? 'White')
            .trim();
    final blackName =
        (row['black']?.toString() ?? row['blackName']?.toString() ?? 'Black')
            .trim();

    final whitePlayerId = row['whitePlayerId']?.toString().trim();
    final blackPlayerId = row['blackPlayerId']?.toString().trim();
    final whitePlayer =
        (whitePlayerId != null && whitePlayerId.isNotEmpty)
            ? gamebasePlayersById[whitePlayerId]
            : null;
    final blackPlayer =
        (blackPlayerId != null && blackPlayerId.isNotEmpty)
            ? gamebasePlayersById[blackPlayerId]
            : null;
    final rowFen =
        row['fen']?.toString() ??
        row['finalFen']?.toString() ??
        row['positionFen']?.toString();
    final rowLastMove = row['lastMove']?.toString();
    final rowSite = row['site']?.toString();
    final whiteEloRaw = (row['whiteElo'] as num?)?.toInt() ?? 0;
    final blackEloRaw = (row['blackElo'] as num?)?.toInt() ?? 0;

    // TWIC broadcast games carry a per-pairing label in `event`
    // ("Round 6: A - B") and the real parent event only in the `site` Lichess
    // broadcast slug. Recover the canonical event name (same logic the other
    // TWIC builders + library use) so cards show the event, not the round, and
    // games group under one event instead of one-per-pairing.
    final canonicalEvent = preferredTwicEventTitle(
      pgnEvent: event,
      tourSlug: row['tourSlug']?.toString(),
      tourId: row['tour_id']?.toString() ?? row['tournament_id']?.toString(),
      site: rowSite,
      fallback: event.isNotEmpty ? event : 'Gamebase',
    );
    final canonicalTourId =
        (row['tour_id']?.toString() ??
                row['tournament_id']?.toString() ??
                canonicalEvent)
            .trim();

    final pgn = buildHeaderOnlyPgn(
      whiteName: whiteName,
      blackName: blackName,
      result: result,
      event: canonicalEvent,
      site: rowSite,
      date: date,
      eco: eco,
      opening: opening,
      variation: variation,
      fen: rowFen,
    );

    final whiteCard = PlayerCard(
      name: whiteName,
      federation: '',
      title: _normalizeTitle(row['whiteTitle'] ?? whitePlayer?.title),
      rating:
          whiteEloRaw > 0 ? whiteEloRaw : _ratingFor(whitePlayer, timeControl),
      countryCode:
          (row['whiteFed']?.toString().trim().isNotEmpty ?? false)
              ? row['whiteFed'].toString().trim()
              : (whitePlayer?.fed ?? ''),
      team: null,
      fideId:
          _parseFide(row['whiteFideId']) ??
          int.tryParse(whitePlayer?.fideId ?? ''),
      gamebasePlayerId:
          (whitePlayerId != null && whitePlayerId.isNotEmpty)
              ? whitePlayerId
              : whitePlayer?.id,
    );

    final blackCard = PlayerCard(
      name: blackName,
      federation: '',
      title: _normalizeTitle(row['blackTitle'] ?? blackPlayer?.title),
      rating:
          blackEloRaw > 0 ? blackEloRaw : _ratingFor(blackPlayer, timeControl),
      countryCode:
          (row['blackFed']?.toString().trim().isNotEmpty ?? false)
              ? row['blackFed'].toString().trim()
              : (blackPlayer?.fed ?? ''),
      team: null,
      fideId:
          _parseFide(row['blackFideId']) ??
          int.tryParse(blackPlayer?.fideId ?? ''),
      gamebasePlayerId:
          (blackPlayerId != null && blackPlayerId.isNotEmpty)
              ? blackPlayerId
              : blackPlayer?.id,
    );

    return GamesTourModel(
      gameId: safeId,
      source: GameSource.twic,
      whitePlayer: whiteCard,
      blackPlayer: blackCard,
      whiteTimeDisplay: '--:--',
      blackTimeDisplay: '--:--',
      whiteClockCentiseconds: 0,
      blackClockCentiseconds: 0,
      gameStatus: GameStatus.fromString(result),
      roundId: 'twic_profile',
      roundSlug:
          (eco != null && eco.trim().isNotEmpty)
              ? eco.trim()
              : (timeControl ?? ''),
      tourId: canonicalTourId.isNotEmpty ? canonicalTourId : canonicalEvent,
      tourSlug: canonicalEvent,
      lastMove: rowLastMove,
      fen: rowFen,
      pgn: pgn,
      lastMoveTime: date,
      eco: (eco != null && eco.trim().isNotEmpty) ? eco.trim() : null,
      openingName:
          (opening != null && opening.trim().isNotEmpty)
              ? opening.trim()
              : null,
      timeControl: timeControl,
      isOnline: row['isOnline'] == true,
    );
  }

  /// Convert a globalSearch row to GamesTourModel (same as existing _getTwicGamesFromGamebase).
  GamesTourModel _globalSearchRowToModel(
    Map<String, dynamic> row, [
    Map<String, GamebasePlayer> gamebasePlayersById = const {},
  ]) {
    return _gamePreviewRowToModel(row, gamebasePlayersById);
  }

  static DateTime? _parseDate(Object? raw) {
    if (raw == null) return null;
    return DateTime.tryParse(raw.toString());
  }

  static int? _parseFide(Object? raw) {
    if (raw == null) return null;
    return int.tryParse(raw.toString());
  }

  static String _normalizeTitle(Object? raw) {
    final text = raw?.toString();
    if (text == null || text.trim().isEmpty) return '';
    return ChessTitleUtils.normalize(text);
  }

  Future<Map<String, GamebasePlayer>> _fetchGamebasePlayersByIds(
    Iterable<Map<String, dynamic>> rows,
    GamebaseRepository repo,
  ) async {
    final ids = <String>{};
    for (final row in rows) {
      final w = row['whitePlayerId']?.toString().trim();
      final b = row['blackPlayerId']?.toString().trim();
      if (w != null && w.isNotEmpty) ids.add(w);
      if (b != null && b.isNotEmpty) ids.add(b);
    }
    if (ids.isEmpty) return const {};

    final fetched = await Future.wait(
      ids.map(repo.getPlayerById),
      eagerError: false,
    );
    final byId = <String, GamebasePlayer>{};
    for (final player in fetched.whereType<GamebasePlayer>()) {
      byId[player.id] = player;
    }
    return byId;
  }

  static int _ratingFor(GamebasePlayer? player, String? timeControl) {
    if (player == null) return 0;
    final tc = (timeControl ?? '').toUpperCase();
    switch (tc) {
      case 'RAPID':
        return player.ratingRapid ?? player.highestRating ?? 0;
      case 'BLITZ':
        return player.ratingBlitz ?? player.highestRating ?? 0;
      case 'CLASSICAL':
      default:
        return player.ratingClassical ?? player.highestRating ?? 0;
    }
  }

  Future<void> loadMore() async {
    if (_playerKey.source != PlayerProfileDataSource.twic) return;
    if (state.isLoading || state.isLoadingMore || !state.hasMorePages) return;

    final token = _loadToken;
    state = state.copyWith(isLoadingMore: true, error: null);
    try {
      final page = await _loadTwicGamesFilteredPage(
        pageNumber: state.nextPageNumber,
        pageSize: _twicPageSize,
      );
      if (!mounted || token != _loadToken) return;

      final merged = _mergeGames(state.allGames, page.games);
      state = state.copyWith(
        allGames: merged,
        isLoadingMore: false,
        hasMorePages: page.hasMore,
        nextPageNumber: page.nextPageNumber,
        totalCount: page.totalCount ?? state.totalCount,
      );
    } catch (e) {
      if (!mounted || token != _loadToken) return;
      state = state.copyWith(
        isLoadingMore: false,
        error: state.allGames.isEmpty ? e.toString() : state.error,
      );
    }
  }

  /// Loads all remaining TWIC pages for the current filter/search state.
  /// Returns the final loaded game count in memory.
  Future<int> loadAllRemainingPages({int maxPages = 250}) async {
    if (_playerKey.source != PlayerProfileDataSource.twic) {
      return state.allGames.length;
    }

    var pages = 0;
    var previousCount = state.allGames.length;

    while (mounted &&
        state.hasMorePages &&
        pages < maxPages &&
        !state.isLoading &&
        !state.isLoadingMore) {
      await loadMore();
      pages += 1;
      final currentCount = state.allGames.length;
      if (currentCount <= previousCount) {
        // Defensive break to avoid spinning if backend pagination stalls.
        break;
      }
      previousCount = currentCount;
    }

    return state.allGames.length;
  }

  void applyFilter(GameFilter filter) {
    state = state.copyWith(filter: filter);
    if (_playerKey.source == PlayerProfileDataSource.twic) _loadGames();
  }

  /// Update only the time control filter, preserving other filter settings
  void setTimeControlFilter(GameTimeControlFilter timeControl) {
    state = state.copyWith(
      filter: state.filter.copyWith(timeControl: timeControl),
    );
    if (_playerKey.source == PlayerProfileDataSource.twic) _loadGames();
  }

  /// Update only the color filter, preserving other filter settings
  void setColorFilter(GameColorFilter color) {
    state = state.copyWith(filter: state.filter.copyWith(color: color));
    if (_playerKey.source == PlayerProfileDataSource.twic) _loadGames();
  }

  /// Update only the ECO filter, preserving other filter settings
  void setEcoFilter(GameEcoFilter eco) {
    state = state.copyWith(filter: state.filter.copyWith(eco: eco));
    if (_playerKey.source == PlayerProfileDataSource.twic) _loadGames();
  }

  /// Update only the result filter, preserving other filter settings
  void setResultFilter(GameResultFilter result) {
    state = state.copyWith(filter: state.filter.copyWith(result: result));
    if (_playerKey.source == PlayerProfileDataSource.twic) _loadGames();
  }

  /// Merge a partial filter update with existing filter state
  void mergeFilter({
    GameTimeControlFilter? timeControl,
    GameColorFilter? color,
    GameEcoFilter? eco,
    GameOnlineFilter? online,
    GameResultFilter? result,
    PlayerResultFilter? playerResultFilter,
    String? searchQuery,
  }) {
    final newFilter = state.filter.copyWith(
      timeControl: timeControl,
      color: color,
      eco: eco,
      online: online,
      result: result,
    );
    state = state.copyWith(
      filter: newFilter,
      playerResultFilter: playerResultFilter ?? state.playerResultFilter,
      searchQuery: searchQuery ?? state.searchQuery,
    );
    if (_playerKey.source == PlayerProfileDataSource.twic) _loadGames();
  }

  void clearFilter() {
    state = state.copyWith(
      filter: GameFilter.defaultFilter(),
      playerResultFilter: PlayerResultFilter.all,
      searchQuery: '',
    );
    if (_playerKey.source == PlayerProfileDataSource.twic) _loadGames();
  }

  void setSearchQuery(String query) {
    if (state.searchQuery == query) return;
    state = state.copyWith(searchQuery: query);
    if (_playerKey.source != PlayerProfileDataSource.twic) return;
    _loadGames();
  }

  void setPlayerResultFilter(PlayerResultFilter filter) {
    state = state.copyWith(playerResultFilter: filter);
    if (_playerKey.source == PlayerProfileDataSource.twic) _loadGames();
  }

  Future<void> refresh() async {
    await _loadGames();
  }
}

/// Provider family for player profile games state using PlayerProfileKey
final playerProfileGamesKeyProvider = StateNotifierProvider.family.autoDispose<
  PlayerProfileGamesNotifier,
  PlayerProfileGamesState,
  PlayerProfileKey
>((ref, playerKey) => PlayerProfileGamesNotifier(ref, playerKey));

/// Legacy provider for backwards compatibility - uses fideId only
final playerProfileGamesProvider = StateNotifierProvider.family
    .autoDispose<PlayerProfileGamesNotifier, PlayerProfileGamesState, int>(
      (ref, fideId) => PlayerProfileGamesNotifier(
        ref,
        PlayerProfileKey(fideId: fideId, playerName: ''),
      ),
    );
