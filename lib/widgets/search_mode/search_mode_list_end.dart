part of 'search_mode.dart';

/// The room a list leaves after its last row for the floating buttons over
/// it, which step away while its search is open: the one way every list
/// under a [SearchModeHost] drops and restores that room. Put it last in
/// the list ([SearchModeListEnd.sliver] in a `CustomScrollView`).
///
/// [base] always stays (the list's own bottom margin, a home indicator);
/// [buttons] is the floating buttons' reach. That reach gives way on the
/// search mode's own timeline as the search opens and grows back as it
/// closes, so a reader at the very end of a list sees it settle with the
/// morph instead of jumping by a button's height at the tap, or when the
/// hits land. It never depends on the hits: an empty search, a search with
/// hits and a closed one all read the timeline alone. With no
/// [SearchModeHost] above it, it is simply [base] + [buttons].
///
/// A list that cannot end in a widget (its room is scroll padding) reads
/// the same value with [extentOf], or [extentAt] for a timeline it already
/// listens to.
class SearchModeListEnd extends StatelessWidget {
  const SearchModeListEnd({super.key, this.base = 0, required this.buttons});

  /// Kept whether the search is open or not.
  final double base;

  /// The floating buttons' reach, while they float.
  final double buttons;

  /// A sliver of it, for a `CustomScrollView`.
  static Widget sliver({Key? key, double base = 0, required double buttons}) =>
      SliverToBoxAdapter(
        key: key,
        child: SearchModeListEnd(base: base, buttons: buttons),
      );

  /// The room at the search mode's timeline value [t] (0 the page, 1 the
  /// search): [base], and as much of [buttons] as the morph has not yet
  /// taken away.
  static double extentAt(
    double t, {
    double base = 0,
    required double buttons,
  }) => base + buttons * (1 - t.clamp(0.0, 1.0));

  /// The room right now under [context]'s search mode, rebuilding [context]
  /// only when the search opens or closes; for the frames in between, let
  /// an `AnimatedBuilder` on [timelineOf] call [extentAt]. With no host,
  /// [base] + [buttons].
  static double extentOf(
    BuildContext context, {
    double base = 0,
    required double buttons,
  }) {
    final timeline = timelineOf(context);
    return timeline == null
        ? base + buttons
        : extentAt(timeline.value, base: base, buttons: buttons);
  }

  /// The timeline the room eases on, or null with no [SearchModeHost] above
  /// [context].
  static Animation<double>? timelineOf(BuildContext context) =>
      SearchModeScope.maybeOf(context)?.timeline;

  @override
  Widget build(BuildContext context) {
    final timeline = timelineOf(context);
    if (timeline == null) return SizedBox(height: base + buttons);
    return AnimatedBuilder(
      animation: timeline,
      builder: (context, _) => SizedBox(
        height: extentAt(timeline.value, base: base, buttons: buttons),
      ),
    );
  }
}
