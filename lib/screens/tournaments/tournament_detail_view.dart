import 'package:chessever2/screens/tournaments/model/about_tour_model.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/png_asset.dart';
import 'package:chessever2/utils/svg_asset.dart';
import 'package:chessever2/utils/url_launcher_provider.dart';
import 'package:chessever2/widgets/chessever_app_bar.dart';
import 'package:chessever2/widgets/network_image_widget.dart';
import 'package:chessever2/widgets/screen_wrapper.dart';
import 'package:chessever2/widgets/segmented_switcher.dart';
import 'package:chessever2/widgets/svg_widget.dart';
import 'package:country_picker/country_picker.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final aboutTourModelProvider = StateProvider<AboutTourModel?>((ref) => null);

final selectedTourModeProvider = StateProvider<_TournamentDetailScreenMode>(
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
          children: [
            SizedBox(height: MediaQuery.of(context).viewPadding.top + 24),
            ChessEverAppBar(title: ref.read(aboutTourModelProvider)!.name),
            SizedBox(height: 36),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20.0),
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
            SizedBox(height: 12),
            Expanded(
              child: IndexedStack(
                index: selectedTourMode.index,
                children: const [_AboutView(), _GamesView(), _StandingsView()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AboutView extends ConsumerWidget {
  const _AboutView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final aboutTourModel = ref.watch(aboutTourModelProvider)!;

    return Scaffold(
      bottomNavigationBar: Container(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewPadding.bottom,
        ),
        child: GestureDetector(
          onTap:
              () => ref
                  .read(urlLauncherProvider)
                  .launchUrl(aboutTourModel.websiteUrl),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SvgWidget(SvgAsset.websiteIcon, height: 12, width: 12),
              SizedBox(width: 4),
              Text(
                aboutTourModel.extractDomain(),
                maxLines: 1,
                style: AppTypography.textXsMedium.copyWith(
                  color: kPrimaryColor,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
      body: Container(
        margin: EdgeInsets.symmetric(horizontal: 20),
        child: SingleChildScrollView(
          padding: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(12),
                  topRight: Radius.circular(12),
                ),
                child: NetworkImageWidget(
                  height: 240,
                  imageUrl: aboutTourModel.imageUrl,
                  placeHolder: PngAsset.premiumIcon,
                ),
              ),
              SizedBox(height: 12),
              Text(
                aboutTourModel.description,
                style: AppTypography.textSmMedium.copyWith(
                  color: kWhiteColor70,
                ),
              ),
              SizedBox(height: 12),
              _TitleDescWidget(
                title: 'Players',
                description: aboutTourModel.players.join(', '),
              ),
              SizedBox(height: 12),
              _TitleDescWidget(
                title: 'Time Control',
                description: aboutTourModel.timeControl,
              ),
              SizedBox(height: 12),
              _TitleDescWidget(title: 'Date', description: aboutTourModel.date),
              SizedBox(height: 12),
              _TitleDescWidget(
                title: 'Location',
                description:
                    '${CountryService().findByName(aboutTourModel.location)} ${aboutTourModel.location}',
              ),
              SizedBox(height: MediaQuery.of(context).viewPadding.bottom),
            ],
          ),
        ),
      ),
    );
  }
}

class _TitleDescWidget extends StatelessWidget {
  const _TitleDescWidget({
    required this.title,
    required this.description,
    super.key,
  });

  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: AppTypography.textXsMedium.copyWith(color: kWhiteColor70),
        ),
        SizedBox(height: 8),
        Text(
          description,
          style: AppTypography.textXsMedium.copyWith(color: kWhiteColor),
        ),
      ],
    );
  }
}

class _GamesView extends StatelessWidget {
  const _GamesView({super.key});

  @override
  Widget build(BuildContext context) {
    return const Placeholder();
  }
}

class _StandingsView extends StatelessWidget {
  const _StandingsView({super.key});

  @override
  Widget build(BuildContext context) {
    return const Placeholder();
  }
}
