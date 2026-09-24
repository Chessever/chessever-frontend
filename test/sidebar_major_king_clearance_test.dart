import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:chessever2/repository/supabase/calendar_event/calendar_event.dart';
import 'package:chessever2/screens/calendar/calendar_screen.dart';
import 'package:chessever2/screens/calendar/provider/calendar_month_events_provider.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/hamburger_menu/sidebar_month_calendar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Pixel checks for the sidebar's major-event king, drawn in the app's own
/// font at real phone sizes: figures in pure green, the king in pure blue and
/// its cut-out edge in pure red, so every pixel says what it belongs to.
///
/// Every day of the month starts a major event, so each cell carries a king,
/// including the top row and the last column, where the grid's clip sits.

const _pixelRatio = 4.0;
const _clear = Color(0x00000000);

Future<void> _loadInter() async {
  final loader = FontLoader('InterDisplay');
  for (final face in ['Regular', 'Medium', 'Bold']) {
    loader.addFont(
      Future.value(
        File(
          'assets/fonts/Inter-$face.otf',
        ).readAsBytesSync().buffer.asByteData(),
      ),
    );
  }
  await loader.load();
}

CalendarMonthEvents _everyDayMajor() => CalendarMonthEvents(
  year: 2026,
  month: 9,
  broadcasts: const [],
  calendarEvents: [
    for (var d = 1; d <= 30; d++)
      CalendarEvent(
        name: 'Major $d',
        startDate: DateTime(2026, 9, d),
        endDate: DateTime(2026, 9, d),
        createdAt: DateTime(2026),
        isMajorUpcoming: true,
      ),
  ],
);

class _Render {
  _Render(this.rgba, this.width, this.height, this.cells);

  final Uint8List rgba;
  final int width;
  final int height;

  /// Day cells in logical pixels, relative to the rendered image.
  final Map<int, Rect> cells;

  int _at(int x, int y, int channel) => rgba[(y * width + x) * 4 + channel];
  bool _opaque(int x, int y) => _at(x, y, 3) > 60;

  bool isKingInk(int x, int y) =>
      _opaque(x, y) && _at(x, y, 2) > 90 && _at(x, y, 0) < 90;
  bool isCutOut(int x, int y) =>
      _opaque(x, y) && _at(x, y, 0) > 90 && _at(x, y, 2) < 90;
  bool isFigure(int x, int y) =>
      _opaque(x, y) && _at(x, y, 1) > 90 && _at(x, y, 0) < 90;

  /// Device pixels of [test] inside [area] (logical).
  List<(int, int)> pixels(Rect area, bool Function(int, int) test) {
    final out = <(int, int)>[];
    final x0 = (area.left * _pixelRatio).floor().clamp(0, width - 1);
    final x1 = (area.right * _pixelRatio).ceil().clamp(0, width - 1);
    final y0 = (area.top * _pixelRatio).floor().clamp(0, height - 1);
    final y1 = (area.bottom * _pixelRatio).ceil().clamp(0, height - 1);
    for (var y = y0; y <= y1; y++) {
      for (var x = x0; x <= x1; x++) {
        if (test(x, y)) out.add((x, y));
      }
    }
    return out;
  }

  /// Where a king on [day] can be: the upper right of its cell and the gaps
  /// above and beside it.
  Rect kingZone(int day) {
    final cell = cells[day]!;
    return Rect.fromLTRB(
      cell.right - cell.width * 0.6,
      cell.top - 10,
      cell.right + 3.9,
      cell.center.dy,
    );
  }
}

