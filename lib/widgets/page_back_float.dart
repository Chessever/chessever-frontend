import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/glass_surface.dart';
import 'package:chessever2/widgets/ink_fab.dart';
import 'package:chessever2/widgets/scroll_chrome.dart';
import 'package:chessever2/widgets/search_mode/search_mode.dart';
import 'package:flutter/material.dart';

/// A pushed page's way back while its header is away.
///
/// The header's own [PageBackButton] folds away with the header as the list
/// scrolls (the scroll chrome). With it gone, the only ways back would be
/// the 20pt iOS edge or a system back. So as the header leaves, this glass
/// disc (the floating buttons' material, [InkFab] small) takes the
/// chevron's place, centred where the header's chevron was, and it goes as
/// the header comes home: the page always has a back in reach, and with the
/// header shown there is nothing extra on it.
///
/// It follows the chrome's own value ([ScrollChromeController], its motor
/// spring), so it runs no motion of its own: it comes in over the second
/// half of the fold, as the header's chevron is mostly gone, and answers
/// taps once it is mostly there. It is announced only while the header's
/// chevron is not. A screen reader and reduced motion keep the header
/// shown, so for them it never appears.
///
/// A child of the page's [Stack], laid over the page's content box (the
/// box the header's row starts in).
class PageBackFloat extends StatefulWidget {
  const PageBackFloat({
    super.key,
    required this.controller,
    this.top,
    this.onPressed,
  });

  /// The page's scroll chrome: the controller its header folds with.
  final ScrollChromeController controller;

  /// Where the header's back target starts, from the top of the [Stack].
  /// Null for the back row every pushed page shares: right under the top
  /// inset ([SearchHeaderMetrics], `viewPadding.top + 4.h`).
  final double? top;

  /// Null pops the route.
  final VoidCallback? onPressed;

  /// How much of the floating back is there at a chrome [value] (1 header
  /// shown, 0 gone): none while the header's chevron is half in view or
  /// more, all of it with the header gone, straight between.
  static double presence(double value) => ((0.5 - value) / 0.5).clamp(0.0, 1.0);

  @override
  State<PageBackFloat> createState() => _PageBackFloatState();
}

class _PageBackFloatState extends State<PageBackFloat> {
  late _Presence _presence = _Presence(widget.controller);

  @override
  void didUpdateWidget(PageBackFloat oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      _presence = _Presence(widget.controller);
    }
  }

  void _back() {
    final pressed = widget.onPressed;
    if (pressed != null) {
      pressed();
    } else {
      Navigator.maybePop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final target = SearchHeaderMetrics.backTarget;
    final button = InkFab(
      key: const ValueKey('page_back_float'),
      label: 'Back',
      size: InkFabSize.small,
      onTap: _back,
      glyph: (color, size) =>
          Icon(Icons.arrow_back_ios_new_outlined, size: size, color: color),
    );
    return PositionedDirectional(
      top: widget.top ?? MediaQuery.viewPaddingOf(context).top + 4.h,
      start: SearchHeaderMetrics.leadingInset,
      width: target,
      height: target,
      child: AnimatedBuilder(
        animation: _presence,
        child: GlassFade(
          opacity: _presence,
          child: Center(child: button),
        ),
        builder: (context, child) {
          final shown = _presence.value;
          // Nothing drawn, laid out or announced while the header's own
          // chevron carries the way back.
          if (shown <= 0) return const SizedBox.shrink();
          return IgnorePointer(ignoring: shown < 0.5, child: child);
        },
      ),
    );
  }
}

/// [PageBackFloat.presence] of a chrome's value, as an animation the glass
/// fades by ([GlassFade]).
class _Presence extends Animation<double> {
  _Presence(this.chrome);

  final ScrollChromeController chrome;

  @override
  double get value => PageBackFloat.presence(chrome.value);

  @override
  AnimationStatus get status => switch (value) {
    <= 0 => AnimationStatus.dismissed,
    >= 1 => AnimationStatus.completed,
    _ => AnimationStatus.forward,
  };

  @override
  void addListener(VoidCallback listener) => chrome.addListener(listener);

  @override
  void removeListener(VoidCallback listener) => chrome.removeListener(listener);

  // The value is read on every change: no status listener is ever told
  // anything a value listener is not.
  @override
  void addStatusListener(AnimationStatusListener listener) {}

  @override
  void removeStatusListener(AnimationStatusListener listener) {}
}
