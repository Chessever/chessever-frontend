import 'package:chessever2/screens/tournaments/tournament_detail_view.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/location_service_provider.dart';
import 'package:chessever2/utils/png_asset.dart';
import 'package:chessever2/utils/svg_asset.dart';
import 'package:chessever2/utils/url_launcher_provider.dart';
import 'package:chessever2/widgets/network_image_widget.dart';
import 'package:chessever2/widgets/svg_widget.dart';
import 'package:country_flags/country_flags.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class AboutTourScreen extends ConsumerWidget {
  const AboutTourScreen({super.key});

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
              _CountryFlag(
                title: 'Location',
                flag: CountryFlag.fromCountryCode(
                  ref
                      .read(locationServiceProvider)
                      .getCountryCode(aboutTourModel.location),
                  width: 16,
                  height: 12,
                ),
                description: aboutTourModel.location,
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

class _CountryFlag extends StatelessWidget {
  const _CountryFlag({
    required this.title,
    required this.flag,
    required this.description,
    super.key,
  });

  final String title;
  final Widget flag;
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
        Row(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            flag,
            SizedBox(width: 4),
            Text(
              description,
              style: AppTypography.textXsMedium.copyWith(color: kWhiteColor),
            ),
          ],
        ),
      ],
    );
  }
}
