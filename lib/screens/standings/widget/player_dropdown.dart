import 'package:chessever2/screens/standings/standing_screen_provider.dart';
import 'package:chessever2/screens/standings/player_standing_model.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../widgets/skeleton_widget.dart';

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
            data:
                (data) => _PlayerDropdown(
                  players: data,
                  selectedPlayerId: data.isNotEmpty ? data.first.name : null,
                  onChanged: (player) {},
                ),
            error:
                (e, _) => Center(
                  child: Text(
                    'Error loading players',
                    style: AppTypography.textXsRegular.copyWith(
                      color: kWhiteColor70,
                    ),
                  ),
                ),
            loading: () {
              final loadingPlayers = [
                PlayerStandingModel(
                  countryCode: 'USA',
                  title: 'GM',
                  name: 'Loading...',
                  score: 0,
                  scoreChange: 0,
                  matchScore: '0.0 / 0',
                ),
              ];
              return SkeletonWidget(
                child: _PlayerDropdown(
                  players: loadingPlayers,
                  selectedPlayerId: loadingPlayers.first.name,
                  onChanged: (_) {},
                ),
              );
            },
          ),
    );
  }
}

class _PlayerDropdown extends StatefulWidget {
  final List<PlayerStandingModel> players;
  final String? selectedPlayerId;
  final ValueChanged<PlayerStandingModel> onChanged;

  const _PlayerDropdown({
    required this.players,
    required this.selectedPlayerId,
    required this.onChanged,
  });

  @override
  State<_PlayerDropdown> createState() => _PlayerDropdownState();
}

class _PlayerDropdownState extends State<_PlayerDropdown> {
  late String? _selectedPlayerId;

  @override
  void initState() {
    _selectedPlayerId = widget.selectedPlayerId;
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.players.isEmpty) {
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

    return DropdownButton<String>(
      value: _selectedPlayerId,
      onChanged: (newValue) {
        if (newValue != null) {
          setState(() {
            _selectedPlayerId = newValue;
          });
          final selectedPlayer = widget.players.firstWhere(
            (e) => e.name == newValue,
            orElse: () => widget.players.first,
          );
          widget.onChanged(selectedPlayer);
        }
      },
      items:
          widget.players.asMap().entries.map<DropdownMenuItem<String>>((entry) {
            final index = entry.key;
            final player = entry.value;
            final isLast = index == widget.players.length - 1;

            return DropdownMenuItem<String>(
              value: player.name,
              child: Column(
                children: [
                  Container(
                    padding: EdgeInsets.symmetric(vertical: 8.h),
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
                  if (!isLast)
                    Divider(
                      height: 1,
                      color: kWhiteColor.withOpacity(0.05),
                    ),
                ],
              ),
            );
          }).toList(),
      underline: Container(),
      icon: Icon(
        Icons.keyboard_arrow_down_outlined,
        color: kWhiteColor,
        size: 20.ic,
      ),
      dropdownColor: kBlack2Color,
      borderRadius: BorderRadius.circular(20.br),
      isExpanded: true,
      style: AppTypography.textMdBold,
      selectedItemBuilder: (BuildContext context) {
        return widget.players.map((e) => e.name).map<Widget>((name) {
          return Container(
            padding: EdgeInsets.symmetric(horizontal: 12.sp),
            alignment: Alignment.center,
            child: Text(
              name,
              style: AppTypography.textXsMedium.copyWith(color: kWhiteColor),
              overflow: TextOverflow.ellipsis,
            ),
          );
        }).toList();
      },
    );
  }
}
