import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

class LifecycleEventHandler extends WidgetsBindingObserver {
  final AsyncCallback? onAppExit;
  final AsyncCallback? onAppResume;

  LifecycleEventHandler({this.onAppExit, this.onAppResume});

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // IMPORTANT: `inactive` can be a transient transition state (for example
    // during notification taps). Treat only paused/detached as true background.
    if (state == AppLifecycleState.detached ||
        state == AppLifecycleState.paused) {
      onAppExit?.call();
    } else if (state == AppLifecycleState.resumed) {
      onAppResume?.call();
    }
  }
}
