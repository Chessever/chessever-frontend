import 'dart:async';
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:chessever2/screens/chessboard/chess_board_screen_new.dart';
import 'package:chessever2/screens/chessboard/provider/chess_board_screen_provider_new.dart';
import 'package:chessever2/revenue_cat_service/subscribe_state.dart';
import 'package:chessever2/screens/collections/collection_bindings.dart';
import 'package:chessever2/screens/collections/collections_data.dart';
import 'package:chessever2/screens/collections/event_view_shell.dart';
import 'package:chessever2/screens/for_you/discovery/widgets/discovery_common.dart'
    show
        DiscoveryAction,
        DiscoveryInkFloor,
        DiscoveryPadlock,
        DiscoveryType,
        discoveryGutter,
        discoveryType;
import 'package:chessever2/screens/streaks/widgets/wall_common.dart'
    show WallPressable;
import 'package:chessever2/screens/for_you/discovery/widgets/discovery_game_cards.dart';
import 'package:chessever2/screens/my_space/models/space_shortcut.dart';
import 'package:chessever2/screens/my_space/widgets/pixel_art.dart';
import 'package:chessever2/screens/my_space/widgets/space_database.dart'
    show spacePlateArtBox;
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/user_error_message.dart';
import 'package:chessever2/widgets/app_button.dart' show TappableScale;
import 'package:chessever2/screens/library/widgets/library_context_menu.dart'
    show LibraryMenuAction;
import 'package:chessever2/screens/my_space/actions/space_menu_action.dart';
import 'package:chessever2/widgets/card_context_menu.dart';
import 'package:chessever2/screens/favorites/tabs/favorites_players_tab.dart'
    show playerPhotoProvider;
import 'package:chessever2/screens/my_space/widgets/space_avatar.dart'
    show SpacePlayerAvatar;
import 'package:chessever2/screens/player_profile/utils/player_menu_actions.dart'
    show playerMenuActions;
import 'package:chessever2/widgets/hub_tile.dart';
import 'package:chessever2/widgets/skeleton_widget.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:intl/intl.dart';

/// Discovery › Collection: the collections, laid out as an event is, with
/// events and books on their own tabs and each entry drawn as an event card.
class CollectionsScreen extends ConsumerWidget {
  const CollectionsScreen({super.key});

  static Future<void> open(BuildContext context) {
    HapticFeedbackService.cardTap();
    return Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const CollectionsScreen()));
  }

  static const _tabs = [CollectionKind.event, CollectionKind.book];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final collections = ref.watch(collectionsProvider);
    return EventViewShell(
      title: 'Collection',
      tabs: const ['Events', 'Books'],
      pageBuilder: (context, index) {
        final kind = _tabs[index];
        return collections.when(
          data: (all) {
            final shown = [
              for (final c in all)
                if (c.kind == kind) c,
            ];
            return RefreshIndicator(
              color: context.colors.textPrimary,
              backgroundColor: context.colors.surface,
              onRefresh: () => ref.refresh(collectionsProvider.future),
              // An empty tab's notice is a list of its own (it still pulls
              // to refresh), so it IS the tab's scrollable, never an item
              // of the card list: there it gets unbounded height, fails
              // layout, and the half-laid-out subtree then fails the
              // semantics parent-data check on every later frame.
              child: shown.isEmpty
                  ? _Notice(
                      text: kind == CollectionKind.event
                          ? 'No annotated events yet.'
                          : 'No books yet.',
                    )
                  : ListView.builder(
                      physics: const AlwaysScrollableScrollPhysics(
                        parent: BouncingScrollPhysics(),
                      ),
                      padding: EdgeInsets.fromLTRB(
                        16.sp,
                        16.sp,
                        16.sp,
                        24.sp + MediaQuery.viewPaddingOf(context).bottom,
                      ),
                      itemCount: shown.length,
                      itemBuilder: (context, i) => Padding(
                        padding: EdgeInsets.only(bottom: 12.sp),
                        child: CollectionCard(collection: shown[i]),
                      ),
                    ),
            );
          },
          loading: () => const _CardsSkeleton(),
          error: (error, _) => _Notice(
            text: userFacingError(
              error,
              fallback: "Couldn't load collections.",
            ),
            actionLabel: 'Try again',
            onAction: () => ref.invalidate(collectionsProvider),
          ),
        );
      },
    );
  }
}

/// [c] as a My Space shortcut: it sits with the databases and opens the
/// collection again from there.
SpaceShortcut collectionSpaceDraft(Collection c) {
  final games = c.gameCount == 1 ? '1 game' : '${c.gameCount} games';
  return SpaceShortcut.draft(
    kind: SpaceShortcutKind.collection,
    targetId: c.id,
    title: c.title,
    subtitle: games,
    params: {
      'slug': c.slug,
      'collectionKind': c.kind.name,
      'gameCount': c.gameCount,
      if (c.coverUrl != null) 'coverUrl': c.coverUrl,
    },
  );
}

/// A collection as the Events list draws an event: its cover (or its pixel
/// object) on the left, the title, who wrote it (a book) or where and when
/// it was played (an event), and how many games it holds with what it is
/// bound to ("91 games · 2 books"; a book names its events when its row
/// carries them). Held, it lifts into the focus menu with Open and My
/// Space.
///
/// A book stands as a book does, on a portrait cover; an event keeps its
/// landscape picture. A Premium collection the viewer cannot read yet
/// carries the padlock after its game count (the page's one lock
/// placement); it still opens, on its preview. [note] is the team's caption
/// when the card is listed for an event ("Chapter 7 is this match's
/// decisive game").
class CollectionCard extends ConsumerWidget {
  const CollectionCard({super.key, required this.collection, this.note});

  final Collection collection;
  final String? note;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = collection;
    final subscription = ref.watch(subscriptionProvider);
    final locked = isCollectionLocked(
      c,
      isSubscribed: subscription.isSubscribed,
      subscriptionLoading: subscription.isLoading,
    );
    final isBook = c.kind == CollectionKind.book;
    // Who wrote it, or where and when it was played: what tells this one
    // from its neighbours (two Sinquefield Cups differ by their year), on a
    // line of its own so the count never pushes the year off the end. An
    // event's subtitle stands in only when it has neither place nor dates.
    final identity = isBook
        ? (c.author == null ? null : 'by ${c.author}')
        : collectionEventLine(c.location, c.dateStart, c.dateEnd) ??
              c.subtitle;
    // A book names the events it covers when its row carries them; counted
    // otherwise, as an event counts the books written about it.
    final named = isBook && note == null ? collectionEventsLine(c.events) : null;
    final bindings = isBook
        ? (named == null && c.eventCount > 0
              ? _plural(c.eventCount, 'event')
              : null)
        : ((c.bookCount ?? 0) > 0 ? _plural(c.bookCount!, 'book') : null);
    final tally = [_plural(c.gameCount, 'game'), ?bindings].join(' · ');
    final caption = note ?? named;

    void open() {
      HapticFeedbackService.cardTap();
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => CollectionScreen(collection: c),
        ),
      );
    }

    return CollectionPlateRow(
      plate: _Cover(collection: c),
      plateSize: isBook
          ? CollectionPlateRow.bookPlate
          : CollectionPlateRow.eventPlate,
      title: c.title,
      meta: identity,
      metaMaxLines: 2,
      tally: tally,
      locked: locked,
      note: caption,
      semanticsLabel: [
        c.title,
        ?identity,
        tally,
        if (locked) 'Premium',
        ?caption,
      ].join(', '),
      onTap: open,
      menuActions: (menuContext) => [
        LibraryMenuAction(
          icon: Icons.open_in_new_rounded,
          label: 'Open',
          onSelected: open,
        ),
        spaceMenuAction(
          context: menuContext,
          ref: ref,
          draft: collectionSpaceDraft(c),
        ),
      ],
    );
  }
}

/// The row every collection list draws: the [plate] on the left
/// ([plateSize]: an event's 5:4 picture or a book's 2:3 cover), the title
/// (two lines at most), the [meta] line ([metaMaxLines] of them), the
/// [tally] under it, and the optional [note] last. [locked] trails the
/// tally (or, without one, the meta) with the Premium padlock, which the
/// text gives way to. A null [onTap] draws the row with no press and no
/// target (an event the server could not resolve still shows what the book
/// covers).
class CollectionPlateRow extends StatelessWidget {
  const CollectionPlateRow({
    super.key,
    required this.plate,
    required this.title,
    required this.meta,
    required this.semanticsLabel,
    this.plateSize,
    this.metaMaxLines = 1,
    this.tally,
    this.locked = false,
    this.note,
    this.onTap,
    this.menuActions,
  });

