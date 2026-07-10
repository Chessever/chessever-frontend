import 'package:chessever2/e2e/e2e_ids.dart';
import 'package:chessever2/screens/premium_games/providers/premium_games_provider.dart';
export 'providers/premium_games_provider.dart' show PremiumGamesType;
import 'package:chessever2/screens/premium_games/widgets/premium_games_filter.dart';
import 'package:chessever2/screens/premium_games/widgets/twic_game_card.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/liquid_glass/glass_back_button.dart';
import 'package:chessever2/widgets/liquid_glass/glass_full_screen_page.dart';
import 'package:chessever2/widgets/liquid_glass/glass_island_top_bar.dart';
import 'package:chessever2/widgets/liquid_glass/glass_motion.dart';
import 'package:chessever2/widgets/liquid_glass/glass_title_chip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

/// Screen displaying premium games (favorites or countrymen).
/// Features TWIC-style game cards with filtering and pagination.
class PremiumGamesScreen extends ConsumerStatefulWidget {
  const PremiumGamesScreen({required this.type, super.key});

  final PremiumGamesType type;

  @override
  ConsumerState<PremiumGamesScreen> createState() => _PremiumGamesScreenState();
}

class _PremiumGamesScreenState extends ConsumerState<PremiumGamesScreen> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      ref.read(premiumGamesProvider(widget.type).notifier).loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final gamesAsync = ref.watch(premiumGamesProvider(widget.type));
    final controlExtent = _controlExtent(context);
    final topContentInset = _topContentInset(context, controlExtent);

    return GlassFullScreenPage(
      key: e2eKey(E2eIds.premiumGamesRoot),
      backgroundColor: context.colors.background,
      includeContentSafeArea: false,
      topOverlayPadding: const EdgeInsets.only(top: 4),
      topOverlay: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: ResponsiveHelper.contentMaxWidth,
          ),
          child: _buildAppBar(controlExtent),
        ),
      ),
      content: gamesAsync.when(
        loading: () => const _LoadingState(),
        error:
            (error, _) => _ErrorState(
              error: error.toString(),
              onRetry:
                  () =>
                      ref
                          .read(premiumGamesProvider(widget.type).notifier)
                          .loadGames(),
            ),
        data: (state) {
          if (state.games.isEmpty) {
            return _EmptyState(type: widget.type);
          }

          final isTablet = ResponsiveHelper.isTablet;
          final horizontalPadding = ResponsiveHelper.adaptive(
            phone: 16.sp,
            tablet: 24.sp,
          );
          final itemCount = state.games.length + (state.isLoadingMore ? 1 : 0);

          return RefreshIndicator(
            color: kPrimaryColor,
            backgroundColor: context.colors.surface,
            edgeOffset: topContentInset,
            onRefresh:
                () =>
                    ref
                        .read(premiumGamesProvider(widget.type).notifier)
                        .refresh(),
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: ResponsiveHelper.contentMaxWidth,
                ),
                child:
                    isTablet
                        ? GridView.builder(
                          controller: _scrollController,
                          padding: EdgeInsets.fromLTRB(
                            horizontalPadding,
                            topContentInset,
                            horizontalPadding,
                            _bottomContentInset(context),
                          ),
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount:
                                    ResponsiveHelper.tabletGridColumns,
                                crossAxisSpacing: 16.sp,
                                mainAxisSpacing: 16.sp,
                                childAspectRatio:
                                    ResponsiveHelper.isLandscape ? 2.2 : 1.8,
                              ),
                          itemCount: itemCount,
                          itemBuilder: (context, index) {
                            if (index == state.games.length) {
                              return _LoadingMoreIndicator();
                            }

                            final game = state.games[index];
                            return TwicGameCard(
                              game: game,
                              allGames: state.games,
                              gameIndex: index,
                              animationIndex: index,
                            );
                          },
                        )
                        : ListView.builder(
                          controller: _scrollController,
                          padding: EdgeInsets.fromLTRB(
                            horizontalPadding,
                            topContentInset,
                            horizontalPadding,
                            _bottomContentInset(context),
                          ),
                          itemCount: itemCount,
                          itemBuilder: (context, index) {
                            if (index == state.games.length) {
                              return _LoadingMoreIndicator();
                            }

                            final game = state.games[index];
                            return TwicGameCard(
                              game: game,
                              allGames: state.games,
                              gameIndex: index,
                              animationIndex: index,
                            );
                          },
                        ),
              ),
            ),
          );
        },
      ),
    );
  }

  double _controlExtent(BuildContext context) {
    final scaledLabelHeight = MediaQuery.textScalerOf(context).scale(16);
    final dynamicExtent = scaledLabelHeight + 28;
    return dynamicExtent < 48 ? 48 : dynamicExtent;
  }

  double _topContentInset(BuildContext context, double controlExtent) {
    return MediaQuery.viewPaddingOf(context).top + 4 + controlExtent + 6 + 12;
  }

  double _bottomContentInset(BuildContext context) {
    final media = MediaQuery.of(context);
    return media.viewPadding.bottom + media.viewInsets.bottom + 24.sp;
  }

  Widget _buildAppBar(double controlExtent) {
    final filter = ref.watch(premiumGamesFilterProvider(widget.type));
    final hasActiveFilters = filter.hasActiveFilters;
    final filterLabel = hasActiveFilters ? 'Filters, active' : 'Filters';

    void openFilters() => _showFilterDialog();

    return GlassIslandTopBar(
      topPadding: 0,
      height: controlExtent,
      horizontalPadding: ResponsiveHelper.adaptive(phone: 12, tablet: 24),
      leading: GlassBackButton(
        onPressed: () {
          HapticFeedbackService.buttonPress();
          Navigator.pop(context);
        },
        size: controlExtent,
      ),
      title: GlassTitleChip(
        label: _getTitle(),
        height: controlExtent,
        maxWidth: 210.w,
      ),
      trailing: [
        Semantics(
          label: filterLabel,
          button: true,
          onTap: openFilters,
          child: ExcludeSemantics(
            child: KeyedSubtree(
              key: e2eKey(E2eIds.premiumGamesFilterButton),
              child: GlassBadge(
                count: hasActiveFilters ? 1 : 0,
                backgroundColor: kPrimaryColor,
                child: GlassIconButton(
                  icon: Icon(
                    Icons.tune_rounded,
                    color:
                        hasActiveFilters
                            ? kPrimaryColor
                            : context.colors.iconPrimary,
                  ),
                  onPressed: openFilters,
                  size: controlExtent,
                  iconSize: 20,
                  useOwnLayer: true,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  String _getTitle() {
    switch (widget.type) {
      case PremiumGamesType.favorites:
        return 'Favorite Games';
      case PremiumGamesType.countrymen:
        return 'Countrymen Games';
    }
  }

  Future<void> _showFilterDialog() async {
    HapticFeedbackService.buttonPress();
    final currentFilter = ref.read(premiumGamesFilterProvider(widget.type));

    final newFilter = await showPremiumGamesFilterDialog(
      context: context,
      type: widget.type,
      currentFilter: currentFilter,
    );

    if (newFilter != null && mounted) {
      ref
          .read(premiumGamesProvider(widget.type).notifier)
          .applyFilter(newFilter);
    }
  }
}

class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 32.sp,
            height: 32.sp,
            child: const CircularProgressIndicator(
              color: kPrimaryColor,
              strokeWidth: 2.5,
            ),
          ),
          SizedBox(height: 16.sp),
          Text(
            'Loading games...',
            style: AppTypography.textSmMedium.copyWith(
              color: context.colors.textPrimary.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }
}

class _LoadingMoreIndicator extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 24.sp),
      child: Center(
        child: SizedBox(
          width: 24.sp,
          height: 24.sp,
          child: const CircularProgressIndicator(
            color: kPrimaryColor,
            strokeWidth: 2,
          ),
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.error, required this.onRetry});

  final String error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(32.sp),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline_rounded,
              color: context.colors.textPrimary.withValues(alpha: 0.4),
              size: 48.ic,
            ),
            SizedBox(height: 16.sp),
            Text(
              'Something went wrong',
              style: AppTypography.textMdMedium.copyWith(
                color: context.colors.textPrimary,
              ),
            ),
            SizedBox(height: 8.sp),
            Text(
              error,
              style: AppTypography.textSmRegular.copyWith(
                color: context.colors.textPrimary.withValues(alpha: 0.5),
              ),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 24.sp),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(
                backgroundColor: kPrimaryColor,
                foregroundColor: kBlackColor,
                padding: EdgeInsets.symmetric(
                  horizontal: 24.sp,
                  vertical: 12.sp,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8.br),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.type});

  final PremiumGamesType type;

  @override
  Widget build(BuildContext context) {
    final motionDuration = GlassMotion.resolveDuration(context, 300.ms);
    final (icon, title, subtitle) = switch (type) {
      PremiumGamesType.favorites => (
        Icons.star_outline_rounded,
        'No favorite games yet',
        'Games from your favorite players will appear here',
      ),
      PremiumGamesType.countrymen => (
        Icons.flag_outlined,
        'No countrymen games yet',
        'Games from players in your country will appear here',
      ),
    };

    return Center(
      child: Padding(
        padding: EdgeInsets.all(32.sp),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80.sp,
              height: 80.sp,
              decoration: BoxDecoration(
                color: context.colors.surface,
                shape: BoxShape.circle,
                border: Border.all(color: context.colors.divider, width: 1),
              ),
              child: Center(
                child: Icon(
                  icon,
                  color: context.colors.textPrimary.withValues(alpha: 0.4),
                  size: 36.ic,
                ),
              ),
            ),
            SizedBox(height: 24.sp),
            Text(
              title,
              style: AppTypography.textMdMedium.copyWith(
                color: context.colors.textPrimary,
              ),
            ),
            SizedBox(height: 8.sp),
            Text(
              subtitle,
              style: AppTypography.textSmRegular.copyWith(
                color: context.colors.textPrimary.withValues(alpha: 0.5),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ).animate().fadeIn(duration: motionDuration),
      ),
    );
  }
}
