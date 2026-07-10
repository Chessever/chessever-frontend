import 'dart:async';

import 'package:chessever2/e2e/e2e_ids.dart';
import 'package:chessever2/main.dart' show routeObserver;
import 'package:chessever2/screens/chessboard/provider/chess_board_screen_provider_new.dart';
import 'package:chessever2/screens/chessboard/widgets/chess_board_from_fen_new.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_list_view_mode_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_provider.dart';
import 'package:chessever2/screens/group_event/providers/countryman_games_tour_screen_provider.dart';
import 'package:chessever2/screens/group_event/widget/empty_widget.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/game_card.dart';
import 'package:chessever2/screens/group_event/widget/tour_loading_widget.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/games_tour_content_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/game_card_wrapper/game_card_wrapper_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/game_card_wrapper/live_game_card_provider.dart';
import 'package:chessever2/widgets/paywall/premium_paywall_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/svg_asset.dart';
import 'package:chessever2/utils/tablet_safe_menu.dart';
import 'package:flutter_svg/svg.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:chessever2/widgets/liquid_glass/glass_back_button.dart';
import 'package:chessever2/widgets/liquid_glass/glass_full_screen_page.dart';
import 'package:chessever2/widgets/liquid_glass/glass_island_top_bar.dart';
import 'package:chessever2/widgets/liquid_glass/glass_motion.dart';
import 'package:chessever2/widgets/liquid_glass/glass_title_chip.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

class CountrymanGamesScreen extends StatelessWidget {
  const CountrymanGamesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controlExtent = _controlExtent(context);
    final topContentInset =
        MediaQuery.viewPaddingOf(context).top + 4 + controlExtent + 6 + 8;

    return GlassFullScreenPage(
      key: e2eKey(E2eIds.countrymenRoot),
      backgroundColor: context.colors.background,
      includeContentSafeArea: false,
      topOverlayPadding: const EdgeInsets.only(top: 4),
      topOverlay: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth:
                ResponsiveHelper.isTablet
                    ? ResponsiveHelper.contentMaxWidth
                    : double.infinity,
          ),
          child: const CountrymanGamesAppBar(),
        ),
      ),
      content: CountrymanGamesList(topContentInset: topContentInset),
    );
  }

  double _controlExtent(BuildContext context) {
    final scaledLabelHeight = MediaQuery.textScalerOf(context).scale(16);
    final dynamicExtent = scaledLabelHeight + 28;
    return dynamicExtent < 48 ? 48 : dynamicExtent;
  }
}

class CountrymanGamesList extends ConsumerStatefulWidget {
  const CountrymanGamesList({required this.topContentInset, super.key});

  final double topContentInset;

  @override
  ConsumerState<CountrymanGamesList> createState() =>
      _CountrymanGamesListState();
}