  /// An event's picture: landscape, 5:4.
  static Size get eventPlate => Size(108.w, 108.w * 4 / 5);

  /// A book's cover, standing as a book stands: 2:3, the shape most covers
  /// are printed in, so a jacket keeps its title and its author.
  static Size get bookPlate => Size(64.w, 96.w);

  final Widget plate;

  /// [eventPlate] when null.
  final Size? plateSize;
  final String title;
  final String? meta;
  final String semanticsLabel;
  final int metaMaxLines;

  /// How much the collection holds ("55 games"), on its own line.
  final String? tally;
  final bool locked;
  final String? note;
  final VoidCallback? onTap;
  final CardMenuActionsBuilder? menuActions;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isLight = context.isLightTheme;
    final size = plateSize ?? eventPlate;
    final metaStyle = AppTypography.textXsMedium.copyWith(
      color: colors.textPrimaryMuted,
    );
    final line = meta;
    final count = tally;
    final caption = note;

    // The padlock stands outside the text, so a long credit or a larger
    // text size shortens the words and never cuts the lock off with them.
    Widget withLock(Widget? text) => Row(
      children: [
        if (text != null) Flexible(child: text),
        if (locked) ...[
          if (text != null) SizedBox(width: DiscoveryPadlock.gap),
          const DiscoveryPadlock(
            key: ValueKey<String>('collection_card_padlock'),
          ),
        ],
      ],
    );

    final Widget? metaText = line == null
        ? null
        : metaMaxLines < 2
        ? Text(
            line,
            maxLines: metaMaxLines,
            overflow: TextOverflow.ellipsis,
            style: metaStyle,
          )
        : LayoutBuilder(
            builder: (context, constraints) => Text(
              _breakAtLastDot(context, line, metaStyle, constraints.maxWidth),
              maxLines: metaMaxLines,
              overflow: TextOverflow.ellipsis,
              style: metaStyle,
            ),
          );

    Widget card = Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(8.br),
        border: isLight
            ? Border.all(color: colors.divider.withValues(alpha: 0.4))
            : null,
      ),
      padding: EdgeInsets.all(6.sp),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(6.br),
            child: SizedBox(
              width: size.width,
              height: size.height,
              child: plate,
            ),
          ),
          SizedBox(width: 10.w),
          Expanded(
            child: Padding(
              // Clear of the card's right rim, so a long title never runs
              // into it.
              padding: EdgeInsets.only(right: 6.sp),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.textSmMedium.copyWith(
                      color: colors.textPrimary,
                      fontSize: 14.f,
                      height: 1.2,
                    ),
                  ),
                  if (metaText != null) ...[
                    SizedBox(height: 4.h),
                    count == null ? withLock(metaText) : metaText,
                  ],
                  if (count != null) ...[
                    SizedBox(height: metaText == null ? 4.h : 2.h),
                    withLock(
                      Text(
                        count,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: metaStyle.copyWith(
                          color: colors.textSecondary,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ] else if (metaText == null && locked) ...[
                    SizedBox(height: 4.h),
                    withLock(null),
                  ],
                  if (caption != null) ...[
                    SizedBox(height: 6.h),
                    Text(
                      caption,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.textXsRegular.copyWith(
                        color: colors.textSecondary,
                        height: 16 / 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );

    final tap = onTap;
    if (tap == null) {
      return Semantics(
        label: semanticsLabel,
        excludeSemantics: true,
        child: card,
      );
    }
    final actions = menuActions;
    if (actions != null) {
      card = CardContextMenu(onPreviewTap: tap, actions: actions, child: card);
    }
    return Semantics(
      button: true,
      label: semanticsLabel,
      excludeSemantics: true,
      onTap: tap,
      child: TappableScale(onTap: tap, child: card),
    );
  }
}

/// [line] as it should wrap in [width]: whole when it fits on one line;
/// otherwise, when its last part ("Jan 13-28, 2024" after "Wijk aan Zee ·")
/// and what leads it each fit a line, broken there with the dot dropped, so
/// no line ends on a dangling separator. Anything longer wraps as it falls.
String _breakAtLastDot(
  BuildContext context,
  String line,
  TextStyle style,
  double width,
) {
  const dot = ' · ';
  final at = line.lastIndexOf(dot);
  if (at <= 0 || !width.isFinite) return line;
  final scaler = MediaQuery.textScalerOf(context);
  final direction = Directionality.of(context);
  // Measured as the Text will draw it: over the ambient style, whose
  // letter spacing the line inherits.
  final drawn = DefaultTextStyle.of(context).style.merge(style);
  bool fits(String text) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: drawn),
      textDirection: direction,
      textScaler: scaler,
      maxLines: 1,
    )..layout(maxWidth: width);
    final fit = !painter.didExceedMaxLines;
    painter.dispose();
    return fit;
  }

  if (fits(line)) return line;
  final head = line.substring(0, at);
  final tail = line.substring(at + dot.length);
  return fits(head) && fits(tail) ? '$head\n$tail' : line;
}

/// A collection's cover, or its pixel object (the trophy for an event, the
/// stacked boards for a book) when it has none.
class _Cover extends StatelessWidget {
  const _Cover({required this.collection});

  final Collection collection;

  @override
  Widget build(BuildContext context) {
    final plate = _PixelPlate(
      section: collection.kind == CollectionKind.book
          ? SpaceSection.library
          : SpaceSection.events,
    );
    final url = collection.coverUrl;
    if (url == null) return plate;
    return CachedNetworkImage(
      imageUrl: url,
      fit: BoxFit.cover,
      placeholder: (_, __) => plate,
      errorWidget: (_, __, ___) => plate,
    );
  }
}

/// The pixel object on the hub's plate: the stacked boards for a book, the
/// trophy for an event.
class _PixelPlate extends StatelessWidget {
  const _PixelPlate({required this.section});

  final SpaceSection section;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: context.isLightTheme
          ? context.colors.surfaceRecessed
          : kHubTileInk,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = constraints.biggest;
          if (!size.isFinite || size.isEmpty) return const SizedBox.shrink();
          // A standing (book) plate is narrow: the object takes more of its
          // width, so it reads at the size it does on a landscape plate.
          final box = size.height > size.width
              ? Rect.fromCenter(
                  center: size.center(Offset.zero),
                  width: size.width * 0.76,
                  height: size.height * 0.56,
                )
              : spacePlateArtBox(size);
          return PixelArtView(
            scene: PixelScene.inBox(
              PixelArt.door(section, tone: PixelTone.of(context)),
              size,
              box,
            ),
          );
        },
      ),
    );
  }
}

/// "Wijk aan Zee · Jan 13-28, 2024": where and when an event was played,
/// as every event line in the collections reads it, or null when it has
/// neither. The place comes first; each date holds together, so a line that
/// wraps breaks after the place or at a range's dash ("Sep 10, 1984 -" over
/// "Feb 15, 1985"), never inside a date.
String? collectionEventLine(String? location, DateTime? start, DateTime? end) {
  final dates = collectionDateRange(
    start,
    end,
  )?.split(' - ').map((d) => d.replaceAll(' ', '\u00a0')).join(' - ');
  final parts = [?location, ?dates];
  return parts.isEmpty ? null : parts.join(' · ');
}

/// "1 game", "55 games".
String _plural(int n, String one) => n == 1 ? '1 $one' : '$n ${one}s';

/// "World Championship 1985", or "World Championship 1984 and 1 more": the
/// events a book covers, as its card names them; null when it names none.
String? collectionEventsLine(List<CollectionEventRef> events) {
  if (events.isEmpty) return null;
  final first = events.first.title;
  final more = events.length - 1;
  return more == 0 ? first : '$first and $more more';
}

/// "Saint Louis · Oct 2-14, 2025": an event's place and dates, or null when
/// it has neither.
String? collectionPlaceAndDates(Collection c) {
  final dates = collectionDateRange(c.dateStart, c.dateEnd);
  final parts = [?c.location, ?dates];
  return parts.isEmpty ? null : parts.join(' · ');
}

