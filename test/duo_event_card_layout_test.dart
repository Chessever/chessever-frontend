import 'package:chessever2/screens/group_event/model/tour_event_card_model.dart';
import 'package:chessever2/screens/group_event/providers/live_group_broadcast_id_provider.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/adaptive_window.dart';
import 'package:chessever2/widgets/event_card/event_card.dart';
import 'package:chessever2/widgets/event_card/event_image_provider.dart';
import 'package:chessever2/widgets/event_card/event_next_round_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'fixtures/duo_window_matrix.dart';

void main() {
  for (final window in duoWindowCases) {
    for (final light in [false, true]) {
      for (final scale in [1.0, 1.3, 1.8]) {
        testWidgets(
          'Duo ${window.name} event title and countdown stay inside the card '
          '${light ? 'light' : 'dark'} ${scale}x',
          (tester) async {
            tester.view.devicePixelRatio = 3;
            applyDuoWindow(tester, window);
            addTearDown(tester.view.reset);
            await tester.pumpWidget(
              ProviderScope(
                overrides: [
                  eventImageProvider.overrideWith(
                    (ref, id) async => const EventImageData(),
                  ),
                  liveGroupBroadcastIdsProvider.overrideWith(
                    (ref) => Stream.value(const <String>[]),
                  ),
                  eventNextRoundProvider.overrideWith(
                    (ref, id) async => NextRoundInfo(
                      name: 'Championship semifinal round 11',
                      startsAt: DateTime.now().add(const Duration(days: 2)),
                    ),
                  ),
                ],
                child: MaterialApp(
                  theme: light ? AppTheme.lightTheme : AppTheme.darkTheme,
                  builder: (_, child) => AdaptiveWindowScope(child: child!),
                  home: Builder(
                    builder: (context) {
                      ResponsiveHelper.init(context);
                      return MediaQuery(
                        data: MediaQuery.of(
                          context,
                        ).copyWith(textScaler: TextScaler.linear(scale)),
                        child: Builder(
                          builder: (context) => Scaffold(
                            body: Center(
                              child: SizedBox(
                                key: const ValueKey('duo_event_card'),
                                width: ResponsiveHelper.isTablet
                                    ? 280
                                    : MediaQuery.sizeOf(context).width - 40,
                                height: EventCard.gridMainAxisExtent(
                                  context,
                                  ResponsiveHelper.isTablet
                                      ? 280
                                      : MediaQuery.sizeOf(context).width - 40,
                                ),
                                child: EventCard(
                                  tourEventCardModel: GroupEventCardModel(
                                    id: 'duo-layout-event',
                                    title:
                                        'European Individual Chess Championship 2026',
                                    dates: 'November 4 - 18, 2026',
                                    startDate: DateTime(2026, 11, 4),
                                    endDate: DateTime(2026, 11, 18),
                                    maxAvgElo: 2750,
                                    timeUntilStart: '',
                                    tourEventCategory:
                                        TourEventCategory.upcoming,
                                    timeControl: '90+30',
                                    eventSource: EventSource.lichessBroadcast,
                                  ),
                                  trailingWidget: SizedBox.square(
                                    dimension: 44,
                                    child: IconButton(
                                      tooltip: 'Star event',
                                      onPressed: () {},
                                      icon: const Icon(
                                        Icons.star_outline_rounded,
                                      ),
                                    ),
                                  ),
                                  heroTagSuffix: 'duo-test',
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            );
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 50));
            expect(tester.takeException(), isNull);
            final card = tester.getRect(
              find.byKey(const ValueKey('duo_event_card')),
            );
            final texts = find.descendant(
              of: find.byType(EventCard),
              matching: find.byType(RichText),
            );
            for (final element in texts.evaluate()) {
              final paragraph = element.renderObject! as RenderParagraph;
              if (paragraph.size.isEmpty) continue;
              final rect = MatrixUtils.transformRect(
                paragraph.getTransformTo(null),
                Offset.zero & paragraph.size,
              );
              expect(rect.top, greaterThanOrEqualTo(card.top));
              expect(rect.bottom, lessThanOrEqualTo(card.bottom));
              expect(rect.left, greaterThanOrEqualTo(card.left));
              expect(rect.right, lessThanOrEqualTo(card.right));
            }
            expect(
              find.text('Championship semifinal round 11'),
              findsOneWidget,
            );
            await tester.tap(find.byTooltip('Star event'));
            expect(tester.takeException(), isNull);
            await tester.pumpWidget(const SizedBox.shrink());
          },
        );
      }
    }
  }
}
