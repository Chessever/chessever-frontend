import 'package:chessever2/providers/favorite_events_provider.dart';
import 'package:chessever2/repository/gamebase/search/gamebase_search_models.dart';
import 'package:chessever2/revenue_cat_service/subscribe_state.dart';
import 'package:chessever2/screens/chessboard/provider/chess_board_screen_provider_new.dart';
import 'package:chessever2/screens/chessboard/provider/game_pgn_stream_provider.dart';
import 'package:chessever2/screens/group_event/model/tour_event_card_model.dart';
import 'package:chessever2/screens/group_event/smart_event/smart_aggregate_event_provider.dart';
import 'package:chessever2/screens/group_event/smart_event/smart_event_standings_provider.dart';
import 'package:chessever2/screens/group_event/widget/filter_popup/filter_popup_state.dart';
import 'package:chessever2/screens/player_profile/player_profile_screen.dart';
import 'package:chessever2/screens/standings/player_standing_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/game_card_wrapper/game_card_wrapper_widget.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/time_utils.dart';
import 'package:chessever2/widgets/auth/auth_upgrade_sheet.dart';
import 'package:chessever2/widgets/alert_dialog/alert_modal.dart';
import 'package:chessever2/widgets/event_card/event_card.dart';
import 'package:chessever2/widgets/figma_player_card.dart';
import 'package:chessever2/widgets/fluid_shimmer_painter.dart';
import 'package:chessever2/widgets/game_filter/game_filter_dialog.dart';
import 'package:chessever2/widgets/game_filter/game_filter_model.dart';
import 'package:chessever2/widgets/game_filter/game_search_filter_bar.dart';
import 'package:chessever2/widgets/generic_error_widget.dart';
import 'package:chessever2/widgets/paywall/premium_paywall_sheet.dart';
import 'package:chessever2/widgets/segmented_switcher.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:intl/intl.dart';

/// Full event view for generated level games. Renders the familiar
/// About / Games / Standings tabbed shell, with every tab computed from the
/// current broadcast aggregate ([smartAggregateEventProvider]).
class SmartEventScreen extends ConsumerStatefulWidget {
  const SmartEventScreen({required this.request, super.key});

  final SmartEventRequest request;

  @override
  ConsumerState<SmartEventScreen> createState() => _SmartEventScreenState();
}

class _SmartEventScreenState extends ConsumerState<SmartEventScreen> {
  static const _tabs = ['About', 'Games', 'Standings'];

