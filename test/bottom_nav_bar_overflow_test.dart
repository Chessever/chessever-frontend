import 'dart:io';

import 'package:chessever2/providers/auth_state_provider.dart';
import 'package:chessever2/repository/authentication/model/app_user.dart';
import 'package:chessever2/screens/home/widget/bottom_nav_bar.dart';
import 'package:chessever2/screens/home/widget/bottom_nav_bar_widget.dart';
import 'package:chessever2/screens/home/widget/home_nav_dock.dart';
import 'package:chessever2/screens/inbox/inbox_provider.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/phone_update_route_observer.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

void main() {
  // Botvinnik has a slot only when it is built in and not switched off; the
  // bar must hold up either way.
  for (final botvinnik in [true, false]) {
    final titles = [
      'Home',
      'Feed',
      if (botvinnik) 'Botvinnik',
      'Collections',
      'Profile',
    ];

    testWidgets('bottom nav bar (${titles.join(', ')}) never overflows on a '
        'short 393px screen at large text scale with a gesture-nav inset', (
      tester,
    ) async {
      // The regression: the nav-item Column (icon + label + vertical padding,
      // whose label height rides MediaQuery.textScaler) was placed in a fixed
      // height slot — clamp(70.h + inset, 70, 120) minus the inset. On a short
      // screen and/or large accessibility text scale and/or a large safe-area
      // inset, that slot dropped a few pixels below the Column's intrinsic
      // height and the bottom overflowed. This combination forces it.
      final mediaQuery = const MediaQueryData(
        size: Size(393, 600),
        devicePixelRatio: 3,
        viewPadding: EdgeInsets.only(bottom: 34),
        padding: EdgeInsets.only(bottom: 34),
      ).copyWith(textScaler: const TextScaler.linear(3));

      // Capture overflow specifically; svg assets aren't bundled in the unit
      // test, so SvgWidget's errorBuilder fires — we must not let that noise
      // mask (or fake) the layout assertion.
      final errors = <FlutterErrorDetails>[];
      final previousOnError = FlutterError.onError;
      FlutterError.onError = errors.add;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            // The Botvinnik switch lives in SQLite, which retries on a timer
            // here.
            botvinnikTabAvailableProvider.overrideWithValue(botvinnik),
            // Profile wears the reader's avatar: a signed-out reader, so the
            // bare person mark.
            currentUserProvider.overrideWithValue(null),
            profileAvatarUrlProvider.overrideWithValue(null),
            inboxHasUnreadProvider.overrideWithValue(false),
          ],
          child: MaterialApp(
            theme: AppTheme.darkTheme,
            home: MediaQuery(
              data: mediaQuery,
              child: Builder(
                builder: (context) {
                  ResponsiveHelper.init(context);
                  return const Scaffold(
                    bottomNavigationBar: BottomNavBar(),
                    body: SizedBox.shrink(),
                  );
                },
              ),
            ),
          ),
        ),
      );

      FlutterError.onError = previousOnError;

      // Equal slots across 393px, in bar order.
      expect(find.byType(BottomNavBarWidget), findsNWidgets(titles.length));
      expect(
        tester
            .widgetList<BottomNavBarWidget>(find.byType(BottomNavBarWidget))
            .map((item) => item.title)
            .toList(),
        titles,
      );
      // The tabs that left the bar stay off it.
      expect(find.text('Events'), findsNothing);
      expect(find.text('Collections'), findsNothing);
      expect(find.text('Calendar'), findsNothing);
      // Marks only: no names drawn, but every slot announces its own.
      for (final title in titles) {
        expect(find.text(title), findsNothing);
      }
      expect(find.byIcon(Icons.home_rounded), findsOneWidget);
      // Signed out, Profile's avatar falls back to the person mark.
      expect(find.byIcon(Icons.person_rounded), findsOneWidget);
      final semantics = tester.ensureSemantics();
      for (final title in titles) {
        expect(find.bySemanticsLabel(title), findsOneWidget);
      }
      semantics.dispose();
      // Equal slots across the full capsule (the screen less its margins),
      // inside its round ends.
      const capsule = 393 - 2 * HomeNavMetrics.sideMargin;
      for (final widget in tester.widgetList<BottomNavBarWidget>(
        find.byType(BottomNavBarWidget),
      )) {
        expect(
          widget.width,
          closeTo(
            (capsule - 2 * HomeNavMetrics.padding) / titles.length,
            0.001,
          ),
        );
      }
      expect(
        tester.getSize(find.byKey(const ValueKey('home-nav-capsule'))),
        const Size(capsule, HomeNavMetrics.normalHeight),
      );

      // A fixed slot, whatever the text scale: the full capsule plus the
      // strip under it, which on Android (the test's platform) clears the
      // whole gesture area.
      final bar = tester.getSize(find.byType(BottomNavBar)).height - 34;
      expect(bar, closeTo(BottomNavBarWidget.barHeight, 1.01));
      // Every slot answers down through the strip under the capsule: no
      // dead strip under the marks.
      for (final slot in tester.widgetList<BottomNavBarWidget>(
        find.byType(BottomNavBarWidget),
      )) {
        expect(
          tester.getSize(find.byWidget(slot)).height,
          closeTo(bar + 34, 1.01),
        );
      }
      for (final item in tester.widgetList<BottomNavBarWidget>(
        find.byType(BottomNavBarWidget),
      )) {
        expect(item.width, greaterThanOrEqualTo(44));
        expect(
          tester.getSize(find.byWidget(item)).height,
          greaterThanOrEqualTo(44),
        );
      }
      final overflowErrors = errors
          .map((e) => e.exceptionAsString())
          .where((e) => e.contains('overflowed'))
          .toList();

      expect(overflowErrors, isEmpty, reason: overflowErrors.join('\n'));
    });
  }

  group('Profile avatar', () {
    setUpAll(() async {
      // Centring is measured in the app font, not square Ahem.
      final fonts = FontLoader('InterDisplay');
      for (final weight in ['Regular', 'Medium', 'Bold']) {
        fonts.addFont(
          File(
            'assets/fonts/Inter-$weight.otf',
          ).readAsBytes().then(ByteData.sublistView),
        );
      }
      await fonts.load();
    });

    const avatar = Key('avatar');

    Future<void> pumpAvatar(WidgetTester tester, AppUser? user) {
      return tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentUserProvider.overrideWithValue(user),
            profileAvatarUrlProvider.overrideWithValue(null),
            inboxHasUnreadProvider.overrideWithValue(false),
          ],
          child: MaterialApp(
            theme: AppTheme.darkTheme,
            home: Builder(
              builder: (context) {
                ResponsiveHelper.init(context);
                return Center(
                  child: KeyedSubtree(
                    key: avatar,
                    child: bottomNavBarGlyph(
                      BottomNavBarItem.profile,
                      ink: Colors.white,
                      side: 24,
                      selected: true,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      );
    }

    final created = DateTime.utc(2026, 11, 18);

    for (final (label, user) in [
      ('signed out', null),
      (
        'a guest',
        AppUser(
          id: 'guest',
          displayName: 'Guest',
          createdAt: created,
          isAnonymous: true,
        ),
      ),
    ]) {
      testWidgets('$label wears the bare person mark, never one on a disc', (
        tester,
      ) async {
        await pumpAvatar(tester, user);
        expect(find.byIcon(Icons.person_rounded), findsOneWidget);
        // A guest's name is the word "Guest": no "G" stands in for a face.
        expect(find.text('G'), findsNothing);
        expect(
          find.descendant(
            of: find.byKey(avatar),
            matching: find.byType(DecoratedBox),
          ),
          findsNothing,
        );
        // Same square as a reader's avatar, so the slot does not move.
        expect(tester.getSize(find.byKey(avatar)), const Size(28, 28));
      });
    }

    testWidgets('a reader\'s initial sits on the centre of its disc', (
      tester,
    ) async {
      await pumpAvatar(
        tester,
        AppUser(id: 'reader', displayName: 'magnus', createdAt: created),
      );
      final initial = find.text('M');
      expect(initial, findsOneWidget);
      final paragraph = tester.renderObject<RenderParagraph>(initial);
      final fontSize = (paragraph.text as TextSpan).style!.fontSize!;
      // The laid-out line, measured again outside layout.
      final line = TextPainter(
        text: paragraph.text,
        textDirection: TextDirection.ltr,
        textScaler: paragraph.textScaler,
      )..layout();
      addTearDown(line.dispose);
      expect(line.height, closeTo(paragraph.size.height, 0.001));
      final baseline = line.computeDistanceToActualBaseline(
        TextBaseline.alphabetic,
      );
      // Inter's capitals stand 1490 of its 2048 units tall.
      final capCentre =
          tester.getTopLeft(initial).dy + baseline - fontSize * 1490 / 2048 / 2;
      final disc = find.descendant(
        of: find.byKey(avatar),
        matching: find.byType(ClipOval),
      );
      expect(capCentre, closeTo(tester.getCenter(disc).dy, 0.05));
      expect(
        tester.getCenter(initial).dx,
        closeTo(tester.getCenter(disc).dx, 0.05),
      );
    });
  });

  test('the section Home shows tells the update reminder whether it may open '
      'over Home', () {
    addTearDown(() => PhoneUpdateRouteObserver.homeSectionSafe.value = true);
    final container = ProviderContainer();
    final hold = container.listen(selectedBottomNavBarItemProvider, (_, _) {});
    // Home, the default start section, is a page to browse.
    expect(PhoneUpdateRouteObserver.homeSectionSafe.value, isTrue);
    for (final item in BottomNavBarItem.values) {
      container.read(selectedBottomNavBarItemProvider.notifier).state = item;
      expect(
        PhoneUpdateRouteObserver.homeSectionSafe.value,
        item == BottomNavBarItem.forYou || item == BottomNavBarItem.profile,
        reason: item.name,
      );
    }
    container.read(selectedBottomNavBarItemProvider.notifier).state =
        BottomNavBarItem.botvinnik;
    expect(PhoneUpdateRouteObserver.homeSectionSafe.value, isFalse);
    hold.close();
    // Left on Botvinnik, then Home is gone: nothing holds the reminder.
    container.dispose();
    expect(PhoneUpdateRouteObserver.homeSectionSafe.value, isTrue);
  });
}
