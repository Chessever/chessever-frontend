import 'package:chessever2/repository/api_utils/api_exceptions.dart';
import 'package:chessever2/repository/models/game.dart';
import 'package:chessever2/repository/models/tournament.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart' show Provider;
import 'package:http/http.dart' as http;
import 'dart:convert';

/// Interface for Chessever repository
abstract class IChesseverRepository {
  Future<Map<String, List<Tournament>>> fetchTournaments();

  Future<List<BroadcastGame>> fetchBroadcastRoundGames(String broadcastId);
}

/// Implementation of [IChesseverRepository]
class ChesseverRepository implements IChesseverRepository {
  final http.Client _client;
  static const _baseUrl = 'http://127.0.0.1:5000';

  ChesseverRepository({http.Client? client})
    : _client = client ?? http.Client();

  @override
  Future<Map<String, List<Tournament>>> fetchTournaments() async {
    final uri = Uri.parse('$_baseUrl/tournaments');
    http.Response res;
    try {
      res = await _client.get(uri).timeout(const Duration(seconds: 10));
    } on http.ClientException catch (e) {
      throw NetworkException('Failed to connect to $_baseUrl: $e');
    }

    if (res.statusCode == 200) {
      try {
        final dynamic decoded = jsonDecode(res.body);
        if (decoded is! Map<String, dynamic>) {
          throw ParsingException(
            'Expected JSON object, got \\${decoded.runtimeType}',
          );
        }
        final Map<String, dynamic> jsonMap = decoded;
        // Define categories
        const categories = ['upcoming', 'started', 'finished'];
        final result = <String, List<Tournament>>{};
        for (final category in categories) {
          final rawList = jsonMap[category];
          if (rawList is List) {
            result[category] =
                rawList.where((e) => e != null).map((e) {
                  if (e is Map<String, dynamic>) {
                    return Tournament.fromJson(e);
                  } else {
                    throw ParsingException('Invalid tournaments entry: $e');
                  }
                }).toList();
          } else {
            // handle missing or null category as empty list
            result[category] = <Tournament>[];
          }
        }
        return result;
      } catch (e) {
        throw ParsingException('Could not parse tournaments: $e');
      }
    }

    if (res.statusCode == 404) {
      throw NotFoundException('Tournaments endpoint not found (404)');
    }

    throw GenericApiException(
      'Error fetching tournaments: HTTP \\${res.statusCode}',
    );
  }

  @override
  Future<List<BroadcastGame>> fetchBroadcastRoundGames(
    String broadcastId,
  ) async {
    final uri = Uri.parse('$_baseUrl/tournaments/$broadcastId/rounds');
    http.Response res;
    try {
      res = await _client.get(uri).timeout(const Duration(seconds: 10));
    } on http.ClientException catch (e) {
      throw NetworkException('Failed to connect to $_baseUrl: $e');
    }

    if (res.statusCode == 200) {
      try {
        final List<dynamic> jsonList = jsonDecode(res.body);
        return jsonList
            .map((e) => BroadcastGame.fromJson(e as Map<String, dynamic>))
            .toList();
      } catch (e) {
        throw ParsingException('Could not parse rounds for $broadcastId: $e');
      }
    }

    if (res.statusCode == 404) {
      throw NotFoundException(
        'Rounds for broadcast $broadcastId not found (404)',
      );
    }

    throw GenericApiException(
      'Error fetching rounds: HTTP \\${res.statusCode}',
    );
  }

  void dispose() => _client.close();
}

final chesseverRepositoryProvider = Provider<IChesseverRepository>((ref) {
  final repo = ChesseverRepository();
  ref.onDispose(() => repo.dispose());
  return repo;
});
