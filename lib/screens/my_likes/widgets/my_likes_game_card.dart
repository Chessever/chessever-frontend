import 'package:chessever2/repository/library/models/saved_analysis.dart';
import 'package:chessever2/repository/library/library_game_event.dart';
import 'package:chessever2/screens/library/widgets/library_game_card.dart';
import 'package:chessever2/screens/library/widgets/swipe_action_card.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/paywall/premium_paywall_sheet.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Greyscale matrix used to desaturate a premium-locked card.
const ColorFilter _greyscale = ColorFilter.matrix(<double>[
  0.2126, 0.7152, 0.0722, 0, 0, //
  0.2126, 0.7152, 0.0722, 0, 0, //
  0.2126, 0.7152, 0.0722, 0, 0, //
  0, 0, 0, 1, 0, //
]);

/// A liked game in the My Likes list. Renders the same [LibraryGameCard] as the
/// Favorites games tab; when [isLocked] (a free user, game liked > 7 days ago)
/// it is dimmed with a PREMIUM lock badge and tapping opens the paywall instead
/// of the game. Swiping left unlikes the game regardless of lock state.
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

  Future<void> _handleLockedTap(BuildContext context, WidgetRef ref) async {
    final unlocked = await requirePremiumGuard(context, ref);
    if (unlocked) onOpen();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final card = LibraryGameCard(
      game: game,
      eventName: _eventName(analysis),
      eco: game.eco,
      date: game.lastMoveTime,
      tags: analysis.tags,
      reserveTagSlot: true,
      tagCounts: tagCounts,
      onTap: isLocked ? () => _handleLockedTap(context, ref) : onOpen,
    );

    final content = isLocked ? _lockedOverlay(card) : card;

    return SwipeActionCard(
      dismissKey: ValueKey('mylikes_remove_${analysis.id}'),
      icon: Icons.heart_broken_rounded,
      label: 'Remove',
      backgroundColor: kRedColor,
      behavior: SwipeActionBehavior.dismiss,
      onAction: onRemove,
      child: content,
    );
  }

  Widget _lockedOverlay(Widget card) {
    return Stack(
      children: [
        ColorFiltered(
          colorFilter: _greyscale,
          child: Opacity(opacity: 0.55, child: card),
        ),
        Positioned(
          top: 8.h,
          right: 8.w,
          child: IgnorePointer(child: const _PremiumBadge()),
        ),
      ],
    );
  }

  String _eventName(SavedAnalysis analysis) {
    final md = analysis.chessGame.metadata;
    return chooseLibraryEventName(
          metadataEvent: md['Event']?.toString(),
          site: md['Site']?.toString(),
          whiteName: analysis.whiteName,
          blackName: analysis.blackName,
        ) ??
        'Library';
  }
}

class _PremiumBadge extends StatelessWidget {
  const _PremiumBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
      decoration: BoxDecoration(
        color: kPrimaryColor,
        borderRadius: BorderRadius.circular(8.br),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.lock_rounded, size: 12.sp, color: kBlackColor),
          SizedBox(width: 4.w),
          Text(
            'PREMIUM',
            style: AppTypography.textXxsBold.copyWith(
              color: kBlackColor,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}
