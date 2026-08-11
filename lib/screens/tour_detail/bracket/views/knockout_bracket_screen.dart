import 'dart:math' as math;

import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/screens/chessboard/provider/chess_board_screen_provider_new.dart';
import 'package:chessever2/screens/tour_detail/bracket/models/knockout_bracket.dart';
import 'package:chessever2/screens/tour_detail/bracket/providers/bracket_share_provider.dart';
import 'package:chessever2/screens/tour_detail/bracket/providers/knockout_bracket_provider.dart';
import 'package:chessever2/screens/tour_detail/bracket/widgets/bracket_camera_controls.dart';
import 'package:chessever2/screens/tour_detail/bracket/widgets/bracket_graph_layout.dart';
import 'package:chessever2/screens/tour_detail/bracket/widgets/bracket_states.dart';
import 'package:chessever2/screens/tour_detail/bracket/widgets/knockout_bracket_canvas.dart';
import 'package:chessever2/screens/tour_detail/bracket/widgets/knockout_match_sheet.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/game_card_wrapper/game_card_wrapper_provider.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/user_error_message.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Portrait-first, two-dimensional knockout bracket.
///
/// The owned [TransformationController] and keep-alive state preserve the
/// user's pan/zoom position while switching tournament tabs and while live
/// bracket data refreshes.
class KnockoutBracketScreen extends ConsumerStatefulWidget {
  const KnockoutBracketScreen({super.key});

  @override
  ConsumerState<KnockoutBracketScreen> createState() =>
      _KnockoutBracketScreenState();
}

