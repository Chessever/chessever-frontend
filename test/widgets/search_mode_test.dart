import 'dart:async';

import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/glass_surface.dart';
import 'package:chessever2/widgets/home_top_bar.dart';
import 'package:chessever2/widgets/ink_fab.dart';
import 'package:chessever2/widgets/live_first_capsule.dart';
import 'package:chessever2/widgets/live_glyph.dart';
import 'package:chessever2/widgets/quick_list_toggles.dart';
import 'package:chessever2/widgets/scroll_chrome.dart';
import 'package:chessever2/widgets/search_mode/search_mode.dart';
import 'package:chessever2/widgets/simple_search_bar.dart';
import 'package:chessever2/widgets/svg_widget.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// The search mode every Games tab runs on: one spring timeline, the search
/// button's own glass flying into the field and back.

const _fabKey = ValueKey('fab');
const _liveKey = ValueKey('live');
const _closeKey = ValueKey('close');
const _backKey = ValueKey('page_back');
const _offscreenKey = ValueKey('offscreen_fab');
const _headerFiltersKey = ValueKey('header_filters');
const _searchFiltersKey = ValueKey('search_filters');
const _searchOnlyKey = ValueKey('search_only_toggle');

/// A page shaped like every Games tab: a 100pt header (back row, gap, tabs)
/// over a long list in a two-page PageView, floating Live first and search.
class _Page extends StatefulWidget {
  const _Page({
    required this.search,
    this.onQuery,
    this.onChrome,
    this.offscreenButton,
    this.headerBack = true,
    this.filters = false,
  });

  final SearchModeController search;

  /// The page's header has its way back (a [PageBackButton]) where the
  /// search header's chevron is.
  final bool headerBack;

  /// Filters in both headers at the same spot (shared), and a toggle only
  /// the search header draws.
  final bool filters;
  final ValueChanged<String>? onQuery;
  final ValueChanged<ScrollChromeController>? onChrome;

  /// While true, a second search button is laid out off to the side of the
  /// page (a tab kept alive beside the one in view).
  final ValueListenable<bool>? offscreenButton;

  @override
  State<_Page> createState() => _PageState();
}

class _PageState extends State<_Page> with SingleTickerProviderStateMixin {
  late final ScrollChromeController _chrome = ScrollChromeController(
    vsync: this,
  );

  @override
  void initState() {
    super.initState();
    widget.onChrome?.call(_chrome);
  }

