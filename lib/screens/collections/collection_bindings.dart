import 'dart:async';

import 'package:chessever2/repository/supabase/group_broadcast/group_broadcast.dart';
import 'package:chessever2/repository/supabase/group_broadcast/group_tour_repository.dart';
import 'package:chessever2/repository/supabase/tour/tour.dart';
import 'package:chessever2/screens/collections/collections_data.dart';
import 'package:chessever2/screens/collections/collections_screen.dart';
import 'package:chessever2/screens/gamebase/event_view/gamebase_virtual_event.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_mode_provider.dart';
import 'package:chessever2/services/deep_link_service.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/app_snack.dart';
import 'package:chessever2/widgets/auth/auth_upgrade_sheet.dart';
import 'package:chessever2/widgets/paywall/premium_paywall_sheet.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Books bound to events and events bound to books: the two directions of
/// one binding the team makes on chessever.com, and the Premium boundary a
/// book's games sit behind.

// ------------------------------------------------------------------ premium

/// Opens the app's paywall for a locked collection and hands the outcome
/// back. The same signature as [requirePremiumGuard], which it is outside
/// tests.
typedef CollectionUnlock =
    Future<bool> Function(
      BuildContext context,
      WidgetRef ref, {
      String? featureId,
      String? returnTo,
      PremiumResume? onEntitled,
    });

final collectionUnlockProvider = Provider<CollectionUnlock>(
  (ref) => requirePremiumGuard,
);

/// Asks the viewer to sign in again (the account sheet) and says whether
/// they came back signed in. The server refused the session it had.
typedef CollectionSignIn = Future<bool> Function(BuildContext context);

final collectionSignInProvider = Provider<CollectionSignIn>(
  (ref) =>
      (context) => showAuthUpgradeSheet(
        context: context,
        title: 'Sign in again',
        message:
            'Your sign-in has expired. Sign in to open your Premium '
            'collections.',
        dismissLabel: 'Not now',
      ),
);

/// The way into a locked [collection] for a viewer the app does not know as
/// a subscriber: the paywall (a guest signs in first). Once they are
/// entitled, [onEntitled] runs: the page confirms the purchase with the
/// server (see [CollectionPremiumConfirm]), which may take a few tries.
Future<void> unlockCollection(
  BuildContext context,
  WidgetRef ref,
  Collection collection, {
  required VoidCallback onEntitled,
}) async {
  HapticFeedbackService.buttonPress();
  await ref.read(collectionUnlockProvider)(
    context,
    ref,
    featureId: collectionPaywallFeatureId(collection.kind),
    returnTo: kCollectionPaywallReturnTo,
    onEntitled: () {
      if (!context.mounted) return;
      onEntitled();
    },
  );
}

/// Where a locked collection's way in stands for this viewer.
enum CollectionUnlockPhase {
  /// The outcome and the padlock: a tap opens the paywall (or, for a
  /// subscriber, confirms with the server).
  offer,

  /// The app knows the viewer as a subscriber (or a purchase just went
  /// through) and the server still says locked: the page is asking again.
  confirming,

  /// The server kept saying locked for the whole confirm window: said so,
  /// with a retry.
  failed,

  /// The server does not accept the viewer's session (none, spent or
  /// refused), and asking again did not change that: said so, with a way
  /// to sign in again.
  signIn,
}

/// What one re-check of a collection's lock found.
enum CollectionAccessCheck {
  /// The server opened the collection.
  open,

  /// Still locked: asked again after the next pause.
  locked,

  /// Still locked because the server refused the session. Once is a token
  /// the SDK was still refreshing; [CollectionPremiumConfirm.signInRefusals]
  /// in a row is a session no wait will mend.
  signInRefused,
}

/// The pauses between the server re-checks while a subscriber's Premium is
/// confirmed: about 35 s in all. Each re-check asks the server to judge
/// anew (it skips the "not Premium" it keeps for 5 s, 30 s when its
/// fallback answered), so the window is for the purchase itself to reach
/// the server from the store, which can take that long.
const List<Duration> kCollectionConfirmBackoff = [
  Duration(seconds: 2),
  Duration(seconds: 3),
  Duration(seconds: 5),
  Duration(seconds: 8),
  Duration(seconds: 8),
  Duration(seconds: 9),
];

