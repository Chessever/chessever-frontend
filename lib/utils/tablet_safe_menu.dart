import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/glass_anchored_route.dart';
import 'package:chessever2/widgets/popup_glass.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show SemanticsRole;
import 'package:flutter/services.dart';

export 'package:chessever2/widgets/glass_anchored_route.dart'
    show
        GlassAnchoredMotion,
        GlassAnchoredRoute,
        GlassAnchoredTransition,
        GlassFold,
        GlassFoldFade,
        GlassFoldIgnorePointer,
        GlassFoldScope,
        GlassFoldTransition,
        GlassMenuAnchoring,
        GlassMenuPlacement,
        GlassScrimPainter,
        RenderGlassFoldTransition,
        RenderGlassMenuPlacement,
        TransientOverlayRoute;

/// Global state to track when tablet-safe popups are open.
/// Used to defer rebuilds that would close popups unexpectedly.
class TabletPopupState {
  static bool isAnyPopupOpen = false;

  static void markOpen() => isAnyPopupOpen = true;
  static void markClosed() => isAnyPopupOpen = false;
}

/// How long a tablet menu ignores taps on the page around it after it opens:
/// tablets deliver a phantom tap some 300-400ms after a menu opens, and it
/// must not close the menu it just opened.
const Duration kTabletMenuDismissGuard = Duration(milliseconds: 600);

/// Shows a popup menu of [items] at [position], on the popups' frosted glass
/// ([PopupGlass]), and resolves with the picked item's value (null when it
/// is dismissed).
///
/// It takes what [showMenu] takes and lays the menu out exactly as
/// [showMenu] does (the same width steps, padding and edge fitting), and the
/// [PopupMenuEntry] items build themselves as they would in a Material menu,
/// so [PopupMenuItem.enabled], `onTap`, keys and text styles all hold.
/// [color] is the tone the glass averages to (the colour the opaque menu
/// was); [shape]'s corner radius is the panel's. [elevation] is ignored: the
/// glass casts its own single shadow.
///
/// On tablets taps on the page around the menu are ignored for
/// [kTabletMenuDismissGuard] after it opens, so the phantom tap that follows
/// an open never closes it ([TabletPopupState] is flagged while it is up).
/// Phones dismiss on the first tap, as [showMenu] does.
///
/// Usage:
/// ```dart
/// showTabletSafeMenu(
///   context: context,
///   position: RelativeRect.fromLTRB(x, y, x2, y2),
///   items: [
///     PopupMenuItem(value: 'action1', child: Text('Action 1')),
///     PopupMenuItem(value: 'action2', child: Text('Action 2')),
///   ],
/// ).then((value) {
///   if (value == 'action1') { /* handle */ }
/// });
/// ```
Future<T?> showTabletSafeMenu<T>({
  required BuildContext context,
  required RelativeRect position,
  required List<PopupMenuEntry<T>> items,
  T? initialValue,
  double? elevation,
  Color? color,
  ShapeBorder? shape,
  BoxConstraints? constraints,
  bool useRootNavigator = false,
}) async {
  final tablet = ResponsiveHelper.isTablet;
  if (!tablet) {
    return showGlassMenu<T>(
      context: context,
      position: position,
      items: items,
      initialValue: initialValue,
      color: color,
      shape: shape,
      constraints: constraints,
      useRootNavigator: useRootNavigator,
    );
  }
  // Only clear the flag this menu raised, never one a popup beneath it set.
  final wasOpen = TabletPopupState.isAnyPopupOpen;
  TabletPopupState.markOpen();
  HapticFeedback.selectionClick();
  try {
    return await showGlassMenu<T>(
      context: context,
      position: position,
      items: items,
      initialValue: initialValue,
      color: color,
      shape: shape,
      constraints: constraints,
      useRootNavigator: useRootNavigator,
      dismissGuard: kTabletMenuDismissGuard,
    );
  } finally {
    if (!wasOpen) TabletPopupState.markClosed();
  }
}

