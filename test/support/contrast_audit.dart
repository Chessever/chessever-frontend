import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// One piece of text (or one icon glyph) whose ink does not clear its floor
/// against the surface it is actually painted on.
class ContrastMiss {
  const ContrastMiss({
    required this.text,
    required this.ink,
    required this.ground,
    required this.ratio,
    required this.floor,
    this.path = '',
  });

  /// The nearest named widgets above the run, for locating it.
  final String path;

  final String text;
  final Color ink;
  final Color ground;
  final double ratio;
  final double floor;

  @override
  String toString() =>
      '"$text" reads ${ratio.toStringAsFixed(2)}:1 (needs $floor) — '
      'ink ${_hex(ink)} on ${_hex(ground)}${path.isEmpty ? '' : '  [$path]'}';
}

String _hex(Color c) =>
    '#${c.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()}';

/// WCAG 2.x contrast of an opaque [fg] against an opaque [bg].
double auditContrast(Color fg, Color bg) {
  final l1 = fg.computeLuminance();
  final l2 = bg.computeLuminance();
  final hi = l1 > l2 ? l1 : l2;
  final lo = l1 > l2 ? l2 : l1;
  return (hi + 0.05) / (lo + 0.05);
}

/// Walks every [RichText] currently on screen (text and icon glyphs alike),
/// resolves the surface it is painted on from its ancestors' fills and
/// opacities, and returns every run that falls under WCAG AA: 4.5:1 for
/// body text, 3:1 for large text (≥24px, or ≥18.66px bold) and icons.
///
/// [fallbackGround] is used when no opaque fill sits above the text (the
/// scaffold background, normally). Runs whose ink resolves to (nearly)
/// transparent are skipped: they are not painted. [skip] drops runs by their
/// text, for glyphs that knowingly sit on a board or a photo; [ignoreWithin]
/// drops every run under a widget of one of those type names (a widget owned
/// and audited elsewhere).
List<ContrastMiss> auditTextContrast(
  WidgetTester tester, {
  required Color fallbackGround,
  bool Function(String text)? skip,
  Set<String> ignoreWithin = const {},
}) {
  final misses = <ContrastMiss>[];
  for (final element in find.byType(RichText).evaluate()) {
    final render = element.renderObject;
    if (render is! RenderParagraph || !render.hasSize) continue;
    if (render.size.isEmpty) continue;
    if (_isOffstage(element)) continue;
    if (ignoreWithin.isNotEmpty && _within(element, ignoreWithin)) continue;

    final layers = <_Layer>[];
    Color? base;
    element.visitAncestorElements((ancestor) {
      final widget = ancestor.widget;
      final opacity = _opacityOf(widget);
      if (opacity != null) {
        layers.add(_Layer.opacity(opacity));
        return true;
      }
      final fill = _fillOf(widget);
      if (fill == null) return true;
      if (fill.a >= 0.999) {
        base = fill;
        return false;
      }
      if (fill.a > 0.001) layers.add(_Layer.fill(fill));
      return true;
    });

    // Composite from the opaque base down toward the text.
    var ground = base ?? fallbackGround;
    var carried = 1.0;
    for (final layer in layers.reversed) {
      if (layer.opacity != null) {
        carried *= layer.opacity!;
      } else {
        final fill = layer.fill!;
        ground = Color.alphaBlend(
          fill.withValues(alpha: fill.a * carried),
          ground,
        );
      }
    }

    final isIcon = _isIconFont(render.text.style?.fontFamily);
    final owners = <String>[];
    element.visitAncestorElements((ancestor) {
      final name = ancestor.widget.runtimeType.toString();
      if (!name.startsWith('_') &&
          !_frameworkWidgets.contains(name) &&
          !name.contains('<')) {
        owners.add(name);
      }
      return owners.length < 7;
    });
    _visitRuns(render.text, null, (run, style) {
      final color = style?.color;
      if (color == null) return;
      if (style?.foreground != null) return;
      final alpha = color.a * carried;
      if (alpha < 0.05) return;
      final trimmed = run.trim();
      if (trimmed.isEmpty) return;
      if (skip != null && skip(trimmed)) return;
      final ink = Color.alphaBlend(color.withValues(alpha: alpha), ground);
      final size = style?.fontSize ?? 14;
      final bold = (style?.fontWeight?.value ?? 400) >= 700;
      final large = size >= 24 || (size >= 18.66 && bold);
      final floor = isIcon || _isIconFont(style?.fontFamily) || large
          ? 3.0
          : 4.5;
      final ratio = auditContrast(ink, ground);
      if (ratio + 0.005 < floor) {
        misses.add(
          ContrastMiss(
            text: trimmed,
            ink: ink,
            ground: ground,
            ratio: ratio,
            floor: floor,
            path: owners.join(' < '),
          ),
        );
      }
    });
  }
  return misses;
}