/// "Oct 2, 2025", "Oct 2-14, 2025", "Sep 28 - Oct 3, 2025".
String? collectionDateRange(DateTime? start, DateTime? end) {
  final from = start ?? end;
  if (from == null) return null;
  final to = start == null ? null : end;
  final full = DateFormat('MMM d, yyyy');
  if (to == null ||
      (from.year == to.year && from.month == to.month && from.day == to.day)) {
    return full.format(from);
  }
  if (from.year == to.year && from.month == to.month) {
    return '${DateFormat('MMM d').format(from)}-${to.day}, ${to.year}';
  }
  if (from.year == to.year) {
    return '${DateFormat('MMM d').format(from)} - ${full.format(to)}';
  }
  return '${full.format(from)} - ${full.format(to)}';
}

/// Where section headers and the player line start: the game cards' edge.
double get _headerInset => discoveryGutter + 4.sp;

/// One collection, laid out as an event. A book: About, Games (its parts
/// and chapters) and Events (the events it covers). An event: About, Games
/// (the annotated games under their rounds), Books (the books written about
/// it) and Players (everyone in it; picking one shows their games).
class CollectionScreen extends ConsumerStatefulWidget {
  const CollectionScreen({super.key, required this.collection});

  /// The list row it was opened from; the detail read fills in the rest.
  final Collection collection;

  @override
  ConsumerState<CollectionScreen> createState() => _CollectionScreenState();
}

class _CollectionScreenState extends ConsumerState<CollectionScreen> {
  static const int _aboutTab = 0;
  static const int _gamesTab = 1;

  static const List<String> _bookTabs = ['About', 'Games', 'Events'];
  static const List<String> _eventTabs = ['About', 'Games', 'Books', 'Players'];

  /// Fixed by the kind the page opened as, so the tab strip never changes
  /// under the viewer.
  late final bool _isBook = widget.collection.kind == CollectionKind.book;

  final EventViewController _tabs = EventViewController();

  /// The player whose games the Games tab shows, or null for all.
  CollectionPlayer? _player;

  /// A preview opens on About (the cover and the credits sell it; the
  /// contents wait on Games); a collection the viewer reads opens on its
  /// games. Decided once, from what is known on the first frame.
  late final int _initialTab = _isLocked(widget.collection)
      ? _aboutTab
      : _gamesTab;

  /// Where the way in stands: offered, or the page confirming the viewer's
  /// Premium with the server, or that confirm having run out.
  CollectionUnlockPhase _phase = CollectionUnlockPhase.offer;

  /// A subscriber the server still has as locked is confirmed once on its
  /// own; after that only a tap asks again.
  bool _autoConfirmed = false;

  /// The confirm was asked for from About's "Read all N games": once the
  /// server opens the collection, the page turns to those games.
  bool _openGamesOnConfirm = false;

  late final CollectionPremiumConfirm _confirm = CollectionPremiumConfirm(
    check: _checkAccess,
    onPhase: _onConfirmPhase,
  );

  @override
  void dispose() {
    _confirm.cancel();
    _tabs.dispose();
    super.dispose();
  }

  bool _isLocked(Collection c) {
    final subscription = ref.read(subscriptionProvider);
    return isCollectionLocked(
      c,
      isSubscribed: subscription.isSubscribed,
      subscriptionLoading: subscription.isLoading,
    );
  }

  /// One try of the confirm: the server asked again for its verdict (anew,
  /// past the "not Premium" it keeps a few seconds) and, when that opens
  /// the collection (or the server could not say), for the games
  /// themselves, which are the proof.
  Future<CollectionAccessCheck> _checkAccess() async {
    final slug = widget.collection.slug;
    final release = ref
        .read(collectionsRepositoryProvider)
        .holdFreshAccess(slug);
    try {
      refreshCollectionAccess(ref, slug);
      final detail = await ref.read(collectionDetailProvider(slug).future);
      // The page closed while the server answered: the run is over.
      if (!mounted) return CollectionAccessCheck.locked;
      if (!detail.isPremium) return CollectionAccessCheck.open;
      if (detail.contentLocked == true) {
        return detail.lockedForSignIn
            ? CollectionAccessCheck.signInRefused
            : CollectionAccessCheck.locked;
      }
      // Held while it is read: the page itself watches the games only once
      // it has drawn the verdict.
      final keep = ref.listenManual(collectionGamesProvider(slug), (_, __) {});
      try {
        await ref.read(collectionGamesProvider(slug).future);
        return CollectionAccessCheck.open;
      } catch (e) {
        if (e is CollectionsRequestException && e.isPremiumGate) {
          return e.isSignInGate
              ? CollectionAccessCheck.signInRefused
              : CollectionAccessCheck.locked;
        }
        // The verdict opened it: the games' own failure is the Games tab's
        // to show, with its own retry.
        if (detail.contentLocked == false) return CollectionAccessCheck.open;
        // No verdict and no games (offline, the check out of reach): no
        // answer, so never a success. The confirm asks again.
        rethrow;
      } finally {
        keep.close();
      }
    } finally {
      release();
    }
  }

  void _onConfirmPhase(CollectionUnlockPhase phase) {
    if (!mounted) return;
    final failedAt = ref.read(collectionConfirmFailedAtProvider.notifier);
    switch (phase) {
      case CollectionUnlockPhase.failed:
      case CollectionUnlockPhase.signIn:
        failedAt.state = DateTime.now();
      case CollectionUnlockPhase.offer:
        // The server opened it: whatever failed before is behind us.
        failedAt.state = null;
        HapticFeedbackService.success();
        if (_openGamesOnConfirm) _tabs.showTab(_gamesTab);
        _openGamesOnConfirm = false;
      case CollectionUnlockPhase.confirming:
        break;
    }
    setState(() => _phase = phase);
  }

  /// Confirms the viewer's Premium with the server.
  void _startConfirm() {
    if (!mounted) return;
    unawaited(_confirm.start());
  }

  /// The server refused the session: the account sheet, and once the
  /// viewer is back signed in, the confirm again on the new session.
  Future<void> _signInAgain() async {
    final signedIn = await ref.read(collectionSignInProvider)(context);
    if (!mounted || !signedIn) return;
    _startConfirm();
  }

  /// The way in, tapped. A subscriber (or a retry after a confirm ran out)
  /// confirms with the server; a refused session signs in again; anyone
  /// else gets the paywall, and a purchase there confirms the same way.
  /// [openGames]: the tap came from About, so the opened collection shows
  /// its games.
  void _unlock(Collection c, {bool openGames = false}) {
    if (_phase == CollectionUnlockPhase.confirming) return;
    _openGamesOnConfirm = openGames;
    if (_phase == CollectionUnlockPhase.signIn) {
      HapticFeedbackService.buttonPress();
      unawaited(_signInAgain());
      return;
    }
    if (_phase == CollectionUnlockPhase.failed ||
        ref.read(subscriptionProvider).isSubscribed) {
      HapticFeedbackService.buttonPress();
      _startConfirm();
      return;
    }
    unawaited(unlockCollection(context, ref, c, onEntitled: _startConfirm));
  }

  void _showPlayer(CollectionPlayer? player) {
    HapticFeedbackService.selection();
    setState(() => _player = player);
    if (player != null) _tabs.showTab(_gamesTab);
  }

