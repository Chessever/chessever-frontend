import 'dart:math' as math;

import 'package:chessever2/screens/group_event/model/tour_detail_view_model.dart';
import 'package:chessever2/screens/group_event/widget/appbar_icons_widget.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_list_view_mode_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/category_dropdown.dart';
import 'package:chessever2/screens/tour_detail/widgets/tournament_menu_button.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/quick_list_toggles.dart';
import 'package:chessever2/widgets/search_mode/search_mode.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_screen_provider.dart';

/// Where [EventHeaderRow] puts things. One geometry for every tab of the
/// event and every state of its header, so nothing moves between them.
abstract final class EventHeaderMetrics {
  /// Where the back chevron's ink starts, from the header's start edge. The
  /// back is the search header's ([SearchHeaderMetrics]), its glyph centred
  /// in its target; Material's `arrow_back_ios_new` is inked from 6 to 17.77
  /// of its 24 units (read from the icon font).
  ///
  /// The event's one gutter: the tab strip under the header is inset this
  /// far on both sides, so the chevron's point and the ⋮'s outer edge stand
  /// on the strip's two edges.
  static double get backInk =>
      SearchHeaderMetrics.leadingInset +
      (SearchHeaderMetrics.backTarget - SearchHeaderMetrics.backGlyph) / 2 +
      SearchHeaderMetrics.backGlyph * 6 / 24;

  /// Where the ⋮'s dots are centred, from the header's end edge: their outer
  /// edge mirrors the chevron's point, so the row is symmetric about the
  /// screen's centre, the middle tab's.
  static double get menuGlyph => backInk + TournamentMenuButton.dotsHalfWidth;

  /// Half the board-view glyph's ink: the toolbar draws it at 20.ic, inked
  /// over 20 of 24 ([BoardViewGlyph]).
  static double get _toggleInkHalf => 20.ic * 20 / 24 / 2;

  /// The clear space between the board-view glyph's ink and the ⋮'s.
  static double get pairGap => 20.ic;

  /// From the board-view glyph's centre to the ⋮'s.
  static double get pairPitch =>
      _toggleInkHalf + pairGap + TournamentMenuButton.dotsHalfWidth;

  /// The ⋮'s tap target, across.
  static double get menuTarget => AppBarIconSurface.bareWidth;

  /// The board view's ([QuickToggleIconButton]'s 44pt target).
  static const double toggleTarget = AppBarIconSurface.minTapTarget;

  /// In the pair the two targets meet, whole, halfway between the glyphs;
  /// each glyph is drawn this far from its target's centre toward the other.
  static double get menuShift => menuTarget / 2 - pairPitch / 2;
  static double get toggleShift => toggleTarget / 2 - pairPitch / 2;

  /// From the header's end edge to the ⋮'s target: alone, centred on its
  /// glyph; in the pair, its glyph drawn toward the board view.
  static double endInset({required bool pair}) => math.max(
    0.0,
    pair ? menuGlyph + pairPitch / 2 - menuTarget : menuGlyph - menuTarget / 2,
  );

  /// From the header's end edge to the far side of the pair's targets.
  static double get pairExtent =>
      endInset(pair: true) + menuTarget + toggleTarget;

  /// From the header's start edge to the far side of the back's target.
  static double get backExtent =>
      SearchHeaderMetrics.leadingInset + SearchHeaderMetrics.backTarget;

  /// The least room between the middle and a control's target.
  static const double middleGap = 4;

  /// Kept clear on both sides of the middle. With [controls], the room the
  /// widest end (the Games pair) takes on every tab, so the category chip is
  /// centred on the screen (the middle tab's centre) and keeps its width
  /// whichever tab is in view.
  static double middleInset({bool controls = true}) =>
      math.max(backExtent, controls ? pairExtent : 0) + middleGap;
}

