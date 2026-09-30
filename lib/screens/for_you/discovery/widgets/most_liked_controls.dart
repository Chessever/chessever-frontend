import 'package:chessever2/screens/standings/player_standing_model.dart';
import 'package:chessever2/widgets/figma_player_card.dart';
import 'package:chessever2/screens/for_you/discovery/models/discovery_models.dart';
import 'package:chessever2/screens/for_you/discovery/widgets/discovery_common.dart';
import 'package:chessever2/screens/player_profile/player_profile_screen.dart';
import 'package:chessever2/screens/player_profile/utils/player_menu_actions.dart';
import 'package:chessever2/screens/player_profile/widgets/lifted_row_menu.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// "‹  21–27 Sep  ›": walks the picked period one day, week, month or year
/// at a time. Earlier periods are Premium for free accounts, shown by the
/// padlock beside the arrow, and stop at the first day there were likes; the
/// next arrow is disabled on the current period, since the future has no
/// ranking. The page's one date control ([DiscoveryDateStepper]), so it
/// reads exactly like the Miniatures one.
class MostLikedDateControl extends StatelessWidget {
  const MostLikedDateControl({
    super.key,
    required this.query,
    required this.now,
    required this.locked,
    required this.onPrevious,
    required this.onNext,
    this.edgeInset = 0,
  });

  final MostLikedQuery query;
  final DateTime now;

  /// Earlier periods sit behind the Premium boundary for this viewer.
  final bool locked;

  /// Null when there is no earlier period to go to.
  final VoidCallback? onPrevious;

  /// Null on the current period.
  final VoidCallback? onNext;

  /// See [DiscoveryDateStepper.edgeInset].
  final double edgeInset;

  String get _unit => switch (query.period) {
    MostLikedPeriod.today => 'day',
    MostLikedPeriod.week => 'week',
    MostLikedPeriod.month => 'month',
    MostLikedPeriod.year => 'year',
  };

  @override
  Widget build(BuildContext context) {
    final label = query.label(now);
    return DiscoveryDateStepper(
      label: label,
      labelSemantics: 'Most liked, $label',
      previousSemantics: locked
          ? 'Previous $_unit, Premium'
          : 'Previous $_unit',
      nextSemantics: 'Next $_unit',
      previousLocked: locked,
      onPrevious: onPrevious,
      onNext: onNext,
      edgeInset: edgeInset,
    );
  }
}

/// The Players view: everyone with a game in the ranking, most-liked first.
/// Uses the same player card as Favorites, Countrymen and standings, with
/// likes in the trailing slot. A tap opens the player's
/// profile; a long press lifts the row into the player focus menu (profile,
/// My Space, share, favourites).
class MostLikedPlayersList extends StatelessWidget {
  const MostLikedPlayersList({super.key, required this.players, this.onPick});

  final List<MostLikedPlayer> players;

  /// When set, tapping a row picks them (the page narrows Games to them)
  /// instead of opening their profile.
  final ValueChanged<MostLikedPlayer>? onPick;

  /// A row's height at the default text size.
  static double get rowHeight => 80.w;

  /// The rank column.
  static double get rankWidth => 24.w;

  /// The profile circle's diameter.
  static double get avatarSize => 56.w;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: discoveryGutter),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final row in players)
            _PlayerRow(
              key: ValueKey('most_liked_player_${row.rank}'),
              row: row,
              onPick: onPick,
            ),
        ],
      ),
    );
  }
}

class _PlayerRow extends ConsumerWidget {
  const _PlayerRow({super.key, required this.row, this.onPick});

  final MostLikedPlayer row;
  final ValueChanged<MostLikedPlayer>? onPick;

  void _tap(BuildContext context) {
    final pick = onPick;
    if (pick != null) {
      HapticFeedbackService.cardTap();
      pick(row);
      return;
    }
    _open(context);
  }

  void _open(BuildContext context) {
    HapticFeedbackService.cardTap();
    final p = row.player;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PlayerProfileScreen(
          fideId: p.fideId,
          playerName: p.name,
          title: p.title.trim().isEmpty ? null : p.title.trim(),
          federation: p.countryCode.trim().isEmpty
              ? null
              : p.countryCode.trim(),
          rating: p.rating > 0 ? p.rating : null,
          gamebasePlayerId: p.gamebasePlayerId,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = row.player;
    final title = p.title.trim();
    final flag = p.countryCode.trim();
    final games = row.games == 1 ? '1 game' : '${row.games} games';
    final detail = [if (p.rating > 0) '${p.rating}', games].join(' · ');

    // Long-press lifts the row into the shared focus menu. The row's one
    // semantics node sits above the menu and carries both actions, so a
    // screen reader can open the profile and reach the menu from the row.
    final menu = LiftedRowMenu(
      onPreviewTap: () => _open(context),
      actions: (rowContext) => playerMenuActions(
        rowContext,
        ref,
        playerName: p.name,
        fideId: p.fideId,
        title: title.isEmpty ? null : title,
        federation: flag.isEmpty ? null : flag,
        rating: p.rating > 0 ? p.rating : null,
        gamebasePlayerId: p.gamebasePlayerId,
        onOpen: () {
          if (context.mounted) _open(context);
        },
      ),
      child: FigmaPlayerCard(
        player: PlayerStandingModel(
          name: p.name,
          fideId: p.fideId,
          gamebasePlayerId: p.gamebasePlayerId,
          title: title.isEmpty ? null : title,
          countryCode: flag,
          score: p.rating,
          scoreChange: 0,
          hasRatingDiff: false,
          matchScore: null,
        ),
        rank: row.rank,
        onTap: () => _tap(context),
        trailing: DiscoveryLikes(likes: row.likes),
      ),
    );
    final likes = discoveryLikes(row.likes);
    return Builder(
      builder: (rowContext) => Semantics(
        container: true,
        button: true,
        label:
            '${row.rank}, ${[if (title.isNotEmpty) title, p.name].join(' ')}, '
            '$detail, $likes',
        onTap: () => _tap(context),
        onLongPress: () => menu.open(rowContext),
        onLongPressHint: 'More actions',
        excludeSemantics: true,
        child: menu,
      ),
    );
  }
}
