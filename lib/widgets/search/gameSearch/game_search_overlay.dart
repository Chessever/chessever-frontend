import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/search/gameSearch/enhanced_game_search.dart';
import 'package:chessever2/widgets/search/gameSearch/game_search_state_provider.dart';
import 'package:chessever2/widgets/search/gameSearch/model/game_search_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class GamesSearchOverlay extends ConsumerStatefulWidget {
  final String query;
  final Function(Games game) onGameTap;
  final VoidCallback? onDismiss;

  const GamesSearchOverlay({
    super.key,
    required this.query,
    required this.onGameTap,
    this.onDismiss,
  });

  @override
  ConsumerState<GamesSearchOverlay> createState() => _GamesSearchOverlayState();
}

class _GamesSearchOverlayState extends ConsumerState<GamesSearchOverlay>
    with TickerProviderStateMixin {
  late final AnimationController _overlayController;
  late final AnimationController _contentController;
  late final Animation<double> _overlayAnimation;
  late final Animation<double> _contentAnimation;
  late final Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
  }

  void _initializeAnimations() {
    _overlayController = AnimationController(
      duration: const Duration(milliseconds: 50),
      vsync: this,
    );

    _contentController = AnimationController(
      duration: const Duration(milliseconds: 50),
      vsync: this,
    );

    _overlayAnimation = CurvedAnimation(
      parent: _overlayController,
      curve: Curves.easeOutCubic,
    );

    _contentAnimation = CurvedAnimation(
      parent: _contentController,
      curve: Curves.easeOutBack,
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, -0.1),
      end: Offset.zero,
    ).animate(_contentAnimation);

    // Start animations
    _overlayController.forward();
    _contentController.forward();
  }

  @override
  void dispose() {
    _overlayController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Watch the search state
    final searchState = ref.watch(gameSearchStateProvider(widget.query));

    return AnimatedBuilder(
      animation: _overlayAnimation,
      builder: (context, child) {
        return FadeTransition(
          opacity: _overlayAnimation,
          child: SlideTransition(
            position: _slideAnimation,
            child: ScaleTransition(
              scale: _contentAnimation,
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 20),
                decoration: BoxDecoration(
                  color: Colors.grey[900],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: kWhiteColor.withOpacity(0.1)),
                  boxShadow: [
                    BoxShadow(
                      color: kBlackColor.withOpacity(0.3),
                      blurRadius: 20.br,
                      offset: const Offset(0, 8),
                    ),
                    BoxShadow(
                      color: kBlackColor.withOpacity(0.1),
                      blurRadius: 40.br,
                      offset: const Offset(0, 16),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12.br),
                  child: _buildContent(searchState),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildContent(GameSearchState state) {
    if (state.hasError) {
      return _ErrorState(message: state.errorMessage!);
    }

    if (state.isSearching) {
      return const _LoadingState();
    }

    if (state.isEmpty) {
      return _EmptyState(query: state.currentQuery);
    }

    if (state.isIdle) {
      return const _IdleState();
    }

    return _ResultsList(results: state.results, onGameTap: widget.onGameTap);
  }
}

class _ResultsList extends StatelessWidget {
  const _ResultsList({required this.results, required this.onGameTap});

  final List<GameSearchResult> results;
  final Function(Games game) onGameTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxHeight: 400, minHeight: 100),
      child: ListView.builder(
        shrinkWrap: true,
        physics: const ClampingScrollPhysics(),
        padding: EdgeInsets.zero,
        itemCount: results.length,
        itemBuilder: (context, index) {
          return AnimatedContainer(
            duration: Duration(milliseconds: 150 + (index * 30)),
            curve: Curves.easeOutCubic,
            child: _GameSearchResultTile(
              result: results[index],
              index: index,
              isLast: index == results.length - 1,
              onTap: () {
                HapticFeedback.selectionClick();
                onGameTap(results[index].game);
              },
            ),
          );
        },
      ),
    );
  }
}

class _GameSearchResultTile extends StatefulWidget {
  final GameSearchResult result;
  final int index;
  final bool isLast;
  final VoidCallback onTap;

  const _GameSearchResultTile({
    required this.result,
    required this.index,
    required this.isLast,
    required this.onTap,
  });

  @override
  State<_GameSearchResultTile> createState() => _GameSearchResultTileState();
}

class _GameSearchResultTileState extends State<_GameSearchResultTile>
    with TickerProviderStateMixin {
  bool _isHovered = false;
  bool _isPressed = false;

  late AnimationController _hoverController;
  late AnimationController _slideController;
  late Animation<double> _scaleAnimation;
  late Animation<Offset> _slideAnimation;
  late Animation<Color?> _colorAnimation;

  late final String _playerNames;

  @override
  void initState() {
    super.initState();
    _initializeData();
    _initializeAnimations();
    _startAnimation();
  }

  void _initializeData() {
    final game = widget.result.game;
    _playerNames =
        game.players?.map((p) => p.name).join(' vs ') ?? 'Unknown players';
  }

  void _initializeAnimations() {
    _hoverController = AnimationController(
      duration: const Duration(milliseconds: 50),
      vsync: this,
    );

    _slideController = AnimationController(
      duration: const Duration(milliseconds: 50),
      vsync: this,
    );

    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.015).animate(
      CurvedAnimation(parent: _hoverController, curve: Curves.easeInOutCubic),
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(-0.3, 0),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _slideController, curve: Curves.easeOutCubic),
    );

    _colorAnimation = ColorTween(
      begin: Colors.transparent,
      end: kWhiteColor.withOpacity(0.05),
    ).animate(_hoverController);
  }

  void _startAnimation() {
    Future.delayed(Duration(milliseconds: widget.index * 2), () {
      if (mounted) {
        _slideController.forward();
      }
    });
  }

  @override
  void dispose() {
    _hoverController.dispose();
    _slideController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SlideTransition(
      position: _slideAnimation,
      child: FadeTransition(
        opacity: _slideController,
        child: MouseRegion(
          onEnter:
              (_) => setState(() {
                _isHovered = true;
                _hoverController.forward();
              }),
          onExit:
              (_) => setState(() {
                _isHovered = false;
                _hoverController.reverse();
              }),
          child: AnimatedBuilder(
            animation: _hoverController,
            builder: (context, child) {
              return Transform.scale(
                scale: _scaleAnimation.value * (_isPressed ? 0.98 : 1.0),
                child: GestureDetector(
                  onTap: widget.onTap,
                  onTapDown: (_) => setState(() => _isPressed = true),
                  onTapUp: (_) => setState(() => _isPressed = false),
                  onTapCancel: () => setState(() => _isPressed = false),
                  child: Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: 12.sp,
                      vertical: 12.sp,
                    ),
                    decoration: BoxDecoration(
                      color: _colorAnimation.value,
                      borderRadius:
                          widget.index == 0
                              ? const BorderRadius.only(
                                topLeft: Radius.circular(12),
                                topRight: Radius.circular(12),
                              )
                              : BorderRadius.zero,
                      border:
                          !widget.isLast
                              ? Border(
                                bottom: BorderSide(
                                  color: kWhiteColor.withOpacity(0.1),
                                  width: 1.0,
                                ),
                              )
                              : null,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _playerNames,
                                style: TextStyle(
                                  color:
                                      _isHovered
                                          ? kWhiteColor
                                          : kWhiteColor.withOpacity(0.9),
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  letterSpacing: 0.2,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              SizedBox(height: 2.h),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _IdleState extends StatelessWidget {
  const _IdleState();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 120,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search,
              size: 32.ic,
              color: kBoardLightGrey.withOpacity(0.5),
            ),
            const SizedBox(height: 12),
            Text(
              'Start typing to search games',
              style: TextStyle(
                color: kBoardLightGrey.withOpacity(0.7),
                fontSize: 14.f,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 200.h,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 24.w,
              height: 24.h,
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(kDarkBlue),
                strokeWidth: 2.5.w,
              ),
            ),
            SizedBox(height: 20.h),
            Text(
              'Searching games...',
              style: TextStyle(
                color: kWhiteColor70,
                fontSize: 14.f,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;

  const _ErrorState({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(16),
      height: 100,
      decoration: BoxDecoration(
        color: kRedColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kRedColor.withOpacity(0.3)),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, color: kRedColor, size: 24.f),
            SizedBox(height: 8.h),
            Text(
              message,
              style: TextStyle(
                color: kRedColor,
                fontSize: 14.f,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String query;

  const _EmptyState({required this.query});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 180,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.0, end: 1.0),
              duration: const Duration(milliseconds: 600),
              builder: (context, value, child) {
                return Transform.scale(
                  scale: 0.8 + (0.2 * value),
                  child: Opacity(
                    opacity: value,
                    child: Icon(
                      Icons.search_off,
                      size: 48.ic,
                      color: kBoardLightGrey.withOpacity(0.6),
                    ),
                  ),
                );
              },
            ),
            SizedBox(height: 16.h),
            Text(
              'No games found',
              style: TextStyle(
                color: kWhiteColor,
                fontSize: 16.f,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.5,
              ),
            ),
            SizedBox(height: 6.h),
            Text(
              'Try different keywords for "$query"',
              style: TextStyle(
                color: kBoardLightGrey.withOpacity(0.8),
                fontSize: 13.f,
                fontWeight: FontWeight.w400,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
