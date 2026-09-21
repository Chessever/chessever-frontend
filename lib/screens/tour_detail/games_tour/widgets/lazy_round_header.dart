import 'viewport_game_card.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_screen_provider.dart';
import 'package:chessever2/theme/app_colors.dart';
import '../models/games_app_bar_view_model.dart';
import '../models/games_tour_model.dart';
import '../providers/games_tour_provider.dart';
import '../providers/knockout_stage_round_resolver.dart';
import 'round_header_widget.dart';

/// Keep a just-opened round responsive while its first roster is in flight.
class LazyRoundHeader extends ConsumerWidget {
  const LazyRoundHeader({
    super.key,
    required this.round,
    required this.roundGames,
    required this.isExpanded,
    this.onToggle,
  });

  final GamesAppBarModel round;
  final List<GamesTourModel> roundGames;
  final bool isExpanded;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Widget? status;
    final detail = ref.watch(tourDetailScreenProvider).valueOrNull;
    if (isExpanded && roundGames.isEmpty && detail != null) {
      final stage = resolveKnockoutStageRoundReference(
        round: round,
        selectedTourId: detail.aboutTourModel.id,
        knownTourIds: detail.tours.map((tour) => tour.tour.id),
      );
      final owner = stage?.siblingTourId ?? detail.aboutTourModel.id;
      ref.watch(gamesTourProvider(owner));
      final loader = ref.read(gamesTourProvider(owner).notifier);
      final sources =
          round.sourceRoundIds.isEmpty ? [round.id] : round.sourceRoundIds;
      final failed = sources.any(loader.roundErrors.containsKey);
      final loaded =
          loader.isCatalogComplete ||
          sources.every(loader.loadedRoundIds.contains);
      status = Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child:
            failed
                ? TextButton(
                  onPressed: loader.refreshGames,
                  child: const Text('Could not load games. Retry'),
                )
                : loaded
                ? Text(
                  'No games available yet',
                  style: TextStyle(color: context.colors.textSecondary),
                )
                : const TournamentCardShimmer(),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RoundHeader(
          round: round,
          roundGames: roundGames,
          isExpanded: isExpanded,
          onToggle: onToggle,
        ),
        if (status != null) status,
      ],
    );
  }
}
