import 'dart:async';
import 'dart:ui';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

enum InterpolationConfig {
  fidelity, // Higher sync with keyboard system animation
  safe, // More conservative, less precise (similar to X and FB)
}

/// Tracks the system keyboard height and provides it to a builder.
///
/// The `builder` receives the current keyboard height (in logical pixels)
/// and rebuilds whenever the keyboard moves, keeping its widget smoothly
/// in sync with the keyboard animation.
///
/// Optionally, `onChange` can be used for side effects.
///
/// When a `FocusNode` is provided, this widget also integrates a
/// `KeyboardPerformanceHandler` that automatically adjusts Dart
/// performance mode:
/// - Prioritizes frame latency (`DartPerformanceMode.latency`) while
///   the keyboard is animating or the text field is focused, improving
///   smoothness during typing and keyboard transitions.
/// - Latency mode is triggered **only once per state transition**:
///   when the keyboard opens or the text field gains focus,
///   and reverted when the keyboard closes or focus is lost.
/// - Reverts to balanced mode (`DartPerformanceMode.balanced`) when
///   the keyboard is closed and the text field loses focus.
///
/// Wrap heavy subtrees in `RepaintBoundary` for performance.
/// Note: keyboard animation smoothness must be observed in release mode.
///
/// Additionally, the optional `warmUpFrame` parameter can schedule a
/// warm-up frame, which runs as soon as possible to pre-render layouts
/// and shaders before keyboard animations start. Useful to prevent the first
/// frame from stuttering due to expensive layout calculations.
///
/// When `interpolateLastPart` is enabled, the final segment of the keyboard
/// animation is interpolated smoothly.
/// This is required on iOS when using a Native TextField (PlatformView),
/// because Flutter cannot reproduce the small wiggles at the end of the
/// keyboard animation when PlatformViews are present.
/// Enabling this prevents micro-bumps by producing a smooth final transition.
class KeyboardAnimationBuilder extends StatefulWidget {
  final Widget Function(BuildContext context, double keyboardHeight) builder;
  final void Function(double keyboardHeight)? onChange;
  final FocusNode? focusNode;
  final double keyboardTotalHeight;
  final bool interpolateLastPart;
  final bool warmUpFrame; // optional: warm-up first frame
  final InterpolationConfig interpolationConfig;

  const KeyboardAnimationBuilder({
    super.key,
    required this.builder,
    this.onChange,
    this.focusNode,
    required this.keyboardTotalHeight,
    required this.interpolateLastPart,
    this.interpolationConfig = InterpolationConfig.fidelity,
    this.warmUpFrame = true, // Experimental: whether to pre-render a frame to potentially improve initial performance
  });

  @override
  State<KeyboardAnimationBuilder> createState() =>
      _KeyboardAnimationBuilderState();
}

