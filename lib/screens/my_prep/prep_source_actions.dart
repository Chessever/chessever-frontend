import 'dart:convert';
import 'dart:io';

import 'package:chessever2/screens/my_prep/models/prep_models.dart';
import 'package:chessever2/screens/my_prep/prep_access.dart';
import 'package:chessever2/screens/my_prep/prep_actions.dart';
import 'package:chessever2/screens/my_prep/library/prep_cloud_sync.dart';
import 'package:chessever2/screens/my_prep/providers/prep_providers.dart';
import 'package:chessever2/screens/my_prep/services/prep_repository.dart';
import 'package:chessever2/screens/my_prep/widgets/prep_dialogs.dart';
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
        '${account.displayName ?? account.username} and its downloaded games '
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
      showAppSnackOn(messenger, '${account.source.label} detached');
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
  PrepAccount account,
) async {
  if (!await ensurePrepAccess(context) || !context.mounted) return;
  final options = await showPrepDownloadOptionsDialog(
    context,
    account: account,
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
  if (live != null) await prepRefreshAccount(context, ref, profile.id, live);
}

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
    existingKeys: {for (final a in profile.accounts) a.key},
  );
  if (result == null || !context.mounted) return;
  final profiles = ref.read(prepProfilesProvider.notifier);
  final replacement = result.accounts.single.copyWith(
    preferences: account.preferences,
  );
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
  if (context.mounted) {
    await prepRefreshAccount(context, ref, profile.id, replacement);
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
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    final files = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pgn'],
      allowMultiple: true,
    );
    if (files == null || files.files.isEmpty || !context.mounted) return;
    final alias = await showPrepRenameDialog(
      context,
      profile.databaseAccount?.username ?? profile.name,
      title: 'Player name in the PGN',
    );
    if (alias == null || !context.mounted) return;
    final repo = ref.read(prepRepositoryProvider);
    final profiles = ref.read(prepProfilesProvider.notifier);
    final cloud = ref.read(prepCloudSyncProvider.notifier);
    var attached = 0;
    for (final (i, file) in files.files.indexed) {
      final bytes =
          file.bytes ??
          (file.path == null ? null : await File(file.path!).readAsBytes());
      if (bytes == null) continue;
      final pgn = utf8.decode(bytes, allowMalformed: true);
      var account = PrepAccount(
        source: PrepSource.manual,
        username: file.name,
        externalId: '${DateTime.now().microsecondsSinceEpoch}-$i',
        playerAliases: [alias],
        preferences: const PrepDownloadPreferences(range: PrepDateRange.all),
      );
      final target = await repo.gamesFile(account);
      final count = await compute(_saveManual, (target.path, pgn, alias));
      account = account.copyWith(
        gameCount: count,
        lastSyncAtMs: DateTime.now().millisecondsSinceEpoch,
      );
      if (profiles.byId(profile.id) == null) {
        await repo.deleteGames(account);
        return;
      }
      try {
        profiles.attach(profile.id, [account]);
        attached++;
      } catch (_) {
        await repo.deleteGames(account);
        rethrow;
      }
    }
    if (attached == 0) {
      throw const PrepException('Could not read the selected PGN files.');
    }
    cloud.syncAfterDownload(profile.id);
    if (messenger != null) {
      showAppSnackOn(
        messenger,
        'PGN source attached',
        tone: AppSnackTone.success,
      );
    }
  } catch (error) {
    if (messenger != null) {
      showAppSnackOn(
        messenger,
        error is PrepException
            ? error.message
            : 'Could not import the PGN file.',
        tone: AppSnackTone.danger,
      );
    }
  }
}

int _saveManual((String, String, String) input) =>
    writeImportedPrepGames(path: input.$1, pgn: input.$2, playerName: input.$3);
