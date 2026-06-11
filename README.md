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
3. Create your environment file:
   ```bash
   cp .env.example .env
   ```
   The public keys are already filled in, so the app builds and reads public
   data out of the box. See [Contributing](#contributing) for live game search.
4. Run the app:
   ```bash
   flutter run
   ```

## Contributing

ChessEver is open source and we welcome contributions. You do **not** need our
production secrets to work on the app.

**1. Get set up.** `cp .env.example .env`. The template ships the public keys
that already live inside every released build, so the app compiles, signs in,
and shows live broadcast data immediately. With no developer key, historical
search and the position explorer fall back to bundled sample data, which is
enough for most UI and feature work.

**2. Get a developer key (optional, for live historical data).** The large
historical game database is served through a separate, rate-limited API. Sign in
and generate a personal key at:

> **https://chessever.com/developers**

Paste it into your `.env` as `GAMEBASE_API_KEY=...` and restart the app. The key
is read-only, rate-limited, scoped to safe endpoints, and expires in 90 days.
You can revoke or rotate it anytime from the same page. It cannot write to or
strain our database, so it is safe to use freely while you build.

**3. Open a PR.** Run `flutter analyze` before pushing. Never commit your `.env`
(it is git-ignored) or any real secret.

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