/// [showMenu] on the popups' frosted glass: the one glass popup menu.
///
/// Same arguments, layout and results as [showMenu] (see
/// [showTabletSafeMenu] for what [color] and [shape] mean on glass). It is
/// the shared anchored route ([GlassAnchoredRoute]): the page under it is
/// only touched by the anchored menus' light tint ([AnchoredGlassDim]),
/// never blurred, and [opener] (the control that opened the menu, in the
/// navigator overlay's coordinates) stays out of that tint. The menu is on
/// screen at full strength from its first frame and grows out of
/// [position] on the anchored menus' spring (never faded in: glass under an
/// opacity loses its frost); it folds shut back into it as it closes, the
/// picked value handed over as the fold begins ([GlassAnchoredMotion]).
///
/// [dismissGuard] keeps taps on the page around the menu from closing it for
/// that long after it opens (see [showTabletSafeMenu]).
Future<T?> showGlassMenu<T>({
  required BuildContext context,
  required RelativeRect position,
  required List<PopupMenuEntry<T>> items,
  T? initialValue,
  Color? color,
  ShapeBorder? shape,
  BoxConstraints? constraints,
  bool useRootNavigator = false,
  String? semanticLabel,
  Duration dismissGuard = Duration.zero,
  RRect? opener,
}) {
  assert(items.isNotEmpty);
  assert(debugCheckHasMaterialLocalizations(context));
  final localizations = MaterialLocalizations.of(context);
  switch (Theme.of(context).platform) {
    case TargetPlatform.iOS:
    case TargetPlatform.macOS:
      break;
    case TargetPlatform.android:
    case TargetPlatform.fuchsia:
    case TargetPlatform.linux:
    case TargetPlatform.windows:
      semanticLabel ??= localizations.popupMenuLabel;
  }
  final navigator = Navigator.of(context, rootNavigator: useRootNavigator);
  final overlay = navigator.overlay?.context.findRenderObject();
  final bounds = overlay is RenderBox && overlay.hasSize
      ? Offset.zero & overlay.size
      : Offset.zero & MediaQuery.sizeOf(context);
  final keys = List<GlobalKey>.generate(items.length, (_) => GlobalKey());
  int? selectedIndex;
  if (initialValue != null) {
    for (var i = 0; selectedIndex == null && i < items.length; i++) {
      if (items[i].represents(initialValue)) selectedIndex = i;
    }
  }
  final selected = selectedIndex;
  return navigator.push(
    GlassAnchoredRoute<T>(
      anchor: position.toRect(bounds),
      anchoring: GlassMenuAnchoring.over,
      dim: AnchoredGlassDim.colorOf(context),
      hole: opener,
      barrierLabel: localizations.menuDismissLabel,
      capturedThemes: InheritedTheme.capture(
        from: context,
        to: navigator.context,
      ),
      dismissGuard: dismissGuard,
      // Menus cycle focus through their items, as Material's do.
      traversalEdgeBehavior: TraversalEdgeBehavior.closedLoop,
      builder: (context) => _GlassMenuPanel<T>(
        items: items,
        itemKeys: keys,
        selectedIndex: selected,
        color: color,
        shape: shape,
        constraints: constraints,
        semanticLabel: semanticLabel,
      ),
    ),
  );
}

/// Corner radius of a glass menu whose caller names no shape.
double _defaultMenuRadius() => 12.br;

// Material's menu metrics ([showMenu]), so a glass menu lays out exactly as
// the menu it replaces.
const double _kMenuWidthStep = 56;
const double _kMenuMinWidth = 2 * _kMenuWidthStep;
const double _kMenuMaxWidth = 5 * _kMenuWidthStep;
const EdgeInsets _kMenuPadding = EdgeInsets.symmetric(vertical: 8);

/// The menu: Material's menu column, drawn on a glass panel.
class _GlassMenuPanel<T> extends StatefulWidget {
  const _GlassMenuPanel({
    required this.items,
    required this.itemKeys,
    required this.selectedIndex,
    required this.color,
    required this.shape,
    required this.constraints,
    required this.semanticLabel,
  });

  final List<PopupMenuEntry<T>> items;
  final List<GlobalKey> itemKeys;
  final int? selectedIndex;
  final Color? color;
  final ShapeBorder? shape;
  final BoxConstraints? constraints;
  final String? semanticLabel;

