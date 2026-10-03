import 'package:chessever2/repository/library/models/saved_analysis.dart';
import 'package:chessever2/repository/library/library_game_event.dart';

import 'package:chessever2/screens/library/widgets/library_game_card.dart';
import 'package:chessever2/screens/library/widgets/saved_game_actions.dart';
import 'package:chessever2/screens/library/widgets/swipe_action_card.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/widgets/card_context_menu.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:chessever2/theme/app_colors.dart';

/// One shared card and menu for both tiers. Access is checked on actions,
/// never conveyed through a lock, missing metadata or a different renderer.
class MyLikesGameCard extends ConsumerWidget {
  const MyLikesGameCard({
    super.key,
    required this.analysis,
    required this.game,
    required this.onOpen,
    required this.onRemove,
    required this.beforeContentAction,
    this.tagCounts,
  });

  final SavedAnalysis analysis;
  final GamesTourModel game;

  /// The parent's access check, awaited before a menu action that reads the
  /// game (edit, copy, move).
  final Future<bool> Function() beforeContentAction;

  /// Library-wide tag → game-count map. Threaded into [LibraryGameCard] so
  /// chips render with the dominant tag first.
  final Map<String, int>? tagCounts;

  /// The parent's gated opening action: checks paid/rewarded access before
  /// opening the board, for both recent and archived likes.
  final VoidCallback onOpen;

  /// Unlikes the game (hard-deletes the saved analysis).
  final Future<void> Function() onRemove;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final content = CardContextMenu(
      onPreviewTap: onOpen,
      actions: (cardContext) => savedGameMenuActions(
        context: cardContext,
        ref: ref,
        analysis: analysis,
        onOpen: onOpen,
        onDelete: onRemove,
        deleteLabel: 'Remove from likes',
        deleteIcon: Icons.heart_broken_rounded,
        showSpaceAction: false,
        showShareAction: false,
        beforeContentAction: beforeContentAction,
      ),
      child: LibraryGameCard(
        game: game,
        eventName: _eventName(analysis),
        eco: game.eco,
        date: game.lastMoveTime,
        tags: analysis.tags,
        reserveTagSlot: true,
        tagCounts: tagCounts,
        onTap: onOpen,
        trailing: CardMoreButton(size: LibraryGameCard.trailingGlyphSize),
      ),
    );

    return SwipeActionCard(
      dismissKey: ValueKey('mylikes_remove_${analysis.id}'),
      icon: Icons.heart_broken_rounded,
      label: 'Remove',
      backgroundColor: context.isLightTheme ? context.colors.danger : kRedColor,
      behavior: SwipeActionBehavior.dismiss,
      onAction: onRemove,
      child: content,
    );
  }

  String _eventName(SavedAnalysis analysis) {
    final md = analysis.chessGame.metadata;
    return chooseLibraryEventName(
          canonicalEventName: md['BroadcastName']?.toString(),
          metadataEvent: md['Event']?.toString(),
          site: md['Site']?.toString(),
          whiteName: analysis.whiteName,
          blackName: analysis.blackName,
        ) ??
        'Library';
  }
}
