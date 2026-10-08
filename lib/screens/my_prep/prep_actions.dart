import 'dart:async';

import 'package:chessever2/screens/library/widgets/library_context_menu.dart';
import 'package:chessever2/screens/my_prep/data/prep_favorites.dart';
import 'package:chessever2/screens/my_prep/library/prep_library.dart'
    show PrepLibraryFolderScreen, prepCloudMenuAction;
import 'package:chessever2/screens/my_prep/models/prep_models.dart';
import 'package:chessever2/screens/my_prep/prep_access.dart';
import 'package:chessever2/screens/my_prep/prep_profile_screen.dart';
import 'package:chessever2/screens/my_prep/prep_source_actions.dart'
    show prepExportProfile;
import 'package:chessever2/screens/my_prep/providers/prep_providers.dart';
import 'package:chessever2/screens/my_prep/services/prep_repository.dart';
import 'package:chessever2/screens/my_prep/widgets/prep_dialogs.dart';
import 'package:chessever2/screens/my_prep/widgets/prep_source_picker.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/widgets/alert_dialog/alert_modal.dart';
import 'package:chessever2/widgets/app_snack.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Adds the reader's own accounts to My games. They all live on one
/// profile, so their games read together as "me".
Future<void> prepAddMine(BuildContext context, WidgetRef ref) async {
  HapticFeedbackService.buttonPress();
  if (!await ensurePrepAccess(context) || !context.mounted) return;
  final profiles = ref.read(prepProfilesProvider.notifier);
  final mine = ref.read(prepProfilesOfKindProvider(PrepKind.mine)) ?? const [];
  final existing = mine.isEmpty ? null : mine.first;
  final result = await showPrepSourcePicker(
    context,
    kind: PrepKind.mine,
    existingKeys: {for (final a in existing?.accounts ?? const []) a.key},
    attaching: existing != null,
    multiple: existing != null,
    lockedFideId: existing?.fideId,
  );
  if (result == null || !context.mounted) return;
  await _releaseFromFavorites(ref, result.accounts);
  if (!context.mounted) return;
  final PrepProfile profile;
  if (existing == null) {
    profile = profiles.create(
      kind: PrepKind.mine,
      name: result.name,
      accounts: result.accounts,
    );
  } else {
    profiles.attach(existing.id, result.accounts);
    profile = existing;
  }
  if (context.mounted) unawaited(PrepProfileScreen.open(context, profile.id));
}

/// Adds an opponent with the accounts the reader typed and opens them.
Future<void> prepAddOpponent(BuildContext context, WidgetRef ref) async {
  HapticFeedbackService.buttonPress();
  if (!await ensurePrepAccess(context) || !context.mounted) return;
  final result = await showPrepSourcePicker(context, kind: PrepKind.opponent);
  if (result == null || !context.mounted) return;
  await _releaseFromFavorites(ref, result.accounts);
  if (!context.mounted) return;
  final profile = ref
      .read(prepProfilesProvider.notifier)
      .create(
        kind: PrepKind.opponent,
        name: result.name,
        accounts: result.accounts,
      );
  unawaited(PrepProfileScreen.open(context, profile.id));
}

/// Attaches a database player or online account to an existing profile.
Future<void> prepAddAccountTo(
  BuildContext context,
  WidgetRef ref,
  PrepProfile profile, {
  PrepSource? source,
}) async {
  if (!await ensurePrepAccess(context) || !context.mounted) return;
  final result = await showPrepSourcePicker(
    context,
    kind: profile.kind,
    only: source,
    attaching: true,
    multiple: true,
    lockedFideId: profile.fideId,
    existingKeys: {for (final a in profile.accounts) a.key},
  );
  if (result == null || !context.mounted) return;
  await _releaseFromFavorites(ref, result.accounts);
  if (!context.mounted) return;
  try {
    ref.read(prepProfilesProvider.notifier).attach(profile.id, result.accounts);
  } catch (error) {
    showAppSnack(context, '$error', tone: AppSnackTone.danger);
    return;
  }
}

