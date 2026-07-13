import 'dart:async';

import 'package:chessever2/screens/tour_detail/games_tour/providers/games_app_bar_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_screen_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_screen_mode_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_list_presentation_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/round_expansion_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/games_tour_content_provider.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_list_view_mode_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_app_bar_view_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';

const String kDefaultGamesTourScrollScopeId = 'global_scroll_scope';
String? _activeGamesTourScrollScopeId;

/// Scope identifier to allow multiple tournament detail screens to coexist
/// without sharing the same ScrollablePositionedList controller.
final gamesTourScrollScopeProvider = Provider<String>(
  (_) => kDefaultGamesTourScrollScopeId,
);

String resolveGamesTourScrollScope(Ref ref) {
  final scopedId = ref.read(gamesTourScrollScopeProvider);
  if (scopedId != kDefaultGamesTourScrollScopeId) {
    return scopedId;
  }
  return _activeGamesTourScrollScopeId ?? scopedId;
}

void markGamesTourScrollScopeActive(String scopeId) {
  if (scopeId == kDefaultGamesTourScrollScopeId) return;
  _activeGamesTourScrollScopeId = scopeId;
}

void clearGamesTourScrollScopeActive(String scopeId) {
  if (_activeGamesTourScrollScopeId == scopeId) {
    _activeGamesTourScrollScopeId = null;
  }
}

/// Track whether we already performed the initial auto-scroll for a given scope.
final gamesTourAutoScrollProvider = StateProvider.autoDispose
    .family<bool, String>((ref, scopeId) => false);

/// True while the tournament games list is actively moving.
///
/// Game-card engine fallbacks use this to stay cache-only during scroll and
/// resume low-priority Stockfish work after the list has settled.
final gamesTourIsScrollingProvider = StateProvider.autoDispose
    .family<bool, String>((ref, scopeId) => false);

final gamesTourScrollProvider = StateNotifierProvider.autoDispose
    .family<_GamesTourScrollProvider, ItemScrollController, String>(
      (ref, scopeId) => _GamesTourScrollProvider(ref, scopeId),
    );

class GamesTourScrollActivityDetector extends ConsumerStatefulWidget {
  const GamesTourScrollActivityDetector({
    required this.scopeId,
    required this.child,
    super.key,
  });

  final String scopeId;
  final Widget child;

  @override
  ConsumerState<GamesTourScrollActivityDetector> createState() =>
      _GamesTourScrollActivityDetectorState();
}

class _GamesTourScrollActivityDetectorState
    extends ConsumerState<GamesTourScrollActivityDetector> {
  static const Duration _idleDelay = Duration(milliseconds: 180);

  Timer? _idleTimer;
  bool _liveCardsPausedForScroll = false;
  late final StateController<Set<String>> _liveGameCardsPauseReasons;

  String _pauseReasonFor(String scopeId) => 'games_tour_scroll_$scopeId';

  @override
  void initState() {
    super.initState();
    _liveGameCardsPauseReasons = ref.read(
      liveGameCardsPauseReasonsProvider.notifier,
    );
    markGamesTourScrollScopeActive(widget.scopeId);
  }

  @override
  void didUpdateWidget(covariant GamesTourScrollActivityDetector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scopeId == widget.scopeId) return;
    clearGamesTourScrollScopeActive(oldWidget.scopeId);
    markGamesTourScrollScopeActive(widget.scopeId);
    if (_liveCardsPausedForScroll) {
      setLiveGameCardsPaused(
        ref,
        reason: _pauseReasonFor(oldWidget.scopeId),
        paused: false,
      );
      setLiveGameCardsPaused(
        ref,
        reason: _pauseReasonFor(widget.scopeId),
        paused: true,
      );
    }
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    if (notification.metrics.axis != Axis.vertical) return false;

    if (notification is ScrollEndNotification) {
      _scheduleIdle();
      return false;
    }

    if (notification is UserScrollNotification &&
        notification.direction == ScrollDirection.idle) {
      _scheduleIdle();
      return false;
    }

    if (notification is ScrollStartNotification ||
        notification is ScrollUpdateNotification ||
        notification is OverscrollNotification ||
        notification is UserScrollNotification) {
      _markScrolling();
    }

    return false;
  }

  void _markScrolling() {
    final isScrolling = ref.read(gamesTourIsScrollingProvider(widget.scopeId));
    if (!isScrolling) {
      ref.read(gamesTourIsScrollingProvider(widget.scopeId).notifier).state =
          true;
    }
    _setLiveCardsPausedForScroll(true);

    _idleTimer?.cancel();
    _idleTimer = Timer(_idleDelay, _markIdle);
  }

  void _scheduleIdle() {
    _idleTimer?.cancel();
    _idleTimer = Timer(_idleDelay, _markIdle);
  }

  void _markIdle() {
    if (!mounted) return;
    final isScrolling = ref.read(gamesTourIsScrollingProvider(widget.scopeId));
    if (isScrolling) {
      ref.read(gamesTourIsScrollingProvider(widget.scopeId).notifier).state =
          false;
    }
    _setLiveCardsPausedForScroll(false);
  }

  void _setLiveCardsPausedForScroll(bool paused) {
    if (_liveCardsPausedForScroll == paused) return;
    _liveCardsPausedForScroll = paused;
    setLiveGameCardsPausedWithNotifier(
      _liveGameCardsPauseReasons,
      reason: _pauseReasonFor(widget.scopeId),
      paused: paused,
    );
  }

  @override
  void dispose() {
    _idleTimer?.cancel();
    _setLiveCardsPausedForScroll(false);
    clearGamesTourScrollScopeActive(widget.scopeId);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollNotification>(
      onNotification: _handleScrollNotification,
      child: widget.child,
    );
  }
}

