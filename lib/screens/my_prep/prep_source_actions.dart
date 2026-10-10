import 'dart:async';
import 'dart:io';

import 'package:chessever2/screens/my_prep/models/prep_models.dart';
import 'package:chessever2/screens/my_prep/prep_access.dart';
import 'package:chessever2/screens/my_prep/prep_actions.dart';
import 'package:chessever2/screens/my_prep/library/prep_cloud_sync.dart';
import 'package:chessever2/screens/my_prep/providers/prep_providers.dart';
import 'package:chessever2/screens/my_prep/services/prep_repository.dart';
import 'package:chessever2/screens/my_prep/widgets/prep_import_dialog.dart';
import 'package:chessever2/screens/my_prep/services/prep_pgn_intake.dart';
import 'package:chessever2/screens/my_prep/widgets/prep_options_dialog.dart';
import 'package:chessever2/screens/my_prep/widgets/prep_source_picker.dart';
import 'package:chessever2/widgets/alert_dialog/alert_modal.dart';
import 'package:chessever2/widgets/app_snack.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:share_plus/share_plus.dart';

Future<void> prepDetachSource(
  BuildContext context,
  WidgetRef ref,
  PrepProfile profile,
  PrepAccount account,
) async {
  final confirmed = await showSmoothConfirmDialog(
    context: context,
    title: 'Detach ${account.source.label}?',
    message:
        '${account.source.online ? account.username : account.displayName ?? account.username} and its downloaded games '
        'will be removed from this profile on this device. Other sources stay attached.',
    confirmText: 'Detach',
    isDangerous: true,
  );
  if (confirmed != true || !context.mounted) return;
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    await ref
        .read(prepProfilesProvider.notifier)
        .removeAccount(profile.id, account);
    if (messenger != null) {
      showAppSnackOn(messenger, '${account.username} detached');
    }
  } catch (_) {
    if (messenger != null) {
      showAppSnackOn(
        messenger,
        'Could not remove the downloaded games. Try again.',
        tone: AppSnackTone.danger,
      );
    }
  }
}

Future<void> prepEditDownloadOptions(
  BuildContext context,
  WidgetRef ref,
  PrepProfile profile,
  PrepAccount account, {
  bool download = false,
}) async {
  if (!await ensurePrepAccess(context) || !context.mounted) return;
  final options = await showPrepDownloadOptionsDialog(
    context,
    account: account,
    download: download,
  );
  if (options == null || !context.mounted) return;
  await ref.read(prepSyncProvider.notifier).cancelAndWait(account);
  if (!context.mounted) return;
  ref.read(prepProfilesProvider.notifier).edit(profile.id, (p) {
    final live = p.accounts.where((a) => a.key == account.key).firstOrNull;
    return live == null
        ? p
        : p.replaceAccount(live.copyWith(preferences: options));
  });
  final live = ref
      .read(prepProfileProvider(profile.id))
      ?.accounts
      .where((a) => a.key == account.key)
      .firstOrNull;
  if (live != null && (download || live.lastSyncAtMs != null)) {
    await prepRefreshAccount(context, ref, profile.id, live);
  }
}

/// Starts the first download of accounts the reader just attached, so a new
/// source never sits idle. Accounts from the add dialog are [scoped]: each
/// already carries the clocks and period chosen there. Otherwise ChessEver
/// starts at once with its saved scope and the online accounts ask once
/// which clocks and period to take, as desktop does. Declining leaves them
/// ready to download later.
Future<void> prepStartDownloads(
  BuildContext context,
  WidgetRef ref,
  String profileId,
  Iterable<PrepAccount> attached, {
  bool scoped = false,
}) async {
  final sync = ref.read(prepSyncProvider.notifier);
  final profiles = ref.read(prepProfilesProvider.notifier);
  PrepAccount? live(PrepAccount account) => profiles
      .byId(profileId)
      ?.accounts
      .where((a) => a.key == account.key)
      .firstOrNull;
  final fresh = [
    for (final account in attached)
      if (live(account) case final a? when a.lastSyncAtMs == null) a,
  ];
  for (final account in fresh) {
    if (scoped || account.source == PrepSource.chessever) {
      unawaited(sync.syncAccount(profileId, account));
    }
  }
  if (scoped) return;
  final online = fresh.where((a) => a.source.online).toList();
  if (online.isEmpty || !context.mounted) return;
  final options = await showPrepDownloadOptionsDialog(
    context,
    account: online.first,
    others: online.sublist(1),
    download: true,
    initial: PrepDownloadPreferences.initialFor(online.first.source),
  );
  if (options == null) return;
  for (final account in online) {
    final clocks = options.timeControls.intersection(
      PrepTimeControl.offeredBy(account.source).toSet(),
    );
    // None of the chosen clocks exist on this site: nothing to take from it.
    if (options.timeControls.isNotEmpty && clocks.isEmpty) continue;
    final chosen = PrepDownloadPreferences(
      timeControls: clocks,
      range: options.range,
      fromDate: options.fromDate,
      toDate: options.toDate,
    );
    profiles.edit(profileId, (p) {
      final current = p.accounts.where((a) => a.key == account.key).firstOrNull;
      return current == null
          ? p
          : p.replaceAccount(current.copyWith(preferences: chosen));
    });
    if (live(account) case final ready?) {
      unawaited(sync.syncAccount(profileId, ready));
    }
  }
}

