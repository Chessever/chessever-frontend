import 'dart:async';
import 'dart:math' as math;

import 'package:chessever2/screens/favorites/tabs/favorites_players_tab.dart';
import 'package:chessever2/screens/library/widgets/library_context_menu.dart';
import 'package:chessever2/screens/my_space/actions/space_menu_action.dart';
import 'package:chessever2/screens/my_space/models/space_shortcut.dart';
import 'package:chessever2/screens/my_space/widgets/pixel_flame.dart';
import 'package:chessever2/screens/player_profile/player_profile_screen.dart';
import 'package:chessever2/screens/streaks/models/streak_models.dart';
import 'package:chessever2/screens/streaks/streak_player_screen.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/federation_flag.dart';
import 'package:chessever2/widgets/player_initials_avatar.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:motor/motor.dart';

/// The wall's fire, one colour per level: ember, flame, blaze, inferno.
const List<Color> kWallFire = [
  Color(0xFFE4552A),
  Color(0xFFF59A3C),
  Color(0xFFFFB454),
  Color(0xFFFFE08A),
];

Color wallFireColor(StreakLevel level) => kWallFire[level.index];

/// The same four levels deepened for paper. The dark ramp brightens towards
/// yellow, which sits at 1.2 to 3.5:1 on the light card; this one keeps the
/// red-to-amber turn and holds 3.3:1 or more even at the chart's faintest
/// square.
const List<Color> kWallFireLight = [
  Color(0xFFB93C1C),
  Color(0xFFA8481A),
  Color(0xFF96590A),
  Color(0xFF7A5600),
];

/// [kWallFire] in dark, [kWallFireLight] on the light theme.
List<Color> wallFirePalette(BuildContext context) =>
    context.isLightTheme ? kWallFireLight : kWallFire;

/// "1105" -> "1,105".
String wallCount(int n) {
  final digits = n.abs().toString();
  final out = StringBuffer(n < 0 ? '-' : '');
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) out.write(',');
    out.write(digits[i]);
  }
  return out.toString();
}

