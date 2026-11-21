// What opening each popup over the board costs: the time from the tap to the
// popup's first frame (host build + layout + paint; the GPU's raster, where
// a backdrop blur is paid, is not in a widget test), the widgets rebuilt on
// that frame and how many of them belong to the page under the popup, and
// how many frames the open animation schedules before it rests.
//
//   flutter test --no-pub test/chessboard_surfaces_open_perf_test.dart
//
// Prints one PERF line per surface (median of the runs).
import 'package:chessever2/screens/chessboard/game_review/game_analysis_report_store.dart';
import 'package:chessever2/utils/foreground_task_scheduler.dart'
    show kForegroundHeavyRefreshDelay;
import 'package:chessground/chessground.dart' show Chessboard;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/chessboard_surfaces_harness.dart';

const _runs = 7;

/// The page's heavy widgets: a rebuild of any of them is the whole board
/// page (or its notation, board or app bar) rebuilt under the popup.
const _heavyPage = {
  'ChessBoardScreenNew',
  '_GamePage',
  '_AnalysisGameBody',
  '_BottomNavBar',
  '_MovesDisplay',
  '_AnalysisBoard',
};

/// Widgets that make up the page under a popup: a rebuild of any of them
/// (or below them) while a popup opens is work the popup caused the page.
const _pageRegions = {
  'ChessBoardScreenNew',
  '_GamePage',
  '_AnalysisGameBody',
  '_BottomNavBar',
  '_AppBar',
  '_MovesDisplay',
  '_AnalysisBoard',
  '_BoardWithSidebar',
  '_PrincipalVariationList',
};

/// The popups' own widgets: never counted as page work.
const _popupRegions = {
  '_GameDropdownOverlay',
  '_EventInfoSheet',
  '_NagPickerSheet',
  '_NotationActionSheet',
  '_DirectCommentSheet',
  'PopupMenuItem<String>',
};

class _OpenCost {
  int builds = 0;
  int pageBuilds = 0;
  final pageTypes = <String, int>{};
}

Future<_OpenCost> _countBuilds(Future<void> Function() run) async {
  final cost = _OpenCost();
  debugOnRebuildDirtyWidget = (element, _) {
    cost.builds++;
    String? region;
    final own = element.widget.runtimeType.toString();
    if (_popupRegions.contains(own)) return;
    if (_pageRegions.contains(own)) region = own;
    if (region == null) {
      element.visitAncestorElements((ancestor) {
        final name = ancestor.widget.runtimeType.toString();
        if (_popupRegions.contains(name)) {
          region = '';
          return false;
        }
        if (_pageRegions.contains(name)) {
          region = name;
          return false;
        }
        return true;
      });
    }
    final page = region;
    if (page != null && page.isNotEmpty) {
      cost.pageBuilds++;
      cost.pageTypes.update(own, (n) => n + 1, ifAbsent: () => 1);
    }
  };
  try {
    await run();
  } finally {
    debugOnRebuildDirtyWidget = null;
  }
  return cost;
}

double _median(List<double> values) {
  final sorted = [...values]..sort();
  return sorted[sorted.length ~/ 2];
}

int _medianInt(List<int> values) {
  final sorted = [...values]..sort();
  return sorted[sorted.length ~/ 2];
}

/// One surface's numbers over [_runs] opens.
class _SurfaceReport {
  _SurfaceReport(this.name);
  final String name;
  final openMs = <double>[];
  final builds = <int>[];
  final pageBuilds = <int>[];
  final frames = <int>[];

  /// The page's heavy widgets any open rebuilt, the unmeasured first one
  /// included: each comes after the surfaces opened before it, which is
  /// where a stale rebuild used to wait for the next popup.
  final heavyRebuilt = <String>{};

  double get medianOpenMs => _median(openMs);
  int get medianBuilds => _medianInt(builds);
  int get medianFrames => _medianInt(frames);

  String get line =>
      'PERF $name: open ${medianOpenMs.toStringAsFixed(2)} ms '
      '(min ${openMs.reduce((a, b) => a < b ? a : b).toStringAsFixed(2)}) | '
      'builds $medianBuilds | page builds ${_medianInt(pageBuilds)} | '
      'open frames $medianFrames | '
      'page rebuilt: ${heavyRebuilt.isEmpty ? 'none' : heavyRebuilt.join(', ')}';
}