/// A favorite opened before keeps its downloaded games; the first open
/// creates its profile from the curated accounts.
Future<void> prepOpenFavorite(
  BuildContext context,
  WidgetRef ref,
  PrepFavorite favorite,
) async {
  HapticFeedbackService.cardTap();
  final profiles = ref.read(prepProfilesProvider.notifier);
  final all = ref.read(prepProfilesProvider).valueOrNull ?? const [];
  final existing = all.where((p) => p.favoriteId == favorite.id).firstOrNull;
  if (existing != null) {
    unawaited(PrepProfileScreen.open(context, existing.id));
    return;
  }
  if (!await ensurePrepAccess(context) || !context.mounted) return;
  final accounts = [
    for (final (source, username) in favorite.accounts)
      if (profiles.owning(source, username) == null)
        PrepAccount(
          source: source,
          username: username,
          displayName: favorite.name,
          title: favorite.title,
          country: favorite.country,
        ),
  ];
  if (accounts.isEmpty) {
    // Every account is already followed elsewhere; open that instead.
    final (source, username) = favorite.accounts.first;
    final owner = profiles.owning(source, username);
    if (owner != null) unawaited(PrepProfileScreen.open(context, owner.id));
    return;
  }
  final profile = profiles.create(
    kind: PrepKind.favorite,
    name: favorite.name,
    accounts: accounts,
    favoriteId: favorite.id,
  );
  // Refresh ratings and avatars quietly; the curated values stand in.
  unawaited(_refreshProfiles(ref, profile.id));
  unawaited(PrepProfileScreen.open(context, profile.id));
}

/// Accounts typed into My games or Opponents move out of a favorite that
/// held them, so one account's games are never stored twice.
Future<void> _releaseFromFavorites(
  WidgetRef ref,
  List<PrepAccount> accounts,
) async {
  final profiles = ref.read(prepProfilesProvider.notifier);
  for (final account in accounts) {
    final owner = profiles.owning(
      account.source,
      account.externalId ?? account.username,
    );
    if (owner == null || owner.kind != PrepKind.favorite) continue;
    if (owner.accounts.length <= 1) {
      await profiles.delete(owner.id);
    } else {
      await profiles.removeAccount(owner.id, account);
    }
  }
}

Future<String?> _refreshProfiles(
  WidgetRef ref,
  String profileId, {
  PrepAccount? only,
}) async {
  final profiles = ref.read(prepProfilesProvider.notifier);
  final repo = ref.read(prepRepositoryProvider);
  final profile = profiles.byId(profileId);
  if (profile == null) return 'This profile was removed.';
  String? firstError;
  for (final account in profile.accounts.where(
    (a) => only == null || a.key == only.key,
  )) {
    try {
      final fresh = await repo.refreshDetails(account);
      profiles.edit(profileId, (p) {
        final live = p.accounts.where((a) => a.key == account.key).firstOrNull;
        if (live == null) return p;
        return p.replaceAccount(
          live.copyWith(
            displayName: fresh.displayName,
            avatarUrl: fresh.avatarUrl,
            title: fresh.title,
            country: fresh.country,
            ratings: fresh.ratings,
            playerAliases: {
              ...live.playerAliases,
              ...fresh.playerAliases,
            }.toList(),
          ),
        );
      });
    } catch (error) {
      // Keep the last known details, and report explicit refresh failures.
      firstError ??= error is PrepException
          ? error.message
          : 'Could not refresh profile details. Try again.';
    }
  }
  return firstError;
}

/// Re-reads every account's profile (ratings, title, avatar).
Future<String?> prepRefreshProfileDetails(
  WidgetRef ref,
  String profileId, {
  PrepAccount? account,
}) => _refreshProfiles(ref, profileId, only: account);