/// A confirm that ran its whole window without the server opening a book,
/// for this app session. Another locked book then says so at once (with
/// its retry) instead of confirming for 35 s again: the viewer's
/// subscription and the server disagree beyond a slow sync.
final collectionConfirmFailedAtProvider = StateProvider<DateTime?>(
  (ref) => null,
);

/// How long a failed confirm stands in for a new one.
const Duration kCollectionConfirmFailureMemory = Duration(minutes: 5);

/// Confirms a subscriber's Premium with the server for one collection: asks
/// again (the detail, and the games when the verdict opens it) with a
/// backoff, until the server opens the collection, refuses the session
/// [signInRefusals] times in a row, or the window runs out.
///
/// [check] is the one read per try (one that throws is no answer and is
/// asked again); [onPhase] reports the phase for the page to draw.
/// [cancel] stops a run for good (the page is gone).
class CollectionPremiumConfirm {
  CollectionPremiumConfirm({
    required this.check,
    required this.onPhase,
    this.backoff = kCollectionConfirmBackoff,
    this.signInRefusals = 2,
  });

  final Future<CollectionAccessCheck> Function() check;
  final ValueChanged<CollectionUnlockPhase> onPhase;
  final List<Duration> backoff;
  final int signInRefusals;

  Timer? _timer;
  int _run = 0;
  bool _cancelled = false;

  /// Starts (or restarts) the confirm. Resolves true when the server opened
  /// the collection, false when the window ran out or the run was replaced.
  Future<bool> start() async {
    if (_cancelled) return false;
    final run = ++_run;
    _timer?.cancel();
    _timer = null;
    onPhase(CollectionUnlockPhase.confirming);
    var refused = 0;
    for (var attempt = 0; attempt <= backoff.length; attempt++) {
      if (attempt > 0) {
        final waited = Completer<void>();
        _timer = Timer(backoff[attempt - 1], waited.complete);
        await waited.future;
        _timer = null;
      }
      if (_cancelled || run != _run) return false;
      CollectionAccessCheck answer;
      try {
        answer = await check();
      } catch (e) {
        // A read that failed outright (offline, the check out of reach) is
        // not an answer: try again.
        debugPrint('[Collections] premium confirm read failed: $e');
        answer = CollectionAccessCheck.locked;
      }
      if (_cancelled || run != _run) return false;
      switch (answer) {
        case CollectionAccessCheck.open:
          onPhase(CollectionUnlockPhase.offer);
          return true;
        case CollectionAccessCheck.signInRefused:
          if (++refused >= signInRefusals) {
            onPhase(CollectionUnlockPhase.signIn);
            return false;
          }
        case CollectionAccessCheck.locked:
          refused = 0;
      }
    }
    onPhase(
      refused > 0
          ? CollectionUnlockPhase.signIn
          : CollectionUnlockPhase.failed,
    );
    return false;
  }

  void cancel() {
    _cancelled = true;
    _timer?.cancel();
    _timer = null;
  }
}

/// Drops what the server said about [slug] for this viewer, so the page
/// reads its verdict, its games and its players again.
void refreshCollectionAccess(WidgetRef ref, String slug) {
  ref.invalidate(collectionDetailProvider(slug));
  ref.invalidate(collectionGamesProvider(slug));
  ref.invalidate(collectionPlayersProvider(slug));
}

// ------------------------------------------------------------ event -> books

/// Every identity the event page for [broadcast] is known by, for
/// `GET /api/collections/for-event`: the group, each of its tours by id and
/// by slug, or, for a database event shown through the same page, its PGN
/// Event name and Site. The server widens these through its mirror, so a
/// group minted again still finds the books bound to it, and reads a Lichess
/// broadcast URL in the Site as that broadcast, so the database twin of a
/// broadcast does too. A database event's books match on its Event name
/// alone (see [CollectionEventAnchors.site]).
CollectionEventAnchors collectionAnchorsForEvent({
  required GroupBroadcast? broadcast,
  Iterable<Tour> tours = const [],
}) {
  if (broadcast == null) return CollectionEventAnchors();
  final virtual = virtualEventKeyFromId(broadcast.id);
  if (virtual != null) {
    return CollectionEventAnchors(
      events: [virtual.eventName],
      site: virtual.site,
      slugs: [virtual.slug],
    );
  }
  final real = [
    for (final t in tours)
      if (!isVirtualGamebaseId(t.id)) t,
  ];
  return CollectionEventAnchors(
    groups: [broadcast.id],
    tours: [for (final t in real) t.id],
    slugs: [for (final t in real) t.slug],
  );
}

