import 'package:chessever2/screens/library/widgets/library_context_menu.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_app_bar_view_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/utils/knockout_match_detector.dart';
import 'package:chessever2/screens/tour_detail/games_tour/utils/round_space_shortcut.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/knockout_tournament_state_provider.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_mode_provider.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_screen_provider.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/card_context_menu.dart';
import 'package:chessever2/widgets/space_shortcut_drafts.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Round header in the Games tab. Tap folds the round; long-press lifts the
/// header into the shared focus menu to pin the round into My Space (and fold
/// it from there too).
class RoundHeader extends ConsumerWidget {
  final GamesAppBarModel round;
  final List<GamesTourModel> roundGames;
  final bool isExpanded;
  final VoidCallback? onToggle;

  const RoundHeader({
    super.key,
    required this.round,
    required this.roundGames,
    this.isExpanded = true,
    this.onToggle,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Removed all the individual visibility checking logic
    // Now handled centrally in GamesTourScreen for better performance

    // Format the round name better for knockout tournaments
    final displayName = _formatRoundName(round, roundGames);

    // Only what the round draft reads; both are stable while the event is
    // open, so a header never rebuilds for them mid-scroll.
    final about = ref.watch(
      tourDetailScreenProvider.select((s) => s.valueOrNull?.aboutTourModel),
    );
    final broadcastId = ref.watch(
      selectedBroadcastModelProvider.select((b) => b?.id),
    );
    final canPin =
        roundSpaceDraft(
          round: round,
          tourId: about?.id,
          groupBroadcastId: about?.groupBroadcastId ?? broadcastId,
        ) !=
        null;

    return CardContextMenu(
      enabled: canPin,
      actions: (menuContext) => _menuActions(menuContext, ref),
      child: _buildHeader(context, displayName),
    );
  }

  List<LibraryMenuAction> _menuActions(BuildContext context, WidgetRef ref) {
    final draft = currentEventRoundSpaceDraft(ref, round);
    if (draft == null) return const [];
    return [
      if (onToggle != null)
        LibraryMenuAction(
          icon: isExpanded ? Icons.unfold_less : Icons.unfold_more,
          label: isExpanded ? 'Collapse round' : 'Expand round',
          onSelected: onToggle!,
        ),
      labeledSpaceMenuAction(
        context: context,
        ref: ref,
        draft: draft,
        addLabel: 'Add round to My Space',
        removeLabel: 'Remove round from My Space',
      ),
    ];
  }

  Widget _buildHeader(BuildContext context, String displayName) {
    return InkWell(
      onTap: onToggle,
      borderRadius: BorderRadius.circular(12.br),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 16.sp, vertical: 14.sp),
        decoration: BoxDecoration(
          color: context.colors.surfaceRecessed,
          borderRadius: BorderRadius.circular(12.br),
          border: Border.all(color: context.colors.textPrimary.withValues(alpha: 0.1)),
          boxShadow: [
            BoxShadow(
              color: context.isLightTheme
                  ? context.colors.shadow
                  : Colors.black.withValues(alpha: 0.1),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 4.w,
              height: 20.h,
              decoration: BoxDecoration(
                color: context.colors.accentText,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            SizedBox(width: 12.w),
            Expanded(
              child: Text(
                '$displayName · ${round.formattedRoundDateTime}',
                style: TextStyle(
                  color: context.colors.textPrimary,
                  fontSize: 16.sp,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (onToggle != null) ...[
              SizedBox(width: 12.w),
              Icon(
                isExpanded
                    ? Icons.keyboard_arrow_up_rounded
                    : Icons.keyboard_arrow_down_rounded,
                color: context.textInk(0.5),
                size: 20.sp,
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _formatRoundName(GamesAppBarModel round, List<GamesTourModel> games) {
    final name = round.name;
    if (games.isEmpty) return name;

    // Check if this is a knockout match format
    final isKnockout = KnockoutMatchDetector.isKnockoutMatchFormat(games);
    final roundIdLower = round.id.toLowerCase();
    final isSyntheticKnockoutRound =
        roundIdLower.startsWith('$kKnockoutStagePrefix-') ||
        roundIdLower.startsWith('knockout-round-');

    // When we're showing a synthetic knockout round (e.g., "Round 1"),
    // keep the tournament stage name instead of downgrading to game slug labels.
    if (isKnockout && isSyntheticKnockoutRound) {
      return name;
    }

    if (isKnockout) {
      // Get first game's round slug to determine display
      final firstSlug = games.first.roundSlug?.toLowerCase() ?? '';

      if (firstSlug.startsWith('game-')) {
        // Standard game format: "Game 1", "Game 2", etc.
        return KnockoutMatchDetector.formatRoundSlug(firstSlug);
      } else if (firstSlug.contains('tiebreak')) {
        // Tiebreak format
        return KnockoutMatchDetector.formatRoundSlug(firstSlug);
      }
    }

    // Default: return the original name
    return name;
  }
}
