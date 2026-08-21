import 'package:chessever2/screens/group_event/model/tour_event_card_model.dart';
import 'package:chessever2/screens/player_profile/player_profile_data_source.dart';
import 'package:chessever2/screens/player_profile/provider/player_profile_provider.dart';
import 'package:chessever2/screens/player_profile/widgets/player_profile_resolved_event_card.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/event_card/event_card.dart';
import 'package:chessever2/widgets/event_card/event_image_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

void main() {
  testWidgets('a resolved profile event keeps only one full EventCard tree', (
    tester,
  ) async {
    const request = PlayerProfileEventCardRequest(
      dataSource: PlayerProfileDataSource.twic,
      tourId: 'raw-event',
      tourName: 'Raw event',
    );
    final resolved = _event(id: 'resolved', title: 'Resolved event');

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          playerEventCardProvider.overrideWith(
            (ref, request) async => resolved,
          ),
          eventImageProvider.overrideWith(
            (ref, id) async => const EventImageData(),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.darkTheme,
          home: Builder(
            builder: (context) {
              ResponsiveHelper.init(context);
              return Scaffold(
                body: SizedBox(
                  width: 360,
                  child: PlayerProfileResolvedEventCard(
                    request: request,
                    fallbackCard: _event(
                      id: 'fallback',
                      title: 'Fallback event',
                    ),
                    heroTagSuffix: 'test',
                    onTap: (_) {},
                    statsRow: const SizedBox(height: 32),
                    trailingWidget: const SizedBox.shrink(),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.pump();

    final card = find.byType(PlayerProfileResolvedEventCard);
    expect(
      find.descendant(of: card, matching: find.byType(EventCard)),
      findsOneWidget,
    );
  });
}

GroupEventCardModel _event({required String id, required String title}) {
  return GroupEventCardModel(
    id: id,
    title: title,
    dates: 'Jul 28, 2026',
    maxAvgElo: 2700,
    timeUntilStart: '',
    tourEventCategory: TourEventCategory.completed,
    timeControl: 'Blitz',
    startDate: DateTime.utc(2026, 7, 28),
    endDate: DateTime.utc(2026, 7, 28),
  );
}
