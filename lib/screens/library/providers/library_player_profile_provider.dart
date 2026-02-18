import 'package:chessever2/repository/gamebase/gamebase_repository.dart';
import 'package:chessever2/screens/gamebase/models/models.dart';
import 'package:chessever2/screens/library/utils/gamebase_pgn_builder.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/utils/chess_title_utils.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Key for identifying a player in the library player profile
class LibraryPlayerProfileKey {
  const LibraryPlayerProfileKey({
    this.fideId,
    required this.playerName,
    this.gamebasePlayerId,
  });

  final int? fideId;
  final String playerName;
  final String? gamebasePlayerId;

  bool get hasFideId => fideId != null && fideId! > 0;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is LibraryPlayerProfileKey &&
        other.fideId == fideId &&
        other.playerName == playerName &&
        other.gamebasePlayerId == gamebasePlayerId;
  }

  @override
  int get hashCode => Object.hash(fideId, playerName, gamebasePlayerId);
}

/// State for library player profile games
class LibraryPlayerGamesState {
  const LibraryPlayerGamesState({
    this.games = const [],
    this.isLoading = false,
    this.hasMore = true,
    this.currentPage = 1,
    this.error,
  });

  final List<GamesTourModel> games;
  final bool isLoading;
  final bool hasMore;
  final int currentPage;
  final String? error;

  LibraryPlayerGamesState copyWith({
    List<GamesTourModel>? games,
    bool? isLoading,
    bool? hasMore,
    int? currentPage,
    String? error,
  }) {
    return LibraryPlayerGamesState(
      games: games ?? this.games,
      isLoading: isLoading ?? this.isLoading,
      hasMore: hasMore ?? this.hasMore,
      currentPage: currentPage ?? this.currentPage,
      error: error,
    );
  }
}

/// Provider for library player profile games
/// Fetches from gamebase (historical chess database) only
final libraryPlayerGamesProvider = StateNotifierProvider.autoDispose.family<
    LibraryPlayerGamesNotifier, LibraryPlayerGamesState, LibraryPlayerProfileKey>(
  (ref, key) => LibraryPlayerGamesNotifier(ref, key),
);

class LibraryPlayerGamesNotifier extends StateNotifier<LibraryPlayerGamesState> {
  final Ref _ref;
  final LibraryPlayerProfileKey _playerKey;
  static const int _pageSize = 30;

  LibraryPlayerGamesNotifier(this._ref, this._playerKey)
      : super(const LibraryPlayerGamesState(isLoading: true)) {
    _loadInitialGames();
  }

