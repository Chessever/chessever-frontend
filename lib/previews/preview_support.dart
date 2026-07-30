import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';

/// Shared plumbing for `@Preview` entry points.
///
/// Run the previewer with:
/// ```sh
/// flutter widget-preview start
/// ```
///
/// **A preview must compile to JavaScript.** The Widget Preview Scaffold only
/// runs as a web app — `-d <device>` does not retarget it at a simulator or
/// desktop — and large parts of this app can never compile to JS: `dart:io`,
/// `dart:ffi` / `package:stockfish`, and `package:dartchess` (64-bit int
/// literals). So a widget is previewable only if its *whole transitive import
/// closure* is web-clean. In practice that means small leaf widgets: anything
/// reaching a screen, a repository, or the engine pulls in hundreds of files
/// and will fail to compile. Verify a candidate by walking its imports for
/// `dart:io`, `dart:ffi`, `package:dartchess` and `package:stockfish` before
/// annotating it. For anything heavier, render it to PNG from a widget test
/// instead.
///
/// Everything here must stay top-level and public: `@Preview` arguments have to
/// be const, and its callbacks have to be static and non-private.

/// Concrete [PreviewThemeData] for Flutter 3.47+ (base class is abstract).
///
/// Applies the app light/dark [ThemeData] from [AppTheme] based on the
/// ambient platform brightness so previews match what ships.
final class AppPreviewThemeData extends PreviewThemeData {
  /// Creates the ChessEver widget-preview theme adapter.
  const AppPreviewThemeData();

  @override
  Widget apply(BuildContext context, Widget child) {
    final brightness =
        MediaQuery.maybePlatformBrightnessOf(context) ?? Brightness.light;
    final theme = brightness == Brightness.dark
        ? AppTheme.darkTheme
        : AppTheme.lightTheme;
    return Theme(data: theme, child: child);
  }
}

/// The app's real themes, so previews match what ships.
PreviewThemeData appPreviewTheme() => const AppPreviewThemeData();

/// Initializes [ResponsiveHelper] before the previewed widget builds.
///
/// Required, not cosmetic: `AppTypography` and the `.sp/.h/.w/.br/.ic`
/// extensions read `late` statics that are only set by `ResponsiveHelper.init`,
/// so a preview without this throws a `LateError` instead of rendering.
Widget responsivePreviewHost(Widget child) {
  return Builder(
    builder: (context) {
      ResponsiveHelper.init(context);
      return child;
    },
  );
}

/// Phone-sized canvas for previews of a full screen or a bottom sheet.
const Size kPhonePreviewSize = Size(393, 852);