  /// Collection games carry their whole PGN, so the board replays them as it
  /// replays an imported file. [games] is the whole list in the order shown,
  /// so prev/next walks the collection.
  void _openGame(List<GamesTourModel> games, int index) {
    HapticFeedbackService.cardTap();
    ref.read(chessboardViewFromProviderNew.notifier).state =
        ChessboardView.tour;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ChessBoardScreenNew(
          currentIndex: index,
          games: games,
          viewSource: ChessboardView.tour,
          showGamebaseButton: false,
          disableGamebaseOverlayByDefault: true,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final slug = widget.collection.slug;
    final detail = ref.watch(collectionDetailProvider(slug));
    final c = detail.valueOrNull ?? widget.collection;
    final subscription = ref.watch(subscriptionProvider);
    final locked = isCollectionLocked(
      c,
      isSubscribed: subscription.isSubscribed,
      subscriptionLoading: subscription.isLoading,
    );
    // Nothing behind the paywall is asked for while it stands: the games
    // and players are read only once the viewer may see them.
    final contents = locked
        ? null
        : ref.watch(collectionContentsProvider(slug));
    final players = locked ? null : ref.watch(collectionPlayersProvider(slug));
    // The server keeps the games from a viewer the app knows as a
    // subscriber (a purchase it has not seen yet, a session it refused, a
    // check that was down): the page confirms on its own, once, instead of
    // offering a subscriber the paywall.
    final serverLocked =
        c.isPremium &&
        (c.contentLocked == true ||
            isCollectionPremiumGate(contents?.error) ||
            isCollectionPremiumGate(players?.error));
    if (serverLocked &&
        subscription.isSubscribed &&
        !_autoConfirmed &&
        _phase == CollectionUnlockPhase.offer) {
      _autoConfirmed = true;
      // Decided before this frame draws, so a subscriber never sees the
      // offer (nor About's facts shift) for the frame before the confirm.
      final failedAt = ref.read(collectionConfirmFailedAtProvider);
      if (failedAt != null &&
          DateTime.now().difference(failedAt) <
              kCollectionConfirmFailureMemory) {
        // A confirm ran out a moment ago: said again at once, with its way
        // on, instead of confirming for the whole window again.
        final refused =
            c.lockedForSignIn ||
            _isSignInGate(contents?.error) ||
            _isSignInGate(players?.error);
        _phase = refused
            ? CollectionUnlockPhase.signIn
            : CollectionUnlockPhase.failed;
      } else {
        _phase = CollectionUnlockPhase.confirming;
        WidgetsBinding.instance.addPostFrameCallback((_) => _startConfirm());
      }
    }
    final phase = _phase;
    void unlock() => _unlock(c);
    // While the page confirms, the locked lines wait with it.
    final VoidCallback? lineTap = phase == CollectionUnlockPhase.confirming
        ? null
        : unlock;

    // The detail read, when it has nothing better than the list row to show
    // yet: the Events tab waits on it, the Books tab when it opened by slug.
    final detailPending = detail.isLoading && !detail.hasValue;
    final detailError = detail.hasError && !detail.hasValue && !detail.isLoading
        ? detail.error
        : null;
    void retryDetail() => ref.invalidate(collectionDetailProvider(slug));
    // Held for the page's life, as its games and players are: the tabs'
    // pages come and go as the viewer swipes, and the Books tab should not
    // ask again (nor flash its skeleton) each time it comes back.
    if (!_isBook && c.id.isNotEmpty) {
      ref.watch(collectionBooksOfEventCollectionProvider(c.id));
    }

    return EventViewShell(
      title: c.title,
      tabs: _isBook ? _bookTabs : _eventTabs,
      initialTab: _initialTab,
      controller: _tabs,
      pageBuilder: (context, index) {
        return switch (index) {
          0 => _AboutPage(
            collection: c,
            playerCount: players?.valueOrNull?.length,
            // A refusal of the games is the server's verdict too.
            locked:
                locked ||
                isCollectionPremiumGate(contents?.error) ||
                isCollectionPremiumGate(players?.error),
            phase: phase,
            onUnlock: () => _unlock(c, openGames: true),
            // Only when there is nothing better than the list row to show;
            // hidden while a retry is in flight so the tap reads as taken.
            error: detailError,
            onRetry: retryDetail,
          ),
          1 =>
            contents == null
                ? _LockedContents(
                    collection: c,
                    phase: phase,
                    onUnlock: unlock,
                    onLineTap: lineTap,
                  )
                : contents.when(
                    // A re-check reloads the games: a refusal on screen
                    // stays until the server's new answer, never a flash
                    // of the skeleton on every try.
                    skipLoadingOnReload: isCollectionPremiumGate(
                      contents.error,
                    ),
                    data: (data) => _GamesPage(
                      contents: data,
                      player: _player,
                      onClearPlayer: () => _showPlayer(null),
                      onOpen: _openGame,
                    ),
                    loading: () => const _CardsSkeleton(),
                    error: (error, _) => isCollectionPremiumGate(error)
                        // The server knows better than the app's subscription
                        // state (a purchase it has not seen yet): the preview.
                        ? _LockedContents(
                            collection: c,
                            phase: phase,
                            onUnlock: unlock,
                            onLineTap: lineTap,
                          )
                        : _Notice(
                            text: _collectionErrorText(
                              error,
                              fallback: "Couldn't load the games.",
                            ),
                            actionLabel: 'Try again',
                            onAction: () {
                              ref.invalidate(collectionDetailProvider(slug));
                              ref.invalidate(collectionGamesProvider(slug));
                            },
                          ),
                  ),
          // Public on both kinds, locked or not: what a book covers and
          // what was written about an event are its credits, not its games.
          2 when _isBook => _EventsPage(
            events: c.events,
            pending: detailPending,
            error: detailError,
            onRetry: retryDetail,
          ),
          2 => _BooksPage(
            collectionId: c.id,
            pending: detailPending,
            error: detailError,
            onRetry: retryDetail,
          ),
          _ =>
            players == null
                ? _LockedPlayers(collection: c, phase: phase, onUnlock: unlock)
                : players.when(
                    skipLoadingOnReload: isCollectionPremiumGate(
                      players.error,
                    ),
                    data: (list) =>
                        _PlayersPage(players: list, onPick: _showPlayer),
                    loading: () => const _CardsSkeleton(),
                    error: (error, _) => isCollectionPremiumGate(error)
                        ? _LockedPlayers(
                            collection: c,
                            phase: phase,
                            onUnlock: unlock,
                          )
                        : _Notice(
                            text: _collectionErrorText(
                              error,
                              fallback: "Couldn't load the players.",
                            ),
                            actionLabel: 'Try again',
                            onAction: () =>
                                ref.invalidate(collectionPlayersProvider(slug)),
                          ),
                  ),
        };
      },
    );
  }
}

bool _isSignInGate(Object? error) =>
    error is CollectionsRequestException && error.isSignInGate;

/// [error] as the reader sees it. The Premium check being out of reach is
/// said as such: the reader may well be entitled, so it is a retry, never
/// a paywall and never "your session has expired".
String _collectionErrorText(Object? error, {required String fallback}) {
  if (error is CollectionsRequestException && error.isAccessCheckUnavailable) {
    return "Couldn't check your Premium access just now.";
  }
  return userFacingError(error, fallback: fallback);
}

/// The Premium outcome a locked collection sells, the same sentence on every
/// tab: what the reader gets, not the word "Premium".
String _unlockLabel(Collection c) {
  final n = c.gameCount;
  if (c.kind == CollectionKind.book) {
    return switch (n) {
      0 => 'Read this book',
      1 => 'Read the game in this book',
      _ => 'Read all $n games in this book',
    };
  }
  return switch (n) {
    0 => 'Replay these games',
    1 => 'Replay the game',
    _ => 'Replay all $n games',
  };
}

/// The one way into a locked collection, in the phase the page is in.
///
/// Offered: its outcome in accent ink with the Premium padlock after it
/// (the locked action's one mark), a 44 target, the paywall behind it.
/// Confirming: a quiet line saying the page is checking the viewer's
/// Premium with the server, no target. Failed: that the check did not go
/// through, and a retry. Sign in: that the server no longer takes the
/// viewer's sign-in, and the way to sign in again. Every phase stands on
/// the same 44 floor, so the page never shifts as one gives way to the
/// next.
class _UnlockAction extends StatelessWidget {
  const _UnlockAction({
    required this.collection,
    required this.phase,
    required this.onUnlock,
  });

  final Collection collection;
  final CollectionUnlockPhase phase;

  /// The way in for every phase: the page routes it (paywall, confirm,
  /// sign in) by the phase it is in.
  final VoidCallback onUnlock;

  // No cross-fade between phases: each one is on screen the frame it
  // applies, never waiting on an animation to be readable.
  @override
  Widget build(BuildContext context) => switch (phase) {
    CollectionUnlockPhase.offer => _offer(),
    CollectionUnlockPhase.confirming => const _ConfirmingLine(),
    CollectionUnlockPhase.failed => _UnlockStatusLine(
      text: _UnlockStatusLine.failedText,
      actionLabel: 'Try again',
      actionKey: const ValueKey('collection_unlock_retry'),
      onAction: onUnlock,
    ),
    CollectionUnlockPhase.signIn => _UnlockStatusLine(
      text: _UnlockStatusLine.signInText,
      actionLabel: 'Sign in again',
      actionKey: const ValueKey('collection_unlock_sign_in'),
      onAction: onUnlock,
    ),
  };

  Widget _offer() {
    final label = _unlockLabel(collection);
    return Align(
      alignment: Alignment.centerLeft,
      child: DiscoveryAction(
        key: const ValueKey('collection_unlock'),
        label: label,
        onTap: onUnlock,
        trailingPadlock: true,
        wraps: true,
        semanticsLabel: '$label, Premium',
      ),
    );
  }
}

/// The confirm under way: a small turning ring and the sentence, in
/// secondary ink, announced to a screen reader as it appears.
class _ConfirmingLine extends StatelessWidget {
  const _ConfirmingLine();

