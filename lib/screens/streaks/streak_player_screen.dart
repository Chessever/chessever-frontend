import 'package:chessever2/screens/library/widgets/library_context_menu.dart';
import 'package:chessever2/screens/my_space/actions/space_menu_action.dart';
import 'package:chessever2/screens/my_space/models/space_game_card.dart';
import 'package:chessever2/screens/my_space/models/space_shortcut.dart';
import 'package:chessever2/screens/my_space/providers/space_shortcuts_provider.dart';
import 'package:chessever2/screens/player_profile/player_profile_screen.dart';
import 'package:chessever2/screens/streaks/models/streak_models.dart';
import 'package:chessever2/screens/streaks/providers/streak_providers.dart';
import 'package:chessever2/screens/streaks/widgets/player_class_scoreboard.dart';
import 'package:chessever2/screens/streaks/widgets/player_embers.dart';
import 'package:chessever2/screens/streaks/widgets/player_recent_games.dart';
import 'package:chessever2/screens/streaks/widgets/player_run_facts.dart';
import 'package:chessever2/screens/streaks/widgets/player_run_strip.dart';
import 'package:chessever2/screens/streaks/widgets/player_streak_avatar.dart';
import 'package:chessever2/screens/streaks/widgets/player_streak_format.dart';
import 'package:chessever2/screens/streaks/widgets/player_streak_header.dart';
import 'package:chessever2/screens/streaks/widgets/player_streak_hero.dart';
import 'package:chessever2/screens/streaks/widgets/streak_share_card.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart'
    show GameStatus;
import 'package:chessever2/services/deep_link_service.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/app_button.dart';
import 'package:chessever2/widgets/app_snack.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Opens one game on the board. A provider so tests can stand in for the
/// router-bound deep-link service.
final streakOpenGameProvider = Provider<Future<bool> Function(String gameId)>(
  (ref) => DeepLinkService.instance.openGameForShortcut,
);

/// Content width cap: on a tablet the card stays a phone-width column.
const double _kMaxContentWidth = 560;

/// One player's streak card: Classical / Rapid / Blitz scoreboard, the run,
/// the strongest win, and a shareable card.
class StreakPlayerScreen extends ConsumerStatefulWidget {
  const StreakPlayerScreen({
    super.key,
    required this.fideId,
    this.initialClass,
    this.fallbackName,
  });

  final int fideId;
  final StreakTimeClass? initialClass;

  /// Shown while loading and when the player has no streak data.
  final String? fallbackName;

  @override
  ConsumerState<StreakPlayerScreen> createState() => _StreakPlayerScreenState();
}

class _StreakPlayerScreenState extends ConsumerState<StreakPlayerScreen> {
  /// The class the user picked on the scoreboard; until then the page opens
  /// on [StreakPlayerScreen.initialClass] or the hottest run (`pickClass`).
  StreakTimeClass? _picked;
  bool _sharing = false;
  final GlobalKey _shareButtonKey = GlobalKey();

  StreakTimeClass _classFor(PlayerStreaks p) =>
      _picked ?? p.pickClass(widget.initialClass);

  SpaceShortcut? _draft(PlayerStreaks? p, StreakTimeClass? tc) {
    // `playerName` is the raw ledger form ("Carlsen, Magnus"), the same as the
    // wall stores: the tile's surname and initials fall back to it once the
    // player drops off the wall.
    final name = p?.name ?? widget.fallbackName?.trim();
    if (name == null || name.isEmpty) return null;
    final display = streakDisplayName(name);
    final cls = tc ?? widget.initialClass ?? StreakTimeClass.standard;
    return SpaceShortcut.draft(
      kind: SpaceShortcutKind.streak,
      targetId: '${widget.fideId}',
      title: display,
      subtitle: '${cls.label} streak',
      params: {
        'timeClass': cls.wire,
        'playerName': name,
        if (p?.title != null) 'title': p!.title,
        if (p?.fed != null) 'fed': p!.fed,
      },
    );
  }

  /// Runs the menu action itself rather than `toggleSpaceShortcut`, which
  /// reads `ref` again after the upsert: popping the card mid-save would throw
  /// there. The action takes the notifier and the messenger before its first
  /// await, so it finishes safely after this screen is gone.
  Future<void> _toggleSpace(SpaceShortcut draft) async {
    if (!mounted) return;
    await spaceMenuAction(
      context: context,
      ref: ref,
      draft: draft,
    ).onSelected();
  }

