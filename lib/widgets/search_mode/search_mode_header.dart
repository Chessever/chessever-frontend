part of 'search_mode.dart';

/// The one geometry every page header and its search header share.
///
/// A page's normal header starts its back row where the search header's row
/// is (right under the page's own top inset, `viewPadding.top + 4.h`), with
/// its back button a [PageBackButton] at [leadingInset]. The search row
/// starts its field on the [gutter] and ends on Cancel.
///
/// Measured from the pages: the event screen, Favorites, collections
/// (`EventViewShell`), the player profile and Prep all draw their back as a
/// 24.ic `arrow_back_ios_new_outlined` in a 48pt target that starts 16.w in
/// (24.w on tablets), its glyph centred at 40 on the 393pt base. That is the
/// one kept.
abstract final class SearchHeaderMetrics {
  /// The back target's start edge.
  static double get leadingInset =>
      ResponsiveHelper.adaptive(phone: 16.w, tablet: 24.w);

  /// The back button's square target.
  static const double backTarget = 48;

  /// The chevron glyph.
  static double get backGlyph => 24.ic;

  /// The back row: the chevron's target, and the least the search row is.
  static const double rowHeight = 48;

  /// The content gutter the field ends on (the tab strip's, the lists').
  static double get gutter =>
      ResponsiveHelper.adaptive(phone: 20.sp, tablet: 32.sp);

  /// How far a 44pt glyph button reaches past its 20pt glyph: trailing
  /// controls give it back from the gutter so their glyph lands on it.
  static const double trailingReach = 12;

  /// Under the search row, before the list starts (the normal header's gap
  /// under its tabs).
  static double get bottomGap => 4.h;

  /// The field's corners: the one search field's
  /// ([HomeSearchFieldSurface.radius]).
  static double get fieldRadius => HomeSearchFieldSurface.radius;

  /// Where the chevron's glyph is centred, from the header's start edge.
  static double get backGlyphCenter => leadingInset + backTarget / 2;
}

/// The page's way back: a 24.ic `arrow_back_ios_new_outlined` in a 48pt
/// target, with the navigation haptic, placed at
/// [SearchHeaderMetrics.leadingInset] in a page's normal header.
///
/// The search header has none: as X sets its search row, the field starts
/// on the gutter and Cancel, at the row's end, puts the search away. The
/// page's chevron goes with the rest of its header as the search opens and
/// comes back with it.
class PageBackButton extends StatelessWidget {
  const PageBackButton({
    super.key,
    this.onPressed,
    this.tooltip = 'Back',
    this.color,
  });

  /// Null pops the route.
  final VoidCallback? onPressed;
  final String tooltip;

  /// Defaults to the text colour.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: SearchHeaderMetrics.backTarget,
      child: IconButton(
        tooltip: tooltip,
        padding: EdgeInsets.zero,
        onPressed: () {
          HapticFeedbackService.navigation();
          final pressed = onPressed;
          if (pressed != null) {
            pressed();
          } else {
            Navigator.maybePop(context);
          }
        },
        icon: Icon(
          Icons.arrow_back_ios_new_outlined,
          size: SearchHeaderMetrics.backGlyph,
          color: color ?? context.colors.textPrimary,
        ),
      ),
    );
  }
}

/// The header of every page's full-page search, in X's order: the field
/// from the gutter (magnifier, words, and the circled x that empties it
/// while it holds any), the page's trailing controls (a view toggle,
/// Filters last), then Cancel, which puts the search away.
///
/// Inside a [SearchModeHost] it is the field: the host's query and focus,
/// its frame and magnifier the glass lands on, its Cancel closing the
/// search. Cancel's room opens on the morph's own timeline, so the field
/// narrows to make it and a trailing control the page's header draws at the
/// same spot (a [SearchModeShared]) starts exactly there, whole from the
/// tap, and glides in by Cancel's width as the word arrives. The other
/// controls, and the word itself, arrive over the last part of the morph,
/// and the field's text as the glass lands under it. Closing runs it all
/// back.
class SearchModeHeader extends StatefulWidget {
  const SearchModeHeader({
    super.key,
    this.hintText = 'Search',
    this.rotatingHints,
    this.textFieldKey,
    this.trailing = const <Widget>[],
    this.closeKey = const ValueKey('search_mode_close'),
  });

  final String hintText;

  /// Words cycled after [hintText] once ("Search event", "Search opening").
  final List<String>? rotatingHints;
  final Key? textFieldKey;

  /// The page's own toolbar glyphs between the field and Cancel, as it
  /// already draws them beside its list: Filters as a
  /// [SearchModeFilterButton] (the one count style, [SearchCountBadge]),
  /// count-less toggles as the toolbar's own buttons
  /// (`ClassicalToggleButton`, `BoardViewToggleButton`). 44pt targets with
  /// 20pt glyphs.
  ///
  /// A control the page's header draws at the same spot is wrapped in a
  /// [SearchModeShared] in both: it starts there, whole, and glides in as
  /// Cancel's room opens. The others arrive with Cancel.
  final List<Widget> trailing;

  /// On Cancel's tap target.
  final Key closeKey;

  @override
  State<SearchModeHeader> createState() => _SearchModeHeaderState();
}

/// [child] fading in on [opacity], and out of reach until it is half there:
/// no control answers a tap while the reader cannot see it.
Widget _fade(Animation<double>? opacity, Widget child) =>
    opacity == null ? child : _Arriving(opacity: opacity, child: child);

