import 'package:chessever2/repository/local_storage/favorite/favourate_standings_player_services.dart';
import 'package:chessever2/repository/local_storage/unified_favorites/unified_favorites_provider.dart';
import 'package:chessever2/screens/standings/widget/player_dropdown.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../../utils/svg_asset.dart';
import '../../../widgets/svg_widget.dart';
import '../score_card_screen.dart';
import '../../tour_detail/player_tour/player_tour_screen_provider.dart';

class ScoreboardAppbar extends ConsumerStatefulWidget {
  final String playerName;

  const ScoreboardAppbar({required this.playerName, super.key});

  @override
  ConsumerState<ScoreboardAppbar> createState() => _ScoreboardAppbarState();
}

class _ScoreboardAppbarState extends ConsumerState<ScoreboardAppbar>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();

    // Animation setup
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );

    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.2).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _toggleFavorite() async {
    final favoritesService = ref.read(favoriteStandingsPlayerService);
    final player = ref.read(selectedPlayerProvider);

    if (player != null) {
      // Toggle in the tournament players favorites system
      await favoritesService.toggleFavorite(player);
      ref.invalidate(tournamentFavoritePlayersProvider);
      final favorites = await favoritesService.getFavoritePlayers();
      final isNowFavorite = favorites.any((fav) => fav.name == player.name);

      // NOTE: We don't sync with unified favorites system here because
      // PlayerStandingModel doesn't have fideId. Users should favorite
      // players from the Players tab to add them to unified favorites.

      if (isNowFavorite) {
        _animationController.forward().then(
          (_) => _animationController.reverse(),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final player = ref.watch(selectedPlayerProvider);
    final favoritesAsync = ref.watch(tournamentFavoritePlayersProvider);
    final isFavorite = favoritesAsync.maybeWhen(
      data:
          (favorites) =>
              player != null && favorites.any((fav) => fav.name == player.name),
      orElse: () => false,
    );

    return Row(
      children: [
        SizedBox(width: 16.w),
        IconButton(
          iconSize: 24.ic,
          padding: EdgeInsets.zero,
          onPressed: () {
            Navigator.of(context).pop();
          },
          icon: Icon(Icons.arrow_back_ios_new_outlined, size: 24.ic),
        ),
        SizedBox(width: 16.w),
        Expanded(
          child: const PlayerDropDown(),
        ),
        SizedBox(width: 16.w),
        GestureDetector(
          onTap: _toggleFavorite,
          behavior: HitTestBehavior.opaque,
          child: SizedBox(
            width: 32.w,
            child: ScaleTransition(
              scale: _scaleAnimation,
              child: SvgWidget(
                isFavorite
                    ? SvgAsset.favouriteRedIcon
                    : SvgAsset.favouriteIcon2,
                semanticsLabel: 'Favorite Icon',
                height: 14.h,
                width: 14.w,
              ),
            ),
          ),
        ),
        SizedBox(width: 20.w),
      ],
    );
  }
}
