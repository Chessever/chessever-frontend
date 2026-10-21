import 'package:chessever2/screens/countrymen/country_rankings_screen.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/country_utils.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/app_snack.dart';
import 'package:chessever2/widgets/federation_flag.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class PlayerProfileInfoRow extends StatelessWidget {
  const PlayerProfileInfoRow({
    super.key,
    required this.fideId,
    required this.federation,
    this.isMemorial = false,
  });

  final int? fideId;
  final String federation;
  final bool isMemorial;

  Future<void> _openFideProfile(BuildContext context) async {
    try {
      if (await launchUrl(
        Uri.https('ratings.fide.com', '/profile/$fideId'),
        mode: LaunchMode.externalApplication,
      )) {
        return;
      }
    } catch (_) {
      // Platform failures use the same transient message as a declined launch.
    }
    if (!context.mounted) return;
    showAppSnack(
      context,
      'Could not open the FIDE profile.',
      tone: AppSnackTone.danger,
    );
  }

  @override
  Widget build(BuildContext context) {
    final rawFederation = federation.trim();
    final code = CountryUtils.resolveFideCode(
      rawFederation.length == 2
          ? CountryUtils.toFideCode(rawFederation)
          : rawFederation,
    );
    final countryName = code == null ? '' : CountryUtils.getCountryName(code);
    final countryLabel = countryName.isEmpty ? rawFederation : countryName;
    final hasFideId = (fideId ?? 0) > 0;
    final VoidCallback? openRankings = code == null
        ? null
        : () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => CountryRankingsScreen(federation: code),
            ),
          );
    final VoidCallback? openFide = hasFideId
        ? () => _openFideProfile(context)
        : null;

    final country = Semantics(
      button: code != null,
      label: code == null ? null : 'Open $countryLabel rankings',
      excludeSemantics: code != null,
      onTap: openRankings,
      child: InkWell(
        borderRadius: BorderRadius.circular(8.br),
        onTap: openRankings,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: EdgeInsets.all(8.sp),
            child: Row(
              children: [
                if (FederationFlag.hasVisibleFlag(rawFederation)) ...[
                  FederationFlag(
                    federation: rawFederation,
                    width: 28.w,
                    height: 20.h,
                  ),
                  SizedBox(width: 10.w),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        countryLabel,
                        style: AppTypography.textSmMedium.copyWith(
                          color: context.colors.textPrimary,
                        ),
                      ),
                      Text(
                        'Federation',
                        style: AppTypography.textXsRegular.copyWith(
                          color: context.colors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                if (code != null) ...[
                  SizedBox(width: 6.w),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 18.ic,
                    color: context.colors.textSecondary,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );

    final fide = Semantics(
      button: hasFideId,
      link: hasFideId,
      label: hasFideId ? 'Open FIDE profile $fideId' : null,
      excludeSemantics: hasFideId,
      onTap: openFide,
      child: Material(
        color: context.colors.surfaceRecessed,
        borderRadius: BorderRadius.circular(8.br),
        child: InkWell(
          onTap: openFide,
          borderRadius: BorderRadius.circular(8.br),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Wrap(
                    alignment: WrapAlignment.center,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 6.w,
                    children: [
                      Text(
                        hasFideId ? fideId.toString() : 'Not assigned',
                        style: AppTypography.textSmBold.copyWith(
                          color: context.colors.textPrimary,
                          fontFamily: 'monospace',
                        ),
                      ),
                      if (hasFideId)
                        Icon(
                          Icons.open_in_new_rounded,
                          size: 14.ic,
                          color: context.colors.textSecondary,
                        ),
                    ],
                  ),
                  Text(
                    isMemorial ? 'Historical FIDE ID' : 'FIDE ID',
                    style: AppTypography.textXsRegular.copyWith(
                      color: context.colors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    return Material(
      color: context.colors.surface,
      borderRadius: BorderRadius.circular(12.br),
      child: Padding(
        padding: EdgeInsets.all(8.sp),
        child: LayoutBuilder(
          builder: (context, constraints) {
            if (rawFederation.isEmpty) return Align(child: fide);
            if (constraints.maxWidth < 300 ||
                MediaQuery.textScalerOf(context).scale(14) > 18) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  country,
                  SizedBox(height: 8.h),
                  fide,
                ],
              );
            }
            return Row(
              children: [
                Expanded(child: country),
                SizedBox(width: 8.w),
                fide,
              ],
            );
          },
        ),
      ),
    );
  }
}
