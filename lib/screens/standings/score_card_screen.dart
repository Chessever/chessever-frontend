import 'dart:math' as math;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:chessever2/screens/standings/player_standing_model.dart';
import 'package:chessever2/screens/standings/providers/player_ratings_provider.dart';
import 'package:chessever2/screens/standings/providers/fide_ratings_provider.dart';
import 'package:chessever2/screens/standings/providers/player_utils_provider.dart';
import 'package:chessever2/screens/standings/widget/scoreboard_appbar.dart';
import 'package:chessever2/screens/standings/widget/scoreboard_card_widget.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_mode_provider.dart';
import 'package:chessever2/screens/player_profile/widgets/performance_stats_row.dart';
import 'package:chessever2/services/fide_photo_service.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/location_service_provider.dart';
import 'package:chessever2/utils/png_asset.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:country_flags/country_flags.dart';
import 'package:skeletonizer/skeletonizer.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/repository/supabase/game/game_repository.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_screen_provider.dart';
import 'package:chessever2/screens/chessboard/chess_board_screen_new.dart';
import 'package:chessever2/screens/chessboard/provider/chess_board_screen_provider_new.dart';
import 'package:chessever2/screens/favorites/favorite_players_provider.dart';
import 'package:chessever2/utils/svg_asset.dart';
import 'package:chessever2/widgets/auth/auth_upgrade_sheet.dart';
import 'package:chessever2/widgets/svg_widget.dart';

final selectedPlayerProvider = StateProvider<PlayerStandingModel?>(
  (ref) => null,
);

final playerGamesProvider = FutureProvider.family<
  List<GamesTourModel>,
  PlayerStandingModel
>((ref, player) async {
  try {
    final gameRepo = ref.read(gameRepositoryProvider);

    List<dynamic> games = [];

    if (player.fideId != null) {
      try {
        games = await gameRepo.getGamesByFideId(
          player.fideId.toString(),
          limit: 50,
        );
      } catch (e) {
        debugPrint('Error fetching by fideId: $e');
      }
    }

    if (games.isEmpty) {
      games = await gameRepo.getGamesByPlayerName(player.name, limit: 50);
    }
    var allGames = games.map((game) => GamesTourModel.fromGame(game)).toList();

    // Sort by date (descending) - most recent games first
    final epochFallback = DateTime.fromMillisecondsSinceEpoch(0);
    allGames.sort((a, b) {
      final aTime = a.lastMoveTime ?? epochFallback;
      final bTime = b.lastMoveTime ?? epochFallback;
      return bTime.compareTo(aTime);
    });

    return allGames;
  } catch (e, _) {
    debugPrint('Error: $e');
    return [];
  }
});

class ScoreCardScreen extends ConsumerWidget {
  const ScoreCardScreen({super.key});

  double? _extractRatingFromPGN(String? pgn, bool isWhite) {
    if (pgn == null || pgn.isEmpty) return null;

    final patterns =
        isWhite
            ? [
              RegExp(r'\[WhiteElo "(\d+(?:\.\d+)?)"\]'),
              RegExp(r'\[WhiteElo (\d+(?:\.\d+)?)\]'),
              RegExp(r'WhiteElo\s+(\d+(?:\.\d+)?)'),
            ]
            : [
              RegExp(r'\[BlackElo "(\d+(?:\.\d+)?)"\]'),
              RegExp(r'\[BlackElo (\d+(?:\.\d+)?)\]'),
              RegExp(r'BlackElo\s+(\d+(?:\.\d+)?)'),
            ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(pgn);
      if (match != null && match.group(1) != null) {
        final rating = double.tryParse(match.group(1)!);
        if (rating != null && rating > 0) {
          return rating;
        }
      }
    }
    return null;
  }

  // Get player rating from game
  double _getPlayerRating(GamesTourModel game, String playerName) {
    final isWhite = game.whitePlayer.name == playerName;
    final playerCard = isWhite ? game.whitePlayer : game.blackPlayer;

    if (playerCard.rating > 0) {
      return playerCard.rating.toDouble();
    }

    final pgnRating = _extractRatingFromPGN(game.pgn, isWhite);
    if (pgnRating != null && pgnRating > 0) {
      return pgnRating;
    }

    return 1500.0;
  }

