import 'package:chessever2/screens/chessboard/widgets/share_game_card_overlay.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessground/chessground.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

const _url = 'https://chessever.com/g/abc123';

/// Pumps the overlay and returns after its FIRST frame, before any spring
/// has ticked.
Future<void> _pumpFirstFrame(
  WidgetTester tester, {
  ThemeData? theme,
  bool reduceMotion = false,
}) async {
  await tester.binding.setSurfaceSize(const Size(430, 932));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        key: UniqueKey(),
        theme: theme ?? AppTheme.darkTheme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(disableAnimations: reduceMotion),
          child: child!,
        ),
        home: Builder(
          builder: (context) {
            ResponsiveHelper.init(context);
            return ShareGameCardOverlay(
              boardSettings: const ChessboardSettings(),
              positionFen: '8/8/4k3/8/8/4K3/8/8 w - - 0 60',
              lastMove: null,
              pgn: '1. e4 e5 *',
              moveSans: const ['e4', 'e5'],
              whitePlayerName: 'Carlsen, Magnus',
              blackPlayerName: 'Nakamura, Hikaru',
              currentMoveIndex: 1,
              evaluation: 0.0,
              mate: 0,
              isFlipped: false,
              gameStatus: GameStatus.ongoing,
              onClose: () {},
              shareUrl: _url,
              gameId: 'test',
            );
          },
        ),
      ),
    ),
  );
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 25; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// The entrance transform a keyed piece of chrome sits in. For the card,
/// `entry(0, 0)` is its scale (z stays 1, so not `getMaxScaleOnAxis`).
Matrix4 _entrance(WidgetTester tester, String key) => tester
    .widgetList<Transform>(
      find.descendant(
        of: find.byKey(ValueKey(key)),
        matching: find.byType(Transform),
      ),
    )
    .first
    .transform;

const _chrome = [
  'share-eval-toggle-entrance',
  'share-link-entrance',
  'share-actions-entrance',
];

void main() {
  testWidgets('every piece of chrome is painted on the first frame', (
    tester,
  ) async {
    await _pumpFirstFrame(tester);

    // Nothing waits behind an opacity: no fade sits over the chrome.
    for (final label in ['Eval Bar', _url, 'Share Image', 'Copy FEN']) {
      final text = find.text(label);
      expect(text, findsOneWidget, reason: label);
      final fades = [
        ...tester
            .widgetList<Opacity>(
              find.ancestor(of: text, matching: find.byType(Opacity)),
            )
            .map((o) => o.opacity),
        ...tester
            .widgetList<FadeTransition>(
              find.ancestor(of: text, matching: find.byType(FadeTransition)),
            )
            .map((f) => f.opacity.value),
      ];
      expect(fades.where((o) => o < 1), isEmpty, reason: label);
    }

    // The motion is real: the card starts at 95% and the rows start below
    // their slots, each a little further down than the one above.
    expect(
      _entrance(tester, 'share-preview-entrance').entry(0, 0),
      closeTo(0.95, 1e-9),
    );
    final rises = [
      for (final key in _chrome) _entrance(tester, key).getTranslation().y,
    ];
    expect(rises.first, greaterThan(0));
    expect(rises, orderedEquals([...rises]..sort()));
  });

  testWidgets('at rest every transform is the exact identity', (tester) async {
    await _pumpFirstFrame(tester);
    await _settle(tester);

    expect(_entrance(tester, 'share-preview-entrance').entry(0, 0), 1.0);
    for (final key in _chrome) {
      expect(_entrance(tester, key).getTranslation().y, 0.0, reason: key);
    }
  });

  testWidgets('reduced motion starts every piece at rest', (tester) async {
    await _pumpFirstFrame(tester, reduceMotion: true);

    expect(_entrance(tester, 'share-preview-entrance').entry(0, 0), 1.0);
    for (final key in _chrome) {
      expect(_entrance(tester, key).getTranslation().y, 0.0, reason: key);
    }
  });

  testWidgets('the eval switch rests on its exact end colours in dark', (
    tester,
  ) async {
    await _pumpFirstFrame(tester);
    await _settle(tester);

    BoxDecoration track() => tester
        .widgetList<Container>(
          find.descendant(
            of: find.bySemanticsLabel('Eval Bar'),
            matching: find.byType(Container),
          ),
        )
        .map((c) => c.decoration)
        .whereType<BoxDecoration>()
        // The pill around the switch is the dark surface; the knob is round.
        .where(
          (d) =>
              d.shape == BoxShape.rectangle &&
              d.border != null &&
              d.color != AppColors.dark.surface,
        )
        .single;

    // On by default: the brand track.
    expect(track().color, kPrimaryColor);

    await tester.tap(find.bySemanticsLabel('Eval Bar'));
    await _settle(tester);
    expect(track().color, AppColors.dark.surfaceRecessed);
    expect((track().border! as Border).top.color, AppColors.dark.divider);
  });
}
