import 'dart:math' as math;

import 'package:chessever2/screens/inbox/inbox_provider.dart';
import 'package:chessever2/screens/inbox/inbox_unread_dot.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/discovery_dot.dart';
import 'package:chessever2/widgets/search/search_motion.dart';
import 'package:chessever2/widgets/search_mode/search_mode.dart'
    show PageBackButton, SearchHeaderMetrics;
import 'package:chessever2/widgets/scroll_chrome.dart';
import 'package:chessever2/widgets/user_avatar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// The one top bar every root (Home, Feed, Botvinnik, Search, Profile)
/// wears, and the pages that borrow its geometry.
///
/// Each root owns only its content slot (its page tabs, a title, the search
/// field) and its side controls. Everything they share is fixed here, so
/// switching tabs never moves or resizes the bar, and the page under it
/// always starts at the same line ([headerExtent]):
///
/// ```text
///   status bar          viewPadding.top     stays put
///   topGap              24.h                ┐
///   row                 rowExtent           │ the band: steps away on
///   bottomGap           12.h                ┘ scroll, and back
///   page                from headerExtent
///   first content       contentGap into the page's scroll
/// ```
///
/// Every value is Events' shipped bar, which is the reference.
class HomeTopBarMetrics {
  const HomeTopBarMetrics._();

  /// The size handed to [UserAvatar], which draws the circle at `.w`.
  static const double avatarSize = 44;

  /// Between the avatar and the tab's content.
  static double get gap => 16.w;

  /// The bar's left and right gutter.
  static double get horizontalPadding =>
      ResponsiveHelper.adaptive(phone: 20.sp, tablet: 32.sp);

  /// From the bottom of the status bar to the top of the bar's row.
  static double get topGap => 24.h;

  /// From the top of the screen to the top of the bar's row.
  static double topInset(BuildContext context) =>
      MediaQuery.viewPaddingOf(context).top + topGap;

  /// From the bottom of the bar's row to the top of the page under it.
  static double get bottomGap => 12.h;

  /// The row's height on every root: the taller of the search field at the
  /// ambient text size ([fieldExtent]) and a control ([controlExtent]). The
  /// row's content is centred on it, so every root's title, tabs and field
  /// sit on one centre line.
  static double rowExtent(BuildContext context) =>
      math.max(fieldExtent(context), controlExtent);

  /// The part of a root's bar that steps away on scroll: [topGap], the row
  /// and [bottomGap]. The status bar's inset above it stays.
  static double bandExtent(BuildContext context) =>
      topGap + rowExtent(context) + bottomGap;

  /// From the top of the screen to where every root's page starts: the
  /// status bar's inset and the band.
  static double headerExtent(BuildContext context) =>
      MediaQuery.viewPaddingOf(context).top + bandExtent(context);

  /// From the top of a root's page to its first content, as the page's
  /// own scroll padding (so the content still scrolls up to the bar): the
  /// lead-in Home's pages (My Space, Today, Discovery) open on, and Profile
  /// and Search with them. One lead-in, so the first card lands on the same
  /// line on every root. Feed is the exception by design: a post is one
  /// framed page, composed by its own layout, not a list.
  static double get contentGap => 16.sp;

  /// The search field at rest: `SimpleSearchBar`'s 4.sp vertical padding
  /// around Events' filter tile (8.sp padding, 20.h glyph).
  static double get fieldHeight => 8.sp + 16.sp + 20.h;

  /// The search field's type: `SimpleSearchBar` sets its text and its hint
  /// in it.
  static TextStyle get fieldTextStyle => AppTypography.textMdRegular;

