import 'package:chessever2/e2e/e2e_ids.dart';
import 'package:chessever2/providers/app_version_provider.dart';
import 'package:chessever2/repository/authentication/auth_repository.dart';
import 'package:chessever2/repository/authentication/model/app_user.dart';
import 'package:chessever2/repository/authentication/model/auth_state.dart';
import 'package:chessever2/revenue_cat_service/subscribe_state.dart';
import 'package:chessever2/screens/calendar/calendar_screen.dart';
import 'package:chessever2/screens/calendar/provider/calendar_month_events_provider.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/hamburger_menu/hamburger_menu.dart';
import 'package:chessever2/widgets/hamburger_menu/hamburger_menu_dialogs.dart';
import 'package:chessever2/widgets/user_avatar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// WCAG 2.x contrast of [ink] (composited over [paper]) against [paper].
double _contrast(Color ink, Color paper) {
  final fg = Color.alphaBlend(ink, paper).computeLuminance();
  final bg = paper.computeLuminance();
  final hi = fg > bg ? fg : bg;
  final lo = fg > bg ? bg : fg;
  return (hi + 0.05) / (lo + 0.05);
}

final _themes = <(String, ThemeData, AppColors)>[
  ('light', AppTheme.lightTheme, AppColors.light),
  ('dark', AppTheme.darkTheme, AppColors.dark),
];

class _SignedInAuth extends AuthController {
  @override
  Future<AppAuthState> build() async => AppAuthState.authenticated(
    AppUser(id: 'user-1', displayName: 'Ada', createdAt: DateTime(2026)),
  );
}

class _FreeSubscription extends SubscriptionNotifier {
  _FreeSubscription() : super() {
    state = SubscriptionState(isSubscribed: false, isLoading: false);
  }

  // RevenueCat has no plugin under test; hold the resolved free state.
  @override
  set state(SubscriptionState value) =>
      super.state = value.copyWith(isSubscribed: false, isLoading: false);
}

HamburgerMenuCallbacks _callbacks() => HamburgerMenuCallbacks(
  onPlayersPressed: () {},
  onBoardPressed: () {},
  onFavoritesPressed: () {},
  onSupportPressed: () {},
  onPremiumPressed: () {},
  onLogoutPressed: () {},
);

Widget _app({
  required ThemeData theme,
  required Widget child,
  double textScale = 1,
}) {
  return ProviderScope(
    overrides: [
      authStateProvider.overrideWith(_SignedInAuth.new),
      subscriptionProvider.overrideWith((ref) => _FreeSubscription()),
      appVersionProvider.overrideWith((ref) async => '35.11.0'),
      availableYearsProvider.overrideWith((ref) => const [2026]),
      calendarMonthEventsProvider.overrideWith(
        (ref, args) async => CalendarMonthEvents(
          year: args.year,
          month: args.month,
          broadcasts: const [],
          calendarEvents: const [],
        ),
      ),
    ],
    child: MaterialApp(
      theme: theme,
      home: Builder(
        builder: (context) {
          ResponsiveHelper.init(context);
          return MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: Scaffold(
              body: Align(alignment: Alignment.topLeft, child: child),
            ),
          );
        },
      ),
    ),
  );
}

/// Status bar and home indicator of the phone the drawer is pumped on.
const _topInset = 24.0;
const _bottomInset = 34.0;

