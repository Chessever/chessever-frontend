import 'package:chessever2/screens/my_space/models/space_shortcut.dart';
import 'package:chessever2/screens/my_space/providers/space_edit_mode_provider.dart';
import 'package:chessever2/screens/my_space/widgets/space_door_actions.dart';
import 'package:chessever2/widgets/popover_add_fab.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// What the add button offers, in the order the page lists its groups.
const List<({IconData icon, String label, SpaceSection section})>
kSpaceAddChoices = [
  // Product scope: retain these entry points for later re-enablement.
  // (
  //   icon: Icons.emoji_events_outlined,
  //   label: 'Event',
  //   section: SpaceSection.events,
  // ),
  // (
  //   icon: Icons.person_outline_rounded,
  //   label: 'Player',
  //   section: SpaceSection.players,
  // ),
  // (icon: Icons.grid_view_outlined, label: 'Game', section: SpaceSection.games),
  // (
  //   icon: Icons.auto_stories_outlined,
  //   label: 'Opening',
  //   section: SpaceSection.openings,
  // ),
  (icon: Icons.dns_outlined, label: 'Database', section: SpaceSection.library),
  (
    icon: Icons.filter_none_outlined,
    label: 'Smart event',
    section: SpaceSection.smartEvents,
  ),
];

/// My Space's add button: everything that can be saved to My Space, then
/// Edit. In Edit the same button is Edit's save.
class SpaceAddFab extends ConsumerWidget {
  const SpaceAddFab({super.key});

  /// What the button announces.
  static const label = 'Add to My Space';

  /// What it announces in Edit, where a tap saves and ends Edit.
  static const saveLabel = 'Save edits';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final editing = ref.watch(spaceEditModeProvider);
    final edit = ref.read(spaceEditModeProvider.notifier);
    // A record, so Edit's row (no section) still differs from a dismissal.
    return PopoverAddFab<({SpaceSection? section})>(
      label: label,
      saveLabel: saveLabel,
      // One tap ends Edit, no popover.
      onSave: editing ? () => edit.state = false : null,
      choices: [
        for (final choice in kSpaceAddChoices)
          PopoverAddChoice(
            leading: Icon(choice.icon),
            label: choice.label,
            value: (section: choice.section),
          ),
        const PopoverAddChoice(
          leading: Icon(Icons.edit_outlined),
          label: 'Edit',
          value: (section: null),
        ),
      ],
      onPicked: (picked) {
        final section = picked.section;
        edit.state = section == null;
        if (section != null) openSpaceAdd(context, ref, section);
      },
    );
  }
}
