# Releases on GitHub Actions

GitHub Actions replacement for Codemagic, which is too expensive now that
both apps are public open source (standard GitHub-hosted runners are free for
public repositories).

| Repository | Workflow file | Replaces (Codemagic) |
|---|---|---|
| `chessever-frontend` | `.github/workflows/mobile-release.yml` | app `chessever-frontend-mobile`, workflow "Flutter-Default Workflow" |
| `chessever_frontend_desktop` | `.github/workflows/desktop-release.yml` | `macos-desktop-release-arm64`, `macos-desktop-release-x64`, `windows-desktop-release`, `linux-desktop-release` in `codemagic.yaml` |
| `chessever_frontend_desktop` | `.github/workflows/desktop-macos-flutter-master.yml` | `macos-desktop-master` in `codemagic.yaml` |

This file covers both repositories (the desktop repo keeps its markdown
docs local, so the shared guide lives here).

## Mobile release

Actions -> **Mobile release** -> Run workflow, on `stable`.

| Input | Default | Effect |
|---|---|---|
| `android` | on | Build the App Bundle on `ubuntu-24.04` |
| `ios` | on | Build the IPA on `macos-26` (Xcode 26.6) |
| `publish` | on | Upload to Google Play `internal` (in-app update priority 5) and App Store Connect (no TestFlight submission) |
| `upload_symbols` | off | Keep R8 `mapping.txt` and dSYMs as run artifacts for 7 days |

Codemagic built both platforms one after the other on a single Mac. Here they
run in parallel, each on its own free runner. The release commands explicitly select the production flavor and `lib/main.dart`.
Build-only runs retain the AAB and IPA for seven days. The remaining commands run
in the same order:

| Codemagic step | GitHub step |
|---|---|
| Flutter `stable`, Xcode `latest` (26.6), Java 17 | `subosito/flutter-action` (stable), `xcode-select` 26.6, `setup-java` 17 |
| Post-clone: decode `GOOGLE_SERVICES_JSON`, `GOOGLE_SERVICE_INFO_PLIST` | "Write Firebase config ..." steps |
| Code signing: `app-store-connect fetch-signing-files com.chessever.app --type IOS_APP_STORE --create`, keystore | "Set up code signing" (same `codemagic-cli-tools` 0.70.0 command); keystore is written to the git-ignored `android/key.properties` that `build.gradle.kts` already reads |
| Pre-build: NDK 27.0.12077973 + 28.2.13676358, required-variable check, `aps-environment` check, `xcode-project use-profiles` | "Install Android NDKs", the checks in each step, "Set up code signing" |
| `flutter build appbundle --release <defines>` | `scripts/ci/mobile_flutter_build.sh appbundle` (same define list and order) |
| `flutter build ipa --release --export-options-plist ... <defines>` | `scripts/ci/mobile_flutter_build.sh ipa --export-options-plist ...` |
| Post-build: embedded profile must carry production APNs | "Check IPA signing" |
| Publish: `google-play bundles publish --track internal --in-app-update-priority 5`, `app-store-connect publish` | Same commands |
| Email to info@, brky29cn@, flutterdev77@ | Not ported. GitHub emails the person who started a failed run. |

## Desktop release

In `chessever_frontend_desktop`: Actions -> **Desktop release** -> Run
workflow, on `main`. The release scripts under `scripts/` run unchanged; the
workflow gives them the `CM_*` variables they read (`CM_BUILD_DIR`,
`CM_BRANCH`, `CM_BUILD_URL`, ...).

