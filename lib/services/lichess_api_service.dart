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
  // LichessApiService._(this._client);
  static final LichessApiService instance = LichessApiService();
  final String _baseUrl = 'https://lichess.org/api';
  final http.Client _client;

  // Allow injecting an http.Client for testing
  LichessApiService({http.Client? client}) : _client = client ?? http.Client();

  // --- Tournament Fetching ---

  Future<Map<String, List<Tournament>>> fetchBroadcasts() async {
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
          'upcoming': [],
          'started': [],
          'finished': [],
        };

        final now = DateTime.now();

        for (var entry in tournaments) {
          // Dates are milliseconds since epoch
          int startMillis, endMillis;
          try {
            startMillis = entry["tour"]["dates"][0] as int;
            endMillis = entry["tour"]["dates"][1] as int;
          } catch (e) {
            startMillis = 0;
            endMillis = 0;
          }

          final start = DateTime.fromMillisecondsSinceEpoch(startMillis);
          final end = DateTime.fromMillisecondsSinceEpoch(endMillis);

          // Determine category
          String category;
          if (now.isBefore(start)) {
            category = 'upcoming';
          } else if (now.isAfter(end)) {
            category = 'finished';
          } else {
            category = 'started';
          }

          // Add if bucket exists
          if (tournamentsByCategory.containsKey(category)) {
            tournamentsByCategory[category]!.add(Tournament.fromJson(entry));
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
  Future<List<BroadcastGame>> fetchBroadcastRoundGames(
    broadcastTournamentSlug,
    broadcastRoundSlug,
    broadcastRoundId) async {
    // final url = Uri.parse('$_baseUrl/broadcast');
    final url = Uri.parse(
      '$_baseUrl/'
      'broadcast/'
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
          final String decodedUtf8 = utf8.decode(response.bodyBytes);
          final Map<String, dynamic> decoded = jsonDecode(decodedUtf8);
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

  // Close the client when the service is no longer needed
  void dispose() {
    _client.close();
  }
}
