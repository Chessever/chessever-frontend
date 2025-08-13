import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/screens/tournaments/model/games_tour_model.dart';
import 'package:chessever2/widgets/search/gameSearch/game_search_overlay.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class EnhancedGamesSearchBar extends ConsumerStatefulWidget {
  final TextEditingController controller;
  final Function(String)? onChanged;
  final Function(Games games)? onGameSelected;
  final String hintText;
  final bool autofocus;
  final VoidCallback? onClose;

  const EnhancedGamesSearchBar({
    super.key,
    required this.controller,
    this.onChanged,
    this.onGameSelected,
    this.hintText = 'Search players or games...',
    this.autofocus = false,
    this.onClose,
  });

  @override
  ConsumerState<EnhancedGamesSearchBar> createState() =>
      _EnhancedGamesSearchBarState();
}

class _EnhancedGamesSearchBarState extends ConsumerState<EnhancedGamesSearchBar>
    with TickerProviderStateMixin {
  bool _showOverlay = false;
  final FocusNode _focusNode = FocusNode();

  // Track current query state
  String _currentQuery = '';

  late AnimationController _overlayController;
  late AnimationController _searchBarController;
  late Animation<double> _overlayAnimation;
  late Animation<double> _searchBarScaleAnimation;

  @override
  void initState() {
    super.initState();

    // Initialize current query from controller
    _currentQuery = widget.controller.text;

    _focusNode.addListener(_onFocusChange);

    _overlayController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _searchBarController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );

    _overlayAnimation = CurvedAnimation(
      parent: _overlayController,
      curve: Curves.easeInOut,
    );

    _searchBarScaleAnimation = Tween<double>(
      begin: 1.0,
      end: 1.02,
    ).animate(
      CurvedAnimation(
        parent: _searchBarController,
        curve: Curves.easeInOut,
      ),
    );
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    _overlayController.dispose();
    _searchBarController.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    if (_focusNode.hasFocus) {
      _searchBarController.forward();
      // Show overlay if there's text
      if (_currentQuery.isNotEmpty) {
        _updateOverlayVisibility(true);
      }
    } else {
      _searchBarController.reverse();
      _updateOverlayVisibility(false);
    }
  }

  void _updateOverlayVisibility(bool show) {
    if (_showOverlay != show) {
      setState(() {
        _showOverlay = show;
      });

      if (show) {
        _overlayController.forward();
      } else {
        _overlayController.reverse();
      }
    }
  }

  // Single method to handle all text changes
  void _handleTextChange(String value) {
    debugPrint('🎯 _handleTextChange called with: "$value"');

    // Update internal state
    setState(() {
      _currentQuery = value;
    });

    // Update overlay visibility based on text and focus
    final shouldShowOverlay = _focusNode.hasFocus && value.isNotEmpty;
    _updateOverlayVisibility(shouldShowOverlay);

    // Notify parent component
    debugPrint('🎯 Notifying parent with: "$value"');
    widget.onChanged?.call(value);
  }

  void _hideOverlay() {
    _updateOverlayVisibility(false);
    _focusNode.unfocus();
    _searchBarController.reverse();
  }

  void _onGameSelected(Games games) {
    _hideOverlay();
    widget.onGameSelected?.call(games);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        // Background tap detector
        if (_showOverlay)
          Positioned.fill(
            child: GestureDetector(
              onTap: _hideOverlay,
              child: Container(color: Colors.transparent),
            ),
          ),

        Column(
          children: [
            // Search bar
            AnimatedBuilder(
              animation: _searchBarController,
              builder: (context, child) {
                return Transform.scale(
                  scale: _searchBarScaleAnimation.value,
                  child: _buildSearchBar(),
                );
              },
            ),

            // Search overlay
            AnimatedBuilder(
              animation: _overlayAnimation,
              builder: (context, child) {
                return ClipRect(
                  child: Align(
                    alignment: Alignment.topCenter,
                    heightFactor: _overlayAnimation.value,
                    child: Container(
                      margin: const EdgeInsets.only(top: 8),
                      child: Transform.translate(
                        offset: Offset(0, (1 - _overlayAnimation.value) * -20),
                        child: Opacity(
                          opacity: _overlayAnimation.value,
                          child: GamesSearchOverlay(
                            query:
                                _currentQuery, // Use internal state instead of controller
                            onGameTap: _onGameSelected,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSearchBar() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color:
              _focusNode.hasFocus
                  ? Colors.blue.withOpacity(0.5)
                  : Colors.transparent,
          width: 2,
        ),
        boxShadow:
            _focusNode.hasFocus
                ? [
                  BoxShadow(
                    color: Colors.blue.withOpacity(0.15),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ]
                : [],
      ),
      child: Row(
        children: [
          AnimatedRotation(
            turns: _focusNode.hasFocus ? 0.25 : 0,
            duration: const Duration(milliseconds: 200),
            child: Icon(
              Icons.search,
              color: _focusNode.hasFocus ? Colors.blue : Colors.white70,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),

          Expanded(
            child: TextField(
              controller: widget.controller,
              focusNode: _focusNode,
              autofocus: widget.autofocus,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 16,
              ),
              onChanged: _handleTextChange, // Single handler
              decoration: InputDecoration(
                hintText: widget.hintText,
                hintStyle: const TextStyle(color: Colors.white70),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),

          GestureDetector(
            onTap: widget.onClose ?? _hideOverlay,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.close,
                color: Colors.white70,
                size: 16,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
