import 'dart:async';
import 'dart:math' as math;

import 'package:chessever2/providers/board_settings_provider_new.dart';
import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter/widgets.dart';
import 'package:heroine/heroine.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

// A mini board card's board flies into the board screen's main board.
//
// * [BoardHeroCard] owns one card's [BoardHeroSlot]; [BoardHeroSource] is the
//   card's board, which becomes a [Heroine] only once a board is opened from
//   it, so the cards that never fly carry nothing.
// * A tap issues a [BoardHeroTicket] (the flight's tag, new on every tap, so
//   the same game on several cards never shares a tag) and runs the card's
//   open callback through [openWithBoardHero], which carries the ticket down
//   that tap's own call chain, across awaits, in a zone value.
// * The open helper takes it with [BoardHeroTicket.claim] and hands it to the
//   board route in a [BoardHeroScope]; the board of the game opened, on the
//   page it opened on, is a [BoardHeroDestination].
//
// The flight goes one way. It runs only when the board screen opens on the
// position and orientation the card shows (a finished game opens on its
// first move, a flipped session opens black at the bottom: no flight then),
// a cheap static board flies instead of chessground, and the way back is the
// route's own transition.

final Object _zoneKey = Object();

/// The spring a board flies on: smooth, no bounce, so it settles exactly on
/// the board screen's board. The looser tolerance ends the spring once it is
/// within half a pixel instead of chasing thousandths for another half
/// second, so the real board takes over as the route transition ends.
class _BoardFlightMotion extends CupertinoMotion {
  const _BoardFlightMotion()
    : super(duration: const Duration(milliseconds: 340), snapToEnd: true);

  @override
  Tolerance get tolerance => const Tolerance(distance: 0.5, velocity: 10);
}

const Motion _boardFlightMotion = _BoardFlightMotion();

bool _pushOnly(HeroineTransitionDetails details) =>
    details.direction == HeroFlightDirection.push;

/// The board-only part of [fen] (piece placement), or null when it does not
/// parse. Positions are compared on this alone.
String? boardHeroPlacement(String? fen) {
  final raw = fen?.trim() ?? '';
  if (raw.isEmpty) return null;
  try {
    return Setup.parseFen(raw).board.fen;
  } catch (_) {
    return null;
  }
}

/// One tap on one card: the tag its board flies under, and what that board
/// showed when it was tapped.
final class BoardHeroTicket {
  BoardHeroTicket._({
    required this.gameId,
    required this.fen,
    required this.placement,
    required this.orientation,
    required this.lastMove,
    required this._slot,
  });

  final String gameId;
  final String fen;

  /// [fen]'s piece placement.
  final String placement;
  final Side orientation;
  final Move? lastMove;

  final BoardHeroSlot _slot;
  bool _claimed = false;
  final Completer<void> _settled = Completer<void>();

  /// The ticket of the card tap that is opening [gameId] on a board with
  /// [boardOrientation] at the bottom, if this call runs on that tap's chain,
  /// nothing claimed it yet and the card shows that side at the bottom too.
  /// Claiming arms the card's board, so a ticket nobody opens a board with
  /// (or one for a board turned the other way) never touches its card.
  static BoardHeroTicket? claim({
    required String gameId,
    required Side boardOrientation,
  }) {
    final ticket = Zone.current[_zoneKey];
    if (ticket is! BoardHeroTicket ||
        ticket._claimed ||
        ticket.gameId != gameId ||
        ticket.orientation != boardOrientation) {
      return null;
    }
    ticket._claimed = true;
    ticket._slot._arm(ticket);
    return ticket;
  }

  /// Whether a board showing [placement] with [orientation] at the bottom
  /// is the board this ticket's card showed.
  bool landsOn({required String placement, required Side orientation}) =>
      this.placement == placement && this.orientation == orientation;

  /// Completes once the board route's push transition has ended, or the
  /// open was abandoned ([settle]). Work that would rebuild the page the
  /// board lands on waits for it.
  Future<void> get settled => _settled.future;

