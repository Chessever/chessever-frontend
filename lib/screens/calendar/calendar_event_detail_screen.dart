import 'package:chessever2/e2e/e2e_ids.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:chessever2/repository/supabase/calendar_event/calendar_event.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/png_asset.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/svg_asset.dart';
import 'package:chessever2/widgets/svg_widget.dart';
import 'package:country_flags/country_flags.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

class CalendarEventDetailScreen extends StatelessWidget {
  const CalendarEventDetailScreen({super.key, required this.event});

  final CalendarEvent event;

  String _formatDateRange() {
    final dateFormat = DateFormat('MMM d, yyyy');
    if (event.startDate == null && event.endDate == null) {
      return 'TBA';
    }
    if (event.startDate != null && event.endDate != null) {
      return '${dateFormat.format(event.startDate!)} - ${dateFormat.format(event.endDate!)}';
    }
    if (event.startDate != null) {
      return dateFormat.format(event.startDate!);
    }
    return dateFormat.format(event.endDate!);
  }

  String _extractDomain() {
    if (event.websiteUrl == null || event.websiteUrl!.isEmpty) return '';
    try {
      final uri = Uri.parse(event.websiteUrl!);
      return uri.host.replaceFirst('www.', '');
    } catch (_) {
      return '';
    }
  }

  List<String> _getTopPlayers() {
    if (event.players == null || event.players!.isEmpty) return [];

    final playerNames = <Map<String, dynamic>>[];

    for (final p in event.players!) {
      if (p is String && p.isNotEmpty) {
        playerNames.add({'name': p, 'rating': 0});
      } else if (p is Map) {
        final name = p['name']?.toString() ?? '';
        final rating = p['rating'] ?? 0;
        if (name.isNotEmpty) {
          playerNames.add({'name': name, 'rating': rating is int ? rating : 0});
        }
      }
    }

    // Sort by rating if available
    playerNames.sort(
      (a, b) => (b['rating'] as int).compareTo(a['rating'] as int),
    );

    return playerNames.take(4).map((p) => p['name'] as String).toList();
  }

  Future<void> _launchWebsite() async {
    if (event.websiteUrl != null && event.websiteUrl!.isNotEmpty) {
      final uri = Uri.parse(event.websiteUrl!);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final domain = _extractDomain();
    final topPlayers = _getTopPlayers();

    return Scaffold(
      key: e2eKey(E2eIds.calendarEventDetailRoot),
      backgroundColor: context.colors.background,
      appBar: AppBar(
        title: Text(
          event.name,
          style: AppTypography.textLgBold.copyWith(
            color: context.colors.textPrimary,
          ),
        ),
        backgroundColor: context.colors.surface,
        iconTheme: IconThemeData(color: context.colors.iconPrimary),
      ),
      bottomNavigationBar: _buildBottomBar(context, domain),
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: ResponsiveHelper.contentMaxWidth,
          ),
          child: Container(
            margin: EdgeInsets.symmetric(
              horizontal: ResponsiveHelper.adaptive(
                phone: 20.sp,
                tablet: 32.sp,
              ),
            ),
            child: SingleChildScrollView(
              padding: EdgeInsets.zero,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(height: 16.h),
                  ClipRRect(
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(12.br),
                      topRight: Radius.circular(12.br),
                    ),
                    child: SizedBox(
                      height: 240.h,
                      width: double.infinity,
                      child: _buildHeroImage(context),
                    ),
                  ),
                  SizedBox(height: 12.h),
                  if (event.description != null &&
                      event.description!.isNotEmpty) ...[
                    SelectableText(
                      event.description!,
                      style: AppTypography.textSmMedium.copyWith(
                        color: context.colors.textPrimaryMuted,
                      ),
                    ),
                    SizedBox(height: 12.h),
                  ],
                  if (topPlayers.isNotEmpty) ...[
                    _TitleDescWidget(
                      title: 'Players',
                      description: topPlayers.join(', '),
                    ),
                    SizedBox(height: 12.h),
                  ],
                  _TitleDescWidget(
                    title: 'Time Control',
                    description: event.timeControl ?? 'Standard',
                  ),
                  SizedBox(height: 12.h),
                  _TitleDescWidget(
                    title: 'Date',
                    description: _formatDateRange(),
                  ),
                  SizedBox(height: 12.h),
                  _CountryFlag(
                    title: 'Location',
                    flag:
                        event.countryCode != null &&
                                event.countryCode!.isNotEmpty
                            ? CountryFlag.fromCountryCode(
event.countryCode!,
  theme: ImageTheme(width: 16.w,
                              height: 12.h,),
)
                            : null,
                    description: event.location ?? 'TBA',
                  ),
                  SizedBox(height: MediaQuery.of(context).viewPadding.bottom),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeroImage(BuildContext context) {
    if (event.imageUrl != null && event.imageUrl!.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: event.imageUrl!,
        fit: BoxFit.cover,
        memCacheWidth:
            (MediaQuery.sizeOf(context).width *
                    MediaQuery.devicePixelRatioOf(context))
                .toInt(),
        fadeInDuration: const Duration(milliseconds: 300),
        fadeOutDuration: const Duration(milliseconds: 200),
        alignment: Alignment.topCenter,
        placeholder: (context, url) => _buildPlaceholder(context),
        errorWidget: (context, url, error) => _buildPlaceholder(context),
      );
    }
    return _buildPlaceholder(context);
  }

  Widget _buildPlaceholder(BuildContext context) {
    // Show country flag as placeholder if available
    if (event.countryCode != null && event.countryCode!.isNotEmpty) {
      return Container(
        height: 240.h,
        color: kLightBlack,
        alignment: Alignment.center,
        child: SizedBox(
          width: 120.w,
          height: 80.h,
          child: CountryFlag.fromCountryCode(
event.countryCode!,
  theme: ImageTheme(shape: const RoundedRectangle(12),
),
          ),
        ),
      );
    }
    return Container(
      height: 240.h,
      color: kLightBlack,
      alignment: Alignment.center,
      child: Image.asset(
        PngAsset.premiumIcon,
        height: 100.h,
        fit: BoxFit.contain,
        cacheHeight: (100 * MediaQuery.devicePixelRatioOf(context)).toInt(),
      ),
    );
  }

  Widget _buildBottomBar(BuildContext context, String domain) {
    if (domain.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewPadding.bottom,
      ),
      child: GestureDetector(
        onTap: _launchWebsite,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SvgWidget(SvgAsset.websiteIcon, height: 12.h, width: 12.h),
            SizedBox(width: 4.w),
            Flexible(
              child: Text(
                domain,
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
    );
  }
}

class _TitleDescWidget extends StatelessWidget {
  const _TitleDescWidget({required this.title, required this.description});

  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: AppTypography.textXsMedium.copyWith(
            color: context.colors.textPrimaryMuted,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          description,
          style: AppTypography.textXsMedium.copyWith(
            color: context.colors.textPrimary,
          ),
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
          style: AppTypography.textXsMedium.copyWith(
            color: context.colors.textPrimaryMuted,
          ),
        ),
        SizedBox(height: 8.h),
        Row(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            if (flag != null) ...[flag!, SizedBox(width: 4.w)],
            Flexible(
              child: Text(
                description,
                maxLines: 1,
                style: AppTypography.textXsMedium.copyWith(
            color: context.colors.textPrimary,
          ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
