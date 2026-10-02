import 'package:chessever2/screens/for_you/discovery/models/discovery_models.dart';
import 'package:chessever2/screens/for_you/discovery/providers/discovery_providers.dart';
import 'package:chessever2/screens/for_you/discovery/widgets/discovery_game_cards.dart';
import 'package:chessever2/screens/library/miniatures_screen.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/widgets/time_control_glyph.dart';
import 'package:chessever2/screens/my_space/models/space_shortcut.dart';
import 'package:chessever2/screens/for_you/discovery/widgets/discovery_event_card.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// The event-style card for today's decisive games ending by move 25.
class TodaysMiniaturesSection extends ConsumerWidget {
  const TodaysMiniaturesSection({super.key});

  /// The Miniatures screen, browsed the same by everyone.
  static Future<void> open(BuildContext context) {
    HapticFeedbackService.cardTap();
    return Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const MiniaturesScreen()));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final minis = ref.watch(discoveryTodayMiniaturesProvider);
    final total = ref.watch(discoveryTodayMiniaturesTotalProvider);
    final empty = minis.valueOrNull?.isEmpty ?? false;
    return DiscoveryEventCard(
      key: const ValueKey('discovery_miniatures_card'),
      title: 'Miniatures',
      artSection: SpaceSection.games,
      count: total,
      caption: minis.hasError
          ? "Couldn't load today's miniatures"
          : empty
          ? 'No miniatures yet today'
          : 'Decisive games in 25 moves or fewer',
      onOpen: () => open(context),
      onRetry: minis.hasError
          ? () => ref.invalidate(discoveryTodayMiniaturesProvider)
          : null,
    );
  }

  /// "[owl] 19 moves · Ø 2751" over a grid or board card: the time-control
  /// glyph, then the length as the line's one bold figure, then the average
  /// rating. Ratings are never comma-grouped.
  static Widget miniatureMeta(DiscoveryMiniature mini) {
    final avg = discoveryAverageRating(mini.game);
    final unit = mini.moves == 1 ? ' move' : ' moves';
    final timeControl = mini.game.timeControl?.trim();
    return DiscoveryCardMeta(
      timeControlAsset: TimeControlGlyph.assetForLabel(mini.game.timeControl),
      parts: [
        DiscoveryMetaPart.figure('${mini.moves}', unit: unit),
        if (avg != null) DiscoveryMetaPart.figure('$avg', prefix: 'Ø '),
      ],
      semanticsLabel: [
        '${mini.moves}$unit',
        if (timeControl != null && timeControl.isNotEmpty) timeControl,
        if (avg != null) 'average rating $avg',
      ].join(', '),
    );
  }
}