class _KnockoutBracketScreenState extends ConsumerState<KnockoutBracketScreen>
    with AutomaticKeepAliveClientMixin, SingleTickerProviderStateMixin {
  static const double _maximumOverviewMinimum = 0.04;
  static const double _maximumScale = 2.4;
  static const double _zoomStep = 1.24;

  final TransformationController _transformationController =
      TransformationController();
  late final AnimationController _cameraAnimationController;
  VoidCallback? _cameraAnimationTick;

  Size _viewportSize = Size.zero;
  BracketGraphLayout? _layout;
  KnockoutBracket? _bracket;
  String? _cameraScopeKey;
  String? _focusedMatchKey;
  bool _hasAppliedInitialCamera = false;
  bool _isOverview = false;
  bool _showGestureHint = true;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _cameraAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
  }

  @override
  void dispose() {
    _stopCameraAnimation();
    _cameraAnimationController.dispose();
    _transformationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final state = ref.watch(knockoutBracketProvider);
    final bracket = state.valueOrNull;

    if (bracket != null) {
      if (bracket.isEmpty) return const BracketEmptyView();
      return _buildBracket(context, bracket);
    }

    if (state.hasError) {
      return BracketErrorView(
        message: userFacingError(
          state.error,
          fallback: 'Couldn’t load the bracket. Please try again.',
        ),
        onRetry: () => retryKnockoutBracket(ref),
      );
    }

    return const BracketLoadingView(key: ValueKey('knockout-bracket-loading'));
  }

  Widget _buildBracket(BuildContext context, KnockoutBracket bracket) {
    final layout = buildBracketGraphLayout(bracket);
    final scopeKey = _scopeKey(bracket);
    final bottomSafeInset = MediaQuery.viewPaddingOf(context).bottom;

    return LayoutBuilder(
      builder: (context, constraints) {
        final viewport = constraints.biggest;
        _scheduleCameraPreparation(
          bracket: bracket,
          layout: layout,
          viewport: viewport,
          scopeKey: scopeKey,
        );

        return ColoredBox(
          color: context.colors.background,
          child: Stack(
            children: [
              Positioned.fill(
                // Snapshot target for "Share brackets": the boundary paints the
                // clipped viewport at the user's current pan/zoom, so the shared
                // image captures exactly the framed area of the canvas.
                child: RepaintBoundary(
                  key: ref.watch(bracketShareBoundaryKeyProvider),
                  child: InteractiveViewer(
                    key: const ValueKey('knockout-bracket-viewer'),
                    transformationController: _transformationController,
                    alignment: Alignment.topLeft,
                    constrained: false,
                    clipBehavior: Clip.hardEdge,
                    boundaryMargin: const EdgeInsets.all(420),
                    minScale: _minimumScaleFor(layout, viewport),
                    maxScale: _maximumScale,
                    panEnabled: true,
                    scaleEnabled: true,
                    panAxis: PanAxis.free,
                    trackpadScrollCausesScale: false,
                    onInteractionStart: (_) {
                      _stopCameraAnimation();
                      _markInteracted();
                    },
                    child: KnockoutBracketCanvas(
                      bracket: bracket,
                      layout: layout,
                      focusedMatchKey: _focusedMatchKey,
                      onMatchTap: (match) => _showMatch(match),
                    ),
                  ),
                ),
              ),
              if (bracket.isPartial)
                const Positioned(
                  top: 12,
                  left: 12,
                  child: BracketPartialNote(),
                ),
              Positioned(
                left: 16,
                right: 16,
                bottom: 72 + bottomSafeInset,
                child: Center(
                  child: BracketGestureHint(visible: _showGestureHint),
                ),
              ),
              Positioned(
                right: 16,
                bottom: 16 + bottomSafeInset,
                child: BracketCameraControls(
                  isOverview: _isOverview,
                  onZoomOut: () => _zoomBy(1 / _zoomStep),
                  onToggleOverview:
                      _isOverview ? _focusCurrentStage : _fitOverview,
                  onZoomIn: () => _zoomBy(_zoomStep),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _scopeKey(KnockoutBracket bracket) {
    final selectedKey = bracket.selectedStageKey;
    final selectedStage =
        selectedKey == null ? null : bracket.stageByKey(selectedKey);
    if (selectedStage != null && selectedStage.sourceTourIds.isNotEmpty) {
      return '${selectedStage.key}:${selectedStage.sourceTourIds.join(',')}';
    }
    for (final stage in bracket.stages) {
      if (stage.sourceTourIds.isNotEmpty) {
        return stage.sourceTourIds.first;
      }
    }
    return bracket.stages.map((stage) => stage.key).join('|');
  }

  void _scheduleCameraPreparation({
    required KnockoutBracket bracket,
    required BracketGraphLayout layout,
    required Size viewport,
    required String scopeKey,
  }) {
    _layout = layout;
    _bracket = bracket;
    _viewportSize = viewport;

    if (_cameraScopeKey != scopeKey) {
      _cameraScopeKey = scopeKey;
      _hasAppliedInitialCamera = false;
      _focusedMatchKey = null;
      _isOverview = false;
      _showGestureHint = true;
    }

    if (_hasAppliedInitialCamera || viewport.isEmpty) return;
    _hasAppliedInitialCamera = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _cameraScopeKey != scopeKey) return;
      _focusCurrentStage(animate: false);
    });
  }

  void _markInteracted() {
    if (!_showGestureHint) return;
    // Keep overview mode armed after a pan/pinch so the middle control remains
    // a one-tap return to the readable current round.
    setState(() => _showGestureHint = false);
  }

  KnockoutStage? _preferredStage() {
    final bracket = _bracket;
    if (bracket == null || bracket.stages.isEmpty) return null;

    final currentKey = bracket.currentStageKey;
    if (currentKey != null) {
      final current = bracket.stageByKey(currentKey);
      if (current != null) return current;
    }
    for (final stage in bracket.stages) {
      if (stage.isLive || stage.state == KnockoutStageState.inProgress) {
        return stage;
      }
    }
    for (final stage in bracket.stages.reversed) {
      if (!stage.isComplete) return stage;
    }
    return bracket.stages.last;
  }

  void _focusCurrentStage({bool animate = true}) {
    final stage = _preferredStage();
    final layout = _layout;
    if (stage == null || layout == null || _viewportSize.isEmpty) return;
    final focusRect = layout.readableFocusRectForStage(stage);
    if (focusRect == null) return;

    final readableScale =
        math
            .min(
              1.0,
              (_viewportSize.width - 28) /
                  (BracketGraphMetrics.matchWidth + 24),
            )
            .clamp(0.78, 1.0)
            .toDouble();
    final target = _matrixForSceneCenter(
      focusRect.center,
      scale: readableScale,
    );
    if (mounted) {
      setState(() => _isOverview = false);
    }
    _setCamera(target, animate: animate);
  }

  void _fitOverview() {
    final layout = _layout;
    if (layout == null || _viewportSize.isEmpty) return;
    final availableWidth = math.max(1.0, _viewportSize.width - 28);
    final availableHeight = math.max(1.0, _viewportSize.height - 34);
    final scale =
        math
            .min(
              availableWidth / layout.size.width,
              availableHeight / layout.size.height,
            )
            .clamp(_minimumScaleFor(layout, _viewportSize), 1.0)
            .toDouble();
    final target = _matrixForSceneCenter(
      Offset(layout.size.width / 2, layout.size.height / 2),
      scale: scale,
    );
    setState(() {
      _isOverview = true;
      _showGestureHint = false;
    });
    _setCamera(target);
  }

  void _zoomBy(double factor) {
    if (_viewportSize.isEmpty) return;
    final currentScale = _transformationController.value.getMaxScaleOnAxis();
    final minimumScale = _minimumScaleFor(_layout, _viewportSize);
    final targetScale =
        (currentScale * factor).clamp(minimumScale, _maximumScale).toDouble();
    if ((targetScale - currentScale).abs() < 0.0001) return;

    final viewportCenter = Offset(
      _viewportSize.width / 2,
      _viewportSize.height / 2,
    );
    final sceneCenter = _transformationController.toScene(viewportCenter);
    setState(() {
      _isOverview = false;
      _showGestureHint = false;
    });
    _setCamera(_matrixForSceneCenter(sceneCenter, scale: targetScale));
  }

  Matrix4 _matrixForSceneCenter(Offset sceneCenter, {required double scale}) {
    final viewportCenter = Offset(
      _viewportSize.width / 2,
      _viewportSize.height / 2,
    );
    final translation = Offset(
      viewportCenter.dx - sceneCenter.dx * scale,
      viewportCenter.dy - sceneCenter.dy * scale,
    );
    return Matrix4.identity()
      ..translateByDouble(translation.dx, translation.dy, 0, 1)
      ..scaleByDouble(scale, scale, 1, 1);
  }

  double _minimumScaleFor(BracketGraphLayout? layout, Size viewport) {
    if (layout == null || viewport.isEmpty || layout.size.isEmpty) {
      return _maximumOverviewMinimum;
    }
    final fitScale = math.min(
      math.max(1.0, viewport.width - 28) / layout.size.width,
      math.max(1.0, viewport.height - 34) / layout.size.height,
    );
    // Fit must remain truthful for very large World Cup first rounds. The
    // lower guard only protects pathological custom data from a zero scale.
    return math
        .min(_maximumOverviewMinimum, fitScale)
        .clamp(0.001, _maximumOverviewMinimum)
        .toDouble();
  }

  void _setCamera(Matrix4 target, {bool animate = true}) {
    _stopCameraAnimation();
    if (!animate) {
      _transformationController.value = target;
      return;
    }

    final animation = Matrix4Tween(
      begin: Matrix4.copy(_transformationController.value),
      end: target,
    ).animate(
      CurvedAnimation(
        parent: _cameraAnimationController,
        curve: Curves.easeOutCubic,
      ),
    );
    void tick() {
      _transformationController.value = animation.value;
    }

    _cameraAnimationTick = tick;
    _cameraAnimationController.addListener(tick);
    _cameraAnimationController.forward(from: 0);
  }

  void _stopCameraAnimation() {
    final tick = _cameraAnimationTick;
    if (tick != null) {
      _cameraAnimationController.removeListener(tick);
      _cameraAnimationTick = null;
    }
    _cameraAnimationController.stop();
  }

  void _showMatch(KnockoutMatch match) {
    setState(() {
      _focusedMatchKey = match.key;
      _showGestureHint = false;
    });
    showKnockoutMatchSheet(
      context: context,
      match: match,
      onGameTap: (game) => _openGame(match, game),
    );
  }

  void _openGame(KnockoutMatch match, Games selectedGame) {
    final navigation = bracketNavigationSelection(
      games: match.games,
      selectedGameId: selectedGame.id,
    );
    if (navigation.selectedIndex < 0 || navigation.games.isEmpty || !mounted) {
      return;
    }

    ref
        .read(gameCardWrapperProvider)
        .navigateToChessBoard(
          context: context,
          orderedGames: navigation.games,
          gameIndex: navigation.selectedIndex,
          onReturnFromChessboard: null,
          listPolicy: BoardNavigationListPolicy.preserve,
        );
  }
}

@visibleForTesting
({List<GamesTourModel> games, int selectedIndex}) bracketNavigationSelection({
  required Iterable<Games> games,
  required String selectedGameId,
}) {
  final converted = <GamesTourModel>[];
  var selectedIndex = -1;
  for (final game in games) {
    try {
      final model = GamesTourModel.fromGame(game);
      converted.add(model);
      if (game.id == selectedGameId) selectedIndex = converted.length - 1;
    } catch (_) {
      // Keep malformed evidence out of chessboard navigation. In particular,
      // never let a failed selected leg inherit the index of a later game.
    }
  }
  return (games: List.unmodifiable(converted), selectedIndex: selectedIndex);
}
