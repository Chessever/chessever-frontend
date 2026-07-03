import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Bumped once per app foreground-resume, after the first resumed frame
/// (see the LifecycleEventHandler wiring in main.dart).
///
/// Data owners that must catch up on server state that changed while the app
/// was backgrounded (event lists, live-id snapshots) listen to this signal
/// instead of each registering its own WidgetsBindingObserver.
final appResumedSignalProvider = StateProvider<int>((ref) => 0);
