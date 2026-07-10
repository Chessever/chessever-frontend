import 'dart:async';
import 'dart:math' as math;

import 'package:chessever2/e2e/e2e_ids.dart';
import 'package:chessever2/revenue_cat_service/subscribe_state.dart';
import 'package:chessever2/screens/chessboard/notation/notation_pointer.dart';
import 'package:chessever2/screens/chessboard/notation/notation_token_builder.dart';
import 'package:chessever2/screens/chessboard/notation/notation_tree.dart';
import 'package:chessever2/screens/chessboard/widgets/nag_display.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/figurine_notation.dart';
import 'package:chessground/chessground.dart';
import 'package:collection/collection.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'package:chessever2/providers/board_settings_provider_new.dart';
import 'package:chessever2/providers/engine_settings_provider.dart';
import 'package:chessever2/screens/chessboard/chess_board_screen_new.dart';
import 'package:chessever2/screens/chessboard/analysis/chess_game_navigator.dart';
import 'package:chessever2/screens/chessboard/provider/chess_board_screen_provider_new.dart';
import 'package:chessever2/screens/settings/settings_page.dart';
import 'package:chessever2/screens/chessboard/widgets/chess_board_bottom_navbar.dart';
import 'package:chessever2/screens/chessboard/widgets/evaluation_bar_widget.dart';
import 'package:chessever2/screens/chessboard/widgets/switch_views_tutorial_overlay.dart';
import 'package:chessever2/screens/gamebase/providers/explorer_eval_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/gamebase/services/player_opening_tree.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/svg_asset.dart';
import 'package:chessever2/widgets/liquid_glass/glass_back_button.dart';
import 'package:chessever2/widgets/liquid_glass/glass_full_screen_page.dart';
import 'package:chessever2/widgets/liquid_glass/glass_island_stack.dart';
import 'package:chessever2/widgets/liquid_glass/glass_island_top_bar.dart';
import 'package:chessever2/widgets/liquid_glass/glass_motion.dart';
import 'package:chessever2/widgets/liquid_glass/glass_title_chip.dart';
import 'package:chessever2/repository/local_storage/local_storage_repository.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:chessever2/widgets/game_filter/rating_tier_filter.dart';
import 'package:chessever2/widgets/game_filter/wheel_range_filter.dart';
import 'package:chessever2/screens/gamebase/providers/gamebase_providers.dart';
import 'package:chessever2/screens/gamebase/providers/gamebase_explorer_state.dart';
import 'package:chessever2/screens/gamebase/widgets/widgets.dart';
import 'package:chessever2/screens/gamebase/models/models.dart';
import 'package:chessever2/main.dart' show routeObserver;
import 'package:chessever2/widgets/auth/auth_upgrade_sheet.dart';
import 'package:chessever2/widgets/paywall/premium_paywall_sheet.dart';

/// Main screen for exploring the Gamebase opening database.
/// Displays a chess board, move statistics, and navigation controls.
class GamebaseExplorerScreen extends ConsumerStatefulWidget {
  const GamebaseExplorerScreen({
    super.key,
    this.initialPlayer,
    this.initialFilters,
  });

