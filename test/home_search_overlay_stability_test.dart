import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/dismiss_keyboard.dart';
import 'package:chessever2/widgets/search/enhanced_rounded_search_bar.dart';
import 'package:chessever2/widgets/search/recent_searches_provider.dart';
import 'package:chessever2/widgets/search/search_overlay_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class _MemoryStorage implements RecentSearchStorage {
  _MemoryStorage(this.value);

  final String? value;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String value) async {}
}

class _SearchPageHarness extends StatefulWidget {
  const _SearchPageHarness({this.emulateHomeProfile = false});

  final bool emulateHomeProfile;

  @override
  State<_SearchPageHarness> createState() => _SearchPageHarnessState();
}

class _SearchPageHarnessState extends State<_SearchPageHarness> {
  final controller = TextEditingController();
  final focusNode = FocusNode();
  bool isSearching = false;

  @override
  void initState() {
    super.initState();
    focusNode.addListener(_handleFocusChange);
  }

  void _handleFocusChange() {
    setState(() => isSearching = focusNode.hasFocus);
  }

  @override
  void dispose() {
    focusNode.removeListener(_handleFocusChange);
    focusNode.dispose();
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ResponsiveHelper.init(context);
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.only(top: 40),
        child: Column(
          children: [
            EnhancedRoundedSearchBar(
              controller: controller,
              focusNode: focusNode,
              showProfile: widget.emulateHomeProfile && !isSearching,
              showFilter: false,
            ),
            const SizedBox(
              key: ValueKey('home-content'),
              height: 100,
              width: double.infinity,
            ),
          ],
        ),
      ),
    );
  }
}

Widget _app(RecentSearchStorage storage, {bool emulateHomeProfile = false}) {
  return ProviderScope(
    overrides: [recentSearchStorageProvider.overrideWithValue(storage)],
    child: MaterialApp(
      theme: AppTheme.darkTheme,
      builder:
          (context, child) =>
              DismissKeyboard(child: child ?? const SizedBox.shrink()),
      home: _SearchPageHarness(emulateHomeProfile: emulateHomeProfile),
    ),
  );
}

