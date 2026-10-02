import 'package:firebase_core/firebase_core.dart';

Future<FirebaseApp>? _initializing;

/// Remote Config and push share one native initialization, even at startup.
Future<FirebaseApp> ensureFirebaseInitialized() =>
    _initializing ??= _initialize();

Future<FirebaseApp> _initialize() async {
  try {
    return Firebase.apps.isEmpty
        ? await Firebase.initializeApp()
        : Firebase.app();
  } catch (_) {
    _initializing = null;
    rethrow;
  }
}