  /// The search field's height at the ambient text size: its 4.sp vertical
  /// padding around the taller of the filter tile and one line of
  /// [fieldTextStyle]. The tile is the taller up to about 1.5x, so this is
  /// [fieldHeight] there; past it the line is, and the field grows with the
  /// system text size.
  ///
  /// Every tab's row stands at least this tall, field or not, so the avatar
  /// lands on the same line on every tab at any text size.
  static double fieldExtent(BuildContext context) {
    final style = fieldTextStyle;
    final painter = TextPainter(
      text: TextSpan(style: style),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
      // A TextField forces its strut to its own style, so its line is
      // exactly this tall whatever it holds.
      strutStyle: StrutStyle.fromTextStyle(style, forceStrutHeight: true),
    );
    final line = painter.preferredLineHeight;
    painter.dispose();
    return 8.sp + math.max(16.sp + 20.h, line);
  }

  /// The tallest any control other than the avatar may stand: the avatar
  /// circle as drawn. The row takes the taller of the avatar (a premium ring
  /// adds its own padding, the same on every tab because the avatar is the
  /// same widget) and [fieldExtent], the same on every tab; a taller control
  /// would grow one tab's row and move its avatar.
  static double get controlExtent => avatarSize.w;

  /// The smallest target any control in the bar answers taps across, however
  /// small it is drawn: 44pt square (see [HomeTopBarTapTarget]).
  static const double minTapTarget = 44;

  /// The largest text scale the bar's chrome follows: the avatar's initials,
  /// the tabs' own controls and Feed's title, which is the scale Feed's page
  /// stops at. The search field's text is not chrome: it follows the system
  /// text size, and the row grows with it on every tab ([fieldExtent]).
  static const double maxTextScale = 1.4;

  /// The one title voice: every root's name on its bar (Feed, Botvinnik,
  /// Profile, Home's selected tab) and every pushed page's centred name
  /// ([PageTitle]). Body ink, the medium size, bold. A page pushed from a
  /// root keeps the root's voice, so moving between them never changes how
  /// a page is named.
  static TextStyle titleStyle(BuildContext context) => AppTypography
      .textMdMedium
      .copyWith(color: context.colors.textPrimary, fontWeight: FontWeight.w700);
}

/// A root's bar: the status bar's inset, then the band
/// ([HomeTopBarMetrics.bandExtent]) holding [child] as the row, its content
/// centred on [HomeTopBarMetrics.rowExtent], [HomeTopBarMetrics.
/// horizontalPadding] in from each side, centred at the tablet content
/// width. It ends exactly at [HomeTopBarMetrics.headerExtent], where the
/// page under it starts, so a root needs nothing else:
///
/// ```dart
/// Column(children: [
///   HomeTopBarFrame(child: title, field or tabs),
///   Expanded(child: page),
/// ])
/// ```
///
/// Under a [ScrollChromeScope] (a root in the home shell) the band steps
/// away with the shell's chrome as the page scrolls, and back, folding up to
/// the status bar and never into it. Inside a [CollapsingChrome] that the
/// host already wraps it in, it leaves with that instead and folds nothing
/// itself.
///
/// [statusBar] off is the older form for a host that keeps the status bar's
/// inset (and any folding) itself: only [HomeTopBarMetrics.topGap] above the
/// row, nothing under it, and the row as tall as its content.
///
/// [trailingOpticalInset] pulls the right gutter in for a row whose last
/// control is a glyph centred in a wider tap target, so the glyph's own edge
/// lands on the gutter rather than its invisible target.
///
/// The frame also carries the bar's tap targets: a control wrapped in a
/// [HomeTopBarTapTarget] answers taps a little past its drawn edge, into the
/// gutter, the inset above the row and the gap below it.
class HomeTopBarFrame extends StatelessWidget {
  const HomeTopBarFrame({
    super.key,
    required this.child,
    this.trailingOpticalInset = 0,
    this.statusBar = true,
  }) : _band = true;

  /// The bar as pages that are not roots placed it before the roots shared
  /// one band ([HomeTopBar]): [HomeTopBarMetrics.topInset] above the row,
  /// nothing under it, the row as tall as its content, never folding.
  const HomeTopBarFrame._plain({
    required this.child,
    this.trailingOpticalInset = 0,
  }) : statusBar = true,
       _band = false;

  final Widget child;
  final double trailingOpticalInset;

  /// Off, the frame leaves the status bar's inset to its host: a bar that
  /// scrolls away folds up to the status bar, never into it.
  final bool statusBar;

