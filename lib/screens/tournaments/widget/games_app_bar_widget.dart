import 'dart:async';
import 'package:chessever2/screens/chessboard/chess_board_screen.dart';
import 'package:chessever2/screens/chessboard/provider/chess_board_screen_provider.dart';
import 'package:chessever2/screens/tournaments/providers/chess_board_visibility_provider.dart';
import 'package:chessever2/screens/tournaments/providers/games_tour_screen_provider.dart';
import 'package:chessever2/screens/tournaments/widget/appbar_icons_widget.dart';
import 'package:chessever2/screens/tournaments/widget/round_drop_down.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/svg_asset.dart';
import 'package:chessever2/widgets/search/gameSearch/enhanced_game_search_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

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

    // Clear search state on widget initialization
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

    // Clear everything when starting search
    _currentSearchQuery = '';
    _searchController.clear();
    ref.read(gamesTourScreenProvider.notifier).clearSearch();

    // Request focus after a short delay to ensure widget is built
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  Future<void> _closeSearch() async {
    setState(() {
      isSearching = false;
    });

    // Clear all search state
    _searchController.clear();
    _currentSearchQuery = '';
    _debounceTimer?.cancel();

    // Refresh games and unfocus
    await ref.read(gamesTourScreenProvider.notifier).refreshGames();
    _focusNode.unfocus();
  }

  void _handleSearchInput(String query) {
    debugPrint('🎯 _handleSearchInput called with: "$query"');

    // Cancel previous timer
    _debounceTimer?.cancel();

    // Update current query immediately
    _currentSearchQuery = query;

    // If query is empty, clear results immediately
    if (query.isEmpty || query.trim().isEmpty) {
      debugPrint('🎯 Empty query, clearing search');
      ref.read(gamesTourScreenProvider.notifier).clearSearch();
      return;
    }

    // Use debounced search
    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      if (mounted && _currentSearchQuery == query) {
        debugPrint('🎯 Executing ENHANCED search for: "$query"');
        ref.read(gamesTourScreenProvider.notifier).searchGamesEnhanced(query);
      }
    });
  }

  void _handleGameSelection(game) {
    try {
      final provider = ref.read(gamesTourScreenProvider.notifier);

      debugPrint(
        '🎯 Before clearSearch - Current state games count: ${ref.read(gamesTourScreenProvider).valueOrNull?.gamesTourModels.length ?? 0}',
      );

      // Clear search to get full games list
      provider.clearSearch();

      // Give it a moment to update - but use a callback to ensure completion
      WidgetsBinding.instance.addPostFrameCallback((_) {
        // Add slight delay to ensure state is updated
        Future.delayed(const Duration(milliseconds: 150), () {
          final gamesTourAsync = ref.read(gamesTourScreenProvider);

          debugPrint(
            '🎯 After clearSearch - State has value: ${gamesTourAsync.hasValue}',
          );

          if (!gamesTourAsync.hasValue) {
            debugPrint('🎯 ERROR: Games data not available after clearSearch');
            return;
          }

          final gamesData = gamesTourAsync.value!;
          final allGames = gamesData.gamesTourModels;

          debugPrint(
            '🎯 Games available after clearSearch: ${allGames.length}',
          );
          debugPrint('🎯 Looking for game with ID: ${game.id}');

          // Find the game index in the full games list
          final gameIndex = allGames.indexWhere(
            (tourGame) => tourGame.gameId == game.id,
          );

          debugPrint('🎯 Found game at index: $gameIndex');

          if (gameIndex == -1) {
            debugPrint(
              '🎯 ERROR: Selected game not found in current games list',
            );
            debugPrint(
              '🎯 Available game IDs: ${allGames.map((g) => g.gameId).take(5).toList()}...',
            );
            return;
          }

          ref.read(chessboardViewFromProvider.notifier).state =
              ChessboardView.tour;

          debugPrint(
            '🎯 Navigating with ${allGames.length} games, index $gameIndex',
          );

          Navigator.push(
            context,
            MaterialPageRoute(
              builder:
                  (_) => ChessBoardScreen(
                    games: allGames,
                    currentIndex: gameIndex,
                  ),
            ),
          );

          _closeSearch();
        });
      });
    } catch (e) {
      debugPrint('🎯 ERROR in _handleGameSelection: $e');
    }
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
                        onChanged:
                            _handleSearchInput, // Direct method reference
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
                      onPressed: () {
                        Navigator.of(context).pop();
                      },
                      icon: Icon(
                        Icons.arrow_back_ios_new_outlined,
                        size: 24.ic,
                      ),
                    ),
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
                        final current = ref.read(chessBoardVisibilityProvider);
                        ref.read(chessBoardVisibilityProvider.notifier).state =
                            !current;
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
                                        .read(gamesTourScreenProvider.notifier)
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
                                              .copyWith(color: kWhiteColor),
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
                ),
      ),
    );
  }
}