  void _openProfile(PlayerStreaks? p) {
    final name = p?.name ?? widget.fallbackName?.trim() ?? '';
    HapticFeedbackService.navigation();
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PlayerProfileScreen(
          fideId: widget.fideId,
          playerName: name,
          title: p?.title,
          federation: p?.fed,
          // The profile's rating is classical (it is shown, shared and saved
          // to favourites as such), whichever class this card is on.
          rating: p?.ratings[StreakTimeClass.standard],
        ),
      ),
    );
  }

  Future<void> _openGame(StreakGame g) async {
    HapticFeedbackService.cardTap();
    final messenger = ScaffoldMessenger.maybeOf(context);
    var opened = false;
    try {
      opened = await ref.read(streakOpenGameProvider)(g.gameId);
    } catch (e) {
      debugPrint('[Streaks] open game ${g.gameId} failed: $e');
    }
    if (!opened && messenger != null && messenger.mounted) {
      showAppSnackOn(
        messenger,
        "Couldn't open this game",
        tone: AppSnackTone.danger,
      );
    }
  }

  /// A recent game's focus menu: open it, or pin it into My Space. The game
  /// id is the one [streakOpenGameProvider] opens, which is exactly what the
  /// My Space opener does with a game shortcut.
  List<LibraryMenuAction> _gameActions(
    BuildContext rowContext,
    PlayerStreaks p,
    StreakTimeClass tc,
    StreakGame g,
  ) {
    final draft = streakGameSpaceDraft(g, player: p, timeClass: tc);
    return [
      LibraryMenuAction(
        icon: Icons.open_in_new_rounded,
        label: 'Open game',
        onSelected: () {
          if (mounted) return _openGame(g);
        },
      ),
      if (draft != null)
        spaceMenuAction(context: rowContext, ref: ref, draft: draft),
    ];
  }

  Future<void> _share(PlayerStreaks p, StreakTimeClass tc) async {
    if (_sharing) return;
    HapticFeedbackService.buttonPress();
    setState(() => _sharing = true);
    Rect? origin;
    final box = _shareButtonKey.currentContext?.findRenderObject();
    if (box is RenderBox && box.hasSize) {
      origin = box.localToGlobal(Offset.zero) & box.size;
    }
    try {
      await shareStreakCard(context, player: p, timeClass: tc, origin: origin);
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(playerStreaksProvider(widget.fideId));
    final player = async.valueOrNull;
    final tc = player == null ? null : _classFor(player);
    final draft = _draft(player, tc);
    final inSpace =
        draft != null && ref.watch(spaceShortcutExistsProvider(draft.key));
    final hasName =
        player != null || (widget.fallbackName?.trim().isNotEmpty ?? false);
    final canShare =
        player != null && tc != null && StreakShareCard.canShare(player, tc);

    final Widget body;
    if (player != null && tc != null) {
      body = _PlayerCard(
        player: player,
        timeClass: tc,
        onSelectClass: (next) {
          if (next == tc) return;
          HapticFeedbackService.selection();
          setState(() => _picked = next);
        },
        onOpenGame: _openGame,
        gameActions: (rowContext, g) =>
            _gameActions(rowContext, player, tc, g),
        onOpenProfile: () => _openProfile(player),
      );
    } else if (async.isLoading) {
      body = _PlayerCardSkeleton(
        fideId: widget.fideId,
        name: widget.fallbackName,
      );
    } else {
      body = _PlayerCardMissing(
        fideId: widget.fideId,
        name: widget.fallbackName,
        failed: async.hasError,
        onRetry: () => ref.invalidate(playerStreaksProvider(widget.fideId)),
      );
    }

    return Scaffold(
      backgroundColor: context.colors.background,
      body: Column(
        children: [
          PlayerStreakTopBar(
            inSpace: inSpace,
            onToggleSpace: draft == null ? null : () => _toggleSpace(draft),
            onOpenProfile: hasName ? () => _openProfile(player) : null,
          ),
          Expanded(
            // Without the pinned bar the page itself must clear the home
            // indicator. Always the same SafeArea, only its bottom flag
            // flips: switching to a class with nothing to share must not
            // remount the card (scroll position, run strip, pixel art).
            child: SafeArea(top: false, bottom: !canShare, child: body),
          ),
          if (canShare)
            _ShareBar(
              buttonKey: _shareButtonKey,
              busy: _sharing,
              onTap: () => _share(player, tc),
            ),
        ],
      ),
    );
  }
}