Future<_Render> _render(
  WidgetTester tester, {
  required Size screen,
  required double textScale,
  required bool light,
}) async {
  tester.view
    ..physicalSize = screen * 3
    ..devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final base = light ? AppColors.light : AppColors.dark;
  final boundary = GlobalKey();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        availableYearsProvider.overrideWith((ref) => const [2026]),
        calendarMonthEventsProvider.overrideWith(
          (ref, args) async => _everyDayMajor(),
        ),
      ],
      child: MaterialApp(
        theme: (light ? AppTheme.lightTheme : AppTheme.darkTheme).copyWith(
          extensions: [
            base.copyWith(
              textPrimary: const Color(0xFF00FF00),
              accentText: const Color(0xFF0000FF),
              background: const Color(0xFFFF0000),
              surface: _clear,
              textSecondary: _clear,
              iconPrimary: _clear,
            ),
          ],
        ),
        home: Builder(
          builder: (context) {
            ResponsiveHelper.init(context);
            return MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(textScale)),
              child: Scaffold(
                backgroundColor: _clear,
                body: Align(
                  alignment: Alignment.topLeft,
                  child: RepaintBoundary(
                    key: boundary,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: SizedBox(
                        // The phone drawer's width.
                        width: 260.w,
                        child: SidebarMonthCalendar(
                          today: DateTime(2026, 9, 23, 15, 30),
                          onDaySelected: (_) {},
                          onOpenFullCalendar: () {},
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();

  final origin = tester.getTopLeft(find.byKey(boundary));
  final cells = <int, Rect>{
    for (var d = 1; d <= 30; d++)
      d: tester
          .getRect(
            find
                .descendant(
                  of: find.byKey(ValueKey('sidebar_day_2026-9-$d')),
                  matching: find.byType(DecoratedBox),
                )
                .first,
          )
          .shift(-origin),
  };

  late _Render render;
  await tester.runAsync(() async {
    final image =
        await (boundary.currentContext!.findRenderObject()!
                as RenderRepaintBoundary)
            .toImage(pixelRatio: _pixelRatio);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    render = _Render(
      bytes!.buffer.asUint8List(),
      image.width,
      image.height,
      cells,
    );
    image.dispose();
  });
  return render;
}

void main() {
  setUpAll(_loadInter);

  for (final (screen, textScale) in [
    (const Size(360, 800), 1.3),
    (const Size(393, 852), 1.0),
  ]) {
    for (final light in [true, false]) {
      final name =
          '${screen.width.toInt()}dp at ${textScale}x, '
          '${light ? 'light' : 'dark'}';

      testWidgets('$name: every king stands clear of every figure', (
        tester,
      ) async {
        final r = await _render(
          tester,
          screen: screen,
          textScale: textScale,
          light: light,
        );

        // Figures only: each cell pulled in past today's 1px edge and its
        // anti-aliasing. That edge is meant to be cut by the king.
        final figures = <(int, int)>[
          for (final cell in r.cells.values)
            ...r.pixels(cell.deflate(2), r.isFigure),
        ];
        expect(figures, isNotEmpty);

        for (final day in r.cells.keys) {
          final cell = r.cells[day]!;
          final zone = r.kingZone(day);
          final ink = r.pixels(zone, r.isKingInk);
          final king = [...ink, ...r.pixels(zone, r.isCutOut)];
          expect(ink, isNotEmpty, reason: 'day $day has its king');

          var nearest = double.infinity;
          for (final (kx, ky) in king) {
            for (final (fx, fy) in figures) {
              if ((fx - kx).abs() > 48 || (fy - ky).abs() > 48) continue;
              final dx = (fx - kx).toDouble();
              final dy = (fy - ky).toDouble();
              nearest = math.min(nearest, math.sqrt(dx * dx + dy * dy));
            }
          }
          // Cut-out edge included, the king never touches a figure of its
          // own day or of the day above.
          expect(
            nearest / _pixelRatio,
            greaterThanOrEqualTo(0.5),
            reason: 'day $day',
          );

          final right = ink.map((p) => p.$1).reduce(math.max) / _pixelRatio;
          final top = ink.map((p) => p.$2).reduce(math.min) / _pixelRatio;
          // At most half the gap to the next day, which it never reaches.
          expect(
            right - cell.right,
            lessThanOrEqualTo(2.0),
            reason: 'day $day',
          );
          // Standing on the corner: it rises past the cell's top edge.
          expect(top, lessThan(cell.top), reason: 'day $day');
        }
      });

      testWidgets('$name: the grid clip never shaves a king', (tester) async {
        final r = await _render(
          tester,
          screen: screen,
          textScale: textScale,
          light: light,
        );

        // Saturday the 5th sits in the top row and the last column, where
        // the clip is; the 16th sits in open grid. Same king, same ink.
        final edge = r.pixels(r.kingZone(5), r.isKingInk).length;
        final open = r.pixels(r.kingZone(16), r.isKingInk).length;
        expect(edge, closeTo(open, open * 0.03));
      });
    }
  }
}
