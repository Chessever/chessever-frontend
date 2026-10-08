import 'dart:async';
import 'dart:isolate';

import 'package:chessever2/repository/library/library_repository.dart';
import 'package:chessever2/repository/library/models/library_folder.dart';
import 'package:chessever2/screens/chessboard/analysis/chess_game.dart';
import 'package:chessever2/screens/library/providers/library_folders_provider.dart';
import 'package:chessever2/screens/my_prep/models/prep_models.dart';
import 'package:chessever2/screens/my_prep/providers/prep_providers.dart';
import 'package:chessever2/screens/my_prep/services/prep_index.dart';
import 'package:chessever2/services/game_tree/game_tree_store.dart';
import 'package:chessever2/services/rewarded_premium/rewarded_access_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// What a player's cloud copy is doing.
@immutable
class PrepCloudStatus {
  const PrepCloudStatus({required this.message, this.done = 0, this.total});
  final String message;
  final int done;
  final int? total;
}

/// Running cloud saves by profile id.
final prepCloudSyncProvider =
    StateNotifierProvider<
      PrepCloudSyncController,
      Map<String, PrepCloudStatus>
    >((ref) => PrepCloudSyncController(ref));

/// Saves a My Prep player to the cloud Library as desktop does: a folder
/// named after them holding one database per account, and from then on
/// uploads each account's new games after every download.
///
/// Premium. A save the reader starts checks access first (see
/// `ensurePrepCloudAccess`); the automatic follow-ups run only while access
/// lasts and stop quietly when it lapses.
class PrepCloudSyncController
    extends StateNotifier<Map<String, PrepCloudStatus>> {
  PrepCloudSyncController(this._ref) : super(const {});

  final Ref _ref;
  final Set<String> _cancel = {};
  final Set<String> _again = {};

  static const int _chunk = 100;

  bool isSaving(String profileId) => state.containsKey(profileId);

  void cancel(String profileId) {
    _cancel.add(profileId);
    _again.remove(profileId);
  }

  /// Follows a download: uploads the new games of a saved player while the
  /// reader has Premium. Never asks for anything.
  void syncAfterDownload(String profileId) {
    final profile = _ref.read(prepProfilesProvider.notifier).byId(profileId);
    if (profile == null || !profile.savedToCloud) return;
    if (!_ref.read(premiumAccessProvider)) return;
    unawaited(save(profileId));
  }

  /// Creates (or finds again) the player's cloud folder and databases and
  /// uploads every game not there yet. Returns the error text, or null.
  Future<String?> save(String profileId) async {
    if (isSaving(profileId)) {
      // Another account finished downloading mid-save: go again after.
      _again.add(profileId);
      return null;
    }
    _cancel.remove(profileId);
    final profiles = _ref.read(prepProfilesProvider.notifier);
    var profile = profiles.byId(profileId);
    if (profile == null) return null;
    final library = _ref.read(libraryRepositoryProvider);
    if (library.supabase.auth.currentUser == null) {
      return 'Sign in to save players to your cloud Library.';
    }
    void report(String message, {int done = 0, int? total}) {
      if (!mounted) return;
      state = {
        ...state,
        profileId: PrepCloudStatus(message: message, done: done, total: total),
      };
    }

    report('Preparing the cloud folder…');
    try {
      // The folder, created again when it was deleted from the Library.
      var folderId = profile.cloudFolderId;
      if (folderId == null || await library.getFolder(folderId) == null) {
        final folder = await library.createFolder(
          name: profile.name,
          nodeType: LibraryFolder.nodeTypeFolder,
        );
        folderId = folder.id;
        profiles.edit(
          profileId,
          (p) => p.copyWith(
            cloudFolderId: folder.id,
            accounts: [
              for (final a in p.accounts) a.copyWith(clearCloud: true),
            ],
          ),
        );
      }
      profile = profiles.byId(profileId)!;

      final repo = _ref.read(prepRepositoryProvider);
      // Each account's database, created again when it was deleted (and
      // then filled from its first game).
      final accounts = <PrepAccount>[];
      for (var account in profile.accounts) {
        final id = account.cloudDatabaseId;
        if (id == null || await library.getFolder(id) == null) {
          final database = await library.createFolder(
            name: '${account.source.label} · ${account.username}',
            parentId: folderId,
            nodeType: LibraryFolder.nodeTypeDatabase,
          );
          account = account.copyWith(
            cloudDatabaseId: database.id,
            cloudSyncedTs: -1,
            cloudSyncedCount: 0,
          );
          _saveAccount(profileId, account);
        }
        accounts.add(account);
      }
      final pending = <(PrepAccount, GameTreeStore, List<(int, int)>)>[];
      var total = 0;
      for (final account in accounts) {
        if (_cancel.contains(profileId)) return null;
        // Combined deduplicates across sources. Each cloud database must
        // preserve its own games, including duplicates in another account.
        final store = await PrepIndex.ensureAccount(repo, profile, account);
        final path = (await repo.gamesFile(account)).path;
        final rows = store.rowsAfter(path, account.cloudSyncedTs ?? -1);
        pending.add((account, store, rows));
        total += rows.length;
      }
      var done = 0;
      report('Saving games to the cloud…', total: total);
      for (var (account, store, rows) in pending) {
        final databaseId = account.cloudDatabaseId!;
        for (var i = 0; i < rows.length; i += _chunk) {
          if (_cancel.contains(profileId)) return null;
          final slice = rows.sublist(i, (i + _chunk).clamp(0, rows.length));
          final games = <(String, String)>[
            for (final (row, _) in slice)
              if (store.pgn(row) case final pgn?) ('prep-$row', pgn),
          ];
          final payload = await _rowsOnIsolate(games);
          await library.insertSavedAnalysisRows(databaseId, payload);
          account = account.copyWith(
            cloudSyncedTs: slice.last.$2,
            cloudSyncedCount: account.cloudSyncedCount + payload.length,
          );
          _saveAccount(profileId, account);
          done += slice.length;
          report('Saving games to the cloud…', done: done, total: total);
        }
      }
      _ref.invalidate(libraryFoldersStreamProvider);
      return null;
    } catch (error) {
      debugPrint('[MyPrep] cloud save failed: $error');
      return 'Could not save to the cloud. Check your connection and try again.';
    } finally {
      if (mounted) state = {...state}..remove(profileId);
      if (_again.remove(profileId) && mounted) unawaited(save(profileId));
    }
  }

  void _saveAccount(String profileId, PrepAccount account) {
    _ref.read(prepProfilesProvider.notifier).edit(profileId, (p) {
      final live = p.accounts.where((a) => a.key == account.key).firstOrNull;
      if (live == null) return p;
      return p.replaceAccount(
        live.copyWith(
          cloudDatabaseId: account.cloudDatabaseId,
          cloudSyncedTs: account.cloudSyncedTs,
          cloudSyncedCount: account.cloudSyncedCount,
        ),
      );
    });
  }

  /// Forgets the cloud link; the cloud copy itself stays in the Library.
  void unlink(String profileId) {
    _ref
        .read(prepProfilesProvider.notifier)
        .edit(
          profileId,
          (p) => p.copyWith(
            clearCloud: true,
            accounts: [
              for (final a in p.accounts) a.copyWith(clearCloud: true),
            ],
          ),
        );
  }
}