  /// Completes [settled] when [route]'s transition stops.
  void followTransition(Route<dynamic> route) {
    final animation = route is TransitionRoute ? route.animation : null;
    if (animation == null || !animation.isAnimating) {
      settle();
      return;
    }
    void onStatus(AnimationStatus status) {
      if (status.isAnimating) return;
      animation.removeStatusListener(onStatus);
      settle();
    }

    animation.addStatusListener(onStatus);
  }

  void settle() {
    if (!_settled.isCompleted) _settled.complete();
  }

  @override
  String toString() => 'BoardHeroTicket($gameId)';
}

/// Runs [open] (a card's tap callback) with [ticket] on its call chain.
void openWithBoardHero(BoardHeroTicket? ticket, VoidCallback open) {
  if (ticket == null) {
    open();
    return;
  }
  runZoned(open, zoneValues: {_zoneKey: ticket});
}

/// One card's link to its board's [Heroine].
class BoardHeroSlot extends ChangeNotifier {
  BoardHeroTicket? _armed;
  bool _disposed = false;

  /// The ticket this card's board flies under, once a board was opened from
  /// it.
  BoardHeroTicket? get armed => _armed;

  /// A ticket for a tap on this card, whose board shows [fen] with
  /// [orientation] at the bottom. Null when [fen] does not parse: the card
  /// then shows a placeholder position and nothing flies.
  BoardHeroTicket? issue({
    required String gameId,
    required String? fen,
    required Side orientation,
    required Move? lastMove,
  }) {
    final placement = boardHeroPlacement(fen);
    if (placement == null) return null;
    return BoardHeroTicket._(
      gameId: gameId,
      fen: fen!.trim(),
      placement: placement,
      orientation: orientation,
      lastMove: lastMove,
      slot: this,
    );
  }

  void _arm(BoardHeroTicket ticket) {
    if (_disposed || identical(_armed, ticket)) return;
    _armed = ticket;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// Owns a card's [BoardHeroSlot] for as long as the card is mounted.
class BoardHeroCard extends StatefulWidget {
  const BoardHeroCard({super.key, required this.builder});

  final Widget Function(BuildContext context, BoardHeroSlot slot) builder;

  @override
  State<BoardHeroCard> createState() => _BoardHeroCardState();
}

class _BoardHeroCardState extends State<BoardHeroCard> {
  final BoardHeroSlot _slot = BoardHeroSlot();

  @override
  void dispose() {
    _slot.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _slot);
}

/// A card's board. It is a [Heroine] only once a board is opened from the
/// card, and a board is only opened with a ticket when it may land it: a
/// position that is still being played, shown the same way up. Cards that
/// never fly carry no heroine, no global key, and nothing for a route
/// change to visit. Arming rebuilds that live card's static board once, in
/// the frame the board route is built; it redraws exactly as it was, and
/// the flight hides it from the next frame.
class BoardHeroSource extends StatelessWidget {
  const BoardHeroSource({super.key, required this.slot, required this.child});

  final BoardHeroSlot slot;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: slot,
      child: child,
      builder: (context, child) {
        final ticket = slot.armed;
        if (ticket == null) return child!;
        return Heroine(
          tag: ticket,
          motion: _boardFlightMotion,
          flightShuttleBuilder: BoardHeroShuttleBuilder(ticket),
          shouldTransition: _pushOnly,
          child: child!,
        );
      },
    );
  }
}

/// Hands a board route its ticket, and the page index of the game it opens
/// on.
class BoardHeroScope extends InheritedWidget {
  const BoardHeroScope({
    super.key,
    required this.ticket,
    required this.pageIndex,
    required super.child,
  });

  final BoardHeroTicket ticket;
  final int pageIndex;

  @override
  bool updateShouldNotify(BoardHeroScope oldWidget) =>
      !identical(ticket, oldWidget.ticket) || pageIndex != oldWidget.pageIndex;
}

