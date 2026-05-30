// Tests for BaseRepository.handleApiCall's debug-only hot-restart retry.
//
// Background: on a debug hot restart, Supabase's background JSON-decode isolate
// (`yet_another_json_isolate`, used by postgrest for responses >~10KB) can be
// torn down mid-flight. Its `onExit` handler delivers a `null` into the port
// `decode()` awaits, so `_handleRes(List response)` receives `null` and throws
// `type 'Null' is not a subtype of type 'List<dynamic>'` — a `TypeError`. The
// transient clears once a fresh isolate is ready, so handleApiCall retries the
// idempotent read once (debug only — release behavior is unchanged).
//
// These tests exercise the retry decision logic with injected closures; no real
// Supabase query runs. Flutter tests run in debug mode, so the kDebugMode guard
// is active here.
//
// BaseRepository's field initialiser (Supabase.instance.client) requires the
// Supabase singleton to exist, so we call Supabase.initialize() once in
// setUpAll with placeholder credentials.

import 'package:chessever2/repository/api_utils/api_exceptions.dart';
import 'package:chessever2/repository/supabase/base_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Minimal concrete repository that just exposes the protected helper.
class _ExposedRepository extends BaseRepository {
  Future<T> run<T>(Future<T> Function() apiCall) => handleApiCall(apiCall);
}

/// Triggers a genuine [TypeError] (the same family thrown by the isolate-decode
/// teardown), without depending on a private constructor.
Never _throwTypeError() {
  final dynamic nothing = null;
  // ignore: unnecessary_cast
  (nothing as List).length; // throws a TypeError
  throw StateError('unreachable');
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://placeholder.supabase.co',
      anonKey: 'placeholder-anon-key',
    );
  });

  late _ExposedRepository repo;
  setUp(() => repo = _ExposedRepository());

  test('retries once and recovers when the first call throws a TypeError', () async {
    var calls = 0;
    final result = await repo.run<int>(() async {
      calls++;
      if (calls == 1) _throwTypeError();
      return 42;
    });

    expect(result, 42);
    expect(calls, 2, reason: 'should retry exactly once after the transient');
  });

  test('does not retry when the first call succeeds', () async {
    var calls = 0;
    final result = await repo.run<int>(() async {
      calls++;
      return 7;
    });

    expect(result, 7);
    expect(calls, 1, reason: 'happy path must run the call exactly once');
  });

  test('non-TypeError errors are wrapped without retrying', () async {
    var calls = 0;
    await expectLater(
      repo.run<int>(() async {
        calls++;
        throw StateError('boom');
      }),
      throwsA(isA<GenericApiException>()),
    );
    expect(calls, 1, reason: 'only the isolate-teardown TypeError should retry');
  });

  test('surfaces the original error when every retry keeps failing', () async {
    var calls = 0;
    await expectLater(
      repo.run<int>(() async {
        calls++;
        _throwTypeError();
      }),
      throwsA(isA<GenericApiException>()),
    );
    expect(calls, 2, reason: 'one initial attempt plus one retry, then give up');
  });
}
