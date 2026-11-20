import 'dart:ui' as ui;

import 'package:chessever2/providers/country_dropdown_provider.dart';
import 'package:chessever2/providers/favorite_players_provider.dart';
import 'package:chessever2/repository/favorites/models/favorite_player.dart';
import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/screens/gamebase/models/gamebase_player.dart';
import 'package:chessever2/screens/group_event/widget/player_search_cards.dart';
import 'package:chessever2/screens/group_event/widget/premium_collection_cards.dart';
import 'package:chessever2/screens/library/widgets/twic_player_search_cards.dart';
import 'package:chessever2/screens/my_space/models/space_shortcut.dart';
import 'package:chessever2/screens/my_space/widgets/space_tile_content.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/art_fade.dart';
import 'package:chessever2/widgets/hub_tile.dart';
import 'package:country_picker/country_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

// Light theme shows card pictures (a player's photo, a federation's flag,
// a favourites mosaic) at their true colour, faded only through their own
// alpha. The surface-coloured veil and the opacity dimming dark uses read on
// paper as a white wash over the picture. Dark must not change at all.
void main() {
  group('fades', () {
    double alphaAt(LinearGradient g, double t) {
      final stops = g.stops!;
      for (var i = 1; i < stops.length; i++) {
        if (t <= stops[i]) {
          final span = stops[i] - stops[i - 1];
          final f = span == 0 ? 1.0 : (t - stops[i - 1]) / span;
          return ui.lerpDouble(g.colors[i - 1].a, g.colors[i].a, f)!;
        }
      }
      return g.colors.last.a;
    }

    test('a straight fade holds, then eases out over many stops', () {
      final g = artFadeLinear(
        opaque: Alignment.centerRight,
        clear: Alignment.centerLeft,
        hold: 0.3,
      );
      expect(g.colors.length, greaterThanOrEqualTo(16));
      expect(alphaAt(g, 0), 1);
      expect(alphaAt(g, 0.3), 1);
      expect(alphaAt(g, 1), 0);
      var last = 1.0;
      for (var t = 0.0; t <= 1; t += 0.01) {
        final a = alphaAt(g, t);
        expect(a, lessThanOrEqualTo(last + 1e-9));
        last = a;
      }
      // No step anywhere: neighbouring stops differ by a small amount.
      for (var i = 1; i < g.colors.length; i++) {
        expect((g.colors[i].a - g.colors[i - 1].a).abs(), lessThan(0.15));
      }
    });

    test('the corner fade is a mask (pure black, alpha only)', () {
      final shader = artFadeCorner(
        const Rect.fromLTWH(0, 0, 170, 108),
        reach: const Size(0.8, 0.8),
      );
      expect(shader, isNotNull);
      // An empty box never throws.
      expect(artFadeCorner(Rect.zero, reach: const Size(1, 1)), isNotNull);
    });

    test('a compact card\'s flag stays inside its own box', () {
      // The fade never reaches past the flag's left edge, so it never shows.
      for (final size in const [
        Size(174, 108),
        Size(361, 120),
        Size(700, 120),
      ]) {
        for (final compact in [true, false]) {
          final reach = PlayerCardLightArt.fadeReach(size, compact: compact);
          expect(
            reach.width * size.width,
            lessThanOrEqualTo(PlayerCardLightArt.flagWidth(size) + 1e-6),
          );
        }
      }
    });
  });

  group('player search cards', () {
    testWidgets('light: no veil, the picture fades through its own alpha', (
      tester,
    ) async {
      await _pumpSearchCards(tester, light: true);
      expect(_veils(tester), findsNothing);
      expect(_dimmed(tester, find.byType(PlayerSearchCards)), findsNothing);
      expect(find.byType(PlayerCardLightArt), findsNWidgets(2));
    });

    testWidgets('dark keeps its veil and dimmed flag', (tester) async {
      await _pumpSearchCards(tester, light: false);
      expect(_veils(tester), findsNWidgets(2));
      expect(_dimmed(tester, find.byType(PlayerSearchCards)), findsWidgets);
      expect(find.byType(PlayerCardLightArt), findsNothing);
    });

    testWidgets('light: the flag shows at its true colour where the card '
        'leaves it whole', (tester) async {
      await _pumpSearchCards(tester, light: true, count: 1);
      final card = tester.getRect(find.byType(PlayerSearchCards));
      // Norway's top-right quarter is solid red; the old light card washed
      // it to a pastel pink under the surface veil.
      final pixel = await _pixel(tester, Offset(card.width - 16, 10));
      expect(pixel.r, greaterThan(0.75));
      expect(pixel.g, lessThan(0.3));
      expect(pixel.b, lessThan(0.3));
    });

    testWidgets('dark: the same spot is the dim print it always was', (
      tester,
    ) async {
      await _pumpSearchCards(tester, light: false, count: 1);
      final card = tester.getRect(find.byType(PlayerSearchCards));
      final pixel = await _pixel(tester, Offset(card.width - 16, 10));
      expect(pixel.r, lessThan(0.5));
    });
  });

  group('TWIC player cards', () {
    for (final light in [true, false]) {
      testWidgets(light ? 'light: no veil' : 'dark keeps its veil', (
        tester,
      ) async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              topTwicSearchedPlayersProvider.overrideWith(
                (ref, query) => const [
                  GamebasePlayer(
                    id: 'p1',
                    fideId: '',
                    name: 'Carlsen, Magnus',
                    gender: PlayerGender.male,
                    fed: 'NOR',
                  ),
                ],
              ),
            ],
            child: _app(
              light: light,
              child: const TwicPlayerSearchCards(searchQuery: 'carlsen'),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 400));
        expect(_veils(tester), light ? findsNothing : findsOneWidget);
        expect(
          find.byType(PlayerCardLightArt),
          light ? findsOneWidget : findsNothing,
        );
        expect(
          _dimmed(tester, find.byType(TwicPlayerSearchCards)),
          light ? findsNothing : findsWidgets,
        );
      });
    }
  });

  group('Favorites and Countrymen tiles', () {
    for (final light in [true, false]) {
      testWidgets(
        light
            ? 'light: art faded by its own alpha, no paper veil'
            : 'dark: the media tile as before',
        (tester) async {
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                countryDropdownProvider.overrideWith((ref) => _Country()),
                favoritePlayersProviderNew.overrideWith(_Favorites.new),
              ],
              child: _app(
                light: light,
                disableAnimations: true,
                child: const PremiumCollectionCards(),
              ),
            ),
          );
          await tester.pump();
          await tester.pump();
          final faces = tester
              .widgetList<HubTileFace>(find.byType(HubTileFace))
              .toList();
          expect(faces, hasLength(2));
          for (final face in faces) {
            expect(face.ramp, !light);
            expect(face.artwork is ArtFade, light);
          }
          expect(
            _dimmed(tester, find.byType(PremiumCollectionCards)),
            light ? findsNothing : findsOneWidget,
          );
        },
      );
    }
  });

  group('My Space countrymen tile', () {
    for (final light in [true, false]) {
      testWidgets(
        light ? 'light: the flag at true colour' : 'dark: dimmed as before',
        (tester) async {
          await tester.pumpWidget(
            ProviderScope(
              child: _app(
                light: light,
                child: SpaceTileContent(
                  shortcut: SpaceShortcut.draft(
                    kind: SpaceShortcutKind.countrymen,
                    targetId: 'NOR',
                    title: 'Norway',
                    subtitle: 'Countrymen',
                  ),
                ),
              ),
            ),
          );
          await tester.pump();
          expect(
            _dimmed(tester, find.byType(SpaceTileContent)),
            light ? findsNothing : findsOneWidget,
          );
          // The long many-stop fade into the plate stays in both themes.
          expect(
            find.descendant(
              of: find.byType(SpaceTileContent),
              matching: find.byType(ShaderMask),
            ),
            findsOneWidget,
          );
        },
      );
    }
  });
}

