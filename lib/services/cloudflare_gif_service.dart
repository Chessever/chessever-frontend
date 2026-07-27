import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

enum CloudflareGifJobStatus {
  queued,
  analyzing,
  rendering,
  encoding,
  storing,
  succeeded,
  failed,
}

class CloudflareGifJob {
  const CloudflareGifJob({
    required this.id,
    required this.status,
    required this.stage,
    required this.completedFrames,
    required this.totalFrames,
    required this.expiresAt,
    this.errorCode,
  });

  final String id;
  final CloudflareGifJobStatus status;
  final CloudflareGifJobStatus stage;
  final int completedFrames;
  final int totalFrames;
  final DateTime expiresAt;
  final String? errorCode;

  bool get isTerminal =>
      status == CloudflareGifJobStatus.succeeded ||
      status == CloudflareGifJobStatus.failed;

  factory CloudflareGifJob.fromJson(Map<String, dynamic> json) {
    CloudflareGifJobStatus parseStatus(Object? value) {
      return CloudflareGifJobStatus.values.firstWhere(
        (status) => status.name == value,
        orElse: () => CloudflareGifJobStatus.queued,
      );
    }

    return CloudflareGifJob(
      id: json['jobId']?.toString() ?? '',
      status: parseStatus(json['status']),
      stage: parseStatus(json['stage']),
      completedFrames: (json['completedFrames'] as num?)?.toInt() ?? 0,
      totalFrames: (json['totalFrames'] as num?)?.toInt() ?? 0,
      expiresAt:
          DateTime.tryParse(json['expiresAt']?.toString() ?? '') ??
          DateTime.now(),
      errorCode: json['errorCode']?.toString(),
    );
  }
}

class CloudflareGifException implements Exception {
  const CloudflareGifException(this.code, this.message, {this.statusCode});

  final String code;
  final String message;
  final int? statusCode;

  @override
  String toString() => 'CloudflareGifException($code): $message';
}

class CloudflareGifCancelled implements Exception {
  const CloudflareGifCancelled();
}

typedef CloudflareAccessTokenProvider = Future<String> Function();

class CloudflareGifService {
  CloudflareGifService({
    required Uri baseUri,
    required CloudflareAccessTokenProvider accessTokenProvider,
    CloudflareAccessTokenProvider? refreshAccessTokenProvider,
    http.Client? client,
  }) : _baseUri = _normalizeBaseUri(baseUri),
       _accessTokenProvider = accessTokenProvider,
       _refreshAccessTokenProvider = refreshAccessTokenProvider,
       _client = client ?? http.Client();