/// The board screen's board for page [pageIndex]. It lands the flight only
/// when it is the opened game's page and, on its first build, shows the
/// card's position the card's way up. That decision is kept: the board under
/// it is never remounted by a later change.
class BoardHeroDestination extends StatefulWidget {
  const BoardHeroDestination({
    super.key,
    required this.gameId,
    required this.pageIndex,
    required this.placement,
    required this.flipped,
    required this.child,
  });

  final String gameId;
  final int pageIndex;

  /// The displayed position's piece placement. Read once, on the first build
  /// of a board route that carries a ticket.
  final ValueGetter<String> placement;
  final bool flipped;
  final Widget child;

  @override
  State<BoardHeroDestination> createState() => _BoardHeroDestinationState();
}

class _BoardHeroDestinationState extends State<BoardHeroDestination> {
  BoardHeroTicket? _ticket;
  bool _decided = false;

  bool _shouldTransition(HeroineTransitionDetails details) =>
      details.direction == HeroFlightDirection.push &&
      _ticket?.gameId == widget.gameId;

  BoardHeroTicket? _landing() {
    // No dependency: the scope is fixed for the route's life.
    final scope = context.getInheritedWidgetOfExactType<BoardHeroScope>();
    if (scope == null || scope.pageIndex != widget.pageIndex) return null;
    final ticket = scope.ticket;
    if (ticket.gameId != widget.gameId) return null;
    final lands = ticket.landsOn(
      placement: widget.placement(),
      orientation: widget.flipped ? Side.black : Side.white,
    );
    return lands ? ticket : null;
  }

  @override
  Widget build(BuildContext context) {
    if (!_decided) {
      _decided = true;
      _ticket = _landing();
    }
    final ticket = _ticket;
    if (ticket == null) return widget.child;
    return Heroine(
      tag: ticket,
      motion: _boardFlightMotion,
      flightShuttleBuilder: BoardHeroShuttleBuilder(ticket),
      shouldTransition: _shouldTransition,
      child: widget.child,
    );
  }
}

/// Flies a static board of the ticket's position, never either end's own
/// subtree: the card's board would replay its marks, and the board screen's
/// would build chessground mid-flight. It is laid out once at the larger
/// end's size and scaled, so each frame of the flight only moves a layer.
class BoardHeroShuttleBuilder extends HeroineShuttleBuilder {
  const BoardHeroShuttleBuilder(this.ticket);

  final BoardHeroTicket ticket;

  @override
  List<Object?> get props => [ticket];

  static double _sideOf(BuildContext context) {
    final box = context.findRenderObject();
    return box is RenderBox && box.hasSize ? box.size.shortestSide : 0;
  }

  @override
  Widget call(
    BuildContext flightContext,
    Animation<double> animation,
    HeroFlightDirection flightDirection,
    BuildContext fromHeroContext,
    BuildContext toHeroContext,
  ) {
    final side = math.max(
      1.0,
      math.max(_sideOf(fromHeroContext), _sideOf(toHeroContext)),
    );
    return BoardHeroShuttle(ticket: ticket, side: side);
  }
}

/// The board in flight: the ticket's position on the reader's board theme.
class BoardHeroShuttle extends ConsumerWidget {
  const BoardHeroShuttle({super.key, required this.ticket, required this.side});

  final BoardHeroTicket ticket;

  /// The size it is laid out at before it is scaled to the flight's rect.
  final double side;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings =
        ref.watch(boardSettingsProviderNew).valueOrNull ??
        const BoardSettingsNew();
    return FittedBox(
      child: SizedBox.square(
        dimension: side,
        child: RepaintBoundary(
          child: StaticChessboard(
            size: side,
            orientation: ticket.orientation,
            fen: ticket.fen,
            lastMove: ticket.lastMove,
            settings: StaticChessboardSettings(
              colorScheme: settings.colorScheme,
              pieceAssets: settings.pieceAssets,
              enableCoordinates: settings.showCoordinates,
              animationDuration: Duration.zero,
            ),
          ),
        ),
      ),
    );
  }
}