/// Online downloads offer the saved scope before the reader starts them.
Future<void> prepDownloadSource(
  BuildContext context,
  WidgetRef ref,
  PrepProfile profile,
  PrepAccount account,
) => account.source.online
    ? prepEditDownloadOptions(context, ref, profile, account, download: true)
    : prepRefreshAccount(context, ref, profile.id, account);

Future<void> prepChangeAccount(
  BuildContext context,
  WidgetRef ref,
  PrepProfile profile,
  PrepAccount account,
) async {
  if (!await ensurePrepAccess(context) || !context.mounted) return;
  final result = await showPrepSourcePicker(
    context,
    kind: profile.kind,
    only: account.source,
    attaching: true,
    // A downloaded account's scope is already chosen; its replacement
    // takes the same games without asking again.
    askScope: account.lastSyncAtMs == null,
    existingKeys: {for (final a in profile.accounts) a.key},
  );
  if (result == null || !context.mounted) return;
  final profiles = ref.read(prepProfilesProvider.notifier);
  final picked = result.accounts.single;
  final replacement = account.lastSyncAtMs == null
      ? picked
      : picked.copyWith(preferences: account.preferences);
  try {
    // The picker does not offer accounts owned by another non-favorite profile.
    final owner = profiles.owning(
      replacement.source,
      replacement.externalId ?? replacement.username,
    );
    if (owner != null && owner.id != profile.id) {
      await profiles.removeAccount(owner.id, replacement);
    }
    if (profiles.byId(profile.id)?.accounts.any((a) => a.key == account.key) !=
        true) {
      return;
    }
    // Attach first so a failed validation cannot discard the current account.
    profiles.attach(profile.id, [replacement]);
    await profiles.removeAccount(profile.id, account);
    unawaited(
      ref.read(prepSyncProvider.notifier).syncAccount(profile.id, replacement),
    );
  } catch (error) {
    if (context.mounted) {
      showAppSnack(
        context,
        error is PrepException
            ? error.message
            : 'Could not change this account. Try again.',
        tone: AppSnackTone.danger,
      );
    }
    return;
  }
}

Future<void> prepReinstallSource(
  BuildContext context,
  WidgetRef ref,
  PrepProfile profile,
  PrepAccount account,
) async {
  if (!await ensurePrepAccess(context) || !context.mounted) return;
  final messenger = ScaffoldMessenger.maybeOf(context);
  final error = await ref
      .read(prepSyncProvider.notifier)
      .syncAccount(profile.id, account, force: true, reinstall: true);
  if (messenger != null) {
    showAppSnackOn(
      messenger,
      error ?? 'Games downloaded again',
      tone: error == null ? AppSnackTone.success : AppSnackTone.danger,
    );
  }
}

Future<void> prepExportSource(
  BuildContext context,
  WidgetRef ref,
  PrepProfile profile,
  PrepAccount account,
) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final box = context.findRenderObject() as RenderBox?;
  final origin = box == null ? null : box.localToGlobal(Offset.zero) & box.size;
  try {
    final file = await ref.read(prepRepositoryProvider).gamesFile(account);
    if (!await file.exists() || await file.length() == 0) {
      if (messenger != null) {
        showAppSnackOn(messenger, 'Download games before exporting.');
      }
      return;
    }
    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'application/x-chess-pgn')],
      subject: '${profile.name} · ${account.source.label}',
      sharePositionOrigin: origin,
    );
  } catch (_) {
    if (messenger != null) {
      showAppSnackOn(
        messenger,
        'Could not export games.',
        tone: AppSnackTone.danger,
      );
    }
  }
}

