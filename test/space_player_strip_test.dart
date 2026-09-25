import 'package:chessever2/screens/favorites/tabs/favorites_players_tab.dart';
import 'package:chessever2/screens/my_space/models/space_shortcut.dart';
import 'package:chessever2/screens/my_space/providers/space_shortcuts_provider.dart';
import 'package:chessever2/screens/my_space/widgets/space_avatar.dart';
import 'package:chessever2/screens/my_space/widgets/space_player_strip.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/space_shortcut_drafts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class _Store extends SpaceShortcutsNotifier {
  @override
  Future<List<SpaceShortcut>> build() async => const [];
}

final _carlsen = spacePlayerDraft(
  playerName: 'Carlsen, Magnus',
  fideId: 1503014,
  title: 'GM',
  federation: 'NO',
  rating: 2837,
);

final _gukesh = spacePlayerDraft(
  playerName: 'Gukesh D',
  fideId: 46616543,
  title: 'GM',
  federation: 'IN',
  rating: 2787,
);

Future<void> _pump(
  WidgetTester tester,
  List<SpaceShortcut> players, {
  Set<int> live = const {},
  ThemeData? theme,
  bool wrap = false,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        playerPhotoProvider.overrideWith((ref, id) async => null),
        spaceShortcutsProvider.overrideWith(_Store.new),
      ],
      child: MaterialApp(
        theme: theme ?? AppTheme.darkTheme,
        home: Builder(
          builder: (context) {
            ResponsiveHelper.init(context);
            return Scaffold(
              body: Align(
                alignment: Alignment.topLeft,
                child: SpacePlayerStrip(
                  players: players,
                  liveFideIds: live,
                  padding: 16,
                  wrap: wrap,
                ),
              ),
            );
          },
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  test('surnames: comma names, given-first names, a trailing initial', () {
    expect(spaceSurname('Carlsen, Magnus'), 'Carlsen');
    expect(spaceSurname('Magnus Carlsen'), 'Carlsen');
    expect(spaceSurname('Gukesh D'), 'Gukesh');
    expect(spaceSurname('Praggnanandhaa R.'), 'Praggnanandhaa');
    expect(spaceInitials('Carlsen, Magnus'), 'MC');
    expect(spaceInitials('Gukesh D'), 'GD');
  });

  testWidgets('a face without a photo is flat initials, never a gradient', (
    tester,
  ) async {
    await _pump(tester, [_carlsen]);

    expect(find.byType(SpacePlayerAvatar), findsOneWidget);
    expect(find.text('MC'), findsOneWidget);
    final gradients = find.descendant(
      of: find.byType(SpacePlayerAvatar),
      matching: find.byWidgetPredicate(
        (w) =>
            (w is Container &&
                w.decoration is BoxDecoration &&
                (w.decoration! as BoxDecoration).gradient != null) ||
            (w is DecoratedBox &&
                w.decoration is BoxDecoration &&
                (w.decoration as BoxDecoration).gradient != null),
      ),
    );
    expect(gradients, findsNothing);
    final disc = tester.widget<ColoredBox>(
      find
          .descendant(
            of: find.byType(SpacePlayerAvatar),
            matching: find.byType(ColoredBox),
          )
          .first,
    );
    expect(disc.color, AppColors.dark.surfaceRecessed);
    // The title band and the standing line.
    expect(find.text('GM'), findsOneWidget);
    expect(find.text('Carlsen'), findsOneWidget);
    expect(find.text('2837'), findsOneWidget);
  });

  testWidgets('a player at the board reads LIVE instead of the rating', (
    tester,
  ) async {
    await _pump(tester, [_carlsen, _gukesh], live: {46616543});

    expect(find.text('LIVE'), findsOneWidget);
    expect(find.text('2787'), findsNothing);
    expect(find.text('2837'), findsOneWidget);
  });

  testWidgets('every face is at least a 44 target', (tester) async {
    await _pump(tester, [_carlsen, _gukesh]);

    for (final face in find.byType(SpacePlayerFace).evaluate()) {
      final size = (face.renderObject! as RenderBox).size;
      expect(size.width, greaterThanOrEqualTo(44));
      expect(size.height, greaterThanOrEqualTo(44));
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('every name is one size on one line: a long surname ends in '
      'an ellipsis rather than shrinking', (tester) async {
    final nepo = spacePlayerDraft(
      playerName: 'Nepomniachtchi, Ian',
      fideId: 4168119,
      title: 'GM',
      federation: 'RU',
      rating: 2757,
    );
    await _pump(tester, [_gukesh, nepo]);

    expect(
      find.descendant(
        of: find.byType(SpacePlayerStrip),
        matching: find.byType(FittedBox),
      ),
      findsNothing,
    );
    final short = tester.widget<Text>(find.text('Gukesh'));
    final long = tester.widget<Text>(find.text('Nepomniachtchi'));
    expect(short.style!.fontSize, long.style!.fontSize);
    expect(long.maxLines, 1);
    expect(long.overflow, TextOverflow.ellipsis);
    expect(
      tester.getBottomLeft(find.text('Gukesh')).dy,
      tester.getBottomLeft(find.text('Nepomniachtchi')).dy,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('See all sets the faces in rows of whole faces', (tester) async {
    await _pump(tester, [
      for (var i = 0; i < 7; i++)
        spacePlayerDraft(
          playerName: 'Player $i',
          fideId: 100 + i,
          title: 'GM',
          rating: 2700,
        ),
    ], wrap: true);

    expect(find.byType(Wrap), findsOneWidget);
    final width = tester.getSize(find.byType(Scaffold)).width;
    for (final face in find.byType(SpacePlayerFace).evaluate()) {
      final box = face.renderObject! as RenderBox;
      final right = box.localToGlobal(Offset(box.size.width, 0)).dx;
      expect(right, lessThanOrEqualTo(width));
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('holding a face offers Open and My Space', (tester) async {
    await _pump(tester, [_carlsen]);

    await tester.longPress(find.byType(SpacePlayerFace));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Open'), findsOneWidget);
    expect(find.text('Add to My Space'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
  });
}
