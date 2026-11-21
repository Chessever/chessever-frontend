import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/widgets/popup_glass.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/rendering.dart';
import 'package:motor/motor.dart';

/// Shows [builder]'s dialog on a [GlassDialogRoute]: the alert modal's open
/// (a plain scrim that fades in on a spring while the dialog scales up, no
/// blur behind it, nothing faded) for the dialogs [showAlertModal] cannot
/// carry:
///
/// - an outside tap goes through the route's barrier, so it asks the
///   dialog's [PopScope] first (a dialog that locks itself while busy, an
///   update that turns mandatory while open);
/// - the dialog gets the root navigator, the opener's themes and a safe
///   area, as [showDialog] gave it;
/// - nothing depends on [ResponsiveHelper] having been initialised.
///
/// [scrim] is the dimming at rest (the theme's scrim at the glass's
/// strength when null; transparent for none). With [scaleIn] false the
/// dialog stands still and only the scrim moves (an anchored tooltip, a
/// full-screen stage).
Future<T?> showGlassDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
  String? barrierLabel,
  Color? scrim,
  bool useRootNavigator = true,
  bool useSafeArea = true,
  bool scaleIn = true,
  RouteSettings? settings,
}) {
  final navigator = Navigator.of(context, rootNavigator: useRootNavigator);
  return navigator.push<T>(
    GlassDialogRoute<T>(
      context: context,
      builder: builder,
      themes: InheritedTheme.capture(from: context, to: navigator.context),
      barrierDismissible: barrierDismissible,
      barrierLabel: barrierLabel,
      scrim: scrim,
      useSafeArea: useSafeArea,
      scaleIn: scaleIn,
      settings: settings,
    ),
  );
}

/// The route behind [showGlassDialog], for callers that keep the route
/// itself (to take exactly this dialog away later).
///
/// It has no transition of its own: the page is at full strength from its
/// first frame (a glass panel under an opacity would lose its frost), and a
/// pop takes it away at once, as the alert modal's does.
class GlassDialogRoute<T> extends RawDialogRoute<T> {
  GlassDialogRoute({
    required BuildContext context,
    required WidgetBuilder builder,
    CapturedThemes? themes,
    super.barrierDismissible = true,
    String? barrierLabel,
    Color? scrim,
    bool useSafeArea = true,
    bool scaleIn = true,
    super.settings,
  }) : super(
         barrierLabel:
             barrierLabel ??
             MaterialLocalizations.of(context).modalBarrierDismissLabel,
         // The stage draws the scrim, so it can fade on a spring; the
         // barrier only takes the outside taps.
         barrierColor: Colors.transparent,
         transitionDuration: Duration.zero,
         transitionBuilder: _still,
         pageBuilder: (context, _, _) {
           Widget dialog = Builder(builder: builder);
           if (useSafeArea) dialog = SafeArea(child: dialog);
           final stage = GlassDialogStage(
             scrim: scrim,
             scaleIn: scaleIn,
             child: dialog,
           );
           return themes?.wrap(stage) ?? stage;
         },
       );

  static Widget _still(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => child;
}

/// The open of a [GlassDialogRoute]: the scrim fades in and the dialog
/// scales up from 0.85, both on the alert modal's spring, both settled at
/// once under reduced motion. The scrim takes no taps: an outside tap falls
/// through to the route's barrier.
class GlassDialogStage extends StatefulWidget {
  const GlassDialogStage({
    super.key,
    required this.child,
    this.scrim,
    this.scaleIn = true,
  });

  final Widget child;
  final Color? scrim;
  final bool scaleIn;

  @override
  State<GlassDialogStage> createState() => _GlassDialogStageState();
}

class _GlassDialogStageState extends State<GlassDialogStage> {
  double _target = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _target = 1);
    });
  }

  @override
  Widget build(BuildContext context) {
    final rest =
        widget.scrim ??
        context.colors.scrim.withValues(
          alpha: PopupGlassStyle.of(context).scrim,
        );
    final dims = rest.a > 0;
    // Nothing to move: the dialog is simply there.
    if (!dims && !widget.scaleIn) return widget.child;
    final still = MediaQuery.disableAnimationsOf(context);
    return SingleMotionBuilder(
      motion: const _OpenSpring(),
      value: _target,
      child: widget.child,
      builder: (context, value, child) {
        final progress = still ? 1.0 : value;
        final Widget content = widget.scaleIn
            ? Transform.scale(scale: 0.85 + 0.15 * progress, child: child)
            : child!;
        if (!dims) return content;
        return Stack(
          fit: StackFit.expand,
          children: [
            IgnorePointer(
              child: ColoredBox(
                color: rest.withValues(
                  alpha: rest.a * progress.clamp(0.0, 1.0),
                ),
              ),
            ),
            content,
          ],
        );
      },
    );
  }
}

