import 'package:chessever2/repository/supabase/game/game_repository.dart';
import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/repository/supabase/group_broadcast/group_tour_repository.dart';
import 'package:chessever2/repository/supabase/tour/tour_repository.dart';
import 'package:chessever2/screens/chessboard/provider/chess_board_screen_provider_new.dart';
import 'package:chessever2/screens/group_event/model/tour_event_card_model.dart';
import 'package:chessever2/screens/group_event/providers/live_group_broadcast_id_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_list_view_mode_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/game_card_wrapper/game_card_wrapper_widget.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/generic_error_widget.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class SmartOpeningQuery {
  const SmartOpeningQuery._({
    required this.rawQuery,
    this.ecoStart,
    this.ecoEnd,
    this.openingTerms = const <String>[],
  });

  final String rawQuery;
  final String? ecoStart;
  final String? ecoEnd;
  final List<String> openingTerms;

  bool get isEco => ecoStart != null;
  bool get isOpeningText => openingTerms.isNotEmpty;

  String get title {
    if (isEco) {
      if (ecoEnd == null || ecoEnd == ecoStart) return 'ECO: $ecoStart';
      return 'ECO: $ecoStart–$ecoEnd';
    }
    return 'Opening: ${_titleCase(rawQuery)}';
  }

  String get subtitle {
    if (isEco) return 'Games from matching ECO codes';
    return 'Games from matching opening names';
  }

  String get badge {
    if (isEco) return ecoEnd == null || ecoEnd == ecoStart ? ecoStart! : 'ECO';
    final term = openingTerms.first;
    return term.length <= 4 ? term.toUpperCase() : term[0].toUpperCase();
  }

  static SmartOpeningQuery? parse(String input) {
    final query = input.trim();
    if (query.isEmpty) return null;

    final compact = query.toUpperCase().replaceAll(RegExp(r'\s+'), '');
    final exactEco = RegExp(r'^[A-E][0-9]{2}$').firstMatch(compact);
    if (exactEco != null) {
      return SmartOpeningQuery._(rawQuery: query, ecoStart: compact);
    }

    final range = RegExp(
      r'^([A-E])([0-9]{2})[-–—]?(?:([A-E])?([0-9]{2}))$',
    ).firstMatch(compact);
    if (range != null && compact.contains(RegExp(r'[-–—]'))) {
      final family = range.group(1)!;
      final start = int.parse(range.group(2)!);
      final endFamily = range.group(3) ?? family;
      final end = int.parse(range.group(4)!);
      if (family == endFamily && start <= end) {
        return SmartOpeningQuery._(
          rawQuery: query,
          ecoStart: '$family${start.toString().padLeft(2, '0')}',
          ecoEnd: '$family${end.toString().padLeft(2, '0')}',
        );
      }
    }

    final normalized = _normalizeOpeningText(query);
    final terms = normalized
        .split(' ')
        .where(
          (term) => term.length >= 3 && !_ignoredOpeningWords.contains(term),
        )
        .toList(growable: false);
    if (terms.isEmpty) return null;

    final hasOpeningSignal = terms.any(_knownOpeningSignals.contains);
    if (!hasOpeningSignal) return null;

    return SmartOpeningQuery._(rawQuery: query, openingTerms: terms);
  }

  bool matchesGame(Games game) {
    if (isEco) return _matchesEco(game.eco);
    final haystack = _normalizeOpeningText(
      '${game.openingName ?? ''} ${game.eco ?? ''} ${game.name ?? ''}',
    );
    return openingTerms.every(haystack.contains);
  }

  @override
  bool operator ==(Object other) {
    return other is SmartOpeningQuery &&
        other.rawQuery == rawQuery &&
        other.ecoStart == ecoStart &&
        other.ecoEnd == ecoEnd &&
        _listEquals(other.openingTerms, openingTerms);
  }

  @override
  int get hashCode =>
      Object.hash(rawQuery, ecoStart, ecoEnd, Object.hashAll(openingTerms));

  bool _matchesEco(String? value) {
    final eco = value?.trim().toUpperCase();
    if (eco == null || !RegExp(r'^[A-E][0-9]{2}$').hasMatch(eco)) {
      return false;
    }
    final start = ecoStart!;
    final end = ecoEnd ?? start;
    if (eco[0] != start[0] || eco[0] != end[0]) return false;
    final code = int.parse(eco.substring(1));
    return code >= int.parse(start.substring(1)) &&
        code <= int.parse(end.substring(1));
  }
}

