import 'package:cached_network_image/cached_network_image.dart';
import 'package:chessever2/screens/group_event/model/about_tour_model.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_mode_provider.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_screen_provider.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/location_service_provider.dart';
import 'package:chessever2/utils/png_asset.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/svg_asset.dart';
import 'package:chessever2/utils/url_launcher_provider.dart';
import 'package:chessever2/widgets/heroine/no_padding_fade_shuttle_builder.dart';
import 'package:chessever2/widgets/logo_pattern_fallback.dart';
import 'package:chessever2/widgets/svg_widget.dart';
import 'package:country_flags/country_flags.dart';
import 'package:flutter/material.dart';
import 'package:heroine/heroine.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:skeletonizer/skeletonizer.dart';

class AboutTourScreen extends ConsumerStatefulWidget {
  const AboutTourScreen({super.key});

  @override
  ConsumerState<AboutTourScreen> createState() => _AboutTourScreenState();
}

class _AboutTourScreenState extends ConsumerState<AboutTourScreen> {
  static const _skeletonEffect = ShimmerEffect(
    baseColor: Color(0xFF2A2A2A),
    highlightColor: Color(0xFF3A3A3A),
    duration: Duration(seconds: 1),
  );

  static const AboutTourModel _fallbackAboutModel = AboutTourModel(
    id: 'Chessever',
    name: 'Chessever',
    description: 'Chessever',
    imageUrl: '',
    players: [],
    timeControl: 'Chessever',
    date: 'Chessever',
    location: 'US',
    websiteUrl: 'https://www.chessever.com/',
  );

  late String _heroTag;
  bool _hasStableHeroTag = false;

  @override
  void initState() {
    super.initState();
    final selectedGroupId = ref.read(selectedBroadcastModelProvider)?.id;
    _hasStableHeroTag = selectedGroupId?.isNotEmpty ?? false;
    _heroTag = _buildHeroTag(selectedGroupId);
  }

  String _buildHeroTag(String? id) {
    final resolvedId = (id?.isNotEmpty ?? false) ? id : 'placeholder';
    return 'event-image-$resolvedId';
  }