class _GamesTourScrollProvider extends StateNotifier<ItemScrollController> {
  _GamesTourScrollProvider(this._ref, this._scopeId)
    : super(_acquireScrollController(_scopeId)) {
    _ref.onDispose(() => _releaseScrollController(_scopeId, state));
    _itemPositionsListener = ItemPositionsListener.create();
    _itemPositionsListener.itemPositions.addListener(_onItemPositionsChanged);

    // Keep the same top item when chessBoard visibility toggles
    _ref.listen<GamesListViewMode>(
      gamesListViewModeProvider,
      (previous, next) => _anchorTopAfterVisibilityChange(),
    );
  }

  final Ref _ref;
  // Scope identifier to keep controllers unique per tournament detail instance
  // ignore: unused_field
  final String _scopeId;
  late ItemPositionsListener _itemPositionsListener;
  Timer? _debounceTimer;
  String? _lastVisibleRoundId;
  bool _isProgrammaticScroll = false;

  static final Map<String, ItemScrollController> _controllersByScope =
      <String, ItemScrollController>{};
  static final Map<String, int> _controllerRefCounts = <String, int>{};

  static ItemScrollController _acquireScrollController(String scopeId) {
    _controllerRefCounts[scopeId] = (_controllerRefCounts[scopeId] ?? 0) + 1;
    return _controllersByScope.putIfAbsent(scopeId, ItemScrollController.new);
  }

  static void _releaseScrollController(
    String scopeId,
    ItemScrollController controller,
  ) {
    final nextCount = (_controllerRefCounts[scopeId] ?? 1) - 1;
    if (nextCount > 0) {
      _controllerRefCounts[scopeId] = nextCount;
      return;
    }

    _controllerRefCounts.remove(scopeId);
    if (identical(_controllersByScope[scopeId], controller)) {
      _controllersByScope.remove(scopeId);
    }
  }

  ItemPositionsListener get itemPositionsListener =>
      _itemPositionsListener; // Expose for Riverpod

  /// Expose the scroll controller for external use
  ItemScrollController get scrollController => state;

  String? _lastVisibleGameId;

  bool get _isGroupEvent =>
      _ref.read(gamesTourScreenModeProvider).valueOrNull ==
      GamesTourScreenMode.groupEvent;

  /// Regular events use the exact round sequence painted by GamesListView.
  /// Team events retain their separate card-list presentation.
  List<GamesAppBarModel> _getVisibleRounds() {
    if (!_isGroupEvent) {
      return _ref.read(gamesTourListPresentationProvider).displayRounds;
    }

    final vm = _ref.read(gamesAppBarProvider).valueOrNull;
    if (vm == null) return <GamesAppBarModel>[];
    final selectedId = vm.selectedId;
    final userSelected = vm.userSelectedId;
    final models = vm.gamesAppBarModels;
    return models
        .where(
          (round) =>
              _getGamesInRound(round.id) > 0 &&
              ((userSelected && round.id == selectedId) ||
                  round.roundStatus != RoundStatus.upcoming),
        )
        .toList(growable: false);
  }

  List<String> get visibleRoundIds =>
      _getVisibleRounds().map((round) => round.id).toList(growable: false);

  int roundHeaderIndex(String roundId) {
    if (!_isGroupEvent) {
      return _ref
              .read(gamesTourListPresentationProvider)
              .layout
              .roundHeaderIndex(roundId) ??
          -1;
    }

    var index = 0;
    final expansionState = _ref.read(roundExpansionProvider);
    for (final round in _getVisibleRounds()) {
      if (round.id == roundId) return index;
      index += groupEventRoundListItemCount(
        isExpanded: expansionState[round.id] ?? true,
        matchupCardCount: _getTeamMatchupCardsInRound(round.id),
      );
    }
    return -1;
  }

  /// Set flag to prevent scroll listener from updating dropdown during programmatic scroll
  void startProgrammaticScroll({String? targetRoundId}) {
    _isProgrammaticScroll = true;
    if (targetRoundId != null) {
      _lastVisibleRoundId = targetRoundId;
    }
  }