void main() {
  testWidgets('first focus expands the search field in one smooth motion, '
      'its end giving Cancel room on the same spring', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      _app(_MemoryStorage(null), emulateHomeProfile: true),
    );
    await tester.pump();
    final field = find.byType(TextField);
    final surface = find.byKey(const ValueKey('simple-search-field-surface'));
    final cancel = find.byKey(const ValueKey('search_field_cancel'));
    final initialRect = tester.getRect(surface);
    expect(cancel, findsNothing);

    await tester.tap(field);
    await tester.pump();

    final leftEdges = <double>[initialRect.left];
    final rightEdges = <double>[initialRect.right];
    for (var elapsed = 0; elapsed < 300; elapsed += 30) {
      await tester.pump(const Duration(milliseconds: 30));
      final rect = tester.getRect(surface);
      leftEdges.add(rect.left);
      rightEdges.add(rect.right);
    }

    // The avatar squeezes out at the start and Cancel's room opens at the
    // end: each edge only ever travels one way, never back.
    for (var index = 1; index < leftEdges.length; index++) {
      expect(leftEdges[index], lessThanOrEqualTo(leftEdges[index - 1]));
      expect(
        rightEdges[index],
        lessThanOrEqualTo(rightEdges[index - 1] + 0.01),
      );
    }
    expect(leftEdges.last, lessThan(initialRect.left - 40));
    // On its way, not there in one frame.
    expect(rightEdges[1], lessThan(initialRect.right - 1));
    expect(rightEdges[1], greaterThan(rightEdges.last + 1));

    await tester.pump(const Duration(milliseconds: 100));
    final settled = tester.getRect(surface);
    expect(settled.left, closeTo(leftEdges.last, 0.5));
    // At rest the field ends where Cancel starts: it gave up exactly the
    // word's room, and the word stands outside it.
    final word = tester.getRect(cancel);
    expect(settled.right, closeTo(word.left, 0.01));
    expect(initialRect.right - settled.right, closeTo(word.width, 0.01));
    expect(word.right, closeTo(initialRect.right, 0.01));
  });

  testWidgets('results expand smoothly between search and homepage content', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    addTearDown(tester.view.resetViewInsets);

    await tester.pumpWidget(_app(_MemoryStorage(null)));
    await tester.pump();
    final content = find.byKey(const ValueKey('home-content'));
    final topBeforeFocus = tester.getTopLeft(content).dy;

    await tester.tap(find.byType(TextField));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final topDuringExpansion = tester.getTopLeft(content).dy;
    await tester.pump(const Duration(milliseconds: 250));
    final topAfterExpansion = tester.getTopLeft(content).dy;

    expect(topDuringExpansion, greaterThan(topBeforeFocus + 1));
    expect(topDuringExpansion, lessThan(topAfterExpansion - 1));
    expect(topAfterExpansion, greaterThan(topBeforeFocus + 40));
    expect(
      find.text('Search players, tournaments, openings, or ECO codes'),
      findsOneWidget,
    );
    final fieldBottom = tester.getBottomLeft(find.byType(TextField)).dy;
    final resultsRect = tester.getRect(find.byType(SearchOverlay));
    expect(resultsRect.top, greaterThan(fieldBottom));
    expect(resultsRect.bottom, lessThanOrEqualTo(topAfterExpansion + 0.5));

    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pump();
    expect(tester.getTopLeft(content).dy, closeTo(topAfterExpansion, 0.5));
    tester.view.resetViewInsets();
    await tester.pump();
    expect(tester.getTopLeft(content).dy, closeTo(topAfterExpansion, 0.5));

    await tester.tap(find.byType(TextField));
    await tester.pump();
    expect(
      tester.widget<TextField>(find.byType(TextField)).focusNode?.hasFocus,
      isTrue,
    );
    expect(
      find.text('Search players, tournaments, openings, or ECO codes'),
      findsOneWidget,
    );

    await tester.tapAt(const Offset(380, 800));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final topDuringCollapse = tester.getTopLeft(content).dy;
    await tester.pump(const Duration(milliseconds: 250));

    expect(topDuringCollapse, lessThan(topAfterExpansion - 1));
    expect(topDuringCollapse, greaterThan(topBeforeFocus + 1));
    expect(tester.getTopLeft(content).dy, closeTo(topBeforeFocus, 0.5));
    expect(
      find.text('Search players, tournaments, openings, or ECO codes'),
      findsNothing,
    );
  });

  testWidgets('touching recent results keeps the field and keyboard focused', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final storage = _MemoryStorage(
      '[{"kind":"opening","targetId":"B9",'
      '"title":"Sicilian: Najdorf","subtitle":"B9 · B90–B99"}]',
    );

    await tester.pumpWidget(_app(storage));
    await tester.pump();
    await tester.tap(find.byType(TextField));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.focusNode?.hasFocus, isTrue);
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Sicilian: Najdorf')),
    );
    await tester.pump();

    expect(field.focusNode?.hasFocus, isTrue);
    expect(find.text('Recent searches'), findsOneWidget);
    await gesture.moveBy(const Offset(0, -20));
    await tester.pump();

    expect(field.focusNode?.hasFocus, isTrue);
    expect(find.text('Recent searches'), findsOneWidget);
    await gesture.up();
    await tester.pump();
    expect(field.focusNode?.hasFocus, isTrue);
  });

  testWidgets('one letter keeps recent searches instead of "No results"', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final storage = _MemoryStorage(
      '[{"kind":"opening","targetId":"B9",'
      '"title":"Sicilian: Najdorf","subtitle":"B9 · B90–B99"}]',
    );

    await tester.pumpWidget(_app(storage));
    await tester.pump();
    await tester.tap(find.byType(TextField));
    await tester.pump(const Duration(milliseconds: 350));

    await tester.enterText(find.byType(TextField), 'k');
    // Past every debounce on the path (bar, overlay) and the async result.
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.text('No results found'), findsNothing);
    expect(find.text('Recent searches'), findsOneWidget);
    expect(find.text('Sicilian: Najdorf'), findsOneWidget);
  });

  testWidgets('tapping outside the complete search control dismisses focus', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_app(_MemoryStorage(null)));
    await tester.pump();
    await tester.tap(find.byType(TextField));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.enterText(find.byType(TextField), "King's indian");
    await tester.pump(const Duration(milliseconds: 450));

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.focusNode?.hasFocus, isTrue);
    // The family row reads "E60-E99  ★ All  King's Indian" as one line.
    expect(find.textContaining("King's Indian"), findsWidgets);
    expect(find.textContaining('E60-E99'), findsOneWidget);
    expect(find.textContaining('E6+E7+E8+E9'), findsNothing);

    await tester.tapAt(const Offset(380, 800));
    await tester.pump();

    expect(field.focusNode?.hasFocus, isFalse);
  });

  testWidgets('the circled x is in the field only while it holds text, and '
      'empties it without letting the keyboard go', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_app(_MemoryStorage(null)));
    await tester.pump();
    final surface = find.byKey(const ValueKey('simple-search-field-surface'));
    final clear = find.descendant(
      of: surface,
      matching: find.byKey(const ValueKey('search_field_clear')),
    );
    final cancel = find.byKey(const ValueKey('search_field_cancel'));

    await tester.tap(find.byType(TextField));
    await _frames(tester);
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.focusNode?.hasFocus, isTrue);
    // The cursor in an empty field: nothing to clear.
    expect(clear.hitTestable(), findsNothing);

    await tester.enterText(find.byType(TextField), 'carlsen');
    await _frames(tester);
    expect(clear.hitTestable(), findsOneWidget);
    final frame = tester.getRect(surface);
    final x = tester.getRect(clear);
    expect(x.right, lessThanOrEqualTo(frame.right + 0.01));
    expect(x.center.dy, closeTo(frame.center.dy, 0.5));
    expect(x.right, lessThanOrEqualTo(tester.getRect(cancel).left + 0.01));

    final platformCalls = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.textInput,
      (call) async {
        platformCalls.add(call.method);
        return null;
      },
    );
    addTearDown(tester.testTextInput.register);

    // Through the app's tap-outside dismisser, as every tap in the app is.
    final gesture = await tester.startGesture(tester.getCenter(clear));
    await tester.pump();
    expect(
      field.focusNode?.hasFocus,
      isTrue,
      reason: 'pressing the x must not drop the keyboard before it clears',
    );
    await gesture.up();
    await tester.pump();

    expect(field.controller?.text, isEmpty);
    expect(field.focusNode?.hasFocus, isTrue);
    expect(platformCalls, isNot(contains('TextInput.hide')));
    expect(platformCalls, isNot(contains('TextInput.clearClient')));
    await _frames(tester);
    // Cancel stays while the field has the cursor; the x is gone with the
    // words.
    expect(cancel, findsOneWidget);
    expect(clear.hitTestable(), findsNothing);
  });

  testWidgets('Cancel explicitly hides a stubborn iOS keyboard', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_app(_MemoryStorage(null)));
    await tester.pump();
    await tester.tap(find.byType(TextField));
    await _frames(tester);

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.focusNode?.hasFocus, isTrue);
    expect(tester.testTextInput.isVisible, isTrue);

    // Model the iOS race from the device report: the global pointer-down
    // handler clears the framework client, but the native keyboard remains
    // first responder until it receives an explicit TextInput.hide.
    var platformKeyboardVisible = true;
    var orphanedNativeInputView = false;
    final platformCalls = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.textInput,
      (call) async {
        platformCalls.add(call.method);
        if (call.method == 'TextInput.clearClient' && platformKeyboardVisible) {
          orphanedNativeInputView = true;
        } else if (call.method == 'TextInput.hide' &&
            !orphanedNativeInputView) {
          platformKeyboardVisible = false;
        }
        return null;
      },
    );
    addTearDown(tester.testTextInput.register);

    // Cancel stands outside the field, the plain word, its lead-in part of
    // its tap: pressed at its leading edge.
    final cancel = find.byKey(const ValueKey('search_field_cancel'));
    expect(cancel, findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('simple-search-field-surface')),
        matching: cancel,
      ),
      findsNothing,
    );
    expect(
      find.descendant(of: cancel, matching: find.text('Cancel')),
      findsOneWidget,
    );
    final cancelRect = tester.getRect(cancel);
    await tester.tapAt(Offset(cancelRect.left + 2, cancelRect.center.dy));
    await tester.pump();

    expect(field.focusNode?.hasFocus, isFalse);
    expect(platformCalls, contains('TextInput.clearClient'));
    expect(
      platformCalls.indexOf('TextInput.hide'),
      lessThan(platformCalls.indexOf('TextInput.clearClient')),
      reason: 'The native keyboard must resign before its client is cleared.',
    );
    expect(
      platformKeyboardVisible,
      isFalse,
      reason:
          'Losing Flutter focus is insufficient when iOS keeps its native '
          'text input view first responder.',
    );
  });
}

/// Pumps the springs home frame by frame: a spring that starts on a frame
/// only moves on the frames after it.
Future<void> _frames(WidgetTester tester) async {
  for (var i = 0; i < 30; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}
