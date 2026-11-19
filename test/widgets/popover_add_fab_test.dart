import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/glass_surface.dart';
import 'package:chessever2/widgets/ink_fab.dart';
import 'package:chessever2/widgets/popover_add_fab.dart';
import 'package:chessever2/widgets/press_spring.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _add = ValueKey<String>('popover_fab_add');
const _save = ValueKey<String>('popover_fab_save');

Widget _host({required bool saving, bool reduceMotion = false}) {
  return MaterialApp(
    theme: AppTheme.darkTheme,
    home: Builder(
      builder: (context) {
        ResponsiveHelper.init(context);
        return MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(disableAnimations: reduceMotion),
          child: Scaffold(
            body: const SizedBox.expand(),
            floatingActionButton: InkFabStack(
              children: [
                PopoverAddFab<int>(
                  label: 'Add to My Space',
                  saveLabel: 'Save My Space',
                  onSave: saving ? () {} : null,
                  choices: const [
                    PopoverAddChoice(
                      leading: Icon(Icons.storage_rounded),
                      label: 'Database',
                      value: 1,
                    ),
                  ],
                  onPicked: (_) {},
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

void main() {
  setUp(() {
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

  testWidgets('the regular floating disc, its glyph in the floating glyph '
      'box, with a tooltip and the floating press', (tester) async {
    await tester.pumpWidget(_host(saving: false));
    await tester.pumpAndSettle();

    final fab = find.byType(PopoverAddFab<int>);
    expect(tester.getSize(fab), Size.square(InkFabSize.regular.side));
    expect(
      tester.getSize(find.byType(GlassSurface)),
      Size.square(InkFabSize.regular.disc),
    );
    // The "+" fills the box every floating button hands its glyph.
    expect(
      tester.getSize(find.byKey(_add)),
      Size.square(InkFabSize.regular.disc * InkFab.glyphFraction),
    );
    expect(find.byKey(_save), findsNothing);
    expect(find.byTooltip('Add to My Space'), findsOneWidget);
    expect(
      tester.widget<PressSpring>(find.byType(PressSpring)).pressedScale,
      0.9,
    );
    // Its swap rides a spring, not a curved switcher.
    expect(find.byType(AnimatedSwitcher), findsNothing);
  });

  testWidgets('saving crosses the "+" into a painted check on a spring and '
      'ends with only the check', (tester) async {
    await tester.pumpWidget(_host(saving: false));
    await tester.pumpAndSettle();
    final fabRect = tester.getRect(find.byType(PopoverAddFab<int>));

    await tester.pumpWidget(_host(saving: true));
    await tester.pump(const Duration(milliseconds: 60));
    // Mid-swap both marks are there, neither at full strength.
    expect(find.byKey(_add), findsOneWidget);
    expect(find.byKey(_save), findsOneWidget);

    await tester.pumpAndSettle();
    expect(find.byKey(_add), findsNothing);
    expect(find.byKey(_save), findsOneWidget);
    // Drawn, not a font glyph, in the same box as the "+".
    expect(
      find.descendant(
        of: find.byType(PopoverAddFab<int>),
        matching: find.byType(Icon),
      ),
      findsNothing,
    );
    expect(
      tester.getSize(find.byKey(_save)),
      Size.square(InkFabSize.regular.disc * InkFab.glyphFraction),
    );
    expect(find.byTooltip('Save My Space'), findsOneWidget);
    // Same button, same place.
    expect(tester.getRect(find.byType(PopoverAddFab<int>)), fabRect);

    await tester.pumpWidget(_host(saving: false));
    await tester.pumpAndSettle();
    expect(find.byKey(_save), findsNothing);
    expect(find.byKey(_add), findsOneWidget);
  });

  testWidgets('with reduced motion the marks swap at once', (tester) async {
    await tester.pumpWidget(_host(saving: false, reduceMotion: true));
    await tester.pump();
    await tester.pumpWidget(_host(saving: true, reduceMotion: true));
    await tester.pump();
    expect(find.byKey(_add), findsNothing);
    expect(find.byKey(_save), findsOneWidget);
  });
}
