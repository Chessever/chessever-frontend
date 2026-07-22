import 'package:chessever2/repository/gamebase/discovery/discovery_models.dart';
import 'package:chessever2/repository/gamebase/discovery/discovery_providers.dart';
import 'package:chessever2/screens/calendar/calendar_screen.dart';
import 'package:chessever2/screens/chessboard/provider/chess_board_screen_provider_new.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_list_view_mode_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/game_card_wrapper/game_card_wrapper_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/game_card_wrapper/game_card_wrapper_widget.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/game_card_wrapper/grid_game_card_wrapper_widget.dart';
import 'package:chessever2/screens/discover/discover_providers.dart';
import 'package:chessever2/screens/home/widget/bottom_nav_bar.dart';
import 'package:chessever2/screens/library/discovery/miniatures_tab.dart';
import 'package:chessever2/screens/library/discovery/studies_tab.dart';
import 'package:chessever2/screens/library/discovery/study_chapters_screen.dart';
import 'package:chessever2/screens/group_event/smart_event/smart_aggregate_event_provider.dart';
import 'package:chessever2/screens/group_event/smart_event/smart_event_screen.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/app_button.dart';
import 'package:chessever2/widgets/event_card/smart_event_card.dart';
import 'package:chessever2/widgets/skeleton_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// The Discover surface — a Netflix-style vertical feed of horizontal rails that
/// replaces the old month-grid Calendar tab. It gathers our own curated content
/// in one place: smart events (per rating tier), studies, and miniatures. The
/// tournament calendar lives on here as a top-right shortcut.
class DiscoverScreen extends ConsumerStatefulWidget {
  const DiscoverScreen({super.key});

  @override
  ConsumerState<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends ConsumerState<DiscoverScreen> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToTop() {
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
  }

  void _openCalendar() {
    HapticFeedbackService.light();
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const _CalendarHost()),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<BottomNavBarReTapRequest>(bottomNavBarReTapRequestProvider, (
      previous,
      next,
    ) {
      if (next.item == BottomNavBarItem.discover) {
        _scrollToTop();
      }
    });

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () async {
          HapticFeedbackService.medium();
          ref.invalidate(discoverCurrentEventsProvider);
          ref.invalidate(studiesListProvider);
          ref.invalidate(miniaturesListProvider);
        },
        color: kPrimaryColor,
        backgroundColor: context.colors.surface,
        displacement: 60.h,
        strokeWidth: 3.w,
        child: ListView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          padding: EdgeInsets.only(
            top: 20.h + MediaQuery.of(context).viewPadding.top,
            bottom: 24.h + MediaQuery.of(context).viewPadding.bottom,
          ),
          children: [
            _Header(onCalendarTap: _openCalendar),
            SizedBox(height: 16.h),
            const _SmartEventsRail(),
            const _StudiesRail(),
            const _MiniaturesSection(),
          ],
        ),
      ),
    );
  }
}

// ── Header ──────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  const _Header({required this.onCalendarTap});

  final VoidCallback onCalendarTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 16.w),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Discover',
                  style: AppTypography.textXlBold.copyWith(
                    color: context.colors.textPrimary,
                  ),
                ),
                SizedBox(height: 2.h),
                Text(
                  'Smart events, studies & miniatures',
                  style: AppTypography.textSmRegular.copyWith(
                    color: context.colors.textPrimaryMuted,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(width: 12.w),
          _CalendarButton(onTap: onCalendarTap),
        ],
      ),
    );
  }
}

