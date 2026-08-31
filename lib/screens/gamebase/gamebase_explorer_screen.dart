import 'dart:async';
import 'dart:math' as math;

import 'package:chessever2/e2e/e2e_ids.dart';
import 'package:chessever2/revenue_cat_service/subscribe_state.dart';
import 'package:chessever2/screens/board_editor/board_editor_screen.dart';
import 'package:chessever2/screens/chessboard/notation/notation_pointer.dart';
import 'package:chessever2/screens/chessboard/notation/notation_token_builder.dart';
import 'package:chessever2/screens/chessboard/notation/notation_tree.dart';
import 'package:chessever2/screens/chessboard/widgets/engine_pv_layouts.dart';
import 'package:chessever2/screens/chessboard/widgets/nag_display.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/figurine_notation.dart';
import 'package:chessground/chessground.dart';
import 'package:collection/collection.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'package:chessever2/providers/board_settings_provider_new.dart';
import 'package:chessever2/providers/engine_settings_provider.dart';
import 'package:chessever2/screens/chessboard/chess_board_screen_new.dart';
import 'package:chessever2/screens/chessboard/analysis/chess_game_navigator.dart';
import 'package:chessever2/screens/chessboard/provider/chess_board_screen_provider_new.dart';
import 'package:chessever2/screens/chessboard/utils/engine_pv_palette.dart';
import 'package:chessever2/screens/settings/settings_page.dart';
import 'package:chessever2/screens/chessboard/widgets/chess_board_bottom_nav_bar.dart';
import 'package:chessever2/screens/chessboard/widgets/evaluation_bar_widget.dart';
import 'package:chessever2/screens/chessboard/widgets/share_game_screen.dart';
import 'package:chessever2/screens/chessboard/widgets/switch_views_tutorial_overlay.dart';
import 'package:chessever2/screens/gamebase/providers/explorer_eval_provider.dart';
import 'package:chessever2/screens/gamebase/utils/board_workspace_coachmarks.dart';
import 'package:chessever2/screens/gamebase/utils/explorer_share_utils.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/gamebase/services/player_opening_tree.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/screen_wrapper.dart';
import 'package:chessever2/repository/local_storage/local_storage_repository.dart';
import 'package:chessever2/widgets/game_filter/rating_tier_filter.dart';
import 'package:chessever2/widgets/game_filter/wheel_range_filter.dart';
import 'package:chessever2/screens/gamebase/providers/explorer_game_focus_provider.dart';
import 'package:chessever2/screens/gamebase/providers/gamebase_providers.dart';
import 'package:chessever2/screens/gamebase/providers/gamebase_explorer_state.dart';
import 'package:chessever2/screens/gamebase/widgets/widgets.dart';
import 'package:chessever2/screens/gamebase/widgets/board_workspace_controls.dart';
import 'package:chessever2/screens/gamebase/models/models.dart';
import 'package:chessever2/main.dart' show routeObserver;
import 'package:chessever2/widgets/app_snack.dart';
import 'package:chessever2/widgets/auth/auth_upgrade_sheet.dart';
import 'package:chessever2/widgets/paywall/premium_paywall_sheet.dart';

/// Main screen for exploring the Gamebase opening database.
/// Displays a chess board, move statistics, and navigation controls.
class GamebaseExplorerScreen extends ConsumerStatefulWidget {
  const GamebaseExplorerScreen({
    super.key,
    this.initialPlayer,
    this.initialFilters,
    this.enableWorkspaceCoachmarks = true,
  });

  /// Creates an isolated explorer scope so other mounted routes (for example
  /// hidden player-profile/game-card widgets) cannot mutate this explorer's
  /// provider state and continuously restart engine analysis.
  static Widget scoped({
    Key? key,
    GamebasePlayer? initialPlayer,
    GamebaseFilters? initialFilters,
    bool enableWorkspaceCoachmarks = true,
  }) {
    return ProviderScope(
      overrides: [
        gamebaseExplorerProvider.overrideWith(
          (ref) => GamebaseExplorerNotifier(ref),
        ),
        explorerEvalProvider.overrideWith((ref) => ExplorerEvalNotifier(ref)),
      ],
      child: GamebaseExplorerScreen(
        key: key,
        initialPlayer: initialPlayer,
        initialFilters: initialFilters,
        enableWorkspaceCoachmarks: enableWorkspaceCoachmarks,
      ),
    );
  }

  /// When non-null, the explorer opens pre-filtered to this player's games.
  final GamebasePlayer? initialPlayer;

  /// Optional filters to pre-apply (e.g. time control, rating from player profile).
  final GamebaseFilters? initialFilters;

  /// Test and embedding escape hatch. Normal Board entries teach the shared
  /// views and Editor once; focused widget tests can disable the persistence IO.
  final bool enableWorkspaceCoachmarks;

  @override
  ConsumerState<GamebaseExplorerScreen> createState() =>
      _GamebaseExplorerScreenState();
}

