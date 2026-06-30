import 'package:chessever2/widgets/federation_flag.dart';
import 'package:flutter/material.dart';
import 'package:flutter_country_flags/flutter_country_flags.dart' as fcf;
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pumpFlag(WidgetTester tester, String? federation) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FederationFlag(federation: federation, width: 16, height: 12),
        ),
      ),
    );
  }

  testWidgets('renders a real flag when federation resolves', (tester) async {
    await pumpFlag(tester, 'CHN');

    expect(find.byType(fcf.FlutterCountryFlags), findsOneWidget);
  });

  test('visibility helper distinguishes FIDE from missing federations', () {
    expect(FederationFlag.hasVisibleFlag('FIDE'), isTrue);
    expect(FederationFlag.hasVisibleFlag('FID'), isTrue);
    expect(FederationFlag.hasVisibleFlag('CHN'), isTrue);
    expect(FederationFlag.hasVisibleFlag(''), isFalse);
    expect(FederationFlag.hasVisibleFlag('?'), isFalse);
    expect(FederationFlag.hasVisibleFlag('Unknown'), isFalse);
  });

  testWidgets('renders FIDE flag for explicit FIDE federation', (tester) async {
    await pumpFlag(tester, 'FIDE');

    expect(find.byType(Image), findsOneWidget);
    expect(find.byType(fcf.FlutterCountryFlags), findsNothing);
  });

  testWidgets('renders no placeholder for missing or sentinel federation', (
    tester,
  ) async {
    await pumpFlag(tester, '');
    expect(find.byType(Icon), findsNothing);
    expect(find.byType(Image), findsNothing);
    expect(find.byType(fcf.FlutterCountryFlags), findsNothing);

    await pumpFlag(tester, 'Unknown');
    expect(find.byType(Icon), findsNothing);
    expect(find.byType(Image), findsNothing);
    expect(find.byType(fcf.FlutterCountryFlags), findsNothing);
  });
}
