import 'package:chessever2/screens/library/widgets/library_context_menu.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:motor/motor.dart';

/// Builds the actions for one card at the moment its menu opens, so rows that
/// read live state (e.g. "Add to" vs "Remove from My Space") are never stale.
typedef CardMenuActionsBuilder =
    List<LibraryMenuAction> Function(BuildContext context);

/// Makes any card open the shared focus menu ([showLibraryContextMenu]) on
/// long-press: the card lifts in place above a blurred page and its actions
/// open beside it.
///
/// The card itself is the preview, so there is nothing to keep in sync. A
/// [CardMoreButton] anywhere inside [child] opens the same menu anchored to
/// the whole card, so the three-dot button and the long-press are one menu.
/// While the copy is lifted the original is hidden (its layout, state and
/// tickers kept), so the blur behind never shows a halo of the card.
///
/// The preview is a rebuilt copy of [child] in the menu's route. Do not wrap a
/// child that carries a GlobalKey (it would be mounted twice) or a heavy live
/// widget such as an interactive board; pass [previewBuilder] with a
/// lightweight stand-in, or turn [showPreview] off.
///
/// Leave [child] without its own `onLongPress`; this wrapper owns it.
class CardContextMenu extends StatefulWidget {
  const CardContextMenu({
    super.key,
    required this.actions,
    required this.child,
    this.enabled = true,
    this.onPreviewTap,
    this.showPreview = true,
    this.previewBuilder,
  });

  final CardMenuActionsBuilder actions;
  final Widget child;

  /// When false the card behaves as if this wrapper were not there.
  final bool enabled;

  /// Tapping the lifted card (e.g. to open it). The menu closes first.
  final VoidCallback? onPreviewTap;

  /// Draw the lifted copy of the card. Turn off for very tall surfaces where
  /// only the actions make sense.
  final bool showPreview;

  /// What lifts in place of a rebuilt [child], laid out at the card's size.
  /// Ignored when [showPreview] is false.
  final WidgetBuilder? previewBuilder;

  /// Opens the menu for the card that [cardContext] belongs to. [origin] is
  /// the global point that summoned it: on a card wider than the menu, a
  /// press on the right half opens the menu against the right edge.
  ///
  /// For a custom trigger; a [CardContextMenu]'s own long-press and
  /// [CardMoreButton] also hide the original while the copy is lifted.
  ///
  /// A card held in its own press-scale when the menu opens is measured as
  /// painted, so the lifted copy starts at the size the finger left it.
  static Future<void> open(
    BuildContext cardContext, {
    required CardMenuActionsBuilder actions,
    Widget? preview,
    WidgetBuilder? previewBuilder,
    VoidCallback? onPreviewTap,
    LibraryContextMenuHandle? handle,
    Offset? origin,
    ValueChanged<bool>? onPreviewLiftChanged,
  }) {
    final list = actions(cardContext);
    if (list.isEmpty) return Future.value();
    return showLibraryContextMenu(
      context: _paintedAnchor(cardContext),
      actions: list,
      previewBuilder:
          previewBuilder ?? (preview == null ? null : (_) => preview),
      onPreviewTap: onPreviewTap,
      handle: handle,
      origin: origin,
      onPreviewLiftChanged: onPreviewLiftChanged,
    );
  }

  @override
  State<CardContextMenu> createState() => _CardContextMenuState();
}

class _CardContextMenuState extends State<CardContextMenu> {
  bool _lifted = false;

  WidgetBuilder? get _preview {
    if (!widget.showPreview) return null;
    final builder = widget.previewBuilder;
    if (builder != null) return builder;
    final child = widget.child;
    return (_) => child;
  }

  void _setLifted(bool value) {
    if (!mounted || _lifted == value) return;
    setState(() => _lifted = value);
  }