/// The phone drawer on a 360x640 phone with a status bar and a home
/// indicator. The view itself is sized, not only the test surface: the
/// responsive helpers read MediaQuery, which follows the view, and at the
/// default 800x600 they would lay out the tablet drawer instead.
Future<void> _pumpDrawer(
  WidgetTester tester, {
  required ThemeData theme,
  double textScale = 1,
  Key? key,
}) async {
  const insets = FakeViewPadding(top: _topInset * 3, bottom: _bottomInset * 3);
  tester.view
    ..physicalSize = const Size(360, 640) * 3
    ..devicePixelRatio = 3
    ..padding = insets
    ..viewPadding = insets;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    _app(
      theme: theme,
      textScale: textScale,
      child: HamburgerMenu(key: key, callbacks: _callbacks()),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _inDrawer(Finder finder) => find.descendant(
  of: find.byKey(e2eKey(E2eIds.homeDrawer)),
  matching: finder,
);

void main() {
  testWidgets(
    'one list: the account rows scroll with the menu, nothing is pinned',
    (tester) async {
      await _pumpDrawer(tester, theme: AppTheme.lightTheme, textScale: 1.3);
      expect(tester.takeException(), isNull);

      final lists = _inDrawer(find.byType(Scrollable));
      expect(lists, findsOneWidget);
      for (final label in [
        'Board',
        'About',
        'Get Premium',
        'Restore purchases',
        'Log out',
      ]) {
        expect(
          find.descendant(of: lists, matching: find.text(label)),
          findsOneWidget,
          reason: '$label sits in the one list',
        );
      }

      // Nothing is cut at 1.3x on the 238-wide drawer: the month title is
      // whole and clear of the chevrons, and "Get Premium" keeps one line
      // (beside the button it broke mid-word).
      final title = find.byKey(const ValueKey('sidebar_calendar_title'));
      final titleText = tester.renderObject<RenderParagraph>(title);
      expect(titleText.didExceedMaxLines, isFalse);
      expect(tester.widget<Text>(title).overflow, isNot(TextOverflow.ellipsis));
      expect(
        tester.getRect(title).right,
        lessThanOrEqualTo(
          tester.getRect(find.byTooltip('Previous month')).left,
        ),
      );
      final premium = tester.renderObject<RenderParagraph>(
        find.text('Get Premium'),
      );
      final oneLine = TextPainter(
        text: premium.text,
        textDirection: TextDirection.ltr,
        textScaler: premium.textScaler,
        maxLines: 1,
      )..layout();
      addTearDown(oneLine.dispose);
      expect(premium.size.height, closeTo(oneLine.height, 0.5));
      expect(premium.size.width, greaterThanOrEqualTo(oneLine.width - 0.5));
      final upgrade = tester.getRect(find.byKey(e2eKey(E2eIds.drawerPremium)));
      expect(
        upgrade.top,
        greaterThanOrEqualTo(tester.getRect(find.text('Get Premium')).bottom),
      );

      // The phone drawer, not the tablet one: 260 design points wide.
      expect(
        tester.getSize(find.byKey(e2eKey(E2eIds.homeDrawer))).width,
        closeTo(260 * 360 / 393, 0.5),
      );

      // One left margin: the menu marks start on the avatar's edge, the
      // same edge the upgrade card's surface starts on.
      final margin = tester.getRect(find.byType(UserAvatar)).left;
      for (final icon in [Icons.leaderboard_outlined, Icons.restore_rounded]) {
        expect(
          tester.getRect(_inDrawer(find.byIcon(icon))).left,
          closeTo(margin, 1),
          reason: '$icon',
        );
      }

      // Every label, Log out included, starts on one line whatever its
      // icon's own size.
      final labelLeft = tester.getRect(find.text('Board')).left;
      for (final label in [
        'Rankings',
        'Streaks',
        'Settings',
        'About',
        'Restore purchases',
        'Log out',
      ]) {
        expect(
          tester.getRect(find.text(label)).left,
          closeTo(labelLeft, 0.5),
          reason: label,
        );
      }

      // On a short phone the account rows start below the fold, laid out
      // in the list rather than floated over it.
      final logOut = find.text('Log out');
      expect(tester.getRect(logOut).top, greaterThan(640));

      await tester.scrollUntilVisible(logOut, 200, scrollable: lists);
      await tester.pumpAndSettle();
      final row = tester.getRect(logOut);
      // Scrolled home, the last row clears the home indicator.
      expect(row.bottom, lessThanOrEqualTo(640 - _bottomInset));
      // Rows never overlap on the way down.
      final restore = tester.getRect(find.text('Restore purchases'));
      expect(restore.bottom, lessThanOrEqualTo(row.top));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('every drawer control is at least 44dp to tap', (tester) async {
    await _pumpDrawer(tester, theme: AppTheme.lightTheme);

    for (final label in ['Board', 'Settings', 'Restore purchases']) {
      final row = find.ancestor(
        of: find.text(label),
        matching: find.byType(InkWell),
      );
      expect(tester.getSize(row.first).height, greaterThanOrEqualTo(44));
    }
    expect(
      tester.getSize(find.byKey(e2eKey(E2eIds.drawerLogout))).height,
      greaterThanOrEqualTo(44),
    );
    expect(
      tester.getSize(find.byKey(e2eKey(E2eIds.drawerPremium))).height,
      greaterThanOrEqualTo(44),
    );
    final dismiss = tester.getSize(
      find.ancestor(
        of: find.byIcon(Icons.close_rounded),
        matching: find.byType(IconButton),
      ),
    );
    expect(dismiss.width, greaterThanOrEqualTo(44));
    expect(dismiss.height, greaterThanOrEqualTo(44));
  });

  testWidgets('a dismissed upgrade card stays dismissed for the session', (
    tester,
  ) async {
    await _pumpDrawer(tester, theme: AppTheme.darkTheme);
    expect(find.text('Get Premium'), findsOneWidget);

    await tester.ensureVisible(find.byTooltip('Dismiss'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Dismiss'));
    await tester.pumpAndSettle();
    expect(find.text('Get Premium'), findsNothing);

    // The drawer is rebuilt from scratch on every open.
    await tester.pumpWidget(
      _app(
        theme: AppTheme.darkTheme,
        child: HamburgerMenu(key: UniqueKey(), callbacks: _callbacks()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Get Premium'), findsNothing);
    expect(find.text('Restore purchases'), findsOneWidget);
  });

  for (final (name, theme, colors) in _themes) {
    testWidgets('$name: drawer ink clears AA on its surfaces', (tester) async {
      await _pumpDrawer(tester, theme: theme);
      final paper = colors.background;

      Color ink(String text) =>
          tester.widget<Text>(_inDrawer(find.text(text))).style!.color!;

      for (final label in [
        'Ada',
        'Full calendar',
        'Board',
        'Rankings',
        'Streaks',
        'Settings',
        'About',
        'Restore purchases',
        'Log out',
      ]) {
        expect(
          _contrast(ink(label), paper),
          greaterThanOrEqualTo(4.5),
          reason: label,
        );
      }
      expect(
        _contrast(ink('Get Premium'), colors.surface),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        _contrast(ink('Upgrade'), colors.brand),
        greaterThanOrEqualTo(4.5),
      );

      // Icons: chevrons, the restore mark and the dismiss cross.
      for (final icon in [
        Icons.chevron_right_outlined,
        Icons.restore_rounded,
        Icons.logout,
      ]) {
        final glyph = tester.widget<Icon>(_inDrawer(find.byIcon(icon)).first);
        expect(
          _contrast(glyph.color!, paper),
          greaterThanOrEqualTo(3),
          reason: '$icon',
        );
      }
      final cross = tester.widget<IconButton>(
        find.ancestor(
          of: find.byIcon(Icons.close_rounded),
          matching: find.byType(IconButton),
        ),
      );
      expect(_contrast(cross.color!, colors.surface), greaterThanOrEqualTo(3));
    });

    testWidgets('$name: delete-account dialog ink clears AA', (tester) async {
      await tester.pumpWidget(
        _app(
          theme: theme,
          child: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDeleteAccountDialog(context),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      final card = colors.surfaceElevated;
      Color ink(String text) =>
          tester.widget<Text>(find.text(text)).style!.color!;

      expect(
        _contrast(ink('Delete account?'), card),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        _contrast(
          tester
              .widget<Text>(find.textContaining('cannot be undone'))
              .style!
              .color!,
          card,
        ),
        greaterThanOrEqualTo(4.5),
      );
      final confirmPaper = Color.alphaBlend(
        colors.danger.withValues(alpha: 0.05),
        card,
      );
      expect(
        _contrast(ink('I understand the consequences'), confirmPaper),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        _contrast(ink('Cancel'), colors.surface),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        _contrast(ink('Delete'), colors.danger),
        greaterThanOrEqualTo(4.5),
      );

      // The empty checkbox edge is a UI boundary: 3:1.
      final box =
          tester
                  .widget<DecoratedBox>(
                    find
                        .descendant(
                          of: find.ancestor(
                            of: find.text('I understand the consequences'),
                            matching: find.byType(Row),
                          ),
                          matching: find.byType(DecoratedBox),
                        )
                        .first,
                  )
                  .decoration
              as BoxDecoration;
      expect(
        _contrast(box.border!.top.color, confirmPaper),
        greaterThanOrEqualTo(3),
      );

      // Confirming arms Delete; the check sits on the solid danger fill.
      await tester.tap(find.text('I understand the consequences'));
      await tester.pumpAndSettle();
      final check = tester.widget<Icon>(find.byIcon(Icons.check_rounded));
      expect(_contrast(check.color!, colors.danger), greaterThanOrEqualTo(4.5));
      final delete = tester.widget<TextButton>(
        find.ancestor(
          of: find.text('Delete'),
          matching: find.byType(TextButton),
        ),
      );
      expect(delete.onPressed, isNotNull);
    });
  }
}