  /// The root's band: the status bar's strip, the row on its centre line,
  /// the gap under it, folding with the shell's chrome.
  final bool _band;

  @override
  Widget build(BuildContext context) {
    final side = HomeTopBarMetrics.horizontalPadding;
    if (!_band) {
      return _TapTargetScope(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: ResponsiveHelper.contentMaxWidth,
            ),
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                side,
                HomeTopBarMetrics.topInset(context),
                side - trailingOpticalInset,
                0,
              ),
              child: child,
            ),
          ),
        ),
      );
    }
    final Widget row = statusBar
        ? ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: HomeTopBarMetrics.rowExtent(context),
            ),
            child: Align(
              alignment: Alignment.centerLeft,
              child: SizedBox(width: double.infinity, child: child),
            ),
          )
        : child;
    final Widget band = Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: ResponsiveHelper.contentMaxWidth),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            side,
            HomeTopBarMetrics.topGap,
            side - trailingOpticalInset,
            statusBar ? HomeTopBarMetrics.bottomGap : 0,
          ),
          child: row,
        ),
      ),
    );
    if (!statusBar) return _TapTargetScope(child: band);
    final chrome = ScrollChromeScope.maybeOf(context);
    return _TapTargetScope(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(height: MediaQuery.viewPaddingOf(context).top),
          if (chrome == null || CollapsingChrome.encloses(context))
            band
          else
            CollapsingChrome(controller: chrome, child: band),
        ],
      ),
    );
  }
}

/// A root's title, in the one style every root's bar sets its name in
/// (Feed, Botvinnik, Profile): Home's selected page tab, so the words on the
/// bar read as one family as the reader moves between tabs. It stops growing
/// at [HomeTopBarMetrics.maxTextScale], like the rest of the bar's chrome.
class HomeTopBarTitle extends StatelessWidget {
  const HomeTopBarTitle(this.title, {super.key});

  final String title;

  /// The title's type: [HomeTopBarMetrics.titleStyle].
  static TextStyle style(BuildContext context) =>
      HomeTopBarMetrics.titleStyle(context);

  @override
  Widget build(BuildContext context) {
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: HomeTopBarMetrics.maxTextScale,
      child: Semantics(
        header: true,
        child: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: style(context),
        ),
      ),
    );
  }
}

/// A pushed page's name in the roots' title voice
/// ([HomeTopBarMetrics.titleStyle]), with an optional bare [mark] before it:
/// the same words, size and weight a root sets its name in, so a page
/// pushed from a root is named the way the root is.
///
/// It is as wide as its words (and mark) and centres them in itself; the row
/// it sits in centres it on the screen (a page's back row, or
/// [HomeTopBarTitleRow]). Long names end in an ellipsis on one line, and the
/// words stop growing at [HomeTopBarMetrics.maxTextScale] like the rest of
/// the bar's chrome. Read as a heading.
class PageTitle extends StatelessWidget {
  const PageTitle(this.title, {super.key, this.mark});

  final String title;

  /// A destination's own glyph before the name, drawn bare (no tile behind
  /// it) at [markSize] in the icon ink. Not read aloud: the name is.
  final Widget? mark;

  /// The mark's square.
  static double get markSize => 22.sp;

  /// The words' type: [HomeTopBarMetrics.titleStyle].
  static TextStyle style(BuildContext context) =>
      HomeTopBarMetrics.titleStyle(context);

  @override
  Widget build(BuildContext context) {
    final words = Text(
      title,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.center,
      style: style(context),
    );
    final glyph = mark;
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: HomeTopBarMetrics.maxTextScale,
      child: Semantics(
        header: true,
        child: glyph == null
            ? words
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ExcludeSemantics(
                    child: IconTheme(
                      data: IconThemeData(
                        size: markSize,
                        color: context.colors.iconPrimary,
                      ),
                      child: SizedBox.square(dimension: markSize, child: glyph),
                    ),
                  ),
                  SizedBox(width: 8.w),
                  Flexible(child: words),
                ],
              ),
      ),
    );
  }
}