  Future<void> _open(
    BuildContext anchor, {
    CardMenuActionsBuilder? actions,
    Offset? origin,
  }) {
    return CardContextMenu.open(
      anchor,
      actions: actions ?? widget.actions,
      previewBuilder: _preview,
      onPreviewTap: widget.onPreviewTap,
      origin: origin,
      onPreviewLiftChanged: _setLifted,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    return _CardMenuScope(
      state: this,
      child: Builder(
        builder: (cardContext) {
          return GestureDetector(
            // Children keep their own taps; only the long-press is ours.
            behavior: HitTestBehavior.deferToChild,
            onLongPressStart: (details) => _open(
              cardContext,
              // A screen reader's long-press action reports no position.
              origin: details.globalPosition == Offset.zero
                  ? null
                  : details.globalPosition,
            ),
            // Installed for good, so hiding never remounts the card.
            child: Visibility.maintain(visible: !_lifted, child: widget.child),
          );
        },
      ),
    );
  }
}

/// Lowest scale still read as a card's own press feedback (cards here press
/// to 0.96-0.98). Anything smaller is the card's layout, not a finger.
const double _kPressScaleFloor = 0.85;

/// How far down a card's single-child chain the press-scale is looked for.
const int _kPaintedAnchorDepth = 64;

/// The context the menu should measure for [anchor]: [anchor] itself, or,
/// while the card is held in its own press-scale, the part of the card under
/// that scale.
///
/// A card's press-scale (TappableScale at 0.96, the folder card at 0.97) sits
/// inside the card, below the box [anchor] measures. Measured there, the
/// menu reads a card at full size while the user is looking at one pressed
/// in, so the lifted copy would pop about 4% larger in one frame before its
/// lift began. Measured under the scale, it starts exactly where it was.
///
/// Only a chain of single children the card's own size is walked, so the box
/// found is the whole card, just as painted; anything else leaves [anchor].
BuildContext _paintedAnchor(BuildContext anchor) {
  if (anchor is! Element) return anchor;
  final root = anchor.findRenderObject();
  if (root is! RenderBox || !root.attached || !root.hasSize) return anchor;
  final size = root.size;
  if (size.isEmpty) return anchor;

  Element element = anchor;
  // The first element below the last box that was measured: its render
  // object is the next box, and nothing the card builds under it is skipped.
  Element? belowLastBox;
  for (var depth = 0; depth < _kPaintedAnchorDepth; depth++) {
    Element? only;
    var count = 0;
    element.visitChildElements((child) {
      count++;
      only = child;
    });
    if (count != 1) break;
    element = only!;
    final start = belowLastBox ??= element;
    if (element is! RenderObjectElement) continue;

    final box = element.renderObject;
    if (box is! RenderBox || !box.attached || !box.hasSize) break;
    if ((box.size.width - size.width).abs() > 0.5 ||
        (box.size.height - size.height).abs() > 0.5) {
      break;
    }
    final painted = MatrixUtils.transformRect(
      box.getTransformTo(root),
      Offset.zero & box.size,
    );
    final scale = painted.width / size.width;
    if (!scale.isFinite) break;
    if (scale < 1 - 1e-3) {
      return scale >= _kPressScaleFloor ? start : anchor;
    }
    belowLastBox = null;
  }
  return anchor;
}

class _CardMenuScope extends InheritedWidget {
  const _CardMenuScope({required this.state, required super.child});

  final _CardContextMenuState state;

  /// The scope's element: it has no render object of its own, so it measures
  /// as the card and is the anchor the menu lifts.
  static InheritedElement? elementOf(BuildContext context) =>
      context.getElementForInheritedWidgetOfExactType<_CardMenuScope>();

  @override
  bool updateShouldNotify(_CardMenuScope oldWidget) =>
      !identical(state, oldWidget.state);
}

/// The three-dot entry to a card's menu. Inside a [CardContextMenu] it opens
/// that card's menu (the whole card lifts); on its own it needs [actions] and
/// anchors to itself.
///
/// The glyph is small and quiet, but the tap target is the platform minimum.
/// A press reads on the button itself (a tonal disc and a slight give) rather
/// than through ink, which an opaque card would paint over. The button also
/// takes the pointer once a press rests on it, so the card around it never
/// sinks as if the card itself had been pressed.
class CardMoreButton extends StatefulWidget {
  const CardMoreButton({
    super.key,
    this.actions,
    this.color,
    this.size,
    this.tooltip = 'More actions',
    this.vertical = false,
  });

  /// Required when the button is not inside a [CardContextMenu].
  final CardMenuActionsBuilder? actions;
  final Color? color;
  final double? size;
  final String tooltip;

  /// `more_vert` instead of `more_horiz`, for app bars that already use it.
  final bool vertical;

