# CodeMagic Environment Variables Setup

## Summary of Changes

We've updated the codebase to support two modes of environment variable loading:

1. **Debug Mode (Local Development)**: Uses `.env` file via `flutter_dotenv`
2. **Production Mode (CodeMagic CI/CD)**: Uses environment variables directly via `String.fromEnvironment()`

## Files Modified

1. **lib/main.dart**
   - Added `_getEnv()` helper function
   - Updated all `dotenv.env['KEY']` to `_getEnv('KEY')`
   - Conditional `.env` file loading (only in debug mode)

2. **lib/repository/authentication/auth_repository.dart**
   - Updated `_env()` method to use conditional logic

3. **lib/repository/supabase/supabase.dart**
   - Added `_getEnv()` helper function
   - Updated supabaseProvider to use new helper

## CodeMagic Configuration

### Environment Variables Already Defined in CodeMagic Dashboard

You've already defined these in your CodeMagic dashboard:

```
SUPABASE_URL=https://oelbsuggrzyqwzmvidju.supabase.co
SUPABASE_ANON_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im9lbGJzdWdncnp5cXd6bXZpZGp1Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NDk5MDgyODYsImV4cCI6MjA2NTQ4NDI4Nn0.YpIEGIVCN2yUmh4ALnuF0i4jKI3ld1VHNVSCN2J7R30
GOOGLE_WEB_CLIENT_ID=816845608736-6fskv7m8sssl2j8a6u6o5lgm162et6qj.apps.googleusercontent.com
GOOGLE_IOS_CLIENT_ID=816845608736-cpurkpq34aqt33e0jsf9pjpto2lql28v.apps.googleusercontent.com
GOOGLE_ANDROID_CLIENT_ID=816845608736-smg45le1m7h14j69thltqlipkcu9fimt.apps.googleusercontent.com
RevenueCatAPIKey=goog_ZmINjxirbMFvSsVMUfviZwrpfBY
APPLE_SERVICE_ID=com.chessever.app
APPLE_REDIRECT_URI=https://oelbsuggrzyqwzmvidju.supabase.co/auth/v1/callback
APPLE_BUNDLE_ID=com.chessever.app
SENTRY_FLUTTER=https://0f28d9f10d332be4a7487bc7b6901f51@o4508880436330496.ingest.de.sentry.io/4510106971734096
AMPLITUDE=c19481babdae8a9f2d4c20b9bacecfb3
CLARITY_PROJECT_ID=to1z6pg0bz
```

### How to Use in CodeMagic Build Script

In your `codemagic.yaml`, you need to pass these environment variables as compile-time constants using `--dart-define`:

```yaml
workflows:
  android-workflow:
    name: Android Workflow
    environment:
      groups:
        - your_env_group_name  # Reference your environment group
    scripts:
      - name: Build Android
        script: |
          flutter build apk --release \
            --dart-define=SUPABASE_URL="$SUPABASE_URL" \
            --dart-define=SUPABASE_ANON_KEY="$SUPABASE_ANON_KEY" \
            --dart-define=GOOGLE_WEB_CLIENT_ID="$GOOGLE_WEB_CLIENT_ID" \
            --dart-define=RevenueCatAPIKey="$RevenueCatAPIKey" \
            --dart-define=APPLE_SERVICE_ID="$APPLE_SERVICE_ID" \
            --dart-define=APPLE_REDIRECT_URI="$APPLE_REDIRECT_URI" \
            --dart-define=APPLE_BUNDLE_ID="$APPLE_BUNDLE_ID" \
            --dart-define=SENTRY_FLUTTER="$SENTRY_FLUTTER" \
            --dart-define=AMPLITUDE="$AMPLITUDE" \
            --dart-define=CLARITY_PROJECT_ID="$CLARITY_PROJECT_ID"

  ios-workflow:
    name: iOS Workflow
    environment:
      groups:
        - your_env_group_name
    scripts:
      - name: Build iOS
        script: |
          flutter build ipa --release \
            --dart-define=SUPABASE_URL="$SUPABASE_URL" \
            --dart-define=SUPABASE_ANON_KEY="$SUPABASE_ANON_KEY" \
            --dart-define=GOOGLE_WEB_CLIENT_ID="$GOOGLE_WEB_CLIENT_ID" \
            --dart-define=RevenueCatAPIKey="$RevenueCatAPIKey" \
            --dart-define=APPLE_SERVICE_ID="$APPLE_SERVICE_ID" \
            --dart-define=APPLE_REDIRECT_URI="$APPLE_REDIRECT_URI" \
            --dart-define=APPLE_BUNDLE_ID="$APPLE_BUNDLE_ID" \
            --dart-define=SENTRY_FLUTTER="$SENTRY_FLUTTER" \
            --dart-define=AMPLITUDE="$AMPLITUDE" \
            --dart-define=CLARITY_PROJECT_ID="$CLARITY_PROJECT_ID"
```

## How It Works

### Debug Mode (Local Development)
```dart
// When kDebugMode == true
String _getEnv(String key) {
  final value = dotenv.env[key];  // Reads from .env file
  if (value == null || value.isEmpty) {
    throw Exception('Missing env variable in .env file: $key');
  }
  return value;
}
```

### Production Mode (CodeMagic)
```dart
// When kDebugMode == false
String _getEnv(String key) {
  return String.fromEnvironment(key);  // Reads from --dart-define
}
```

## Testing Locally

1. **Debug Mode**: Just run normally
   ```bash
   flutter run
   ```
   This will use your `.env` file.

2. **Production Mode**: Test with dart-define
   ```bash
   flutter run --release \
     --dart-define=SUPABASE_URL="https://oelbsuggrzyqwzmvidju.supabase.co" \
     --dart-define=SUPABASE_ANON_KEY="your_key_here" \
     # ... add all other variables
   ```

## Security Notes

1. ✅ `.env` file should remain in `.gitignore`
2. ✅ Environment variables in CodeMagic are encrypted and secure
3. ✅ Production builds don't include `.env` file
4. ✅ All secrets are injected at compile time via `--dart-define`

## Environment Variables Used by Each Service

- **Supabase**: SUPABASE_URL, SUPABASE_ANON_KEY
- **Google Sign-In**: GOOGLE_WEB_CLIENT_ID
- **Apple Sign-In**: APPLE_SERVICE_ID, APPLE_REDIRECT_URI, APPLE_BUNDLE_ID
- **RevenueCat**: RevenueCatAPIKey
- **Sentry**: SENTRY_FLUTTER
- **Amplitude**: AMPLITUDE
- **Clarity**: CLARITY_PROJECT_ID
