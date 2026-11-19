import 'package:chessever2/screens/home/home_screen.dart';
import 'package:chessever2/widgets/scroll_chrome.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Android's back on the Home shell ([HomeBackScope]): hidden bars come back,
/// then Home opens, then the app closes. What the page holds back with (a
/// PopScope of its own, a drawer) answers first and alone.
void main() {
  late ScrollChromeController chrome;
  late List<String> systemCalls;
  late int homeOpens;

  setUp(() {
    chrome = ScrollChromeController(vsync: const TestVSync());
    systemCalls = [];
    homeOpens = 0;
  });

  tearDown(() => chrome.dispose());

  Future<void> pumpShell(
    WidgetTester tester, {
    required bool atHome,
    required Widget page,
  }) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        systemCalls.add(call.method);
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: HomeBackScope(
          chrome: chrome,
          atHome: atHome,
          onGoHome: () => homeOpens++,
          child: page,
        ),
      ),
    );
  }

  Future<void> back(WidgetTester tester) async {
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
  }

  bool appClosed() => systemCalls.contains('SystemNavigator.pop');

  testWidgets('hidden bars come back, then Home, then the app closes', (
    tester,
  ) async {
    await pumpShell(tester, atHome: false, page: const Text('Feed'));
    chrome.hide(animate: false);
    await tester.pump();

    await back(tester);
    expect(chrome.value, 1, reason: 'the first back brings the bars back');
    expect(homeOpens, 0);
    expect(appClosed(), isFalse);

    await back(tester);
    expect(homeOpens, 1, reason: 'with the bars in view, back opens Home');
    expect(appClosed(), isFalse);

    // On Home with its bars hidden, back brings them back first.
    await pumpShell(tester, atHome: true, page: const Text('Home'));
    chrome.hide(animate: false);
    await tester.pump();
    await back(tester);
    expect(chrome.value, 1);
    expect(appClosed(), isFalse);

    await back(tester);
    expect(appClosed(), isTrue, reason: 'Home with its bars closes the app');
    expect(homeOpens, 1);
  });

  testWidgets(
    'a page PopScope refusing on Home answers alone (My Space Edit)',
    (tester) async {
      var editing = true;
      var editBacks = 0;
      late StateSetter setPage;
      await pumpShell(
        tester,
        atHome: true,
        page: StatefulBuilder(
          builder: (context, setState) {
            setPage = setState;
            return PopScope(
              canPop: !editing,
              onPopInvokedWithResult: (didPop, _) {
                if (didPop) return;
                editBacks++;
                setState(() => editing = false);
              },
              child: Text(editing ? 'Editing' : 'My Space'),
            );
          },
        ),
      );

      await back(tester);
      expect(editBacks, 1);
      expect(find.text('My Space'), findsOneWidget);
      expect(
        homeOpens,
        0,
        reason: 'Home re-selected would scroll My Space to its top',
      );
      expect(chrome.value, 1);
      expect(appClosed(), isFalse);

      // Edit left, the next back is the shell's again: the app closes.
      setPage(() {});
      await tester.pump();
      await back(tester);
      expect(editBacks, 1);
      expect(appClosed(), isTrue);
    },
  );

  testWidgets('a page PopScope refusing elsewhere leaves bars and section', (
    tester,
  ) async {
    var searchBacks = 0;
    await pumpShell(
      tester,
      atHome: false,
      page: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) searchBacks++;
        },
        child: const Text('Searching'),
      ),
    );
    chrome.hide(animate: false);
    await tester.pump();

    await back(tester);
    expect(searchBacks, 1);
    expect(chrome.value, 0, reason: 'the bars stay away under a search');
    expect(homeOpens, 0);
    expect(appClosed(), isFalse);
  });

  testWidgets('back closes an open drawer and nothing else (Botvinnik)', (
    tester,
  ) async {
    final scaffold = GlobalKey<ScaffoldState>();
    await pumpShell(
      tester,
      atHome: false,
      page: Scaffold(
        key: scaffold,
        drawer: const Drawer(child: Text('Conversations')),
        body: const Text('Botvinnik'),
      ),
    );

    scaffold.currentState!.openDrawer();
    await tester.pumpAndSettle();
    expect(find.text('Conversations'), findsOneWidget);

    await back(tester);
    expect(find.text('Conversations'), findsNothing);
    expect(homeOpens, 0, reason: 'the drawer takes the back, not the shell');
    expect(appClosed(), isFalse);

    await back(tester);
    expect(homeOpens, 1);
  });

  testWidgets('a drawer open on Home closes before the app does', (
    tester,
  ) async {
    final scaffold = GlobalKey<ScaffoldState>();
    await pumpShell(
      tester,
      atHome: true,
      page: Scaffold(
        key: scaffold,
        drawer: const Drawer(child: Text('Drawer')),
        body: const Text('Home'),
      ),
    );
    scaffold.currentState!.openDrawer();
    await tester.pumpAndSettle();

    await back(tester);
    expect(find.text('Drawer'), findsNothing);
    expect(appClosed(), isFalse);

    await back(tester);
    expect(appClosed(), isTrue);
  });
}
