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
  testWidgets('first focus expands the search field in one smooth motion', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      _app(_MemoryStorage(null), emulateHomeProfile: true),
    );
    await tester.pump();
    final field = find.byType(TextField);
    final surface = find.byKey(const ValueKey('simple-search-field-surface'));
    final initialRect = tester.getRect(surface);

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

    for (var index = 1; index < leftEdges.length; index++) {
      expect(leftEdges[index], lessThanOrEqualTo(leftEdges[index - 1]));
      expect(rightEdges[index], closeTo(rightEdges.first, 0.5));
    }
    expect(leftEdges.last, lessThan(initialRect.left - 40));

    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.getRect(surface).left, closeTo(leftEdges.last, 0.5));
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
    expect(find.text("King's Indian"), findsWidgets);
    expect(find.text('E60-E99'), findsOneWidget);
    expect(find.textContaining('E6+E7+E8+E9'), findsNothing);

    await tester.tapAt(const Offset(380, 800));
    await tester.pump();

    expect(field.focusNode?.hasFocus, isFalse);
  });

  testWidgets('clear suffix explicitly hides a stubborn iOS keyboard', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_app(_MemoryStorage(null)));
    await tester.pump();
    await tester.tap(find.byType(TextField));
    await tester.pump(const Duration(milliseconds: 350));

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

    final clearButton = find.descendant(
      of: find.byKey(const ValueKey('simple-search-field-surface')),
      matching: find.byIcon(Icons.close),
    );
    expect(clearButton, findsOneWidget);
    final clearGesture = find.ancestor(
      of: clearButton,
      matching: find.byType(GestureDetector),
    );
    expect(clearGesture, findsOneWidget);
    final clearRect = tester.getRect(clearGesture);
    await tester.tapAt(Offset(clearRect.left + 2, clearRect.center.dy));
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
