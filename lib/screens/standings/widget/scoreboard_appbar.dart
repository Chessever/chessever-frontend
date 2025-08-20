import 'package:chessever2/screens/standings/widget/player_dropdown.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../../utils/svg_asset.dart';
import '../../../widgets/svg_widget.dart';
import '../score_card_screen.dart';
import '../standing_screen_provider.dart';

class ScoreboardAppbar extends ConsumerStatefulWidget {
  final String playerName;

  const ScoreboardAppbar({
    required this.playerName,
    super.key,
  });

  @override
  ConsumerState<ScoreboardAppbar> createState() => _ScoreboardAppbarState();
}

class _ScoreboardAppbarState extends ConsumerState<ScoreboardAppbar>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;
  bool _isFavorite = false;

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

    _loadFavoriteStatus();
  }

  Future<void> _loadFavoriteStatus() async {
    final favoritesService = ref.read(favoritesServiceProvider);
    final favorites = await favoritesService.getFavoritePlayers();
    if (mounted) {
      setState(() {
        _isFavorite = favorites.any(
          (player) => player.name == widget.playerName,
        );
      });
    }
  }

  @override
  void didUpdateWidget(ScoreboardAppbar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.playerName != widget.playerName) {
      _loadFavoriteStatus();
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _toggleFavorite() async {
    final favoritesService = ref.read(favoritesServiceProvider);
    final player = ref.read(selectedPlayerProvider);

    if (player != null) {
      await favoritesService.toggleFavorite(player);

      ref.invalidate(favoritePlayersProvider);

      if (mounted) {
        setState(() {
          _isFavorite = !_isFavorite;
        });
      }

      if (_isFavorite) {
        _animationController.forward().then(
          (_) => _animationController.reverse(),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(width: 16.w),
        IconButton(
          iconSize: 24.ic,
          padding: EdgeInsets.zero,
          onPressed: () {
            Navigator.of(context).pop();
          },
          icon: Icon(
            Icons.arrow_back_ios_new_outlined,
            size: 24.ic,
          ),
        ),
        const Spacer(),
        const PlayerDropDown(),
        const Spacer(),
        GestureDetector(
          onTap: _toggleFavorite,
          behavior: HitTestBehavior.opaque,
          child: SizedBox(
            width: 32.w,
            child: ScaleTransition(
              scale: _scaleAnimation,
              child: SvgWidget(
                _isFavorite
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
