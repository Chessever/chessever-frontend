import 'dart:async';
import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/screens/chessboard/chess_board_screen_new.dart';
import 'package:chessever2/screens/chessboard/provider/chess_board_screen_provider_new.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/chess_board_visibility_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_screen_provider.dart';
import 'package:chessever2/screens/group_event/widget/appbar_icons_widget.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/round_drop_down.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/svg_asset.dart';
import 'package:chessever2/widgets/search/gameSearch/enhanced_game_search_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../provider/tour_detail_screen_provider.dart';

class GamesAppBarWidget extends ConsumerStatefulWidget {
  const GamesAppBarWidget({super.key});

  @override
  ConsumerState<GamesAppBarWidget> createState() => _GamesAppBarWidgetState();
}

class _GamesAppBarWidgetState extends ConsumerState<GamesAppBarWidget> {
  bool isSearching = false;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  late final GlobalKey _menuKey;
  Timer? _debounceTimer;
  String _currentSearchQuery = '';

  @override
  void initState() {
    _menuKey = GlobalKey();
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(gamesTourScreenProvider.notifier).clearSearch();
      }
    });
  }

  void _startSearch() {
    setState(() {
      isSearching = true;
    });
    _currentSearchQuery = '';
    _searchController.clear();
    ref.read(gamesTourScreenProvider.notifier).clearSearch();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  Future<void> _closeSearch() async {
    setState(() {
      isSearching = false;
    });
    _searchController.clear();
    _currentSearchQuery = '';
    _debounceTimer?.cancel();
    await ref.read(gamesTourScreenProvider.notifier).refreshGames();
    _focusNode.unfocus();
  }

  void _handleSearchInput(String query) {
    _debounceTimer?.cancel();
    _currentSearchQuery = query;

    if (query.trim().isEmpty) {
      ref.read(gamesTourScreenProvider.notifier).clearSearch();
      return;
    }

    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      if (mounted && _currentSearchQuery == query) {
        ref.read(gamesTourScreenProvider.notifier).searchGamesEnhanced(query);
      }
    });
  }

  void _handleGameSelection(Games game) {
    try {
      ref.read(chessboardViewFromProviderNew.notifier).state =
          ChessboardView.tour;
      ref.read(gamesTourScreenProvider.notifier).clearSearch();

      final gamesTourAsync = ref.read(gamesTourScreenProvider);
      if (!gamesTourAsync.hasValue) return;

      final gamesData = gamesTourAsync.value!;
      final allGames = gamesData.gamesTourModels;
      final gameIndex = allGames.indexWhere(
        (tourGame) => tourGame.gameId == game.id,
      );
      if (gameIndex == -1) return;

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
      _closeSearch();
    } catch (e) {}
  }

  @override
  void dispose() {
    _searchController.dispose();
    _focusNode.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tourDetailAsync = ref.watch(tourDetailScreenProvider);

    return tourDetailAsync.when(
      data: (tourData) {
        final hasTours = tourData.tours.isNotEmpty;

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
                        IconButton(
                          iconSize: 24.ic,
                          padding: EdgeInsets.zero,
                          onPressed: () => Navigator.of(context).pop(),
                          icon: Icon(
                            Icons.arrow_back_ios_new_outlined,
                            size: 24.ic,
                          ),
                        ),

                        if (hasTours) ...[
                          const Spacer(),
                          RoundDropDown(),
                          const Spacer(),
                          AppBarIcons(
                            image: SvgAsset.searchIcon,
                            onTap: _startSearch,
                          ),
                          SizedBox(width: 18.w),
                          AppBarIcons(
                            image: SvgAsset.chase_grid,
                            onTap: () {
                              final current = ref.read(
                                chessBoardVisibilityProvider,
                              );
                              ref
                                  .read(chessBoardVisibilityProvider.notifier)
                                  .state = !current;
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

                                showMenu(
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
                                  color: kBlack2Color,
                                  items: <PopupMenuEntry<String>>[
                                    PopupMenuItem<String>(
                                      value: 'Unpin all',
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
                                                MainAxisAlignment.spaceBetween,
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
                                    PopupMenuItem<String>(
                                      value: 'share',
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(
                                            "Active games on top",
                                            style: AppTypography.textXsMedium
                                                .copyWith(color: kWhiteColor),
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
                      ],
                    ),
          ),
        );
      },
      loading: () => SizedBox.shrink(),
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
