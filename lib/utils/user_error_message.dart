import 'dart:async';

/// Converts any thrown error/exception into a safe, user-facing English message.
///
/// **Never returns the raw error text.** Backend/API/endpoint errors — URLs,
/// HTTP status bodies, PostgREST/Dio/Supabase payloads, SQL, stack traces — must
/// never reach the UI. They leak internal implementation details and read as
/// gibberish to users. This classifies a few common failure shapes (offline,
/// timeout, auth, not-found, server) into friendly copy, and otherwise returns a
/// generic fallback.
///
/// Always log the real [error] separately for debugging (e.g.
/// `talker.handle(e, st)`); this helper is only for what the user sees.
///
/// ```dart
/// } catch (e, st) {
///   talker.handle(e, st);                       // dev diagnostics
///   showSnack(userFacingError(e,                 // safe user copy
///       fallback: 'Could not save this game. Please try again.'));
/// }
/// ```
String userFacingError(Object? error, {String? fallback}) {
  final generic = fallback ?? 'Something went wrong. Please try again.';
  if (error == null) return generic;

  // Only ever inspect the raw text for classification — never forward it.
  final raw = error.toString().toLowerCase();

  // Connectivity / offline.
  if (raw.contains('socketexception') ||
      raw.contains('clientexception') ||
      raw.contains('failed host lookup') ||
      raw.contains('network is unreachable') ||
      raw.contains('connection refused') ||
      raw.contains('connection closed') ||
      raw.contains('connection reset') ||
      raw.contains('connection error') ||
      raw.contains('no address associated with hostname') ||
      raw.contains('xmlhttprequest')) {
    return 'No internet connection. Please check your network and try again.';
  }

  // Timeouts.
  if (error is TimeoutException ||
      raw.contains('timeout') ||
      raw.contains('timed out')) {
    return 'The request timed out. Please try again.';
  }

  // Auth / session.
  if (raw.contains('unauthorized') ||
      raw.contains('forbidden') ||
      raw.contains('not authenticated') ||
      raw.contains('jwt expired') ||
      raw.contains('invalid token') ||
      raw.contains(' 401') ||
      raw.contains(' 403')) {
    return 'Your session has expired. Please sign in again.';
  }

  // Missing resource.
  if (raw.contains('not found') || raw.contains(' 404')) {
    return "We couldn't find what you were looking for.";
  }

  // Server-side trouble.
  if (raw.contains('internal server error') ||
      raw.contains('bad gateway') ||
      raw.contains('service unavailable') ||
      raw.contains(' 500') ||
      raw.contains(' 502') ||
      raw.contains(' 503')) {
    return 'Our servers are having trouble right now. Please try again shortly.';
  }

  return generic;
}
