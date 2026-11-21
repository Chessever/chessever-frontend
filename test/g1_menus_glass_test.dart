// G1 (focus menu + popup menus): every menu surface is the popups' frosted
// glass ([PopupGlass]); nothing blurs the whole screen on any frame of an
// open or a close; glass is never under an opacity (it would lose its
// frost); and the shared glass menu behaves as the Material menu it
// replaces.
import 'package:chessever2/screens/chessboard/video/video_session.dart';
import 'package:chessever2/screens/chessboard/video/video_stream.dart';
import 'package:chessever2/screens/chessboard/video/video_widgets.dart';
import 'package:chessever2/screens/chessboard/widgets/like_tag_chip.dart';
import 'package:chessever2/screens/chessboard/widgets/like_tag_offer.dart';
import 'package:chessever2/screens/for_you/discovery/models/discovery_models.dart';
import 'package:chessever2/screens/for_you/discovery/reports_share.dart';
import 'package:chessever2/screens/for_you/discovery/widgets/most_liked_controls.dart';
import 'package:chessever2/screens/library/miniatures/miniatures_mode_provider.dart';
import 'package:chessever2/screens/library/miniatures/miniatures_share.dart';
import 'package:chessever2/screens/library/widgets/library_context_menu.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/tablet_safe_menu.dart';
import 'package:chessever2/widgets/glass_surface.dart';
import 'package:chessever2/widgets/popover_add_fab.dart';
import 'package:chessever2/widgets/popup_glass.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

const _phone = Size(393, 852);
const _tablet = Size(834, 1194);
const _open = ValueKey('g1_open');
const _card = ValueKey('g1_card');

void _useView(WidgetTester tester, [Size size = _phone]) {
  tester.view.devicePixelRatio = 3;
  tester.view.physicalSize = size * 3;
  addTearDown(tester.view.reset);
}

/// Whether anything between [finder]'s render object and the root fades it.
bool _underOpacity(WidgetTester tester, Finder finder) {
  RenderObject? node = tester.renderObject(finder).parent;
  while (node != null) {
    if (node is RenderOpacity && node.opacity < 1) return true;
    if (node is RenderAnimatedOpacity && node.opacity.value < 1) return true;
    node = node.parent;
  }
  return false;
}

/// One frame's checks: no backdrop filter covers the screen; every glass
/// panel on screen is at full strength (never under an opacity) and has
/// exactly one backdrop filter, clipped to it, or shares the one of the
/// cluster it sits in ([PopupGlassCluster]), clipped to that.
void _expectGlassFrame(WidgetTester tester, Size screen, String when) {
  for (final element in find.byType(BackdropFilter).evaluate()) {
    final size = (element.renderObject! as RenderBox).size;
    expect(
      size.width < screen.width || size.height < screen.height,
      isTrue,
      reason: '$when: a backdrop filter covers the screen ($size)',
    );
  }
  for (final element in find.byType(PopupGlass).evaluate()) {
    final glass = find.byElementPredicate((e) => identical(e, element));
    expect(_underOpacity(tester, glass), isFalse, reason: '$when: faded');
    final cluster = find.ancestor(
      of: glass,
      matching: find.byType(PopupGlassCluster),
    );
    final owner = cluster.evaluate().isEmpty ? glass : cluster;
    final filters = find.descendant(
      of: owner,
      matching: find.byType(BackdropFilter),
    );
    expect(filters, findsOneWidget, reason: when);
    final panel = tester.getRect(owner);
    final filter = tester.getRect(filters);
    expect(filter.width, lessThanOrEqualTo(panel.width + 0.01));
    expect(filter.height, lessThanOrEqualTo(panel.height + 0.01));
  }
}

/// Every backdrop filter on screen belongs to a glass panel, or to a
/// floating glass button ([GlassSurface]) of the page itself.
void _expectOnlyGlassBlurs(WidgetTester tester) {
  for (final element in find.byType(BackdropFilter).evaluate()) {
    final self = find.byElementPredicate((e) => identical(e, element));
    final owned =
        find
            .ancestor(of: self, matching: find.byType(PopupGlass))
            .evaluate()
            .isNotEmpty ||
        find
            .ancestor(of: self, matching: find.byType(GlassSurface))
            .evaluate()
            .isNotEmpty;
    expect(owned, isTrue, reason: 'a backdrop filter outside the glass');
  }
}

