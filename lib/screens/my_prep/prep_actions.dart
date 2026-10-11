import 'dart:async';

import 'package:chessever2/repository/supabase/chess_player/chess_player_repository.dart'
    show ChessPlayer;
import 'package:chessever2/screens/library/widgets/library_context_menu.dart';
import 'package:chessever2/screens/my_prep/data/prep_favorites.dart';
import 'package:chessever2/screens/my_prep/library/prep_library.dart'
    show PrepLibraryFolderScreen, prepCloudMenuAction;
import 'package:chessever2/screens/my_prep/models/prep_models.dart';
import 'package:chessever2/screens/my_prep/prep_access.dart';
import 'package:chessever2/screens/my_prep/prep_profile_screen.dart';
import 'package:chessever2/screens/my_prep/prep_source_actions.dart'
    show prepExportProfile, prepStartDownloads;
import 'package:chessever2/screens/my_prep/providers/prep_known_accounts_provider.dart';
import 'package:chessever2/screens/my_prep/providers/prep_providers.dart';
import 'package:chessever2/screens/my_prep/services/prep_repository.dart';
import 'package:chessever2/screens/my_prep/widgets/prep_dialogs.dart';
import 'package:chessever2/screens/my_prep/widgets/prep_source_picker.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/widgets/alert_dialog/alert_modal.dart';
import 'package:chessever2/widgets/app_snack.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Adds the reader's own accounts to My Games. They all live on one
/// profile, so their games read together as "me".
Future<void> prepAddMine(
  BuildContext context,
  WidgetRef ref, {
  PrepSource? source,
}) async {
  HapticFeedbackService.buttonPress();
  if (!await ensurePrepAccess(context) || !context.mounted) return;
  final profiles = ref.read(prepProfilesProvider.notifier);
  final mine = ref.read(prepProfilesOfKindProvider(PrepKind.mine)) ?? const [];
  final existing = mine.isEmpty ? null : mine.first;
  final result = await showPrepSourcePicker(
    context,
    kind: PrepKind.mine,
    only: source,
    existingKeys: {for (final a in existing?.accounts ?? const []) a.key},
    attaching: existing != null,
    multiple: true,
    lockedFideId: existing?.fideId,
  );
  if (result == null || !context.mounted) return;
  await _releaseFromFavorites(ref, result.accounts);
  if (!context.mounted) return;
  final String profileId;
  if (existing == null) {
    profileId = profiles
        .create(
          kind: PrepKind.mine,
          name: result.name,
          accounts: result.accounts,
        )
        .id;
  } else {
    profiles.attach(existing.id, result.accounts);
    profileId = existing.id;
  }
  // The card itself reports the download; no snack is needed.
  await prepStartDownloads(
    context,
    ref,
    profileId,
    result.accounts,
    scoped: true,
  );
}

/// Adds an opponent with every account the reader typed. They stay on the
/// list, where the new card reports its download.
Future<void> prepAddOpponent(
  BuildContext context,
  WidgetRef ref, {
  PrepSource? source,
}) => _prepAddPlayer(context, ref, PrepKind.opponent, source);

Future<void> _prepAddPlayer(
  BuildContext context,
  WidgetRef ref,
  PrepKind kind,
  PrepSource? source,
) async {
  HapticFeedbackService.buttonPress();
  if (!await ensurePrepAccess(context) || !context.mounted) return;
  await _prepPickPlayer(context, ref, kind, only: source);
}

/// The add sheet, and the profile made from what it hands back. [initial]
/// accounts are chosen when it opens; a profile keeping any of them
/// remembers the ranked player ([favoriteId]) they belong to.
Future<PrepProfile?> _prepPickPlayer(
  BuildContext context,
  WidgetRef ref,
  PrepKind kind, {
  PrepSource? only,
  List<PrepAccount> initial = const [],
  String? favoriteId,
}) async {
  final result = await showPrepSourcePicker(
    context,
    kind: kind,
    only: only,
    multiple: true,
    initial: initial,
  );
  if (result == null || !context.mounted) return null;
  await _releaseFromFavorites(ref, result.accounts);
  if (!context.mounted) return null;
  final known = {for (final account in initial) account.key};
  final profile = ref
      .read(prepProfilesProvider.notifier)
      .create(
        kind: kind,
        name: result.name,
        accounts: result.accounts,
        favoriteId: result.accounts.any((a) => known.contains(a.key))
            ? favoriteId
            : null,
      );
  await prepStartDownloads(
    context,
    ref,
    profile.id,
    result.accounts,
    scoped: true,
  );
  return profile;
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
  await prepStartDownloads(
    context,
    ref,
    profile.id,
    result.accounts,
    scoped: true,
  );
}

