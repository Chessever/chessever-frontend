import 'dart:async';

import 'package:chessever2/services/editorial_link_service.dart';
import 'package:chessever2/screens/collections/collections_data.dart';
import 'package:chessever2/services/rewarded_premium/rewarded_access_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

void main() {
  test(
    'matches app destinations without treating another host as internal',
    () {
      for (final page in EditorialPage.values) {
        final path = switch (page) {
          EditorialPage.myPrep => 'my-prep',
          EditorialPage.myLikes => 'my-likes',
          _ => page.name,
        };
        expect(
          editorialPageForUri(Uri.parse('https://chessever.com/$path')),
          page,
        );
        expect(
          editorialPageForUri(
            Uri.parse('https://www.chessever.com/app/$path/'),
          ),
          page,
        );
        expect(
          editorialPageForUri(Uri.parse('https://unrelated.example/$path')),
          isNull,
        );
      }
      expect(
        editorialPageForUri(Uri.parse('https://chessever.com:444/reports')),
        isNull,
      );
      expect(
        editorialPageForUri(Uri.parse('https://user@chessever.com/reports')),
        isNull,
      );
    },
  );

  for (final allowed in [false, true]) {
    testWidgets('Premium destination waits for access (allowed=$allowed)', (
      tester,
    ) async {
      final decision = Completer<bool>();
      final calls = <String>[];
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            editorialAccessRequestProvider.overrideWithValue((
              context,
              feature,
            ) {
              calls.add('access:$feature');
              return decision.future;
            }),
            editorialPageNavigationProvider.overrideWithValue(
              (context, page) => calls.add('navigate:${page.name}'),
            ),
          ],
          child: MaterialApp(
            home: Consumer(
              builder: (context, ref, _) => Scaffold(
                body: TextButton(
                  onPressed: () => ref.read(editorialLinkOpenerProvider)(
                    context,
                    Uri.parse('https://chessever.com/reports'),
                  ),
                  child: const Text('See'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('See'));
      await tester.pump();
      expect(calls, ['access:game_reports']);
      // A second tap cannot create another dialog or duplicate the route.
      await tester.tap(find.text('See'));
      await tester.pump();
      expect(calls, ['access:game_reports']);
      decision.complete(allowed);
      await tester.pump();
      expect(
        calls,
        allowed
            ? ['access:game_reports', 'navigate:reports']
            : ['access:game_reports'],
      );
    });
  }

  testWidgets('free destination opens without asking for Premium', (
    tester,
  ) async {
    final opened = <EditorialPage>[];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          editorialAccessRequestProvider.overrideWithValue(
            (context, feature) async => throw StateError('unexpected paywall'),
          ),
          editorialPageNavigationProvider.overrideWithValue(
            (context, page) => opened.add(page),
          ),
        ],
        child: MaterialApp(
          home: Consumer(
            builder: (context, ref, _) => TextButton(
              onPressed: () => ref.read(editorialLinkOpenerProvider)(
                context,
                Uri.parse('https://chessever.com/feed'),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pump();
    expect(opened, [EditorialPage.feed]);
  });

  testWidgets('an entitled user skips the actual Premium prompt', (
    tester,
  ) async {
    final opened = <EditorialPage>[];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          premiumAccessProvider.overrideWithValue(true),
          editorialPageNavigationProvider.overrideWithValue(
            (context, page) => opened.add(page),
          ),
        ],
        child: MaterialApp(
          home: Consumer(
            builder: (context, ref, _) => TextButton(
              onPressed: () => ref.read(editorialLinkOpenerProvider)(
                context,
                Uri.parse('https://chessever.com/reports'),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pump();
    expect(opened, [EditorialPage.reports]);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'collection metadata determines Premium access before navigation',
    (tester) async {
      final repository = _LockedCollection();
      final features = <String>[];
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            collectionsRepositoryProvider.overrideWithValue(repository),
            editorialAccessRequestProvider.overrideWithValue((
              context,
              feature,
            ) async {
              features.add(feature);
              return false;
            }),
          ],
          child: MaterialApp(
            home: Consumer(
              builder: (context, ref, _) => TextButton(
                onPressed: () => ref.read(editorialLinkOpenerProvider)(
                  context,
                  Uri.parse('https://chessever.com/collections/local-book'),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pump();
      expect(repository.slug, 'local-book');
      expect(features, ['collection_books']);
      expect(repository.released, true);
      expect(find.text('Open'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('leaving the source while paywall is pending never navigates', (
    tester,
  ) async {
    final decision = Completer<bool>();
    var navigations = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          editorialAccessRequestProvider.overrideWithValue(
            (context, feature) => decision.future,
          ),
          editorialPageNavigationProvider.overrideWithValue(
            (context, page) => navigations++,
          ),
        ],
        child: MaterialApp(
          home: Consumer(
            builder: (context, ref, _) => TextButton(
              onPressed: () => ref.read(editorialLinkOpenerProvider)(
                context,
                Uri.parse('https://chessever.com/reports'),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpWidget(const SizedBox());
    decision.complete(true);
    await tester.pump();
    expect(navigations, 0);
    expect(tester.takeException(), isNull);
  });
}

class _LockedCollection implements CollectionsRepository {
  String? slug;
  bool released = false;
  @override
  VoidCallback holdFreshAccess(String slug) =>
      () => released = true;
  @override
  Future<Collection> fetchCollection(String slug) async {
    this.slug = slug;
    return Collection.fromJson({
      'id': 'local-book',
      'slug': slug,
      'title': 'Local fixture',
      'kind': 'book',
      'access': 'premium',
      'contentLocked': true,
    });
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