Future<void> prepExportProfile(
  BuildContext context,
  WidgetRef ref,
  PrepProfile profile,
) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final box = context.findRenderObject() as RenderBox?;
  final origin = box == null ? null : box.localToGlobal(Offset.zero) & box.size;
  Directory? temporary;
  try {
    final repo = ref.read(prepRepositoryProvider);
    final files = [
      for (final account in profile.accounts)
        (await repo.gamesFile(account)).path,
    ];
    temporary = await Directory.systemTemp.createTemp('chessever-prep-export-');
    final path = '${temporary.path}/combined.pgn';
    final count = await compute(_exportCombined, (path, files));
    if (count == 0) {
      if (messenger != null) {
        showAppSnackOn(messenger, 'Download games before exporting.');
      }
      return;
    }
    await Share.shareXFiles(
      [XFile(path, mimeType: 'application/x-chess-pgn')],
      subject: '${profile.name} · Combined',
      sharePositionOrigin: origin,
    );
  } catch (_) {
    if (messenger != null) {
      showAppSnackOn(
        messenger,
        'Could not export games.',
        tone: AppSnackTone.danger,
      );
    }
  } finally {
    if (temporary != null && await temporary.exists()) {
      await temporary.delete(recursive: true);
    }
  }
}

int _exportCombined((String, List<String>) input) =>
    writeCombinedPrepGames(path: input.$1, sources: input.$2);

/// Manual sources use an explicit PGN player name, so their side is never guessed.
Future<void> prepImportSource(
  BuildContext context,
  WidgetRef ref,
  PrepProfile profile,
) async {
  if (!await ensurePrepAccess(context) || !context.mounted) return;
  final repo = ref.read(prepRepositoryProvider);
  final profiles = ref.read(prepProfilesProvider.notifier);
  final cloud = ref.read(prepCloudSyncProvider.notifier);
  await showPrepImportDialog(
    context,
    playerName: profile.databaseAccount?.username ?? profile.name,
    onImport: ({required alias, required label, pgn}) async {
      final inputs = <(String, String)>[];
      if (pgn != null) {
        if (pgn.length > kPrepImportMaxBytes) {
          throw const PrepException('Paste a PGN smaller than 64 MB.');
        }
        inputs.add((label, pgn));
      } else {
        final files = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['pgn', 'bz2', 'zst'],
          allowMultiple: true,
          withData: false,
        );
        if (files == null || files.files.isEmpty) return false;
        for (final file in files.files) {
          if (file.size > kPrepImportMaxBytes) {
            throw PrepException('${file.name} is larger than 64 MB.');
          }
          final bytes =
              file.bytes ??
              (file.path == null ? null : await File(file.path!).readAsBytes());
          if (bytes == null) {
            throw PrepException('Could not read ${file.name}.');
          }
          inputs.add((
            file.name,
            await compute(decodePrepPgn, (file.name, bytes)),
          ));
        }
      }
      final accounts = <PrepAccount>[];
      final prepared = <PrepAccount>[];
      try {
        for (final (i, input) in inputs.indexed) {
          var account = PrepAccount(
            source: PrepSource.manual,
            username: input.$1,
            externalId: '${DateTime.now().microsecondsSinceEpoch}-$i',
            playerAliases: [alias],
            preferences: const PrepDownloadPreferences(
              range: PrepDateRange.all,
            ),
          );
          prepared.add(account);
          final target = await repo.gamesFile(account);
          final count = await compute(_saveManual, (
            target.path,
            input.$2,
            alias,
          ));
          account = account.copyWith(
            gameCount: count,
            lastSyncAtMs: DateTime.now().millisecondsSinceEpoch,
          );
          accounts.add(account);
        }
        if (profiles.byId(profile.id) == null) {
          throw const PrepException('This profile was removed.');
        }
        // Validate every selected database before attaching any of them.
        profiles.attach(profile.id, accounts);
      } catch (_) {
        for (final account in prepared) {
          await repo.deleteGames(account);
        }
        rethrow;
      }
      cloud.syncAfterDownload(profile.id);
      return true;
    },
  );
}

int _saveManual((String, String, String) input) =>
    writeImportedPrepGames(path: input.$1, pgn: input.$2, playerName: input.$3);
