import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:chessever2/screens/home/start_screen.dart';
import 'package:chessever2/screens/home/widget/bottom_nav_bar.dart';
import 'package:chessever2/screens/home/widget/bottom_nav_bar_widget.dart';
import 'package:chessever2/screens/inbox/inbox_provider.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/widgets/glass_surface.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// The phone dock's geometry: one frosted capsule floating over the foot of
/// the page, never gone. Reading on (the section's chrome at 0) it draws in
/// to [compactHeight] tall and only as wide as its marks need; heading back
/// (the chrome at 1) it stands at [normalHeight] across the screen.
///
/// Its slot in the Scaffold is [extent] tall whatever the capsule's shape,
/// so the capsule changing shape never lays the page out again: the page
/// runs under the slot ([Scaffold.extendBody]) and pads its end by it
/// ([MediaQuery.paddingOf]).
@immutable
class HomeNavMetrics {
  const HomeNavMetrics({
    required this.gap,
    required this.count,
    required this.screenWidth,
  });

  /// [count] marks on the dock of the screen [context] is on.
  ///
  /// The gap under the capsule rides the system's own bottom inset: on an
  /// iPhone the capsule sits a little into the home indicator's strip
  /// (`inset - 12`, 22 on a Face ID phone), never closer than 12 to the
  /// screen's edge; on Android it stays wholly above the gesture bar or the
  /// three buttons, which it must never cover.
  factory HomeNavMetrics.of(BuildContext context, {required int count}) {
    final inset = MediaQuery.viewPaddingOf(context).bottom;
    final ios = Theme.of(context).platform == TargetPlatform.iOS;
    return HomeNavMetrics(
      gap: ios ? math.max(minGap, inset - 12) : math.max(minGap, inset),
      count: count,
      screenWidth: MediaQuery.sizeOf(context).width,
    );
  }

  /// Space under the capsule, to the screen's bottom edge.
  final double gap;

  /// Marks on the dock.
  final int count;
  final double screenWidth;

  /// The capsule as the reader heads back up a page: full height, across
  /// the screen.
  static const double normalHeight = 56;

  /// Reading on: down to every mark's own 44pt target and no further.
  static const double compactHeight = 44;

  /// The marks' side at full size and drawn in ([BottomNavBarWidget.iconSide]
  /// at 28).
  static const double normalMark = 28;
  static const double compactMark = 22;

  /// The least space between the capsule and the screen's bottom edge.
  static const double minGap = 12;

  /// The full capsule's margin to either side of the screen, and the widest
  /// it ever gets (a landscape phone).
  static const double sideMargin = 16;
  static const double maxWidth = 440;

  /// The compact capsule: [count] 44pt targets, [compactStep] apart, inside
  /// [padding] at either end.
  static const double compactSlot = 44;
  static const double compactStep = 6;

  /// Inside the capsule's round ends, before the first mark and after the
  /// last: the marks never touch the rim.
  static const double padding = 10;

  /// The Scaffold's slot: constant, so a change of shape relays out the dock
  /// alone, never the page.
  double get extent => gap + normalHeight;

  /// How far the page's foot is covered with the capsule drawn in: what a
  /// page centred between the bars keeps clear of (Feed).
  double get compactExtent => gap + compactHeight;

  /// How far the capsule's top drops as it draws in: what floating buttons
  /// over it ride down by, so they keep their distance from it.
  double get ride => normalHeight - compactHeight;

  double get normalWidth =>
      math.max(0, math.min(screenWidth - 2 * sideMargin, maxWidth));

  double get compactWidth => math.min(
    normalWidth,
    count * compactSlot + math.max(0, count - 1) * compactStep + 2 * padding,
  );

  /// The capsule at [shown] (the section's chrome: 1 full, 0 drawn in).
  double heightAt(double shown) =>
      lerpDouble(compactHeight, normalHeight, shown.clamp(0.0, 1.0))!;

  double widthAt(double shown) =>
      lerpDouble(compactWidth, normalWidth, shown.clamp(0.0, 1.0))!;

  /// The marks' scale at [shown]: drawn at their full size and scaled, so a
  /// photo's cache never changes size as the dock draws in.
  double markScaleAt(double shown) =>
      lerpDouble(compactMark / normalMark, 1, shown.clamp(0.0, 1.0))!;

  @override
  bool operator ==(Object other) =>
      other is HomeNavMetrics &&
      other.gap == gap &&
      other.count == count &&
      other.screenWidth == screenWidth;

  @override
  int get hashCode => Object.hash(gap, count, screenWidth);
}

/// The dock's metrics, for a page under it that composes itself between the
/// bars (Feed keeps its posts clear of the drawn-in capsule). Absent on a
/// tablet, which has the rail instead, and on pushed pages.
class HomeNavScope extends InheritedWidget {
  const HomeNavScope({super.key, required this.metrics, required super.child});

  final HomeNavMetrics metrics;

  static HomeNavMetrics? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<HomeNavScope>()?.metrics;

