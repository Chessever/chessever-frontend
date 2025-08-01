import 'package:chessever2/screens/tournaments/model/games_app_bar_view_model.dart';
import 'package:chessever2/screens/tournaments/providers/games_app_bar_provider.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/svg_asset.dart';
import 'package:chessever2/widgets/divider_widget.dart';
import 'package:chessever2/widgets/skeleton_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class RoundDropDown extends ConsumerWidget {
  const RoundDropDown({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SizedBox(
      height: 32.h,
      width: 120.w,

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
          SvgAsset.check,
          width: 16.w,
          height: 16.h,
        );
        break;
      case RoundStatus.current:
        trailingIcon = SvgPicture.asset(
          SvgAsset.selectedSvg,
          width: 16.w,
          height: 16.h,
        );
        break;
      case RoundStatus.upcoming:
        trailingIcon = SvgPicture.asset(
          SvgAsset.calendarIcon,
          width: 16.w,
          height: 16.h,
        );
        break;
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                round.name,
                style: AppTypography.textXsRegular.copyWith(color: kWhiteColor),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
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
          widget.rounds.asMap().entries.map<DropdownMenuItem<String>>((entry) {
            final index = entry.key;
            final round = entry.value;
            final isLast = index == widget.rounds.length - 1;

            return DropdownMenuItem<String>(
              value: round.id,
              child: SingleChildScrollView(
                physics: const NeverScrollableScrollPhysics(),
                child: Column(
                  // crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildDropdownItem(round),
                    if (!isLast)
                      Padding(
                        padding: EdgeInsets.symmetric(vertical: 5.h),
                        child: DividerWidget(),
                      ),
                  ],
                ),
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