/// The alert modal's open spring ([CupertinoMotion.bouncy]), let go once
/// it is within a hair of rest and set exactly on its target.
///
/// The default tolerance keeps a bouncy spring ticking for a second (about
/// 64 frames, each one re-blurring the panel's backdrop) to settle motion
/// far below a pixel. Cut where what is left moves a 300 pt panel's edge
/// by about a tenth of a pixel and the scrim by under one percent of its
/// strength, the open is about 40 frames.
class _OpenSpring extends Motion {
  const _OpenSpring()
    : super(tolerance: const Tolerance(distance: 0.005, velocity: 0.05));

  static const _spring = CupertinoMotion.bouncy();

  @override
  bool get needsSettle => true;

  @override
  bool get unboundedWillSettle => false;

  @override
  Simulation createSimulation({
    double start = 0,
    double end = 1,
    double velocity = 0,
  }) => SpringSimulation(
    _spring.description,
    start,
    end,
    velocity,
    tolerance: tolerance,
    snapToEnd: true,
  );

  @override
  bool operator ==(Object other) => other is _OpenSpring;

  @override
  int get hashCode => (_OpenSpring).hashCode;
}

/// A Material [Dialog] whose surface is [PopupGlass]: the dialog keeps its
/// inset, its width rules and its dialog semantics; its own Material draws
/// nothing, and the glass (averaging to [tone], the colour the dialog used
/// to be) is cut to [borderRadius].
class GlassDialog extends StatelessWidget {
  const GlassDialog({
    super.key,
    required this.child,
    required this.borderRadius,
    this.tone,
    this.insetPadding,
    this.constraints,
    this.dark = false,
    this.cover,
  });

  final Widget child;
  final BorderRadius borderRadius;
  final Color? tone;
  final EdgeInsets? insetPadding;
  final BoxConstraints? constraints;

  /// A denser plate, for a tone whose own text sits close to 4.5:1 (see
  /// [PopupGlassStyle.of]); null keeps the theme's.
  final double? cover;

  /// The surface is dark in both themes: see [FixedDarkPopupGlass].
  final bool dark;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.transparent,
      elevation: 0,
      insetPadding: insetPadding,
      constraints: constraints,
      shape: RoundedRectangleBorder(borderRadius: borderRadius),
      child: dark
          ? FixedDarkPopupGlass(
              borderRadius: borderRadius,
              tone: tone,
              cover: cover,
              child: child,
            )
          : PopupGlass(
              borderRadius: borderRadius,
              tone: tone,
              cover: cover,
              child: child,
            ),
    );
  }
}

/// A Material [AlertDialog] on [PopupGlass].
///
/// Give the dialog no surface of its own (`backgroundColor`,
/// `surfaceTintColor` and `shadowColor` transparent, `elevation` 0) and
/// leave everything else as it was: its inset, paddings, text styles,
/// scrolling, actions bar and semantics lay out exactly as before. The
/// frame then finds where the dialog put its (now invisible) card and lays
/// the glass under exactly that rect, every layout.
///
/// Sizing the glass by the dialog's intrinsic size instead is not safe: an
/// [OverflowBar] reports its intrinsic height from its buttons' shortest
/// words, so actions that stack in layout (a long "Remind me in 3 days")
/// come out a row short and the content is cut.
class GlassAlertFrame extends StatelessWidget {
  const GlassAlertFrame({
    super.key,
    required this.child,
    required this.borderRadius,
    this.tone,
  });

  /// The dialog: an [AlertDialog] or a [Dialog], drawn transparent.
  final Widget child;
  final BorderRadius borderRadius;
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    return _GlassUnderDialog(
      glass: IgnorePointer(
        child: PopupGlass(
          borderRadius: borderRadius,
          tone: tone,
          child: const SizedBox.expand(),
        ),
      ),
      dialog: child,
    );
  }
}

/// Lays out [dialog] as it would lay itself out, then [glass] at exactly
/// the rect of the dialog's card, under it.
class _GlassUnderDialog extends MultiChildRenderObjectWidget {
  _GlassUnderDialog({required Widget glass, required Widget dialog})
    : super(children: [glass, dialog]);

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderGlassUnderDialog();
}

class _GlassUnderDialogParentData extends ContainerBoxParentData<RenderBox> {}

