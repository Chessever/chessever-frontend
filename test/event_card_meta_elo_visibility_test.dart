import 'package:chessever2/screens/group_event/model/tour_event_card_model.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/time_utils.dart';
import 'package:chessever2/widgets/event_card/event_card.dart';
import 'package:chessever2/widgets/event_card/event_image_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Regression: long cross-month date ranges on the shared event-card meta line
/// used to ellipsize the trailing `Ø ####` digits. Elo must stay fully laid out
/// under phone-width pressure.
void main() {
  const elo = 2750;

  GroupEventCardModel crossMonthEvent() {
    // Multi-month span yields e.g. "Jan 5 - 20 Mar, 2026" (longer than same-month).
    final start = DateTime(2026, 1, 5);
    final end = DateTime(2026, 3, 20);
    return GroupEventCardModel(
      id: 'cross-month-event',
      title: 'Long Cross-Month Masters',
      dates: TimeUtils.formatDateRange(start, end),
      maxAvgElo: elo,
      timeUntilStart: '',
      tourEventCategory: TourEventCategory.completed,
      // No blitz/rapid/classic asset path — pure text span in meta.
      timeControl: '90+30',
      startDate: start,
      endDate: end,
      eventSource: EventSource.lichessBroadcast,
    );
  }

  Future<void> pumpCard(WidgetTester tester, {required double width}) async {
    final mediaQuery = MediaQueryData(
      size: Size(width, 800),
      devicePixelRatio: 3,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          eventImageProvider.overrideWith(
            (ref, id) async => const EventImageData(),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.darkTheme,
          home: MediaQuery(
            data: mediaQuery,
            child: Builder(
              builder: (context) {
                ResponsiveHelper.init(context);
                return Scaffold(
                  body: Center(
                    // Phone list content width after image + padding is tight;
                    // constrain the whole card to a typical narrow phone.
                    child: SizedBox(
                      width: width,
                      child: EventCard(
                        tourEventCardModel: crossMonthEvent(),
                        forceCompactLayout: true,
                        trailingWidget: const SizedBox.shrink(),
                        heroTagSuffix: 'test',
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    // Settle image provider async.
    await tester.pump(const Duration(milliseconds: 50));
  }

  testWidgets(
    'meta line keeps full Ø elo digits under cross-month date + phone width',
    (tester) async {
      // Narrow phone forces meta pressure; dates ellipsize, Elo must not.
      await pumpCard(tester, width: 320);

      final dateRange = TimeUtils.formatDateRange(
        DateTime(2026, 1, 5),
        DateTime(2026, 3, 20),
      );
      expect(dateRange, contains('-'));
      expect(dateRange.length, greaterThan(12));

      final eloLabel = 'Ø $elo';

      // Elo must appear as its own laid-out paragraph (not only buried inside
      // a single ellipsized meta Text.rich that can clip trailing digits).
      final eloParagraphs =
          tester.allRenderObjects.whereType<RenderParagraph>().where((p) {
            final plain = p.text.toPlainText();
            return plain.contains(eloLabel) &&
                !plain.contains(dateRange.split(' ').first);
          }).toList();

      expect(
        eloParagraphs,
        isNotEmpty,
        reason:
            'Expected a dedicated meta span for "$eloLabel" outside the '
            'date ellipsis path; found only: '
            '${tester.allRenderObjects.whereType<RenderParagraph>().map((p) => p.text.toPlainText()).toList()}',
      );

      final eloParagraph = eloParagraphs.first;
      expect(eloParagraph.didExceedMaxLines, isFalse);
      expect(eloParagraph.text.toPlainText(), contains(eloLabel));
      // All four digits present (guards against "Ø 27…" style truncation).
      expect(eloParagraph.text.toPlainText(), contains('$elo'));

      // Same RenderParagraph: laid-out width must meet its unconstrained
      // intrinsic width. If the parent squeezed this span, size < intrinsic
      // and trailing digits would paint clipped/ellipsized.
      final intrinsic = eloParagraph.getMaxIntrinsicWidth(double.infinity);
      expect(
        eloParagraph.size.width + 0.5,
        greaterThanOrEqualTo(intrinsic),
        reason:
            'Elo span width ${eloParagraph.size.width} < intrinsic '
            '$intrinsic; digits are clipped',
      );
    },
  );

  test(
    'cross-month formatDateRange is long enough to stress meta layout',
    () {
      final range = TimeUtils.formatDateRange(
        DateTime(2026, 1, 5),
        DateTime(2026, 3, 20),
      );
      // Same-month would be shorter ("Jan 5 - 20, 2026"); cross-month includes
      // a second month token.
      expect(range, matches(RegExp(r'Jan.*Mar.*2026', caseSensitive: false)));
    },
  );
}
