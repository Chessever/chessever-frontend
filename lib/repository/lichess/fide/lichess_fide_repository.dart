import 'dart:async';
import 'dart:convert';
import 'package:chessever2/repository/lichess/fide/fide_player.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:http/http.dart' as http;

final lichessFideRepoProvider = Provider<LichessFideRepository>(
  (ref) => LichessFideRepository(),
);

class LichessFideRepository {
  final String baseUrl = 'https://lichess.org/api/fide';

  /// Get FIDE player by ID
  /// Endpoint: GET /api/fide/player/{playerId}
  Future<FidePlayer?> getPlayerById(int fideId) async {
    try {
      final uri = Uri.parse('$baseUrl/player/$fideId');
      print('🌐 Lichess FIDE: Requesting player $fideId from $uri');

      final resp = await http.get(uri).timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          print('⏱️ Lichess FIDE: Request timeout after 5 seconds');
          throw TimeoutException('Lichess FIDE API timeout');
        },
      );

      print('📡 Lichess FIDE: Response status ${resp.statusCode}');

      if (resp.statusCode == 200) {
        final decoded = jsonDecode(resp.body) as Map<String, dynamic>;
        final player = FidePlayer.fromJson(decoded);
        print(
          '✅ Lichess FIDE: Found player ${player.name} - '
          'Classical: ${player.standard}, Rapid: ${player.rapid}, Blitz: ${player.blitz}',
        );
        return player;
      }

      if (resp.statusCode == 404) {
        print('📭 Lichess FIDE: Player $fideId not found');
        return null;
      }

      print('❌ Lichess FIDE: Unexpected status ${resp.statusCode}');
      return null;
    } catch (e) {
      print('❌ Lichess FIDE: Error fetching player $fideId - $e');
      return null;
    }
  }

  /// Search FIDE players by name
  /// Endpoint: GET /api/fide/player?q=NAME
  Future<List<FidePlayer>> searchPlayersByName(String name) async {
    try {
      final uri = Uri.parse('$baseUrl/player?q=${Uri.encodeComponent(name)}');
      print('🌐 Lichess FIDE: Searching players matching "$name"');

      final resp = await http.get(uri).timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          print('⏱️ Lichess FIDE: Search timeout after 5 seconds');
          throw TimeoutException('Lichess FIDE API timeout');
        },
      );

      print('📡 Lichess FIDE: Search response status ${resp.statusCode}');

      if (resp.statusCode == 200) {
        final decoded = jsonDecode(resp.body) as List<dynamic>;
        final players = decoded
            .map((json) => FidePlayer.fromJson(json as Map<String, dynamic>))
            .toList();
        print('✅ Lichess FIDE: Found ${players.length} players matching "$name"');
        return players;
      }

      if (resp.statusCode == 404) {
        print('📭 Lichess FIDE: No players found matching "$name"');
        return [];
      }

      print('❌ Lichess FIDE: Unexpected status ${resp.statusCode}');
      return [];
    } catch (e) {
      print('❌ Lichess FIDE: Error searching for "$name" - $e');
      return [];
    }
  }
}