/// "Carlsen, Magnus" and "Magnus Carlsen" both read "MC".
String wallInitials(String name) {
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

/// The wall's one text voice: InterDisplay at an exact size and line.
TextStyle wallText(
  double size,
  double line,
  FontWeight weight,
  Color color, {
  bool tabular = false,
  double? letterSpacing,
}) {
  return AppTypography.textSmMedium.copyWith(
    fontSize: size.f,
    height: line / size,
    fontWeight: weight,
    color: color,
    letterSpacing: letterSpacing,
    fontFeatures: tabular ? const [FontFeature.tabularFigures()] : null,
  );
}

/// The time-control glyphs the event cards already use.
String wallTimeClassAsset(StreakTimeClass tc) => switch (tc) {
  StreakTimeClass.standard => 'assets/pngs/classical.png',
  StreakTimeClass.rapid => 'assets/pngs/rapid.png',
  StreakTimeClass.blitz => 'assets/pngs/blitz.png',
};

/// "IND · 2727 · 32 y": whatever the row knows, nothing it does not.
String wallMeta(StreakRow row, {bool withAge = true}) {
  return [
    if (row.fed != null) row.fed!,
    if (row.rating != null && row.rating! > 0) '${row.rating}',
    if (withAge && row.age != null) '${row.age} y',
  ].join(' · ');
}

/// The player avatar as the design draws it: the app's photo avatar (or the
/// app's initials gradient), with the title strip cut by the circle along
/// its foot, and the federation flag notched into the top-right corner when
/// [showFlag] is on.
///
/// The strip is drawn here rather than by [PlayerInitialsAvatar] because at
/// 40 px that widget's strip grows to half the disc and slices the initials;
/// the design keeps it at 24 % and lifts the initials clear of it.
class WallAvatar extends ConsumerWidget {
  const WallAvatar({
    super.key,
    required this.row,
    required this.size,
    this.showFlag = false,
    this.ringColor,
  });

  final StreakRow row;
  final double size;
  final bool showFlag;

  /// The colour of the cut-out around the flag: whatever the avatar sits on.
  /// Defaults to the page background; a tile passes its own surface.
  final Color? ringColor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final photo = ref.watch(playerPhotoProvider(row.fideId)).valueOrNull;
    final hasPhoto = photo != null && photo.isNotEmpty;
    final title = row.title;
    final strip = (size * 0.24).roundToDouble();
    final initials = wallInitials(row.name);
    final flag = showFlag && FederationFlag.hasVisibleFlag(row.fed);
    final ring = 2.w;
    final initialsSize = (size * 0.38).roundToDouble();
    final initialsLift = title == null ? 0.0 : (strip * 0.55).roundToDouble();
    // On a small disc the flag's cut-out reaches the caps of the initials;
    // drop them just clear of it (toward the disc's true centre), never onto
    // the title strip. Larger discs clear the flag and stay as they were.
    var initialsDrop = 0.0;
    if (flag) {
      final flagBottom = size * 0.02 - ring + 13.5.w + 2 * ring;
      final capTop =
          (size - initialsLift - initialsSize) / 2 + initialsSize * 0.08;
      final room =
          (size - (title == null ? 0.0 : strip)) -
          (size - initialsLift + initialsSize) / 2 -
          2;
      initialsDrop = (flagBottom + 1 - capTop).clamp(0.0, math.max(room, 0.0));
    }

    final disc = ClipOval(
      child: SizedBox.square(
        dimension: size,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (hasPhoto)
              PlayerInitialsAvatar(
                photoUrl: photo,
                initials: initials,
                size: size,
                isCircular: true,
              )
            else
              DecoratedBox(
                decoration: const BoxDecoration(
                  gradient: kProfileInitialsGradient,
                ),
                child: Padding(
                  padding: EdgeInsets.only(
                    top: initialsDrop * 2,
                    bottom: initialsLift,
                  ),
                  child: Center(
                    child: Text(
                      initials,
                      maxLines: 1,
                      textScaler: TextScaler.noScaling,
                      style: AppTypography.textSmBold.copyWith(
                        fontSize: initialsSize,
                        height: 1,
                        letterSpacing: 1,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            if (title != null)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: strip,
                child: ColoredBox(
                  color: titleBadgeFill(context, getTitleBadgeColor(title)),
                  // Centred in the strip; with a line height of 1 the caps
                  // sit a hair above centre, which is where the chord the
                  // circle cuts is widest.
                  child: Center(
                    child: Text(
                      title,
                      maxLines: 1,
                      textScaler: TextScaler.noScaling,
                      style: AppTypography.textSmBold.copyWith(
                        fontSize: (strip * 0.72).clamp(7.0, 11.0),
                        height: 1,
                        fontWeight: FontWeight.w600,
                        // White in dark as shipped; on paper, whichever of
                        // white or ink clears AA on the deepened fill.
                        color: titleBadgeInk(
                          context,
                          titleBadgeFill(context, getTitleBadgeColor(title)),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );

    if (!flag) return ExcludeSemantics(child: disc);
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: size,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            disc,
            Positioned(
              right: size * 0.02 - ring,
              top: size * 0.02 - ring,
              // The ring is the colour underneath (the page, or the tile), so
              // the flag reads as cut out of the avatar rather than stuck on
              // top of it.
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: ringColor ?? context.colors.background,
                  borderRadius: BorderRadius.circular(3.w),
                ),
                child: Padding(
                  padding: EdgeInsets.all(ring),
                  child: FederationFlag(
                    federation: row.fed,
                    width: 18.w,
                    height: 13.5.w,
                    borderRadius: BorderRadius.circular(2.w),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A [PixelFlame] at its resting frame. A thousand-row list of flickering
/// flames is noise; the podium keeps the live ones.
class WallStillFlame extends StatelessWidget {
  const WallStillFlame({super.key, required this.streak, required this.size});

  final int streak;
  final double size;

  @override
  Widget build(BuildContext context) {
    return MediaQuery(
      data: MediaQuery.of(context).copyWith(disableAnimations: true),
      child: PixelFlame(streak: streak, size: size),
    );
  }
}

/// Press feedback for wall targets, on a motor spring: podium players give
/// a little ([pressScale]), list rows light up with a tonal wash instead.
class WallPressable extends StatefulWidget {
  const WallPressable({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.pressScale,
    this.wash,
    this.semanticLabel,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// Scale at full press, e.g. 0.97. Null keeps the size.
  final double? pressScale;

  /// Fill at full press. Null keeps the surface.
  final Color? wash;
  final String? semanticLabel;

  @override
  State<WallPressable> createState() => _WallPressableState();
}

class _WallPressableState extends State<WallPressable> {
  bool _pressed = false;

  void _set(bool v) {
    if (_pressed != v && mounted) setState(() => _pressed = v);
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: widget.onTap != null,
      label: widget.semanticLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _set(true),
        onTapUp: (_) => _set(false),
        onTapCancel: () => _set(false),
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        child: SingleMotionBuilder(
          motion: const CupertinoMotion.snappy(),
          value: _pressed ? 1.0 : 0.0,
          child: widget.child,
          builder: (context, p, child) {
            Widget out = child!;
            final wash = widget.wash;
            if (wash != null) {
              out = ColoredBox(
                color: wash.withValues(alpha: wash.a * p.clamp(0.0, 1.0)),
                child: out,
              );
            }
            final scale = widget.pressScale;
            if (scale != null) {
              out = Transform.scale(scale: 1 - (1 - scale) * p, child: out);
            }
            return out;
          },
        ),
      ),
    );
  }
}

/// Opens one player's streak card on [row]'s time control.
void openWallStreakCard(BuildContext context, StreakRow row) {
  HapticFeedbackService.cardTap();
  unawaited(
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => StreakPlayerScreen(
          fideId: row.fideId,
          initialClass: row.timeClass,
          fallbackName: row.displayName,
        ),
      ),
    ),
  );
}

void _openProfile(BuildContext context, StreakRow row) {
  unawaited(
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PlayerProfileScreen(
          fideId: row.fideId,
          playerName: row.displayName,
          title: row.title,
          federation: row.fed,
          // The profile's rating is classical; a rapid or blitz number
          // there would be mislabelled.
          rating: row.timeClass == StreakTimeClass.standard ? row.rating : null,
        ),
      ),
    ),
  );
}

/// The My Space shortcut for [row]: one per player, opening on this class.
SpaceShortcut wallStreakDraft(StreakRow row) {
  return SpaceShortcut.draft(
    kind: SpaceShortcutKind.streak,
    targetId: '${row.fideId}',
    title: row.displayName,
    subtitle: '${row.timeClass.label} streak',
    params: {
      'timeClass': row.timeClass.wire,
      // Raw "Surname, First", as the player card stores it: the tile's
      // surname and initials read it once the player drops off the wall.
      'playerName': row.name,
      if (row.title != null) 'title': row.title,
      if (row.fed != null) 'fed': row.fed,
    },
  );
}

/// The long-press menu every wall entry shares. [context] must be the pressed
/// target's own context: the menu anchors to its rect.
Future<void> showWallRowMenu(
  BuildContext context,
  WidgetRef ref,
  StreakRow row, {
  WidgetBuilder? previewBuilder,
}) {
  final navigatorContext = Navigator.of(context).context;
  return showLibraryContextMenu(
    context: context,
    previewBuilder: previewBuilder,
    actions: [
      LibraryMenuAction(
        icon: Icons.local_fire_department_outlined,
        label: 'Open streak card',
        onSelected: () {
          if (navigatorContext.mounted) {
            openWallStreakCard(navigatorContext, row);
          }
        },
      ),
      LibraryMenuAction(
        icon: Icons.person_outline_rounded,
        label: 'Open profile',
        onSelected: () {
          if (navigatorContext.mounted) _openProfile(navigatorContext, row);
        },
      ),
      spaceMenuAction(context: context, ref: ref, draft: wallStreakDraft(row)),
    ],
  );
}