/// A ranked player already added opens their profile. Anyone else opens the
/// add sheet. [onResolved] runs as the sheet is about to open.
Future<void> prepOpenFavorite(
  BuildContext context,
  WidgetRef ref,
  ChessPlayer player, {
  VoidCallback? onResolved,
}) async {
  HapticFeedbackService.cardTap();
  final existing = _favoriteProfile(ref, '${player.fideid}');
  if (existing != null) {
    unawaited(prepAttachFavoriteDatabase(ref, existing));
    unawaited(PrepProfileScreen.open(context, existing.id));
    return;
  }
  await _addRanked(context, ref, player, add: false, onResolved: onResolved);
}

/// The + on a Players row. It adds nothing by itself: the reader goes
/// through the add sheet first, as for any other profile. A player kept
/// from an earlier version moves to Profiles instead, asked the same
/// question about what to download.
Future<void> prepAddFavorite(
  BuildContext context,
  WidgetRef ref,
  ChessPlayer player, {
  VoidCallback? onResolved,
}) async {
  HapticFeedbackService.buttonPress();
  final existing = _favoriteProfile(ref, '${player.fideid}');
  if (existing != null) {
    if (!await ensurePrepAccess(context) || !context.mounted) return;
    await _moveToOpponents(
      context,
      ref,
      existing,
      ScaffoldMessenger.maybeOf(context),
    );
    return;
  }
  await _addRanked(context, ref, player, add: true, onResolved: onResolved);
}

/// The add sheet Profiles uses, opened on a ranked [player] with ChessEver
/// and the handles the server knows for them already chosen. The reader
/// drops what they do not want and picks what to download; nothing is
/// created or downloaded before that. Where another profile already holds
/// every one of the player's sources, a tap opens it and [add] only says
/// where the player is.
Future<void> _addRanked(
  BuildContext context,
  WidgetRef ref,
  ChessPlayer player, {
  required bool add,
  VoidCallback? onResolved,
}) async {
  final fide = '${player.fideid}';
  if (!await ensurePrepAccess(context) || !context.mounted) return;
  final sources = await _favoriteSources(ref, player);
  if (!context.mounted) return;
  if (sources.known.isEmpty) {
    showAppSnack(context, _favoriteUnavailable, tone: AppSnackTone.danger);
    return;
  }
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (sources.free.isEmpty) {
    if (add) {
      await _moveToOpponents(context, ref, sources.owner!, messenger);
    } else {
      unawaited(PrepProfileScreen.open(context, sources.owner!.id));
    }
    return;
  }
  onResolved?.call();
  final profile = await _prepPickPlayer(
    context,
    ref,
    PrepKind.opponent,
    initial: sources.free,
    favoriteId: kPrepFavoritesByFide[fide]?.id ?? fide,
  );
  if (profile == null) return;
  // Refresh ratings and avatars quietly; the curated values stand in.
  unawaited(_refreshProfiles(ref, profile.id));
  if (messenger != null) {
    showAppSnackOn(messenger, '${profile.name} added to Profiles');
  }
}

/// The + on a player already kept in Players: they move to Profiles with
/// their games.
Future<void> prepMoveFavoriteToOpponents(
  BuildContext context,
  WidgetRef ref,
  PrepProfile profile,
) async {
  HapticFeedbackService.buttonPress();
  if (!await ensurePrepAccess(context) || !context.mounted) return;
  await _moveToOpponents(
    context,
    ref,
    profile,
    ScaffoldMessenger.maybeOf(context),
  );
}

/// A favorite joins Profiles as it stands. What it never downloaded is
/// offered with its clocks and period first, as when a source is attached.
/// A profile that was never in Players only says where it already is.
Future<void> _moveToOpponents(
  BuildContext context,
  WidgetRef ref,
  PrepProfile profile,
  ScaffoldMessengerState? messenger,
) async {
  if (profile.kind != PrepKind.favorite) {
    if (messenger != null) {
      showAppSnackOn(
        messenger,
        '${profile.name} is already in '
        '${profile.kind == PrepKind.mine ? 'My Games' : 'Profiles'}',
      );
    }
    return;
  }
  ref
      .read(prepProfilesProvider.notifier)
      .edit(profile.id, (p) => p.copyWith(kind: PrepKind.opponent));
  unawaited(prepAttachFavoriteDatabase(ref, profile));
  if (messenger != null) {
    showAppSnackOn(messenger, '${profile.name} added to Profiles');
  }
  await prepStartDownloads(context, ref, profile.id, profile.accounts);
}

