import 'dart:convert';

import 'package:chessever2/screens/standings/utils/scorecard_name_actions.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/share_card.dart';
import 'package:chessever2/widgets/player_name_share_target.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child) {
  return MaterialApp(
    theme: AppTheme.darkTheme,
    home: Builder(
      builder: (context) {
        ResponsiveHelper.init(context);
        return Scaffold(body: child);
      },
    ),
  );
}

final _onePixelPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
);

class _MemoryCoachmarkStore implements ScorecardNameCoachmarkStore {
  bool seen = false;
  int writes = 0;

  @override
  Future<bool> hasSeen() async => seen;

  @override
  Future<void> markSeen() async {
    seen = true;
    writes += 1;
  }
}

void main() {
  testWidgets(
    'tapping the player name opens the existing share preview directly',
    (tester) async {
      var shareCalls = 0;

      await tester.pumpWidget(
        _host(
          Builder(
            builder: (context) {
              return PlayerNameShareTarget(
                playerName: 'Vaishali Rameshbabu',
                onShare:
                    () => showShareImagePreview(
                      context,
                      imageBytes: _onePixelPng,
                      onShareImage: () async => shareCalls += 1,
                      onShareLink: () async {},
                    ),
                child: const Text('Vaishali Rameshbabu'),
              );
            },
          ),
        ),
      );

      expect(find.text('Share Preview'), findsNothing);
      expect(find.byType(PopupMenuButton), findsNothing);

      await tester.tap(find.text('Vaishali Rameshbabu'));
      await tester.pumpAndSettle();

      expect(find.text('Share Preview'), findsOneWidget);
      expect(find.text('Share Image'), findsOneWidget);
      expect(find.text('Share Link'), findsOneWidget);
      expect(find.byIcon(Icons.share), findsNothing);
      expect(find.byIcon(Icons.arrow_outward_rounded), findsNothing);
      expect(find.byType(PopupMenuButton), findsNothing);
    },
  );

  testWidgets('name tap does not insert an intermediate action sheet', (
    tester,
  ) async {
    var shareCalls = 0;

    await tester.pumpWidget(
      _host(
        PlayerNameShareTarget(
          playerName: 'Vaishali Rameshbabu',
          onShare: () async => shareCalls += 1,
          child: const Text('Vaishali Rameshbabu'),
        ),
      ),
    );

    await tester.tap(find.text('Vaishali Rameshbabu'));
    await tester.pump();

    expect(shareCalls, 1);
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.byType(PopupMenuButton), findsNothing);
  });

  testWidgets('player name share target is exposed as an accessible button', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        PlayerNameShareTarget(
          playerName: 'Vaishali Rameshbabu',
          onShare: () async {},
          child: const Text('Vaishali Rameshbabu'),
        ),
      ),
    );

    final semantics = tester.getSemantics(find.byType(PlayerNameShareTarget));
    expect(semantics.label, contains('Share Vaishali Rameshbabu'));
    expect(semantics.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
  });

  testWidgets('does not restore a permanent share-icon affordance', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        PlayerNameShareTarget(
          playerName: 'Vaishali Rameshbabu',
          onShare: () async {},
          child: const Text('Vaishali Rameshbabu'),
        ),
      ),
    );

    expect(find.byIcon(Icons.share), findsNothing);
    expect(find.byIcon(Icons.share_outlined), findsNothing);
    expect(find.byIcon(Icons.ios_share), findsNothing);
    expect(find.byIcon(Icons.arrow_outward_rounded), findsNothing);
  });

  testWidgets('shows the coachmark once and persists only after display', (
    tester,
  ) async {
    final store = _MemoryCoachmarkStore();
    final tracker = ScorecardNameCoachmarkTracker(store);
    const message = 'Tap the player’s name to share this profile.';

    await tester.pumpWidget(
      _host(
        PlayerNameShareTarget(
          playerName: 'Vaishali Rameshbabu',
          onShare: () async {},
          coachmarkMessage: message,
          coachmarkTracker: tracker,
          child: const Text('Vaishali Rameshbabu'),
        ),
      ),
    );

    await tester.pump();
    await tester.pump();

    expect(store.writes, 1);
    expect(find.text(message), findsOneWidget);

    await tester.pumpWidget(
      _host(
        PlayerNameShareTarget(
          playerName: 'Vaishali Rameshbabu',
          onShare: () async {},
          coachmarkMessage: message,
          coachmarkTracker: tracker,
          child: const Text('Vaishali Rameshbabu'),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(store.writes, 1);
  });
}
