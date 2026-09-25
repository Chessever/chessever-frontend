import 'dart:async';

import 'package:chessever2/screens/for_you/discovery/widgets/discovery_common.dart';
import 'package:chessever2/screens/library/miniatures/miniatures_access.dart';
import 'package:chessever2/screens/my_likes/widgets/my_likes_archive_boundary.dart';
import 'package:chessever2/widgets/paywall/premium_paywall_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Pumps a button that runs [onTap] with a live context and ref, and returns
/// the context so a test can check what a gate does with it.
Future<BuildContext> _pumpHost(
  WidgetTester tester,
  Future<void> Function(BuildContext context, WidgetRef ref) onTap,
) async {
  late BuildContext host;
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        home: Consumer(
          builder: (context, ref, _) {
            host = context;
            return Scaffold(
              body: TextButton(
                onPressed: () => onTap(context, ref),
                child: const Text('Go'),
              ),
            );
          },
        ),
      ),
    ),
  );
  return host;
}

void main() {
  group('feature id for the paywall analytics', () {
    test('passes the fixed snake_case ids the gates send', () {
      for (final id in [
        kMiniaturesArchiveFeatureId,
        kMyLikesHistoryFeatureId,
        kMyLikesExportFeatureId,
        'most_liked_rankings',
        'smart_event_create',
        'game_review',
        'opening_tree',
        'streaks_filters',
      ]) {
        expect(paywallFeatureIdForAnalytics(id), id, reason: id);
      }
    });

    test('drops anything that could be user, player or account data', () {
      for (final leak in [
        'Magnus Carlsen',
        'someone@example.com',
        '3f2a9c1e-5b7d-4e8a-9c3f-1a2b3c4d5e6f',
        '1503014',
        'player_1503014/extra',
        'Miniatures_Archive',
        '',
        'a' * 65,
      ]) {
        expect(paywallFeatureIdForAnalytics(leak), isNull, reason: leak);
      }
      expect(paywallFeatureIdForAnalytics(null), isNull);
    });
  });

  group('return target for the paywall analytics', () {
    test('passes fixed route-like names', () {
      for (final target in [
        discoveryReturnTo('most_liked'),
        kMiniaturesReturnTo,
        kMyLikesReturnTo,
        'for_you/my_space',
        'streaks',
      ]) {
        expect(paywallReturnToForAnalytics(target), target, reason: target);
      }
    });

    test('drops ids and malformed paths', () {
      for (final bad in [
        'player/1503014',
        '/for_you',
        'for_you/',
        'for_you//discovery',
        'for_you/Discovery',
        'event?id=42',
      ]) {
        expect(paywallReturnToForAnalytics(bad), isNull, reason: bad);
      }
    });
  });

  group('resumePremiumAction', () {
    testWidgets('with no action it answers true at once', (tester) async {
      final context = await _pumpHost(tester, (_, __) async {});
      expect(await resumePremiumAction(context), isTrue);
    });

    testWidgets('runs the intended action and answers true', (tester) async {
      final context = await _pumpHost(tester, (_, __) async {});
      var resumed = 0;

      final result = await resumePremiumAction(
        context,
        onEntitled: () => resumed++,
      );

      expect(result, isTrue);
      expect(resumed, 1);
    });

    testWidgets('waits for the celebration to close before resuming', (
      tester,
    ) async {
      final context = await _pumpHost(tester, (_, __) async {});
      final celebration = Completer<void>();
      var resumed = 0;

      final pending = resumePremiumAction(
        context,
        onEntitled: () => resumed++,
        after: celebration.future,
      );
      await tester.pump();
      expect(resumed, 0, reason: 'the celebration is still on screen');

      celebration.complete();
      expect(await pending, isTrue);
      expect(resumed, 1);
    });

    testWidgets('a failed celebration never strands the action', (
      tester,
    ) async {
      final context = await _pumpHost(tester, (_, __) async {});
      var resumed = 0;

      await resumePremiumAction(
        context,
        onEntitled: () => resumed++,
        after: Future<void>.error(StateError('no navigator')),
      );

      expect(resumed, 1);
    });

    testWidgets('skips the action once the originating screen is gone', (
      tester,
    ) async {
      final context = await _pumpHost(tester, (_, __) async {});
      await tester.pumpWidget(const SizedBox());
      var resumed = 0;

      final result = await resumePremiumAction(
        context,
        onEntitled: () => resumed++,
      );

      expect(result, isTrue, reason: 'the viewer is still entitled');
      expect(resumed, 0);
    });
  });

  testWidgets(
    'requirePremiumGuard resumes the intended action when it passes',
    (tester) async {
      // Tests run as a debug build, where the guard always passes: this pins
      // that the resume action rides along with the pass.
      bool? allowed;
      var resumed = 0;
      await _pumpHost(tester, (context, ref) async {
        allowed = await requirePremiumGuard(
          context,
          ref,
          featureId: kMiniaturesArchiveFeatureId,
          returnTo: kMiniaturesReturnTo,
          onEntitled: () => resumed++,
        );
      });

      await tester.tap(find.text('Go'));
      await tester.pump();

      expect(allowed, isTrue);
      expect(resumed, 1);
    },
  );
}
