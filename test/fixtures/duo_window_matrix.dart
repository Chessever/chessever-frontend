import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Logical sizes verified against the installed iPhone Duo simulator profile:
/// outer 1398×2034 and inner 2007×2853 physical pixels, both at 3× scale.
/// Test data only; production layout does not identify devices from these sizes.
/// All four states must work as cold starts and as both ends of transitions.
class DuoWindowCase {
  const DuoWindowCase(this.name, this.size, {required this.unfolded});

  final String name;
  final Size size;
  final bool unfolded;

  bool get landscape => size.width > size.height;
}

const duoWindowCases = <DuoWindowCase>[
  DuoWindowCase('folded portrait', Size(466, 678), unfolded: false),
  DuoWindowCase('folded landscape', Size(678, 466), unfolded: false),
  DuoWindowCase('unfolded portrait', Size(669, 951), unfolded: true),
  DuoWindowCase('unfolded landscape', Size(951, 669), unfolded: true),
];

typedef DuoWindowTransition = ({DuoWindowCase from, DuoWindowCase to});

Iterable<DuoWindowTransition> get duoWindowTransitions sync* {
  for (final from in duoWindowCases) {
    for (final to in duoWindowCases) {
      if (!identical(from, to)) yield (from: from, to: to);
    }
  }
}

/// Conservative safe-edge fixtures in both landscape directions. These are
/// stress inputs, not a prediction of the native device's reported insets.
/// Preserve an open keyboard while updating the physical window and safe area.
void applyDuoWindow(
  WidgetTester tester,
  DuoWindowCase window, {
  bool mirrorInsets = false,
}) {
  final dpr = tester.view.devicePixelRatio;
  final keyboardOpen = tester.view.viewInsets.bottom > 0;
  final left = window.landscape ? (mirrorInsets ? 20.0 : 62.0) : 0.0;
  final right = window.landscape ? (mirrorInsets ? 62.0 : 20.0) : 0.0;
  final top = window.landscape ? 0.0 : 59.0;
  final bottom = window.landscape ? 21.0 : 34.0;
  tester.view
    ..physicalSize = window.size * dpr
    ..viewPadding = FakeViewPadding(
      left: left * dpr,
      right: right * dpr,
      top: top * dpr,
      bottom: bottom * dpr,
    )
    ..padding = FakeViewPadding(
      left: left * dpr,
      right: right * dpr,
      top: top * dpr,
      bottom: keyboardOpen ? 0 : bottom * dpr,
    );
}
