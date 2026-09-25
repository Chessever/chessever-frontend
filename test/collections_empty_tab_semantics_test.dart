import 'package:chessever2/repository/gamebase/gamebase_repository.dart';
import 'package:chessever2/screens/collections/collections_data.dart';
import 'package:chessever2/screens/collections/collections_screen.dart';
import 'package:chessever2/screens/my_space/models/space_shortcut.dart';
import 'package:chessever2/screens/my_space/providers/space_shortcuts_provider.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Discovery › Collection with a tab that has nothing in it (no books
/// published yet, or no collections at all).
///
/// The empty tab's notice is itself a vertical list (so it can be pulled to
/// refresh on its own). It used to be built as the only item of the tab's
/// card list, which hands it unbounded height: "Vertical viewport was given
/// unbounded height", and after that one layout error the framework leaves
/// the half-laid-out subtree's semantics parent data dirty, so every later
/// frame fails `!semantics.parentDataDirty` (object.dart) until the screen
/// goes away. The notice must be the tab's own scrollable instead.

class _FakeCollections extends CollectionsRepository {
  _FakeCollections(this.all) : super(GamebaseRepository(Dio(), apiKey: 'test'));

  final List<Collection> all;
  int fetches = 0;

  @override
  Future<List<Collection>> fetchCollections() async {
    fetches++;
    return all;
  }
}

class _NoShortcuts extends SpaceShortcutsNotifier {
  @override
  Future<List<SpaceShortcut>> build() async => const [];
}

const _event = Collection(
  id: 'c1',
  slug: 'zurich-1953-event',
  kind: CollectionKind.event,
  title: 'Zurich 1953',
  gameCount: 210,
);

/// Every FlutterError the test raises, reported or thrown.
class _Errors {
  _Errors() {
    _previous = FlutterError.onError;
    FlutterError.onError = (details) => seen.add(details);
  }

  late final void Function(FlutterErrorDetails)? _previous;
  final List<FlutterErrorDetails> seen = [];

  void restore() => FlutterError.onError = _previous;

  /// Each distinct error once, with how many frames raised it.
  String describe() {
    final counts = <String, int>{};
    for (final e in seen) {
      final line = e.exceptionAsString().split('\n').first;
      counts[line] = (counts[line] ?? 0) + 1;
    }
    return [for (final e in counts.entries) '${e.value}x ${e.key}'].join('\n');
  }
}

Future<_FakeCollections> _pump(
  WidgetTester tester,
  List<Collection> all,
) async {
  tester.view.physicalSize = const Size(402, 874);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final repo = _FakeCollections(all);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        collectionsRepositoryProvider.overrideWithValue(repo),
        spaceShortcutsProvider.overrideWith(_NoShortcuts.new),
      ],
      child: MaterialApp(
        // Pinned to the variant's platform: the shared theme would keep the
        // first variant's platform (and its scroll physics) for every run.
        theme: AppTheme.darkTheme.copyWith(platform: defaultTargetPlatform),
        home: Builder(
          builder: (context) {
            ResponsiveHelper.init(context);
            return const CollectionsScreen();
          },
        ),
      ),
    ),
  );
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
  return repo;
}

/// Frames after the tab settles: the loop fails on each one of them.
Future<void> _frames(WidgetTester tester, [int count = 20]) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

/// No render object reachable for semantics is left with dirty semantics
/// parent data (what the framework's own debug check asserts every frame).
void _expectSemanticsClean(WidgetTester tester) {
  final dirty = <RenderObject>[];
  void walk(RenderObject node) {
    if (node.debugNeedsSemanticsUpdate) dirty.add(node);
    node.visitChildrenForSemantics(walk);
  }

  walk(tester.binding.renderViews.first);
  expect(
    dirty,
    isEmpty,
    reason: 'render objects left with dirty semantics parent data',
  );
}

/// The owner hit it on iOS; the test default is Android. Both scroll
/// chromes differ (bounce vs stretch), so both are driven.
final _platforms = TargetPlatformVariant(const {
  TargetPlatform.android,
  TargetPlatform.iOS,
});

void main() {
  testWidgets('an empty Books tab shows its notice with no layout or '
      'semantics error, frame after frame', (tester) async {
    final handle = tester.ensureSemantics();
    final errors = _Errors();
    try {
      await _pump(tester, const [_event]);
      expect(find.text('Zurich 1953'), findsOneWidget);

      await tester.tap(find.text('Books'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await _frames(tester);
      // First, so a regression names its cause (the layout error, then the
      // semantics check failing on every frame) rather than a finder miss.
      expect(errors.seen, isEmpty, reason: errors.describe());

      expect(find.text('No books yet.'), findsOneWidget);
      expect(find.bySemanticsLabel('No books yet.'), findsOneWidget);
      _expectSemanticsClean(tester);

      // Back and forth: the rebuilt tab stays clean too.
      await tester.tap(find.text('Events'));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('Books'));
      await tester.pump(const Duration(milliseconds: 400));
      await _frames(tester);
      _expectSemanticsClean(tester);
    } finally {
      errors.restore();
    }
    expect(tester.takeException(), isNull);
    expect(errors.seen, isEmpty, reason: errors.describe());
    handle.dispose();
  }, variant: _platforms);

  testWidgets('with no collections at all, the Events tab opens on its '
      'notice cleanly and still pulls to refresh', (tester) async {
    final handle = tester.ensureSemantics();
    final errors = _Errors();
    late _FakeCollections repo;
    try {
      repo = await _pump(tester, const []);
      await _frames(tester);
      expect(errors.seen, isEmpty, reason: errors.describe());

      expect(find.text('No annotated events yet.'), findsOneWidget);
      expect(find.bySemanticsLabel('No annotated events yet.'), findsOneWidget);
      _expectSemanticsClean(tester);

      final before = repo.fetches;
      await tester.fling(
        find.text('No annotated events yet.'),
        const Offset(0, 320),
        1200,
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      await _frames(tester);
      expect(repo.fetches, greaterThan(before));
      _expectSemanticsClean(tester);
    } finally {
      errors.restore();
    }
    expect(tester.takeException(), isNull);
    expect(errors.seen, isEmpty, reason: errors.describe());
    handle.dispose();
  }, variant: _platforms);
}