/// Opens a surface [_runs] times: [open] triggers it and pumps its first
/// frame (timed), [close] takes it away again.
Future<_SurfaceReport> _measure(
  SurfacesBoard board,
  String name, {
  required Future<void> Function() open,
  required Future<void> Function() close,
  Future<void> Function()? before,
}) async {
  final report = _SurfaceReport(name);
  // Each surface opens on a quiet page. A route that really covers the
  // board (a sheet a profile can be pushed over) pauses its engine, and the
  // resume it queues on close re-evaluates the position (a whole-page
  // rebuild) some 700 ms later: that is the closed route's work, not the
  // next popup's.
  await board.tester.pump(kForegroundHeavyRefreshDelay);
  await board.settle();
  // One unmeasured open first: the first open of anything pays one-time
  // costs (code paths warming up) that no later open does. Every later open
  // comes straight after the one before closed, well inside that delay: a
  // menu or the move actions must leave nothing queued behind them.
  for (var run = -1; run < _runs; run++) {
    if (before != null) await before();
    final stopwatch = Stopwatch();
    final cost = await _countBuilds(() async {
      stopwatch.start();
      await open();
      stopwatch.stop();
    });
    final frames = await board.settle();
    if (run >= 0) {
      report.openMs.add(stopwatch.elapsedMicroseconds / 1000);
      report.builds.add(cost.builds);
      report.pageBuilds.add(cost.pageBuilds);
      report.frames.add(frames);
    }
    report.heavyRebuilt.addAll(cost.pageTypes.keys.where(_heavyPage.contains));
    await close();
    await board.settle();
  }
  // ignore: avoid_print
  print(report.line);
  return report;
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({
      'swipable_walkthrough_dont_show': true,
      'explorer_panel_walkthrough_dont_show': true,
      'like_walkthrough_dont_show': true,
      'board_pinch_coachmark_dont_show': true,
    });
    await Supabase.initialize(
      url: 'https://placeholder.supabase.co',
      publishableKey: 'placeholder-anon-key',
    );
    GameAnalysisReportStore.debugSetInstance(GameAnalysisReportStore.memory());
  });

  tearDownAll(GameAnalysisReportStore.debugResetInstance);

  testWidgets('opening every board popup', (tester) async {
    final board = await pumpSurfacesBoard(tester);
    final reports = <_SurfaceReport>[];
    Future<void> pop() async {
      board.navigator.pop();
      await tester.pump();
    }

    // The app-bar game switcher (an in-page panel, no route).
    reports.add(
      await _measure(
        board,
        'game switcher',
        open: () async {
          board.tapGameSwitcher();
          await tester.pump();
        },
        close: () async {
          await tester.tapAt(const Offset(8, 840));
          await tester.pump();
        },
      ),
    );

    // The app bar's three dots.
    reports.add(
      await _measure(
        board,
        'overflow menu',
        open: () async {
          await tester.tap(find.byIcon(Icons.more_vert).first);
          await tester.pump();
        },
        close: pop,
      ),
    );

    // A hold on the board.
    TestGesture? hold;
    reports.add(
      await _measure(
        board,
        'board menu',
        before: () async {
          final center = tester.getCenter(find.byType(Chessboard).first);
          hold = await tester.startGesture(center);
          await tester.pump(
            kLongPressTimeout - const Duration(milliseconds: 1),
          );
        },
        open: () async {
          // The hold's timer fires, the menu is pushed and built.
          await tester.pump(const Duration(milliseconds: 2));
          await tester.pump();
        },
        close: () async {
          await hold?.up();
          await tester.pump();
          board.navigator.pop();
          await tester.pump();
        },
      ),
    );

    // The event info sheet.
    reports.add(
      await _measure(
        board,
        'event info sheet',
        open: () async {
          await tester.tap(find.byTooltip('Event info').first);
          await tester.pump();
        },
        close: pop,
      ),
    );

    // A hold on a move: the move actions sheet.
    final move = find.textContaining(RegExp(r'^[NBRQK]?[a-h]?x?[a-h][1-8]'));
    reports.add(
      await _measure(
        board,
        'move actions sheet',
        before: () async {
          hold = await tester.startGesture(tester.getCenter(move.first));
          await tester.pump(
            kLongPressTimeout - const Duration(milliseconds: 1),
          );
        },
        open: () async {
          await tester.pump(const Duration(milliseconds: 2));
          await tester.pump();
        },
        close: () async {
          await hold?.up();
          await tester.pump();
          board.navigator.pop();
          await tester.pump();
        },
      ),
    );

    // From the move actions: the NAG picker.
    reports.add(
      await _measure(
        board,
        'NAG picker',
        before: () async {
          await tester.longPress(move.first);
          await board.settle();
        },
        open: () async {
          await tester.tap(find.text('Annotate (!? ± ∞ =)'));
          await tester.pump();
          // The picker is pushed after a microtask, on the next frame.
          await tester.pump();
        },
        close: pop,
      ),
    );

    // From the move actions: the comment editor page.
    reports.add(
      await _measure(
        board,
        'comment editor',
        before: () async {
          await tester.longPress(move.first);
          await board.settle();
        },
        open: () async {
          await tester.tap(find.text('Comment').first);
          await tester.pump();
        },
        close: () async {
          FocusManager.instance.primaryFocus?.unfocus();
          await tester.pump();
          board.navigator.pop();
          await tester.pump();
        },
      ),
    );

    expect(tester.takeException(), isNull);
    expect(reports, hasLength(7));
    for (final report in reports) {
      // The screen never rebuilds for a popup opening over it (it did for
      // every route: it read `ModalRoute.of`, ~400 widgets an open).
      expect(
        report.heavyRebuilt,
        isNot(contains('ChessBoardScreenNew')),
        reason: report.line,
      );
      switch (report.name) {
        case 'NAG picker':
          // Opening the picker first steps the board to the move: the
          // notation's update is intended.
          break;
        default:
          // Nothing of the page rebuilds as the popup opens: not on a
          // hold either (the board menu, the move actions), which used to
          // rebuild the board page, its board, notation host and bottom bar
          // (~200 widgets) after any earlier menu, from the engine and feed
          // resume the menu's close had queued.
          expect(report.heavyRebuilt, isEmpty, reason: report.line);
      }
    }
    await board.dispose();
  });

  // The root of the holds' page rebuild: every route pushed over the board
  // paused its engine and PiP feed, and its close queued a resume that,
  // some 700 ms later, re-evaluated the position and rebuilt the whole page
  // (board, notation host, bottom bar: ~200 widgets), on whatever frame was
  // next, the next popup's open included. A menu, a popover or the move
  // actions hang over a board that stays on screen and live: they pause
  // nothing, so their close leaves nothing behind.
  testWidgets('a menu or the move actions leave the page quiet after they '
      'close', (tester) async {
    final board = await pumpSurfacesBoard(tester);
    final move = find.textContaining(RegExp(r'^[NBRQK]?[a-h]?x?[a-h][1-8]'));
    Future<void> hold(Finder target) async {
      final gesture = await tester.startGesture(tester.getCenter(target.first));
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 20));
      await gesture.up();
      await tester.pump();
    }

    final surfaces = <String, Future<void> Function()>{
      'overflow menu': () => tester.tap(find.byIcon(Icons.more_vert).first),
      'board menu': () => hold(find.byType(Chessboard)),
      'move actions sheet': () => hold(move),
    };
    for (final MapEntry(key: name, value: open) in surfaces.entries) {
      await open();
      await board.settle();
      board.navigator.pop();
      await tester.pump();
      await board.settle();
      // Well past the resume's delay, frame by frame.
      final cost = await _countBuilds(() async {
        for (var i = 0; i < 90; i++) {
          await tester.pump(const Duration(milliseconds: 16));
        }
      });
      expect(
        cost.pageTypes.keys.where(_heavyPage.contains),
        isEmpty,
        reason: '$name: the page rebuilt after it closed',
      );
    }
    expect(tester.takeException(), isNull);
    await board.dispose();
  });
}
