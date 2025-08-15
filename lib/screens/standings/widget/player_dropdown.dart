import 'package:chessever2/screens/standings/standing_screen_provider.dart';
import 'package:chessever2/screens/standings/player_standing_model.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../widgets/skeleton_widget.dart';
import '../score_card_screen.dart';

class PlayerDropDown extends ConsumerWidget {
  const PlayerDropDown({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SizedBox(
      height: 32.h,
      width: 200.w,
      child: ref
          .watch(standingScreenProvider)
          .when(
            data: (players) => _PlayerDropdown(players: players),
            error:
                (e, _) => Center(
                  child: Text(
                    'Error loading players',
                    style: AppTypography.textXsRegular.copyWith(
                      color: kWhiteColor70,
                    ),
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
                  ),
                ),
          ),
    );
  }
}

class _PlayerDropdown extends ConsumerWidget {
  final List<PlayerStandingModel> players;

  const _PlayerDropdown({required this.players});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedPlayer = ref.watch(selectedPlayerProvider);

    if (players.isEmpty) {
      return Container(
        padding: EdgeInsets.symmetric(horizontal: 12.sp),
        alignment: Alignment.center,
        child: Text(
          'No players',
          style: AppTypography.textXsMedium.copyWith(color: kWhiteColor),
          overflow: TextOverflow.ellipsis,
        ),
      );
    }

    return DropdownButton<PlayerStandingModel>(
      value: selectedPlayer ?? players.first,
      onChanged: (player) {
        if (player != null) {
          ref.read(selectedPlayerProvider.notifier).state = player;
        }
      },
      items:
          players.map(
            (player) {
              final isLast = player == players.last;
              return DropdownMenuItem<PlayerStandingModel>(
                value: player,
                child: Container(
                  padding: EdgeInsets.symmetric(vertical: 8.h),
                  decoration: BoxDecoration(
                    border:
                        isLast
                            ? null
                            : Border(
                              bottom: BorderSide(
                                color: kWhiteColor.withOpacity(0.05),
                                width: 1,
                              ),
                            ),
                  ),
                  alignment: Alignment.centerLeft,
                  child: Text(
                    player.name,
                    style: AppTypography.textXsRegular.copyWith(
                      color: kWhiteColor,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              );
            },
          ).toList(),

      underline: Container(),
      icon: Icon(
        Icons.keyboard_arrow_down_outlined,
        color: kWhiteColor,
        size: 20.ic,
      ),
      dropdownColor: kBlack2Color,
      borderRadius: BorderRadius.circular(20.br),
      isExpanded: true,
    );
  }
}