/// The long-press and ••• menu for a profile card. [fromLibrary] leaves out
/// "Show in Library" where the reader already is there.
List<LibraryMenuAction> prepProfileMenu(
  BuildContext context,
  WidgetRef ref,
  PrepProfile profile, {
  bool fromLibrary = false,
}) {
  final sync = ref.read(prepSyncProvider.notifier);
  final messenger = ScaffoldMessenger.maybeOf(context);
  return [
    LibraryMenuAction(
      icon: Icons.refresh_rounded,
      label: 'Refresh games',
      prominent: true,
      onSelected: () async {
        if (!await ensurePrepAccess(context)) return;
        final error = await sync.syncProfile(profile.id, force: true);
        if (messenger == null) return;
        showAppSnackOn(
          messenger,
          error ?? '${profile.name} is up to date',
          tone: error == null ? AppSnackTone.neutral : AppSnackTone.danger,
        );
      },
    ),
    if (!fromLibrary)
      LibraryMenuAction(
        icon: Icons.folder_open_rounded,
        label: 'Show in Library',
        onSelected: () => PrepLibraryFolderScreen.open(context, profile.id),
      ),
    prepCloudMenuAction(context, ref, profile),
    LibraryMenuAction(
      icon: Icons.ios_share_rounded,
      label: 'Export combined PGN',
      enabled: profile.gameCount > 0 && !profile.accounts.any(sync.isSyncing),
      onSelected: () => prepExportProfile(context, ref, profile),
    ),
    if (profile.kind == PrepKind.favorite)
      LibraryMenuAction(
        icon: Icons.person_add_alt_1_rounded,
        label: 'Add to Opponents',
        prominent: true,
        onSelected: () {
          ref
              .read(prepProfilesProvider.notifier)
              .edit(profile.id, (p) => p.copyWith(kind: PrepKind.opponent));
          if (messenger != null) {
            showAppSnackOn(messenger, '${profile.name} added to Opponents');
          }
        },
      ),
    LibraryMenuAction(
      icon: Icons.add_link_rounded,
      label: 'Attach source',
      onSelected: () => prepAddAccountTo(context, ref, profile),
    ),
    if (profile.kind != PrepKind.favorite)
      LibraryMenuAction(
        icon: Icons.edit_rounded,
        label: 'Rename',
        onSelected: () async {
          final name = await showPrepRenameDialog(context, profile.name);
          if (name == null) return;
          ref
              .read(prepProfilesProvider.notifier)
              .edit(profile.id, (p) => p.copyWith(name: name));
        },
      ),
    LibraryMenuAction(
      icon: Icons.delete_outline_rounded,
      label: profile.kind == PrepKind.favorite
          ? 'Clear downloaded games'
          : 'Remove',
      destructive: true,
      onSelected: () => prepConfirmRemove(context, ref, profile),
    ),
  ];
}

/// Removes a profile and its downloaded games after asking.
Future<bool> prepConfirmRemove(
  BuildContext context,
  WidgetRef ref,
  PrepProfile profile,
) async {
  final favorite = profile.kind == PrepKind.favorite;
  final ok = await showSmoothConfirmDialog(
    context: context,
    title: favorite
        ? 'Clear ${profile.name}’s games?'
        : profile.kind == PrepKind.mine
        ? 'Remove your accounts?'
        : 'Remove ${profile.name}?',
    message: favorite
        ? 'The downloaded games are deleted from this device. They stay in '
              'Favorites and download again when opened.'
        : 'Their downloaded games are deleted from this device. You can add '
              'them again any time.',
    confirmText: favorite ? 'Clear' : 'Remove',
    isDangerous: true,
  );
  if (ok != true) return false;
  for (final account in profile.accounts) {
    ref.read(prepSyncProvider.notifier).cancel(account);
  }
  await ref.read(prepProfilesProvider.notifier).delete(profile.id);
  return true;
}

/// A reader-requested refresh of one account, behind the Premium gate.
Future<void> prepRefreshAccount(
  BuildContext context,
  WidgetRef ref,
  String profileId,
  PrepAccount account,
) async {
  HapticFeedbackService.buttonPress();
  if (!await ensurePrepAccess(context) || !context.mounted) return;
  final messenger = ScaffoldMessenger.maybeOf(context);
  final error = await ref
      .read(prepSyncProvider.notifier)
      .syncAccount(profileId, account, force: true);
  if (error != null && messenger != null) {
    showAppSnackOn(messenger, error, tone: AppSnackTone.danger);
  }
}

/// A reader-requested refresh of a whole profile (pull to refresh).
Future<void> prepRefreshProfile(
  BuildContext context,
  WidgetRef ref,
  String profileId,
) async {
  if (!await ensurePrepAccess(context) || !context.mounted) return;
  final messenger = ScaffoldMessenger.maybeOf(context);
  final error = await ref
      .read(prepSyncProvider.notifier)
      .syncProfile(profileId, force: true);
  if (error != null && messenger != null) {
    showAppSnackOn(messenger, error, tone: AppSnackTone.danger);
  }
}