class _CountrymanGamesListState extends ConsumerState<CountrymanGamesList>
    with WidgetsBindingObserver, RouteAware {
  static const Duration _scrollIdleDelay = Duration(milliseconds: 180);

  Timer? _scrollIdleTimer;
  bool _routeSubscribed = false;
  bool _routeIsCurrent = true;
  bool _appIsResumed = true;
  bool _liveCardsPausedForScroll = false;
  late final StateController<Set<String>> _liveGameCardsPauseReasons;

  String get _liveCardsPauseReason => 'countryman_games_scroll_$hashCode';
  // Keep the scrollable subtree mounted while a game route covers this screen
  // so returning from the board preserves list state.
  bool get _isActiveOnScreen => _routeIsCurrent;

  @override
  void initState() {
    super.initState();
    _liveGameCardsPauseReasons = ref.read(
      liveGameCardsPauseReasonsProvider.notifier,
    );
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_routeSubscribed) return;
    final route = ModalRoute.of(context);
    if (route == null) return;
    routeObserver.subscribe(this, route);
    _routeSubscribed = true;
    _routeIsCurrent = route.isCurrent;
  }

  @override
  void dispose() {
    if (_routeSubscribed) {
      routeObserver.unsubscribe(this);
    }
    WidgetsBinding.instance.removeObserver(this);
    _scrollIdleTimer?.cancel();
    _setLiveCardsPausedForScroll(false);
    super.dispose();
  }

  @override
  void didPush() {
    _setRouteActive(true);
  }

  @override
  void didPopNext() {
    _setRouteActive(true);
  }

  @override
  void didPushNext() {
    _setRouteActive(false);
  }

  @override
  void didPop() {
    _setRouteActive(false);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    _setAppResumed(state == AppLifecycleState.resumed);
  }

  void _setRouteActive(bool isActive) {
    if (!mounted) return;
    if (_routeIsCurrent != isActive) {
      setState(() => _routeIsCurrent = isActive);
    }
    if (!isActive) {
      _stopLiveCardsForHiddenRoute();
    }
  }

  void _setAppResumed(bool isResumed) {
    if (!mounted) return;
    if (_appIsResumed != isResumed) {
      setState(() => _appIsResumed = isResumed);
    }
    if (!isResumed) {
      _stopLiveCardsForHiddenRoute();
    }
  }

  void _openChessBoard(List<GamesTourModel> updatedGames, int index) {
    if (!mounted) return;
    ref
        .read(gameCardWrapperProvider)
        .navigateToChessBoard(
          context: context,
          orderedGames: updatedGames,
          gameIndex: index,
          onReturnFromChessboard: (_) {},
          viewSource: ChessboardView.countryman,
        );
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    if (notification.metrics.axis != Axis.vertical) return false;

    if (notification is ScrollEndNotification) {
      _scheduleLiveCardsIdle();
      return false;
    }

    if (notification is UserScrollNotification &&
        notification.direction == ScrollDirection.idle) {
      _scheduleLiveCardsIdle();
      return false;
    }

    if (notification is ScrollStartNotification ||
        notification is ScrollUpdateNotification ||
        notification is OverscrollNotification ||
        notification is UserScrollNotification) {
      _markLiveCardsScrolling();
    }

    return false;
  }

  void _markLiveCardsScrolling() {
    _setLiveCardsPausedForScroll(true);
    _scrollIdleTimer?.cancel();
    _scrollIdleTimer = Timer(_scrollIdleDelay, _markLiveCardsIdle);
  }

  void _scheduleLiveCardsIdle() {
    _scrollIdleTimer?.cancel();
    _scrollIdleTimer = Timer(_scrollIdleDelay, _markLiveCardsIdle);
  }

  void _markLiveCardsIdle() {
    _setLiveCardsPausedForScroll(false);
  }

  void _stopLiveCardsForHiddenRoute() {
    _scrollIdleTimer?.cancel();
    _setLiveCardsPausedForScroll(false);
  }

  void _setLiveCardsPausedForScroll(bool paused) {
    if (_liveCardsPausedForScroll == paused) return;
    _liveCardsPausedForScroll = paused;
    setLiveGameCardsPausedWithNotifier(
      _liveGameCardsPauseReasons,
      reason: _liveCardsPauseReason,
      paused: paused,
    );
  }

  @override
  Widget build(BuildContext context) {
    final gamesListViewMode = ref.watch(gamesListViewModeProvider);
    final shouldStream = ref.watch(shouldStreamProvider);
    final streamEnabled = shouldStream && _isActiveOnScreen && _appIsResumed;

    return ref
        .watch(countrymanGamesTourScreenProvider)
        .when(
          data: (data) {
            if (data.gamesTourModels.isEmpty) {
              return Padding(
                padding: EdgeInsets.only(top: widget.topContentInset),
                child: EmptyWidget(
                  title:
                      "No games available yet. Check back soon or set a\nreminder for updates.",
                ),
              );
            }

            final horizontalPadding = ResponsiveHelper.adaptive(
              phone: 20.sp,
              tablet: 32.sp,
            );
            final isTablet = ResponsiveHelper.isTablet;
            final bottomPadding = MediaQuery.of(context).viewPadding.bottom;

            Widget buildGameItem(int index) {
              final baseGame = data.gamesTourModels[index];
              return Consumer(
                builder: (context, ref, _) {
                  final liveBatchKey = liveContextBatchKeyForGame(
                    game: baseGame,
                    contextGames: data.gamesTourModels,
                    scopePrefix: 'countryman_screen',
                  );
                  final game = watchLiveGame(
                    ref,
                    baseGame,
                    batchKey: liveBatchKey,
                    streamEnabled: streamEnabled,
                  );
                  final allowStockfishFallback =
                      streamEnabled && !ref.watch(liveGameCardsPausedProvider);
                  final updatedGames = List<GamesTourModel>.from(
                    data.gamesTourModels,
                  );
                  if (index >= 0 && index < updatedGames.length) {
                    updatedGames[index] = game;
                  }

                  return gamesListViewMode == GamesListViewMode.chessBoard
                      ? ChessBoardFromFENNew(
                        pinnedIds: data.pinnedGamedIs,
                        onPinToggle: (gamesTourModel) async {
                          await ref
                              .read(countrymanGamesTourScreenProvider.notifier)
                              .togglePinGame(gamesTourModel.gameId);
                        },
                        onChanged: () async {
                          final hasPremium = await requirePremiumGuard(
                            context,
                            ref,
                          );
                          if (!hasPremium) return;
                          _openChessBoard(updatedGames, index);
                        },
                        gamesTourModel: game,
                        allowStockfishFallback: allowStockfishFallback,
                      )
                      : GameCard(
                        onTap: () async {
                          final hasPremium = await requirePremiumGuard(
                            context,
                            ref,
                          );
                          if (!hasPremium) return;
                          _openChessBoard(updatedGames, index);
                        },
                        matchComparison: MatchWithComparison(
                          game: game,
                          comparison: MatchComparison.sameOrder,
                        ),
                        allowStockfishFallback: allowStockfishFallback,
                        pinnedIds: data.pinnedGamedIs,
                        onPinToggle: (gamesTourModel) async {
                          await ref
                              .read(countrymanGamesTourScreenProvider.notifier)
                              .togglePinGame(gamesTourModel.gameId);
                        },
                      );
                },
              );
            }

            return NotificationListener<ScrollNotification>(
              onNotification: _handleScrollNotification,
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: ResponsiveHelper.contentMaxWidth,
                  ),
                  child:
                      isTablet
                          ? GridView.builder(
                            padding: EdgeInsets.only(
                              left: horizontalPadding,
                              right: horizontalPadding,
                              top: widget.topContentInset + 12.sp,
                              bottom: bottomPadding + 24.sp,
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
                            itemCount: data.gamesTourModels.length,
                            itemBuilder:
                                (context, index) => buildGameItem(index),
                          )
                          : ListView.builder(
                            padding: EdgeInsets.only(
                              left: horizontalPadding,
                              right: horizontalPadding,
                              top: widget.topContentInset + 12.sp,
                              bottom: bottomPadding + 24.sp,
                            ),
                            itemCount: data.gamesTourModels.length,
                            itemBuilder: (context, index) {
                              return Padding(
                                padding: EdgeInsets.only(bottom: 12.sp),
                                child: buildGameItem(index),
                              );
                            },
                          ),
                ),
              ),
            );
          },
          error:
              (_, __) => Padding(
                padding: EdgeInsets.only(top: widget.topContentInset),
                child: const _CountrymanGamesErrorState(),
              ),
          loading:
              () => Padding(
                padding: EdgeInsets.only(top: widget.topContentInset),
                child: const TourLoadingWidget(),
              ),
        );
  }
}

