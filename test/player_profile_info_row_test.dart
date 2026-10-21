import 'package:chessever2/providers/country_dropdown_provider.dart';
import 'package:chessever2/providers/favorite_players_provider.dart';
import 'package:chessever2/repository/favorites/models/favorite_player.dart';
import 'package:chessever2/screens/countrymen/country_rankings_screen.dart';
import 'package:chessever2/screens/countrymen/tabs/countrymen_players_tab.dart';
import 'package:chessever2/screens/favorites/rankings/ranking_filters.dart';
import 'package:chessever2/screens/player_profile/widgets/player_profile_info_row.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:country_picker/country_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class _NoFavorites extends FavoritePlayersNotifierNew {
  @override
  Future<List<FavoritePlayer>> build() async => [];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const launcher = MethodChannel('plugins.flutter.io/url_launcher');
  final launches = <MethodCall>[];
  final requests = <(String, RankingFilters)>[];
  var launchSucceeds = true;
  var launchThrows = false;

  setUp(() {
    launches.clear();
    requests.clear();
    launchSucceeds = true;
    launchThrows = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(launcher, (call) async {
          launches.add(call);
          if (launchThrows) throw PlatformException(code: 'unavailable');
          return launchSucceeds;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(launcher, null);
  });

  Future<ProviderContainer> pumpInfo(
    WidgetTester tester, {
    String federation = 'NOR',
    int? fideId = 1503014,
    bool memorial = false,
    double width = 393,
    double textScale = 1,
    ThemeData? theme,
  }) async {
    tester.view.physicalSize = Size(width, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final container = ProviderContainer(
      overrides: [
        // Reading the saved-country notifier would boot storage. Profile
        // navigation must never read or change it.
        countryDropdownProvider.overrideWith((ref) {
          throw StateError('Profile rankings touched the pinned country');
        }),
        favoritePlayersProviderNew.overrideWith(_NoFavorites.new),
        countryRankingsFetcherProvider.overrideWithValue(({
          required countryCode,
          required filters,
          required searchQuery,
          required limit,
          required offset,
        }) async {
          requests.add((countryCode, filters));
          return [];
        }),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: theme ?? AppTheme.darkTheme,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: Builder(
            builder: (context) {
              ResponsiveHelper.init(context);
              return Scaffold(
                body: Padding(
                  padding: const EdgeInsets.all(20),
                  child: PlayerProfileInfoRow(
                    fideId: fideId,
                    federation: federation,
                    isMemorial: memorial,
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets('FIDE ID opens the official profile in an external browser', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pumpInfo(tester);
    final link = find.bySemanticsLabel('Open FIDE profile 1503014');
    expect(tester.getSemantics(link).flagsCollection.isLink, isTrue);
    expect(
      tester
          .getSemantics(link)
          .getSemanticsData()
          .hasAction(SemanticsAction.tap),
      isTrue,
    );
    final country = find.bySemanticsLabel('Open Norway rankings');
    expect(
      tester
          .getSemantics(country)
          .getSemanticsData()
          .hasAction(SemanticsAction.tap),
      isTrue,
    );
    expect(tester.getSize(country).height, greaterThanOrEqualTo(48));
    expect(tester.getSize(link).height, greaterThanOrEqualTo(48));
    await tester.tap(find.text('1503014'));
    await tester.pumpAndSettle();
    expect(launches.single.method, 'launch');
    expect(
      launches.single.arguments['url'],
      'https://ratings.fide.com/profile/1503014',
    );
    expect(launches.single.arguments['useSafariVC'], isFalse);
    expect(launches.single.arguments['useWebView'], isFalse);
    expect(tester.takeException(), isNull);
    handle.dispose();
  });

  for (final throws in [false, true]) {
    testWidgets('FIDE launch failure (throws: $throws) shows app snack', (
      tester,
    ) async {
      await pumpInfo(tester);
      launchSucceeds = false;
      launchThrows = throws;
      await tester.tap(find.text('1503014'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Could not open the FIDE profile.'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 5));
    });
  }

  for (final (input, code, name) in [
    ('NOR', 'NOR', 'Norway'),
    (' tr ', 'TUR', 'Turkey'),
    ('Scotland', 'SCO', 'Scotland'),
    ('WLS', 'WLS', 'Wales'),
  ]) {
    testWidgets(
      '$input opens its exact in-app ranking without changing country',
      (tester) async {
        final container = await pumpInfo(tester, federation: input);
        final temporary = CountryService().findByCode('AZ');
        container.read(temporaryCountryProvider.notifier).state = temporary;
        await tester.tap(find.text(name));
        await tester.pumpAndSettle();
        expect(find.byType(CountryRankingsScreen), findsOneWidget);
        expect(find.text('$name rankings'), findsOneWidget);
        expect(requests.single, (code, RankingFilters.defaults));
        expect(
          find.text('No registered chess players found from $name'),
          findsOneWidget,
        );
        expect(container.read(temporaryCountryProvider), same(temporary));
        await tester.tap(
          find.byKey(const ValueKey('ranking-time-control-rapid')),
        );
        await tester.pumpAndSettle();
        expect(requests.last.$1, code);
        expect(requests.last.$2.timeControl, RankingTimeControl.rapid);
        await tester.tap(find.byType(BackButton));
        await tester.pumpAndSettle();
        expect(find.byType(PlayerProfileInfoRow), findsOneWidget);
        expect(container.read(temporaryCountryProvider), same(temporary));
        expect(launches, isEmpty);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final id in [null, 0, -1]) {
    testWidgets('missing or invalid FIDE ID $id has no link', (tester) async {
      await pumpInfo(tester, fideId: id, federation: 'FID');
      expect(find.text('Not assigned'), findsOneWidget);
      await tester.tap(find.text('Not assigned'));
      await tester.tap(find.text('FID'));
      await tester.pumpAndSettle();
      expect(launches, isEmpty);
      expect(requests, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }

  for (final theme in [AppTheme.darkTheme, AppTheme.lightTheme]) {
    testWidgets(
      'narrow profile with large text keeps both targets readable (${theme.brightness})',
      (tester) async {
        await pumpInfo(
          tester,
          federation: 'United States',
          fideId: 12345678901,
          memorial: true,
          width: 320,
          textScale: 2,
          theme: theme,
        );
        expect(find.text('United States'), findsOneWidget);
        expect(find.text('Historical FIDE ID'), findsOneWidget);
        expect(find.text('12345678901'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
