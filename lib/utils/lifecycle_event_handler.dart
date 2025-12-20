import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

class LifecycleEventHandler extends WidgetsBindingObserver {
  final AsyncCallback? onAppExit;
  final AsyncCallback? onAppResume;

  LifecycleEventHandler({this.onAppExit, this.onAppResume});

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      onAppExit?.call();
    } else if (state == AppLifecycleState.resumed) {
      onAppResume?.call();
    }
  }
}