  @override
  State<_GlassMenuPanel<T>> createState() => _GlassMenuPanelState<T>();
}

class _GlassMenuPanelState<T> extends State<_GlassMenuPanel<T>> {
  @override
  void initState() {
    super.initState();
    final selected = widget.selectedIndex;
    if (selected != null) {
      // Opens scrolled to the selected item, as Material's menu does.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final itemContext = widget.itemKeys[selected].currentContext;
        if (itemContext != null) Scrollable.ensureVisible(itemContext);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final popupTheme = PopupMenuTheme.of(context);
    // The app's own neutral surface when no tone is named, like every other
    // glass: Material's fallback (the scheme's surfaceContainer) is a cool
    // blue-slate in the dark theme.
    final tone = widget.color ?? popupTheme.color ?? context.colors.surface;
    final shape = widget.shape ?? popupTheme.shape;
    final radius = shape is RoundedRectangleBorder
        ? shape.borderRadius.resolve(Directionality.of(context))
        : BorderRadius.circular(_defaultMenuRadius());

    final children = <Widget>[
      for (var i = 0; i < widget.items.length; i++)
        KeyedSubtree(
          key: widget.itemKeys[i],
          child: i == widget.selectedIndex
              ? ColoredBox(color: theme.highlightColor, child: widget.items[i])
              : widget.items[i],
        ),
    ];

    final column = ConstrainedBox(
      constraints:
          widget.constraints ??
          const BoxConstraints(
            minWidth: _kMenuMinWidth,
            maxWidth: _kMenuMaxWidth,
          ),
      child: IntrinsicWidth(
        stepWidth: _kMenuWidthStep,
        child: Semantics(
          role: SemanticsRole.menu,
          scopesRoute: true,
          namesRoute: true,
          explicitChildNodes: true,
          label: widget.semanticLabel,
          child: SingleChildScrollView(
            padding: popupTheme.menuPadding ?? _kMenuPadding,
            child: ListBody(children: children),
          ),
        ),
      ),
    );

    return PopupGlass(
      borderRadius: radius,
      tone: tone,
      // Solved over the page as the anchored dim leaves it.
      page: AnchoredGlassDim.pageOf(context),
      cover: AnchoredGlassDim.cover,
      // The rows' ink lands on the glass; they fade as the menu folds.
      child: GlassFoldFade(
        child: Material(type: MaterialType.transparency, child: column),
      ),
    );
  }
}

/// [PopupMenuButton] on glass: the same button, the same arguments that
/// matter here, opening [showGlassMenu] instead of [showMenu].
///
/// Swap the class name at a [PopupMenuButton] site and nothing else changes
/// but the menu's surface.
class GlassPopupMenuButton<T> extends StatefulWidget {
  const GlassPopupMenuButton({
    super.key,
    required this.itemBuilder,
    this.initialValue,
    this.onOpened,
    this.onSelected,
    this.onCanceled,
    this.tooltip,
    this.padding = const EdgeInsets.all(8),
    this.child,
    this.icon,
    this.iconSize,
    this.iconColor,
    this.offset = Offset.zero,
    this.enabled = true,
    this.shape,
    this.color,
    this.constraints,
    this.position,
    this.useRootNavigator = false,
    this.splashRadius,
    this.borderRadius,
    this.enableFeedback,
    this.style,
  });

  final PopupMenuItemBuilder<T> itemBuilder;
  final T? initialValue;
  final VoidCallback? onOpened;
  final PopupMenuItemSelected<T>? onSelected;
  final PopupMenuCanceled? onCanceled;
  final String? tooltip;
  final EdgeInsetsGeometry padding;
  final Widget? child;
  final Widget? icon;
  final double? iconSize;
  final Color? iconColor;
  final Offset offset;
  final bool enabled;
  final ShapeBorder? shape;

  /// The tone the glass averages to: the colour the opaque menu was.
  final Color? color;
  final BoxConstraints? constraints;
  final PopupMenuPosition? position;
  final bool useRootNavigator;
  final double? splashRadius;
  final BorderRadius? borderRadius;
  final bool? enableFeedback;
  final ButtonStyle? style;

