import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/page_back_float.dart';
import 'package:chessever2/widgets/scroll_chrome.dart';
import 'package:chessever2/widgets/search_mode/search_mode.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final Finder _float = find.byKey(const ValueKey('page_back_float'));

/// A pushed page whose header (with its back) folds away as its list
/// scrolls, and the floating back over it.
class _Page extends StatefulWidget {
  const _Page({required this.onController});

  final ValueChanged<ScrollChromeController> onController;

  @override
  State<_Page> createState() => _PageState();
}

class _PageState extends State<_Page> with SingleTickerProviderStateMixin {
  late final ScrollChromeController chrome = ScrollChromeController(
    vsync: this,
  );

  @override
  void initState() {
    super.initState();
    widget.onController(chrome);
  }

  @override
  void dispose() {
    chrome.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.passthrough,
        children: [
          Column(
            children: [
              SizedBox(height: MediaQuery.viewPaddingOf(context).top + 4.h),
              CollapsingChrome(
                controller: chrome,
                child: const SizedBox(
                  height: 120,
                  width: double.infinity,
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: PageBackButton(key: ValueKey('header_back')),
                  ),
                ),
              ),
              Expanded(
                child: ScrollChromeRegion(
                  controller: chrome,
                  child: ListView.builder(
                    itemCount: 80,
                    itemBuilder: (context, i) =>
                        SizedBox(height: 60, child: Text('row $i')),
                  ),
                ),
              ),
            ],
          ),
          PageBackFloat(controller: chrome),
        ],
      ),
    );
  }
}

Future<(ScrollChromeController, NavigatorState)> _pump(
  WidgetTester tester,
) async {
  late ScrollChromeController chrome;
  final navigator = GlobalKey<NavigatorState>();
  await tester.pumpWidget(
    MaterialApp(
      navigatorKey: navigator,
      home: const Scaffold(body: Text('home')),
    ),
  );
  navigator.currentState!.push(
    MaterialPageRoute<void>(
      builder: (_) => _Page(onController: (c) => chrome = c),
    ),
  );
  await tester.pumpAndSettle();
  return (chrome, navigator.currentState!);
}

void main() {
  setUp(() => ResponsiveHelper.initFromSize(const Size(393, 852)));

  testWidgets('with the header shown there is nothing extra on the page', (
    tester,
  ) async {
    await _pump(tester);
    expect(_float, findsNothing);
    expect(find.byKey(const ValueKey('header_back')), findsOneWidget);
  });

  testWidgets('with the header folded away, a back stays in reach where its '
      'chevron was, and goes back', (tester) async {
    final (chrome, navigator) = await _pump(tester);
    await tester.drag(find.text('row 3'), const Offset(0, -400));
    await tester.pumpAndSettle();
    expect(chrome.value, 0);

    expect(_float, findsOneWidget);
    final disc = tester.getCenter(_float);
    expect(disc.dx, closeTo(SearchHeaderMetrics.backGlyphCenter, 0.5));
    expect(disc.dy, closeTo(4.h + SearchHeaderMetrics.backTarget / 2, 0.5));
    expect(find.bySemanticsLabel('Back'), findsWidgets);

    await tester.tap(_float);
    await tester.pumpAndSettle();
    expect(navigator.canPop(), isFalse);
    expect(find.text('home'), findsOneWidget);
  });

  testWidgets('it leaves as the header comes home', (tester) async {
    final (chrome, _) = await _pump(tester);
    await tester.drag(find.text('row 3'), const Offset(0, -400));
    await tester.pumpAndSettle();
    expect(_float, findsOneWidget);

    chrome.show();
    await tester.pumpAndSettle();
    expect(chrome.value, 1);
    expect(_float, findsNothing);
  });

  test('presence follows the fold: none while the header\'s chevron is half '
      'in view or more, all of it with the header gone', () {
    expect(PageBackFloat.presence(1), 0);
    expect(PageBackFloat.presence(0.5), 0);
    expect(PageBackFloat.presence(0.25), closeTo(0.5, 1e-9));
    expect(PageBackFloat.presence(0), 1);
  });
}
