import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Makes Android and iOS read the same two accessibility signals, so the
/// app's motion (the scroll-away bars, the search morph, every spring) plays
/// the same on every phone.
///
/// * Reduced motion ([MediaQueryData.disableAnimations]) always reads false.
///   Android reports it whenever the transition animation scale is 0, which
///   many OEM battery savers set without the reader asking. Product decision
///   (2026-11-20): the app looks the same on every phone.
/// * A screen reader ([MediaQueryData.accessibleNavigation]) on Android is
///   whether touch exploration (TalkBack and its kin) is on, asked of the
///   system ([kTouchExplorationChannel]). Flutter's own flag turns on, and
///   stays on, the first time ANY accessibility service reads the view tree
///   (password managers, OEM helpers, launchers, automation apps), so on
///   many Android phones it was true with no screen reader running and the
///   scroll-away bars never moved (PM's phone, 38.21.0). iOS reports it only
///   for VoiceOver, so iOS keeps the system's value.
class AppMotionAlwaysOn extends StatefulWidget {
  const AppMotionAlwaysOn({super.key, required this.child});

  final Widget child;

  @override
  State<AppMotionAlwaysOn> createState() => _AppMotionAlwaysOnState();
}

/// The Android channel answering whether touch exploration is on
/// (`TouchExplorationBridge.kt`).
const MethodChannel kTouchExplorationChannel = MethodChannel(
  'com.chessever/touch_exploration',
);

class _AppMotionAlwaysOnState extends State<AppMotionAlwaysOn> {
  /// Touch exploration on Android; false until the system answers (and
  /// where it cannot).
  bool _touchExploration = false;

  static bool get _android =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  void initState() {
    super.initState();
    if (!_android) return;
    kTouchExplorationChannel.setMethodCallHandler(_onCall);
    _ask();
  }

  Future<void> _ask() async {
    try {
      final on = await kTouchExplorationChannel.invokeMethod<bool>(
        'touchExploration',
      );
      _set(on ?? false);
    } on MissingPluginException {
      // No bridge (tests, an engine without the activity): no screen reader.
    } on PlatformException catch (error) {
      debugPrint('[AppMotion] touch exploration unknown: $error');
    }
  }

  Future<void> _onCall(MethodCall call) async {
    if (call.method == 'touchExplorationChanged') {
      _set(call.arguments == true);
    }
  }

  void _set(bool on) {
    if (!mounted || on == _touchExploration) return;
    setState(() => _touchExploration = on);
  }

  @override
  void dispose() {
    if (_android) kTouchExplorationChannel.setMethodCallHandler(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = MediaQuery.of(context);
    final screenReader = _android
        ? _touchExploration
        : data.accessibleNavigation;
    if (!data.disableAnimations && screenReader == data.accessibleNavigation) {
      return widget.child;
    }
    return MediaQuery(
      data: data.copyWith(
        disableAnimations: false,
        accessibleNavigation: screenReader,
      ),
      child: widget.child,
    );
  }
}
