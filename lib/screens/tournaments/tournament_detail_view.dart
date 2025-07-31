import 'package:chessever2/repository/supabase/group_broadcast/group_broadcast.dart';
import 'package:chessever2/screens/standings_screen.dart';
import 'package:chessever2/screens/tournaments/about_tour_screen.dart';
import 'package:chessever2/screens/tournaments/games_tour_screen.dart';
import 'package:chessever2/screens/tournaments/providers/tour_detail_screen_provider.dart';
import 'package:chessever2/screens/tournaments/widget/games_app_bar_widget.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/app_bar_with_title.dart';
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
                    return selectedTourMode == _TournamentDetailScreenMode.about
                        ? AppBarWithTitle(
                          title: data.aboutTourModel.name.substring(
                            0,
                            data.aboutTourModel.name.length > 20
                                ? 20
                                : data.aboutTourModel.name.length,
                          ),
                        )
                        : selectedTourMode == _TournamentDetailScreenMode.games
                        ? GamesAppBarWidget()
                        : AppBarWithTitle(
                          title: data.aboutTourModel.name.substring(
                            0,
                            data.aboutTourModel.name.length > 20
                                ? 20
                                : data.aboutTourModel.name.length,
                          ),
                        );
                  },
                  error: (e, _) {
                    return SkeletonWidget(
                      child: AppBarWithTitle(title: "Chessever"),
                    );
                  },
                  loading: () {
                    return SkeletonWidget(
                      child: AppBarWithTitle(title: "Chessever"),
                    );
                  },
                ),
            SizedBox(height: 36.h),
            Padding(
              padding:  EdgeInsets.symmetric(horizontal: 20.sp),
              child: SegmentedSwitcher(
                backgroundColor: kPopUpColor,
                selectedBackgroundColor: kPopUpColor,
                options: _mappedName.values.toList(),
                initialSelection: _mappedName.values.toList().indexOf(
                  _mappedName[selectedTourMode]!,
                ),
                onSelectionChanged: (index) {
                  ref.read(selectedTourModeProvider.notifier).state =
                      _TournamentDetailScreenMode.values[index];
                },
              ),
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