  void _maybeUpdateHeroTagFromAbout(AboutTourModel about) {
    if (_hasStableHeroTag) {
      return;
    }

    final fallbackId =
        about.groupBroadcastId?.isNotEmpty == true
            ? about.groupBroadcastId
            : about.id.isNotEmpty
            ? about.id
            : null;

    if (fallbackId == null) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _hasStableHeroTag) {
        return;
      }
      setState(() {
        _heroTag = _buildHeroTag(fallbackId);
        _hasStableHeroTag = true;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final tourDetailAsync = ref.watch(tourDetailScreenProvider);

    tourDetailAsync.whenOrNull(
      data: (data) => _maybeUpdateHeroTagFromAbout(data.aboutTourModel),
    );

    final aboutModel = tourDetailAsync.when(
      data: (data) => data.aboutTourModel,
      loading: () => _fallbackAboutModel,
      error: (_, __) => _fallbackAboutModel,
    );

    final isSkeleton = tourDetailAsync.maybeWhen(
      data: (_) => false,
      orElse: () => true,
    );

    final countryCode = ref
        .read(locationServiceProvider)
        .getCountryCode(aboutModel.location);

    var ratedPlayers =
        aboutModel.players.where((p) => p.rating != null).toList();
    if (ratedPlayers.isNotEmpty) {
      ratedPlayers.sort((a, b) => b.rating!.compareTo(a.rating!));
      ratedPlayers = ratedPlayers.take(4).toList();
    }

    final domain = aboutModel.extractDomain();

    final horizontalPadding = ResponsiveHelper.adaptive(
      phone: 20.sp,
      tablet: 32.sp,
    );

    return Scaffold(
      bottomNavigationBar: _buildBottomBar(
        context,
        domain,
        isSkeleton,
        aboutModel,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: ResponsiveHelper.contentMaxWidth,
          ),
          child: Container(
            margin: EdgeInsets.symmetric(horizontal: horizontalPadding),
            child: SingleChildScrollView(
              padding: EdgeInsets.zero,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(height: 16.h),
                  Heroine(
                    tag: _heroTag,
                    flightShuttleBuilder: const NoPaddingFadeShuttleBuilder(),
                    child: ClipRRect(
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(12.br),
                        topRight: Radius.circular(12.br),
                      ),
                      child: SizedBox(
                        height: 240.h,
                        width: double.infinity,
                        child: _buildHeroChild(context, aboutModel, isSkeleton),
                      ),
                    ),
                  ),
                  SizedBox(height: 12.h),
                  Skeletonizer(
                    enabled: isSkeleton,
                    ignoreContainers: true,
                    effect: _skeletonEffect,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          aboutModel.description,
                          style: AppTypography.textSmMedium.copyWith(
                            color: kWhiteColor70,
                          ),
                        ),
                        SizedBox(height: 12.h),
                        _TitleDescWidget(
                          title: 'Players',
                          description: ratedPlayers
                              .map((e) => e.displayName)
                              .join(', '),
                        ),
                        SizedBox(height: 12),
                        _TitleDescWidget(
                          title: 'Time Control',
                          description: aboutModel.timeControl,
                        ),
                        SizedBox(height: 12.h),
                        _TitleDescWidget(
                          title: 'Date',
                          description: aboutModel.date,
                        ),
                        SizedBox(height: 12.h),
                        _CountryFlag(
                          title: 'Location',
                          flag:
                              countryCode.isNotEmpty
                                  ? CountryFlag.fromCountryCode(
                                    countryCode,
                                    width: 16.w,
                                    height: 12.h,
                                  )
                                  : null,
                          description: aboutModel.location,
                        ),
                        SizedBox(
                          height: MediaQuery.of(context).viewPadding.bottom,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeroChild(
    BuildContext context,
    AboutTourModel aboutModel,
    bool isSkeleton,
  ) {
    if (!isSkeleton && aboutModel.imageUrl.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: aboutModel.imageUrl,
        fit: BoxFit.cover,
        fadeInDuration: const Duration(milliseconds: 300),
        fadeOutDuration: const Duration(milliseconds: 200),
        alignment: Alignment.topCenter,
        placeholder: (context, url) => _buildHeroPlaceholder(),
        errorWidget: (context, url, error) => _buildHeroError(),
      );
    }

    return _buildHeroPlaceholder();
  }

  Widget _buildHeroPlaceholder() {
    return Container(
      height: 240.h,
      color: kLightBlack,
      alignment: Alignment.center,
      child: Image.asset(
        PngAsset.premiumIcon,
        height: 100.h,
        fit: BoxFit.contain,
      ),
    );
  }

  Widget _buildHeroError() {
    return SizedBox(
      height: 240.h,
      width: double.infinity,
      child: const LogoPatternFallback(),
    );
  }

  Widget _buildBottomBar(
    BuildContext context,
    String domain,
    bool isSkeleton,
    AboutTourModel aboutModel,
  ) {
    if (!isSkeleton && domain.isEmpty) {
      return const SizedBox.shrink();
    }

    return Skeletonizer(
      enabled: isSkeleton,
      ignoreContainers: true,
      effect: _skeletonEffect,
      child: Container(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewPadding.bottom,
        ),
        child: GestureDetector(
          onTap:
              isSkeleton
                  ? null
                  : () => ref
                      .read(urlLauncherProvider)
                      .launchCustomUrl(aboutModel.websiteUrl),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SvgWidget(SvgAsset.websiteIcon, height: 12.h, width: 12.h),
              SizedBox(width: 4.w),
              Flexible(
                child: Text(
                  domain.isEmpty ? 'Chessever' : domain,
                  maxLines: 1,
                  style: AppTypography.textXsMedium.copyWith(
                    color: kPrimaryColor,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
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
  final Widget? flag;
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
        SizedBox(height: 8.w),
        Row(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            if (flag != null) ...[flag!, SizedBox(width: 4.w)],
            Flexible(
              child: Text(
                description,
                maxLines: 1,
                style: AppTypography.textXsMedium.copyWith(color: kWhiteColor),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
