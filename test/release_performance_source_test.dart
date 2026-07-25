import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Clarity session recorder stays release-only and startup-deferred', () {
    final mainSource = File('lib/main.dart').readAsStringSync();

    // Clarity was once removed outright because its render-tree capture loop
    // caused periodic foreground stalls (9094c373). It is reactivated on
    // purpose, but only in the shape that keeps startup unaffected: gated out
    // of debug builds and deferred through ForegroundTaskScheduler instead of
    // running inside the first-frame callback.
    final clarityBlock = mainSource.substring(
      mainSource.indexOf("key: 'startup_clarity'") - 200,
      mainSource.indexOf("key: 'startup_clarity'"),
    );
    expect(
      clarityBlock,
      contains('if (!kDebugMode)'),
      reason: 'Clarity must never record debug/dev sessions.',
    );
    expect(
      clarityBlock,
      contains('ForegroundTaskScheduler.schedule'),
      reason:
          'Clarity.initialize must stay behind the startup warmup scheduler '
          'so its capture loop cannot contribute to first-frame stalls.',
    );
    expect(
      mainSource,
      contains("delay: kStartupWarmupDelay"),
      reason: 'Clarity init keeps the warmup delay it shipped with.',
    );
  });

  test('iOS PiP does not churn full 720px frames behind covered routes', () {
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

  test('iOS PiP uses square 720 board stack with player rows, not landscape column', () {
    final pipSource =
        File('ios/Runner/ChessPipController.swift').readAsStringSync();

    // Frame size: square content at the pre-shrink resolution.
    expect(
      pipSource,
      contains('CGSize(width: 720, height: 720)'),
      reason: 'PiP must render a 720x720 square frame matching the in-app board.',
    );
    expect(
      pipSource,
      isNot(contains('CGSize(width: 768, height: 540)')),
      reason: 'Landscape 768x540 shrink frame must not remain the active size.',
    );
    expect(
      pipSource,
      isNot(contains('768x540')),
      reason: 'No landscape shrink size comments/call should remain active.',
    );

    // Layout: top/bottom single-line player rows around the board (not side column).
    expect(
      pipSource,
      contains('drawPlayerRow'),
      reason: 'Square layout draws PlayerFirstRow-style rows above/below the board.',
    );
    expect(
      pipSource,
      isNot(contains('drawPlayerBlock')),
      reason: 'Side-column stacked player blocks were the shrink regression.',
    );
    expect(
      pipSource,
      contains('[title, name, rating]'),
      reason: 'Player row label is single-line title/name/rating, not split lines.',
    );

    // Piece-asset fix from the same commit must stay.
    expect(
      pipSource,
      contains('.webp'),
      reason: 'Native piece loaders must keep chessground v10 .webp paths.',
    );
    expect(
      pipSource,
      contains('"totoy"'),
      reason: 'The totoy piece set must remain registered on iOS.',
    );
    expect(
      pipSource,
      isNot(contains('pieceCode).png"')),
      reason: 'Do not reintroduce broken .png piece paths.',
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