class _KeyboardAnimationBuilderState extends State<KeyboardAnimationBuilder>
    with WidgetsBindingObserver {
  final ValueNotifier<double> _keyboardHeightNotifier =
      ValueNotifier<double>(0.0);
  // Hidden focus node for off-screen warm-up
  final FocusNode _hiddenFocusNode = FocusNode();
  late Curve _animationCurve;
  late double interpolationStart;

  // Initialize performance handler if a focusNode is provided
  late final _performanceHandler = widget.focusNode != null
      ? KeyboardPerformanceHandler(focusNode: widget.focusNode!)
      : null;

  @override
  void initState() {
    super.initState();
    // Observe metrics changes to detect keyboard height changes
    WidgetsBinding.instance.addObserver(this);

    // Set the configuration used to interpolate the last part of the animation.
    _configureInterpolation();

    // Optional: schedule a warm-up frame to pre-render layouts
    if (widget.warmUpFrame) {
      SchedulerBinding.instance.scheduleWarmUpFrame();
    }
  }

  /// Sets the interpolation start and animation curve based on the current configuration.
  /// - InterpolationConfig.fidelity:
  ///   - Interpolates only the very last part of the animation
  ///   - Ensures the best fidelity with keyboard animation
  ///   - Introduces occasionally micro-bumps due to Flutter engine
  ///
  /// - InterpolationConfig.safe:
  ///   - Interpolate the last 20-30% portion of the animation
  ///   - Less fidelity with the system keyboard animation (similar to X or FB)
  ///   - Minor micro-bumps may still occur, but they are rare
  void _configureInterpolation() {
    switch (widget.interpolationConfig) {
      case InterpolationConfig.safe:
        interpolationStart = 0.6; // 60% of total height
        // or 70%
        _animationCurve = const Cubic(0.5, 0.80, 0.9, 1);
        break;
      case InterpolationConfig.fidelity:
        interpolationStart = 0.7; // 70% linear interpolation
        _animationCurve = Curves.linear;
        break;
      default:
        interpolationStart = 0; // Fallback to a total interpolation
        _animationCurve = const Cubic(0.46, 0.60, 0.9, 1);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _performanceHandler?.dispose();
    _hiddenFocusNode.dispose();
    _keyboardHeightNotifier.dispose();
    super.dispose();
  }

  @override
  Future<void> didChangeMetrics() async {
    final view = View.of(context);
    final newHeightRaw = view.viewInsets.bottom / view.devicePixelRatio;
    bool isFocused = widget.focusNode?.hasFocus ?? true; // default true if no focusNode

    // Round to nearest 0.5px to avoid sub-pixel bumps caused by rendering
    // tiny floating-point fluctuations (sub-0.5px) that are inconsistent across frames.
    // Note: From logs, keyboard height changes like this:
    // 334.084998 → 334.325097 → 334.535569 → 334.719998 → 334.881534 → 335.022973
    // When we round, the values become 334.0 → 334.5 → 335.0
    double newHeight;
    if (isFocused) {
      // Keyboard opening → round UP
      newHeight = (newHeightRaw * 2).ceil() / 2;
    } else {
      // Keyboard closing → round DOWN
      newHeight = (newHeightRaw * 2).floor() / 2;
    }

    // Enable on iOS when a Native TextField (PlatformView) is present.
    // Interpolates the final segment of the keyboard animation to prevent micro-bumps.
    // Note: This complements the Main Debounce updates.
    var progress;
    if (widget.interpolateLastPart) {
      // Smoothly interpolate the last part of the animation
      if (newHeight >= (widget.keyboardTotalHeight * interpolationStart)) {
        double startHeight = widget.keyboardTotalHeight * interpolationStart;
        // Prevent division by zero
        final double denom = widget.keyboardTotalHeight - startHeight;
        progress = denom.abs() < 0.0001 ? 1.0 : (newHeight - startHeight) / denom;

        // Apply a curves
        final curve = _animationCurve;
        //Cubic(0.46, 0.70, 0.9, 1)
        //Cubic(0.46, 0.60, 1, 1)
        //Cubic(0.16, 1.0, 0.3, 1.0);
        //Curves.easeOutSine;
        //Curves.easeOutCubic;

        final smoothedProgress = curve.transform(progress.clamp(0.0, 1.0));

        newHeight = progress < 1.0
            ? startHeight +
                smoothedProgress * (widget.keyboardTotalHeight - startHeight)
            : progress == 1
                ? widget.keyboardTotalHeight
                : newHeight;

        updateKeyboardHeight(newHeight);
      }
    }

    // When interpolating the final portion of the animation, only update the height
    // if the interpolation hasn't fully completed (progress < 1.0).
    if (!widget.interpolateLastPart ||
        widget.interpolateLastPart && progress != 1.0) {
      updateKeyboardHeight(newHeight);
    }
  }

  // Update UI and ValueNotifier with adjusted height
  void updateKeyboardHeight(double newHeight) {
    if (_keyboardHeightNotifier.value != newHeight) {
      _keyboardHeightNotifier.value = newHeight;
      widget.onChange?.call(newHeight);
      _performanceHandler?.onKeyboardHeightChanged(newHeight);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: _keyboardHeightNotifier,
      builder: (context, height, child) {
        return widget.builder(context, height);
        /*
        // By adding the Stack + off-screen widget, the engine does a tiny
        // render pass early, which indirectly might help prevent occasional
        // stutters during the first keyboard animation
        return Stack(
          children: [
            widget.builder(context, height),
            Positioned(
              left: -1000,
              top: -1000,
              child: SizedBox(width: 1, height: 1),
            ),
          ],
        );
        */
      },
    );
  }
}

/// Handles Dart performance mode based on keyboard animation and focus.
class KeyboardPerformanceHandler {
  final FocusNode focusNode;
  bool _wasKeyboardClosed = true;

  KeyboardPerformanceHandler({required this.focusNode}) {
    // Listen to focus changes
    focusNode.addListener(_handleFocusChange);
  }

  void dispose() {
    focusNode.removeListener(_handleFocusChange);
    _setBalancedMode();
  }

  void onKeyboardHeightChanged(double keyboardHeight) {
    // Detect start/end of keyboard animation
    if (keyboardHeight > 0 && _wasKeyboardClosed) {
      _wasKeyboardClosed = false;
      _setLatencyMode();
    } else if (keyboardHeight == 0 && !_wasKeyboardClosed) {
      _wasKeyboardClosed = true;
      _setBalancedMode();
    }
  }

  void _handleFocusChange() {
    // Prioritize latency while typing
    if (focusNode.hasFocus) {
      _setLatencyMode();
    } else if (_wasKeyboardClosed) {
      _setBalancedMode();
    }
  }

  void _setLatencyMode() {
    // Prioritize frame latency (smoothness) for keyboard animation or typing
    PlatformDispatcher.instance
        .requestDartPerformanceMode(DartPerformanceMode.latency);
  }

  void _setBalancedMode() {
    // Return to balanced mode for normal operation
    PlatformDispatcher.instance
        .requestDartPerformanceMode(DartPerformanceMode.balanced);
  }
}
