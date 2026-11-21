import 'dart:math' as math;

import 'package:chessever2/screens/chessboard/widgets/smooth_sheet_config.dart'
    show
        SpringSheetTransition,
        SurfaceSpring,
        kSheetEntranceMotion,
        kSheetExitMotion,
        settlingSimulation;
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/glass_sheet.dart';
import 'package:chessever2/widgets/popup_glass.dart';
import 'package:flutter/material.dart';
import 'package:motor/motor.dart';

export 'package:chessever2/widgets/glass_sheet.dart'
    show GlassSheet, glassSheetBarrier;

/// [showModalBottomSheet] for a sheet whose surface is glass, on the sheet
/// spring ([SpringSheetTransition], the smooth_sheets sheets' slide): the
/// route paints no fill and no elevation of its own, and dims the page with
/// the glass scrim ([glassSheetBarrier]), a plain tint that fades in with
/// the route (nothing blurs the screen). [builder] returns the glass: a
/// [GlassSheet], or an inset [PopupGlass] for a floating card.
///
/// Everything else is Material's bottom sheet: the drag to dismiss, the
/// fling, the keyboard and the semantics. A drag let go short of closing
/// springs back on the same spring.
///
/// Every panel the route shows is a sheet's ([PopupGlassSheetScope]): a
/// floating card frosts in light as densely as the sheet glass does.
Future<T?> showGlassModalBottomSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = false,
  bool useRootNavigator = false,
  bool useSafeArea = false,
  bool isDismissible = true,
  bool enableDrag = true,
  BoxConstraints? constraints,
}) {
  final navigator = Navigator.of(context, rootNavigator: useRootNavigator);
  final localizations = MaterialLocalizations.of(context);
  return navigator.push<T>(
    GlassModalSheetRoute<T>(
      builder: (context) => PopupGlassSheetScope(child: builder(context)),
      capturedThemes: InheritedTheme.capture(
        from: context,
        to: navigator.context,
      ),
      isScrollControlled: isScrollControlled,
      barrierLabel: localizations.scrimLabel,
      barrierOnTapHint: localizations.scrimOnTapHint(
        localizations.bottomSheetLabel,
      ),
      modalBarrierColor: glassSheetBarrier(context),
      isDismissible: isDismissible,
      enableDrag: enableDrag,
      useSafeArea: useSafeArea,
      constraints: constraints,
      vsync: navigator,
    ),
  );
}

/// The route behind [showGlassModalBottomSheet]: Material's modal bottom
/// sheet with no surface of its own, slid by the sheet spring.
class GlassModalSheetRoute<T> extends ModalBottomSheetRoute<T>
    with SpringSheetTransition<T> {
  GlassModalSheetRoute({
    required super.builder,
    required TickerProvider vsync,
    super.capturedThemes,
    super.barrierLabel,
    super.barrierOnTapHint,
    super.modalBarrierColor,
    super.isDismissible,
    super.enableDrag,
    super.useSafeArea,
    super.constraints,
    required super.isScrollControlled,
    this.entranceMotion = kSheetEntranceMotion,
    this.exitMotion = kSheetExitMotion,
  }) : super(
         backgroundColor: Colors.transparent,
         elevation: 0,
         // The spring carries all of the easing: the sheet's own curve maps
         // the route's value 1:1.
         sheetAnimationStyle: const AnimationStyle(
           curve: Curves.linear,
           reverseCurve: Curves.linear,
         ),
         transitionAnimationController: _SheetSpringController(
           vsync: vsync,
           snapBack: entranceMotion,
         ),
       );

  @override
  final Motion entranceMotion;

  @override
  final Motion exitMotion;

  /// The scrim fades with the sheet's own spring, 1:1.
  @override
  Curve get barrierCurve => Curves.linear;

  @override
  AnimationController createAnimationController() {
    final controller = super.createAnimationController();
    // Made for this route alone: it goes with the route.
    willDisposeAnimationController = true;
    return controller;
  }
}

