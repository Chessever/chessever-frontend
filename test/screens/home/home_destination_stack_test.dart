import 'package:chessever2/screens/home/home_destination_stack.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('builds destinations lazily and visits each only once', (
    tester,
  ) async {
    final builds = <int>[];
    var currentIndex = 0;
    late StateSetter setHostState;

    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            setHostState = setState;
            return HomeDestinationStack(
              itemCount: 5,
              currentIndex: currentIndex,
              itemBuilder: (context, index) {
                builds.add(index);
                return Text('Destination $index');
              },
            );
          },
        ),
      ),
    );

    expect(builds, [0]);
    expect(find.text('Destination 0'), findsOneWidget);
    expect(find.text('Destination 1'), findsNothing);

    setHostState(() => currentIndex = 1);
    await tester.pump();
    expect(builds, [0, 1]);
    expect(find.text('Destination 0'), findsNothing);
    expect(find.text('Destination 1'), findsOneWidget);

    setHostState(() => currentIndex = 0);
    await tester.pump();
    expect(builds, [0, 1]);
    expect(find.text('Destination 0'), findsOneWidget);
  });

  testWidgets('retains destination state while disabling hidden semantics', (
    tester,
  ) async {
    var currentIndex = 0;
    late StateSetter setHostState;

    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            setHostState = setState;
            return HomeDestinationStack(
              itemCount: 2,
              currentIndex: currentIndex,
              itemBuilder:
                  (context, index) => _RetainedDestination(index: index),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('Increment 0'));
    await tester.pump();
    expect(find.text('Count 0: 1'), findsOneWidget);

    setHostState(() => currentIndex = 1);
    await tester.pump();
    expect(find.text('Count 0: 1'), findsNothing);
    expect(find.text('Count 1: 0'), findsOneWidget);

    final semantics = tester.ensureSemantics();
    expect(
      tester.getSemantics(find.text('Increment 1')).label,
      contains('Increment 1'),
    );
    semantics.dispose();

    setHostState(() => currentIndex = 0);
    await tester.pump();
    expect(find.text('Count 0: 1'), findsOneWidget);
  });
}

class _RetainedDestination extends StatefulWidget {
  const _RetainedDestination({required this.index});

  final int index;

  @override
  State<_RetainedDestination> createState() => _RetainedDestinationState();
}

class _RetainedDestinationState extends State<_RetainedDestination> {
  var count = 0;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text('Count ${widget.index}: $count'),
        TextButton(
          onPressed: () => setState(() => count++),
          child: Text('Increment ${widget.index}'),
        ),
      ],
    );
  }
}
