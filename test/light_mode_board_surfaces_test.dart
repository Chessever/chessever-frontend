import 'package:chessever2/providers/auto_pin_preferences_provider.dart';
import 'package:chessever2/providers/board_settings_provider_new.dart';
import 'package:chessever2/providers/engine_settings_provider.dart';
import 'package:chessever2/repository/lichess/cloud_eval/cloud_eval.dart';
import 'package:chessever2/repository/local_storage/auto_pin_preferences/auto_pin_preferences_repository.dart';
import 'package:chessever2/repository/library/models/saved_analysis.dart';
import 'package:chessever2/repository/library/models/library_folder.dart';
import 'package:chessever2/screens/chessboard/widgets/player_first_row_detail_widget.dart';
import 'package:chessever2/screens/library/providers/library_folders_provider.dart';
import 'package:chessever2/screens/library/widgets/book_saved_game_card.dart';
import 'package:chessever2/screens/library/widgets/folder_card.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/event_no_spoilers_provider.dart';
import 'package:chessever2/screens/library/utils/load_saved_analysis.dart';
import 'package:chessever2/screens/my_likes/provider/my_likes_provider.dart';
import 'package:chessever2/screens/gamebase/utils/continuation_line.dart';
import 'package:chessever2/screens/gamebase/widgets/explorer_game_card.dart';
import 'package:dartchess/dartchess.dart';
import 'package:chessever2/screens/my_likes/widgets/my_likes_archive_boundary.dart';
import 'package:chessever2/screens/my_likes/widgets/my_likes_game_card.dart';
import 'package:chessever2/screens/my_space/models/space_shortcut.dart';
import 'package:chessever2/screens/my_space/providers/space_shortcuts_provider.dart';
import 'package:chessever2/revenue_cat_service/subscribe_state.dart';
import 'package:chessever2/screens/for_you/discovery/discovery_view.dart';
import 'package:chessever2/screens/for_you/discovery/models/discovery_models.dart';
import 'package:chessever2/screens/for_you/discovery/providers/discovery_providers.dart';
import 'package:chessever2/screens/favorites/tabs/favorites_players_tab.dart';
import 'package:chessever2/screens/group_event/smart_event/smart_aggregate_event_provider.dart';
import 'package:chessever2/screens/library/providers/miniatures_provider.dart';
import 'package:chessever2/screens/streaks/models/streak_models.dart';
import 'package:chessever2/screens/streaks/providers/streak_providers.dart';
import 'package:chessever2/repository/supabase/game_analysis_quota_repository.dart';
import 'package:chessever2/screens/chessboard/analysis/chess_game.dart';
import 'package:chessever2/screens/chessboard/game_review/game_analysis_report.dart';
import 'package:chessever2/screens/chessboard/game_review/game_review_provider.dart';
import 'package:chessever2/screens/chessboard/game_review/game_review_sheet.dart';
import 'package:chessever2/screens/chessboard/provider/stockfish_singleton.dart';
import 'package:chessever2/screens/chessboard/utils/live_stream_coachmark.dart';
import 'package:chessever2/screens/chessboard/widgets/chess_board_bottom_nav_bar.dart';
import 'package:chessever2/screens/chessboard/widgets/context_pop_up_menu.dart';
import 'package:chessever2/screens/my_likes/widgets/date_section_header.dart';
import 'package:chessever2/screens/premium_games/widgets/twic_game_card.dart';
import 'package:chessever2/screens/settings/widgets/board_settings_body.dart';
import 'package:chessever2/screens/settings/widgets/engine_settings_body.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'support/contrast_audit.dart';

