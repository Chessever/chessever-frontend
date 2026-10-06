import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'board_scan_position.dart';

class BoardScanException implements Exception {
  const BoardScanException(this.message);
  final String message;
  @override
  String toString() => message;
}

String boardScanBaseUrl(String supabaseUrl) {
  const override = String.fromEnvironment('BOARD_SCAN_API_BASE_URL');
  if (override.trim().isNotEmpty) {
    return override.trim().replaceFirst(RegExp(r'/$'), '');
  }
  return supabaseUrl.contains('odmekzlfunfocvedqusl')
      ? 'https://chessever-board-scan-test.young-sun-69a8.workers.dev'
      : 'https://chessever-board-scan.young-sun-69a8.workers.dev';
}

class BoardScanApi {
  BoardScanApi() : _client = http.Client();
  final http.Client _client;
  void close() => _client.close();

  Future<BoardScanPosition> scan(
    List<Map<String, String>> quadrants, {
    required bool photo,
    Map<String, dynamic>? source,
  }) async {
    final supabase = Supabase.instance.client;
    var session = supabase.auth.currentSession;
    if (session == null || session.user.isAnonymous) {
      throw const BoardScanException('Sign in to import a board image.');
    }
    final uri = Uri.parse(
      '${boardScanBaseUrl(supabase.rest.url)}/v1/board-scan',
    );
    final body = jsonEncode({
      'kind': photo ? 'photo' : 'diagram',
      'quadrants': quadrants,
      if (source != null) 'source': source,
    });
    for (var attempt = 0; attempt < 2; attempt++) {
      final response = await _client
          .post(
            uri,
            headers: {
              'content-type': 'application/json',
              'authorization': 'Bearer ${session!.accessToken}',
            },
            body: body,
          )
          .timeout(const Duration(seconds: 190));
      if (response.statusCode == 401 && attempt == 0) {
        session = (await supabase.auth.refreshSession()).session;
        if (session != null) continue;
      }
      Map<String, dynamic> json;
      try {
        json = jsonDecode(response.body) as Map<String, dynamic>;
      } catch (_) {
        throw const BoardScanException(
          'Image recognition is unavailable. Try again shortly.',
        );
      }
      if (response.statusCode != 200) {
        throw BoardScanException(
          json['error'] is String
              ? json['error'] as String
              : 'The image could not be read. Try again.',
        );
      }
      return BoardScanPosition(
        squares: Map<String, String>.from(json['squares'] as Map),
        warnings: (json['warnings'] as List? ?? [])
            .whereType<String>()
            .toList(),
      );
    }
    throw const BoardScanException('Sign in again to import a board image.');
  }
}
