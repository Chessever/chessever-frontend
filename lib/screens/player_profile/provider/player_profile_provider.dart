import 'package:chessever2/repository/supabase/game/game_repository.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/widgets/game_filter/game_filter_model.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
  });

  final String tourId;
  final String tourName;
  final String? tourSlug;
  final int gamesPlayed;
  final double? score;
  final DateTime? startDate;
  final DateTime? endDate;
}

/// Provider to fetch basic player profile from chess_players table
final playerProfileDataProvider = FutureProvider.family
    .autoDispose<PlayerProfileData?, int>((ref, fideId) async {
  try {
    final supabase = Supabase.instance.client;

    // Fetch from chess_players table
    final response = await supabase
        .from('chess_players')
        .select()
        .eq('fideid', fideId)
        .maybeSingle();

    if (response == null) return null;

    // Handle birthday as int (year) and convert to string
    final birthdayInt = response['birthday'] as int?;
    final birthdayStr = birthdayInt != null ? birthdayInt.toString() : null;

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

    final allGames = games.map((game) => GamesTourModel.fromGame(game)).toList();

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

/// Request for player analytics with fideId and name context
class PlayerAnalyticsRequest {
  final int fideId;
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
  int get hashCode => fideId.hashCode ^ playerName.hashCode ^ games.length.hashCode;
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
    required this.colorStats,
    required this.resultStats,
    required this.recentForm,
    required this.avgOpponentRating,
  });

  final List<OpeningStatistic> openingStats;
  final ColorStatistics colorStats;
  final ResultStatistics resultStats;
  final List<double> recentForm;
  final int avgOpponentRating;

  factory PlayerAnalytics.fromGames(
    List<GamesTourModel> games,
    int targetFideId,
    String targetPlayerName,
  ) {
    if (games.isEmpty) {
      return const PlayerAnalytics(
        openingStats: [],
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
    final openingMap = <String, Map<String, dynamic>>{};

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

    for (int i = 0; i < games.length; i++) {
      final game = games[i];
      final eco = game.eco ?? 'Unknown';

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
      final targetWon = (isTargetWhite && isWhiteWin) || (isTargetBlack && isBlackWin);
      final targetLost = (isTargetWhite && isBlackWin) || (isTargetBlack && isWhiteWin);
      final targetDrew = isDraw;

      // Get opponent
      final opponent = isTargetWhite ? game.blackPlayer : game.whitePlayer;

      // Only count completed games for statistics
      if (isCompleted) {
        // Update opening stats (from target player's perspective)
        if (!openingMap.containsKey(eco)) {
          openingMap[eco] = {
            'eco': eco,
            'openingName': game.openingName,
            'count': 0,
            'wins': 0,
            'draws': 0,
            'losses': 0,
          };
        }
        openingMap[eco]!['count'] = (openingMap[eco]!['count'] as int) + 1;

        if (targetWon) {
          openingMap[eco]!['wins'] = (openingMap[eco]!['wins'] as int) + 1;
          totalWins++;
          if (form.length < 10) form.add(1.0);
        } else if (targetLost) {
          openingMap[eco]!['losses'] = (openingMap[eco]!['losses'] as int) + 1;
          totalLosses++;
          if (form.length < 10) form.add(0.0);
        } else if (targetDrew) {
          openingMap[eco]!['draws'] = (openingMap[eco]!['draws'] as int) + 1;
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

    // Convert opening map to sorted list
    final openingStats = openingMap.entries.map((e) {
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

    // Sort by count descending
    openingStats.sort((a, b) => b.count.compareTo(a.count));

    return PlayerAnalytics(
      openingStats: openingStats.take(20).toList(),
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
      avgOpponentRating: ratingCount > 0 ? totalOpponentRating ~/ ratingCount : 0,
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
        .contains('players', '[{"fideId": $fideId}]')
        .order('date_start', ascending: false)
        .limit(500);

    if (response == null || (response as List).isEmpty) {
      return [];
    }

    // Group by tour_id and calculate stats
    final tourMap = <String, Map<String, dynamic>>{};
    for (final row in response) {
      final tourId = row['tour_id'] as String?;
      if (tourId == null) continue;

      if (!tourMap.containsKey(tourId)) {
        tourMap[tourId] = {
          'tour_id': tourId,
          'tour_slug': row['tour_slug'],
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
        final blackPlayer = players.length > 1 ? players[1] as Map<String, dynamic>? : null;
        final isWhite = whitePlayer?['fideId'] == fideId;
        final isBlack = blackPlayer?['fideId'] == fideId;

        if (isWhite || isBlack) {
          final isWhiteWin = status == 'whiteWins' || status == '1-0';
          final isBlackWin = status == 'blackWins' || status == '0-1';
          final isDraw = status == 'draw' || status == '1/2-1/2';

          if ((isWhite && isWhiteWin) || (isBlack && isBlackWin)) {
            tourMap[tourId]!['wins'] = (tourMap[tourId]!['wins'] as int) + 1;
          } else if ((isWhite && isBlackWin) || (isBlack && isWhiteWin)) {
            tourMap[tourId]!['losses'] = (tourMap[tourId]!['losses'] as int) + 1;
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

    if (toursResponse != null) {
      for (final tour in toursResponse as List) {
        final tourId = tour['id'] as String;
        tourDetails[tourId] = tour;
        final gbId = tour['group_broadcast_id'] as String?;
        if (gbId != null && gbId.isNotEmpty) {
          groupBroadcastIds.add(gbId);
        }
      }
    }

    // Fetch group_broadcast dates
    final groupBroadcastDates = <String, Map<String, DateTime?>>{};
    if (groupBroadcastIds.isNotEmpty) {
      final gbResponse = await supabase
          .from('group_broadcasts')
          .select('id, date_start, date_end')
          .inFilter('id', groupBroadcastIds.toList());

      if (gbResponse != null) {
        for (final gb in gbResponse as List) {
          final gbId = gb['id'] as String;
          groupBroadcastDates[gbId] = {
            'start': gb['date_start'] != null
                ? DateTime.tryParse(gb['date_start'] as String)
                : null,
            'end': gb['date_end'] != null
                ? DateTime.tryParse(gb['date_end'] as String)
                : null,
          };
        }
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

      events.add(PlayerEventData(
        tourId: tourId,
        tourName: tour?['name'] as String? ??
            data['tour_slug'] as String? ??
            'Unknown Tournament',
        tourSlug: tour?['slug'] as String? ?? data['tour_slug'] as String?,
        gamesPlayed: data['count'] as int,
        score: score,
        startDate: startDate,
        endDate: endDate,
      ));
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
class PlayerProfileGamesState {
  const PlayerProfileGamesState({
    this.allGames = const [],
    this.filter = const GameFilter(),
    this.isLoading = false,
    this.error,
    this.searchQuery = '',
  });

  final List<GamesTourModel> allGames;
  final GameFilter filter;
  final bool isLoading;
  final String? error;
  final String searchQuery;

  List<GamesTourModel> get filteredGames {
    var games = allGames;

    // Apply search query
    if (searchQuery.isNotEmpty) {
      final query = searchQuery.toLowerCase();
      games = games.where((game) {
        return game.whitePlayer.name.toLowerCase().contains(query) ||
            game.blackPlayer.name.toLowerCase().contains(query) ||
            (game.openingName?.toLowerCase().contains(query) ?? false) ||
            (game.eco?.toLowerCase().contains(query) ?? false);
      }).toList();
    }

    // Apply filter
    return GameFilterHelper.applyFilter(games, filter);
  }

  PlayerProfileGamesState copyWith({
    List<GamesTourModel>? allGames,
    GameFilter? filter,
    bool? isLoading,
    String? error,
    String? searchQuery,
  }) {
    return PlayerProfileGamesState(
      allGames: allGames ?? this.allGames,
      filter: filter ?? this.filter,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      searchQuery: searchQuery ?? this.searchQuery,
    );
  }
}

/// Notifier for player profile games state
class PlayerProfileGamesNotifier
    extends StateNotifier<PlayerProfileGamesState> {
  PlayerProfileGamesNotifier(this._ref, this._fideId)
      : super(const PlayerProfileGamesState()) {
    _loadGames();
  }

  final Ref _ref;
  final int _fideId;

  Future<void> _loadGames() async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      final gameRepo = _ref.read(gameRepositoryProvider);
      final games = await gameRepo.getGamesByFideId(
        _fideId.toString(),
        limit: 1000,
      );

      final allGames =
          games.map((game) => GamesTourModel.fromGame(game)).toList();

      // Sort by date descending
      final epochFallback = DateTime.fromMillisecondsSinceEpoch(0);
      allGames.sort((a, b) {
        final aTime = a.lastMoveTime ?? epochFallback;
        final bTime = b.lastMoveTime ?? epochFallback;
        return bTime.compareTo(aTime);
      });

      state = state.copyWith(allGames: allGames, isLoading: false);
    } catch (e) {
      state = state.copyWith(error: e.toString(), isLoading: false);
    }
  }

  void applyFilter(GameFilter filter) {
    state = state.copyWith(filter: filter);
  }

  void clearFilter() {
    state = state.copyWith(filter: GameFilter.defaultFilter());
  }

  void setSearchQuery(String query) {
    state = state.copyWith(searchQuery: query);
  }

  Future<void> refresh() async {
    await _loadGames();
  }
}

/// Provider family for player profile games state
final playerProfileGamesProvider = StateNotifierProvider.family
    .autoDispose<PlayerProfileGamesNotifier, PlayerProfileGamesState, int>(
  (ref, fideId) => PlayerProfileGamesNotifier(ref, fideId),
);