class _RenderGlassUnderDialog extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _GlassUnderDialogParentData>,
        RenderBoxContainerDefaultsMixin<
          RenderBox,
          _GlassUnderDialogParentData
        > {
  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _GlassUnderDialogParentData) {
      child.parentData = _GlassUnderDialogParentData();
    }
  }

  RenderBox get _glass => firstChild!;
  RenderBox get _dialog => lastChild!;

  @override
  void performLayout() {
    // Loose, so the dialog is never a relayout boundary: anything that
    // changes its card's size (an error line, the keyboard inset) lays this
    // out again, and the glass follows.
    _dialog.layout(constraints.loosen(), parentUsesSize: true);
    (_dialog.parentData! as BoxParentData).offset = Offset.zero;
    size = constraints.constrain(_dialog.size);
    var card = Rect.zero;
    // Reads the sizes the dialog's own layout just settled below it.
    invokeLayoutCallback<BoxConstraints>((_) => card = _cardOf(_dialog));
    _glass.layout(BoxConstraints.tight(card.size));
    (_glass.parentData! as BoxParentData).offset = card.topLeft;
  }

  /// The card a Material dialog centres in its inset: the child of the
  /// first [Align] down its single-child spine (a [Dialog] is semantics,
  /// its inset padding, an [Align], then its card), relative to [root].
  static Rect _cardOf(RenderBox root) {
    var offset = Offset.zero;
    RenderObject? node = root;
    while (node is RenderBox) {
      if (node is RenderPositionedBox) {
        final card = node.child;
        if (card == null || !card.hasSize) break;
        return (offset + (card.parentData! as BoxParentData).offset) &
            card.size;
      }
      if (node is! RenderObjectWithChildMixin<RenderBox>) break;
      final child = (node as RenderObjectWithChildMixin<RenderBox>).child;
      if (child == null) break;
      if (node is RenderShiftedBox) {
        offset += (child.parentData! as BoxParentData).offset;
      }
      node = child;
    }
    assert(false, 'GlassAlertFrame: no dialog card found under $root');
    return Rect.zero;
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) =>
      constraints.constrain(_dialog.getDryLayout(constraints.loosen()));

  @override
  double computeMinIntrinsicWidth(double height) =>
      _dialog.getMinIntrinsicWidth(height);

  @override
  double computeMaxIntrinsicWidth(double height) =>
      _dialog.getMaxIntrinsicWidth(height);

  @override
  double computeMinIntrinsicHeight(double width) =>
      _dialog.getMinIntrinsicHeight(width);

  @override
  double computeMaxIntrinsicHeight(double width) =>
      _dialog.getMaxIntrinsicHeight(width);

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}

/// [PopupGlass] for a surface that keeps one dark tone in both themes (a
/// dark card on a dark stage): the glass is the dark theme's (its quiet
/// rim, no paper sheen across the top of a dark panel), and [child] keeps
/// the theme it was drawn with.
class FixedDarkPopupGlass extends StatelessWidget {
  const FixedDarkPopupGlass({
    super.key,
    required this.child,
    required this.borderRadius,
    this.tone,
    this.padding,
    this.cover,
    this.page,
  });

  final Widget child;
  final BorderRadius borderRadius;
  final Color? tone;
  final EdgeInsetsGeometry? padding;
  final double? cover;

  /// What the glass stands on, when it is not the dark theme's dimmed page
  /// (a lightbox's own stage); see [PopupGlassStyle.of].
  final Color? page;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // One shape in both themes, so a theme switch never remounts [child].
    return Theme(
      data: theme.brightness == Brightness.dark ? theme : AppTheme.darkTheme,
      child: PopupGlass(
        borderRadius: borderRadius,
        tone: tone,
        padding: padding,
        cover: cover,
        page: page,
        child: Theme(data: theme, child: child),
      ),
    );
  }
}

/// The white teaching card of a coachmark (pinch to resize, swipe to
/// browse, My Space's edit tips), cut from the popups' paper glass in both
/// themes: the plate, its grain, the lit rim and one tight contact shadow,
/// where the card used to be a flat white box under a wide black bloom.
/// [child] keeps the theme it was drawn with (black type on white).
///
/// It stands on its coachmark's [stage], a near-opaque dark scrim with
/// nothing behind it worth frosting, so it takes the glass without the live
/// blur ([PopupGlassNoFrost]): the coachmarks' demos loop, and a blur would
/// be paid again on every frame of them. The plate covers nearly all of the
/// stage, so the card stays white.
class TeachingCardGlass extends StatelessWidget {
  const TeachingCardGlass({
    super.key,
    required this.child,
    required this.borderRadius,
    required this.stage,
    this.padding,
  });

  final Widget child;
  final BorderRadius borderRadius;

  /// The coachmark's scrim at rest, over the page.
  final Color stage;
  final EdgeInsetsGeometry? padding;

  /// How much of the stage the white plate covers.
  static const double cover = 0.96;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final page = Color.alphaBlend(stage, context.colors.background);
    // One shape in both themes, so a theme switch never remounts [child].
    return PopupGlassNoFrost(
      child: Theme(
        data: theme.brightness == Brightness.light
            ? theme
            : AppTheme.lightTheme,
        child: PopupGlass(
          borderRadius: borderRadius,
          tone: Colors.white,
          cover: cover,
          page: page,
          padding: padding,
          child: Theme(data: theme, child: child),
        ),
      ),
    );
  }
}
