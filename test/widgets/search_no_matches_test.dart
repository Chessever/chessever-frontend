import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/search_mode/search_mode.dart';
import 'package:chessever2/widgets/search_no_matches.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(393, 852);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.darkTheme,
      home: Builder(
        builder: (context) {
          ResponsiveHelper.init(context);
          return Scaffold(body: child);
        },
      ),
    ),
  );
}

Finder get _title => find.byKey(const ValueKey('search_no_matches_title'));
Finder get _clear => find.byKey(const ValueKey('search_no_matches_clear'));

/// Every opacity above [finder], multiplied.
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

void main() {
  test('the line echoes the words, or says what the list holds', () {
    expect(
      SearchNoMatches.titleFor(query: 'carlsen'),
      'No matches for "carlsen"',
    );
    expect(
      SearchNoMatches.titleFor(query: '  carlsen  '),
      'No matches for "carlsen"',
    );
    expect(SearchNoMatches.titleFor(), 'No matching games');
    expect(SearchNoMatches.titleFor(query: '   '), 'No matching games');
    expect(SearchNoMatches.titleFor(subject: 'players'), 'No matching players');
    expect(SearchNoMatches.clearLabelFor(filtered: false), 'Clear search');
    expect(SearchNoMatches.clearLabelFor(filtered: true), 'Clear filters');
  });

  testWidgets('whole from its first frame, on the gutter, in the app\'s type', (
    tester,
  ) async {
    await _pump(tester, const SearchNoMatches(query: 'najdorf'));
    // No time pumped: nothing waits on an entrance.
    expect(find.text('No matches for "najdorf"'), findsOneWidget);
    expect(_paintedOpacity(tester, _title), 1);

    final rect = tester.getRect(_title);
    expect(rect.left, closeTo(SearchHeaderMetrics.gutter, 0.01));
    expect(rect.top, closeTo(SearchNoMatches.topGap, 0.01));
    final style = tester.widget<Text>(_title).style!;
    expect(style.fontSize, AppTypography.textMdRegular.fontSize);
    expect(style.color, tester.element(_title).colors.textSecondary);
    // No action unless asked for.
    expect(_clear, findsNothing);
  });

  testWidgets('a screen reader hears it as it appears', (tester) async {
    final semantics = tester.ensureSemantics();
    await _pump(tester, const SearchNoMatches(query: 'ding'));
    expect(
      tester.getSemantics(_title),
      isSemantics(label: 'No matches for "ding"', isLiveRegion: true),
    );
    semantics.dispose();
  });

  testWidgets('the way back clears, once, with the button haptic, in a 44pt '
      'target', (tester) async {
    final haptics = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'HapticFeedback.vibrate') haptics.add(call);
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    var cleared = 0;
    await _pump(
      tester,
      SearchNoMatches(query: 'tal', onClear: () => cleared++),
    );
    expect(find.text('Clear search'), findsOneWidget);
    expect(_paintedOpacity(tester, find.text('Clear search')), 1);
    expect(tester.getSize(_clear).height, greaterThanOrEqualTo(44));
    // Under the line, on its start edge.
    expect(
      tester.getRect(find.text('Clear search')).left,
      closeTo(tester.getRect(_title).left, 0.01),
    );
    expect(
      tester.widget<Text>(find.text('Clear search')).style!.color,
      tester.element(_clear).colors.accentText,
    );
    await tester.tap(_clear);
    await tester.pumpAndSettle();
    expect(cleared, 1);
    expect(haptics, hasLength(1));
  });

  testWidgets('filters that empty the list are what it clears', (tester) async {
    final semantics = tester.ensureSemantics();
    var cleared = 0;
    await _pump(
      tester,
      CustomScrollView(
        slivers: [
          SearchNoMatches.sliver(filtered: true, onClear: () => cleared++),
        ],
      ),
    );
    expect(find.text('No matching games'), findsOneWidget);
    expect(find.text('Clear filters'), findsOneWidget);
    expect(
      tester.getSemantics(_clear),
      isSemantics(label: 'Clear filters', isButton: true, hasTapAction: true),
    );
    tester.semantics.tap(find.semantics.byLabel('Clear filters'));
    await tester.pumpAndSettle();
    expect(cleared, 1);
    semantics.dispose();
  });
}
