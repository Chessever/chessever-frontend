import 'package:chessever2/screens/tour_detail/player_tour/player_tour_screen_provider.dart';
import 'package:chessever2/screens/standings/player_standing_model.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:dropdown_button2/dropdown_button2.dart';

import '../../../widgets/skeleton_widget.dart';
import '../score_card_screen.dart';

class PlayerDropDown extends ConsumerWidget {
  const PlayerDropDown({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      constraints: BoxConstraints(minWidth: 200.w, maxWidth: double.infinity),
      child: ref
          .watch(playerTourScreenProvider)
          .when(
            data: (players) => _PlayerDropdown(players: players),
            error:
                (e, _) => Container(
                  height: 40.h,
                  padding: EdgeInsets.symmetric(horizontal: 12.sp),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: kBackgroundColor,
                    borderRadius: BorderRadius.circular(8.br),
                    border: Border.all(color: kDarkGreyColor, width: 1.w),
                  ),
                  child: Text(
                    'Error loading players',
                    style: AppTypography.textXsRegular.copyWith(
                      color: kWhiteColor70,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            loading:
                () => SkeletonWidget(
                  child: _PlayerDropdown(
                    players: [
                      PlayerStandingModel(
                        countryCode: 'USA',
                        title: 'GM',
                        name: 'Loading...',
                        score: 0,
                        scoreChange: 0,
                        matchScore: '0.0 / 0',
                      ),
                    ],
                    isLoading: true,
                  ),
                ),
          ),
    );
  }
}

class _PlayerDropdown extends ConsumerStatefulWidget {
  final List<PlayerStandingModel> players;
  final bool isLoading;

  const _PlayerDropdown({required this.players, this.isLoading = false});

  @override
  ConsumerState<_PlayerDropdown> createState() => _PlayerDropdownState();
}

class _PlayerDropdownState extends ConsumerState<_PlayerDropdown> {
  var isDropDownOpen = false;

  @override
  Widget build(BuildContext context) {
    final selectedPlayer = ref.watch(selectedPlayerProvider);

    if (widget.players.isEmpty) {
      return Container(
        height: 40.h,
        padding: EdgeInsets.symmetric(horizontal: 12.sp),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: kBackgroundColor,
          borderRadius: BorderRadius.circular(8.br),
          border: Border.all(color: kDarkGreyColor, width: 1.w),
        ),
        child: Text(
          'No players',
          style: AppTypography.textXsMedium.copyWith(color: kWhiteColor70),
          overflow: TextOverflow.ellipsis,
        ),
      );
    }

    final borderRadius =
        isDropDownOpen
            ? BorderRadius.circular(10.br)
            : BorderRadius.circular(8.br);

    final dropDownBorderRadius = BorderRadius.circular(10.br);
    final currentPlayer = selectedPlayer ?? widget.players.first;

    return ClipRRect(
      borderRadius: borderRadius,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: kBackgroundColor,
          borderRadius: borderRadius,
          border:
              isDropDownOpen
                  ? null
                  : Border.all(color: kDarkGreyColor, width: 1.w),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton2<PlayerStandingModel>(
            isExpanded: true,
            customButton: Container(
              height: 40.h,
              padding: EdgeInsets.symmetric(horizontal: 12.sp),
              child: Row(
                children: [
                  Expanded(
                    child:
                        widget.isLoading
                            ? Text(
                              'Loading players...',
                              style: AppTypography.textSmMedium.copyWith(
                                color: kWhiteColor70,
                              ),
                              overflow: TextOverflow.ellipsis,
                            )
                            : Text(
                              currentPlayer.name,
                              style: AppTypography.textSmMedium.copyWith(
                                color: kWhiteColor70,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                  ),
                  SizedBox(width: 8.w),
                  Icon(
                    isDropDownOpen
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    color: kWhiteColor,
                    size: 20.ic,
                  ),
                ],
              ),
            ),
            dropdownStyleData: DropdownStyleData(
              padding: EdgeInsets.zero,
              offset: const Offset(0, -4),
              decoration: BoxDecoration(
                color: kBlack2Color,
                borderRadius: dropDownBorderRadius,
                border: Border.all(color: kDarkGreyColor),
              ),
              maxHeight: 240.h,
            ),
            buttonStyleData: ButtonStyleData(
              height: 40.h,
              padding: EdgeInsets.zero,
            ),
            menuItemStyleData: MenuItemStyleData(
              height: 44.h,
              padding: EdgeInsets.zero,
            ),
            value: widget.isLoading ? null : currentPlayer,
            onChanged:
                widget.isLoading
                    ? null
                    : (player) {
                      if (player != null) {
                        ref.read(selectedPlayerProvider.notifier).state =
                            player;
                      }
                    },
            onMenuStateChange: (isOpen) {
              setState(() {
                isDropDownOpen = isOpen;
              });
            },
            items:
                widget.isLoading
                    ? []
                    : widget.players.asMap().entries.map((entry) {
                      final index = entry.key;
                      final player = entry.value;
                      final isLast = index == widget.players.length - 1;

                      return DropdownMenuItem<PlayerStandingModel>(
                        value: player,
                        child: Container(
                          decoration: BoxDecoration(
                            border:
                                isLast
                                    ? null
                                    : Border(
                                      bottom: BorderSide(
                                        color: kDarkGreyColor,
                                        width: 1.w,
                                      ),
                                    ),
                          ),
                          height: 44.h,
                          child: Row(
                            children: [
                              SizedBox(width: 12.w),
                              Expanded(
                                child: Text(
                                  player.name,
                                  style: AppTypography.textMdMedium.copyWith(
                                    color: kWhiteColor,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              SizedBox(width: 12.w),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
          ),
        ),
      ),
    );
  }
}
