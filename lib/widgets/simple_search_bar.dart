import 'dart:async';

import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/home_top_bar.dart';
import 'package:flutter/material.dart';
import 'package:chessever2/utils/svg_asset.dart';
import 'package:chessever2/widgets/svg_widget.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/widgets/search/search_motion.dart';
import 'package:chessever2/widgets/search_mode/search_mode.dart';
import 'package:motor/motor.dart';

class SimpleSearchBar extends StatefulWidget {
  const SimpleSearchBar({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.onCloseTap,
    required this.onOpenFilter,
    this.hintText = '',
    this.autofocus = false,
    this.onChanged,
    this.filterBadgeCount = 0,
    this.textFieldKey,
    this.filterButtonKey,
    this.compactFilter = false,
    this.rotatingHints,
    this.rotationInterval = const Duration(seconds: 2),
    this.actions,
    this.showClear = true,
    this.onSubmitted,
    this.textInputAction,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onCloseTap;
  final VoidCallback? onOpenFilter;
  final String hintText;
  final bool autofocus;
  final ValueChanged<String>? onChanged;
  final int filterBadgeCount;
  final Key? textFieldKey;
  final Key? filterButtonKey;

  /// Detail search bars keep the filter icon within their existing row height.
  final bool compactFilter;

  /// Optional list of words cycled after the static [hintText]. When provided
  /// the hint reads as "`hintText` word" and the trailing word animates in
  /// with a slide+fade swap every [rotationInterval]. Rotation pauses while
  /// the field has text.
  final List<String>? rotatingHints;
  final Duration rotationInterval;

  /// Bare glyph controls drawn inside the field, just before the filter glyph
  /// (the home Events bar's Live first, passed through
  /// `EnhancedRoundedSearchBar.fieldActions`).
  ///
  /// Each one is drawn in the filter glyph's box, so the field never changes
  /// height, and takes a 44pt tap in a home top bar. They give way to the
  /// text while the field has focus, the way the bar's avatar does.
  final List<Widget>? actions;

  /// The clear button inside the field. Off where the host clears the
  /// field itself (the Search tab's Cancel, beside the field).
  final bool showClear;

  /// The keyboard's action key, and what it does with the text.
  final ValueChanged<String>? onSubmitted;
  final TextInputAction? textInputAction;

  @override
  State<SimpleSearchBar> createState() => _SimpleSearchBarState();
}

class _SimpleSearchBarState extends State<SimpleSearchBar> {
  Timer? _rotationTimer;
  Timer? _fadeOutTimer;
  int _hintIndex = 0;
  // Rotation runs exactly one full cycle through [rotatingHints] and then
  // stops, leaving the plain static hintText — this keeps the affordance
  // subtle on first view without drawing the eye forever.
  bool _cycleDone = false;
  // Set between the last word and _cycleDone: SpringHintWord receives an
  // empty string so the final word spring-fades out instead of snapping.
  bool _cycleFadingOut = false;
  // Must comfortably cover SpringHintWord's 420ms spring so the word has
  // fully settled before the plain hintText takes over.
  static const Duration _cycleFadeOutDuration = Duration(milliseconds: 460);

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTextChanged);
    _restartRotation();
  }

