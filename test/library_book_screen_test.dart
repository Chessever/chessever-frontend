import 'package:chessever2/repository/library/library_book_publication.dart';
import 'package:chessever2/repository/library/models/library_folder.dart';
import 'package:chessever2/screens/library/library_book_screen.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class _Publisher implements LibraryBookPublisher {
  @override
  bool get isConfigured => true;
  @override
  Future<void> unpublishTree(LibraryFolder folder) async {}
  LibraryBookPublication publication = const LibraryBookPublication(
    status: 'unpublished',
    metadata: LibraryBookMetadata(
      title: 'My study',
      author: 'Owner',
      about: 'A chess study',
    ),
  );
  final saves =
      <({LibraryBookMetadata metadata, bool publish, bool refreshGames})>[];
  bool fail = false;
  int withdrawals = 0;
  @override
  Future<LibraryBookPublication> load(LibraryFolder folder) async =>
      publication;
  @override
  Future<LibraryBookPublication> save(
    LibraryFolder folder,
    LibraryBookMetadata metadata, {
    bool publish = false,
    bool refreshGames = false,
  }) async {
    saves.add((
      metadata: metadata,
      publish: publish,
      refreshGames: refreshGames,
    ));
    if (fail) {
      throw const LibraryBookPublicationException(
        'Offline. Retry when connected.',
      );
    }
    return publication = LibraryBookPublication(
      status: 'draft',
      metadata: metadata,
      gameCount: 2,
    );
  }

  @override
  Future<LibraryBookPublication> unpublish(LibraryFolder folder) async {
    withdrawals++;
    return publication = LibraryBookPublication(
      status: 'archived',
      metadata: publication.metadata,
    );
  }
}

Future<void> _pump(
  WidgetTester tester,
  _Publisher publisher, {
  double width = 390,
}) async {
  tester.view.physicalSize = Size(width, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [libraryBookPublisherProvider.overrideWithValue(publisher)],
      child: MaterialApp(
        theme: AppTheme.darkTheme,
        home: Builder(
          builder: (context) {
            ResponsiveHelper.init(context);
            return LibraryBookScreen(
              folder: LibraryFolder(
                id: 'folder',
                userId: 'owner',
                name: 'My study',
                color: '#000000',
                icon: 'folder',
                orderIndex: 0,
                createdAt: DateTime(2026),
                updatedAt: DateTime(2026),
              ),
            );
          },
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, String text) async {
  final list = find
      .descendant(
        of: find.byType(SingleChildScrollView).first,
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Scrollable &&
              widget.axisDirection == AxisDirection.down,
        ),
      )
      .first;
  await tester.scrollUntilVisible(find.text(text), 300, scrollable: list);
  await tester.ensureVisible(find.text(text).last);
  await tester.pumpAndSettle();
  await tester.tap(find.text(text).last);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('title stays validated after scrolling down to the actions', (
    tester,
  ) async {
    final publisher = _Publisher();
    await _pump(tester, publisher, width: 320);
    await tester.enterText(find.byType(TextFormField).first, '');
    await _tap(tester, 'Submit for approval');
    expect(publisher.saves, isEmpty);
    expect(
      find.text('Check the highlighted book details before saving.'),
      findsOneWidget,
    );
  });

  testWidgets('saving a draft never makes the private folder public', (
    tester,
  ) async {
    final publisher = _Publisher();
    await _pump(tester, publisher, width: 320);
    await _tap(tester, 'Save private draft');
    expect(publisher.saves.single.publish, isFalse);
    expect(publisher.saves.single.refreshGames, isFalse);
    expect(publisher.publication.status, 'draft');
    expect(tester.takeException(), isNull);
  });

  testWidgets('publish failure keeps entered metadata and retry publishes it', (
    tester,
  ) async {
    final publisher = _Publisher()..fail = true;
    await _pump(tester, publisher);
    await tester.enterText(
      find.byType(TextFormField).first,
      'My Sicilian study',
    );
    await _tap(tester, 'Submit for approval');
    expect(find.text('Offline. Retry when connected.'), findsOneWidget);
    expect(publisher.saves.single.metadata.title, 'My Sicilian study');
    publisher.fail = false;
    await _tap(tester, 'Submit for approval');
    expect(publisher.saves.last.publish, isTrue);
    expect(publisher.saves.last.refreshGames, isTrue);
    expect(publisher.publication.metadata.title, 'My Sicilian study');
    expect(publisher.publication.isPublished, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'published edits return to review with the current folder games',
    (tester) async {
      final publisher = _Publisher()
        ..publication = const LibraryBookPublication(
          status: 'published',
          metadata: LibraryBookMetadata(
            title: 'Public study',
            author: 'Owner',
            about: 'A chess study',
          ),
          gameCount: 2,
        );
      await _pump(tester, publisher);
      await _tap(tester, 'Submit changes');
      expect(publisher.saves.single.publish, isTrue);
      expect(publisher.saves.single.refreshGames, isTrue);
      expect(publisher.publication.isPublished, isFalse);
      expect(tester.takeException(), isNull);
    },
  );
}
