import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android test flavor is isolated from production', () {
    final gradle = File('android/app/build.gradle.kts').readAsStringSync();
    final manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    final firebaseFile = File(
      'android/app/src/chessevertest/google-services.json',
    );

    expect(gradle, contains('create("production")'));
    expect(gradle, contains('create("chessevertest")'));
    expect(gradle, contains('applicationIdSuffix = ".test"'));
    expect(manifest, contains(r'android:label="${appName}"'));
    expect(manifest, contains(r'android:scheme="${authRedirectScheme}"'));
    // Firebase client files are deliberately ignored and injected by CI before
    // the build phase. Validate their identity when present in a local checkout
    // without making a clean clone depend on an ignored file.
    if (firebaseFile.existsSync()) {
      final firebase =
          jsonDecode(firebaseFile.readAsStringSync()) as Map<String, dynamic>;
      expect(firebase['project_info']['project_id'], 'chessever-test-2026');
      expect(
        firebase['client'][0]['client_info']['android_client_info']
            ['package_name'],
        'com.chessEver.app.test',
      );
    }
  });

  test('iOS test scheme selects the isolated identity and Firebase config', () {
    final project =
        File('ios/Runner.xcodeproj/project.pbxproj').readAsStringSync();
    final info = File('ios/Runner/Info.plist').readAsStringSync();

    expect(
      File(
        'ios/Runner.xcodeproj/xcshareddata/xcschemes/chessevertest.xcscheme',
      ).existsSync(),
      isTrue,
    );
    expect(
      project,
      contains('PRODUCT_BUNDLE_IDENTIFIER = com.chessever.app.test'),
    );
    expect(project, contains('APP_DISPLAY_NAME = "ChessEver Test"'));
    expect(project, contains('GoogleService-Info-test.plist'));
    expect(project, contains('name = "Select Firebase configuration"'));
    expect(project, contains('name = "Debug-chessevertest"'));
    expect(project, contains('name = "Profile-chessevertest"'));
    expect(project, contains('name = "Release-chessevertest"'));
    expect(
      'name = "Debug-chessevertest"'.allMatches(project).length,
      greaterThanOrEqualTo(4),
    );
    expect(info, contains(r'<string>$(APP_DISPLAY_NAME)</string>'));
    expect(info, contains(r'<string>$(AUTH_REDIRECT_SCHEME)</string>'));
  });

  test('production remains the default flavor for existing build commands', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final project =
        File('ios/Runner.xcodeproj/project.pbxproj').readAsStringSync();

    expect(pubspec, contains('default-flavor: production'));
    expect(
      File(
        'ios/Runner.xcodeproj/xcshareddata/xcschemes/production.xcscheme',
      ).existsSync(),
      isTrue,
    );
    expect(project, contains('name = "Debug-production"'));
    expect(project, contains('name = "Profile-production"'));
    expect(project, contains('name = "Release-production"'));
    expect(
      'name = "Debug-production"'.allMatches(project).length,
      greaterThanOrEqualTo(4),
    );
  });
}
