import 'package:chessever2/screens/my_likes/my_likes_screen.dart';
import 'package:chessever2/screens/my_space/library/space_library_bridge.dart';
import 'package:chessever2/screens/my_space/models/space_shortcut.dart';
import 'package:chessever2/screens/my_space/sheets/space_add_sheet.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/widgets/app_snack.dart';
import 'package:chessever2/widgets/auth/auth_upgrade_sheet.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// What each row's door does. Every door but My Likes adds right here, over
/// My Space, without leaving it: Library runs the Library tab's own add
/// flow, every other row opens its add sheet. My Likes is the door to the
/// full list, and says so with its arrow.
void openSpaceDoor(BuildContext context, WidgetRef ref, SpaceSection section) {
  HapticFeedbackService.buttonPress();
  switch (section) {
    case SpaceSection.library:
      _libraryAdd(context, ref);
    case SpaceSection.likes:
      Navigator.of(
        context,
      ).push(MaterialPageRoute<void>(builder: (_) => const MyLikesScreen()));
    case SpaceSection.links:
      showAppSnack(
        context,
        'Hold anything in ChessEver and choose Add to My Space',
      );
    case SpaceSection.players:
    case SpaceSection.events:
    case SpaceSection.games:
    case SpaceSection.smartEvents:
    case SpaceSection.openings:
      showSpaceAddSheet(context, ref, section);
  }
}

Future<void> _libraryAdd(BuildContext context, WidgetRef ref) async {
  if (!await requireFullAuthGuard(context)) return;
  if (!context.mounted) return;
  await spaceLibraryAdd(context, ref);
}
