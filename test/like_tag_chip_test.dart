import 'package:chessever2/screens/chessboard/widgets/like_tag_chip.dart';
import 'package:chessever2/screens/chessboard/widgets/like_tag_offer.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

void main() {
  testWidgets(
    'board toolbar still closes through its shared offer controller',
    (tester) async {
      final offers = await _pumpToolbar(tester);
      expect(find.text('Sacrifice'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 5000));
      expect(offers.current.value, isNotNull);
      await tester.pump(const Duration(milliseconds: 300));
      expect(offers.current.value, isNull);
      expect(find.byType(LikeTagChip), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'toolbar menu opens below, pauses expiry, and tears down mid-exit',
    (tester) async {
      final offers = await _pumpToolbar(tester);
      await tester.pump(const Duration(milliseconds: 600));
      final chip = tester.getRect(find.byType(LikeTagChip));
      await tester.tap(find.text('Sacrifice'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));
      final panel = tester.getRect(
        find
            .ancestor(
              of: find.byType(GridView),
              matching: find.byType(Material),
            )
            .first,
      );
      expect(panel.top, greaterThan(chip.bottom));
      expect(panel.bottom, lessThan(852));
      expect(find.text('1 selected'), findsOneWidget);
      await tester.pump(const Duration(seconds: 6));
      expect(offers.current.value, isNotNull);
      await tester.tapAt(const Offset(3, 700));
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(GridView), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}

Future<TagChipOfferController> _pumpToolbar(WidgetTester tester) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(393, 852);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  final offers = TagChipOfferController()..open('game', ['Sacrifice']);
  addTearDown(offers.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [tagChipOfferProvider.overrideWithValue(offers)],
      child: MaterialApp(
        theme: AppTheme.darkTheme,
        home: Builder(
          builder: (context) {
            ResponsiveHelper.init(context);
            return Scaffold(
              appBar: AppBar(
                actions: [
                  ValueListenableBuilder<TagOffer?>(
                    valueListenable: offers.current,
                    builder: (context, offer, _) => offer == null
                        ? const SizedBox.shrink()
                        : LikeTagChip(key: ValueKey(offer.token), offer: offer),
                  ),
                  const SizedBox(width: 16),
                ],
              ),
            );
          },
        ),
      ),
    ),
  );
  await tester.pump();
  return offers;
}
