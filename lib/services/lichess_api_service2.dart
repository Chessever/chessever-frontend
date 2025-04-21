// lib/services/lichess_api_service.dart

import 'dart:async';
import 'dart:convert';           // utf8, jsonDecode, LineSplitter
import 'package:http/http.dart' as http;
import 'package:http/http.dart' show Request, StreamedResponse;

import '../models/tournament.dart';
import '../models/game.dart';

/// --- Custom Exceptions ---------------------------------------------------

abstract class ApiException implements Exception {
  final String message;
  ApiException(this.message);
  @override
  String toString() => message;
}

class NetworkException   extends ApiException { NetworkException(String msg) : super(msg);   }
class RateLimitException extends ApiException { RateLimitException(String msg) : super(msg); }
class NotFoundException  extends ApiException { NotFoundException(String msg) : super(msg);  }
class ParsingException   extends ApiException { ParsingException(String msg) : super(msg);   }

/// --- Broadcast Event Model -----------------------------------------------

class BroadcastEvent {
  final String type;
  final Map<String, dynamic> data;

  BroadcastEvent({
    required this.type,
    required this.data,
  });

  factory BroadcastEvent.fromJson(Map<String, dynamic> json) {
    return BroadcastEvent(
      type: json['type'] as String,
      data: json['data'] as Map<String, dynamic>,  // adjust key if needed
    );
  }
}
class GenericApiException extends ApiException {
  GenericApiException(String message) : super(message);
}

/// --- LichessApiService ---------------------------------------------------

class LichessApiService {
  final String _baseUrl = 'https://lichess.org/api';
  final http.Client _client;

  LichessApiService({http.Client? client})
      : _client = client ?? http.Client();

  // … your existing methods (fetchArenaTournamentsParsed, fetchTournamentGamesParsed, etc.) …

  /// Opens a server‑sent ND‑JSON stream on `/api/broadcast/{id}`.
  /// Yields each line as a parsed [BroadcastEvent].
  Stream<BroadcastEvent> streamBroadcast(String broadcastId) async* {
    final uri = Uri.parse('$_baseUrl/broadcast/$broadcastId');
    final req = Request('GET', uri)
      ..headers['Accept'] = 'application/x-ndjson';

    StreamedResponse response;
    try {
      response = await _client.send(req)
          .timeout(const Duration(seconds: 20));
    } on http.ClientException catch (e) {
      throw NetworkException('Network error opening broadcast stream: $e');
    }

    if (response.statusCode == 200) {
      // Transform byte stream → UTF8 strings → line by line
      final lines = response.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter());

      await for (final line in lines) {
        if (line.trim().isEmpty) continue;
        try {
          final jsonMap = jsonDecode(line) as Map<String, dynamic>;
          yield BroadcastEvent.fromJson(jsonMap);
        } catch (e) {
          // Skip malformed lines; you could log this if you want
          print('Warning: malformed broadcast JSON: $line');
        }
      }
    } else if (response.statusCode == 429) {
      throw RateLimitException('Broadcast rate limit exceeded (429).');
    } else if (response.statusCode == 404) {
      throw NotFoundException('Broadcast $broadcastId not found (404).');
    } else {
      throw GenericApiException(
        'Failed to open broadcast $broadcastId: HTTP ${response.statusCode}'
      );
    }
  }

  void dispose() {
    _client.close();
  }
}
