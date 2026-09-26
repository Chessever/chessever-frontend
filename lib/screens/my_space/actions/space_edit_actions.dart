import 'dart:async';

import 'package:chessever2/screens/my_space/actions/space_player_actions.dart'
    show spacePlayerRemover;
import 'package:chessever2/screens/my_space/models/space_shortcut.dart';
import 'package:chessever2/screens/my_space/providers/space_players_provider.dart';
import 'package:chessever2/screens/my_space/providers/space_shortcuts_provider.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/widgets/app_snack.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

// What a See all page's Edit does with what the reader picked: takes it out
// of My Space (one snack, one Undo for all of it) or puts a card somewhere
// else in its group.

/// The keys a group's Edit selects by: a face's identity for Players (a
/// face can stand for a follow with no pin behind it), a pin's key for
/// everything else.
Set<String> spaceEditKeys(
  WidgetRef ref,
  SpaceSection section,
  List<SpaceShortcut> pins,
) {
  if (section == SpaceSection.players) {
    return {
      for (final e in ref.watch(spacePlayersProvider) ?? const []) e.identity,
    };
  }
  return {for (final s in pins) s.key};
}

/// Takes the things of [section] under [keys] out of My Space and offers one
/// Undo that puts every one of them back where it stood. A player leaves My
/// Space only: their pins go and their follow is hidden here, never
/// unfollowed. Returns how many left.
///
/// The cards leave the page at once and the snack follows them at once;
/// Undo puts them back at once too, whatever the server is doing. The
/// store writes a put-back row only once the delete it follows has
/// answered ([SpaceShortcutsNotifier.restore]), so the two never race.
/// Everything it needs is read before the first write, so it may finish
/// after the page has gone.
Future<int> spaceRemoveSelected({
  required BuildContext context,
  required WidgetRef ref,
  required SpaceSection section,
  required Set<String> keys,
}) async {
  if (keys.isEmpty) return 0;
  final messenger = ScaffoldMessenger.maybeOf(context);
  HapticFeedbackService.light();

  final int count;
  final Future<void> Function() undo;
  final Future<void> written;
  if (section == SpaceSection.players) {
    final entries = [
      for (final e in ref.read(spacePlayersProvider) ?? const [])
        if (keys.contains(e.identity)) e,
    ];
    final removers = [for (final e in entries) spacePlayerRemover(ref, e)];
    count = removers.length;
    // Every remover takes its face off the page now; their writes run
    // together.
    final removals = [for (final r in removers) r()];
    written = Future.wait([for (final r in removals) r.written]);
    undo = () => Future.wait([for (final r in removals) r.undo()]);
  } else {
    final store = ref.read(spaceShortcutsProvider.notifier);
    final doomed = [
      for (final s in ref.read(spaceShortcutsProvider).valueOrNull ?? const [])
        if (s.section == section && keys.contains(s.key)) s,
    ];
    count = doomed.length;
    // Each removal leaves the list at once; only its delete is awaited.
    written = Future.wait([
      for (final s in doomed) store.removeTarget(s.kind, s.targetId),
    ]);
    undo = () => Future.wait([for (final s in doomed) store.restore(s)]);
  }

  if (count > 0 && messenger != null && messenger.mounted) {
    showAppSnackOn(
      messenger,
      count == 1 ? 'Removed from My Space' : 'Removed $count from My Space',
      actionLabel: 'Undo',
      onAction: () {
        HapticFeedbackService.light();
        unawaited(
          undo().catchError((Object e) {
            debugPrint('[MySpace] undo failed: $e');
          }),
        );
      },
    );
  }
  try {
    await written;
  } catch (e) {
    debugPrint('[MySpace] remove failed: $e');
  }
  return count;
}

/// Where [key] lands in its section's stored row once it stands where
/// [visible] (the order the page shows, [key] in its new place) puts it:
/// right after the pin now before it, else right before the one after it.
/// Pins the page does not show keep their places.
int spaceStoreIndexFor(
  List<SpaceShortcut> sectionRow,
  String key,
  List<String> visible,
) {
  final store = [
    for (final s in sectionRow)
      if (s.key != key) s.key,
  ];
  final at = visible.indexOf(key);
  if (at > 0) {
    final before = store.indexOf(visible[at - 1]);
    if (before >= 0) return before + 1;
  }
  if (at >= 0 && at + 1 < visible.length) {
    final after = store.indexOf(visible[at + 1]);
    if (after >= 0) return after;
  }
  return at <= 0 ? 0 : store.length;
}

/// Puts the pin [key] of [section] where [visible] shows it.
Future<void> spaceReorderPin(
  WidgetRef ref,
  SpaceSection section,
  String key,
  List<String> visible,
) {
  final row =
      ref.read(spaceShortcutsBySectionProvider)[section] ??
      const <SpaceShortcut>[];
  return ref
      .read(spaceShortcutsProvider.notifier)
      .moveWithinSection(key, spaceStoreIndexFor(row, key, visible));
}
