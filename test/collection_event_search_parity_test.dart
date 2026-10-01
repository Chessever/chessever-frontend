import 'package:chessever2/screens/tour_detail/widgets/event_search_bar.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/simple_search_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final size in [const Size(390, 844), const Size(1024, 1366)]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'collection and tournament search match at $size and ${scale}x text',
        (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final tournament = TextEditingController(text: 'Tal');
          final collection = TextEditingController(text: 'Tal');
          final tournamentFocus = FocusNode();
          final collectionFocus = FocusNode();
          addTearDown(tournament.dispose);
          addTearDown(collection.dispose);
          addTearDown(tournamentFocus.dispose);
          addTearDown(collectionFocus.dispose);
          var filtersOpened = 0;
          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.darkTheme,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
              home: Builder(
                builder: (context) {
                  ResponsiveHelper.init(context);
                  final inset = ResponsiveHelper.adaptive(
                    phone: 20.sp,
                    tablet: 32.sp,
                  );
                  return Scaffold(
                    body: Center(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: ResponsiveHelper.isTablet
                              ? ResponsiveHelper.contentMaxWidth
                              : double.infinity,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            EventSearchBarFrame(
                              horizontalPadding: inset,
                              child: SimpleSearchBar(
                                key: const ValueKey(
                                  'tournament_search_reference',
                                ),
                                controller: tournament,
                                focusNode: tournamentFocus,
                                onCloseTap: () {},
                                onOpenFilter: null,
                              ),
                            ),
                            EventSearchBarFrame(
                              horizontalPadding: inset,
                              child: SimpleSearchBar(
                                key: const ValueKey(
                                  'collection_search_reference',
                                ),
                                controller: collection,
                                focusNode: collectionFocus,
                                onCloseTap: () {},
                                compactFilter: true,
                                filterBadgeCount: 3,
                                filterButtonKey: const ValueKey(
                                  'parity_filter',
                                ),
                                onOpenFilter: () => filtersOpened++,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          );
          await tester.pumpAndSettle();
          final reference = tester.getSize(
            find.byKey(const ValueKey('tournament_search_reference')),
          );
          final actual = tester.getSize(
            find.byKey(const ValueKey('collection_search_reference')),
          );
          expect(actual.width, closeTo(reference.width, 0.01));
          expect(actual.height, closeTo(reference.height, 0.01));
          await tester.tap(find.byKey(const ValueKey('parity_filter')));
          expect(filtersOpened, 1);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
  }
}