class CountrymanGamesAppBar extends ConsumerStatefulWidget {
  const CountrymanGamesAppBar({super.key});

  @override
  ConsumerState<CountrymanGamesAppBar> createState() =>
      _GamesAppBarWidgetState();
}

class _GamesAppBarWidgetState extends ConsumerState<CountrymanGamesAppBar> {
  bool isSearching = false;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  late final GlobalKey _menuKey;

  @override
  void initState() {
    _menuKey = GlobalKey();
    super.initState();
  }

  void _startSearch() {
    setState(() => isSearching = true);
    _focusNode.requestFocus();
  }

  Future<void> _closeSearch() async {
    setState(() => isSearching = false);
    _searchController.clear();
    await ref.read(countrymanGamesTourScreenProvider.notifier).refreshGames();
    _focusNode.unfocus();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _openMenu() {
    final RenderBox? renderBox =
        _menuKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    final offset = renderBox.localToGlobal(Offset.zero);
    showTabletSafeMenu(
      context: context,
      position: RelativeRect.fromLTRB(
        offset.dx,
        offset.dy + renderBox.size.height,
        offset.dx + renderBox.size.width,
        offset.dy,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.br)),
      color: context.colors.surface,
      items: <PopupMenuEntry<String>>[
        PopupMenuItem<String>(
          value: 'Unpin all',
          child: InkWell(
            onTap: () {
              Navigator.pop(context);
              ref
                  .read(countrymanGamesTourScreenProvider.notifier)
                  .unpinAllGames();
            },
            child: SizedBox(
              width: 200,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Unpin all',
                    style: AppTypography.textXsMedium.copyWith(
                      color: context.colors.textPrimary,
                    ),
                  ),
                  SvgPicture.asset(SvgAsset.unpine, height: 13.h, width: 13.w),
                ],
              ),
            ),
          ),
        ),
        PopupMenuDivider(
          height: 1.h,
          thickness: 0.5.w,
          color: context.colors.divider,
        ),
        PopupMenuItem<String>(
          value: 'active',
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Active games on top',
                style: AppTypography.textXsMedium.copyWith(
                  color: context.colors.textPrimary,
                ),
              ),
              SvgPicture.asset(SvgAsset.active, height: 13.h, width: 13.w),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final controlExtent = _controlExtent(context);
    final reduceMotion = GlassMotion.reduceMotion(context);