const _favoriteUnavailable =
    'Could not load this player from ChessEver. Check your connection and retry.';

/// The profile standing for the ranked player [fide], whichever tab it is in.
PrepProfile? _favoriteProfile(WidgetRef ref, String fide) =>
    (ref.read(prepProfilesProvider).valueOrNull ?? const <PrepProfile>[])
        .where((p) => prepFavoriteFide(p) == fide)
        .firstOrNull;

/// What Players knows of a ranked [player]: their ChessEver source and the
/// Lichess and Chess.com handles the server lists for them. `free` are the
/// ones no profile holds yet, and `owner` the profile holding the first of
/// the rest.
Future<({List<PrepAccount> known, List<PrepAccount> free, PrepProfile? owner})>
_favoriteSources(WidgetRef ref, ChessPlayer player) async {
  final fide = '${player.fideid}';
  final profiles = ref.read(prepProfilesProvider.notifier);
  // Both are asked at once: neither waits on the other.
  final (database, handles) = await (
    _databaseAccount(ref, fide),
    prepKnownAccounts(ref),
  ).wait;
  final known = [
    ?database,
    for (final (source, username)
        in handles[fide] ?? const <(PrepSource, String)>[])
      PrepAccount(
        source: source,
        username: username,
        displayName: kPrepFavoritesByFide[fide]?.name ?? player.name,
        title: player.title,
        country: player.country,
      ),
  ];
  PrepProfile? owner(PrepAccount a) =>
      profiles.owning(a.source, a.externalId ?? a.username);
  return (
    known: known,
    free: [
      for (final account in known)
        if (owner(account) == null) account,
    ],
    owner: known.map(owner).whereType<PrepProfile>().firstOrNull,
  );
}

/// Whether [profile] is a favorite saved before ChessEver was one of its
/// sources. A reader who detached the database keeps its FIDE identity, so
/// that choice is never undone.
bool prepFavoriteLacksDatabase(PrepProfile profile) =>
    profile.kind == PrepKind.favorite &&
    profile.fideId == null &&
    prepFavoriteFide(profile) != null;

/// Gives such a favorite its ChessEver source.
Future<void> prepAttachFavoriteDatabase(
  WidgetRef ref,
  PrepProfile profile,
) async {
  if (!prepFavoriteLacksDatabase(profile)) return;
  final profiles = ref.read(prepProfilesProvider.notifier);
  final account = await _databaseAccount(ref, prepFavoriteFide(profile)!);
  if (account == null) return;
  try {
    profiles.attach(profile.id, [account]);
    unawaited(
      ref.read(prepSyncProvider.notifier).syncAccount(profile.id, account),
    );
  } on PrepException {
    // Another profile holds this player; leave both as they are.
  }
}

Future<PrepAccount?> _databaseAccount(WidgetRef ref, String fideId) async {
  try {
    final players = await ref
        .read(prepRepositoryProvider)
        .searchPlayers(fideId);
    final player = players.where((p) => p.fideId == fideId).firstOrNull;
    return player == null ? null : PrepAccount.fromPlayer(player);
  } catch (_) {
    return null;
  }
}

/// Accounts typed into My Games or Profiles move out of a favorite that
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
        label: 'Add to Profiles',
        prominent: true,
        onSelected: () {
          ref
              .read(prepProfilesProvider.notifier)
              .edit(profile.id, (p) => p.copyWith(kind: PrepKind.opponent));
          if (messenger != null) {
            showAppSnackOn(messenger, '${profile.name} added to Profiles');
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
      label: profile.kind == PrepKind.favorite && profile.favoriteId != null
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
  final favorite =
      profile.kind == PrepKind.favorite && profile.favoriteId != null;
  final ok = await showSmoothConfirmDialog(
    context: context,
    title: favorite
        ? 'Clear ${profile.name}’s games?'
        : profile.kind == PrepKind.mine
        ? 'Remove your accounts?'
        : 'Remove ${profile.name}?',
    message: favorite
        ? 'The downloaded games are deleted from this device. They stay in '
              'Players and download again when opened.'
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