// Top-level so the isolate's closure captures only [games], never the
// controller (which holds a Ref and cannot cross isolates).
Future<List<Map<String, dynamic>>> _rowsOnIsolate(
  List<(String, String)> games,
) => Isolate.run(() => _savedAnalysisRows(games), debugName: 'prep-cloud-rows');

/// Saved-analysis rows for (id, PGN) pairs, parsed off the UI isolate.
List<Map<String, dynamic>> _savedAnalysisRows(List<(String, String)> games) {
  final rows = <Map<String, dynamic>>[];
  for (final (id, pgn) in games) {
    final ChessGame game;
    try {
      game = ChessGame.fromPgn(id, pgn);
    } catch (_) {
      continue;
    }
    final white = (game.metadata['White']?.toString().trim() ?? '');
    final black = (game.metadata['Black']?.toString().trim() ?? '');
    rows.add({
      'title':
          '${white.isEmpty ? 'White' : white} vs '
          '${black.isEmpty ? 'Black' : black}',
      'source_game_id': null,
      'source_tournament_id': null,
      'chess_game': game.toJson(),
      'analysis_state': const <String, dynamic>{},
      'variation_comments': const <String, String>{},
      'move_nags': const <String, List<int>>{},
      'last_viewed_position': -1,
      'tags': const <String>[],
      'notes': null,
      'is_favorite': false,
    });
  }
  return rows;
}
