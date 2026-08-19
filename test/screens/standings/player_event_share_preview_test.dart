import 'dart:convert';

import 'package:chessever2/screens/standings/utils/player_event_share_utils.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/share_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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

    final onePixelPng = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: Builder(
          builder: (context) {
            ResponsiveHelper.init(context);
            return Scaffold(
              body: SharePreviewSheet(
                imageBytes: onePixelPng,
                onShareImage: () async {},
                onShareLink: shareUrl == null ? null : () async {},
              ),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(shareUrl, contains('/player/13730039'));
    expect(find.text('Share Link'), findsOneWidget);
    expect(find.text('Share Image'), findsOneWidget);
  });
}
