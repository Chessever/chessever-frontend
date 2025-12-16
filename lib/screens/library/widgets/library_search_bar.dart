import 'package:chessever2/repository/library/models/library_folder.dart';
import 'package:chessever2/repository/library/models/saved_analysis.dart';
import 'package:chessever2/screens/gamebase/models/models.dart';
import 'package:chessever2/screens/library/widgets/library_search_overlay.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';

import 'package:easy_debounce/easy_debounce.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:motor/motor.dart';

class LibrarySearchBar extends ConsumerStatefulWidget {
  final TextEditingController controller;
  final Function(String) onChanged;
  final Function(LibraryFolder) onFolderTap;
  final Function(SavedAnalysis) onAnalysisTap;
  final Function(GamebasePlayer) onPlayerTap;
  final Function(Map<String, dynamic>) onGameTap;
  final VoidCallback? onFilterTap;
  final VoidCallback? onProfileTap;
  final bool enableOverlay;
  final String hintText;
  final bool isFilterActive;

  const LibrarySearchBar({
    super.key,
    required this.controller,
    required this.onChanged,
    required this.onFolderTap,
    required this.onAnalysisTap,
    required this.onPlayerTap,
    required this.onGameTap,
    this.onFilterTap,
    this.onProfileTap,
    this.enableOverlay = true,
    this.hintText = 'Search',
    this.isFilterActive = false,
  });

  @override
  ConsumerState<LibrarySearchBar> createState() => _LibrarySearchBarState();
}

class _LibrarySearchBarState extends ConsumerState<LibrarySearchBar> {
  bool _showOverlay = false;
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_onFocusChange);
    widget.controller.addListener(_onTextChange);
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    widget.controller.removeListener(_onTextChange);
    EasyDebounce.cancel('lib_search_debounce');
    super.dispose();
  }

  void _onFocusChange() {
    setState(() {
      _showOverlay =
          widget.enableOverlay &&
          _focusNode.hasFocus &&
          widget.controller.text.isNotEmpty;
    });
  }

  void _onTextChange() {
    final hasText = widget.controller.text.isNotEmpty;
    final shouldShowOverlay =
        widget.enableOverlay && _focusNode.hasFocus && hasText;

    if (shouldShowOverlay != _showOverlay) {
      setState(() => _showOverlay = shouldShowOverlay);
    }

    // Debounce handled by parent or provider usually, but we call onChanged
    EasyDebounce.debounce(
      'lib_search_debounce',
      const Duration(milliseconds: 100),
      () => widget.onChanged(widget.controller.text),
    );
  }

  void _hideOverlay() {
    setState(() => _showOverlay = false);
    _focusNode.unfocus();
  }

  void _clearSearch() {
    widget.controller.clear();
    widget.onChanged('');
    _hideOverlay();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        if (_showOverlay && widget.enableOverlay)
          Positioned.fill(
            child: GestureDetector(
              onTap: _hideOverlay,
              behavior: HitTestBehavior.opaque,
              child: Container(color: Colors.transparent),
            ),
          ),
        Column(
          children: [
            SingleMotionBuilder(
              motion: CupertinoMotion.snappy(),
              value: _focusNode.hasFocus ? 1.0 : 0.0,
              builder: (context, value, child) {
                return Transform.scale(
                  scale: 0.98 + (value * 0.02),
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF09090B), // Zinc 950
                      borderRadius: BorderRadius.circular(12.br),
                      border: Border.all(
                        color:
                            _focusNode.hasFocus
                                ? const Color(0xFF52525B) // Zinc 600
                                : const Color(0xFF27272A), // Zinc 800
                      ),
                      boxShadow:
                          _focusNode.hasFocus
                              ? [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.25),
                                  blurRadius: 12,
                                  offset: const Offset(0, 4),
                                ),
                              ]
                              : [],
                    ),
                    child: child,
                  ),
                );
              },
              child: _buildInputRow(),
            ),
            if (widget.enableOverlay)
              SingleMotionBuilder(
                motion: CupertinoMotion.bouncy(),
                value: _showOverlay ? 1.0 : 0.0,
                builder: (context, value, child) {
                  if (value < 0.01) return const SizedBox.shrink();
                  return ClipRect(
                    child: Align(
                      alignment: Alignment.topCenter,
                      heightFactor: value,
                      child: Container(
                        margin: EdgeInsets.only(top: 8.h),
                        child: Transform.translate(
                          offset: Offset(0, (1 - value) * -20),
                          child: Opacity(
                            opacity: value.clamp(0.0, 1.0),
                            child: child,
                          ),
                        ),
                      ),
                    ),
                  );
                },
                child: LibrarySearchOverlay(
                  query: widget.controller.text,
                  onFolderTap: (f) {
                    _hideOverlay();
                    widget.onFolderTap(f);
                  },
                  onAnalysisTap: (a) {
                    _hideOverlay();
                    widget.onAnalysisTap(a);
                  },
                  onPlayerTap: (p) {
                    _hideOverlay();
                    widget.onPlayerTap(p);
                  },
                  onGameTap: (g) {
                    _hideOverlay();
                    widget.onGameTap(g);
                  },
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildInputRow() {
    return Row(
      children: [
        SizedBox(width: 12.w),
        Icon(
          Icons.search,
          size: 20.sp,
          color: const Color(0xFFA1A1AA), // Zinc 400
        ),
        SizedBox(width: 8.w),
        Expanded(
          child: TextField(
            controller: widget.controller,
            focusNode: _focusNode,
            style: AppTypography.textSmRegular.copyWith(
              color: const Color(0xFFFAFAFA), // Zinc 50
            ),
            decoration: InputDecoration(
              isDense: true,
              hintText: widget.hintText,
              hintStyle: AppTypography.textSmRegular.copyWith(
                color: const Color(0xFFA1A1AA), // Zinc 400
              ),
              border: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(vertical: 14.h),
            ),
          ),
        ),
        if (widget.controller.text.isNotEmpty)
          GestureDetector(
            onTap: _clearSearch,
            child: Icon(
              Icons.close,
              size: 20.sp,
              color: const Color(0xFFA1A1AA),
            ),
          ),
        SizedBox(width: 8.w),
        // Filter Button
        GestureDetector(
          onTap: widget.onFilterTap,
          child: Container(
            padding: EdgeInsets.all(8.sp),
            decoration: BoxDecoration(
              color: const Color(0xFF18181B), // Zinc 900
              borderRadius: BorderRadius.circular(8.br),
              border: Border.all(
                color:
                    widget.isFilterActive
                        ? const Color(0xFF52525B) // Zinc 600
                        : const Color(0xFF27272A),
              ),
            ),
            child: Icon(
              Icons.tune_rounded,
              size: 16.sp,
              color: const Color(0xFFFAFAFA),
            ),
          ),
        ),
        SizedBox(width: 8.w),
      ],
    );
  }
}
