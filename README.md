# Chessever Frontend

This is a Flutter project for the Chessever application.

## Getting Started

### Prerequisites

- Flutter SDK: Make sure you have Flutter installed. You can find installation
  instructions [here](https://flutter.dev/docs/get-started/install).
- An editor like VS Code or Android Studio.

### Running the Project

1. Clone the repository:
   ```bash
   git clone https://github.com/Chessever/chessever-frontend
   cd chessever-frontend
   ```
2. Get the dependencies:
   ```bash
   flutter pub get
   ```
3. Create a local env file. Do not commit it.
   ```bash
   cp .env.example .env
   ```
4. Generate your personal Gamebase API key:
   - Open https://chessever.com/account#developers
   - Sign in with your ChessEver account
   - Go to Developer API Keys and click Generate key
   - Paste it into `.env` as `GAMEBASE_API_KEY=...`
5. Run the app with compile-time env values:
   ```bash
   flutter run --dart-define-from-file=.env
   ```

`.env.example` contains only public client config and empty personal-key slots.
`.env` is intentionally ignored and is not bundled as a Flutter asset. Use
`--dart-define-from-file` for local debug runs and CI/release builds.

## Mobile E2E Tests

This repository includes a Patrol-based signed-in mobile E2E suite for route
coverage, live-data fetching, and chess-board engine assertions.

- Full operating guide: `patrol_test/README.md`
- Local smoke run: `./tool/patrol_smoke.sh`
- Local deep run: `./tool/patrol_deep.sh`
- Env template: `.env.e2e.example`

The suite runs the real app in a dedicated `E2E` mode, signs in with a real
test account, suppresses non-essential prompts, and exercises page roots,
search/filter flows, tournament/calendar/library/player routes, and board
interactions such as notation taps, move traversal, game swipes, and engine
line visibility.

## Generating Splash Screen

To generate or update the native splash screen for this project, run the following command in your
terminal:

```bash
flutter pub run flutter_native_splash:create
flutter gen-l10n
```

This command uses the `flutter_native_splash` package configuration defined in `pubspec.yaml`
to create splash screens for Android and iOS. And also generates localization utils.

```bash
dart run flutter_launcher_icons:generate
```bash
This command uses the `flutter_launcher_icons` package configuration defined in `pubspec.yaml`
to create app icons for Android and iOS. 


```bash
flutter pub run build_runner build --delete-conflicting-outputs
```

This command will generate assets using `build_runner`


IOS Bundle Identifier updated to : com.chessever.app

#### Project Knowledge
///pvs -> moves from the current position []
///knodes -> 1000 nodes, nodes are the number of positions that the engine has looked at
