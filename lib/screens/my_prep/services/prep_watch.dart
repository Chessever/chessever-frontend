import 'dart:convert';

import 'package:chessever2/screens/my_prep/models/prep_models.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Starring a Prep profile asks the server to watch the player: every hour
/// it reads the player's game totals on Lichess and Chess.com, and when they
/// grew it pushes the same day, while the reader is awake, twice a day at
/// most. Profiles live on the device, so a starred profile's online accounts
/// are mirrored to `prep_profile_watches`
/// (`supabase/migrations/20261017120000_prep_profile_watches.sql`).

/// Whether [profile] has anything the server can watch. The reader's own
/// games are not news to them, and only online accounts keep getting games.
bool prepCanWatch(PrepProfile profile) =>
    profile.kind != PrepKind.mine && prepWatchAccounts(profile).isNotEmpty;

/// The accounts the server checks for [profile], counted over the clocks
/// each one downloads. One with a fixed end date gets no new games.
List<Map<String, Object?>> prepWatchAccounts(PrepProfile profile) => [
  for (final account in profile.accounts)
    if (account.source.online && account.preferences.untilMs == null)
      {
        'source': account.source.name,
        'username': account.username,
        'time_controls': [
          for (final clock in account.preferences.timeControls) clock.name,
        ]..sort(),
      },
];

/// What the server holds for a starred [profile], or null while it is not
/// watched. A change means the server's copy must be written again.
String? prepWatchSignature(PrepProfile profile) =>
    profile.watching && prepCanWatch(profile)
    ? jsonEncode([profile.name, profile.title, prepWatchAccounts(profile)])
    : null;

/// Writes the server's copy of starred profiles. False when it could not
/// be written now (signed out, offline); the caller keeps it to try again.
class PrepWatchRemote {
  const PrepWatchRemote();

  SupabaseClient? get _client {
    try {
      final client = Supabase.instance.client;
      return client.auth.currentUser == null ? null : client;
    } catch (_) {
      // Not initialized (tests, a very early call).
      return null;
    }
  }

  Future<bool> watch(PrepProfile profile) async {
    final client = _client;
    if (client == null) return false;
    try {
      await client.rpc(
        'set_prep_profile_watch',
        params: {
          'p_profile_id': profile.id,
          'p_profile_name': profile.name,
          'p_profile_title': profile.title,
          'p_accounts': prepWatchAccounts(profile),
          // The reader's day moves with them; every write carries it.
          'p_utc_offset_minutes': DateTime.now().timeZoneOffset.inMinutes,
        },
      );
      return true;
    } catch (error) {
      debugPrint('[MyPrep] star not saved: $error');
      return false;
    }
  }

  Future<bool> unwatch(String profileId) async {
    final client = _client;
    if (client == null) return false;
    try {
      await client.rpc(
        'clear_prep_profile_watch',
        params: {'p_profile_id': profileId},
      );
      return true;
    } catch (error) {
      debugPrint('[MyPrep] unstar not saved: $error');
      return false;
    }
  }
}

final prepWatchRemoteProvider = Provider<PrepWatchRemote>(
  (ref) => const PrepWatchRemote(),
);
