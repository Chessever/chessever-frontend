import 'package:chessever2/screens/collections/opening_event_card.dart';
import 'package:chessever2/screens/library/widgets/library_context_menu.dart';
import 'package:chessever2/screens/my_space/actions/space_menu_action.dart';
import 'package:chessever2/screens/my_space/models/space_shortcut.dart';
import 'package:chessever2/screens/my_space/navigation/space_shortcut_navigator.dart';
import 'package:chessever2/screens/my_space/widgets/space_tile_content.dart'
    show spaceOpeningFace;
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Saved openings use the same event frame and core position as Collections.
/// Their established explorer destination and long-press menu stay intact.
class SpaceOpeningCard extends ConsumerWidget {
  const SpaceOpeningCard({super.key, required this.shortcut});
  final SpaceShortcut shortcut;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final face = spaceOpeningFace(shortcut);
    void open() {
      HapticFeedbackService.cardTap();
      openSpaceShortcut(context, ref, shortcut);
    }

    return OpeningEventCard(
      name: face.name,
      eco: face.eco,
      fen: face.fen,
      lastMove: face.lastMove,
      caption: face.caption,
      onTap: open,
      gameCount: int.tryParse('${shortcut.params['gameCount'] ?? ''}'),
      menuActions: (menuContext) => [
        LibraryMenuAction(
          icon: Icons.open_in_new_rounded,
          label: 'Open',
          onSelected: open,
        ),
        spaceMenuAction(context: menuContext, ref: ref, draft: shortcut),
      ],
    );
  }
}