/// A root's row with its [title] centred on the bar, whatever stands at
/// either side: [leading] on the start gutter, [trailing] on the end one.
/// The title is centred on the screen, not between the controls, so it sits
/// in the same place on every root.
class HomeTopBarTitleRow extends StatelessWidget {
  const HomeTopBarTitleRow({
    super.key,
    required this.title,
    this.leading,
    this.trailing = const <Widget>[],
  });

  /// Usually a [HomeTopBarTitle], or a button around one.
  final Widget title;
  final Widget? leading;
  final List<Widget> trailing;

  /// Kept clear of the title on each side, for the controls: a 44pt target
  /// and the gap after it.
  static double get sideReserve => 56.w;

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        HomeTopBarRow(
          showAvatar: false,
          leading: leading,
          content: const SizedBox.shrink(),
          trailing: trailing,
        ),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: sideReserve),
          child: Center(heightFactor: 1, child: title),
        ),
      ],
    );
  }
}

/// The profile avatar that opens the home sidebar, identical on every tab.
///
/// The whole avatar is one tap target, the premium ring included, and it
/// reads as a single "Open sidebar" button to a screen reader. It is never
/// placed in a box that fixes its height: squeezing the ringed avatar into a
/// 44pt row is what turned it into an oval.
class HomeTopBarAvatar extends ConsumerWidget {
  const HomeTopBarAvatar({super.key, this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tap = onTap;
    final unread = ref.watch(inboxHasUnreadProvider);
    final VoidCallback? handleTap = tap == null
        ? null
        : () {
            HapticFeedbackService.navigation();
            tap();
          };
    // Its own node carrying the tap: without `container` the label would
    // merge into whatever encloses the bar, and `excludeSemantics` would
    // drop the gesture's action, leaving a screen reader nothing to press.
    return Semantics(
      container: true,
      button: handleTap != null,
      label: unread ? 'Open sidebar, unread Inbox messages' : 'Open sidebar',
      onTap: handleTap,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: handleTap,
        child: IgnorePointer(
          child: InboxAvatarBadge(
            unread: unread,
            child: const UserAvatar(size: HomeTopBarMetrics.avatarSize),
          ),
        ),
      ),
    );
  }
}

/// The row inside a home bar: avatar, the tab's [content], its [trailing]
/// controls.
///
/// While [focusNode] has focus the row hands its width to the content (the
/// search field): the avatar and the trailing controls squeeze out on
/// [SearchMotion.morph], the spring the field's own morph runs on, and come
/// back when it lets go. Only width closes, so the row never changes height.
///
/// The row stands as tall as the taller of the avatar and the search field at
/// the ambient text size ([HomeTopBarMetrics.fieldExtent]) on every tab,
/// field or not, and centres everything on that height. So the search
/// field's text follows the system text size, as Events' bar always has, and
/// the avatar still lands on the same line on every tab: when a large text
/// size grows the field, every tab's row grows with it.
///
/// Invariant: nothing in [content] or [trailing] may stand taller than that.
/// A control stays within [HomeTopBarMetrics.controlExtent]; a field built
/// from `SimpleSearchBar` stands exactly [HomeTopBarMetrics.fieldExtent].
///
/// The chrome (the avatar's initials, the [trailing] controls) stops growing
/// at [HomeTopBarMetrics.maxTextScale]; the controls are drawn at a fixed
/// size. The avatar and every trailing control sit in a
/// [HomeTopBarTapTarget], so each answers taps across at least
/// [HomeTopBarMetrics.minTapTarget] square however small the phone draws
/// it, without the row's layout changing.
class HomeTopBarRow extends StatelessWidget {
  const HomeTopBarRow({
    super.key,
    required this.content,
    this.showAvatar = true,
    this.onAvatarTap,
    this.avatarKey,
    this.focusNode,
    this.trailing = const <Widget>[],
    this.leading,
  });

  final Widget content;
  final bool showAvatar;

