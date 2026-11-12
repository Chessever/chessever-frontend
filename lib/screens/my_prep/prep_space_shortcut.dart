import 'dart:async';

import 'package:chessever2/screens/my_prep/models/prep_models.dart';
import 'package:chessever2/screens/my_prep/providers/prep_providers.dart';
import 'package:chessever2/screens/my_prep/services/prep_watch.dart';
import 'package:chessever2/screens/my_space/models/space_shortcut.dart';
import 'package:chessever2/screens/my_space/providers/space_auto_provider.dart';
import 'package:chessever2/screens/my_space/providers/space_shortcuts_provider.dart';
import 'package:chessever2/widgets/app_snack.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// The pin param holding [prepPinRecipe].
const kPrepPinRecipe = 'profile';

/// Pins the saved profile itself, so online-only and imported profiles open
/// with the same combined sources as they do in My Prep. The pin carries
/// the profile's sources ([prepPinRecipe]): profiles are kept on the device
/// and pins on the account, so this is what lets the card open on the
/// reader's other devices.
SpaceShortcut prepProfileSpaceDraft(PrepProfile profile) => SpaceShortcut.draft(
  kind: SpaceShortcutKind.prepProfile,
  targetId: profile.id,
  title: profile.name,
  subtitle: 'Prep',
  params: {kPrepPinRecipe: ?prepPinRecipe(profile)},
);

/// What another device needs to rebuild [profile]: who it is and where its
/// games come from, never the games or how far they are downloaded. Null
/// when it has nothing to download again (imported PGN files stay on the
/// device that read them).
Map<String, dynamic>? prepPinRecipe(PrepProfile profile) {
  final accounts = [
    for (final a in profile.accounts)
      if (a.source != PrepSource.manual)
        <String, dynamic>{
          'source': a.source.name,
          'username': a.username,
          'displayName': ?a.displayName,
          'avatarUrl': ?a.avatarUrl,
          'title': ?a.title,
          'country': ?a.country,
          'externalId': ?a.externalId,
          'fideId': ?a.fideId,
          if (a.playerAliases.isNotEmpty) 'playerAliases': a.playerAliases,
          'preferences': a.preferences.toJson(),
        },
  ];
  if (accounts.isEmpty) return null;
  return {
    'kind': profile.kind.name,
    'name': profile.name,
    'createdAtMs': profile.createdAtMs,
    'fideIdentity': ?profile.fideId,
    'favoriteId': ?profile.favoriteId,
    if (profile.watching) 'watching': true,
    'accounts': accounts,
  };
}

/// The profile [pin] carries, under the pin's id, without games. Null for a
/// pin saved before pins carried one, or one with nothing to download.
PrepProfile? prepProfileFromPin(SpaceShortcut pin) {
  final recipe = pin.params[kPrepPinRecipe];
  if (pin.kind != SpaceShortcutKind.prepProfile || recipe is! Map) return null;
  final profile = PrepProfile.fromJson({
    ...recipe,
    'id': pin.targetId,
    'name': recipe['name'] ?? pin.title,
  });
  return profile == null || profile.accounts.isEmpty ? null : profile;
}

/// The profile on this device that [pin] stands for: its own, or, for a pin
/// made on another device, the profile here that already holds one of its
/// sources (the same player, added on both).
PrepProfile? prepProfileForPin(SpaceShortcut pin, List<PrepProfile> profiles) {
  if (pin.kind != SpaceShortcutKind.prepProfile) return null;
  for (final p in profiles) {
    if (p.id == pin.targetId) return p;
  }
  final keys = {
    for (final a in prepProfileFromPin(pin)?.accounts ?? const <PrepAccount>[])
      a.key,
  };
  if (keys.isEmpty) return null;
  for (final p in profiles) {
    if (p.accounts.any((a) => keys.contains(a.key))) return p;
  }
  return null;
}