class _GamebaseExplorerScreenState extends ConsumerState<GamebaseExplorerScreen>
    with RouteAware, WidgetsBindingObserver {
  bool _isFlipped = false;
  bool _routeActive = true;
  bool _appIsResumed = true;
  Timer? _backwardLongPressTimer;
  Timer? _forwardLongPressTimer;
  final GlobalKey<TooltipState> _viewsCoachmarkKey = GlobalKey<TooltipState>();
  final GlobalKey<TooltipState> _editorCoachmarkKey = GlobalKey<TooltipState>();

  void _resetExplorerState({bool fetch = false, bool preserveScope = true}) {
    final notifier = ref.read(gamebaseExplorerProvider.notifier);
    final evalNotifier = ref.read(explorerEvalProvider.notifier);
    final scopedPlayer = preserveScope ? widget.initialPlayer : null;

    evalNotifier.clearPvPreview(resumeEvaluation: fetch);

    if (fetch && scopedPlayer != null) {
      notifier.enableLocalPlayerTree(scopedPlayer.id);
      ref.read(playerOpeningTreeProvider(scopedPlayer.id).notifier).start();
      final filters = preserveScope ? widget.initialFilters : null;
      if (filters != null) {
        notifier.initializeWithPlayerAndFilters(scopedPlayer, filters);
      } else {
        notifier.initializeWithPlayer(scopedPlayer);
      }
    } else {
      notifier.disableLocalPlayerTree();
      notifier.reset(fetch: fetch);
    }

    // On teardown (fetch=false), explicitly stop the engine.
    // On init (fetch=true), let _ExplorerEvalBar handle engine lifecycle
    // via its initState/didUpdateWidget to avoid double-start conflicts
    // that cause depth jitter and perpetual "..." states.
    if (!fetch) {
      evalNotifier.setEngineEnabled(
        enabled: false,
        fen: ref.read(gamebaseExplorerProvider).currentFen,
      );
    }
  }

  bool _shouldShowClearFilters(GamebaseExplorerState state) {
    final scopedPlayer = widget.initialPlayer;
    if (scopedPlayer == null) return state.hasActiveFilters;

    final hasRatingOrTimeFilters =
        state.filters.timeControls.isNotEmpty ||
        state.filters.minRating != null ||
        state.filters.maxRating != null ||
        state.filters.yearFrom != null ||
        state.filters.yearTo != null;

    final hasColorFilter = state.filters.playerColor != null;
    final hasResultFilter = state.filters.gameResult != null;
    final hasFormatFilter = state.filters.isOnline != null;

    final hasDifferentPlayerScope =
        state.filters.playerIds.length != 1 ||
        state.filters.playerIds.first != scopedPlayer.id ||
        state.filters.selectedPlayers.length != 1 ||
        state.filters.selectedPlayers.first.id != scopedPlayer.id;

    return hasRatingOrTimeFilters ||
        hasColorFilter ||
        hasResultFilter ||
        hasFormatFilter ||
        hasDifferentPlayerScope;
  }

  void _pauseScopedOpeningTree() {
    final scopedPlayerId = widget.initialPlayer?.id;
    if (scopedPlayerId == null || scopedPlayerId.isEmpty) return;
    final treeState = ref.read(playerOpeningTreeProvider(scopedPlayerId));
    if (treeState.progress.isRunning) {
      ref.read(playerOpeningTreeProvider(scopedPlayerId).notifier).cancel();
    }
  }

  void _resumeScopedOpeningTree() {
    if (!_routeActive || !_appIsResumed) return;
    final scopedPlayerId = widget.initialPlayer?.id;
    if (scopedPlayerId == null || scopedPlayerId.isEmpty) return;
    final treeState = ref.read(playerOpeningTreeProvider(scopedPlayerId));
    if (treeState.progress.status == PlayerOpeningTreeStatus.canceled) {
      ref.read(playerOpeningTreeProvider(scopedPlayerId).notifier).start();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    routeObserver.subscribe(this, ModalRoute.of(context)!);
  }

  @override
  void didPushNext() {
    // Another route was pushed on top — this explorer is now in the background.
    // Disable its engine to prevent Stockfish contention with the foreground
    // explorer (which also uses isCurrentPosition: true). Multiple background
    // explorers retrying after cancellation cause an infinite preemption cycle.
    setState(() => _routeActive = false);
    _pauseScopedOpeningTree();
    super.didPushNext();
  }

  @override
  void didPopNext() {
    // The route on top was popped — this explorer is visible again.
    // Re-enable its engine so the eval restarts.
    setState(() => _routeActive = true);
    _resumeScopedOpeningTree();
    super.didPopNext();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    _appIsResumed = state == AppLifecycleState.resumed;
    if (_appIsResumed) {
      _resumeScopedOpeningTree();
    } else {
      _pauseScopedOpeningTree();
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Riverpod best practice: never modify providers synchronously in widget
    // lifecycles (can happen while the widget tree is building).
    // Defer to post-frame to keep provider updates safe.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      // A fresh Board entry starts in Explorer. Returning from Board Editor
      // keeps this screen alive, so the current workspace is not reset.
      ref.read(explorerPageIndexProvider.notifier).state =
          boardWorkspaceDefaultPage;
      _resetExplorerState(fetch: true);
      if (widget.enableWorkspaceCoachmarks) {
        unawaited(_showWorkspaceCoachmarks());
      }
    });
  }

  Future<void> _showWorkspaceCoachmarks() async {
    await showBoardWorkspaceCoachmarks(
      viewsTracker: boardWorkspaceViewsCoachmarkTracker,
      editorTracker: boardWorkspaceEditorCoachmarkTracker,
      isEligible: () => mounted && _routeActive,
      showViews:
          () =>
              _viewsCoachmarkKey.currentState?.ensureTooltipVisible() ?? false,
      showEditor: () {
        Tooltip.dismissAllToolTips();
        return _editorCoachmarkKey.currentState?.ensureTooltipVisible() ??
            false;
      },
    );
  }

  @override
  void dispose() {
    Tooltip.dismissAllToolTips();
    WidgetsBinding.instance.removeObserver(this);
    routeObserver.unsubscribe(this);
    _stopLongPressBackward();
    _stopLongPressForward();
    super.dispose();
  }

  static final double _evalBarWidth = 20.sp;

  Future<void> _toggleEngineAnalysis() async {
    final current = ref.read(engineSettingsProviderNew).valueOrNull;
    final nextValue = !(current?.showEngineAnalysis ?? true);
    if (!nextValue) {
      ref
          .read(explorerEvalProvider.notifier)
          .clearPvPreview(resumeEvaluation: false);
    }
    await ref
        .read(engineSettingsProviderNew.notifier)
        .toggleEngineAnalysis(nextValue);
  }

  void _startLongPressBackward() {
    _backwardLongPressTimer?.cancel();
    _backwardLongPressTimer = Timer.periodic(
      const Duration(milliseconds: 130),
      (_) {
        final focusState = ref.read(explorerFocusedGameProvider);
        if (focusState != null) {
          if (!focusState.canGoBackward) {
            _stopLongPressBackward();
            return;
          }
          ref.read(explorerFocusedGameProvider.notifier).backward();
          return;
        }
        final preview = ref.read(explorerEvalProvider).pvPreview;
        if (preview != null) {
          if (!preview.canMoveBackward) {
            _stopLongPressBackward();
            return;
          }
          ref.read(explorerEvalProvider.notifier).navigateLockedPvBackward();
          return;
        }
        final currentState = ref.read(gamebaseExplorerProvider);
        if (!currentState.canGoBack) {
          _stopLongPressBackward();
          return;
        }
        ref.read(gamebaseExplorerProvider.notifier).goBack();
      },
    );
  }

  void _stopLongPressBackward() {
    _backwardLongPressTimer?.cancel();
    _backwardLongPressTimer = null;
  }

  void _startLongPressForward() {
    _forwardLongPressTimer?.cancel();
    _forwardLongPressTimer = Timer.periodic(const Duration(milliseconds: 130), (
      _,
    ) {
      final focusState = ref.read(explorerFocusedGameProvider);
      if (focusState != null) {
        if (!focusState.canGoForward) {
          _stopLongPressForward();
          return;
        }
        ref.read(explorerFocusedGameProvider.notifier).forward();
        return;
      }
      final preview = ref.read(explorerEvalProvider).pvPreview;
      if (preview != null) {
        if (!preview.canMoveForward) {
          _stopLongPressForward();
          return;
        }
        ref.read(explorerEvalProvider.notifier).navigateLockedPvForward();
        return;
      }
      final currentState = ref.read(gamebaseExplorerProvider);
      if (!currentState.canGoForward) {
        _stopLongPressForward();
        return;
      }
      // About to cross the free-tier boundary — halt the auto-repeat and
      // surface the paywall instead of silently parking the user on a
      // blurred panel.
      if (_forwardStepWouldCrossFreeLimit()) {
        _stopLongPressForward();
        unawaited(requirePremiumGuard(context, ref));
        return;
      }
      ref.read(gamebaseExplorerProvider.notifier).goForward();
    });
  }

  void _stopLongPressForward() {
    _forwardLongPressTimer?.cancel();
    _forwardLongPressTimer = null;
  }

  /// Returns true when a single forward ply from the current explorer state
  /// would land past the free-tier move limit for a non-subscriber.
  bool _forwardStepWouldCrossFreeLimit() {
    if (kDebugMode) return false;
    if (ref.read(subscriptionProvider).isSubscribed) return false;
    final currentMoveNumber =
        ref.read(gamebaseExplorerProvider.notifier).effectiveMoveNumber;
    return currentMoveNumber >= kFreeExplorerMoveNumberLimit;
  }

  /// Gate for any user action that advances the explorer by a single ply.
  /// If the next step would cross the free-tier boundary, the paywall is
  /// shown immediately and this returns whether the user just subscribed.
  Future<bool> _ensureExplorerForwardAllowed() async {
    if (!_forwardStepWouldCrossFreeLimit()) return true;
    if (!mounted) return false;
    return requirePremiumGuard(context, ref);
  }

  @override
  Widget build(BuildContext context) {
    final showEngineAnalysis =
        _routeActive &&
        ref.watch(
          engineSettingsProviderNew.select(
            (s) => s.valueOrNull?.showEngineAnalysis ?? true,
          ),
        );

    final state = ref.watch(gamebaseExplorerProvider);
    final preview = ref.watch(
      explorerEvalProvider.select((value) => value.pvPreview),
    );
    // Trello #984: a focused explorer game card owns the arrows and walks its
    // continuation; the explorer position stays put until focus is released.
    final explorerFocus = ref.watch(explorerFocusedGameProvider);
    final explorerFocusNotifier = ref.read(
      explorerFocusedGameProvider.notifier,
    );
    // Swiping the panel over to the notation page releases the focus.
    ref.listen<int>(explorerPageIndexProvider, (previous, next) {
      if (next != 0) {
        ref.read(explorerFocusedGameProvider.notifier).clear();
      }
    });
    final canMoveForward =
        explorerFocus?.canGoForward ??
        (preview?.canMoveForward ?? state.canGoForward);
    final canMoveBackward =
        explorerFocus?.canGoBackward ??
        (preview?.canMoveBackward ?? state.canGoBack);
    final scopedPlayerId = widget.initialPlayer?.id;
    if (scopedPlayerId != null && scopedPlayerId.isNotEmpty) {
      ref.listen<PlayerOpeningTreeState>(
        playerOpeningTreeProvider(scopedPlayerId),
        (previous, next) {
          if (previous?.index == next.index &&
              previous?.progress.status == next.progress.status &&
              previous?.progress.error == next.progress.error) {
            return;
          }
          Future.microtask(() {
            if (!mounted) return;
            ref
                .read(gamebaseExplorerProvider.notifier)
                .syncLocalPlayerTree(scopedPlayerId);
          });
        },
      );
    }

    return ScreenWrapper(
      child: PopScope(
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop) return;
          _resetExplorerState();
        },
        child: Scaffold(
          key: e2eKey(E2eIds.openingExplorerRoot),
          backgroundColor: context.colors.surface,
          appBar: _buildAppBar(context),
          bottomNavigationBar: ChessBoardBottomNavBar(
            gameIndex: 0,
            onFlip: () => setState(() => _isFlipped = !_isFlipped),
            toggleEngineVisibility: _toggleEngineAnalysis,
            onEngineSettingsLongPress: () {
              requireFullAuthGuard(context).then((allowed) {
                if (!allowed || !context.mounted) return;
                Navigator.of(context).push(
                  SettingsPage.route(initiallyExpanded: SettingsSection.board),
                );
              });
            },
            onRightMove:
                explorerFocus != null
                    ? (explorerFocus.canGoForward
                        ? explorerFocusNotifier.forward
                        : null)
                    : canMoveForward
                    ? () async {
                      if (preview != null) {
                        ref
                            .read(explorerEvalProvider.notifier)
                            .navigateLockedPvForward();
                        return;
                      }
                      final allowed = await _ensureExplorerForwardAllowed();
                      if (!allowed) return;
                      ref.read(gamebaseExplorerProvider.notifier).goForward();
                    }
                    : null,
            onLeftMove:
                explorerFocus != null
                    ? (explorerFocus.canGoBackward
                        ? explorerFocusNotifier.backward
                        : null)
                    : canMoveBackward
                    ? () {
                      if (preview != null) {
                        ref
                            .read(explorerEvalProvider.notifier)
                            .navigateLockedPvBackward();
                        return;
                      }
                      ref.read(gamebaseExplorerProvider.notifier).goBack();
                    }
                    : null,
            onLongPressBackwardStart:
                canMoveBackward ? _startLongPressBackward : null,
            onLongPressBackwardEnd: _stopLongPressBackward,
            onLongPressForwardStart:
                canMoveForward ? _startLongPressForward : null,
            onLongPressForwardEnd: _stopLongPressForward,
            canMoveForward: canMoveForward,
            canMoveBackward: canMoveBackward,
            showEngineAnalysis: showEngineAnalysis,
            showUnseenMoveBadge: false,
            showGamebaseButton: false,
          ),
          body: LayoutBuilder(
            builder: (context, constraints) {
              final isTablet = ResponsiveHelper.isTablet;
              final isLandscape = ResponsiveHelper.isLandscape;

              if (isTablet && isLandscape) {
                return _buildTabletLandscapeLayout(
                  constraints,
                  showEngineAnalysis: showEngineAnalysis,
                );
              } else if (isTablet) {
                return _buildTabletPortraitLayout(
                  constraints,
                  showEngineAnalysis: showEngineAnalysis,
                );
              } else {
                return _buildPhoneLayout(
                  constraints,
                  showEngineAnalysis: showEngineAnalysis,
                );
              }
            },
          ),
        ),
      ),
    );
  }

  /// Phone layout — identical to the original layout.
  Widget _buildPhoneLayout(
    BoxConstraints constraints, {
    required bool showEngineAnalysis,
  }) {
    final state = ref.watch(gamebaseExplorerProvider);
    final preview = ref.watch(
      explorerEvalProvider.select((value) => value.pvPreview),
    );
    final boardFen = preview?.currentFen ?? state.currentFen;
    final boardSize = constraints.maxWidth - 48.sp - _evalBarWidth - 4.sp;

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: ResponsiveHelper.contentMaxWidth),
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.all(24.sp),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _ExplorerEvalBar(
                    fen: state.currentFen,
                    height: boardSize,
                    width: _evalBarWidth,
                    isFlipped: _isFlipped,
                    showEngineAnalysis: showEngineAnalysis,
                  ),
                  SizedBox(width: 4.sp),
                  _GamebaseChessBoard(
                    fen: boardFen,
                    boardSize: boardSize,
                    isFlipped: _isFlipped,
                    isPreviewing: preview != null,
                    lastMove: preview?.currentMove,
                  ),
                ],
              ),
            ),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: context.colors.surfaceRecessed,
                  borderRadius: BorderRadius.vertical(
                    top: Radius.circular(16.br),
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    if (showEngineAnalysis) const _ExplorerEngineLines(),
                    Expanded(
                      child: _ExplorerBottomPanels(
                        onFilter: () => _showFilterSheet(context),
                        hasActiveFilters: _shouldShowClearFilters(state),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Tablet landscape — side-by-side: board on left, stats panel on right.
  Widget _buildTabletLandscapeLayout(
    BoxConstraints constraints, {
    required bool showEngineAnalysis,
  }) {
    final state = ref.watch(gamebaseExplorerProvider);
    final preview = ref.watch(
      explorerEvalProvider.select((value) => value.pvPreview),
    );
    final boardFen = preview?.currentFen ?? state.currentFen;
    final availableHeight = constraints.maxHeight;
    final verticalPadding = 8.sp * 2; // top + bottom
    final boardSize = (availableHeight - verticalPadding).clamp(
      200.0,
      double.infinity,
    );
    final leftWidth = boardSize + _evalBarWidth + 4.sp + 24.sp;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 12.sp, vertical: 8.sp),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Left column: board + nav controls
          SizedBox(
            width: leftWidth,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _ExplorerEvalBar(
                      fen: state.currentFen,
                      height: boardSize,
                      width: _evalBarWidth,
                      isFlipped: _isFlipped,
                      showEngineAnalysis: showEngineAnalysis,
                    ),
                    SizedBox(width: 4.sp),
                    _GamebaseChessBoard(
                      fen: boardFen,
                      boardSize: boardSize,
                      isFlipped: _isFlipped,
                      isPreviewing: preview != null,
                      lastMove: preview?.currentMove,
                    ),
                  ],
                ),
              ],
            ),
          ),
          SizedBox(width: 12.sp),
          // Right column: stats panel
          Expanded(
            child: Container(
              height: availableHeight - verticalPadding,
              decoration: BoxDecoration(
                color: context.colors.surfaceRecessed,
                borderRadius: BorderRadius.circular(12.sp),
                border: Border.all(color: context.colors.divider),
              ),
              clipBehavior: Clip.antiAlias,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12.sp),
                child: Column(
                  children: [
                    if (showEngineAnalysis) const _ExplorerEngineLines(),
                    Expanded(
                      child: _ExplorerBottomPanels(
                        onFilter: () => _showFilterSheet(context),
                        hasActiveFilters: _shouldShowClearFilters(state),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Tablet portrait — centered column with constrained width.
  Widget _buildTabletPortraitLayout(
    BoxConstraints constraints, {
    required bool showEngineAnalysis,
  }) {
    final state = ref.watch(gamebaseExplorerProvider);
    final preview = ref.watch(
      explorerEvalProvider.select((value) => value.pvPreview),
    );
    final boardFen = preview?.currentFen ?? state.currentFen;
    final contentMaxWidth = (constraints.maxWidth * 0.85).clamp(0.0, 720.0);
    final boardSize = contentMaxWidth - 48.sp - _evalBarWidth - 4.sp;

    return SizedBox.expand(
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: contentMaxWidth),
          child: Column(
            children: [
              Padding(
                padding: EdgeInsets.all(24.sp),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _ExplorerEvalBar(
                      fen: state.currentFen,
                      height: boardSize,
                      width: _evalBarWidth,
                      isFlipped: _isFlipped,
                      showEngineAnalysis: showEngineAnalysis,
                    ),
                    SizedBox(width: 4.sp),
                    _GamebaseChessBoard(
                      fen: boardFen,
                      boardSize: boardSize,
                      isFlipped: _isFlipped,
                      isPreviewing: preview != null,
                      lastMove: preview?.currentMove,
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: context.colors.surfaceRecessed,
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(16.br),
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      if (showEngineAnalysis) const _ExplorerEngineLines(),
                      Expanded(
                        child: _ExplorerBottomPanels(
                          onFilter: () => _showFilterSheet(context),
                          hasActiveFilters: _shouldShowClearFilters(state),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context) {
    final currentPage = ref.watch(explorerPageIndexProvider);

    return AppBar(
      backgroundColor: context.colors.surface,
      elevation: 0,
      centerTitle: false,
      titleSpacing: 0,
      leading: IconButton(
        icon: Icon(Icons.arrow_back, size: 24.ic),
        onPressed: () => Navigator.of(context).pop(),
      ),
      title: Tooltip(
        key: _viewsCoachmarkKey,
        message: boardWorkspaceViewsCoachmarkMessage,
        triggerMode: TooltipTriggerMode.manual,
        preferBelow: true,
        showDuration: const Duration(seconds: 5),
        padding: EdgeInsets.symmetric(horizontal: 16.sp, vertical: 12.sp),
        decoration: BoxDecoration(
          color: const Color(0xFF08080A),
          borderRadius: BorderRadius.circular(16.br),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        textStyle: AppTypography.textSmMedium.copyWith(
          color: Colors.white.withValues(alpha: 0.94),
        ),
        child: _ExplorerSegmentedTitle(currentPage: currentPage, isLarge: true),
      ),
      actions: [
        IconButton(
          key: e2eKey(E2eIds.openingExplorerSaveButton),
          icon: Icon(
            Icons.save_outlined,
            size: 22.ic,
            semanticLabel: 'Save analysis',
          ),
          onPressed: () => _openAnalysisAndSave(context),
          tooltip: 'Save analysis',
        ),
        Tooltip(
          key: _editorCoachmarkKey,
          message: boardWorkspaceEditorCoachmarkMessage,
          triggerMode: TooltipTriggerMode.manual,
          preferBelow: true,
          showDuration: const Duration(seconds: 6),
          padding: EdgeInsets.symmetric(horizontal: 16.sp, vertical: 12.sp),
          decoration: BoxDecoration(
            color: const Color(0xFF08080A),
            borderRadius: BorderRadius.circular(16.br),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          textStyle: AppTypography.textSmMedium.copyWith(
            color: Colors.white.withValues(alpha: 0.94),
          ),
          child: IconButton(
            key: const ValueKey<String>('opening_explorer_board_editor'),
            onPressed: _openBoardEditor,
            tooltip: 'Board Editor',
            icon: const ExplorerBoardEditorIcon(),
          ),
        ),
        PopupMenuButton<ExplorerBoardMenuAction>(
          key: const ValueKey<String>('opening_explorer_more_menu'),
          tooltip: 'More board actions',
          icon: Icon(Icons.more_vert, size: 22.ic),
          onSelected: _handleBoardMenuAction,
          itemBuilder:
              (context) => [
                for (final item in explorerBoardMenuItems)
                  PopupMenuItem<ExplorerBoardMenuAction>(
                    value: item.action,
                    child: Row(
                      children: [
                        Icon(
                          item.icon,
                          color: context.colors.textPrimary,
                          size: 20.ic,
                        ),
                        SizedBox(width: 10.sp),
                        Text(item.label),
                      ],
                    ),
                  ),
              ],
        ),
      ],
    );
  }

  Future<void> _handleBoardMenuAction(ExplorerBoardMenuAction action) async {
    switch (action) {
      case ExplorerBoardMenuAction.copyPgn:
        await _copyExplorerPgn();
      case ExplorerBoardMenuAction.boardSettings:
        final allowed = await requireFullAuthGuard(context);
        if (!allowed || !mounted) return;
        await Navigator.of(
          context,
        ).push(SettingsPage.route(initiallyExpanded: SettingsSection.board));
      case ExplorerBoardMenuAction.share:
        await _shareExplorerBoard();
    }
  }

  String? _currentExplorerPgn() {
    final game = ref.read(gamebaseExplorerProvider).game;
    if (game == null) return null;
    final pgn = exportGameToPgn(game).trim();
    return pgn.isEmpty ? null : pgn;
  }

  Future<void> _copyExplorerPgn() async {
    final pgn = _currentExplorerPgn();
    if (pgn == null) {
      if (mounted) showAppSnack(context, 'No PGN to copy');
      return;
    }
    await Clipboard.setData(ClipboardData(text: pgn));
    if (!mounted) return;
    HapticFeedback.lightImpact();
    showAppSnack(context, 'PGN copied');
  }

  Future<void> _shareExplorerBoard() async {
    final state = ref.read(gamebaseExplorerProvider);
    final game = state.game;
    if (game == null) {
      if (mounted) showAppSnack(context, 'No analysis to share');
      return;
    }

    final payload = buildExplorerSharePayload(
      game: game,
      movePointer: state.movePointer,
      currentFen: state.currentFen,
    );
    final evalState = ref.read(explorerEvalProvider);
    final hasCurrentEval =
        explorerFenPositionKey(evalState.fen) ==
        explorerFenPositionKey(state.currentFen);

    await pushGameShareScreen(
      context: context,
      game: payload.tourGame,
      shareData: ResolvedGameShareData(
        pgn: payload.pgn,
        shareUrl: null,
        snapshot: payload.snapshot,
        evaluation: hasCurrentEval ? evalState.evaluation : null,
        mate: hasCurrentEval ? (evalState.mate ?? 0) : 0,
        isFlipped: _isFlipped,
        isAtGameEnd: false,
      ),
    );
  }

  Future<void> _openBoardEditor() async {
    final notifier = ref.read(gamebaseExplorerProvider.notifier);
    final currentFen = ref.read(gamebaseExplorerProvider).currentFen;
    final minimumMoveNumber = notifier.effectiveMoveNumber;
    final editedFen = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder:
            (_) => BoardEditorScreen(
              initialFen: currentFen,
              returnFenOnDone: true,
            ),
      ),
    );
    if (!mounted || editedFen == null || editedFen.trim().isEmpty) return;
    notifier.setPosition(
      editedFen,
      startingFen: editedFen,
      minimumMoveNumber: minimumMoveNumber,
    );
  }

  void _openAnalysisAndSave(BuildContext context) {
    final state = ref.read(gamebaseExplorerProvider);
    final game = state.game;
    if (game == null) return;

    final timestamp = DateTime.now().millisecondsSinceEpoch;

    // Use the notation tree helper to export full PGN with variations
    final pgn = exportGameToPgn(game);

    final whitePlayer = PlayerCard(
      name: game.metadata['White']?.toString() ?? 'White',
      federation: '',
      title: '',
      rating: 0,
      countryCode: '',
      team: null,
      fideId: null,
    );

    final blackPlayer = PlayerCard(
      name: game.metadata['Black']?.toString() ?? 'Black',
      federation: '',
      title: '',
      rating: 0,
      countryCode: '',
      team: null,
      fideId: null,
    );

    final tourGame = GamesTourModel(
      gameId: 'explorer_$timestamp',
      source: GameSource.openingExplorer,
      whitePlayer: whitePlayer,
      blackPlayer: blackPlayer,
      whiteTimeDisplay: '--:--',
      blackTimeDisplay: '--:--',
      whiteClockCentiseconds: 0,
      blackClockCentiseconds: 0,
      gameStatus: GameStatus.unknown,
      roundId: 'opening_explorer',
      tourId: 'opening_explorer',
      pgn: pgn,
    );

    ref.read(chessboardViewFromProviderNew.notifier).state =
        ChessboardView.tour;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder:
            (_) => ChessBoardScreenNew(
              currentIndex: 0,
              games: [tourGame],
              viewSource: ChessboardView.tour,
              hideEventInfo: true,
              showGamebaseButton: false,
              disableGamebaseOverlayByDefault: true,
              startAtLastMove: true,
              showSaveAnalysisOnLoad: true,
            ),
      ),
    );
  }

  void _showFilterSheet(BuildContext context) {
    final container = ProviderScope.containerOf(context);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.colors.surfaceRecessed,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16.br)),
      ),
      constraints: ResponsiveHelper.bottomSheetConstraints,
      builder:
          (_) => UncontrolledProviderScope(
            container: container,
            child: _FilterSheet(scopedPlayer: widget.initialPlayer),
          ),
    );
  }
}

/// Chess board widget for displaying the current position.
class _GamebaseChessBoard extends ConsumerStatefulWidget {
  const _GamebaseChessBoard({
    required this.fen,
    required this.boardSize,
    required this.isPreviewing,
    this.lastMove,
    this.isFlipped = false,
  });

  final String fen;
  final double boardSize;
  final bool isFlipped;
  final bool isPreviewing;
  final Move? lastMove;

  @override
  ConsumerState<_GamebaseChessBoard> createState() =>
      _GamebaseChessBoardState();
}

class _GamebaseChessBoardState extends ConsumerState<_GamebaseChessBoard> {
  // We used to bump a _selectionEpoch and re-key the Chessboard on every
  // external FEN change to clear chessground's tap-selection — but the
  // resulting widget remount made chessground's didUpdateWidget never run,
  // which skipped its built-in piece-translation animation. Keep the key
  // stable; chessground clears its own selection on the next board tap.

  // chessground v10 drives the interactive board through a controller instead
  // of rebuilding the widget with a new fen. We own it here and feed it new
  // positions via [updatePosition] whenever the external fen changes.
  late final ChessboardController _boardController;

  @override
  void initState() {
    super.initState();
    _boardController = ChessboardController(
      game: _gameDataFor(
        widget.fen,
        isPreviewing: widget.isPreviewing,
        lastMove: widget.lastMove,
      ),
    );
  }

  @override
  void didUpdateWidget(covariant _GamebaseChessBoard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.fen != widget.fen ||
        oldWidget.isPreviewing != widget.isPreviewing ||
        oldWidget.lastMove != widget.lastMove) {
      _boardController.updatePosition(
        _gameDataFor(
          widget.fen,
          isPreviewing: widget.isPreviewing,
          lastMove: widget.lastMove,
        ),
      );
    }
  }

  @override
  void dispose() {
    _boardController.dispose();
    super.dispose();
  }

  /// Builds chessground [GameData] from a fen. Falls back to a non-interactive
  /// snapshot when the fen is not a legal chess position (the board still
  /// renders the placement via the lenient [readFen]).
  GameData _gameDataFor(
    String fen, {
    required bool isPreviewing,
    Move? lastMove,
  }) {
    Chess? position;
    try {
      position = Chess.fromSetup(Setup.parseFen(fen));
    } catch (_) {
      position = null;
    }
    if (position == null) {
      return GameData(
        fen: fen,
        playerSide: PlayerSide.none,
        sideToMove: Side.white,
        validMoves: const {},
        lastMove: lastMove,
      );
    }
    return GameData(
      fen: fen,
      playerSide:
          isPreviewing
              ? PlayerSide.none
              : (position.turn == Side.white
                  ? PlayerSide.white
                  : PlayerSide.black),
      sideToMove: position.turn,
      validMoves: makeLegalMoves(position),
      lastMove: lastMove,
      kingSquareInCheck:
          position.isCheck ? position.board.kingOf(position.turn) : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final boardSettingsAsync = ref.watch(boardSettingsProviderNew);
    final boardSettings =
        boardSettingsAsync.valueOrNull ?? const BoardSettingsNew();
    final notifier = ref.read(gamebaseExplorerProvider.notifier);

    Chess? position;
    try {
      position = Chess.fromSetup(Setup.parseFen(widget.fen));
    } catch (_) {
      position = null;
    }

    return Container(
      height: widget.boardSize,
      width: widget.boardSize,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4.br),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4.br),
        child:
            position == null
                ? StaticChessboard(
                  size: widget.boardSize,
                  settings: StaticChessboardSettings(
                    enableCoordinates: boardSettings.showCoordinates,
                    colorScheme: boardSettings.colorScheme,
                    pieceAssets: boardSettings.pieceAssets,
                  ),
                  orientation: widget.isFlipped ? Side.black : Side.white,
                  fen: widget.fen,
                )
                : Chessboard(
                  size: widget.boardSize,
                  controller: _boardController,
                  settings: ChessboardSettings(
                    enableCoordinates: boardSettings.showCoordinates,
                    animationDuration: const Duration(milliseconds: 200),
                    colorScheme: boardSettings.colorScheme,
                    pieceAssets: boardSettings.pieceAssets,
                    pieceShiftMethod: PieceShiftMethod.tapTwoSquares,
                    autoQueenPromotionOnPremove: false,
                    enablePremoves: false,
                  ),
                  orientation: widget.isFlipped ? Side.black : Side.white,
                  // chessground v10: promotion is resolved inside the board,
                  // so onMove receives the fully-resolved move (promotion role
                  // already set) and lives on the widget, not GameData.
                  onMove: (Move move, {bool? viaDragAndDrop}) async {
                    if (ref.read(explorerEvalProvider).pvPreview != null) {
                      return;
                    }
                    // Playing this move would land past the free-tier
                    // boundary — surface the paywall instead of advancing
                    // and then blurring the panel. Chessground snaps the
                    // piece back when state doesn't change.
                    if (!kDebugMode &&
                        !ref.read(subscriptionProvider).isSubscribed) {
                      final currentMoveNumber =
                          ref
                              .read(gamebaseExplorerProvider.notifier)
                              .effectiveMoveNumber;
                      if (currentMoveNumber >= kFreeExplorerMoveNumberLimit) {
                        if (!context.mounted) return;
                        final unlocked = await requirePremiumGuard(
                          context,
                          ref,
                        );
                        if (!unlocked) return;
                      }
                    }
                    notifier.makeMove(move.uci);
                  },
                ),
      ),
    );
  }
}

/// Eval bar for the standalone gamebase explorer, powered by local Stockfish
/// with progressive depth updates via [explorerEvalProvider].
class _ExplorerEvalBar extends ConsumerStatefulWidget {
  const _ExplorerEvalBar({
    required this.fen,
    required this.height,
    required this.width,
    required this.showEngineAnalysis,
    this.isFlipped = false,
  });

  final String fen;
  final double height;
  final double width;
  final bool showEngineAnalysis;
  final bool isFlipped;

  @override
  ConsumerState<_ExplorerEvalBar> createState() => _ExplorerEvalBarState();
}

class _ExplorerEvalBarState extends ConsumerState<_ExplorerEvalBar> {
  String _positionKey(String fen) {
    final parts = fen.trim().split(RegExp(r'\s+'));
    if (parts.length < 4) return fen.trim();
    return parts.take(4).join(' ');
  }

  bool _samePosition(String a, String b) => _positionKey(a) == _positionKey(b);

  void _syncEngineState({bool force = false}) {
    ref
        .read(explorerEvalProvider.notifier)
        .setEngineEnabled(
          enabled: widget.showEngineAnalysis,
          fen: widget.fen,
          force: force,
        );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _syncEngineState(force: true);
    });
  }

  @override
  void didUpdateWidget(covariant _ExplorerEvalBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_samePosition(widget.fen, oldWidget.fen)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _syncEngineState(force: true);
      });
    } else if (widget.showEngineAnalysis != oldWidget.showEngineAnalysis) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _syncEngineState();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.showEngineAnalysis || widget.fen.isEmpty) {
      return SizedBox(width: widget.width, height: widget.height);
    }

    final evalState = ref.watch(explorerEvalProvider);
    final currentKey = _positionKey(widget.fen);
    final evalKey = _positionKey(evalState.fen);
    final isEvalForCurrentPosition = currentKey == evalKey;

    return EvaluationBarWidget(
      key: e2eKey(E2eIds.boardEvalBar),
      width: widget.width,
      height: widget.height,
      isFlipped: widget.isFlipped,
      // Ignore stale engine output from previous positions. This prevents
      // transient wrong eval values while a new position evaluation starts.
      evaluation: isEvalForCurrentPosition ? evalState.evaluation : null,
      mate: isEvalForCurrentPosition ? evalState.mate : null,
      isEvaluating: isEvalForCurrentPosition ? evalState.isEvaluating : true,
      positionKey: currentKey,
    );
  }
}

