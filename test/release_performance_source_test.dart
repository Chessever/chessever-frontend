import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('release app does not install an app-wide render-tree capture loop', () {
    final mainSource = File('lib/main.dart').readAsStringSync();
    final pubspecSource = File('pubspec.yaml').readAsStringSync();

    expect(
      mainSource,
      isNot(contains('Clarity.initialize(')),
      reason:
          'clarity_flutter 1.4.2 captures every changed RenderView once per '
          'second by repainting the full render tree on Flutter\'s UI isolate.',
    );
    expect(
      pubspecSource,
      isNot(contains('clarity_flutter:')),
      reason:
          'Keep the full-tree session recorder out of release artifacts so it '
          'cannot be re-enabled accidentally by startup initialization.',
    );
  });

  test('iOS PiP uses actual piece assets and does not churn frames behind covered routes', () {
    final pipSource =
        File('ios/Runner/ChessPipController.swift').readAsStringSync();
    final boardSource =
        File(
          'lib/screens/chessboard/chess_board_screen_new.dart',
        ).readAsStringSync();
    final didPushNext = boardSource.substring(
      boardSource.indexOf('void didPushNext()'),
      boardSource.indexOf('void didPopNext()'),
    );

    expect(pipSource, contains('cachedPixelBuffer'));
    expect(
      pipSource,
      contains('piece_sets/\\(pieceSet)/\\(pieceCode).webp'),
      reason:
          'Chessground ships WebP piece assets. A PNG lookup silently falls '
          'back to letter glyphs in native PiP.',
    );
    expect(
      pipSource,
      contains('CGSize(width: 1280, height: 720)'),
      reason:
          'A landscape PiP canvas keeps the board compact instead of letting a '
          'square source consume the phone screen.',
    );
    expect(
      pipSource,
      isNot(contains('makeSampleBuffer(image: image)')),
      reason:
          'The foreground PiP keepalive must reuse its converted pixel buffer '
          'instead of allocating and drawing 720x720 pixels every second.',
    );
    expect(
      didPushNext,
      contains('PipService.instance.clearActiveGame()'),
      reason:
          'A covered board must stop its native foreground render loop; the '
          'board re-primes PiP when its route becomes visible again.',
    );
    expect(
      boardSource,
      contains('if (_isRouteCovered) return;'),
      reason:
          'Realtime/provider emissions must not restart PiP priming behind a '
          'covered board route after the one-time clear.',
    );
  });

  test('player opening-tree polling is owned by visible consumers', () {
    final providerSource =
        File(
          'lib/screens/gamebase/providers/gamebase_providers.dart',
        ).readAsStringSync();
    final profileSource =
        File(
          'lib/screens/player_profile/player_profile_screen.dart',
        ).readAsStringSync();

    expect(
      providerSource,
      contains(
        RegExp(
          r'playerOpeningTreeProvider\s*=\s*'
          r'StateNotifierProvider\.autoDispose\s*\.family',
        ),
      ),
      reason:
          'Each visited player previously left a non-auto-disposed one-second '
          'poll loop alive after navigation.',
    );
    expect(
      profileSource,
      isNot(contains('_startExplorerTreeForPlayer')),
      reason:
          'Merely rendering a player profile must not start backend polling. '
          'The visible Explorer screen owns that work.',
    );
    expect(
      File(
        'lib/screens/gamebase/gamebase_explorer_screen.dart',
      ).readAsStringSync(),
      contains('void didChangeAppLifecycleState(AppLifecycleState state)'),
      reason: 'The visible tree poll must pause while the app is backgrounded.',
    );
  });

  test('cached For You feed defers heavy catch-up work while offscreen', () {
    final providerSource =
        File('lib/providers/for_you_games_provider.dart').readAsStringSync();
    final widgetSource =
        File(
          'lib/screens/group_event/widget/for_you_games_widget.dart',
        ).readAsStringSync();

    expect(
      providerSource,
      contains('if (!ref.read(forYouSurfaceVisibleProvider))'),
    );
    expect(widgetSource, contains('_publishSurfaceVisibility()'));
    expect(
      widgetSource,
      isNot(contains('forceFeedRefresh: true')),
      reason:
          'A quick app switch must respect the five-minute feed staleness gate.',
    );
    expect(
      providerSource,
      isNot(contains('_queuedTopGamesRefresh')),
      reason:
          'Simultaneous tab/widget activation refreshes must coalesce instead '
          'of deliberately running the same top-games RPC twice.',
    );
    expect(
      providerSource,
      contains('_liveFeedRefreshScheduled) {'),
      reason:
          'A pending live-set full refresh must suppress the activation '
          'top-games refresh that would otherwise overlap it.',
    );
  });

  test('tournament safety net polls lightweight rows without overlap', () {
    final repositorySource =
        File(
          'lib/repository/supabase/game/game_repository.dart',
        ).readAsStringSync();
    final providerSource =
        File(
          'lib/screens/tour_detail/games_tour/providers/games_tour_provider.dart',
        ).readAsStringSync();

    expect(
      repositorySource,
      contains(".select('id,round_id,round_slug,status')"),
    );
    expect(providerSource, contains('.getTourGamesSafetyNet(tourId)'));
    expect(providerSource, contains('_safetyNetRefreshInFlight'));
    expect(providerSource, contains('selectedTourModeProvider'));
    expect(providerSource, contains('_isRefreshActive(generation)'));
  });
}
