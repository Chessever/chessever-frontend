# Google OAuth Production Setup Verification

## 1. Release Keystore SHA-1
```bash
keytool -list -v -keystore android/my-release-key.jks -alias my-key-alias -storepass HelloChessever | grep SHA1
```
**Expected:** `DC:83:1A:5D:5C:F3:77:62:9A:BE:C4:6A:F3:D5:09:10:03:45:A9:F9`

## 2. Google Cloud Console Checklist

### Navigate to: https://console.cloud.google.com/apis/credentials

### Find OAuth 2.0 Client ID: `882734779574-9ajudu3cqv1v6qc1edcasldc7ac3e50l.apps.googleusercontent.com`

Verify:
- [ ] Type: **Android**
- [ ] Package name: `com.chessEver.app`
- [ ] SHA-1: `DC:83:1A:5D:5C:F3:77:62:9A:BE:C4:6A:F3:D5:09:10:03:45:A9:F9`

### Find Web OAuth 2.0 Client ID: `882734779574-0qk635jlqrbp9qhenmau7pd6bffiag2j.apps.googleusercontent.com`

Verify:
- [ ] Type: **Web application**
- [ ] Exists and is enabled

## 3. Enable Required APIs

Navigate to: https://console.cloud.google.com/apis/library

Enable:
- [ ] Google Sign-In API (or Google Identity API)
- [ ] Google People API

## 4. OAuth Consent Screen

Navigate to: https://console.cloud.google.com/apis/credentials/consent

Verify:
- [ ] App name is set
- [ ] User support email is set
- [ ] Scopes include `email` and `profile`
- [ ] Publishing status: **Published** (not Testing)
  - OR if Testing: Add test users

## 5. CodeMagic Environment Variables

Verify in CodeMagic dashboard:
- [ ] `GOOGLE_ANDROID_CLIENT_ID` = `882734779574-9ajudu3cqv1v6qc1edcasldc7ac3e50l.apps.googleusercontent.com`
- [ ] `GOOGLE_WEB_CLIENT_ID` = `882734779574-0qk635jlqrbp9qhenmau7pd6bffiag2j.apps.googleusercontent.com`
- [ ] `GOOGLE_IOS_CLIENT_ID` = `882734779574-8v68and9jcueedkvk0dl2ftse6dn8kt3.apps.googleusercontent.com`

## 6. Build Configuration

Verify CodeMagic build script includes:
```bash
--dart-define=GOOGLE_ANDROID_CLIENT_ID=$GOOGLE_ANDROID_CLIENT_ID \
--dart-define=GOOGLE_WEB_CLIENT_ID=$GOOGLE_WEB_CLIENT_ID \
--dart-define=GOOGLE_IOS_CLIENT_ID=$GOOGLE_IOS_CLIENT_ID
```

## 7. Test Locally with Production Config

```bash
flutter build apk --release \
  --dart-define=GOOGLE_ANDROID_CLIENT_ID=882734779574-9ajudu3cqv1v6qc1edcasldc7ac3e50l.apps.googleusercontent.com \
  --dart-define=GOOGLE_WEB_CLIENT_ID=882734779574-0qk635jlqrbp9qhenmau7pd6bffiag2j.apps.googleusercontent.com \
  --dart-define=GOOGLE_IOS_CLIENT_ID=882734779574-8v68and9jcueedkvk0dl2ftse6dn8kt3.apps.googleusercontent.com
```

Install on device and test Google Sign-In.

## Common Issues

### Issue: "Developer console is not set up correctly"
**Cause:** SHA-1 certificate not registered or wrong package name
**Fix:** Double-check SHA-1 matches exactly in GCP Android client

### Issue: OAuth works in debug but not production
**Cause:** Debug SHA-1 registered but not release SHA-1
**Fix:** Add release SHA-1 to production Android client ID

### Issue: "Access blocked: This app's request is invalid"
**Cause:** OAuth consent screen not published
**Fix:** Publish the OAuth consent screen or add test users

### Issue: Silent failure with no error
**Cause:** Wrong client ID in environment variables
**Fix:** Verify CodeMagic is using production client ID

## After Fixing

1. Update Google Cloud Console configuration
2. Wait 5-10 minutes for changes to propagate
3. Build new release in CodeMagic
4. Test on real device
