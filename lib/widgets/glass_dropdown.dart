/// The anchored members of the popup glass family: dropdown menus and the
/// panels that drop from a chip (an event's categories, a smart event's
/// tiers).
///
/// They are cut from the centred popups' glass ([PopupGlass]): one backdrop
/// filter clipped to the panel, a plate solved so the glass averages to the
/// menu's old tone, the lit rim, the grain and one tight contact shadow.
/// What differs is the page around them: every anchored menu dims it with
/// the one anchored dim ([AnchoredGlassDim]), lighter than a dialog's (a
/// plain tint that rides the open, never a blur of the screen), and the
/// plate is solved over the page that dim leaves, so the glass still lands
/// on the menu's own tone.
///
/// Dropdowns open on the shared anchored route ([GlassAnchoredRoute]); the
/// in-page popovers ([GlassPopoverLayer]) on the same spring
/// ([GlassAnchoredMotion]), from the same scale, over the same dim
/// ([AnchoredGlassDim]) with the chip that opened them left lit, and both
/// fold shut the same way ([GlassFold]). The popovers stay overlay entries
/// on purpose: nothing about the page's route changes while one is up, so
/// nothing on the page that reads its route rebuilds for it.
library;

import 'dart:math' as math;

import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/widgets/glass_anchored_route.dart';
import 'package:chessever2/widgets/popup_glass.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

/// The compact glass panel a menu or popover is drawn on: [PopupGlass]
/// solved over the page the anchored dim leaves ([AnchoredGlassDim]).
///
/// [tone] is the colour the menu's opaque panel was (the theme's surface
/// when null). [page] is what the page under the panel looks like once
/// dimmed; it defaults to the anchored dim's page. A menu inside another
/// popup passes that popup's surface.
///
/// What it holds fades as the panel folds shut ([GlassFoldFade]); the glass
/// itself only ever folds.
class GlassPopoverPanel extends StatelessWidget {
  const GlassPopoverPanel({
    super.key,
    required this.child,
    required this.borderRadius,
    this.width,
    this.height,
    this.constraints,
    this.padding,
    this.tone,
    this.page,
  });

  final Widget child;
  final BorderRadius borderRadius;
  final double? width;
  final double? height;
  final BoxConstraints? constraints;
  final EdgeInsetsGeometry? padding;
  final Color? tone;
  final Color? page;

  @override
  Widget build(BuildContext context) {
    return PopupGlass(
      borderRadius: borderRadius,
      width: width,
      height: height,
      constraints: constraints,
      padding: padding,
      tone: tone ?? context.colors.surface,
      page: page ?? AnchoredGlassDim.pageOf(context),
      // Over another popup's flat surface the theme's coverage holds.
      cover: page == null ? AnchoredGlassDim.cover : null,
      child: GlassFoldFade(child: child),
    );
  }
}

/// An open popover in an [OverlayEntry]: the anchored dim (a tap on it calls
/// [onDismiss]) with [hole] (the chip that opened it, in the overlay's
/// coordinates) left lit, and [child], the panel, placed at [left], [top]
/// and grown on the anchored menus' spring ([GlassAnchoredMotion]) from
/// [scaleAlignment].
///
/// The spring starts in the frame the entry is inserted, so the panel and
/// every row in it are drawn from that first frame. When [closing] turns
/// true the panel folds shut into [scaleAlignment] on the anchored close
/// spring ([GlassFold]) while the dim clears and taps already reach the
/// page; [onClosed] then takes the entry away (at once under reduced
/// motion). Removing the entry outright closes it instantly. It is an
/// overlay entry rather than a route on purpose: nothing about the page's
/// route changes while it is up, so nothing on the page that reads its
/// route rebuilds for it.
class GlassPopoverLayer extends StatefulWidget {
  const GlassPopoverLayer({
    super.key,
    required this.left,
    required this.top,
    required this.child,
    this.scaleAlignment = Alignment.topCenter,
    this.onDismiss,
    this.hole,
    this.closing,
    this.onClosed,
  });

