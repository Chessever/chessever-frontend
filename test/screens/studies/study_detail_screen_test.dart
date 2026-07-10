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
