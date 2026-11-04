import 'package:chessever2/screens/my_prep/models/prep_models.dart';
import 'package:chessever2/screens/my_prep/providers/prep_providers.dart';
import 'package:chessever2/screens/my_space/models/space_shortcut.dart';
import 'package:chessever2/screens/my_space/providers/space_auto_provider.dart';
import 'package:chessever2/screens/my_space/providers/space_shortcuts_provider.dart';
import 'package:chessever2/widgets/app_snack.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Pins the saved profile itself, so online-only and imported profiles open
/// with the same combined sources as they do in My Prep.
SpaceShortcut prepProfileSpaceDraft(PrepProfile profile) => SpaceShortcut.draft(
  kind: SpaceShortcutKind.prepProfile,
  targetId: profile.id,
  title: profile.name,
  subtitle: 'Prep',
);

/// Called only after an explicit account add/change succeeds, never on load,
/// refresh or automatic favorite hydration. Uses the manual pin's identity and
/// persistence; taking that pin out of My Space remains an intentional choice.
/// This runs independently of downloads and can outlive the initiating widget.
Future<void> prepAutoPinProfile(BuildContext context, String profileId) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    // Do not overwrite a cache still loading or miss a pin it already holds.
    await container.read(spaceShortcutsProvider.future);
    final profile = container.read(prepProfileProvider(profileId));
    if (profile == null || profile.accounts.isEmpty) return;
    final draft = prepProfileSpaceDraft(profile);
    // Read after the await: a removal while the store loads must also win.
    if (container.read(spaceHiddenAutoKeysProvider).contains(draft.key)) return;
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
}
