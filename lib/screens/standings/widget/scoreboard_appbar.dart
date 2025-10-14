import 'package:chessever2/screens/favorites/favorite_players_provider.dart';
import 'package:chessever2/screens/standings/widget/player_dropdown.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:chessever2/utils/svg_asset.dart';
import 'package:chessever2/widgets/svg_widget.dart';
import 'package:chessever2/screens/standings/score_card_screen.dart';

class ScoreboardAppbar extends ConsumerStatefulWidget {
  const ScoreboardAppbar({super.key});

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
    print('toggle pressed');
    final favoritesService = ref.read(favoritePlayersNotifierProvider.notifier);
    final player = ref.read(selectedPlayerProvider);

    if (player != null) {
      // Toggle in the tournament players favorites system
      final isNowFavorite = await favoritesService.toggleFavorite(player);

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
    final favoritesAsync = ref.watch(favoritePlayersNotifierProvider);
    final isFavorite = favoritesAsync.maybeWhen(
      data:
          (favorites) =>
              player != null &&
              favorites.players.any((fav) => fav.fideId == player.fideId),
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
        Expanded(child: const PlayerDropDown()),
        SizedBox(width: 16.w),
        InkWell(
          onTap: _toggleFavorite,
          child: Container(
            width: 48.w,
            height: 36.h,
            padding: EdgeInsets.all(8.sp),
            child: ScaleTransition(
              scale: _scaleAnimation,
              child: SvgWidget(
                isFavorite
                    ? SvgAsset.favouriteRedIcon
                    : SvgAsset.favouriteIcon2,
                semanticsLabel: 'Favorite Icon',
                height: 20.h,
                width: 20.w,
              ),
            ),
          ),
        ),
        SizedBox(width: 20.w),
      ],
    );
  }
}