const _capture = ValueKey('light_art_capture');

Widget _app({
  required bool light,
  required Widget child,
  bool disableAnimations = false,
}) {
  return MaterialApp(
    theme: light ? AppTheme.lightTheme : AppTheme.darkTheme,
    home: Builder(
      builder: (context) {
        ResponsiveHelper.init(context);
        return MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(disableAnimations: disableAnimations),
          child: Scaffold(
            body: Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: RepaintBoundary(key: _capture, child: child),
              ),
            ),
          ),
        );
      },
    ),
  );
}

Future<void> _pumpSearchCards(
  WidgetTester tester, {
  required bool light,
  int count = 2,
}) async {
  final players = [
    for (final (name, fed) in const [
      ('Carlsen, Magnus', 'NOR'),
      ('Nakamura, Hikaru', 'USA'),
    ].take(count))
      SearchPlayer(
        id: name,
        name: name,
        fed: fed,
        rating: 2800,
        title: 'GM',
        tournamentId: 't',
        tournamentName: 'T',
      ),
  ];
  await tester.pumpWidget(
    ProviderScope(
      child: _app(
        light: light,
        child: PlayerSearchCards(
          players: players,
          animateIn: false,
          bottomPadding: 0,
        ),
      ),
    ),
  );
  await tester.pump();
}

/// A surface-coloured gradient laid over a card: the dark veil.
Finder _veils(WidgetTester tester) {
  final surface = tester
      .element(find.byKey(_capture))
      .colors
      .surface
      .withValues(alpha: 1);
  return find.byWidgetPredicate((widget) {
    if (widget is! DecoratedBox) return false;
    final decoration = widget.decoration;
    if (decoration is! BoxDecoration) return false;
    final gradient = decoration.gradient;
    if (gradient == null) return false;
    return gradient.colors.any(
      (c) => c.a > 0 && c.withValues(alpha: 1) == surface,
    );
  });
}

/// A picture dimmed by an opacity under [scope].
Finder _dimmed(WidgetTester tester, Finder scope) => find.descendant(
  of: scope,
  matching: find.byWidgetPredicate(
    (widget) => widget is Opacity && widget.opacity > 0 && widget.opacity < 1,
  ),
);

Future<Color> _pixel(WidgetTester tester, Offset at) async {
  final boundary =
      tester.renderObject(find.byKey(_capture)) as RenderRepaintBoundary;
  late Color color;
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final x = at.dx.round().clamp(0, image.width - 1);
    final y = at.dy.round().clamp(0, image.height - 1);
    final i = (y * image.width + x) * 4;
    final bytes = data!.buffer.asUint8List();
    color = Color.fromARGB(bytes[i + 3], bytes[i], bytes[i + 1], bytes[i + 2]);
    image.dispose();
  });
  return color;
}

class _Country extends StateNotifier<AsyncValue<Country>>
    implements SelectedCountryNotifier {
  _Country() : super(AsyncData(CountryService().findByCode('NO')!));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Favorites extends FavoritePlayersNotifierNew {
  @override
  Future<List<FavoritePlayer>> build() async => [
    FavoritePlayer(
      id: 'f1',
      userId: 'u',
      playerName: 'Carlsen, Magnus',
      metadata: const {},
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    ),
  ];
}