  /// Stands where the avatar does: on a page pushed over the home shell,
  /// the page's [PageBackButton] (its chevron lands where every pushed
  /// page's does); on a root, a control of its own on the bar's gutter.
  /// Shown only when the avatar is not.
  final Widget? leading;
  final VoidCallback? onAvatarTap;
  final Key? avatarKey;
  final FocusNode? focusNode;
  final List<Widget> trailing;

  @override
  Widget build(BuildContext context) {
    Widget chrome(Widget child) => MediaQuery.withClampedTextScaling(
      maxScaleFactor: HomeTopBarMetrics.maxTextScale,
      child: child,
    );
    return Row(
      children: [
        // No width: only holds the row at the field's height, so a tab
        // without a field stands exactly as tall as one with it.
        SizedBox(height: HomeTopBarMetrics.fieldExtent(context)),
        if (showAvatar)
          _FocusSqueeze(
            focusNode: focusNode,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                HomeTopBarTapTarget(
                  child: chrome(
                    // The way into the drawer, so a dot on a drawer row can
                    // lead here first.
                    DiscoveryDotAnchor(
                      id: 'home.menu',
                      child: HomeTopBarAvatar(
                        key: avatarKey,
                        onTap: onAvatarTap,
                      ),
                    ),
                  ),
                ),
                SizedBox(width: HomeTopBarMetrics.gap),
              ],
            ),
          ),
        if (!showAvatar && leading != null)
          _FocusSqueeze(
            focusNode: focusNode,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // A way back lands on every pushed page's x; any other
                // control (Botvinnik's Chats) sits on the bar's gutter.
                if (leading is PageBackButton) ...[
                  HomeTopBarTapTarget(
                    child: chrome(_LeadingBack(child: leading!)),
                  ),
                  // The field keeps the gap it had from the chevron's glyph.
                  SizedBox(
                    width: math.max(0.0, 12.w + _LeadingBack.shift(context)),
                  ),
                ] else ...[
                  HomeTopBarTapTarget(child: chrome(leading!)),
                  SizedBox(width: 12.w),
                ],
              ],
            ),
          ),
        Expanded(child: content),
        if (trailing.isNotEmpty)
          _FocusSqueeze(
            focusNode: focusNode,
            child: chrome(
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final control in trailing)
                    HomeTopBarTapTarget(
                      // Keyed as the control is, so the row still matches
                      // its controls by key when the list changes.
                      key: switch (control.key) {
                        final Key key => ValueKey<Key>(key),
                        null => null,
                      },
                      child: control,
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// A [HomeTopBarRow] on the bar's inset and gutter, for a page that is not a
/// root (the Library pushed from My Space): placed as such pages always
/// were, under [HomeTopBarMetrics.topInset], with nothing added under the
/// row and no folding. Roots wear [HomeTopBarFrame]. A null [onOpenSidebar]
/// means there is no sidebar to open (the screen is outside the home shell),
/// so no avatar is offered rather than a dead control.
class HomeTopBar extends StatelessWidget {
  const HomeTopBar({
    super.key,
    required this.content,
    this.onOpenSidebar,
    this.avatarKey,
    this.focusNode,
    this.trailing = const <Widget>[],
    this.trailingOpticalInset = 0,
    this.leading,
  });

  final Widget content;
  final VoidCallback? onOpenSidebar;

  /// Takes the avatar's place when there is no sidebar to open.
  final Widget? leading;
  final Key? avatarKey;
  final FocusNode? focusNode;
  final List<Widget> trailing;
  final double trailingOpticalInset;

  @override
  Widget build(BuildContext context) {
    return HomeTopBarFrame._plain(
      trailingOpticalInset: trailingOpticalInset,
      child: HomeTopBarRow(
        content: content,
        showAvatar: onOpenSidebar != null,
        onAvatarTap: onOpenSidebar,
        avatarKey: avatarKey,
        focusNode: focusNode,
        trailing: trailing,
        leading: leading,
      ),
    );
  }
}

/// A [HomeTopBarRow]'s leading [PageBackButton] at its one place. The row
/// starts on the bar's gutter ([HomeTopBarMetrics.horizontalPadding]),
/// wider than a pushed page's back inset, so the button is drawn [shift]
/// toward the edge: its chevron lands where every pushed page's does
/// ([SearchHeaderMetrics.leadingInset]), the same glyph at the same x. As
/// tall as the bar's controls, so the row keeps its height.
class _LeadingBack extends StatelessWidget {
  const _LeadingBack({required this.child});

  final Widget child;

  /// How far the button is drawn toward the start edge (negative: toward
  /// it), in the row's start direction.
  static double shift(BuildContext context) =>
      SearchHeaderMetrics.leadingInset - HomeTopBarMetrics.horizontalPadding;

  @override
  Widget build(BuildContext context) {
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final dx = shift(context);
    return SizedBox(
      height: HomeTopBarMetrics.controlExtent,
      child: Transform.translate(
        offset: Offset(rtl ? -dx : dx, 0),
        child: child,
      ),
    );
  }
}

/// The app's one search field look, at [lift] 0 (resting) to 1 (focused):
/// the Search tab's and Events' field in the home bar, the Library's, and
/// every Games tab's search header (`EventSearchBarFrame`, which the search
/// morph's glass lands on).
///
/// Tonal elevation with a self-coloured edge: the fill ([fillOf]) is the
/// page's surface stepping a hair toward the ink, and the stroke ([edgeOf])
/// is that same surface lifted further, so focus reads as a lit lip rather
/// than a drawn outline. Works in both themes because `textPrimary` flips.
///
/// It stands at least [heightOf] tall (the home bar's field, its text
/// following the system size), so a field with a filter glyph and one
/// without are the same field; `SimpleSearchBar` centres its row in it.
class HomeSearchFieldSurface extends StatelessWidget {
  const HomeSearchFieldSurface({
    super.key,
    required this.lift,
    required this.child,
  });

  final double lift;
  final Widget child;

  /// The field's corners.
  static double get radius => 12.br;

  /// The field's height: [HomeTopBarMetrics.fieldExtent].
  static double heightOf(BuildContext context) =>
      HomeTopBarMetrics.fieldExtent(context);

  /// The fill at [lift]: the page's surface, a hair toward the ink as the
  /// field takes focus.
  static Color fillOf(BuildContext context, double lift) {
    final colors = context.colors;
    return Color.lerp(
      colors.surface,
      colors.textPrimary,
      0.04 * lift.clamp(0.0, 1.0),
    )!;
  }

  /// The 1pt edge at [lift], drawn inside the field: the fill lifted
  /// further. At rest it is the fill's own colour, so no line shows.
  static Color edgeOf(BuildContext context, double lift) {
    final t = lift.clamp(0.0, 1.0);
    return Color.lerp(
      fillOf(context, t),
      context.colors.textPrimary,
      0.16 * t,
    )!;
  }

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      key: const ValueKey('simple-search-field-surface'),
      decoration: BoxDecoration(
        color: fillOf(context, lift),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: edgeOf(context, lift)),
      ),
      // DecoratedBox does not inset for its border, so the stroke costs no
      // layout and the field cannot jump by a pixel when it lights up.
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: heightOf(context)),
        child: child,
      ),
    );
  }
}