  @override
  void didUpdateWidget(covariant SimpleSearchBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onTextChanged);
      widget.controller.addListener(_onTextChanged);
    }
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
    widget.controller.removeListener(_onTextChanged);
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
    final hints = widget.rotatingHints;
    return hints != null && hints.length > 1;
  }

  void _restartRotation() {
    _rotationTimer?.cancel();
    if (!_canRotate ||
        widget.controller.text.isNotEmpty ||
        _cycleDone ||
        _cycleFadingOut) {
      return;
    }
    _rotationTimer = Timer.periodic(widget.rotationInterval, (_) {
      if (!mounted) return;
      final next = _hintIndex + 1;
      if (next >= widget.rotatingHints!.length) {
        _rotationTimer?.cancel();
        // Kick off the spring fade of the final word, then flip to the
        // static hintText once the spring has settled — prevents the
        // abrupt "snap" the user reported at cycle end.
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

  void _onTextChanged() {
    final isEmpty = widget.controller.text.isEmpty;
    final isRunning = _rotationTimer?.isActive ?? false;
    if (isEmpty && !isRunning) {
      _restartRotation();
    } else if (!isEmpty && isRunning) {
      _rotationTimer?.cancel();
    }
    // Note: no setState here. The clear-icon slot watches the controller
    // + focus node directly via ListenableBuilder so it can toggle without
    // rebuilding the whole search bar (and blowing away keyboard focus on
    // each keystroke).
  }

  Widget? _buildRotatingHint() {
    if (_cycleDone) return null;
    final hints = widget.rotatingHints;
    if (hints == null || hints.isEmpty) return null;
    // Empty string during fade-out lets SpringHintWord spring the last word
    // away instead of popping it off in a single frame.
    final word = _cycleFadingOut ? '' : hints[_hintIndex % hints.length];
    final prefix = widget.hintText.isEmpty ? '' : '${widget.hintText} ';
    // Scales down only when the hint would overflow (accessibility text
    // sizes on narrow phones); at every size where it fits it is untouched.
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: AlignmentDirectional.centerStart,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (prefix.isNotEmpty)
            Text(prefix, style: AppTypography.textMdRegular),
          SpringHintWord(word: word, style: AppTypography.textMdRegular),
        ],
      ),
    );
  }

  /// The filter glyph's box: its 20pt glyph and this padding, all of it the
  /// tap. [_buildActions] draws each action in the same box.
  EdgeInsets get _filterPadding => widget.compactFilter
      ? EdgeInsets.symmetric(horizontal: 8.sp)
      : EdgeInsets.all(8.sp);

  /// [actions] in the filter glyph's box each, squeezed out while the field
  /// has focus. Listening to the focus node here keeps the squeeze off this
  /// widget's build, so it never rebuilds the [TextField].
  Widget _buildActions(List<Widget> actions) {
    final box = _filterPadding;
    final slot = Size(box.horizontal + 20.w, box.vertical + 20.h);
    return ListenableBuilder(
      listenable: widget.focusNode,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final action in actions) ...[
            SizedBox(width: 8.w),
            // A 44pt reach in the home top bar without growing the row.
            HomeTopBarTapTarget(
              child: SizedBox.fromSize(size: slot, child: action),
            ),
          ],
        ],
      ),
      builder: (context, child) => SqueezeSlot(
        open: !widget.focusNode.hasFocus,
        motion: SearchMotion.morph,
        child: child!,
      ),
    );
  }

  /// Inside a search header the leading magnifier is handed to the search
  /// morph ([SearchFieldHandoff]): measured, and left to the glass's own
  /// magnifier while that one flies in or out of its place.
  Widget _magnifier(BuildContext context, Widget icon) =>
      SearchFieldHandoff.maybeOf(context)?.magnifier(icon) ?? icon;

  @override
  Widget build(BuildContext context) {
    final rotatingHint = _buildRotatingHint();
    final actions = widget.actions ?? const <Widget>[];
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 8.sp, vertical: 4.sp),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Tint only. The magnifier used to spin a quarter turn on focus,
          // which is decorative motion competing with the field morph — and a
          // rotating glyph is the one thing in this row the eye cannot help
          // tracking. The colour lift says "focused" without the pirouette.
          _magnifier(
            context,
            _FocusTint(
              focusNode: widget.focusNode,
              builder: (context, color) => SvgWidget(
                SvgAsset.searchIcon,
                height: 20.h,
                width: 20.w,
                colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
              ),
            ),
          ),
          SizedBox(width: 8.w),
          Expanded(
            child: TextField(
              key: widget.textFieldKey,
              controller: widget.controller,
              focusNode: widget.focusNode,
              autofocus: widget.autofocus,
              onChanged: widget.onChanged,
              onSubmitted: widget.onSubmitted,
              textInputAction: widget.textInputAction,
              style: AppTypography.textMdRegular,
              decoration: InputDecoration(
                hintText: rotatingHint == null ? widget.hintText : null,
                hint: rotatingHint,
                hintStyle: AppTypography.textMdRegular,
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
          // Clear/reset suffix icon — visible while the field has focus OR
          // contains text. Scoped to a ListenableBuilder so toggling it
          // doesn't rebuild the TextField and cause IME / focus churn.
          if (widget.showClear)
            ListenableBuilder(
              listenable: Listenable.merge([
                widget.controller,
                widget.focusNode,
              ]),
              builder: (context, _) {
                final visible =
                    widget.focusNode.hasFocus ||
                    widget.controller.text.isNotEmpty;
                // Grows out of the field edge on the same spring as the morph
                // instead of appearing in a single frame. Width and scale come
                // off one value so the button fills its slot exactly and is
                // never clipped mid-travel.
                return SqueezeSlot(
                  open: visible,
                  motion: SearchMotion.accent,
                  // A 44pt reach in the home top bar without growing the row.
                  child: HomeTopBarTapTarget(
                    child: GestureDetector(
                      onTap: widget.onCloseTap,
                      child: Container(
                        padding: EdgeInsets.all(4.sp),
                        decoration: BoxDecoration(
                          color: context.colors.surfaceRecessed,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.close,
                          size: 16.ic,
                          color: context.colors.textPrimary,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),

          if (actions.isNotEmpty) _buildActions(actions),

          if (widget.onOpenFilter != null) ...[
            SizedBox(width: 8.w),
            // A 44pt reach in the home top bar without growing the row.
            HomeTopBarTapTarget(
              child: Semantics(
                container: true,
                button: true,
                label: widget.filterBadgeCount > 0
                    ? 'Filters, ${widget.filterBadgeCount} active'
                    : 'Filters',
                onTap: widget.onOpenFilter,
                excludeSemantics: true,
                child: GestureDetector(
                  key: widget.filterButtonKey,
                  // The bare glyph sits in its old tile's box, and the whole
                  // box still takes the tap: without a fill nothing else in it
                  // would answer the pointer.
                  behavior: HitTestBehavior.opaque,
                  onTap: widget.onOpenFilter,
                  child: Padding(
                    padding: _filterPadding,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        if (widget.filterBadgeCount > 0)
                          SvgWidget(
                            SvgAsset.listFilterIcon,
                            height: 20.h,
                            width: 20.w,
                            colorFilter: ColorFilter.mode(
                              context.colors.textPrimary,
                              BlendMode.srcIn,
                            ),
                          )
                        else
                          _FocusTint(
                            focusNode: widget.focusNode,
                            builder: (context, color) => SvgWidget(
                              SvgAsset.listFilterIcon,
                              height: 20.h,
                              width: 20.w,
                              colorFilter: ColorFilter.mode(
                                color,
                                BlendMode.srcIn,
                              ),
                            ),
                          ),
                        // The app's one filter count (the search
                        // button's and the search header's), ringed by the
                        // field it sits in: the one search field's fill
                        // (HomeSearchFieldSurface) at rest.
                        if (widget.filterBadgeCount > 0)
                          Positioned(
                            right: -7,
                            top: -7,
                            child: SearchCountBadge(
                              count: widget.filterBadgeCount,
                              diameter: 16,
                              ringColor: HomeSearchFieldSurface.fillOf(
                                context,
                                0,
                              ),
                            ),
                          ),
                      ],
                    ),
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

/// Lifts an icon from its resting tint to the brand tint while the field holds
/// focus, on [SearchMotion.accent].
///
/// Listening to the focus node here rather than reading `hasFocus` during the
/// parent's build is what lets [SimpleSearchBar] stay built across a focus
/// change — rebuilding the row would rebuild the [TextField] and churn the IME.
class _FocusTint extends StatelessWidget {
  const _FocusTint({required this.focusNode, required this.builder});

  final FocusNode focusNode;
  final Widget Function(BuildContext context, Color color) builder;

  @override
  Widget build(BuildContext context) {
    final resting = context.colors.iconSecondary;
    final active = context.colors.brand;
    return ListenableBuilder(
      listenable: focusNode,
      builder: (context, _) => ParkedMotionBuilder(
        value: focusNode.hasFocus ? 1.0 : 0.0,
        motion: SearchMotion.accent,
        builder: (context, t, __) =>
            builder(context, Color.lerp(resting, active, t.clamp(0.0, 1.0))!),
      ),
    );
  }
}

/// Cross-fades a single hint word with a tight iOS-style spring. Reused by
/// the home-page search bar and the library/TWIC search bar so the
/// `Search {rotating word}` affordance feels identical everywhere.
class SpringHintWord extends StatefulWidget {
  const SpringHintWord({super.key, required this.word, required this.style});

  final String word;
  final TextStyle style;

  @override
  State<SpringHintWord> createState() => _SpringHintWordState();
}

class _SpringHintWordState extends State<SpringHintWord>
    with SingleTickerProviderStateMixin {
  // iOS "smooth" spring — critically damped, no overshoot. Ideal for text so
  // the glyphs settle crisply instead of wobbling. The short duration keeps
  // the 2s rotation cadence feeling tight.
  static const _motion = CupertinoMotion.smooth(
    duration: Duration(milliseconds: 420),
  );

  late final SingleMotionController _controller;
  late String _current;
  String? _previous;

  @override
  void initState() {
    super.initState();
    _current = widget.word;
    _controller = SingleMotionController(
      motion: _motion,
      vsync: this,
      initialValue: 1,
    );
    _controller.addStatusListener(_onStatus);
  }

  @override
  void didUpdateWidget(covariant SpringHintWord oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.word != widget.word) {
      _previous = _current;
      _current = widget.word;
      _controller.value = 0;
      _controller.animateTo(1);
    }
  }

  void _onStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed && _previous != null) {
      setState(() => _previous = null);
    }
  }

  @override
  void dispose() {
    _controller
      ..removeStatusListener(_onStatus)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final progress = _controller.value;
          final inOpacity = progress.clamp(0.0, 1.0);
          final outOpacity = (1 - progress).clamp(0.0, 1.0);
          final travel = (widget.style.fontSize ?? 14.sp) * 0.9;
          final inDy = (1 - progress) * travel;
          final outDy = -progress * travel;
          final current = Transform.translate(
            offset: Offset(0, inDy),
            child: Opacity(
              opacity: inOpacity,
              child: Text(
                _current,
                style: widget.style,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.clip,
              ),
            ),
          );
          if (_previous == null) return current;
          return Stack(
            clipBehavior: Clip.hardEdge,
            alignment: Alignment.centerLeft,
            children: [
              Transform.translate(
                offset: Offset(0, outDy),
                child: Opacity(
                  opacity: outOpacity,
                  child: Text(
                    _previous!,
                    style: widget.style,
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.clip,
                  ),
                ),
              ),
              current,
            ],
          );
        },
      ),
    );
  }
}
