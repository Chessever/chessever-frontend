import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Search bar component for library screen
/// Follows the same design pattern as EnhancedGamesSearchBar
class LibrarySearchBar extends ConsumerStatefulWidget {
  final TextEditingController controller;
  final Function(String)? onChanged;
  final String hintText;
  final bool autofocus;
  final VoidCallback? onClose;

  const LibrarySearchBar({
    super.key,
    required this.controller,
    this.onChanged,
    this.hintText = 'Search',
    this.autofocus = false,
    this.onClose,
  });

  @override
  ConsumerState<LibrarySearchBar> createState() => _LibrarySearchBarState();
}

class _LibrarySearchBarState extends ConsumerState<LibrarySearchBar>
    with TickerProviderStateMixin {
  final FocusNode _focusNode = FocusNode();
  late AnimationController _searchBarController;
  late Animation<double> _searchBarScaleAnimation;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_onFocusChange);

    _searchBarController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );

    _searchBarScaleAnimation = Tween<double>(begin: 1.0, end: 1.02).animate(
      CurvedAnimation(parent: _searchBarController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    _searchBarController.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    if (_focusNode.hasFocus) {
      _searchBarController.forward();
    } else {
      _searchBarController.reverse();
    }
  }

  void _handleTextChange(String value) {
    widget.onChanged?.call(value);
  }

  void _hideOverlay() {
    _focusNode.unfocus();
    _searchBarController.reverse();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
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
    final isLight = context.isLightTheme;
    // Light rests on a 1px hairline; the heavier ring is reserved for focus.
    // Dark keeps 2.w throughout (its resting edge is transparent anyway).
    final focusRingWidth = 2.w;
    final borderWidth = isLight && !focusNode.hasFocus ? 1.0 : focusRingWidth;
    // Container insets its child by the border width, so pad back the
    // difference: the field keeps one height and the text never jumps on focus.
    final borderSlack = focusRingWidth - borderWidth;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      margin: EdgeInsets.symmetric(horizontal: margin ?? 20.sp),
      padding: EdgeInsets.symmetric(
        horizontal: 12.sp + borderSlack,
        vertical: 8.sp + borderSlack,
      ),
      decoration: BoxDecoration(
        // Dark keeps the historic grey[900] field; light sits on paper with a
        // hairline edge so the field reads without a filled dark slab.
        color: isLight ? context.colors.surface : Colors.grey[900],
        borderRadius: BorderRadius.circular(8.br),
        border: Border.all(
          color:
              focusNode.hasFocus
                  // Full accentText: at 0.6 alpha the ring fell under 3:1
                  // against the light surface.
                  ? (isLight
                      ? context.colors.accentText
                      : kDarkBlue.withValues(alpha: 0.5))
                  : (isLight ? context.colors.divider : Colors.transparent),
          width: borderWidth,
        ),
        boxShadow:
            focusNode.hasFocus && !isLight
                ? [
                  BoxShadow(
                    color: kDarkBlue.withValues(alpha: 0.15),
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
              color:
                  focusNode.hasFocus
                      ? (isLight ? context.colors.accentText : Colors.blue)
                      : (isLight
                          ? context.colors.textSecondary
                          : Colors.white70),
              size: 20.ic,
            ),
          ),
          SizedBox(width: 12.w),
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              autofocus: autoFocus,
              style: TextStyle(color: context.colors.textPrimaryMuted, fontSize: 16.f),
              onChanged: onChanged,
              decoration: InputDecoration(
                hintText: hintText,
                hintStyle: TextStyle(color: context.colors.textPrimaryMuted),
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
                  color:
                      isLight
                          ? context.colors.textPrimary.withValues(alpha: 0.06)
                          : Colors.white.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.close, color: context.colors.textPrimaryMuted, size: 16.ic),
              ),
            ),
        ],
      ),
    );
  }
}
