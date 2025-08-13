import 'package:chessever2/repository/local_storage/sesions_manager/session_manager.dart';
import 'package:chessever2/screens/tournaments/model/tour_event_card_model.dart';
import 'package:chessever2/utils/svg_asset.dart';
import 'package:chessever2/widgets/search/search_overlay_widget.dart';
import 'package:chessever2/widgets/svg_widget.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class EnhancedRoundedSearchBar extends ConsumerStatefulWidget {
  final TextEditingController controller;
  final Function(String)? onChanged;
  final Function(TourEventCardModel)? onTournamentSelected;
  final String hintText;
  final bool autofocus;
  final VoidCallback? onFilterTap;
  final VoidCallback? onProfileTap;
  final bool showProfile;
  final bool showFilter;

  const EnhancedRoundedSearchBar({
    super.key,
    required this.controller,
    this.onChanged,
    this.onTournamentSelected,
    this.hintText = 'Search tournaments or players',
    this.autofocus = false,
    this.onFilterTap,
    this.onProfileTap,
    this.showProfile = true,
    this.showFilter = true,
  });

  @override
  ConsumerState<EnhancedRoundedSearchBar> createState() =>
      _EnhancedRoundedSearchBarState();
}

class _EnhancedRoundedSearchBarState
    extends ConsumerState<EnhancedRoundedSearchBar>
    with TickerProviderStateMixin {
  bool _showOverlay = false;
  final FocusNode _focusNode = FocusNode();
  
  late AnimationController _overlayController;
  late AnimationController _searchBarController;
  late Animation<double> _overlayAnimation;
  late Animation<double> _searchBarScaleAnimation;
  late Animation<Color?> _borderColorAnimation;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_onFocusChange);
    widget.controller.addListener(_onTextChange);
    
    // Initialize animation controllers
    _overlayController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    
    _searchBarController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    
    // Setup animations
    _overlayAnimation = CurvedAnimation(
      parent: _overlayController,
      curve: Curves.easeInOut,
    );
    
    _searchBarScaleAnimation = Tween<double>(
      begin: 1.0,
      end: 1.02,
    ).animate(CurvedAnimation(
      parent: _searchBarController,
      curve: Curves.easeInOut,
    ));
    
    _borderColorAnimation = ColorTween(
      begin: Colors.transparent,
      end: Colors.blue.withOpacity(0.3),
    ).animate(CurvedAnimation(
      parent: _searchBarController,
      curve: Curves.easeInOut,
    ));
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    widget.controller.removeListener(_onTextChange);
    _overlayController.dispose();
    _searchBarController.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    setState(() {
      _showOverlay = _focusNode.hasFocus && widget.controller.text.isNotEmpty;
    });
    
    if (_focusNode.hasFocus) {
      _searchBarController.forward();
      if (widget.controller.text.isNotEmpty) {
        _overlayController.forward();
      }
    } else {
      _searchBarController.reverse();
      _overlayController.reverse();
    }
  }

  void _onTextChange() {
    final hasText = widget.controller.text.isNotEmpty;
    if (hasText != _showOverlay && _focusNode.hasFocus) {
      setState(() {
        _showOverlay = hasText;
      });
      
      if (hasText) {
        _overlayController.forward();
      } else {
        _overlayController.reverse();
      }
    }
    widget.onChanged?.call(widget.controller.text);
  }

  void _hideOverlay() {
    setState(() {
      _showOverlay = false;
    });
    _focusNode.unfocus();
    _overlayController.reverse();
    _searchBarController.reverse();
  }

  void _onTournamentSelected(TourEventCardModel tournament) {
    _hideOverlay();
    widget.onTournamentSelected?.call(tournament);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        // Invisible barrier to detect taps outside
        if (_showOverlay)
          Positioned.fill(
            child: GestureDetector(
              onTap: _hideOverlay,
              child: Container(
                color: Colors.transparent,
              ),
            ),
          ),

        Column(
          children: [
            // Animated search bar
            AnimatedBuilder(
              animation: _searchBarController,
              builder: (context, child) {
                return Transform.scale(
                  scale: _searchBarScaleAnimation.value,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: _focusNode.hasFocus
                          ? [
                              BoxShadow(
                                color: Colors.blue.withOpacity(0.15),
                                blurRadius: 12,
                                offset: const Offset(0, 4),
                              ),
                            ]
                          : [],
                    ),
                    child: _buildSearchBar(),
                  ),
                );
              },
            ),

            // Animated search overlay
            AnimatedBuilder(
              animation: _overlayAnimation,
              builder: (context, child) {
                return ClipRect(
                  child: Align(
                    alignment: Alignment.topCenter,
                    heightFactor: _overlayAnimation.value,
                    child: Container(
                      margin: const EdgeInsets.only(top: 12),
                      child: Transform.translate(
                        offset: Offset(0, (1 - _overlayAnimation.value) * -20),
                        child: Opacity(
                          opacity: _overlayAnimation.value,
                          child: SearchOverlay(
                            query: widget.controller.text,
                            onTournamentTap: _onTournamentSelected,
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
    final sessionManager = ref.read(sessionManagerProvider);

    return AnimatedBuilder(
      animation: _borderColorAnimation,
      builder: (context, child) {
        return Row(
          children: [
            if (widget.showProfile) ...[
              _buildProfileAvatar(sessionManager),
              const SizedBox(width: 16),
            ],

            // Search bar container
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.grey[900],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _borderColorAnimation.value ?? Colors.transparent,
                    width: 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: _buildSearchInput(),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildProfileAvatar(sessionManager) {
    return FutureBuilder<String?>(
      future: sessionManager.getUserInitials(),
      builder: (context, snapshot) {
        final initials = snapshot.data ?? '';

        return GestureDetector(
          onTap: widget.onProfileTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [
                  Colors.blue.shade400,
                  Colors.purple.shade400,
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.blue.withOpacity(0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Center(
              child: Text(
                initials.toUpperCase(),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSearchInput() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          AnimatedRotation(
            turns: _focusNode.hasFocus ? 0.25 : 0,
            duration: const Duration(milliseconds: 200),
            child: SvgWidget(
              SvgAsset.searchIcon,
              height: 20,
              width: 20,
              colorFilter: ColorFilter.mode(
                _focusNode.hasFocus ? Colors.blue : Colors.grey[400]!,
                BlendMode.srcIn,
              ),
            ),
          ),
          const SizedBox(width: 12),

          Expanded(
            child: TextField(
              controller: widget.controller,
              focusNode: _focusNode,
              autofocus: widget.autofocus,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
              ),
              decoration: InputDecoration(
                hintText: widget.hintText,
                hintStyle: TextStyle(
                  color: Colors.grey[400],
                  fontSize: 16,
                ),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),

          // Clear button with animation
          AnimatedScale(
            scale: widget.controller.text.isNotEmpty ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 200),
            child: AnimatedOpacity(
              opacity: widget.controller.text.isNotEmpty ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 200),
              child: GestureDetector(
                onTap: () {
                  widget.controller.clear();
                  _hideOverlay();
                },
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.grey[700],
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.close,
                    size: 16,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),

          if (widget.showFilter && widget.onFilterTap != null) ...[
            const SizedBox(width: 8),
            GestureDetector(
              onTap: widget.onFilterTap,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _focusNode.hasFocus 
                      ? Colors.blue.withOpacity(0.1) 
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SvgWidget(
                  SvgAsset.listFilterIcon,
                  height: 20,
                  width: 20,
                  colorFilter: ColorFilter.mode(
                    _focusNode.hasFocus ? Colors.blue : Colors.grey[400]!,
                    BlendMode.srcIn,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}