class _CalendarButton extends StatelessWidget {
  const _CalendarButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TappableScale(
      onTap: onTap,
      child: Container(
        height: 44.h,
        padding: EdgeInsets.symmetric(horizontal: 12.w),
        decoration: BoxDecoration(
          color: context.colors.surface,
          borderRadius: BorderRadius.circular(12.br),
          border: Border.all(color: context.colors.divider, width: 1.w),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.calendar_month_rounded,
              size: 18.ic,
              color: kPrimaryColor,
            ),
            SizedBox(width: 6.w),
            Text(
              'Calendar',
              style: AppTypography.textXsMedium.copyWith(
                color: context.colors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Section header ──────────────────────────────────────────────────────────

class _RailHeader extends StatelessWidget {
  const _RailHeader({required this.title, this.onSeeAll});

  final String title;
  final VoidCallback? onSeeAll;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16.w, 20.h, 8.w, 10.h),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: AppTypography.textMdBold.copyWith(
                color: context.colors.textPrimary,
              ),
            ),
          ),
          if (onSeeAll != null)
            TextButton(
              onPressed: onSeeAll,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'See all',
                    style: AppTypography.textXsMedium.copyWith(
                      color: kPrimaryColor,
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 16.ic,
                    color: kPrimaryColor,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ── Smart events rail ───────────────────────────────────────────────────────

class _SmartEventsRail extends ConsumerWidget {
  const _SmartEventsRail();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cards = ref.watch(discoverSmartTierCardsProvider);
    final eventsAsync = ref.watch(discoverCurrentEventsProvider);

    // Hide the whole section only when the load finished with no tiers.
    if (cards.isEmpty && !eventsAsync.isLoading) return const SizedBox.shrink();

    final cardWidth = MediaQuery.sizeOf(context).width * 0.82;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _RailHeader(title: 'Smart events'),
        SizedBox(
          height: 96.h,
          child: cards.isEmpty
              ? _RailSkeleton(itemWidth: cardWidth, itemHeight: 88.h)
              : ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: EdgeInsets.symmetric(horizontal: 16.w),
                  physics: const BouncingScrollPhysics(),
                  itemCount: cards.length,
                  separatorBuilder: (_, __) => SizedBox(width: 12.w),
                  itemBuilder: (context, i) => SizedBox(
                    width: cardWidth,
                    child: _SmartRailCard(data: cards[i]),
                  ),
                ),
        ),
      ],
    );
  }
}

class _SmartRailCard extends ConsumerWidget {
  const _SmartRailCard({required this.data});

  final SmartEventCardData data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hidden = ref.watch(
      smartEventDismissedEventIdsProvider(data.request.dismissScopeId),
    );
    final visibleCount =
        data.request.events.where((e) => !hidden.contains(e.id)).length;

    return SmartEventCard(
      tierLabel: data.request.tierLabel,
      minElo: data.request.minElo,
      liveCount: visibleCount,
      avgElo: data.avgElo,
      titleSuffix: data.request.titleSuffix,
      caption: data.request.caption,
      countSingular: data.request.countSingular,
      countPlural: data.request.countPlural,
      accentColor: smartEventAccentColor(data.request.scopeId),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => SmartEventScreen(request: data.request),
        ),
      ),
    );
  }
}

// ── Studies rail ────────────────────────────────────────────────────────────

class _StudiesRail extends ConsumerWidget {
  const _StudiesRail();

  void _seeAll(BuildContext context) {
    HapticFeedbackService.light();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const _FullTabPage(
          title: 'Studies',
          child: StudiesTab(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final listAsync = ref.watch(studiesListProvider);

    return listAsync.when(
      loading: () => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _RailHeader(title: 'Studies'),
          SizedBox(
            height: 150.h,
            child: _RailSkeleton(itemWidth: 168.w, itemHeight: 150.h),
          ),
        ],
      ),
      error: (e, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _RailHeader(title: 'Studies'),
          _RailNotice(
            message: "Couldn't load studies",
            onRetry: () => ref.invalidate(studiesListProvider),
          ),
        ],
      ),
      data: (page) {
        if (page.items.isEmpty) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _RailHeader(title: 'Studies'),
              const _RailNotice(message: 'No studies yet — pull to refresh'),
            ],
          );
        }
        final items = page.items.take(12).toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _RailHeader(title: 'Studies', onSeeAll: () => _seeAll(context)),
            SizedBox(
              height: 150.h,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: EdgeInsets.symmetric(horizontal: 16.w),
                physics: const BouncingScrollPhysics(),
                itemCount: items.length,
                separatorBuilder: (_, __) => SizedBox(width: 12.w),
                itemBuilder: (context, i) => _StudyRailCard(
                  study: items[i],
                ).animate().fadeIn(
                      duration: 220.ms,
                      delay: Duration(milliseconds: (i % 8) * 30),
                    ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _StudyRailCard extends StatelessWidget {
  const _StudyRailCard({required this.study});

  final LichessStudy study;

  @override
  Widget build(BuildContext context) {
    final chapters = study.chapterCount == 1
        ? '1 chapter'
        : '${study.chapterCount} chapters';

    return TappableScale(
      onTap: () {
        HapticFeedbackService.cardTap();
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => StudyChaptersScreen(study: study)),
        );
      },
      child: Container(
        width: 168.w,
        padding: EdgeInsets.all(12.sp),
        decoration: BoxDecoration(
          color: context.colors.surface,
          borderRadius: BorderRadius.circular(14.br),
          border: Border.all(color: context.colors.divider, width: 1.w),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 38.h,
                  height: 38.h,
                  decoration: BoxDecoration(
                    color: kPrimaryColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10.br),
                  ),
                  child: Icon(
                    Icons.menu_book_rounded,
                    color: kPrimaryColor,
                    size: 20.ic,
                  ),
                ),
                const Spacer(),
                _QualityPill(score: study.credibilityScore),
              ],
            ),
            SizedBox(height: 10.h),
            Text(
              study.name,
              style: AppTypography.textSmMedium.copyWith(
                color: context.colors.textPrimary,
                height: 1.25,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const Spacer(),
            Text(
              chapters,
              style: AppTypography.textXsRegular.copyWith(
                color: context.colors.textPrimaryMuted,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

class _QualityPill extends StatelessWidget {
  const _QualityPill({required this.score});

  final double score;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 7.w, vertical: 3.h),
      decoration: BoxDecoration(
        color: kPrimaryColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8.br),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.star_rounded, size: 12.ic, color: kPrimaryColor),
          SizedBox(width: 3.w),
          Text(
            studyQualityLabel(score),
            style: AppTypography.textXxsBold.copyWith(color: kPrimaryColor),
          ),
        ],
      ),
    );
  }
}

