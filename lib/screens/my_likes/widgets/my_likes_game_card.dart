import 'package:chessever2/constants/game_tags.dart';
import 'package:chessever2/repository/library/models/saved_analysis.dart';
import 'package:chessever2/screens/library/widgets/library_game_card.dart';
import 'package:chessever2/screens/library/widgets/swipe_action_card.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
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
  });

  final SavedAnalysis analysis;
  final GamesTourModel game;
  final bool isLocked;

  /// Opens the game on the board. For a locked card this is only reached after
  /// the user successfully subscribes via the paywall.
  final VoidCallback onOpen;

  /// Unlikes the game (hard-deletes the saved analysis).
  final Future<void> Function() onRemove;

  Future<void> _handleLockedTap(BuildContext context, WidgetRef ref) async {
    HapticFeedbackService.cardTap();
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
      onTap: isLocked ? () => _handleLockedTap(context, ref) : onOpen,
    );

    final visual =
        analysis.tags.isEmpty
            ? card
            : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [card, _buildTagsStrip(context)],
            );

    final content = isLocked ? _lockedOverlay(visual) : visual;

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

  /// Compact, read-only chips showing the tags the user attached to this game
  /// (set in the board save/edit sheet). Tapping them to filter happens via the
  /// tag row at the top of the screen, so these are non-interactive.
  Widget _buildTagsStrip(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(12.w, 6.h, 12.w, 2.h),
      child: Wrap(
        spacing: 6.w,
        runSpacing: 6.h,
        children: [
          for (final tag in analysis.tags)
            Container(
              padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
              decoration: BoxDecoration(
                color: context.colors.danger.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8.br),
                border: Border.all(
                  color: context.colors.danger.withValues(alpha: 0.25),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    iconForGameTag(tag),
                    size: 11.sp,
                    color: context.colors.danger.withValues(alpha: 0.9),
                  ),
                  SizedBox(width: 4.w),
                  Text(
                    tag,
                    style: AppTypography.textXxsMedium.copyWith(
                      color: context.colors.textPrimary.withValues(alpha: 0.75),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  String _eventName(SavedAnalysis analysis) {
    final md = analysis.chessGame.metadata;
    final raw = (md['Event'] ?? md['Site'] ?? '').toString().trim();
    return raw.isEmpty ? 'Library' : raw;
  }
}

class _PremiumBadge extends StatelessWidget {
  const _PremiumBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
      decoration: BoxDecoration(
        color: const Color(0xFFFFB300),
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