  static const String text = 'Confirming your Premium…';

  @override
  Widget build(BuildContext context) {
    final ink = context.colors.textSecondary;
    final style = discoveryType(context, DiscoveryType.label, color: ink);
    final line = MediaQuery.textScalerOf(context).scale(13.f) * 18 / 13;
    final ring = 12.w;
    return Semantics(
      key: const ValueKey('collection_unlock_status'),
      container: true,
      liveRegion: true,
      label: 'Confirming your Premium',
      excludeSemantics: true,
      child: DiscoveryInkFloor(
        minHeight: 44.w,
        inset: math.max(0, (44.w - line) / 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // On the first line's centre, beside the words it belongs to.
            SizedBox(
              height: line,
              child: Center(
                child: _TurningRing(size: ring, color: ink),
              ),
            ),
            SizedBox(width: 8.w),
            Flexible(child: Text(text, style: style)),
          ],
        ),
      ),
    );
  }
}

/// A quarter arc turning on a faint track: work under way, the same
/// length in every frame. Still (the arc at rest) when the system asks for
/// less motion.
class _TurningRing extends StatefulWidget {
  const _TurningRing({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  State<_TurningRing> createState() => _TurningRingState();
}

class _TurningRingState extends State<_TurningRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _turn = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _turn.stop();
    } else if (!_turn.isAnimating) {
      _turn.repeat();
    }
  }

  @override
  void dispose() {
    _turn.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RotationTransition(
      turns: _turn,
      child: SizedBox.square(
        dimension: widget.size,
        child: CircularProgressIndicator(
          value: 0.28,
          strokeWidth: 1.5,
          strokeCap: StrokeCap.round,
          color: widget.color,
          backgroundColor: widget.color.withValues(alpha: 0.2),
        ),
      ),
    );
  }
}

/// The confirm ended without the server opening the collection: what
/// happened, in secondary ink, and the way on beside it (a retry, or
/// signing in again).
class _UnlockStatusLine extends StatelessWidget {
  const _UnlockStatusLine({
    required this.text,
    required this.actionLabel,
    required this.actionKey,
    required this.onAction,
  });

  static const String failedText = "Couldn't confirm your Premium just now.";
  static const String signInText = 'Your sign-in has expired.';

  final String text;
  final String actionLabel;
  final Key actionKey;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final line = MediaQuery.textScalerOf(context).scale(13.f) * 18 / 13;
    return Semantics(
      key: const ValueKey('collection_unlock_status'),
      container: true,
      liveRegion: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Flexible(
            child: DiscoveryInkFloor(
              minHeight: 44.w,
              inset: math.max(0, (44.w - line) / 2),
              child: Text(
                text,
                style: discoveryType(
                  context,
                  DiscoveryType.label,
                  color: context.colors.textSecondary,
                ),
              ),
            ),
          ),
          SizedBox(width: 12.w),
          DiscoveryAction(key: actionKey, label: actionLabel, onTap: onAction),
        ],
      ),
    );
  }
}

class _AboutPage extends ConsumerWidget {
  const _AboutPage({
    required this.collection,
    required this.playerCount,
    required this.locked,
    required this.phase,
    required this.onUnlock,
    this.error,
    this.onRetry,
  });

  final Collection collection;

  /// Null until the Players read lands (and while the collection is locked).
  final int? playerCount;

  /// The viewer sees the preview: the credits, the contents and the way in.
  final bool locked;
  final CollectionUnlockPhase phase;
  final VoidCallback onUnlock;

  /// Why the detail read failed, when [collection] is still just the list
  /// row (no About text, credits or edition).
  final Object? error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final c = collection;
    final paragraphs = _paragraphs(c.about);
    final foreword = _paragraphs(c.foreword);
    final players = playerCount;
    // The offered way in says how many games wait behind it ("Read all 55
    // games in this book"), so the facts do not say it again right above.
    final offersCount = locked && phase == CollectionUnlockPhase.offer;
    final facts = [
      if (!offersCount) c.gameCount == 1 ? '1 game' : '${c.gameCount} games',
      if (players != null && players > 0)
        players == 1 ? '1 player' : '$players players',
    ].join(' · ');
    final isBook = c.kind == CollectionKind.book;
    final credit = isBook ? c.author : c.annotator ?? c.author;
    final annotator = isBook && c.annotator != c.author ? c.annotator : null;
    final edition = isBook
        ? [?c.publisher, if (c.publishedYear != null) '${c.publishedYear}']
        : [?collectionPlaceAndDates(c)];
    final body = AppTypography.textSmRegular.copyWith(
      color: colors.textPrimary,
      fontSize: 15.f,
      height: 22 / 15,
    );
    final secondary = AppTypography.textSmRegular.copyWith(
      color: colors.textSecondary,
    );
    return ListView(
      padding: EdgeInsets.fromLTRB(
        20.sp,
        20.sp,
        20.sp,
        32.sp + MediaQuery.viewPaddingOf(context).bottom,
      ),
      children: [
        if (c.coverUrl != null) ...[
          if (isBook)
            _BookCover(collection: c)
          else
            ClipRRect(
              borderRadius: BorderRadius.circular(8.br),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: _Cover(collection: c),
              ),
            ),
          SizedBox(height: isBook ? 20.sp : 16.sp),
        ],
        Text(
          c.title,
          style: AppTypography.textSmMedium.copyWith(
            color: colors.textPrimary,
            fontSize: 20.f,
            height: 26 / 20,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.2,
          ),
        ),
        if (credit != null) ...[
          SizedBox(height: 4.sp),
          Text(
            isBook ? 'by $credit' : 'Annotated by $credit',
            style: AppTypography.textSmMedium.copyWith(
              color: colors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
        if (annotator != null) ...[
          SizedBox(height: 4.sp),
          Text('Annotated by $annotator', style: secondary),
        ],
        if (c.subtitle != null) ...[
          SizedBox(height: 4.sp),
          Text(c.subtitle!, style: secondary),
        ],
        if (edition.isNotEmpty) ...[
          SizedBox(height: 4.sp),
          Text(edition.join(' · '), style: secondary),
        ],
        if (facts.isNotEmpty) ...[
          SizedBox(height: 4.sp),
          Text(facts, style: secondary),
        ],
        if (locked) ...[
          SizedBox(height: 4.sp),
          _UnlockAction(collection: c, phase: phase, onUnlock: onUnlock),
        ],
        if (error != null) ...[
          SizedBox(height: 16.sp),
          Row(
            children: [
              Expanded(
                child: Text(
                  userFacingError(
                    error,
                    fallback: "Couldn't load the rest of this collection.",
                  ),
                  style: secondary,
                ),
              ),
              if (onRetry != null)
                TextButton(
                  onPressed: onRetry,
                  child: Text(
                    'Try again',
                    style: AppTypography.textSmMedium.copyWith(
                      color: colors.accentText,
                    ),
                  ),
                ),
            ],
          ),
        ],
        for (final p in paragraphs) ...[
          SizedBox(height: 16.sp),
          Text(p, style: body),
        ],
        // The author's own foreword, when the book has one: after the
        // description, under a heading of the page's own voice.
        if (foreword.isNotEmpty) ...[
          SizedBox(height: 28.sp),
          Semantics(
            header: true,
            child: Text('Foreword', style: _aboutHeadingStyle(context)),
          ),
          for (var i = 0; i < foreword.length; i++) ...[
            SizedBox(height: i == 0 ? 10.sp : 16.sp),
            Text(
              foreword[i],
              key: i == 0 ? const ValueKey('collection_foreword') : null,
              style: body,
            ),
          ],
        ],
      ],
    );
  }
}

/// A book's jacket on its About page, whole: standing 2:3 as it was
/// printed, centred over the title as a shelf would show it, never cropped
/// to a landscape band that loses its title and author. A tight shadow cast
/// from above lifts it off a light page; on a dark one a faint lip of the
/// ink separates a dark jacket from the ground.
class _BookCover extends StatelessWidget {
  const _BookCover({required this.collection});

