import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/dismiss_keyboard.dart';
import 'package:chessever2/widgets/search/enhanced_rounded_search_bar.dart';
import 'package:chessever2/widgets/search/recent_searches_provider.dart';
import 'package:chessever2/widgets/search/search_overlay_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class _MemoryStorage implements RecentSearchStorage {
  @override
  Future<String?> read() async => null;

  @override
  Future<void> write(String value) async {}
}

/// Counts how many times the search field's own subtree is rebuilt, so a test
/// can prove focus does not churn the [TextField] (and with it the IME).
class _BuildCounter extends StatelessWidget {
  const _BuildCounter({required this.onBuild, required this.child});

  final VoidCallback onBuild;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    onBuild();
    return child;
  }
}

class _Harness extends StatefulWidget {
  const _Harness({required this.onFieldBuild});

  final VoidCallback onFieldBuild;

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  final controller = TextEditingController();
  final focusNode = FocusNode();

  @override
  void dispose() {
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
            _BuildCounter(
              onBuild: widget.onFieldBuild,
              child: EnhancedRoundedSearchBar(
                controller: controller,
                focusNode: focusNode,
                showFilter: false,
              ),
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

Widget _app(VoidCallback onFieldBuild) {
  return ProviderScope(
    overrides: [
      recentSearchStorageProvider.overrideWithValue(_MemoryStorage()),
    ],
    child: MaterialApp(
      theme: AppTheme.darkTheme,
      builder:
          (context, child) =>
              DismissKeyboard(child: child ?? const SizedBox.shrink()),
      home: _Harness(onFieldBuild: onFieldBuild),
    ),
  );
}

void main() {
  testWidgets('focus reveals the prebuilt results subtree', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_app(() {}));
    await tester.pump();

    final includingOffstage = find.byType(SearchOverlay, skipOffstage: false);
    expect(includingOffstage, findsOneWidget);
    expect(find.byType(SearchOverlay), findsNothing);
    final elementBeforeFocus = tester.element(includingOffstage);

    await tester.tap(find.byType(TextField));
    await tester.pump();

    expect(find.byType(SearchOverlay), findsOneWidget);
    expect(
      identical(tester.element(includingOffstage), elementBeforeFocus),
      isTrue,
      reason: 'focus replaced the prebuilt results element',
    );
  });

  testWidgets('the morph stops ticking once it is visually at rest', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_app(() {}));
    await tester.pump();

    await tester.tap(find.byType(TextField));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // Springs approach their target asymptotically and would otherwise keep
    // scheduling frames for hundreds of milliseconds after the motion is over.
    // Every one of those is a wasted frame at 120Hz.
    expect(
      tester.binding.transientCallbackCount,
      0,
      reason: 'the focus morph is still ticking after it has settled',
    );

    await tester.tapAt(const Offset(380, 800));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(
      tester.binding.transientCallbackCount,
      0,
      reason: 'the collapse is still ticking after it has settled',
    );
    expect(find.byType(SearchOverlay), findsNothing);
  });

  testWidgets('focus and the keyboard never rebuild the text field', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    addTearDown(tester.view.resetViewInsets);

    var fieldBuilds = 0;
    await tester.pumpWidget(_app(() => fieldBuilds++));
    await tester.pump();

    final buildsBeforeFocus = fieldBuilds;

    await tester.tap(find.byType(TextField));
    // Every frame of the morph, plus the frames of the keyboard sliding up.
    for (var elapsed = 0; elapsed < 400; elapsed += 16) {
      tester.view.viewInsets = FakeViewPadding(
        bottom: (elapsed * 0.75).clamp(0, 300).toDouble(),
      );
      await tester.pump(const Duration(milliseconds: 16));
    }

    // Rebuilding here would rebuild the TextField, which churns the IME and
    // re-lays out the text on every frame of the animation.
    expect(
      fieldBuilds,
      buildsBeforeFocus,
      reason: 'taking focus rebuilt the search field subtree',
    );
    expect(find.byType(SearchOverlay), findsOneWidget);
  });

  testWidgets('nothing jumps or reverses across the morph', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_app(() {}));
    await tester.pump();

    final surface = find.byKey(const ValueKey('simple-search-field-surface'));
    final content = find.byKey(const ValueKey('home-content'));

    /// One 120Hz frame's worth of geometry: the field, then the page below.
    List<Rect> sample() => [tester.getRect(surface), tester.getRect(content)];

    void check(List<List<Rect>> frames, {required bool expanding}) {
      final fieldHeight = frames.first[0].height;
      for (var i = 1; i < frames.length; i++) {
        final previous = frames[i - 1];
        final current = frames[i];

        // The row's height is set by the 44.w avatar. Dropping the avatar from
        // the tree at the end of the squeeze used to take 40dp out of the row
        // in one frame, snapping the panel and the whole page below it.
        expect(
          current[0].height,
          closeTo(fieldHeight, 0.01),
          reason: 'the field changed height mid-morph at frame $i',
        );

        final travelled = current[1].top - previous[1].top;
        expect(
          expanding ? travelled : -travelled,
          greaterThanOrEqualTo(-0.01),
          reason: 'the page below reversed direction at frame $i',
        );
        expect(
          travelled.abs(),
          lessThan(12),
          reason: 'the page below jumped ${travelled.abs()}dp in one frame',
        );

        final slid = current[0].left - previous[0].left;
        expect(
          expanding ? -slid : slid,
          greaterThanOrEqualTo(-0.01),
          reason: 'the field reversed direction at frame $i',
        );
      }
    }

    final field = find.byType(TextField);
    await tester.tap(field);
    final opening = <List<Rect>>[];
    for (var i = 0; i < 50; i++) {
      await tester.pump(const Duration(milliseconds: 8));
      opening.add(sample());
    }
    check(opening, expanding: true);

    await tester.tapAt(const Offset(380, 800));
    final closing = <List<Rect>>[];
    for (var i = 0; i < 50; i++) {
      await tester.pump(const Duration(milliseconds: 8));
      closing.add(sample());
    }
    check(closing, expanding: false);
  });

  testWidgets('the panel holds one height while the keyboard slides in', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    addTearDown(tester.view.resetViewInsets);

    await tester.pumpWidget(_app(() {}));
    await tester.pump();
    await tester.tap(find.byType(TextField));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final settled = tester.getRect(find.byType(SearchOverlay));

    // The panel's height must not be a function of the keyboard inset: reading
    // it made the whole results tree rebuild on every frame of the slide, on
    // the same frames the panel was unrolling.
    for (final inset in [0.0, 90.0, 210.0, 300.0]) {
      tester.view.viewInsets = FakeViewPadding(bottom: inset);
      await tester.pump();
      expect(tester.getRect(find.byType(SearchOverlay)), settled);
    }
  });
}
