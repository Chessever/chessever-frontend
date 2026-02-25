import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
// import 'package:chessever2/widgets/search/gameSearch/game_search_overlay.dart'; // Unused: overlay is disabled
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
    this.hintText = 'Search',
    this.autofocus = false,
    this.onClose,
  });

  @override
  ConsumerState<EnhancedGamesSearchBar> createState() =>
      _EnhancedGamesSearchBarState();
}

class _EnhancedGamesSearchBarState extends ConsumerState<EnhancedGamesSearchBar>
    with TickerProviderStateMixin {
  // bool _showOverlay = false; // Unused: overlay is disabled
  final FocusNode _focusNode = FocusNode();

  // Track current query state
  String _currentQuery = '';

  // late AnimationController _overlayController; // Unused: overlay is disabled
  late AnimationController _searchBarController;
  // late Animation<double> _overlayAnimation; // Unused: overlay is disabled
  late Animation<double> _searchBarScaleAnimation;

  @override
  void initState() {
    super.initState();

    // Initialize current query from controller
    _currentQuery = widget.controller.text;

    _focusNode.addListener(_onFocusChange);

    // Overlay controller is disabled
    // _overlayController = AnimationController(
    //   duration: const Duration(milliseconds: 300),
    //   vsync: this,
    // );

    _searchBarController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );

    // Overlay animation is disabled
    // _overlayAnimation = CurvedAnimation(
    //   parent: _overlayController,
    //   curve: Curves.easeInOut,
    // );

    _searchBarScaleAnimation = Tween<double>(begin: 1.0, end: 1.02).animate(
      CurvedAnimation(parent: _searchBarController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    // _overlayController.dispose(); // Overlay is disabled
    _searchBarController.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    if (_focusNode.hasFocus) {
      _searchBarController.forward();
      // Overlay visibility updates are disabled
      // if (_currentQuery.isNotEmpty) {
      //   _updateOverlayVisibility(true);
      // }
    } else {
      _searchBarController.reverse();
      // _updateOverlayVisibility(false); // Overlay is disabled
    }
  }

  // COMMENTED OUT: Overlay visibility management is disabled
  // void _updateOverlayVisibility(bool show) {
  //   if (_showOverlay != show) {
  //     setState(() {
  //       _showOverlay = show;
  //     });
  //
  //     if (show) {
  //       _overlayController.forward();
  //     } else {
  //       _overlayController.reverse();
  //     }
  //   }
  // }

  // Single method to handle all text changes
  void _handleTextChange(String value) {
    debugPrint('🎯 _handleTextChange called with: "$value"');

    // Update internal state (kept for potential future use)
    setState(() {
      _currentQuery = value;
    });

    // Overlay visibility updates are disabled
    // final shouldShowOverlay = _focusNode.hasFocus && value.isNotEmpty;
    // _updateOverlayVisibility(shouldShowOverlay);

    // Notify parent component
    debugPrint('🎯 Notifying parent with: "$value"');
    widget.onChanged?.call(value);
  }

  void _hideOverlay() {
    // Simplified: just unfocus since overlay is disabled
    _focusNode.unfocus();
    _searchBarController.reverse();
  }

  // COMMENTED OUT: Game selection from overlay is disabled
  // void _onGameSelected(Games games) {
  //   _hideOverlay();
  //   widget.onGameSelected?.call(games);
  // }

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        // COMMENTED OUT: Background tap detector for dropdown overlay
        // The dropdown is disabled because we already filter games live in the Games List View
        // if (_showOverlay)
        //   Positioned.fill(
        //     child: GestureDetector(
        //       onTap: _hideOverlay,
        //       child: Container(color: Colors.transparent),
        //     ),
        //   ),
        Column(
          children: [
            // Search bar
            AnimatedBuilder(
              animation: _searchBarController,
              builder: (context, child) {
                return Transform.scale(
                  scale: _searchBarScaleAnimation.value,
                  child: SearchBarWidget(
                    hintText: widget.hintText,
                    autoFocus: widget.autofocus,
                    controller: widget.controller,
                    focusNode: _focusNode,
                    onClose: widget.onClose ?? _hideOverlay,
                    onChanged: _handleTextChange,
                  ),
                );
              },
            ),

            // COMMENTED OUT: Search overlay dropdown
            // The dropdown showing search results is redundant because we already
            // filter games live in the Games List View below. This keeps the UI cleaner.
            // AnimatedBuilder(
            //   animation: _overlayAnimation,
            //   builder: (context, child) {
            //     return ClipRect(
            //       child: Align(
            //         alignment: Alignment.topCenter,
            //         heightFactor: _overlayAnimation.value,
            //         child: Container(
            //           margin: EdgeInsets.only(top: 8.sp),
            //           child: Transform.translate(
            //             offset: Offset(0, (1 - _overlayAnimation.value) * -20),
            //             child: Opacity(
            //               opacity: _overlayAnimation.value,
            //               child: GamesSearchOverlay(
            //                 query:
            //                     _currentQuery, // Use internal state instead of controller
            //                 onGameTap: _onGameSelected,
            //               ),
            //             ),
            //           ),
            //         ),
            //       ),
            //     );
            //   },
            // ),
          ],
        ),
      ],
    );
  }
}

class SearchBarWidget extends StatelessWidget {
  const SearchBarWidget({
    required this.hintText,
    required this.autoFocus,
    required this.controller,
    required this.focusNode,
    required this.onClose,
    this.margin,
    this.onChanged,
    super.key,
  });

  final String hintText;
  final bool autoFocus;
  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String>? onChanged;
  final VoidCallback onClose;
  final double? margin;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      margin: EdgeInsets.symmetric(horizontal: margin ?? 20.sp),
      padding: EdgeInsets.symmetric(horizontal: 12.sp, vertical: 8.sp),
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: BorderRadius.circular(8.br),
        border: Border.all(
          color:
              focusNode.hasFocus
                  ? kDarkBlue.withOpacity(0.5)
                  : Colors.transparent,
          width: 2.w,
        ),
        boxShadow:
            focusNode.hasFocus
                ? [
                  BoxShadow(
                    color: kDarkBlue.withOpacity(0.15),
                    blurRadius: 12.br,
                    offset: const Offset(0, 4),
                  ),
                ]
                : [],
      ),
      child: Row(
        children: [
          AnimatedRotation(
            turns: focusNode.hasFocus ? 0.25 : 0,
            duration: const Duration(milliseconds: 200),
            child: Icon(
              Icons.search,
              color: focusNode.hasFocus ? Colors.blue : Colors.white70,
              size: 20.ic,
            ),
          ),
          SizedBox(width: 12.w),

          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              autofocus: autoFocus,
              style: TextStyle(color: kWhiteColor70, fontSize: 16.f),
              onChanged: onChanged,
              decoration: InputDecoration(
                hintText: hintText,
                hintStyle: const TextStyle(color: kWhiteColor70),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
          if (controller.text.isNotEmpty || focusNode.hasFocus)
            GestureDetector(
              onTap: onClose,
              child: Container(
                padding: EdgeInsets.all(4.sp),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.close, color: kWhiteColor70, size: 16.ic),
              ),
            ),
        ],
      ),
    );
  }
}