  final double left;
  final double top;
  final Alignment scaleAlignment;
  final VoidCallback? onDismiss;

  /// The control that opened the popover, left out of the dim.
  final RRect? hole;

  /// Turns true to fold the popover away.
  final ValueListenable<bool>? closing;

  /// The fold is done: remove the entry.
  final VoidCallback? onClosed;
  final Widget child;

  @override
  State<GlassPopoverLayer> createState() => _GlassPopoverLayerState();
}

class _GlassPopoverLayerState extends State<GlassPopoverLayer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _open = AnimationController(vsync: this);
  late final GlassFold _fold = GlassFold(_open);
  bool _started = false;
  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    widget.closing?.addListener(_onClosing);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (_started) return;
    _started = true;
    if (_reduceMotion) {
      _open.value = 1;
    } else {
      _open.animateWith(GlassAnchoredMotion.simulation(from: 0));
    }
  }

  @override
  void didUpdateWidget(GlassPopoverLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.closing, widget.closing)) return;
    oldWidget.closing?.removeListener(_onClosing);
    widget.closing?.addListener(_onClosing);
    _onClosing();
  }

  @override
  void dispose() {
    widget.closing?.removeListener(_onClosing);
    _open.dispose();
    super.dispose();
  }

  void _onClosing() {
    if (!(widget.closing?.value ?? false) || _fold.closing) return;
    _fold.close();
    if (_reduceMotion || _open.value <= 0) {
      _open.value = 0;
      widget.onClosed?.call();
      return;
    }
    _open
        .animateBackWith(GlassAnchoredMotion.closeSimulation(from: _open.value))
        .orCancel
        .then((_) {
          if (mounted) widget.onClosed?.call();
        }, onError: (Object _) {});
  }

  @override
  Widget build(BuildContext context) {
    return GlassFoldIgnorePointer(
      fold: _fold,
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: widget.onDismiss,
              child: CustomPaint(
                painter: GlassScrimPainter(
                  color: AnchoredGlassDim.colorOf(context),
                  hole: widget.hole,
                  progress: _open,
                ),
              ),
            ),
          ),
          Positioned(
            left: widget.left,
            top: widget.top,
            child: GlassFoldTransition(
              fold: _fold,
              alignment: widget.scaleAlignment,
              // Taps on the panel stay on the panel. A frame of the springs
              // moves a layer; the glass and its rows are not repainted.
              child: GestureDetector(
                onTap: () {},
                behavior: HitTestBehavior.opaque,
                child: GlassFoldScope(
                  fold: _fold,
                  child: RepaintBoundary(child: widget.child),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Decides whether a menu item matches what the reader typed into a
/// [GlassDropdown]'s search field.
typedef GlassDropdownMatch<T> =
    bool Function(DropdownMenuItem<T> item, String query);

/// A [DropdownButton] whose menu is a [GlassPopoverPanel].
///
/// A drop-in: the same items, values, hint, selected-item builder, icon,
/// style and sizes as [DropdownButton], and the button draws exactly as
/// [DropdownButton]'s does (it honours [DropdownButtonHideUnderline], and
/// with [decoration] it is the [DropdownButtonFormField] field). Only the
/// menu changes: Material's fades its whole route in under an opacity and a
/// black elevation shadow, which no glass survives, and builds every item
/// up front. This one drops from the button (or rises above it when there
/// is no room below) on the shared anchored route ([GlassAnchoredRoute]):
/// the anchored menus' spring over their plain dim. It draws its items
/// lazily, opens scrolled to the selection and folds shut into the button
/// as it closes, its pick handed over at once.
///
/// The DropdownButton2 extras the country picker relies on are here too:
/// [customButton], [menuWidth], [menuOffset], a fixed [menuHeader] (a search
/// field) filtering the items through [searchController] and [searchMatch],
/// [onMenuStateChange], and [GlassDropdownState.open] for a programmatic
/// open.
class GlassDropdown<T> extends StatefulWidget {
  const GlassDropdown({
    super.key,
    required this.items,
    required this.value,
    required this.onChanged,
    this.hint,
    this.disabledHint,
    this.selectedItemBuilder,
    this.icon,
    this.iconSize = 24,
    this.iconEnabledColor,
    this.iconDisabledColor,
    this.isExpanded = false,
    this.isDense = false,
    this.itemHeight = kMinInteractiveDimension,
    this.menuMaxHeight,
    this.style,
    this.dropdownColor,
    this.borderRadius,
    this.menuBorderRadius,
    this.underline,
    this.alignment = AlignmentDirectional.centerStart,
    this.decoration,
    this.customButton,
    this.menuWidth,
    this.menuMargin = const EdgeInsetsDirectional.only(start: 16, end: 24),
    this.menuOffset = Offset.zero,
    this.menuPadding = const EdgeInsets.symmetric(vertical: 8),
    this.menuItemPadding = const EdgeInsets.symmetric(horizontal: 16),
    this.menuHeader,
    this.menuHeaderHeight = 0,
    this.searchController,
    this.searchMatch,
    this.onMenuStateChange,
    this.sizeToAllItems = true,
    this.highlightSelected = true,
  });

  final List<DropdownMenuItem<T>>? items;
  final T? value;

  /// Null (or no items) disables the button.
  final ValueChanged<T?>? onChanged;
  final Widget? hint;
  final Widget? disabledHint;
  final DropdownButtonBuilder? selectedItemBuilder;
  final Widget? icon;
  final double iconSize;
  final Color? iconEnabledColor;
  final Color? iconDisabledColor;
  final bool isExpanded;
  final bool isDense;

  /// Each menu row's height, as [DropdownButton.itemHeight]; null lets a row
  /// take its own height.
  final double? itemHeight;
  final double? menuMaxHeight;
  final TextStyle? style;

  /// The tone the opaque menu used to be; the glass averages to it.
  final Color? dropdownColor;

  /// The button's ink radius, and the menu's corner unless
  /// [menuBorderRadius] says otherwise.
  final BorderRadius? borderRadius;
  final BorderRadius? menuBorderRadius;
  final Widget? underline;
  final AlignmentGeometry alignment;

  /// Draws the button as [DropdownButtonFormField]'s field.
  final InputDecoration? decoration;

  /// Replaces the whole button (DropdownButton2's `customButton`).
  final Widget? customButton;

  /// The menu's width; the button's (plus [menuMargin]) when null.
  final double? menuWidth;

  /// How far the menu reaches past the button on each side. The default is
  /// [DropdownButton]'s, which lines the rows' text up with the button's.
  final EdgeInsetsGeometry menuMargin;
  final Offset menuOffset;
  final EdgeInsetsGeometry menuPadding;
  final EdgeInsetsGeometry menuItemPadding;

  /// A fixed block above the items (a search field), [menuHeaderHeight]
  /// tall.
  final Widget? menuHeader;
  final double menuHeaderHeight;
  final TextEditingController? searchController;
  final GlassDropdownMatch<T>? searchMatch;
  final ValueChanged<bool>? onMenuStateChange;

  /// Sizes the button to its widest item, as [DropdownButton] does, which
  /// builds every item into the button. False builds only the selected one:
  /// for items that are all one size (flags).
  final bool sizeToAllItems;

  /// Tints the selected row as [DropdownButton]'s menu does.
  final bool highlightSelected;

  @override
  State<GlassDropdown<T>> createState() => GlassDropdownState<T>();
}

class GlassDropdownState<T> extends State<GlassDropdown<T>> {
  GlassAnchoredRoute<_GlassMenuResult<T>>? _route;
  bool _isOpen = false;

  bool get _enabled =>
      widget.items != null &&
      widget.items!.isNotEmpty &&
      widget.onChanged != null;

  int? get _selectedIndex {
    final items = widget.items;
    if (items == null || widget.value == null) return null;
    final index = items.indexWhere((item) => item.value == widget.value);
    return index < 0 ? null : index;
  }

  TextStyle get _textStyle =>
      widget.style ?? Theme.of(context).textTheme.titleMedium!;

  Color get _iconColor {
    final dark = Theme.brightnessOf(context) == Brightness.dark;
    if (_enabled) {
      return widget.iconEnabledColor ??
          (dark ? Colors.white70 : Colors.grey.shade700);
    }
    return widget.iconDisabledColor ??
        (dark ? Colors.white10 : Colors.grey.shade400);
  }

  double get _denseButtonHeight {
    final fallback = Theme.of(context).textTheme.titleMedium!;
    final fontSize = _textStyle.fontSize ?? fallback.fontSize!;
    final lineHeight = _textStyle.height ?? fallback.height ?? 1.0;
    final scaled = MediaQuery.textScalerOf(
      context,
    ).scale(fontSize * lineHeight);
    return math.max(scaled, math.max(widget.iconSize, 24.0));
  }

  /// Opens the menu, as a tap on the button does.
  void open() {
    if (!_enabled || _route != null || !mounted) return;
    final navigator = Navigator.of(context);
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final buttonRect =
        box.localToGlobal(
          Offset.zero,
          ancestor: navigator.context.findRenderObject(),
        ) &
        box.size;
    final direction = Directionality.of(context);
    // Inside a dialog or a sheet the page is dimmed already, and the menu
    // sits on that popup's own surface.
    final overPopup = ModalRoute.of(context) is PopupRoute;
    final selectedIndex = _selectedIndex;
    final menu = _GlassMenuSpec<T>(
      items: widget.items!,
      selectedIndex: selectedIndex,
      buttonRect: buttonRect,
      textDirection: direction,
      style: _textStyle,
      itemHeight: widget.itemHeight,
      menuMaxHeight: widget.menuMaxHeight,
      menuWidth: widget.menuWidth,
      menuMargin: widget.menuMargin,
      menuPadding: widget.menuPadding,
      menuItemPadding: widget.menuItemPadding,
      borderRadius:
          widget.menuBorderRadius ??
          widget.borderRadius ??
          BorderRadius.circular(12),
      tone: widget.dropdownColor,
      header: widget.menuHeader,
      headerHeight: widget.menuHeader == null ? 0 : widget.menuHeaderHeight,
      searchController: widget.searchController,
      searchMatch: widget.searchMatch,
      highlightSelected: widget.highlightSelected,
      overPopup: overPopup,
    );
    final route = GlassAnchoredRoute<_GlassMenuResult<T>>(
      // The rows line up with the button's text: the menu reaches past the
      // button by [menuMargin] on each side.
      anchor: widget.menuMargin
          .resolve(direction)
          .inflateRect(buttonRect)
          .shift(widget.menuOffset),
      anchoring: GlassMenuAnchoring.drop,
      dim: overPopup
          ? const Color(0x00000000)
          : AnchoredGlassDim.colorOf(context),
      capturedThemes: InheritedTheme.capture(
        from: context,
        to: navigator.context,
      ),
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      builder: (context) => _GlassMenu<T>(spec: menu),
    );
    _route = route;
    setState(() => _isOpen = true);
    widget.onMenuStateChange?.call(true);
    navigator.push(route).then((result) {
      if (identical(_route, route)) _route = null;
      if (!mounted) return;
      setState(() => _isOpen = false);
      // DropdownButton2's order: the menu reports closed, then the pick.
      widget.onMenuStateChange?.call(false);
      if (result == null) return;
      widget.onChanged?.call(result.value);
    });
  }

  @override
  void dispose() {
    final route = _route;
    _route = null;
    if (route != null && route.isActive) {
      route.navigator?.removeRoute(route);
    }
    super.dispose();
  }

  Widget _buttonInner() {
    final List<Widget> shown = widget.selectedItemBuilder != null
        ? List<Widget>.of(widget.selectedItemBuilder!(context))
        : List<Widget>.of(widget.items ?? const []);
    int? hintIndex;
    final hint = _enabled ? widget.hint : widget.disabledHint ?? widget.hint;
    if (hint != null) {
      hintIndex = shown.length;
      shown.add(
        DefaultTextStyle(
          style: _textStyle.copyWith(color: Theme.of(context).hintColor),
          child: IgnorePointer(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                minHeight: kMinInteractiveDimension,
              ),
              child: Align(alignment: widget.alignment, child: hint),
            ),
          ),
        ),
      );
    }
    if (shown.isEmpty) return const SizedBox.shrink();
    Widget sized(Widget item) {
      if (widget.isDense) return item;
      return widget.itemHeight != null
          ? SizedBox(height: widget.itemHeight, child: item)
          : Column(mainAxisSize: MainAxisSize.min, children: [item]);
    }

    final index = _selectedIndex ?? hintIndex;
    if (!widget.sizeToAllItems) {
      if (index == null) return const SizedBox.shrink();
      return Align(alignment: widget.alignment, child: sized(shown[index]));
    }
    return IndexedStack(
      index: index,
      alignment: widget.alignment,
      children: [for (final item in shown) sized(item)],
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget result;
    final decoration = widget.decoration;
    final icon = IconTheme(
      data: IconThemeData(color: _iconColor, size: widget.iconSize),
      child: widget.icon ?? const Icon(Icons.arrow_drop_down),
    );
    final textStyle = _enabled
        ? _textStyle
        : _textStyle.copyWith(color: Theme.of(context).disabledColor);
    if (widget.customButton != null) {
      result = DefaultTextStyle(style: textStyle, child: widget.customButton!);
    } else {
      final inner = _buttonInner();
      result = DefaultTextStyle(
        style: textStyle,
        child: SizedBox(
          height: widget.isDense ? _denseButtonHeight : null,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.isExpanded) Expanded(child: inner) else inner,
              if (decoration == null) icon,
            ],
          ),
        ),
      );
    }
    if (decoration == null && !DropdownButtonHideUnderline.at(context)) {
      final bottom = (widget.isDense || widget.itemHeight == null) ? 0.0 : 8.0;
      result = Stack(
        children: [
          result,
          Positioned(
            left: 0,
            right: 0,
            bottom: bottom,
            child:
                widget.underline ??
                Container(
                  height: 1,
                  decoration: const BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: Color(0xFFBDBDBD), width: 0),
                    ),
                  ),
                ),
          ),
        ],
      );
    }

    if (decoration != null) {
      final filled =
          decoration.filled ?? InputDecorationTheme.of(context).filled;
      final outlined =
          decoration.border?.isOutline ??
          InputDecorationTheme.of(context).border?.isOutline ??
          false;
      final endMargin = (filled || outlined) ? 12.0 : 0.0;
      result = GestureDetector(
        onTap: _enabled ? open : null,
        behavior: HitTestBehavior.opaque,
        child: InputDecorator(
          decoration: decoration.copyWith(
            suffixIconConstraints: BoxConstraints(
              minWidth: widget.iconSize + endMargin,
              minHeight: widget.iconSize,
            ),
            suffixIcon: Padding(
              padding: EdgeInsetsDirectional.only(end: endMargin),
              child: icon,
            ),
          ),
          isEmpty: _selectedIndex == null && widget.hint == null,
          isFocused: _isOpen,
          child: result,
        ),
      );
    } else {
      result = InkWell(
        onTap: _enabled ? open : null,
        borderRadius: widget.borderRadius,
        enableFeedback: false,
        child: result,
      );
    }
    return Semantics(button: true, expanded: _isOpen, child: result);
  }
}

