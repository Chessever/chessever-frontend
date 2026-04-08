import 'package:chessever2/repository/library/models/library_folder.dart';
import 'package:chessever2/repository/library/models/saved_analysis.dart';
import 'package:chessever2/screens/gamebase/models/models.dart';
import 'package:chessever2/screens/library/widgets/animated_search_hint.dart';
import 'package:chessever2/screens/library/widgets/library_search_overlay.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/svg_asset.dart';
import 'package:chessever2/widgets/svg_widget.dart';

import 'package:easy_debounce/easy_debounce.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:motor/motor.dart';

class LibrarySearchBar extends ConsumerStatefulWidget {
  final TextEditingController controller;
  final Function(String) onChanged;
  final Function(LibraryFolder)? onFolderTap;
  final Function(SavedAnalysis)? onAnalysisTap;
  final Function(GamebasePlayer)? onPlayerTap;
  final Function(Map<String, dynamic>)? onGameTap;
  final VoidCallback? onProfileTap;
  final VoidCallback? onFilterTap;
  final bool enableOverlay;
  final bool showFilterIcon;
  final String hintText;
  final FocusNode? focusNode;
  final List<String>? hintPhrases;
  final Key? textFieldKey;
  final Key? filterButtonKey;
  final int filterBadgeCount;

  const LibrarySearchBar({
    super.key,
    required this.controller,
    required this.onChanged,
    this.onFolderTap,
    this.onAnalysisTap,
    this.onPlayerTap,
    this.onGameTap,
    this.onProfileTap,
    this.onFilterTap,
    this.enableOverlay = true,
    this.showFilterIcon = true,
    this.hintText = 'Search',
    this.focusNode,
    this.hintPhrases,
    this.textFieldKey,
    this.filterButtonKey,
    this.filterBadgeCount = 0,
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
            // CSS: bg #1A1A1C, radius 12px, height 40px, no border
            SingleMotionBuilder(
              motion: CupertinoMotion.snappy(),
              value: _effectiveFocusNode.hasFocus ? 1.0 : 0.0,
              builder: (context, value, child) {
                final clamped = value.clamp(0.0, 1.0);
                return Transform.scale(
                  scale: 0.98 + (clamped * 0.02),
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A1A1C),
                      borderRadius: BorderRadius.circular(12.br),
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
                    widget.onFolderTap?.call(f);
                  },
                  onAnalysisTap: (a) {
                    _hideOverlay();
                    widget.onAnalysisTap?.call(a);
                  },
                  onPlayerTap: (p) {
                    _hideOverlay();
                    widget.onPlayerTap?.call(p);
                  },
                  onGameTap: (g) {
                    _hideOverlay();
                    widget.onGameTap?.call(g);
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

    // CSS: height 40px, padding 4px 12px
    return SizedBox(
      height: 40.h,
      child: Row(
        children: [
          SizedBox(width: 12.w),
          // CSS: search icon 16x16, rgba(255,255,255,0.7)
          Icon(
            Icons.search,
            size: 16.sp,
            color: const Color(0xFFFFFFFF).withValues(alpha: 0.7),
          ),
          SizedBox(width: 4.w),
          Expanded(
            child: Stack(
              alignment: Alignment.centerLeft,
              children: [
                // Animated hint text (shown when empty and not focused)
                if (isEmpty && !_effectiveFocusNode.hasFocus)
                  if (widget.hintPhrases != null &&
                      widget.hintPhrases!.length > 1)
                    AnimatedSearchHint(
                      textColor: const Color(0xFFFFFFFF).withValues(alpha: 0.7),
                      textStyle: AppTypography.textXsRegular,
                      phrases: widget.hintPhrases!,
                    )
                  else
                    Text(
                      widget.hintText,
                      style: AppTypography.textXsRegular.copyWith(
                        color: const Color(0xFFFFFFFF).withValues(alpha: 0.7),
                      ),
                    ),
                // CSS: 12px, Inter, rgba(255,255,255,0.7)
                TextField(
                  key: widget.textFieldKey,
                  controller: widget.controller,
                  focusNode: _effectiveFocusNode,
                  onTapOutside: (_) => _effectiveFocusNode.unfocus(),
                  style: AppTypography.textXsRegular.copyWith(
                    color: const Color(0xFFFAFAFA),
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText:
                        _effectiveFocusNode.hasFocus ? widget.hintText : null,
                    hintStyle: AppTypography.textXsRegular.copyWith(
                      color: const Color(0xFFFFFFFF).withValues(alpha: 0.7),
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
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
                child: Icon(
                  Icons.close,
                  size: 16.sp,
                  color: const Color(0xFFFFFFFF).withValues(alpha: 0.7),
                ),
              ),
            ),
          if (widget.showFilterIcon) ...[
            if (widget.controller.text.isNotEmpty) SizedBox(width: 4.w),
            // CSS: list-filter icon 24x24 in 32x32 container, radius 4px
            GestureDetector(
              key: widget.filterButtonKey,
              onTap: widget.onFilterTap,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 32.h,
                    height: 32.h,
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A1A1C),
                      borderRadius: BorderRadius.circular(4.br),
                    ),
                    child: Center(
                      child: SvgWidget(
                        SvgAsset.listFilterIcon,
                        width: 24.sp,
                        height: 24.sp,
                        colorFilter: ColorFilter.mode(
                          widget.filterBadgeCount > 0
                              ? kWhiteColor
                              : _effectiveFocusNode.hasFocus
                              ? kPrimaryColor
                              : Colors.grey[400]!,
                          BlendMode.srcIn,
                        ),
                      ),
                    ),
                  ),
                  if (widget.filterBadgeCount > 0)
                    Positioned(
                      right: -4.w,
                      top: -4.h,
                      child: Container(
                        padding: EdgeInsets.all(4.w),
                        decoration: const BoxDecoration(
                          color: Color(0xFFEF4444),
                          shape: BoxShape.circle,
                        ),
                        constraints: BoxConstraints(
                          minWidth: 16.w,
                          minHeight: 16.h,
                        ),
                        child: Text(
                          '${widget.filterBadgeCount}',
                          style: AppTypography.textXsBold.copyWith(
                            color: kWhiteColor,
                            fontSize: 10.sp,
                            height: 1,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
          SizedBox(width: widget.showFilterIcon ? 4.w : 12.w),
        ],
      ),
    );
  }
}
