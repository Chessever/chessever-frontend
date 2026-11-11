import 'dart:convert';

import 'package:chessever2/screens/my_prep/data/prep_favorites.dart';
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

/// Whether [profile] has anything the server can watch: at least one online
/// account whose download window is still open. This holds for the reader's
/// own profile too, so starring it works like any other player.
bool prepCanWatch(PrepProfile profile) => prepWatchAccounts(profile).isNotEmpty;

/// The ChessEver database player a profile's star follows when there is no
/// online account to check (an over-the-board player such as one added
/// from Players): by FIDE id, or by the database's own name when the player
/// has none. Starring follows them like the Players star does, so the push
/// comes when they sit down at a live broadcast board. Null when the star
/// watches online accounts instead, or there is nothing to follow. The
/// reader's own profile is never followed into broadcasts: that push would
/// be about themselves.
({String? fideId, String name})? prepStarPlayer(PrepProfile profile) {
  if (profile.kind == PrepKind.mine || prepCanWatch(profile)) return null;
  final database = profile.databaseAccount;
  final name = (database?.username ?? profile.name).trim();
  final fide = prepFavoriteFide(profile)?.trim();
  if (fide != null && (int.tryParse(fide) ?? 0) > 0 && name.isNotEmpty) {
    return (fideId: fide, name: name);
  }
  if (database == null || name.isEmpty) return null;
  return (fideId: null, name: name);
}

/// Whether [profile]'s row and top bar show a star at all.
bool prepCanStar(PrepProfile profile) =>
    prepCanWatch(profile) || prepStarPlayer(profile) != null;

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
    final params = <String, Object?>{
      'p_profile_id': profile.id,
      'p_profile_name': profile.name,
      'p_profile_title': profile.title,
      'p_accounts': prepWatchAccounts(profile),
      // The reader's day moves with them; every write carries it.
      'p_utc_offset_minutes': DateTime.now().timeZoneOffset.inMinutes,
      // Lets the push speak to the reader about their own games.
      'p_profile_kind': profile.kind.name,
    };
    try {
      await client.rpc('set_prep_profile_watch', params: params);
      return true;
    } on PostgrestException catch (error) {
      // A server without p_profile_kind (PGRST202: no such signature)
      // still takes the star; only the push's wording waits for it.
      if (error.code == 'PGRST202') {
        try {
          await client.rpc(
            'set_prep_profile_watch',
            params: {...params}..remove('p_profile_kind'),
          );
          return true;
        } catch (retry) {
          debugPrint('[MyPrep] star not saved: $retry');
          return false;
        }
      }
      debugPrint('[MyPrep] star not saved: $error');
      return false;
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