/// The event screen's header row on every tab and in every state: the way
/// back where the search header's is, the middle (the category chip, or the
/// title while there is none) centred on the screen, and at the end the ⋮,
/// with the board view beside it on Games as a tight pair.
class EventHeaderRow extends StatelessWidget {
  const EventHeaderRow({
    super.key,
    this.middle = const SizedBox.shrink(),
    this.tourData,
    this.onToggleBoardView,
    this.reserveControls = true,
  });

  final Widget middle;

  /// The event the ⋮ acts on; null leaves the end empty.
  final TourDetailViewModel? tourData;

  /// The board view toggle's tap, shown beside the ⋮; null hides it.
  final VoidCallback? onToggleBoardView;

  /// Keep the controls' room beside the middle even where they are not
  /// shown ([EventHeaderMetrics.middleInset]). False for a title that only
  /// has to clear the back.
  final bool reserveControls;

  @override
  Widget build(BuildContext context) {
    final menuData = tourData;
    final toggle = onToggleBoardView;
    final pair = menuData != null && toggle != null;
    Widget? end;
    if (menuData != null) {
      final menu = TournamentMenuButton(
        tourData: menuData,
        boxed: false,
        glyphShift: pair ? -EventHeaderMetrics.menuShift : 0,
      );
      end = toggle == null
          ? menu
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _BoardViewSlot(
                  shift: EventHeaderMetrics.toggleShift,
                  onTap: toggle,
                ),
                menu,
              ],
            );
    }
    final inset = EventHeaderMetrics.middleInset(controls: reserveControls);
    return Stack(
      children: [
        // The row's width and height: the middle, centred on the screen
        // between equal insets.
        ConstrainedBox(
          constraints: const BoxConstraints(
            minWidth: double.infinity,
            minHeight: SearchHeaderMetrics.rowHeight,
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: inset),
            child: Align(heightFactor: 1, child: middle),
          ),
        ),
        // Where the search header's chevron is, so nothing moves as a
        // search opens or closes over this header.
        PositionedDirectional(
          start: SearchHeaderMetrics.leadingInset,
          top: 0,
          bottom: 0,
          child: const Center(child: PageBackButton()),
        ),
        if (end != null)
          PositionedDirectional(
            end: EventHeaderMetrics.endInset(pair: pair),
            top: 0,
            bottom: 0,
            child: Center(child: end),
          ),
      ],
    );
  }
}

/// The board view in the header's pair: a whole 44pt target, its glyph drawn
/// [shift] toward the ⋮. The toolbar's own button keeps its tap, name and
/// feedback, but its target moves with its glyph, so the slot holds it to
/// the slot's own square and answers the strip it leaves with the same tap.
class _BoardViewSlot extends StatelessWidget {
  const _BoardViewSlot({required this.shift, required this.onTap});

  final double shift;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final rtl = Directionality.of(context) == TextDirection.rtl;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      excludeFromSemantics: true,
      onTap: onTap,
      child: SizedBox.square(
        dimension: EventHeaderMetrics.toggleTarget,
        child: Transform.translate(
          offset: Offset(rtl ? -shift : shift, 0),
          child: BoardViewToggleButton(onTap: onTap),
        ),
      ),
    );
  }
}

class GamesAppBarWidget extends ConsumerWidget {
  const GamesAppBarWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tourDetailAsync = ref.watch(tourDetailScreenProvider);
    return tourDetailAsync.when(
      data: (tourData) {
        if (tourData.tours.isEmpty) return const EventHeaderRow();
        // Bare glyphs (Trello #1420): no tile behind the view toggle or the
        // ⋮. The view toggle is every Games list's own board-view button;
        // the switcher gives the tap feedback.
        return EventHeaderRow(
          middle: const CategoryDropdown(),
          tourData: tourData,
          onToggleBoardView: () =>
              ref.read(gamesListViewModeSwitcher).toggleViewMode(),
        );
      },
      loading: () => const EventHeaderRow(),
      error: (e, _) => EventHeaderRow(
        reserveControls: false,
        middle: Text(
          'Error loading tours',
          style: AppTypography.textXsRegular.copyWith(
            color: context.colors.textPrimaryMuted,
          ),
        ),
      ),
    );
  }
}