  /// Creates an isolated explorer scope so other mounted routes (for example
  /// hidden player-profile/game-card widgets) cannot mutate this explorer's
  /// provider state and continuously restart engine analysis.
  static Widget scoped({
    Key? key,
    GamebasePlayer? initialPlayer,
    GamebaseFilters? initialFilters,
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
      ),
    );
  }

  /// When non-null, the explorer opens pre-filtered to this player's games.
  final GamebasePlayer? initialPlayer;

  /// Optional filters to pre-apply (e.g. time control, rating from player profile).
  final GamebaseFilters? initialFilters;

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

  void _resetExplorerState({bool fetch = false, bool preserveScope = true}) {
    final notifier = ref.read(gamebaseExplorerProvider.notifier);
    final scopedPlayer = preserveScope ? widget.initialPlayer : null;

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
      ref
          .read(explorerEvalProvider.notifier)
          .setEngineEnabled(
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

      // Always start fresh; preserve player scope when present.
      _resetExplorerState(fetch: true);
    });
  }

  @override
  void dispose() {
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
    await ref
        .read(engineSettingsProviderNew.notifier)
        .toggleEngineAnalysis(nextValue);
  }

  void _startLongPressBackward() {
    _backwardLongPressTimer?.cancel();
    _backwardLongPressTimer = Timer.periodic(
      const Duration(milliseconds: 130),
      (_) {
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
        ref.read(gamebaseExplorerProvider).currentMoveNumber;
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
    final controlExtent = _floatingControlExtent(context);
    final viewPadding = MediaQuery.viewPaddingOf(context);
    final topContentInset = _topContentInset(context, controlExtent);
    final bottomContentInset = _bottomContentInset(context, controlExtent);
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

    return PopScope(
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) return;
        _resetExplorerState();
      },
      child: GlassFullScreenPage(
        key: e2eKey(E2eIds.openingExplorerRoot),
        backgroundColor: context.colors.surface,
        includeContentSafeArea: false,
        topOverlayPadding: const EdgeInsets.only(top: 4),
        bottomOverlayPadding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
        contentPadding: EdgeInsets.fromLTRB(
          viewPadding.left,
          topContentInset,
          viewPadding.right,
          bottomContentInset,
        ),
        topOverlay: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth:
                  ResponsiveHelper.isTablet
                      ? ResponsiveHelper.contentMaxWidth
                      : double.infinity,
            ),
            child: GlassIslandStack(
              includeStatusBar: false,
              gap: 8,
              children: [
                _buildTopBar(context, controlExtent),
                _buildViewSwitcher(context, controlExtent),
              ],
            ),
          ),
        ),
        bottomOverlay: _buildBottomControls(
          context,
          state: state,
          showEngineAnalysis: showEngineAnalysis,
          controlExtent: controlExtent,
        ),
        content: LayoutBuilder(
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
    );
  }

  double _floatingControlExtent(BuildContext context) {
    final scaledLabelHeight = MediaQuery.textScalerOf(context).scale(16);
    final dynamicExtent = scaledLabelHeight + 28;
    return dynamicExtent < 48 ? 48 : dynamicExtent;
  }

  double _topContentInset(BuildContext context, double controlExtent) {
    return MediaQuery.viewPaddingOf(context).top +
        4 +
        controlExtent +
        6 +
        8 +
        controlExtent +
        4 +
        8;
  }

  double _bottomContentInset(BuildContext context, double controlExtent) {
    return MediaQuery.viewPaddingOf(context).bottom + controlExtent + 24;
  }

  /// Phone layout — identical to the original layout.
  Widget _buildPhoneLayout(
    BoxConstraints constraints, {
    required bool showEngineAnalysis,
  }) {
    final state = ref.watch(gamebaseExplorerProvider);
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
                    fen: state.currentFen,
                    boardSize: boardSize,
                    isFlipped: _isFlipped,
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
                    const Expanded(child: _ExplorerBottomPanels()),
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
                      fen: state.currentFen,
                      boardSize: boardSize,
                      isFlipped: _isFlipped,
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
                    const Expanded(child: _ExplorerBottomPanels()),
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
                      fen: state.currentFen,
                      boardSize: boardSize,
                      isFlipped: _isFlipped,
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
                      const Expanded(child: _ExplorerBottomPanels()),
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

  Widget _buildTopBar(BuildContext context, double controlExtent) {
    final state = ref.watch(gamebaseExplorerProvider);
    final reduceMotion = GlassMotion.reduceMotion(context);
    final playerLabel =
        state.filters.selectedPlayers.isNotEmpty
            ? state.filters.selectedPlayers.first.titleAndName
            : 'Opening Explorer';
    final viewPadding = MediaQuery.viewPaddingOf(context);
    final viewportWidth =
        MediaQuery.sizeOf(context).width - viewPadding.left - viewPadding.right;
    final primaryActionWidth = controlExtent + 18;
    final titleSpace = viewportWidth - 200 - primaryActionWidth;
    final showTitle = titleSpace >= 64;
    void resetExplorer() =>
        _resetExplorerState(fetch: true, preserveScope: true);
    void openFilters() => _showFilterSheet(context);

    return Semantics(
      label: '$playerLabel explorer controls',
      container: true,
      child: GlassIslandTopBar(
        topPadding: 0,
        height: controlExtent,
        leading: const GlassBackButton(),
        title:
            showTitle
                ? GlassTitleChip(
                  label: playerLabel,
                  height: controlExtent,
                  maxWidth: math.min(160.w, titleSpace),
                )
                : null,
        trailing: [
          Tooltip(
            message: 'Reset explorer',
            child: Semantics(
              label: 'Reset explorer',
              button: true,
              onTap: resetExplorer,
              child: ExcludeSemantics(
                child: GlassIconButton(
                  icon: Icon(
                    Icons.restart_alt,
                    color: context.colors.iconPrimary,
                  ),
                  onPressed: resetExplorer,
                  size: 48,
                  iconSize: 20,
                  interactionScale: reduceMotion ? 1 : 0.95,
                  anchorStretch: !reduceMotion,
                  useOwnLayer: true,
                ),
              ),
            ),
          ),
          Tooltip(
            message: 'Filters',
            child: Semantics(
              label:
                  _shouldShowClearFilters(state)
                      ? 'Filters, active'
                      : 'Filters',
              button: true,
              onTap: openFilters,
              child: ExcludeSemantics(
                child: GlassBadge(
                  count: _shouldShowClearFilters(state) ? 1 : 0,
                  backgroundColor: kPrimaryColor,
                  child: GlassIconButton(
                    icon: Icon(Icons.tune, color: context.colors.iconPrimary),
                    onPressed: openFilters,
                    size: 48,
                    iconSize: 18,
                    interactionScale: reduceMotion ? 1 : 0.95,
                    anchorStretch: !reduceMotion,
                    useOwnLayer: true,
                  ),
                ),
              ),
            ),
          ),
          Semantics(
            label: 'Open position in analysis',
            button: true,
            onTap: () => _openAnalysis(context),
            child: ExcludeSemantics(
              child: GlassButton.custom(
                key: e2eKey(E2eIds.openingExplorerDoneButton),
                label: 'Open position in analysis',
                onTap: () => _openAnalysis(context),
                width: primaryActionWidth,
                height: controlExtent,
                useOwnLayer: true,
                style: GlassButtonStyle.prominent,
                interactionScale: reduceMotion ? 1 : 1.03,
                stretch: reduceMotion ? 0 : 0.3,
                shape: LiquidRoundedSuperellipse(
                  borderRadius: controlExtent / 2,
                ),
                child: Text(
                  'Done',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.textSmMedium.copyWith(
                    color: context.colors.textPrimary,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildViewSwitcher(BuildContext context, double controlExtent) {
    final currentPage = ref.watch(explorerPageIndexProvider);
    final viewPadding = MediaQuery.viewPaddingOf(context);
    final availableWidth =
        MediaQuery.sizeOf(context).width -
        viewPadding.left -
        viewPadding.right -
        96;
    final width = math.min(availableWidth, 280.0);

    return Align(
      alignment: Alignment.topCenter,
      child: GlassContainer(
        width: width,
        height: controlExtent,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        alignment: Alignment.center,
        useOwnLayer: true,
        quality: GlassQuality.standard,
        shape: LiquidRoundedSuperellipse(borderRadius: controlExtent / 2),
        child: _ExplorerSegmentedTitle(currentPage: currentPage),
      ),
    );
  }

  Widget _buildBottomControls(
    BuildContext context, {
    required GamebaseExplorerState state,
    required bool showEngineAnalysis,
    required double controlExtent,
  }) {
    final fullWidth = MediaQuery.sizeOf(context).width;
    final viewPadding = MediaQuery.viewPaddingOf(context);
    final islandWidth = math.min(
      fullWidth - viewPadding.left - viewPadding.right - 24,
      ResponsiveHelper.isTablet ? 520.0 : 380.0,
    );
    final barHeight = controlExtent + 8;
    final buttonWidth = (islandWidth - 8) / 4;

    void openEngineSettings() {
      requireFullAuthGuard(context).then((allowed) {
        if (!allowed || !context.mounted) return;
        Navigator.of(
          context,
        ).push(SettingsPage.route(initiallyExpanded: SettingsSection.board));
      });
    }

    final VoidCallback? goBack =
        state.canGoBack
            ? () => ref.read(gamebaseExplorerProvider.notifier).goBack()
            : null;
    final VoidCallback? goForward =
        state.canGoForward
            ? () async {
              final allowed = await _ensureExplorerForwardAllowed();
              if (!allowed) return;
              ref.read(gamebaseExplorerProvider.notifier).goForward();
            }
            : null;

    Widget semanticControl({
      required String label,
      required Widget child,
      required VoidCallback? onTap,
      VoidCallback? onLongPress,
      bool? toggled,
    }) {
      return Semantics(
        label: label,
        button: true,
        enabled: onTap != null,
        toggled: toggled,
        onTap: onTap,
        onLongPress: onLongPress,
        child: ExcludeSemantics(child: child),
      );
    }

    final island = GlassContainer(
      width: islandWidth,
      height: barHeight,
      padding: const EdgeInsets.all(4),
      alignment: Alignment.center,
      useOwnLayer: true,
      quality: GlassQuality.standard,
      shape: LiquidRoundedSuperellipse(borderRadius: barHeight / 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          semanticControl(
            label:
                showEngineAnalysis
                    ? 'Hide engine analysis'
                    : 'Show engine analysis',
            toggled: showEngineAnalysis,
            onTap: _toggleEngineAnalysis,
            onLongPress: openEngineSettings,
            child: ChessSvgBottomNavbar(
              key: e2eKey(E2eIds.boardEngineToggle),
              width: buttonWidth,
              svgPath: SvgAsset.laptop,
              onPressed: _toggleEngineAnalysis,
              onLongPress: openEngineSettings,
              isActive: showEngineAnalysis,
            ),
          ),
          semanticControl(
            label: 'Flip board',
            onTap: () => setState(() => _isFlipped = !_isFlipped),
            child: ChessSvgBottomNavbar(
              key: e2eKey(E2eIds.boardFlip),
              width: buttonWidth,
              svgPath: SvgAsset.refresh,
              onPressed: () => setState(() => _isFlipped = !_isFlipped),
            ),
          ),
          semanticControl(
            label: 'Previous move',
            onTap: goBack,
            onLongPress: state.canGoBack ? _startLongPressBackward : null,
            child: ChessSvgBottomNavbarWithLongPress(
              key: e2eKey(E2eIds.boardMoveBack),
              svgPath: SvgAsset.left_arrow,
              width: buttonWidth,
              onPressed: goBack,
              onLongPressStart:
                  state.canGoBack ? _startLongPressBackward : null,
              onLongPressEnd: _stopLongPressBackward,
            ),
          ),
          semanticControl(
            label: 'Next move',
            onTap: goForward,
            onLongPress: state.canGoForward ? _startLongPressForward : null,
            child: ChessSvgBottomNavbarWithLongPress(
              key: e2eKey(E2eIds.boardMoveForward),
              svgPath: SvgAsset.right_arrow,
              width: buttonWidth,
              onPressed: goForward,
              onLongPressStart:
                  state.canGoForward ? _startLongPressForward : null,
              onLongPressEnd: _stopLongPressForward,
              showBadge: false,
            ),
          ),
        ],
      ),
    );

    final isTabletLandscape =
        ResponsiveHelper.isTablet && ResponsiveHelper.isLandscape;
    return Center(
      child: GestureDetector(
        onHorizontalDragStart: isTabletLandscape ? (_) {} : null,
        onHorizontalDragUpdate: isTabletLandscape ? (_) {} : null,
        onHorizontalDragEnd: isTabletLandscape ? (_) {} : null,
        behavior: HitTestBehavior.opaque,
        child: island,
      ),
    );
  }

  void _openAnalysis(BuildContext context) {
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
              hideEventInfo: true,
              showGamebaseButton: false,
              disableGamebaseOverlayByDefault: true,
              startAtLastMove: true,
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
    this.isFlipped = false,
  });

  final String fen;
  final double boardSize;
  final bool isFlipped;

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
    _boardController = ChessboardController(game: _gameDataFor(widget.fen));
  }

  @override
  void didUpdateWidget(covariant _GamebaseChessBoard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.fen != widget.fen) {
      _boardController.updatePosition(_gameDataFor(widget.fen));
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
  GameData _gameDataFor(String fen) {
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
      );
    }
    return GameData(
      fen: fen,
      playerSide:
          position.turn == Side.white ? PlayerSide.white : PlayerSide.black,
      sideToMove: position.turn,
      validMoves: makeLegalMoves(position),
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
                    animationDuration: GlassMotion.resolveDuration(
                      context,
                      const Duration(milliseconds: 200),
                    ),
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
                    // Playing this move would land past the free-tier
                    // boundary — surface the paywall instead of advancing
                    // and then blurring the panel. Chessground snaps the
                    // piece back when state doesn't change.
                    if (!kDebugMode &&
                        !ref.read(subscriptionProvider).isSubscribed) {
                      final currentMoveNumber =
                          ref.read(gamebaseExplorerProvider).currentMoveNumber;
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
        duration: GlassMotion.resolveDuration(
          context,
          const Duration(milliseconds: 180),
        ),
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
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(8.br),
        border: Border.all(color: context.colors.divider),
      ),
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
    );
  }
}

/// Compact engine analysis lines displayed above the move statistics.
/// Shows up to 3 Stockfish PV lines, each as a single horizontal row
/// with an eval badge and SAN moves.
class _ExplorerEngineLines extends ConsumerWidget {
  const _ExplorerEngineLines();
  static const int _kMaxRows = 3;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final evalState = ref.watch(explorerEvalProvider);
    final pvLines = evalState.pvLines;

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

    final lines = pvLines.take(_kMaxRows).toList();
    final notifier = ref.read(gamebaseExplorerProvider.notifier);
    final uciRegex = RegExp(r'^[a-h][1-8][a-h][1-8][qrbn]?$');

    return Column(
      key: e2eKey(E2eIds.openingExplorerEngineLines),
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < _kMaxRows; i++) ...[
          if (i > 0)
            Divider(
              height: 1,
              color: context.colors.divider.withValues(alpha: 0.3),
              indent: 12.sp,
              endIndent: 12.sp,
            ),
          if (i < lines.length)
            _EngineLine(
              line: lines[i],
              lineIndex: i,
              isWhiteToMove: isWhiteToMove,
              startMoveNumber: startMoveNumber,
              useFigurine: useFigurine,
              pieceAssets: pieceAssets,
              onTap: () async {
                if (lines[i].uciMoves.isEmpty) return;
                final firstUci = lines[i].uciMoves.first.trim().toLowerCase();
                if (!uciRegex.hasMatch(firstUci)) return;
                if (!kDebugMode &&
                    !ref.read(subscriptionProvider).isSubscribed) {
                  final currentMoveNumber =
                      ref.read(gamebaseExplorerProvider).currentMoveNumber;
                  if (currentMoveNumber >= kFreeExplorerMoveNumberLimit) {
                    if (!context.mounted) return;
                    final unlocked = await requirePremiumGuard(context, ref);
                    if (!unlocked) return;
                  }
                }
                notifier.makeMove(firstUci);
              },
            )
          else
            _EngineLinePlaceholder(
              isPrimary: i == 0,
              isEvaluating: evalState.isEvaluating,
            ),
        ],
        Divider(color: context.colors.divider, height: 1),
      ],
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

/// Single engine line row: eval badge + SAN move text.
class _EngineLine extends StatelessWidget {
  const _EngineLine({
    required this.line,
    required this.lineIndex,
    required this.isWhiteToMove,
    required this.startMoveNumber,
    required this.useFigurine,
    required this.pieceAssets,
    this.onTap,
  });

  final ExplorerPvLine line;
  final int lineIndex;
  final bool isWhiteToMove;
  final int startMoveNumber;
  final bool useFigurine;
  final PieceAssets pieceAssets;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final evalText = line.displayEval;

    // Eval badge: white bg for white advantage, dark for black, neutral for 0.0.
    final bool isWhiteWinning =
        (line.mate != null && line.mate! > 0) ||
        (line.evaluation != null && line.evaluation! > 0);
    final bool isBlackWinning =
        (line.mate != null && line.mate! < 0) ||
        (line.evaluation != null && line.evaluation! < 0);

    Color evalBgColor;
    Color evalTextColor;
    if (isWhiteWinning) {
      evalBgColor = context.colors.textPrimary;
      evalTextColor = context.colors.surface;
    } else if (isBlackWinning) {
      evalBgColor = context.colors.divider;
      evalTextColor = context.colors.textPrimary;
    } else {
      evalBgColor = context.colors.textSecondary.withValues(alpha: 0.3);
      evalTextColor = context.colors.textPrimary;
    }

    final moveText = _formatMoveText();
    final moveStyle = TextStyle(
      color: context.colors.textPrimary.withValues(
        alpha: lineIndex == 0 ? 0.9 : 0.6,
      ),
      fontSize: 12.f,
      fontWeight: lineIndex == 0 ? FontWeight.w500 : FontWeight.w400,
    );

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 5.sp, horizontal: 12.sp),
          child: Row(
            children: [
              // Eval badge
              Container(
                width: 44.w,
                padding: EdgeInsets.symmetric(vertical: 2.sp),
                decoration: BoxDecoration(
                  color: evalBgColor,
                  borderRadius: BorderRadius.circular(3.br),
                ),
                child: Text(
                  evalText,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: evalTextColor,
                    fontSize: 11.f,
                    fontWeight: FontWeight.w700,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              SizedBox(width: 8.sp),
              // Moves
              Expanded(
                child:
                    useFigurine
                        ? RichText(
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          text: TextSpan(
                            children: buildFigurineSpans(
                              text: moveText,
                              pieceAssets: pieceAssets,
                              style: moveStyle,
                              pieceSize: 14.f,
                            ),
                          ),
                        )
                        : Text(
                          moveText,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: moveStyle,
                        ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatMoveText() {
    if (line.sanMoves.isEmpty) return '';
    final buffer = StringBuffer();
    var moveNum = startMoveNumber;
    var isWhite = isWhiteToMove;

    for (var i = 0; i < line.sanMoves.length; i++) {
      if (isWhite) {
        if (i > 0) buffer.write(' ');
        buffer.write('$moveNum.');
      } else if (i == 0) {
        buffer.write('$moveNum...');
      } else {
        buffer.write(' ');
      }
      buffer.write(line.sanMoves[i]);

      if (!isWhite) moveNum++;
      isWhite = !isWhite;
    }
    return buffer.toString();
  }
}

// Floating segmented island content that toggles between Explorer (page 0)
// and Notation (page 1). Tap-to-cycle is preserved from the original app bar.
class _ExplorerSegmentedTitle extends ConsumerWidget {
  const _ExplorerSegmentedTitle({required this.currentPage});

  final int currentPage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    void toggleView() {
      ref.read(explorerPageIndexProvider.notifier).state =
          (currentPage + 1) % 2;
    }

    return Semantics(
      label:
          currentPage == 0
              ? 'Opening Explorer: Moves view. Tap to switch to notation.'
              : 'Opening Explorer: Notation view. Tap to switch to moves.',
      button: true,
      onTap: toggleView,
      child: ExcludeSemantics(
        child: GestureDetector(
          onTap: toggleView,
          behavior: HitTestBehavior.opaque,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _SegmentLabel(label: 'Explorer', isActive: currentPage == 0),
              SizedBox(width: 8.sp),
              _ExplorerPageDot(isSelected: currentPage == 0),
              SizedBox(width: 4.sp),
              _ExplorerPageDot(isSelected: currentPage == 1),
              SizedBox(width: 8.sp),
              _SegmentLabel(label: 'Notation', isActive: currentPage == 1),
            ],
          ),
        ),
      ),
    );
  }
}

class _SegmentLabel extends StatelessWidget {
  const _SegmentLabel({required this.label, required this.isActive});

  final String label;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    return AnimatedDefaultTextStyle(
      duration: GlassMotion.resolveDuration(
        context,
        const Duration(milliseconds: 200),
      ),
      style: TextStyle(
        color:
            isActive
                ? context.colors.textPrimary
                : context.colors.textSecondary.withValues(alpha: 0.7),
        fontSize: 13.f,
        // Constant weight prevents layout shift as the active label changes.
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
      ),
      child: Text(label),
    );
  }
}

class _ExplorerPageDot extends StatelessWidget {
  const _ExplorerPageDot({required this.isSelected});

  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: GlassMotion.resolveDuration(
        context,
        const Duration(milliseconds: 180),
      ),
      curve: Curves.easeOutCubic,
      width: isSelected ? 12.sp : 4.sp,
      height: 4.sp,
      decoration: BoxDecoration(
        color:
            isSelected
                ? context.colors.textPrimary.withValues(alpha: 0.92)
                : context.colors.textSecondary.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(999.br),
      ),
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
  const _ExplorerBottomPanels();

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
  bool _hasCheckedWalkthrough = false;
  bool _showTutorialOverlay = false;
  OverlayEntry? _tutorialEntry;

  @override
  void initState() {
    super.initState();
    final initialPage = ref.read(explorerPageIndexProvider);
    _currentPageIndex = initialPage;
    _pageController = PageController(initialPage: initialPage);
    _setupSwipeAnimation();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _hasCheckedWalkthrough) return;
      _hasCheckedWalkthrough = true;
      _checkAndShowWalkthrough();
    });
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

  Future<void> _checkAndShowWalkthrough() async {
    if (GlassMotion.reduceMotion(context)) return;

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
        if (GlassMotion.reduceMotion(context)) {
          _pageController.jumpToPage(next);
        } else {
          _pageController.animateToPage(
            next,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
          );
        }
      }
    });

    return PageView(
      controller: _pageController,
      onPageChanged: (page) {
        if (_showTutorialOverlay) return;
        _currentPageIndex = page;
        ref.read(explorerPageIndexProvider.notifier).state = page;
      },
      children: [
        const MoveStatisticsPanel(
          key: PageStorageKey<String>('opening-explorer-moves-panel'),
        ),
        _ExplorerNotationView(
          key: const PageStorageKey<String>('opening-explorer-notation-panel'),
          isActive: ref.watch(explorerPageIndexProvider) == 1,
        ),
      ],
    );
  }
}

class _ExplorerNotationViewState extends ConsumerState<_ExplorerNotationView> {
  static const int _autoCollapseDepth = 3;
  static const int _autoCollapseMoveThreshold = 12;
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
      autoCollapseMoveThreshold: _autoCollapseMoveThreshold,
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
                duration: GlassMotion.resolveDuration(
                  context,
                  const Duration(milliseconds: 150),
                ),
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
                    duration: GlassMotion.resolveDuration(
                      context,
                      const Duration(milliseconds: 150),
                    ),
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
      duration: GlassMotion.resolveDuration(
        context,
        const Duration(milliseconds: 220),
      ),
      curve: Curves.easeOutCubic,
      alignment: 0.5,
    );
  }
}
