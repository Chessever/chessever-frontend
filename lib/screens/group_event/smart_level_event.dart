import 'dart:async';

import 'package:chessever2/providers/auth_state_provider.dart';
import 'package:chessever2/providers/auto_pin_preferences_provider.dart';
import 'package:chessever2/providers/country_dropdown_provider.dart';
import 'package:chessever2/repository/local_storage/auto_pin_preferences/auto_pin_preferences_repository.dart';
import 'package:chessever2/repository/sqlite/app_database.dart';
import 'package:chessever2/repository/supabase/game/game_repository.dart';
import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/repository/supabase/group_broadcast/group_tour_repository.dart';
import 'package:chessever2/repository/supabase/tour/tour_repository.dart';
import 'package:chessever2/screens/chessboard/provider/chess_board_screen_provider_new.dart';
import 'package:chessever2/screens/group_event/model/tour_event_card_model.dart';
import 'package:chessever2/screens/group_event/providers/live_group_broadcast_id_provider.dart';
import 'package:chessever2/screens/group_event/widget/filter_popup/filter_popup_state.dart';
import 'package:chessever2/screens/standings/player_standing_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_list_view_mode_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_auto_pin_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/game_card_wrapper/game_card_wrapper_widget.dart';
import 'package:chessever2/screens/tour_detail/player_tour/player_tour_screen_provider.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/game_filter/rating_tier_filter.dart';
import 'package:chessever2/widgets/generic_error_widget.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class SmartLevelTier {
  const SmartLevelTier({required this.label, required this.minRating});

  final String label;
  final int minRating;

  String get title => '$label Level';
  String get subtitle => 'Games $minRating+';

  static SmartLevelTier? fromFilter(FilterPopupState filter) {
    return fromMinRating(filter.minElo);
  }

  static SmartLevelTier? fromMinRating(int? minRating) {
    final normalized = RatingTierFilter.normalizeMinRating(minRating);
    if (normalized == null) return null;

    for (final tier in RatingTierFilter.tiers) {
      if (tier.minRating == normalized) {
        return SmartLevelTier(label: tier.label, minRating: tier.minRating);
      }
    }
    return null;
  }
}

class SmartLevelEventCard extends ConsumerWidget {
  const SmartLevelEventCard({super.key, required this.tier, this.margin});