  // Calculate K-factor
  int _getKFactor(double rating) {
    if (rating >= 2400) {
      return 10;
    } else {
      return 20;
    }
  }

  // Calculate FIDE Elo rating change
  double _calculateFideRatingChange(
    double playerRating,
    double opponentRating,
    GameStatus gameStatus,
    String playerName,
    GamesTourModel game,
  ) {
    double actualScore;
    final isWhite = game.whitePlayer.name == playerName;

    switch (gameStatus) {
      case GameStatus.whiteWins:
        actualScore = isWhite ? 1.0 : 0.0;
        break;
      case GameStatus.blackWins:
        actualScore = isWhite ? 0.0 : 1.0;
        break;
      case GameStatus.draw:
        actualScore = 0.5;
        break;
      default:
        return 0;
    }

    double ratingDiff = (opponentRating - playerRating).clamp(-400.0, 400.0);
    double expectedScore = 1 / (1 + math.pow(10, ratingDiff / 400.0));
    int kFactor = _getKFactor(playerRating);
    double ratingChange = kFactor * (actualScore - expectedScore);

    return ratingChange;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final player = ref.watch(selectedPlayerProvider);

    if (player == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final selectedBroadcast = ref.watch(selectedBroadcastModelProvider);

    List<GamesTourModel> allGames = [];
    bool isLoadingGames = false;
    bool hasTournamentContext = false;

    if (selectedBroadcast != null) {
      hasTournamentContext = true;
      final gamesTourAsync = ref.watch(gamesTourScreenProvider);
      allGames = gamesTourAsync.when(
        data: (data) => data.gamesTourModels,
        loading: () {
          isLoadingGames = true;
          return [];
        },
        error: (_, __) => [],
      );
    } else {
      hasTournamentContext = false;
      final playerGamesAsync = ref.watch(playerGamesProvider(player));
      allGames = playerGamesAsync.when(
        data: (games) => games,
        loading: () {
          isLoadingGames = true;
          return [];
        },
        error: (_, __) => [],
      );
    }

    final gameDateFallback = DateTime.fromMillisecondsSinceEpoch(0);
    final playerGames =
        allGames.where((game) {
          return ref
                  .read(playerUtilsProvider)
                  .isSamePlayer(game.whitePlayer.name, player.name) ||
              ref
                  .read(playerUtilsProvider)
                  .isSamePlayer(game.blackPlayer.name, player.name);
        }).toList();
    playerGames.sort((a, b) {
      final aTime = a.lastMoveTime ?? gameDateFallback;
      final bTime = b.lastMoveTime ?? gameDateFallback;
      return bTime.compareTo(aTime);
    });

    final nameParts = player.name.split(',');
    final initials =
        nameParts.length > 1
            ? '${nameParts[0].trim().isNotEmpty ? nameParts[0].trim()[0] : ''}'
                '${nameParts[1].trim().isNotEmpty ? nameParts[1].trim()[0] : ''}'
            : player.name.trim().isNotEmpty
            ? player.name.trim().substring(
              0,
              math.min(2, player.name.trim().length),
            )
            : '';

    // Calculate total performance
    double totalPerformance = 0.0;
    for (final game in playerGames) {
      final playerRating = _getPlayerRating(game, player.name);
      final isWhite = game.whitePlayer.name == player.name;
      final opponent = isWhite ? game.blackPlayer : game.whitePlayer;
      final opponentRating = _getPlayerRating(game, opponent.name);

      if (playerRating > 0 && opponentRating > 0) {
        final ratingChange = _calculateFideRatingChange(
          playerRating,
          opponentRating,
          game.gameStatus,
          player.name,
          game,
        );
        totalPerformance += ratingChange;
      }
    }

    final displayPerformance =
        playerGames.isEmpty
            ? (player.scoreChange.toDouble())
            : totalPerformance;
    final performanceRating = (player.score + displayPerformance).round();
    final displayScore = player.matchScore ?? "0 / 0";
    final parsedScore = _parseScoreValues(displayScore);
    final validCountryCode = ref
        .read(locationServiceProvider)
        .getValidCountryCode(player.countryCode);
    final photoFuture = FidePhotoService.getPhotoUrlOrNull(
      player.fideId?.toString(),
    );

    return Scaffold(
      backgroundColor: kBackgroundColor,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            const _SliverScoreboardAppBar(),
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 20.sp),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(height: 14.h),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _PlayerAvatarTile(
                          photoFuture: photoFuture,
                          initials: initials,
                          title: player.title,
                        ),
                        SizedBox(width: 10.w),
                        Expanded(
                          child: IntrinsicHeight(
                            child: Row(
                              children: [
                                Expanded(
                                  child: _RatingDisplay(
                                    label: 'Classical',
                                    playerName: player.name,
                                    fideId: player.fideId,
                                    timeControlType: "standard",
                                    assetPath: PngAsset.classicalIcon,
                                  ),
                                ),
                                SizedBox(width: 6.w),
                                Expanded(
                                  child: _RatingDisplay(
                                    label: 'Rapid',
                                    playerName: player.name,
                                    fideId: player.fideId,
                                    timeControlType: "rapid",
                                    assetPath: PngAsset.rapidIcon,
                                  ),
                                ),
                                SizedBox(width: 6.w),
                                Expanded(
                                  child: _RatingDisplay(
                                    label: 'Blitz',
                                    playerName: player.name,
                                    fideId: player.fideId,
                                    timeControlType: "blitz",
                                    assetPath: PngAsset.blitzIcon,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 16.h),
                    PerformanceStatsRow(
                      performanceRating: performanceRating,
                      score: parsedScore.$1,
                      totalGames: parsedScore.$2,
                      ratingDiff: player.scoreChange,
                    ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: SizedBox(height: 16.h),
            ),
            if (isLoadingGames)
              const SliverFillRemaining(
                child: Center(child: CircularProgressIndicator()),
              )
            else if (playerGames.isEmpty)
              SliverFillRemaining(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.info_outline,
                        size: 48.ic,
                        color: kWhiteColor.withValues(alpha: 0.5),
                      ),
                      SizedBox(height: 16.h),
                      Text(
                        hasTournamentContext
                            ? 'No games in this tournament'
                            : 'No games available',
                        style: AppTypography.textMdMedium.copyWith(
                          color: kWhiteColor.withValues(alpha: 0.7),
                        ),
                      ),
                      SizedBox(height: 8.h),
                      Text(
                        hasTournamentContext
                            ? 'This player has not played in this tournament yet'
                            : 'Games will appear once they are played',
                        textAlign: TextAlign.center,
                        style: AppTypography.textSmRegular.copyWith(
                          color: kWhiteColor.withValues(alpha: 0.5),
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final game = playerGames[index];
                    final isWhite = game.whitePlayer.name == player.name;
                    final opponent =
                        isWhite ? game.blackPlayer : game.whitePlayer;
                    final result = _getPlayerResult(game, player.name);

                    final playerRating = _getPlayerRating(game, player.name);
                    final opponentRating = _getPlayerRating(game, opponent.name);

                    double ratingChange = 0.0;
                    if (playerRating > 0 && opponentRating > 0) {
                      ratingChange = _calculateFideRatingChange(
                        playerRating,
                        opponentRating,
                        game.gameStatus,
                        player.name,
                        game,
                      );
                    }

                    return Padding(
                      padding: EdgeInsets.symmetric(horizontal: 20.0.sp),
                      child: ScoreboardCardWidget(
                        roundLabel:
                            hasTournamentContext ? _buildRoundLabel(game) : null,
                        countryCode: opponent.countryCode,
                        title: opponent.title,
                        name: opponent.name,
                        score: opponent.rating,
                        scoreChange: ratingChange != 0.0 ? ratingChange : null,
                        matchScore: result,
                        isWhite: isWhite,
                        index: index,
                        isFirst: index == 0,
                        isLast: index == playerGames.length - 1,
                        onTap: () {
                          if (ref.read(selectedBroadcastModelProvider) == null) {
                            ref
                                .read(chessboardViewFromProviderNew.notifier)
                                .state = ChessboardView.favScorecard;
                          } else {
                            ref
                                .read(chessboardViewFromProviderNew.notifier)
                                .state = ChessboardView.tour;
                          }

                          final gameIndex = allGames.indexWhere(
                            (g) => g.gameId == game.gameId,
                          );

                          if (gameIndex != -1) {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder:
                                    (_) => ChessBoardScreenNew(
                                      games: allGames,
                                      currentIndex: gameIndex,
                                    ),
                              ),
                            );
                          }
                        },
                      ),
                    );
                  },
                  childCount: playerGames.length,
                ),
              ),
            SliverPadding(padding: EdgeInsets.only(bottom: 20.h)),
          ],
        ),
      ),
    );
  }

  (double?, int?) _parseScoreValues(String scoreText) {
    final match = RegExp(
      r'([0-9]+(?:\.[0-9]+)?)\s*/\s*([0-9]+)',
    ).firstMatch(scoreText);
    if (match != null) {
      final score = double.tryParse(match.group(1) ?? '');
      final totalGames = int.tryParse(match.group(2) ?? '');
      return (score, totalGames);
    }
    return (null, null);
  }

  String _getPlayerResult(GamesTourModel game, String playerName) {
    final isWhite = game.whitePlayer.name == playerName;
    switch (game.gameStatus) {
      case GameStatus.whiteWins:
        return isWhite ? '1' : '0';
      case GameStatus.blackWins:
        return isWhite ? '0' : '1';
      case GameStatus.draw:
        return '½';
      case GameStatus.ongoing:
        return '–';
      case GameStatus.unknown:
        return '-';
    }
  }

  String? _buildRoundLabel(GamesTourModel game) {
    final slugLabel = _parseRoundLabel(game.roundSlug);
    if (slugLabel != null) return slugLabel;

    final roundIdLabel = _parseRoundLabel(game.roundId);
    return roundIdLabel;
  }

  String? _parseRoundLabel(String? source) {
    if (source == null || source.isEmpty) return null;

    final patterns = [
      RegExp(r'round[-\s]?(\d+)', caseSensitive: false),
      RegExp(r'rapid[-\s]?(\d+)', caseSensitive: false),
      RegExp(r'blitz[-\s]?(\d+)', caseSensitive: false),
      RegExp(r'^(\d+)$'),
      RegExp(r'r(\d+)', caseSensitive: false),
      RegExp(r'game[-\s]?(\d+)', caseSensitive: false),
    ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(source);
      if (match != null && match.groupCount >= 1) {
        final number = match.group(1);
        if (number != null && number.isNotEmpty) {
          return 'R$number:';
        }
      }
    }

    return null;
  }
}