/// Pumps 16 ms frames until none is scheduled, checking each frame.
Future<int> _checkFrames(
  WidgetTester tester,
  Size screen,
  String when, {
  bool Function()? done,
}) async {
  var frames = 0;
  while (tester.binding.hasScheduledFrame &&
      frames < 240 &&
      !(done?.call() ?? false)) {
    _expectGlassFrame(tester, screen, '$when frame $frames');
    await tester.pump(const Duration(milliseconds: 16));
    frames++;
  }
  _expectGlassFrame(tester, screen, '$when at rest');
  return frames;
}

Future<void> _pumpHost(
  WidgetTester tester,
  void Function(BuildContext context) opener, {
  bool light = false,
  Size size = _phone,
  Widget? body,
}) async {
  _useView(tester, size);
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        theme: light ? AppTheme.lightTheme : AppTheme.darkTheme,
        home: Builder(
          builder: (context) {
            ResponsiveHelper.init(context);
            return Scaffold(
              body: Stack(
                children: [
                  ?body,
                  Positioned(
                    left: 24,
                    top: 120,
                    child: Builder(
                      builder: (context) => TextButton(
                        key: _open,
                        onPressed: () => opener(context),
                        child: const Text('open'),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    ),
  );
}

void _press(WidgetTester tester) =>
    tester.widget<TextButton>(find.byKey(_open)).onPressed!();

List<PopupMenuEntry<String>> _items() => const [
  PopupMenuItem(value: 'share', child: Text('Share')),
  PopupMenuItem(value: 'copy', child: Text('Copy link')),
  PopupMenuDivider(),
  PopupMenuItem(value: 'off', enabled: false, child: Text('Unavailable')),
];

RelativeRect _at(WidgetTester tester, Offset point) {
  final overlay = tester.renderObject<RenderBox>(find.byType(Overlay).first);
  return RelativeRect.fromRect(
    point & const Size(48, 40),
    Offset.zero & overlay.size,
  );
}

void main() {
  group('the glass popup menu', () {
    testWidgets('lays its items out exactly where showMenu did', (
      tester,
    ) async {
      final rects = <String, List<Rect>>{};
      Future<void> run(
        Future<String?> Function(BuildContext, RelativeRect) show,
      ) async {
        await _pumpHost(tester, (context) {
          show(context, _at(tester, const Offset(300, 200)));
        });
        _press(tester);
        await tester.pumpAndSettle();
        for (final label in ['Share', 'Copy link', 'Unavailable']) {
          (rects[label] ??= []).add(tester.getRect(find.text(label)));
        }
        await tester.tapAt(const Offset(8, 800));
        await tester.pumpAndSettle();
        expect(find.text('Share'), findsNothing);
      }

      await run(
        (context, position) => showMenu<String>(
          context: context,
          position: position,
          items: _items(),
        ),
      );
      await run(
        (context, position) => showTabletSafeMenu<String>(
          context: context,
          position: position,
          items: _items(),
        ),
      );
      for (final MapEntry(key: label, value: pair) in rects.entries) {
        expect(pair.last, pair.first, reason: label);
      }
    });

    for (final light in [false, true]) {
      testWidgets('every frame of the open and close is glass at full '
          'strength over a plain dim (${light ? 'light' : 'dark'})', (
        tester,
      ) async {
        String? result = 'unset';
        await _pumpHost(tester, light: light, (context) async {
          result = await showTabletSafeMenu<String>(
            context: context,
            position: _at(tester, const Offset(300, 200)),
            items: _items(),
          );
        });
        _press(tester);
        await tester.pump();
        // On screen, readable, from the first frame.
        expect(find.text('Share'), findsOneWidget);
        expect(find.byType(PopupGlass), findsOneWidget);
        final frames = await _checkFrames(tester, _phone, 'open');
        expect(frames, greaterThan(0));
        expect(find.byType(BackdropFilter), findsOneWidget);

        // The dim is the anchored menus' plain tint, painted by the route
        // (the barrier only takes the tap).
        final context = tester.element(find.text('Share'));
        final barrier = tester.widget<ModalBarrier>(
          find.byType(ModalBarrier).last,
        );
        expect(barrier.color, anyOf(isNull, const Color(0x00000000)));
        final dim = tester
            .widgetList<CustomPaint>(find.byType(CustomPaint))
            .map((paint) => paint.painter)
            .whereType<GlassScrimPainter>()
            .single;
        expect(dim.color, AnchoredGlassDim.colorOf(context));
        expect(
          dim.color.a,
          closeTo(light ? AnchoredGlassDim.light : AnchoredGlassDim.dark, 0.001),
        );
        // The glass averages to the menu theme's tone, or to the app's own
        // neutral surface (never the scheme's blue-slate surfaceContainer),
        // solved over the page the anchored dim leaves.
        final glass = tester.widget<PopupGlass>(find.byType(PopupGlass));
        expect(
          glass.tone,
          Theme.of(context).popupMenuTheme.color ?? context.colors.surface,
        );
        expect(glass.tone, isNot(Theme.of(context).colorScheme.surfaceContainer));
        expect(glass.page, AnchoredGlassDim.pageOf(context));

        await tester.tapAt(const Offset(8, 800));
        await tester.pump();
        await _checkFrames(tester, _phone, 'close');
        expect(find.byType(PopupGlass), findsNothing);
        expect(result, isNull);
      });
    }

    testWidgets('a picked item resolves with its value; a disabled one '
        'does nothing', (tester) async {
      String? result;
      await _pumpHost(tester, (context) async {
        result = await showTabletSafeMenu<String>(
          context: context,
          position: _at(tester, const Offset(40, 300)),
          items: _items(),
        );
      });
      _press(tester);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Unavailable'));
      await tester.pumpAndSettle();
      expect(find.text('Share'), findsOneWidget);
      await tester.tap(find.text('Copy link'));
      await tester.pumpAndSettle();
      expect(result, 'copy');
      expect(find.byType(PopupGlass), findsNothing);
    });

    testWidgets('tablet: taps around a fresh menu are ignored for the '
        'guard, then close it; the tablet flag is up meanwhile', (
      tester,
    ) async {
      var done = false;
      await _pumpHost(tester, size: _tablet, (context) async {
        await showTabletSafeMenu<String>(
          context: context,
          position: _at(tester, const Offset(300, 200)),
          items: _items(),
        );
        done = true;
      });
      expect(ResponsiveHelper.isTablet, isTrue);
      _press(tester);
      await tester.pump();
      expect(TabletPopupState.isAnyPopupOpen, isTrue);
      // The phantom tap, some 350ms after the open: swallowed.
      await tester.pump(const Duration(milliseconds: 350));
      await tester.tapAt(const Offset(8, 900));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Share'), findsOneWidget);
      await tester.pump(kTabletMenuDismissGuard);
      await tester.tapAt(const Offset(8, 900));
      await tester.pumpAndSettle();
      expect(find.text('Share'), findsNothing);
      expect(done, isTrue);
      expect(TabletPopupState.isAnyPopupOpen, isFalse);
    });

    testWidgets('GlassPopupMenuButton opens the glass menu and reports '
        'like PopupMenuButton', (tester) async {
      final picked = <String>[];
      var opened = 0;
      var canceled = 0;
      _useView(tester);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Builder(
            builder: (context) {
              ResponsiveHelper.init(context);
              return Scaffold(
                appBar: AppBar(
                  actions: [
                    GlassPopupMenuButton<String>(
                      key: const ValueKey('g1_button'),
                      tooltip: 'Add source',
                      icon: const Icon(Icons.add_rounded),
                      onOpened: () => opened++,
                      onCanceled: () => canceled++,
                      onSelected: picked.add,
                      itemBuilder: (_) => _items(),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      );
      expect(find.byTooltip('Add source'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('g1_button')));
      await tester.pumpAndSettle();
      expect(opened, 1);
      expect(find.byType(PopupGlass), findsOneWidget);
      // Grows from the button: the menu covers it at the top right.
      final button = tester.getRect(find.byKey(const ValueKey('g1_button')));
      final menu = tester.getRect(find.byType(PopupGlass));
      expect(menu.right, closeTo(_phone.width - 8, 0.5));
      expect(menu.top, lessThanOrEqualTo(button.bottom));
      await tester.tap(find.text('Share'));
      await tester.pumpAndSettle();
      expect(picked, ['share']);
      await tester.tap(find.byKey(const ValueKey('g1_button')));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(8, 800));
      await tester.pumpAndSettle();
      expect(canceled, 1);
    });
  });

  group('the sites on the glass menu', () {
    final sites = <String, void Function(BuildContext)>{
      'Reports share': (context) => showReportsShareMenu(context, null),
      'Most liked share': (context) => showMostLikedShareMenu(
        context,
        period: MostLikedPeriod.week,
        view: MostLikedView.games,
      ),
      'Miniatures share': (context) =>
          showMiniaturesShareMenu(context, MiniaturesScreenMode.games),
    };
    for (final MapEntry(key: name, value: opener) in sites.entries) {
      testWidgets('$name opens on glass', (tester) async {
        await _pumpHost(tester, opener);
        _press(tester);
        await tester.pump();
        expect(find.text('Share'), findsOneWidget);
        await _checkFrames(tester, _phone, name);
        expect(find.byType(PopupGlass), findsOneWidget);
        _expectOnlyGlassBlurs(tester);
        await tester.tapAt(const Offset(8, 800));
        await tester.pumpAndSettle();
        expect(find.text('Share'), findsNothing);
      });
    }

    testWidgets('a stream chip holds into Follow author on glass', (
      tester,
    ) async {
      _useView(tester);
      final session = EventVideoSession(repository: null);
      addTearDown(session.dispose);
      session.streams = EventVideoStream.readList([
        {
          'id': 'analysis-1',
          'label': 'Analysis · English',
          'kind': 'analysis',
          'authorId': 'author-1',
          'authorName': 'Coach',
          'countryCode': 'GB',
          'url': 'https://www.youtube.com/watch?v=abcdefghijk',
          'provider': 'youtube',
          'sourceId': 'abcdefghijk',
          'publication': {'language': 'en', 'title': 'Analysis'},
        },
      ]);
      expect(session.streams, hasLength(1));
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.darkTheme,
            home: Builder(
              builder: (context) {
                ResponsiveHelper.init(context);
                return EventVideoScope(
                  session: session,
                  player: null,
                  child: const Scaffold(body: EventVideoFlags()),
                );
              },
            ),
          ),
        ),
      );
      await tester.longPress(
        find.byKey(const ValueKey('video_stream_analysis-1')),
      );
      await tester.pump();
      expect(find.text('Follow author'), findsOneWidget);
      await _checkFrames(tester, _phone, 'follow');
      expect(find.byType(PopupGlass), findsOneWidget);
      await tester.tapAt(const Offset(8, 800));
      await tester.pumpAndSettle();
      expect(find.text('Follow author'), findsNothing);
    });
  });

  group('the focus menu', () {
    for (final light in [false, true]) {
      testWidgets('every frame of the open and close: panels of glass at '
          'full strength on one shared blur (${light ? 'light' : 'dark'})', (
        tester,
      ) async {
        await _pumpHost(
          tester,
          light: light,
          (_) {},
          body: Positioned(
            left: 16,
            top: 300,
            width: 361,
            height: 120,
            child: Builder(
              builder: (cardContext) => GestureDetector(
                onLongPress: () => showLibraryContextMenu(
                  context: cardContext,
                  previewBuilder: (_) =>
                      const ColoredBox(color: Color(0xFF2F5D50)),
                  actions: [
                    for (final label in ['Share', 'Copy link'])
                      LibraryMenuAction(
                        icon: Icons.ios_share_rounded,
                        label: label,
                        prominent: true,
                        onSelected: () {},
                      ),
                    LibraryMenuAction(
                      icon: Icons.copy_rounded,
                      label: 'Copy PGN',
                      onSelected: () {},
                    ),
                    LibraryMenuAction(
                      icon: Icons.delete_outline_rounded,
                      label: 'Remove',
                      destructive: true,
                      onSelected: () {},
                    ),
                  ],
                ),
                child: const ColoredBox(key: _card, color: Color(0xFF2F5D50)),
              ),
            ),
          ),
        );
        await tester.longPress(find.byKey(_card));
        await tester.pump();
        expect(find.text('Copy PGN'), findsOneWidget);
        await _checkFrames(tester, _phone, 'open');
        // Two quick tiles, the list and the destructive group: four panels
        // on one frost, the block's single backdrop filter (the page is read
        // once, and the gutters between the panels are frosted too).
        expect(find.byType(PopupGlass), findsNWidgets(4));
        expect(find.byType(BackdropFilter), findsOneWidget);
        expect(
          find.ancestor(
            of: find.byType(BackdropFilter),
            matching: find.byType(PopupGlassCluster),
          ),
          findsOneWidget,
        );
        final veil = tester.widget<ColoredBox>(find.byKey(kFocusMenuVeilKey));
        final context = tester.element(find.byKey(kFocusMenuVeilKey));
        expect(
          veil.color,
          context.colors.scrim.withValues(
            alpha: PopupGlassStyle.of(context).scrim,
          ),
        );
        for (final glass in tester.widgetList<PopupGlass>(
          find.byType(PopupGlass),
        )) {
          expect(glass.tone, context.colors.surface);
        }

        await tester.tapAt(const Offset(200, 820));
        await tester.pump();
        await _checkFrames(tester, _phone, 'close');
        expect(find.byType(PopupGlass), findsNothing);
        expect(find.byKey(kFocusMenuVeilKey), findsNothing);
      });
    }
  });

  testWidgets('a card half past the screen bottom lifts whole: the copy '
      'is never sliced where the edge was', (tester) async {
    _useView(tester);
    const card = Color(0xFFE08A1E);
    const copy = Color(0xFF2E8B7A);
    const capture = ValueKey('g1_capture');
    await tester.pumpWidget(
      RepaintBoundary(
        key: capture,
        child: MaterialApp(
          theme: AppTheme.darkTheme,
          home: Builder(
            builder: (context) {
              ResponsiveHelper.init(context);
              return Scaffold(
                body: ListView(
                  children: [
                    const SizedBox(height: 600),
                    Container(key: _card, height: 420, color: card),
                    const SizedBox(height: 400),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
    showLibraryContextMenu(
      context: tester.element(find.byKey(_card)),
      actions: [
        for (var i = 0; i < 3; i++)
          LibraryMenuAction(
            icon: Icons.copy_rounded,
            label: 'Action $i',
            onSelected: () {},
          ),
      ],
      previewBuilder: (_) =>
          const SizedBox(height: 420, child: ColoredBox(color: copy)),
    );
    await tester.pumpAndSettle();
    final lifted = find.byWidgetPredicate(
      (widget) => widget is ColoredBox && widget.color == copy,
    );
    final rect = tester.getRect(lifted);
    // Moved up into view, whole.
    expect(rect.bottom, lessThan(_phone.height));
    final probe = Offset(rect.center.dx, rect.bottom - 6);
    late Color seen;
    await tester.runAsync(() async {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(capture),
      );
      final image = await boundary.toImage();
      final data = (await image.toByteData())!;
      final i = (probe.dy.floor() * image.width + probe.dx.floor()) * 4;
      seen = Color.fromARGB(
        255,
        data.getUint8(i),
        data.getUint8(i + 1),
        data.getUint8(i + 2),
      );
      image.dispose();
    });
    expect(seen, copy, reason: 'the copy is cut above its bottom edge');
  });

  group('the popover', () {
    for (final light in [false, true]) {
      testWidgets('opens and folds away on glass, never faded '
          '(${light ? 'light' : 'dark'})', (tester) async {
        _useView(tester);
        final semantics = tester.ensureSemantics();
        int? picked;
        await tester.pumpWidget(
          MaterialApp(
            theme: light ? AppTheme.lightTheme : AppTheme.darkTheme,
            home: Builder(
              builder: (context) {
                ResponsiveHelper.init(context);
                return Scaffold(
                  body: const SizedBox.expand(),
                  floatingActionButton: PopoverAddFab<int>(
                    label: 'Add to My Space',
                    choices: const [
                      PopoverAddChoice(
                        leading: Icon(Icons.storage_rounded),
                        label: 'Database',
                        value: 1,
                      ),
                      PopoverAddChoice(
                        leading: Icon(Icons.auto_awesome_rounded),
                        label: 'Smart event',
                        value: 2,
                      ),
                    ],
                    onPicked: (value) => picked = value,
                  ),
                );
              },
            ),
          ),
        );
        await tester.tap(find.byType(PopoverAddFab<int>));
        await tester.pump();
        expect(find.text('Database'), findsOneWidget);
        await _checkFrames(tester, _phone, 'open');
        expect(find.byType(PopupGlass), findsOneWidget);
        _expectOnlyGlassBlurs(tester);
        final context = tester.element(find.text('Database'));
        expect(
          tester.widget<PopupGlass>(find.byType(PopupGlass)).tone,
          light ? context.colors.popup : context.colors.surface,
        );
        // The dim leaves the button (now the popover's close) lit.
        final dim = tester
            .widgetList<CustomPaint>(find.byType(CustomPaint))
            .map((paint) => paint.painter)
            .whereType<GlassScrimPainter>()
            .single;
        expect(dim.color, AnchoredGlassDim.colorOf(context));
        expect(
          dim.hole!.outerRect.contains(
            tester.getCenter(find.byType(PopoverAddFab<int>)),
          ),
          isTrue,
        );
        // The button's semantics say it is open (the popover is named
        // after it too: the button is the first).
        expect(
          tester.getSemantics(find.bySemanticsLabel('Add to My Space').first),
          isSemantics(isExpanded: true, hasExpandedState: true),
        );

        await tester.tap(find.text('Smart event'));
        await tester.pump();
        await _checkFrames(tester, _phone, 'close');
        expect(find.byType(PopupGlass), findsNothing);
        expect(picked, 2);
        semantics.dispose();
      });
    }
  });

  group('the tag picker', () {
    for (final light in [false, true]) {
      testWidgets('drops on glass over a plain dim '
          '(${light ? 'light' : 'dark'})', (tester) async {
        _useView(tester);
        final offers = TagChipOfferController()..open('game', const []);
        addTearDown(offers.dispose);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [tagChipOfferProvider.overrideWithValue(offers)],
            child: MaterialApp(
              theme: light ? AppTheme.lightTheme : AppTheme.darkTheme,
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
                              : LikeTagChip(
                                  key: ValueKey(offer.token),
                                  offer: offer,
                                ),
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
        await tester.pump(const Duration(milliseconds: 600));
        await tester.tap(find.byType(LikeTagChip));
        await tester.pump();
        expect(find.text('Save'), findsOneWidget);
        await _checkFrames(tester, _phone, 'open');
        final glass = find.byType(PopupGlass);
        expect(glass, findsOneWidget);
        final context = tester.element(find.text('Save'));
        expect(
          tester.widget<PopupGlass>(glass).tone,
          context.colors.surfaceElevated,
        );
        expect(find.byType(BackdropFilter), findsOneWidget);
        // The dim under it rides the menu's spring, a plain tint that
        // leaves the chip that opened it lit.
        final dim = tester
            .widgetList<CustomPaint>(find.byType(CustomPaint))
            .map((paint) => paint.painter)
            .whereType<GlassScrimPainter>()
            .single;
        expect(dim.color, AnchoredGlassDim.colorOf(context));
        expect(
          dim.hole!.outerRect.contains(
            tester.getCenter(find.byType(LikeTagChip)),
          ),
          isTrue,
        );

        await tester.tapAt(const Offset(8, 800));
        await tester.pump();
        await _checkFrames(
          tester,
          _phone,
          'close',
          done: () => find.byType(PopupGlass).evaluate().isEmpty,
        );
        expect(find.byType(PopupGlass), findsNothing);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 1));
      });
    }
  });
}
