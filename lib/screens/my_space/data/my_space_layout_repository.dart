import 'package:chessever2/screens/my_space/domain/my_space_layout.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum MySpaceLayoutFailureKind {
  unauthenticated,
  premiumRequired,
  revisionConflict,
  invalidDocument,
  unavailable,
}

final class MySpaceLayoutException implements Exception {
  const MySpaceLayoutException({
    required this.kind,
    required this.message,
    this.cause,
  });

  final MySpaceLayoutFailureKind kind;
  final String message;
  final Object? cause;

  @override
  String toString() => 'MySpaceLayoutException(${kind.name}): $message';
}

final class MySpaceStoredLayout {
  const MySpaceStoredLayout({
    required this.userId,
    required this.layout,
    required this.revision,
    required this.createdAt,
    required this.updatedAt,
  });

  final String userId;
  final MySpaceLayout layout;
  final int revision;
  final DateTime createdAt;
  final DateTime updatedAt;
}

abstract interface class MySpaceLayoutBackend {
  Future<Map<String, dynamic>?> fetchCurrentUserLayout();

  Future<Map<String, dynamic>> saveCurrentUserLayout({
    required Map<String, dynamic> layout,
    required int expectedRevision,
  });
}

final class SupabaseMySpaceLayoutBackend implements MySpaceLayoutBackend {
  const SupabaseMySpaceLayoutBackend(this._client);

  final SupabaseClient _client;

  @override
  Future<Map<String, dynamic>?> fetchCurrentUserLayout() async {
    final userId = _requireUserId();
    try {
      final row =
          await _client
              .from('user_my_space_layouts')
              .select(
                'user_id, schema_version, revision, shelves, created_at, updated_at',
              )
              .eq('user_id', userId)
              .maybeSingle();
      return row == null ? null : Map<String, dynamic>.from(row);
    } on PostgrestException catch (error) {
      throw mapMySpacePostgrestException(error);
    } catch (error) {
      throw MySpaceLayoutException(
        kind: MySpaceLayoutFailureKind.unavailable,
        message: 'The My Space layout could not be loaded.',
        cause: error,
      );
    }
  }

  @override
  Future<Map<String, dynamic>> saveCurrentUserLayout({
    required Map<String, dynamic> layout,
    required int expectedRevision,
  }) async {
    _requireUserId();
    try {
      final response = await _client.rpc(
        'save_my_space_layout',
        params: {'p_layout': layout, 'p_expected_revision': expectedRevision},
      );
      if (response is Map) return Map<String, dynamic>.from(response);
      if (response is List && response.length == 1 && response.single is Map) {
        return Map<String, dynamic>.from(response.single as Map);
      }
      throw const FormatException(
        'save_my_space_layout returned an invalid row payload.',
      );
    } on PostgrestException catch (error) {
      throw mapMySpacePostgrestException(error);
    } on MySpaceLayoutException {
      rethrow;
    } catch (error) {
      throw MySpaceLayoutException(
        kind: MySpaceLayoutFailureKind.unavailable,
        message: 'The My Space layout could not be saved.',
        cause: error,
      );
    }
  }

  String _requireUserId() {
    final userId = _client.auth.currentUser?.id;
    if (userId == null || userId.isEmpty) {
      throw const MySpaceLayoutException(
        kind: MySpaceLayoutFailureKind.unauthenticated,
        message: 'Sign in to use a saved My Space layout.',
      );
    }
    return userId;
  }
}

final class MySpaceLayoutRepository {
  const MySpaceLayoutRepository(this._backend);

  final MySpaceLayoutBackend _backend;

  Future<MySpaceStoredLayout?> fetch() async {
    final row = await _backend.fetchCurrentUserLayout();
    return row == null ? null : decodeMySpaceStoredLayout(row);
  }