// ── Miniatures section ──────────────────────────────────────────────────────

/// Miniatures render with the app's real game cards, honouring the user's
/// "Games View Mode" setting (grid / board list / traditional card) — the same
/// widgets and layout the Games tab uses, so it feels native, not bespoke.
class _MiniaturesSection extends ConsumerWidget {
  const _MiniaturesSection();

  static const _maxItems = 6;

  void _seeAll(BuildContext context) {
    HapticFeedbackService.light();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const _FullTabPage(
          title: 'Miniatures',
          child: MiniaturesTab(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final listAsync = ref.watch(miniaturesListProvider);

    return listAsync.when(
      loading: () => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _RailHeader(title: 'Miniatures'),
          SizedBox(
            height: 118.h,
            child: _RailSkeleton(itemWidth: 230.w, itemHeight: 118.h),
          ),
        ],
      ),
      error: (e, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _RailHeader(title: 'Miniatures'),
          _RailNotice(
            message: "Couldn't load miniatures",
            onRetry: () => ref.invalidate(miniaturesListProvider),
          ),
        ],
      ),
      data: (page) {
        if (page.items.isEmpty) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _RailHeader(title: 'Miniatures'),
              const _RailNotice(message: 'No miniatures yet — pull to refresh'),
            ],
          );
        }
        final items = page.items.take(_maxItems).toList();
        final models = [for (final m in items) m.toGamesTourModel()];
        final mode = ref.watch(gamesListViewModeProvider);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _RailHeader(title: 'Miniatures', onSeeAll: () => _seeAll(context)),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 16.w),
              child: _MiniatureGamesLayout(models: models, mode: mode),
            ),
          ],
        );
      },
    );
  }
}

/// Lays the miniature game cards out with the same widgets the Games tab uses,
/// switching on the persisted [GamesListViewMode]. Streaming/pins are off since
/// miniatures are static master-database games.
class _MiniatureGamesLayout extends ConsumerWidget {
  const _MiniatureGamesLayout({required this.models, required this.mode});

  final List<GamesTourModel> models;
  final GamesListViewMode mode;

