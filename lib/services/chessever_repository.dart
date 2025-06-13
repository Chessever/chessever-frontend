import 'package:chessever2/services/models/game.dart';
import 'package:chessever2/services/models/tournament.dart';

abstract class IChesseverRepository {
  Future<Map<String, List<Tournament>>> fetchTournaments();

  Future<List<BroadcastGame>> fetchBroadcastRoundGames(String broadcastId);
}
