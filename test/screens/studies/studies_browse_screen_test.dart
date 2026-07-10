import 'dart:async';

import 'package:chessever2/repository/gamebase/gamebase_repository.dart';
import 'package:chessever2/screens/studies/providers/studies_provider.dart';
import 'package:chessever2/screens/studies/studies_browse_screen.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import 'study_test_support.dart';

void main() {
  testWidgets(
    'uses floating full-screen controls and distinct loading/empty states',
    (tester) async {
      final firstPage = Completer<GamebaseStudiesPage>();
      final repository = _repository(
        studiesHandler:
            ({required filter, required limit, required offset}) =>
                firstPage.future,
      );

      final semantics = tester.ensureSemantics();
      await _pumpBrowse(tester, repository: repository);

      expect(
        find.byKey(const ValueKey<String>('studies-browse-full-screen-page')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('studies-browse-floating-controls')),
        findsOneWidget,
      );
      expect(find.byType(AppBar), findsNothing);
      expect(
        find.byKey(const ValueKey<String>('studies-loading-state')),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel('Loading Studies'), findsWidgets);
      expect(
        tester
            .getSize(
              find.byKey(const ValueKey<String>('studies-refresh-button')),
            )
            .height,
        greaterThanOrEqualTo(48),
      );
      final switcher = tester.widget<AnimatedSwitcher>(
        find.byKey(const ValueKey<String>('studies-state-switcher')),
      );
      expect(switcher.duration, Duration.zero);

      firstPage.complete(testStudiesPage(items: const []));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey<String>('studies-empty-state')),
        findsOneWidget,
      );
      expect(find.text('No quality-gated Studies yet'), findsOneWidget);
      expect(find.text('Refresh Studies'), findsOneWidget);
      semantics.dispose();
    },
  );

  for (final entry in <(String, ThemeData)>[
    ('light', AppTheme.lightTheme),
    ('dark', AppTheme.darkTheme),
  ]) {
    testWidgets('renders useful metadata and actions in ${entry.$1} mode', (
      tester,
    ) async {
      final study = testStudy();
      GamebaseStudySummary? openedStudy;
      final repository = _repository(
        studiesHandler:
            ({required filter, required limit, required offset}) async =>
                testStudiesPage(items: <GamebaseStudySummary>[study]),
      );

      await _pumpBrowse(
        tester,
        repository: repository,
        theme: entry.$2,
        textScaler: const TextScaler.linear(1.25),
        screen: StudiesBrowseScreen(
          onOpenStudy: (selected) => openedStudy = selected,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Credibility-ranked Studies'), findsOneWidget);
      expect(find.text(study.name), findsOneWidget);
      expect(find.text('840 views'), findsOneWidget);
      expect(find.text('2 chapters'), findsOneWidget);
      expect(find.text('Annotated'), findsOneWidget);
      expect(find.text('Gamebook'), findsOneWidget);
      expect(find.text('Sicilian Defense'), findsOneWidget);
      expect(find.text('B90 · B91'), findsOneWidget);
      expect(find.text('Example White · Example Black'), findsOneWidget);
      expect(find.text('76.4'), findsOneWidget);

      final card = find.byKey(const ValueKey<String>('study-card-AbCd1234'));
      final material = tester.widget<Material>(
        find.descendant(of: card, matching: find.byType(Material)).first,
      );
      expect(material.color, entry.$2.extension<AppColors>()!.surface);

      await tester.tap(find.text(study.name));
      await tester.pump();
      expect(openedStudy?.canonicalStudyId, 'AbCd1234');
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('shows a safe cold error with an accessible retry', (
    tester,
  ) async {
    final repository = _repository(
      studiesHandler:
          ({required filter, required limit, required offset}) =>
              Future<GamebaseStudiesPage>.error(
                const GamebaseStudyRequestException(
                  operation: 'list Studies',
                  message: 'offline',
                ),
              ),
    );

    await _pumpBrowse(tester, repository: repository);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('studies-error-state')),
      findsOneWidget,
    );
    expect(find.text('Studies could not load'), findsOneWidget);
    expect(find.text('Retry Studies'), findsOneWidget);
    expect(
      tester.getSize(find.widgetWithText(FilledButton, 'Retry Studies')).height,
      greaterThanOrEqualTo(48),
    );
  });

  testWidgets('retains loaded cards when the next page fails', (tester) async {
    final studies = <GamebaseStudySummary>[
      testStudy(id: 'AbCd0001', name: 'First Study'),
      testStudy(id: 'AbCd0002', name: 'Second Study'),
    ];
    final repository = _repository(
      studiesHandler: ({required filter, required limit, required offset}) {
        if (offset == 0) {
          return Future<GamebaseStudiesPage>.value(
            testStudiesPage(items: studies, total: 4),
          );
        }
        return Future<GamebaseStudiesPage>.error(
          StateError('later page failed'),
        );
      },
    );

    await _pumpBrowse(tester, repository: repository);
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(StudiesBrowseScreen)),
    );

    await container.read(studiesProvider.notifier).loadMore();
    await tester.pump();

    expect(find.text('First Study'), findsOneWidget);
    expect(find.text('Second Study'), findsOneWidget);
    expect(
      find.text(
        'More Studies could not load. Your current list is still available.',
      ),
      findsOneWidget,
    );
    final retry = find.byKey(const ValueKey<String>('studies-load-more-retry'));
    expect(retry, findsOneWidget);
    expect(tester.getSize(retry).height, greaterThanOrEqualTo(48));
  });
}

WidgetTestGamebaseRepository _repository({
  required StudiesPageHandler studiesHandler,
}) {
  return WidgetTestGamebaseRepository(
    studiesHandler: studiesHandler,
    detailHandler:
        (_) => Future<GamebaseStudyDetail>.error(
          StateError('Detail should not be requested'),
        ),
  );
}

Future<void> _pumpBrowse(
  WidgetTester tester, {
  required GamebaseRepository repository,
  ThemeData? theme,
  TextScaler textScaler = TextScaler.noScaling,
  StudiesBrowseScreen screen = const StudiesBrowseScreen(),
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(393, 1000);
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