  // Default to Games because this surface is opened from a generated games card.
  int _index = 1;
  late final PageController _page = PageController(initialPage: _index);

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  void _select(int i) {
    if (_index == i) return;
    setState(() => _index = i);
    _page.animateToPage(
      i,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final horizontalPadding =
        ResponsiveHelper.isTablet ? 24.sp.toDouble() : 16.sp.toDouble();

    return _SmartEventRequestScope(
      request: widget.request,
      child: Scaffold(
        backgroundColor: context.colors.background,
        body: SafeArea(
          child: Column(
            children: [
              _AppBar(request: widget.request),
              SizedBox(height: 8.h),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
                child: SegmentedSwitcher(
                  options: _tabs,
                  initialSelection: _index,
                  currentSelection: _index,
                  onSelectionChanged: _select,
                ),
              ),
              SizedBox(height: 8.h),
              Expanded(
                child: PageView(
                  controller: _page,
                  onPageChanged: (i) => setState(() => _index = i),
                  children: const [_AboutTab(), _GamesTab(), _StandingsTab()],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AppBar extends ConsumerWidget {
  const _AppBar({required this.request});

  final SmartEventRequest request;

  Future<bool> _confirmFavoriteChange(
    BuildContext context, {
    required bool isSaved,
  }) async {
    final confirmed = await showSmoothConfirmDialog(
      context: context,
      title:
          isSaved
              ? 'Remove ${request.displayName}?'
              : 'Save ${request.displayName}?',
      message:
          isSaved
              ? 'This will remove ${request.displayName} from your For You.'
              : 'This will add ${request.displayName} to your For You tab.',
      confirmText: isSaved ? 'Remove' : 'Save',
      isDangerous: isSaved,
    );
    return confirmed == true;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favoritesAsync = ref.watch(favoriteEventsProvider);
    final isSaved = favoritesAsync.maybeWhen(
      data:
          (favorites) => favorites.any(
            (favorite) => favorite.eventId == request.favoriteEventId,
          ),
      orElse: () => false,
      skipLoadingOnRefresh: true,
      skipLoadingOnReload: true,
    );

    return Padding(
      padding: EdgeInsets.fromLTRB(8.w, 8.h, 16.w, 0),
      child: Row(
        children: [
          IconButton(
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            iconSize: 24.ic,
            icon: Icon(
              Icons.arrow_back_ios_new_outlined,
              size: 24.ic,
              color: context.colors.textPrimary,
            ),
            onPressed: () => Navigator.of(context).pop(),
          ),
          Expanded(child: Center(child: _TitleSelector(request: request))),
          IconButton(
            tooltip:
                isSaved
                    ? 'Remove ${request.displayName}'
                    : 'Save ${request.displayName}',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            iconSize: 26.ic,
            icon: Icon(
              isSaved
                  ? Icons.remove_circle_outline_rounded
                  : Icons.add_circle_outline_rounded,
              color: context.colors.textPrimary,
            ),
            onPressed: () async {
              final allowed = await requireFullAuthGuard(context);
              if (!allowed || !context.mounted) return;
              final confirmed = await _confirmFavoriteChange(
                context,
                isSaved: isSaved,
              );
              if (!confirmed || !context.mounted) return;

              final notifier = ref.read(favoriteEventsProvider.notifier);
              if (isSaved) {
                await notifier.removeFavorite(request.favoriteEventId);
                if (context.mounted) Navigator.of(context).pop();
                return;
              }

              await notifier.addFavorite(
                eventId: request.favoriteEventId,
                eventName: request.displayName,
                maxAvgElo: request.minElo > 0 ? request.minElo : null,
                extraMetadata: request.toFavoriteMetadata(),
              );
            },
          ),
        ],
      ),
    );
  }
}

/// Stadium-chip dropdown that swaps the active level filter
/// (GM / IM / FM / CM / All) without leaving the screen. Visual language
/// matches the regular event view's [CategoryDropdown] — shimmer-bordered
/// chip when closed, kPrimary tint when open, scale + fade overlay panel.
class _TitleSelector extends StatefulWidget {
  const _TitleSelector({required this.request});

  final SmartEventRequest request;

  @override
  State<_TitleSelector> createState() => _TitleSelectorState();
}

class _TitleSelectorState extends State<_TitleSelector>
    with TickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  );
  late final Animation<double> _animation = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeInCubic,
  );
  late final AnimationController _shimmerController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3000),
  )..repeat();

  OverlayEntry? _overlay;
  bool _isOpen = false;

  @override
  void dispose() {
    _overlay?.remove();
    _overlay = null;
    _shimmerController.dispose();
    _controller.dispose();
    super.dispose();
  }

  List<SmartEventRequest> _options() {
    const tiers = <(String, int)>[
      ('GM', 2500),
      ('IM', 2400),
      ('FM', 2300),
      ('CM', 2200),
    ];
    final options = tiers
        .map(
          (tier) => SmartEventRequest(
            source: widget.request.source,
            tierLabel: tier.$1,
            titleSuffix: 'Games',
            minElo: tier.$2,
            maxElo: kFilterMaxElo.round(),
            caption: 'From your ${tier.$2}+ filter',
            countSingular: 'live event',
            countPlural: 'live events',
            events: widget.request.events,
          ),
        )
        .toList(growable: true);
    options.add(
      SmartEventRequest(
        source: widget.request.source,
        tierLabel: 'All',
        titleSuffix: 'Games',
        minElo: kFilterMinElo.round(),
        maxElo: kFilterMaxElo.round(),
        caption: 'From your filters',
        countSingular: 'live event',
        countPlural: 'live events',
        events: widget.request.events,
      ),
    );
    return options;
  }

  void _open() {
    if (_isOpen) return;
    HapticFeedbackService.selection();
    setState(() => _isOpen = true);
    _shimmerController.stop();
    _controller.forward();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final overlayState = Overlay.of(context);
      final renderBox = context.findRenderObject() as RenderBox?;
      if (renderBox == null) return;
      final triggerSize = renderBox.size;
      final triggerOffset = renderBox.localToGlobal(Offset.zero);
      final screenSize = MediaQuery.of(context).size;

      _overlay = OverlayEntry(
        builder: (_) => _TierOverlay(
          triggerSize: triggerSize,
          triggerOffset: triggerOffset,
          screenWidth: screenSize.width,
          animation: _animation,
          options: _options(),
          currentTierLabel: widget.request.tierLabel,
          onDismiss: _close,
          onSelect: _onSelect,
        ),
      );
      overlayState.insert(_overlay!);
    });
  }

  void _close() {
    if (!_isOpen) return;
    _controller.reverse().then((_) {
      if (!mounted) return;
      _overlay?.remove();
      _overlay = null;
      if (mounted) {
        setState(() => _isOpen = false);
        _shimmerController.repeat();
      }
    });
  }

  void _onSelect(SmartEventRequest next) {
    HapticFeedbackService.selection();
    if (next.scopeId == widget.request.scopeId &&
        next.displayName == widget.request.displayName) {
      _close();
      return;
    }
    _controller.reverse().then((_) {
      if (!mounted) return;
      _overlay?.remove();
      _overlay = null;
      if (mounted) setState(() => _isOpen = false);
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => SmartEventScreen(request: next),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _isOpen ? _close() : _open(),
      child: AnimatedBuilder(
        animation: _shimmerController,
        builder: (context, child) {
          return CustomPaint(
            painter: _isOpen
                ? null
                : FluidShimmerPainter(
                    progress: _shimmerController.value,
                    shimmerColor: kPrimaryColor.withValues(alpha: 0.4),
                    borderRadius: 14.br,
                  ),
            child: child,
          );
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          padding: EdgeInsets.symmetric(horizontal: 14.sp, vertical: 8.sp),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14.br),
            color: _isOpen
                ? kPrimaryColor.withValues(alpha: 0.15)
                : context.colors.textPrimary.withValues(alpha: 0.06),
            border: Border.all(
              color: _isOpen
                  ? kPrimaryColor.withValues(alpha: 0.4)
                  : context.colors.textPrimary.withValues(alpha: 0.12),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  widget.request.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.textSmMedium.copyWith(
                    color: _isOpen
                        ? kPrimaryColor
                        : context.colors.textPrimary,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
              SizedBox(width: 6.sp),
              AnimatedRotation(
                turns: _isOpen ? 0.5 : 0,
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOutCubic,
                child: Icon(
                  Icons.keyboard_arrow_down_rounded,
                  size: 18.ic,
                  color: _isOpen
                      ? kPrimaryColor
                      : context.colors.textPrimary.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Floating panel anchored under [_TitleSelector]'s chip. Scale + fade in
/// from the top, surface bg, kPrimary check mark on the active tier.
class _TierOverlay extends StatelessWidget {
  const _TierOverlay({
    required this.triggerSize,
    required this.triggerOffset,
    required this.screenWidth,
    required this.animation,
    required this.options,
    required this.currentTierLabel,
    required this.onDismiss,
    required this.onSelect,
  });

  final Size triggerSize;
  final Offset triggerOffset;
  final double screenWidth;
  final Animation<double> animation;
  final List<SmartEventRequest> options;
  final String currentTierLabel;
  final VoidCallback onDismiss;
  final ValueChanged<SmartEventRequest> onSelect;

  @override
  Widget build(BuildContext context) {
    final panelWidth = (screenWidth - 32.w).clamp(220.0, 320.w);
    final leftOffset = (screenWidth - panelWidth) / 2;
    final topOffset = triggerOffset.dy + triggerSize.height + 8.sp;

    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: onDismiss,
          ),
        ),
        Positioned(
          left: leftOffset,
          top: topOffset,
          child: Material(
            type: MaterialType.transparency,
            child: AnimatedBuilder(
              animation: animation,
              builder: (context, child) {
                final progress = animation.value.clamp(0.0, 1.0);
                return Transform.scale(
                  scale: 0.94 + (progress * 0.06),
                  alignment: Alignment.topCenter,
                  child: Opacity(opacity: progress, child: child),
                );
              },
              child: GestureDetector(
                onTap: () {},
                behavior: HitTestBehavior.opaque,
                child: Container(
                  width: panelWidth,
                  decoration: BoxDecoration(
                    color: context.colors.surface,
                    borderRadius: BorderRadius.circular(16.br),
                    border: Border.all(
                      color: context.colors.textPrimary.withValues(alpha: 0.08),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.18),
                        blurRadius: 24,
                        spreadRadius: -6,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16.br),
                    child: ListView(
                      shrinkWrap: true,
                      padding: EdgeInsets.symmetric(vertical: 6.sp),
                      children: [
                        for (var i = 0; i < options.length; i++)
                          _TierOptionRow(
                            index: i,
                            animation: animation,
                            option: options[i],
                            isSelected:
                                options[i].tierLabel == currentTierLabel,
                            onTap: () => onSelect(options[i]),
                          ),
                      ],
                    ),
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

class _TierOptionRow extends StatelessWidget {
  const _TierOptionRow({
    required this.index,
    required this.animation,
    required this.option,
    required this.isSelected,
    required this.onTap,
  });

  final int index;
  final Animation<double> animation;
  final SmartEventRequest option;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final stagger = (index * 0.06).clamp(0.0, 0.4);
    final itemAnimation = CurvedAnimation(
      parent: animation,
      curve: Interval(
        stagger,
        (stagger + 0.5).clamp(0.0, 1.0),
        curve: Curves.easeOutCubic,
      ),
    );

    return AnimatedBuilder(
      animation: itemAnimation,
      builder: (context, child) {
        final v = itemAnimation.value.clamp(0.0, 1.0);
        return Transform.translate(
          offset: Offset(0, 10 * (1 - v)),
          child: Opacity(opacity: v, child: child),
        );
      },
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 16.sp, vertical: 12.sp),
          color: isSelected
              ? kPrimaryColor.withValues(alpha: 0.10)
              : Colors.transparent,
          child: Row(
            children: [
              Expanded(
                child: Text(
                  option.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.textSmMedium.copyWith(
                    color: isSelected
                        ? kPrimaryColor
                        : context.colors.textPrimary,
                    fontWeight:
                        isSelected ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
              ),
              if (isSelected)
                Icon(
                  Icons.check_rounded,
                  size: 18.ic,
                  color: kPrimaryColor,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shared async scaffold so each tab renders consistent loading / error /
/// empty states off the one cached provider.
class _TabAsync extends ConsumerWidget {
  const _TabAsync({required this.builder});

  final Widget Function(SmartAggregateEvent event) builder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final request = _SmartEventRequestScope.of(context);
    final async = ref.watch(smartAggregateEventProvider(request));
    return async.when(
      data: (event) {
        if (event.games.isEmpty) {
          return _EmptyState();
        }
        return builder(event);
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error:
          (e, _) => GenericErrorWidget(
            onRetry: () => ref.invalidate(smartAggregateEventProvider(request)),
          ),
    );
  }
}

class _SmartEventRequestScope extends InheritedWidget {
  const _SmartEventRequestScope({required this.request, required super.child});

  final SmartEventRequest request;

  static SmartEventRequest of(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<_SmartEventRequestScope>();
    assert(scope != null, 'SmartEventRequestScope was not found');
    return scope!.request;
  }

  @override
  bool updateShouldNotify(_SmartEventRequestScope oldWidget) {
    return request != oldWidget.request;
  }
}

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(32.sp),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.sports_esports_outlined,
              size: 40.sp,
              color: context.colors.textPrimaryMuted,
            ),
            SizedBox(height: 12.h),
            Text(
              'No live games right now',
              textAlign: TextAlign.center,
              style: AppTypography.textSmMedium.copyWith(
                color: context.colors.textPrimaryMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GamesTab extends ConsumerStatefulWidget {
  const _GamesTab();

  @override
  ConsumerState<_GamesTab> createState() => _GamesTabState();
}

class _GamesTabState extends ConsumerState<_GamesTab> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  GameFilter _filter = GameFilter.defaultFilter();
  String _query = '';

  /// Track collapsed state for date sections — mirrors the Countrymen /
  /// Favorites games tabs.
  final Set<String> _collapsedDates = {};

  void _toggleDateSection(String dateKey) {
    HapticFeedback.lightImpact();
    setState(() {
      if (_collapsedDates.contains(dateKey)) {
        _collapsedDates.remove(dateKey);
      } else {
        _collapsedDates.add(dateKey);
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final request = _SmartEventRequestScope.of(context);
    final smartQuery = SmartEventGamesQuery(
      request: request,
      filter: _filter.hasActiveFilters ? _filter : null,
      searchQuery: _query,
    );
    final async = ref.watch(smartFilteredAggregateEventProvider(smartQuery));

    return async.when(
      data: (event) {
        final games = _applySmartGameControls(
          event.games,
          event.gameEventNames,
        );
        final gamesData = GamesScreenModel(
          gamesTourModels: games,
          pinnedGamedIs: event.pinnedGameIds,
        );
        final liveGameIds = games
            .where((game) => game.effectiveGameStatus.isOngoing)
            .map((game) => game.gameId)
            .toList(growable: false);
        final liveBatchKey =
            liveGameIds.isEmpty
                ? null
                : LiveGamesBatchKey(
                  scopeId: 'smart_event:${request.scopeId}',
                  gameIds: liveGameIds,
                );

        final rows = _buildDayRows(games);
        return RefreshIndicator(
          color: kPrimaryColor,
          backgroundColor: context.colors.surface,
          onRefresh: () async {
            ref.invalidate(smartAggregateEventRepositoryProvider(smartQuery));
            ref.invalidate(smartAggregateEventProvider(request));
          },
          child: ListView.builder(
            padding: EdgeInsets.fromLTRB(16.sp, 8.sp, 16.sp, 24.sp),
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            itemCount: games.isEmpty ? 2 : rows.length + 1,
            itemBuilder: (context, i) {
              if (i == 0) {
                return Padding(
                  padding: EdgeInsets.only(bottom: 12.sp),
                  child: GameSearchFilterBar(
                    controller: _searchController,
                    focusNode: _focusNode,
                    currentFilter: _filter,
                    hintText: 'Search games',
                    onChanged: (value) => setState(() => _query = value.trim()),
                    onClear:
                        () => setState(() {
                          _query = '';
                          _searchController.clear();
                        }),
                    onFilterTap: () async {
                      final result = await showGameFilterDialog(
                        context: context,
                        currentFilter: _filter,
                        showColorFilter: false,
                        showSortSection: false,
                        showLevelFilter: false,
                        showYearFilter: false,
                      );
                      if (result != null && mounted) {
                        setState(() => _filter = result);
                      }
                    },
                  ),
                );
              }
              if (games.isEmpty) {
                return _EmptyState();
              }
              final row = rows[i - 1];
              if (row.header != null) {
                final header = row.header!;
                return Padding(
                  padding: EdgeInsets.only(bottom: 12.h),
                  child: _DateHeader(
                    dateLabel: _formatDateHeader(header.dateKey),
                    gameCount: header.gameCount,
                    isExpanded: !_collapsedDates.contains(header.dateKey),
                    onToggle: () => _toggleDateSection(header.dateKey),
                  ),
                );
              }
              final game = row.game!;
              final gameIndex = games.indexWhere(
                (g) => g.gameId == game.gameId,
              );
              return Padding(
                padding: EdgeInsets.only(
                  bottom: row.isLastInSection ? 16.h : 12.h,
                ),
                child: GameCardWrapperWidget(
                  key: ValueKey('smart_${game.gameId}'),
                  game: game,
                  gamesData: gamesData,
                  gameIndex: gameIndex < 0 ? 0 : gameIndex,
                  isChessBoardVisible: false,
                  viewSource: ChessboardView.tour,
                  onReturnFromChessboard: (_) {},
                  liveBatchKey: liveBatchKey,
                  onBeforeOpen: () => _guardGameOpen(context),
                ),
              );
            },
          ),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error:
          (e, _) => GenericErrorWidget(
            onRetry: () {
              ref.invalidate(smartAggregateEventRepositoryProvider(smartQuery));
              ref.invalidate(smartAggregateEventProvider(request));
            },
          ),
    );
  }

  List<GamesTourModel> _applySmartGameControls(
    List<GamesTourModel> source,
    Map<String, String> gameEventNames,
  ) {
    final query = _query.toLowerCase();
    final filtered = source
        .where((game) {
          if (!_matchesSmartGameFilter(game, _filter)) return false;
          if (query.isEmpty) return true;
          final eventName = gameEventNames[game.gameId]?.toLowerCase() ?? '';
          return game.whitePlayer.name.toLowerCase().contains(query) ||
              game.blackPlayer.name.toLowerCase().contains(query) ||
              eventName.contains(query) ||
              (game.eco?.toLowerCase().contains(query) ?? false) ||
              (game.openingName?.toLowerCase().contains(query) ?? false);
        })
        .toList(growable: false);

    if (_filter.sorts.isEmpty) return filtered;

    final sorted = List<GamesTourModel>.from(filtered);
    sorted.sort((a, b) {
      for (final criterion in _filter.sorts) {
        final comparison = _compareBySortCriterion(a, b, criterion);
        if (comparison != 0) return comparison;
      }
      return 0;
    });
    return sorted;
  }

  bool _matchesSmartGameFilter(GamesTourModel game, GameFilter filter) {
    if (filter.live != GameLiveFilter.all) {
      final isLive = GameFilterHelper.isLiveNow(game);
      final isCompleted = game.effectiveGameStatus.isFinished;
      if (filter.live == GameLiveFilter.live && !isLive) return false;
      if (filter.live == GameLiveFilter.completed && !isCompleted) {
        return false;
      }
    }

    if (!filter.result.matches(game.gameStatus)) return false;
    if (!_matchesTimeControl(game, filter.timeControl)) return false;
    if (filter.online != GameOnlineFilter.all) {
      if (filter.online == GameOnlineFilter.online && !game.isOnline) {
        return false;
      }
      if (filter.online == GameOnlineFilter.otb && game.isOnline) return false;
    }
    if (!filter.eco.matches(game.eco)) return false;

    final year = game.lastMoveTime?.year ?? game.bucketDate?.year;
    if (year != null && (year < filter.minYear || year > filter.maxYear)) {
      return false;
    }

    final gameAvgElo = smartGameAverageElo(game);
    if (gameAvgElo < filter.minRating || gameAvgElo > filter.maxRating) {
      return false;
    }
    return true;
  }

  bool _matchesTimeControl(GamesTourModel game, GameTimeControlFilter filter) {
    if (filter == GameTimeControlFilter.all) return true;
    final value = game.timeControl?.toLowerCase();
    if (value == null || value.isEmpty) return true;
    return switch (filter) {
      GameTimeControlFilter.classical =>
        value == 'standard' || value == 'classical',
      GameTimeControlFilter.rapid => value == 'rapid',
      GameTimeControlFilter.blitz => value == 'blitz' || value == 'bullet',
      GameTimeControlFilter.all => true,
    };
  }

  Future<bool> _guardGameOpen(BuildContext context) async {
    if (ref.read(subscriptionProvider).isSubscribed) return true;
    if (!context.mounted) return false;
    return await showPremiumPaywallSheet(context: context);
  }

  /// Group games by day and flatten into header + game rows, honoring the
  /// collapsed state. Games arrive pre-sorted (day desc, pinned, avg Elo).
  List<_GameListRow> _buildDayRows(List<GamesTourModel> games) {
    final gamesByDate = <String, List<GamesTourModel>>{};
    for (final game in games) {
      final dateKey = DateFormat('yyyy-MM-dd').format(_gameDay(game));
      gamesByDate.putIfAbsent(dateKey, () => []).add(game);
    }
    final sortedKeys = gamesByDate.keys.toList()..sort((a, b) => b.compareTo(a));

    final rows = <_GameListRow>[];
    for (final dateKey in sortedKeys) {
      final dateGames = gamesByDate[dateKey]!;
      rows.add(
        _GameListRow.header(
          _DateHeaderData(dateKey: dateKey, gameCount: dateGames.length),
        ),
      );
      if (_collapsedDates.contains(dateKey)) continue;
      for (var i = 0; i < dateGames.length; i++) {
        rows.add(
          _GameListRow.game(
            dateGames[i],
            isLastInSection: i == dateGames.length - 1,
          ),
        );
      }
    }
    return rows;
  }

  DateTime _gameDay(GamesTourModel game) {
    final raw = game.lastMoveTime ?? game.bucketDate ?? DateTime.now();
    final local = raw.toLocal();
    return DateTime(local.year, local.month, local.day);
  }

  String _formatDateHeader(String dateKey) {
    final date = DateTime.parse(dateKey);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final gameDate = DateTime(date.year, date.month, date.day);

    if (gameDate == today) {
      return 'Today';
    } else if (gameDate == yesterday) {
      return 'Yesterday';
    } else {
      return DateFormat('EEEE, MMM d').format(date);
    }
  }

  int _compareBySortCriterion(
    GamesTourModel a,
    GamesTourModel b,
    GameSortCriterion criterion,
  ) {
    int comparison;
    switch (criterion.field) {
      case GamebaseSortField.date:
        final ad = a.lastMoveTime ?? a.bucketDate ?? DateTime(0);
        final bd = b.lastMoveTime ?? b.bucketDate ?? DateTime(0);
        comparison = ad.compareTo(bd);
        break;
      case GamebaseSortField.whiteElo:
        comparison = a.whitePlayer.rating.compareTo(b.whitePlayer.rating);
        break;
      case GamebaseSortField.blackElo:
        comparison = a.blackPlayer.rating.compareTo(b.blackPlayer.rating);
        break;
      case GamebaseSortField.avgElo:
        comparison = smartGameAverageElo(a).compareTo(smartGameAverageElo(b));
        break;
    }
    return criterion.direction == GamebaseSortDirection.asc
        ? comparison
        : -comparison;
  }
}

class _DateHeaderData {
  const _DateHeaderData({required this.dateKey, required this.gameCount});

  final String dateKey;
  final int gameCount;
}

class _GameListRow {
  const _GameListRow._({this.header, this.game, this.isLastInSection = false});

  factory _GameListRow.header(_DateHeaderData value) =>
      _GameListRow._(header: value);

  factory _GameListRow.game(
    GamesTourModel value, {
    required bool isLastInSection,
  }) =>
      _GameListRow._(game: value, isLastInSection: isLastInSection);

  final _DateHeaderData? header;
  final GamesTourModel? game;
  final bool isLastInSection;
}

/// Date section header — identical to the Countrymen / Favorites games tabs.
class _DateHeader extends StatelessWidget {
  final String dateLabel;
  final int gameCount;
  final bool isExpanded;
  final VoidCallback? onToggle;

  const _DateHeader({
    required this.dateLabel,
    required this.gameCount,
    required this.isExpanded,
    this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onToggle,
      borderRadius: BorderRadius.circular(12.br),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 16.sp, vertical: 14.sp),
        decoration: BoxDecoration(
          color: context.colors.surfaceRecessed,
          borderRadius: BorderRadius.circular(12.br),
          border: Border.all(
            color: context.colors.textPrimary.withValues(alpha: 0.1),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 4.w,
              height: 20.h,
              decoration: BoxDecoration(
                color: kPrimaryColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            SizedBox(width: 12.w),
            Expanded(
              child: Text(
                '$dateLabel • $gameCount ${gameCount == 1 ? 'game' : 'games'}',
                style: TextStyle(
                  color: context.colors.textPrimary,
                  fontSize: 16.sp,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (onToggle != null) ...[
              SizedBox(width: 12.w),
              Icon(
                isExpanded
                    ? Icons.keyboard_arrow_up_rounded
                    : Icons.keyboard_arrow_down_rounded,
                color: context.colors.textPrimary.withValues(alpha: 0.5),
                size: 20.sp,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AboutTab extends ConsumerWidget {
  const _AboutTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final request = _SmartEventRequestScope.of(context);
    return _TabAsync(
      builder: (event) {
        final dateSpan = TimeUtils.formatDateRange(
          event.dateStart,
          event.dateEnd,
        );

        return ListView(
          padding: EdgeInsets.fromLTRB(16.sp, 8.sp, 16.sp, 24.sp),
          children: [
            Container(
              padding: EdgeInsets.all(16.sp),
              decoration: BoxDecoration(
                color: context.colors.surface,
                borderRadius: BorderRadius.circular(12.br),
                border: Border.all(color: kPrimaryColor.withValues(alpha: 0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'This database gathers the strongest games from every '
                    'ongoing broadcast into one place, so you never have to '
                    'switch between tournaments.',
                    style: AppTypography.textSmRegular.copyWith(
                      color: context.colors.textPrimary,
                      height: 1.4,
                    ),
                  ),
                  SizedBox(height: 16.h),
                  Wrap(
                    spacing: 10.w,
                    runSpacing: 10.h,
                    children: [
                      _Stat(
                        label: 'Tournaments',
                        value: '${event.tournamentCount}',
                      ),
                      _Stat(
                        label: 'Live games',
                        value: '${event.liveGameCount}',
                      ),
                      if (event.avgElo > 0)
                        _Stat(label: 'Avg ELO', value: 'Ø ${event.avgElo}'),
                    ],
                  ),
                  if (dateSpan.isNotEmpty) ...[
                    SizedBox(height: 14.h),
                    _MetaRow(
                      icon: Icons.calendar_today_rounded,
                      text: dateSpan,
                    ),
                  ],
                  if (event.timeControls.isNotEmpty) ...[
                    SizedBox(height: 8.h),
                    _MetaRow(
                      icon: Icons.timer_outlined,
                      text: event.timeControls.join(' · '),
                    ),
                  ],
                ],
              ),
            ),
            SizedBox(height: 20.h),
            Text(
              'Included tournaments',
              style: AppTypography.textSmBold.copyWith(
                color: context.colors.textPrimary,
              ),
            ),
            SizedBox(height: 10.h),
            ...event.events.map(
              (includedEvent) => Padding(
                padding: EdgeInsets.only(bottom: 8.h),
                child: _DismissibleIncludedEventCard(
                  event: includedEvent,
                  scopeId: request.scopeId,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 10.h),
      decoration: BoxDecoration(
        color: kPrimaryColor.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10.br),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: AppTypography.textMdMedium.copyWith(
              color: context.colors.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          SizedBox(height: 2.h),
          Text(
            label,
            style: AppTypography.textXxsMedium.copyWith(
              color: context.colors.textPrimaryMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class _MetaRow extends StatelessWidget {
  const _MetaRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 14.sp, color: context.colors.textPrimaryMuted),
        SizedBox(width: 8.w),
        Expanded(
          child: Text(
            text,
            style: AppTypography.textXsMedium.copyWith(
              color: context.colors.textPrimaryMuted,
            ),
          ),
        ),
      ],
    );
  }
}

/// Standings grouped by included event: each section renders the event card
/// followed by that event's live standings — the same ranked list the user
/// would see inside the event's own Standings tab.
class _StandingsTab extends ConsumerStatefulWidget {
  const _StandingsTab();

  @override
  ConsumerState<_StandingsTab> createState() => _StandingsTabState();
}

class _StandingsTabState extends ConsumerState<_StandingsTab> {
  final Set<String> _collapsedEventIds = {};

  void _toggleEventSection(String eventId) {
    HapticFeedback.lightImpact();
    setState(() {
      if (_collapsedEventIds.contains(eventId)) {
        _collapsedEventIds.remove(eventId);
      } else {
        _collapsedEventIds.add(eventId);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final request = _SmartEventRequestScope.of(context);
    final async = ref.watch(smartAggregateEventProvider(request));
    return async.when(
      data: (event) {
        if (event.events.isEmpty) {
          return _EmptyState();
        }
        final rows = _buildRows(event.events, request.scopeId);
        final horizontalPadding = ResponsiveHelper.adaptive(
          phone: 16.sp,
          tablet: 24.sp,
        );
        return Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: ResponsiveHelper.contentMaxWidth,
            ),
            child: ListView.builder(
              padding: EdgeInsets.fromLTRB(
                horizontalPadding,
                8.sp,
                horizontalPadding,
                24.sp,
              ),
              physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics(),
              ),
              itemCount: rows.length,
              itemBuilder: (context, i) => rows[i],
            ),
          ),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error:
          (e, _) => GenericErrorWidget(
            onRetry: () => ref.invalidate(smartAggregateEventProvider(request)),
          ),
    );
  }

  /// Flattened section rows so the outer list stays virtualized even when an
  /// expanded event carries a long standings table.
  List<Widget> _buildRows(List<GroupEventCardModel> events, String scopeId) {
    final rows = <Widget>[];
    for (final includedEvent in events) {
      final isExpanded = !_collapsedEventIds.contains(includedEvent.id);
      rows.add(
        Padding(
          padding: EdgeInsets.only(bottom: isExpanded ? 8.h : 12.h),
          child: _StandingsEventHeaderCard(
            event: includedEvent,
            scopeId: scopeId,
            isExpanded: isExpanded,
            onToggle: () => _toggleEventSection(includedEvent.id),
          ),
        ),
      );
      if (!isExpanded) continue;
      rows.addAll(_buildStandingsRows(includedEvent));
      rows.add(SizedBox(height: 16.h));
    }
    return rows;
  }

  List<Widget> _buildStandingsRows(GroupEventCardModel event) {
    final standingsAsync = ref.watch(smartEventStandingsProvider(event.id));
    return standingsAsync.when(
      skipLoadingOnRefresh: true,
      skipLoadingOnReload: true,
      data: (standings) {
        if (standings.isEmpty) {
          return [_StandingsSectionStatus(message: 'No standings yet')];
        }
        return [
          const FigmaStandingsHeader(showScore: true),
          SizedBox(height: 8.sp),
          ...standings.map(
            (player) => FigmaPlayerCard(
              key: ValueKey(
                'smart_standing_${event.id}_'
                '${player.fideId ?? player.gamebasePlayerId ?? player.name}',
              ),
              player: player,
              rank: player.overallRank,
              isFavorite: false,
              showFavoriteButton: false,
              onTap: () => _openPlayerProfile(context, player),
            ),
          ),
        ];
      },
      loading:
          () => [
            Padding(
              padding: EdgeInsets.symmetric(vertical: 24.h),
              child: Center(
                child: SizedBox(
                  width: 24.w,
                  height: 24.h,
                  child: CircularProgressIndicator(
                    color: context.colors.textPrimary,
                    strokeWidth: 2,
                  ),
                ),
              ),
            ),
          ],
      error:
          (_, __) => [
            _StandingsSectionStatus(message: 'Standings unavailable'),
          ],
    );
  }

  void _openPlayerProfile(BuildContext context, PlayerStandingModel player) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (_) => PlayerProfileScreen(
              fideId: player.fideId,
              playerName: player.name,
              title:
                  (player.title == null || player.title!.isEmpty)
                      ? null
                      : player.title,
              federation:
                  player.countryCode.isEmpty ? null : player.countryCode,
              rating: player.score > 0 ? player.score : null,
              gamebasePlayerId: player.gamebasePlayerId,
            ),
      ),
    );
  }
}

/// Event card heading a standings section. Tapping it (or the chevron badge)
/// collapses or expands the standings underneath.
class _StandingsEventHeaderCard extends StatelessWidget {
  const _StandingsEventHeaderCard({
    required this.event,
    required this.scopeId,
    required this.isExpanded,
    required this.onToggle,
  });

  final GroupEventCardModel event;
  final String scopeId;
  final bool isExpanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        EventCard(
          tourEventCardModel: event,
          forceCompactLayout: true,
          heroTagSuffix: 'smart_standings_$scopeId',
          onTap: onToggle,
        ),
        Positioned(
          top: -6,
          right: -6,
          child: Material(
            color: context.colors.surface,
            shape: const CircleBorder(),
            elevation: 2,
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onToggle,
              child: Tooltip(
                message: isExpanded ? 'Hide standings' : 'Show standings',
                child: SizedBox(
                  width: 28.sp,
                  height: 28.sp,
                  child: Icon(
                    isExpanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    size: 19.sp,
                    color: context.colors.textPrimary.withValues(alpha: 0.7),
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

class _StandingsSectionStatus extends StatelessWidget {
  const _StandingsSectionStatus({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 16.h),
      child: Center(
        child: Text(
          message,
          style: AppTypography.textSmMedium.copyWith(
            color: context.colors.textPrimaryMuted,
          ),
        ),
      ),
    );
  }
}

class _DismissibleIncludedEventCard extends ConsumerWidget {
  const _DismissibleIncludedEventCard({
    required this.event,
    required this.scopeId,
  });

  final GroupEventCardModel event;
  final String scopeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    void restore() {
      final notifier = ref.read(
        smartEventDismissedEventIdsProvider(scopeId).notifier,
      );
      notifier.state = {...notifier.state}..remove(event.id);
    }

    void dismiss() {
      final notifier = ref.read(
        smartEventDismissedEventIdsProvider(scopeId).notifier,
      );
      notifier.state = {...notifier.state, event.id};

      final messenger = ScaffoldMessenger.of(context);
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: const Text('Tournament hidden from this view'),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
          action: SnackBarAction(
            label: 'Undo',
            textColor: kPrimaryColor,
            onPressed: restore,
          ),
        ),
      );
    }

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Dismissible(
          key: ValueKey('smart_about_dismiss_${scopeId}_${event.id}'),
          direction: DismissDirection.endToStart,
          dismissThresholds: const {DismissDirection.endToStart: 0.35},
          background: const SizedBox.shrink(),
          secondaryBackground: const _IncludedEventDismissBackground(),
          onDismissed: (_) => dismiss(),
          child: Semantics(
            customSemanticsActions: {
              const CustomSemanticsAction(label: 'Hide from this view'): dismiss,
            },
            child: EventCard(
              tourEventCardModel: event,
              forceCompactLayout: true,
              heroTagSuffix: 'smart_about_$scopeId',
            ),
          ),
        ),
        Positioned(
          top: -6,
          right: -6,
          child: Material(
            color: context.colors.surface,
            shape: const CircleBorder(),
            elevation: 2,
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: dismiss,
              child: Tooltip(
                message: 'Hide from this view',
                child: SizedBox(
                  width: 28.sp,
                  height: 28.sp,
                  child: Icon(
                    Icons.close_rounded,
                    size: 17.sp,
                    color: kRedColor,
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

class _IncludedEventDismissBackground extends StatelessWidget {
  const _IncludedEventDismissBackground();

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.centerRight,
      padding: EdgeInsets.only(right: 18.w),
      decoration: BoxDecoration(
        color: kRedColor.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8.br),
        border: Border.all(color: kRedColor.withValues(alpha: 0.18)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.visibility_off_outlined, size: 18.sp, color: kRedColor),
          SizedBox(width: 6.w),
          Text(
            'Hide',
            style: AppTypography.textXsMedium.copyWith(color: kRedColor),
          ),
        ],
      ),
    );
  }
}
