import 'dart:io';

import 'package:chessever2/screens/chessboard/chess_board_screen_new.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

void main() {
  test('board share captures and reuses the exact rendered board surface', () {
    final boardSource =
        File('lib/screens/chessboard/chess_board_screen_new.dart').readAsStringSync();
    final screenSource =
        File('lib/screens/chessboard/widgets/share_game_screen.dart').readAsStringSync();
    final overlaySource =
        File('lib/screens/chessboard/widgets/share_game_card_overlay.dart')
            .readAsStringSync();

    expect(
      boardSource,
      allOf(
        contains('captureBoundaryPng('),
        contains('boardShareBoundaryKeyProvider'),
      ),
      reason: 'The share action must capture the already-rendered board.',
    );
    expect(
      boardSource,
      contains('key: boardShareBoundaryKey'),
      reason: 'The capture boundary must include board overlays and annotations.',
    );
    expect(
      boardSource,
      contains('_resolveAppBarShareData(captureBoardImage: true)'),
      reason: 'The share action must request the board capture explicitly.',
    );
    expect(screenSource, contains('final Uint8List? boardImageBytes;'));
    expect(screenSource, contains('boardImageBytes: shareData.boardImageBytes'));
    expect(overlaySource, contains('final Uint8List? boardImageBytes;'));
    expect(
      overlaySource,
      allOf(contains('Image.memory('), contains('boardImageBytes!')),
      reason: 'The cleaned share card must reuse the exact board pixels.',
    );
  });

  testWidgets('share lookup resolves the same live board boundary key', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final otherContainer = ProviderContainer();
    addTearDown(otherContainer.dispose);
    final mountedKey = container.read(boardShareBoundaryKeyProvider);
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: RepaintBoundary(
            key: mountedKey,
            child: const SizedBox(
              width: 80,
              height: 80,
              child: ColoredBox(color: Colors.red),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final lookupKey = container.read(boardShareBoundaryKeyProvider);
    expect(identical(lookupKey, mountedKey), isTrue);
    expect(lookupKey.currentContext, isNotNull);
    expect(
      identical(otherContainer.read(boardShareBoundaryKeyProvider), mountedKey),
      isFalse,
      reason: 'Nested board screens must not reuse a GlobalKey.',
    );
  });
}
