import 'package:chessever2/screens/chessboard/chess_board_screen_new.dart';
import 'package:chessever2/screens/chessboard/provider/chess_board_screen_provider_new.dart';
import 'package:chessever2/screens/chessboard/widgets/chess_board_widget_new.dart';
import 'package:chessever2/screens/group_event/model/games_tour_model.dart';
import 'package:chessever2/screens/group_event/providers/chess_board_visibility_provider.dart';
import 'package:chessever2/screens/group_event/providers/countryman_games_tour_screen_provider.dart';
import 'package:chessever2/screens/group_event/providers/game_fen_stream_provider.dart';
import 'package:chessever2/screens/group_event/widget/empty_widget.dart';
import 'package:chessever2/screens/group_event/widget/game_card.dart';
import 'package:chessever2/screens/group_event/widget/tour_loading_widget.dart';
import 'package:chessever2/widgets/generic_error_widget.dart';
import 'package:chessever2/widgets/screen_wrapper.dart';
import 'package:flutter/material.dart';
import 'package:chessever2/screens/group_event/widget/appbar_icons_widget.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/svg_asset.dart';
import 'package:flutter_svg/svg.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class CountrymanGamesScreen extends StatelessWidget {
  const CountrymanGamesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ScreenWrapper(
      child: Scaffold(
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

class CountrymanGamesList extends ConsumerWidget {
  const CountrymanGamesList({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isChessBoardVisible = ref.watch(chessBoardVisibilityProvider);

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

            return ListView.builder(
              padding: EdgeInsets.only(
                left: 20.sp,
                right: 20.sp,
                top: 12.sp,
                bottom: MediaQuery.of(context).viewPadding.bottom,
              ),
              itemCount: data.gamesTourModels.length,
              itemBuilder: (context, index) {
                var game = data.gamesTourModels[index];

                // Update game with live FEN if ongoing
                if (game.gameStatus == GameStatus.ongoing) {
                  ref
                      .watch(gameFenStreamProvider(game.gameId))
                      .whenOrNull(
                        data: (fen) {
                          if (fen != null) {
                            game = game.copyWith(fen: fen);
                          }
                        },
                      );
                }

                return Padding(
                  padding: EdgeInsets.only(bottom: 12.sp),
                  child:
                      isChessBoardVisible
                          ? ChessBoardFromFENNew(
                            onChanged: () {
                              ref
                                  .read(chessboardViewFromProviderNew.notifier)
                                  .state = ChessboardView.countryman;
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder:
                                      (_) => ChessBoardScreenNew(
                                        games: data.gamesTourModels,
                                        currentIndex: index,
                                      ),
                                ),
                              );
                            },
                            gamesTourModel: data.gamesTourModels[index],
                          )
                          : GameCard(
                            onTap: () {
                              ref
                                  .read(chessboardViewFromProviderNew.notifier)
                                  .state = ChessboardView.countryman;
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder:
                                      (_) => ChessBoardScreenNew(
                                        games: data.gamesTourModels,
                                        currentIndex: index,
                                      ),
                                ),
                              );
                            },
                            gamesTourModel: game,
                            pinnedIds: data.pinnedGamedIs,
                            onPinToggle: (gamesTourModel) async {
                              await ref
                                  .read(
                                    countrymanGamesTourScreenProvider.notifier,
                                  )
                                  .togglePinGame(gamesTourModel.gameId);
                            },
                          ),
                );
              },
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
                          color: kBlack2Color,
                          borderRadius: BorderRadius.circular(4.br),
                        ),
                        child: Row(
                          children: [
                            SvgPicture.asset(
                              SvgAsset.searchIcon,
                              color: kWhiteColor,
                            ),
                            SizedBox(width: 4.w),
                            Expanded(
                              child: TextField(
                                controller: _searchController,
                                focusNode: _focusNode,
                                style: const TextStyle(color: kWhiteColor70),
                                decoration: const InputDecoration(
                                  hintText: "Search...",

                                  hintStyle: TextStyle(color: kWhiteColor70),
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
                              child: const Icon(
                                Icons.close,
                                color: kWhiteColor70,
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
                        color: kWhiteColor,
                      ),
                    ),
                    Spacer(),
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
