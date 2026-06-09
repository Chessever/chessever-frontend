import 'package:chessever2/providers/favorite_events_provider.dart';
import 'package:chessever2/repository/gamebase/search/gamebase_search_models.dart';
import 'package:chessever2/revenue_cat_service/subscribe_state.dart';
import 'package:chessever2/screens/chessboard/provider/chess_board_screen_provider_new.dart';
import 'package:chessever2/screens/chessboard/provider/game_pgn_stream_provider.dart';
import 'package:chessever2/screens/group_event/model/tour_event_card_model.dart';
import 'package:chessever2/screens/group_event/smart_event/smart_aggregate_event_provider.dart';
import 'package:chessever2/screens/player_profile/player_profile_screen.dart';
import 'package:chessever2/screens/standings/player_standing_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/game_card_wrapper/game_card_wrapper_widget.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/time_utils.dart';
import 'package:chessever2/widgets/auth/auth_upgrade_sheet.dart';
import 'package:chessever2/widgets/alert_dialog/alert_modal.dart';
import 'package:chessever2/widgets/event_card/event_card.dart';
import 'package:chessever2/widgets/figma_player_card.dart';
import 'package:chessever2/widgets/game_filter/game_filter_dialog.dart';
import 'package:chessever2/widgets/game_filter/game_filter_model.dart';
import 'package:chessever2/widgets/game_filter/game_search_filter_bar.dart';
import 'package:chessever2/widgets/generic_error_widget.dart';
import 'package:chessever2/widgets/paywall/premium_paywall_sheet.dart';
import 'package:chessever2/widgets/segmented_switcher.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Full event view for generated level games. Renders the familiar
/// About / Games / Players tabbed shell, with every tab computed from the
/// current broadcast aggregate ([smartAggregateEventProvider]).
class SmartEventScreen extends ConsumerStatefulWidget {
  const SmartEventScreen({required this.request, super.key});

  final SmartEventRequest request;

  @override
  ConsumerState<SmartEventScreen> createState() => _SmartEventScreenState();
}

