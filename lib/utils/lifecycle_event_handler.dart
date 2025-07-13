import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

class LifecycleEventHandler extends WidgetsBindingObserver {
  final AsyncCallback? onAppExit;

  LifecycleEventHandler({this.onAppExit});

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      onAppExit?.call();
    }
  }
}
