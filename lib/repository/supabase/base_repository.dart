import 'dart:async';
import 'dart:io';
import 'package:chessever2/repository/api_utils/api_exceptions.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

abstract class BaseRepository {
  final SupabaseClient _supabase = Supabase.instance.client;

  SupabaseClient get supabase => _supabase;

  Future<T> handleApiCall<T>(Future<T> Function() apiCall) async {
    try {
      return await apiCall();
    } on PostgrestException catch (e) {
      throw _handlePostgrestException(e);
    } on SocketException {
      throw NetworkException('No internet connection');
    } on TimeoutException {
      throw NetworkException('Request timeout');
    } catch (e) {
      // Debug-only hot-restart recovery.
      //
      // A hot restart can tear down Supabase's background JSON-decode isolate
      // (`yet_another_json_isolate`, which postgrest uses for responses larger
      // than ~10KB) mid-flight. The dying isolate's `onExit` handler delivers a
      // `null` into the same port `decode()` is awaiting, so its
      // `_handleRes(List response)` receives `null` and throws
      // `type 'Null' is not a subtype of type 'List<dynamic>'`. It is a
      // transient that clears the moment a fresh isolate is ready, and it can
      // never occur in a release build (release builds do not hot restart).
      //
      // Guarded on `kDebugMode` so release/production behavior stays byte for
      // byte identical (the whole block is tree-shaken away in release). Reads
      // are idempotent, so retry the call once — bounded by a timeout so a
      // genuinely dead isolate can't leave the restart stuck.
      if (kDebugMode && e is TypeError) {
        try {
          await Future<void>.delayed(const Duration(milliseconds: 100));
          return await apiCall().timeout(const Duration(seconds: 5));
        } catch (_) {
          // Retry failed or timed out — fall through to the original error.
        }
      }
      throw GenericApiException('Unexpected error: ${e.toString()}');
    }
  }

  Exception _handlePostgrestException(PostgrestException e) {
    switch (e.code) {
      case '23503':
        return NotFoundException('Referenced resource not found');
      case '23505':
        return GenericApiException('Duplicate entry');
      case '42P01':
        return GenericApiException('Table does not exist');
      case 'PGRST116':
        return NotFoundException('No rows found');
      default:
        if (e.message.toLowerCase().contains('rate limit')) {
          return RateLimitException('Too many requests');
        }
        return GenericApiException('Database error: ${e.message}');
    }
  }
}
