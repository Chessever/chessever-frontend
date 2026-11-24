import 'dart:async';
import 'dart:math' as math;

import 'package:chessever2/repository/library/models/library_folder.dart';
import 'package:chessever2/repository/library/models/saved_analysis.dart';
import 'package:chessever2/screens/gamebase/models/models.dart';
import 'package:chessever2/screens/library/widgets/animated_search_hint.dart';
import 'package:chessever2/screens/library/widgets/library_search_overlay.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/text_scale.dart';
import 'package:chessever2/widgets/dismiss_keyboard.dart';
import 'package:chessever2/widgets/home_top_bar.dart' show HomeTopBarMetrics;
import 'package:chessever2/widgets/search/search_cancel_button.dart';
import 'package:chessever2/widgets/search/search_clear_button.dart';
import 'package:chessever2/widgets/search/search_motion.dart' show SearchMotion;
import 'package:chessever2/widgets/search_mode/search_mode.dart'
    show SearchHeaderMetrics;
import 'package:chessever2/widgets/search_mode/search_mode_filter_button.dart';
import 'package:chessever2/widgets/simple_search_bar.dart';

import 'package:easy_debounce/easy_debounce.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:motor/motor.dart';

/// The ChessEver Database's search row (TWIC contents), in X's order: the
/// field (magnifier, words, and the circled x that empties it while it holds
/// any), then Filters outside it, then Cancel while the field has the cursor
/// or holds text. The x only empties the field and keeps the cursor; Cancel
/// clears the search and puts the keyboard away.
///
/// The page pads the row's end by [endPadding], as the search header ends
/// its own: the Filters glyph at rest, and Cancel's word once it opens, both
/// end on the gutter.
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

  /// Words cycled after [hintText] (e.g. "Search player" → "Search event").
  /// When set, only the trailing word animates with a spring swap — matching
  /// the home-page search. Takes precedence over [hintPhrases].
  final List<String>? rotatingHints;
  final Duration rotationInterval;
  final Key? textFieldKey;

  /// On the Filters button's tap target.
  final Key? filterButtonKey;
  final int filterBadgeCount;

  /// On Cancel's tap target.
  final Key cancelKey;

  /// How far a 44pt glyph button reaches past its glyph
  /// ([SearchHeaderMetrics.trailingReach]), never more than the gutter (a
  /// folded Duo pane is narrower than it).
  static double get reach =>
      math.min(SearchHeaderMetrics.trailingReach, SearchHeaderMetrics.gutter);

  /// The page's padding after the bar: a glyph button's [reach] short of the
  /// gutter. With Cancel shut the Filters glyph ends on the gutter; Cancel
  /// gives the reach back after its word, so open, the word ends there.
  static double get endPadding => SearchHeaderMetrics.gutter - reach;

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
    this.rotatingHints,
    this.rotationInterval = const Duration(seconds: 2),
    this.textFieldKey,
    this.filterButtonKey,
    this.filterBadgeCount = 0,
    this.cancelKey = const ValueKey('search_field_cancel'),
  });

  @override
  ConsumerState<LibrarySearchBar> createState() => _LibrarySearchBarState();
}

class _LibrarySearchBarState extends ConsumerState<LibrarySearchBar> {
  bool _showOverlay = false;
  final FocusNode _internalFocusNode = FocusNode();
  late final FocusNode _effectiveFocusNode;

  Timer? _rotationTimer;
  Timer? _fadeOutTimer;
  int _hintIndex = 0;
  // One full pass through [rotatingHints], then we freeze on plain hintText.
  bool _cycleDone = false;
  // Brief window after the final tick where SpringHintWord is given an
  // empty word so the last entry spring-fades out before we hand back to
  // the static hintText — fixes the abrupt "snap" at cycle end.
  bool _cycleFadingOut = false;
  static const Duration _cycleFadeOutDuration = Duration(milliseconds: 460);

  @override
  void initState() {
    super.initState();
    _effectiveFocusNode = widget.focusNode ?? _internalFocusNode;
    _effectiveFocusNode.addListener(_onFocusChange);
    widget.controller.addListener(_onTextChange);
    _restartRotation();
  }