    if (isSearching) {
      return GlassIslandTopBar(
        key: const ValueKey('search_mode'),
        topPadding: 0,
        height: controlExtent,
        leading: GlassBackButton(
          onPressed: _closeSearch,
          semanticLabel: 'Close search',
        ),
        center: GlassSearchBar(
          key: e2eKey(E2eIds.countrymenSearchField),
          controller: _searchController,
          focusNode: _focusNode,
          placeholder: 'Search',
          onChanged:
              ref.read(countrymanGamesTourScreenProvider.notifier).searchGames,
          useOwnLayer: true,
          height: controlExtent,
          showsCancelButton: false,
          autofocus: true,
        ),
        trailing: [
          Semantics(
            label: 'Clear and close search',
            button: true,
            onTap: _closeSearch,
            child: ExcludeSemantics(
              child: GlassIconButton(
                icon: Icon(Icons.close, color: context.colors.iconPrimary),
                onPressed: _closeSearch,
                size: 48,
                iconSize: 18,
                interactionScale: reduceMotion ? 1 : 0.95,
                anchorStretch: !reduceMotion,
                useOwnLayer: true,
              ),
            ),
          ),
        ],
      );
    }

    return GlassIslandTopBar(
      key: const ValueKey('app_bar_mode'),
      topPadding: 0,
      height: controlExtent,
      leading: const GlassBackButton(),
      title: GlassTitleChip(label: 'Countrymen Games', height: controlExtent),
      trailing: [
        Semantics(
          label: 'Search countrymen games',
          button: true,
          onTap: _startSearch,
          child: ExcludeSemantics(
            child: GlassIconButton(
              key: e2eKey(E2eIds.countrymenSearchToggle),
              icon: Icon(Icons.search, color: context.colors.iconPrimary),
              onPressed: _startSearch,
              size: 48,
              iconSize: 20,
              interactionScale: reduceMotion ? 1 : 0.95,
              anchorStretch: !reduceMotion,
              useOwnLayer: true,
            ),
          ),
        ),
        Semantics(
          label: 'Change games view',
          button: true,
          onTap: _toggleViewMode,
          child: ExcludeSemantics(
            child: GlassIconButton(
              icon: Icon(
                Icons.grid_view_rounded,
                color: context.colors.iconPrimary,
              ),
              onPressed: _toggleViewMode,
              size: 48,
              iconSize: 18,
              interactionScale: reduceMotion ? 1 : 0.95,
              anchorStretch: !reduceMotion,
              useOwnLayer: true,
            ),
          ),
        ),
        KeyedSubtree(
          key: _menuKey,
          child: Semantics(
            label: 'More countrymen game options',
            button: true,
            onTap: _openMenu,
            child: ExcludeSemantics(
              child: GlassIconButton(
                icon: Icon(Icons.more_horiz, color: context.colors.iconPrimary),
                onPressed: _openMenu,
                size: 48,
                iconSize: 20,
                interactionScale: reduceMotion ? 1 : 0.95,
                anchorStretch: !reduceMotion,
                useOwnLayer: true,
              ),
            ),
          ),
        ),
      ],
    );
  }

  double _controlExtent(BuildContext context) {
    final scaledLabelHeight = MediaQuery.textScalerOf(context).scale(16);
    final dynamicExtent = scaledLabelHeight + 28;
    return dynamicExtent < 48 ? 48 : dynamicExtent;
  }

  void _toggleViewMode() {
    ref.read(gamesListViewModeSwitcher).toggleViewMode();
  }
}

class _CountrymanGamesErrorState extends StatelessWidget {
  const _CountrymanGamesErrorState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline_rounded,
              size: 40,
              color: context.colors.iconSecondary,
            ),
            const SizedBox(height: 12),
            Text(
              'Something went wrong',
              textAlign: TextAlign.center,
              style: AppTypography.textSmMedium.copyWith(
                color: context.colors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