  final Collection collection;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isLight = context.isLightTheme;
    final radius = BorderRadius.circular(4.br);
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = math.min(constraints.maxWidth * 0.42, 200.0);
        return Center(
          child: Container(
            width: width,
            height: width * 3 / 2,
            decoration: BoxDecoration(
              borderRadius: radius,
              boxShadow: isLight
                  ? [
                      BoxShadow(
                        color: colors.textPrimary.withValues(alpha: 0.16),
                        offset: const Offset(0, 3),
                        blurRadius: 8,
                        spreadRadius: -2,
                      ),
                    ]
                  : null,
            ),
            foregroundDecoration: isLight
                ? null
                : BoxDecoration(
                    borderRadius: radius,
                    border: Border.all(
                      color: colors.textPrimary.withValues(alpha: 0.1),
                    ),
                  ),
            child: ClipRRect(
              borderRadius: radius,
              child: _Cover(collection: collection),
            ),
          ),
        );
      },
    );
  }
}

/// A heading inside the About page: the page's own ink and weight, no
/// label above it and no rule beside it.
TextStyle _aboutHeadingStyle(BuildContext context) =>
    AppTypography.textSmMedium.copyWith(
      color: context.colors.textPrimary,
      fontSize: 15.f,
      height: 20 / 15,
      fontWeight: FontWeight.w600,
    );

/// A book's Events tab: the events it covers, each drawn as the Collection
/// list draws an event (its image or the trophy, the name, the place and
/// dates) with the team's note under it. A tap opens the event wherever it
/// lives: its broadcast, its database page, or its annotated collection.
/// The events arrive with the detail read, so the tab waits on it (or says
/// it failed, with a retry) while it has none from the list row.
class _EventsPage extends StatelessWidget {
  const _EventsPage({
    required this.events,
    required this.pending,
    required this.error,
    required this.onRetry,
  });

  final List<CollectionEventRef> events;
  final bool pending;
  final Object? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (events.isEmpty) {
      if (pending) return const _CardsSkeleton();
      final failed = error;
      if (failed != null) {
        return _Notice(
          text: userFacingError(
            failed,
            fallback: "Couldn't load this book's events.",
          ),
          actionLabel: 'Try again',
          onAction: onRetry,
        );
      }
      return const _Notice(text: 'No events for this book yet.');
    }
    return ListView.builder(
      key: const PageStorageKey<String>('collection_events'),
      padding: _tabListPadding(context),
      itemCount: events.length,
      itemBuilder: (context, i) => Padding(
        padding: EdgeInsets.only(bottom: 12.sp),
        child: _EventRefRow(
          key: ValueKey<String>('collection_event_${events[i].linkId}'),
          event: events[i],
        ),
      ),
    );
  }
}

/// An event collection's Books tab: the books written about it, each drawn
/// as the Books list draws a book, with the team's note on why it belongs
/// here. A book opens on its own page (its preview, for a viewer without
/// Premium). [collectionId] is empty while a page opened by slug (from a
/// book's event) waits on its detail read.
class _BooksPage extends ConsumerWidget {
  const _BooksPage({
    required this.collectionId,
    required this.pending,
    required this.error,
    required this.onRetry,
  });

  final String collectionId;
  final bool pending;

  /// The detail read's failure, when the page still has no id to ask with.
  final Object? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (collectionId.isEmpty) {
      final failed = error;
      if (failed != null && !pending) {
        return _Notice(
          text: userFacingError(
            failed,
            fallback: "Couldn't load the books about this event.",
          ),
          actionLabel: 'Try again',
          onAction: onRetry,
        );
      }
      return const _CardsSkeleton();
    }
    final books = ref.watch(
      collectionBooksOfEventCollectionProvider(collectionId),
    );
    return books.when(
      data: (list) => list.isEmpty
          ? const _Notice(text: 'No books about this event yet.')
          : ListView.builder(
              key: const PageStorageKey<String>('collection_books'),
              padding: _tabListPadding(context),
              itemCount: list.length,
              itemBuilder: (context, i) => Padding(
                padding: EdgeInsets.only(bottom: 12.sp),
                child: CollectionCard(
                  key: ValueKey<String>('event_book_${list[i].id}'),
                  collection: list[i],
                  note: list[i].note,
                ),
              ),
            ),
      loading: () => const _CardsSkeleton(),
      error: (error, _) => _Notice(
        text: userFacingError(
          error,
          fallback: "Couldn't load the books about this event.",
        ),
        actionLabel: 'Try again',
        onAction: () => ref.invalidate(
          collectionBooksOfEventCollectionProvider(collectionId),
        ),
      ),
    );
  }
}

/// A card list on a collection's tab: the Collection list's own gutters.
EdgeInsets _tabListPadding(BuildContext context) => EdgeInsets.fromLTRB(
  16.sp,
  16.sp,
  16.sp,
  12.sp + MediaQuery.viewPaddingOf(context).bottom,
);

class _EventRefRow extends ConsumerWidget {
  const _EventRefRow({super.key, required this.event});

  final CollectionEventRef event;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final e = event;
    // Room for the dates on a second line: a range across two years fills
    // one line alone.
    final line = collectionEventLine(e.location, e.dateStart, e.dateEnd);
    final canOpen = e.open != null;
    return CollectionPlateRow(
      plate: _EventPlate(imageUrl: e.imageUrl),
      title: e.title,
      meta: line,
      metaMaxLines: 2,
      note: e.note,
      semanticsLabel: [
        e.title,
        ?line,
        ?e.note,
        if (canOpen) 'Open event',
      ].join(', '),
      onTap: canOpen ? () => openCollectionEvent(context, ref, e) : null,
    );
  }
}

/// An event's picture, or the trophy the Collection list gives events
/// without one.
class _EventPlate extends StatelessWidget {
  const _EventPlate({required this.imageUrl});

  final String? imageUrl;

  @override
  Widget build(BuildContext context) {
    final plate = _PixelPlate(section: SpaceSection.events);
    final url = imageUrl;
    if (url == null) return plate;
    return CachedNetworkImage(
      imageUrl: url,
      fit: BoxFit.cover,
      placeholder: (_, __) => plate,
      errorWidget: (_, __, ___) => plate,
    );
  }
}

/// A locked collection's Games tab: its contents as the book prints them
/// (parts, then their chapters with how many games each holds), every entry
/// a way to the paywall, and the outcome line leading them.
class _LockedContents extends StatelessWidget {
  const _LockedContents({
    required this.collection,
    required this.phase,
    required this.onUnlock,
    required this.onLineTap,
  });

  final Collection collection;
  final CollectionUnlockPhase phase;
  final VoidCallback onUnlock;

  /// A chapter's tap; null while the page confirms the viewer's Premium.
  final VoidCallback? onLineTap;

  @override
  Widget build(BuildContext context) {
    final rows = <({CollectionSection section, int depth})>[];
    void walk(List<CollectionSection> nodes, int depth) {
      for (final s in nodes) {
        rows.add((section: s, depth: depth));
        walk(s.children, depth + 1);
      }
    }

    walk(collection.sections, 0);
    // A book kept without parts or chapters has no contents to show: the
    // preview says who plays in it instead, as its Players tab does, so the
    // way in never stands alone on an empty page.
    if (rows.isEmpty) {
      return _LockedPlayers(
        key: const PageStorageKey<String>('collection_locked_contents'),
        collection: collection,
        phase: phase,
        onUnlock: onUnlock,
      );
    }
    final leadWidth = _contentsLeadWidth(context, [
      for (final r in rows) r.section,
    ]);
    return ListView.builder(
      key: const PageStorageKey<String>('collection_locked_contents'),
      padding: EdgeInsets.only(
        top: 8.sp,
        bottom: 24.sp + MediaQuery.viewPaddingOf(context).bottom,
      ),
      itemCount: rows.length + 1,
      itemBuilder: (context, i) {
        if (i == 0) {
          return Padding(
            padding: EdgeInsets.fromLTRB(
              _headerInset,
              0,
              _headerInset,
              4.sp,
            ),
            child: _UnlockAction(
              collection: collection,
              phase: phase,
              onUnlock: onUnlock,
            ),
          );
        }
        final row = rows[i - 1];
        return _ContentsRow(
          key: ValueKey<String>('collection_contents_${row.section.id}'),
          section: row.section,
          depth: row.depth,
          first: i == 1,
          leadWidth: leadWidth,
          onTap: onLineTap,
        );
      },
    );
  }
}

