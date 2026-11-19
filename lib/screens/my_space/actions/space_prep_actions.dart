import 'package:chessever2/screens/library/widgets/library_context_menu.dart';
import 'package:chessever2/screens/my_prep/models/prep_models.dart';
import 'package:chessever2/screens/my_prep/prep_actions.dart'
    show prepProfileMenu;
import 'package:chessever2/screens/my_space/actions/space_menu_action.dart';
import 'package:chessever2/screens/my_space/models/space_shortcut.dart';
import 'package:flutter/widgets.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// A Prep card's hold menu in My Space: the Prep page's own rows
/// ([prepProfileMenu]) in the Prep page's order, with this card's "Remove
/// from My Space" where the Prep page has its My Space row, and nothing that
/// deletes. Removing or clearing a profile's games stays on Prep: leaving My
/// Space never touches the source.
///
/// [profile] is the profile on this device that [pin] stands for. A pin made
/// on another device can key differently from that profile, so the My Space
/// row is always [pin]'s own. With no profile here yet (one still to be
/// rebuilt from another device), the card can only leave My Space.
List<LibraryMenuAction> spacePrepProfileMenu(
  BuildContext context,
  WidgetRef ref,
  SpaceShortcut pin,
  PrepProfile? profile,
) {
  final space = spaceMenuAction(context: context, ref: ref, draft: pin);
  if (profile == null) return [space];
  return [
    for (final action in prepProfileMenu(context, ref, profile))
      if (isSpaceMenuAction(action)) space else if (!action.destructive) action,
  ];
}
