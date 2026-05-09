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
                  ? kDarkBlue.withValues(alpha: 0.5)
                  : Colors.transparent,
          width: 2.w,
        ),
        boxShadow:
            focusNode.hasFocus
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
                  color: Colors.white.withValues(alpha: 0.1),
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
