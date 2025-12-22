import 'package:chessever2/repository/library/models/library_folder.dart';
import 'package:chessever2/repository/library/models/saved_analysis.dart';
import 'package:chessever2/screens/gamebase/models/models.dart';
import 'package:chessever2/screens/library/widgets/animated_search_hint.dart';
import 'package:chessever2/screens/library/widgets/library_search_overlay.dart';
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
  final VoidCallback? onProfileTap;
  final bool enableOverlay;
  final String hintText;
  final FocusNode? focusNode;

  const LibrarySearchBar({
    super.key,
    required this.controller,
    required this.onChanged,
    required this.onFolderTap,
    required this.onAnalysisTap,
    required this.onPlayerTap,
    required this.onGameTap,
    this.onProfileTap,
    this.enableOverlay = true,
    this.hintText = 'Search',
    this.focusNode,
  });

  @override
  ConsumerState<LibrarySearchBar> createState() => _LibrarySearchBarState();
}

class _LibrarySearchBarState extends ConsumerState<LibrarySearchBar> {
  bool _showOverlay = false;
  final FocusNode _internalFocusNode = FocusNode();
  late final FocusNode _effectiveFocusNode;

  @override
  void initState() {
    super.initState();
    _effectiveFocusNode = widget.focusNode ?? _internalFocusNode;
    _effectiveFocusNode.addListener(_onFocusChange);
    widget.controller.addListener(_onTextChange);
  }

  @override
  void dispose() {
    _effectiveFocusNode.removeListener(_onFocusChange);
    if (widget.focusNode == null) _internalFocusNode.dispose();
    widget.controller.removeListener(_onTextChange);
    EasyDebounce.cancel('lib_search_debounce');
    super.dispose();
  }

  void _onFocusChange() {
    setState(() {
      _showOverlay =
          widget.enableOverlay &&
          _effectiveFocusNode.hasFocus &&
          widget.controller.text.isNotEmpty;
    });
  }

  void _onTextChange() {
    final hasText = widget.controller.text.isNotEmpty;
    final shouldShowOverlay =
        widget.enableOverlay && _effectiveFocusNode.hasFocus && hasText;

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
    _effectiveFocusNode.unfocus();
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
              value: _effectiveFocusNode.hasFocus ? 1.0 : 0.0,
              builder: (context, value, child) {
                return Transform.scale(
                  scale: 0.98 + (value * 0.02),
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF09090B), // Zinc 950
                      borderRadius: BorderRadius.circular(12.br),
                      border: Border.all(
                        color:
                            _effectiveFocusNode.hasFocus
                                ? const Color(0xFF52525B) // Zinc 600
                                : const Color(0xFF27272A), // Zinc 800
                      ),
                      boxShadow:
                          _effectiveFocusNode.hasFocus
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
    final isEmpty = widget.controller.text.isEmpty;

    return SizedBox(
      height: 44.h,
      child: Row(
        children: [
          SizedBox(width: 12.w),
          Icon(
            Icons.search,
            size: 20.sp,
            color: const Color(0xFFA1A1AA), // Zinc 400
          ),
          SizedBox(width: 8.w),
          Expanded(
            child: Stack(
              alignment: Alignment.centerLeft,
              children: [
                // Animated hint text (shown when empty and not focused)
                if (isEmpty && !_effectiveFocusNode.hasFocus)
                  const AnimatedSearchHint(
                    textColor: Color(0xFFA1A1AA), // Zinc 400
                  ),
                // TextField (always present but transparent hint when animated)
                TextField(
                  controller: widget.controller,
                  focusNode: _effectiveFocusNode,
                  style: AppTypography.textSmRegular.copyWith(
                    color: const Color(0xFFFAFAFA), // Zinc 50
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    // Show static hint only when focused and empty
                    hintText: _effectiveFocusNode.hasFocus ? widget.hintText : null,
                    hintStyle: AppTypography.textSmRegular.copyWith(
                      color: const Color(0xFFA1A1AA), // Zinc 400
                    ),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ],
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
          SizedBox(width: 12.w),
        ],
      ),
    );
  }
}
