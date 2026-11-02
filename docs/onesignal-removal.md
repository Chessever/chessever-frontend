# OneSignal SDK removal — 37.6.11+3778

This version uses Firebase Cloud Messaging and the ChessEver delivery service directly.
It does not initialize or require the OneSignal SDK, a OneSignal device ID, or the
`ONESIGNAL_APP_ID` release setting. Native iOS/Android channels now own notification
permission queries and requests. Prompts stay in the existing onboarding/settings flows.

Direct registration follows startup, authentication, permission, token-refresh and resume
events. Existing installation proof storage is retained. Firebase/native tap handling,
deep links, receipt reporting and tap deduplication remain in place. RevenueCat still
handles purchases/accounts, but the app no longer forwards a OneSignal subscription ID.

The companion admin-portal deployment includes production migration
`20261102175656_standalone_push_registration.sql` and a new service-only registration RPC.
The authenticated Worker hashes installation proofs and supplies the owner ID. For an
upgrade, the native FCM/APNs token matches only owned legacy records for the same platform.
The database transaction registers direct push and retires duplicate legacy mirrors
atomically. Failed ownership/proof checks preserve the old records. No OneSignal API
request is involved in registration.

Older app versions still depend on OneSignal delivery. At inspection there were 2,331
opted-in legacy registrations. Keep the compatibility transport and credentials until the
new app has been released and the remaining legacy-client requirements are resolved.
Existing external RevenueCat/OneSignal campaigns are not migrated by removing client ID
forwarding. Backend legacy timezone lookups and credential checks also remain until final
transport retirement. Native registration timezones already take precedence for current
devices. Email continues through SES, with all existing opt-outs and suppressions intact.

## Validation

- Scoped Flutter analysis: no issues.
- Focused native-permission, returning-sign-in, onboarding, direct-tap, Inbox-navigation
  and native dependency regression tests passed.
- iOS AppDelegate syntax and release-shell script syntax checks passed.
- Backend production build and registration/database tests passed; production synthetic
  registration and deduplication were verified inside a rolled-back transaction.
- Full app suite: 6,129 passed, four skipped, 45 failed. Failures are in other feature
  suites, including board gestures, event/My Space menus, streak/puzzle UI, dated Inbox
  text and the old counter smoke test. The full suite is not a clean release gate.
- No app build, live-device test, or store submission was performed.

## Device checks before release

Following AGENTS.md, the user performs live-device validation:

1. Upgrade an existing iOS and Android install; separately test fresh installs. Confirm
   direct FCM registration without a OneSignal SDK initialization.
2. Grant/deny notifications during onboarding; change permission in OS settings and return
   to the app. Check that the portal reflects the device's actual opt-in state.
3. Send an explicitly authorized test; verify foreground, background and terminated-app
   taps open the correct Inbox/game destination and record receipt/open events.
4. Sign out, change accounts and switch accounts quickly. The previous account must no
   longer target the installation. Verify token refresh and restart registration.
5. Verify one notification per physical device after upgrade, including old duplicate
   mirror records. A fresh user must register without any legacy mirror.

Release this app version before removing the remaining compatibility transport or
downgrading/canceling OneSignal based on legacy-client readiness. Registration counts are
not OneSignal's monthly active user metric. Historical provider data and email provenance
should be preserved.
