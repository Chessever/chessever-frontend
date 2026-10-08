import 'package:chessever2/screens/my_prep/models/prep_models.dart';
import 'package:chessever2/screens/my_prep/services/prep_repository.dart';
import 'package:chessever2/services/game_tree/game_tree_builder.dart';
import 'package:chessever2/services/game_tree/game_tree_service.dart';
import 'package:chessever2/services/game_tree/game_tree_store.dart';

/// The opening indexes behind My Prep: one per profile (every account's
/// games together, the Combined database) and, when the reader builds one
/// from the Library, one per account.
///
/// Each reads the account PGN files in place. A sync appends to those
/// files, so bringing an index up to date reads only the new games.
abstract final class PrepIndex {
  static const Map<String, String> sourceLabels = {
    'chessever': 'ChessEver',
    'manual': 'PGN',
    'lichess': 'Lichess',
    'chesscom': 'Chess.com',
  };

  /// The scope of one account's own tree.
  static String accountScope(PrepAccount account) =>
      GameTreeService.scopeFor('prep-account:${account.key}');

  static Future<List<GameTreeSourceFile>> _sources(
    PrepRepository repo,
    Iterable<PrepAccount> accounts,
  ) async => [
    for (final account in accounts)
      GameTreeSourceFile(
        path: (await repo.gamesFile(account)).path,
        kind: account.source.name,
      ),
  ];

  /// The profile's Combined index, brought up to date.
  static Future<GameTreeStore> ensureProfile(
    PrepRepository repo,
    PrepProfile profile, {
    void Function(double fraction)? onProgress,
  }) async => GameTreeService.ensure(
    scopeId: profile.id,
    sources: await _sources(repo, profile.accounts),
    aliases: profile.aliases.toList(),
    playerScope: true,
    onProgress: onProgress,
    sourceLabels: sourceLabels,
  );

  /// One account's own index, brought up to date.
  static Future<GameTreeStore> ensureAccount(
    PrepRepository repo,
    PrepProfile profile,
    PrepAccount account, {
    void Function(double fraction)? onProgress,
  }) async => GameTreeService.ensure(
    scopeId: accountScope(account),
    sources: await _sources(repo, [account]),
    aliases: profile.aliases.toList(),
    playerScope: true,
    onProgress: onProgress,
    sourceLabels: sourceLabels,
  );

  /// Deletes every index a profile (or one of its accounts) owns.
  static Future<void> forget(
    String profileId, {
    Iterable<PrepAccount> accounts = const [],
    bool profileToo = true,
  }) async {
    if (profileToo) await GameTreeService.delete(profileId);
    for (final account in accounts) {
      await GameTreeService.delete(accountScope(account));
    }
  }
}
