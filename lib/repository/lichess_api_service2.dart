import 'dart:async';
import 'dart:convert';
import 'package:chessever2/repository/api_utils/api_exceptions.dart';
import 'package:chessever2/repository/models/game.dart';
import 'package:chessever2/repository/models/tournament.dart';
import 'package:http/http.dart' as http;
import 'package:http/http.dart' show Request, StreamedResponse;
import 'package:hooks_riverpod/hooks_riverpod.dart';

abstract class ApiException implements Exception {
  final String message;

  ApiException(this.message);

  @override
  String toString() => message;
}

class BroadcastEvent {
  final String type;
  final Map<String, dynamic> data;

  BroadcastEvent({required this.type, required this.data});

  factory BroadcastEvent.fromJson(Map<String, dynamic> json) {
    return BroadcastEvent(
      type: json['type'] as String,
      data: json['data'] as Map<String, dynamic>, // adjust key if needed
    );
  }
}

abstract class ILichessRepository {
  Future<List<Tournament>> fetchArenaTournaments();

  Future<List<GameExport>> fetchTournamentGames(String tournamentId);

  Stream<BroadcastEvent> streamBroadcast(String broadcastId);
}

class LichessRepository implements ILichessRepository {
  final http.Client _client;
  final String _baseUrl = 'https://lichess.org/api';

  LichessRepository({http.Client? client}) : _client = client ?? http.Client();

  @override
  Future<List<Tournament>> fetchArenaTournaments() async {
    final uri = Uri.parse('$_baseUrl/tournament');
    try {
      final resp = await _client.get(uri);
      if (resp.statusCode != 200) {
        throw NetworkException(
          'Failed to fetch tournaments: ${resp.statusCode}',
        );
      }
      final data = json.decode(resp.body) as Map<String, dynamic>;
      final list =
          (data['tournaments'] as List<dynamic>? ?? [])
              .map((e) => Tournament.fromJson(e as Map<String, dynamic>))
              .toList();
      return list;
    } catch (e) {
      throw ParsingException('Failed to parse tournaments: $e');
    }
  }

  @override
  Future<List<GameExport>> fetchTournamentGames(String tournamentId) async {
    final uri = Uri.parse('$_baseUrl/tournament/$tournamentId/games');
    try {
      final resp = await _client.get(uri);
      if (resp.statusCode != 200) {
        throw NetworkException('Failed to fetch games: ${resp.statusCode}');
      }
      final data = json.decode(resp.body) as Map<String, dynamic>;
      final list =
          (data['games'] as List<dynamic>? ?? [])
              .map((e) => GameExport.fromJson(e as Map<String, dynamic>))
              .toList();
      return list;
    } catch (e) {
      throw ParsingException('Failed to parse games: $e');
    }
  }

  @override
  Stream<BroadcastEvent> streamBroadcast(String broadcastId) async* {
    final uri = Uri.parse('$_baseUrl/broadcast/$broadcastId');
    final req = Request('GET', uri)..headers['Accept'] = 'application/x-ndjson';

    StreamedResponse response;
    try {
      response = await _client.send(req).timeout(const Duration(seconds: 20));
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
          // Optionally log malformed lines
        }
      }
    } else if (response.statusCode == 429) {
      throw RateLimitException('Broadcast rate limit exceeded (429).');
    } else if (response.statusCode == 404) {
      throw NotFoundException('Broadcast $broadcastId not found (404).');
    } else {
      throw GenericApiException(
        'Failed to open broadcast $broadcastId: HTTP ${response.statusCode}',
      );
    }
  }

  void dispose() {
    _client.close();
  }
}

final lichessRepositoryProvider = Provider<ILichessRepository>((ref) {
  final repo = LichessRepository();
  ref.onDispose(() => repo.dispose());
  return repo;
});
