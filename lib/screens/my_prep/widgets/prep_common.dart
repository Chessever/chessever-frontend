import 'package:chessever2/screens/my_prep/models/prep_models.dart';
import 'package:chessever2/screens/my_prep/services/prep_analysis.dart';
import 'package:chessever2/services/fide_photo_service.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/png_asset.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/federation_flag.dart';
import 'package:chessever2/widgets/player_initials_avatar.dart';
import 'package:chessever2/widgets/time_control_glyph.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Chess.com's green, used only on its own mark and source chips.
const Color kChessComGreen = Color(0xFF81B64C);

double prepSegmentHeight(BuildContext context, {bool wrapLabels = false}) {
  final scaler = MediaQuery.textScalerOf(context);
  final lines = wrapLabels && scaler.scale(12) > 15 ? 2 : 1;
  return (scaler.scale(AppTypography.textSmMedium.fontSize ?? 14) *
              (AppTypography.textSmMedium.height ?? 1.4) *
              lines +
          16.h)
      .clamp(44.0, double.infinity);
}

/// The app's own time-control mark for a clock category, as desktop draws
/// them. Correspondence has no art, so it falls back to a plain glyph.
class PrepClockGlyph extends StatelessWidget {
  const PrepClockGlyph(this.clock, {super.key, required this.size});
  final PrepTimeControl clock;
  final double size;

  static String? assetFor(PrepTimeControl clock) => switch (clock) {
    PrepTimeControl.ultrabullet => PngAsset.ultraBulletIcon,
    PrepTimeControl.bullet => PngAsset.bulletIcon,
    PrepTimeControl.blitz => PngAsset.blitzIcon,
    PrepTimeControl.rapid => PngAsset.rapidIcon,
    PrepTimeControl.classical => PngAsset.classicalIcon,
    PrepTimeControl.correspondence => null,
  };

  @override
  Widget build(BuildContext context) {
    final asset = assetFor(clock);
    return asset == null
        ? Icon(
            Icons.mail_outline_rounded,
            size: size,
            color: context.colors.iconSecondary,
          )
        : TimeControlGlyph(asset, size: size);
  }
}

/// Real provider marks, directly on the app surface.
class PrepSourceMark extends StatelessWidget {
  const PrepSourceMark({super.key, required this.source, this.size = 20});

  final PrepSource source;
  final double size;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: SizedBox(
        width: size,
        height: size,
        child: switch (source) {
          PrepSource.lichess => SvgPicture.asset(
            'assets/svgs/lichess_logo.svg',
            width: size,
            height: size,
            colorFilter: ColorFilter.mode(
              context.colors.textPrimary,
              BlendMode.srcIn,
            ),
          ),
          PrepSource.chesscom => Image.asset(
            'assets/pngs/chesscom_pawn.png',
            width: size,
            height: size,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.medium,
          ),
          // Isolate the mark from the existing transparent logo lockup.
          // Its 504 x 480 bounds sit centered in a 528 x 528 source viewport;
          // the wordmark below it stays outside that viewport.
          PrepSource.chessever => ClipRect(
            child: Stack(
              children: [
                Positioned(
                  left: -size * 326 / 528,
                  top: size * 24 / 528,
                  width: size * 1180 / 528,
                  height: size * 624 / 528,
                  child: Image.asset(
                    'assets/pngs/chessever.png',
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.medium,
                  ),
                ),
              ],
            ),
          ),
          PrepSource.manual => Icon(
            Icons.description_outlined,
            size: size,
            color: context.colors.textPrimary,
          ),
        },
      ),
    );
  }
}

/// Text for work in progress. A band of the primary ink travels across the
/// label, so "Downloading games…" reads as running rather than as a caption.
/// With animations disabled it is plain text.
class PrepShimmerText extends StatefulWidget {
  const PrepShimmerText(
    this.text, {
    super.key,
    required this.style,
    this.semanticsLabel,
  });

  final String text;
  final TextStyle style;
  final String? semanticsLabel;

  @override
  State<PrepShimmerText> createState() => _PrepShimmerTextState();
}

class _PrepShimmerTextState extends State<PrepShimmerText>
    with SingleTickerProviderStateMixin {
  // Constant motion, so the sweep is linear and never eases.
  late final _sweep = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _sweep.stop();
    } else if (!_sweep.isAnimating) {
      _sweep.repeat();
    }
  }

  @override
  void dispose() {
    _sweep.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = Text(
      widget.text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      semanticsLabel: widget.semanticsLabel,
      style: widget.style,
    );
    if (MediaQuery.disableAnimationsOf(context)) return text;
    final base = widget.style.color ?? context.colors.textSecondary;
    final highlight = context.colors.textPrimary;
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _sweep,
        child: text,
        builder: (context, child) {
          // The band starts fully off the left edge and leaves off the right.
          final center = -2 + 4 * _sweep.value;
          return ShaderMask(
            blendMode: BlendMode.srcIn,
            shaderCallback: (bounds) => LinearGradient(
              begin: Alignment(center - 1, 0),
              end: Alignment(center + 1, 0),
              colors: [base, highlight, base],
            ).createShader(bounds),
            child: child,
          );
        },
      ),
    );
  }
}

/// Evenly spaced source marks. No brand is covered by its neighbour.
class PrepSourceMarks extends StatelessWidget {
  const PrepSourceMarks({super.key, required this.sources, this.size = 18});

  final Iterable<PrepSource> sources;
  final double size;

