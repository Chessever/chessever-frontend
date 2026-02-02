import 'dart:convert';

import 'package:chessever2/repository/sqlite/app_database.dart';

import 'chess_game.dart';
import 'chess_game_navigator.dart';

class ChessGameNavigatorStateManager {
  ChessGameNavigatorStateManager();

  static const _recentGamesKey = 'recent_game_states';
  static const _gameStatePrefix = 'gs:';
  static const _maxGames = 100;

  AppDatabase get _db => AppDatabase.instance;

  Future<void> saveState(ChessGameNavigatorState state) async {
    final recentGames = await _getRecentGames();
    recentGames.removeWhere((gameId) => gameId == state.game.gameId);
    recentGames.add(state.game.gameId);

    if (recentGames.length > _maxGames) {
      final oldestId = recentGames.removeAt(0);
      await _db.remove(_gameStatePrefix + oldestId);
    }

    final serialized = jsonEncode({
      'ts': DateTime.now().toIso8601String(),
      'g': state.game.toJson(),
      'p': state.movePointer,
    });

    await Future.wait([
      _db.setString(_gameStatePrefix + state.game.gameId, serialized),
      _db.setList(key: _recentGamesKey, items: recentGames),
    ]);
  }

  Future<ChessGameNavigatorState?> loadState(String gameId) async {
    final rawState = await _db.getString(_gameStatePrefix + gameId);
    if (rawState == null) {
      return null;
    }

    try {
      final json = jsonDecode(rawState) as Map<String, dynamic>;
      return ChessGameNavigatorState(
        game: ChessGame.fromJson((json['g'] as Map).cast<String, dynamic>()),
        movePointer: (json['p'] as List).cast<int>(),
      );
    } catch (_) {
      await _cleanupState(gameId);
      return null;
    }
  }

  Future<List<String>> _getRecentGames() async {
    return await _db.getList(key: _recentGamesKey);
  }

  Future<void> _cleanupState(String gameId) async {
    final recent = await _getRecentGames();
    recent.remove(gameId);
    await Future.wait([
      _db.remove(_gameStatePrefix + gameId),
      _db.setList(key: _recentGamesKey, items: recent),
    ]);
  }
}