/// What a contents line says: its number or label in quiet ink ([lead],
/// when the section has a title of its own) and its title.
({String? lead, String title}) _contentsLabel(CollectionSection s) {
  final named = s.title != null && s.title != s.label;
  final ({String? lead, String title}) label = switch (s.kind) {
    CollectionSectionKind.part => (
      lead: named ? s.label : null,
      title: named ? s.title! : s.label,
    ),
    CollectionSectionKind.chapter => (
      lead: named ? s.number ?? s.label : null,
      title: named ? s.title! : s.label,
    ),
    CollectionSectionKind.round ||
    CollectionSectionKind.stage ||
    CollectionSectionKind.other => (
      lead: null,
      title: named ? '${s.label} · ${s.title}' : s.label,
    ),
  };
  if (label.title.isNotEmpty) return label;
  return (lead: label.lead, title: s.number ?? 'Games');
}

/// A chapter or round line of a locked collection's contents.
TextStyle _contentsLineStyle(BuildContext context) => AppTypography.textSmMedium
    .copyWith(color: context.colors.textPrimary, fontWeight: FontWeight.w500);

double get _contentsLeadGap => 8.sp;

/// The width of the widest chapter number among [rows], as the contents
/// set it, so every chapter title starts on one line down the list.
double _contentsLeadWidth(
  BuildContext context,
  Iterable<CollectionSection> rows,
) {
  final style = _contentsLineStyle(
    context,
  ).copyWith(fontFeatures: const [FontFeature.tabularFigures()]);
  final scaler = MediaQuery.textScalerOf(context);
  var widest = 0.0;
  for (final s in rows) {
    if (s.kind == CollectionSectionKind.part) continue;
    final lead = _contentsLabel(s).lead;
    if (lead == null) continue;
    final painter = TextPainter(
      text: TextSpan(text: lead, style: style),
      textDirection: Directionality.of(context),
      textScaler: scaler,
      maxLines: 1,
    )..layout();
    widest = math.max(widest, painter.width);
    painter.dispose();
  }
  return widest.ceilToDouble();
}

/// One entry of a locked collection's contents. A part is a heading; a
/// chapter or round is a 44-high line with its number in quiet ink, its
/// title, and on the right its game count and the padlock.
class _ContentsRow extends StatelessWidget {
  const _ContentsRow({
    super.key,
    required this.section,
    required this.depth,
    required this.first,
    required this.leadWidth,
    required this.onTap,
  });

  final CollectionSection section;
  final int depth;
  final bool first;

  /// The width of the list's number column (its widest chapter number),
  /// 0 when no chapter carries one.
  final double leadWidth;