/// Light-mode audit of the board, review, library and settings surfaces:
/// every text run and icon glyph is measured against the fill it is actually
/// painted on, and dark mode is checked to still paint its historic inks.
void main() {
  const light = AppColors.light;

  Future<void> pumpSurface(
    WidgetTester tester,
    Widget child, {
    required ThemeData theme,
    List<Override> overrides = const [],
    Size size = const Size(393, 1400),
    double textScale = 1.0,
    bool settle = true,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides,
        child: MaterialApp(
          theme: theme,
          home: Builder(
            builder: (context) {
              ResponsiveHelper.init(context);
              return MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(textScale)),
                child: Scaffold(body: child),
              );
            },
          ),
        ),
      ),
    );
    if (settle) {
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
    } else {
      // Looping motion (flames) never settles.
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 60));
      }
    }
  }

  List<ContrastMiss> audit(WidgetTester tester) =>
      auditTextContrast(tester, fallbackGround: light.background);

  group('settings bodies', () {
    final overrides = <Override>[
      engineSettingsProviderNew.overrideWith(_EngineSettings.new),
      boardSettingsProviderNew.overrideWith(_BoardSettings.new),
      autoPinPreferencesProvider.overrideWith(_AutoPin.new),
    ];

    testWidgets('engine experience reads on paper', (tester) async {
      await pumpSurface(
        tester,
        SingleChildScrollView(child: EngineSettingsBody(trackPersist: (_) {})),
        theme: AppTheme.lightTheme,
        overrides: overrides,
      );
      expectNoContrastMisses(audit(tester), where: 'EngineSettingsBody');
    });

    testWidgets('board settings read on paper', (tester) async {
      await pumpSurface(
        tester,
        SingleChildScrollView(child: BoardSettingsBody(trackPersist: (_) {})),
        theme: AppTheme.lightTheme,
        overrides: overrides,
        size: const Size(393, 2600),
      );
      expectNoContrastMisses(audit(tester), where: 'BoardSettingsBody');
    });
  });

  group('library and likes', () {
    testWidgets('date header reads on its recessed plate', (tester) async {
      await pumpSurface(
        tester,
        const DateSectionHeader(
          dateLabel: 'Yesterday',
          gameCount: 12,
          isExpanded: true,
          onToggle: _noop,
        ),
        theme: AppTheme.lightTheme,
      );
      expectNoContrastMisses(audit(tester), where: 'DateSectionHeader');
    });

    testWidgets('board context menu reads, icons included', (tester) async {
      await pumpSurface(
        tester,
        Center(
          child: ContextPopupMenu(
            isPinned: false,
            onPinToggle: _noop,
            onShare: _noop,
            isLiveEnabled: false,
            onLiveToggle: _noop,
          ),
        ),
        theme: AppTheme.lightTheme,
      );
      expectNoContrastMisses(audit(tester), where: 'ContextPopupMenu');
    });
  });

  group('premium games card', () {
    for (final status in [
      GameStatus.whiteWins,
      GameStatus.blackWins,
      GameStatus.draw,
      GameStatus.ongoing,
      GameStatus.unknown,
    ]) {
      testWidgets('names and result badge read in light (${status.name})', (
        tester,
      ) async {
        final game = _game(status);
        await pumpSurface(
          tester,
          Padding(
            padding: const EdgeInsets.all(16),
            child: TwicGameCard(game: game, allGames: [game], gameIndex: 0),
          ),
          theme: AppTheme.lightTheme,
        );
        expect(find.textContaining('Lovelace'), findsOneWidget);
        expectNoContrastMisses(audit(tester), where: 'TwicGameCard');
      });
    }
  });

  group('discovery', () {
    testWidgets('For You discovery reads on paper', (tester) async {
      await pumpSurface(
        tester,
        const DiscoveryView(),
        theme: AppTheme.lightTheme,
        size: const Size(390, 5200),
        overrides: [
          subscriptionProvider.overrideWith((ref) => _Subscription()),
          streakWallProvider.overrideWith(() => _FakeWall(_wall)),
          playerPhotoProvider.overrideWith((ref, fideId) async => null),
          boardSettingsProviderNew.overrideWith(_BoardSettings.new),
          mostLikedProvider.overrideWith(
            (ref, query) => Future.value(const MostLikedResult.notLive()),
          ),
          discoveryTodayMiniaturesProvider.overrideWith(
            (ref) async => const [],
          ),
          discoveryAnalyzedGamesProvider.overrideWith((ref) async => const []),
          discoveryReviewCurveProvider.overrideWith((ref) async => null),
          discoverySmartRequestsProvider.overrideWith(
            (ref) => const AsyncData(<SmartEventRequest>[]),
          ),
          discoveryCountryProvider.overrideWith((ref) => null),
          miniaturesTotalCountProvider.overrideWith((ref) async => 566112),
          // The seam over the viewer's favourites, never the account.
          discoveryFollowedFideIdsProvider.overrideWith(
            (ref) => const <int>{},
          ),
        ],
        settle: false,
      );
      expect(find.text('Collection'), findsOneWidget);
      expectNoContrastMisses(
        auditTextContrast(tester, fallbackGround: light.background),
        where: 'DiscoveryView',
      );
    });
  });

  group('my likes', () {
    final like = SavedAnalysis(
      id: 'like-audit',
      userId: 'user-1',
      folderId: 'liked-folder',
      title: 'Game',
      sourceGameId: 'game-1',
      chessGame: ChessGame.fromPgn(
        'game-1',
        '[White "White"]\n[Black "Black"]\n[Result "1-0"]\n\n1. e4 e5 1-0',
      ),
      analysisState: const {},
      variationComments: const {},
      lastViewedPosition: -1,
      tags: const ['Trap', 'Endgame'],
      isFavorite: false,
      createdAt: DateTime.utc(2026, 9, 1, 12),
      updatedAt: DateTime.utc(2026, 9, 1, 12),
    );
    final game = savedAnalysisToCardGame(
      like,
    ).copyWith(gameStatus: GameStatus.whiteWins);

    for (final locked in [false, true]) {
      testWidgets('like card reads on paper (locked: $locked)', (tester) async {
        await pumpSurface(
          tester,
          Padding(
            padding: const EdgeInsets.all(16),
            child: Align(
              alignment: Alignment.topCenter,
              child: MyLikesGameCard(
                analysis: like,
                game: game,
                isLocked: locked,
                onOpen: _noop,
                onRemove: () async {},
              ),
            ),
          ),
          theme: AppTheme.lightTheme,
          overrides: [spaceShortcutsProvider.overrideWith(_NoShortcuts.new)],
          settle: false,
        );
        expectNoContrastMisses(audit(tester), where: 'MyLikesGameCard');
      });
    }

    testWidgets('archive boundary reads on paper', (tester) async {
      await pumpSurface(
        tester,
        Padding(
          padding: const EdgeInsets.all(16),
          child: MyLikesArchiveBoundary(
            data: const MyLikesData(
              sections: [],
              openableAnalyses: [],
              totalLiked: 34,
              visibleCount: 20,
              archivedCount: 14,
              archivedMatchCount: 14,
            ),
            onViewHistory: _noop,
          ),
        ),
        theme: AppTheme.lightTheme,
      );
      expectNoContrastMisses(audit(tester), where: 'MyLikesArchiveBoundary');
    });
  });

  group('explorer', () {
    testWidgets('explorer game card reads on paper', (tester) async {
      final game = _game(GameStatus.whiteWins).copyWith(
        source: GameSource.gamebase,
        tourSlug: 'Tata Steel Masters 2024',
        eco: 'C45',
        lastMoveTime: DateTime(2024, 5, 12),
      );
      await pumpSurface(
        tester,
        Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: 390,
            child: ExplorerGameCard(
              game: game,
              anchorFen: kInitialFEN,
              line: buildContinuationLine(kInitialFEN, const [
                'e2e4',
                'e7e5',
                'g1f3',
              ]),
              allGames: [game],
              index: 0,
              playMoveSound: (_) {},
            ),
          ),
        ),
        theme: AppTheme.lightTheme,
        overrides: [
          boardSettingsProviderNew.overrideWith(_BoardSettings.new),
          engineSettingsProviderNew.overrideWith(_EngineSettings.new),
        ],
        settle: false,
      );
      expect(find.textContaining('Lovelace'), findsWidgets);
      expectNoContrastMisses(audit(tester), where: 'ExplorerGameCard');
    });
  });

  group('board chrome', () {
    testWidgets('bottom bar and its stream coachmark read on paper', (
      tester,
    ) async {
      await pumpSurface(
        tester,
        Align(
          alignment: Alignment.bottomCenter,
          child: ChessBoardBottomNavBar(
            gameIndex: 0,
            onLeftMove: _noop,
            onRightMove: _noop,
            onFlip: _noop,
            onVideoToggle: _noop,
            videoVisible: true,
            canMoveForward: true,
            canMoveBackward: true,
            showEngineAnalysis: true,
            showUnseenMoveBadge: false,
            liveStreamCoachmarkTracker: LiveStreamCoachmarkTracker(
              _CoachmarkStore(),
            ),
          ),
        ),
        theme: AppTheme.lightTheme,
        size: const Size(393, 800),
        overrides: [
          engineSettingsProviderNew.overrideWith(_EngineSettings.new),
          engineDepthStatusProvider.overrideWithValue(null),
        ],
        settle: false,
      );
      expect(
        find.text('Turn off the stream by clicking camera icon.'),
        findsOneWidget,
      );
      expectNoContrastMisses(audit(tester), where: 'ChessBoardBottomNavBar');
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('library cards', () {
    final at = DateTime.utc(2026, 9, 1);
    final folder = LibraryFolder(
      id: 'db-1',
      userId: 'user-1',
      name: 'Openings prep',
      color: '#F59E0B',
      icon: 'folder',
      orderIndex: 0,
      createdAt: at,
      updatedAt: at,
    );
    final saved = SavedAnalysis(
      id: 'analysis-1',
      userId: 'user-1',
      folderId: 'db-1',
      title: 'Opera game',
      sourceGameId: 'source-game-1',
      chessGame: ChessGame.fromPgn(
        'analysis-1',
        '[Event "Paris Opera"]\n[White "Morphy, Paul"]\n'
            '[Black "Isouard, Count"]\n[Result "1-0"]\n\n1. e4 e5 2. Nf3 d6 1-0',
      ),
      analysisState: const {},
      variationComments: const {},
      lastViewedPosition: -1,
      tags: const [],
      isFavorite: false,
      createdAt: at,
      updatedAt: at,
    );
    final overrides = <Override>[
      spaceShortcutsProvider.overrideWith(_NoShortcuts.new),
      engineSettingsProviderNew.overrideWith(_EngineSettings.new),
      folderAnalysisCountProvider.overrideWith((ref, id) async => 12),
    ];

    testWidgets('database card reads on paper', (tester) async {
      await pumpSurface(
        tester,
        Padding(
          padding: const EdgeInsets.all(16),
          child: FolderCard(folder: folder, isExpanded: true),
        ),
        theme: AppTheme.lightTheme,
        overrides: overrides,
        settle: false,
      );
      expect(find.text('Openings prep'), findsOneWidget);
      expectNoContrastMisses(audit(tester), where: 'FolderCard');
    });

    testWidgets('saved game card reads on paper', (tester) async {
      await pumpSurface(
        tester,
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [BookSavedGameCard(analysis: saved, onTap: _noop)],
          ),
        ),
        theme: AppTheme.lightTheme,
        overrides: overrides,
        settle: false,
      );
      expectNoContrastMisses(audit(tester), where: 'BookSavedGameCard');
    });
  });

  group('player row', () {
    for (final view in PlayerView.values) {
      testWidgets('name, rating and clock read on paper (${view.name})', (
        tester,
      ) async {
        final game = _game(GameStatus.ongoing).copyWith(
          whiteClockCentiseconds: 54000,
          blackClockCentiseconds: 61000,
          fen: 'rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 2',
          lastMove: 'e7e5',
        );
        await pumpSurface(
          tester,
          Center(
            child: SizedBox(
              width: view == PlayerView.gridView ? 180 : 390,
              child: PlayerFirstRowDetailWidget(
                playerView: view,
                isWhitePlayer: true,
                gamesTourModel: game,
                showClock: true,
              ),
            ),
          ),
          theme: AppTheme.lightTheme,
          overrides: [
            engineSettingsProviderNew.overrideWith(_EngineSettings.new),
            eventNoSpoilersProvider.overrideWith(
              (ref, tourId) => _NoSpoilers(ref: ref, tourId: tourId),
            ),
          ],
          settle: false,
        );
        expectNoContrastMisses(audit(tester), where: 'PlayerFirstRow');
      });
    }
  });

  group('game review sheet', () {
    Future<MobileGameReviewController> completedReview(
      WidgetTester tester,
    ) async {
      final chessGame = ChessGame.fromPgn(
        'light-audit',
        '[White "Ada"]\n[Black "Grace"]\n[Result "1-0"]\n\n1. e4 e5 1-0',
      );
      final controller = MobileGameReviewController(
        reportController: GameAnalysisReportController(evaluator: _evaluator),
        claimQuota: _allowClaim,
      );
      addTearDown(controller.dispose);
      await tester.runAsync(() async {
        controller.configure(
          game: chessGame,
          active: true,
          finished: true,
          whiteRating: 2100,
          blackRating: 2050,
        );
        await controller.retry();
        for (
          var i = 0;
          i < 40 &&
              controller.reviewState.reportState.status !=
                  GameReportStatus.completed;
          i++
        ) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
      });
      expect(
        controller.reviewState.reportState.status,
        GameReportStatus.completed,
      );
      return controller;
    }

    testWidgets('Game Analysis button reads in every state', (tester) async {
      await pumpSurface(
        tester,
        const Column(
          children: [
            GameAnalysisButton(
              state: MobileGameReviewState(isEligible: true),
              onPressed: _noop,
            ),
            GameAnalysisButton(
              state: MobileGameReviewState(
                isEligible: true,
                reportState: GameReportState(
                  status: GameReportStatus.running,
                  progress: 0.42,
                ),
              ),
              onPressed: _noop,
            ),
            GameAnalysisButton(
              state: MobileGameReviewState(
                isEligible: true,
                reportState: GameReportState(
                  status: GameReportStatus.completed,
                  progress: 1.0,
                ),
              ),
              onPressed: _noop,
            ),
            GameAnalysisButton(
              state: MobileGameReviewState(
                isEligible: true,
                reportState: GameReportState(status: GameReportStatus.failed),
              ),
              onPressed: _noop,
            ),
            GameAnalysisButton(
              state: MobileGameReviewState(
                unavailableMessage: 'Game analysis starts when the game ends',
              ),
              onPressed: _noop,
            ),
          ],
        ),
        theme: AppTheme.lightTheme,
        settle: false,
      );
      expect(find.text('Show report'), findsOneWidget);
      expectNoContrastMisses(audit(tester), where: 'GameAnalysisButton');
    });

    testWidgets('completed review reads on paper, graph caption included', (
      tester,
    ) async {
      final controller = await completedReview(tester);
      await pumpSurface(
        tester,
        GameReviewSheet(
          controller: controller,
          game: _game(GameStatus.whiteWins),
          activePly: 1,
          onJumpToPly: (_) {},
          onClose: _noop,
        ),
        theme: AppTheme.lightTheme,
        size: const Size(393, 900),
      );
      await tester.pump(const Duration(milliseconds: 600));

      final caption = find.byKey(const ValueKey('game-review-graph-info'));
      expect(caption, findsOneWidget);
      final capsule =
          tester.widget<Container>(caption).decoration! as BoxDecoration;
      final label = tester.widget<Text>(
        find.descendant(of: caption, matching: find.byType(Text)),
      );
      final ground = Color.alphaBlend(capsule.color!, light.surface);
      expect(
        auditContrast(label.style!.color!, ground),
        greaterThanOrEqualTo(4.5),
        reason: 'graph caption ink on its capsule',
      );

      expectNoContrastMisses(audit(tester), where: 'GameReviewSheet');
    });

    testWidgets('dark keeps the charcoal caption with page ink', (
      tester,
    ) async {
      final controller = await completedReview(tester);
      await pumpSurface(
        tester,
        GameReviewSheet(
          controller: controller,
          game: _game(GameStatus.whiteWins),
          activePly: 1,
          onJumpToPly: (_) {},
          onClose: _noop,
        ),
        theme: AppTheme.darkTheme,
        size: const Size(393, 900),
      );
      await tester.pump(const Duration(milliseconds: 600));
      final caption = find.byKey(const ValueKey('game-review-graph-info'));
      final capsule =
          tester.widget<Container>(caption).decoration! as BoxDecoration;
      expect(capsule.color, const Color(0xFF303034).withValues(alpha: 0.92));
      final label = tester.widget<Text>(
        find.descendant(of: caption, matching: find.byType(Text)),
      );
      expect(label.style!.color, AppColors.dark.textPrimary);
    });
  });
}

void _noop() {}

class _EngineSettings extends EngineSettingsNotifierNew {
  @override
  Future<EngineSettings> build() async => const EngineSettings();
}

class _CoachmarkStore implements LiveStreamCoachmarkStore {
  bool seen = false;

  @override
  Future<bool> hasSeen() async => seen;

  @override
  Future<void> markSeen() async => seen = true;
}

class _NoSpoilers extends EventNoSpoilersController {
  _NoSpoilers({required super.ref, required super.tourId});

  @override
  Future<void> load() async {
    state = const EventNoSpoilersState(enabled: false, isLoading: false);
  }
}

class _NoShortcuts extends SpaceShortcutsNotifier {
  @override
  Future<List<SpaceShortcut>> build() async => const [];
}

class _AutoPin extends AutoPinPreferencesNotifier {
  @override
  Future<AutoPinPreferences> build() async => AutoPinPreferences.defaults;
}

class _BoardSettings extends BoardSettingsNotifierNew {
  @override
  Future<BoardSettingsNew> build() async => const BoardSettingsNew();
}

Future<GameAnalysisClaimResult> _allowClaim(String _) async =>
    const GameAnalysisClaimResult(
      allowed: true,
      reason: 'premium',
      isPremium: true,
    );

Future<EnhancedCloudEval> _evaluator(
  String fen, {
  required int depth,
  required int multiPv,
  required String ownerId,
  void Function(int reachedDepth, int knodes)? onProgress,
}) async {
  onProgress?.call(depth, 500);
  final whiteToMove = fen.split(' ')[1] == 'w';
  final top = whiteToMove
      ? (fen.startsWith('rnbqkbnr/pppppppp') ? 'e2e4' : 'g1f3')
      : 'e7e5';
  return EnhancedCloudEval(
    fen: fen,
    knodes: 500,
    depth: depth,
    pvs: [
      Pv(moves: top, cp: 180),
      if (multiPv > 1) Pv(moves: whiteToMove ? 'd2d4' : 'd7d5', cp: 20),
      if (multiPv > 2) Pv(moves: whiteToMove ? 'c2c4' : 'c7c5', cp: -40),
    ],
    requestedMultiPv: multiPv,
  );
}

GamesTourModel _game(GameStatus status) => GamesTourModel(
  gameId: 'light-audit-game',
  whitePlayer: PlayerCard(
    name: 'Ada Lovelace',
    federation: '',
    title: 'GM',
    rating: 2100,
    countryCode: '',
    team: null,
  ),
  blackPlayer: PlayerCard(
    name: 'Grace Hopper',
    federation: '',
    title: 'IM',
    rating: 2050,
    countryCode: '',
    team: null,
  ),
  whiteTimeDisplay: '',
  blackTimeDisplay: '',
  whiteClockCentiseconds: 0,
  blackClockCentiseconds: 0,
  gameStatus: status,
  roundId: 'round',
  tourId: 'tour',
);

class _FakeWall extends StreakWallNotifier {
  _FakeWall(this._rows);

  final List<StreakRow> _rows;

  @override
  Future<List<StreakRow>> build() async => _rows;

  @override
  Future<void> refresh() async {}

  @override
  Future<void> refreshIfStale({Duration maxAge = kStreakWallMaxAge}) async {}
}

class _Subscription extends StateNotifier<SubscriptionState>
    implements SubscriptionNotifier {
  _Subscription() : super(SubscriptionState(isSubscribed: false));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

StreakRow _row(int fideId, StreakTimeClass tc, String name, int streak) =>
    StreakRow(
      fideId: fideId,
      timeClass: tc,
      name: name,
      title: 'GM',
      fed: 'IND',
      rating: 2740,
      currentStreak: streak,
      bestStreak: streak,
    );

final _wall = <StreakRow>[
  _row(1, StreakTimeClass.standard, 'Gujrathi, Vidit', 14),
  _row(2, StreakTimeClass.standard, 'Abdusattorov, Nodirbek', 7),
  _row(4, StreakTimeClass.rapid, 'Nakamura, Hikaru', 8),
  _row(5, StreakTimeClass.blitz, 'So, Wesley', 6),
];