  Future<void> _loadInitialGames() async {
    try {
      final games = await _fetchGamebaseGames(page: 1);
      if (!mounted) return;

      // Sort by date descending
      final epochFallback = DateTime.fromMillisecondsSinceEpoch(0);
      games.sort((a, b) {
        final aTime = a.lastMoveTime ?? epochFallback;
        final bTime = b.lastMoveTime ?? epochFallback;
        return bTime.compareTo(aTime);
      });

      state = state.copyWith(
        games: games,
        isLoading: false,
        hasMore: games.length >= _pageSize,
        currentPage: 1,
        error: null,
      );
    } catch (e, st) {
      debugPrint('[LibraryPlayerGames] Initial load error: $e');
      debugPrintStack(stackTrace: st, label: '[LibraryPlayerGames] Initial load');
      if (!mounted) return;
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> loadMoreGames() async {
    if (state.isLoading || !state.hasMore) return;

    state = state.copyWith(isLoading: true);

    try {
      final nextPage = state.currentPage + 1;
      final newGames = await _fetchGamebaseGames(page: nextPage);
      if (!mounted) return;

      state = state.copyWith(
        games: [...state.games, ...newGames],
        isLoading: false,
        hasMore: newGames.length >= _pageSize,
        currentPage: nextPage,
      );
    } catch (e, st) {
      debugPrint('[LibraryPlayerGames] Load more error: $e');
      debugPrintStack(stackTrace: st, label: '[LibraryPlayerGames] Load more');
      if (!mounted) return;
      state = state.copyWith(isLoading: false);
    }
  }

  Future<void> refreshGames() async {
    state = state.copyWith(isLoading: true, error: null);
    await _loadInitialGames();
  }

  /// Fetch games from Gamebase (historical chess database)
  /// Uses multiple search strategies to comprehensively find all games:
  /// 1. Search by player name (gamebase text search is optimized for names)
  /// 2. Filter results by gamebasePlayerId or FIDE ID when available
  Future<List<GamesTourModel>> _fetchGamebaseGames({required int page}) async {
    try {
      final repo = _ref.read(gamebaseRepositoryProvider);
      final playerName = _playerKey.playerName.trim();

      if (playerName.isEmpty) return [];

      // Always search by player name - gamebase text search is optimized for names
      // Searching by numeric FIDE ID often yields poor results
      debugPrint('[LibraryPlayerGames] Fetching gamebase games for: "$playerName", '
          'page=$page, gamebasePlayerId=${_playerKey.gamebasePlayerId}, '
          'fideId=${_playerKey.fideId}');

      // Fetch more results to compensate for filtering
      final fetchSize = (_pageSize * 4).clamp(40, 150);

      final response = await repo.globalSearch(
        query: playerName,
        resources: ['game'], // Only search for games
        pageNumber: page,
        pageSize: fetchSize,
      );

      final playerId = _playerKey.gamebasePlayerId;
      final fideIdStr = _playerKey.hasFideId ? _playerKey.fideId.toString() : null;

      // Filter and extract game rows
      final rows = response.results
          .where((r) => r.resource == 'game')
          .map((r) {
            final preview = r.preview ?? const <String, dynamic>{};
            final id = preview['id']?.toString() ?? r.id;
            return <String, dynamic>{'id': id, ...preview};
          })
          .where((row) {
            // If we have a gamebase player ID, strictly filter by it
            if (playerId != null && playerId.isNotEmpty) {
              final w = row['whitePlayerId']?.toString();
              final b = row['blackPlayerId']?.toString();
              return w == playerId || b == playerId;
            }
            // If we have a FIDE ID, try to match by white/black FIDE IDs
            if (fideIdStr != null) {
              final wFideId = row['whiteFideId']?.toString();
              final bFideId = row['blackFideId']?.toString();
              if (wFideId == fideIdStr || bFideId == fideIdStr) {
                return true;
              }
            }
            // Fallback: match by player name in white/black fields
            final normalizedSearch = _normalizeNameForSearch(playerName);
            final whiteName = _normalizeNameForSearch(
              row['white']?.toString() ?? row['whiteName']?.toString() ?? '',
            );
            final blackName = _normalizeNameForSearch(
              row['black']?.toString() ?? row['blackName']?.toString() ?? '',
            );
            return whiteName.contains(normalizedSearch) ||
                blackName.contains(normalizedSearch) ||
                normalizedSearch.contains(whiteName) ||
                normalizedSearch.contains(blackName);
          })
          .take(_pageSize)
          .toList(growable: false);

      // Enrich with player details
      final playerIds = <String>{};
      for (final row in rows) {
        final w = row['whitePlayerId']?.toString().trim();
        final b = row['blackPlayerId']?.toString().trim();
        if (w != null && w.isNotEmpty) playerIds.add(w);
        if (b != null && b.isNotEmpty) playerIds.add(b);
      }

      final byId = <String, GamebasePlayer>{};
      if (playerIds.isNotEmpty) {
        debugPrint('[LibraryPlayerGames] Enriching ${playerIds.length} player IDs');
        final fetched = await Future.wait(
          playerIds.map((id) async {
            try {
              return await repo.getPlayerById(id);
            } catch (e) {
              debugPrint('[LibraryPlayerGames] Failed to fetch player $id: $e');
              return null;
            }
          }),
          eagerError: false,
        );
        for (final p in fetched.whereType<GamebasePlayer>()) {
          byId[p.id] = GamebasePlayer(
            id: p.id,
            fideId: p.fideId,
            name: p.name,
            gender: p.gender,
            fed: p.fed,
            title: ChessTitleUtils.normalize(p.title),
            ratingClassical: p.ratingClassical,
            ratingRapid: p.ratingRapid,
            ratingBlitz: p.ratingBlitz,
          );
        }
      }

      final games = _convertGamebaseRows(rows, byId);
      debugPrint('[LibraryPlayerGames] Fetched ${games.length} gamebase games');
      return games;
    } catch (e, st) {
      debugPrint('[LibraryPlayerGames] Gamebase fetch error: $e');
      debugPrintStack(stackTrace: st, label: '[LibraryPlayerGames] Gamebase fetch');
      return [];
    }
  }

  /// Convert gamebase row data to GamesTourModel
  List<GamesTourModel> _convertGamebaseRows(
    List<Map<String, dynamic>> rows,
    Map<String, GamebasePlayer> byId,
  ) {
    int ratingFor(GamebasePlayer? p, String? timeControl) {
      if (p == null) return 0;
      final tc = (timeControl ?? '').toUpperCase();
      switch (tc) {
        case 'RAPID':
          return p.ratingRapid ?? p.highestRating ?? 0;
        case 'BLITZ':
          return p.ratingBlitz ?? p.highestRating ?? 0;
        case 'CLASSICAL':
        default:
          return p.ratingClassical ?? p.highestRating ?? 0;
      }
    }

    DateTime? parseDate(Object? raw) {
      if (raw == null) return null;
      return DateTime.tryParse(raw.toString());
    }

    return rows.map((row) {
      final id = row['id']?.toString() ?? 'unknown';
      final result = row['result']?.toString() ?? '*';
      final timeControl = row['timeControl']?.toString();
      final date = parseDate(row['date']);

      final whiteName =
          (row['white']?.toString() ?? row['whiteName']?.toString() ?? 'White')
              .trim();
      final blackName =
          (row['black']?.toString() ?? row['blackName']?.toString() ?? 'Black')
              .trim();
      final event = (row['event']?.toString() ?? 'Gamebase').trim();
      final site = row['site']?.toString();
      final eco = row['eco']?.toString();
      final opening = row['opening']?.toString();
      final variation = row['variation']?.toString();

      final w = byId[row['whitePlayerId']?.toString() ?? ''];
      final b = byId[row['blackPlayerId']?.toString() ?? ''];

      final pgn = buildHeaderOnlyPgn(
        whiteName: whiteName,
        blackName: blackName,
        result: result,
        event: event,
        site: site,
        date: date,
        eco: eco,
        opening: opening,
        variation: variation,
      );

      final whiteCard = PlayerCard(
        name: whiteName,
        federation: '',
        title: ChessTitleUtils.normalize(w?.title),
        rating: ratingFor(w, timeControl),
        countryCode: w?.fed ?? '',
        team: null,
        fideId: int.tryParse(w?.fideId ?? ''),
      );
      final blackCard = PlayerCard(
        name: blackName,
        federation: '',
        title: ChessTitleUtils.normalize(b?.title),
        rating: ratingFor(b, timeControl),
        countryCode: b?.fed ?? '',
        team: null,
        fideId: int.tryParse(b?.fideId ?? ''),
      );

      final formatCode = (eco != null && eco.trim().isNotEmpty)
          ? eco.trim()
          : (timeControl ?? '');

      return GamesTourModel(
        gameId: id,
        whitePlayer: whiteCard,
        blackPlayer: blackCard,
        whiteTimeDisplay: '--:--',
        blackTimeDisplay: '--:--',
        whiteClockCentiseconds: 0,
        blackClockCentiseconds: 0,
        gameStatus: GameStatus.fromString(result),
        roundId: 'gamebase_library',
        roundSlug: formatCode.isNotEmpty ? formatCode : null,
        tourId: event.isNotEmpty ? event : 'Gamebase',
        pgn: pgn,
        lastMoveTime: date,
      );
    }).toList(growable: false);
  }

  /// Normalize player name for search matching
  /// Handles various name formats: "Last, First" or "First Last"
  String _normalizeNameForSearch(String name) {
    return name
        .toLowerCase()
        .replaceAll(',', ' ')
        .replaceAll('.', '')
        .replaceAll('-', ' ')
        .split(' ')
        .where((s) => s.isNotEmpty)
        .join(' ')
        .trim();
  }
}
