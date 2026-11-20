import 'package:chessever2/utils/app_motion.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// What the app below [AppMotionAlwaysOn] reads, under system [flags].
Future<({bool disabled, bool screenReader})> _read(
  WidgetTester tester, {
  required bool disableAnimations,
  required bool accessibleNavigation,
}) async {
  late bool disabled;
  late bool screenReader;
  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(
        disableAnimations: disableAnimations,
        accessibleNavigation: accessibleNavigation,
      ),
      child: AppMotionAlwaysOn(
        child: Builder(
          builder: (context) {
            disabled = MediaQuery.disableAnimationsOf(context);
            screenReader = MediaQuery.accessibleNavigationOf(context);
            return const SizedBox();
          },
        ),
      ),
    ),
  );
  await tester.pump();
  return (disabled: disabled, screenReader: screenReader);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(
    () => messenger.setMockMethodCallHandler(kTouchExplorationChannel, null),
  );

  testWidgets('the system reduced-motion flag never reaches the app', (
    tester,
  ) async {
    final read = await _read(
      tester,
      disableAnimations: true,
      accessibleNavigation: false,
    );
    expect(read.disabled, isFalse);
  });

  testWidgets('Android: an accessibility service that is not a screen reader '
      'does not turn the app into screen-reader mode', (tester) async {
    // Flutter's flag is up (a password manager read the view tree), but
    // nothing explores the screen by touch.
    messenger.setMockMethodCallHandler(
      kTouchExplorationChannel,
      (call) async => false,
    );
    final read = await _read(
      tester,
      disableAnimations: false,
      accessibleNavigation: true,
    );
    expect(read.screenReader, isFalse);
  });

  testWidgets('Android: TalkBack (touch exploration) is honoured, and '
      'follows changes', (tester) async {
    messenger.setMockMethodCallHandler(
      kTouchExplorationChannel,
      (call) async => true,
    );
    var read = await _read(
      tester,
      disableAnimations: false,
      accessibleNavigation: false,
    );
    expect(read.screenReader, isTrue);

    // TalkBack turned off: the bridge says so.
    await messenger.handlePlatformMessage(
      kTouchExplorationChannel.name,
      kTouchExplorationChannel.codec.encodeMethodCall(
        const MethodCall('touchExplorationChanged', false),
      ),
      (_) {},
    );
    await tester.pump();
    read = await _read(
      tester,
      disableAnimations: false,
      accessibleNavigation: false,
    );
    expect(read.screenReader, isFalse);
  });

  testWidgets('iOS keeps the system value (VoiceOver only)', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final read = await _read(
      tester,
      disableAnimations: true,
      accessibleNavigation: true,
    );
    expect(read.disabled, isFalse);
    expect(read.screenReader, isTrue);
    debugDefaultTargetPlatformOverride = null;
  });
}