class _Arriving extends SingleChildRenderObjectWidget {
  const _Arriving({required this.opacity, super.child});

  final Animation<double> opacity;

  /// Below this much of itself it takes no touches.
  static const double reachable = 0.5;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderArriving(opacity: opacity);

  @override
  void updateRenderObject(BuildContext context, _RenderArriving renderObject) {
    renderObject.opacity = opacity;
  }
}

class _RenderArriving extends RenderAnimatedOpacity {
  _RenderArriving({required super.opacity});

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) =>
      opacity.value >= _Arriving.reachable &&
      super.hitTest(result, position: position);
}

class _SearchModeHeaderState extends State<SearchModeHeader> {
  final GlobalKey _frameKey = GlobalKey(debugLabel: 'Search field frame');
  final GlobalKey _iconKey = GlobalKey(debugLabel: 'Search field magnifier');
  _SearchModeHostState? _host;

  /// For the morphing header used with no host above it.
  TextEditingController? _ownText;
  FocusNode? _ownFocus;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final host = SearchModeScope.maybeOf(context)?._host;
    if (host != _host) {
      _host?._detachField(_frameKey);
      host?._attachField(_frameKey, _iconKey);
      _host = host;
    }
  }

  @override
  void activate() {
    super.activate();
    _host?._attachField(_frameKey, _iconKey);
  }

  /// Out of the tree from this frame's build on (the slot drops the search
  /// header the frame a close lands): the glass must not measure the field
  /// while it paints that frame, when its element still answers to the key.
  @override
  void deactivate() {
    _host?._detachField(_frameKey);
    super.deactivate();
  }

  @override
  void dispose() {
    _host?._detachField(_frameKey);
    _ownText?.dispose();
    _ownFocus?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scope = SearchModeScope.maybeOf(context);
    Widget arriving(Widget child) => _fade(scope?.searchContentOpacity, child);

    final controller = scope?.controller;
    final text = controller?.text ?? (_ownText ??= TextEditingController());
    final focus = controller?.focusNode ?? (_ownFocus ??= FocusNode());
    // The app's one search field ([HomeSearchFieldSurface]): the Search
    // tab's surface, focus lift and edge, height and type.
    final frame = EventSearchBarFrame(
      compact: true,
      focusNode: focus,
      child: _fade(
        scope?.fieldContentOpacity,
        SimpleSearchBar(
          controller: text,
          focusNode: focus,
          textFieldKey: widget.textFieldKey,
          hintText: widget.hintText,
          rotatingHints: widget.rotatingHints,
          onCloseTap: scope != null ? scope._host._clearField : text.clear,
        ),
      ),
    );
    final Widget field = scope == null
        ? frame
        : SearchFieldHandoff._(
            frameKey: _frameKey,
            iconKey: _iconKey,
            flight: scope._host._flight,
            child: frame,
          );
    final VoidCallback close =
        scope?.close ?? () => Navigator.maybePop(context);

    final trailing = widget.trailing;
    final gutter = SearchHeaderMetrics.gutter;
    // The row ends a glyph button's reach short of the gutter: with Cancel's
    // room shut (the instant of the tap), the last trailing glyph lands on
    // the gutter, where the page's header draws it; Cancel gives the reach
    // back after its word, so open, the word ends on the gutter.
    // Never negative: a folded Duo pane is narrower than the gutter.
    final reach = math.min(SearchHeaderMetrics.trailingReach, gutter);
    final cancel = arriving(
      SearchCancelWord(
        tapKey: widget.closeKey,
        focusNode: focus,
        onTap: close,
        hint: 'Closes the search',
        endInset: reach,
        // After a 44pt glyph button, whose box already holds the glyph
        // 12pt in: the word sits as far from that glyph as the glyph from
        // the field (4 + 12).
        startGap: trailing.isEmpty
            ? null
            : SearchCancelWord.afterGlyph - SearchHeaderMetrics.trailingReach,
      ),
    );
    return Padding(
      padding: EdgeInsetsDirectional.fromSTEB(
        gutter,
        0,
        gutter - reach,
        SearchHeaderMetrics.bottomGap,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minHeight: SearchHeaderMetrics.rowHeight,
        ),
        child: Row(
          children: [
            Expanded(child: field),
            if (trailing.isNotEmpty) ...[
              const SizedBox(width: 4),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final control in trailing)
                    control is SearchModeShared ? control : arriving(control),
                ],
              ),
            ],
            _CancelRoom(timeline: scope?.timeline, child: cancel),
          ],
        ),
      ),
    );
  }
}

/// Cancel's room at the end of the search row, opening on the morph's
/// [timeline]: shut at the tap, so everything before it starts where the
/// page's header has it, and whole once the search is open. With no host it
/// is whole.
class _CancelRoom extends StatelessWidget {
  const _CancelRoom({required this.timeline, required this.child});

  final Animation<double>? timeline;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final timeline = this.timeline;
    if (timeline == null) return child;
    return AnimatedBuilder(
      animation: timeline,
      child: child,
      builder: (context, child) {
        final f = timeline.value.clamp(0.0, 1.0);
        return ClipRect(
          clipBehavior: f < 1 ? Clip.hardEdge : Clip.none,
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            widthFactor: f,
            child: child,
          ),
        );
      },
    );
  }
}
