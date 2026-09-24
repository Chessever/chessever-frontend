import 'dart:math' as math;

import 'package:chessever2/repository/library/models/saved_analysis.dart';
import 'package:chessever2/repository/library/library_game_event.dart';
import 'package:chessever2/screens/for_you/discovery/widgets/discovery_common.dart';
import 'package:chessever2/screens/library/widgets/library_game_card.dart';
import 'package:chessever2/screens/library/widgets/saved_game_actions.dart';
import 'package:chessever2/screens/library/widgets/swipe_action_card.dart';
import 'package:chessever2/screens/my_likes/widgets/my_likes_archive_boundary.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/app_button.dart';
import 'package:chessever2/widgets/card_context_menu.dart';
import 'package:chessever2/widgets/paywall/premium_paywall_sheet.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:chessever2/theme/app_colors.dart';

/// Greyscale matrix used to desaturate a premium-locked card.
const ColorFilter _greyscale = ColorFilter.matrix(<double>[
  0.2126, 0.7152, 0.0722, 0, 0, //
  0.2126, 0.7152, 0.0722, 0, 0, //
  0.2126, 0.7152, 0.0722, 0, 0, //
  0, 0, 0, 1, 0, //
]);

/// A liked game in the My Likes list. Renders the same [LibraryGameCard] as the
/// Favorites games tab; when [isLocked] (a free user, a like older than their
/// latest 20) it is dimmed with the For You lock notch cut into its corner and
/// tapping opens the paywall instead of the game. Swiping left unlikes the game
/// regardless of lock state.
class MyLikesGameCard extends ConsumerWidget {
  const MyLikesGameCard({
    super.key,
    required this.analysis,
    required this.game,
    required this.isLocked,
    required this.onOpen,
    required this.onRemove,
    this.tagCounts,
  });

  final SavedAnalysis analysis;
  final GamesTourModel game;
  final bool isLocked;

  /// Library-wide tag → game-count map. Threaded into [LibraryGameCard] so
  /// chips render with the dominant tag first.
  final Map<String, int>? tagCounts;

  /// Opens the game on the board. For a locked card this is only reached after
  /// the user successfully subscribes via the paywall.
  final VoidCallback onOpen;

  /// Unlikes the game (hard-deletes the saved analysis).
  final Future<void> Function() onRemove;

  /// Opens the paywall; a confirmed purchase or restore resumes straight into
  /// this game.
  Future<void> _handleLockedTap(BuildContext context, WidgetRef ref) async {
    await requirePremiumGuard(
      context,
      ref,
      featureId: kMyLikesHistoryFeatureId,
      returnTo: kMyLikesReturnTo,
      onEntitled: onOpen,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    void openLocked() => _handleLockedTap(context, ref);

    Widget buildCard({VoidCallback? onLongPress, Widget? trailing}) {
      final card = LibraryGameCard(
        game: game,
        eventName: _eventName(analysis),
        eco: game.eco,
        date: game.lastMoveTime,
        // A locked like keeps its tags behind the paywall with the rest of the
        // analysis. The emptied slot is where the lock notch is cut, so the
        // cut never lands on a chip.
        tags: isLocked ? const <String>[] : analysis.tags,
        reserveTagSlot: true,
        tagCounts: tagCounts,
        onTap: isLocked ? openLocked : onOpen,
        onLongPress: isLocked ? null : onLongPress,
        trailing: isLocked ? null : trailing,
      );
      if (!isLocked) return card;
      return _LockedLikeCard(
        card: card,
        onTap: openLocked,
        onLongPress: onLongPress,
      );
    }

    final Widget content;
    if (isLocked) {
      // The lock notch owns the corner a 3-dot would sit in; a locked like
      // keeps its long-press menu (open behind the paywall, or remove).
      content = buildCard(
        onLongPress: () => showSavedGameActions(
          context: context,
          ref: ref,
          analysis: analysis,
          onOpen: openLocked,
          previewBuilder: (_) => buildCard(),
          onDelete: onRemove,
          deleteLabel: 'Remove from likes',
          deleteIcon: Icons.heart_broken_rounded,
          locked: true,
        ),
      );
    } else {
      // Long-press and the trailing 3-dot open one menu, with the card lifted
      // in place as its own preview.
      content = CardContextMenu(
        onPreviewTap: onOpen,
        actions: (cardContext) => savedGameMenuActions(
          context: cardContext,
          ref: ref,
          analysis: analysis,
          onOpen: onOpen,
          onDelete: onRemove,
          deleteLabel: 'Remove from likes',
          deleteIcon: Icons.heart_broken_rounded,
        ),
        child: buildCard(
          trailing: CardMoreButton(size: LibraryGameCard.trailingGlyphSize),
        ),
      );
    }

    return SwipeActionCard(
      dismissKey: ValueKey('mylikes_remove_${analysis.id}'),
      icon: Icons.heart_broken_rounded,
      label: 'Remove',
      backgroundColor:
          context.isLightTheme ? context.colors.danger : kRedColor,
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

/// A like older than a free user's latest 20: the card greyed and dimmed, with
/// the For You lock notch (the shared [DiscoveryPadlock]) cut out of its
/// bottom-right corner.
///
/// The notch is a real cut, so the page (or the long-press menu's scrim) shows
/// through it, rather than a square of page colour laid on top. Card, cut and
/// padlock press as one: the inner card's gestures are switched off and this
/// layer owns tap and long-press, so the notch never slides off the corner
/// while the card scales under a finger, and a tap on the padlock opens the
/// paywall like the rest of the card.
class _LockedLikeCard extends StatelessWidget {
  const _LockedLikeCard({
    required this.card,
    required this.onTap,
    this.onLongPress,
  });

  final Widget card;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    // Held inside the empty tag slot plus the card's bottom padding (25 tall
    // in design units), so the cut stays clear of the date row above it.
    final notch = math.min(22.w, 22.h);
    final longPress = onLongPress;

    return Semantics(
      label: 'Older like, opens with Premium',
      child: TappableScale(
        onTap: () {
          HapticFeedbackService.cardTap();
          onTap();
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onLongPress: longPress == null
              ? null
              : () {
                  HapticFeedbackService.buttonPress();
                  longPress();
                },
          child: Stack(
            children: [
              IgnorePointer(
                child: ClipPath(
                  clipper: _CornerNotchClipper(notch: notch, radius: 3.w),
                  child: ColorFiltered(
                    colorFilter: _greyscale,
                    child: Opacity(opacity: 0.55, child: card),
                  ),
                ),
              ),
              Positioned(
                right: 0,
                bottom: 0,
                width: notch,
                height: notch,
                child: const Center(child: DiscoveryPadlock()),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The card less a [notch]-sized square at its bottom-right corner. The one
/// inner corner of the cut is rounded by [radius], as in [DiscoveryLockNotch].
class _CornerNotchClipper extends CustomClipper<Path> {
  const _CornerNotchClipper({required this.notch, required this.radius});

  final double notch;
  final double radius;

  @override
  Path getClip(Size size) {
    // Overshoots the outer edges so no hairline of card survives along them.
    final cut = Path()
      ..addRRect(
        RRect.fromRectAndCorners(
          Rect.fromLTRB(
            size.width - notch,
            size.height - notch,
            size.width + 1,
            size.height + 1,
          ),
          topLeft: Radius.circular(radius),
        ),
      );
    return Path.combine(
      PathOperation.difference,
      Path()..addRect(Offset.zero & size),
      cut,
    );
  }

  @override
  bool shouldReclip(_CornerNotchClipper oldClipper) =>
      oldClipper.notch != notch || oldClipper.radius != radius;
}
