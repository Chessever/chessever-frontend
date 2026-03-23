// Tests for GameRepository.getGameByAnyId
//
// Strategy: extend GameRepository (so the real routing logic runs untouched)
// and override only getGameById / getGameByLichessId to record calls and
// return stub data.  No actual Supabase queries are made.
//
// BaseRepository's field initialiser (Supabase.instance.client) requires the
// Supabase singleton to exist, so we call Supabase.initialize() once in
// setUpAll with placeholder credentials.  The overridden methods never touch
// the client, so the fake URL/key have no effect on test behaviour.

import 'package:chessever2/repository/supabase/game/game_repository.dart';
import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ---------------------------------------------------------------------------
// Tracking fake
// ---------------------------------------------------------------------------

/// Subclass of the real [GameRepository] that intercepts the two leaf methods
/// so we can assert which one [getGameByAnyId] chose to delegate to.
class _TrackingGameRepository extends GameRepository {
  String? calledGetByIdWith;
  String? calledGetByLichessIdWith;

  void reset() {
    calledGetByIdWith = null;
    calledGetByLichessIdWith = null;
  }

  @override
  Future<Games> getGameById(String id) async {
    calledGetByIdWith = id;
    return _stubGame(id);
  }

  @override
  Future<Games> getGameByLichessId(String lichessId) async {
    calledGetByLichessIdWith = lichessId;
    return _stubGame(lichessId);
  }
}

// ---------------------------------------------------------------------------
// Helper
// ---------------------------------------------------------------------------