/// Filter sheet for time controls and ratings.
///
/// Uses local draft state and only applies changes when the user taps "Apply".
/// This prevents multiple expensive aggregate requests while toggling controls.
class _FilterSheet extends ConsumerStatefulWidget {
  const _FilterSheet({this.scopedPlayer});

  final GamebasePlayer? scopedPlayer;

  @override
  ConsumerState<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends ConsumerState<_FilterSheet> {
  static const double _yearMin = 1800;
  static double get _yearMax => DateTime.now().year.toDouble();

  late GamebaseFilters _draftFilters;
  late int? _selectedMinRating;
  late RangeValues _yearRange;
  final TextEditingController _playerSearchController = TextEditingController();
  final FocusNode _playerSearchFocusNode = FocusNode();
  String _playerSearchQuery = '';

  @override
  void initState() {
    super.initState();
    _draftFilters = ref.read(gamebaseExplorerProvider).filters;
    final scopedPlayer = widget.scopedPlayer;
    if (scopedPlayer != null) {
      _draftFilters = _draftFilters.copyWith(
        playerIds: [scopedPlayer.id],
        selectedPlayers: [scopedPlayer],
      );
    }
    _selectedMinRating = RatingTierFilter.normalizeMinRating(
      _draftFilters.minRating,
    );
    _yearRange = RangeValues(
      (_draftFilters.yearFrom?.toDouble() ?? _yearMin).clamp(
        _yearMin,
        _yearMax,
      ),
      (_draftFilters.yearTo?.toDouble() ?? _yearMax).clamp(_yearMin, _yearMax),
    );
  }

  @override
  void dispose() {
    _playerSearchController.dispose();
    _playerSearchFocusNode.dispose();
    super.dispose();
  }

  void _toggleTimeControl(TimeControl timeControl) {
    final current = _draftFilters.timeControls;
    if (current.contains(timeControl)) {
      setState(() {
        _draftFilters = _draftFilters.copyWith(timeControls: const []);
      });
      return;
    }
    setState(() {
      _draftFilters = _draftFilters.copyWith(timeControls: [timeControl]);
    });
  }

  void _onYearRangeChanged(RangeValues values) {
    setState(() => _yearRange = values);
  }

  int? get _effectiveMinRating => _selectedMinRating;

  int? get _effectiveMaxRating => null;

  int? get _effectiveYearFrom {
    final v = _yearRange.start.round();
    return v <= _yearMin ? null : v;
  }

  int? get _effectiveYearTo {
    final v = _yearRange.end.round();
    return v >= _yearMax ? null : v;
  }

  bool _canUsePlayerFilter(bool isSubscribed) {
    return widget.scopedPlayer != null || isSubscribed;
  }

  GamebaseFilters _sanitizePlayerFilters(
    GamebaseFilters filters, {
    required bool canUsePlayerFilter,
  }) {
    if (widget.scopedPlayer != null || canUsePlayerFilter) {
      return filters;
    }

    return filters.copyWith(
      playerIds: const [],
      selectedPlayers: const [],
      playerColor: null,
    );
  }

  Widget _buildPlayerSearchField({required bool canUsePlayerFilter}) {
    final field = TextField(
      controller: _playerSearchController,
      focusNode: _playerSearchFocusNode,
      readOnly: !canUsePlayerFilter,
      style: TextStyle(color: context.colors.textPrimary, fontSize: 13.f),
      decoration: InputDecoration(
        hintText: 'Search player',
        hintStyle: TextStyle(
          color: context.colors.textSecondary.withValues(alpha: 0.65),
          fontSize: 13.f,
        ),
        prefixIcon: Icon(
          Icons.search_rounded,
          size: 18.sp,
          color: context.colors.textSecondary,
        ),
        filled: true,
        fillColor: context.colors.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8.br),
          borderSide: BorderSide(color: context.colors.divider),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8.br),
          borderSide: BorderSide(color: context.colors.divider),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8.br),
          borderSide: BorderSide(color: kPrimaryColor),
        ),
        contentPadding: EdgeInsets.symmetric(
          horizontal: 12.sp,
          vertical: 10.sp,
        ),
      ),
      onChanged:
          canUsePlayerFilter
              ? (value) {
                setState(() {
                  _playerSearchQuery = value.trim();
                });
              }
              : null,
    );

    if (canUsePlayerFilter) {
      return field;
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () async {
        await requirePremiumGuard(context, ref);
      },
      child: AbsorbPointer(child: ExcludeSemantics(child: field)),
    );
  }

  void _setPlayer(GamebasePlayer player) {
    setState(() {
      // Backend currently supports a single player filter.
      _draftFilters = _draftFilters.copyWith(
        playerIds: [player.id],
        selectedPlayers: [player],
      );
      _playerSearchQuery = '';
      _playerSearchController.clear();
    });
    _playerSearchFocusNode.unfocus();
  }

  void _removePlayer(String playerId) {
    final currentIds = List<String>.from(_draftFilters.playerIds);
    final currentPlayers = List<GamebasePlayer>.from(
      _draftFilters.selectedPlayers,
    );
    currentIds.remove(playerId);
    currentPlayers.removeWhere((p) => p.id == playerId);
    setState(() {
      _draftFilters = _draftFilters.copyWith(
        playerIds: currentIds,
        selectedPlayers: currentPlayers,
        playerColor: currentIds.isEmpty ? null : _draftFilters.playerColor,
      );
    });
  }

  void _toggleColor(GamebasePlayerColor color) {
    setState(() {
      _draftFilters = _draftFilters.copyWith(
        playerColor: _draftFilters.playerColor == color ? null : color,
      );
    });
  }

  void _toggleResult(GamebaseGameResult result) {
    setState(() {
      _draftFilters = _draftFilters.copyWith(
        gameResult: _draftFilters.gameResult == result ? null : result,
      );
    });
  }

  // Kept while the OTB/Online filter UI is commented out in the bottom sheet.
  // ignore: unused_element
  void _toggleOnline(bool value) {
    setState(() {
      _draftFilters = _draftFilters.copyWith(
        isOnline: _draftFilters.isOnline == value ? null : value,
      );
    });
  }

  void _apply() {
    final canUsePlayerFilter = _canUsePlayerFilter(
      ref.read(subscriptionProvider).isSubscribed,
    );
    final treeBackedPlayerScope = widget.scopedPlayer != null;
    final finalFilters = _sanitizePlayerFilters(
      _draftFilters.copyWith(
        minRating: treeBackedPlayerScope ? null : _effectiveMinRating,
        maxRating: treeBackedPlayerScope ? null : _effectiveMaxRating,
        gameResult: treeBackedPlayerScope ? null : _draftFilters.gameResult,
        yearFrom: treeBackedPlayerScope ? null : _effectiveYearFrom,
        yearTo: treeBackedPlayerScope ? null : _effectiveYearTo,
      ),
      canUsePlayerFilter: canUsePlayerFilter,
    );

    Navigator.pop(context);
    ref.read(gamebaseExplorerProvider.notifier).updateFilters(finalFilters);
  }

  bool _isScopedPlayerDraft(GamebaseFilters filters) {
    final scopedPlayer = widget.scopedPlayer;
    if (scopedPlayer == null) return false;
    return filters.playerIds.length == 1 &&
        filters.playerIds.first == scopedPlayer.id &&
        filters.selectedPlayers.length == 1 &&
        filters.selectedPlayers.first.id == scopedPlayer.id;
  }

  bool _hasActiveDraft(GamebaseFilters filters) {
    final isTreeBackedPlayerScope = widget.scopedPlayer != null;
    final hasTimeOrRatingOrYear =
        filters.timeControls.isNotEmpty ||
        (!isTreeBackedPlayerScope &&
            (_effectiveMinRating != null ||
                _effectiveMaxRating != null ||
                _effectiveYearFrom != null ||
                _effectiveYearTo != null));
    final hasColor = filters.playerColor != null;
    final hasResult = !isTreeBackedPlayerScope && filters.gameResult != null;
    final hasFormat = filters.isOnline != null;
    if (widget.scopedPlayer == null) {
      return hasTimeOrRatingOrYear ||
          hasColor ||
          hasResult ||
          hasFormat ||
          filters.playerIds.isNotEmpty;
    }
    return hasTimeOrRatingOrYear ||
        hasColor ||
        hasResult ||
        hasFormat ||
        !_isScopedPlayerDraft(filters);
  }

  void _clearAll() {
    Navigator.pop(context);

    final notifier = ref.read(gamebaseExplorerProvider.notifier);
    final scopedPlayer = widget.scopedPlayer;
    if (scopedPlayer != null) {
      notifier.updateFilters(
        GamebaseFilters(
          playerIds: [scopedPlayer.id],
          selectedPlayers: [scopedPlayer],
        ),
      );
    } else {
      notifier.clearFilters();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isSubscribed = ref.watch(
      subscriptionProvider.select((s) => s.isSubscribed),
    );
    final canUsePlayerFilter = _canUsePlayerFilter(isSubscribed);
    final filters = _sanitizePlayerFilters(
      _draftFilters,
      canUsePlayerFilter: canUsePlayerFilter,
    );
    final isTreeBackedPlayerScope = widget.scopedPlayer != null;
    final hasActiveDraft = _hasActiveDraft(filters);

    return SafeArea(
      top: false,
      child: AnimatedPadding(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          child: Padding(
            padding: EdgeInsets.all(16.sp),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Filters',
                      style: TextStyle(
                        color: context.colors.textPrimary,
                        fontSize: 18.f,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (hasActiveDraft)
                      TextButton(
                        onPressed: _clearAll,
                        child: Text(
                          'Clear all',
                          style: TextStyle(
                            color: kPrimaryColor,
                            fontSize: 14.f,
                          ),
                        ),
                      ),
                  ],
                ),
                SizedBox(height: 16.sp),

                // Time control filters
                Text(
                  'Time Control',
                  style: TextStyle(
                    color: context.colors.textSecondary,
                    fontSize: 12.f,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                SizedBox(height: 8.sp),
                Wrap(
                  spacing: 8.sp,
                  children:
                      TimeControl.values.map((tc) {
                        final isSelected = filters.timeControls.contains(tc);
                        return FilterChip(
                          label: Text(tc.displayName),
                          selected: isSelected,
                          onSelected: (_) => _toggleTimeControl(tc),
                          selectedColor: kPrimaryColor.withValues(alpha: 0.2),
                          showCheckmark: false,
                          labelStyle: TextStyle(
                            color:
                                isSelected
                                    ? kPrimaryColor
                                    : context.colors.textPrimary,
                            fontSize: 12.f,
                          ),
                          backgroundColor: context.colors.surface,
                          side: BorderSide(
                            color:
                                isSelected
                                    ? kPrimaryColor
                                    : context.colors.divider,
                          ),
                        );
                      }).toList(),
                ),
                SizedBox(height: 16.sp),

                if (!isTreeBackedPlayerScope) ...[
                  // Result filter
                  Text(
                    'Result',
                    style: TextStyle(
                      color: context.colors.textSecondary,
                      fontSize: 12.f,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  SizedBox(height: 8.sp),
                  Wrap(
                    spacing: 8.sp,
                    children:
                        GamebaseGameResult.values.map((r) {
                          final isSelected = filters.gameResult == r;
                          return FilterChip(
                            label: Text(r.displayText),
                            selected: isSelected,
                            onSelected: (_) => _toggleResult(r),
                            selectedColor: kPrimaryColor.withValues(alpha: 0.2),
                            showCheckmark: false,
                            labelStyle: TextStyle(
                              color:
                                  isSelected
                                      ? kPrimaryColor
                                      : context.colors.textPrimary,
                              fontSize: 12.f,
                            ),
                            backgroundColor: context.colors.surface,
                            side: BorderSide(
                              color:
                                  isSelected
                                      ? kPrimaryColor
                                      : context.colors.divider,
                            ),
                          );
                        }).toList(),
                  ),
                  SizedBox(height: 16.sp),
                ],

                // Color filter (visible when a player is selected)
                if (widget.scopedPlayer != null ||
                    filters.playerIds.isNotEmpty) ...[
                  Text(
                    'Color',
                    style: TextStyle(
                      color: context.colors.textSecondary,
                      fontSize: 12.f,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  SizedBox(height: 8.sp),
                  Wrap(
                    spacing: 8.sp,
                    children: [
                      FilterChip(
                        label: const Text('White'),
                        avatar: Icon(
                          Icons.circle,
                          size: 14.sp,
                          color: context.colors.textPrimary,
                        ),
                        selected:
                            filters.playerColor == GamebasePlayerColor.white,
                        onSelected:
                            (_) => _toggleColor(GamebasePlayerColor.white),
                        selectedColor: kPrimaryColor.withValues(alpha: 0.2),
                        showCheckmark: false,
                        labelStyle: TextStyle(
                          color:
                              filters.playerColor == GamebasePlayerColor.white
                                  ? kPrimaryColor
                                  : context.colors.textPrimary,
                          fontSize: 12.f,
                        ),
                        backgroundColor: context.colors.surface,
                        side: BorderSide(
                          color:
                              filters.playerColor == GamebasePlayerColor.white
                                  ? kPrimaryColor
                                  : context.colors.divider,
                        ),
                      ),
                      FilterChip(
                        label: const Text('Black'),
                        avatar: Icon(
                          Icons.circle,
                          size: 14.sp,
                          color: kBlackColor,
                        ),
                        selected:
                            filters.playerColor == GamebasePlayerColor.black,
                        onSelected:
                            (_) => _toggleColor(GamebasePlayerColor.black),
                        selectedColor: kPrimaryColor.withValues(alpha: 0.2),
                        showCheckmark: false,
                        labelStyle: TextStyle(
                          color:
                              filters.playerColor == GamebasePlayerColor.black
                                  ? kPrimaryColor
                                  : context.colors.textPrimary,
                          fontSize: 12.f,
                        ),
                        backgroundColor: context.colors.surface,
                        side: BorderSide(
                          color:
                              filters.playerColor == GamebasePlayerColor.black
                                  ? kPrimaryColor
                                  : context.colors.divider,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 16.sp),
                ],

                // Format filter (OTB / Online) — commented out per product
                // request: we don't want this filter exposed in the opening
                // explorer bottom sheet anymore. Kept here (not deleted) so
                // it can be reinstated quickly if needed.
                /*
                Text(
                  'Format',
                  style: TextStyle(
                    color: context.colors.textSecondary,
                    fontSize: 12.f,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                SizedBox(height: 8.sp),
                Wrap(
                  spacing: 8.sp,
                  children: [
                    FilterChip(
                      label: const Text('OTB Only'),
                      avatar: Icon(
                        Icons.public_off_rounded,
                        size: 14.sp,
                        color:
                            filters.isOnline == false
                                ? kPrimaryColor
                                : context.colors.textPrimary,
                      ),
                      selected: filters.isOnline == false,
                      onSelected: (_) => _toggleOnline(false),
                      selectedColor: kPrimaryColor.withValues(alpha: 0.2),
                      showCheckmark: false,
                      labelStyle: TextStyle(
                        color:
                            filters.isOnline == false
                                ? kPrimaryColor
                                : context.colors.textPrimary,
                        fontSize: 12.f,
                      ),
                      backgroundColor: context.colors.surface,
                      side: BorderSide(
                        color:
                            filters.isOnline == false
                                ? kPrimaryColor
                                : context.colors.divider,
                      ),
                    ),
                    FilterChip(
                      label: const Text('Online Only'),
                      avatar: Icon(
                        Icons.public_rounded,
                        size: 14.sp,
                        color:
                            filters.isOnline == true
                                ? kPrimaryColor
                                : context.colors.textPrimary,
                      ),
                      selected: filters.isOnline == true,
                      onSelected: (_) => _toggleOnline(true),
                      selectedColor: kPrimaryColor.withValues(alpha: 0.2),
                      showCheckmark: false,
                      labelStyle: TextStyle(
                        color:
                            filters.isOnline == true
                                ? kPrimaryColor
                                : context.colors.textPrimary,
                        fontSize: 12.f,
                      ),
                      backgroundColor: context.colors.surface,
                      side: BorderSide(
                        color:
                            filters.isOnline == true
                                ? kPrimaryColor
                                : context.colors.divider,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 16.sp),
                */
                if (!isTreeBackedPlayerScope) ...[
                  // Rating level
                  Text(
                    'Level',
                    style: TextStyle(
                      color: context.colors.textSecondary,
                      fontSize: 12.f,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  SizedBox(height: 8.sp),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4.w),
                    child: RatingTierFilter(
                      selectedMinRating: _selectedMinRating,
                      onChanged:
                          (value) => setState(() => _selectedMinRating = value),
                    ),
                  ),
                  SizedBox(height: 24.sp),

                  // Year range
                  Text(
                    'Year Range',
                    style: TextStyle(
                      color: context.colors.textSecondary,
                      fontSize: 12.f,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  SizedBox(height: 8.sp),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16.w),
                    child: WheelRangeFilter(
                      minValue: _yearMin,
                      maxValue: _yearMax,
                      currentStart: _yearRange.start,
                      currentEnd: _yearRange.end,
                      divisions: (_yearMax - _yearMin).toInt(),
                      onChanged: _onYearRangeChanged,
                    ),
                  ),
                  SizedBox(height: 24.sp),
                ],

                if (widget.scopedPlayer == null) ...[
                  // Player search (hidden in player-scoped explorer)
                  Text(
                    'Player',
                    style: TextStyle(
                      color: context.colors.textSecondary,
                      fontSize: 12.f,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  SizedBox(height: 8.sp),
                  _buildPlayerSearchField(
                    canUsePlayerFilter: canUsePlayerFilter,
                  ),
                  if (canUsePlayerFilter && _playerSearchQuery.length >= 2) ...[
                    SizedBox(height: 8.sp),
                    _PlayerSearchResults(
                      query: _playerSearchQuery,
                      onPlayerSelected: _setPlayer,
                    ),
                  ],
                ],
                if (widget.scopedPlayer == null &&
                    canUsePlayerFilter &&
                    filters.selectedPlayers.isNotEmpty) ...[
                  SizedBox(height: 10.sp),
                  Wrap(
                    spacing: 8.sp,
                    runSpacing: 8.sp,
                    children: [
                      for (final player in filters.selectedPlayers)
                        Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: 10.sp,
                            vertical: 6.sp,
                          ),
                          decoration: BoxDecoration(
                            color: kPrimaryColor.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(24.br),
                            border: Border.all(
                              color: kPrimaryColor.withValues(alpha: 0.45),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                player.titleAndName,
                                style: TextStyle(
                                  color: context.colors.textPrimary,
                                  fontSize: 12.f,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              SizedBox(width: 6.sp),
                              GestureDetector(
                                onTap: () => _removePlayer(player.id),
                                child: Icon(
                                  Icons.close_rounded,
                                  size: 14.sp,
                                  color: context.colors.textPrimary,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ] else ...[
                  SizedBox(height: 4.sp),
                ],
                SizedBox(height: 24.sp),

                // Apply button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _apply,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kPrimaryColor,
                      padding: EdgeInsets.symmetric(vertical: 12.sp),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8.br),
                      ),
                    ),
                    child: Text(
                      'Apply',
                      style: TextStyle(
                        color: context.colors.textPrimary,
                        fontSize: 14.f,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PlayerSearchResults extends ConsumerWidget {
  const _PlayerSearchResults({
    required this.query,
    required this.onPlayerSelected,
  });

  final String query;
  final ValueChanged<GamebasePlayer> onPlayerSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final results = ref.watch(playerSearchProvider(query));

    return Container(
      constraints: BoxConstraints(maxHeight: 200.h),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(8.br),
        border: Border.all(color: context.colors.divider),
      ),
      child: Material(
        color: Colors.transparent,
        child: results.when(
          data: (players) {
            if (players.isEmpty) {
              return Padding(
                padding: EdgeInsets.all(12.sp),
                child: Text(
                  'No players found',
                  style: TextStyle(
                    color: context.colors.textSecondary,
                    fontSize: 12.f,
                  ),
                ),
              );
            }
            return ListView.separated(
              shrinkWrap: true,
              itemCount: players.length,
              separatorBuilder:
                  (_, __) => Divider(height: 1, color: context.colors.divider),
              itemBuilder: (context, index) {
                final player = players[index];
                return ListTile(
                  dense: true,
                  onTap: () => onPlayerSelected(player),
                  title: Text(
                    player.titleAndName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: context.colors.textPrimary,
                      fontSize: 13.f,
                    ),
                  ),
                  subtitle: Text(
                    '${player.fed}${player.highestRating != null ? ' • ${player.highestRating}' : ''}',
                    style: TextStyle(
                      color: context.colors.textSecondary,
                      fontSize: 11.f,
                    ),
                  ),
                  trailing: Icon(
                    Icons.add_rounded,
                    size: 18.sp,
                    color: kPrimaryColor,
                  ),
                );
              },
            );
          },
          loading:
              () => Padding(
                padding: EdgeInsets.all(12.sp),
                child: Row(
                  children: [
                    SizedBox(
                      width: 16.sp,
                      height: 16.sp,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: kPrimaryColor,
                      ),
                    ),
                    SizedBox(width: 10.sp),
                    Text(
                      'Searching...',
                      style: TextStyle(
                        color: context.colors.textSecondary,
                        fontSize: 12.f,
                      ),
                    ),
                  ],
                ),
              ),
          error:
              (_, __) => Padding(
                padding: EdgeInsets.all(12.sp),
                child: Text(
                  'Search failed',
                  style: TextStyle(color: kRedColor, fontSize: 12.f),
                ),
              ),
        ),
      ),
    );
  }
}

class _ExplorerPvToken {
  const _ExplorerPvToken(this.text, {this.moveIndex});

  final String text;
  final int? moveIndex;
}

/// Compact engine analysis lines displayed above the move statistics.
/// Every SAN move is independently tappable so it can open the same locked,
/// non-committing PV preview used by the normal analysis board.
class _ExplorerEngineLines extends ConsumerStatefulWidget {
  const _ExplorerEngineLines();

  @override
  ConsumerState<_ExplorerEngineLines> createState() =>
      _ExplorerEngineLinesState();
}

class _ExplorerEngineLinesState extends ConsumerState<_ExplorerEngineLines> {
  static const int _kMaxRows = 3;
  static final RegExp _uciRegex = RegExp(r'^[a-h][1-8][a-h][1-8][qrbn]?$');
  final GlobalKey _previewCursorKey = GlobalKey();

  List<_ExplorerPvToken> _formatTokens(
    List<String> sanMoves,
    int startMoveNumber,
    bool isWhiteToMove,
  ) {
    final tokens = <_ExplorerPvToken>[];
    var moveNumber = startMoveNumber;
    var whiteToMove = isWhiteToMove;

    for (var index = 0; index < sanMoves.length; index++) {
      if (whiteToMove) {
        tokens.add(_ExplorerPvToken('$moveNumber.'));
      } else if (index == 0) {
        tokens.add(_ExplorerPvToken('$moveNumber...'));
      }
      tokens.add(_ExplorerPvToken(sanMoves[index], moveIndex: index));
      if (!whiteToMove) moveNumber++;
      whiteToMove = !whiteToMove;
    }
    return tokens;
  }

  List<InlineSpan> _buildMoveSpans({
    required BuildContext context,
    required ExplorerPvLine line,
    required int variantIndex,
    required int startMoveNumber,
    required bool isWhiteToMove,
    required bool useFigurine,
    required PieceAssets pieceAssets,
    required Color accentColor,
    required String baseFen,
    required int? selectedMoveIndex,
  }) {
    final style = AppTypography.textXsMedium.copyWith(
      color: context.colors.textPrimary.withValues(alpha: 0.95),
      fontWeight: FontWeight.w600,
    );
    final spans = <InlineSpan>[];

    for (final token in _formatTokens(
      line.sanMoves,
      startMoveNumber,
      isWhiteToMove,
    )) {
      final moveIndex = token.moveIndex;
      if (moveIndex == null) {
        spans.add(TextSpan(text: '${token.text} ', style: style));
        continue;
      }

      final selected = moveIndex == selectedMoveIndex;
      final moveText =
          useFigurine
              ? Text.rich(
                TextSpan(
                  children: buildFigurineSpans(
                    text: token.text,
                    pieceAssets: pieceAssets,
                    style: style,
                    pieceSize: 12.sp,
                  ),
                ),
              )
              : Text(token.text, style: style);
      final decoratedMove =
          selected
              ? Container(
                padding: EdgeInsets.symmetric(horizontal: 3.sp, vertical: 1.sp),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(3.sp),
                ),
                child: moveText,
              )
              : moveText;

      Widget target = GestureDetector(
        key: ValueKey<String>(
          'opening_explorer_pv_move_${variantIndex}_$moveIndex',
        ),
        behavior: HitTestBehavior.opaque,
        onTap: () {
          HapticFeedback.lightImpact();
          final evalState = ref.read(explorerEvalProvider);
          if (explorerFenPositionKey(evalState.fen) !=
              explorerFenPositionKey(baseFen)) {
            ref
                .read(explorerEvalProvider.notifier)
                .evaluatePosition(baseFen, force: true);
            return;
          }
          ref
              .read(explorerEvalProvider.notifier)
              .previewPrincipalVariationMoveAt(
                line,
                variantIndex,
                moveIndex,
                baseFen: baseFen,
              );
        },
        child: decoratedMove,
      );
      if (selected) {
        target = KeyedSubtree(key: _previewCursorKey, child: target);
      }
      spans.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Padding(padding: EdgeInsets.only(right: 4.sp), child: target),
        ),
      );
    }
    return spans;
  }

  @override
  Widget build(BuildContext context) {
    final evalState = ref.watch(explorerEvalProvider);
    final pvLines = evalState.pvLines;
    final preview = evalState.pvPreview;

    final useFigurine = ref.watch(
      boardSettingsProviderNew.select(
        (s) =>
            s.valueOrNull?.useFigurine ?? const BoardSettingsNew().useFigurine,
      ),
    );
    final pieceAssets = ref.watch(
      boardSettingsProviderNew.select(
        (s) =>
            s.valueOrNull?.pieceAssets ?? const BoardSettingsNew().pieceAssets,
      ),
    );

    final baseFen = ref.watch(
      gamebaseExplorerProvider.select((s) => s.currentFen),
    );
    final fenParts = baseFen.split(' ');
    final isWhiteToMove = fenParts.length > 1 ? fenParts[1] == 'w' : true;
    final startMoveNumber =
        fenParts.length > 5 ? (int.tryParse(fenParts[5]) ?? 1) : 1;

    final engineSettings = ref.watch(engineSettingsProviderNew).valueOrNull;
    final linesView = engineSettings?.engineLinesView ?? EngineLinesView.list;

    Future<void> playLine(ExplorerPvLine line) async {
      if (line.uciMoves.isEmpty) return;
      final firstUci = line.uciMoves.first.trim().toLowerCase();
      if (!_uciRegex.hasMatch(firstUci)) return;
      if (!kDebugMode && !ref.read(subscriptionProvider).isSubscribed) {
        final currentMoveNumber =
            ref.read(gamebaseExplorerProvider.notifier).effectiveMoveNumber;
        if (currentMoveNumber >= kFreeExplorerMoveNumberLimit) {
          if (!context.mounted) return;
          final unlocked = await requirePremiumGuard(context, ref);
          if (!unlocked) return;
        }
      }
      ref
          .read(explorerEvalProvider.notifier)
          .clearPvPreview(resumeEvaluation: false);
      ref.read(gamebaseExplorerProvider.notifier).makeMove(firstUci);
    }

    EnginePvItem buildItem(ExplorerPvLine line, int variantIndex) {
      final accentColor = enginePvVariantColor(variantIndex, isSelected: true);
      final isSelected = preview?.variantIndex == variantIndex;
      final evalValue =
          line.mate != null ? line.mate!.toDouble() : (line.evaluation ?? 0.0);
      return EnginePvItem(
        evalText: line.displayEval,
        accentColor: accentColor,
        moveSpans: _buildMoveSpans(
          context: context,
          line: line,
          variantIndex: variantIndex,
          startMoveNumber: startMoveNumber,
          isWhiteToMove: isWhiteToMove,
          useFigurine: useFigurine,
          pieceAssets: pieceAssets,
          accentColor: accentColor,
          baseFen: baseFen,
          selectedMoveIndex: isSelected ? preview?.moveIndex : null,
        ),
        isWhiteWinning: evalValue > 0,
        isBlackWinning: evalValue < 0,
        isPrimary: variantIndex == 0,
        scrollTargetKey: isSelected ? _previewCursorKey : null,
        onTap: preview != null ? null : () => playLine(line),
      );
    }

    // ChessEver layout: horizontally swipeable engine cards. Honors the user's
    // "Number of Lines" engine setting (list mode keeps the 3-row cap).
    if (linesView == EngineLinesView.cards) {
      final pvCount = (engineSettings?.multiPvForLichess() ?? _kMaxRows).clamp(
        1,
        5,
      );
      final items =
          preview != null
              ? <EnginePvItem>[buildItem(preview.line, preview.variantIndex)]
              : <EnginePvItem>[
                for (
                  var index = 0;
                  index < pvLines.length && index < pvCount;
                  index++
                )
                  buildItem(pvLines[index], index),
              ];
      return Padding(
        key: e2eKey(E2eIds.openingExplorerEngineLines),
        padding: EdgeInsets.symmetric(horizontal: 12.sp, vertical: 6.sp),
        child: EnginePvCardsView(
          key: ValueKey<String>(
            preview == null
                ? 'opening_explorer_live_pvs'
                : 'opening_explorer_locked_pv_${preview.variantIndex}',
          ),
          items: items,
          cardHeight: 64.h,
          emptyPlaceholder: _EngineLinePlaceholder(
            isPrimary: true,
            isEvaluating: evalState.isEvaluating,
          ),
        ),
      );
    }

    final lines = pvLines.take(_kMaxRows).toList();
    final items = <EnginePvItem>[
      for (var index = 0; index < lines.length; index++)
        buildItem(
          preview?.variantIndex == index ? preview!.line : lines[index],
          index,
        ),
    ];

    return Padding(
      key: e2eKey(E2eIds.openingExplorerEngineLines),
      padding: EdgeInsets.symmetric(horizontal: 12.sp, vertical: 4.sp),
      child: EnginePvListView(
        items: items,
        slotCount: _kMaxRows,
        isEvaluating: evalState.isEvaluating,
      ),
    );
  }
}

class _EngineLinePlaceholder extends StatelessWidget {
  const _EngineLinePlaceholder({
    required this.isPrimary,
    required this.isEvaluating,
  });

  final bool isPrimary;
  final bool isEvaluating;

  @override
  Widget build(BuildContext context) {
    final label = ' ';
    final badgeText = isEvaluating ? '...' : '-';

    return Padding(
      padding: EdgeInsets.symmetric(vertical: 5.sp, horizontal: 12.sp),
      child: Row(
        children: [
          Container(
            width: 44.w,
            padding: EdgeInsets.symmetric(vertical: 2.sp),
            decoration: BoxDecoration(
              color: context.colors.textSecondary.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(3.br),
            ),
            child: Text(
              badgeText,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: context.colors.textPrimary.withValues(
                  alpha: isEvaluating ? 0.35 : 0.18,
                ),
                fontSize: 11.f,
                fontWeight: FontWeight.w700,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          SizedBox(width: 8.sp),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: context.colors.textPrimary.withValues(
                  alpha: isPrimary ? 0.65 : 0.18,
                ),
                fontSize: 12.f,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// App-bar control for the two views of one shared Board workspace.
class _ExplorerSegmentedTitle extends ConsumerWidget {
  const _ExplorerSegmentedTitle({
    required this.currentPage,
    this.isLarge = false,
  });

  final int currentPage;
  final bool isLarge;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ExplorerViewToggle(
      currentPage: currentPage,
      compact: !isLarge,
      onSelected:
          (value) => ref.read(explorerPageIndexProvider.notifier).state = value,
    );
  }
}

class _ExplorerNotationView extends ConsumerStatefulWidget {
  const _ExplorerNotationView({required this.isActive, super.key});

  final bool isActive;

  @override
  ConsumerState<_ExplorerNotationView> createState() =>
      _ExplorerNotationViewState();
}

class _ExplorerBottomPanels extends ConsumerStatefulWidget {
  const _ExplorerBottomPanels({
    required this.onFilter,
    required this.hasActiveFilters,
  });

  final VoidCallback onFilter;
  final bool hasActiveFilters;

  @override
  ConsumerState<_ExplorerBottomPanels> createState() =>
      _ExplorerBottomPanelsState();
}

class _ExplorerBottomPanelsState extends ConsumerState<_ExplorerBottomPanels>
    with SingleTickerProviderStateMixin {
  static const int _totalPages = 2;
  static const String _kWalkthroughShownDateKey =
      kSwitchViewsWalkthroughShownDateKey;
  static const String _kWalkthroughDontShowKey =
      kSwitchViewsWalkthroughDontShowKey;

  late final PageController _pageController;
  late AnimationController _swipeController;
  late Animation<double> _swipeFadeAnimation;
  late Animation<double> _swipeScaleAnimation;
  late Animation<double> _swipeMoveAnimation;
  int _currentPageIndex = 0;
  bool _showTutorialOverlay = false;
  OverlayEntry? _tutorialEntry;

  @override
  void initState() {
    super.initState();
    final initialPage = ref.read(explorerPageIndexProvider);
    _currentPageIndex = initialPage;
    _pageController = PageController(initialPage: initialPage);
    _setupSwipeAnimation();
    // The old swipe overlay is superseded by the one-time app-bar coachmarks,
    // which teach both the Explorer/Notation switch and Board Editor.
  }

  @override
  void dispose() {
    _removeTutorialOverlay();
    _swipeController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  void _setupSwipeAnimation() {
    _swipeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    );

    _swipeFadeAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0), weight: 10),
      TweenSequenceItem(tween: ConstantTween(1.0), weight: 80),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0), weight: 10),
    ]).animate(_swipeController);

    _swipeScaleAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: ConstantTween(1.0), weight: 10),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.8), weight: 10),
      TweenSequenceItem(tween: ConstantTween(0.8), weight: 60),
      TweenSequenceItem(tween: Tween(begin: 0.8, end: 1.0), weight: 10),
      TweenSequenceItem(tween: ConstantTween(1.0), weight: 10),
    ]).animate(_swipeController);

    _swipeMoveAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: ConstantTween(0.0), weight: 15),
      TweenSequenceItem(
        tween: Tween(
          begin: 0.0,
          end: 1.0,
        ).chain(CurveTween(curve: Curves.easeInOutCubic)),
        weight: 35,
      ),
      TweenSequenceItem(tween: ConstantTween(1.0), weight: 10),
      TweenSequenceItem(
        tween: Tween(
          begin: 1.0,
          end: 0.0,
        ).chain(CurveTween(curve: Curves.easeInOutCubic)),
        weight: 35,
      ),
      TweenSequenceItem(tween: ConstantTween(0.0), weight: 5),
    ]).animate(_swipeController);

    // Sync _pageController with the tutorial animation.
    // This makes the notation panel slide underneath the finger hint
    // during the "Switch Views" walkthrough.
    _swipeController.addListener(() {
      if (!_pageController.hasClients) return;

      final width = _pageController.position.viewportDimension;
      bool canGoNext = _currentPageIndex < _totalPages - 1;
      double direction = canGoNext ? 1.0 : -1.0;

      // Sync with overlay's maxDrag (width * 0.5)
      double maxDrag = width * 0.5;

      // handTranslation in overlay is: -1 * moveValue * maxDrag * direction
      // We want PageView to move by exactly that amount.
      // PageView offset = baseOffset - handTranslation
      double moveValue = _swipeMoveAnimation.value;
      double handTranslation = -1 * moveValue * maxDrag * direction;
      double baseOffset = _currentPageIndex * width;

      _pageController.position.jumpTo(baseOffset - handTranslation);
    });
  }

  // Kept for backward compatibility with the existing walkthrough storage and
  // overlay implementation; the app-bar coachmarks are now the active path.
  // ignore: unused_element
  Future<void> _checkAndShowWalkthrough() async {
    final prefs = ref.read(sharedPreferencesRepository);
    final now = DateTime.now();

    bool shouldShow = kDebugMode;
    if (!shouldShow) {
      final dontShow = await prefs.getBool(_kWalkthroughDontShowKey) ?? false;
      if (dontShow) return;

      final lastShownMs = await prefs.getInt(_kWalkthroughShownDateKey);
      if (lastShownMs == null) {
        shouldShow = true;
      } else {
        final lastShownDate = DateTime.fromMillisecondsSinceEpoch(lastShownMs);
        if (now.difference(lastShownDate).inDays >= 7) {
          shouldShow = true;
        }
      }
    }

    if (!shouldShow || !mounted) return;

    _showTutorialOverlay = true;
    _insertTutorialOverlay();

    int count = 0;
    void statusListener(AnimationStatus status) {
      if (status == AnimationStatus.completed) {
        count++;
        if (count < 1) {
          _swipeController.forward(from: 0.0);
        } else {
          _swipeController.removeStatusListener(statusListener);
          if (_pageController.hasClients) {
            _pageController.jumpToPage(_currentPageIndex);
          }
        }
      }
    }

    _swipeController.addStatusListener(statusListener);
    _swipeController.forward();

    await prefs.setInt(_kWalkthroughShownDateKey, now.millisecondsSinceEpoch);
  }

  void _insertTutorialOverlay() {
    _tutorialEntry = OverlayEntry(
      builder:
          (_) => SwitchViewsTutorialOverlay(
            animationController: _swipeController,
            moveAnimation: _swipeMoveAnimation,
            fadeAnimation: _swipeFadeAnimation,
            scaleAnimation: _swipeScaleAnimation,
            currentPageIndex: _currentPageIndex,
            totalItems: _totalPages,
            onDismiss: _onWalkthroughFinished,
            onDontShowAgain: () async {
              await _suppressWalkthrough();
              _onWalkthroughFinished();
            },
          ),
    );
    Overlay.of(context, rootOverlay: true).insert(_tutorialEntry!);
  }

  void _removeTutorialOverlay() {
    _tutorialEntry?.remove();
    _tutorialEntry = null;
  }

  void _onWalkthroughFinished() {
    _removeTutorialOverlay();
    _swipeController.stop();
    _swipeController.reset();
    if (_pageController.hasClients) {
      _pageController.jumpToPage(_currentPageIndex);
    }
    if (mounted) {
      setState(() {
        _showTutorialOverlay = false;
      });
    } else {
      _showTutorialOverlay = false;
    }
  }

  Future<void> _suppressWalkthrough() async {
    final prefs = ref.read(sharedPreferencesRepository);
    await prefs.setBool(_kWalkthroughDontShowKey, true);
  }

  @override
  Widget build(BuildContext context) {
    // Sync external page changes (e.g. from AppBar toggle) to PageView
    ref.listen(explorerPageIndexProvider, (previous, next) {
      if (_showTutorialOverlay) return;
      if (_pageController.hasClients && _pageController.page?.round() != next) {
        _pageController.animateToPage(
          next,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
        );
      }
    });

    final pageView = PageView(
      controller: _pageController,
      onPageChanged: (page) {
        if (_showTutorialOverlay) return;
        _currentPageIndex = page;
        ref.read(explorerPageIndexProvider.notifier).state = page;
      },
      children: [
        MoveStatisticsPanel(
          key: const PageStorageKey<String>('opening-explorer-moves-panel'),
          onFilter: widget.onFilter,
          hasActiveFilters: widget.hasActiveFilters,
        ),
        _ExplorerNotationView(
          key: const PageStorageKey<String>('opening-explorer-notation-panel'),
          isActive: ref.watch(explorerPageIndexProvider) == 1,
        ),
      ],
    );

    final preview = ref.watch(
      explorerEvalProvider.select((value) => value.pvPreview),
    );
    if (preview == null) return pageView;

    return Stack(
      fit: StackFit.expand,
      children: [
        pageView,
        Material(
          color: context.colors.surfaceRecessed.withValues(alpha: 0.94),
          child: Semantics(
            button: true,
            label: 'Exit engine line preview',
            child: InkWell(
              key: const ValueKey<String>(
                'opening_explorer_pv_preview_dismiss',
              ),
              onTap:
                  () =>
                      ref.read(explorerEvalProvider.notifier).clearPvPreview(),
              child: Center(
                child: Padding(
                  padding: EdgeInsets.all(20.sp),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.close_rounded,
                        color: context.colors.textPrimary,
                        size: 24.sp,
                      ),
                      SizedBox(height: 8.sp),
                      Text(
                        'Previewing engine line',
                        style: AppTypography.textSmMedium.copyWith(
                          color: context.colors.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      SizedBox(height: 4.sp),
                      Text(
                        'Tap to return to the explorer',
                        style: AppTypography.textXsRegular.copyWith(
                          color: context.colors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ExplorerNotationViewState extends ConsumerState<_ExplorerNotationView> {
  static const int _autoCollapseDepth = 3;
  static const List<Color> _variationDepthPalette = [
    Color(0xFFE9EDCC),
    Color(0xFFD6E3BC),
    Color(0xFFBFD3CB),
    Color(0xFFA6C2DA),
    Color(0xFF8EB2CB),
  ];

  final ScrollController _scrollController = ScrollController();
  final Map<String, GlobalKey> _moveKeys = {};
  final ListEquality<int> _pointerEquality = const ListEquality<int>();
  final Set<String> _collapsedVariationIds = <String>{};
  final Set<String> _expandedVariationIds = <String>{};
  String? _lastSignature;
  ChessMovePointer? _lastPointer;

  @override
  void didUpdateWidget(covariant _ExplorerNotationView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !oldWidget.isActive) {
      _lastPointer = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final pointer = ref.read(gamebaseExplorerProvider).movePointer;
        if (pointer.isEmpty) return;
        _scrollToPointer(NotationPointer.encode(pointer));
      });
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(gamebaseExplorerProvider);
    final game = state.game;
    if (game == null || game.mainline.isEmpty) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(20.sp),
          child: Text(
            'Play a move to build the notation.',
            style: AppTypography.textSmRegular.copyWith(
              color: context.colors.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    final signature = notationGameSignature(game);
    if (_lastSignature != signature) {
      _moveKeys.clear();
      _lastSignature = signature;
      _lastPointer = null;
      _collapsedVariationIds.clear();
      _expandedVariationIds.clear();
    }

    final tree = NotationTreeBuilder.build(game);
    final pointerId =
        state.movePointer.isEmpty
            ? null
            : NotationPointer.encode(state.movePointer);
    final forcedOpenIds = <String>{};
    _collectVariationAncestors(pointerId, tree.mainline, forcedOpenIds);
    final pointerMap = <String, NotationMoveNode>{};
    final rawPgnMode = ref.watch(
      boardSettingsProviderNew.select(
        (s) => s.valueOrNull?.rawPgnMode ?? false,
      ),
    );
    final tokens = buildNotationTokens(
      tree.mainline,
      depth: 0,
      startingPly: tree.startingPly,
      pointerMap: pointerMap,
      forcedOpenIds: forcedOpenIds,
      variationComments: const {},
      lichessAnnotations: const {},
      collapsedVariationIds: _collapsedVariationIds,
      expandedVariationIds: _expandedVariationIds,
      autoCollapseDepth: _autoCollapseDepth,
      rawPgnMode: rawPgnMode,
    );

    if (tokens.isEmpty) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(20.sp),
          child: Text(
            'No notation available for this line yet.',
            style: AppTypography.textSmRegular.copyWith(
              color: context.colors.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    final useFigurine = ref.watch(
      boardSettingsProviderNew.select(
        (s) =>
            s.valueOrNull?.useFigurine ?? const BoardSettingsNew().useFigurine,
      ),
    );
    final pieceAssets = ref.watch(
      boardSettingsProviderNew.select(
        (s) =>
            s.valueOrNull?.pieceAssets ?? const BoardSettingsNew().pieceAssets,
      ),
    );

    final currentNode = pointerId == null ? null : pointerMap[pointerId];
    final currentPly = currentNode?.ply ?? -1;

    if (widget.isActive && pointerId != null) {
      _schedulePointerScroll(state.movePointer, pointerId);
    }

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: context.colors.surfaceRecessed.withValues(alpha: 0.22),
      ),
      child: SingleChildScrollView(
        controller: _scrollController,
        padding: EdgeInsets.all(18.sp),
        child: Wrap(
          spacing: 2.sp,
          runSpacing: 2.sp,
          children:
              tokens.map((token) {
                if (token.type == NotationTokenType.move) {
                  return _buildMoveChip(
                    token,
                    pointerId,
                    currentPly,
                    useFigurine,
                    pieceAssets,
                    rawPgnMode: rawPgnMode,
                  );
                }
                if (token.type == NotationTokenType.comment ||
                    token.type == NotationTokenType.lichessComment) {
                  return Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: 4.sp,
                      vertical: 2.sp,
                    ),
                    child: Text(
                      token.text,
                      style: AppTypography.textXsRegular.copyWith(
                        color: context.colors.textPrimaryMuted.withValues(
                          alpha: 0.65,
                        ),
                        fontStyle: FontStyle.italic,
                        height: 1.35,
                      ),
                    ),
                  );
                }
                return _buildAuxToken(token, currentPly);
              }).toList(),
        ),
      ),
    );
  }

  void _collectVariationAncestors(
    String? targetId,
    List<NotationMoveNode> nodes,
    Set<String> out,
  ) {
    if (targetId == null) return;
    for (final node in nodes) {
      final id = NotationPointer.encode(node.pointer);
      if (targetId.startsWith(id)) {
        for (final variation in node.variations) {
          if (targetId.startsWith(variation.id)) {
            out.add(variation.id);
            _collectVariationAncestors(targetId, variation.moves, out);
          }
        }
      }
    }
  }

  Widget _buildMoveChip(
    NotationDisplayToken token,
    String? currentPointerId,
    int currentPly,
    bool useFigurine,
    PieceAssets? pieceAssets, {
    bool rawPgnMode = false,
  }) {
    final pointerId = token.pointerId;
    final key =
        pointerId == null
            ? null
            : _moveKeys.putIfAbsent(pointerId, () => GlobalKey());
    final isCurrent = pointerId != null && pointerId == currentPointerId;

    final nags =
        rawPgnMode ? const <int>[] : token.node?.move.nags ?? const <int>[];
    // Resolve NAGs into displays. Quality NAGs tint the move text and render
    // hugged to the SAN; evaluation/observation NAGs render in muted slate
    // with a leading hair-space and never recolor the SAN.
    final displayNags = <NagDisplay>[];
    NagDisplay? firstQualityNag;
    final seen = <int>{};
    for (final nag in nags) {
      if (!seen.add(nag)) continue;
      final d = getNagDisplay(nag);
      if (d != null) {
        displayNags.add(d);
        if (d.isQuality) firstQualityNag ??= d;
      }
    }

    final baseColor = _resolveMoveColor(token, currentPly);
    final color = firstQualityNag?.color ?? baseColor;
    final textStyle = AppTypography.textXsMedium.copyWith(
      color: color,
      fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
    );
    final numberStyle = AppTypography.textXsMedium.copyWith(
      color: context.colors.textPrimary.withValues(alpha: 0.5),
      fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
    );

    final List<InlineSpan> moveSpans;
    if (useFigurine && pieceAssets != null) {
      moveSpans = buildFigurineSpans(
        text: token.text,
        pieceAssets: pieceAssets,
        style: textStyle,
        pieceSize: 12.sp,
        numberStyle: numberStyle,
      );
    } else {
      final String fullText = token.text;
      String prefix = '';
      String body = fullText;
      final prefixRegex = RegExp(r'^(\d+\.{1,3}\s+)(.*)$');
      final match = prefixRegex.firstMatch(fullText);
      if (match != null) {
        prefix = match.group(1)!;
        body = match.group(2)!;
      }
      moveSpans = [
        if (prefix.isNotEmpty) TextSpan(text: prefix, style: numberStyle),
        TextSpan(text: body, style: textStyle),
      ];
    }

    if (displayNags.isNotEmpty) {
      // Order: quality first (hugged, bold, color-coded), then evaluation,
      // then observation (both with leading hair-space, muted slate, w500).
      final ordered = [...displayNags]..sort((a, b) {
        int rank(NagDisplay d) => switch (d.category) {
          NagCategory.quality => 0,
          NagCategory.evaluation => 1,
          NagCategory.observation => 2,
        };
        return rank(a).compareTo(rank(b));
      });
      for (final d in ordered) {
        if (d.isQuality) {
          moveSpans.add(
            TextSpan(
              text: d.symbol,
              style: textStyle.copyWith(
                color: d.color,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.2,
              ),
            ),
          );
        } else {
          moveSpans.add(
            TextSpan(
              text: ' ${d.symbol}',
              style: textStyle.copyWith(
                color: d.color,
                fontWeight: FontWeight.w500,
                fontSize: (textStyle.fontSize ?? 12.0) - 0.5,
                letterSpacing: 0.0,
              ),
            ),
          );
        }
      }
    }

    return GestureDetector(
      key: key,
      onTap: () {
        if (token.pointer != null) {
          ref
              .read(gamebaseExplorerProvider.notifier)
              .goToMovePointer(token.pointer!);
        }
      },
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 6.sp, vertical: 2.sp),
        decoration: BoxDecoration(
          color:
              isCurrent
                  ? context.colors.textPrimaryMuted.withValues(alpha: 0.25)
                  : Colors.transparent,
          borderRadius: BorderRadius.circular(4.sp),
          border: Border.all(
            color: isCurrent ? context.colors.textPrimary : Colors.transparent,
            width: 0.7,
          ),
        ),
        child: Text.rich(TextSpan(children: moveSpans)),
      ),
    );
  }

  Widget _buildAuxToken(NotationDisplayToken token, int currentPly) {
    final isVariationToken =
        token.type != NotationTokenType.ellipsis &&
        (token.variation != null || token.variationColorKey != null);
    Color depthColor;
    if (isVariationToken) {
      depthColor = _accentColorForToken(token);
    } else if (token.depth > 0) {
      depthColor = _colorForVariationDepth(token.depth);
    } else {
      depthColor = context.colors.textPrimary.withValues(alpha: 0.75);
    }

    if (token.type == NotationTokenType.variationPlaceholder) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _toggleVariationCollapse(token),
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 8.sp, vertical: 4.sp),
          decoration: BoxDecoration(
            color: depthColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(6.sp),
            border: Border.all(
              color: depthColor.withValues(alpha: 0.25),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.unfold_more_rounded,
                size: 12.sp,
                color: depthColor.withValues(alpha: 0.7),
              ),
              SizedBox(width: 4.sp),
              Text(
                token.text,
                style: AppTypography.textXsMedium.copyWith(
                  color: depthColor.withValues(alpha: 0.85),
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (token.type == NotationTokenType.openParen && token.variation != null) {
      final isCollapsed = token.isCollapsed;
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _toggleVariationCollapse(token),
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 4.sp, vertical: 2.sp),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                curve: Curves.easeOutCubic,
                width: 16.sp,
                height: 16.sp,
                margin: EdgeInsets.only(right: 3.sp),
                decoration: BoxDecoration(
                  color:
                      isCollapsed
                          ? depthColor.withValues(alpha: 0.2)
                          : depthColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4.sp),
                  border: Border.all(
                    color: depthColor.withValues(
                      alpha: isCollapsed ? 0.4 : 0.25,
                    ),
                    width: 1,
                  ),
                ),
                child: Center(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 150),
                    child: Icon(
                      isCollapsed ? Icons.add_rounded : Icons.remove_rounded,
                      key: ValueKey<bool>(isCollapsed),
                      size: 12.sp,
                      color: depthColor.withValues(alpha: 0.9),
                    ),
                  ),
                ),
              ),
              Text(
                token.text,
                style: AppTypography.textXsMedium.copyWith(
                  color: depthColor.withValues(alpha: 0.85),
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (token.type == NotationTokenType.closeParen && token.variation != null) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _toggleVariationCollapse(token),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 2.sp, vertical: 2.sp),
          child: Text(
            token.text,
            style: AppTypography.textXsMedium.copyWith(
              color: depthColor.withValues(alpha: 0.85),
              fontStyle: FontStyle.italic,
            ),
          ),
        ),
      );
    }

    return Text(
      token.text,
      style: AppTypography.textXsMedium.copyWith(
        color:
            token.type == NotationTokenType.ellipsis
                ? context.colors.textPrimaryMuted
                : depthColor.withValues(alpha: 0.85),
        fontStyle:
            token.type == NotationTokenType.ellipsis
                ? FontStyle.normal
                : FontStyle.italic,
      ),
    );
  }

  void _toggleVariationCollapse(NotationDisplayToken token) {
    final variation = token.variation;
    if (variation == null) return;

    final variationId = variation.id;
    final defaultCollapsed = token.defaultsToCollapsed;

    setState(() {
      if (defaultCollapsed) {
        if (!_expandedVariationIds.remove(variationId)) {
          _expandedVariationIds.add(variationId);
          _collapsedVariationIds.remove(variationId);
        }
      } else {
        if (!_collapsedVariationIds.remove(variationId)) {
          _collapsedVariationIds.add(variationId);
          _expandedVariationIds.remove(variationId);
        }
      }
    });
  }

  Color _accentColorForToken(NotationDisplayToken token) {
    final depth = math.max(1, token.depth);
    final seed = token.variationColorKey ?? token.variation?.id;
    return _colorForVariationAccent(depth, seed: seed);
  }

  Color _colorForVariationAccent(int depth, {String? seed}) {
    if (seed == null || seed.isEmpty) {
      return _colorForVariationDepth(depth);
    }
    return _colorFromSeed(seed);
  }

  Color _colorFromSeed(String seed) {
    final normalizedSeed = seed.hashCode & 0x7fffffff;
    final random = math.Random(normalizedSeed);
    final hue = random.nextDouble() * 360.0;
    final saturation = 0.45 + random.nextDouble() * 0.35;
    final lightness = 0.45 + random.nextDouble() * 0.25;
    return HSLColor.fromAHSL(1.0, hue, saturation, lightness).toColor();
  }

  Color _colorForVariationDepth(int depth) {
    if (depth <= 0) return context.colors.textPrimary;
    final paletteIndex = (depth - 1) % _variationDepthPalette.length;
    return _variationDepthPalette[paletteIndex];
  }

  Color _resolveMoveColor(NotationDisplayToken token, int currentPly) {
    final node = token.node;
    if (node == null || token.pointerId == null) {
      return context.colors.textPrimary;
    }

    final isPast = currentPly >= 0 && node.ply <= currentPly;
    if (node.isMainline || token.depth <= 0) {
      return isPast ? context.colors.textPrimary : context.colors.textPrimary;
    }

    final depthColor = _colorForVariationAccent(
      token.depth,
      seed: token.variationColorKey ?? token.variation?.id,
    );
    return depthColor.withValues(alpha: isPast ? 0.95 : 0.75);
  }

  void _schedulePointerScroll(ChessMovePointer pointer, String pointerId) {
    if (!widget.isActive) return;
    if (_lastPointer != null &&
        _pointerEquality.equals(_lastPointer!, pointer)) {
      return;
    }
    _lastPointer = List<int>.of(pointer);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _scrollToPointer(pointerId);
    });
  }

  void _scrollToPointer(String pointerId) {
    if (!_scrollController.hasClients) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _scrollToPointer(pointerId);
      });
      return;
    }

    final key = _moveKeys[pointerId];
    final targetContext = key?.currentContext;
    if (targetContext == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _scrollToPointer(pointerId);
      });
      return;
    }

    Scrollable.ensureVisible(
      targetContext,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      alignment: 0.5,
    );
  }
}
