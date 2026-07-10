import 'package:chessever2/repository/gamebase/gamebase_repository.dart';
import 'package:chessever2/screens/studies/study_detail_screen.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import 'study_test_support.dart';

void main() {
  const contentVersion =
      'sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';
  const olderVersion =
      'sha256:abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789';

  for (final entry in <(String, ThemeData)>[
    ('light', AppTheme.lightTheme),
    ('dark', AppTheme.darkTheme),
  ]) {
    testWidgets('renders ordered quality metadata in ${entry.$1} mode', (
      tester,
    ) async {
      final detail = testStudyDetail();
      final repository = _repository(detailHandler: (_) async => detail);
      final semantics = tester.ensureSemantics();

      await _pumpDetail(
        tester,
        repository: repository,
        theme: entry.$2,
        textScaler: const TextScaler.linear(1.25),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey<String>('study-detail-full-screen-page')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('study-detail-floating-controls')),
        findsOneWidget,
      );
      expect(find.byType(AppBar), findsNothing);
      expect(find.text('Annotated Sicilian Model Games'), findsOneWidget);
      expect(find.text('Credibility score'), findsOneWidget);
      expect(find.text('76.4'), findsOneWidget);
      expect(find.text('840 views'), findsOneWidget);
      expect(find.text('2 chapters'), findsOneWidget);
      expect(find.text('Sicilian Defense'), findsWidgets);
      expect(find.text('B90 · B91'), findsOneWidget);
      expect(find.text('Example White · Example Black'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('Source safety')), findsOneWidget);
      expect(
        tester
            .getSize(
              find.byKey(const ValueKey<String>('open-study-on-lichess')),
            )
            .height,
        greaterThanOrEqualTo(48),
      );

      final firstChapter = find.text('Main line');
      final secondChapter = find.text('Dragon endgame');
      final detailScroll = find.descendant(
        of: find.byKey(const PageStorageKey<String>('study-detail-content')),
        matching: find.byType(Scrollable),
      );
      await tester.scrollUntilVisible(
        firstChapter,
        320,
        scrollable: detailScroll,
      );
      await tester.scrollUntilVisible(
        secondChapter,
        320,
        scrollable: detailScroll,
      );
      expect(firstChapter, findsOneWidget);
      expect(secondChapter, findsOneWidget);
      expect(
        tester.getTopLeft(firstChapter).dy,
        lessThan(tester.getTopLeft(secondChapter).dy),
      );

      final switcher = tester.widget<AnimatedSwitcher>(
        find.byKey(const ValueKey<String>('study-detail-state-switcher')),
      );
      expect(switcher.duration, Duration.zero);
      expect(tester.takeException(), isNull);
      semantics.dispose();
    });
  }

  testWidgets(
    'shows additive source attribution and validation without PGN claims',
    (tester) async {
      final study = testStudy(
        author: 'vetted_author',
        sourceMetadata: GamebaseStudySourceMetadata(
          source: GamebaseStudySource.lichess,
          sourceId: 'AbCd1234',
          url: Uri.parse('https://lichess.org/study/AbCd1234'),
          authorUsername: 'vetted_author',
          attribution: 'Study by vetted_author on Lichess',
        ),
        validation: GamebaseStudyValidation(
          status: GamebaseStudyValidationStatus.valid,
          validatorVersion: 'lichess-study-mainline-v1',
          validatedAt: DateTime.utc(2026, 7, 10, 3),
        ),
      );
      final repository = _repository(
        detailHandler: (_) async => testStudyDetail(study: study),
      );

      await _pumpDetail(tester, repository: repository);
      await tester.pumpAndSettle();

      expect(find.text('Study by vetted_author on Lichess'), findsOneWidget);
      expect(
        find.textContaining('replayed every mainline as legal chess moves'),
        findsOneWidget,
      );
      expect(find.textContaining('mirrored PGN'), findsNothing);
      expect(find.text('Open Study on Lichess'), findsOneWidget);
    },
  );

  testWidgets(
    'opens only canonical Study and chapter URLs through the callback',
    (tester) async {
      final opened = <Uri>[];
      final repository = _repository(
        detailHandler: (_) async => testStudyDetail(),
      );

      await _pumpDetail(
        tester,
        repository: repository,
        screen: StudyDetailScreen(
          lichessStudyId: 'AbCd1234',
          openExternalLink: (uri) async {
            opened.add(uri);
            return true;
          },
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey<String>('open-study-on-lichess')),
      );
      await tester.pump();

      final chapterButton = find.byKey(
        const ValueKey<String>('open-chapter-Chapter1'),
      );
      await tester.ensureVisible(chapterButton);
      await tester.pump();
      await tester.tap(chapterButton);
      await tester.pump();

      expect(opened.map((uri) => uri.toString()), const <String>[
        'https://lichess.org/study/AbCd1234',
        'https://lichess.org/study/AbCd1234/Chapter1',
      ]);
      expect(
        find.textContaining(RegExp('bookmark|progress', caseSensitive: false)),
        findsNothing,
      );
      expect(find.textContaining('Open chapter in ChessEver'), findsNothing);
    },
  );

  testWidgets('shares and copies canonical public Study and chapter links', (
    tester,
  ) async {
    final shared = <String>[];
    final copied = <String>[];
    final study = testStudy(
      contentCapabilities: const GamebaseStudyContentCapabilities(
        contentVersion: contentVersion,
        rights: null,
        redistribution: GamebaseStudyRedistributionCapability.unknown,
        canOpenMirroredChapterInApp: false,
        canDownloadMirroredPgn: false,
      ),
    );
    final repository = _repository(
      detailHandler: (_) async => testStudyDetail(study: study),
    );

    await _pumpDetail(
      tester,
      repository: repository,
      screen: StudyDetailScreen(
        lichessStudyId: 'AbCd1234',
        shareLink: (_, text) async => shared.add(text),
        copyLink: (text) async => copied.add(text),
      ),
    );
    await tester.pumpAndSettle();

    final studyActions = find.byKey(
      const ValueKey<String>('share-study-actions'),
    );
    await tester.tap(
      find.descendant(
        of: studyActions,
        matching: find.bySemanticsLabel('Share Study'),
      ),
    );
    await tester.tap(
      find.descendant(
        of: studyActions,
        matching: find.bySemanticsLabel('Copy Study share text'),
      ),
    );
    await tester.pump();

    final chapterActions = find.byKey(
      const ValueKey<String>('share-chapter-actions-Chapter1'),
    );
    await tester.ensureVisible(chapterActions);
    await tester.pump();
    await tester.tap(
      find.descendant(
        of: chapterActions,
        matching: find.bySemanticsLabel('Share chapter'),
      ),
    );
    await tester.tap(
      find.descendant(
        of: chapterActions,
        matching: find.bySemanticsLabel('Copy chapter share text'),
      ),
    );
    await tester.pump();

    expect(shared, hasLength(2));
    expect(shared.first, contains('Source: Lichess · Shared via ChessEver'));
    expect(
      shared.first,
      endsWith(
        'https://chessever.com/studies/AbCd1234?v=sha256%3A0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef',
      ),
    );
    expect(
      shared.last,
      endsWith(
        'https://chessever.com/studies/AbCd1234/chapters/Chapter1?v=sha256%3A0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef',
      ),
    );
    expect(copied, hasLength(2));
    expect(copied.first, contains('Source: Lichess · Shared via ChessEver'));
    expect(
      copied.first,
      endsWith(
        'https://chessever.com/studies/AbCd1234?v=sha256%3A0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef',
      ),
    );
    expect(copied.last, contains('/chapters/Chapter1'));
  });

  testWidgets('highlights nearest current context and explains version drift', (
    tester,
  ) async {
    final study = testStudy(
      contentCapabilities: const GamebaseStudyContentCapabilities(
        contentVersion: contentVersion,
        rights: null,
        redistribution: GamebaseStudyRedistributionCapability.unknown,
        canOpenMirroredChapterInApp: false,
        canDownloadMirroredPgn: false,
      ),
    );
    final repository = _repository(
      detailHandler: (_) async => testStudyDetail(study: study),
    );

    await _pumpDetail(
      tester,
      repository: repository,
      screen: const StudyDetailScreen(
        lichessStudyId: 'AbCd1234',
        chapterId: 'Chapter1',
        ply: 99,
        contentVersion: olderVersion,
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.textContaining('changed since the link was shared'),
      findsOneWidget,
    );
    expect(find.textContaining('nearest available ply 56'), findsOneWidget);
    expect(
      find.bySemanticsLabel(RegExp('Shared context, Chapter 1')),
      findsOneWidget,
    );
    expect(find.textContaining('mirrored PGN'), findsNothing);
  });

  testWidgets('explains a missing shared chapter without failing silently', (
    tester,
  ) async {
    final repository = _repository(
      detailHandler: (_) async => testStudyDetail(),
    );

    await _pumpDetail(
      tester,
      repository: repository,
      screen: const StudyDetailScreen(
        lichessStudyId: 'AbCd1234',
        chapterId: 'Missing1',
        ply: 3,
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.textContaining('shared chapter is no longer available'),
      findsOneWidget,
    );
    expect(find.text('Annotated Sicilian Model Games'), findsOneWidget);
  });

  testWidgets('reveals a requested chapter outside the initial viewport', (
    tester,
  ) async {
    final chapters = List<GamebaseStudyChapterMetadata>.generate(
      18,
      (index) => testChapter(
        chapterId: 'Chapter${index.toString().padLeft(2, '0')}',
        orderIndex: index,
        name: 'Chapter number ${index + 1}',
      ),
    );
    final repository = _repository(
      detailHandler: (_) async => testStudyDetail(chapters: chapters),
    );

    await _pumpDetail(
      tester,
      repository: repository,
      screen: const StudyDetailScreen(
        lichessStudyId: 'AbCd1234',
        chapterId: 'Chapter17',
      ),
    );
    await tester.pumpAndSettle();

    final requested = find.bySemanticsLabel(
      RegExp('Shared context, Chapter 18'),
    );
    expect(requested, findsOneWidget);
    expect(tester.getTopLeft(requested).dy, lessThan(1100));
  });

  testWidgets('shows a removed or private Study tombstone', (tester) async {
    final repository = _repository(
      detailHandler:
          (_) => Future<GamebaseStudyDetail>.error(
            const GamebaseStudyRequestException(
              operation: 'get Study',
              message: 'not found',
              statusCode: 404,
            ),
          ),
    );

    await _pumpDetail(tester, repository: repository);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('study-detail-error-state')),
      findsOneWidget,
    );
    expect(find.text('This Study is no longer available'), findsOneWidget);
    expect(
      find.text('It may have been removed or made private at the source.'),
      findsOneWidget,
    );
    final retry = find.widgetWithText(FilledButton, 'Retry Study');
    expect(retry, findsOneWidget);
    expect(tester.getSize(retry).height, greaterThanOrEqualTo(48));
  });

  test(
    'default launcher rejects noncanonical hosts before platform launch',
    () async {
      expect(
        await openCanonicalLichessStudyUrl(
          Uri.parse('https://example.com/study/AbCd1234'),
        ),
        isFalse,
      );
      expect(
        await openCanonicalLichessStudyUrl(
          Uri.parse('https://lichess.org/analysis/AbCd1234'),
        ),
        isFalse,
      );
    },
  );
}

WidgetTestGamebaseRepository _repository({
  required StudyDetailHandler detailHandler,
}) {
  return WidgetTestGamebaseRepository(
    studiesHandler:
        ({required filter, required limit, required offset}) =>
            Future<GamebaseStudiesPage>.error(
              StateError('Studies list should not be requested'),
            ),
    detailHandler: detailHandler,
  );
}

Future<void> _pumpDetail(
  WidgetTester tester, {
  required GamebaseRepository repository,
  ThemeData? theme,
  TextScaler textScaler = TextScaler.noScaling,
  StudyDetailScreen screen = const StudyDetailScreen(
    lichessStudyId: 'AbCd1234',
  ),
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(393, 1100);
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        gamebaseRepositoryProvider.overrideWithValue(repository),
      ],
      child: LiquidGlassWidgets.wrap(
        child: MaterialApp(
          theme: theme ?? AppTheme.lightTheme,
          home: Builder(
            builder: (context) {
              ResponsiveHelper.init(context);
              return MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: textScaler, disableAnimations: true),
                child: screen,
              );
            },
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}