const Set<String> _frameworkWidgets = {
  'Text',
  'RichText',
  'Padding',
  'Center',
  'Align',
  'SizedBox',
  'Row',
  'Column',
  'Flex',
  'Expanded',
  'Flexible',
  'Container',
  'DecoratedBox',
  'ColoredBox',
  'ConstrainedBox',
  'DefaultTextStyle',
  'Semantics',
  'MergeSemantics',
  'IconTheme',
  'Icon',
  'Builder',
  'Stack',
  'Positioned',
  'LimitedBox',
  'ClipRRect',
  'ClipPath',
  'Opacity',
  'FittedBox',
  'AnimatedContainer',
  'Material',
  'InkWell',
  'GestureDetector',
  'Listener',
  'MouseRegion',
  'RepaintBoundary',
  'KeyedSubtree',
  'Transform',
  'AnimatedDefaultTextStyle',
  'ExcludeSemantics',
  'IgnorePointer',
  'PhysicalShape',
  'PhysicalModel',
  'CustomPaint',
  'ClipOval',
  'AspectRatio',
  'IntrinsicHeight',
  'IntrinsicWidth',
  'Wrap',
  'Baseline',
  'FractionallySizedBox',
  'UnconstrainedBox',
  'OverflowBox',
  'Offstage',
  'Visibility',
  'TickerMode',
  'FadeTransition',
  'ScaleTransition',
  'SlideTransition',
  'AnimatedBuilder',
  'ValueListenableBuilder',
};

class _Layer {
  _Layer.opacity(double this.opacity) : fill = null;
  _Layer.fill(Color this.fill) : opacity = null;

  final double? opacity;
  final Color? fill;
}

bool _isIconFont(String? family) =>
    family != null &&
    (family.contains('MaterialIcons') ||
        family.contains('CupertinoIcons') ||
        family.contains('Icons'));

bool _isOffstage(Element element) {
  var hidden = false;
  element.visitAncestorElements((ancestor) {
    final widget = ancestor.widget;
    if (widget is Offstage && widget.offstage) {
      hidden = true;
      return false;
    }
    if (widget is Visibility && !widget.visible) {
      hidden = true;
      return false;
    }
    return true;
  });
  return hidden;
}

bool _within(Element element, Set<String> names) {
  var inside = false;
  element.visitAncestorElements((ancestor) {
    if (names.contains(ancestor.widget.runtimeType.toString())) {
      inside = true;
      return false;
    }
    return true;
  });
  return inside;
}

double? _opacityOf(Widget widget) {
  if (widget is Opacity) return widget.opacity;
  if (widget is FadeTransition) return widget.opacity.value;
  return null;
}

Color? _fillOf(Widget widget) {
  if (widget is ColoredBox) return widget.color;
  if (widget is DecoratedBox) {
    final decoration = widget.decoration;
    if (decoration is BoxDecoration) {
      if (decoration.gradient != null) {
        final colors = decoration.gradient!.colors;
        return colors.isEmpty ? null : colors.first;
      }
      return decoration.color;
    }
    if (decoration is ShapeDecoration) return decoration.color;
    return null;
  }
  if (widget is PhysicalShape) return widget.color;
  if (widget is PhysicalModel) return widget.color;
  return null;
}

void _visitRuns(
  InlineSpan span,
  TextStyle? inherited,
  void Function(String run, TextStyle? style) onRun,
) {
  final style = inherited?.merge(span.style) ?? span.style;
  if (span is TextSpan) {
    final text = span.text;
    if (text != null && text.isNotEmpty) onRun(text, style);
    for (final child in span.children ?? const <InlineSpan>[]) {
      _visitRuns(child, style, onRun);
    }
  }
}

/// Fails with every miss listed, so one run shows the whole picture.
void expectNoContrastMisses(List<ContrastMiss> misses, {String? where}) {
  expect(
    misses,
    isEmpty,
    reason:
        '${where ?? 'surface'} has ${misses.length} run(s) under AA:\n'
        '${misses.map((m) => '  $m').join('\n')}',
  );
}
