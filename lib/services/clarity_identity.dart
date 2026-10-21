import 'dart:async';

import 'package:clarity_flutter/clarity_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Connects recordings to backend accounts, including anonymous guest accounts.
/// Start after Clarity initialization so delayed startup cannot miss auth events.
class ClarityIdentity {
  ClarityIdentity._();
  static final instance = ClarityIdentity._();
  StreamSubscription<AuthState>? _subscription;
  SupabaseClient? _client;
  String? _userId;

  void start(SupabaseClient client) {
    if (_subscription != null) return;
    _client = client;
    _userId = client.auth.currentUser?.id;
    Clarity.setOnSessionStartedCallback(_identifyCurrentUser);
    _identify();
    _subscription = client.auth.onAuthStateChange.listen((event) {
      final next = event.session?.user.id;
      if (next == _userId) return;
      _userId = next;
      // A recording must not retain a previous account's identity after logout
      // or an account switch. Read current auth in the callback to avoid races.
      Clarity.startNewSession(_identifyCurrentUser);
    });
  }

  /// Clarity carries a new session's callback to its session isolate inside
  /// an event, so it must be sendable: a static tear-off. A closure over this
  /// instance drags the SupabaseClient and its isolate handles along, and the
  /// send throws "object is unsendable" (CHESSEVER-23T).
  static void _identifyCurrentUser(String _) => instance._identify();

  void _identify() {
    if (_client == null) return;
    Clarity.setCustomUserId(_client!.auth.currentUser?.id ?? 'signed-out');
  }

  void stop() {
    unawaited(_subscription?.cancel());
    _subscription = null;
    _client = null;
    _userId = null;
  }
}
