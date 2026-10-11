import 'dart:async';

import 'package:chessever2/screens/my_prep/data/prep_favorites.dart';
import 'package:chessever2/screens/my_prep/models/prep_models.dart';
import 'package:chessever2/utils/transient_request_retry.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The Lichess and Chess.com handles ChessEver has published for FIDE
/// players (`player_online_accounts`), by FIDE id. The list is curated on
/// the server, so a handle added or withdrawn there reaches every reader
/// the next time My Prep reads it.
///
/// It fails rather than answer with nothing: an unreachable or still empty
/// table must not read as "no player has a handle".
final prepKnownAccountsProvider = FutureProvider.autoDispose<PrepKnownAccounts>(
  (ref) async {
    // Once read, kept a while past its last reader, then read again.
    final link = ref.keepAlive();
    Timer? expiry;
    var disposed = false;
    ref.onDispose(() {
      disposed = true;
      expiry?.cancel();
    });
    try {
      final known = <String, List<(PrepSource, String)>>{};
      for (var from = 0; ; from += _page) {
        final rows = await retryTransientRead(
          () => Supabase.instance.client
              .from('player_online_accounts')
              .select('fide_id, platform, username')
              // A stable order, so pages neither repeat nor skip a row.
              .order('fide_id')
              .order('platform')
              .order('username')
              .range(from, from + _page - 1),
        );
        for (final row in rows) {
          final source = switch (row['platform']) {
            'lichess' => PrepSource.lichess,
            'chesscom' => PrepSource.chesscom,
            _ => null,
          };
          final username = row['username']?.toString().trim() ?? '';
          if (source == null || username.isEmpty) continue;
          (known['${row['fide_id']}'] ??= []).add((source, username));
        }
        if (rows.length < _page) break;
      }
      if (known.isEmpty) throw StateError('No handles are published yet.');
      if (!disposed) expiry = Timer(const Duration(minutes: 15), link.close);
      return known;
    } catch (_) {
      link.close();
      rethrow;
    }
  },
);

const int _page = 1000;

/// The handles to go by right now: the server's once they are read, the
/// ones shipped with the app until then and whenever it cannot be reached.
final prepKnownAccountsNowProvider = Provider.autoDispose<PrepKnownAccounts>(
  (ref) =>
      ref.watch(prepKnownAccountsProvider).valueOrNull ?? kPrepBundledAccounts,
);

/// The same list for an action about to show it, which gives the server a
/// moment to answer before settling for the shipped one.
Future<PrepKnownAccounts> prepKnownAccounts(WidgetRef ref) async {
  try {
    return await ref
        .read(prepKnownAccountsProvider.future)
        .timeout(const Duration(seconds: 4));
  } catch (_) {
    return kPrepBundledAccounts;
  }
}
