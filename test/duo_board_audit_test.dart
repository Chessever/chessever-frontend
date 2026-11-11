import 'dart:async';

import 'package:chessever2/providers/board_settings_provider_new.dart';
import 'package:chessever2/providers/country_dropdown_provider.dart';
import 'package:chessever2/providers/engine_settings_provider.dart';
import 'package:chessever2/repository/gamebase/gamebase_repository.dart';
import 'package:chessever2/repository/gamebase/search/gamebase_search_models.dart';
import 'package:chessever2/repository/library/library_repository.dart';
import 'package:chessever2/repository/library/models/library_folder.dart';
import 'package:chessever2/repository/library/models/saved_analysis.dart';
import 'package:chessever2/repository/lichess/cloud_eval/cloud_eval.dart';
import 'package:chessever2/repository/liked_games/liked_games_provider.dart';
import 'package:chessever2/repository/supabase/game_analysis_quota_repository.dart';
import 'package:chessever2/screens/board_editor/board_editor_screen.dart';
import 'package:chessever2/screens/board_editor/board_editor_space_draft.dart';
import 'package:chessever2/screens/chessboard/provider/current_eval_provider.dart';
import 'package:chessever2/screens/my_space/models/space_shortcut.dart';
import 'package:chessever2/screens/my_space/providers/space_shortcuts_provider.dart';
import 'package:chessground/chessground.dart' show ChessboardEditor;
import 'package:chessever2/screens/chessboard/analysis/chess_game.dart';
import 'package:chessever2/screens/chessboard/game_review/game_analysis_report.dart';
import 'package:chessever2/screens/chessboard/game_review/game_review_provider.dart';
import 'package:chessever2/screens/chessboard/game_review/game_review_sheet.dart';
import 'package:chessever2/screens/chessboard/provider/chess_board_screen_provider_new.dart';
import 'package:chessever2/screens/chessboard/provider/stockfish_singleton.dart';
import 'package:chessever2/screens/chessboard/view_model/chess_board_state_new.dart';
import 'package:chessever2/screens/chessboard/widgets/engine_pv_layouts.dart';
import 'package:chessever2/screens/chessboard/widgets/like_tag_chip.dart';
import 'package:chessever2/screens/chessboard/widgets/like_tag_offer.dart';
import 'package:chessever2/screens/chessboard/widgets/save_analysis_sheet.dart';
import 'package:chessever2/screens/chessboard/widgets/switch_views_tutorial_overlay.dart';
import 'package:chessever2/screens/favorites/tabs/favorites_players_tab.dart';
import 'package:chessever2/screens/gamebase/models/models.dart';
import 'package:chessever2/screens/gamebase/widgets/board_opening_explorer_panel.dart';
import 'package:chessever2/screens/library/providers/library_folders_provider.dart';
import 'package:chessever2/screens/standings/player_standing_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/adaptive_window.dart';
import 'package:chessever2/widgets/country_dropdown.dart';
import 'package:chessever2/widgets/figma_player_card.dart';
import 'package:chessever2/widgets/segmented_switcher.dart';
import 'package:chessever2/widgets/window_orientation_scope.dart';
import 'package:country_picker/country_picker.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'fixtures/duo_window_matrix.dart';

