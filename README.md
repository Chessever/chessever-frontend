# Chessever Frontend

This is a Flutter project for the Chessever application.

## Getting Started

### Prerequisites

- Flutter SDK: Make sure you have Flutter installed. You can find installation instructions [here](https://flutter.dev/docs/get-started/install).
- An editor like VS Code or Android Studio.

### Running the Project

1.  Clone the repository:
    ```bash
    git clone https://github.com/Chessever/chessever-frontend
    cd chessever-frontend
    ```
2.  Get the dependencies:
    ```bash
    flutter pub get
    ```
3.  Run the app:
    ```bash
    flutter run
    ```

## Generating Splash Screen

To generate or update the native splash screen for this project, run the following command in your terminal:

```bash
flutter pub run flutter_native_splash:create
flutter gen-l10n
```

This command uses the `flutter_native_splash` package configuration defined in `pubspec.yaml` 
to create splash screens for Android and iOS. And also generates localization utils.

