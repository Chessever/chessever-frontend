import 'package:skeletonizer/skeletonizer.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:visibility_detector/visibility_detector.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/skeleton_widget.dart';
import '../models/games_tour_model.dart';
import '../providers/tour_game_snapshot_provider.dart';
import '../providers/tournament_card_visibility_provider.dart';

/// Scroll caches and shrink-wrapped team lists mount offscreen children. Keep
/// those children as cheap placeholders until they actually intersect the view.
class ViewportGameCard extends ConsumerStatefulWidget {
  const ViewportGameCard({
    super.key,
    required this.game,
    required this.builder,
    this.board = false,
    this.grid = false,
  });

  final GamesTourModel game;
  final WidgetBuilder builder;
  final bool board;
  final bool grid;

  @override
  ConsumerState<ViewportGameCard> createState() => _ViewportGameCardState();
}

class _ViewportGameCardState extends ConsumerState<ViewportGameCard> {
  final _token = Object();
  late final _visibilityKey = UniqueKey();
  late final StateController<Map<Object, String>> _visibleCards;
  bool _visible = false;
  bool _visited = false;
  Size? _renderedSize;

  @override
  void initState() {
    super.initState();
    _visibleCards = ref.read(visibleTournamentCardsProvider.notifier);
  }

  void _onVisibility(VisibilityInfo info) {
    if (!mounted) return;
    final visible = info.visibleFraction > 0;
    if (_visible && _visited) _renderedSize = info.size;
    if (visible == _visible) return;
    _setRegistered(visible);
    setState(() {
      _visible = visible;
      _visited |= visible;
    });
  }

  void _setRegistered(bool visible) {
    final next = {..._visibleCards.state}..remove(_token);
    if (visible) next[_token] = widget.game.gameId;
    _visibleCards.state = next;
  }

  @override
  void didUpdateWidget(ViewportGameCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.game.gameId != widget.game.gameId) {
      _visited = _visible;
      _renderedSize = null;
      scheduleMicrotask(() {
        if (mounted) _setRegistered(_visible);
      });
    }
  }

  @override
  void dispose() {
    final cards = _visibleCards;
    final token = _token;
    scheduleMicrotask(() {
      if (cards.mounted) cards.state = {...cards.state}..remove(token);
    });
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Preserve an already-requested snapshot while this cached row is mounted;
    // scrolling back should not download the same PGN again. Never prefetch a
    // snapshot for a row that has not reached the viewport.
    final snapshot =
        _visited && widget.game.isPgnDeferred
            ? ref.watch(tourGameSnapshotProvider(widget.game.gameId))
            : null;
    final ready = _visible && snapshot?.isLoading != true;
    return VisibilityDetector(
      key: _visibilityKey,
      onVisibilityChanged: _onVisibility,
      child:
          ready
              ? TournamentCardViewport(child: Builder(builder: widget.builder))
              : TickerMode(
                enabled: _visible,
                child: TournamentCardShimmer(
                  board: widget.board,
                  grid: widget.grid,
                  size: _renderedSize,
                ),
              ),
    );
  }
}

/// Reuses the application's shimmer effect without building a real chessboard,
/// player lookups, clocks, or evaluation providers underneath the skeleton.
class TournamentCardShimmer extends StatelessWidget {
  const TournamentCardShimmer({
    super.key,
    this.board = false,
    this.grid = false,
    this.size,
  });

  final bool board;
  final bool grid;
  final Size? size;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width =
            grid && ResponsiveHelper.isPhone
                ? MediaQuery.sizeOf(context).width / 2 - 24.sp
                : constraints.maxWidth;
        final height =
            size?.height ??
            (board
                ? (width - (grid ? 10.w : 48.sp + 20.w)) +
                    48.h +
                    (grid ? 0 : 8.sp)
                : 84.h);
        return SizedBox(
          width: width,
          height: height,
          child: SkeletonWidget(
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: board && !grid ? 24.sp : 12.sp,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Bone(height: 16.h),
                  SizedBox(height: 8.h),
                  const Expanded(child: Bone()),
                  SizedBox(height: 8.h),
                  Bone(height: 12.h),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