  /// Null while the page confirms the viewer's Premium.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final s = section;
    final isPart = s.kind == CollectionSectionKind.part;
    final (:lead, :title) = _contentsLabel(s);
    final main = isPart
        ? AppTypography.textSmMedium.copyWith(
            color: colors.textPrimary,
            fontSize: 17.f,
            height: 22 / 17,
            fontWeight: FontWeight.w700,
          )
        : _contentsLineStyle(context);
    final muted = main.copyWith(
      color: colors.textSecondary,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    // A chapter's title is what sells the book: two lines, as a part's.
    // Its number stands in the list's own column, so a title that wraps
    // hangs clear of the numbers, as a printed table of contents does.
    final Widget heading = !isPart && lead != null && leadWidth > 0
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              SizedBox(
                width: leadWidth,
                child: Text(
                  lead,
                  maxLines: 1,
                  softWrap: false,
                  textAlign: TextAlign.right,
                  style: muted,
                ),
              ),
              SizedBox(width: _contentsLeadGap),
              Expanded(
                child: Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: main,
                ),
              ),
            ],
          )
        : Text.rich(
            TextSpan(
              children: [
                if (lead != null) TextSpan(text: '$lead  ', style: muted),
                TextSpan(text: title),
              ],
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: main,
          );

    if (isPart) {
      return Semantics(
        header: true,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            _headerInset,
            first ? 8.sp : 24.sp,
            _headerInset,
            4.sp,
          ),
          child: heading,
        ),
      );
    }

    final count = s.gameCount == 1 ? '1 game' : '${s.gameCount} games';
    final tap = onTap;
    final line = Container(
      constraints: BoxConstraints(minHeight: 44.sp),
      // A title that wraps keeps clear of the next line's.
      padding: EdgeInsets.fromLTRB(
        _headerInset + (depth > 0 ? 12.sp : 0),
        8.sp,
        _headerInset,
        8.sp,
      ),
      alignment: Alignment.centerLeft,
      child: Row(
        children: [
          Expanded(child: heading),
          if (s.gameCount > 0) ...[
            SizedBox(width: 12.sp),
            Text(
              count,
              style: AppTypography.textXsMedium.copyWith(
                color: colors.textSecondary,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
          SizedBox(width: DiscoveryPadlock.gap + 2.sp),
          DiscoveryPadlock(color: colors.textSecondary),
        ],
      ),
    );
    return Semantics(
      button: tap != null,
      label: '${lead == null ? '' : '$lead '}$title, $count, Premium',
      excludeSemantics: true,
      onTap: tap,
      // A list line answers a press with a wash of the card surface, the
      // way a table row does; it does not shrink. No press while the page
      // is confirming the viewer's Premium: the line at the top says so.
      child: tap == null
          ? line
          : WallPressable(wash: colors.surface, onTap: tap, child: line),
    );
  }
}

/// A locked collection's Players tab: who is in it stays behind the same
/// boundary as their games.
class _LockedPlayers extends StatelessWidget {
  const _LockedPlayers({
    super.key,
    required this.collection,
    required this.phase,
    required this.onUnlock,
  });

  final Collection collection;
  final CollectionUnlockPhase phase;
  final VoidCallback onUnlock;

  @override
  Widget build(BuildContext context) {
    final names = collection.players.take(6).toList();
    final more = collection.players.length - names.length;
    return ListView(
      padding: EdgeInsets.fromLTRB(
        _headerInset,
        8.sp,
        _headerInset,
        24.sp + MediaQuery.viewPaddingOf(context).bottom,
      ),
      children: [
        _UnlockAction(collection: collection, phase: phase, onUnlock: onUnlock),
        if (names.isNotEmpty) ...[
          SizedBox(height: 8.sp),
          Text(
            // Names read "Last, First", so a comma cannot also part them.
            [...names, if (more > 0) '$more more'].join(' · '),
            style: AppTypography.textSmRegular.copyWith(
              color: context.colors.textSecondary,
              height: 20 / 14,
            ),
          ),
        ],
      ],
    );
  }
}

/// [text]'s paragraphs: blank lines separate them.
List<String> _paragraphs(String? text) => [
  for (final p in (text ?? '').split(RegExp(r'\n\s*\n')))
    if (p.trim().isNotEmpty) p.trim(),
];

class _GamesPage extends StatelessWidget {
  const _GamesPage({
    required this.contents,
    required this.player,
    required this.onClearPlayer,
    required this.onOpen,
  });

  final CollectionContents contents;
  final CollectionPlayer? player;
  final VoidCallback onClearPlayer;
  final void Function(List<GamesTourModel> games, int index) onOpen;

  /// By key only: cards and player rows share it (`fide:<id>` or
  /// `name:<lower>`), and the Players tab counts games the same way. A name
  /// match across different keys is a namesake, not the same player.
  static bool _plays(CollectionGame g, CollectionPlayer p) =>
      g.card.involves(p.key);

  @override
  Widget build(BuildContext context) {
    if (contents.games.isEmpty) {
      return const _Notice(text: 'No games in this collection yet.');
    }
    final picked = player;
    final groups = groupCollectionGames(contents.sections, [
      for (final g in contents.games)
        if (picked == null || _plays(g, picked)) g,
    ]);
    // The order the board steps through: exactly the order drawn.
    final ordered = [
      for (final group in groups)
        for (final g in group.games) g.game,
    ];
    // A collection with no sections lists its games with no headers at all.
    final headed = groups.any((g) => g.section != null);
    final lead = picked == null ? 0 : 1;
    return ListView.builder(
      padding: EdgeInsets.only(
        top: 16.sp,
        bottom: 24.sp + MediaQuery.viewPaddingOf(context).bottom,
      ),
      itemCount: lead + (groups.isEmpty ? 1 : groups.length),
      itemBuilder: (context, i) {
        if (picked != null && i == 0) {
          return _PlayerLine(name: picked.name, onClear: onClearPlayer);
        }
        if (groups.isEmpty) {
          // Inline, not a _Notice: that one is a scrollable of its own.
          return Padding(
            padding: EdgeInsets.fromLTRB(20.sp, 24.sp, 20.sp, 0),
            child: Text(
              'No games of this player here.',
              textAlign: TextAlign.center,
              style: AppTypography.textSmRegular.copyWith(
                color: context.colors.textSecondary,
              ),
            ),
          );
        }
        final index = i - lead;
        final group = groups[index];
        final intro = _paragraphs(group.section?.intro);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (headed)
              _SectionHeader(section: group.section, first: index == 0),
            if (intro.isNotEmpty) _SectionIntro(paragraphs: intro),
            if (group.games.isNotEmpty)
              Padding(
                padding: EdgeInsets.only(bottom: 4.sp),
                child: DiscoveryGameList(
                  games: [for (final g in group.games) g.game],
                  streamEnabled: false,
                  onOpen: (_, local) => onOpen(ordered, group.offset + local),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// The picked player's name over their games, and the way back to all.
class _PlayerLine extends StatelessWidget {
  const _PlayerLine({required this.name, required this.onClear});

  final String name;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(_headerInset, 0, 8.sp, 8.sp),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Games of $name',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.textSmMedium.copyWith(
                color: context.colors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          TextButton(
            onPressed: onClear,
            child: Text(
              'Show all',
              style: AppTypography.textSmMedium.copyWith(
                color: context.colors.accentText,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The header over a run of games: a round and its date, a book's part, a
/// chapter's number and title, or "Other games" for those in no section.
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.section, required this.first});

  /// Null for the games in no section.
  final CollectionSection? section;

  /// The first header sits right under the list's own top padding.
  final bool first;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final s = section;
    final isPart = s?.kind == CollectionSectionKind.part;
    final main = isPart
        ? AppTypography.textSmMedium.copyWith(
            color: colors.textPrimary,
            fontSize: 17.f,
            height: 22 / 17,
            fontWeight: FontWeight.w700,
          )
        : AppTypography.textSmMedium.copyWith(
            color: colors.textPrimary,
            fontWeight: FontWeight.w600,
          );
    final muted = main.copyWith(
      color: colors.textSecondary,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    String? lead;
    var title = 'Other games';
    String? date;
    if (s != null) {
      final named = s.title != null && s.title != s.label;
      switch (s.kind) {
        case CollectionSectionKind.part:
          lead = named ? s.label : null;
          title = named ? s.title! : s.label;
        case CollectionSectionKind.chapter:
          lead = named ? s.number ?? s.label : null;
          title = named ? s.title! : s.label;
        case CollectionSectionKind.round:
        case CollectionSectionKind.stage:
        case CollectionSectionKind.other:
          title = named ? '${s.label} · ${s.title}' : s.label;
          final day = s.startsOn;
          date = day == null ? null : DateFormat('MMM d, yyyy').format(day);
      }
      if (title.isEmpty) title = s.number ?? 'Games';
    }

    return Semantics(
      header: true,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          _headerInset,
          first ? 0 : (isPart ? 28.sp : 20.sp),
          _headerInset,
          10.sp,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Expanded(
              child: Text.rich(
                TextSpan(
                  children: [
                    if (lead != null) TextSpan(text: '$lead  ', style: muted),
                    TextSpan(text: title),
                  ],
                ),
                style: main,
              ),
            ),
            if (date != null) ...[
              SizedBox(width: 12.sp),
              Text(
                date,
                style: AppTypography.textXsMedium.copyWith(
                  color: colors.textSecondary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A chapter's introduction, read before its games.
class _SectionIntro extends StatelessWidget {
  const _SectionIntro({required this.paragraphs});

  final List<String> paragraphs;

  @override
  Widget build(BuildContext context) {
    final style = AppTypography.textSmRegular.copyWith(
      color: context.colors.textSecondary,
      height: 20 / 14,
    );
    return Padding(
      padding: EdgeInsets.fromLTRB(_headerInset, 0, _headerInset, 12.sp),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < paragraphs.length; i++) ...[
            if (i > 0) SizedBox(height: 8.sp),
            Text(paragraphs[i], style: style),
          ],
        ],
      ),
    );
  }
}

class _PlayersPage extends StatelessWidget {
  const _PlayersPage({required this.players, required this.onPick});

  final List<CollectionPlayer> players;
  final ValueChanged<CollectionPlayer> onPick;

  @override
  Widget build(BuildContext context) {
    if (players.isEmpty) {
      return const _Notice(text: 'No players in this collection yet.');
    }
    return ListView.separated(
      padding: EdgeInsets.fromLTRB(
        16.sp,
        12.sp,
        16.sp,
        24.sp + MediaQuery.viewPaddingOf(context).bottom,
      ),
      itemCount: players.length,
      separatorBuilder: (_, __) => SizedBox(height: 8.sp),
      itemBuilder: (context, i) => _CollectionPlayerRow(
        key: ValueKey<String>('collection_player_${players[i].key}'),
        player: players[i],
        onPick: onPick,
      ),
    );
  }
}

/// One of a collection's players: their profile circle (photo, flag and
/// title, as every person on these pages wears it), the name and best
/// rating, and how many of the collection's games they play. Tap shows
/// their games here; a long press lifts the row into the player focus menu
/// (their games, My Space for the player and their Games tab, share).
class _CollectionPlayerRow extends ConsumerWidget {
  const _CollectionPlayerRow({
    super.key,
    required this.player,
    required this.onPick,
  });

  final CollectionPlayer player;
  final ValueChanged<CollectionPlayer> onPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = player;
    final colors = context.colors;
    final fideId = int.tryParse(p.fideId ?? '');
    final photo = fideId == null || fideId <= 0
        ? null
        : ref.watch(playerPhotoProvider(fideId)).valueOrNull;
    final title = p.title?.trim();
    final fed = p.fed?.trim();
    final count = p.games == 1 ? '1 game' : '${p.games} games';
    void pick() => onPick(p);
    return Semantics(
      button: true,
      label: '${title ?? ''} ${p.name}, $count. Show their games'.trim(),
      excludeSemantics: true,
      onTap: pick,
      child: TappableScale(
        onTap: pick,
        child: CardContextMenu(
          onPreviewTap: pick,
          actions: (menuContext) => playerMenuActions(
            menuContext,
            ref,
            playerName: p.name,
            fideId: fideId != null && fideId > 0 ? fideId : null,
            title: title == null || title.isEmpty ? null : title,
            federation: fed == null || fed.isEmpty ? null : fed,
            rating: p.bestElo,
            gamebasePlayerId: p.playerId,
            onOpen: pick,
            openLabel: 'Show their games',
            openIcon: Icons.open_in_new_rounded,
          ),
          child: Container(
            constraints: BoxConstraints(minHeight: 56.sp),
            padding: EdgeInsets.symmetric(horizontal: 12.sp, vertical: 8.sp),
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(8.br),
            ),
            child: Row(
              children: [
                SpacePlayerAvatar(
                  size: 40.sp,
                  name: p.name,
                  photoUrl: photo,
                  title: title,
                  federation: fed,
                  ring: colors.surface,
                ),
                SizedBox(width: 14.sp),
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(text: p.name),
                        if (p.bestElo != null)
                          TextSpan(
                            text: '  ${p.bestElo}',
                            style: TextStyle(
                              color: colors.textSecondary,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                      ],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.textSmMedium.copyWith(
                      color: colors.textPrimary,
                    ),
                  ),
                ),
                SizedBox(width: 12.sp),
                Text(
                  count,
                  style: AppTypography.textSmMedium.copyWith(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w600,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.text, this.actionLabel, this.onAction});

  final String text;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(20.sp, 32.sp, 20.sp, 32.sp),
      children: [
        Text(
          text,
          textAlign: TextAlign.center,
          style: AppTypography.textSmRegular.copyWith(
            color: context.colors.textSecondary,
          ),
        ),
        if (actionLabel != null && onAction != null) ...[
          SizedBox(height: 8.sp),
          Center(
            child: TextButton(
              onPressed: onAction,
              child: Text(
                actionLabel!,
                style: AppTypography.textSmMedium.copyWith(
                  color: context.colors.accentText,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _CardsSkeleton extends StatelessWidget {
  const _CardsSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.all(16.sp),
      children: [
        for (var i = 0; i < 4; i++)
          Padding(
            padding: EdgeInsets.only(bottom: 12.sp),
            child: SkeletonWidget(
              ignoreContainers: true,
              child: Container(
                height: 84.sp,
                decoration: BoxDecoration(
                  color: context.colors.surfaceRecessed,
                  borderRadius: BorderRadius.circular(8.br),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