| Input | Default | Runner | Replaces |
|---|---|---|---|
| `macos_arm64` | on | `macos-26`, Xcode 26.6 | `macos-desktop-release-arm64` |
| `macos_x64` | on | `macos-26`, Xcode 26.6 | `macos-desktop-release-x64` |
| `windows` | on | `windows-2022` (Visual Studio 2022, Inno Setup 6) | `windows-desktop-release` |
| `linux` | on | `ubuntu-24.04` (same glibc floor as Codemagic's `linux_x2`) | `linux-desktop-release` |
| `publish` | on | | Off passes `--skip-upload` / `-SkipUpload`: still builds, signs and notarizes, uploads nothing to R2 |

Each job runs Codemagic's steps in Codemagic's order: Telegram "started",
verify environment, `flutter pub get`, the same pre-flight tests, build,
publish, success marker, then Telegram "finished" (always, read from the
marker). Runs with `publish` off keep the installers (`.dmg`, `.exe`,
`.deb`) as run artifacts for 7 days so they can be tried by hand, and their
Telegram messages say "(dry run)". Published runs keep none; the installers
are on R2.

- **macOS.** Both architectures build on Apple Silicon, as on Codemagic
  (`MACOS_ENGINE_ARCH` selects the slice). The frozen names hold: Apple
  Silicon publishes as updater platform `macos` with `Chessever.dmg`, Intel
  as `macos-x64` with `Chessever-intel.dmg`, and
  `scripts/codemagic_publish_macos.sh` still decides them. The Developer ID
  `.p12` goes into a temporary keychain using the same `keychain`,
  `app-store-connect profiles get SUW9J8GQ8V` and `xcode-project use-profiles`
  commands Codemagic ran.
- **Concurrency.** The four jobs publish in parallel, as on Codemagic;
  `r2_publish_release.py` updates the manifests with ETag compare-and-swap.
  Whole runs are queued (`concurrency: desktop-release`) so two versions never
  prune each other.
- **Runner sizes.** Free macOS runners have 3 vCPUs and 7 GB of memory, far
  less than Codemagic's `mac_mini_m4`. The macOS timeout is 180 minutes.
- **Linux.** `codemagic_publish_linux.sh` launches the built app with
  `--verify-release-env`, and the GTK runner opens a window first. Hosted
  Ubuntu has no display, so the publish step runs under `xvfb-run`.

**macOS desktop (Flutter master)** ports `macos-desktop-master`: unsigned,
ad-hoc signed, never published, zipped `.app` kept for 7 days. It reads only
the app-config organization secrets, so it needs no `release` environment and
no approval.

## How the secrets are protected

Both repositories are public, so their Actions logs and artifacts are public
too. The setup splits values by what a leak would cost.

1. **Organization secrets and variables** (Settings -> Secrets and variables ->
   Actions, at the organization) hold the values compiled into the apps:
   Supabase anon key, Sentry DSN, analytics IDs, Firebase config, and so on.
   Anyone can already pull these out of a store build. Each one is visible
   only to the repositories that use it ("Selected repositories").
2. **`release` environment secrets** (per repository) hold everything that
   signs or publishes: keystore, store API keys, distribution certificates, R2
   credentials. A job gets them only if it runs on the release branch
   (`stable` here, `main` on desktop) and a reviewer approves the run.
   The setup script also switches off admin bypass, so none of the six admins
   per repository can skip the approval.

The workflows add:

- Manual trigger only. No `pull_request` or `pull_request_target`, so a
  fork's pull request can never reach a secret.
- `GITHUB_TOKEN` limited to `contents: read`; checkout does not persist it.
- Every action pinned to a full commit SHA, and the Python tools
  (`codemagic-cli-tools`, `boto3`) installed with `--require-hashes` from a
  lock file covering every dependency (`scripts/ci/release-tools.txt`;
  regenerate with the `uv` command in its header).
- Secrets are passed only to the steps that use them, never job-wide, so
  setup actions never see them.
- Flutter passes dart-defines to Gradle and Xcode base64-encoded, and GitHub
  masks only the literal secret. The build scripts also mask each encoded
  define, so a failing native step cannot print them.
- Anyone signed in to GitHub can download a public repository's artifacts.
  Mobile retains AAB/IPA files only for build-only runs, and symbols are opt-in. Desktop keeps
  only installers, and only from dry runs. No job uploads build logs.
- Keystore, `key.properties`, Firebase files, keychain and certificates are
  deleted at the end of every job, pass or fail.

## Secret catalogue

Codemagic never reveals a secure value, so each one has to come from its
original source. Where a credential can be issued twice, create a new one for
GitHub (a new Play service-account key, App Store Connect API key, R2 token).
Then Codemagic's copies can be revoked on their own when it is switched off.

### Organization variables (public)

Set by the setup script with values that already ship in the apps.

| Name | Repositories |
|---|---|
| `CHESSEVER_CLOUDFLARE_API_BASE` | both |
| `GOOGLE_WEB_CLIENT_ID` | mobile |
| `GOOGLE_IOS_CLIENT_ID` | mobile |

### Organization secrets: `org-shared/` (both repositories)

Identical in both Codemagic apps today.

| Name | Source |
|---|---|
| `SUPABASE_URL` | Production Supabase project -> Settings -> API |
| `SUPABASE_ANON_KEY` | Same page (anon key) |
| `SENTRY_FLUTTER` | Sentry project DSN |

### Organization secrets: `org-mobile/` (chessever-frontend)

| Name | Codemagic name | Source |
|---|---|---|
| `REVENUECAT_API_KEY` | `RevenueCatAPIKey` | RevenueCat -> API keys |
| `AMPLITUDE` | same | Amplitude project API key |
| `CLARITY_PROJECT_ID` | same | Microsoft Clarity project |
| `ONESIGNAL_APP_ID` | same | OneSignal app settings |
| `APPSFLYER_DEV_KEY` | same | AppsFlyer dev key |
| `GAMEBASE_API_KEY` | same | Gamebase release key |
| `GOOGLE_SERVICES_JSON_B64` | `GOOGLE_SERVICES_JSON` | Firebase -> Android app `com.chessEver.app` -> `google-services.json` (raw file) |
| `GOOGLE_SERVICE_INFO_PLIST_B64` | `GOOGLE_SERVICE_INFO_PLIST` | Firebase -> iOS app `com.chessever.app` -> `GoogleService-Info.plist` (raw file) |

Most of these also sit in the local git-ignored `.env`. Check they are the
production values before using them.

### Organization secrets: `org-desktop/` (chessever_frontend_desktop)

| Name | Source |
|---|---|
| `GOOGLE_DESKTOP_CLIENT_ID` | Google Cloud -> OAuth desktop client |
| `GOOGLE_DESKTOP_CLIENT_SECRET` | Same client |

### `release` environment: `release-mobile/` (chessever-frontend)

| Name | Source |
|---|---|
| `ANDROID_KEYSTORE_B64` | Upload keystore `my-release-key.jks`, alias `my-key-alias` (raw file) |
| `ANDROID_KEYSTORE_PASSWORD` | Keystore password |
| `ANDROID_KEY_PASSWORD` | Key password |
| `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON` | Google Cloud -> the service account Codemagic publishes with -> new JSON key |
| `APP_STORE_CONNECT_ISSUER_ID` | App Store Connect -> Users and Access -> Integrations |
| `APP_STORE_CONNECT_KEY_IDENTIFIER` | Same page (key ID) |
| `APP_STORE_CONNECT_PRIVATE_KEY` | The key's `AuthKey_<id>.p8` (downloadable once; create a new App Manager key if it is gone) |
| `IOS_DISTRIBUTION_CERTIFICATE_KEY` | PEM private key of the Apple Distribution certificate (below) |

**`IOS_DISTRIBUTION_CERTIFICATE_KEY`.** `fetch-signing-files` reuses the
Apple Distribution certificate whose private key you give it, and with
`--create` it issues a new one when none matches. Either:

- export the existing certificate's key from its `.p12`:
  `openssl pkcs12 -in distribution.p12 -nocerts -nodes -legacy | openssl rsa -out IOS_DISTRIBUTION_CERTIFICATE_KEY`
  (drop `-legacy` if OpenSSL rejects it), or
- create a fresh key with `openssl genrsa -out IOS_DISTRIBUTION_CERTIFICATE_KEY 2048`.
  The first run then creates a new Apple Distribution certificate and
  matching App Store profiles. Apple caps distribution certificates per team,
  so revoke an unused one first if the cap is reached. Codemagic keeps
  working with its own certificate.

### `release` environment: `release-desktop/` (chessever_frontend_desktop)

| Name | Codemagic name | Source |
|---|---|---|
| `APP_STORE_CONNECT_ISSUER_ID` | same | As above (notarization and profile download) |
| `APP_STORE_CONNECT_KEY_IDENTIFIER` | same | As above |
| `APP_STORE_CONNECT_PRIVATE_KEY` | same | As above |
| `MACOS_DEVELOPER_ID_P12_B64` | `CM_CERTIFICATE` | "Developer ID Application: ChessEver LLC" exported from Keychain Access as `.p12` (raw file) |
| `MACOS_DEVELOPER_ID_P12_PASSWORD` | `CM_CERTIFICATE_PASSWORD` | Password chosen at export |
| `R2_ACCOUNT_ID` | same | Cloudflare account ID |
| `R2_ACCESS_KEY_ID` | same | Cloudflare -> R2 -> API token, Object Read and Write on the releases bucket only |
| `R2_SECRET_ACCESS_KEY` | same | Same token |
| `TELEGRAM_BOT_TOKEN` | same | Release-notification bot |
| `TELEGRAM_CHAT_ID` | same | Release-notification destination (CI only) |
| `R2_BUCKET` (optional) | same | Defaults to `chessever-releases` |
| `SENTRY_AUTH_TOKEN`, `SENTRY_ORG`, `SENTRY_PROJECT` (optional) | not set | Windows symbol upload; skipped when absent, as on Codemagic |

Not carried over: `CODEMAGIC_PUBLISHER_KEY` and `CODEMAGIC_PUBLISH_REMOTE`
(the old droplet upload; nothing reads them since the move to R2),
`GAMEBASE_API_KEY` in the desktop group (no desktop build passes it), and the
mobile `TELEGRAM_BOT_TOKEN` / `TELEGRAM_CHAT_ID` (no mobile step uses them).

## One-time setup

Run on a Mac (the script uses `plutil` to check the plist).

1. Put every value in a private directory outside all git checkouts, one file
   per value, file name = secret name. Raw files go under the `*_B64` names
   and the script encodes them.

   ```text
   ~/.chessever-ci/
     org-shared/SUPABASE_URL
     org-mobile/GOOGLE_SERVICES_JSON_B64        <- raw google-services.json
     release-mobile/ANDROID_KEYSTORE_B64        <- raw my-release-key.jks
     release-desktop/MACOS_DEVELOPER_ID_P12_B64 <- raw .p12
     ...
   ```

   `chmod -R go-rwx ~/.chessever-ci`

2. Give `gh` access to organization secrets:
   `gh auth refresh -h github.com -s admin:org`
3. Check the plan, then apply it:

   ```bash
   scripts/ci/setup_github_release.sh ~/.chessever-ci          # lists ok / MISSING / INVALID
   scripts/ci/setup_github_release.sh ~/.chessever-ci --apply
   ```

   The script sets the organization variables and secrets, creates the
   `release` environment in both repositories (deploys from `stable` and
   `main` only, approval by `devberkay`; set `RELEASE_REVIEWERS="a b"` to
   change), switches off admin bypass and fills the environment secrets. It
   is safe to run again. Before writing anything it stops if an organization
   secret or variable of the same name already exists with another scope,
   because setting it would replace that value for everything that uses it.
4. If the script ends with "GitHub kept admin bypass on", untick **Allow
   administrators to bypass configured protection rules** under Settings ->
   Environments -> `release` in the repositories it names.
5. Recommended: protect `stable` in the phone repo (desktop `main` already
   is). The environment checks only the branch name, so anyone who can push
   to `stable` can change a workflow there, and the approval dialog does not
   show that change. Until then, check the run's commit before approving.
6. Optional: Organization -> Settings -> Actions -> General -> enable
   **Require actions to be pinned to a full-length commit SHA**. These
   workflows already comply; confirm Copilot code review and Dependabot still
   run afterwards.
7. When the GitHub runs are trusted, delete the values directory, switch off
   the Codemagic workflows and revoke the credentials only Codemagic used.

## First runs

1. Run **Mobile release** and **Desktop release** with `publish` off. This
   signs, notarizes and builds everything without uploading, so it checks
   every secret except the upload-only ones (Play service account, R2).
   Mobile AAB/IPA files and desktop installers are available as run artifacts.
   An App Store IPA still requires store distribution or suitable provisioning to install.
2. Run them again with `publish` on for a real release. Google Play and App
   Store Connect reject a build number they have already seen, and R2 refuses
   to overwrite an archive with different bytes, so bump `pubspec.yaml` as
   usual and do not release the same version from Codemagic too.

Expect approval prompts: each run waits on the `release` environment until a
reviewer clicks **Review deployments**.

## Known gaps

- Feedback bot credentials are intentionally excluded from both apps. Feedback
  goes through the production `chessever-feedback` Worker with bounded payloads,
  per-address and aggregate rate limits, and server-configured destinations.
  CI must never compile a bot token into a public app. Existing organization copies are not read by these workflows.
  Desktop build notifications still use CI-only release environment secrets.
- Free hosted macOS runners have 3 vCPUs and 7 GB of memory, so the iOS
  build is slower than on Codemagic's M2. The job timeout is 120 minutes.
- The Android job keeps Codemagic's `JAVA_TOOL_OPTIONS=-Xmx10g`, which applies
  to every JVM including the Kotlin daemon. The runner has 16 GB. If a build
  is killed for memory, drop that line first.
