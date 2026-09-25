import 'package:cached_network_image/cached_network_image.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/federation_flag.dart';
import 'package:flutter/material.dart';

/// "Carlsen, Magnus" and "Magnus Carlsen" both read "MC"; one word reads its
/// first two letters.
String spaceInitials(String name) {
  final clean = name.replaceAll(',', ' ').trim();
  if (clean.isEmpty) return '?';
  final parts = clean.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.length == 1) {
    final only = parts.first;
    return (only.length <= 2 ? only : only.substring(0, 2)).toUpperCase();
  }
  final commaFirst = name.contains(',');
  final first = commaFirst ? parts[1] : parts.first;
  final last = commaFirst ? parts.first : parts.last;
  return '${first[0]}${last[0]}'.toUpperCase();
}

/// The title band: a quiet strip in the page's own ink (a dark veil in dark,
/// a paper veil in light) and no hue of its own, so a row of faces reads as
/// faces in the page's monochrome rather than a row of tinted badges.
Color _bandFill(BuildContext context) => context.isLightTheme
    ? const Color(0xFFFFFFFF).withValues(alpha: 0.88)
    : const Color(0xFF0C0C0E).withValues(alpha: 0.72);

/// The title band's label: the page's own text ink on its veil.
Color _bandInk(BuildContext context) => context.isLightTheme
    ? AppColors.light.textPrimary
    : const Color(0xFFFFFFFF).withValues(alpha: 0.92);

/// A person's face wherever My Space shows one: the FIDE photo in a circle,
/// or their initials on a flat recessed disc when there is no photo (never
/// a gradient), the title (GM, IM...) on a quiet veil across the chin, and
/// the federation's flag cut into the top-right of the circle.
///
/// The photo carries a hairline outline in the page's own ink (white at 10%
/// in dark, black at 10% in light), so a pale photo keeps its edge on any
/// surface. [ring] is the colour the flag is cut out of: the surface the
/// face sits on.
class SpacePlayerAvatar extends StatelessWidget {
  const SpacePlayerAvatar({
    super.key,
    required this.size,
    required this.name,
    this.photoUrl,
    this.title,
    this.federation,
    this.ring,
  });

  final double size;
  final String name;
  final String? photoUrl;
  final String? title;
  final String? federation;
  final Color? ring;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final light = context.isLightTheme;
    final label = title?.trim().toUpperCase();
    final hasTitle = label != null && label.isNotEmpty && label.length <= 3;
    final band = hasTitle ? (size * 0.25).roundToDouble() : 0.0;
    final initials = spaceInitials(name);

    Widget disc() => ColoredBox(
      color: colors.surfaceRecessed,
      child: Padding(
        // The initials centre in what the band leaves clear.
        padding: EdgeInsets.only(bottom: band),
        child: Center(
          child: Text(
            initials,
            maxLines: 1,
            softWrap: false,
            // Sized to the face, not to reading text.
            textScaler: TextScaler.noScaling,
            style: TextStyle(
              fontFamily: 'InterDisplay',
              fontSize: size * (hasTitle ? 0.3 : 0.34),
              height: 1,
              leadingDistribution: TextLeadingDistribution.even,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.4,
              color: colors.textPrimaryMuted,
            ),
          ),
        ),
      ),
    );

    final url = photoUrl?.trim();
    final photo = url == null || url.isEmpty
        ? disc()
        : CachedNetworkImage(
            imageUrl: url,
            width: size,
            height: size,
            fit: BoxFit.cover,
            memCacheWidth: (size * MediaQuery.devicePixelRatioOf(context))
                .round(),
            fadeInDuration: const Duration(milliseconds: 120),
            fadeOutDuration: Duration.zero,
            placeholder: (_, _) => disc(),
            errorWidget: (_, _, _) => disc(),
          );

    final fill = hasTitle ? _bandFill(context) : null;
    final face = ClipOval(
      child: SizedBox.square(
        dimension: size,
        child: Stack(
          fit: StackFit.expand,
          children: [
            photo,
            if (fill != null)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: band,
                child: ColoredBox(
                  color: fill,
                  child: Center(
                    child: Text(
                      label!,
                      maxLines: 1,
                      softWrap: false,
                      textScaler: TextScaler.noScaling,
                      style: TextStyle(
                        fontFamily: 'InterDisplay',
                        fontSize: band * 0.58,
                        height: 1,
                        leadingDistribution: TextLeadingDistribution.even,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.3,
                        color: _bandInk(context),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );

    final outline = DecoratedBox(
      position: DecorationPosition.foreground,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: (light ? Colors.black : Colors.white).withValues(alpha: 0.1),
        ),
      ),
      child: face,
    );

    final showFlag = FederationFlag.hasVisibleFlag(federation);
    if (!showFlag) return SizedBox.square(dimension: size, child: outline);
    final flagWidth = (size * 0.3).roundToDouble();
    final cut = 2.w;
    return SizedBox.square(
      dimension: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          outline,
          Positioned(
            // On the circle's rim at one o'clock, set out past it by a
            // share of the face, so it scales with the circle and its foot
            // stays above the initials' cap line at every size.
            right: -cut - size * 0.04,
            top: -cut - size * 0.07,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: ring ?? colors.background,
                borderRadius: BorderRadius.circular(3.w),
              ),
              child: Padding(
                padding: EdgeInsets.all(cut),
                child: FederationFlag(
                  federation: federation,
                  width: flagWidth,
                  height: flagWidth * 0.75,
                  borderRadius: BorderRadius.circular(2.w),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A federation as a face: its flag filling the circle, for a saved
/// Countrymen shortcut among saved players.
class SpaceFlagAvatar extends StatelessWidget {
  const SpaceFlagAvatar({super.key, required this.size, required this.country});

  final double size;
  final String country;

  @override
  Widget build(BuildContext context) {
    final light = context.isLightTheme;
    return SizedBox.square(
      dimension: size,
      child: DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: (light ? Colors.black : Colors.white).withValues(alpha: 0.1),
          ),
        ),
        child: ClipOval(
          child: ColoredBox(
            color: context.colors.surfaceRecessed,
            child: FittedBox(
              fit: BoxFit.cover,
              child: FederationFlag(
                federation: country,
                width: size * 4 / 3,
                height: size,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
