# OAuth Redirect URI Configuration Checklist

## Your Supabase Auth Callback URL
```
https://oelbsuggrzyqwzmvidju.supabase.co/auth/v1/callback
```

---

## ✅ 1. Mobile App Code (auth_repository.dart)

### Current Status: CORRECT ✅

**Apple Sign-In (Android only):**
- Line 223: `redirectUri: Uri.parse(_env('APPLE_REDIRECT_URI'))`
- Uses: `https://oelbsuggrzyqwzmvidju.supabase.co/auth/v1/callback`
- Status: ✅ CORRECT

**Google Sign-In:**
- NO redirect URI needed in mobile code
- The Google Sign-In SDK handles this internally
- Status: ✅ CORRECT

---

## 🔧 2. Google Cloud Console Configuration

**Location:** https://console.cloud.google.com/

### Web Client (GOOGLE_WEB_CLIENT_ID)
**Client ID:** `816845608736-6fskv7m8sssl2j8a6u6o5lgm162et6qj.apps.googleusercontent.com`

**Required Configuration:**
1. Go to: APIs & Services → Credentials
2. Find your Web Client ID
3. **Authorized redirect URIs** must include:
   ```
   https://oelbsuggrzyqwzmvidju.supabase.co/auth/v1/callback
   ```

**Check:** [ ] Redirect URI added to Web Client

### iOS Client (GOOGLE_IOS_CLIENT_ID)
**Client ID:** `816845608736-cpurkpq34aqt33e0jsf9pjpto2lql28v.apps.googleusercontent.com`

**Required Configuration:**
- Bundle ID: `com.chessever.app`
- No redirect URI needed (native flow)

**Check:** [ ] Bundle ID configured correctly

### Android Client (GOOGLE_ANDROID_CLIENT_ID)
**Client ID:** `816845608736-smg45le1m7h14j69thltqlipkcu9fimt.apps.googleusercontent.com`

**Required Configuration:**
- Package name: `com.chessever.app`
- SHA-1: Your release keystore SHA-1
- No redirect URI needed (native flow)

**Check:** [ ] Package name configured
**Check:** [ ] Release SHA-1 added

---

## 🔧 3. Supabase Dashboard Configuration

**Location:** https://supabase.com/dashboard/project/oelbsuggrzyqwzmvidju/auth/providers

### Google Provider
1. Enable Google provider
2. **Client ID (for OAuth):** `816845608736-6fskv7m8sssl2j8a6u6o5lgm162et6qj.apps.googleusercontent.com`
3. **Client Secret:** (from Google Cloud Console Web Client)
4. **Authorized Client IDs** should include:
   ```
   816845608736-6fskv7m8sssl2j8a6u6o5lgm162et6qj.apps.googleusercontent.com
   816845608736-cpurkpq34aqt33e0jsf9pjpto2lql28v.apps.googleusercontent.com
   816845608736-smg45le1m7h14j69thltqlipkcu9fimt.apps.googleusercontent.com
   ```

**Check:** [ ] Google provider enabled
**Check:** [ ] All client IDs added to authorized list

### Apple Provider
1. Enable Apple provider
2. **Services ID:** `com.chessever.app`
3. **Team ID:** (from Apple Developer)
4. **Key ID:** (from Apple Developer)
5. **Private Key:** (from Apple Developer .p8 file)

**Check:** [ ] Apple provider enabled
**Check:** [ ] All Apple credentials configured

---

## 🔧 4. Apple Developer Console

**Location:** https://developer.apple.com/account/resources/identifiers/list/serviceId

### Sign in with Apple Configuration

1. **Services ID:** `com.chessever.app`
2. **Domains and Subdomains:**
   ```
   oelbsuggrzyqwzmvidju.supabase.co
   ```
3. **Return URLs:**
   ```
   https://oelbsuggrzyqwzmvidju.supabase.co/auth/v1/callback
   ```

**Check:** [ ] Services ID created
**Check:** [ ] Domain added
**Check:** [ ] Return URL added

---

## 🔍 Common Issues & Solutions

### Issue 1: "Google Sign-In Failed"
**Possible Causes:**
- ❌ Web Client redirect URI not configured in Google Cloud Console
- ❌ Wrong client IDs in Supabase
- ❌ Release SHA-1 not added to Android client

**Solution:** Verify sections 2 and 3 above

### Issue 2: "Apple Sign-In Failed on Android"
**Possible Causes:**
- ❌ APPLE_REDIRECT_URI not in .env file
- ❌ Apple Services ID not configured correctly
- ❌ Return URL not added in Apple Developer Console

**Solution:** Verify sections 1 and 4 above

### Issue 3: "Redirect URI Mismatch"
**Possible Causes:**
- ❌ Different redirect URIs in different places
- ❌ Typo in redirect URI

**Solution:** Ensure ALL places use:
```
https://oelbsuggrzyqwzmvidju.supabase.co/auth/v1/callback
```

---

## 📝 Summary

### In Your Code (auth_repository.dart):
- ✅ APPLE_REDIRECT_URI is used ONLY for Apple Sign-In on Android
- ✅ Google Sign-In does NOT use redirect URI in code
- ✅ Current implementation is CORRECT

### In External Dashboards:
- 🔧 Google Cloud Console: Add redirect URI to Web Client
- 🔧 Supabase Dashboard: Configure both Google and Apple providers
- 🔧 Apple Developer: Configure Services ID with redirect URI

---

## 🎯 Action Items

1. [ ] Check Google Cloud Console Web Client redirect URIs
2. [ ] Verify Supabase Google provider configuration
3. [ ] Verify Supabase Apple provider configuration
4. [ ] Check Apple Developer Services ID configuration
5. [ ] Test Google Sign-In on both iOS and Android
6. [ ] Test Apple Sign-In on both iOS and Android

---

**Note:** The confusion might be because `APPLE_REDIRECT_URI` is actually your Supabase callback URL that's used by BOTH providers in their respective dashboards, but in the mobile code, it's only explicitly used for Apple Android web flow.
