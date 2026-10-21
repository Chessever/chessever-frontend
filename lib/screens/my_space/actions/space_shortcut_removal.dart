import 'package:chessever2/screens/my_space/models/space_shortcut.dart';
import 'package:chessever2/screens/my_space/providers/space_auto_provider.dart';
import 'package:chessever2/screens/my_space/providers/space_shortcuts_provider.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// A removal owns only My Space's pin and visibility. Source repositories
/// are never involved, including when an automatic card stands in for a pin.
typedef SpaceShortcutRemoval = ({
  Future<void> written,
  Future<void> Function() undo,
});

SpaceShortcutRemoval Function() spaceShortcutRemover(
  WidgetRef ref,
  SpaceShortcut target,
) {
  final store = ref.read(spaceShortcutsProvider.notifier);
  final hidden = ref.read(spaceHiddenAutoKeysProvider.notifier);
  final wasHidden = ref.read(spaceHiddenAutoKeysProvider).contains(target.key);
  final pin = (ref.read(spaceShortcutsProvider).valueOrNull ?? const [])
      .where((s) => s.key == target.key)
      .firstOrNull;
  // A menu invokes this after its route closes; no WidgetRef survives into
  // the callback. Undo can likewise outlive the card that was removed.
  return () {
    hidden.hide(target.key);
    final written = store
        .removeTarget(target.kind, target.targetId)
        .then((_) {});
    return (
      written: written,
      undo: () async {
        if (!wasHidden) hidden.unhide(target.key);
        if (pin != null) await store.restore(pin);
      },
    );
  };
}

SpaceShortcutRemoval removeSpaceShortcut(WidgetRef ref, SpaceShortcut target) =>
    spaceShortcutRemover(ref, target)();
