import 'package:chessever2/repository/supabase/group_broadcast/group_broadcast.dart';
import 'package:chessever2/screens/standings/standings_screen.dart';
import 'package:chessever2/screens/tournaments/about_tour_screen.dart';
import 'package:chessever2/screens/tournaments/games_tour_screen.dart';
import 'package:chessever2/screens/tournaments/model/tour_detail_view_model.dart';
import 'package:chessever2/screens/tournaments/providers/tour_detail_screen_provider.dart';
import 'package:chessever2/screens/tournaments/widget/games_app_bar_widget.dart';
import 'package:chessever2/screens/tournaments/widget/round_drop_down.dart';
import 'package:chessever2/screens/tournaments/widget/text_dropdown_widget.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/screen_wrapper.dart';
import 'package:chessever2/widgets/segmented_switcher.dart';
import 'package:chessever2/widgets/skeleton_widget.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final selectedBroadcastModelProvider = StateProvider<GroupBroadcast?>(
  (ref) => null,
);

final selectedTourModeProvider =
    AutoDisposeStateProvider<_TournamentDetailScreenMode>(
      (ref) => _TournamentDetailScreenMode.about,
    );

///For Tabs
enum _TournamentDetailScreenMode { about, games, standings }

const _mappedName = {
  _TournamentDetailScreenMode.about: 'About',
  _TournamentDetailScreenMode.games: 'Games',
  _TournamentDetailScreenMode.standings: 'Standings',
};

class TournamentDetailView extends ConsumerWidget {
  const TournamentDetailView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedTourMode = ref.watch(selectedTourModeProvider);

    return ScreenWrapper(
      child: Scaffold(
        body: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(height: MediaQuery.of(context).viewPadding.top + 24.h),
            ref
                .watch(tourDetailScreenProvider)
                .when(
                  data: (data) {
                    return Column(
                      children: [
                        selectedTourMode == _TournamentDetailScreenMode.about
                            ? _TourDetailDropDownAppBar(data: data)
                            : selectedTourMode ==
                                _TournamentDetailScreenMode.games
                            ? GamesAppBarWidget()
                            : _StandingAppBar(),
                        SizedBox(height: 36.h),
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: 20.sp),
                          child: SegmentedSwitcher(
                            backgroundColor: kPopUpColor,
                            selectedBackgroundColor: kPopUpColor,
                            options: _mappedName.values.toList(),
                            initialSelection: _mappedName.values
                                .toList()
                                .indexOf(_mappedName[selectedTourMode]!),
                            onSelectionChanged: (index) {
                              ref
                                      .read(selectedTourModeProvider.notifier)
                                      .state =
                                  _TournamentDetailScreenMode.values[index];
                            },
                          ),
                        ),
                      ],
                    );
                  },
                  error: (e, _) {
                    return LoadingAppBarWithTitle(title: "Chessever");
                  },
                  loading: () {
                    return LoadingAppBarWithTitle(title: "Chessever");
                  },
                ),

            SizedBox(height: 12.h),
            Expanded(
              child: () {
                switch (selectedTourMode) {
                  case _TournamentDetailScreenMode.about:
                    return const AboutTourScreen();
                  case _TournamentDetailScreenMode.games:
                    return const GamesTourScreen();
                  case _TournamentDetailScreenMode.standings:
                    return const StandingsScreen();
                }
              }(),
            ),
          ],
        ),
      ),
    );
  }
}

class _StandingAppBar extends StatelessWidget {
  const _StandingAppBar({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(width: 20),
        IconButton(
          iconSize: 24,
          padding: EdgeInsets.zero,
          onPressed: () {
            Navigator.of(context).pop();
          },
          icon: Icon(Icons.arrow_back_ios_new_outlined, size: 24),
        ),
        Spacer(),
        RoundDropDown(),
        Spacer(),
        SizedBox(width: 44),
      ],
    );
  }
}

class _TourDetailDropDownAppBar extends ConsumerWidget {
  const _TourDetailDropDownAppBar({required this.data, super.key});

  final TourDetailViewModel data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      children: [
        SizedBox(width: 20),
        IconButton(
          iconSize: 24,
          padding: EdgeInsets.zero,
          onPressed: () {
            Navigator.of(context).pop();
          },
          icon: Icon(Icons.arrow_back_ios_new_outlined, size: 24),
        ),
        Spacer(),
        SizedBox(
          height: 32.h,
          width: 150.w,
          child: TextDropDownWidget(
            items:
                data.tours
                    .map((e) => {'key': e.id, 'value': e.name.split('|').last})
                    .toList(),
            selectedId: data.selectedTourId,
            onChanged: (value) {
              ref
                  .read(tourDetailScreenProvider.notifier)
                  .updateSelection(value);
            },
          ),
        ),
        Spacer(),
        SizedBox(width: 44),
      ],
    );
  }
}

class LoadingAppBarWithTitle extends StatelessWidget {
  const LoadingAppBarWithTitle({required this.title, super.key});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(width: 20),
        IconButton(
          iconSize: 24,
          padding: EdgeInsets.zero,
          onPressed: () {
            Navigator.of(context).pop();
          },
          icon: Icon(Icons.arrow_back_ios_new_outlined, size: 24),
        ),
        SizedBox(width: 44),
        SkeletonWidget(
          child: Text(
            title,
            style: AppTypography.textMdRegular.copyWith(color: kWhiteColor),
          ),
        ),
        SizedBox(width: 44),
      ],
    );
  }
}