/// A centred column no wider than a phone, with the page gutter.
class _Column extends StatelessWidget {
  const _Column({required this.child, this.gutter = true});

  final Widget child;
  final bool gutter;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: _kMaxContentWidth),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: gutter ? 16.w : 0),
          child: child,
        ),
      ),
    );
  }
}

class _PlayerCard extends StatelessWidget {
  const _PlayerCard({
    required this.player,
    required this.timeClass,
    required this.onSelectClass,
    required this.onOpenGame,
    required this.onOpenProfile,
    this.gameActions,
  });

  final PlayerStreaks player;
  final StreakTimeClass timeClass;
  final ValueChanged<StreakTimeClass> onSelectClass;
  final ValueChanged<StreakGame> onOpenGame;
  final VoidCallback onOpenProfile;
  final List<LibraryMenuAction> Function(BuildContext rowContext, StreakGame g)?
  gameActions;

  @override
  Widget build(BuildContext context) {
    final run = player.run(timeClass);
    final label = timeClass.label.toLowerCase();

    return SingleChildScrollView(
      key: const ValueKey('streak-player-scroll'),
      padding: EdgeInsets.only(bottom: 24.w),
      child: Stack(
        children: [
          // The embers sit behind the hero and scroll with it; the design
          // draws them in the top 470pt of a 390pt frame.
          Positioned(
            left: 0,
            right: 0,
            // The frame's origin is the top of the screen; the column starts
            // under the 98pt bar, so the frame is lifted by that much.
            top: -98.w,
            height: 470.w,
            child: IgnorePointer(
              child: RepaintBoundary(
                child: CustomPaint(
                  painter: StreakEmberPainter(
                    embers: kPlayerHeroEmbers,
                    frame: const Size(390, 470),
                  ),
                ),
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(height: 6.w),
              _Column(
                child: PlayerStreakIdentity(
                  player: player,
                  timeClass: timeClass,
                  onOpenProfile: onOpenProfile,
                ),
              ),
              SizedBox(height: 18.w),
              _Column(
                child: PlayerStreakHero(run: run, timeClass: timeClass),
              ),
              SizedBox(height: 26.w),
              _Column(
                child: PlayerClassScoreboard(
                  player: player,
                  selected: timeClass,
                  onSelect: onSelectClass,
                ),
              ),
              if (run != null && run.currentRunGames.isNotEmpty) ...[
                SizedBox(height: 28.w),
                _Column(
                  child: PlayerRunStrip(
                    key: ValueKey('streak-run-${timeClass.wire}'),
                    run: run,
                    onOpenGame: onOpenGame,
                  ),
                ),
              ],
              if (run != null) ...[
                SizedBox(height: 20.w),
                _Column(child: PlayerRunFacts(run: run)),
              ],
              if (run != null && run.games.isNotEmpty) ...[
                SizedBox(height: 28.w),
                _Column(
                  gutter: false,
                  child: PlayerRecentGames(
                    run: run,
                    onOpenGame: onOpenGame,
                    gameActions: gameActions,
                  ),
                ),
              ],
              if (run == null) ...[
                SizedBox(height: 28.w),
                _Column(
                  child: Text(
                    'No decisive $label games in ChessEver broadcasts yet.',
                    textAlign: TextAlign.center,
                    style: streakText(
                      context,
                      size: 13,
                      line: 18,
                      color: context.colors.textSecondary,
                    ),
                  ),
                ),
              ],
              SizedBox(height: 20.w),
              _Column(
                child: Text(
                  'A streak is every decisive win over the board since the '
                  "last loss in the same time control. Draws don't break it; "
                  "online games don't count.",
                  style: streakText(
                    context,
                    size: 12,
                    line: 17,
                    color: context.colors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The one action: a cyan fill, radius 4, pinned above the home indicator.
class _ShareBar extends StatelessWidget {
  const _ShareBar({
    required this.buttonKey,
    required this.busy,
    required this.onTap,
  });

  final GlobalKey buttonKey;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return ColoredBox(
      color: colors.background,
      child: SafeArea(
        top: false,
        minimum: EdgeInsets.only(bottom: 12.w),
        child: _Column(
          child: Padding(
            padding: EdgeInsets.only(top: 10.w),
            child: Semantics(
              button: true,
              enabled: !busy,
              label: busy ? 'Preparing streak card' : 'Share streak card',
              excludeSemantics: true,
              child: TappableScale(
                key: const ValueKey('streak-player-share'),
                scaleDown: 0.97,
                onTap: busy ? () {} : onTap,
                child: Container(
                  key: buttonKey,
                  height: 50.w,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: busy ? colors.brandMuted : colors.brand,
                    borderRadius: BorderRadius.circular(4.w),
                  ),
                  child: Text(
                    busy ? 'Preparing card…' : 'Share streak card',
                    style: streakText(
                      context,
                      size: 15,
                      line: 20,
                      weight: FontWeight.w700,
                      color: const Color(0xFF0C0C0E),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Loading: the real layout's silhouette in still bones (no shimmer, so the
/// wait reads calm), with the name already in place when the caller knows it.
class _PlayerCardSkeleton extends StatelessWidget {
  const _PlayerCardSkeleton({required this.fideId, this.name});

  final int fideId;
  final String? name;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    Widget block(double w, double h, {Color? color}) => Container(
      width: w,
      height: h,
      decoration: BoxDecoration(
        color: color ?? colors.skeleton,
        borderRadius: BorderRadius.circular(4.w),
      ),
    );
    final known = name?.trim().isNotEmpty ?? false;

    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      child: Semantics(
        label: 'Loading streaks',
        child: Column(
          children: [
            SizedBox(height: 6.w),
            if (known)
              PlayerStreakAvatar(fideId: fideId, name: name!, size: 72.w)
            else
              Container(
                width: 72.w,
                height: 72.w,
                decoration: BoxDecoration(
                  color: colors.skeleton,
                  shape: BoxShape.circle,
                ),
              ),
            SizedBox(height: 12.w),
            if (known)
              _Column(
                child: Text(
                  streakDisplayName(name!),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: streakText(
                    context,
                    size: 22,
                    line: 28,
                    weight: FontWeight.w700,
                  ),
                ),
              )
            else
              block(160.w, 22.w),
            SizedBox(height: 8.w),
            block(140.w, 12.w),
            SizedBox(height: 30.w),
            block(120.w, 84.w),
            SizedBox(height: 14.w),
            block(90.w, 16.w),
            SizedBox(height: 30.w),
            _Column(
              child: Row(
                children: [
                  for (var i = 0; i < 3; i++) ...[
                    if (i > 0) SizedBox(width: 8.w),
                    Expanded(
                      child: block(
                        double.infinity,
                        96.w,
                        color: colors.surface,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            SizedBox(height: 28.w),
            _Column(
              child: Row(
                children: [
                  for (var i = 0; i < 7; i++) ...[
                    if (i > 0) SizedBox(width: 4.w),
                    Expanded(
                      child: AspectRatio(
                        aspectRatio: 1,
                        child: block(double.infinity, double.infinity),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Not on any wall (or the read failed): who we were asked about, and why
/// there is nothing to draw.
class _PlayerCardMissing extends StatelessWidget {
  const _PlayerCardMissing({
    required this.fideId,
    required this.failed,
    required this.onRetry,
    this.name,
  });

  final int fideId;
  final String? name;
  final bool failed;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final known = name?.trim().isNotEmpty ?? false;
    final colors = context.colors;
    return SingleChildScrollView(
      child: _Column(
        child: Column(
          children: [
            SizedBox(height: 6.w),
            if (known) ...[
              PlayerStreakAvatar(fideId: fideId, name: name!, size: 72.w),
              SizedBox(height: 12.w),
              Text(
                streakDisplayName(name!),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: streakText(
                  context,
                  size: 22,
                  line: 28,
                  weight: FontWeight.w700,
                ),
              ),
              SizedBox(height: 18.w),
            ] else
              SizedBox(height: 40.w),
            Text(
              failed ? "Couldn't load streaks" : 'No streak data yet',
              key: const ValueKey('streak-player-empty'),
              textAlign: TextAlign.center,
              style: streakText(
                context,
                size: 16,
                line: 20,
                weight: FontWeight.w700,
              ),
            ),
            SizedBox(height: 6.w),
            Text(
              failed
                  ? 'Check your connection and try again.'
                  : 'Streaks count decisive wins over the board from '
                        'ChessEver broadcasts. This player has none on record '
                        'yet.',
              textAlign: TextAlign.center,
              style: streakText(
                context,
                size: 13,
                line: 18,
                color: colors.textPrimaryMuted,
              ),
            ),
            if (failed) ...[
              SizedBox(height: 16.w),
              Semantics(
                button: true,
                label: 'Try again',
                excludeSemantics: true,
                child: TappableScale(
                  scaleDown: 0.97,
                  onTap: onRetry,
                  child: SizedBox(
                    height: 44.w,
                    child: Center(
                      child: Text(
                        'Try again',
                        style: streakText(
                          context,
                          size: 15,
                          line: 20,
                          weight: FontWeight.w700,
                          color: context.colors.accentText,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The My Space shortcut for one game on a streak card. The target is the
/// game id the card itself opens; null when the ledger row has none.
///
/// Carries the game card snapshot ([kSpaceGameCardParam]) built from what the
/// streak row already knows, so the My Space tile draws titles, federations,
/// ratings and the result without a lookup, and the player's FIDE id gives the
/// tile's own enrichment something to resolve.
SpaceShortcut? streakGameSpaceDraft(
  StreakGame g, {
  required PlayerStreaks player,
  required StreakTimeClass timeClass,
}) {
  final id = g.gameId.trim();
  if (id.isEmpty) return null;
  final me = player.name.trim();
  final opponent = g.opponentName?.trim() ?? '';
  final playedBlack = g.color == 'black';
  final mine = <String, Object?>{
    'name': me,
    if (player.title?.trim().isNotEmpty == true) 'title': player.title!.trim(),
    if (player.fed?.trim().isNotEmpty == true) 'fed': player.fed!.trim(),
    if ((player.ratings[timeClass] ?? 0) > 0)
      'rating': player.ratings[timeClass],
    if (player.fideId > 0) 'fideId': player.fideId,
  };
  final theirs = <String, Object?>{
    'name': opponent,
    if (g.opponentTitle?.trim().isNotEmpty == true)
      'title': g.opponentTitle!.trim(),
    if (g.opponentFed?.trim().isNotEmpty == true) 'fed': g.opponentFed!.trim(),
    if ((g.opponentRating ?? 0) > 0) 'rating': g.opponentRating,
  };
  final white = playedBlack ? opponent : me;
  final black = playedBlack ? me : opponent;
  final event = [
    if (g.tourName?.trim().isNotEmpty == true) g.tourName!.trim(),
    if (g.roundName?.trim().isNotEmpty == true) g.roundName!.trim(),
  ].join(' · ');
  return SpaceShortcut.draft(
    kind: SpaceShortcutKind.game,
    targetId: id,
    title: '${_surname(white)} – ${_surname(black)}',
    subtitle: event.isEmpty ? null : event,
    params: {
      if (g.tourId?.trim().isNotEmpty == true) 'tourId': g.tourId!.trim(),
      if (g.roundId?.trim().isNotEmpty == true) 'roundId': g.roundId!.trim(),
      if (white.isNotEmpty) 'white': white,
      if (black.isNotEmpty) 'black': black,
      kSpaceGameCardParam: <String, Object?>{
        'v': kSpaceGameCardVersion,
        // Unknown on purpose: the ledger holds no position, and a decided
        // status would stop the tile looking the game up for its board. The
        // lookup stores the full snapshot, result included, once it lands.
        'status': GameStatus.unknown.name,
        'white': playedBlack ? theirs : mine,
        'black': playedBlack ? mine : theirs,
      },
    },
  );
}

/// "Carlsen, Magnus" and "Magnus Carlsen" both read "Carlsen".
String _surname(String name) {
  final trimmed = name.trim();
  if (trimmed.isEmpty) return '?';
  final comma = trimmed.indexOf(',');
  if (comma > 0) return trimmed.substring(0, comma).trim();
  final tokens = trimmed.split(RegExp(r'\s+'));
  return tokens.length == 1 ? tokens.first : tokens.last;
}
