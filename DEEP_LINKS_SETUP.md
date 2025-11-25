# Deep Links Setup for ChessEver

Host these files on `chessever.com` to enable universal links (for sharing games, notifications, etc.)

---

## 1. Android App Links

**Host at:** `https://chessever.com/.well-known/assetlinks.json`

```json
[{
  "relation": ["delegate_permission/common.handle_all_urls"],
  "target": {
    "namespace": "android_app",
    "package_name": "com.chessEver.app",
    "sha256_cert_fingerprints": [
      "68:A6:A4:FF:2D:AF:EF:3C:42:9F:F8:A8:A7:C0:14:EE:49:C1:51:C3:86:AB:BB:66:DC:12:27:92:BF:88:2D:DE",
      "52:31:C5:10:40:A4:B7:51:61:C7:C6:8E:1F:06:C0:2E:B5:DE:1E:8D:CE:72:8C:7E:B7:22:70:91:60:2C:AC:8E",
      "C5:0C:08:57:75:B3:56:90:ED:39:7C:61:33:43:00:85:02:30:3B:63:BE:AD:4A:10:29:BD:44:D9:D0:31:1E:FD"
    ]
  }
}]
```

---

## 2. iOS Universal Links

**Host at:** `https://chessever.com/.well-known/apple-app-site-association`

**Note:** No `.json` extension for this file!

```json
{
  "applinks": {
    "apps": [],
    "details": [{
      "appID": "N8J7TUZMYR.com.chessever.app",
      "paths": ["*"]
    }]
  }
}
```

---

## Important Requirements

1. **No file extension** - `apple-app-site-association` must NOT have `.json` extension
2. **Content-Type** - Both files should be served with `Content-Type: application/json`
3. **HTTPS required** - Must be served over HTTPS with valid SSL certificate
4. **No redirects** - Files must be served directly at the URL, not via redirects

---

## Verification

After hosting, verify your setup:

- **Android:** https://digitalassetlinks.googleapis.com/v1/statements:list?source.web.site=https://chessever.com&relation=delegate_permission/common.handle_all_urls
- **iOS:** https://chessever.com/.well-known/apple-app-site-association

---

## Supabase Dashboard Settings

- **Site URL:** `https://chessever.com`
- **Redirect URLs:**
  - `com.chessever.app://**`
  - `https://chessever.com/**`
