import 'dart:async';

import 'package:dio/dio.dart';
import 'package:chessever2/repository/library/library_book_publication.dart';
import 'package:chessever2/repository/library/models/library_folder.dart';
import 'package:chessever2/screens/library/library_book_screen.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:chessever2/screens/library/cover_cropper.dart';
import 'dart:convert';
import 'dart:typed_data';

Uint8List? pickedCover;
Uint8List? pickedAuthorPhoto;

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

  final authorPhotos = <Uint8List>[];
  int authorPhotoRemovals = 0;
  final suggestionQueries = <String>[];

  /// Answers name suggestions; a test may hold one back with a completer.
  Future<List<LibraryAuthorSuggestion>> Function(String name) suggest =
      (_) async => const [];

  LibraryBookPublication _withAuthorPhoto(String url) => LibraryBookPublication(
    status: 'draft',
    bookId: publication.bookId,
    metadata: LibraryBookMetadata(
      title: publication.metadata.title,
      author: publication.metadata.author,
      about: publication.metadata.about,
      coverUrl: publication.metadata.coverUrl,
      authorCredit: LibraryAuthorCredit.other,
      authorPhotoUrl: url,
    ),
  );

  @override
  Future<LibraryBookPublication> uploadAuthorPhoto(
    LibraryFolder folder,
    Uint8List image,
  ) async {
    authorPhotos.add(image);
    return publication = _withAuthorPhoto(
      'https://media.example.invalid/author.webp',
    );
  }

  @override
  Future<LibraryBookPublication> removeAuthorPhoto(LibraryFolder folder) async {
    authorPhotoRemovals++;
    return publication = _withAuthorPhoto('');
  }

  @override
  Future<List<LibraryAuthorSuggestion>> suggestAuthors(String name) {
    suggestionQueries.add(name);
    return suggest(name);
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
          (_) async => pickedCover,
        ),
        authorPhotoPickerProvider.overrideWithValue(
          (_) async => pickedAuthorPhoto,
        ),
        libraryAuthorProfilePhotoProvider.overrideWithValue(null),
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
    expect(find.text('Optional'), findsNWidgets(4));
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

  group('author credit', () {
    Finder authorField() => find.byType(TextField).at(2);

    Future<void> creditSomeoneElse(WidgetTester tester) async {
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Someone else'));
      await tester.tap(find.text('Someone else'));
      await tester.pumpAndSettle();
    }

    testWidgets('an older server never receives the credit key for "Me"', (
      tester,
    ) async {
      final publisher = _Publisher();
      await _pump(tester, publisher);
      await _tap(tester, 'Save private draft');
      final sent = publisher.saves.single.metadata;
      expect(sent.authorCredit, isNull);
      expect(sent.toJson().containsKey('authorCredit'), isFalse);
    });

    testWidgets('an older server never receives an empty description', (
      tester,
    ) async {
      // An older server refuses the key: an empty one is never sent.
      final older = _Publisher();
      await _pump(tester, older);
      expect(find.text('About the author'), findsOneWidget);
      await _tap(tester, 'Save private draft');
      expect(
        older.saves.single.metadata.toJson().containsKey('authorAbout'),
        isFalse,
      );
    });

    testWidgets('a server that knows descriptions gets the edited one back', (
      tester,
    ) async {
      // Null (an emptied field) clears what the collection wrote.
      final publisher = _Publisher()
        ..publication = LibraryBookPublication(
          status: 'draft',
          bookId: 'book-1',
          metadata: LibraryBookMetadata.fromJson(const {
            'title': 'My study',
            'author': 'Owner',
            'about': 'A chess study',
            'authorBio': 'Coach from Baku.',
          }),
        );
      await _pump(tester, publisher);
      expect(find.text('Coach from Baku.'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Coach from Baku.'),
        '  Coach and author.  ',
      );
      await _tap(tester, 'Save private draft');
      expect(
        publisher.saves.single.metadata.toJson()['authorAbout'],
        'Coach and author.',
      );
      expect(
        const LibraryBookMetadata(title: 'T', authorAbout: ' ').toJson(),
        containsPair('authorAbout', null),
      );
    });

    testWidgets('a server that knows credits gets "self" back for "Me"', (
      tester,
    ) async {
      final publisher = _Publisher()
        ..publication = const LibraryBookPublication(
          status: 'draft',
          bookId: 'book-1',
          metadata: LibraryBookMetadata(
            title: 'My study',
            author: 'Owner',
            about: 'A chess study',
            authorCredit: LibraryAuthorCredit.self,
          ),
        );
      await _pump(tester, publisher);
      await _tap(tester, 'Save private draft');
      expect(publisher.saves.single.metadata.toJson()['authorCredit'], 'self');
    });

    testWidgets(
      'crediting someone else clears a pre-filled own name and is not remembered',
      (tester) async {
        SharedPreferences.setMockInitialValues({
          'library_book.last_author': 'Jason Statham',
        });
        final publisher = _Publisher()
          ..publication = const LibraryBookPublication(
            status: 'draft',
            metadata: LibraryBookMetadata(title: 'Fresh', about: 'Games'),
          );
        await _pump(tester, publisher);
        await tester.pumpAndSettle();
        expect(
          tester.widget<TextField>(authorField()).controller!.text,
          'Jason Statham',
        );
        await creditSomeoneElse(tester);
        expect(tester.widget<TextField>(authorField()).controller!.text, '');
        expect(find.text('Author photo'), findsOneWidget);
        await tester.enterText(authorField(), 'Garry Kasparov');
        await tester.pump(const Duration(milliseconds: 400));
        await _tap(tester, 'Save private draft');
        final sent = publisher.saves.single.metadata;
        expect(sent.author, 'Garry Kasparov');
        expect(sent.toJson()['authorCredit'], 'other');
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString('library_book.last_author'), 'Jason Statham');
      },
    );

    testWidgets('a suggestion fills the exact spelling; stale answers lose', (
      tester,
    ) async {
      final slow = Completer<List<LibraryAuthorSuggestion>>();
      final publisher = _Publisher()
        ..suggest = (name) => name == 'Mag'
            ? slow.future
            : Future.value(const [
                LibraryAuthorSuggestion(
                  id: 'credit:1',
                  name: 'Magnus Carlsen',
                  bookCount: 3,
                ),
              ]);
      await _pump(tester, publisher);
      await creditSomeoneElse(tester);
      await tester.enterText(authorField(), 'Mag');
      await tester.pump(const Duration(milliseconds: 350));
      await tester.enterText(authorField(), 'magnus carl');
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      expect(find.text('Magnus Carlsen'), findsOneWidget);
      expect(find.text('3 collections'), findsOneWidget);
      // The slower answer for an older name arrives last and is ignored.
      slow.complete(const [
        LibraryAuthorSuggestion(id: 'credit:2', name: 'Magda Stale'),
      ]);
      await tester.pumpAndSettle();
      expect(find.text('Magda Stale'), findsNothing);
      await tester.tap(
        find.byKey(const ValueKey('book_author_suggestion_Magnus Carlsen')),
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(authorField()).controller!.text,
        'Magnus Carlsen',
      );
      expect(
        find.text('Matches an existing ChessEver author.'),
        findsOneWidget,
      );
      // Switching asks once for the name already there, then per pause.
      expect(publisher.suggestionQueries, ['Owner', 'Mag', 'magnus carl']);
    });

    testWidgets('an author photo is uploaded on pick, after a first save', (
      tester,
    ) async {
      pickedAuthorPhoto = _onePixelPng;
      addTearDown(() => pickedAuthorPhoto = null);
      final publisher = _Publisher();
      await _pump(tester, publisher);
      await creditSomeoneElse(tester);
      await tester.enterText(authorField(), 'Garry Kasparov');
      await tester.pump(const Duration(milliseconds: 400));
      // The cover has its own "Choose from gallery"; this is the author's.
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      final choose = find.byKey(const ValueKey('book_author_photo_choose'));
      await tester.ensureVisible(choose);
      await tester.pumpAndSettle();
      await tester.tap(choose);
      await tester.pumpAndSettle();
      // Never saved: saved privately first, credited to someone else.
      expect(publisher.saves.single.publish, isFalse);
      expect(publisher.saves.single.metadata.toJson()['authorCredit'], 'other');
      expect(publisher.authorPhotos.single, pickedAuthorPhoto);
      expect(publisher.covers, isEmpty);
      expect(find.text('Remove photo'), findsOneWidget);
      await _tap(tester, 'Remove photo');
      expect(publisher.authorPhotoRemovals, 1);
    });

    testWidgets('switching a credited book with a photo to Me warns first', (
      tester,
    ) async {
      final publisher = _Publisher()
        ..publication = const LibraryBookPublication(
          status: 'draft',
          bookId: 'book-1',
          metadata: LibraryBookMetadata(
            title: 'Kasparov’s games',
            author: 'Garry Kasparov',
            about: 'Games',
            authorCredit: LibraryAuthorCredit.other,
            authorPhotoUrl: 'https://media.example.invalid/author.webp',
          ),
        );
      await _pump(tester, publisher);
      expect(find.text('Remove photo'), findsOneWidget);
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.ensureVisible(find.text('Me'));
      await tester.tap(find.text('Me'));
      await tester.pumpAndSettle();
      expect(
        find.text('The saved author photo will be removed when you save.'),
        findsOneWidget,
      );
      await _tap(tester, 'Save private draft');
      expect(publisher.saves.single.metadata.toJson()['authorCredit'], 'self');
    });

    testWidgets('the resume draft keeps the credit', (tester) async {
      SharedPreferences.setMockInitialValues({
        'library_book.draft.folder':
            '{"title":"My study","author":"Garry Kasparov","about":"A chess study","authorCredit":"other"}',
      });
      final publisher = _Publisher();
      await _pump(tester, publisher);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(find.text('Author photo'), findsOneWidget);
      await _tap(tester, 'Save private draft');
      expect(publisher.saves.single.metadata.toJson()['authorCredit'], 'other');
    });
  });

  test('editor metadata only carries the credit it knows', () {
    final legacy = LibraryBookMetadata.fromJson({'title': 'A'});
    expect(legacy.authorCredit, isNull);
    expect(legacy.toJson().containsKey('authorCredit'), isFalse);
    final credited = LibraryBookMetadata.fromJson({
      'title': 'A',
      'authorCredit': 'other',
      'authorPhotoUrl': 'https://media.example.invalid/a.webp',
    });
    expect(credited.authorCredit, LibraryAuthorCredit.other);
    expect(credited.authorPhotoUrl, 'https://media.example.invalid/a.webp');
    // The photo is set by its upload, never sent with the details.
    expect(credited.toJson().containsKey('authorPhotoUrl'), isFalse);
    expect(
      LibraryAuthorSuggestion.fromJson({
        'id': 'credit:1',
        'name': ' Magnus Carlsen ',
        'bookCount': 2,
        'avatarUrl': 'http://insecure.invalid/a.png',
      })!.avatarUrl,
      isNull,
    );
    expect(LibraryAuthorSuggestion.fromJson({'name': ' '}), isNull);
  });

  group('publisher service', () {
    final folder = LibraryFolder(
      id: 'folder',
      userId: 'owner',
      name: 'My study',
      color: '#000000',
      icon: 'folder',
      orderIndex: 0,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );
    GamebaseLibraryBookPublisher failing(int status, [Object? data]) =>
        GamebaseLibraryBookPublisher(
          dio: Dio(),
          production: true,
          baseUrl: 'https://service.chessever.com',
          accessToken: () => 'token',
          apiRequest:
              ({
                required folderId,
                required method,
                required bearer,
                body,
                query,
                required resource,
              }) async => throw DioException(
                requestOptions: RequestOptions(path: '/x'),
                response: Response(
                  requestOptions: RequestOptions(path: '/x'),
                  statusCode: status,
                  data: data,
                ),
              ),
        );

    test('an older server refusing a someone-else credit says so', () async {
      final publisher = failing(400, {
        'status': 'error',
        'error': {'message': 'Check the book details and try again.'},
      });
      await expectLater(
        publisher.save(
          folder,
          const LibraryBookMetadata(
            title: 'A',
            author: 'Garry Kasparov',
            authorCredit: LibraryAuthorCredit.other,
          ),
        ),
        throwsA(
          isA<LibraryBookPublicationException>().having(
            (e) => e.message,
            'message',
            startsWith('Crediting someone else is not available here yet'),
          ),
        ),
      );
    });

    test('author photo refusals keep their reason', () async {
      await expectLater(
        failing(422, {
          'status': 'error',
          'error': {'code': 'author_photo_aspect'},
        }).uploadAuthorPhoto(folder, Uint8List(4)),
        throwsA(
          isA<LibraryBookPublicationException>().having(
            (e) => e.message,
            'message',
            'The author photo must be a square.',
          ),
        ),
      );
      await expectLater(
        failing(404).uploadAuthorPhoto(folder, Uint8List(4)),
        throwsA(
          isA<LibraryBookPublicationException>().having(
            (e) => e.message,
            'message',
            'Author photo uploads are not available here yet.',
          ),
        ),
      );
    });

    test('suggestions fail quietly and skip one-letter names', () async {
      var asked = 0;
      final publisher = GamebaseLibraryBookPublisher(
        dio: Dio(),
        production: true,
        baseUrl: 'https://service.chessever.com',
        accessToken: () => 'token',
        suggestionRequest:
            ({required name, required limit, required bearer}) async {
              asked++;
              throw StateError('offline');
            },
      );
      expect(await publisher.suggestAuthors('M'), isEmpty);
      expect(asked, 0);
      expect(await publisher.suggestAuthors('Magnus'), isEmpty);
      expect(asked, 1);
    });
  });
}