bool _listEquals(List<String> a, List<String> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

const _ignoredOpeningWords = <String>{
  'opening',
  'defense',
  'defence',
  'variation',
  'system',
  'attack',
  'game',
};

const _knownOpeningSignals = <String>{
  'sicilian',
  'najdorf',
  'dragon',
  'sveshnikov',
  'kan',
  'taimanov',
  'scheveningen',
  'alapin',
  'caro',
  'kann',
  'french',
  'ruy',
  'lopez',
  'spanish',
  'berlin',
  'italian',
  'giuoco',
  'piano',
  'scotch',
  'petroff',
  'philidor',
  'pirc',
  'modern',
  'alekhine',
  'queen',
  'gambit',
  'catalan',
  'nimzo',
  'indian',
  'grunfeld',
  'gruenfeld',
  'benoni',
  'benko',
  'dutch',
  'london',
  'colle',
  'reti',
  'english',
  'bird',
  'vienna',
  'kings',
  'king',
  'slav',
  'semi',
  'tarrasch',
  'veresov',
  'trompowsky',
};

String _normalizeOpeningText(String value) {
  return value
      .toLowerCase()
      .replaceAll('&', ' and ')
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

String _titleCase(String value) {
  return value
      .trim()
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .map((part) => part[0].toUpperCase() + part.substring(1).toLowerCase())
      .join(' ');
}

class SmartOpeningEventCard extends StatelessWidget {
  const SmartOpeningEventCard({super.key, required this.query, this.margin});

  final SmartOpeningQuery query;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: margin ?? EdgeInsets.only(bottom: 12.sp),
      child: InkWell(
        borderRadius: BorderRadius.circular(14.br),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => SmartOpeningEventScreen(query: query),
            ),
          );
        },
        child: Container(
          padding: EdgeInsets.all(14.sp),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                kPrimaryColor.withValues(alpha: 0.18),
                context.colors.surface,
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(14.br),
            border: Border.all(color: kPrimaryColor.withValues(alpha: 0.32)),
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
                  query.badge,
                  style: TextStyle(
                    color: kBlackColor,
                    fontWeight: FontWeight.w800,
                    fontSize: query.badge.length > 3 ? 12.sp : 15.sp,
                  ),
                ),
              ),
              SizedBox(width: 12.sp),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      query.title,
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
                      'Smart database from current games',
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

class SmartOpeningEventState {
  const SmartOpeningEventState({required this.games});

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

final smartOpeningEventProvider = FutureProvider.autoDispose
    .family<SmartOpeningEventState, SmartOpeningQuery>((ref, query) async {
      final broadcasts = await ref
          .read(groupBroadcastRepositoryProvider)
          .getCurrentGroupBroadcasts(limit: 80);
      if (broadcasts.isEmpty) return const SmartOpeningEventState(games: []);

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
      if (tourIds.isEmpty) return const SmartOpeningEventState(games: []);

      final rawGames = await ref
          .read(gameRepositoryProvider)
          .getGamesFromTourIds(tourIds: tourIds, limit: 1000, offset: 0);
      final models = <GamesTourModel>[];
      for (final game in rawGames) {
        if (!query.matchesGame(game)) continue;
        try {
          models.add(GamesTourModel.fromGame(game));
        } catch (_) {
          // Keep the smart event resilient to malformed rows.
        }
      }

      models.sort((a, b) {
        final dateCompare = _gameDate(b).compareTo(_gameDate(a));
        if (dateCompare != 0) return dateCompare;
        return _averageRating(b).compareTo(_averageRating(a));
      });

      return SmartOpeningEventState(games: models);
    });

DateTime _gameDate(GamesTourModel game) {
  return game.bucketDate ?? DateTime.fromMillisecondsSinceEpoch(0);
}

int _averageRating(GamesTourModel game) {
  final white = game.whitePlayer.rating;
  final black = game.blackPlayer.rating;
  if (white > 0 && black > 0) return ((white + black) / 2).round();
  return white > black ? white : black;
}

class SmartOpeningEventScreen extends ConsumerWidget {
  const SmartOpeningEventScreen({super.key, required this.query});

  final SmartOpeningQuery query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(smartOpeningEventProvider(query));
    final viewMode = ref.watch(gamesListViewModeProvider);

    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: AppBar(
        backgroundColor: context.colors.background,
        foregroundColor: context.colors.textPrimary,
        elevation: 0,
        title: Text(query.title),
      ),
      body: SafeArea(
        child: state.when(
          data:
              (data) => _SmartOpeningGamesList(
                query: query,
                data: data,
                viewMode: viewMode,
              ),
          loading: () => const Center(child: CircularProgressIndicator()),
          error:
              (error, stack) => GenericErrorWidget(
                message: error.toString(),
                onRetry: () => ref.invalidate(smartOpeningEventProvider),
              ),
        ),
      ),
    );
  }
}

class _SmartOpeningGamesList extends StatelessWidget {
  const _SmartOpeningGamesList({
    required this.query,
    required this.data,
    required this.viewMode,
  });

  final SmartOpeningQuery query;
  final SmartOpeningEventState data;
  final GamesListViewMode viewMode;

  @override
  Widget build(BuildContext context) {
    if (data.games.isEmpty) {
      return Center(
        child: Text(
          'No ${query.title} games found',
          style: TextStyle(color: context.colors.textSecondary),
        ),
      );
    }

    final entries =
        data.gamesByDay.entries.toList()
          ..sort((a, b) => b.key.compareTo(a.key));
    return ListView.builder(
      padding: EdgeInsets.fromLTRB(16.sp, 12.sp, 16.sp, 24.sp),
      itemCount: entries.length,
      itemBuilder: (context, sectionIndex) {
        final entry = entries[sectionIndex];
        final games = entry.value;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.only(
                top: sectionIndex == 0 ? 0 : 18.sp,
                bottom: 8.sp,
              ),
              child: Text(
                _formatSmartOpeningDay(entry.key),
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

String _formatSmartOpeningDay(DateTime day) {
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
