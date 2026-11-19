import 'package:chessever2/screens/inbox/inbox_provider.dart';
import 'package:chessever2/chat/botvinnik_chat_button.dart';
import 'package:chessever2/chat/botvinnik_icon.dart';
import 'package:chessever2/chat/botvinnik_provider.dart';
import 'package:chessever2/chat/chat_api.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/glass_surface.dart';
import 'package:chessever2/widgets/ink_fab.dart';
import 'package:chessever2/widgets/press_spring.dart';
import 'package:chessever2/widgets/search_mode/search_count_badge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class _FixedEnabled extends BotvinnikEnabledNotifier {
  _FixedEnabled(this.value);

  final bool value;

  @override
  Future<bool> build() async => value;
}

void main() {
  setUp(() {
    // The 393pt design phone, so `52.ic` is exactly 52dp.
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.physicalSize = const Size(393 * 3, 852 * 3);
    view.devicePixelRatio = 3;
  });

  tearDown(() {
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.resetPhysicalSize();
    view.resetDevicePixelRatio();
  });

  Widget host({
    required ThemeData theme,
    VoidCallback? onPressed,
    bool enabled = true,
    int unreadCount = 0,
    bool reduceMotion = false,
    Animation<double>? fade,
    InkFabSize size = InkFabSize.regular,
  }) {
    Widget button = BotvinnikChatButton(
      screenContext: const ChatScreenContext(screen: 'test'),
      size: size,
      onPressed: onPressed,
    );
    if (fade != null) button = GlassFade(opacity: fade, child: button);
    return ProviderScope(
      overrides: [
        inboxUnreadCountProvider.overrideWithValue(unreadCount),
        botvinnikEnabledProvider.overrideWith(() => _FixedEnabled(enabled)),
      ],
      child: MaterialApp(
        theme: theme,
        home: Builder(
          builder: (context) {
            ResponsiveHelper.init(context);
            return MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(disableAnimations: reduceMotion),
              child: Scaffold(
                body: const SizedBox.expand(),
                floatingActionButton: button,
              ),
            );
          },
        ),
      ),
    );
  }

  testWidgets(
    'unread count wears the one count badge and announces exact total',
    (tester) async {
      final semantics = tester.ensureSemantics();
      for (final count in [1, 12, 105, 0]) {
        await tester.pumpWidget(
          host(theme: AppTheme.darkTheme, unreadCount: count),
        );
        await tester.pumpAndSettle();
        final badge = find.byKey(const ValueKey('botvinnik-unread-badge'));
        expect(badge, count == 0 ? findsNothing : findsOneWidget);
        if (count > 0) {
          // The one count style: a single digit, else "9+" (the exact
          // total is read aloud).
          expect(find.text(count > 9 ? '9+' : '$count'), findsOneWidget);
          expect(
            find.bySemanticsLabel(
              'Ask Botvinnik, $count unread Inbox messages',
            ),
            findsOneWidget,
          );
          expect(
            find.descendant(
              of: find.byType(BotvinnikChatButton),
              matching: find.byType(SearchCountBadge),
            ),
            findsOneWidget,
          );
        }
      }
      semantics.dispose();
    },
  );

  testWidgets('the unread count steps back with the glass, never alone', (
    tester,
  ) async {
    // As a sibling of the search button in a floating stack: the stack
    // fades its buttons as glass while the search opens.
    final fade = ValueNotifier<double>(1);
    addTearDown(fade.dispose);
    final opacity = _Notified(fade);
    await tester.pumpWidget(
      host(theme: AppTheme.darkTheme, unreadCount: 3, fade: opacity),
    );
    await tester.pumpAndSettle();
    final badge = find.byKey(const ValueKey('botvinnik-unread-badge'));
    double badgeOpacity() => tester
        .widget<FadeTransition>(
          find.ancestor(of: badge, matching: find.byType(FadeTransition)).first,
        )
        .opacity
        .value;
    expect(badgeOpacity(), 1);

    fade.value = 0.4;
    await tester.pump();
    // The badge and the glass at the same strength.
    expect(badgeOpacity(), 0.4);
    expect(
      GlassFade.maybeOf(tester.element(find.byType(GlassSurface)))!.value,
      0.4,
    );

    // The app's one count: the brand's tonal accent, not a red of its own.
    final coin =
        tester
                .widget<Container>(
                  find.descendant(of: badge, matching: find.byType(Container)),
                )
                .decoration!
            as BoxDecoration;
    expect(coin.color, tester.element(badge).colors.accentText);
  });

  for (final (name, theme) in [
    ('dark', AppTheme.darkTheme),
    ('light', AppTheme.lightTheme),
  ]) {
    group('$name theme', () {
      testWidgets('renders the trimmed mark on the regular floating disc', (
        tester,
      ) async {
        await tester.pumpWidget(host(theme: theme));
        await tester.pumpAndSettle();

        final launcher = find.byType(BotvinnikChatButton);
        expect(launcher, findsOneWidget);
        // The same disc as the search it shares a stack with.
        final disc = InkFabSize.regular.disc;
        expect(disc, 52);
        expect(tester.getSize(launcher), Size.square(InkFabSize.regular.side));

        final mark = find.byType(BotvinnikMark);
        expect(mark, findsOneWidget);
        // The king fills ~70% of the launcher's height.
        final markSide = tester.getSize(mark).height;
        expect(
          markSide * BotvinnikMark.artworkHeightFactor / disc,
          closeTo(0.70, 0.02),
        );
        // Drawn from the trimmed PNG, not the tinted SVG.
        final image = tester.widget<Image>(
          find.descendant(of: mark, matching: find.byType(Image)),
        );
        expect(image.color, isNull);
        expect(image.colorBlendMode, isNull);
        expect(find.byType(BotvinnikIcon), findsNothing);
      });

      testWidgets('announces itself as the Ask Botvinnik button', (
        tester,
      ) async {
        final semantics = tester.ensureSemantics();
        await tester.pumpWidget(host(theme: theme, onPressed: () {}));
        await tester.pumpAndSettle();

        final node = find.bySemanticsLabel(BotvinnikChatButton.label);
        expect(node, findsOneWidget);
        expect(
          tester.getSemantics(node),
          matchesSemantics(
            label: BotvinnikChatButton.label,
            isButton: true,
            hasTapAction: true,
            isFocusable: true,
            hasFocusAction: true,
          ),
        );
        expect(find.byTooltip(BotvinnikChatButton.label), findsOneWidget);
        semantics.dispose();
      });

      testWidgets('a tap runs the launcher action once', (tester) async {
        var opened = 0;
        await tester.pumpWidget(host(theme: theme, onPressed: () => opened++));
        await tester.pumpAndSettle();

        await tester.tap(find.byType(BotvinnikChatButton));
        await tester.pumpAndSettle();
        expect(opened, 1);
      });
    });
  }

  testWidgets('small sits above the main button at the small disc', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(theme: AppTheme.darkTheme, size: InkFabSize.small),
    );
    await tester.pumpAndSettle();
    expect(InkFabSize.small.disc, 44);
    expect(
      tester.getSize(find.byType(BotvinnikChatButton)),
      Size.square(InkFabSize.small.side),
    );
    expect(tester.getSize(find.byType(GlassSurface)), const Size.square(44));
    expect(
      tester.getRect(find.byType(BotvinnikMark)).height,
      closeTo(44 * 0.73, 1e-6),
    );
  });

  testWidgets('presses like every floating button and settles to identity', (
    tester,
  ) async {
    await tester.pumpWidget(host(theme: AppTheme.darkTheme, onPressed: () {}));
    await tester.pumpAndSettle();

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(BotvinnikChatButton)),
    );
    await tester.pumpAndSettle();
    // getRect applies the press transform; getSize would not.
    final pressed = tester.getRect(find.byType(BotvinnikMark)).height;
    await gesture.up();
    await tester.pumpAndSettle();
    final rest = tester.getRect(find.byType(BotvinnikMark)).height;

    expect(pressed, lessThan(rest));
    // [PressSpring] at 0.9, the floating buttons' press.
    expect(pressed / rest, closeTo(0.9, 0.005));
    expect(rest, closeTo(52 * 0.73, 1e-6));
    expect(
      find.descendant(
        of: find.byType(BotvinnikChatButton),
        matching: find.byType(PressSpring),
      ),
      findsOneWidget,
    );
  });

  testWidgets('arrives at rest with its page: no entrance, no hero', (
    tester,
  ) async {
    await tester.pumpWidget(host(theme: AppTheme.darkTheme));
    await tester.pump();

    final launcher = find.byType(BotvinnikChatButton);
    final mark = find.byType(BotvinnikMark);
    expect(mark, findsOneWidget);
    // At rest on its very first frame.
    expect(tester.getRect(mark).height, closeTo(52 * 0.73, 1e-6));
    for (final fader in [Opacity, FadeTransition, AnimatedOpacity]) {
      expect(
        find.descendant(of: launcher, matching: find.byType(fader)),
        findsNothing,
        reason: 'the launcher must never gate visibility on $fader',
      );
    }
    // Nothing matched its hero; it no longer flies between routes.
    expect(
      find.descendant(of: launcher, matching: find.byType(Hero)),
      findsNothing,
    );
  });

  testWidgets('hidden when the user turned Botvinnik off', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(host(theme: AppTheme.darkTheme, enabled: false));
    await tester.pumpAndSettle();

    expect(find.byType(BotvinnikMark), findsNothing);
    expect(find.bySemanticsLabel(BotvinnikChatButton.label), findsNothing);
    semantics.dispose();
  });

  testWidgets('reduced motion keeps the press still', (tester) async {
    await tester.pumpWidget(
      host(theme: AppTheme.darkTheme, reduceMotion: true, onPressed: () {}),
    );
    await tester.pump();
    final rest = tester.getRect(find.byType(BotvinnikMark)).height;
    expect(rest, closeTo(52 * 0.73, 1e-6));

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(BotvinnikChatButton)),
    );
    await tester.pump();
    expect(tester.getRect(find.byType(BotvinnikMark)).height, rest);
    await gesture.up();
    await tester.pump(PressSpring.minHold);
  });
}

/// A [ValueNotifier] read as an animation.
class _Notified extends Animation<double>
    with AnimationLocalListenersMixin, AnimationLocalStatusListenersMixin {
  _Notified(this._source) {
    _source.addListener(notifyListeners);
  }

  final ValueNotifier<double> _source;

  @override
  double get value => _source.value;

  @override
  AnimationStatus get status => AnimationStatus.forward;

  @override
  void didRegisterListener() {}

  @override
  void didUnregisterListener() {}
}