class _GlassMenuResult<T> {
  const _GlassMenuResult(this.value);
  final T? value;
}

/// Everything the open menu needs from its button, read when it opens.
class _GlassMenuSpec<T> {
  const _GlassMenuSpec({
    required this.items,
    required this.selectedIndex,
    required this.buttonRect,
    required this.textDirection,
    required this.style,
    required this.itemHeight,
    required this.menuMaxHeight,
    required this.menuWidth,
    required this.menuMargin,
    required this.menuPadding,
    required this.menuItemPadding,
    required this.borderRadius,
    required this.tone,
    required this.header,
    required this.headerHeight,
    required this.searchController,
    required this.searchMatch,
    required this.highlightSelected,
    required this.overPopup,
  });

  final List<DropdownMenuItem<T>> items;
  final int? selectedIndex;
  final Rect buttonRect;
  final TextDirection textDirection;
  final TextStyle style;
  final double? itemHeight;
  final double? menuMaxHeight;
  final double? menuWidth;
  final EdgeInsetsGeometry menuMargin;
  final EdgeInsetsGeometry menuPadding;
  final EdgeInsetsGeometry menuItemPadding;
  final BorderRadius borderRadius;
  final Color? tone;
  final Widget? header;
  final double headerHeight;
  final TextEditingController? searchController;
  final GlassDropdownMatch<T>? searchMatch;
  final bool highlightSelected;

