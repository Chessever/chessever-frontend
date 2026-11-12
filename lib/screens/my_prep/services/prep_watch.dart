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

/// Whether [profile] has anything the server can watch: at least one online
/// account whose download window is still open. This holds for the reader's
/// own profile too, so starring it works like any other player.
bool prepCanWatch(PrepProfile profile) => prepWatchAccounts(profile).isNotEmpty;

/// Whether [profile] shows a star: every profile with a name does. The
/// star only ever asks for this profile's new-game pushes ([prepCanWatch]
/// says whether the server has an account to check yet); it never follows
/// or favorites the player, which is the heart's job.
bool prepCanStar(PrepProfile profile) => profile.name.trim().isNotEmpty;

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

/// A starred profile as the server holds it: enough to tell every device
/// of the reader that it is starred, and to rebuild it on one that lacks it.
@immutable
class PrepWatched {
  const PrepWatched({
    required this.name,
    this.title,
    this.kind,
    this.accounts = const [],
  });

  final String name;
  final String? title;

  /// Null on rows written before the server kept it.
  final PrepKind? kind;
  final List<PrepAccount> accounts;

  /// The profile these rows describe, starred, under [id]. An older row
  /// has no kind; the id still starts with it.
  PrepProfile asProfile(String id) => PrepProfile(
    id: id,
    kind:
        kind ??
        PrepKind.values.where((k) => id.startsWith('${k.name}-')).firstOrNull ??
        PrepKind.opponent,
    name: name,
    createdAtMs: DateTime.now().millisecondsSinceEpoch,
    accounts: accounts,
    watching: true,
  );
}

/// Reads and writes the server's copy of starred profiles. A write is
/// false when it could not be made now (signed out, offline); the caller
/// keeps it to try again.
class PrepWatchRemote {
  const PrepWatchRemote();

  /// Every profile the reader stars, on any of their devices, by profile
  /// id. Null when it could not be read (signed out, offline).
  Future<Map<String, PrepWatched>?> watched() async {
    final client = _client;
    final user = client?.auth.currentUser?.id;
    if (client == null || user == null) return null;
    try {
      final rows = await client
          .from('prep_profile_watches')
          .select()
          .eq('user_id', user);
      return prepWatchedFromRows(rows);
    } catch (error) {
      debugPrint('[MyPrep] stars not read: $error');
      return null;
    }
  }

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

/// The server's rows (one per watched account) as starred profiles.
Map<String, PrepWatched> prepWatchedFromRows(List<dynamic> rows) {
  final watched = <String, PrepWatched>{};
  for (final row in rows) {
    if (row is! Map) continue;
    final id = row['profile_id']?.toString() ?? '';
    final name = row['profile_name']?.toString() ?? '';
    final source = PrepSource.tryParse(row['source']);
    final username = row['username']?.toString().trim() ?? '';
    if (id.isEmpty || name.isEmpty || source == null || username.isEmpty) {
      continue;
    }
    final title = row['profile_title']?.toString();
    final clocks = row['time_controls'];
    final kind = row['profile_kind'];
    final before = watched[id];
    watched[id] = PrepWatched(
      name: name,
      title: title,
      kind: kind == null ? before?.kind : PrepKind.tryParse(kind),
      accounts: [
        ...?before?.accounts,
        PrepAccount(
          source: source,
          username: username,
          title: title,
          preferences: PrepDownloadPreferences(
            timeControls: {
              for (final clock in PrepTimeControl.values)
                if (clocks is List && clocks.contains(clock.name)) clock,
            },
          ),
        ),
      ],
    );
  }
  return watched;
}