  factory CloudflareGifService.fromEnvironment() {
    final value = _cloudflareApiBase();
    if (value == null || value.isEmpty) {
      throw const CloudflareGifException(
        'service_not_configured',
        'Cloud GIF service is not configured.',
      );
    }
    final uri = Uri.tryParse(value);
    if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
      throw const CloudflareGifException(
        'service_not_configured',
        'Cloud GIF service URL is invalid.',
      );
    }
    return CloudflareGifService(
      baseUri: uri,
      accessTokenProvider: _supabaseAccessToken,
      refreshAccessTokenProvider: _refreshSupabaseAccessToken,
    );
  }

  final Uri _baseUri;
  final CloudflareAccessTokenProvider _accessTokenProvider;
  final CloudflareAccessTokenProvider? _refreshAccessTokenProvider;
  final http.Client _client;

  static Uri _normalizeBaseUri(Uri uri) {
    return Uri.parse('${uri.toString().replaceFirst(RegExp(r'/+$'), '')}/');
  }

  static String? _cloudflareApiBase() {
    const releaseValue = String.fromEnvironment(
      'CHESSEVER_CLOUDFLARE_API_BASE',
      defaultValue: '',
    );
    final normalizedRelease = releaseValue.trim();
    if (normalizedRelease.isNotEmpty) return normalizedRelease;
    if (!kDebugMode) return null;
    try {
      final debugValue =
          dotenv.env['CHESSEVER_CLOUDFLARE_API_BASE']?.trim() ?? '';
      return debugValue.isEmpty ? null : debugValue;
    } catch (_) {
      return null;
    }
  }

  static Future<String> _supabaseAccessToken() async {
    final auth = Supabase.instance.client.auth;
    var session = auth.currentSession;
    if (session == null) {
      throw const CloudflareGifException(
        'authentication_required',
        'Sign in to generate a GIF.',
      );
    }
    final expiresAt = session.expiresAt;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    if (expiresAt != null && expiresAt <= now + 30) {
      session = (await auth.refreshSession()).session;
    }
    final token = session?.accessToken.trim();
    if (token == null || token.isEmpty) {
      throw const CloudflareGifException(
        'authentication_required',
        'Sign in to generate a GIF.',
      );
    }
    return token;
  }

  static Future<String> _refreshSupabaseAccessToken() async {
    final session =
        (await Supabase.instance.client.auth.refreshSession()).session;
    final token = session?.accessToken.trim();
    if (token == null || token.isEmpty) {
      throw const CloudflareGifException(
        'authentication_required',
        'Sign in to generate a GIF.',
      );
    }
    return token;
  }

  Future<CloudflareGifJob> submitJob({
    required String pgn,
    required bool flipped,
    required Map<String, Object?> metadata,
  }) async {
    final response = await _postJson('v1/gif-jobs', <String, Object?>{
      'schemaVersion': 1,
      'pgn': pgn,
      'flipped': flipped,
      'metadata': metadata,
    });
    return CloudflareGifJob.fromJson(response);
  }

  Future<CloudflareGifJob> getJob(String jobId) async {
    final response = await _getJson('v1/gif-jobs/$jobId');
    return CloudflareGifJob.fromJson(response);
  }

  Future<CloudflareGifJob> waitUntilComplete(
    String jobId, {
    required void Function(CloudflareGifJob job) onProgress,
    bool Function()? isCancelled,
    Duration timeout = const Duration(minutes: 10),
    Duration initialPollInterval = const Duration(milliseconds: 800),
  }) async {
    final deadline = DateTime.now().add(timeout);
    var interval = initialPollInterval;
    while (DateTime.now().isBefore(deadline)) {
      if (isCancelled?.call() ?? false) {
        throw const CloudflareGifCancelled();
      }
      final job = await getJob(jobId);
      onProgress(job);
      if (job.status == CloudflareGifJobStatus.succeeded) return job;
      if (job.status == CloudflareGifJobStatus.failed) {
        throw CloudflareGifException(
          job.errorCode ?? 'generation_failed',
          messageForErrorCode(job.errorCode),
        );
      }
      await Future<void>.delayed(interval);
      final nextMilliseconds = (interval.inMilliseconds * 1.35).round().clamp(
        800,
        2000,
      );
      interval = Duration(milliseconds: nextMilliseconds);
    }
    throw const CloudflareGifException(
      'generation_timeout',
      'GIF generation took too long. Reopen Share to resume it.',
    );
  }

  Future<void> downloadToFile({
    required String jobId,
    required String outputPath,
  }) async {
    var token = await _accessTokenProvider();
    var response = await _sendDownloadRequest(jobId, token);
    if (response.statusCode == HttpStatus.unauthorized &&
        _refreshAccessTokenProvider != null) {
      await response.stream.drain<void>();
      token = await _refreshAccessTokenProvider();
      response = await _sendDownloadRequest(jobId, token);
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final bytes = await response.stream.toBytes();
      throw _exceptionFromResponse(
        response.statusCode,
        utf8.decode(bytes, allowMalformed: true),
      );
    }

    final output = File(outputPath);
    final sink = output.openWrite();
    try {
      await response.stream.pipe(sink);
    } catch (_) {
      await sink.close();
      try {
        if (await output.exists()) await output.delete();
      } catch (_) {
        // Keep the original download error.
      }
      rethrow;
    }
  }

  Future<Map<String, dynamic>> _postJson(
    String path,
    Map<String, Object?> body,
  ) async {
    final encoded = jsonEncode(body);
    var token = await _accessTokenProvider();
    var response = await _client.post(
      _baseUri.resolve(path),
      headers: _jsonHeaders(token),
      body: encoded,
    );
    if (response.statusCode == HttpStatus.unauthorized &&
        _refreshAccessTokenProvider != null) {
      token = await _refreshAccessTokenProvider();
      response = await _client.post(
        _baseUri.resolve(path),
        headers: _jsonHeaders(token),
        body: encoded,
      );
    }
    return _decodeJsonResponse(response);
  }

  Future<Map<String, dynamic>> _getJson(String path) async {
    var token = await _accessTokenProvider();
    var response = await _client.get(
      _baseUri.resolve(path),
      headers: <String, String>{'authorization': 'Bearer $token'},
    );
    if (response.statusCode == HttpStatus.unauthorized &&
        _refreshAccessTokenProvider != null) {
      token = await _refreshAccessTokenProvider();
      response = await _client.get(
        _baseUri.resolve(path),
        headers: <String, String>{'authorization': 'Bearer $token'},
      );
    }
    return _decodeJsonResponse(response);
  }

  Map<String, String> _jsonHeaders(String token) => <String, String>{
    'authorization': 'Bearer $token',
    'content-type': 'application/json',
  };

  Future<http.StreamedResponse> _sendDownloadRequest(
    String jobId,
    String token,
  ) {
    final request = http.Request(
      'GET',
      _baseUri.resolve('v1/gif-jobs/$jobId/file'),
    )..headers['authorization'] = 'Bearer $token';
    return _client.send(request);
  }

  Map<String, dynamic> _decodeJsonResponse(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _exceptionFromResponse(response.statusCode, response.body);
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const CloudflareGifException(
        'invalid_response',
        'Cloud GIF service returned an invalid response.',
      );
    }
    return decoded;
  }

  static CloudflareGifException _exceptionFromResponse(
    int statusCode,
    String responseBody,
  ) {
    String code = 'request_failed';
    String message = 'Cloud GIF request failed.';
    try {
      final decoded = jsonDecode(responseBody);
      if (decoded is Map<String, dynamic>) {
        final error = decoded['error'];
        if (error is Map<String, dynamic>) {
          code = error['code']?.toString() ?? code;
          message = error['message']?.toString() ?? message;
        }
      }
    } catch (_) {
      // Fall back to the stable generic error.
    }
    return CloudflareGifException(code, message, statusCode: statusCode);
  }

  @visibleForTesting
  static String messageForErrorCode(String? code) {
    return switch (code) {
      'too_many_plies' => 'GIF export supports games up to 300 plies.',
      'pgn_too_large' => 'This PGN is too large to export as a GIF.',
      'invalid_pgn' || 'no_moves' => 'This game could not be replayed.',
      'renderer_failed' => 'Cloud rendering failed. Please try again.',
      'active_job_limit' => 'Finish the active GIF job first.',
      'daily_job_limit' => 'Daily GIF generation limit reached.',
      _ => 'GIF generation failed. Please try again.',
    };
  }

  void close() => _client.close();
}