  /// The button is inside another popup (a dialog, a sheet): the route adds
  /// no dim of its own, and the glass is solved over that popup's surface.
  final bool overPopup;
}

/// The open dropdown's panel: the shared route places it under (or above)
/// the button and runs its spring.
class _GlassMenu<T> extends StatefulWidget {
  const _GlassMenu({required this.spec});

  final _GlassMenuSpec<T> spec;

  @override
  State<_GlassMenu<T>> createState() => _GlassMenuState<T>();
}

class _GlassMenuState<T> extends State<_GlassMenu<T>> {
  ScrollController? _scroll;
  final GlobalKey _selectedKey = GlobalKey();
  late List<int> _shown = _filter();

  _GlassMenuSpec<T> get spec => widget.spec;

  @override
  void initState() {
    super.initState();
    spec.searchController?.addListener(_onSearch);
    if (spec.itemHeight == null && spec.selectedIndex != null) {
      // Rows of their own heights: the first frame opens near the selection
      // by estimate, then lands it in view.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final target = _selectedKey.currentContext;
        if (!mounted || target == null) return;
        Scrollable.ensureVisible(target, alignment: 0.5);
      });
    }
  }

  @override
  void dispose() {
    spec.searchController?.removeListener(_onSearch);
    _scroll?.dispose();
    super.dispose();
  }

  List<int> _filter() {
    final query = spec.searchController?.text ?? '';
    final match = spec.searchMatch;
    if (query.isEmpty || match == null) {
      return List<int>.generate(spec.items.length, (i) => i);
    }
    return [
      for (var i = 0; i < spec.items.length; i++)
        if (match(spec.items[i], query)) i,
    ];
  }

  void _onSearch() {
    final next = _filter();
    setState(() => _shown = next);
    if (_scroll?.hasClients ?? false) _scroll!.jumpTo(0);
  }

  void _select(DropdownMenuItem<T> item) {
    item.onTap?.call();
    Navigator.of(context).pop(_GlassMenuResult<T>(item.value));
  }

  Widget _row(BuildContext context, int position) {
    final index = _shown[position];
    final item = spec.items[index];
    final selected = index == spec.selectedIndex;
    Widget child = Padding(padding: spec.menuItemPadding, child: item);
    if (spec.itemHeight != null) {
      child = SizedBox(height: spec.itemHeight, child: child);
    }
    if (item.enabled) {
      child = InkWell(
        onTap: () => _select(item),
        child: Ink(
          color: selected && spec.highlightSelected
              ? Theme.of(context).focusColor
              : null,
          child: child,
        ),
      );
    }
    return selected ? KeyedSubtree(key: _selectedKey, child: child) : child;
  }

  @override
  Widget build(BuildContext context) {
    final padding = spec.menuPadding.resolve(spec.textDirection);
    // The room the route leaves the panel: the screen less 8 points and the
    // safe area (and the keyboard) on every side.
    return LayoutBuilder(
      builder: (context, constraints) {
        final anchorWidth = spec.menuMargin
            .resolve(spec.textDirection)
            .inflateRect(spec.buttonRect)
            .width;
        final width = math.min(
          spec.menuWidth ?? anchorWidth,
          constraints.maxWidth,
        );
        final maxHeight = math.min(
          spec.menuMaxHeight ?? double.infinity,
          constraints.maxHeight,
        );

        // Rows of their own height: the button shows the same item, so its
        // height is the best guess at a row's until the menu is laid out.
        final rowHeight =
            spec.itemHeight ??
            math.max(kMinInteractiveDimension, spec.buttonRect.height);
        final listContent = padding.vertical + _shown.length * rowHeight;
        final listHeight = math.max(0.0, maxHeight - spec.headerHeight);

        _scroll ??= ScrollController(
          initialScrollOffset: _initialOffset(
            padding: padding,
            rowHeight: rowHeight,
            viewport: listHeight,
            content: listContent,
          ),
        );

        Widget list = ListView.builder(
          controller: _scroll,
          padding: padding,
          shrinkWrap: spec.itemHeight == null,
          itemExtent: spec.itemHeight,
          itemCount: _shown.length,
          itemBuilder: _row,
        );
        // A quiet tonal thumb with round caps, set in from the rim and held
        // clear of the rounded corners at both ends, so it is never sliced
        // by the panel's silhouette.
        final corner = math.max(
          math.max(spec.borderRadius.topRight.y, spec.borderRadius.topLeft.y),
          math.max(
            spec.borderRadius.bottomRight.y,
            spec.borderRadius.bottomLeft.y,
          ),
        );
        list = RawScrollbar(
          controller: _scroll,
          thumbVisibility: true,
          thickness: 3,
          radius: const Radius.circular(1.5),
          crossAxisMargin: 4,
          mainAxisMargin: corner,
          thumbColor: context.colors.textPrimary.withValues(alpha: 0.22),
          child: ScrollConfiguration(
            behavior: ScrollConfiguration.of(context).copyWith(
              scrollbars: false,
              overscroll: false,
              physics: const ClampingScrollPhysics(),
            ),
            child: list,
          ),
        );
        list = spec.itemHeight == null
            ? Flexible(child: list)
            : SizedBox(height: math.min(listHeight, listContent), child: list);

        return GlassPopoverPanel(
          width: width,
          borderRadius: spec.borderRadius,
          tone: spec.tone,
          page: spec.overPopup ? context.colors.surface : null,
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: Semantics(
            scopesRoute: true,
            namesRoute: true,
            explicitChildNodes: true,
            label: MaterialLocalizations.of(context).popupMenuLabel,
            child: Material(
              type: MaterialType.transparency,
              textStyle: spec.style,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [?spec.header, list],
              ),
            ),
          ),
        );
      },
    );
  }

  /// Opens with the selected row in the middle of the list, as far as the
  /// list can scroll.
  double _initialOffset({
    required EdgeInsets padding,
    required double rowHeight,
    required double viewport,
    required double content,
  }) {
    final selected = spec.selectedIndex;
    if (selected == null) return 0;
    final position = _shown.indexOf(selected);
    if (position < 0) return 0;
    final centred =
        padding.top + position * rowHeight - (viewport - rowHeight) / 2;
    return centred.clamp(0.0, math.max(0.0, content - viewport));
  }
}