  Future<MySpaceStoredLayout> save({
    required MySpaceLayout layout,
    required int expectedRevision,
  }) async {
    if (expectedRevision < 0) {
      throw ArgumentError.value(
        expectedRevision,
        'expectedRevision',
        'Must be zero for an insert or a positive stored revision.',
      );
    }
    final payload = layout.toJson();
    final row = await _backend.saveCurrentUserLayout(
      layout: payload,
      expectedRevision: expectedRevision,
    );
    return decodeMySpaceStoredLayout(row);
  }
}

final mySpaceLayoutRepositoryProvider = Provider<MySpaceLayoutRepository>((
  ref,
) {
  return MySpaceLayoutRepository(
    SupabaseMySpaceLayoutBackend(Supabase.instance.client),
  );
});

MySpaceStoredLayout decodeMySpaceStoredLayout(Map<String, dynamic> row) {
  final userId = _requiredString(row['user_id'], 'user_id');
  final schemaVersion = _requiredInt(row['schema_version'], 'schema_version');
  final revision = _requiredInt(row['revision'], 'revision');
  if (revision < 1) {
    throw const FormatException('revision must be positive.');
  }
  final shelves = row['shelves'];
  if (shelves is! List) {
    throw const FormatException('shelves must be a JSON array.');
  }

  return MySpaceStoredLayout(
    userId: userId,
    layout: MySpaceLayout.fromJson({
      'schema_version': schemaVersion,
      'shelves': shelves,
    }),
    revision: revision,
    createdAt: _requiredDate(row['created_at'], 'created_at'),
    updatedAt: _requiredDate(row['updated_at'], 'updated_at'),
  );
}

MySpaceLayoutException mapMySpacePostgrestException(PostgrestException error) {
  final signal =
      <Object?>[
        error.message,
        error.details,
        error.hint,
      ].whereType<Object>().join(' ').toUpperCase();

  if (signal.contains('MY_SPACE_LAYOUT_UNAUTHENTICATED') ||
      error.code == '28000') {
    return MySpaceLayoutException(
      kind: MySpaceLayoutFailureKind.unauthenticated,
      message: 'Sign in to save your My Space layout.',
      cause: error,
    );
  }
  if (signal.contains('MY_SPACE_LAYOUT_PREMIUM_REQUIRED')) {
    return MySpaceLayoutException(
      kind: MySpaceLayoutFailureKind.premiumRequired,
      message: 'Premium is required to customize My Space.',
      cause: error,
    );
  }
  if (signal.contains('MY_SPACE_LAYOUT_REVISION_CONFLICT') ||
      error.code == '40001') {
    return MySpaceLayoutException(
      kind: MySpaceLayoutFailureKind.revisionConflict,
      message: 'My Space changed on another device. Reload and try again.',
      cause: error,
    );
  }
  if (signal.contains('MY_SPACE_LAYOUT_INVALID') ||
      signal.contains('MY_SPACE_LAYOUT_UNSUPPORTED') ||
      signal.contains('MY_SPACE_LAYOUT_DUPLICATE') ||
      signal.contains('MY_SPACE_LAYOUT_TOO_MANY') ||
      signal.contains('MY_SPACE_LAYOUT_PAYLOAD_TOO_LARGE') ||
      error.code == '22001' ||
      error.code == '22023') {
    return MySpaceLayoutException(
      kind: MySpaceLayoutFailureKind.invalidDocument,
      message: 'This My Space layout is not valid for the current app version.',
      cause: error,
    );
  }
  return MySpaceLayoutException(
    kind: MySpaceLayoutFailureKind.unavailable,
    message: 'The My Space service is unavailable right now.',
    cause: error,
  );
}

String _requiredString(Object? value, String field) {
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('$field must be a non-empty string.');
  }
  return value;
}

int _requiredInt(Object? value, String field) {
  if (value is int) return value;
  if (value is num && value.isFinite && value == value.roundToDouble()) {
    return value.toInt();
  }
  throw FormatException('$field must be an integer.');
}

DateTime _requiredDate(Object? value, String field) {
  if (value is String) {
    final parsed = DateTime.tryParse(value);
    if (parsed != null) return parsed;
  }
  throw FormatException('$field must be an ISO-8601 timestamp.');
}