/// Squeezes [child] out of the row while [focusNode] has focus. Listening
/// here keeps the collapse off the host screen's build, so the keyboard
/// coming up never rebuilds the tab.
class _FocusSqueeze extends StatelessWidget {
  const _FocusSqueeze({required this.focusNode, required this.child});

  final FocusNode? focusNode;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final node = focusNode;
    if (node == null) return child;
    return ListenableBuilder(
      listenable: node,
      child: child,
      builder: (context, child) => SqueezeSlot(
        open: !node.hasFocus,
        motion: SearchMotion.morph,
        child: child!,
      ),
    );
  }
}

/// Answers taps on [child] across at least [HomeTopBarMetrics.minTapTarget]
/// square, centred on it, however small it is drawn, without changing its
/// layout: a 40pt avatar on a narrow phone is still a 44pt target.
///
/// The extra reach is carried by the [HomeTopBarFrame] around the bar, so it
/// takes in the gutter, the inset above the row and the gap below it as well
/// as the space between controls. It only claims spots nothing else would
/// answer: anything there that handles the pointer itself (another control,
/// the search field's text) keeps the tap. The tap is handed on as one just
/// inside the control's edge, through the usual path, so whatever blocks the
/// control's own taps blocks this too. The nearest control wins where two
/// reaches overlap, and a control squeezed out of the row, or caught
/// mid-squeeze, keeps only what it paints. Outside a [HomeTopBarFrame] it
/// adds nothing.
class HomeTopBarTapTarget extends SingleChildRenderObjectWidget {
  const HomeTopBarTapTarget({super.key, required Widget super.child});

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderTapTarget();
}

