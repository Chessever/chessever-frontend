# Phone store-update reminders

Scope
- The App Store/Play Store version prompt (`CustomUpgradeAlert`) owns the exact
  label `Remind me in 3 days`. Shorebird's separate patch download/restart dialog
  and its existing `Later` action are unchanged.
- Android/iOS app only; no desktop/web flow, push notifications, timers,
  background jobs, server state or new remote queries.

Policy
- A successful reminder click persists the offered semantic version and an
  absolute UTC deadline exactly 72 hours from the click. The deadline keeps
  microsecond precision and survives process restarts in local SharedPreferences
  (`phone_store_update_snooze_v1`), through the existing initialized preference
  service. No account/device identifier is stored.
- A newer optional release does not reset or bypass the active deadline. At the
  next safe launch/resume on or after that deadline, the latest successfully
  checked store version is offered. Re-snoozing binds a new 72 hours to that offer.
- Installing the snoozed version or a newer version clears the record, even when
  the current store check has no offer. A store redirect alone never clears it.
  Once the original target is installed, a still-newer release is a new eligible
  offer; the old cooldown no longer applies.
- Minimum-version/critical updates bypass the optional cooldown, have no remind
  action and cannot be dismissed via back/barrier. Explicit manual checks bypass
  optional snooze/ignore state but still wait for a safe route. There was no
  separate settings manual-check UI to change; the existing store launch uses
  Upgrader's platform-specific URL contract unchanged.
- Back/barrier dismissal of an optional offer also saves a three-day snooze,
  starting when the dialog is dismissed, so it does not return on every resume.
  Mandatory offers cannot be dismissed this way.
- Device wall-clock changes affect the absolute local deadline; no network clock
  or background scheduling is introduced.

Safe entry
- One automatic check is armed at launch and each foreground resume. It waits
  until a completed root-navigator page is one of `/home_screen`,
  `/group_event_screen`, `/calendar_screen`, `/library_screen`,
  `/favorites_screen` or `/player_list_screen`.
- Splash, authentication/onboarding, all unnamed pages, board/game/editor/Watch
  routes, modals, local-history overlays and interactive transitions defer it.
  The full route stack is tracked, including replacement/removal of covered
  pages. A checked offer is reused during that entry's route deferral, avoiding
  duplicate store requests. Nothing fires merely because time passes while the
  user remains in a foreground game.
- Checks and dialogs are single-flight. Foreground generation and mounted checks
  prevent stale async completions from showing after background/disposal.
  Snooze/store completions close only their exact dialog, never a new game route.
- Store failures never reuse stale version info; another entry/explicit check can
  retry. Failed local saves keep the prompt open with retry feedback rather than
  claiming a persistent snooze succeeded.

Validation
- `test/phone_update_reminder_test.dart`: injected-clock boundaries, persistence,
  installed-target clearing, newer-version policy, missing offers/preferences,
  click-time capture and corrupt-record handling.
- `test/phone_update_prompt_test.dart`: real Navigator/lifecycle widget tests for
  launch/resume, safe-route/transition/modal deferral, concurrent checks/dialogs,
  mandatory/manual/store behavior, save failure and async disposal/deep-link races.
- `test/phone_store_upgrader_test.dart`: production adapter request coalescing,
  stale-info removal, failure retry and single resume ownership, with local fake
  store responses only.

Physical-device QA (user-run; not performed by this change)
- Android and iOS: with an optional store update, verify exact label and retained
  update/release-notes UI; tap remind, force-stop/relaunch, and resume before 72h:
  no automatic reminder. Check both light/dark and large accessibility text.
- At/after 72h: enter/resume Home, observe one reminder. Resume a live/analysis
  board, editor, game or Watch screen first: no reminder until returning to a safe
  route. Keep a sheet/drawer open: do not stack another dialog.
- Publish/install only through a separately authorized QA/release workflow:
  verify a newer optional offer during the snooze does not bypass it; verify a
  same/newer installed package retires the snooze on relaunch.
- Verify `Update Now` opens the correct platform store; cancelling store purchase/
  download does not mark the update installed. Exercise explicit manual checks
  if such a host entrypoint is supplied.
- In an authorized minimum-version/critical-update fixture: no remind action,
  back/barrier cannot dismiss, store action remains available.
- Offline/failing store check: no stale update dialog and no loop. Restore network
  and resume: retry. Rapid background/foreground, route switches and deep links
  while saving must not duplicate dialogs or close the newly opened game.