class _PlayerHeaderRow extends StatelessWidget {
  final String countryCode;
  final String rawCountryCode;
  final String? title;
  final String name;

  const _PlayerHeaderRow({
    required this.countryCode,
    required this.rawCountryCode,
    required this.title,
    required this.name,
  });

  @override
  Widget build(BuildContext context) {
    Widget flagWidget = const SizedBox.shrink();
    if (rawCountryCode.toUpperCase() == 'FID') {
      flagWidget = Image.asset(
        PngAsset.fideLogo,
        height: 18.h,
        width: 24.w,
        fit: BoxFit.cover,
      );
    } else if (countryCode.isNotEmpty) {
      flagWidget = CountryFlag.fromCountryCode(
        countryCode,
        height: 18.h,
        width: 24.w,
      );
    }

    return Row(
      children: [
        flagWidget,
        SizedBox(width: 10.w),
        Expanded(
          child: Text(
            '${title != null && title!.isNotEmpty ? '${title!} ' : ''}$name',
            style: AppTypography.textLgBold.copyWith(color: kWhiteColor),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Icon(Icons.keyboard_arrow_down, color: kWhiteColor70, size: 22.ic),
      ],
    );
  }
}

class _PlayerAvatarTile extends StatelessWidget {
  final Future<String?>? photoFuture;
  final String initials;
  final String? title;

  const _PlayerAvatarTile({
    required this.photoFuture,
    required this.initials,
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    final avatarSize = 110.w;

    return Stack(
      alignment: Alignment.bottomCenter,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12.br),
          child: FutureBuilder<String?>(
            future: photoFuture,
            builder: (context, snapshot) {
              final photoUrl = snapshot.data;
              if (photoUrl != null && photoUrl.isNotEmpty) {
                return CachedNetworkImage(
                  imageUrl: photoUrl,
                  width: avatarSize,
                  height: avatarSize,
                  fit: BoxFit.cover,
                  placeholder:
                      (context, url) => _AvatarPlaceholder(
                        initials: initials,
                        size: avatarSize,
                      ),
                  errorWidget:
                      (context, url, error) => _AvatarPlaceholder(
                        initials: initials,
                        size: avatarSize,
                      ),
                );
              }

              return _AvatarPlaceholder(initials: initials, size: avatarSize);
            },
          ),
        ),
        if (title != null && title!.isNotEmpty)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 4.w, vertical: 2.h),
              decoration: BoxDecoration(
                color: kGreenColor.withValues(alpha: 0.9),
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(12.br),
                  bottomRight: Radius.circular(12.br),
                ),
              ),
              child: Text(
                title!,
                textAlign: TextAlign.center,
                style: AppTypography.textXsMedium.copyWith(
                  color: Colors.white,
                  fontSize: 10.sp,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _SliverScoreboardAppBar extends ConsumerStatefulWidget {
  const _SliverScoreboardAppBar();

  @override
  ConsumerState<_SliverScoreboardAppBar> createState() =>
      _SliverScoreboardAppBarState();
}

class _SliverScoreboardAppBarState extends ConsumerState<_SliverScoreboardAppBar>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.2).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _toggleFavorite() async {
    final allowed = await requireFullAuthGuard(context);
    if (!allowed) return;

    final favoritesNotifier = ref.read(
      favoritePlayersNotifierProvider.notifier,
    );
    final player = ref.read(selectedPlayerProvider);

    if (player != null) {
      try {
        final isNowFavorite = await favoritesNotifier.toggleFavorite(player);
        if (isNowFavorite) {
          _animationController.forward().then(
            (_) => _animationController.reverse(),
          );
        }
      } catch (e) {
        debugPrint('Error toggling favorite: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to update favorite. Please try again.'),
              duration: Duration(seconds: 2),
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final player = ref.watch(selectedPlayerProvider);
    if (player == null) return const SliverAppBar();

    final validCountryCode = ref
        .read(locationServiceProvider)
        .getValidCountryCode(player.countryCode);

    final favoritesAsync = ref.watch(favoritePlayersNotifierProvider);
    final isFavorite =
        favoritesAsync.maybeWhen(
          data: (state) => state.players.any((p) => p.fideId == player.fideId),
          orElse: () => false,
          skipLoadingOnRefresh: true,
          skipLoadingOnReload: true,
        );

    return SliverAppBar(
      pinned: true,
      backgroundColor: kBackgroundColor,
      elevation: 0,
      centerTitle: false,
      leading: IconButton(
        icon: Icon(
          Icons.arrow_back_ios_new_outlined,
          color: kWhiteColor,
          size: 22.ic,
        ),
        onPressed: () => Navigator.of(context).pop(),
      ),
      title: _PlayerHeaderRow(
        countryCode: validCountryCode,
        rawCountryCode: player.countryCode,
        title: player.title,
        name: player.name,
      ),
      actions: [
        InkWell(
          onTap: _toggleFavorite,
          child: Container(
            width: 48.w,
            padding: EdgeInsets.all(8.sp),
            child: ScaleTransition(
              scale: _scaleAnimation,
              child: SvgWidget(
                isFavorite
                    ? SvgAsset.favouriteRedIcon
                    : SvgAsset.favouriteIcon2,
                semanticsLabel: 'Favorite Icon',
                height: 20.h,
                width: 20.w,
              ),
            ),
          ),
        ),
        SizedBox(width: 8.w),
      ],
    );
  }
}

class _AvatarPlaceholder extends StatelessWidget {
  final String initials;
  final double size;

  const _AvatarPlaceholder({required this.initials, required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12.br),
        gradient: kProfileInitialsGradient,
      ),
      child: Center(
        child: Text(
          initials,
          style: AppTypography.textXlBold.copyWith(color: kWhiteColor),
        ),
      ),
    );
  }
}

class _RatingDisplay extends ConsumerWidget {
  final String label;
  final String playerName;
  final int? fideId;
  final String timeControlType;
  final String assetPath;

  const _RatingDisplay({
    required this.label,
    required this.playerName,
    this.fideId,
    required this.timeControlType,
    required this.assetPath,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Widget _wrapCard(Widget value) {
      return Container(
        padding: EdgeInsets.symmetric(horizontal: 4.sp, vertical: 10.sp),
        width: double.infinity,
        decoration: BoxDecoration(
          color: kBlack2Color,
          borderRadius: BorderRadius.circular(10.br),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Image.asset(assetPath, width: 22.w, height: 22.h),
            SizedBox(height: 6.h),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.textXsMedium.copyWith(
                color: kWhiteColor70,
                fontSize: 11.sp,
              ),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 6.h),
            value,
          ],
        ),
      );
    }

    // Try FIDE API first if we have a FIDE ID
    if (fideId != null) {
      final fideRequest = FideRatingRequest(
        fideId: fideId,
        timeControlType: timeControlType,
      );
      final fideRatingAsync = ref.watch(fideRatingProvider(fideRequest));

      return _wrapCard(
        fideRatingAsync.when(
          data: (rating) {
            if (rating != null && rating > 0) {
              return Text(
                rating.toString(),
                style: AppTypography.textLgBold.copyWith(color: kWhiteColor),
              );
            }
            return _FallbackRatingDisplay(
              playerName: playerName,
              timeControlType: timeControlType,
            );
          },
          loading:
              () => Skeletonizer(
                enabled: true,
                ignoreContainers: true,
                effect: const ShimmerEffect(
                  baseColor: Color(0xFF2A2A2A),
                  highlightColor: Color(0xFF3A3A3A),
                ),
                child: Text(
                  '2400',
                  style: AppTypography.textLgBold.copyWith(color: kWhiteColor),
                ),
              ),
          error:
              (_, __) => _FallbackRatingDisplay(
                playerName: playerName,
                timeControlType: timeControlType,
              ),
        ),
      );
    }

    // No FIDE ID - use PGN-based ratings
    return _wrapCard(
      _FallbackRatingDisplay(
        playerName: playerName,
        timeControlType: timeControlType,
      ),
    );
  }
}

/// Fallback widget using PGN-based ratings from Supabase
class _FallbackRatingDisplay extends ConsumerWidget {
  final String playerName;
  final String timeControlType;

  const _FallbackRatingDisplay({
    required this.playerName,
    required this.timeControlType,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ratingRequest = PlayerRatingRequest(
      playerName: playerName,
      timeControlType: timeControlType,
    );

    final ratingAsync = ref.watch(playerLatestRatingProvider(ratingRequest));

    return ratingAsync.when(
      data:
          (rating) => Text(
            rating?.toString() ?? '-',
            style: AppTypography.textLgBold.copyWith(color: kWhiteColor),
          ),
      loading:
          () => Skeletonizer(
            enabled: true,
            ignoreContainers: true,
            effect: const ShimmerEffect(
              baseColor: Color(0xFF2A2A2A),
              highlightColor: Color(0xFF3A3A3A),
            ),
            child: Text(
              '2400',
              style: AppTypography.textLgBold.copyWith(color: kWhiteColor),
            ),
          ),
      error:
          (_, __) => Text(
            '-',
            style: AppTypography.textLgBold.copyWith(color: kWhiteColor),
          ),
    );
  }
}