/// The sheet's controller. A drag let go short of closing settles back on
/// the entrance spring instead of a linear run over a fixed duration
/// ([BottomSheet] asks for `forward()` then); push and pop are the route's
/// own simulations, and a fling is the controller's own spring.
class _SheetSpringController extends AnimationController {
  _SheetSpringController({required super.vsync, required this.snapBack})
    : super(
        // Read by the route for its durations; the springs set the pace.
        duration: const Duration(milliseconds: 400),
        reverseDuration: const Duration(milliseconds: 320),
      );

  final Motion snapBack;

  @override
  TickerFuture forward({double? from}) {
    if (from != null) value = from;
    if (value >= upperBound) return super.forward();
    return animateWith(
      settlingSimulation(snapBack, start: value, end: upperBound),
    );
  }
}

/// The smooth sheet's slide: the sheet springs, at rest once nothing moves
/// by a pixel ([SurfaceSpring]).
const Motion _entranceSlide = SurfaceSpring(
  kSheetEntranceMotion as SpringMotion,
);
const Motion _exitSlide = SurfaceSpring(kSheetExitMotion as SpringMotion);

/// How long a closed sheet stays on screen while its spring carries it out.
/// The result is handed back the moment it closes, and the page under it
/// takes taps again at once; only the picture of the sheet lingers.
const Duration _kSheetExit = Duration(milliseconds: 350);

/// Shows a bottom sheet on Motor springs, its surface the one sheet glass
/// ([GlassSheet], toned to [backgroundColor] or the theme's surface),
/// frosted or solid by [GlassSheet]'s one rule (My Space's add sheet, up to
/// 88% of the screen tall, is solid).
///
/// The page under it is only dimmed by a plain tint that fades in: nothing
/// blurs the whole screen. Closing (a tap on the page, a swipe down, the
/// sheet's own close, system back) pops the route at once, so the result
/// arrives without waiting for the slide out, which plays on the route's
/// exit.
Future<T?> showSmoothBottomSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isDismissible = true,
  bool enableDrag = true,
  Color? backgroundColor,
  double? maxHeight,
}) {
  return Navigator.of(context, rootNavigator: true).push<T>(
    _SmoothSheetRoute<T>(
      builder: builder,
      dismissible: isDismissible,
      enableDrag: enableDrag,
      backgroundColor: backgroundColor,
      maxHeight: maxHeight,
    ),
  );
}

/// The sheet's route: on screen from its first frame (the spring, not the
/// route, moves it in), and kept on screen for [_kSheetExit] after a pop so
/// the spring can carry it out. It draws no barrier of its own; the sheet
/// paints its scrim.
class _SmoothSheetRoute<T> extends PopupRoute<T> {
  _SmoothSheetRoute({
    required this.builder,
    required this.dismissible,
    required this.enableDrag,
    required this.backgroundColor,
    required this.maxHeight,
  });

  final WidgetBuilder builder;
  final bool dismissible;
  final bool enableDrag;
  final Color? backgroundColor;
  final double? maxHeight;

  @override
  Color? get barrierColor => Colors.transparent;

  @override
  bool get barrierDismissible => dismissible;

  @override
  String? get barrierLabel => 'Dismiss';

  @override
  Duration get transitionDuration => Duration.zero;

  @override
  Duration get reverseTransitionDuration => _kSheetExit;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    // As showGeneralDialog's route builds it: its own semantics scope, on
    // one screen of a folding device.
    return Semantics(
      scopesRoute: true,
      explicitChildNodes: true,
      child: DisplayFeatureSubScreen(
        child: _SmoothBottomSheetWrapper<T>(
          routeAnimation: animation,
          builder: builder,
          isDismissible: dismissible,
          enableDrag: enableDrag,
          backgroundColor: backgroundColor,
          maxHeight: maxHeight,
        ),
      ),
    );
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => child; // Never faded: glass under an opacity would lose its frost.
}

