import 'package:chessever2/screens/tournaments/model/games_app_bar_view_model.dart';
import 'package:chessever2/screens/tournaments/providers/games_app_bar_provider.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/svg_asset.dart';
import 'package:chessever2/widgets/skeleton_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class GamesAppBarWidget extends ConsumerWidget {
  const GamesAppBarWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      children: [
        SizedBox(width: 20.w),
        IconButton(
          iconSize: 24.ic,
          padding: EdgeInsets.zero,
          onPressed: () {
            Navigator.of(context).pop();
          },
          icon: Icon(Icons.arrow_back_ios_new_outlined, size: 24.ic),
        ),
        const Spacer(),

        SizedBox(
          height: 32.h,
          width: 120.w,
          child: ref
              .watch(gamesAppBarProvider)
              .when(
                data: (data) {
                  return _RoundDropdown(
                    rounds: data.gamesAppBarModels,
                    selectedRoundId: data.selectedId,
                    onChanged: (model) {
                      ref
                          .read(gamesAppBarProvider.notifier)
                          .selectNewRound(model);
                    },
                  );
                },
                error: (e, _) {
                  return Center(
                    child: Text(
                      'Error loading rounds',
                      style: AppTypography.textXsRegular.copyWith(
                        color: kWhiteColor70,
                      ),
                    ),
                  );
                },
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
                      selectedRoundId: loadingRound.gamesAppBarModels.first.id,
                      onChanged: (_) {},
                    ),
                  );
                },
              ),
        ),
        const Spacer(),
        SizedBox(width: 44.w),
      ],
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
