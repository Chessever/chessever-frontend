import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:chessever2/services/cloudflare_gif_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('submits an authenticated versioned GIF request', () async {
    late http.Request captured;
    final client = MockClient((request) async {
      captured = request;
      return http.Response(
        jsonEncode({
          'jobId': 'job-1',
          'status': 'queued',
          'stage': 'queued',
          'completedFrames': 0,
          'totalFrames': 5,
          'expiresAt': '2026-07-28T12:00:00Z',
        }),
        202,
      );
    });
    final service = CloudflareGifService(
      baseUri: Uri.parse('https://cloudflare.example.test'),
      accessTokenProvider: () async => 'access-token',
      client: client,
    );

    final job = await service.submitJob(
      pgn: '1. e4 e5 *',
      flipped: true,
      metadata: const {
        'white': 'Alice',
        'black': 'Bob',
        'whiteRating': 2400,
        'whitePhotoData': 'data:image/webp;base64,UklGRg==',
        'event': 'Test Event • Round 1',
        'result': '1/2-1/2',
      },
    );

    final body = jsonDecode(captured.body) as Map<String, dynamic>;
    expect(captured.url.path, '/v1/gif-jobs');
    expect(captured.headers['authorization'], 'Bearer access-token');
    expect(body['schemaVersion'], 1);
    expect(body['flipped'], isTrue);
    expect(body['metadata']['whiteRating'], 2400);
    expect(
      body['metadata']['whitePhotoData'],
      'data:image/webp;base64,UklGRg==',
    );
    expect(body['metadata']['result'], '1/2-1/2');
    expect(job.id, 'job-1');
    expect(job.totalFrames, 5);
    service.close();
  });

  test('polls until the workflow succeeds and reports progress', () async {
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      final succeeded = calls > 1;
      return http.Response(
        jsonEncode({
          'jobId': 'job-2',
          'status': succeeded ? 'succeeded' : 'rendering',
          'stage': succeeded ? 'succeeded' : 'rendering',
          'completedFrames': succeeded ? 8 : 4,
          'totalFrames': 8,
          'expiresAt': '2026-07-28T12:00:00Z',
        }),
        200,
      );
    });
    final service = CloudflareGifService(
      baseUri: Uri.parse('https://cloudflare.example.test/'),
      accessTokenProvider: () async => 'access-token',
      client: client,
    );
    final progress = <CloudflareGifJob>[];

    final completed = await service.waitUntilComplete(
      'job-2',
      onProgress: progress.add,
      initialPollInterval: Duration.zero,
    );

    expect(completed.status, CloudflareGifJobStatus.succeeded);
    expect(progress.map((job) => job.completedFrames), [4, 8]);
    service.close();
  });

  test('cancels polling without cancelling the remote job', () async {
    final service = CloudflareGifService(
      baseUri: Uri.parse('https://cloudflare.example.test/'),
      accessTokenProvider: () async => 'access-token',
      client: MockClient((_) async => throw StateError('must not poll')),
    );

    expect(
      () => service.waitUntilComplete(
        'job-cancelled',
        onProgress: (_) {},
        isCancelled: () => true,
      ),
      throwsA(isA<CloudflareGifCancelled>()),
    );
    service.close();
  });

  test('times out a non-terminal workflow', () async {
    final service = CloudflareGifService(
      baseUri: Uri.parse('https://cloudflare.example.test/'),
      accessTokenProvider: () async => 'access-token',
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'jobId': 'job-timeout',
            'status': 'queued',
            'stage': 'queued',
            'completedFrames': 0,
            'totalFrames': 0,
            'expiresAt': '2026-07-28T12:00:00Z',
          }),
          200,
        ),
      ),
    );

    expect(
      () => service.waitUntilComplete(
        'job-timeout',
        onProgress: (_) {},
        timeout: Duration.zero,
      ),
      throwsA(
        isA<CloudflareGifException>().having(
          (error) => error.code,
          'code',
          'generation_timeout',
        ),
      ),
    );
    service.close();
  });

  test('surfaces stable API errors', () async {
    final client = MockClient(
      (_) async => http.Response(
        jsonEncode({
          'error': {
            'code': 'active_job_limit',
            'message': 'Finish the active GIF job first.',
          },
        }),
        409,
      ),
    );
    final service = CloudflareGifService(
      baseUri: Uri.parse('https://cloudflare.example.test/'),
      accessTokenProvider: () async => 'access-token',
      client: client,
    );

    expect(
      () => service.getJob('job-3'),
      throwsA(
        isA<CloudflareGifException>().having(
          (error) => error.code,
          'code',
          'active_job_limit',
        ),
      ),
    );
    service.close();
  });

  test('refreshes the Supabase token once after unauthorized', () async {
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      if (calls == 1) {
        expect(request.headers['authorization'], 'Bearer stale-token');
        return http.Response(
          jsonEncode({
            'error': {'code': 'invalid_token', 'message': 'Expired'},
          }),
          401,
        );
      }
      expect(request.headers['authorization'], 'Bearer fresh-token');
      return http.Response(
        jsonEncode({
          'jobId': 'job-4',
          'status': 'queued',
          'stage': 'queued',
          'completedFrames': 0,
          'totalFrames': 0,
          'expiresAt': '2026-07-28T12:00:00Z',
        }),
        200,
      );
    });
    final service = CloudflareGifService(
      baseUri: Uri.parse('https://cloudflare.example.test/'),
      accessTokenProvider: () async => 'stale-token',
      refreshAccessTokenProvider: () async => 'fresh-token',
      client: client,
    );

    final job = await service.getJob('job-4');

    expect(job.id, 'job-4');
    expect(calls, 2);
    service.close();
  });

  test('streams a completed GIF to disk', () async {
    final tempDir = await Directory.systemTemp.createTemp('cloud-gif-test-');
    final outputPath = '${tempDir.path}/game.gif';
    final client = MockClient((request) async {
      expect(request.url.path, '/v1/gif-jobs/job-5/file');
      return http.Response.bytes(
        const [0x47, 0x49, 0x46, 0x38, 0x39, 0x61],
        200,
        headers: const {'content-type': 'image/gif'},
      );
    });
    final service = CloudflareGifService(
      baseUri: Uri.parse('https://cloudflare.example.test/'),
      accessTokenProvider: () async => 'access-token',
      client: client,
    );

    await service.downloadToFile(jobId: 'job-5', outputPath: outputPath);

    expect(await File(outputPath).readAsBytes(), [
      0x47,
      0x49,
      0x46,
      0x38,
      0x39,
      0x61,
    ]);
    service.close();
    await tempDir.delete(recursive: true);
  });

  test('maps stable renderer and validation error messages', () {
    expect(
      CloudflareGifService.messageForErrorCode('too_many_plies'),
      contains('300 plies'),
    );
    expect(
      CloudflareGifService.messageForErrorCode('pgn_too_large'),
      contains('too large'),
    );
    expect(
      CloudflareGifService.messageForErrorCode('invalid_pgn'),
      contains('could not be replayed'),
    );
    expect(
      CloudflareGifService.messageForErrorCode('no_moves'),
      contains('could not be replayed'),
    );
    expect(
      CloudflareGifService.messageForErrorCode('renderer_failed'),
      contains('Cloud rendering failed'),
    );
    expect(
      CloudflareGifService.messageForErrorCode('daily_job_limit'),
      contains('Daily'),
    );
  });

  test('detects supported cloud GIF player-photo formats by signature', () {
    expect(
      cloudGifPhotoMimeType(
        Uint8List.fromList([0x89, 0x50, 0x4e, 0x47, 13, 10, 26, 10]),
      ),
      'image/png',
    );
    expect(
      cloudGifPhotoMimeType(Uint8List.fromList([0xff, 0xd8, 0xff, 0xe0])),
      'image/jpeg',
    );
    expect(
      cloudGifPhotoMimeType(
        Uint8List.fromList([
          0x52,
          0x49,
          0x46,
          0x46,
          0,
          0,
          0,
          0,
          0x57,
          0x45,
          0x42,
          0x50,
        ]),
      ),
      'image/webp',
    );
    expect(cloudGifPhotoMimeType(Uint8List.fromList([1, 2, 3])), isNull);
  });

  test('reports missing mobile Cloudflare configuration', () {
    expect(
      CloudflareGifService.fromEnvironment,
      throwsA(
        isA<CloudflareGifException>().having(
          (error) => error.code,
          'code',
          'service_not_configured',
        ),
      ),
    );
  });

  test('surfaces authentication failures from the token provider', () {
    final service = CloudflareGifService(
      baseUri: Uri.parse('https://cloudflare.example.test/'),
      accessTokenProvider:
          () async =>
              throw const CloudflareGifException(
                'authentication_required',
                'Sign in to generate a GIF.',
              ),
      client: MockClient((_) async => throw StateError('must not request')),
    );

    expect(
      () => service.getJob('job-auth'),
      throwsA(
        isA<CloudflareGifException>().having(
          (error) => error.code,
          'code',
          'authentication_required',
        ),
      ),
    );
    service.close();
  });
}
