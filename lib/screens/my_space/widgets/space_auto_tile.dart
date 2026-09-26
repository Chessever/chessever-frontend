import 'dart:async';

import 'package:chessever2/repository/library/models/saved_analysis.dart';
import 'package:chessever2/repository/liked_games/liked_games_provider.dart';
import 'package:chessever2/screens/library/utils/load_saved_analysis.dart';
import 'package:chessever2/screens/library/widgets/library_context_menu.dart';
import 'package:chessever2/screens/library/widgets/saved_game_actions.dart';
import 'package:chessever2/screens/my_likes/provider/my_likes_provider.dart'
    show myLikesTagCountsProvider, myLikesViewProvider;
import 'package:chessever2/screens/my_space/actions/space_share.dart';
import 'package:chessever2/screens/my_space/library/space_library_bridge.dart';
import 'package:chessever2/screens/my_space/models/space_auto_item.dart';
import 'package:chessever2/screens/my_space/models/space_shortcut.dart';
import 'package:chessever2/screens/my_space/navigation/space_shortcut_navigator.dart';
import 'package:chessever2/screens/my_space/providers/space_auto_provider.dart';
import 'package:chessever2/screens/my_space/providers/space_shortcuts_provider.dart';
import 'package:chessever2/screens/my_space/widgets/space_tile.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/widgets/app_snack.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:share_plus/share_plus.dart';

/// A tile a row shows without it being pinned: a Library destination, a liked
/// game, or a suggestion. It opens like the thing it stands for and carries
/// that thing's own menu (the Library card's, the My Likes card's), or, for a
/// suggestion, Pin to My Space and Hide. It is never carried, reordered or
/// thrown out; the rows and "See all" build every such tile here.
class SpaceAutoTile extends ConsumerWidget {
  const SpaceAutoTile({
    super.key,
    required this.item,
    required this.section,
    required this.onOpen,
    this.liked = const [],
    this.slotX = 0,
    this.slotY = 0,
    this.entering = false,
  });

  final SpaceAutoItem item;
  final SpaceSection section;

  /// Every liked game the row mirrors, newest first, so opening one swipes
  /// through the rest like My Likes does.
  final List<SavedAnalysis> liked;

  /// Runs an open through the host's one-at-a-time guard.
  final void Function(Future<void> Function() open) onOpen;
  final double slotX;
  final double slotY;
  final bool entering;

  Future<void> _open(BuildContext context, WidgetRef ref) async {
    final folder = item.folder;
    final analysis = item.analysis;
    if (folder != null) {
      await spaceOpenLibraryFolder(context, folder);
      return;
    }
    if (analysis != null) {
      HapticFeedbackService.cardTap();
      final index = liked.indexWhere((a) => a.id == analysis.id);
      if (index < 0) {
        await loadSavedAnalysis(context, analysis);
      } else {
        await loadSavedAnalysisWithSwiping(context, liked, index);
      }
      return;
    }
    HapticFeedbackService.cardTap();
    await openSpaceShortcut(context, ref, item.shortcut);
  }

  List<LibraryMenuAction> _actions(
    BuildContext context,
    WidgetRef ref,
    VoidCallback open,
  ) {
    final openRow = LibraryMenuAction(
      icon: Icons.north_east_rounded,
      label: 'Open',
      onSelected: open,
    );
    final folder = item.folder;
    if (folder != null) {
      return [openRow, ...spaceLibraryFolderActions(context, ref, folder)];
    }
    final analysis = item.analysis;
    if (analysis != null) {
      final messenger = ScaffoldMessenger.maybeOf(context);
      final likes = ref.read(likedGamesProvider.notifier);
      final container = ProviderScope.containerOf(context, listen: false);
      return savedGameMenuActions(
        context: context,
        ref: ref,
        analysis: analysis,
        onOpen: open,
        deleteLabel: 'Remove from likes',
        deleteIcon: Icons.heart_broken_rounded,
        onDelete: () async {
          final removed = await likes.removeAnalysis(analysis);
          if (removed) {
            container.invalidate(myLikesViewProvider);
            container.invalidate(myLikesTagCountsProvider);
          } else if (messenger != null && messenger.mounted) {
            showAppSnackOn(
              messenger,
              "Couldn't remove this like. Please try again.",
              tone: AppSnackTone.danger,
            );
          }
        },
      );
    }
    return _suggestionActions(context, ref, openRow);
  }

  List<LibraryMenuAction> _suggestionActions(
    BuildContext context,
    WidgetRef ref,
    LibraryMenuAction openRow,
  ) {
    final draft = item.shortcut;
    final messenger = ScaffoldMessenger.maybeOf(context);
    final store = ref.read(spaceShortcutsProvider.notifier);
    final hidden = ref.read(spaceHiddenAutoKeysProvider.notifier);
    final url = spaceShortcutShareUrl(draft);

    void say(
      String message, {
      AppSnackTone tone = AppSnackTone.neutral,
      FutureOr<void> Function()? undo,
    }) {
      if (messenger == null || !messenger.mounted) return;
      showAppSnackOn(
        messenger,
        message,
        tone: tone,
        actionLabel: undo == null ? null : 'Undo',
        onAction: undo,
      );
    }

    return [
      openRow,
      LibraryMenuAction(
        icon: Icons.push_pin_outlined,
        label: 'Pin to My Space',
        onSelected: () async {
          final added = await store.add(draft);
          HapticFeedbackService.success();
          say(
            added ? 'Pinned to ${section.title}' : 'Already in My Space',
            tone: added ? AppSnackTone.success : AppSnackTone.neutral,
            undo: added
                ? () => store.removeTarget(draft.kind, draft.targetId)
                : null,
          );
        },
      ),
      if (url != null) ...[
        LibraryMenuAction(
          icon: Icons.ios_share_rounded,
          label: 'Share',
          onSelected: () async {
            // iPad anchors the share sheet to the tile it came from.
            final box = context.mounted ? context.findRenderObject() : null;
            final origin = box is RenderBox && box.hasSize
                ? box.localToGlobal(Offset.zero) & box.size
                : const Rect.fromLTWH(0, 0, 1, 1);
            try {
              await Share.share(url, sharePositionOrigin: origin);
            } catch (e) {
              debugPrint('[MySpace] share failed: $e');
            }
          },
        ),
        LibraryMenuAction(
          icon: Icons.link_rounded,
          label: 'Copy link',
          onSelected: () {
            Clipboard.setData(ClipboardData(text: url));
            HapticFeedbackService.success();
            say('Link copied');
          },
        ),
      ],
      LibraryMenuAction(
        icon: Icons.visibility_off_outlined,
        label: 'Hide',
        onSelected: () {
          hidden.hide(draft.key);
          HapticFeedbackService.light();
          say(
            'Hidden from ${section.title}',
            undo: () => hidden.unhide(draft.key),
          );
        },
      ),
    ];
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    void open() => onOpen(() => _open(context, ref));
    final folder = item.folder;
    return SpaceTile(
      shortcut: item.shortcut,
      slotX: slotX,
      slotY: slotY,
      entering: entering,
      swipeToRemove: false,
      canMoveToFront: false,
      holdToGrab: false,
      onOpen: open,
      onMoveToFront: () {},
      onRemove: () async => false,
      menuActions: (menuContext) => _actions(context, ref, open),
      subtitle: folder == null
          ? null
          : SpaceLibraryCountText(key: ValueKey(folder), folder: folder),
    );
  }
}