  void _open(
    BuildContext context,
    WidgetRef ref,
    List<GamesTourModel> games,
    int i,
  ) {
    ref.read(gameCardWrapperProvider).navigateToChessBoard(
          context: context,
          orderedGames: games,
          gameIndex: i,
          onReturnFromChessboard: (_) {},
          viewSource: ChessboardView.tour,
          showGamebaseButton: true,
          disableGamebaseOverlayByDefault: true,
        );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (mode == GamesListViewMode.chessBoardGrid) {
      // Manual 2-column rows so each card self-sizes vertically (mirrors the
      // For You phone grid); a fixed-aspect GridView would clip the info block.
      return Column(
        children: [
          for (var r = 0; r < models.length; r += 2)
            Padding(
              padding: EdgeInsets.only(bottom: 12.h),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _gridCard(context, ref, r)),
                  SizedBox(width: 12.w),
                  Expanded(
                    child: r + 1 < models.length
                        ? _gridCard(context, ref, r + 1)
                        : const SizedBox.shrink(),
                  ),
                ],
              ),
            ),
        ],
      );
    }

    // gamesCard (traditional) + chessBoard (board list) both use the row card.
    final gamesData = GamesScreenModel(
      gamesTourModels: models,
      pinnedGamedIs: const <String>[],
    );
    return Column(
      children: [
        for (var i = 0; i < models.length; i++)
          Padding(
            padding: EdgeInsets.only(bottom: 12.h),
            child: GameCardWrapperWidget(
              key: ValueKey('mini_card_${models[i].gameId}'),
              game: models[i],
              gamesData: gamesData,
              gameIndex: i,
              isChessBoardVisible: mode == GamesListViewMode.chessBoard,
              viewSource: ChessboardView.tour,
              allowStockfishFallback: false,
              streamEnabled: false,
            ),
          ),
      ],
    );
  }

  Widget _gridCard(BuildContext context, WidgetRef ref, int i) {
    return GridGameCardWrapperWidget(
      key: ValueKey('mini_grid_${models[i].gameId}'),
      game: models[i],
      orderedGames: models,
      gameIndex: i,
      pinnedIds: const <String>[],
      onPinToggle: (_) {},
      allowStockfishFallback: false,
      streamEnabled: false,
      viewSource: ChessboardView.tour,
      onChangedWithLiveGames: (updated) => _open(context, ref, updated, i),
    );
  }
}

// ── Shared bits ─────────────────────────────────────────────────────────────

class _RailSkeleton extends StatelessWidget {
  const _RailSkeleton({required this.itemWidth, required this.itemHeight});

  final double itemWidth;
  final double itemHeight;

  @override
  Widget build(BuildContext context) {
    return SkeletonWidget(
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: 16.w),
        physics: const NeverScrollableScrollPhysics(),
        itemCount: 4,
        separatorBuilder: (_, __) => SizedBox(width: 12.w),
        itemBuilder: (context, i) => Container(
          width: itemWidth,
          height: itemHeight,
          decoration: BoxDecoration(
            color: context.colors.surface,
            borderRadius: BorderRadius.circular(14.br),
          ),
        ),
      ),
    );
  }
}

/// Visible in-rail state for empty / error, so a section never silently
/// vanishes — the user always sees the rail exists and can retry.
class _RailNotice extends StatelessWidget {
  const _RailNotice({required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.fromLTRB(16.w, 0, 16.w, 4.h),
      padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 16.h),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(14.br),
        border: Border.all(color: context.colors.divider, width: 1.w),
      ),
      child: Row(
        children: [
          Icon(
            Icons.info_outline_rounded,
            size: 18.ic,
            color: context.colors.textPrimaryMuted,
          ),
          SizedBox(width: 10.w),
          Expanded(
            child: Text(
              message,
              style: AppTypography.textSmRegular.copyWith(
                color: context.colors.textPrimaryMuted,
              ),
            ),
          ),
          if (onRetry != null) ...[
            SizedBox(width: 8.w),
            GestureDetector(
              onTap: onRetry,
              child: Text(
                'Retry',
                style: AppTypography.textSmMedium.copyWith(color: kPrimaryColor),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Hosts a full Discovery tab (Studies / Miniatures) as a pushed page with a
/// simple back-and-title bar, since the tabs themselves ship without a Scaffold.
class _FullTabPage extends StatelessWidget {
  const _FullTabPage({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.background,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(4.w, 4.h, 16.w, 4.h),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: Icon(
                      Icons.arrow_back_ios_new_rounded,
                      size: 20.ic,
                      color: context.colors.iconPrimary,
                    ),
                  ),
                  Text(
                    title,
                    style: AppTypography.textLgBold.copyWith(
                      color: context.colors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }
}

/// Wraps the preserved [CalendarScreen] with a floating back button so it works
/// as a pushed page (it was built as a bottom-nav root without a back affordance).
class _CalendarHost extends StatelessWidget {
  const _CalendarHost();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.background,
      body: Stack(
        children: [
          const CalendarScreen(),
          Positioned(
            top: MediaQuery.of(context).viewPadding.top + 8.h,
            left: 8.w,
            child: Material(
              color: context.colors.surface,
              shape: const CircleBorder(),
              elevation: 2,
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () => Navigator.of(context).maybePop(),
                child: Padding(
                  padding: EdgeInsets.all(8.sp),
                  child: Icon(
                    Icons.arrow_back_ios_new_rounded,
                    size: 18.ic,
                    color: context.colors.iconPrimary,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
