# Splash Screen Hang Fix

## Issue
Users on Android were reporting that the app gets stuck at the splash screen. Clearing the app cache resolved the issue. This indicated a problem with local storage initialization or processing during startup.

## Root Cause
The `main()` function in `lib/main.dart` contained a `Future.wait` block that included `_clearEvaluationCache()`. This function iterates over all keys in `SharedPreferences` matching the `cloud_eval_` prefix and removes them one by one using `await`.

```dart
      // Find and remove all evaluation cache entries
      final keys = prefs.getKeys().where((k) => k.startsWith(evalPrefix));
      int removedCount = 0;

      for (final key in keys) {
        await prefs.remove(key);
        removedCount++;
      }
```

For users with a large number of cached evaluations (potentially thousands), this synchronous-like iteration (even with `await`) takes a significant amount of time, preventing `runApp()` from being called and leaving the user stuck on the native splash screen.

## Fix
The `_clearEvaluationCache()` function (and `_resetFavoritesForMigration()`) was removed from the blocking `Future.wait` call in `main()`. Instead, it is now called using `unawaited()`, allowing it to run in the background while the app continues to initialize and render the UI.

```dart
      // Clear evaluation cache in background (don't block startup)
      unawaited(_clearEvaluationCache());

      // Parallelize all critical initialization tasks
      await Future.wait([
        // ... other critical tasks ...
      ]);
```

## Verification
- Code analysis confirms `_clearEvaluationCache` is no longer blocking `runApp`.
- `unawaited` ensures the future is executed but not waited for.
- `SharedPreferencesService.instance.initialize()` remains the first critical step to ensure `prefs` is available.