  /// Reset flag after programmatic scroll completes to re-enable scroll sync
  void endProgrammaticScroll() {
    // Add a small delay to ensure the scroll has fully completed
    Future.delayed(const Duration(milliseconds: 200), () {
      _isProgrammaticScroll = false;
    });
  }

  void _onItemPositionsChanged() {
    // Skip updates during programmatic scroll
    if (_isProgrammaticScroll) return;

    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 50), () {
      final positions = _itemPositionsListener.itemPositions.value;
      if (positions.isEmpty) return;

      // Find the topmost visible item (considering items that are at least partially visible).
      final topItem =
          positions.where((pos) => pos.itemLeadingEdge < 0.3).firstOrNull;
      if (topItem == null) return;

      final gameId = _getGameIdFromItemIndex(topItem.index);
      if (gameId != null && gameId != _lastVisibleGameId) {
        _lastVisibleGameId = gameId;
      }

      final visibleRoundId = _getRoundIdFromItemIndex(topItem.index);
      if (visibleRoundId != null && visibleRoundId != _lastVisibleRoundId) {
        _lastVisibleRoundId = visibleRoundId;
        _notifyRoundChange(visibleRoundId);
      }
    });
  }

  String? _getGameIdFromItemIndex(int itemIndex) {
    if (_isGroupEvent) return null;
    return _ref
        .read(gamesTourListPresentationProvider)
        .layout
        .firstGameIdAt(itemIndex);
  }

  // Ensure the item anchored at the top remains the same after layout changes
  void _anchorTopAfterVisibilityChange() {
    if (_lastVisibleGameId == null) return;

    final targetIndex = _getItemIndexForGameId(_lastVisibleGameId!);
    if (targetIndex == null) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!state.isAttached) return;
      state.jumpTo(index: targetIndex, alignment: 0.1);
    });
  }

  int? _getItemIndexForGameId(String gameId) {
    if (_isGroupEvent) return null;
    return _ref
        .read(gamesTourListPresentationProvider)
        .layout
        .itemIndexForGameId(gameId);
  }

  void _notifyRoundChange(String roundId) {
    final gamesAppBarAsync = _ref.read(gamesAppBarProvider);
    final gamesAppBarData = gamesAppBarAsync.valueOrNull;
    if (gamesAppBarData == null) return;

    final currentSelected = gamesAppBarData.selectedId;
    final wasUserSelected = gamesAppBarData.userSelectedId;

    // Only update if round actually changed and it wasn't a user selection
    if (currentSelected != roundId && !wasUserSelected) {
      final targetRound =
          gamesAppBarData.gamesAppBarModels
              .where((round) => round.id == roundId)
              .firstOrNull;
      if (targetRound != null) {
        _ref.read(gamesAppBarProvider.notifier).selectSilently(targetRound);
      }
    }
  }

  String? _getRoundIdFromItemIndex(int itemIndex) {
    if (!_isGroupEvent) {
      return _ref
          .read(gamesTourListPresentationProvider)
          .layout
          .roundIdAt(itemIndex);
    }

    final rounds = _getVisibleRounds();
    final expansionState = _ref.read(roundExpansionProvider);

    int currentIndex = 0;
    for (final round in rounds) {
      if (itemIndex == currentIndex) return round.id; // header
      final itemCount = groupEventRoundListItemCount(
        isExpanded: expansionState[round.id] ?? true,
        matchupCardCount: _getTeamMatchupCardsInRound(round.id),
      );
      currentIndex += itemCount;
      if (itemIndex < currentIndex) return round.id;
    }
    return null;
  }

  int _getTeamMatchupCardsInRound(String roundId) {
    // Get games for this round
    final gamesData = _ref.read(gamesTourScreenProvider).valueOrNull;
    if (gamesData == null) return 0;

    final roundGames = _getGamesForRound(roundId);
    if (roundGames.isEmpty) return 0;

    // Use the same grouping logic as the UI
    final grouped = _ref
        .read(gamesTourContentProvider)
        .getGroupHeader(selectedRoundId: roundId, gamesScreenModel: gamesData);

    // Return the number of team matchup cards
    return grouped.keys.length;
  }

  int _getGamesInRound(String roundId) {
    return _getGamesForRound(roundId).length;
  }

  List<GamesTourModel> _getGamesForRound(String roundId) {
    final gamesData = _ref.read(gamesTourScreenProvider).valueOrNull;
    if (gamesData == null) return const [];
    return gamesData.gamesTourModels
        .where((game) => game.roundId == roundId)
        .toList(growable: false);
  }

  @override
  void dispose() {
    _itemPositionsListener.itemPositions.removeListener(
      _onItemPositionsChanged,
    );
    _debounceTimer?.cancel();
    super.dispose();
  }
}

int groupEventRoundListItemCount({
  required bool isExpanded,
  required int matchupCardCount,
}) => 1 + (isExpanded ? matchupCardCount : 0);
