import 'package:chessever2/repository/supabase/round/round.dart';
import 'package:chessever2/screens/tournaments/model/games_app_bar_view_model.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/svg_asset.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';

class GamesAppBarWidget extends StatelessWidget {
  const GamesAppBarWidget({super.key});

  @override
  Widget build(BuildContext context) {
    final sampleData = [
      {
        'id': 'qdBcMm1h',
        'slug': 'round-1',
        'tour_id': '5LW5RS0a',
        'tour_slug': 'norway-chess-2024--women',
        'name': 'Round 1',
        'created_at': '2024-05-25T21:31:09.495Z',
        'ongoing': false,
        'starts_at': '2026-05-27T15:00:00.000Z',
        'url':
            'https://lichess.org/broadcast/norway-chess-2024--women/round-1/qdBcMm1h',
      },
      {
        'id': 'xiL30gik',
        'slug': 'round-2',
        'tour_id': '5LW5RS0a',
        'tour_slug': 'norway-chess-2024--women',
        'name': 'Round 2',
        'created_at': '2024-05-25T21:44:37.425Z',
        'ongoing': false,
        'starts_at': '2024-05-28T15:00:00.000Z',
        'url':
            'https://lichess.org/broadcast/norway-chess-2024--women/round-2/xiL30gik',
      },
      // Add more as needed...
    ];

    final rounds = List.generate(sampleData.length, (index) {
      final round = Round.fromJson(sampleData[index]);
      return GamesAppBarViewModel.fromTour(round);
    });

    return Row(
      children: [
        const SizedBox(width: 20),
        IconButton(
          iconSize: 24,
          padding: EdgeInsets.zero,
          onPressed: () {
            Navigator.of(context).pop();
          },
          icon: Icon(Icons.arrow_back_ios_new_outlined, size: 24),
        ),
        const Spacer(),
        SizedBox(
          height: 32,
          width: 120,
          child: _RoundDropdown(
            rounds: rounds,
            selectedRound: rounds.first,
            onChanged: (_) {},
          ),
        ),
        const Spacer(),
        const SizedBox(width: 44),
      ],
    );
  }
}

class _RoundDropdown extends StatefulWidget {
  final List<GamesAppBarViewModel> rounds;
  final GamesAppBarViewModel selectedRound;
  final ValueChanged<GamesAppBarViewModel> onChanged;

  const _RoundDropdown({
    required this.rounds,
    required this.selectedRound,
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
              (round) => round.id == widget.selectedRound.id,
              orElse: () => widget.rounds.first,
            )
            .id;
    super.initState();
  }

  Widget _buildDropdownItem(GamesAppBarViewModel round) {
    Widget trailingIcon;

    switch (round.status) {
      case RoundStatus.completed:
        trailingIcon = SvgPicture.asset(
          SvgAsset.selectedSvg,
          width: 16,
          height: 16,
          colorFilter: const ColorFilter.mode(kGreenColor, BlendMode.srcIn),
        );
        break;
      case RoundStatus.current:
        trailingIcon = Container(
          width: 16,
          height: 16,
          decoration: const BoxDecoration(
            color: kPrimaryColor,
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.circle, color: kWhiteColor, size: 8),
        );
        break;
      case RoundStatus.upcoming:
        trailingIcon = SvgPicture.asset(
          SvgAsset.calendarIcon,
          width: 16,
          height: 16,
          colorFilter: const ColorFilter.mode(kWhiteColor70, BlendMode.srcIn),
        );
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8),
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
                const SizedBox(height: 2),
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
          const SizedBox(width: 8),
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
      icon: const Icon(Icons.arrow_drop_down, color: kWhiteColor),
      dropdownColor: kPopUpColor,
      borderRadius: BorderRadius.circular(8),
      isExpanded: true,
      style: TextStyle(color: kWhiteColor, fontSize: 12),
      selectedItemBuilder: (BuildContext context) {
        return widget.rounds.map((e) => e.id).map<Widget>((id) {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
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
