import 'package:chessever2/repository/supabase/group_broadcast/group_broadcast.dart';
import 'package:chessever2/screens/standings/standings_screen.dart';
import 'package:chessever2/screens/tournaments/about_tour_screen.dart';
import 'package:chessever2/screens/tournaments/games_tour_screen.dart';
import 'package:chessever2/screens/tournaments/model/tour_detail_view_model.dart';
import 'package:chessever2/screens/tournaments/providers/tour_detail_screen_provider.dart';
import 'package:chessever2/screens/tournaments/widget/games_app_bar_widget.dart';
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

class TournamentDetailView extends ConsumerStatefulWidget {
  const TournamentDetailView({super.key});

  @override
  ConsumerState<TournamentDetailView> createState() =>
      _TournamentDetailViewState();
}

class _TournamentDetailViewState extends ConsumerState<TournamentDetailView> {
  late PageController pageController;

  // Define the pages for the PageView
  final List<Widget> _pages = const [
    AboutTourScreen(),
    GamesTourScreen(),
    StandingsScreen(),
  ];

  @override
  void initState() {
    super.initState();
    final selectedTourMode = ref.read(selectedTourModeProvider);
    pageController = PageController(
      initialPage: _TournamentDetailScreenMode.values.indexOf(selectedTourMode),
    );
  }

  @override
  void dispose() {
    pageController.dispose();
    ref.invalidate(selectedTourIdProvider);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selectedTourMode = ref.watch(selectedTourModeProvider);

    return ScreenWrapper(
      child: Scaffold(
        body: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(height: MediaQuery.of(context).viewPadding.top + 4.h),
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
                            : _TourDetailDropDownAppBar(data: data),
                        SizedBox(height: 8.h),
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: 20.sp),
                          child: SegmentedSwitcher(
                            key: UniqueKey(),
                            backgroundColor: kPopUpColor,
                            selectedBackgroundColor: kPopUpColor,
                            options: _mappedName.values.toList(),
                            initialSelection: _mappedName.values
                                .toList()
                                .indexOf(_mappedName[selectedTourMode]!),
                            onSelectionChanged: (index) {
                              // Animate to the selected page first
                              pageController.animateToPage(
                                index,
                                duration: const Duration(milliseconds: 300),
                                curve: Curves.easeInOut,
                              );

                              // Update state after animation starts
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
            Expanded(
              child: PageView.builder(
                controller: pageController,
                itemCount: _pages.length,
                onPageChanged: (index) {
                  // Update the selected mode when page changes (from swiping)
                  if (_TournamentDetailScreenMode.values.indexOf(
                        ref.read(selectedTourModeProvider),
                      ) !=
                      index) {
                    ref.read(selectedTourModeProvider.notifier).state =
                        _TournamentDetailScreenMode.values[index];
                  }
                },
                itemBuilder: (context, index) {
                  return _pages[index];
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TourDetailDropDownAppBar extends ConsumerWidget {
  const _TourDetailDropDownAppBar({
    required this.data,
    super.key,
  });

  final TourDetailViewModel data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      children: [
        SizedBox(width: 16.w),
        IconButton(
          iconSize: 24.ic,
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
            selectedId:
                ref.watch(selectedTourIdProvider) ?? data.tours.first.id,
            onChanged: (value) {
              ref
                  .read(tourDetailScreenProvider.notifier)
                  .updateSelection(value);
            },
          ),
        ),
        Spacer(),
        SizedBox(width: 44.w),
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
