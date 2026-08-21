import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/search/enhanced_rounded_search_bar.dart';
import 'package:chessever2/widgets/search/recent_searches_provider.dart';
import 'package:chessever2/widgets/stable_height_slot.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class _MemoryStorage implements RecentSearchStorage {
  @override
  Future<String?> read() async => null;

  @override
  Future<void> write(String value) async {}
}

/// Counts `performLayout` calls on whatever it wraps.
class _CountLayouts extends SingleChildRenderObjectWidget {
  const _CountLayouts({required this.onLayout, required Widget super.child});

  final VoidCallback onLayout;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderCountLayouts(onLayout);

  @override
  void updateRenderObject(BuildContext context, _RenderCountLayouts renderer) {
    renderer.onLayout = onLayout;
  }
}

class _RenderCountLayouts extends RenderProxyBox {
  _RenderCountLayouts(this.onLayout);

  VoidCallback onLayout;

  @override
  void performLayout() {
    onLayout();
    super.performLayout();
  }
}

/// The events screen's shape: a search bar whose panel unrolls downward, over
/// a tab that fills the rest of the column.
class _Harness extends StatefulWidget {
  const _Harness({required this.onPageLayout, required this.stabilise});

  final VoidCallback onPageLayout;
  final bool stabilise;

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  final controller = TextEditingController();
  final focusNode = FocusNode();
  final pageController = PageController();

  @override
  void dispose() {
    focusNode.dispose();
    controller.dispose();
    pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ResponsiveHelper.init(context);
    final tab = _CountLayouts(
      onLayout: widget.onPageLayout,
      child: PageView.builder(
        controller: pageController,
        itemCount: 1,
        itemBuilder:
            (context, _) => ListView.builder(
              itemCount: 40,
              itemBuilder:
                  (context, i) => SizedBox(height: 90, child: Text('event $i')),
            ),
      ),
    );

    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: Column(
        children: [
          const SizedBox(height: 24),
          EnhancedRoundedSearchBar(
            controller: controller,
            focusNode: focusNode,
          ),
          const SizedBox(height: 16),
          Expanded(
            child: widget.stabilise ? StableHeightSlot(child: tab) : tab,
          ),
        ],
      ),
    );
  }
}

Future<int> _layoutsDuringMorph(
  WidgetTester tester, {
  required bool stabilise,
}) async {
  var layouts = 0;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        recentSearchStorageProvider.overrideWithValue(_MemoryStorage()),
      ],
      child: MaterialApp(
        theme: AppTheme.darkTheme,
        home: _Harness(onPageLayout: () => layouts++, stabilise: stabilise),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));

  layouts = 0;
  await tester.tap(find.byType(TextField));
  for (var i = 0; i < 45; i++) {
    await tester.pump(const Duration(milliseconds: 8));
  }
  return layouts;
}

void main() {
  testWidgets('the unrolling panel does not re-lay-out the tab beneath it', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    // The panel grows by taking layout space, so without a stable slot the
    // whole tab — PageView, viewport, sliver — re-lays-out once per frame of
    // the morph. That is the animation paying for itself in dropped frames.
    final unstable = await _layoutsDuringMorph(tester, stabilise: false);
    expect(
      unstable,
      greaterThan(10),
      reason: 'the harness no longer reproduces the relayout it guards against',
    );

    final stable = await _layoutsDuringMorph(tester, stabilise: true);
    expect(
      stable,
      0,
      reason: 'the tab re-laid-out $stable times across the morph',
    );
  });
}
