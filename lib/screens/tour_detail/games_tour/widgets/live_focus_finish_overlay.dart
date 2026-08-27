import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/event_no_spoilers_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/game_display_mode_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/live_focus_finish_hold_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/games_tour_content_provider.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

@visibleForTesting
const liveFocusFinishOverlayKey = ValueKey<String>('live-focus-finish-overlay');

@visibleForTesting
const liveFocusFinishScoreKey = ValueKey<String>('live-focus-finish-score');

/// Half-transparent dark grey used while a just-finished Live First board
/// stays pinned so the final score can be read before the structured exit.
const Color kLiveFocusFinishOverlayFill = Color(0x802C2C2E);

/// Detects a live → finished transition, holds the board in the Live First
/// tier, paints the score overlay, then collapses the card out of the live
/// slot before the re-sort is allowed to move it.
class LiveFocusFinishLayer extends ConsumerStatefulWidget {
  const LiveFocusFinishLayer({
    required this.game,
    required this.child,
    this.comparison = MatchComparison.sameOrder,
    this.borderRadius,
    super.key,
  });

  final GamesTourModel game;
  final Widget child;
  final MatchComparison comparison;
  final BorderRadius? borderRadius;

  @override
  ConsumerState<LiveFocusFinishLayer> createState() =>
      _LiveFocusFinishLayerState();
}

class _LiveFocusFinishLayerState extends ConsumerState<LiveFocusFinishLayer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _exitController;
  late final Animation<double> _exitSize;
  late final Animation<double> _exitFade;
  late final Animation<Offset> _exitSlide;

  @override
  void initState() {
    super.initState();
    _exitController = AnimationController(
      vsync: this,
      duration: kLiveFocusFinishExitDuration,
    );
    final exitCurve = CurvedAnimation(
      parent: _exitController,
      curve: Curves.easeInCubic,
    );
    _exitSize = Tween<double>(begin: 1, end: 0).animate(exitCurve);
    _exitFade = Tween<double>(begin: 1, end: 0).animate(exitCurve);
    _exitSlide = Tween<Offset>(
      begin: Offset.zero,
      end: const Offset(0, 0.08),
    ).animate(exitCurve);
  }

  @override
  void didUpdateWidget(LiveFocusFinishLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    _maybeHold(oldWidget.game, widget.game);
  }

  @override
  void dispose() {
    _exitController.dispose();
    super.dispose();
  }

  void _maybeHold(GamesTourModel previous, GamesTourModel next) {
    if (previous.gameId != next.gameId) return;
    if (previous.effectiveGameStatus.isFinished) return;
    if (!next.effectiveGameStatus.isFinished) return;
    final tourId = next.tourId;
    if (tourId.isEmpty) return;
    if (ref.read(gameDisplayModeProvider(tourId)) !=
        GameDisplayMode.hideFinishedGames) {
      return;
    }
    Future<void>(() {
      if (!mounted) return;
      ref.read(liveFocusFinishHoldProvider(tourId).notifier).hold(next.gameId);
    });
  }

  void _syncExit(LiveFocusFinishPhase? phase) {
    if (phase == LiveFocusFinishPhase.exiting) {
      if (_exitController.status == AnimationStatus.dismissed) {
        _exitController.forward();
      }
      return;
    }
    if (_exitController.value != 0) {
      _exitController.reset();
    }
  }

  @override
  Widget build(BuildContext context) {
    final tourId = widget.game.tourId;
    final phase =
        tourId.isEmpty
            ? null
            : ref.watch(
              liveFocusFinishHoldProvider(
                tourId,
              ).select((state) => state.phaseOf(widget.game.gameId)),
            );
    if (tourId.isNotEmpty) {
      ref.listen<LiveFocusFinishPhase?>(
        liveFocusFinishHoldProvider(
          tourId,
        ).select((state) => state.phaseOf(widget.game.gameId)),
        (previous, next) => _syncExit(next),
      );
    }
    if (phase == LiveFocusFinishPhase.exiting &&
        _exitController.status == AnimationStatus.dismissed) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _syncExit(phase);
      });
    }

    final hideSpoilers =
        widget.game.source == GameSource.supabase &&
        ref.watch(
          eventNoSpoilersProvider(tourId).select((state) => state.enabled),
        );
    final showOverlay = phase != null && !hideSpoilers;

    Widget content = widget.child;
    if (showOverlay) {
      final radius = widget.borderRadius ?? BorderRadius.circular(12.br);
      content = Stack(
        children: [
          widget.child,
          Positioned.fill(
            child: IgnorePointer(
              child: ClipRRect(
                borderRadius: radius,
                child: LiveFocusFinishScoreOverlay(
                  score: gameResultScoreLabel(
                    status: widget.game.effectiveGameStatus,
                    comparison: widget.comparison,
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    }

    if (phase == null && _exitController.value == 0) {
      return content;
    }

    return SizeTransition(
      sizeFactor: _exitSize,
      alignment: Alignment.topCenter,
      child: FadeTransition(
        opacity: _exitFade,
        child: SlideTransition(position: _exitSlide, child: content),
      ),
    );
  }
}

class LiveFocusFinishScoreOverlay extends StatefulWidget {
  const LiveFocusFinishScoreOverlay({required this.score, super.key});

  final String score;

  @override
  State<LiveFocusFinishScoreOverlay> createState() =>
      _LiveFocusFinishScoreOverlayState();
}

class _LiveFocusFinishScoreOverlayState
    extends State<LiveFocusFinishScoreOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
    _scale = Tween<double>(
      begin: 0.84,
      end: 1,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutBack));
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      key: liveFocusFinishOverlayKey,
      opacity: _fade,
      child: ColoredBox(
        color: kLiveFocusFinishOverlayFill,
        child: Center(
          child: ScaleTransition(
            scale: _scale,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 16.sp),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  widget.score,
                  key: liveFocusFinishScoreKey,
                  textAlign: TextAlign.center,
                  style: AppTypography.displaySmBold.copyWith(
                    color: Colors.white,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String gameResultScoreLabel({
  required GameStatus status,
  MatchComparison comparison = MatchComparison.sameOrder,
}) {
  final reversed = comparison == MatchComparison.oppositeOrder;
  switch (status) {
    case GameStatus.whiteWins:
      return reversed ? '0–1' : '1–0';
    case GameStatus.blackWins:
      return reversed ? '1–0' : '0–1';
    case GameStatus.draw:
      return '½–½';
    case GameStatus.ongoing:
      return '*';
    case GameStatus.unknown:
      return '';
  }
}
