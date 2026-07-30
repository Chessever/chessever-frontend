import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/fullscreen_image_viewer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Guards the yellow double-underline on fullscreen avatar initials:
/// Text without a Material ancestor during Heroine flight / no-photo path.
void main() {
  Widget host({
    required String? photoUrl,
    required String initials,
    String? title,
  }) {
    return MaterialApp(
      home: Builder(
        builder: (context) {
          ResponsiveHelper.init(context);
          return Scaffold(
            body: Builder(
              builder:
                  (inner) => TextButton(
                    onPressed:
                        () => showPlayerAvatarFullscreen(
                          context: inner,
                          photoUrl: photoUrl,
                          initials: initials,
                          heroTag: 'test_fullscreen_avatar',
                          title: title,
                        ),
                    child: const Text('open'),
                  ),
            ),
          );
        },
      ),
    );
  }

  /// Walks ancestors of [textFinder] and returns every [Material] above it.
  List<Material> materialsAbove(WidgetTester tester, Finder textFinder) {
    final element = tester.element(textFinder);
    final materials = <Material>[];
    element.visitAncestorElements((ancestor) {
      final widget = ancestor.widget;
      if (widget is Material) {
        materials.add(widget);
      }
      return true;
    });
    return materials;
  }

  testWidgets(
    'no-photo fullscreen initials Text has transparent Material ancestor',
    (tester) async {
      await tester.pumpWidget(
        host(photoUrl: null, initials: 'ab', title: 'GM'),
      );

      await tester.tap(find.text('open'));
      // Route push + Heroine / fade settle.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      final initialsText = find.text('AB');
      expect(initialsText, findsOneWidget);

      final materials = materialsAbove(tester, initialsText);
      expect(
        materials.any((m) => m.type == MaterialType.transparency),
        isTrue,
        reason:
            'Fullscreen initials must sit under MaterialType.transparency so '
            'Heroine flight does not paint yellow underlines',
      );

      // Title badge on the same surface also needs Material.
      final titleText = find.text('GM');
      expect(titleText, findsOneWidget);
      final titleMaterials = materialsAbove(tester, titleText);
      expect(
        titleMaterials.any((m) => m.type == MaterialType.transparency),
        isTrue,
        reason: 'Title badge Text must share the transparent Material ancestor',
      );
    },
  );

  testWidgets(
    'empty photoUrl fullscreen still paints initials under Material',
    (tester) async {
      await tester.pumpWidget(host(photoUrl: '', initials: 'xy'));

      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      final initialsText = find.text('XY');
      expect(initialsText, findsOneWidget);

      final materials = materialsAbove(tester, initialsText);
      expect(
        materials.any((m) => m.type == MaterialType.transparency),
        isTrue,
      );
    },
  );
}
