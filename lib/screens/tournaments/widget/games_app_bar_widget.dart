import 'package:chessever2/screens/tournaments/model/games_app_bar_view_model.dart';
import 'package:chessever2/screens/tournaments/providers/games_app_bar_provider.dart';
import 'package:chessever2/screens/tournaments/providers/games_tour_screen_provider.dart';
import 'package:chessever2/screens/tournaments/widget/appbar_icons_widget.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/svg_asset.dart';
import 'package:chessever2/widgets/skeleton_widget.dart';
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

  void _startSearch() {
    setState(() {
      isSearching = true;
    });
    _focusNode.requestFocus();
  }

  void _closeSearch() {
    setState(() {
      isSearching = false;
      _searchController.clear();
    });
    _focusNode.unfocus();
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
                                        .read(gamesTourScreenProvider.notifier)
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
                    const Spacer(),
                    SizedBox(
                      height: 32.h,
                      width: 100.w,
                      child: ref
                          .watch(gamesAppBarProvider)
                          .when(
                            data:
                                (data) => _RoundDropdown(
                                  rounds: data.gamesAppBarModels,
                                  selectedRoundId: data.selectedId,
                                  onChanged: (model) {
                                    ref
                                        .read(gamesAppBarProvider.notifier)
                                        .selectNewRound(model);
                                  },
                                ),
                            error:
                                (e, _) => Center(
                                  child: Text(
                                    'Error loading rounds',
                                    style: AppTypography.textXsRegular.copyWith(
                                      color: kWhiteColor70,
                                    ),
                                  ),
                                ),
                            loading: () {
                              final loadingRound = GamesAppBarViewModel(
                                gamesAppBarModels: [
                                  GamesAppBarModel(
                                    id: 'qdBcMm1h',
                                    name: 'round-1',
                                    startsAt: DateTime.now(),
                                    ongoing: false,
                                  ),
                                ],
                                selectedId: 'qdBcMm1h',
                              );
                              return SkeletonWidget(
                                child: _RoundDropdown(
                                  rounds: loadingRound.gamesAppBarModels,
                                  selectedRoundId:
                                      loadingRound.gamesAppBarModels.first.id,
                                  onChanged: (_) {},
                                ),
                              );
                            },
                          ),
                    ),
                    const Spacer(),
                    AppBarIcons(
                      image: SvgAsset.searchIcon,
                      onTap: _startSearch,
                    ),
                    SizedBox(width: 18.w),
                    AppBarIcons(image: SvgAsset.chase_grid, onTap: () {}),
                    SizedBox(width: 20.w),
                  ],
                ),
      ),
    );
  }
}

class _RoundDropdown extends StatefulWidget {
  final List<GamesAppBarModel> rounds;
  final String selectedRoundId;
  final ValueChanged<GamesAppBarModel> onChanged;

  const _RoundDropdown({
    required this.rounds,
    required this.selectedRoundId,
    required this.onChanged,
  });

  @override
  State<_RoundDropdown> createState() => _RoundDropdownState();
}

class _RoundDropdownState extends State<_RoundDropdown> {
  late String _selectedRoundId;

  @override
  void initState() {
    // Ensure the selected round exists in the rounds list
    _selectedRoundId =
        widget.rounds
            .firstWhere(
              (round) => round.id == widget.selectedRoundId,
              orElse: () => widget.rounds.first,
            )
            .id;
    super.initState();
  }

  Widget _buildDropdownItem(GamesAppBarModel round) {
    Widget trailingIcon;

    switch (round.status) {
      case RoundStatus.completed:
        trailingIcon = SvgPicture.asset(
          SvgAsset.selectedSvg,
          width: 16.w,
          height: 16.h,
          colorFilter: const ColorFilter.mode(kGreenColor, BlendMode.srcIn),
        );
        break;
      case RoundStatus.current:
        trailingIcon = Container(
          width: 16.w,
          height: 16.h,
          decoration: const BoxDecoration(
            color: kPrimaryColor,
            shape: BoxShape.circle,
          ),
          child: Icon(Icons.circle, color: kWhiteColor, size: 8.ic),
        );
        break;
      case RoundStatus.upcoming:
        trailingIcon = SvgPicture.asset(
          SvgAsset.calendarIcon,
          width: 16.w,
          height: 16.h,
          colorFilter: const ColorFilter.mode(kWhiteColor70, BlendMode.srcIn),
        );
        break;
    }

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8.sp),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  round.name,
                  style: AppTypography.textXsRegular.copyWith(
                    color: kWhiteColor,
                  ),
                  maxLines: 1,
                ),
                SizedBox(height: 2.h),
                Text(
                  round.formattedStartDate,
                  style: AppTypography.textXsRegular.copyWith(
                    color: kWhiteColor70,
                  ),
                  maxLines: 1,
                ),
              ],
            ),
          ),
          SizedBox(width: 8.w),
          trailingIcon,
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DropdownButton<String>(
      value: _selectedRoundId,
      onChanged: (newValue) {
        if (newValue != null) {
          setState(() {
            _selectedRoundId = newValue;
          });
          widget.onChanged(widget.rounds.firstWhere((e) => e.id == newValue));
        }
      },
      items:
          widget.rounds.map((e) => e.id).map<DropdownMenuItem<String>>((id) {
            return DropdownMenuItem<String>(
              value: widget.rounds.firstWhere((e) => e.id == id).id,
              child: _buildDropdownItem(
                widget.rounds.firstWhere((e) => e.id == id),
              ),
            );
          }).toList(),
      underline: Container(),
      icon: Icon(
        Icons.keyboard_arrow_down_outlined,
        color: kWhiteColor,
        size: 20.ic,
      ),
      dropdownColor: kPopUpColor,
      borderRadius: BorderRadius.circular(8.br),
      isExpanded: true,
      style: AppTypography.textMdBold,
      selectedItemBuilder: (BuildContext context) {
        return widget.rounds.map((e) => e.id).map<Widget>((id) {
          return Container(
            padding: EdgeInsets.symmetric(horizontal: 12.sp),
            alignment: Alignment.center,
            child: Text(
              widget.rounds.firstWhere((e) => e.id == id).name,
              style: AppTypography.textXsMedium.copyWith(color: kWhiteColor),
              overflow: TextOverflow.ellipsis,
            ),
          );
        }).toList();
      },
    );
  }
}
