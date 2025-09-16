import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/widgets/search/gameSearch/enhanced_game_search.dart';
import 'package:chessever2/widgets/search/gameSearch/game_search_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'dart:async';

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

  Timer? _searchDebouncer;
  String? _lastQuery;
  EnhancedGameSearchResult? _cachedResult;
  bool _isSearching = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _initializeController();
    _startInitialSearch();
  }

  void _initializeAnimations() {
    _overlayController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _contentController = AnimationController(
      duration: const Duration(milliseconds: 400),
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

  void _initializeController() {
    final controller = ref.read(gameSearchProvider);
    controller.tryInitializeFromProvider();
  }

  void _startInitialSearch() {
    if (widget.query.isNotEmpty) {
      _performSearch(widget.query);
    }
  }

  @override
  void didUpdateWidget(GamesSearchOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.query != widget.query) {
      _performSearch(widget.query);
    }
  }

  void _performSearch(String query) {
    if (query.isEmpty) {
      setState(() {
        _cachedResult = EnhancedGameSearchResult(
          results: [],
          timestamp: DateTime.now(),
        );
        _isSearching = false;
        _errorMessage = null;
      });
      return;
    }

    // Debounce search to prevent excessive API calls
    _searchDebouncer?.cancel();
    _searchDebouncer = Timer(const Duration(milliseconds: 300), () {
      _executeSearch(query);
    });
  }

  Future<void> _executeSearch(String query) async {
    if (_lastQuery == query && _cachedResult != null) {
      return; // Use cached result
    }

    setState(() {
      _isSearching = true;
      _errorMessage = null;
    });

    try {
      final controller = ref.read(gameSearchProvider);

      if (controller.selectedTourId == null) {
        setState(() {
          _errorMessage = 'No tournament selected';
          _isSearching = false;
        });
        return;
      }

      final result = await controller.searchGames(query);

      if (mounted) {
        setState(() {
          _cachedResult = result;
          _lastQuery = query;
          _isSearching = false;
          _errorMessage = null;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Search failed. Please try again.';
          _isSearching = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _searchDebouncer?.cancel();
    _overlayController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
                  color: kDarkGreyColor,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: kDarkGreyColor.withOpacity(0.4)),
                  boxShadow: [
                    BoxShadow(
                      color: kBlackColor.withOpacity(0.3),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                    BoxShadow(
                      color: kBlackColor.withOpacity(0.1),
                      blurRadius: 40,
                      offset: const Offset(0, 16),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: _SearchOverlay(
                    errorMessage: _errorMessage,
                    isSearching: _isSearching,
                    cachedResult: _cachedResult,
                    query: widget.query,
                    onGameTap: widget.onGameTap,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SearchOverlay extends ConsumerWidget {
  const _SearchOverlay({
    required this.errorMessage,
    required this.isSearching,
    required this.cachedResult,
    required this.query,
    required this.onGameTap,
    super.key,
  });

  final String? errorMessage;
  final bool isSearching;
  final EnhancedGameSearchResult? cachedResult;
  final String query;
  final Function(Games game) onGameTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (errorMessage != null) {
      return _ErrorState(message: errorMessage!);
    }

    if (isSearching) {
      return _LoadingState();
    }

    final searchResult =
        cachedResult ??
        EnhancedGameSearchResult(results: [], timestamp: DateTime.now());

    if (searchResult.results.isEmpty && query.isNotEmpty) {
      return _EmptyState(query: query);
    }

    if (searchResult.results.isEmpty) {
      return _IdleState();
    }

    final controller = ref.read(gameSearchProvider);
    final sortedResults = controller.sortSearchResultsByRoundOrder(
      searchResult.results,
    );

    return Container(
      constraints: const BoxConstraints(maxHeight: 400, minHeight: 100),
      child: ListView.builder(
        shrinkWrap: true,
        physics: const ClampingScrollPhysics(),
        padding: EdgeInsets.zero,
        itemCount: sortedResults.length,
        itemBuilder: (context, index) {
          return AnimatedContainer(
            duration: Duration(milliseconds: 150 + (index * 30)),
            curve: Curves.easeOutCubic,
            child: _EnhancedGameSearchResultTile(
              result: sortedResults[index],
              index: index,
              isLast: index == sortedResults.length - 1,
              onTap: () {
                HapticFeedback.selectionClick();
                onGameTap(sortedResults[index].game);
              },
            ),
          );
        },
      ),
    );
  }
}

class _IdleState extends StatelessWidget {
  const _IdleState({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 120,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search,
              size: 32,
              color: kBoardLightGrey.withOpacity(0.5),
            ),
            const SizedBox(height: 12),
            Text(
              'Start typing to search games',
              style: TextStyle(
                color: kBoardLightGrey.withOpacity(0.7),
                fontSize: 14,
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

  const _ErrorState({required this.message, super.key});

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
            const Icon(Icons.error_outline, color: kRedColor, size: 24),
            const SizedBox(height: 8),
            Text(
              message,
              style: const TextStyle(
                color: kRedColor,
                fontSize: 14,
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
  const _EmptyState({required this.query, super.key});

  final String query;

  @override
  Widget build(BuildContext context) {
    return Container(
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
                      size: 48,
                      color: kBoardLightGrey.withOpacity(0.6),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 16),
            const Text(
              'No games found',
              style: TextStyle(
                color: kWhiteColor,
                fontSize: 16,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Try different keywords for "$query"',
              style: TextStyle(
                color: kBoardLightGrey.withOpacity(0.8),
                fontSize: 13,
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

class _LoadingState extends StatelessWidget {
  const _LoadingState({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 200,
      child: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(kDarkBlue),
                strokeWidth: 2.5,
              ),
            ),
            SizedBox(height: 20),
            Text(
              'Searching games...',
              style: TextStyle(
                color: kWhiteColor70,
                fontSize: 14,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EnhancedGameSearchResultTile extends StatefulWidget {
  final GameSearchResult result;
  final int index;
  final bool isLast;
  final VoidCallback onTap;

  const _EnhancedGameSearchResultTile({
    required this.result,
    required this.index,
    required this.isLast,
    required this.onTap,
  });

  @override
  State<_EnhancedGameSearchResultTile> createState() =>
      _EnhancedGameSearchResultTileState();
}

class _EnhancedGameSearchResultTileState
    extends State<_EnhancedGameSearchResultTile>
    with TickerProviderStateMixin {
  bool _isHovered = false;
  bool _isPressed = false;

  late AnimationController _hoverController;
  late AnimationController _pressController;
  late AnimationController _slideController;

  late Animation<double> _scaleAnimation;
  late Animation<double> _opacityAnimation;
  late Animation<Offset> _slideAnimation;
  late Animation<Color?> _colorAnimation;

  late final String _playerNames;
  late final String _roundInfo;

  @override
  void initState() {
    super.initState();
    _initializeData();
    _initializeAnimations();
    _startSlideAnimation();
  }

  void _initializeData() {
    final game = widget.result.game;
    _playerNames =
        game.players?.map((p) => p.name).join(' vs ') ?? 'Unknown players';
    _roundInfo =
        'Round ${game.roundId ?? 'N/A'}${game.boardNr != null ? ' • Board ${game.boardNr}' : ''}';
  }

  void _initializeAnimations() {
    _hoverController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );

    _pressController = AnimationController(
      duration: const Duration(milliseconds: 100),
      vsync: this,
    );

    _slideController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );

    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.015).animate(
      CurvedAnimation(parent: _hoverController, curve: Curves.easeInOutCubic),
    );

    _opacityAnimation = Tween<double>(begin: 0.0, end: 0.08).animate(
      CurvedAnimation(parent: _hoverController, curve: Curves.easeInOut),
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

  void _startSlideAnimation() {
    Future.delayed(Duration(milliseconds: widget.index * 50), () {
      if (mounted) {
        _slideController.forward();
      }
    });
  }

  void _handleHoverStart() {
    setState(() => _isHovered = true);
    _hoverController.forward();
  }

  void _handleHoverEnd() {
    setState(() => _isHovered = false);
    _hoverController.reverse();
  }

  void _handleTapDown(TapDownDetails details) {
    setState(() => _isPressed = true);
    _pressController.forward();
  }

  void _handleTapUp(TapUpDetails details) {
    setState(() => _isPressed = false);
    _pressController.reverse();
  }

  void _handleTapCancel() {
    setState(() => _isPressed = false);
    _pressController.reverse();
  }

  @override
  void dispose() {
    _hoverController.dispose();
    _pressController.dispose();
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
          onEnter: (_) => _handleHoverStart(),
          onExit: (_) => _handleHoverEnd(),
          child: AnimatedBuilder(
            animation: Listenable.merge([_hoverController, _pressController]),
            builder: (context, child) {
              return Transform.scale(
                scale: _scaleAnimation.value * (_isPressed ? 0.98 : 1.0),
                child: GestureDetector(
                  onTap: widget.onTap,
                  onTapDown: _handleTapDown,
                  onTapUp: _handleTapUp,
                  onTapCancel: _handleTapCancel,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeInOutCubic,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
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
                                  color: kWhiteColor.withOpacity(0.05),
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
                              const SizedBox(height: 2),
                              Text(
                                _roundInfo,
                                style: TextStyle(
                                  color:
                                      _isHovered
                                          ? kBoardLightGrey.withOpacity(0.9)
                                          : kBoardLightGrey.withOpacity(0.7),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w400,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        AnimatedRotation(
                          turns: _isHovered ? 0.0 : -0.25,
                          duration: const Duration(milliseconds: 200),
                          child: Icon(
                            Icons.arrow_forward_ios,
                            color:
                                _isHovered
                                    ? kDarkBlue
                                    : kBoardLightGrey.withOpacity(0.4),
                            size: 14,
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