  @override
  bool updateShouldNotify(HomeNavScope oldWidget) =>
      metrics != oldWidget.metrics;
}

/// The phone's way between sections: the section marks on one frosted
/// capsule ([GlassSurface], the floating buttons' own material) that floats
/// over the page and never leaves it.
///
/// It follows the section's scroll chrome ([chrome]): reading on draws it
/// in to a compact capsule with smaller marks, heading back opens it up
/// again, on the chrome's own value (its spring, a list's scroll or Feed's
/// pages turning it). Every mark stays a 44pt target at every size. With no
/// chrome (a test, a still section) it stands full.
///
/// Its slot is [HomeNavMetrics.extent] tall at every frame, so the page
/// under it is never laid out again as it changes shape. Each mark's target
/// runs from the capsule's top down to the screen's edge, so the strip
/// under the capsule is never dead.
///
/// A soft scrim of the page's own ground ([scrim]) rises behind it, so the
/// capsule and the system's own bar under it read over any content. It
/// fades in over many eased steps, with no edge of its own. Feed has its
/// own deck there and turns it off.
class HomeNavDock extends ConsumerWidget {
  const HomeNavDock({super.key, this.chrome, this.scrim = true});

  /// How much of the section's chrome is shown: 1 the full capsule, 0 the
  /// compact one. Null stands it full.
  final ValueListenable<double>? chrome;

  /// Whether the page's ground rises behind the dock.
  final bool scrim;

  /// How far the scrim reaches above the dock's slot.
  static const double scrimReach = 24;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(visibleBottomNavItemsProvider);
    final selected = ref.watch(selectedBottomNavBarItemProvider);
    final unread = ref.watch(inboxHasUnreadProvider);
    final m = HomeNavMetrics.of(context, count: items.length);

    Widget capsule(double shown) {
      final width = m.widthAt(shown);
      final height = m.heightAt(shown);
      final left = (m.screenWidth - width) / 2;
      final markScale = m.markScaleAt(shown);
      final slotWidth = items.isEmpty
          ? 0.0
          : math.max(0.0, width - 2 * HomeNavMetrics.padding) / items.length;
      return Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: left,
            width: width,
            bottom: m.gap,
            height: height,
            child: GlassSurface(
              key: const ValueKey('home-nav-capsule'),
              borderRadius: BorderRadius.circular(height / 2),
              child: const SizedBox.expand(),
            ),
          ),
          // The marks: each target from the capsule's top to the screen's
          // edge, its mark centred in the capsule.
          Positioned(
            left: left + HomeNavMetrics.padding,
            width: math.max(0, width - 2 * HomeNavMetrics.padding),
            bottom: 0,
            height: height + m.gap,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final item in items)
                  BottomNavBarWidget(
                    key: bottomNavBarItemKey(item),
                    width: slotWidth,
                    bottomInset: m.gap,
                    markScale: markScale,
                    semanticsValue: item == BottomNavBarItem.profile && unread
                        ? 'Unread Inbox messages'
                        : null,
                    isSelected: selected == item,
                    dotId: bottomNavBarDotIds[item],
                    onTap: () => selectBottomNavBarItem(ref, item),
                    glyph: (ink, side) => bottomNavBarGlyph(
                      item,
                      ink: ink,
                      side: side,
                      selected: selected == item,
                    ),
                    title: namesBottomNavBarIcons[item]!,
                    onLongPress: () => unawaited(
                      makeStartScreenDefault(context, ref, section: item),
                    ),
                  ),
              ],
            ),
          ),
        ],
      );
    }

    final shape = chrome;
    return RepaintBoundary(
      child: SizedBox(
        key: const ValueKey('home-nav-dock'),
        height: m.extent,
        width: double.infinity,
        child: Stack(
          clipBehavior: Clip.none,
          fit: StackFit.expand,
          children: [
            if (scrim)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: m.extent + scrimReach,
                child: const IgnorePointer(child: _DockScrim()),
              ),
            if (shape == null)
              capsule(1)
            else
              AnimatedBuilder(
                animation: shape,
                builder: (context, _) => capsule(shape.value),
              ),
          ],
        ),
      ),
    );
  }
}

/// The page's ground rising behind the dock: from nothing at its top to
/// [_strength] at the screen's edge, over many eased steps, so no line or
/// band shows where it starts.
class _DockScrim extends StatelessWidget {
  const _DockScrim();

  static const double _strength = 0.92;
  static const int _steps = 14;

  @override
  Widget build(BuildContext context) {
    final ground = context.colors.background;
    final stops = <double>[];
    final colors = <Color>[];
    for (var i = 0; i < _steps; i++) {
      final t = i / (_steps - 1);
      // Eased in and out (smoothstep): no slope break at either end.
      final eased = t * t * (3 - 2 * t);
      stops.add(t);
      colors.add(ground.withValues(alpha: _strength * eased));
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: colors,
          stops: stops,
        ),
      ),
    );
  }
}