class _SmartEventScreenState extends ConsumerState<SmartEventScreen> {
  static const _tabs = ['About', 'Games', 'Players'];

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
                  children: const [_AboutTab(), _GamesTab(), _PlayersTab()],
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
          Expanded(
            child: Center(
              child: Text(
                request.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.textMdMedium.copyWith(
                  color: context.colors.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
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
              Icons.event_busy_outlined,
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
                return Padding(
                  padding: EdgeInsets.fromLTRB(2.sp, 6.sp, 2.sp, 8.sp),
                  child: Text(
                    row.header!,
                    style: AppTypography.textSmBold.copyWith(
                      color: context.colors.textPrimary,
                    ),
                  ),
                );
              }
              final game = row.game!;
              final gameIndex = games.indexWhere(
                (g) => g.gameId == game.gameId,
              );
              return Padding(
                padding: EdgeInsets.only(bottom: 12.sp),
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

  List<_GameListRow> _buildDayRows(List<GamesTourModel> games) {
    final rows = <_GameListRow>[];
    DateTime? currentDay;
    for (final game in games) {
      final day = _gameDay(game);
      if (currentDay == null || !_sameDay(currentDay, day)) {
        currentDay = day;
        rows.add(_GameListRow.header(_dayLabel(day)));
      }
      rows.add(_GameListRow.game(game));
    }
    return rows;
  }

  DateTime _gameDay(GamesTourModel game) {
    final raw = game.lastMoveTime ?? game.bucketDate ?? DateTime.now();
    final local = raw.toLocal();
    return DateTime(local.year, local.month, local.day);
  }

  bool _sameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  String _dayLabel(DateTime day) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    if (_sameDay(day, today)) return 'Today';
    if (_sameDay(day, today.subtract(const Duration(days: 1)))) {
      return 'Yesterday';
    }
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return '${months[day.month - 1]} ${day.day}';
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

class _GameListRow {
  const _GameListRow._({this.header, this.game});

  factory _GameListRow.header(String value) => _GameListRow._(header: value);

  factory _GameListRow.game(GamesTourModel value) =>
      _GameListRow._(game: value);

  final String? header;
  final GamesTourModel? game;
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

class _PlayersTab extends ConsumerWidget {
  const _PlayersTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _TabAsync(
      builder: (event) {
        final rows = _buildPlayers(event.games, event.gameEventNames);
        if (rows.isEmpty) {
          return _EmptyState();
        }
        final horizontalPadding = ResponsiveHelper.adaptive(
          phone: 16.sp,
          tablet: 24.sp,
        );
        return Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: ResponsiveHelper.contentMaxWidth,
            ),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
              child: Column(
                children: [
                  const FigmaStandingsHeader(showScore: true),
                  Expanded(
                    child: ListView.builder(
                      padding: EdgeInsets.only(top: 8.sp, bottom: 24.sp),
                      itemCount: rows.length,
                      itemBuilder: (context, i) {
                        final row = rows[i];
                        return FigmaPlayerCard(
                          key: ValueKey(
                            'smart_player_${row.fideId ?? row.name}_${row.rank}',
                          ),
                          player: row.toStandingModel(),
                          rank: row.rank,
                          isFavorite: false,
                          showFavoriteButton: false,
                          onTap: () => _openPlayerProfile(context, row),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _openPlayerProfile(BuildContext context, _SmartPlayerRow row) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (_) => PlayerProfileScreen(
              fideId: row.fideId,
              playerName: row.name,
              title: row.title.isEmpty ? null : row.title,
              federation: row.countryCode.isEmpty ? null : row.countryCode,
              rating: row.rating > 0 ? row.rating : null,
              gamebasePlayerId: row.gamebasePlayerId,
            ),
      ),
    );
  }

  List<_SmartPlayerRow> _buildPlayers(
    List<GamesTourModel> games,
    Map<String, String> gameEventNames,
  ) {
    final table = <String, _SmartPlayerRow>{};

    _SmartPlayerRow slot(PlayerCard player) {
      final name = player.name.trim();
      final fideId = player.fideId;
      final key = fideId != null ? 'f$fideId' : 'n${name.toLowerCase().trim()}';
      return table.putIfAbsent(
        key,
        () => _SmartPlayerRow(
          name: name,
          rating: player.rating,
          title: player.title,
          countryCode: player.countryCode,
          fideId: player.fideId,
          gamebasePlayerId: player.gamebasePlayerId,
        ),
      );
    }

    for (final game in games) {
      final eventName = gameEventNames[game.gameId] ?? 'Generated games';
      for (final player in [game.whitePlayer, game.blackPlayer]) {
        if (player.name.trim().isEmpty) continue;
        final row = slot(player);
        row.games++;
        row.events.add(eventName);
        if (player.rating > row.rating) row.rating = player.rating;
        if (row.title.isEmpty && player.title.isNotEmpty) {
          row.title = player.title;
        }
        if (row.countryCode.isEmpty && player.countryCode.isNotEmpty) {
          row.countryCode = player.countryCode;
        }
      }
    }

    final list =
        table.values.toList()..sort((a, b) {
          final byRating = b.rating.compareTo(a.rating);
          if (byRating != 0) return byRating;
          return a.name.compareTo(b.name);
        });
    for (var i = 0; i < list.length; i++) {
      list[i].rank = i + 1;
    }
    return list;
  }
}

class _SmartPlayerRow {
  _SmartPlayerRow({
    required this.name,
    required this.rating,
    required this.title,
    required this.countryCode,
    this.fideId,
    this.gamebasePlayerId,
  });

  final String name;
  String title;
  String countryCode;
  final int? fideId;
  final String? gamebasePlayerId;
  int rating;
  int games = 0;
  int rank = 0;
  final Set<String> events = <String>{};

  PlayerStandingModel toStandingModel() {
    final eventCount = events.length;
    final gameText = games == 1 ? '1 game' : '$games games';
    return PlayerStandingModel(
      countryCode: countryCode,
      title: title.isEmpty ? null : title,
      name: name,
      score: rating,
      scoreChange: 0,
      matchScore: eventCount > 1 ? '$gameText / $eventCount events' : gameText,
      fideId: fideId,
      gamebasePlayerId: gamebasePlayerId,
      overallRank: rank,
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
    void dismiss() {
      final notifier = ref.read(
        smartEventDismissedEventIdsProvider(scopeId).notifier,
      );
      notifier.state = {...notifier.state, event.id};
    }

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Dismissible(
          key: ValueKey('smart_about_dismiss_${scopeId}_${event.id}'),
          direction: DismissDirection.startToEnd,
          background: Container(
            alignment: Alignment.centerLeft,
            padding: EdgeInsets.only(left: 18.w),
            decoration: BoxDecoration(
              color: kRedColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10.br),
              border: Border.all(color: kRedColor.withValues(alpha: 0.28)),
            ),
            child: Icon(Icons.close_rounded, size: 20.sp, color: kRedColor),
          ),
          onDismissed: (_) => dismiss(),
          child: EventCard(
            tourEventCardModel: event,
            forceCompactLayout: true,
            heroTagSuffix: 'smart_about_$scopeId',
          ),
        ),
        Positioned(
          top: 0,
          right: 0,
          child: Material(
            color: context.colors.surface,
            shape: const CircleBorder(),
            elevation: 2,
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: dismiss,
              child: SizedBox(
                width: 28.sp,
                height: 28.sp,
                child: Icon(Icons.close_rounded, size: 17.sp, color: kRedColor),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