Games _stubGame(String id) => Games(
  id: id,
  roundId: 'round-1',
  roundSlug: 'round-1',
  tourId: 'tour-1',
  tourSlug: 'tour-slug',
  players: [
    Player(
      name: 'White Player',
      title: 'GM',
      rating: 2700,
      fideId: 1,
      fed: 'USA',
      clock: 0,
      team: '',
    ),
    Player(
      name: 'Black Player',
      title: 'IM',
      rating: 2650,
      fideId: 2,
      fed: 'RUS',
      clock: 0,
      team: '',
    ),
  ],
);

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  setUpAll(() async {
    // Required for platform-channel calls made during Supabase.initialize().
    TestWidgetsFlutterBinding.ensureInitialized();

    // supabase_flutter calls SharedPreferences.getInstance() during init to
    // restore a previous auth session.  Provide an empty in-memory store so
    // the platform channel is satisfied without touching the device.
    SharedPreferences.setMockInitialValues({});

    // One-time setup: satisfy BaseRepository's `Supabase.instance.client`
    // field initialiser.  Calling initialize() a second time is a no-op in
    // supabase_flutter, so this is safe when the suite runs alongside others.
    await Supabase.initialize(
      url: 'https://placeholder.supabase.co',
      anonKey: 'placeholder-anon-key',
    );
  });

  late _TrackingGameRepository repo;
  setUp(() => repo = _TrackingGameRepository());

  // -------------------------------------------------------------------------
  group('getGameByAnyId — UUID routing', () {
    test('lowercase UUID routes to getGameById', () async {
      const id = 'fe6351a5-6354-4c16-b7f6-9124e5d9a9ef';
      await repo.getGameByAnyId(id);

      expect(repo.calledGetByIdWith, equals(id));
      expect(repo.calledGetByLichessIdWith, isNull);
    });

    test('uppercase UUID routes to getGameById (case-insensitive regex)', () async {
      const id = 'FE6351A5-6354-4C16-B7F6-9124E5D9A9EF';
      await repo.getGameByAnyId(id);

      expect(repo.calledGetByIdWith, equals(id));
      expect(repo.calledGetByLichessIdWith, isNull);
    });

    test('mixed-case UUID routes to getGameById', () async {
      const id = 'Fe6351A5-6354-4C16-b7f6-9124e5d9a9ef';
      await repo.getGameByAnyId(id);

      expect(repo.calledGetByIdWith, equals(id));
      expect(repo.calledGetByLichessIdWith, isNull);
    });

    test('UUID with leading/trailing whitespace is trimmed then routes to getGameById',
        () async {
      const bare = 'fe6351a5-6354-4c16-b7f6-9124e5d9a9ef';
      await repo.getGameByAnyId('  $bare  ');

      expect(repo.calledGetByIdWith, equals(bare), reason: 'trimmed value passed');
      expect(repo.calledGetByLichessIdWith, isNull);
    });

    test('returns the Games object produced by getGameById', () async {
      const id = 'fe6351a5-6354-4c16-b7f6-9124e5d9a9ef';
      final result = await repo.getGameByAnyId(id);

      expect(result.id, equals(id));
    });
  });

  // -------------------------------------------------------------------------
  group('getGameByAnyId — short-ID (Lichess) routing', () {
    test('8-char alphanumeric Lichess ID routes to getGameByLichessId', () async {
      const id = '4uVwSr9q';
      await repo.getGameByAnyId(id);

      expect(repo.calledGetByLichessIdWith, equals(id));
      expect(repo.calledGetByIdWith, isNull);
    });

    test('short ID with leading/trailing whitespace is trimmed then routes to getGameByLichessId',
        () async {
      const bare = '4uVwSr9q';
      await repo.getGameByAnyId('  $bare  ');

      expect(repo.calledGetByLichessIdWith, equals(bare), reason: 'trimmed value passed');
      expect(repo.calledGetByIdWith, isNull);
    });

    test('returns the Games object produced by getGameByLichessId', () async {
      const id = '4uVwSr9q';
      final result = await repo.getGameByAnyId(id);

      expect(result.id, equals(id));
    });
  });

  // -------------------------------------------------------------------------
  group('getGameByAnyId — non-UUID formats always route to getGameByLichessId', () {
    test('UUID without dashes is not a valid UUID', () async {
      // 32 hex chars, no dashes — looks UUID-ish but fails the pattern
      await repo.getGameByAnyId('fe6351a563544c16b7f69124e5d9a9ef');

      expect(repo.calledGetByLichessIdWith, isNotNull);
      expect(repo.calledGetByIdWith, isNull);
    });

    test('UUID with an extra trailing segment is not a valid UUID', () async {
      await repo.getGameByAnyId('fe6351a5-6354-4c16-b7f6-9124e5d9a9ef-extra');

      expect(repo.calledGetByLichessIdWith, isNotNull);
      expect(repo.calledGetByIdWith, isNull);
    });

    test('numeric-only string routes to getGameByLichessId', () async {
      await repo.getGameByAnyId('12345678');

      expect(repo.calledGetByLichessIdWith, equals('12345678'));
      expect(repo.calledGetByIdWith, isNull);
    });
  });

  // -------------------------------------------------------------------------
  group('getGameByAnyId — no cross-contamination between sequential calls', () {
    test('Lichess call followed by UUID call: each uses the correct method', () async {
      await repo.getGameByAnyId('4uVwSr9q');
      expect(repo.calledGetByLichessIdWith, equals('4uVwSr9q'));
      expect(repo.calledGetByIdWith, isNull);

      repo.reset();

      await repo.getGameByAnyId('fe6351a5-6354-4c16-b7f6-9124e5d9a9ef');
      expect(repo.calledGetByIdWith, equals('fe6351a5-6354-4c16-b7f6-9124e5d9a9ef'));
      expect(repo.calledGetByLichessIdWith, isNull);
    });

    test('UUID call followed by Lichess call: each uses the correct method', () async {
      await repo.getGameByAnyId('4f8a1b2c-3d4e-5f6a-7b8c-9d0e1f2a3b4c');
      expect(repo.calledGetByIdWith, isNotNull);
      expect(repo.calledGetByLichessIdWith, isNull);

      repo.reset();

      await repo.getGameByAnyId('AbCd1234');
      expect(repo.calledGetByLichessIdWith, equals('AbCd1234'));
      expect(repo.calledGetByIdWith, isNull);
    });
  });
}
