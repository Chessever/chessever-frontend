import 'dart:convert';
import 'package:chessever2/repository/local_storage/local_storage_repository.dart';
import 'package:chessever2/screens/chessboard/chessboard_with_analysis_screen/chess_game.dart';
import 'package:chessever2/screens/chessboard/chessboard_with_analysis_screen/chess_game_navigator.dart';

class ChessGameNavigatorStateManager {
  static const String kRecentGamesKey = 'recent_game_states';
  static const int kMaxGames = 100;

  final AppSharedPreferences storage;

  ChessGameNavigatorStateManager({required this.storage});

  Future<void> saveState(
    ChessGameNavigatorState state,
  ) async {
    final recentGames = await _getRecentGames();

    recentGames.removeWhere((gameId) => gameId == state.game.gameId);

    recentGames.add(state.game.gameId);

    if (recentGames.length > kMaxGames) {
      final oldestGameId = recentGames.removeAt(0);
      await storage.delete('gs:$oldestGameId'); // Clean up old game state
    }

    await Future.wait([
      storage.setString(
          'gs:${state.game.gameId}',
          jsonEncode({
            "ts": DateTime.now().toIso8601String(),
            "g": state.game.toJson(),
            "p": state.movePointer
          })),
      storage.setStringList(kRecentGamesKey, recentGames),
    ]);
  }

  Future<ChessGameNavigatorState?> loadState(String gameId) async {
    final stateStr = await storage.getString('gs:$gameId');

    if (stateStr == null) {
      return null;
    }

    try {
      final json = jsonDecode(stateStr);

      return ChessGameNavigatorState(
        game: ChessGame.fromJson(json['g']),
        movePointer: (json['p'] as List).cast<int>(),
      );
    } catch (e) {
      print('Error parsing game state: $e');

      await _cleanupState(gameId);

      return null;
    }
  }

  Future<List<String>> _getRecentGames() async {
    return await storage.getStringList(kRecentGamesKey);
  }

  Future<void> _cleanupState(String gameId) async {
    final recentGames = await _getRecentGames();
    recentGames.remove(gameId);
    await Future.wait([
      storage.delete('gs:$gameId'),
      storage.setStringList(kRecentGamesKey, recentGames),
    ]);
  }
}