class _RenderTapTarget extends RenderProxyBox {
  _RenderTapTargetScope? _scope;

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    var node = parent;
    while (node != null && node is! _RenderTapTargetScope) {
      node = node.parent;
    }
    _scope = node as _RenderTapTargetScope?;
    _scope?._targets.add(this);
  }

  @override
  void detach() {
    _scope?._targets.remove(this);
    _scope = null;
    super.detach();
  }
}

/// Where a [HomeTopBarFrame]'s tap targets reach past their drawn edges.
class _TapTargetScope extends SingleChildRenderObjectWidget {
  const _TapTargetScope({required Widget super.child});

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderTapTargetScope();
}

class _RenderTapTargetScope extends RenderProxyBox {
  final Set<_RenderTapTarget> _targets = <_RenderTapTarget>{};

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    final forwarded = _reachedFrom(position);
    if (forwarded == null) return super.hitTest(result, position: position);
    // In a small control's reach, off the control (possibly just outside
    // this box, in the gap under the row). Whatever handles the pointer there
    // keeps it; otherwise the tap goes to the control.
    final there = BoxHitTestResult();
    final answered =
        super.hitTest(there, position: position) &&
        there.path.any((entry) => entry.target is RenderPointerListener);
    return super.hitTest(result, position: answered ? position : forwarded);
  }

  /// A point well inside the nearest control whose target reaches
  /// [position] from off the control, clear of a rounded corner; null when
  /// none does, or when [position] is on one of them already.
  Offset? _reachedFrom(Offset position) {
    const side = HomeTopBarMetrics.minTapTarget;
    // A parent asks about every point in its own box; no target reaches
    // further than half a target past this one.
    if (_targets.isEmpty ||
        !(Offset.zero & size).inflate(side / 2).contains(position)) {
      return null;
    }
    Rect? nearest;
    var nearestDistance = double.infinity;
    for (final target in _targets) {
      if (!target.attached || !target.hasSize) continue;
      final drawn = MatrixUtils.transformRect(
        target.getTransformTo(this),
        Offset.zero & target.size,
      );
      // Drawn whole, and short of a full target on some side.
      if (drawn.isEmpty ||
          drawn.width < target.size.width - 0.5 ||
          drawn.height < target.size.height - 0.5 ||
          (drawn.width >= side && drawn.height >= side)) {
        continue;
      }
      if (drawn.contains(position)) return null;
      final reach = Rect.fromCenter(
        center: drawn.center,
        width: math.max(drawn.width, side),
        height: math.max(drawn.height, side),
      );
      if (!reach.contains(position)) continue;
      final dx = math.max(
        0.0,
        math.max(drawn.left - position.dx, position.dx - drawn.right),
      );
      final dy = math.max(
        0.0,
        math.max(drawn.top - position.dy, position.dy - drawn.bottom),
      );
      final distance = dx * dx + dy * dy;
      if (distance < nearestDistance) {
        nearestDistance = distance;
        nearest = drawn;
      }
    }
    if (nearest == null) return null;
    final core = nearest.deflate(nearest.shortestSide / 4);
    return Offset(
      position.dx.clamp(core.left, core.right),
      position.dy.clamp(core.top, core.bottom),
    );
  }
}