  @override
  void didUpdateWidget(covariant LibrarySearchBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_listsEqual(oldWidget.rotatingHints, widget.rotatingHints) ||
        oldWidget.rotationInterval != widget.rotationInterval) {
      _hintIndex = 0;
      _cycleDone = false;
      _cycleFadingOut = false;
      _fadeOutTimer?.cancel();
      _restartRotation();
    }
  }

  @override
  void dispose() {
    _rotationTimer?.cancel();
    _fadeOutTimer?.cancel();
    _effectiveFocusNode.removeListener(_onFocusChange);
    if (widget.focusNode == null) _internalFocusNode.dispose();
    widget.controller.removeListener(_onTextChange);
    EasyDebounce.cancel('lib_search_debounce');
    super.dispose();
  }

  bool _listsEqual(List<String>? a, List<String>? b) {
    if (identical(a, b)) return true;
    if (a == null || b == null) return false;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  bool get _canRotate {
    final h = widget.rotatingHints;
    return h != null && h.length > 1 && !_cycleDone;
  }

  bool get _showRotatingOverlay => _canRotate || _cycleFadingOut;

  void _restartRotation() {
    _rotationTimer?.cancel();
    if (!_canRotate ||
        widget.controller.text.isNotEmpty ||
        _effectiveFocusNode.hasFocus ||
        _cycleFadingOut) {
      return;
    }
    _rotationTimer = Timer.periodic(widget.rotationInterval, (_) {
      if (!mounted) return;
      final next = _hintIndex + 1;
      if (next >= widget.rotatingHints!.length) {
        _rotationTimer?.cancel();
        setState(() => _cycleFadingOut = true);
        _fadeOutTimer?.cancel();
        _fadeOutTimer = Timer(_cycleFadeOutDuration, () {
          if (!mounted) return;
          setState(() => _cycleDone = true);
        });
      } else {
        setState(() => _hintIndex = next);
      }
    });
  }

  void _onFocusChange() {
    setState(() {
      _showOverlay =
          widget.enableOverlay &&
          _effectiveFocusNode.hasFocus &&
          widget.controller.text.isNotEmpty;
    });
    // Rotation pauses while the field is focused so the hint is stable
    // under the caret, and resumes once focus leaves an empty field.
    if (_effectiveFocusNode.hasFocus) {
      _rotationTimer?.cancel();
    } else {
      _restartRotation();
    }
  }

  void _onTextChange() {
    final hasText = widget.controller.text.isNotEmpty;
    final shouldShowOverlay =
        widget.enableOverlay && _effectiveFocusNode.hasFocus && hasText;

    if (shouldShowOverlay != _showOverlay) {
      setState(() => _showOverlay = shouldShowOverlay);
    }

    final isRunning = _rotationTimer?.isActive ?? false;
    if (hasText && isRunning) {
      _rotationTimer?.cancel();
    } else if (!hasText && !isRunning && !_effectiveFocusNode.hasFocus) {
      _restartRotation();
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

  /// The circled x: the words go and the cursor stays (as X's does), and
  /// the page is told at once rather than after the bar's typing debounce.
  void _clearField() {
    if (widget.controller.text.isNotEmpty) widget.controller.clear();
    EasyDebounce.cancel('lib_search_debounce');
    widget.onChanged('');
    if (!_effectiveFocusNode.hasFocus && _effectiveFocusNode.context != null) {
      _effectiveFocusNode.requestFocus();
    }
  }

  /// Cancel: the words go, the keyboard with them, and the field rests.
  void _cancel() {
    if (widget.controller.text.isNotEmpty) widget.controller.clear();
    EasyDebounce.cancel('lib_search_debounce');
    widget.onChanged('');
    if (_showOverlay) setState(() => _showOverlay = false);
    dismissSoftwareKeyboard(focusNode: _effectiveFocusNode);
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
            _buildSearchRow(),
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

  Widget _buildRotatingHint() {
    final hints = widget.rotatingHints!;
    // Empty word during fade-out lets SpringHintWord animate the last entry
    // away before the hint reverts to static text.
    final word = _cycleFadingOut ? '' : hints[_hintIndex % hints.length];
    final prefix = widget.hintText.isEmpty ? '' : '${widget.hintText} ';
    final style = AppTypography.textXsRegular.copyWith(
      color: context.colors.textPrimary.withValues(alpha: 0.7),
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (prefix.isNotEmpty) Text(prefix, style: style),
        Flexible(
          child: SpringHintWord(word: word, style: style),
        ),
      ],
    );
  }

  /// The row: the field, then Filters outside it (the boxed 44pt glyph, so
  /// the row's end padding plus its reach puts the glyph on the gutter),
  /// then Cancel, whose room opens on the field morph's spring while the
  /// field has the cursor or holds text. The field narrows to make room.
  ///
  /// The row is always a Cancel target tall, so the word opening never
  /// changes its height and nothing below it moves.
  Widget _buildSearchRow() {
    final reach = LibrarySearchBar.reach;
    final filter = widget.showFilterIcon;
    final rowHeight = math.max(
      SearchModeFilterButton.target,
      math.max(HomeTopBarMetrics.minTapTarget, 44.w),
    );
    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: rowHeight),
      child: Row(
        children: [
          Expanded(child: _buildField()),
          if (filter) ...[
            const SizedBox(width: 4),
            SearchModeFilterButton(
              key: widget.filterButtonKey,
              count: widget.filterBadgeCount,
              onTap: widget.onFilterTap,
            ),
          ],
          SearchCancelButton(
            controller: widget.controller,
            focusNode: _effectiveFocusNode,
            onCancel: _cancel,
            cancelKey: widget.cancelKey,
            // The word at the field's own size, as X sets it.
            textStyle: AppTypography.textXsRegular,
            // After the boxed Filters, whose box holds the glyph 12pt in.
            startGap: filter
                ? SearchCancelWord.afterGlyph - SearchHeaderMetrics.trailingReach
                : null,
            // With Filters last, the row ends their reach short of the
            // gutter and Cancel gives it back after its word. Without them
            // the field ends on the gutter at rest and so does the word.
            endInset: filter ? reach : 0,
          ),
          if (!filter) SizedBox(width: reach),
        ],
      ),
    );
  }

  /// The field's frame: the page's surface, lifting a hair on focus.
  // CSS: bg #1A1A1C, radius 12px, height 40px, no border
  Widget _buildField() {
    return SingleMotionBuilder(
      motion: CupertinoMotion.snappy(),
      value: _effectiveFocusNode.hasFocus ? 1.0 : 0.0,
      builder: (context, value, child) {
        final clamped = value.clamp(0.0, 1.0);
        return Transform.scale(
          scale: 0.98 + (clamped * 0.02),
          child: Container(
            decoration: BoxDecoration(
              color: context.colors.surface,
              borderRadius: BorderRadius.circular(12.br),
            ),
            child: child,
          ),
        );
      },
      child: _buildInputRow(),
    );
  }

  /// The hint under an empty field without the cursor. It listens to the
  /// controller and the focus node itself, so it goes the moment words
  /// arrive, however they arrive, without rebuilding the [TextField].
  Widget _buildHint() {
    return ListenableBuilder(
      listenable: Listenable.merge([widget.controller, _effectiveFocusNode]),
      builder: (context, _) {
        if (widget.controller.text.isNotEmpty || _effectiveFocusNode.hasFocus) {
          return const SizedBox.shrink();
        }
        if (_showRotatingOverlay) return _buildRotatingHint();
        if (widget.hintPhrases != null && widget.hintPhrases!.length > 1) {
          return AnimatedSearchHint(
            textColor: context.colors.textPrimary.withValues(alpha: 0.7),
            textStyle: AppTypography.textXsRegular,
            phrases: widget.hintPhrases!,
          );
        }
        return Text(
          widget.hintText,
          style: AppTypography.textXsRegular.copyWith(
            color: context.colors.textPrimary.withValues(alpha: 0.7),
          ),
        );
      },
    );
  }

  Widget _buildInputRow() {
    const searchGlyphStart = 12.0;
    final searchGlyph = 16.sp;
    // The circled x's centre sits as far in from the field's end as the
    // magnifier's sits from its start, so the two marks frame the words.
    final clearEnd = math.max(
      0.0,
      searchGlyphStart.w +
          searchGlyph / 2 -
          (SearchClearButton.endInset + SearchClearButton.glyph / 2),
    );

    // CSS: height 40px, padding 4px 12px
    return SizedBox(
      height: 40.h * context.textGrowth,
      child: Row(
        children: [
          SizedBox(width: searchGlyphStart.w),
          // CSS: search icon 16x16, rgba(255,255,255,0.7)
          Icon(
            Icons.search,
            size: searchGlyph,
            color: context.colors.textPrimary.withValues(alpha: 0.7),
          ),
          SizedBox(width: 4.w),
          Expanded(
            child: Stack(
              alignment: Alignment.centerLeft,
              children: [
                _buildHint(),
                // CSS: 12px, Inter, rgba(255,255,255,0.7)
                TextField(
                  key: widget.textFieldKey,
                  controller: widget.controller,
                  focusNode: _effectiveFocusNode,
                  onTapOutside: (_) => _effectiveFocusNode.unfocus(),
                  style: AppTypography.textXsRegular.copyWith(
                    color: context.colors.textPrimary,
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: _effectiveFocusNode.hasFocus
                        ? widget.hintText
                        : null,
                    hintStyle: AppTypography.textXsRegular.copyWith(
                      color: context.colors.textPrimary.withValues(alpha: 0.7),
                    ),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ],
            ),
          ),
          // X's clear: there only while the field holds text, it empties the
          // field and keeps the cursor. It listens to the controller itself,
          // so it comes and goes with the words rather than with the page's
          // next rebuild. It belongs to the field: pressing it is not a tap
          // outside it, so the keyboard stays up through the tap.
          SearchClearButton(
            controller: widget.controller,
            focusNode: _effectiveFocusNode,
            onTap: _clearField,
          ),
          SizedBox(width: clearEnd),
        ],
      ),
    );
  }
}