class _SmoothBottomSheetWrapper<T> extends StatefulWidget {
  const _SmoothBottomSheetWrapper({
    required this.routeAnimation,
    required this.builder,
    required this.isDismissible,
    required this.enableDrag,
    this.backgroundColor,
    this.maxHeight,
  });

  /// The route's own animation: it turns to reverse when the route pops.
  final Animation<double> routeAnimation;
  final WidgetBuilder builder;
  final bool isDismissible;
  final bool enableDrag;
  final Color? backgroundColor;
  final double? maxHeight;

  @override
  State<_SmoothBottomSheetWrapper<T>> createState() =>
      _SmoothBottomSheetWrapperState<T>();
}

/// The tallest the sheet may be: [maxHeight], held under the room between
/// the status bar and the keyboard (90% of it when [maxHeight] is null).
double _maxSheetHeight(BuildContext context, double? maxHeight) {
  final available = math.max(
    0.0,
    MediaQuery.sizeOf(context).height -
        MediaQuery.paddingOf(context).top -
        MediaQuery.viewInsetsOf(context).bottom,
  );
  return math.min(maxHeight ?? available * 0.9, available);
}

class _SmoothBottomSheetWrapperState<T>
    extends State<_SmoothBottomSheetWrapper<T>> {
  /// Where the springs are headed: 1 shown, 0 gone.
  double _shown = 0.0;

  /// How far a finger has pulled the sheet down.
  double _dragOffset = 0.0;
  bool _isDragging = false;
  bool _popped = false;

  /// The route is on its way out: the sheet slides away, taps pass through.
  bool _exiting = false;

  /// The glass and its content, built once: a drag or the slide moves it
  /// without building the content again.
  late Widget _panel = _buildPanel();

  Widget _buildPanel() => RepaintBoundary(
    child: _SheetPanel(
      builder: widget.builder,
      enableDrag: widget.enableDrag,
      backgroundColor: widget.backgroundColor,
      maxHeight: widget.maxHeight,
    ),
  );

  @override
  void initState() {
    super.initState();
    widget.routeAnimation.addStatusListener(_onRouteStatus);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_exiting) setState(() => _shown = 1.0);
    });
  }

  @override
  void didUpdateWidget(_SmoothBottomSheetWrapper<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.routeAnimation != widget.routeAnimation) {
      oldWidget.routeAnimation.removeStatusListener(_onRouteStatus);
      widget.routeAnimation.addStatusListener(_onRouteStatus);
    }
    if (oldWidget.builder != widget.builder ||
        oldWidget.enableDrag != widget.enableDrag ||
        oldWidget.backgroundColor != widget.backgroundColor ||
        oldWidget.maxHeight != widget.maxHeight) {
      _panel = _buildPanel();
    }
  }

  @override
  void dispose() {
    widget.routeAnimation.removeStatusListener(_onRouteStatus);
    super.dispose();
  }

  /// However the route was popped, the sheet slides out on its spring.
  void _onRouteStatus(AnimationStatus status) {
    if (status != AnimationStatus.reverse || _exiting || !mounted) return;
    setState(() {
      _exiting = true;
      _isDragging = false;
      _shown = 0.0;
    });
  }

  void _close([T? result]) {
    if (_popped || _exiting) return;
    _popped = true;
    Navigator.of(context).pop(result);
  }

  void _onDragStart(DragStartDetails details) {
    if (!widget.enableDrag || _exiting) return;
    _isDragging = true;
    _dragOffset = 0.0;
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (!widget.enableDrag || !_isDragging) return;
    setState(() {
      _dragOffset = (_dragOffset + details.delta.dy).clamp(0.0, 500.0);
    });
  }

  void _onDragEnd(DragEndDetails details) {
    if (!widget.enableDrag || !_isDragging) return;

    final velocity = details.velocity.pixelsPerSecond.dy;
    final shouldClose = _dragOffset > 100 || velocity > 500;

    if (shouldClose && widget.isDismissible) {
      // The slide out starts from where the finger let go.
      _isDragging = false;
      _close();
    } else {
      setState(() {
        _isDragging = false;
        _dragOffset = 0.0;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    final travel = _maxSheetHeight(context, widget.maxHeight);
    final scrim = glassSheetBarrier(context);

    // Under reduced motion a closed sheet is simply gone (kept in the tree,
    // so nothing inside is torn down before its route is).
    return Offstage(
      offstage: _exiting && reduceMotion,
      child: Stack(
        children: [
          // The scrim: a plain tint that fades in. Nothing blurs the page.
          Positioned.fill(
            child: GestureDetector(
              onTap: widget.isDismissible ? () => _close() : null,
              child: SingleMotionBuilder(
                motion: const SurfaceSpring(CupertinoMotion.smooth()),
                value: _shown,
                builder: (context, opacity, _) => ColoredBox(
                  color: scrim.withValues(
                    alpha: scrim.a * opacity.clamp(0.0, 1.0),
                  ),
                ),
              ),
            ),
          ),

          // The sheet. A tablet keeps it to a readable width.
          Positioned(
            left: 0,
            right: 0,
            bottom: keyboard,
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: ResponsiveHelper.isTablet ? 500.0 : double.infinity,
                ),
                child: GestureDetector(
                  onVerticalDragStart: _onDragStart,
                  onVerticalDragUpdate: _onDragUpdate,
                  onVerticalDragEnd: _onDragEnd,
                  child: SingleMotionBuilder(
                    // The sheet springs every sheet rides (MotionSheetRoute,
                    // showGlassModalBottomSheet): critically damped, so a
                    // tall sheet never overshoots and lifts its bottom edge
                    // off the screen, and the exit is the shorter one.
                    motion: _exiting ? _exitSlide : _entranceSlide,
                    value: _shown,
                    child: SingleMotionBuilder(
                      // Follows the finger; springs back if it lets go early.
                      motion: _isDragging
                          ? const LinearMotion(Duration(milliseconds: 1))
                          : const CupertinoMotion.snappy(),
                      value: _dragOffset,
                      child: _panel,
                      builder: (context, drag, panel) => Transform.translate(
                        offset: Offset(0, reduceMotion ? 0 : drag),
                        child: panel,
                      ),
                    ),
                    builder: (context, progress, panel) => Transform.translate(
                      offset: Offset(
                        0,
                        reduceMotion ? 0 : (1 - progress) * travel,
                      ),
                      child: panel,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The sheet itself: the glass, the drag handle, the content and the room
/// for the home indicator.
class _SheetPanel extends StatelessWidget {
  const _SheetPanel({
    required this.builder,
    required this.enableDrag,
    required this.backgroundColor,
    required this.maxHeight,
  });

  final WidgetBuilder builder;
  final bool enableDrag;
  final Color? backgroundColor;
  final double? maxHeight;

  @override
  Widget build(BuildContext context) {
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: _maxSheetHeight(context, maxHeight),
      ),
      child: Material(
        color: Colors.transparent,
        child: GlassSheet(
          radius: 20.br,
          tone: backgroundColor ?? context.colors.surface,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Drag handle
              if (enableDrag)
                Padding(
                  padding: EdgeInsets.only(top: 12.h, bottom: 8.h),
                  child: Container(
                    width: 36.w,
                    height: 4.h,
                    decoration: BoxDecoration(
                      // Paper needs a solid ink to clear 3:1 (30% ink reads
                      // ~1.9:1); dark keeps its original 30% white.
                      color: context.isLightTheme
                          ? context.colors.placeholder
                          : context.colors.textPrimary.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(2.br),
                    ),
                  ),
                ),
              // Content
              Flexible(
                child: MediaQuery.removeViewInsets(
                  context: context,
                  removeBottom: true,
                  child: Builder(builder: builder),
                ),
              ),
              // Safe area padding
              SizedBox(
                height: keyboard > 0
                    ? 0
                    : MediaQuery.viewPaddingOf(context).bottom,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
