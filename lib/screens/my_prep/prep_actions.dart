import 'dart:async';

import 'package:chessever2/screens/library/widgets/library_context_menu.dart';
import 'package:chessever2/screens/my_prep/data/prep_favorites.dart';
import 'package:chessever2/screens/my_prep/library/prep_library.dart'
    show PrepLibraryFolderScreen, prepCloudMenuAction;
import 'package:chessever2/screens/my_prep/models/prep_models.dart';
import 'package:chessever2/screens/my_prep/prep_access.dart';
import 'package:chessever2/screens/my_prep/prep_profile_screen.dart';
import 'package:chessever2/screens/my_prep/providers/prep_providers.dart';
import 'package:chessever2/screens/my_prep/widgets/prep_dialogs.dart';
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
  final result = await showPrepAddAccountsDialog(
    context,
    kind: PrepKind.mine,
    existingKeys: {for (final a in existing?.accounts ?? const []) a.key},
  );
  if (result == null || !context.mounted) return;
  await _releaseFromFavorites(ref, result.accounts);
  if (!context.mounted) return;
  final PrepProfile profile;
  if (existing == null) {
    profile = profiles.create(
      kind: PrepKind.mine,
      name: 'My games',
      accounts: result.accounts,
    );
  } else {
    profiles.edit(
      existing.id,
      (p) => p.copyWith(accounts: [...p.accounts, ...result.accounts]),
    );
    profile = existing;
  }
  _syncNew(context, ref, profile.id, result.accounts);
}

/// Adds an opponent with the accounts the reader typed and opens them.
Future<void> prepAddOpponent(BuildContext context, WidgetRef ref) async {
  HapticFeedbackService.buttonPress();
  if (!await ensurePrepAccess(context) || !context.mounted) return;
  final result = await showPrepAddAccountsDialog(
    context,
    kind: PrepKind.opponent,
  );
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
  _syncNew(context, ref, profile.id, result.accounts);
  unawaited(PrepProfileScreen.open(context, profile.id));
}

/// Adds another Lichess or Chess.com account to an existing profile.
Future<void> prepAddAccountTo(
  BuildContext context,
  WidgetRef ref,
  PrepProfile profile,
) async {
  if (!await ensurePrepAccess(context) || !context.mounted) return;
  final have = {for (final a in profile.accounts) a.source};
  final missing = PrepSource.values.where((s) => !have.contains(s)).toList();
  final result = await showPrepAddAccountsDialog(
    context,
    kind: profile.kind,
    only: missing.length == 1 ? missing.first : null,
    existingKeys: {for (final a in profile.accounts) a.key},
  );
  if (result == null || !context.mounted) return;
  await _releaseFromFavorites(ref, result.accounts);
  if (!context.mounted) return;
  ref
      .read(prepProfilesProvider.notifier)
      .edit(
        profile.id,
        (p) => p.copyWith(accounts: [...p.accounts, ...result.accounts]),
      );
  _syncNew(context, ref, profile.id, result.accounts);
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
    final owner = profiles.owning(account.source, account.username);
    if (owner == null || owner.kind != PrepKind.favorite) continue;
    if (owner.accounts.length <= 1) {
      await profiles.delete(owner.id);
    } else {
      await profiles.removeAccount(owner.id, account);
    }
  }
}

void _syncNew(
  BuildContext context,
  WidgetRef ref,
  String profileId,
  List<PrepAccount> accounts,
) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final sync = ref.read(prepSyncProvider.notifier);
  unawaited(() async {
    for (final account in accounts) {
      final error = await sync.syncAccount(profileId, account);
      if (error != null && messenger != null) {
        showAppSnackOn(messenger, error, tone: AppSnackTone.danger);
      }
    }
  }());
}

Future<void> _refreshProfiles(WidgetRef ref, String profileId) async {
  final profiles = ref.read(prepProfilesProvider.notifier);
  final repo = ref.read(prepRepositoryProvider);
  final profile = profiles.byId(profileId);
  if (profile == null) return;
  for (final account in profile.accounts) {
    try {
      final fresh = await repo.lookup(account.source, account.username);
      profiles.edit(profileId, (p) {
        final live = p.accounts.where((a) => a.key == account.key).firstOrNull;
        if (live == null) return p;
        return p.replaceAccount(
          live.copyWith(
            avatarUrl: fresh.avatarUrl,
            title: fresh.title,
            country: fresh.country,
            ratings: fresh.ratings,
          ),
        );
      });
    } catch (_) {
      // Keep the curated details.
    }
  }
}

/// Re-reads every account's profile (ratings, title, avatar).
Future<void> prepRefreshProfileDetails(WidgetRef ref, String profileId) =>
    _refreshProfiles(ref, profileId);

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
    if (profile.kind != PrepKind.favorite)
      LibraryMenuAction(
        icon: Icons.add_link_rounded,
        label: 'Add account',
        visible: profile.accounts.length < PrepSource.values.length ||
            profile.kind == PrepKind.mine,
        onSelected: () => prepAddAccountTo(context, ref, profile),
      ),
    if (profile.kind == PrepKind.opponent)
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
