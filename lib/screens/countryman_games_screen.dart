import 'dart:async';

import 'package:chessever2/e2e/e2e_ids.dart';
import 'package:chessever2/main.dart' show routeObserver;
import 'package:chessever2/screens/chessboard/chess_board_screen_new.dart';
import 'package:chessever2/screens/chessboard/provider/chess_board_screen_provider_new.dart';
import 'package:chessever2/screens/chessboard/provider/game_pgn_stream_provider.dart';
import 'package:chessever2/screens/chessboard/widgets/chess_board_from_fen_new.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_list_view_mode_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_provider.dart';
import 'package:chessever2/screens/group_event/providers/countryman_games_tour_screen_provider.dart';
import 'package:chessever2/screens/group_event/widget/empty_widget.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/game_card.dart';
import 'package:chessever2/screens/group_event/widget/tour_loading_widget.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/games_tour_content_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/game_card_wrapper/live_game_card_provider.dart';
import 'package:chessever2/widgets/generic_error_widget.dart';
import 'package:chessever2/widgets/paywall/premium_paywall_sheet.dart';
import 'package:chessever2/widgets/screen_wrapper.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:chessever2/screens/group_event/widget/appbar_icons_widget.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/svg_asset.dart';
import 'package:chessever2/utils/tablet_safe_menu.dart';
import 'package:flutter_svg/svg.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class CountrymanGamesScreen extends StatelessWidget {
  const CountrymanGamesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ScreenWrapper(
      child: Scaffold(
        key: e2eKey(E2eIds.countrymenRoot),
        body: Column(
          children: [
            SizedBox(height: MediaQuery.of(context).viewPadding.top + 24),
            CountrymanGamesAppBar(),
            Expanded(child: CountrymanGamesList()),
          ],
        ),
      ),
    );
  }
}

class CountrymanGamesList extends ConsumerStatefulWidget {
  const CountrymanGamesList({super.key});

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

  String get _liveCardsPauseReason => 'countryman_games_scroll_$hashCode';
  // Keep rendering while backgrounded so the OS app-switcher snapshot is not
  // blank. Route coverage still removes the list from active provider work.
  bool get _isActiveOnScreen => _routeIsCurrent;

  @override
  void initState() {
    super.initState();
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
    setLiveGameCardsPaused(ref, reason: _liveCardsPauseReason, paused: paused);
  }