  @override
  Widget build(BuildContext context) {
    final list = sources.toSet().toList()
      ..sort((a, b) => a.index.compareTo(b.index));
    if (list.isEmpty) return const SizedBox.shrink();
    final step = size + 6;
    return SizedBox(
      width: size + step * (list.length - 1),
      height: size,
      child: Stack(
        children: [
          for (var i = 0; i < list.length; i++)
            Positioned(
              left: step * i,
              child: PrepSourceMark(source: list[i], size: size),
            ),
        ],
      ),
    );
  }
}

final _fidePhotoProvider = FutureProvider.autoDispose.family<String?, String?>(
  (ref, fideId) => FidePhotoService.getPhotoUrlOrNull(fideId),
);

/// A profile's picture: its FIDE photo for famous players, a Chess.com
/// avatar when one exists, or initials, with the title band the app's
/// player cards use.
class PrepAvatar extends ConsumerWidget {
  const PrepAvatar({
    super.key,
    required this.name,
    required this.size,
    this.photoUrl,
    this.fideId,
    this.title,
    this.borderRadius,
  });

  final String name;
  final double size;
  final String? photoUrl;
  final String? fideId;
  final String? title;
  final double? borderRadius;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fidePhoto = fideId == null
        ? null
        : ref.watch(_fidePhotoProvider(fideId)).valueOrNull;
    return PlayerInitialsAvatar(
      photoUrl: fidePhoto ?? photoUrl,
      initials: prepInitials(name),
      size: size,
      borderRadius: borderRadius ?? 8.br,
      title: title,
    );
  }
}

String prepInitials(String name) {
  final words = name
      .split(RegExp(r'[\s_\-]+'))
      .where((w) => w.isNotEmpty)
      .toList();
  if (words.isEmpty) return '?';
  if (words.length == 1) {
    return words.first
        .substring(0, words.first.length.clamp(0, 2))
        .toUpperCase();
  }
  return (words.first[0] + words.last[0]).toUpperCase();
}

/// A small flag, or nothing when the country is unknown.
class PrepFlag extends StatelessWidget {
  const PrepFlag({super.key, required this.country});
  final String? country;

  @override
  Widget build(BuildContext context) {
    if (!FederationFlag.hasVisibleFlag(country)) return const SizedBox.shrink();
    return Padding(
      padding: EdgeInsets.only(right: 6.w),
      child: FederationFlag(
        federation: country,
        width: 16.w,
        height: 11.h,
        borderRadius: BorderRadius.circular(2.br),
      ),
    );
  }
}

/// Wins, draws and losses as one proportional bar.
class PrepResultBar extends StatelessWidget {
  const PrepResultBar({super.key, required this.tally, this.height = 6});

  final PrepTally tally;
  final double height;

  @override
  Widget build(BuildContext context) {
    final total = tally.total;
    final colors = context.colors;
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: SizedBox(
        height: height,
        child: total == 0
            ? ColoredBox(color: colors.surfaceRecessed)
            : Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (tally.wins > 0)
                    Expanded(
                      flex: tally.wins,
                      child: ColoredBox(color: colors.brand),
                    ),
                  if (tally.draws > 0)
                    Expanded(
                      flex: tally.draws,
                      child: ColoredBox(color: colors.textTertiary),
                    ),
                  if (tally.losses > 0)
                    Expanded(
                      flex: tally.losses,
                      child: ColoredBox(color: colors.danger),
                    ),
                ],
              ),
      ),
    );
  }
}

/// `+12 =4 −3`, coloured like the bar.
class PrepTallyText extends StatelessWidget {
  const PrepTallyText({super.key, required this.tally, this.style});

  final PrepTally tally;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final base = (style ?? AppTypography.textXsMedium).copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final colors = context.colors;
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '+${tally.wins}',
            style: base.copyWith(color: colors.accentText),
          ),
          TextSpan(
            text: '  =${tally.draws}',
            style: base.copyWith(color: colors.textSecondary),
          ),
          TextSpan(
            text: '  −${tally.losses}',
            style: base.copyWith(color: colors.danger),
          ),
        ],
      ),
      semanticsLabel:
          '${tally.wins} wins, ${tally.draws} draws, ${tally.losses} losses',
    );
  }
}

/// A row of headline numbers, in the player profile's stat style.
class PrepStatStrip extends StatelessWidget {
  const PrepStatStrip({super.key, required this.items});

  final List<(String label, String value)> items;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8.sp, vertical: 14.sp),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(12.br),
      ),
      child: Row(
        children: [
          for (final (label, value) in items)
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.textXsMedium.copyWith(
                      color: context.colors.textPrimaryMuted,
                    ),
                  ),
                  SizedBox(height: 4.h),
                  Text(
                    value,
                    maxLines: 1,
                    style: AppTypography.textLgBold.copyWith(
                      color: context.colors.textPrimary,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// "Synced 3 h ago" style wording.
String prepSyncedAgo(int? ms) {
  if (ms == null) return 'Not downloaded yet';
  final diff = DateTime.now().difference(
    DateTime.fromMillisecondsSinceEpoch(ms),
  );
  if (diff.inMinutes < 1) return 'Updated just now';
  if (diff.inMinutes < 60) return 'Updated ${diff.inMinutes} min ago';
  if (diff.inHours < 24) return 'Updated ${diff.inHours} h ago';
  if (diff.inDays == 1) return 'Updated yesterday';
  return 'Updated ${diff.inDays} days ago';
}

String prepCount(int n) {
  if (n < 1000) return '$n';
  final text = n.toString();
  final buffer = StringBuffer();
  for (var i = 0; i < text.length; i++) {
    if (i > 0 && (text.length - i) % 3 == 0) buffer.write(',');
    buffer.write(text[i]);
  }
  return buffer.toString();
}

String prepGamesLabel(int n) => n == 1 ? '1 game' : '${prepCount(n)} games';
