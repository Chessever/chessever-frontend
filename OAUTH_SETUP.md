# OAuth Configuration Guide for ChessEver

Complete guide to configure Google Sign In (Android + iOS) and Apple Sign In (iOS) with Supabase.

---

## 📱 What You'll Get

- **iOS**: Apple Sign In + Google Sign In (2 buttons)
- **Android**: Google Sign In (1 button)

---

## 🔑 Part 1: Google Cloud Console Configuration

### Step 1: Create/Access Google Cloud Project

1. Go to [Google Cloud Console](https://console.cloud.google.com/)
2. Select your existing project or create a new one
3. Enable **Google+ API** (if not already enabled)

### Step 2: Create OAuth 2.0 Credentials

You need **3 OAuth clients**:

#### A. Web Application (for Supabase)

1. **APIs & Services** → **Credentials** → **Create Credentials** → **OAuth 2.0 Client ID**
2. Application type: **Web application**
3. Name: `ChessEver Web Client`
4. Authorized redirect URIs:
   ```
   https://YOUR_SUPABASE_PROJECT_REF.supabase.co/auth/v1/callback
   ```
   (Replace `YOUR_SUPABASE_PROJECT_REF` with your actual Supabase project reference)

5. **Create** → Save the **Client ID** → This is your `GOOGLE_WEB_CLIENT_ID`

#### B. iOS Application

1. **Create Credentials** → **OAuth 2.0 Client ID**
2. Application type: **iOS**
3. Name: `ChessEver iOS Client`
4. Bundle ID: `com.chessever.app` (or your actual bundle ID)
5. **Create** → Save the **Client ID** → This is your `GOOGLE_IOS_CLIENT_ID`

#### C. Android Application (if you don't have one)

1. **Create Credentials** → **OAuth 2.0 Client ID**
2. Application type: **Android**
3. Name: `ChessEver Android Client`
4. Package name: `com.chessEver.app`
5. SHA-1 certificate fingerprint:
   ```bash
   # Get your debug SHA-1
   keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey -storepass android -keypass android

   # Get your release SHA-1 (when you have release keystore)
   keytool -list -v -keystore /path/to/your/release.keystore -alias your-alias
   ```
6. **Create**

---

## 🔵 Part 2: Supabase Dashboard Configuration

### Step 1: Enable Google Provider

1. Go to [Supabase Dashboard](https://app.supabase.com/)
2. Select your project
3. **Authentication** → **Providers** → **Google**
4. Toggle **Enable Sign in with Google**
5. Paste your credentials:
   - **Client ID (for OAuth)**: `GOOGLE_WEB_CLIENT_ID` (from Google Cloud Console - Web Application)
   - **Client Secret (for OAuth)**: `GOOGLE_WEB_CLIENT_SECRET` (from Google Cloud Console - Web Application)
6. **Authorized Client IDs**: Add both iOS and Android client IDs (comma-separated):
   ```
   YOUR_GOOGLE_IOS_CLIENT_ID,YOUR_GOOGLE_ANDROID_CLIENT_ID
   ```
7. **Save**

### Step 2: Enable Apple Provider (iOS only)

1. **Authentication** → **Providers** → **Apple**
2. Toggle **Enable Sign in with Apple**
3. Configure (see Part 4 for Apple Developer setup):
   - **Services ID**: Your Apple Services ID
   - **Secret Key**: Generated from Apple Developer
   - **Key ID**: From Apple Developer
   - **Team ID**: Your Apple Developer Team ID
4. **Authorized Client IDs**: Same as Services ID
5. **Save**

---

## 🍎 Part 3: Apple Developer Configuration (iOS Only)

### Step 1: Register App ID

1. Go to [Apple Developer](https://developer.apple.com/account/)
2. **Certificates, Identifiers & Profiles** → **Identifiers** → **+**
3. Select **App IDs** → **Continue**
4. Type: **App**
5. Description: `ChessEver`
6. Bundle ID: `com.chessever.app`
7. **Capabilities**: Check **Sign In with Apple**
8. **Continue** → **Register**

### Step 2: Create Services ID

1. **Identifiers** → **+**
2. Select **Services IDs** → **Continue**
3. Description: `ChessEver Sign In`
4. Identifier: `com.chessever.app.signin` (This is your `APPLE_SERVICE_ID`)
5. **Continue** → **Register**
6. Click on the newly created Services ID
7. Check **Sign In with Apple**
8. **Configure**:
   - **Primary App ID**: Select `com.chessever.app`
   - **Domains and Subdomains**: `YOUR_SUPABASE_PROJECT_REF.supabase.co`
   - **Return URLs**: `https://YOUR_SUPABASE_PROJECT_REF.supabase.co/auth/v1/callback`
9. **Save** → **Continue** → **Register**

### Step 3: Create Sign In with Apple Key

1. **Keys** → **+**
2. Key Name: `ChessEver Sign In Key`
3. Check **Sign In with Apple**
4. **Configure** → Select your primary App ID → **Save**
5. **Continue** → **Register**
6. **Download** the `.p8` file (you can only download once!)
7. Note the **Key ID** (e.g., `AB12CD34EF`)

### Step 4: Get Apple Credentials

You'll need these for `.env`:
- **Services ID**: `com.chessever.app.signin`
- **Key ID**: From Step 3 (e.g., `AB12CD34EF`)
- **Team ID**: Found in top-right of Apple Developer (e.g., `XYZ1234ABC`)
- **Private Key**: Content of the downloaded `.p8` file

---

## 📱 Part 4: iOS Native Configuration

### Step 1: Update Info.plist

Add Google Sign In URL scheme:

```xml
<!-- Add inside the existing <dict> tag in Info.plist -->

<!-- Google Sign In URL Scheme -->
<key>CFBundleURLTypes</key>
<array>
    <!-- Existing URL schemes -->
    <dict>
        <key>CFBundleURLName</key>
        <string>com.chessever.app</string>
        <key>CFBundleURLSchemes</key>
        <array>
            <string>com.chessever.app</string>
        </array>
    </dict>

    <!-- ADD THIS: Google Sign In URL Scheme -->
    <dict>
        <key>CFBundleTypeRole</key>
        <string>Editor</string>
        <key>CFBundleURLSchemes</key>
        <array>
            <!-- This is your REVERSED Google iOS Client ID -->
            <string>com.googleusercontent.apps.YOUR-IOS-CLIENT-ID-HERE</string>
        </array>
    </dict>
</array>

<!-- ADD THIS: Google Sign In Client ID -->
<key>GIDClientID</key>
<string>YOUR_GOOGLE_IOS_CLIENT_ID.apps.googleusercontent.com</string>

<!-- ADD THIS: Google Sign In Server Client ID -->
<key>GIDServerClientID</key>
<string>YOUR_GOOGLE_WEB_CLIENT_ID.apps.googleusercontent.com</string>
```

**How to get reversed Client ID:**
If your iOS Client ID is `123456789-abc123.apps.googleusercontent.com`, the reversed is:
```
com.googleusercontent.apps.123456789-abc123
```

---

## 🤖 Part 5: Android Native Configuration

### Option A: If you already have `google-services.json`

✅ You're all set! The Android client ID comes from this file.

### Option B: If you DON'T have `google-services.json`

1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Add/Select your project
3. Add Android app
4. Package name: `com.chessEver.app`
5. Download `google-services.json`
6. Place it in `android/app/google-services.json`

### Update AndroidManifest.xml

No changes needed! The `google-services.json` handles everything.

---

## 🔐 Part 6: Environment Variables

Update your `.env` file:

```env
# Supabase
SUPABASE_URL=https://YOUR_PROJECT_REF.supabase.co
SUPABASE_ANON_KEY=your_supabase_anon_key

# Google OAuth
GOOGLE_WEB_CLIENT_ID=YOUR_WEB_CLIENT_ID.apps.googleusercontent.com
GOOGLE_IOS_CLIENT_ID=YOUR_IOS_CLIENT_ID.apps.googleusercontent.com

# Apple OAuth (iOS only)
APPLE_SERVICE_ID=com.chessever.app.signin
APPLE_REDIRECT_URI=https://YOUR_PROJECT_REF.supabase.co/auth/v1/callback

# Analytics
AMPLITUDE=your_amplitude_key
SENTRY_FLUTTER=your_sentry_dsn
CLARITY_PROJECT_ID=your_clarity_id
```

### Update CodeMagic Build Settings

Add these as environment variables in CodeMagic:
- `GOOGLE_WEB_CLIENT_ID`
- `GOOGLE_IOS_CLIENT_ID`
- `APPLE_SERVICE_ID`
- `APPLE_REDIRECT_URI`

---

## ✅ Testing Checklist

### iOS Testing
- [ ] Google Sign In works
- [ ] Apple Sign In works
- [ ] Both buttons appear
- [ ] Session persists after app restart
- [ ] Logout works for both providers

### Android Testing
- [ ] Google Sign In works
- [ ] Only Google button appears
- [ ] Session persists after app restart
- [ ] Logout works

---

## 🐛 Common Issues & Solutions

### Issue: "Invalid client" error on iOS Google Sign In
**Solution**: Check that `GOOGLE_IOS_CLIENT_ID` in `.env` matches the iOS Client ID in Google Cloud Console

### Issue: "Failed to get Google tokens"
**Solution**:
1. Verify reversed Client ID in Info.plist matches your iOS Client ID
2. Check `GIDClientID` and `GIDServerClientID` in Info.plist

### Issue: Apple Sign In shows "Invalid credentials"
**Solution**:
1. Verify Services ID matches `APPLE_SERVICE_ID` in `.env`
2. Check return URLs in Apple Developer match Supabase callback URL
3. Ensure `.p8` key is correctly configured in Supabase

### Issue: "Authorized Client IDs" error
**Solution**: Add both iOS and Android Client IDs to Supabase's "Authorized Client IDs" field (comma-separated)

### Issue: Android Google Sign In fails
**Solution**:
1. Verify `google-services.json` exists in `android/app/`
2. Check SHA-1 fingerprint is added to Google Cloud Console
3. Run `flutter clean && flutter pub get`

---

## 📋 Quick Reference

| Platform | Providers Available |
|----------|-------------------|
| **iOS** | Google + Apple |
| **Android** | Google only |

| Config File | Purpose |
|-------------|---------|
| `Info.plist` | iOS Google + Apple URL schemes |
| `google-services.json` | Android Google Sign In |
| `.env` | All OAuth credentials |

---

## 🎉 You're Done!

Run the app and test authentication on both platforms!