/// Duo audit for the board and analysis area: the panels, sheets and menus
/// around the board that the workspace-layout matrix does not pump.
///
/// Every surface is cold-started in all four Duo window states at 1.0 and
/// 1.3 text, and the ones that hold state are carried across every
/// folded<->unfolded transition.
const _scales = [1.0, 1.3];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ---------------------------------------------------------------------------
  // Save Analysis sheet
  // ---------------------------------------------------------------------------
  for (final window in duoWindowCases) {
    for (final scale in _scales) {
      testWidgets('save analysis sheet fits ${window.name} at ${scale}x', (
        tester,
      ) async {
        _duo(tester, window);
        await _openSaveAnalysis(tester, scale: scale);
        expect(tester.takeException(), isNull);
        await _tapReachable(tester, find.text('Database 0'));
        await _expectReachable(tester, find.byType(FilledButton));
        expect(
          tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
          isNotNull,
        );
        await _expectReachable(
          tester,
          find.widgetWithText(TextButton, 'Cancel'),
        );
        await _tapReachable(tester, find.text('Tags'));
        expect(tester.takeException(), isNull);
        await _expectReachable(tester, find.text('Opening'));
        await _expectReachable(tester, find.byType(FilledButton));
      });
    }
  }

  for (final transition in _foldTransitions) {
    testWidgets(
      'save analysis keeps database and tags from ${transition.from.name} to ${transition.to.name}',
      (tester) async {
        _duo(tester, transition.from);
        await _openSaveAnalysis(tester, scale: 1.3);
        await _tapReachable(tester, find.text('Database 3'));
        await _tapReachable(tester, find.text('Tags'));
        await _tapReachable(tester, find.text('Opening'));
        final state = tester.state(find.byType(FilledButton));
        for (final window in [transition.to, transition.from]) {
          _duo(tester, window, mirrorInsets: window == transition.to);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: window.name);
          expect(tester.state(find.byType(FilledButton)), same(state));
          expect(find.text('1 selected'), findsOneWidget);
          expect(
            tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
            isNotNull,
            reason: 'the chosen database survives ${window.name}',
          );
          await _expectReachable(tester, find.byType(FilledButton));
        }
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Game Review sheet (completed report)
  // ---------------------------------------------------------------------------
  for (final window in duoWindowCases) {
    for (final scale in _scales) {
      testWidgets('game review sheet fits ${window.name} at ${scale}x', (
        tester,
      ) async {
        _duo(tester, window);
        final controller = await _completedReview(tester);
        var closed = false;
        await tester.pumpWidget(
          _app(
            scale: scale,
            child: Scaffold(
              body: Stack(
                children: [
                  Positioned.fill(
                    child: GameReviewSheet(
                      controller: controller,
                      game: _game(),
                      activePly: 0,
                      onJumpToPly: (_) {},
                      onClose: () => closed = true,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600));
        expect(tester.takeException(), isNull);
        final close = find.byKey(const ValueKey('game-review-close'));
        expect(close.hitTestable(), findsOneWidget);

        // Open to the full report and check it still lays out.
        await tester.tapAt(tester.getCenter(close) - const Offset(80, 0));
        await tester.pump(const Duration(milliseconds: 600));
        expect(tester.takeException(), isNull);
        expect(find.text('Accuracy'), findsOneWidget);
        await tester.tap(close.hitTestable());
        for (var i = 0; i < 10 && !closed; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(closed, isTrue);
        expect(tester.takeException(), isNull);
      });
    }
  }

  for (final transition in _foldTransitions) {
    testWidgets(
      'game review sheet keeps its state from ${transition.from.name} to ${transition.to.name}',
      (tester) async {
        _duo(tester, transition.from);
        final controller = await _completedReview(tester);
        await tester.pumpWidget(
          _app(
            scale: 1.3,
            child: Scaffold(
              body: GameReviewSheet(
                controller: controller,
                game: _game(),
                activePly: 2,
                onJumpToPly: (_) {},
                onClose: () {},
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600));
        final state = tester.state(find.byType(GameReviewSheet));
        for (final window in [transition.to, transition.from]) {
          _duo(tester, window, mirrorInsets: window == transition.to);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 600));
          expect(tester.takeException(), isNull, reason: window.name);
          expect(tester.state(find.byType(GameReviewSheet)), same(state));
          expect(find.textContaining('1... e5'), findsOneWidget);
          expect(
            find.byKey(const ValueKey('game-review-close')).hitTestable(),
            findsOneWidget,
          );
        }
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Engine PV list and cards
  // ---------------------------------------------------------------------------
  for (final window in duoWindowCases) {
    for (final scale in _scales) {
      testWidgets(
        'engine lines list and cards fit ${window.name} at ${scale}x',
        (tester) async {
          _duo(tester, window);
          final taps = <int>[];
          final items = [
            for (var i = 0; i < 3; i++)
              EnginePvItem(
                evalText: ['+12.45', '-0.35', '#-12'][i],
                isPrimary: i == 0,
                isWhiteWinning: i == 0,
                isBlackWinning: i == 2,
                accentColor: Colors.teal,
                moveSpans: [
                  TextSpan(
                    text:
                        '1. e4 e5 2. Nf3 Nc6 3. Bb5 a6 4. Ba4 Nf6 5. O-O Be7 '
                        '6. Re1 b5 7. Bb3 d6 8. c3 O-O 9. h3 Nb8 10. d4 Nbd7',
                  ),
                ],
                onTap: () => taps.add(i),
              ),
          ];
          await tester.pumpWidget(
            _app(
              scale: scale,
              child: Scaffold(
                body: SafeArea(
                  child: Column(
                    children: [
                      EnginePvListView(items: items),
                      const SizedBox(height: 12),
                      EnginePvCardsView(items: items),
                    ],
                  ),
                ),
              ),
            ),
          );
          await tester.pump(const Duration(milliseconds: 300));
          expect(tester.takeException(), isNull);
          for (final eval in ['+12.45', '-0.35', '#-12']) {
            expect(find.text(eval).hitTestable(), findsWidgets, reason: eval);
          }
          await tester.tap(find.text('-0.35').first);
          await tester.pump(const Duration(milliseconds: 300));
          expect(taps, isNotEmpty);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  // ---------------------------------------------------------------------------
  // SegmentedSwitcher (board view tabs, players tabs)
  // ---------------------------------------------------------------------------
  for (final window in duoWindowCases) {
    for (final scale in _scales) {
      for (final scrollable in [false, true]) {
        testWidgets(
          'segmented switcher ${scrollable ? 'scrollable ' : ''}fits ${window.name} at ${scale}x',
          (tester) async {
            _duo(tester, window);
            final options = scrollable
                ? ['Standings', 'Games', 'Players', 'Pairings']
                : ['Notation', 'Explorer', 'Engine'];
            var selected = 0;
            await tester.pumpWidget(
              _app(
                scale: scale,
                child: Scaffold(
                  body: SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: SegmentedSwitcher(
                        options: options,
                        isScrollable: scrollable,
                        onSelectionChanged: (i) => selected = i,
                      ),
                    ),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            for (final (i, label) in options.indexed.toList().reversed) {
              await _expectReachable(tester, find.text(label));
              await tester.tap(find.text(label));
              await tester.pumpAndSettle();
              expect(selected, i, reason: label);
            }
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }

  for (final transition in _foldTransitions) {
    testWidgets(
      'segmented switcher keeps its selection from ${transition.from.name} to ${transition.to.name}',
      (tester) async {
        _duo(tester, transition.from);
        var selected = 0;
        await tester.pumpWidget(
          _app(
            scale: 1.3,
            child: Scaffold(
              body: SafeArea(
                child: StatefulBuilder(
                  builder: (context, setState) => SegmentedSwitcher(
                    options: const ['Notation', 'Explorer', 'Engine'],
                    currentSelection: selected,
                    onSelectionChanged: (i) => setState(() => selected = i),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Engine'));
        await tester.pumpAndSettle();
        final state = tester.state(find.byType(SegmentedSwitcher));
        for (final window in [transition.to, transition.from]) {
          _duo(tester, window, mirrorInsets: window == transition.to);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: window.name);
          expect(tester.state(find.byType(SegmentedSwitcher)), same(state));
          expect(selected, 2);
          expect(find.text('Notation').hitTestable(), findsOneWidget);
        }
      },
    );
  }

  // ---------------------------------------------------------------------------
  // FigmaPlayerCard (players lists beside the board)
  // ---------------------------------------------------------------------------
  for (final window in duoWindowCases) {
    for (final scale in _scales) {
      testWidgets('player cards fit ${window.name} at ${scale}x', (
        tester,
      ) async {
        _duo(tester, window);
        final tapped = <int>[];
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              playerPhotoProvider.overrideWith((ref, fideId) async => null),
            ],
            child: _app(
              scale: scale,
              child: Scaffold(
                body: SafeArea(
                  child: ListView(
                    children: [
                      for (var i = 0; i < 12; i++)
                        FigmaPlayerCard(
                          player: PlayerStandingModel(
                            countryCode: ['NO', 'US', 'IN', 'FIDE'][i % 4],
                            title: i.isEven ? 'GM' : 'WIM',
                            name: i == 3
                                ? 'Vachier-Lagrave, Maxime Alexandre Bernard'
                                : 'Player $i, Test',
                            score: 2850 - i,
                            scoreChange: i.isEven ? 12 : -7,
                            matchScore: '${i % 3}.5/9',
                          ),
                          rank: i + 98,
                          showFavoriteButton: false,
                          onTap: () => tapped.add(i),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 300));
        expect(tester.takeException(), isNull);
        final long = find.textContaining('Vachier-Lagrave');
        await _expectReachable(tester, long);
        await tester.tap(long);
        await tester.pump();
        expect(tapped, contains(3));
        expect(tester.takeException(), isNull);
      });
    }
  }

  // ---------------------------------------------------------------------------
  // CountryDropdown (players / profile federation picker)
  // ---------------------------------------------------------------------------
  for (final window in duoWindowCases) {
    for (final scale in _scales) {
      for (final compact in [false, true]) {
        testWidgets(
          '${compact ? 'compact ' : ''}country dropdown opens in ${window.name} at ${scale}x',
          (tester) async {
            _duo(tester, window);
            Country? chosen;
            await tester.pumpWidget(
              ProviderScope(
                overrides: [
                  countryDropdownProvider.overrideWith((ref) => _Country()),
                ],
                child: _app(
                  scale: scale,
                  child: Scaffold(
                    body: SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Align(
                          alignment: Alignment.topCenter,
                          child: CountryDropdown(
                            selectedCountryCode: 'NO',
                            compact: compact,
                            requireAuthToChange: false,
                            onChanged: (c) => chosen = c,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            await tester.tap(find.text('Norway'));
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            // Unfolded windows class as tablets, where the dropdown holds a
            // fresh menu open for 600ms of wall-clock time against phantom
            // taps. A person reads before choosing; let real time pass.
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 700)),
            );
            // The menu opens on the selection; its neighbour is one tap away.
            final item = find.text('Oman');
            await tester.ensureVisible(item.last);
            await tester.pumpAndSettle();
            expect(item.hitTestable(), findsWidgets);
            await tester.tap(item.hitTestable().last);
            await tester.pumpAndSettle();
            expect(chosen?.countryCode, 'OM');
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }

  group('country dropdown quick pick', () {
    for (final window in duoWindowCases.where((w) => w.unfolded)) {
      testWidgets('country dropdown closes on a quick pick in ${window.name}', (
        tester,
      ) async {
        _duo(tester, window);
        Country? chosen;
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              countryDropdownProvider.overrideWith((ref) => _Country()),
            ],
            child: _app(
              scale: 1.0,
              child: Scaffold(
                body: SafeArea(
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: CountryDropdown(
                      selectedCountryCode: 'NO',
                      requireAuthToChange: false,
                      onChanged: (c) => chosen = c,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Norway'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Oman').hitTestable().last);
        await tester.pumpAndSettle();
        expect(chosen?.countryCode, 'OM');
        expect(tester.takeException(), isNull);
        // The pick closed the menu: only the field's own label remains.
        expect(find.text('Oman'), findsNothing);
        expect(find.text('Afghanistan'), findsNothing);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  });

  // ---------------------------------------------------------------------------
  // Like tag chip dropdown (board toolbar)
  // ---------------------------------------------------------------------------
  for (final window in duoWindowCases) {
    for (final scale in _scales) {
      testWidgets('like tag menu fits ${window.name} at ${scale}x', (
        tester,
      ) async {
        _duo(tester, window);
        final offers = TagChipOfferController()..open('game', ['Sacrifice']);
        addTearDown(offers.dispose);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [tagChipOfferProvider.overrideWithValue(offers)],
            child: _app(
              scale: scale,
              child: Scaffold(
                appBar: AppBar(
                  actions: [
                    ValueListenableBuilder<TagOffer?>(
                      valueListenable: offers.current,
                      builder: (context, offer, _) => offer == null
                          ? const SizedBox.shrink()
                          : LikeTagChip(
                              key: ValueKey(offer.token),
                              offer: offer,
                            ),
                    ),
                    const SizedBox(width: 16),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 600));
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Sacrifice'));
        await tester.pump(const Duration(milliseconds: 700));
        expect(tester.takeException(), isNull);
        final panel = tester.getRect(
          find
              .ancestor(
                of: find.byType(GridView),
                matching: find.byType(Material),
              )
              .first,
        );
        expect(panel.left, greaterThanOrEqualTo(0));
        expect(panel.right, lessThanOrEqualTo(window.size.width));
        expect(panel.bottom, lessThanOrEqualTo(window.size.height));
        await tester.ensureVisible(find.text('Opening'));
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tap(find.text('Opening').hitTestable());
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.text('2 selected'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 1));
      });
    }
  }

  // ---------------------------------------------------------------------------
  // Board opening explorer panel (gamebase explorer beside the board)
  // ---------------------------------------------------------------------------
  for (final window in duoWindowCases) {
    for (final scale in _scales) {
      testWidgets('board explorer panel fits ${window.name} at ${scale}x', (
        tester,
      ) async {
        _duo(tester, window);
        final moves = <String>[];
        final container = ProviderContainer(
          overrides: [
            gamebaseRepositoryProvider.overrideWithValue(_Gamebase()),
            boardSettingsProviderNew.overrideWith(_BoardSettings.new),
            engineSettingsProviderNew.overrideWith(_EngineSettings.new),
          ],
        );
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: _app(
              scale: scale,
              child: Scaffold(
                body: SafeArea(
                  child: BoardOpeningExplorerPanel(
                    currentFen: _startFen,
                    startingFen: _startFen,
                    lineUcis: const <String>[],
                    onMoveSelected: moves.add,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 250));
        await tester.pump(const Duration(milliseconds: 50));
        await tester.pump(const Duration(milliseconds: 300));
        expect(tester.takeException(), isNull);
        for (final key in [
          'opening_explorer_sort_games',
          'opening_explorer_filter_button',
        ]) {
          await _expectReachable(tester, find.byKey(ValueKey(key)));
        }
        // The e4 row, found by its game count (its move-number cell; the SAN is a figurine span).
        final e4 = find.text('1.');
        await _expectReachable(tester, e4.first);
        await tester.tap(e4.first);
        await tester.pump(const Duration(milliseconds: 300));
        expect(moves, contains('e2e4'));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        container.dispose();
      });
    }
  }

  // ---------------------------------------------------------------------------
  // Board editor at default text (its own test covers 1.3x transitions)
  // ---------------------------------------------------------------------------
  for (final window in duoWindowCases) {
    testWidgets('board editor fits ${window.name} at 1.0x', (tester) async {
      _duo(tester, window);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            boardSettingsProviderNew.overrideWith(_BoardSettings.new),
            spaceShortcutsProvider.overrideWith(_MemorySpace.new),
            ecoPositionIndexProvider.overrideWith(
              (ref) async => buildEcoPositionIndex(),
            ),
            gameCardEvalWithStockfishFallbackProvider.overrideWith(
              (ref, fen) async => CloudEval(
                fen: fen,
                knodes: 1,
                depth: 20,
                pvs: [Pv(moves: 'e2e4', cp: 20)],
              ),
            ),
          ],
          child: _app(scale: 1.0, child: boardEditorAt(_startFen)),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
      final board = tester.getRect(find.byType(ChessboardEditor));
      final pad = tester.view.padding;
      expect(board.left, greaterThanOrEqualTo(pad.left / 3 - 0.5));
      expect(
        board.right,
        lessThanOrEqualTo(window.size.width - pad.right / 3 + 0.5),
      );
      expect(
        board.bottom,
        lessThanOrEqualTo(window.size.height - pad.bottom / 3 + 0.5),
      );
      for (final label in ['Analyze', 'Paste FEN', 'Paste PGN']) {
        await _expectReachable(tester, find.text(label));
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 10));
    });
  }

  // ---------------------------------------------------------------------------
  // Switch Views coachmark (Explorer <-> Notation)
  // ---------------------------------------------------------------------------
  for (final window in duoWindowCases) {
    for (final scale in _scales) {
      group('coachmark', () {
        testWidgets('switch views coachmark fits ${window.name} at ${scale}x', (
          tester,
        ) async {
          _duo(tester, window);
          var dismissed = 0;
          var never = 0;
          final animation = AnimationController(
            vsync: const TestVSync(),
            duration: const Duration(seconds: 1),
          );
          addTearDown(animation.dispose);
          await tester.pumpWidget(
            _app(
              scale: scale,
              child: SwitchViewsTutorialOverlay(
                onDismiss: () => dismissed++,
                onDontShowAgain: () => never++,
                animationController: animation,
                moveAnimation: animation,
                fadeAnimation: animation,
                scaleAnimation: animation,
                currentPageIndex: 0,
                totalItems: 2,
                currentStep: 1,
                totalSteps: 2,
              ),
            ),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 600));
          expect(tester.takeException(), isNull);
          for (final label in ['Switch Views', "Don't show again", 'Got it']) {
            await _expectReachable(tester, find.text(label));
          }
          await tester.tap(find.text("Don't show again"));
          await tester.pump(const Duration(milliseconds: 600));
          expect(never, 1);
          expect(dismissed, 0);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump(const Duration(seconds: 9));
        });
      });
    }
  }
}

// -----------------------------------------------------------------------------
// Harness
// -----------------------------------------------------------------------------

const _startFen = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';

/// The four directed folded<->unfolded transitions.
Iterable<DuoWindowTransition> get _foldTransitions =>
    duoWindowTransitions.where((t) => t.from.unfolded != t.to.unfolded);

void _duo(
  WidgetTester tester,
  DuoWindowCase window, {
  bool mirrorInsets = false,
}) {
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  applyDuoWindow(tester, window, mirrorInsets: mirrorInsets);
}

Widget _app({required double scale, required Widget child, Key? key}) =>
    MaterialApp(
      key: key,
      theme: AppTheme.darkTheme,
      builder: (_, child) => MediaQuery.withClampedTextScaling(
        minScaleFactor: scale,
        maxScaleFactor: scale,
        child: WindowOrientationScope(
          child: AdaptiveWindowScope(child: child!),
        ),
      ),
      home: child,
    );

Future<void> _expectReachable(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump(const Duration(milliseconds: 300));
  expect(finder.hitTestable(), findsWidgets, reason: finder.toString());
  final rect = tester.getRect(finder.hitTestable().first);
  final size = tester.view.physicalSize / tester.view.devicePixelRatio;
  expect(rect.left, greaterThanOrEqualTo(-0.5), reason: '$finder left');
  expect(rect.right, lessThanOrEqualTo(size.width + 0.5), reason: '$finder');
}

Future<void> _tapReachable(WidgetTester tester, Finder finder) async {
  await _expectReachable(tester, finder);
  await tester.tap(finder.hitTestable().first);
  await tester.pumpAndSettle();
}

// Save Analysis -----------------------------------------------------------------

Future<void> _openSaveAnalysis(
  WidgetTester tester, {
  required double scale,
}) async {
  final game = GamesTourModel(
    gameId: 'duo-save',
    source: GameSource.localAnalysis,
    whitePlayer: _card('White', ''),
    blackPlayer: _card('Black', ''),
    whiteTimeDisplay: '',
    blackTimeDisplay: '',
    whiteClockCentiseconds: 0,
    blackClockCentiseconds: 0,
    gameStatus: GameStatus.unknown,
    roundId: '',
    tourId: '',
  );
  final state = ChessBoardStateNew(game: game);
  final params = ChessBoardProviderParams(game: game, index: 0);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        chessBoardScreenProviderNew(
          params,
        ).overrideWith((ref) => _Board(state)),
        likedGamesProvider.overrideWith(_NoLikes.new),
        likedGamePendingTagsProvider(
          game.likeId,
        ).overrideWith((ref) => const <String>[]),
        libraryRepositoryProvider.overrideWithValue(_Library()),
        folderAnalysisCountProvider.overrideWith((ref, folderId) async => 1),
      ],
      child: _app(
        scale: scale,
        child: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => unawaited(
                  showSaveAnalysisSheet(
                    context: context,
                    state: state,
                    params: params,
                  ),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

class _Board extends StateNotifier<AsyncValue<ChessBoardStateNew>>
    implements ChessBoardScreenNotifierNew {
  _Board(ChessBoardStateNew initial) : super(AsyncData(initial));

  @override
  SavedAnalysisData? get savedAnalysisData => null;

  @override
  void updateSavedAnalysisTagsSnapshot(List<String> tags) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NoLikes extends LikedGamesNotifier {
  @override
  Future<List<SavedAnalysis>> build() async => [];
}

class _Library implements LibraryRepository {
  @override
  Future<List<LibraryFolder>> getFolders() async => [
    for (var i = 0; i < 8; i++)
      LibraryFolder(
        id: 'db-$i',
        userId: 'duo-user',
        name: 'Database $i',
        color: '#0FB4E5',
        icon: 'database',
        orderIndex: i,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      ),
  ];

  @override
  Future<List<SavedAnalysis>> getSavedAnalysesBySourceGame({
    required String sourceGameId,
  }) async => [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// Game Review -----------------------------------------------------------------

Future<GameAnalysisClaimResult> _allowClaim(String _) async =>
    const GameAnalysisClaimResult(
      allowed: true,
      reason: 'premium',
      isPremium: true,
    );

Future<MobileGameReviewController> _completedReview(WidgetTester tester) async {
  final controller = MobileGameReviewController(
    reportController: GameAnalysisReportController(evaluator: _evaluator),
    claimQuota: _allowClaim,
  );
  addTearDown(controller.dispose);
  final game = _game();
  await tester.runAsync(() async {
    controller.configure(
      game: ChessGame.fromPgn(
        'duo-review',
        '[White "Ada"]\n[Black "Grace"]\n[Result "1-0"]\n\n1. e4 e5 1-0',
      ),
      active: true,
      finished: true,
      whiteRating: game.whitePlayer.rating,
      blackRating: game.blackPlayer.rating,
    );
    await controller.retry();
    for (
      var i = 0;
      i < 50 &&
          controller.reviewState.reportState.status !=
              GameReportStatus.completed;
      i++
    ) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  });
  expect(controller.reviewState.reportState.status, GameReportStatus.completed);
  return controller;
}

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

PlayerCard _card(String name, String title, [int rating = 0]) => PlayerCard(
  name: name,
  federation: '',
  title: title,
  rating: rating,
  countryCode: '',
  team: null,
);

GamesTourModel _game() => GamesTourModel(
  gameId: 'duo-review-game',
  whitePlayer: _card('Ada Lovelace-Byron of a Very Long Name', 'GM', 2100),
  blackPlayer: _card('Grace Brewster Murray Hopper', 'WIM', 2050),
  whiteTimeDisplay: '',
  blackTimeDisplay: '',
  whiteClockCentiseconds: 0,
  blackClockCentiseconds: 0,
  gameStatus: GameStatus.whiteWins,
  roundId: 'round',
  tourId: 'tour',
);

// Country ---------------------------------------------------------------------

class _Country extends StateNotifier<AsyncValue<Country>>
    implements SelectedCountryNotifier {
  _Country() : super(AsyncData(CountryService().findByCode('NO')!));

  @override
  String getCountryName(String code) => CountryService().findByCode(code)!.name;

  @override
  void selectCountry(String code) {
    state = AsyncData(CountryService().findByCode(code)!);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// Explorer --------------------------------------------------------------------

class _BoardSettings extends BoardSettingsNotifierNew {
  @override
  Future<BoardSettingsNew> build() async => const BoardSettingsNew();
}

class _EngineSettings extends EngineSettingsNotifierNew {
  @override
  Future<EngineSettings> build() async =>
      const EngineSettings(showEngineAnalysis: false);
}

class _Gamebase extends GamebaseRepository {
  _Gamebase() : super(Dio(), baseUrl: 'http://localhost', apiKey: 'test');

  @override
  Future<GamebaseResponse> getMoveAggregates({
    required String fen,
    List<String> moves = const [],
    String? playerId,
    TimeControl? timeControl,
    int? minRating,
    int? maxRating,
    String? color,
    String? result,
    int? yearFrom,
    int? yearTo,
    bool? isOnline,
  }) async => GamebaseResponse(
    status: 'success',
    data: GamebaseData(
      moves: const [
        MoveAggregate(
          uci: 'e2e4',
          white: 412345,
          black: 301234,
          draws: 398765,
          total: 1112344,
        ),
        MoveAggregate(
          uci: 'd2d4',
          white: 312345,
          black: 201234,
          draws: 298765,
          total: 812344,
        ),
        MoveAggregate(uci: 'g1f3', white: 10, black: 6, draws: 4, total: 20),
        MoveAggregate(uci: 'b2b4', white: 1, black: 0, draws: 0, total: 1),
      ],
    ),
  );

  @override
  Future<GamebaseSearchQueryResponse> getFenPositionGames({
    required String fen,
    String? uci,
    TimeControl? timeControl,
    String? playerId,
    String? color,
    String? result,
    int? minRating,
    int? maxRating,
    int? yearFrom,
    int? yearTo,
    GamebaseSortField? sortBy,
    GamebaseSortDirection? sortDirection,
    bool? isOnline,
    int notationPlies = 0,
    int pageNumber = 0,
    int pageSize = 20,
  }) async => GamebaseSearchQueryResponse(
    status: 'success',
    data: const [],
    metadata: GamebasePaginationMetadata(
      pageNumber: pageNumber,
      pageSize: pageSize,
      totalCount: 0,
      hasMoreValue: false,
    ),
  );

  @override
  Future<GamebaseGameWithPgn?> getGameWithPgn(String id) async => null;
}

// Board editor ------------------------------------------------------------------

/// My Space in memory: never touches SQLite or Supabase.
class _MemorySpace extends SpaceShortcutsNotifier {
  @override
  Future<List<SpaceShortcut>> build() async => const [];
}