/// The books bound to one event, each drawn as the Books tab draws it with
/// the team's note under it, under "Book" or "Books" as they number (the
/// way a book's page heads its "Event" or "Events"). Nothing at all while
/// they load, when there are none, or when the read fails: an event without
/// books looks exactly as it did before books existed.
class CollectionBooksSection extends ConsumerWidget {
  const CollectionBooksSection({
    super.key,
    required this.anchors,
    required this.titleStyle,
    this.topGap = 0,
    this.titleGap,
  });

  final CollectionEventAnchors anchors;

  /// The heading's style, in the host page's own heading voice.
  final TextStyle titleStyle;

  /// Space above the heading, part of the section so an event with no
  /// books leaves no gap behind.
  final double topGap;

  /// Space between the heading and the first book; 10.sp by default.
  final double? titleGap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (anchors.isEmpty) return const SizedBox.shrink();
    final books =
        ref.watch(collectionBooksForEventProvider(anchors)).valueOrNull ??
        const <Collection>[];
    if (books.isEmpty) return const SizedBox.shrink();
    return Column(
      key: const ValueKey<String>('collection_books_section'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(height: topGap),
        Semantics(
          header: true,
          child: Text(
            books.length == 1 ? 'Book' : 'Books',
            style: titleStyle,
          ),
        ),
        SizedBox(height: titleGap ?? 10.sp),
        for (var i = 0; i < books.length; i++) ...[
          if (i > 0) SizedBox(height: 8.sp),
          CollectionCard(
            key: ValueKey<String>('event_book_${books[i].id}'),
            collection: books[i],
            note: books[i].note,
          ),
        ],
      ],
    );
  }
}

// ------------------------------------------------------------ book -> event

/// Opens one of a book's events wherever it lives, the way every other
/// event link in the app opens it: a broadcast on its tournament page (on
/// the bound tour when the server named one), a database event on the same
/// page backed by the game database, an annotated event on its collection
/// page. Says so when the event cannot be opened.
Future<void> openCollectionEvent(
  BuildContext context,
  WidgetRef ref,
  CollectionEventRef event,
) async {
  final open = event.open;
  if (open == null) return;
  HapticFeedbackService.cardTap();

  void pushTournament(GroupBroadcast broadcast) {
    ref.read(selectedBroadcastModelProvider.notifier).state = broadcast;
    ref.read(selectedTourModeProvider.notifier).state =
        TournamentDetailScreenMode.games;
    unawaited(Navigator.of(context).pushNamed('/tournament_detail_screen'));
  }

  var opened = false;
  switch (open.kind) {
    case CollectionEventOpenKind.broadcast:
      opened = await DeepLinkService.instance.openEventForShortcut(
        eventId: open.groupBroadcastId,
        tourId: open.tourId,
      );
    case CollectionEventOpenKind.broadcastSlug:
      try {
        final broadcast = await ref
            .read(groupBroadcastRepositoryProvider)
            .getGroupBroadcastBySlug(open.slug!);
        if (broadcast != null && context.mounted) {
          pushTournament(broadcast);
          opened = true;
        }
      } catch (e) {
        debugPrint('[Collections] event ${open.slug} unavailable: $e');
      }
    case CollectionEventOpenKind.database:
      if (context.mounted) {
        pushTournament(
          virtualGroupBroadcastForEvent(open.eventName!, site: open.site),
        );
        opened = true;
      }
    case CollectionEventOpenKind.collection:
      if (context.mounted) {
        unawaited(
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => CollectionScreen(
                collection: Collection(
                  // The slug reads the detail; the id arrives with it.
                  id: '',
                  slug: open.slug!,
                  kind: CollectionKind.event,
                  title: event.title,
                  location: event.location,
                  dateStart: event.dateStart,
                  dateEnd: event.dateEnd,
                  coverUrl: event.imageUrl,
                ),
              ),
            ),
          ),
        );
        opened = true;
      }
  }
  if (!opened && context.mounted) {
    showAppSnack(
      context,
      "Couldn't open this event",
      tone: AppSnackTone.danger,
    );
  }
}