  final SmartLevelTier tier;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: margin ?? EdgeInsets.only(bottom: 12.sp),
      child: InkWell(
        borderRadius: BorderRadius.circular(14.br),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => SmartLevelEventScreen(initialTier: tier),
            ),
          );
        },
        child: Container(
          padding: EdgeInsets.all(14.sp),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                kPrimaryColor.withValues(alpha: 0.22),
                context.colors.surface,
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(14.br),
            border: Border.all(color: kPrimaryColor.withValues(alpha: 0.35)),
          ),
          child: Row(
            children: [
              Container(
                width: 42.sp,
                height: 42.sp,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: kPrimaryColor,
                  borderRadius: BorderRadius.circular(11.br),
                ),
                child: Text(
                  tier.label,
                  style: TextStyle(
                    color: kBlackColor,
                    fontWeight: FontWeight.w800,
                    fontSize: 15.sp,
                  ),
                ),
              ),
              SizedBox(width: 12.sp),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tier.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: context.colors.textPrimary,
                        fontSize: 16.sp,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(height: 3.sp),
                    Text(
                      'Top games from all current events',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: context.colors.textSecondary,
                        fontSize: 12.sp,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: context.colors.textSecondary,
                size: 22.sp,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class SmartLevelEventArgs {
  const SmartLevelEventArgs({required this.tier, this.query = ''});

  final SmartLevelTier tier;
  final String query;

  @override
  bool operator ==(Object other) {
    return other is SmartLevelEventArgs &&
        other.tier.minRating == tier.minRating &&
        other.query == query;
  }

  @override
  int get hashCode => Object.hash(tier.minRating, query);
}

class SmartLevelEventState {
  const SmartLevelEventState({required this.games});

  final List<GamesTourModel> games;

  Map<DateTime, List<GamesTourModel>> get gamesByDay {
    final grouped = <DateTime, List<GamesTourModel>>{};
    for (final game in games) {
      final rawDate = game.bucketDate ?? DateTime.fromMillisecondsSinceEpoch(0);
      final day = DateTime(rawDate.year, rawDate.month, rawDate.day);
      grouped.putIfAbsent(day, () => <GamesTourModel>[]).add(game);
    }
    return grouped;
  }
}

final smartLevelEventProvider = FutureProvider.autoDispose
    .family<SmartLevelEventState, SmartLevelEventArgs>((ref, args) async {
      final broadcasts = await ref
          .read(groupBroadcastRepositoryProvider)
          .getCurrentGroupBroadcasts(minElo: args.tier.minRating, limit: 40);
      if (broadcasts.isEmpty) {
        return const SmartLevelEventState(games: []);
      }

      final liveIds = ref.read(liveGroupBroadcastIdsProvider).valueOrNull ?? [];
      final visibleBroadcasts = broadcasts
          .where((broadcast) {
            final category = GroupEventCardModel.getCategory(
              groupId: broadcast.id,
              groupName: broadcast.name,
              startDate: broadcast.dateStart,
              endDate: broadcast.dateEnd,
              liveGroupIds: liveIds,
            );
            return category == TourEventCategory.live ||
                category == TourEventCategory.ongoing ||
                category == TourEventCategory.upcoming;
          })
          .toList(growable: false);

      final toursByEvent = await ref
          .read(tourRepositoryProvider)
          .getToursByGroupBroadcastIds(
            visibleBroadcasts.map((broadcast) => broadcast.id).toList(),
          );
      final tourIds = toursByEvent.values
          .expand((tours) => tours)
          .map((tour) => tour.id)
          .toSet()
          .toList(growable: false);
      if (tourIds.isEmpty) {
        return const SmartLevelEventState(games: []);
      }

      final rawGames = await ref
          .read(gameRepositoryProvider)
          .getGamesFromTourIds(tourIds: tourIds, limit: 500, offset: 0);
      final query = args.query.trim().toLowerCase();
      final models = <GamesTourModel>[];
      for (final game in rawGames) {
        if (!_gameMatchesAverageRating(game, args.tier.minRating)) continue;
        if (query.isNotEmpty && !_gameMatchesQuery(game, query)) continue;
        try {
          models.add(GamesTourModel.fromGame(game));
        } catch (_) {
          // Keep the smart event resilient to malformed rows.
        }
      }

      final pinnedIds = await _loadSmartLevelAutoPins(ref, models);
      models.sort((a, b) {
        final aPinned = pinnedIds.contains(a.gameId);
        final bPinned = pinnedIds.contains(b.gameId);
        if (aPinned && !bPinned) return -1;
        if (!aPinned && bPinned) return 1;

        final dateCompare = _gameDate(b).compareTo(_gameDate(a));
        if (dateCompare != 0) return dateCompare;
        return _averageRating(b).compareTo(_averageRating(a));
      });

      return SmartLevelEventState(games: models);
    });

bool _gameMatchesAverageRating(Games game, int minRating) {
  final players = game.players;
  if (players == null || players.length < 2) return false;
  final ratings = players
      .take(2)
      .map((player) => player.rating)
      .where((r) => r > 0);
  if (ratings.length < 2) return false;
  return ratings.reduce((a, b) => a + b) / 2 >= minRating;
}

bool _gameMatchesQuery(Games game, String query) {
  if ((game.name ?? '').toLowerCase().contains(query)) return true;
  if ((game.openingName ?? '').toLowerCase().contains(query)) return true;
  if ((game.eco ?? '').toLowerCase().contains(query)) return true;
  final players = game.players ?? const <Player>[];
  return players.any(
    (player) =>
        player.name.toLowerCase().contains(query) ||
        player.title.toLowerCase().contains(query) ||
        player.fed.toLowerCase().contains(query),
  );
}

DateTime _gameDate(GamesTourModel game) {
  return game.bucketDate ?? DateTime.fromMillisecondsSinceEpoch(0);
}

int _averageRating(GamesTourModel game) {
  final white = game.whitePlayer.rating;
  final black = game.blackPlayer.rating;
  if (white > 0 && black > 0) return ((white + black) / 2).round();
  return white > black ? white : black;
}

Future<Set<String>> _loadSmartLevelAutoPins(
  Ref ref,
  List<GamesTourModel> games,
) async {
  final prefs = await ref.read(autoPinPreferencesProvider.future);
  if (!prefs.favoritePlayersAutoPinEnabled && !prefs.countrymenAutoPinEnabled) {
    return const <String>{};
  }

  final pinnedIds = <String>{};
  final favoritePlayers =
      prefs.favoritePlayersAutoPinEnabled
          ? await ref.read(tournamentFavoritePlayersProvider.future)
          : const <PlayerStandingModel>[];
  final countryCode =
      prefs.countrymenAutoPinEnabled
          ? await _resolveSmartLevelCountryCode(ref)
          : null;

  for (final game in games) {
    if (prefs.favoritePlayersAutoPinEnabled &&
        _matchesFavoritePlayer(game, favoritePlayers)) {
      pinnedIds.add(game.gameId);
      continue;
    }
    if (countryCode != null && countryCode.isNotEmpty) {
      if (CountryCodeMatcher.matches(
            game.whitePlayer.countryCode,
            countryCode,
          ) ||
          CountryCodeMatcher.matches(
            game.blackPlayer.countryCode,
            countryCode,
          )) {
        pinnedIds.add(game.gameId);
      }
    }
  }
  return pinnedIds;
}

bool _matchesFavoritePlayer(
  GamesTourModel game,
  List<PlayerStandingModel> favoritePlayers,
) {
  return favoritePlayers.any(
        (player) =>
            player.name == game.whitePlayer.name &&
            (player.countryCode.isEmpty ||
                CountryCodeMatcher.matches(
                  game.whitePlayer.countryCode,
                  player.countryCode,
                )),
      ) ||
      favoritePlayers.any(
        (player) =>
            player.name == game.blackPlayer.name &&
            (player.countryCode.isEmpty ||
                CountryCodeMatcher.matches(
                  game.blackPlayer.countryCode,
                  player.countryCode,
                )),
      );
}

Future<String?> _resolveSmartLevelCountryCode(Ref ref) async {
  final userId = ref.read(currentUserProvider)?.id;
  // Keep the repository touched so app-level auto-pin storage is initialized in
  // the same code path as event games. The selected country remains global.
  unawaited(
    AutoPinPreferencesRepository(
      AppDatabase.instance,
    ).getTournamentAutoPinDisabled('smart-level', userId),
  );
  final cachedCountryCode = await AppDatabase.instance.getString(
    'selected_country_code',
  );
  if (cachedCountryCode != null && cachedCountryCode.isNotEmpty) {
    return cachedCountryCode;
  }
  return ref.read(countryDropdownProvider).valueOrNull?.countryCode;
}

class SmartLevelEventScreen extends ConsumerStatefulWidget {
  const SmartLevelEventScreen({super.key, required this.initialTier});

  final SmartLevelTier initialTier;

  @override
  ConsumerState<SmartLevelEventScreen> createState() =>
      _SmartLevelEventScreenState();
}

class _SmartLevelEventScreenState extends ConsumerState<SmartLevelEventScreen> {
  late SmartLevelTier _tier;
  String _query = '';
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tier = widget.initialTier;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(
      smartLevelEventProvider(SmartLevelEventArgs(tier: _tier, query: _query)),
    );
    final viewMode = ref.watch(gamesListViewModeProvider);

    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: AppBar(
        backgroundColor: context.colors.background,
        foregroundColor: context.colors.textPrimary,
        elevation: 0,
        title: Text(_tier.title),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(16.sp, 8.sp, 16.sp, 10.sp),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _searchController,
                    onChanged: (value) => setState(() => _query = value),
                    style: TextStyle(color: context.colors.textPrimary),
                    decoration: InputDecoration(
                      hintText: 'Search this level',
                      hintStyle: TextStyle(color: context.colors.textSecondary),
                      prefixIcon: Icon(
                        Icons.search_rounded,
                        color: context.colors.textSecondary,
                      ),
                      filled: true,
                      fillColor: context.colors.surface,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12.br),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  SizedBox(height: 10.sp),
                  RatingTierFilter(
                    selectedMinRating: _tier.minRating,
                    onChanged: (minRating) {
                      final tier = SmartLevelTier.fromMinRating(minRating);
                      if (tier != null) setState(() => _tier = tier);
                    },
                  ),
                ],
              ),
            ),
            Expanded(
              child: state.when(
                data:
                    (data) => _SmartLevelGamesList(
                      tier: _tier,
                      data: data,
                      viewMode: viewMode,
                    ),
                loading: () => const Center(child: CircularProgressIndicator()),
                error:
                    (error, stack) => GenericErrorWidget(
                      message: error.toString(),
                      onRetry: () => ref.invalidate(smartLevelEventProvider),
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SmartLevelGamesList extends ConsumerWidget {
  const _SmartLevelGamesList({
    required this.tier,
    required this.data,
    required this.viewMode,
  });

  final SmartLevelTier tier;
  final SmartLevelEventState data;
  final GamesListViewMode viewMode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (data.games.isEmpty) {
      return Center(
        child: Text(
          'No ${tier.title} games found',
          style: TextStyle(color: context.colors.textSecondary),
        ),
      );
    }

    final entries =
        data.gamesByDay.entries.toList()
          ..sort((a, b) => b.key.compareTo(a.key));
    return ListView.builder(
      padding: EdgeInsets.fromLTRB(16.sp, 0, 16.sp, 24.sp),
      itemCount: entries.length,
      itemBuilder: (context, sectionIndex) {
        final entry = entries[sectionIndex];
        final games = entry.value;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.only(
                top: sectionIndex == 0 ? 4.sp : 18.sp,
                bottom: 8.sp,
              ),
              child: Text(
                _formatSmartLevelDay(entry.key),
                style: TextStyle(
                  color: context.colors.textPrimary,
                  fontSize: 15.sp,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            ...List.generate(games.length, (index) {
              final game = games[index];
              final globalIndex = data.games.indexWhere(
                (item) => item.gameId == game.gameId,
              );
              final gamesData = GamesScreenModel(
                gamesTourModels: data.games,
                pinnedGamedIs: const [],
              );
              return Padding(
                padding: EdgeInsets.only(bottom: 10.sp),
                child: GameCardWrapperWidget(
                  game: game,
                  gamesData: gamesData,
                  gameIndex: globalIndex < 0 ? index : globalIndex,
                  isChessBoardVisible:
                      viewMode == GamesListViewMode.chessBoardGrid,
                  viewSource: ChessboardView.forYou,
                  onReturnFromChessboard: (_) {},
                  onPinToggle: (_) async {},
                ),
              );
            }),
          ],
        );
      },
    );
  }
}

String _formatSmartLevelDay(DateTime day) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final yesterday = today.subtract(const Duration(days: 1));
  if (day == today) return 'Today';
  if (day == yesterday) return 'Yesterday';
  const months = <String>[
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${months[day.month - 1]} ${day.day}';
}