/// Keeps Prep pins and the profiles on this device in step. Watch it from
/// the home shell.
///
/// * A pin whose profile is here gets the profile's sources written into it
///   once (pins saved before they carried any), and again whenever the
///   reader changes the profile here.
/// * A pin whose profile is not here (made on another of the reader's
///   devices) is rebuilt from the sources it carries, or, for a starred
///   profile, from the server's copy of the star, and its games download.
/// * A profile deleted here takes its pin with it, so the pin never puts
///   it back.
final prepSpaceSyncProvider = Provider<void>((ref) {
  const same = DeepCollectionEquality();
  // Pins already looked at this session and left alone.
  final settled = <String>{};
  var restoring = false;

  Future<void> restore(List<SpaceShortcut> pins) async {
    if (restoring) return;
    restoring = true;
    try {
      final watched = await ref.read(prepWatchRemoteProvider).watched();
      if (watched == null) {
        // Signed out or offline: the next change or launch tries again.
        settled.removeAll(pins.map((pin) => pin.key));
        return;
      }
      final profiles = ref.read(prepProfilesProvider.notifier);
      final restored = <String>{};
      for (final pin in pins) {
        final star = watched[pin.targetId];
        final carried =
            prepProfileFromPin(pin) ?? star?.asProfile(pin.targetId);
        if (carried == null) continue;
        // The server knows whether a profile it can watch is starred.
        final profile = carried.copyWith(
          watching: prepCanWatch(carried) ? star != null : carried.watching,
        );
        final holder = profiles.restore(profile);
        if (holder != null) restored.add(holder.id);
      }
      final sync = ref.read(prepSyncProvider.notifier);
      for (final id in restored) {
        await sync.syncProfile(id);
      }
    } finally {
      restoring = false;
    }
  }

  void settle() {
    final profiles = ref.read(prepProfilesProvider).valueOrNull;
    final pins = ref.read(spaceShortcutsProvider).valueOrNull;
    if (profiles == null || pins == null) return;
    final held = {for (final p in profiles) p.id: p};
    final missing = <SpaceShortcut>[];
    for (final pin in pins) {
      if (pin.kind != SpaceShortcutKind.prepProfile) continue;
      final profile = held[pin.targetId];
      if (profile == null) {
        // Also one that opens a profile here already: your own profile may
        // still lack the accounts the other device gave it.
        if (settled.add(pin.key)) missing.add(pin);
        continue;
      }
      if (pin.params[kPrepPinRecipe] != null) continue;
      final recipe = prepPinRecipe(profile);
      if (recipe == null) continue;
      unawaited(
        ref.read(spaceShortcutsProvider.notifier).mergeParams(pin.key, {
          kPrepPinRecipe: recipe,
        }),
      );
    }
    if (missing.isNotEmpty) unawaited(restore(missing));
  }

  ref.listen(spaceShortcutsProvider, (_, _) => settle());
  ref.listen(prepProfilesProvider, (before, after) {
    final was = before?.valueOrNull;
    final now = after.valueOrNull;
    if (was != null && now != null) {
      final store = ref.read(spaceShortcutsProvider.notifier);
      final held = {for (final p in now) p.id: p};
      for (final old in was) {
        final profile = held[old.id];
        if (profile == null) {
          unawaited(store.removeTarget(SpaceShortcutKind.prepProfile, old.id));
          continue;
        }
        final recipe = prepPinRecipe(profile);
        if (recipe == null || same.equals(recipe, prepPinRecipe(old))) {
          continue;
        }
        unawaited(
          store.mergeParams(
            SpaceShortcut.keyFor(SpaceShortcutKind.prepProfile, profile.id),
            {kPrepPinRecipe: recipe},
          ),
        );
      }
    }
    settle();
  });
  settle();
});

/// Captures the store and messenger before an import or menu action can outlive
/// its widget. Invoke only after an explicit account add/change or promotion
/// succeeds, never on load, refresh or automatic favorite hydration.
/// Uses the manual pin's identity and persistence; taking that pin out of
/// My Space remains an intentional choice.
Future<void> Function(String profileId) prepProfileAutoPinner(
  BuildContext context,
) {
  final container = ProviderScope.containerOf(context, listen: false);
  final messenger = ScaffoldMessenger.maybeOf(context);
  return (profileId) async {
    try {
      // Do not overwrite a cache still loading or miss a pin it already holds.
      await container.read(spaceShortcutsProvider.future);
      final profile = container.read(prepProfileProvider(profileId));
      if (profile == null || profile.accounts.isEmpty) return;
      final draft = prepProfileSpaceDraft(profile);
      // Read after the await: a removal while the store loads must also win.
      if (container.read(spaceHiddenAutoKeysProvider).contains(draft.key)) {
        return;
      }
      await container.read(spaceShortcutsProvider.notifier).add(draft);
    } catch (_) {
      // The profile/download is still valid. Remote write failures already keep
      // a local pin in the existing store; this covers failure to load/add it.
      if (messenger != null && messenger.mounted) {
        showAppSnackOn(
          messenger,
          'Profile saved. Could not add to My Space. Try its profile menu.',
          tone: AppSnackTone.danger,
        );
      }
    }
  };
}

/// Starts an automatic pin independently of downloads while the host is mounted.
Future<void> prepAutoPinProfile(BuildContext context, String profileId) =>
    prepProfileAutoPinner(context)(profileId);