  @override
  Widget build(BuildContext context) {
    if (!_isActiveOnScreen) {
      return const SizedBox.shrink();
    }

    final gamesListViewMode = ref.watch(gamesListViewModeProvider);
    final shouldStream = ref.watch(shouldStreamProvider);
    final streamEnabled = shouldStream;

    return ref
        .watch(countrymanGamesTourScreenProvider)
        .when(
          data: (data) {
            if (data.gamesTourModels.isEmpty) {
              return EmptyWidget(
                title:
                    "No games available yet. Check back soon or set a\nreminder for updates.",
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
                  final game = watchLiveGame(
                    ref,
                    baseGame,
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
                          if (!context.mounted) return;

                          ref
                              .read(chessboardViewFromProviderNew.notifier)
                              .state = ChessboardView.countryman;
                          ref.read(shouldStreamProvider.notifier).state = false;
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder:
                                  (_) => ChessBoardScreenNew(
                                    games: updatedGames,
                                    currentIndex: index,
                                  ),
                            ),
                          ).then((_) {
                            if (context.mounted) {
                              ref.read(shouldStreamProvider.notifier).state =
                                  true;
                              ref.invalidate(gameUpdatesStreamProvider);
                              ref.invalidate(liveGameUpdateStreamProvider);
                              ref.invalidate(gameUpdatesBatchStreamProvider);
                            }
                          });
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
                          if (!context.mounted) return;

                          ref
                              .read(chessboardViewFromProviderNew.notifier)
                              .state = ChessboardView.countryman;
                          ref.read(shouldStreamProvider.notifier).state = false;
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder:
                                  (_) => ChessBoardScreenNew(
                                    games: updatedGames,
                                    currentIndex: index,
                                  ),
                            ),
                          ).then((_) {
                            if (context.mounted) {
                              ref.read(shouldStreamProvider.notifier).state =
                                  true;
                              ref.invalidate(gameUpdatesStreamProvider);
                              ref.invalidate(liveGameUpdateStreamProvider);
                              ref.invalidate(gameUpdatesBatchStreamProvider);
                            }
                          });
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
                              top: 12.sp,
                              bottom: bottomPadding,
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
                              top: 12.sp,
                              bottom: bottomPadding,
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
          error: (_, __) => GenericErrorWidget(),
          loading: () => TourLoadingWidget(),
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
    setState(() {
      isSearching = true;
    });
    _focusNode.requestFocus();
  }

  Future<void> _closeSearch() async {
    setState(() {
      isSearching = false;
    });
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

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () {
        if (isSearching) _closeSearch();
      },
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        transitionBuilder: (child, animation) {
          return FadeTransition(
            opacity: animation,
            child: SizeTransition(
              sizeFactor: animation,
              axis: Axis.horizontal,
              child: child,
            ),
          );
        },
        child:
            isSearching
                ? Row(
                  key: const ValueKey('search_mode'),
                  children: [
                    Expanded(
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeInOut,
                        // height: 45.h,
                        margin: EdgeInsets.symmetric(horizontal: 20.sp),
                        padding: EdgeInsets.symmetric(
                          horizontal: 12.sp,
                          vertical: 5.sp,
                        ),
                        decoration: BoxDecoration(
                          color: context.colors.surface,
                          borderRadius: BorderRadius.circular(4.br),
                        ),
                        child: Row(
                          children: [
                            SvgPicture.asset(
                              SvgAsset.searchIcon,
                              colorFilter: ColorFilter.mode(
                                context.colors.textPrimary,
                                BlendMode.srcIn,
                              ),
                            ),
                            SizedBox(width: 4.w),
                            Expanded(
                              child: TextField(
                                key: e2eKey(E2eIds.countrymenSearchField),
                                controller: _searchController,
                                focusNode: _focusNode,
                                style: TextStyle(
                                  color: context.colors.textPrimaryMuted,
                                ),
                                decoration: InputDecoration(
                                  hintText: 'Search',

                                  hintStyle: TextStyle(
                                    color: context.colors.textPrimaryMuted,
                                  ),
                                  border: InputBorder.none,
                                  isDense: true,
                                ),
                                onChanged:
                                    ref
                                        .read(
                                          countrymanGamesTourScreenProvider
                                              .notifier,
                                        )
                                        .searchGames,
                              ),
                            ),
                            GestureDetector(
                              onTap: _closeSearch,
                              child: Icon(
                                Icons.close,
                                color: context.colors.textPrimaryMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                )
                : Row(
                  key: const ValueKey(
                    'app_bar_mode',
                  ), // uniquely identifies this Row
                  children: [
                    SizedBox(width: 20.w),
                    IconButton(
                      iconSize: 24.ic,
                      padding: EdgeInsets.zero,
                      onPressed: () {
                        Navigator.of(context).pop();
                      },
                      icon: Icon(
                        Icons.arrow_back_ios_new_outlined,
                        size: 24.ic,
                      ),
                    ),
                    Spacer(),
                    Text(
                      'Countrymen',
                      style: AppTypography.textMdMedium.copyWith(
                        color: context.colors.textPrimary,
                      ),
                    ),
                    Spacer(),
                    AppBarIcons(
                      key: e2eKey(E2eIds.countrymenSearchToggle),
                      image: SvgAsset.searchIcon,
                      onTap: _startSearch,
                    ),
                    SizedBox(width: 18.w),
                    AppBarIcons(
                      image: SvgAsset.chase_grid,
                      onTap: () {
                        ref.read(gamesListViewModeSwitcher).toggleViewMode();
                      },
                    ),
                    SizedBox(width: 18.w),
                    AppBarIcons(
                      key: _menuKey,
                      padding: EdgeInsets.symmetric(
                        horizontal: 2.sp,
                        vertical: 1.sp,
                      ),
                      image: SvgAsset.threeDots,
                      onTap: () {
                        final RenderBox? renderBox =
                            _menuKey.currentContext?.findRenderObject()
                                as RenderBox?;

                        if (renderBox != null) {
                          final Offset offset = renderBox.localToGlobal(
                            Offset.zero,
                          );

                          showTabletSafeMenu(
                            context: context,
                            position: RelativeRect.fromLTRB(
                              offset.dx,
                              offset.dy + renderBox.size.height,
                              offset.dx + renderBox.size.width,
                              offset.dy,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12.br),
                            ),
                            color: context.colors.surface,
                            items: <PopupMenuEntry<String>>[
                              PopupMenuItem<String>(
                                value: 'Unpin all',
                                child: InkWell(
                                  onTap: () {
                                    Navigator.pop(context);
                                    ref
                                        .read(
                                          countrymanGamesTourScreenProvider
                                              .notifier,
                                        )
                                        .unpinAllGames();
                                  },
                                  child: SizedBox(
                                    width: 200,
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          "Unpin all",
                                          style: AppTypography.textXsMedium
                                              .copyWith(
                                                color:
                                                    context.colors.textPrimary,
                                              ),
                                        ),
                                        SvgPicture.asset(
                                          SvgAsset.unpine,
                                          height: 13.h,
                                          width: 13.w,
                                        ),
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
                                value: 'share',
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      "Active games on top",
                                      style: AppTypography.textXsMedium
                                          .copyWith(
                                            color: context.colors.textPrimary,
                                          ),
                                    ),
                                    SvgPicture.asset(
                                      SvgAsset.active,
                                      height: 13.h,
                                      width: 13.w,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          );
                        }
                      },
                    ),

                    SizedBox(width: 20.w),
                  ],
                ),
      ),
    );
  }
}
