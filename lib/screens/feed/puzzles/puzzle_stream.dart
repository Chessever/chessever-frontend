import 'dart:async';

import 'package:chessever2/screens/feed/puzzles/feed_puzzle.dart';
import 'package:chessever2/screens/feed/puzzles/puzzle_tab_provider.dart';
import 'package:chessever2/screens/feed/widgets/feed_pull_refresh.dart';
import 'package:chessever2/screens/feed/widgets/feed_sfx_provider.dart';
import 'package:chessever2/screens/feed/widgets/feed_states.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/user_error_message.dart';
import 'package:chessever2/widgets/app_snack.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:motor/motor.dart';

/// The puzzle the viewer was last on in the Puzzle tab, by id, so a return
/// to the tab (Home rebuilds it) puts them back where they were.
final puzzleCurrentIdProvider = StateProvider<String?>((ref) => null);

/// The Puzzle tab's body: puzzles as posts, one per page, swiped exactly
/// like the Feed tab's games and pulled down on the first one to refresh.
///
/// [FeedPuzzlePage] already sits on the Feed's page geometry (header line,
/// player rows, board, status line, action row), so a puzzle here lands
/// where a game lands in the Feed.
class PuzzleStream extends ConsumerStatefulWidget {
  const PuzzleStream({
    required this.isVisible,
    required this.nextRequests,
    super.key,
  });

  /// The tab is selected, the app is in front and nothing covers it.
  final bool isVisible;

  /// Ticks when the bottom-nav Feed item is tapped again while this tab
  /// shows: the tap moves to the next puzzle, as it moves to the next game.
  final ValueListenable<int> nextRequests;

  @override
  ConsumerState<PuzzleStream> createState() => _PuzzleStreamState();
}

class _PuzzleStreamState extends ConsumerState<PuzzleStream> {
  late final PageController _pages;
  int _index = 0;

  static final Curve _pageCurve = const CupertinoMotion.smooth().toCurve;

  @override
  void initState() {
    super.initState();
    _index = _restoredIndex();
    _pages = PageController(initialPage: _index);
    widget.nextRequests.addListener(_goNext);
  }

  @override
  void didUpdateWidget(covariant PuzzleStream oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.nextRequests != widget.nextRequests) {
      oldWidget.nextRequests.removeListener(_goNext);
      widget.nextRequests.addListener(_goNext);
    }
  }

  @override
  void dispose() {
    widget.nextRequests.removeListener(_goNext);
    _pages.dispose();
    super.dispose();
  }

  int _restoredIndex() {
    final id = ref.read(puzzleCurrentIdProvider);
    final list = ref.read(puzzleTabProvider).valueOrNull;
    if (id == null || list == null) return 0;
    final index = list.indexWhere((p) => p.id == id);
    return index < 0 ? 0 : index;
  }

  void _onPageChanged(int index, List<FeedPuzzle> puzzles) {
    if (index == _index) return;
    setState(() => _index = index);
    if (index < puzzles.length) {
      ref.read(puzzleCurrentIdProvider.notifier).state = puzzles[index].id;
    }
    feedSfxSafely(ref.read(feedSfxProvider).playSwipe);
    if (index >= puzzles.length - 3) {
      unawaited(ref.read(puzzleTabProvider.notifier).loadMore());
    }
  }

  void _goNext() {
    if (!mounted || !_pages.hasClients || !widget.isVisible) return;
    final puzzles = ref.read(puzzleTabProvider).valueOrNull ?? const [];
    if (_index >= puzzles.length - 1) {
      unawaited(ref.read(puzzleTabProvider.notifier).loadMore());
      return;
    }
    if (MediaQuery.disableAnimationsOf(context)) {
      _pages.jumpToPage(_index + 1);
      return;
    }
    unawaited(
      _pages.animateToPage(
        _index + 1,
        duration: const Duration(milliseconds: 420),
        curve: _pageCurve,
      ),
    );
  }

  Future<void> _refresh() async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      await ref
          .read(puzzleTabProvider.notifier)
          .refresh()
          .timeout(const Duration(seconds: 20));
      if (!mounted) return;
      unawaited(HapticFeedbackService.light());
      setState(() => _index = 0);
      if (_pages.hasClients) _pages.jumpToPage(0);
      final first = ref.read(puzzleTabProvider).valueOrNull?.firstOrNull;
      ref.read(puzzleCurrentIdProvider.notifier).state = first?.id;
    } catch (_) {
      if (messenger != null) {
        showAppSnackOn(
          messenger,
          "Couldn't load new puzzles",
          tone: AppSnackTone.danger,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(puzzleTabProvider);
    final puzzles = state.valueOrNull ?? const <FeedPuzzle>[];

    if (puzzles.isEmpty) {
      if (state.isLoading) return const FeedSkeleton(puzzles: true);
      return FeedMessage(
        title: state.hasError ? "Puzzles didn't load" : 'No puzzles right now',
        body: state.hasError
            ? userFacingError(
                state.error,
                fallback: 'Something went wrong. Please try again.',
              )
            : 'Check your connection and try again.',
        actionLabel: 'Try again',
        onAction: () => ref.invalidate(puzzleTabProvider),
      );
    }

    return FeedPullRefresh(
      key: const ValueKey('puzzle_refresh'),
      onRefresh: _refresh,
      child: PageView.builder(
        key: const ValueKey('puzzle_pages'),
        controller: _pages,
        scrollDirection: Axis.vertical,
        physics: feedPagePhysics,
        allowImplicitScrolling: true,
        onPageChanged: (i) => _onPageChanged(i, puzzles),
        itemCount: puzzles.length,
        findChildIndexCallback: (key) {
          if (key is! ValueKey<String>) return null;
          final index = puzzles.indexWhere(
            (p) => 'puzzle:${p.id}' == key.value,
          );
          return index < 0 ? null : index;
        },
        itemBuilder: (context, i) {
          final puzzle = puzzles[i];
          return FeedPuzzlePage(
            key: ValueKey('puzzle:${puzzle.id}'),
            puzzle: puzzle,
            isCurrent: i == _index,
            isVisible: widget.isVisible,
            onRequestNext: _goNext,
          );
        },
      ),
    );
  }
}
