import 'dart:convert';
import 'dart:io';

import 'package:chessever2/screens/tour_detail/bracket/models/knockout_bracket.dart';
import 'package:chessever2/screens/tour_detail/bracket/widgets/bracket_share_image_card.dart';
import 'package:chessever2/screens/tour_detail/bracket/widgets/knockout_match_card.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/share_card_palette.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// A 1x1 fully transparent PNG: the empty canvas a bracket snapshot leaves
/// between its cards.
final Uint8List _transparentPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA'
  '60e6kgAAAABJRU5ErkJggg==',
);

/// The app's Inter face, so text lays out at its real width (the test font
/// draws every glyph a full em wide and overflows the card's footer).
Future<void> _loadInter() async {
  final loader = FontLoader('InterDisplay');
  for (final weight in ['Regular', 'Medium', 'Bold']) {
    final bytes = File('assets/fonts/Inter-$weight.otf').readAsBytesSync();
    loader.addFont(Future.value(ByteData.sublistView(bytes)));
  }
  await loader.load();
}

double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  required Brightness brightness,
}) async {
  await tester.binding.setSurfaceSize(const Size(430, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      key: UniqueKey(),
      theme: brightness == Brightness.light
          ? AppTheme.lightTheme
          : AppTheme.darkTheme,
      home: Builder(
        builder: (context) {
          ResponsiveHelper.init(context);
          return Scaffold(body: SingleChildScrollView(child: child));
        },
      ),
    ),
  );
}

/// The framed well the snapshot sits in: the decoration directly around the
/// snapshot's [AspectRatio].
BoxDecoration _well(WidgetTester tester) {
  final box = tester.widget<DecoratedBox>(
    find
        .ancestor(
          of: find.byType(AspectRatio),
          matching: find.byType(DecoratedBox),
        )
        .first,
  );
  return box.decoration as BoxDecoration;
}

Widget _shareCard(ShareCardPalette palette) => ShareCardScope(
  palette: palette,
  child: BracketShareImageCard(
    width: 400,
    eventName: 'FIDE World Cup',
    snapshot: _transparentPng,
    snapshotAspectRatio: 1,
  ),
);

void main() {
  setUpAll(_loadInter);

  group('bracket share frame', () {
    test('paper sets the snapshot on the live canvas ground; dark on none', () {
      expect(
        BracketShareImageCard.snapshotGround(ShareCardPalette.light),
        AppColors.light.background,
      );
      expect(BracketShareImageCard.snapshotGround(ShareCardPalette.dark), null);
    });

    testWidgets('light: the paper match cards lift off the snapshot ground', (
      tester,
    ) async {
      await _pump(
        tester,
        _shareCard(ShareCardPalette.light),
        brightness: Brightness.light,
      );
      final ground = _well(tester).color!;
      expect(ground, AppColors.light.background);
      // Without the ground the paper cards sit on a paper page of their own
      // tone (1:1) and only a hairline separates them.
      expect(ShareCardPalette.light.bg, AppColors.light.popup);
      expect(
        _contrast(AppColors.light.popup, ground),
        greaterThan(1.1),
        reason: 'card fill vs snapshot ground',
      );
    });

    testWidgets('dark: the well keeps its historical empty frame', (
      tester,
    ) async {
      await _pump(
        tester,
        _shareCard(ShareCardPalette.dark),
        brightness: Brightness.dark,
      );
      final well = _well(tester);
      expect(well.color, isNull);
      expect(
        (well.border! as Border).top.color,
        ShareCardPalette.dark.hairline,
      );
    });
  });

  group('knockout match card lift', () {
    const alpha = BracketParticipant(id: 'a', name: 'Alpha', rating: 2700);
    const beta = BracketParticipant(id: 'b', name: 'Beta', rating: 2680);
    final match = KnockoutMatch(
      key: 'm',
      stageKey: 'final',
      participant1: alpha,
      participant2: beta,
      games: const [],
      participant1Score: 1,
      participant2Score: 0,
      leader: alpha,
      winner: alpha,
      minimumBoardOrder: 1,
      isComplete: true,
      isLive: false,
    );

    BoxDecoration cardFrame(WidgetTester tester) =>
        tester.widget<Ink>(find.byType(Ink)).decoration! as BoxDecoration;

    Widget card() => SizedBox(
      width: 220,
      height: 92,
      child: KnockoutMatchCard(match: match, onTap: () {}),
    );

    testWidgets('light: one tight shadow cast from above, on paper', (
      tester,
    ) async {
      await _pump(tester, card(), brightness: Brightness.light);
      final frame = cardFrame(tester);
      expect(frame.color, AppColors.light.popup);
      final shadow = frame.boxShadow!.single;
      expect(shadow.color, AppColors.light.shadow);
      expect(shadow.blurRadius, lessThanOrEqualTo(4));
      expect(shadow.offset.dx, 0);
      expect(shadow.offset.dy, greaterThan(0));
    });

    testWidgets('dark: tone alone, no shadow', (tester) async {
      await _pump(tester, card(), brightness: Brightness.dark);
      final frame = cardFrame(tester);
      expect(frame.color, AppColors.dark.popup);
      expect(frame.boxShadow, isNull);
      expect((frame.border! as Border).top.color, AppColors.dark.divider);
    });
  });
}
