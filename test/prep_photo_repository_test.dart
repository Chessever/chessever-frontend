import 'dart:convert';

import 'package:chessever2/repository/gamebase/gamebase_repository.dart';
import 'package:chessever2/screens/my_prep/models/prep_models.dart';
import 'package:chessever2/screens/my_prep/services/prep_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

PrepRepository _repository(
  Future<http.Response> Function(http.Request) handler, {
  Future<String?> Function(String)? fidePhotoLookup,
}) {
  final repo = PrepRepository(
    GamebaseRepository(
      Dio(),
      baseUrl: 'https://example.invalid',
      apiKey: 'test-key',
    ),
    client: MockClient(handler),
    fidePhotoLookup: fidePhotoLookup ?? (_) async => null,
  );
  addTearDown(repo.dispose);
  return repo;
}

http.Response _profile(Object? profile, {int status = 200}) =>
    http.Response(jsonEncode(profile), status);

const _chessCom = PrepAccount(
  source: PrepSource.chesscom,
  username: 'ClubPlayer',
);
const _lichess = PrepAccount(
  source: PrepSource.lichess,
  username: 'ClubPlayer',
);

void main() {
  test('Chess.com photo lookup reads only the public profile', () async {
    final requests = <Uri>[];
    final repo = _repository((request) async {
      requests.add(request.url);
      return _profile({
        'avatar': '  https://images.chesscomfiles.com/player.jpg  ',
      });
    });

    expect(
      await repo.lookupPhoto(_chessCom),
      'https://images.chesscomfiles.com/player.jpg',
    );
    expect(requests.map((uri) => uri.toString()), [
      'https://api.chess.com/pub/player/clubplayer',
    ]);
  });

  test('Chess.com photo lookup rejects absent or non-web avatars', () async {
    for (final avatar in <Object?>[
      null,
      '',
      '   ',
      '/images/player.jpg',
      'https://',
      'javascript:alert(1)',
      'data:image/png;base64,AAAA',
      123,
      {'url': 'https://example.com/player.jpg'},
    ]) {
      final repo = _repository((_) async => _profile({'avatar': avatar}));
      expect(await repo.lookupPhoto(_chessCom), isNull, reason: '$avatar');
    }
  });

  test('new Chess.com accounts retain the validated avatar', () async {
    final requests = <String>[];
    final repo = _repository((request) async {
      requests.add(request.url.path);
      return request.url.path.endsWith('/stats')
          ? _profile({})
          : _profile({
              'username': 'clubplayer',
              'url': 'https://www.chess.com/member/ClubPlayer',
              'avatar': '  https://example.com/player.jpg ',
            });
    });

    final account = await repo.lookup(PrepSource.chesscom, 'ClubPlayer');
    expect(account.avatarUrl, 'https://example.com/player.jpg');
    expect(account.username, 'ClubPlayer');
    expect(requests, [
      '/pub/player/clubplayer',
      '/pub/player/clubplayer/stats',
    ]);
  });

  test(
    'Lichess photo lookup resolves only its top-level linked FIDE id',
    () async {
      final ids = <String>[];
      final requests = <Uri>[];
      final repo = _repository(
        (request) async {
          requests.add(request.url);
          return _profile({
            'username': 'ClubPlayer',
            if (request.url.queryParameters['fideId'] == 'true')
              'fideId': 1503014,
            'profile': {'fideId': 9999999},
          });
        },
        fidePhotoLookup: (id) async {
          ids.add(id);
          return ' https://example.com/fide-player.webp ';
        },
      );

      expect(
        await repo.lookupPhoto(_lichess),
        'https://example.com/fide-player.webp',
      );
      expect(ids, ['1503014']);
      expect(requests.map((uri) => uri.toString()), [
        'https://lichess.org/api/user/ClubPlayer?fideId=true',
      ]);
    },
  );

  test('Lichess ignores missing and invalid linked FIDE ids', () async {
    for (final fideId in <Object?>[null, 0, -1, '1503014', 1.5]) {
      final repo = _repository(
        (_) async => _profile({
          'fideId': fideId,
          'profile': {
            'fideId': 1503014,
            'avatar': 'https://example.com/unsupported-avatar.jpg',
          },
          'avatar': 'https://example.com/unsupported-avatar.jpg',
        }),
        fidePhotoLookup: (_) async => throw StateError('Must not resolve'),
      );

      expect(await repo.lookupPhoto(_lichess), isNull, reason: '$fideId');
    }
  });

  test('Lichess returns no portrait when FIDE has no photo', () async {
    final repo = _repository((_) async => _profile({'fideId': 1503014}));
    expect(await repo.lookupPhoto(_lichess), isNull);
  });

  test(
    'new Lichess accounts save the portrait without binding identity',
    () async {
      final repo = _repository(
        (request) async => _profile({
          'username': 'ClubPlayer',
          if (request.url.queryParameters['fideId'] == 'true')
            'fideId': 1503014,
          'title': 'GM',
          'perfs': {
            'blitz': {'rating': 2500, 'games': 10},
          },
        }),
        fidePhotoLookup: (_) async => 'https://example.com/fide-player.webp',
      );

      final account = await repo.lookup(PrepSource.lichess, 'ClubPlayer');
      expect(account.avatarUrl, 'https://example.com/fide-player.webp');
      expect(account.fideId, isNull);
      expect(account.title, 'GM');
      expect(account.ratings['blitz'], 2500);
      expect(
        PrepAccount.fromJson(account.toJson())!.avatarUrl,
        account.avatarUrl,
      );
    },
  );

  test(
    'a failed portrait lookup does not block adding a Lichess account',
    () async {
      final repo = _repository(
        (_) async => _profile({'username': 'ClubPlayer', 'fideId': 1503014}),
        fidePhotoLookup: (_) async => throw StateError('Photo service offline'),
      );

      final account = await repo.lookup(PrepSource.lichess, 'ClubPlayer');
      expect(account.username, 'ClubPlayer');
      expect(account.avatarUrl, isNull);
    },
  );

  test('photo lookup ignores closed and unavailable online accounts', () async {
    for (final (account, profile, status) in [
      (
        _chessCom,
        {'status': 'closed:fair_play', 'avatar': 'https://x.test/a'},
        200,
      ),
      (_lichess, {'closed': true, 'fideId': 1503014}, 200),
      (_lichess, {'disabled': true, 'fideId': 1503014}, 200),
      (_chessCom, <String, Object?>{}, 404),
      (_lichess, <String, Object?>{}, 404),
      (_chessCom, <Object>[], 200),
    ]) {
      final repo = _repository(
        (_) async => _profile(profile, status: status),
        fidePhotoLookup: (_) async => throw StateError('Must not resolve'),
      );
      expect(await repo.lookupPhoto(account), isNull);
    }
  });

  test('non-online accounts do not request an online profile photo', () async {
    final repo = _repository((_) async => throw StateError('Must not fetch'));
    for (final source in [PrepSource.manual, PrepSource.chessever]) {
      expect(
        await repo.lookupPhoto(PrepAccount(source: source, username: 'Player')),
        isNull,
      );
    }
  });

  test(
    'photo-only lookups preserve retryable HTTP and transport errors',
    () async {
      for (final status in [429, 503]) {
        final repo = _repository((_) async => _profile({}, status: status));
        expect(repo.lookupPhoto(_chessCom), throwsA(isA<PrepException>()));
      }
      final repo = _repository(
        (_) async => throw http.ClientException('offline'),
      );
      expect(repo.lookupPhoto(_chessCom), throwsA(isA<http.ClientException>()));
    },
  );
}
