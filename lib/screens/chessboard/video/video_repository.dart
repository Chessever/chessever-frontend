import 'dart:convert';

import 'package:http/http.dart' as http;
import '../../../config/app_environment.dart';
import 'video_stream.dart';

/// Production uses the approved public spectator API. Test builds require
/// explicit isolated origins and never fall back to the production service.
class EventVideoConfiguration {
  const EventVideoConfiguration._(this.apiOrigin, this.embedOrigin);
  final Uri apiOrigin, embedOrigin;
  static EventVideoConfiguration? fromEnvironment() => forFlavor(
    AppEnvironment.flavor,
    testApiOrigin: const String.fromEnvironment(
      'CHESSEVER_TEST_VIDEO_API_ORIGIN',
    ),
    testEmbedOrigin: const String.fromEnvironment(
      'CHESSEVER_TEST_VIDEO_EMBED_ORIGIN',
    ),
  );

  static EventVideoConfiguration? forFlavor(
    AppFlavor flavor, {
    String testApiOrigin = '',
    String testEmbedOrigin = '',
  }) {
    if (flavor == AppFlavor.production) {
      return EventVideoConfiguration._(
        Uri.parse('https://api.broadcast.chessever.com'),
        Uri.parse('https://chessever.com'),
      );
    }
    Uri? origin(String value) {
      final u = Uri.tryParse(value);
      if (u == null ||
          u.scheme != 'https' ||
          u.host.isEmpty ||
          u.userInfo.isNotEmpty ||
          u.hasPort ||
          (u.path.isNotEmpty && u.path != '/') ||
          u.hasQuery ||
          u.hasFragment) {
        return null;
      }
      // Refuse the known production hosts as well as ambiguous hostnames.
      // A dedicated test/staging label is required, not a query parameter.
      final labels = u.host.split('.');
      if (!labels.any(
        (p) =>
            p == 'test' ||
            p == 'staging' ||
            p.startsWith('test-') ||
            p.startsWith('staging-') ||
            p.endsWith('-test'),
      )) {
        return null;
      }
      return Uri(scheme: 'https', host: u.host);
    }

    final api = origin(testApiOrigin), embed = origin(testEmbedOrigin);
    return api == null || embed == null
        ? null
        : EventVideoConfiguration._(api, embed);
  }
}

class ResolvedEventVideos {
  const ResolvedEventVideos(this.streams, {this.sourceScope, this.sourceId});
  final List<EventVideoStream> streams;
  final String? sourceScope, sourceId;
}

class VideoMetadataException implements Exception {
  const VideoMetadataException(this.permanent);
  final bool permanent;
}

abstract interface class EventVideoRepository {
  Future<ResolvedEventVideos> fetch({
    required String tourId,
    required String roundId,
  });
  void close();
}

class HttpEventVideoRepository implements EventVideoRepository {
  HttpEventVideoRepository(this.configuration, {http.Client? client})
    : _client = client ?? http.Client();
  final EventVideoConfiguration configuration;
  final http.Client _client;
  @override
  Future<ResolvedEventVideos> fetch({
    required String tourId,
    required String roundId,
  }) async {
    final segments = [
      'api',
      'broadcast',
      if (roundId.isNotEmpty) ...['round', roundId] else tourId,
      'video-streams',
    ];
    final uri = configuration.apiOrigin.replace(pathSegments: segments);
    // Never follow an API redirect into an unverified environment.
    final request = http.Request('GET', uri)..followRedirects = false;
    final response = await http.Response.fromStream(
      await _client.send(request).timeout(const Duration(seconds: 12)),
    ).timeout(const Duration(seconds: 12));
    if (response.statusCode != 200) {
      throw VideoMetadataException(
        const [401, 403, 404, 410].contains(response.statusCode),
      );
    }
    final body = jsonDecode(response.body);
    if (body is! Map || body['streams'] is! List) {
      throw const FormatException('Invalid video metadata');
    }
    final source = body['source'];
    return ResolvedEventVideos(
      EventVideoStream.readList(body['streams']),
      sourceScope: source is Map ? source['scope'] as String? : null,
      sourceId: source is Map ? source['id'] as String? : null,
    );
  }

  @override
  void close() => _client.close();
}
