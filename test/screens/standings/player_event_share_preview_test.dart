import 'dart:convert';

import 'package:chessever2/screens/standings/utils/player_event_share_utils.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/share_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final _onePixelPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
);

Future<void> _pumpPreview(
  WidgetTester tester, {
  required String? shareUrl,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.darkTheme,
      home: Builder(
        builder: (context) {
          ResponsiveHelper.init(context);
          return Scaffold(
            body: SharePreviewSheet(
              imageBytes: _onePixelPng,
              onShareImage: () async {},
              onShareLink: shareUrl == null ? null : () async {},
            ),
          );
        },
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('resolved event-player URL exposes Share Link in the preview', (
    tester,
  ) async {
    final shareUrl = buildPlayerEventShareUrl(
      hasEventContext: true,
      eventName: 'KazChess Masters',
      contextTourId: 'tour-456',
      contextTourSlug: 'kazchess-masters',
      playerFideId: 13730039,
    );

    await _pumpPreview(tester, shareUrl: shareUrl);

    expect(shareUrl, contains('/player/13730039'));
    expect(shareUrl, contains('/broadcast/'));
    expect(find.text('Share Link'), findsOneWidget);
    expect(find.text('Share Image'), findsOneWidget);
  });

  testWidgets(
    'archive fallback profile URL still exposes Share Link, never /broadcast/',
    (tester) async {
      final shareUrl = buildPlayerEventShareUrl(
        hasEventContext: true,
        canonicalEventId: 'TCh-RUS 2026',
        eventName: 'TCh-RUS 2026',
        tourId: 'TCh-RUS 2026',
        tourSlug: 'TCh-RUS 2026',
        playerFideId: 13730039,
      );

      await _pumpPreview(tester, shareUrl: shareUrl);

      expect(shareUrl, isNot(contains('/broadcast/')));
      expect(shareUrl, 'https://chessever.com/player/13730039');
      expect(find.text('Share Link'), findsOneWidget);
      expect(find.text('Share Image'), findsOneWidget);
    },
  );

  testWidgets('unresolved identity keeps Share Image and hides Share Link', (
    tester,
  ) async {
    final shareUrl = buildPlayerEventShareUrl(
      hasEventContext: true,
      eventName: 'Unknown event',
    );

    await _pumpPreview(tester, shareUrl: shareUrl);

    expect(shareUrl, isNull);
    expect(find.text('Share Link'), findsNothing);
    expect(find.text('Share Image'), findsOneWidget);
  });
}