  @override
  State<GlassPopupMenuButton<T>> createState() =>
      _GlassPopupMenuButtonState<T>();
}

class _GlassPopupMenuButtonState<T> extends State<GlassPopupMenuButton<T>> {
  bool _expanded = false;

  /// The button, in the navigator overlay's coordinates.
  Rect? _buttonRect() {
    final button = context.findRenderObject();
    final overlay = Navigator.of(
      context,
      rootNavigator: widget.useRootNavigator,
    ).overlay?.context.findRenderObject();
    if (button is! RenderBox || overlay is! RenderBox) return null;
    return MatrixUtils.transformRect(
      button.getTransformTo(overlay),
      Offset.zero & button.size,
    );
  }

  RelativeRect? _position() {
    final button = context.findRenderObject();
    final overlay = Navigator.of(
      context,
      rootNavigator: widget.useRootNavigator,
    ).overlay?.context.findRenderObject();
    if (button is! RenderBox || overlay is! RenderBox) return null;
    final placement =
        widget.position ??
        PopupMenuTheme.of(context).position ??
        PopupMenuPosition.over;
    var offset = widget.offset;
    if (placement == PopupMenuPosition.under) {
      offset += Offset(0, button.size.height);
      // Without a child it is an IconButton: leave out its padding.
      if (widget.child == null) {
        offset -= Offset(0, widget.padding.vertical / 2);
      }
    }
    return RelativeRect.fromRect(
      Rect.fromPoints(
        button.localToGlobal(offset, ancestor: overlay),
        button.localToGlobal(
          button.size.bottomRight(Offset.zero) + offset,
          ancestor: overlay,
        ),
      ),
      Offset.zero & overlay.size,
    );
  }

  /// Opens the menu, as [PopupMenuButtonState.showButtonMenu] does.
  Future<void> showButtonMenu() async {
    final items = widget.itemBuilder(context);
    final position = _position();
    if (items.isEmpty || position == null) return;
    widget.onOpened?.call();
    setState(() => _expanded = true);
    final button = _buttonRect();
    final value = await showGlassMenu<T>(
      context: context,
      position: position,
      items: items,
      initialValue: widget.initialValue,
      color: widget.color,
      shape: widget.shape,
      constraints: widget.constraints,
      useRootNavigator: widget.useRootNavigator,
      // The button stays lit while its menu is open.
      opener: button == null
          ? null
          : RRect.fromRectAndRadius(
              button,
              Radius.circular(
                widget.child == null
                    ? button.shortestSide / 2
                    : widget.borderRadius?.topLeft.x ?? 0,
              ),
            ),
    );
    if (!mounted) return;
    setState(() => _expanded = false);
    if (value == null) {
      widget.onCanceled?.call();
      return;
    }
    widget.onSelected?.call(value);
  }

  @override
  Widget build(BuildContext context) {
    final popupTheme = PopupMenuTheme.of(context);
    final iconTheme = IconTheme.of(context);
    final feedback = widget.enableFeedback ?? popupTheme.enableFeedback ?? true;
    final tooltip =
        widget.tooltip ?? MaterialLocalizations.of(context).showMenuTooltip;
    final child = widget.child;
    if (child != null) {
      return Semantics(
        expanded: _expanded,
        child: Tooltip(
          message: tooltip,
          child: InkWell(
            borderRadius: widget.borderRadius,
            onTap: widget.enabled ? showButtonMenu : null,
            canRequestFocus: widget.enabled,
            radius: widget.splashRadius,
            enableFeedback: feedback,
            child: child,
          ),
        ),
      );
    }
    return IconButton(
      icon: Semantics(
        expanded: _expanded,
        child: widget.icon ?? Icon(Icons.adaptive.more),
      ),
      padding: widget.padding,
      splashRadius: widget.splashRadius,
      iconSize: widget.iconSize ?? popupTheme.iconSize ?? iconTheme.size,
      color: widget.iconColor ?? popupTheme.iconColor ?? iconTheme.color,
      tooltip: tooltip,
      onPressed: widget.enabled ? showButtonMenu : null,
      enableFeedback: feedback,
      style: widget.style,
    );
  }
}