  @override
  void dispose() {
    _chrome.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SearchModeHost(
      controller: widget.search,
      chrome: _chrome,
      debounce: const Duration(milliseconds: 200),
      onQuery: widget.onQuery,
      child: Scaffold(
        floatingActionButton: SlidingFabs(
          controller: _chrome,
          child: InkFabStack(
            children: [
              LiveFirstCapsule(
                key: _liveKey,
                on: false,
                liveCount: 3,
                onTap: () {},
              ),
              const SearchInkFab(key: _fabKey, label: 'Search games'),
            ],
          ),
        ),
        body: Column(
          children: [
            SizedBox(height: MediaQuery.viewPaddingOf(context).top + 4),
            if (widget.offscreenButton case final offscreen?)
              ValueListenableBuilder<bool>(
                valueListenable: offscreen,
                builder: (context, on, _) => on
                    ? SizedBox(
                        height: 0,
                        child: OverflowBox(
                          maxHeight: 100,
                          alignment: Alignment.topLeft,
                          child: Transform.translate(
                            offset: const Offset(800, 300),
                            child: const SearchInkFab(key: _offscreenKey),
                          ),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            CollapsingChrome(
              controller: _chrome,
              child: SearchModeHeaderSlot(
                header: _Header(
                  back: widget.headerBack,
                  filters: widget.filters,
                ),
                search: SearchModeHeader(
                  hintText: 'Search games',
                  closeKey: _closeKey,
                  trailing: [
                    if (widget.filters) ...[
                      const SizedBox.square(
                        dimension: 44,
                        child: Icon(
                          Icons.grid_view_rounded,
                          key: _searchOnlyKey,
                        ),
                      ),
                      SearchModeShared(
                        id: 'filters',
                        child: SearchModeFilterButton(
                          key: _searchFiltersKey,
                          count: 2,
                          onTap: () {},
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            Expanded(
              child: ScrollChromeRegion(
                controller: _chrome,
                child: ListenableBuilder(
                  listenable: widget.search,
                  builder: (context, _) => PageView(
                    physics: widget.search.pagePhysics(),
                    children: [
                      ListView.builder(
                        itemCount: 100,
                        itemExtent: 50,
                        itemBuilder: (context, i) => Text('row $i'),
                      ),
                      const Center(child: Text('Second tab')),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({this.back = true, this.filters = false});

  final bool back;
  final bool filters;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: SearchHeaderMetrics.rowHeight,
          child: Row(
            children: [
              SizedBox(width: SearchHeaderMetrics.leadingInset),
              if (back)
                const PageBackButton(key: _backKey)
              else
                const SizedBox(width: SearchHeaderMetrics.backTarget),
              const Expanded(child: Center(child: Text('Event title'))),
              if (filters) ...[
                // The toolbar's Filters at the search header's own spot: the
                // last control, its glyph on the gutter.
                SearchModeShared(
                  id: 'filters',
                  child: SearchModeFilterButton(
                    key: _headerFiltersKey,
                    count: 2,
                    onTap: () {},
                  ),
                ),
                SizedBox(
                  width:
                      SearchHeaderMetrics.gutter -
                      SearchHeaderMetrics.trailingReach,
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 8),
        const SizedBox(height: 40, child: Center(child: Text('Tabs'))),
        const SizedBox(height: 4),
      ],
    );
  }
}

Future<SearchModeController> _pump(
  WidgetTester tester, {
  bool reduceMotion = false,
  bool pushed = false,
  ValueChanged<String>? onQuery,
  ValueChanged<ScrollChromeController>? onChrome,
  ValueListenable<bool>? offscreenButton,
  bool headerBack = true,
  bool filters = false,
  TargetPlatform? platform,
  bool nested = false,
  ValueListenable<bool>? shellAway,
}) async {
  tester.view.physicalSize = const Size(393, 852);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final search = SearchModeController();
  Widget host(BuildContext context) => MediaQuery(
    data: MediaQuery.of(context).copyWith(disableAnimations: reduceMotion),
    child: _Page(
      search: search,
      onQuery: onQuery,
      onChrome: onChrome,
      offscreenButton: offscreenButton,
      headerBack: headerBack,
      filters: filters,
    ),
  );
  // In a tab's own navigator inside the app's (a shell's): what the page's
  // route says about being in front stops at it.
  final WidgetBuilder section = nested
      ? (context) => Navigator(
          onGenerateRoute: (_) => MaterialPageRoute<void>(builder: host),
        )
      : host;
  // A section of the home shell: a tap on nothing puts the keyboard away,
  // and while another section is in view this one is kept, out of sight,
  // its tickers off and its focus excluded (home_screen.dart).
  final WidgetBuilder page = shellAway == null
      ? section
      : (context) => GestureDetector(
          onTap: FocusScope.of(context).unfocus,
          child: ValueListenableBuilder<bool>(
            valueListenable: shellAway,
            builder: (context, away, _) => Offstage(
              offstage: away,
              child: TickerMode(
                enabled: !away,
                child: ExcludeFocus(
                  excluding: away,
                  child: Builder(builder: section),
                ),
              ),
            ),
          ),
        );
  await tester.pumpWidget(
    MaterialApp(
      theme: platform == null
          ? AppTheme.darkTheme
          : AppTheme.darkTheme.copyWith(platform: platform),
      home: Builder(
        builder: (context) {
          ResponsiveHelper.init(context);
          if (!pushed) return page(context);
          return Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => Navigator.of(
                  context,
                ).push(MaterialPageRoute<void>(builder: page)),
                child: const Text('Open page'),
              ),
            ),
          );
        },
      ),
    ),
  );
  if (pushed) {
    await tester.tap(find.text('Open page'));
    await tester.pumpAndSettle();
  }
  await tester.pump();
  return search;
}

/// Unmounts the page, then lets its controller go.
Future<void> _done(WidgetTester tester, SearchModeController search) async {
  await tester.pumpWidget(const SizedBox.shrink());
  search.dispose();
}

Future<void> _frames(WidgetTester tester, [int count = 90]) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

Finder get _slot => find.byType(SearchModeHeaderSlot);
Finder get _fabGlass => find.descendant(
  of: find.byKey(_fabKey),
  matching: find.byType(GlassSurface),
);

/// The search button's disc: drawn (1) or carried by the glass (0).
double _discOpacity(WidgetTester tester) => tester
    .widget<Opacity>(
      find.ancestor(of: _fabGlass, matching: find.byType(Opacity)).first,
    )
    .opacity;

/// Live first, stepping back with the search (as glass: [GlassFade]).
/// The stack's own fade for its siblings: the nearest one above the button
/// (the buttons' leave-with-the-chrome fade sits further out).
GlassFade _sibling(WidgetTester tester) => tester.widget<GlassFade>(
  find
      .ancestor(of: find.byKey(_liveKey), matching: find.byType(GlassFade))
      .first,
);

/// How strongly [finder]'s widget is painted: every opacity above it,
/// multiplied.
double _paintedOpacity(WidgetTester tester, Finder finder) {
  var opacity = 1.0;
  for (
    RenderObject? node = tester.renderObject(finder);
    node != null;
    node = node.parent
  ) {
    if (node is RenderOpacity) opacity *= node.opacity;
    if (node is RenderAnimatedOpacity) opacity *= node.opacity.value;
  }
  return opacity;
}

/// Of every copy [all] finds, the ones painted at all: each must be whole
/// (no half-faded control) and there must be exactly one, at [rest].
void _expectOneStill(
  WidgetTester tester,
  Finder all,
  Rect rest,
  String reason,
) {
  final drawn = <Rect>[];
  for (var i = 0; i < all.evaluate().length; i++) {
    final copy = all.at(i);
    final opacity = _paintedOpacity(tester, copy);
    if (opacity == 0) continue;
    expect(opacity, 1, reason: '$reason: a copy half there');
    drawn.add(tester.getRect(copy));
  }
  expect(drawn, hasLength(1), reason: '$reason: copies drawn');
  expect(
    drawn.single,
    rectMoreOrLessEquals(rest, epsilon: 0.01),
    reason: '$reason: moved',
  );
}

/// The field's text and hint, arriving over the last part of the morph: the
/// opacity they are painted at (the nearest fade above the field).
double _fieldContentOpacity(WidgetTester tester) {
  RenderObject? node = tester.renderObject(find.byType(SimpleSearchBar));
  while (node != null && node is! RenderAnimatedOpacity) {
    node = node.parent;
  }
  return (node! as RenderAnimatedOpacity).opacity.value;
}

void main() {
  testWidgets('opens and closes: the search, then the page, in full', (
    tester,
  ) async {
    late ScrollChromeController chrome;
    final search = await _pump(tester, onChrome: (c) => chrome = c);
    expect(find.byType(SearchModeHeader), findsNothing);
    expect(tester.getSize(_slot).height, 100);
    expect(_discOpacity(tester), 1);

    await tester.tap(find.byKey(_fabKey));
    expect(search.isSearching, isTrue);
    await _frames(tester);

    expect(search.debugFlightActive, isFalse);
    expect(search.timeline.value, 1);
    expect(find.byType(SearchModeHeader), findsOneWidget);
    // The header gave its height to the search header, cursor in the field.
    expect(tester.getSize(_slot).height, closeTo(52, 0.01));
    expect(search.focusNode.hasFocus, isTrue);
    expect(chrome.held, isTrue);
    expect(_fieldContentOpacity(tester), 1);
    expect(find.text('Search games'), findsOneWidget);
    // Nothing floats while searching; the tab holds still.
    expect(_discOpacity(tester), 0);
    expect(_sibling(tester).opacity.value, 0);
    expect(
      tester.widget<PageView>(find.byType(PageView)).physics,
      isA<NeverScrollableScrollPhysics>(),
    );
    // The page's header is still there, out of reach.
    expect(find.text('Event title', skipOffstage: false), findsOneWidget);
    expect(find.text('Event title').hitTestable(), findsNothing);

    await tester.tap(find.byKey(_closeKey));
    expect(search.isSearching, isFalse);
    expect(search.focusNode.hasFocus, isFalse);
    await _frames(tester);

    expect(search.debugFlightActive, isFalse);
    expect(search.timeline.value, 0);
    expect(find.byType(SearchModeHeader), findsNothing);
    expect(tester.getSize(_slot).height, 100);
    expect(_discOpacity(tester), 1);
    expect(_sibling(tester).opacity.value, 1);
    expect(chrome.held, isFalse);
    expect(tester.widget<PageView>(find.byType(PageView)).physics, isNull);
    expect(find.text('Event title').hitTestable(), findsOneWidget);
    await _done(tester, search);
  });

  testWidgets('no frame draws neither the search button nor its glass', (
    tester,
  ) async {
    final search = await _pump(tester);

    /// Every frame from the tap to the one after the glass lands: what was
    /// painted in it.
    Future<void> watch({required bool opening}) async {
      var painted = search.debugGlassPaintCount;
      for (var frame = 0; frame < 90; frame++) {
        final flying = search.debugFlightActive;
        await tester.pump(const Duration(milliseconds: 16));
        final glass = search.debugGlassPaintCount > painted;
        painted = search.debugGlassPaintCount;
        // As built for this frame's paint.
        final button = _discOpacity(tester) == 1;
        final field =
            !flying &&
            opening &&
            find.byType(SearchFieldFill).evaluate().isNotEmpty;
        expect(
          glass || button || field,
          isTrue,
          reason: 'frame $frame: nothing carries the search button',
        );
        expect(
          glass && button,
          isFalse,
          reason: 'frame $frame: two search buttons at once',
        );
        if (!flying) {
          // The frame after the landing: the field (or the button) took
          // over from the glass.
          expect(glass, isFalse, reason: 'frame $frame: glass after landing');
          expect(opening ? field : button, isTrue);
          return;
        }
      }
      fail('the glass never landed');
    }

    await tester.tap(find.byKey(_fabKey));
    await watch(opening: true);
    await tester.tap(find.byKey(_closeKey));
    await watch(opening: false);
    expect(_discOpacity(tester), 1);
    expect(tester.takeException(), isNull);
    await _done(tester, search);
  });

  testWidgets('the glass leaves the button as drawn and lands on the field', (
    tester,
  ) async {
    final search = await _pump(tester);

    await tester.tap(find.byKey(_fabKey));
    await tester.pump();
    // The first frame: the glass exactly where the button was drawn.
    expect(search.debugFlightActive, isTrue);
    expect(
      search.debugGlassRect,
      rectMoreOrLessEquals(tester.getRect(_fabGlass), epsilon: 0.5),
    );
    // The field's own magnifier stands down while the glass's flies in.
    final magnifier = find
        .descendant(
          of: find.byType(SimpleSearchBar),
          matching: find.byType(Opacity),
        )
        .first;
    expect(tester.widget<Opacity>(magnifier).opacity, 0);

    // The glass drawn in each frame, up to the one it lands in.
    Rect? last;
    var frames = 0;
    for (var i = 0; i < 90 && search.debugFlightActive; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      frames++;
      last = search.debugGlassRect;
    }
    expect(search.debugFlightActive, isFalse);
    final field = tester.getRect(find.byType(SearchFieldFill));
    // The frame it lands in, the glass is drawn exactly on the field it
    // becomes.
    expect(last, rectMoreOrLessEquals(field, epsilon: 0.01));
    // Landed in about a third of a second: no sub-pixel creep at the end.
    expect(frames * 16, inInclusiveRange(300, 352));
    // The frame after, the field is drawn instead, its own magnifier back.
    await tester.pump(const Duration(milliseconds: 16));
    expect(tester.widget<Opacity>(magnifier).opacity, 1);

    // And back: the first frame of the close is the field itself.
    await tester.tap(find.byKey(_closeKey));
    await tester.pump();
    expect(search.debugFlightActive, isTrue);
    expect(search.debugGlassRect, rectMoreOrLessEquals(field, epsilon: 0.5));
    for (var i = 0; i < 90 && search.debugFlightActive; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      last = search.debugGlassRect;
    }
    // It lands exactly on the button, drawn the frame after.
    expect(
      last,
      rectMoreOrLessEquals(tester.getRect(_fabGlass), epsilon: 0.01),
    );
    await tester.pump(const Duration(milliseconds: 16));
    expect(_discOpacity(tester), 1);
    expect(tester.takeException(), isNull);
    await _done(tester, search);
  });

  testWidgets('closing mid-flight turns round from where it is', (
    tester,
  ) async {
    final search = await _pump(tester);
    await tester.tap(find.byKey(_fabKey));
    await _frames(tester, 6);
    final t = search.timeline.value;
    expect(t, inExclusiveRange(0.05, 0.95));
    final before = search.debugGlassRect!;

    search.close();
    await tester.pump(const Duration(milliseconds: 16));
    // Same flight, no restart: it carries on from where it was.
    expect(search.debugFlightActive, isTrue);
    expect((search.timeline.value - t).abs(), lessThan(0.15));
    final after = search.debugGlassRect!;
    expect((after.center - before.center).distance, lessThan(60));

    // Turned round: it only goes back now.
    var previous = search.timeline.value;
    for (var i = 0; i < 90 && search.debugFlightActive; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      if (i > 3) {
        expect(search.timeline.value, lessThanOrEqualTo(previous + 1e-9));
      }
      previous = search.timeline.value;
    }
    expect(search.debugFlightActive, isFalse);
    expect(search.timeline.value, 0);
    expect(find.byType(SearchModeHeader), findsNothing);
    // The frame after the landing, the button is drawn again.
    await tester.pump(const Duration(milliseconds: 16));
    expect(_discOpacity(tester), 1);

    // And opening again during a close turns round too.
    await tester.tap(find.byKey(_fabKey));
    await _frames(tester);
    await tester.tap(find.byKey(_closeKey));
    await _frames(tester, 6);
    search.open();
    await _frames(tester);
    expect(search.isSearching, isTrue);
    expect(search.timeline.value, 1);
    expect(search.debugFlightActive, isFalse);
    await _done(tester, search);
  });

  testWidgets('the header height springs, the list never jumps', (
    tester,
  ) async {
    final search = await _pump(tester);
    final listTop = find.text('row 0');
    final heights = <double>[tester.getSize(_slot).height];
    final tops = <double>[tester.getTopLeft(listTop).dy];

    await tester.tap(find.byKey(_fabKey));
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      heights.add(tester.getSize(_slot).height);
      tops.add(tester.getTopLeft(listTop).dy);
    }
    expect(heights.last, closeTo(52, 0.01));
    for (var i = 1; i < heights.length; i++) {
      expect(heights[i], lessThanOrEqualTo(heights[i - 1] + 1e-9));
      expect(heights[i - 1] - heights[i], lessThan(12));
      expect(tops[i - 1] - tops[i], lessThan(12));
    }
    await _done(tester, search);
  });

  testWidgets('the chevron sits where the page puts its back button', (
    tester,
  ) async {
    final search = await _pump(tester);
    final back = tester.getCenter(find.byKey(_backKey));
    expect(back.dx, SearchHeaderMetrics.backGlyphCenter);

    await tester.tap(find.byKey(_fabKey));
    await _frames(tester);
    expect(
      tester.getCenter(find.byKey(_closeKey)),
      offsetMoreOrLessEquals(back, epsilon: 0.01),
    );
    // The field ends on the gutter.
    expect(
      tester.getRect(find.byType(SearchFieldFill)).right,
      closeTo(393 - SearchHeaderMetrics.gutter, 0.01),
    );
    await _done(tester, search);
  });

  testWidgets('PageBackButton is the pages\' back, glyph for glyph', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    const legacy = ValueKey('legacy_back');
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: Builder(
          builder: (context) {
            ResponsiveHelper.init(context);
            return Scaffold(
              body: Column(
                children: [
                  // The event screen's, Favorites', the shell's: 16.w in.
                  Row(
                    children: [
                      SizedBox(width: 16.w),
                      IconButton(
                        iconSize: 24.ic,
                        padding: EdgeInsets.zero,
                        onPressed: () {},
                        icon: Icon(
                          Icons.arrow_back_ios_new_outlined,
                          key: legacy,
                          size: 24.ic,
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      SizedBox(width: SearchHeaderMetrics.leadingInset),
                      const PageBackButton(key: _backKey),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
    final page = tester.getRect(find.byKey(legacy));
    final glyph = tester.getRect(
      find.descendant(of: find.byKey(_backKey), matching: find.byType(Icon)),
    );
    expect(glyph.size, page.size);
    expect(glyph.center.dx, closeTo(page.center.dx, 0.01));
    expect(glyph.center.dx, closeTo(SearchHeaderMetrics.backGlyphCenter, 0.01));
  });

  testWidgets('popped or disposed mid-flight, nothing is left behind', (
    tester,
  ) async {
    var search = await _pump(tester, pushed: true);
    await tester.tap(find.byKey(_fabKey));
    await _frames(tester, 3);
    expect(search.debugFlightActive, isTrue);
    Navigator.of(tester.element(find.byType(_Page))).pop();
    await tester.pumpAndSettle();
    expect(find.byType(_Page), findsNothing);
    expect(find.byType(SearchModeHost), findsNothing);
    expect(find.text('Open page'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _done(tester, search);

    search = await _pump(tester);
    await tester.tap(find.byKey(_fabKey));
    await _frames(tester, 3);
    expect(search.debugFlightActive, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
    expect(search.debugFlightActive, isFalse);
    search.dispose();
  });

  testWidgets('reduced motion lands at once, everything in view', (
    tester,
  ) async {
    final search = await _pump(tester, reduceMotion: true);

    await tester.tap(find.byKey(_fabKey));
    await tester.pump();
    expect(search.debugFlightActive, isFalse);
    expect(search.debugGlassPaintCount, 0);
    expect(search.timeline.value, 1);
    expect(tester.getSize(_slot).height, closeTo(52, 0.01));
    expect(_fieldContentOpacity(tester), 1);
    expect(find.text('Search games'), findsOneWidget);
    expect(find.byKey(_closeKey).hitTestable(), findsOneWidget);
    expect(_discOpacity(tester), 0);
    // The field's focus lift lands too.
    await tester.pump();
    expect(
      tester.widget<SearchFieldFill>(find.byType(SearchFieldFill)).color,
      isSameColorAs(
        HomeSearchFieldSurface.fillOf(tester.element(find.byType(_Page)), 1),
      ),
    );

    await tester.tap(find.byKey(_closeKey));
    await tester.pump();
    expect(search.debugFlightActive, isFalse);
    expect(search.timeline.value, 0);
    expect(tester.getSize(_slot).height, 100);
    expect(_discOpacity(tester), 1);
    expect(find.text('Event title').hitTestable(), findsOneWidget);
    await _done(tester, search);
  });

  testWidgets('system back closes the search before the page', (tester) async {
    final search = await _pump(tester, pushed: true);
    await tester.tap(find.byKey(_fabKey));
    await _frames(tester);

    await tester.binding.handlePopRoute();
    await _frames(tester);
    expect(search.isSearching, isFalse);
    expect(find.byType(_Page), findsOneWidget);
    expect(find.byType(SearchModeHeader), findsNothing);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(_Page), findsNothing);
    await _done(tester, search);
  });

  testWidgets('the query runs once typing settles; close clears it at once', (
    tester,
  ) async {
    final queries = <String>[];
    final search = await _pump(tester, onQuery: queries.add);
    await tester.tap(find.byKey(_fabKey));
    await _frames(tester);

    await tester.enterText(find.byType(EditableText), 'carl');
    await tester.pump(const Duration(milliseconds: 100));
    expect(queries, isEmpty);
    await tester.pump(const Duration(milliseconds: 150));
    expect(queries, ['carl']);

    await tester.enterText(find.byType(EditableText), 'carlsen');
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.byKey(_closeKey));
    // The page hears it in the same tick as the close, the pending
    // keystroke dropped.
    expect(queries, ['carl', '']);
    expect(search.query, isEmpty);
    // The words leave with the field, on the timeline, never in one frame.
    final fades = <double>[];
    while (search.debugFlightActive) {
      await tester.pump(const Duration(milliseconds: 16));
      if (find.byType(SimpleSearchBar).evaluate().isEmpty) break;
      if (search.text.text != 'carlsen') break;
      fades.add(_fieldContentOpacity(tester));
    }
    expect(fades.first, 1);
    expect(fades.any((o) => o > 0 && o < 1), isTrue, reason: '$fades');
    expect(fades.last, 0, reason: '$fades');
    for (var i = 1; i < fades.length; i++) {
      expect(fades[i], lessThanOrEqualTo(fades[i - 1]));
    }
    await _frames(tester);
    // Emptied once the close has landed, without telling the page again.
    expect(search.text.text, isEmpty);
    expect(queries, ['carl', '']);
    await _done(tester, search);
  });

  testWidgets('a search reopened as it closes starts empty', (tester) async {
    final queries = <String>[];
    final search = await _pump(tester, onQuery: queries.add);
    await tester.tap(find.byKey(_fabKey));
    await _frames(tester);
    await tester.enterText(find.byType(EditableText), 'carlsen');
    await tester.pump(const Duration(milliseconds: 250));
    expect(queries, ['carlsen']);

    await tester.tap(find.byKey(_closeKey));
    await tester.pump(const Duration(milliseconds: 16));
    expect(search.text.text, 'carlsen');
    search.open();
    expect(search.text.text, isEmpty);
    await _frames(tester);
    expect(search.isSearching, isTrue);
    expect(find.text('carlsen'), findsNothing);
    expect(queries, ['carlsen', '']);
    await _done(tester, search);
  });

  testWidgets('one filter count: the accent coin, on the button and field', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final text = TextEditingController();
    final focus = FocusNode();
    addTearDown(text.dispose);
    addTearDown(focus.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: Builder(
          builder: (context) {
            ResponsiveHelper.init(context);
            return MediaQuery(
              // Large text: the digit follows it, as far as the coin holds.
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(2)),
              child: Scaffold(
                body: Column(
                  children: [
                    const SearchInkFab(badgeCount: 3),
                    SimpleSearchBar(
                      controller: text,
                      focusNode: focus,
                      onCloseTap: () {},
                      onOpenFilter: () {},
                      filterBadgeCount: 2,
                    ),
                    SearchModeFilterButton(count: 4, onTap: () {}),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
    final accent = tester.element(find.byType(Column).first).colors.accentText;
    final badges = find.byType(SearchCountBadge);
    expect(badges, findsNWidgets(3));
    for (final badge in badges.evaluate()) {
      final widget = badge.widget as SearchCountBadge;
      final coin = find.descendant(
        of: find.byWidget(widget),
        matching: find.byType(Container),
      );
      final decoration =
          tester.widget<Container>(coin.first).decoration! as BoxDecoration;
      expect(decoration.color, accent);
      final digit = tester.widget<Text>(
        find.descendant(of: find.byWidget(widget), matching: find.byType(Text)),
      );
      // The toolbar's digit: 10pt on a 16pt coin, 11 on the button's 20.
      expect(digit.style!.fontSize, widget.diameter == 16 ? 10 : 11);
      expect(digit.textScaler!.scale(10), closeTo(11.5, 0.001));
      // And it stays inside its coin, round for one digit.
      expect(
        tester.getSize(find.byWidget(digit)).height,
        lessThanOrEqualTo(widget.diameter),
      );
      expect(
        tester.getSize(find.byWidget(widget)),
        Size.square(widget.diameter),
      );
      expect(
        tester.getCenter(find.byWidget(digit)),
        offsetMoreOrLessEquals(
          tester.getCenter(find.byWidget(widget)),
          epsilon: 0.01,
        ),
      );
    }
    expect(find.bySemanticsLabel('Filters, 2 active'), findsOneWidget);
    expect(find.bySemanticsLabel('Filters, 4 active'), findsOneWidget);
  });

  testWidgets('Filters in the search header: the toolbar\'s glyph and spot, '
      'the one count, on the gutter', (tester) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var taps = 0;
    Widget page(int count) => MaterialApp(
      theme: AppTheme.darkTheme,
      home: Builder(
        builder: (context) {
          ResponsiveHelper.init(context);
          return Scaffold(
            body: Column(
              children: [
                SearchModeHeader(
                  trailing: [
                    SearchModeFilterButton(count: count, onTap: () => taps++),
                  ],
                ),
                // The list toolbar's own Filters, as the Games tabs draw it.
                Row(
                  children: [
                    QuickToggleIconButton(
                      label: 'Toolbar filters',
                      selected: count > 0,
                      badgeCount: count,
                      onTap: () {},
                      child: const Icon(Icons.tune_rounded),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );

    await tester.pumpWidget(page(2));
    final colors = tester.element(find.byType(SearchModeHeader)).colors;
    final button = find.byType(SearchModeFilterButton);
    final toolbar = find.byType(QuickToggleIconButton);
    final glyph = find.descendant(
      of: button,
      matching: find.byIcon(Icons.tune_rounded),
    );
    final toolbarGlyph = find.descendant(
      of: toolbar,
      matching: find.byIcon(Icons.tune_rounded),
    );
    // The toolbar's target and glyph, in its accent while a filter is on.
    expect(tester.getSize(button), tester.getSize(toolbar));
    expect(tester.getSize(glyph), tester.getSize(toolbarGlyph));
    expect(
      tester.getCenter(glyph) - tester.getTopLeft(button),
      tester.getCenter(toolbarGlyph) - tester.getTopLeft(toolbar),
    );
    expect(tester.widget<Icon>(glyph).color, colors.accentText);
    // The last trailing glyph ends on the gutter, as the field does without.
    expect(
      tester.getRect(glyph).right,
      closeTo(393 - SearchHeaderMetrics.gutter, 0.01),
    );
    // The one count, anchored where the toolbar anchors its own.
    final coin = find.descendant(
      of: button,
      matching: find.byType(SearchCountBadge),
    );
    final toolbarCoin = find
        .descendant(of: toolbar, matching: find.byType(Container))
        .first;
    expect(
      tester.getTopRight(coin) - tester.getTopLeft(button),
      tester.getTopRight(toolbarCoin) - tester.getTopLeft(toolbar),
    );
    final coinFill =
        tester
                .widget<Container>(
                  find.descendant(of: coin, matching: find.byType(Container)),
                )
                .decoration!
            as BoxDecoration;
    expect(coinFill.color, colors.accentText);
    expect(find.bySemanticsLabel('Filters, 2 active'), findsOneWidget);
    await tester.tap(button);
    expect(taps, 1);

    // Nothing applied: the resting ink, no count.
    await tester.pumpWidget(page(0));
    expect(tester.widget<Icon>(glyph).color, colors.iconPrimary);
    expect(coin, findsNothing);
    expect(find.bySemanticsLabel('Filters'), findsOneWidget);
  });

  testWidgets('the search glyph wears the same ink as its siblings', (
    tester,
  ) async {
    final search = await _pump(tester);
    final style = GlassStyle.of(tester.element(find.byKey(_fabKey)));
    final glyph = tester.widget<SvgWidget>(
      find.descendant(
        of: find.byKey(_fabKey),
        matching: find.byType(SvgWidget),
      ),
    );
    expect(glyph.colorFilter, ColorFilter.mode(style.ink, BlendMode.srcIn));
    // Live first's waves use the same ink while the toggle is off.
    final live = tester.widget<LiveGlyph>(
      find.descendant(
        of: find.byKey(_liveKey),
        matching: find.byKey(const ValueKey('live_first_capsule_off')),
      ),
    );
    expect(live.waveColor, style.ink);
    await _done(tester, search);
  });

  testWidgets('the siblings fade as glass, never under an opacity', (
    tester,
  ) async {
    final search = await _pump(tester);
    final liveFilter = find.descendant(
      of: find.byKey(_liveKey),
      matching: find.byType(BackdropFilter),
    );
    final livePlate = find
        .descendant(of: liveFilter, matching: find.byType(ColoredBox))
        .first;
    final restingPlate = tester.widget<ColoredBox>(livePlate).color;
    final gate = tester.renderObject(
      find
          .ancestor(of: find.byKey(_liveKey), matching: find.byType(GlassFade))
          .first,
    );
    expect(gate, isNot(paintsNothing));

    await tester.tap(find.byKey(_fabKey));
    var thinned = false;
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      final opacity = _sibling(tester).opacity.value;
      if (opacity <= 0) break;
      // Nothing between the glass and the page fades it as a layer.
      for (
        RenderObject? node = tester.renderObject(liveFilter).parent;
        node != null;
        node = node.parent
      ) {
        if (node is RenderOpacity) {
          expect(node.opacity, anyOf(0.0, 1.0));
        }
        if (node is RenderAnimatedOpacity) {
          expect(node.opacity.value, anyOf(0.0, 1.0));
        }
      }
      if (opacity < 1) {
        thinned = true;
        // The glass thins its own material instead.
        final plate = tester.widget<ColoredBox>(livePlate).color;
        expect(plate.a, closeTo(restingPlate.a * opacity, 0.01));
      }
    }
    expect(thinned, isTrue);
    await _frames(tester);
    // Gone, it is not drawn at all.
    expect(_sibling(tester).opacity.value, 0);
    expect(gate, paintsNothing);

    await tester.tap(find.byKey(_closeKey));
    await _frames(tester);
    expect(_sibling(tester).opacity.value, 1);
    expect(gate, isNot(paintsNothing));
    expect(tester.widget<ColoredBox>(livePlate).color, restingPlate);
    await _done(tester, search);
  });

  testWidgets('the chevron both headers draw holds still: whole and in '
      'place every frame, both ways', (tester) async {
    final search = await _pump(tester);
    final chevrons = find.byIcon(
      Icons.arrow_back_ios_new_outlined,
      skipOffstage: false,
    );
    final rest = tester.getRect(chevrons);
    _expectOneStill(tester, chevrons, rest, 'at rest');

    await tester.tap(find.byKey(_fabKey));
    for (var frame = 0; frame < 30; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
      _expectOneStill(tester, chevrons, rest, 'opening, frame $frame');
    }
    // Visible from the tap, so it answers from the tap: it turns the
    // search round.
    expect(find.byKey(_closeKey).hitTestable(), findsOneWidget);

    await tester.tap(find.byKey(_closeKey));
    for (var frame = 0; frame < 30; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
      _expectOneStill(tester, chevrons, rest, 'closing, frame $frame');
    }
    expect(search.isSearching, isFalse);
    await _done(tester, search);
  });

  testWidgets('a trailing control both headers draw holds still; one only '
      'the search draws arrives with it', (tester) async {
    final search = await _pump(tester, filters: true);
    final filters = find.byType(SearchModeFilterButton, skipOffstage: false);
    final rest = tester.getRect(find.byKey(_headerFiltersKey));
    _expectOneStill(tester, filters, rest, 'at rest');

    await tester.tap(find.byKey(_fabKey));
    final arriving = <double>[];
    for (var frame = 0; frame < 30; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
      _expectOneStill(tester, filters, rest, 'opening, frame $frame');
      arriving.add(_paintedOpacity(tester, find.byKey(_searchOnlyKey)));
      if (frame == 1) {
        // Not there to see yet: no tap.
        expect(find.byKey(_searchOnlyKey).hitTestable(), findsNothing);
      }
    }
    // The control that differs fades in, never pops.
    expect(arriving.first, 0);
    expect(arriving.any((o) => o > 0 && o < 1), isTrue, reason: '$arriving');
    expect(arriving.last, 1);
    expect(
      tester.getRect(find.byKey(_searchFiltersKey)),
      rectMoreOrLessEquals(rest, epsilon: 0.01),
    );

    await tester.tap(find.byKey(_closeKey));
    for (var frame = 0; frame < 30; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
      _expectOneStill(tester, filters, rest, 'closing, frame $frame');
    }
    await _done(tester, search);
  });

  testWidgets('with no way back in the page header, the chevron arrives '
      'with the search and takes no tap before it can be seen', (tester) async {
    final search = await _pump(tester, headerBack: false);
    await tester.tap(find.byKey(_fabKey));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    // Built and in place, but not yet there to see.
    expect(find.byKey(_closeKey), findsOneWidget);
    expect(_paintedOpacity(tester, find.byKey(_closeKey)), lessThan(0.5));
    expect(find.byKey(_closeKey).hitTestable(), findsNothing);
    await tester.tapAt(tester.getCenter(find.byKey(_closeKey)));
    await tester.pump();
    expect(search.isSearching, isTrue);

    await _frames(tester);
    expect(_paintedOpacity(tester, find.byKey(_closeKey)), 1);
    expect(find.byKey(_closeKey).hitTestable(), findsOneWidget);
    expect(find.byType(EditableText).hitTestable(), findsOneWidget);
    await _done(tester, search);
  });

  testWidgets('iOS: the back swipe closes the search, then the next one '
      'pops the page', (tester) async {
    final search = await _pump(
      tester,
      pushed: true,
      platform: TargetPlatform.iOS,
    );
    await tester.tap(find.byKey(_fabKey));
    await _frames(tester);
    expect(search.isSearching, isTrue);

    // A short drag from the edge is not a swipe: the search stays.
    await tester.dragFrom(const Offset(4, 420), const Offset(24, 0));
    await _frames(tester, 10);
    expect(search.isSearching, isTrue);

    // From the screen's edge, where the route's own swipe starts.
    await tester.timedDragFrom(
      const Offset(4, 420),
      const Offset(160, 0),
      const Duration(milliseconds: 200),
    );
    await _frames(tester);
    expect(search.isSearching, isFalse);
    expect(find.byType(_Page), findsOneWidget);
    expect(find.byType(SearchModeHeader), findsNothing);

    // Closed, the swipe is the page's again: it goes back.
    await tester.timedDragFrom(
      const Offset(4, 420),
      const Offset(300, 0),
      const Duration(milliseconds: 300),
    );
    await tester.pumpAndSettle();
    expect(find.byType(_Page), findsNothing);
    expect(find.text('Open page'), findsOneWidget);
    await _done(tester, search);
  });

  testWidgets('Android: system back closes the search first; an edge drag '
      'does nothing special', (tester) async {
    final search = await _pump(
      tester,
      pushed: true,
      platform: TargetPlatform.android,
    );
    await tester.tap(find.byKey(_fabKey));
    await _frames(tester);
    await tester.timedDragFrom(
      const Offset(4, 420),
      const Offset(160, 0),
      const Duration(milliseconds: 200),
    );
    await _frames(tester);
    expect(search.isSearching, isTrue);

    await tester.binding.handlePopRoute();
    await _frames(tester);
    expect(search.isSearching, isFalse);
    expect(find.byType(_Page), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(_Page), findsNothing);
    await _done(tester, search);
  });

  testWidgets('the field is the Search tab\'s, and the glass lands on its '
      'colours', (tester) async {
    final search = await _pump(tester);
    final context = tester.element(find.byType(_Page));

    await tester.tap(find.byKey(_fabKey));
    await tester.pump();
    // Leaving the button, the glass is glass: none of the field in it yet.
    expect(search.debugGlassLook!.fill!.a, lessThan(0.05));
    GlassLook? landing;
    for (var i = 0; i < 90 && search.debugFlightActive; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      landing = search.debugGlassLook;
    }
    expect(search.debugFlightActive, isFalse);
    // The frame it lands, its material is the field drawn after it: the
    // field's fill and its edge, nothing of the glass left.
    final fill = tester.widget<SearchFieldFill>(find.byType(SearchFieldFill));
    expect(landing!.fill, isSameColorAs(fill.color));
    expect(landing.rimTop, isSameColorAs(fill.edge!));
    expect(landing.rimBottom, isSameColorAs(fill.edge!));
    expect(landing.plate.a, 0);
    expect(landing.blurs, isFalse);

    await _frames(tester, 30);
    // Focused: the home field's lift and edge, its height, its type.
    final focused = tester.widget<SearchFieldFill>(
      find.byType(SearchFieldFill),
    );
    expect(
      focused.color,
      isSameColorAs(HomeSearchFieldSurface.fillOf(context, 1)),
    );
    expect(
      focused.edge,
      isSameColorAs(HomeSearchFieldSurface.edgeOf(context, 1)),
    );
    expect(focused.radius, HomeSearchFieldSurface.radius);
    final field = tester.getRect(find.byType(SearchFieldFill));
    expect(field.height, HomeSearchFieldSurface.heightOf(context));
    expect(
      field.center.dy,
      closeTo(tester.getCenter(find.byKey(_closeKey)).dy, 0.01),
    );
    expect(
      tester.widget<EditableText>(find.byType(EditableText)).style.fontSize,
      HomeTopBarMetrics.fieldTextStyle.fontSize,
    );

    // The keyboard put away over a query: the field rests, on the spring
    // it lifted on (with nothing typed the search would close with it).
    await tester.enterText(find.byType(EditableText), 'carl');
    search.focusNode.unfocus();
    await _frames(tester, 40);
    expect(search.isSearching, isTrue);
    final resting = tester.widget<SearchFieldFill>(
      find.byType(SearchFieldFill),
    );
    expect(
      resting.color,
      isSameColorAs(HomeSearchFieldSurface.fillOf(context, 0)),
    );
    // A tap anywhere on the field, not only on its line of text, brings
    // the keyboard back.
    await tester.tapAt(field.topCenter + const Offset(0, 3));
    await tester.pump();
    expect(search.focusNode.hasFocus, isTrue);
    await _done(tester, search);
  });

  testWidgets('with a second search button out of view, the glass keeps to '
      'the one in view', (tester) async {
    final offscreen = ValueNotifier<bool>(false);
    addTearDown(offscreen.dispose);
    final search = await _pump(tester, offscreenButton: offscreen);
    // Registered last, and laid out off to the side of the page.
    offscreen.value = true;
    await tester.pump();
    expect(find.byKey(_offscreenKey), findsOneWidget);
    final fab = tester.getRect(_fabGlass);

    await tester.tap(find.byKey(_fabKey));
    await tester.pump();
    expect(search.debugGlassRect, rectMoreOrLessEquals(fab, epsilon: 0.5));
    await _frames(tester);

    // Opened from code, then closed: no tap to say which, so the one in
    // view.
    await tester.tap(find.byKey(_closeKey));
    await _frames(tester);
    search.open();
    await _frames(tester);
    expect(search.isSearching, isTrue);
    search.close();
    Rect? last;
    for (var i = 0; i < 90 && search.debugFlightActive; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      last = search.debugGlassRect;
    }
    // Drawn on the button in view the frame it lands.
    expect(search.debugFlightActive, isFalse);
    expect(last, rectMoreOrLessEquals(fab, epsilon: 0.01));
    await _done(tester, search);
  });

  testWidgets('the chrome is let go with the host and with its controller', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final chrome = ScrollChromeController(vsync: const TestVSync());
    addTearDown(chrome.dispose);
    final first = SearchModeController();
    final second = SearchModeController();
    addTearDown(first.dispose);
    addTearDown(second.dispose);

    Widget host(SearchModeController search) => MaterialApp(
      theme: AppTheme.darkTheme,
      home: Builder(
        builder: (context) {
          ResponsiveHelper.init(context);
          return SearchModeHost(
            controller: search,
            chrome: chrome,
            child: const Scaffold(
              body: SearchModeHeaderSlot(
                header: SizedBox(height: 100),
                search: SearchModeHeader(),
              ),
            ),
          );
        },
      ),
    );

    await tester.pumpWidget(host(first));
    first.open();
    await _frames(tester, 30);
    expect(first.focusNode.hasFocus, isTrue);
    expect(chrome.held, isTrue);

    // Another controller takes the host: the first one's field no longer
    // holds the chrome.
    await tester.pumpWidget(host(second));
    expect(chrome.held, isFalse);

    second.open();
    await _frames(tester, 30);
    expect(chrome.held, isTrue);
    // The page goes, its chrome stays (a shell's): let go.
    await tester.pumpWidget(const SizedBox.shrink());
    expect(chrome.held, isFalse);
  });

  testWidgets('a slow first frame never eats the morph: the glass sets off '
      'from where it rests, both ways', (tester) async {
    final search = await _pump(tester);
    await tester.tap(find.byKey(_fabKey));
    // The frame that builds the search header and its field, taking long.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    // Still on the button: the spring starts after that frame, not under it,
    // so it does not leap through the time it took.
    expect(search.timeline.value, lessThan(0.01));
    expect(
      search.debugGlassRect,
      rectMoreOrLessEquals(tester.getRect(_fabGlass), epsilon: 0.5),
    );
    var previous = search.debugGlassRect!.center;
    await tester.pump(const Duration(milliseconds: 16));
    expect((search.debugGlassRect!.center - previous).distance, lessThan(60));
    await _frames(tester);
    expect(search.timeline.value, 1);

    // And back: the costly frame of the close (the page clearing its query)
    // keeps the glass on the field.
    final field = tester.getRect(find.byType(SearchFieldFill));
    await tester.tap(find.byKey(_closeKey));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    expect(search.timeline.value, greaterThan(0.99));
    expect(search.debugGlassRect, rectMoreOrLessEquals(field, epsilon: 0.5));
    previous = search.debugGlassRect!.center;
    await tester.pump(const Duration(milliseconds: 16));
    expect((search.debugGlassRect!.center - previous).distance, lessThan(60));
    await _frames(tester);
    expect(search.timeline.value, 0);
    expect(_discOpacity(tester), 1);
    await _done(tester, search);
  });

  group('the keyboard put away', () {
    testWidgets('with nothing typed, the search closes with it: the glass '
        'flies back from the field into the button', (tester) async {
      Future<void> putAway(SearchModeController search, String how) async {
        await _openFully(tester, search);
        final field = tester.getRect(find.byType(SearchFieldFill));
        switch (how) {
          // Done (or Search) on the keyboard.
          case 'done':
            await tester.testTextInput.receiveAction(TextInputAction.done);
          // A list that dismisses the keyboard on drag, a page putting it
          // away, iOS closing the input.
          case 'unfocus':
            FocusManager.instance.primaryFocus!.unfocus();
        }
        await tester.pump();
        expect(search.focusNode.hasFocus, isFalse, reason: how);
        // It sets off at once, from the field as drawn.
        await tester.pump(const Duration(milliseconds: 16));
        expect(search.isSearching, isFalse, reason: how);
        final drawn = await _flightBack(tester, search);
        expect(drawn.first, rectMoreOrLessEquals(field, epsilon: 0.5));
        // A real flight, the chevron's own (about 20 frames), never a snap.
        expect(drawn.length, greaterThan(15), reason: how);
        // It lands on the button, drawn the frame after.
        expect(
          drawn.last,
          rectMoreOrLessEquals(tester.getRect(_fabGlass), epsilon: 0.01),
        );
        await tester.pump(const Duration(milliseconds: 16));
        expect(_discOpacity(tester), 1);
        expect(find.byType(SearchModeHeader), findsNothing);
        expect(tester.getSize(_slot).height, 100);
      }

      late ScrollChromeController chrome;
      final search = await _pump(tester, onChrome: (c) => chrome = c);
      await putAway(search, 'done');
      expect(chrome.held, isFalse);
      await putAway(search, 'unfocus');
      expect(tester.takeException(), isNull);
      await _done(tester, search);
    });

    testWidgets('the empty field\'s clear button closes it too', (
      tester,
    ) async {
      final search = await _pump(tester);
      await _openFully(tester, search);
      await tester.tap(
        find.descendant(
          of: find.byType(SimpleSearchBar),
          matching: find.byIcon(Icons.close),
        ),
      );
      await tester.pump();
      expect(search.isSearching, isFalse);
      final drawn = await _flightBack(tester, search);
      expect(drawn.length, greaterThan(15));
      expect(find.byType(SearchModeHeader), findsNothing);
      await _done(tester, search);
    });

    testWidgets('with words typed, only the keyboard goes: the results stay', (
      tester,
    ) async {
      final queries = <String>[];
      final search = await _pump(tester, onQuery: queries.add);
      await _openFully(tester, search);
      await tester.enterText(find.byType(EditableText), 'carl');
      await tester.pump(const Duration(milliseconds: 250));
      expect(queries, ['carl']);
      final painted = search.debugGlassPaintCount;

      await tester.testTextInput.receiveAction(TextInputAction.done);
      await _frames(tester);
      expect(search.focusNode.hasFocus, isFalse);
      expect(search.isSearching, isTrue);
      expect(search.query, 'carl');
      expect(queries, ['carl']);
      // Nothing flew, nothing moved.
      expect(search.debugGlassPaintCount, painted);
      expect(search.timeline.value, 1);
      expect(find.byType(SearchModeHeader), findsOneWidget);
      expect(find.text('carl'), findsOneWidget);
      expect(_discOpacity(tester), 0);
      await _done(tester, search);
    });

    testWidgets('Android back that only hides the keyboard closes it; with '
        'words, the field keeps them and its cursor', (tester) async {
      final search = await _pump(tester, platform: TargetPlatform.android);
      await _openFully(tester, search);
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await _frames(tester, 20);
      expect(search.isSearching, isTrue);

      // The keyboard goes down; the field keeps its focus (Android).
      tester.view.resetViewInsets();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      expect(search.isSearching, isFalse);
      final drawn = await _flightBack(tester, search);
      expect(drawn.length, greaterThan(15));
      expect(search.focusNode.hasFocus, isFalse);
      expect(find.byType(SearchModeHeader), findsNothing);

      await _openFully(tester, search);
      await tester.enterText(find.byType(EditableText), 'carl');
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await _frames(tester, 20);
      tester.view.resetViewInsets();
      await _frames(tester);
      expect(search.isSearching, isTrue);
      expect(search.focusNode.hasFocus, isTrue);
      expect(search.query, 'carl');
      expect(search.debugFlightActive, isFalse);
      await _done(tester, search);
    });

    testWidgets('a route, a sheet or a dialog taking the focus never closes '
        'it', (tester) async {
      final search = await _pump(tester);
      await _openFully(tester, search);
      final page = tester.element(find.byType(SearchModeHeader));

      /// Shows something over the page, then takes it away again: the search
      /// is open throughout.
      Future<void> over(String what, VoidCallback show, Finder shown) async {
        show();
        await tester.pumpAndSettle();
        expect(shown, findsOneWidget, reason: what);
        expect(search.focusNode.hasFocus, isFalse, reason: what);
        expect(search.isSearching, isTrue, reason: what);
        Navigator.of(tester.element(shown)).pop();
        await tester.pumpAndSettle();
        expect(shown, findsNothing, reason: what);
        expect(search.isSearching, isTrue, reason: what);
        expect(search.debugFlightActive, isFalse, reason: what);
        expect(find.byType(SearchModeHeader), findsOneWidget, reason: what);
      }

      // A game opened from the results.
      await over(
        'a game',
        () => Navigator.of(page).push(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Center(child: Text('Game'))),
          ),
        ),
        find.text('Game'),
      );
      // Back from it, the field has its cursor again.
      expect(search.focusNode.hasFocus, isTrue);

      // The filter popup.
      await over(
        'a dialog',
        () => showDialog<void>(
          context: page,
          builder: (_) => const Dialog(child: Text('Filters')),
        ),
        find.text('Filters'),
      );
      // A sheet.
      await over(
        'a sheet',
        () => showModalBottomSheet<void>(
          context: page,
          builder: (_) => const SizedBox(height: 200, child: Text('Sheet')),
        ),
        find.text('Sheet'),
      );
      // The page putting the keyboard away on its way to a player.
      await over('a page putting the keyboard away first', () {
        FocusManager.instance.primaryFocus?.unfocus();
        Navigator.of(page).push(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Center(child: Text('Player'))),
          ),
        );
      }, find.text('Player'));
      expect(tester.takeException(), isNull);
      await _done(tester, search);
    });

    testWidgets('a dialog over a tab\'s own navigator does not close it', (
      tester,
    ) async {
      // The page's route is still the one in front of its navigator; the
      // dialog is on the app's, above it.
      final search = await _pump(tester, nested: true);
      await _openFully(tester, search);
      final page = tester.element(find.byType(SearchModeHeader));
      FocusManager.instance.primaryFocus?.unfocus();
      unawaited(
        showDialog<void>(
          context: page,
          builder: (_) => const Dialog(child: Text('Filters')),
        ),
      );
      await tester.pumpAndSettle();
      expect(ModalRoute.isCurrentOf(page), isTrue);
      expect(search.isSearching, isTrue);
      Navigator.of(tester.element(find.text('Filters'))).pop();
      await tester.pumpAndSettle();
      expect(search.isSearching, isTrue);
      expect(find.byType(SearchModeHeader), findsOneWidget);
      await _done(tester, search);
    });

    testWidgets('never while the glass is still flying in', (tester) async {
      final search = await _pump(tester);
      await tester.tap(find.byKey(_fabKey));
      await _frames(tester, 4);
      expect(search.debugFlightActive, isTrue);
      expect(search.focusNode.hasFocus, isTrue);
      search.focusNode.unfocus();
      await _frames(tester);
      expect(search.isSearching, isTrue);
      expect(search.timeline.value, 1);
      expect(search.debugFlightActive, isFalse);
      expect(find.byType(SearchModeHeader), findsOneWidget);
      await _done(tester, search);
    });

    testWidgets('a finger still on the page holds it until it lifts', (
      tester,
    ) async {
      final search = await _pump(tester);
      await _openFully(tester, search);
      // A drag on the list that puts the keyboard away.
      final gesture = await tester.startGesture(
        tester.getCenter(find.text('row 6')),
      );
      await gesture.moveBy(const Offset(0, -30));
      FocusManager.instance.primaryFocus?.unfocus();
      await _frames(tester, 20);
      expect(search.isSearching, isTrue);
      await gesture.moveBy(const Offset(0, -30));
      await _frames(tester, 5);
      expect(search.isSearching, isTrue);
      expect(search.debugFlightActive, isFalse);

      await gesture.up();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      expect(search.isSearching, isFalse);
      final drawn = await _flightBack(tester, search);
      expect(drawn.length, greaterThan(15));
      expect(find.byType(SearchModeHeader), findsNothing);
      await _done(tester, search);
    });

    testWidgets('the app leaving the screen never closes it', (tester) async {
      addTearDown(
        () => tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        ),
      );
      final search = await _pump(tester);
      await _openFully(tester, search);
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await _frames(tester, 20);

      // The keyboard goes with the app (in either order).
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.view.resetViewInsets();
      await _frames(tester, 20);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await _frames(tester);
      expect(search.isSearching, isTrue);

      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await _frames(tester, 20);
      tester.view.resetViewInsets();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await _frames(tester, 20);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await _frames(tester);
      expect(search.isSearching, isTrue);
      expect(search.focusNode.hasFocus, isTrue);
      expect(find.byType(SearchModeHeader), findsOneWidget);
      await _done(tester, search);
    });

    testWidgets('in a shell section: a tap on nothing closes it with the '
        'flight; leaving the section closes it at once, nothing left to '
        'play on the way back', (tester) async {
      final away = ValueNotifier<bool>(false);
      addTearDown(away.dispose);
      final search = await _pump(tester, shellAway: away);
      await _openFully(tester, search);
      // A row with nothing to do on a tap: the shell puts the keyboard away.
      await tester.tap(find.text('row 8'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      expect(search.isSearching, isFalse);
      final drawn = await _flightBack(tester, search);
      expect(drawn.length, greaterThan(15));
      expect(find.byType(SearchModeHeader), findsNothing);

      // The dock to another section: the keyboard goes, and this section is
      // kept out of sight with its tickers off.
      await _openFully(tester, search);
      final painted = search.debugGlassPaintCount;
      FocusManager.instance.primaryFocus?.unfocus();
      away.value = true;
      await _frames(tester, 5);
      expect(search.isSearching, isFalse);
      expect(search.debugFlightActive, isFalse);
      expect(search.timeline.value, 0);

      // Back to it: the page as it was before the search, nothing flying.
      away.value = false;
      await tester.pump();
      expect(search.debugFlightActive, isFalse);
      expect(find.byType(SearchModeHeader), findsNothing);
      expect(_discOpacity(tester), 1);
      await _frames(tester, 30);
      expect(search.debugGlassPaintCount, painted);
      expect(tester.takeException(), isNull);
      await _done(tester, search);
    });
  });
}

/// Taps the search button and lets the glass land in the field, the cursor
/// in it.
Future<void> _openFully(
  WidgetTester tester,
  SearchModeController search,
) async {
  await tester.tap(find.byKey(_fabKey));
  await _frames(tester);
  expect(search.isSearching, isTrue);
  expect(search.debugFlightActive, isFalse);
  expect(search.focusNode.hasFocus, isTrue);
}

/// Frames until a closing search's glass has landed in the button: the
/// glass as drawn in each of them.
Future<List<Rect>> _flightBack(
  WidgetTester tester,
  SearchModeController search,
) async {
  final drawn = <Rect>[];
  for (var i = 0; i < 90; i++) {
    final painted = search.debugGlassPaintCount;
    await tester.pump(const Duration(milliseconds: 16));
    if (search.debugGlassPaintCount > painted) {
      drawn.add(search.debugGlassRect!);
    }
    if (!search.debugFlightActive && drawn.isNotEmpty) return drawn;
  }
  fail('the glass never landed');
}
