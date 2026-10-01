import 'package:chessever2/repository/library/library_book_publication.dart';
import 'package:chessever2/repository/library/models/library_folder.dart';
import 'package:chessever2/screens/library/library_book_screen.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:chessever2/repository/library/collection_cover.dart';
import 'dart:convert';
import 'dart:typed_data';

Uint8List? pickedCover;

/// A valid 1×1 PNG, so the instant preview can decode it.
final _onePixelPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
);

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
      bookId: 'book-1',
      gameCount: 2,
    );
  }

  final covers = <Uint8List>[];
  int coverRemovals = 0;
  @override
  Future<LibraryBookPublication> uploadCover(
    LibraryFolder folder,
    Uint8List image,
  ) async {
    covers.add(image);
    return publication = LibraryBookPublication(
      status: 'draft',
      bookId: publication.bookId,
      metadata: LibraryBookMetadata(
        title: publication.metadata.title,
        author: publication.metadata.author,
        about: publication.metadata.about,
        coverUrl: 'https://media.example.invalid/cover.webp',
      ),
    );
  }

  @override
  Future<LibraryBookPublication> removeCover(LibraryFolder folder) async {
    coverRemovals++;
    return publication = LibraryBookPublication(
      status: 'draft',
      bookId: publication.bookId,
      metadata: LibraryBookMetadata(
        title: publication.metadata.title,
        author: publication.metadata.author,
        about: publication.metadata.about,
      ),
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
      overrides: [
        libraryBookPublisherProvider.overrideWithValue(publisher),
        collectionCoverPickerProvider.overrideWithValue(
          () async => pickedCover,
        ),
      ],
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
  // A focused field's caret scrolls itself back into view a frame later,
  // which would pull the target off-screen after it was scrolled to.
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
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
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('title stays validated after scrolling down to the actions', (
    tester,
  ) async {
    final publisher = _Publisher();
    await _pump(tester, publisher, width: 320);
    await tester.enterText(find.byType(TextFormField).first, '');
    await _tap(tester, 'Submit for approval');
    expect(publisher.saves, isEmpty);
    expect(
      find.text('Check the highlighted collection details before saving.'),
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
    await tester.pumpAndSettle();
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

  testWidgets('foreword and publisher are not asked for but survive a save', (
    tester,
  ) async {
    final publisher = _Publisher()
      ..publication = const LibraryBookPublication(
        status: 'unpublished',
        metadata: LibraryBookMetadata(
          title: 'My study',
          author: 'Owner',
          about: 'A chess study',
          foreword: 'Kept foreword',
          publisher: 'ChessEver',
        ),
      );
    await _pump(tester, publisher);
    expect(find.text('Foreword'), findsNothing);
    expect(find.text('Publisher'), findsNothing);
    expect(find.text('Optional'), findsNWidgets(3));
    await _tap(tester, 'Save private draft');
    expect(publisher.saves.single.metadata.foreword, 'Kept foreword');
    expect(publisher.saves.single.metadata.publisher, 'ChessEver');
  });

  testWidgets('preview follows what is typed', (tester) async {
    final publisher = _Publisher();
    await _pump(tester, publisher);
    final preview = find.byKey(const ValueKey('book_preview'));
    expect(
      find.descendant(of: preview, matching: find.text('by Owner')),
      findsOneWidget,
    );
    await tester.enterText(find.byType(TextFormField).first, 'Endgame Gems');
    await tester.pump();
    expect(
      find.descendant(of: preview, matching: find.text('Endgame Gems')),
      findsOneWidget,
    );
    // Editing the subtitle turns the preview to the page, where it shows.
    await tester.enterText(find.byType(TextFormField).at(1), 'Forty wins');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('book_preview_page')), findsOneWidget);
    expect(
      find.descendant(of: preview, matching: find.text('Forty wins')),
      findsOneWidget,
    );
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

  testWidgets('author capitalizes every word and text stays tidy', (
    tester,
  ) async {
    final publisher = _Publisher();
    await _pump(tester, publisher);
    final author = find.byType(TextField).at(2);
    expect(
      tester.widget<TextField>(author).textCapitalization,
      TextCapitalization.words,
    );
    await tester.enterText(author, '  Jason   Statham 42');
    await tester.enterText(find.byType(TextField).first, ' Endgame   Gems');
    await tester.pump();
    expect(tester.widget<TextField>(author).controller!.text, 'Jason Statham ');
    expect(
      tester.widget<TextField>(find.byType(TextField).first).controller!.text,
      'Endgame Gems',
    );
  });

  testWidgets('a saved author pre-fills the next fresh collection', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'library_book.last_author': 'Jason Statham',
    });
    final publisher = _Publisher()
      ..publication = const LibraryBookPublication(
        status: 'draft',
        metadata: LibraryBookMetadata(title: 'Fresh'),
      );
    await _pump(tester, publisher);
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField).at(2)).controller!.text,
      'Jason Statham',
    );
  });

  testWidgets('unsubmitted edits are offered back on the next visit', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'library_book.draft.folder':
          '{"title":"Half-done study","author":"Owner","about":"A chess study"}',
    });
    final publisher = _Publisher();
    await _pump(tester, publisher);
    await tester.pumpAndSettle();
    expect(find.text('Continue where you left off?'), findsOneWidget);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField).first).controller!.text,
      'Half-done study',
    );
    await _tap(tester, 'Save private draft');
    expect(publisher.saves.single.metadata.title, 'Half-done study');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('library_book.draft.folder'), isNull);
  });

  testWidgets('no prompt when the stored draft matches the saved details', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'library_book.draft.folder':
          '{"title":"My study","author":"Owner","about":"A chess study"}',
    });
    await _pump(tester, _Publisher());
    await tester.pumpAndSettle();
    expect(find.text('Continue where you left off?'), findsNothing);
  });

  testWidgets('a picked cover is uploaded, never typed as a link', (
    tester,
  ) async {
    pickedCover = _onePixelPng;
    addTearDown(() => pickedCover = null);
    final publisher = _Publisher();
    await _pump(tester, publisher);
    expect(find.text('Cover image link'), findsNothing);
    await _tap(tester, 'Choose from gallery');
    // Never saved: the details are saved privately first, then the cover.
    expect(publisher.saves.single.publish, isFalse);
    expect(publisher.covers.single, pickedCover);
    expect(find.text('Replace photo'), findsOneWidget);
    // Later saves carry the uploaded cover through.
    await _tap(tester, 'Save private draft');
    expect(
      publisher.saves.last.metadata.coverUrl,
      'https://media.example.invalid/cover.webp',
    );
    await _tap(tester, 'Remove cover');
    expect(publisher.coverRemovals, 1);
    expect(find.text('Choose from gallery'), findsOneWidget);
  });
}
