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
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

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

    return Scaffold(
      key: e2eKey(E2eIds.premiumGamesRoot),
      backgroundColor: context.colors.surface,
      appBar: _buildAppBar(),
      body: gamesAsync.when(
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
            backgroundColor: kBlackColor,
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
                          padding: EdgeInsets.all(horizontalPadding),
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
                          padding: EdgeInsets.all(horizontalPadding),
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

  PreferredSizeWidget _buildAppBar() {
    final filter = ref.watch(premiumGamesFilterProvider(widget.type));
    final hasActiveFilters = filter.hasActiveFilters;

    return AppBar(
      backgroundColor: kBlackColor,
      surfaceTintColor: Colors.transparent,
      leading: IconButton(
        onPressed: () {
          HapticFeedbackService.buttonPress();
          Navigator.pop(context);
        },
        icon: Icon(
          Icons.arrow_back_ios_new_rounded,
          color: context.colors.textPrimary,
          size: 20.ic,
        ),
      ),
      title: Text(
        _getTitle(),
        style: AppTypography.textMdBold.copyWith(color: context.colors.textPrimary),
      ),
      centerTitle: true,
      actions: [
        Stack(
          children: [
            IconButton(
              key: e2eKey(E2eIds.premiumGamesFilterButton),
              onPressed: _showFilterDialog,
              icon: Icon(
                Icons.tune_rounded,
                color: hasActiveFilters ? kPrimaryColor : context.colors.textPrimary,
                size: 22.ic,
              ),
            ),
            if (hasActiveFilters)
              Positioned(
                right: 10.sp,
                top: 10.sp,
                child: Container(
                  width: 8.sp,
                  height: 8.sp,
                  decoration: const BoxDecoration(
                    color: kPrimaryColor,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
          ],
        ),
        SizedBox(width: 4.sp),
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
              style: AppTypography.textMdMedium.copyWith(color: context.colors.textPrimary),
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
                color: kBlackColor,
                shape: BoxShape.circle,
                border: Border.all(
                  color: context.colors.surfaceRecessed.withValues(alpha: 0.3),
                  width: 1,
                ),
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
              style: AppTypography.textMdMedium.copyWith(color: context.colors.textPrimary),
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
        ).animate().fadeIn(duration: 300.ms),
      ),
    );
  }
}
