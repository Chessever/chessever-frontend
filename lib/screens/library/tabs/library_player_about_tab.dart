import 'package:chessever2/screens/gamebase/models/models.dart';
import 'package:chessever2/screens/library/providers/library_player_profile_provider.dart';
import 'package:chessever2/screens/player_profile/provider/player_profile_provider.dart';
import 'package:chessever2/services/fide_photo_service.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/chess_title_utils.dart';
import 'package:chessever2/utils/country_utils.dart';
import 'package:chessever2/utils/png_asset.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/federation_flag.dart';
import 'package:chessever2/widgets/player_initials_avatar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// About tab for library player profile - shows player info and analytics
class LibraryPlayerAboutTab extends ConsumerStatefulWidget {
  const LibraryPlayerAboutTab({
    super.key,
    required this.playerKey,
    required this.player,
  });

  final LibraryPlayerProfileKey playerKey;
  final GamebasePlayer player;

  @override
  ConsumerState<LibraryPlayerAboutTab> createState() =>
      _LibraryPlayerAboutTabState();
}

class _LibraryPlayerAboutTabState extends ConsumerState<LibraryPlayerAboutTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  int? get _fideIdInt => int.tryParse(widget.player.fideId);

  @override
  Widget build(BuildContext context) {
    super.build(context);

    // Profile data only available with fideId
    final profileDataAsync =
        _fideIdInt != null
            ? ref.watch(playerProfileDataProvider(_fideIdInt!))
            : const AsyncValue<PlayerProfileData?>.data(null);

    // Watch games from library provider (gamebase)
    final gamesState = ref.watch(libraryPlayerGamesProvider(widget.playerKey));

    return RefreshIndicator(
      onRefresh: () async {
        if (_fideIdInt != null) {
          ref.invalidate(playerProfileDataProvider(_fideIdInt!));
        }
        ref.invalidate(libraryPlayerGamesProvider(widget.playerKey));
      },
      color: kWhiteColor,
      backgroundColor: kBlack2Color,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        padding: EdgeInsets.symmetric(horizontal: 20.sp, vertical: 16.h),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Player header with photo and ratings
            _PlayerHeaderSection(
              player: widget.player,
              profileData: profileDataAsync.valueOrNull,
            ),

            SizedBox(height: 24.h),

            // Analytics section (computed from games)
            if (gamesState.isLoading && gamesState.games.isEmpty)
              _buildLoadingAnalytics()
            else if (gamesState.error != null && gamesState.games.isEmpty)
              _buildErrorMessage(gamesState.error!)
            else if (gamesState.games.isEmpty)
              _buildNoGamesMessage()
            else
              _buildAnalyticsSection(gamesState.games),
          ],
        ),
      ),
    );
  }

  Widget _buildAnalyticsSection(List<dynamic> games) {
    final analyticsRequest = PlayerAnalyticsRequest(
      fideId: _fideIdInt,
      playerName: widget.player.name,
      games: games.cast(),
    );
    final analytics = ref.watch(playerAnalyticsProvider(analyticsRequest));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Overall statistics
        _OverallStatsSection(
          resultStats: analytics.resultStats,
          avgOpponentRating: analytics.avgOpponentRating,
        ),

        SizedBox(height: 24.h),

        // Color performance
        _ColorPerformanceSection(colorStats: analytics.colorStats),

        SizedBox(height: 24.h),

        // Recent form
        if (analytics.recentForm.isNotEmpty) ...[
          _RecentFormSection(form: analytics.recentForm),
          SizedBox(height: 24.h),
        ],

        // Opening repertoire
        if (analytics.openingStats.isNotEmpty)
          _OpeningRepertoireSection(openingStats: analytics.openingStats),

        SizedBox(height: 24.h),
      ],
    );
  }

  Widget _buildNoGamesMessage() {
    return Container(
      padding: EdgeInsets.all(24.sp),
      decoration: BoxDecoration(
        color: kBlack2Color,
        borderRadius: BorderRadius.circular(12.br),
      ),
      child: Column(
        children: [
          Icon(
            Icons.sports_esports_outlined,
            size: 48.ic,
            color: kWhiteColor.withValues(alpha: 0.4),
          ),
          SizedBox(height: 12.h),
          Text(
            'No games found',
            style: AppTypography.textMdMedium.copyWith(color: kWhiteColor),
          ),
          SizedBox(height: 4.h),
          Text(
            'Analytics will appear when games are available',
            style: AppTypography.textSmRegular.copyWith(
              color: kWhiteColor.withValues(alpha: 0.6),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    ).animate().fadeIn(duration: 300.ms);
  }

  Widget _buildLoadingAnalytics() {
    return Column(
          children: List.generate(
            3,
            (index) => Container(
              margin: EdgeInsets.only(bottom: 16.h),
              height: 120.h,
              decoration: BoxDecoration(
                color: kBlack2Color,
                borderRadius: BorderRadius.circular(12.br),
              ),
            ),
          ),
        )
        .animate(onPlay: (c) => c.repeat())
        .shimmer(duration: 1500.ms, color: kWhiteColor.withValues(alpha: 0.1));
  }

  Widget _buildErrorMessage(String error) {
    return Container(
      padding: EdgeInsets.all(24.sp),
      decoration: BoxDecoration(
        color: kBlack2Color,
        borderRadius: BorderRadius.circular(12.br),
      ),
      child: Column(
        children: [
          Icon(
            Icons.error_outline,
            size: 48.ic,
            color: Colors.redAccent.withValues(alpha: 0.7),
          ),
          SizedBox(height: 12.h),
          Text(
            'Failed to load analytics',
            style: AppTypography.textMdMedium.copyWith(color: kWhiteColor),
          ),
          SizedBox(height: 4.h),
          Text(
            error,
            style: AppTypography.textSmRegular.copyWith(
              color: kWhiteColor.withValues(alpha: 0.6),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

/// Player header with photo and rating cards
class _PlayerHeaderSection extends StatefulWidget {
  const _PlayerHeaderSection({required this.player, this.profileData});

  final GamebasePlayer player;
  final PlayerProfileData? profileData;

  @override
  State<_PlayerHeaderSection> createState() => _PlayerHeaderSectionState();
}

class _PlayerHeaderSectionState extends State<_PlayerHeaderSection> {
  Future<String?>? _photoFuture;

  int? get _fideIdInt => int.tryParse(widget.player.fideId);

  @override
  void initState() {
    super.initState();
    if (_fideIdInt != null) {
      _photoFuture = FidePhotoService.getPhotoUrlOrNull(_fideIdInt.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final initials = getPlayerInitials(widget.player.name);
    final countryCode = CountryUtils.toIso2Code(widget.player.fed);
    final countryName = CountryUtils.getCountryName(widget.player.fed);
    final displayTitle = ChessTitleUtils.normalize(widget.player.title);

    // Use profile data ratings, fallback to gamebase ratings
    final classicalRating =
        widget.profileData?.classicalRating ??
        widget.player.ratingClassical ??
        widget.player.highestRating;
    final rapidRating =
        widget.profileData?.rapidRating ?? widget.player.ratingRapid;
    final blitzRating =
        widget.profileData?.blitzRating ?? widget.player.ratingBlitz;

    return Column(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Player avatar
            _buildAvatar(initials, displayTitle),

            SizedBox(width: 16.w),

            // Rating cards
            Expanded(
              child: Row(
                children: [
                  Expanded(
                    child: _RatingCard(
                      icon: PngAsset.classicalIcon,
                      label: 'Classical',
                      rating: classicalRating,
                      games: widget.profileData?.classicalGames,
                    ),
                  ),
                  SizedBox(width: 6.w),
                  Expanded(
                    child: _RatingCard(
                      icon: PngAsset.rapidIcon,
                      label: 'Rapid',
                      rating: rapidRating,
                      games: widget.profileData?.rapidGames,
                    ),
                  ),
                  SizedBox(width: 6.w),
                  Expanded(
                    child: _RatingCard(
                      icon: PngAsset.blitzIcon,
                      label: 'Blitz',
                      rating: blitzRating,
                      games: widget.profileData?.blitzGames,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),

        SizedBox(height: 16.h),

        // Player info row
        Container(
          padding: EdgeInsets.all(16.sp),
          decoration: BoxDecoration(
            color: kBlack2Color,
            borderRadius: BorderRadius.circular(12.br),
          ),
          child: Row(
            children: [
              // Country
              if (countryCode.isNotEmpty) ...[
                FederationFlag(
                  federation: widget.player.fed,
                  width: 28.w,
                  height: 20.h,
                  borderRadius: BorderRadius.circular(2.br),
                ),
                SizedBox(width: 10.w),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        countryName.isNotEmpty
                            ? countryName
                            : widget.player.fed,
                        style: AppTypography.textSmMedium.copyWith(
                          color: kWhiteColor,
                        ),
                      ),
                      Text(
                        'Federation',
                        style: AppTypography.textXsRegular.copyWith(
                          color: kWhiteColor.withValues(alpha: 0.5),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              // FIDE ID
              Container(
                padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
                decoration: BoxDecoration(
                  color: kDarkGreyColor,
                  borderRadius: BorderRadius.circular(8.br),
                ),
                child: Column(
                  children: [
                    Text(
                      _fideIdInt?.toString() ?? '-',
                      style: AppTypography.textSmBold.copyWith(
                        color: kWhiteColor,
                        fontFamily: 'monospace',
                      ),
                    ),
                    Text(
                      'FIDE ID',
                      style: AppTypography.textXsRegular.copyWith(
                        color: kWhiteColor.withValues(alpha: 0.5),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    ).animate().fadeIn(duration: 300.ms).slideY(begin: -0.02, end: 0);
  }

  Widget _buildAvatar(String initials, String displayTitle) {
    return FutureBuilder<String?>(
      future: _photoFuture,
      builder: (context, snapshot) {
        return PlayerInitialsAvatar(
          photoUrl: snapshot.data,
          initials: initials,
          size: 110.w,
          borderRadius: 12.br,
          title: displayTitle.isNotEmpty ? displayTitle : null,
        );
      },
    );
  }
}

/// Rating card widget
class _RatingCard extends StatelessWidget {
  const _RatingCard({
    required this.icon,
    required this.label,
    this.rating,
    this.games,
  });

  final String icon;
  final String label;
  final int? rating;
  final int? games;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8.sp, vertical: 10.sp),
      height: 110.w,
      decoration: BoxDecoration(
        color: kBlack2Color,
        borderRadius: BorderRadius.circular(10.br),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Image.asset(icon, width: 20.w, height: 20.h),
          SizedBox(height: 6.h),
          Text(
            label,
            style: AppTypography.textXsMedium.copyWith(
              color: kWhiteColor70,
              fontSize: 10.sp,
            ),
          ),
          SizedBox(height: 4.h),
          Text(
            rating?.toString() ?? '-',
            style: AppTypography.textLgBold.copyWith(color: kWhiteColor),
          ),
          if (games != null && games! > 0)
            Text(
              '$games games',
              style: AppTypography.textXsRegular.copyWith(
                color: kWhiteColor.withValues(alpha: 0.4),
                fontSize: 9.sp,
              ),
            ),
        ],
      ),
    );
  }
}

/// Overall statistics section
class _OverallStatsSection extends StatelessWidget {
  const _OverallStatsSection({
    required this.resultStats,
    required this.avgOpponentRating,
  });

  final ResultStatistics resultStats;
  final int avgOpponentRating;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Overall Performance',
          style: AppTypography.textSmBold.copyWith(color: kWhiteColor),
        ),
        SizedBox(height: 12.h),
        Container(
          padding: EdgeInsets.all(16.sp),
          decoration: BoxDecoration(
            color: kBlack2Color,
            borderRadius: BorderRadius.circular(12.br),
          ),
          child: Column(
            children: [
              // Win/Draw/Loss percentages
              Row(
                children: [
                  _StatBox(
                    label: 'Win Rate',
                    value: '${(resultStats.winRate * 100).toStringAsFixed(1)}%',
                    color: kGreenColor,
                  ),
                  SizedBox(width: 12.w),
                  _StatBox(
                    label: 'Draw Rate',
                    value:
                        '${(resultStats.drawRate * 100).toStringAsFixed(1)}%',
                    color: kWhiteColor70,
                  ),
                  SizedBox(width: 12.w),
                  _StatBox(
                    label: 'Loss Rate',
                    value:
                        '${(resultStats.lossRate * 100).toStringAsFixed(1)}%',
                    color: Colors.redAccent,
                  ),
                ],
              ),

              SizedBox(height: 16.h),

              // Win/Draw/Loss bar
              ClipRRect(
                borderRadius: BorderRadius.circular(4.br),
                child: SizedBox(
                  height: 8.h,
                  child: Row(
                    children: [
                      Expanded(
                        flex: resultStats.wins,
                        child: Container(color: kGreenColor),
                      ),
                      if (resultStats.draws > 0)
                        Expanded(
                          flex: resultStats.draws,
                          child: Container(
                            color: kWhiteColor.withValues(alpha: 0.5),
                          ),
                        ),
                      if (resultStats.losses > 0)
                        Expanded(
                          flex: resultStats.losses,
                          child: Container(color: Colors.redAccent),
                        ),
                    ],
                  ),
                ),
              ),

              SizedBox(height: 16.h),

              // Total games and avg opponent
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${resultStats.totalGames}',
                        style: AppTypography.textLgBold.copyWith(
                          color: kWhiteColor,
                        ),
                      ),
                      Text(
                        'Total Games',
                        style: AppTypography.textXsRegular.copyWith(
                          color: kWhiteColor.withValues(alpha: 0.5),
                        ),
                      ),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${resultStats.wins}W / ${resultStats.draws}D / ${resultStats.losses}L',
                        style: AppTypography.textSmMedium.copyWith(
                          color: kWhiteColor,
                        ),
                      ),
                      Text(
                        'W / D / L',
                        style: AppTypography.textXsRegular.copyWith(
                          color: kWhiteColor.withValues(alpha: 0.5),
                        ),
                      ),
                    ],
                  ),
                  if (avgOpponentRating > 0)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '$avgOpponentRating',
                          style: AppTypography.textLgBold.copyWith(
                            color: kWhiteColor,
                          ),
                        ),
                        Text(
                          'Avg. Opponent',
                          style: AppTypography.textXsRegular.copyWith(
                            color: kWhiteColor.withValues(alpha: 0.5),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    ).animate().fadeIn(duration: 300.ms, delay: 100.ms);
  }
}

/// Stat box widget
class _StatBox extends StatelessWidget {
  const _StatBox({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: EdgeInsets.symmetric(vertical: 12.h),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(8.br),
        ),
        child: Column(
          children: [
            Text(value, style: AppTypography.textMdBold.copyWith(color: color)),
            SizedBox(height: 2.h),
            Text(
              label,
              style: AppTypography.textXsRegular.copyWith(
                color: kWhiteColor.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Color performance section
class _ColorPerformanceSection extends StatelessWidget {
  const _ColorPerformanceSection({required this.colorStats});

  final ColorStatistics colorStats;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Performance by Color',
          style: AppTypography.textSmBold.copyWith(color: kWhiteColor),
        ),
        SizedBox(height: 12.h),
        Row(
          children: [
            Expanded(
              child: _ColorStatCard(
                color: Colors.white,
                label: 'As White',
                games: colorStats.whiteGames,
                wins: colorStats.whiteWins,
                draws: colorStats.whiteDraws,
                losses: colorStats.whiteLosses,
                score: colorStats.whiteScore,
              ),
            ),
            SizedBox(width: 12.w),
            Expanded(
              child: _ColorStatCard(
                color: Colors.black,
                label: 'As Black',
                games: colorStats.blackGames,
                wins: colorStats.blackWins,
                draws: colorStats.blackDraws,
                losses: colorStats.blackLosses,
                score: colorStats.blackScore,
              ),
            ),
          ],
        ),
      ],
    ).animate().fadeIn(duration: 300.ms, delay: 200.ms);
  }
}

/// Color stat card
class _ColorStatCard extends StatelessWidget {
  const _ColorStatCard({
    required this.color,
    required this.label,
    required this.games,
    required this.wins,
    required this.draws,
    required this.losses,
    required this.score,
  });

  final Color color;
  final String label;
  final int games;
  final int wins;
  final int draws;
  final int losses;
  final double score;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(16.sp),
      decoration: BoxDecoration(
        color: kBlack2Color,
        borderRadius: BorderRadius.circular(12.br),
        border: Border.all(
          color: kWhiteColor.withValues(alpha: 0.08),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 20.w,
                height: 20.w,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(4.br),
                  border: Border.all(
                    color: kWhiteColor.withValues(alpha: 0.3),
                    width: 1,
                  ),
                ),
              ),
              SizedBox(width: 8.w),
              Text(
                label,
                style: AppTypography.textSmMedium.copyWith(color: kWhiteColor),
              ),
            ],
          ),
          SizedBox(height: 12.h),
          Text(
            '${(score * 100).toStringAsFixed(1)}%',
            style: AppTypography.textXlBold.copyWith(color: kWhiteColor),
          ),
          Text(
            'Score',
            style: AppTypography.textXsRegular.copyWith(
              color: kWhiteColor.withValues(alpha: 0.5),
            ),
          ),
          SizedBox(height: 8.h),
          Row(
            children: [
              _WLDIndicator(value: wins, type: 'W'),
              SizedBox(width: 6.w),
              _WLDIndicator(value: draws, type: 'D'),
              SizedBox(width: 6.w),
              _WLDIndicator(value: losses, type: 'L'),
            ],
          ),
          SizedBox(height: 4.h),
          Text(
            '$games games',
            style: AppTypography.textXsRegular.copyWith(
              color: kWhiteColor.withValues(alpha: 0.4),
            ),
          ),
        ],
      ),
    );
  }
}

/// Recent form section
class _RecentFormSection extends StatelessWidget {
  const _RecentFormSection({required this.form});

  final List<double> form;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Recent Form (Last ${form.length} games)',
          style: AppTypography.textSmBold.copyWith(color: kWhiteColor),
        ),
        SizedBox(height: 12.h),
        Container(
          padding: EdgeInsets.all(16.sp),
          decoration: BoxDecoration(
            color: kBlack2Color,
            borderRadius: BorderRadius.circular(12.br),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children:
                form.map((result) {
                  Color bgColor;
                  String text;
                  if (result == 1.0) {
                    bgColor = kGreenColor;
                    text = 'W';
                  } else if (result == 0.5) {
                    bgColor = kWhiteColor.withValues(alpha: 0.5);
                    text = 'D';
                  } else {
                    bgColor = Colors.redAccent;
                    text = 'L';
                  }
                  return Container(
                    width: 28.w,
                    height: 28.w,
                    decoration: BoxDecoration(
                      color: bgColor,
                      borderRadius: BorderRadius.circular(6.br),
                    ),
                    child: Center(
                      child: Text(
                        text,
                        style: AppTypography.textXsBold.copyWith(
                          color: result == 0.5 ? kBlackColor : kWhiteColor,
                        ),
                      ),
                    ),
                  );
                }).toList(),
          ),
        ),
      ],
    ).animate().fadeIn(duration: 300.ms, delay: 300.ms);
  }
}

/// Opening repertoire section
class _OpeningRepertoireSection extends StatelessWidget {
  const _OpeningRepertoireSection({required this.openingStats});

  final List<OpeningStatistic> openingStats;

  @override
  Widget build(BuildContext context) {
    final topOpenings = openingStats.take(10).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Opening Repertoire',
          style: AppTypography.textSmBold.copyWith(color: kWhiteColor),
        ),
        SizedBox(height: 12.h),
        Container(
          decoration: BoxDecoration(
            color: kBlack2Color,
            borderRadius: BorderRadius.circular(12.br),
          ),
          child: ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: topOpenings.length,
            separatorBuilder:
                (_, __) => Divider(
                  color: kDividerColor,
                  height: 1,
                  indent: 16.w,
                  endIndent: 16.w,
                ),
            itemBuilder: (context, index) {
              final opening = topOpenings[index];
              return _OpeningRow(opening: opening);
            },
          ),
        ),
      ],
    ).animate().fadeIn(duration: 300.ms, delay: 400.ms);
  }
}

/// Opening row widget
class _OpeningRow extends StatelessWidget {
  const _OpeningRow({required this.opening});

  final OpeningStatistic opening;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
      child: Row(
        children: [
          Container(
            width: 42.w,
            padding: EdgeInsets.symmetric(vertical: 4.h),
            decoration: BoxDecoration(
              color: _getEcoColor(opening.eco),
              borderRadius: BorderRadius.circular(6.br),
            ),
            child: Text(
              opening.eco,
              textAlign: TextAlign.center,
              style: AppTypography.textXsBold.copyWith(
                color: kWhiteColor,
                fontFamily: 'monospace',
              ),
            ),
          ),
          SizedBox(width: 12.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  opening.openingName ?? opening.eco,
                  style: AppTypography.textSmMedium.copyWith(
                    color: kWhiteColor,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                SizedBox(height: 4.h),
                Row(
                  children: [
                    _WLDIndicator(
                      value: opening.wins,
                      type: 'W',
                      compact: true,
                    ),
                    SizedBox(width: 4.w),
                    _WLDIndicator(
                      value: opening.draws,
                      type: 'D',
                      compact: true,
                    ),
                    SizedBox(width: 4.w),
                    _WLDIndicator(
                      value: opening.losses,
                      type: 'L',
                      compact: true,
                    ),
                    SizedBox(width: 8.w),
                    Text(
                      '${opening.count} games',
                      style: AppTypography.textXsRegular.copyWith(
                        color: kWhiteColor.withValues(alpha: 0.4),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${(opening.score * 100).toStringAsFixed(0)}%',
                style: AppTypography.textSmBold.copyWith(
                  color: _getScoreColor(opening.score),
                ),
              ),
              Text(
                'score',
                style: AppTypography.textXsRegular.copyWith(
                  color: kWhiteColor.withValues(alpha: 0.4),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Color _getEcoColor(String eco) {
    if (eco.isEmpty) return kDarkGreyColor;
    switch (eco[0].toUpperCase()) {
      case 'A':
        return const Color(0xFF4A90A4);
      case 'B':
        return const Color(0xFF8B4513);
      case 'C':
        return const Color(0xFF6B8E23);
      case 'D':
        return const Color(0xFF8B008B);
      case 'E':
        return const Color(0xFFB8860B);
      default:
        return kDarkGreyColor;
    }
  }

  Color _getScoreColor(double score) {
    if (score >= 0.6) return kGreenColor;
    if (score >= 0.4) return kWhiteColor;
    return Colors.redAccent;
  }
}

/// Win/Loss/Draw indicator with color
class _WLDIndicator extends StatelessWidget {
  const _WLDIndicator({
    required this.value,
    required this.type,
    this.compact = false,
  });

  final int value;
  final String type;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final Color bgColor;
    final Color textColor;

    switch (type) {
      case 'W':
        bgColor = kGreenColor.withValues(alpha: 0.2);
        textColor = kGreenColor;
        break;
      case 'L':
        bgColor = Colors.redAccent.withValues(alpha: 0.2);
        textColor = Colors.redAccent;
        break;
      case 'D':
      default:
        bgColor = kWhiteColor.withValues(alpha: 0.15);
        textColor = kWhiteColor.withValues(alpha: 0.7);
        break;
    }

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 6.w : 8.w,
        vertical: compact ? 2.h : 4.h,
      ),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(4.br),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            type,
            style: (compact
                    ? AppTypography.textXsBold
                    : AppTypography.textXsMedium)
                .copyWith(color: textColor),
          ),
          SizedBox(width: compact ? 2.w : 4.w),
          Text(
            value.toString(),
            style: (compact
                    ? AppTypography.textXsBold
                    : AppTypography.textXsMedium)
                .copyWith(color: textColor),
          ),
        ],
      ),
    );
  }
}
