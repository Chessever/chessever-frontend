import 'dart:async';
import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/screens/chessboard/chess_board_screen_new.dart';
import 'package:chessever2/screens/chessboard/provider/chess_board_screen_provider_new.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_app_bar_view_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_list_view_mode_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_app_bar_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_pin_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_screen_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/knockout_tournament_state_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/utils/knockout_match_detector.dart';
import 'package:chessever2/screens/group_event/widget/appbar_icons_widget.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/round_drop_down.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/svg_asset.dart';
import 'package:chessever2/widgets/search/gameSearch/enhanced_game_search_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/svg.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_screen_provider.dart';

// Enum for menu items to improve maintainability
enum MenuAction { unpinAll, showHideFinishedGames }

class GamesAppBarWidget extends ConsumerStatefulWidget {
  const GamesAppBarWidget({super.key});

  @override
  ConsumerState<GamesAppBarWidget> createState() => _GamesAppBarWidgetState();
}

class _GamesAppBarWidgetState extends ConsumerState<GamesAppBarWidget>
    with TickerProviderStateMixin {
  bool isSearching = false;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  late final GlobalKey _menuKey;
  Timer? _debounceTimer;
  late AnimationController _animationController;

  @override
  void initState() {
    super.initState();
    _menuKey = GlobalKey();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(gamesTourScreenProvider.notifier).clearSearch();
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _focusNode.dispose();
    _debounceTimer?.cancel();
    _animationController.dispose();
    super.dispose();
  }

  void _startSearch() {
    HapticFeedback.lightImpact();
    setState(() {
      isSearching = true;
    });
    _searchController.clear();
    ref.read(gamesTourScreenProvider.notifier).clearSearch();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
    _animationController.forward();
  }

  Future<void> _closeSearch() async {
    HapticFeedback.lightImpact();
    setState(() {
      isSearching = false;
    });

    try {
      await ref.read(gamesTourScreenProvider.notifier).refreshGames();
    } catch (e) {
      debugPrint('Error refreshing games on search close: $e');
    }

    _searchController.clear();
    _debounceTimer?.cancel();
    _focusNode.unfocus();
    _animationController.reverse();
  }

  void _handleSearchInput(String query) {
    _debounceTimer?.cancel();

    if (query.trim().isEmpty) {
      ref.read(gamesTourScreenProvider.notifier).clearSearch();
      return;
    }

    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      ref.read(gamesTourScreenProvider.notifier).searchGamesEnhanced(query);
    });
  }

  void _handleGameSelection(Games game) {
    try {
      final tourDetail = ref.read(tourDetailScreenProvider).valueOrNull;
      final mainTourId = tourDetail?.aboutTourModel.id;
      if (mainTourId == null) return;

      ref.read(chessboardViewFromProviderNew.notifier).state =
          ChessboardView.tour;
      ref.read(gamesTourScreenProvider.notifier).clearSearch();

      if (game.tourId != mainTourId) {
        _openStageGame(game);
        return;
      }

      final gamesTourAsync = ref.read(gamesTourScreenProvider);
      if (!gamesTourAsync.hasValue) return;

      final gamesData = gamesTourAsync.value!;
      final allGames = gamesData.gamesTourModels;

      final rounds = ref.read(gamesAppBarProvider).value!.gamesAppBarModels;

      final arrangedGames = _buildOrderedGamesForMainTour(
        rounds: rounds,
        primaryTourGames: allGames,
      );

      final gameIndex = arrangedGames.indexWhere(
        (tourGame) => tourGame.gameId == game.id,
      );
      if (gameIndex == -1) return;

      Navigator.push(
        context,
        MaterialPageRoute(
          builder:
              (_) => ChessBoardScreenNew(
                games: arrangedGames,
                currentIndex: gameIndex,
              ),
        ),
      );
      _closeSearch();
    } catch (e) {
      debugPrint('Error handling game selection: $e');
    }
  }

  List<GamesTourModel> _buildOrderedGamesForMainTour({
    required List<GamesAppBarModel> rounds,
    required List<GamesTourModel> primaryTourGames,
  }) {
    final ordered = <GamesTourModel>[];

    for (final round in rounds) {
      List<GamesTourModel> roundGames;
      if (_isSyntheticKnockoutRound(round.id)) {
        final stageTourId = round.id.replaceFirst('$kKnockoutStagePrefix-', '');
        if (stageTourId == round.id) {
          roundGames =
              primaryTourGames.where((game) => game.roundId == round.id).toList();
        } else {
          roundGames = _fetchStageGames(stageTourId);
        }
      } else {
        roundGames =
            primaryTourGames.where((game) => game.roundId == round.id).toList();
      }

      if (roundGames.isEmpty) continue;

      if (_isKnockoutRoundId(round.id)) {
        ordered.addAll(_orderMatchGames(roundGames));
      } else {
        ordered.addAll(roundGames);
      }
    }

    return ordered;
  }

  void _openStageGame(Games game) {
    final stageGames = _orderMatchGames(_fetchStageGames(game.tourId));
    if (stageGames.isEmpty) return;

    final stageIndex = stageGames.indexWhere((g) => g.gameId == game.id);
    if (stageIndex == -1) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (_) => ChessBoardScreenNew(
              games: stageGames,
              currentIndex: stageIndex,
            ),
      ),
    );
    _closeSearch();
  }

  List<GamesTourModel> _fetchStageGames(String tourId) {
    if (tourId.isEmpty) return const [];
    final stageState = ref.read(knockoutTournamentStateProvider(tourId));
    if (stageState.allGames.isNotEmpty) {
      return List<GamesTourModel>.from(stageState.allGames);
    }

    final stageAsync = ref.read(gamesTourProvider(tourId));
    final rawGames = stageAsync.valueOrNull ?? const <Games>[];
    return rawGames.map(GamesTourModel.fromGame).toList();
  }

  List<GamesTourModel> _orderMatchGames(List<GamesTourModel> games) {
    if (games.isEmpty) return games;
    if (!KnockoutMatchDetector.isKnockoutMatchFormat(games)) {
      return games;
    }
    final ordered = <GamesTourModel>[];
    final matches =
        KnockoutMatchDetector.groupByMatchesAcrossAllRounds(games);
    for (final matchGames in matches.values) {
      ordered.addAll(matchGames);
    }
    return ordered;
  }

  bool _isSyntheticKnockoutRound(String roundId) {
    return roundId.startsWith('$kKnockoutStagePrefix-');
  }

  bool _isKnockoutRoundId(String roundId) {
    final lower = roundId.toLowerCase();
    return lower.startsWith('$kKnockoutStagePrefix-') ||
        lower.startsWith('knockout-round-');
  }

  @override
  Widget build(BuildContext context) {
    final tourDetailAsync = ref.watch(tourDetailScreenProvider);
    return tourDetailAsync.when(
      data: (tourData) {
        final hasTours = tourData.tours.isNotEmpty;
        final disableAutoPin =
            ref
                .watch(gamesPinprovider(tourData.aboutTourModel.id))
                .autoPinDisabled;

        final gamesTourScreen = ref.watch(gamesTourScreenProvider.notifier);

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
                          child: EnhancedGamesSearchBar(
                            controller: _searchController,
                            hintText: "Search players or games...",
                            onChanged: _handleSearchInput,
                            onGameSelected: _handleGameSelection,
                            onClose: _closeSearch,
                            autofocus: true,
                          ),
                        ),
                      ],
                    )
                    : Row(
                      key: const ValueKey('app_bar_mode'),
                      children: [
                        SizedBox(width: 16.w),
                        Semantics(
                          label: 'Back button',
                          child: IconButton(
                            iconSize: 24.ic,
                            padding: EdgeInsets.zero,
                            onPressed: () => Navigator.of(context).pop(),
                            icon: Icon(
                              Icons.arrow_back_ios_new_outlined,
                              size: 24.ic,
                            ),
                          ),
                        ),
                        if (hasTours) ...[
                          const Spacer(),
                          const RoundDropDown(),
                          const Spacer(),
                          Semantics(
                            label: 'Search games',
                            child: AppBarIcons(
                              image: SvgAsset.searchIcon,
                              onTap: _startSearch,
                            ),
                          ),
                          SizedBox(width: 18.w),
                          Semantics(
                            label: 'Toggle chessboard view',
                            child: AppBarIcons(
                              image: SvgAsset.chase_grid,
                              onTap: () {
                                ref
                                    .read(gamesListViewModeSwitcher)
                                    .toggleViewMode();
                              },
                            ),
                          ),
                          SizedBox(width: 18.w),
                          Semantics(
                            label: 'More options',
                            child: AppBarIcons(
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
                                  showMenu(
                                    context: context,
                                    position: RelativeRect.fromLTRB(
                                      offset.dx,
                                      offset.dy + renderBox.size.height,
                                      offset.dx + renderBox.size.width,
                                      offset.dy,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(
                                        12.br,
                                      ),
                                    ),
                                    color: kBlack2Color,
                                    items: <PopupMenuEntry<MenuAction>>[
                                      PopupMenuItem<MenuAction>(
                                        value: MenuAction.unpinAll,
                                        child: InkWell(
                                          onTap: () {
                                            Navigator.pop(context);
                                            ref
                                                .read(
                                                  gamesTourScreenProvider
                                                      .notifier,
                                                )
                                                .unpinAllGames();
                                          },
                                          child: SizedBox(
                                            width: 200,
                                            child: Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment
                                                      .spaceBetween,
                                              children: [
                                                Text(
                                                  "Unpin all",
                                                  style: AppTypography
                                                      .textXsMedium
                                                      .copyWith(
                                                        color: kWhiteColor,
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
                                        color: kDividerColor,
                                      ),
                                      if (disableAutoPin) ...[
                                        PopupMenuItem<MenuAction>(
                                          value: MenuAction.unpinAll,
                                          child: InkWell(
                                            onTap: () async {
                                              Navigator.pop(context);
                                              await ref
                                                  .read(
                                                    gamesPinprovider(
                                                      tourData
                                                          .aboutTourModel
                                                          .id,
                                                    ).notifier,
                                                  )
                                                  .enableAutoPin();
                                            },
                                            child: SizedBox(
                                              width: 200,
                                              child: Row(
                                                mainAxisAlignment:
                                                    MainAxisAlignment
                                                        .spaceBetween,
                                                children: [
                                                  Text(
                                                    "Enable Auto Pin",
                                                    style: AppTypography
                                                        .textXsMedium
                                                        .copyWith(
                                                          color: kWhiteColor,
                                                        ),
                                                  ),
                                                  SvgPicture.asset(
                                                    SvgAsset.pin,
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
                                          color: kDividerColor,
                                        ),
                                      ],

                                      PopupMenuItem<MenuAction>(
                                        value: MenuAction.showHideFinishedGames,
                                        child: InkWell(
                                          onTap: () async {
                                            Navigator.pop(context);
                                            await ref
                                                .read(
                                                  gamesTourScreenProvider
                                                      .notifier,
                                                )
                                                .toggleFinishedGames();
                                          },
                                          child: SizedBox(
                                            width: 200,
                                            child: Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment
                                                      .spaceBetween,
                                              children: [
                                                Text(
                                                  gamesTourScreen.getTitle(),
                                                  style: AppTypography
                                                      .textXsMedium
                                                      .copyWith(
                                                        color: kWhiteColor,
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
                                        ),
                                      ),
                                    ],
                                  );
                                }
                              },
                            ),
                          ),
                          SizedBox(width: 20.w),
                        ],
                      ],
                    ),
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      error:
          (e, _) => Center(
            child: Text(
              'Error loading tours',
              style: AppTypography.textXsRegular.copyWith(color: kWhiteColor70),
            ),
          ),
    );
  }
}
