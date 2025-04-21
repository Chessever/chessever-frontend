// lib/services/lichess_api_service.dart
import 'package:http/http.dart' as http;
import 'dart:convert'; // For jsonDecode and utf8
import '../models/tournament.dart';
import '../models/game.dart';

// Define custom exception classes for better error handling
class ApiException implements Exception {
  final String message;
  ApiException(this.message);
  @override
  String toString() => message;
}

class NetworkException extends ApiException {
  NetworkException(String message) : super(message);
}

class RateLimitException extends ApiException {
  RateLimitException(String message) : super(message);
}

class NotFoundException extends ApiException {
  NotFoundException(String message) : super(message);
}

class ParsingException extends ApiException {
  ParsingException(String message) : super(message);
}

class LichessApiService {
  final String _baseUrl = 'https://lichess.org/api';
  final http.Client _client;

  // Allow injecting an http.Client for testing
  LichessApiService({http.Client? client}) : _client = client ?? http.Client();

  // --- Tournament Fetching ---

  // Fetches Arena tournaments and parses them
  Future<Map<String, List<Tournament>>> fetchArenaTournamentsParsed() async {
    final url = Uri.parse('$_baseUrl/broadcast');
    try {
      final response = await _client
          .get(url)
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        String raw = utf8.decode(response.bodyBytes);
        raw = raw.trim(); // this removes stray newlines, spaces, BOM, etc.
        final lines = raw.split('\n').where((l) => l.isNotEmpty);
        final tournaments =
            lines.map((l) => jsonDecode(l) as Map<String, dynamic>).toList();

        Map<String, List<Tournament>> tournamentsByCategory = {
          'created': [],
          'started': [],
          'finished': [],
        };

        for (var entry in tournaments) {
          // final type = entry['type'] as String? ?? 'unknown';
          final type = 'started';
          if (tournamentsByCategory.containsKey(type)) {
            tournamentsByCategory[type]!.add(
              Tournament.fromJson(entry, 'arena'),
            );
          }
        }

        return tournamentsByCategory;
      } else if (response.statusCode == 429) {
        throw RateLimitException(
          'API rate limit exceeded (429). Please wait and retry.',
        );
      } else if (response.statusCode == 404) {
        throw NotFoundException('Arena tournaments endpoint not found (404).');
      } else {
        throw ApiException(
          'Failed to load Arena tournaments: ${response.statusCode}',
        );
      }
    } on http.ClientException catch (e) {
      throw NetworkException('Network error fetching arenas: $e');
    } on FormatException catch (e) {
      throw ParsingException('Failed to parse Arena tournament data: $e');
    } catch (e) {
      // Catch any other unexpected errors
      throw ApiException('An unexpected error occurred fetching arenas: $e');
    }
  }


  // --- Game Fetching ---
  Future<List<BroadcastGame>> fetchBroadcastRoundGames({
    required String broadcastTournamentSlug,
    required String broadcastRoundSlug,
    required String broadcastRoundId,
  }) async {
    final url = Uri.parse(
      'https://lichess.org/api/broadcast/'
      '$broadcastTournamentSlug/'
      '$broadcastRoundSlug/'
      '$broadcastRoundId',
    );

    try {
      final response = await http
          .get(url, headers: {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 20));

      switch (response.statusCode) {
        case 200:
          final Map<String, dynamic> decoded = jsonDecode(
            utf8.decode(response.bodyBytes),
          );
          final gamesJson = decoded['games'] as List<dynamic>;

          return gamesJson
              .map((g) => BroadcastGame.fromJson(g as Map<String, dynamic>))
              .toList();

        case 404:
          throw NotFoundException(
            'Broadcast round not found: $broadcastRoundId (404).',
          );

        case 429:
          throw RateLimitException(
            'API rate limit exceeded (429). Please wait and retry.',
          );

        default:
          throw ApiException(
            'Failed to load broadcast games (${response.statusCode}).',
          );
      }
    } on http.ClientException catch (e) {
      throw NetworkException('Network error: $e');
    } on FormatException catch (e) {
      throw ParsingException('Invalid JSON received: $e');
    } catch (e) {
      throw ApiException('Unexpected error: $e');
    }
  }
  // Fetches games for a tournament (Arena or Swiss) and parses ND-JSON
  // Future<List<Game>> fetchTournamentGamesParsed(String tournamentId, bool isSwiss) async {
  //   final endpoint = isSwiss? 'swiss/$tournamentId/games' : 'tournament/$tournamentId/games';
  //   final url = Uri.parse('$_baseUrl/$endpoint');

  //   try {
  //     final response = await _client.get(
  //       url,
  //       headers: {'Accept': 'application/x-ndjson'}, // Request ND-JSON
  //     ).timeout(const Duration(seconds: 20)); // Longer timeout for potentially large game lists

  //     if (response.statusCode == 200) {
  //       final rawNdJson = utf8.decode(response.bodyBytes);
  //       final lines = rawNdJson.split('\n').where((line) => line.trim().isNotEmpty);
  //       List<Game> games = [];
  //       for (var line in lines) {
  //         try {
  //            final Map<String, dynamic> jsonMap = jsonDecode(line);
  //            games.add(Game.fromJson(jsonMap));
  //         } catch (e) {
  //            print("Warning: Skipping invalid game JSON line: $line - Error: $e");
  //            // Optionally log this error more formally
  //         }
  //       }
  //       return games;
  //     } else if (response.statusCode == 429) {
  //       throw RateLimitException('API rate limit exceeded (429) fetching games. Please wait and retry.');
  //     } else if (response.statusCode == 404) {
  //        throw NotFoundException('Games not found for tournament $tournamentId (404).');
  //     } else {
  //       throw ApiException('Failed to load games for tournament $tournamentId: ${response.statusCode}');
  //     }
  //   } on http.ClientException catch (e) {
  //      throw NetworkException('Network error fetching games: $e');
  //   } on FormatException catch (e) {
  //      throw ParsingException('Failed to parse game data for tournament $tournamentId: $e');
  //   } catch (e) {
  //     throw ApiException('An unexpected error occurred fetching games: $e');
  //   }
  // }

  // Close the client when the service is no longer needed
  void dispose() {
    _client.close();
  }
}