  @override
  State<CardMoreButton> createState() => _CardMoreButtonState();
}

/// Press feedback: short and firm, landing exactly on rest.
const Motion _kMorePressMotion = CupertinoMotion.smooth(
  duration: Duration(milliseconds: 140),
  snapToEnd: true,
);
const double _kMorePressedScale = 0.97;
const double _kMoreTarget = 44;

class _CardMoreButtonState extends State<CardMoreButton> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (!mounted || _pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final scopeElement = _CardMenuScope.elementOf(context);
    final card = (scopeElement?.widget as _CardMenuScope?)?.state;
    final canOpen = widget.actions != null || card != null;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    // Tonal: a step off the surface in the ink's own direction, the same
    // step the focus menu's rows take when pressed.
    final fill = context.isLightTheme
        ? context.colors.textPrimary.withValues(alpha: 0.08)
        : const Color(0xFFFFFFFF).withValues(alpha: 0.10);

    Widget button = SizedBox(
      width: _kMoreTarget,
      height: _kMoreTarget,
      child: Center(
        child: Icon(
          widget.vertical ? Icons.more_vert_rounded : Icons.more_horiz_rounded,
          size: widget.size ?? 20.sp,
          color: widget.color ?? context.colors.iconSecondary,
        ),
      ),
    );

    if (canOpen) {
      button = RawGestureDetector(
        // The whole 44dp square is the target, not just the glyph's ink.
        behavior: HitTestBehavior.opaque,
        gestures: <Type, GestureRecognizerFactory>{
          _ClaimingTapGestureRecognizer:
              GestureRecognizerFactoryWithHandlers<
                _ClaimingTapGestureRecognizer
              >(
                () => _ClaimingTapGestureRecognizer(debugOwner: this),
                (recognizer) => recognizer
                  ..onTapDown = ((_) => _setPressed(true))
                  ..onTapUp = ((_) => _setPressed(false))
                  ..onTapCancel = (() => _setPressed(false))
                  ..onTap = (() => _open(context)),
              ),
        },
        child: SingleMotionBuilder(
          value: _pressed ? 1.0 : 0.0,
          motion: _kMorePressMotion,
          active: !reduceMotion,
          builder: (context, t, child) {
            final k = t.clamp(0.0, 1.0);
            return Transform.scale(
              // Reduced motion keeps the tonal change and drops the give.
              scale: reduceMotion ? 1.0 : 1 - (1 - _kMorePressedScale) * k,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: fill.withValues(alpha: fill.a * k),
                  shape: BoxShape.circle,
                ),
                child: child,
              ),
            );
          },
          child: button,
        ),
      );
    }

    return Semantics(
      button: true,
      label: widget.tooltip,
      excludeSemantics: true,
      onTap: canOpen ? () => _open(context) : null,
      child: Tooltip(message: widget.tooltip, child: button),
    );
  }

  void _open(BuildContext context) {
    final actions = widget.actions;
    // The button's own centre is the press point, so the menu opens on the
    // side of the card the button sits on.
    final box = context.findRenderObject();
    final origin = box is RenderBox && box.hasSize
        ? box.localToGlobal(box.size.center(Offset.zero))
        : null;
    final scopeElement = _CardMenuScope.elementOf(context);
    final card = (scopeElement?.widget as _CardMenuScope?)?.state;
    if (card != null && card.mounted && scopeElement != null) {
      // Inside a card the whole card lifts, whichever actions it shows.
      card._open(scopeElement, actions: actions, origin: origin);
    } else if (actions != null) {
      CardContextMenu.open(context, actions: actions, origin: origin);
    }
  }
}

/// A tap that keeps the pointer once a press has rested on it for the press
/// timeout.
///
/// Every tap recognizer under a finger reports its press at that timeout,
/// the enclosing card's press-scale included, so on its own the card would
/// sink under a held button. This one claims the arena at that moment
/// instead. Its timer was started first (the button is deeper in the hit
/// test than the card), so the card's recognizer is turned away before it
/// ever reports a press. A drag that leaves within the timeout still goes to
/// the list or swipe around the button, and a quick tap resolves on release
/// exactly as before.
class _ClaimingTapGestureRecognizer extends TapGestureRecognizer {
  _ClaimingTapGestureRecognizer({super.debugOwner});

  @override
  void didExceedDeadline() {
    super.didExceedDeadline();
    if (state == GestureRecognizerState.possible) {
      resolve(GestureDisposition.accepted);
    }
  }
}
