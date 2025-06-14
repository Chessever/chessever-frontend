
import 'package:chessever2/repository/models/game.dart';
import 'package:chessever2/repository/models/tournament.dart';

abstract class IChesseverRepository {
  Future<Map<String, List<Tournament>>> fetchTournaments();

  Future<List<BroadcastGame>> fetchBroadcastRoundGames(String broadcastId);
}
