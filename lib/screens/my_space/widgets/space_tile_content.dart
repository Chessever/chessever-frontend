import 'dart:async';
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:chessever2/screens/chessboard/widgets/chess_board_from_fen_new.dart';
import 'package:chessever2/screens/chessboard/widgets/player_first_row_detail_widget.dart'
    show PlayerView;
import 'package:chessever2/screens/favorites/tabs/favorites_players_tab.dart';
import 'package:chessever2/screens/group_event/providers/live_group_broadcast_id_provider.dart';
import 'package:chessever2/screens/gamebase/event_view/gamebase_virtual_event_id.dart';
import 'package:chessever2/screens/my_space/actions/space_share.dart'
    show isSpaceCalendarEvent;
import 'package:chessever2/screens/my_space/models/space_shortcut.dart';
import 'package:chessever2/screens/my_space/navigation/space_shortcut_navigator.dart';
import 'package:chessever2/screens/my_space/providers/space_game_card_provider.dart';
import 'package:chessever2/screens/my_space/widgets/pixel_flame.dart';
import 'package:chessever2/screens/my_space/widgets/space_game_rows.dart';
import 'package:chessever2/screens/my_space/widgets/space_glyphs.dart';
import 'package:chessever2/screens/my_space/widgets/space_metrics.dart';
import 'package:chessever2/screens/streaks/models/streak_models.dart';
import 'package:chessever2/screens/streaks/providers/streak_providers.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart'
    show GameStatus;
import 'package:chessever2/screens/tour_detail/games_tour/providers/live_rounds_id_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/live_tour_id_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/game_card_wrapper/live_game_card_provider.dart'
    show watchLiveGamePosition;
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/event_card/event_image_provider.dart';
import 'package:chessever2/widgets/event_card/event_next_round_provider.dart';
import 'package:chessever2/widgets/federation_flag.dart';
import 'package:chessever2/widgets/player_initials_avatar.dart';
import 'package:chessever2/widgets/space_shortcut_drafts.dart';
import 'package:chessever2/widgets/time_control_glyph.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:motor/motor.dart';

/// The face of one My Space tile. Pure presentation: gestures, lift and the
/// swipe-to-remove physics live in `SpaceTile`, which wraps this.
///
/// Every tile is exactly [SpaceMetrics.railHeight] tall and
/// [SpaceShortcutKind.tileWidth] wide, so a rail never reflows when a live
/// status line resolves.
class SpaceTileContent extends StatelessWidget {
  const SpaceTileContent({
    super.key,
    required this.shortcut,
    this.subtitle,
    this.preview = false,
  });

  final SpaceShortcut shortcut;

  /// A live second line (a database's game count) in place of the stored
  /// subtitle, on tiles whose face is a glyph and a name.
  final Widget? subtitle;

  /// The copy the long-press menu lifts over the tile. A game's ending marks
  /// start at rest there, as on the grid card's lifted copy, instead of
  /// replaying over the tile they cover.
  final bool preview;

  @override
  Widget build(BuildContext context) {
    final body = switch (shortcut.kind) {
      SpaceShortcutKind.player ||
      SpaceShortcutKind.playerGames => _PlayerTile(shortcut: shortcut),
      SpaceShortcutKind.streak => _StreakTile(shortcut: shortcut),
      SpaceShortcutKind.countrymen => _CountrymenTile(shortcut: shortcut),
      SpaceShortcutKind.event ||
      SpaceShortcutKind.round => _EventTile(shortcut: shortcut),
      SpaceShortcutKind.position ||
      SpaceShortcutKind.opening ||
      SpaceShortcutKind.playerOpenings => _OpeningTile(shortcut: shortcut),
      SpaceShortcutKind.game => _GameTile(shortcut: shortcut, preview: preview),
      SpaceShortcutKind.folder ||
      SpaceShortcutKind.miniatures ||
      SpaceShortcutKind.likes ||
      SpaceShortcutKind.smartEvent ||
      SpaceShortcutKind.link => _GlyphTile(
        shortcut: shortcut,
        subtitle: subtitle,
      ),
    };
    return SizedBox(
      width: shortcut.kind.tileWidth,
      height: SpaceMetrics.railHeight,
      child: body,
    );
  }
}

// ---------------------------------------------------------------- type

/// One scale for every string on a tile: the spec's px sizes, run through the
/// app's font scaling, with the spec's line heights kept as ratios.
///
/// [tabular] is for a bare number that changes in place (a row's count, a
/// streak). Inter's tabular set also widens the hyphen and the full stop, so
/// on words and move lists it would read "Caro - Kann" and "1 . e4".
TextStyle spaceText(
  BuildContext context, {
  required double size,
  required double line,
  FontWeight weight = FontWeight.w500,
  Color? color,
  bool tabular = false,
}) {
  return AppTypography.textXsMedium.copyWith(
    fontSize: size.f,
    height: line / size,
    fontWeight: weight,
    color: color ?? context.colors.textPrimary,
    fontFeatures: tabular ? const [FontFeature.tabularFigures()] : null,
  );
}

// ---------------------------------------------------------------- params

extension _Params on SpaceShortcut {
  String? str(String key) {
    final v = params[key];
    if (v == null) return null;
    final s = v.toString().trim();
    return s.isEmpty ? null : s;
  }

  int? integer(String key) {
    final v = params[key];
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? '');
  }

  int? get fideId {
    final fromParams = integer('fideId');
    if (fromParams != null && fromParams > 0) return fromParams;
    final fromTarget = int.tryParse(targetId);
    return fromTarget != null && fromTarget > 0 ? fromTarget : null;
  }
}

String _initials(String name) {
  final clean = name.replaceAll(',', ' ').trim();
  if (clean.isEmpty) return '?';
  final parts = clean.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.length == 1) {
    final only = parts.first;
    return (only.length <= 2 ? only : only.substring(0, 2)).toUpperCase();
  }
  // "Carlsen, Magnus" and "Magnus Carlsen" both read "MC".
  final commaFirst = name.contains(',');
  final first = commaFirst ? parts[1] : parts.first;
  final last = commaFirst ? parts.first : parts.last;
  return '${first[0]}${last[0]}'.toUpperCase();
}

/// The flat plate every filled tile sits on.
BoxDecoration _plate(BuildContext context) => BoxDecoration(
  color: context.colors.surface,
  borderRadius: BorderRadius.circular(4.w),
);

// ---------------------------------------------------------------- players

class _PlayerTile extends ConsumerWidget {
  const _PlayerTile({required this.shortcut});

  final SpaceShortcut shortcut;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fideId = shortcut.fideId;
    final photo = fideId == null
        ? null
        : ref.watch(playerPhotoProvider(fideId)).valueOrNull;
    final name = shortcut.str('playerName') ?? shortcut.title;
    final title = shortcut.str('title');
    final rating = shortcut.integer('rating');
    final federation = shortcut.str('federation');

    // No cheap "is playing now" source exists for an arbitrary player, so the
    // status line is the player's standing: title and rating, else whatever
    // the pinning surface wrote.
    final status = shortcut.kind == SpaceShortcutKind.playerGames
        ? 'Games'
        : [
            if (rating != null && rating > 0) rating.toString(),
            if (federation != null) federation.toUpperCase(),
          ].join(' · ');

    return DecoratedBox(
      decoration: _plate(context),
      child: Padding(
        padding: EdgeInsets.fromLTRB(12.w, 18.w, 12.w, 14.w),
        child: Column(
          children: [
            _AvatarWithFlag(
              size: 72.w,
              photoUrl: photo,
              initials: _initials(name),
              title: title,
              federation: federation,
            ),
            SizedBox(height: 14.w),
            // At most two lines, which the plate holds at any text size.
            _PlayerName(name: name),
            SizedBox(height: 2.w),
            Text(
              status.isNotEmpty ? status : (shortcut.subtitle ?? ''),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: spaceText(
                context,
                size: 11,
                line: 15,
                color: context.colors.textPrimaryMuted,
              ),
            ),
            if (shortcut.kind == SpaceShortcutKind.playerGames) ...[
              const Spacer(),
              _OpenRow(label: 'All games'),
            ],
          ],
        ),
      ),
    );
  }
}

/// A player's name on the narrow plate, never broken inside a word.
///
/// "Carlsen, Magnus" stacks surname over given name. A name without a comma
/// stays on one line when it fits, else splits at its last space; an initial
/// ("Praggnanandhaa R") never stands on a line of its own. Each line shrinks
/// to the plate rather than wrapping, so "Nepomniachtchi" or
/// "Vachier-Lagrave" is never cut in two.
class _PlayerName extends StatelessWidget {
  const _PlayerName({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final style = spaceText(
      context,
      size: 13,
      line: 17,
      weight: FontWeight.w700,
    );
    return Semantics(
      label: name,
      excludeSemantics: true,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final lines = _nameLines(name, (text) {
            if (!constraints.maxWidth.isFinite) return true;
            final painter = _painter(context, text, style)..layout();
            final fits = painter.width <= constraints.maxWidth;
            painter.dispose();
            return fits;
          });
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final line in lines)
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(line, maxLines: 1, softWrap: false, style: style),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// The lines [_PlayerName] sets [name] on. [fits] says whether a string fits
/// one line of the plate.
List<String> _nameLines(String name, bool Function(String) fits) {
  final clean = name.trim();
  final comma = clean.indexOf(',');
  if (comma > 0) {
    final surname = clean.substring(0, comma).trim();
    final given = clean.substring(comma + 1).trim();
    return given.isEmpty ? [surname] : [surname, given];
  }
  if (fits(clean)) return [clean];
  final words = clean.split(RegExp(r'\s+'));
  bool initial(String w) => w.replaceAll('.', '').length <= 1;
  var cut = words.length - 1;
  while (cut > 0 && initial(words[cut])) {
    cut--;
  }
  if (cut <= 0 || words.take(cut).every(initial)) return [clean];
  return [words.take(cut).join(' '), words.skip(cut).join(' ')];
}

/// [text] laid out the way a [Text] in [style] would be here (inherited
/// style, text scale), for tiles that pick a layout from how copy wraps.
/// The caller lays it out and disposes it.
TextPainter _painter(
  BuildContext context,
  String text,
  TextStyle style, {
  int? maxLines,
}) {
  return TextPainter(
    text: TextSpan(
      text: text,
      style: DefaultTextStyle.of(context).style.merge(style),
    ),
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
    maxLines: maxLines,
  );
}

class _AvatarWithFlag extends StatelessWidget {
  const _AvatarWithFlag({
    required this.size,
    required this.photoUrl,
    required this.initials,
    required this.title,
    required this.federation,
  });

  final double size;
  final String? photoUrl;
  final String initials;
  final String? title;
  final String? federation;

  @override
  Widget build(BuildContext context) {
    final showFlag = FederationFlag.hasVisibleFlag(federation);
    final ring = 2.w;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          PlayerInitialsAvatar(
            photoUrl: photoUrl,
            initials: initials,
            size: size,
            title: title,
            isCircular: true,
          ),
          if (showFlag)
            Positioned(
              right: size * 0.02 - ring,
              top: size * 0.02 - ring,
              // The ring is the plate colour, so the flag reads as cut out of
              // the avatar rather than stuck on top of it.
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: context.colors.surface,
                  borderRadius: BorderRadius.circular(3.w),
                ),
                child: Padding(
                  padding: EdgeInsets.all(ring),
                  child: FederationFlag(
                    federation: federation,
                    width: 18.w,
                    height: 13.5.w,
                    borderRadius: BorderRadius.circular(2.w),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Where the streak wall stands, as far as a tile cares.
enum _WallPhase { loading, ready, failed }

_WallPhase _wallPhase(AsyncValue<List<StreakRow>> wall) {
  if (wall.hasValue) return _WallPhase.ready;
  if (wall.hasError && !wall.isLoading) return _WallPhase.failed;
  return _WallPhase.loading;
}

/// A live streak card (StreakTile spec): the player's current run, read from
/// the streak wall.
///
/// The tile shows the class a tap opens, so the count here and the card
/// behind it never disagree: a pinned class shows only itself, live or cold,
/// and a pin without a class shows the hottest live run, which is also where
/// the card opens. The wall only holds runs of three or more, so a player off
/// it reads "Under 3 in a row": the card may still be warming up at one or
/// two, and "No live run" would contradict it.
///
/// The wall is re-read (when stale) each time the tile mounts and each time
/// the app comes back to the foreground, so a failed first read or a session
/// that lives for days never leaves an old count standing.
class _StreakTile extends ConsumerStatefulWidget {
  const _StreakTile({required this.shortcut});

  final SpaceShortcut shortcut;

  @override
  ConsumerState<_StreakTile> createState() => _StreakTileState();
}

class _StreakTileState extends ConsumerState<_StreakTile> {
  late final AppLifecycleListener _lifecycle;

  /// Three text lines, a flame row and the run strip fill the fixed 209pt
  /// plate with ~7pt to spare at 1x. At 1.15 that slack is gone (the strip
  /// overflows by a hair); 1.1 keeps ~2pt, so the strip stays inside the
  /// padding on every phone.
  static const double _maxTextScale = 1.1;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: _refreshWall);
    // After this frame: a retry publishes a loading state, which a provider
    // may not do while the tree is building.
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshWall());
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  void _refreshWall() {
    if (!mounted) return;
    final wall = ref.read(streakWallProvider);
    // A read is already in flight (the first build refreshes a stale cache
    // on its own); every other state, a failed one included, re-reads when
    // what it holds is older than the wall's max age.
    if (wall.isLoading && !wall.hasValue) return;
    unawaited(ref.read(streakWallProvider.notifier).refreshIfStale());
  }

  /// The run to show. A pinned class shows only itself: it is the class a
  /// tap opens. With nothing pinned, the hottest live run, ties broken the
  /// way the card's `pickClass` breaks them, so the tap lands on it too.
  static StreakRow? _pick(List<StreakRow> live, StreakTimeClass? pinned) {
    if (pinned != null) {
      for (final row in live) {
        if (row.timeClass == pinned) return row;
      }
      return null;
    }
    StreakRow? hottest;
    for (final row in live) {
      if (hottest == null || _hotter(row, hottest)) hottest = row;
    }
    return hottest;
  }

  static bool _hotter(StreakRow a, StreakRow b) {
    if (a.currentStreak != b.currentStreak) {
      return a.currentStreak > b.currentStreak;
    }
    if (a.bestStreak != b.bestStreak) return a.bestStreak > b.bestStreak;
    return a.timeClass.index < b.timeClass.index;
  }

  /// "Carlsen, Magnus" → "Carlsen"; a name without a comma stays whole.
  static String _surname(String name) {
    final comma = name.indexOf(',');
    return comma > 0 ? name.substring(0, comma).trim() : name.trim();
  }

  @override
  Widget build(BuildContext context) {
    // Every Text below reads the clamped scaler from its own element, so the
    // tile body can be built (and watch providers) right here in build.
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: _maxTextScale,
      child: _buildTile(context),
    );
  }

  Widget _buildTile(BuildContext context) {
    final shortcut = widget.shortcut;
    final fideId = shortcut.fideId;
    final photo = fideId == null
        ? null
        : ref.watch(playerPhotoProvider(fideId)).valueOrNull;
    final pinned = StreakTimeClassX.tryParse(shortcut.str('timeClass'));
    final phase = ref.watch(streakWallProvider.select(_wallPhase));
    final live = _pick(
      fideId == null
          ? const <StreakRow>[]
          : ref.watch(playerLiveStreaksProvider(fideId)),
      pinned,
    );

    final storedName = shortcut.str('playerName') ?? shortcut.title;
    final initialsName = live?.name ?? storedName;
    final surname = live?.shortName ?? _surname(storedName);
    final shownClass = live?.timeClass ?? pinned;
    final muted = context.colors.textPrimaryMuted;
    // The spec's ember orange, deepened on the light plate so it still reads.
    final warm = context.isLightTheme
        ? const Color(0xFFB4470F)
        : const Color(0xFFF59A3C);

    final n = live?.currentStreak;
    final String word;
    final Color wordColor;
    if (n != null) {
      word = live!.level.word.toLowerCase();
      wordColor = warm;
    } else {
      word = switch (phase) {
        // Off the wall is under three, not necessarily zero.
        _WallPhase.ready => 'Under 3 in a row',
        _WallPhase.failed => "Couldn't load",
        // Still loading: hold the line so nothing jumps when it lands.
        _WallPhase.loading => '',
      };
      wordColor = muted;
    }

    return DecoratedBox(
      decoration: _plate(context),
      child: Padding(
        padding: EdgeInsets.fromLTRB(12.w, 16.w, 12.w, 14.w),
        child: Column(
          children: [
            _AvatarWithFlag(
              size: 60.w,
              photoUrl: photo,
              initials: _initials(initialsName),
              title: live?.title ?? shortcut.str('title'),
              federation:
                  live?.fed ??
                  shortcut.str('fed') ??
                  shortcut.str('federation'),
            ),
            SizedBox(height: 12.w),
            SizedBox(
              height: 34.w,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  // Without a live run (cold, loading or unreadable) the
                  // flame is dimmed and still, as on the player card: a lit
                  // flame always means a run.
                  TickerMode(
                    enabled: n != null,
                    child: Opacity(
                      opacity: n == null ? 0.35 : 1,
                      child: PixelFlame(streak: n ?? 0, size: 30.w),
                    ),
                  ),
                  if (n != null) ...[
                    SizedBox(width: 5.w),
                    // A three-digit run shrinks to the tile rather than
                    // spilling past it.
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.bottomLeft,
                        child: Text(
                          '$n',
                          maxLines: 1,
                          style: spaceText(
                            context,
                            size: 32,
                            line: 32,
                            weight: FontWeight.w700,
                            tabular: true,
                          ).copyWith(letterSpacing: 0.5),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            SizedBox(height: 4.w),
            // "Under 3 in a row" is the widest status and only just fits at
            // 1x: at larger text it shrinks to the tile instead of losing
            // its last word to an ellipsis.
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                word,
                maxLines: 1,
                style: spaceText(
                  context,
                  size: 11,
                  line: 14,
                  weight: FontWeight.w600,
                  color: wordColor,
                ),
              ),
            ),
            SizedBox(height: 10.w),
            Text(
              surname,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: spaceText(
                context,
                size: 13,
                line: 17,
                weight: FontWeight.w700,
              ),
            ),
            Text(
              shownClass == null ? 'Streak' : '${shownClass.label} wins',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: spaceText(context, size: 11, line: 15, color: muted),
            ),
            const Spacer(),
            if (n != null) _RunStrip(wins: n),
          ],
        ),
      ),
    );
  }
}

/// The run as a strip of small squares: the loss that anchors it, then up to
/// eleven wins, the latest three brightest.
class _RunStrip extends StatelessWidget {
  const _RunStrip({required this.wins});

  final int wins;

  static const _loss = Color(0xFFF5453A);
  static const _win = Color(0xFFE4552A);
  static const _fresh = Color(0xFFFFB454);

  // On paper the bright amber of the latest wins washes out; the three
  // steps are inked instead, each clearing 3:1 on the plate.
  static const _winLight = Color(0xFFE4552A);
  static const _freshLight = Color(0xFFA85E00);
  static const _maxShown = 11;

  @override
  Widget build(BuildContext context) {
    final shown = wins.clamp(0, _maxShown);
    final light = context.isLightTheme;
    final loss = light ? context.colors.danger : _loss;
    final win = light ? _winLight : _win;
    final fresh = light ? _freshLight : _fresh;
    final colors = [
      loss,
      for (var i = 0; i < shown; i++) i >= shown - 3 ? fresh : win,
    ];
    final side = 6.w;
    return Semantics(
      label: '$wins decisive wins since the last loss',
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < colors.length; i++) ...[
              if (i > 0) SizedBox(width: 2.w),
              SizedBox(
                width: side,
                height: side,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors[i],
                    borderRadius: BorderRadius.circular(1.w),
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

class _CountrymenTile extends StatelessWidget {
  const _CountrymenTile({required this.shortcut});

  final SpaceShortcut shortcut;

  @override
  Widget build(BuildContext context) {
    final code = shortcut.targetId;
    final hasFlag = FederationFlag.hasVisibleFlag(code);
    final width = SpaceMetrics.narrow;
    final flagHeight = 112.w;
    return DecoratedBox(
      decoration: _plate(context),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4.w),
        child: Stack(
          children: [
            if (hasFlag)
              Positioned(
                left: 0,
                top: 0,
                width: width,
                height: flagHeight,
                // The flag dissolves into the plate over a long, many-stop
                // fade so there is no seam where the image stops.
                child: Opacity(
                  opacity: 0.55,
                  child: ShaderMask(
                    blendMode: BlendMode.dstIn,
                    shaderCallback: (rect) => const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      stops: [0, 0.45, 0.58, 0.7, 0.8, 0.88, 0.95, 1],
                      colors: [
                        Color(0xFF000000),
                        Color(0xFF000000),
                        Color(0xCC000000),
                        Color(0x99000000),
                        Color(0x59000000),
                        Color(0x33000000),
                        Color(0x14000000),
                        Color(0x00000000),
                      ],
                    ).createShader(rect),
                    child: FittedBox(
                      fit: BoxFit.cover,
                      clipBehavior: Clip.hardEdge,
                      child: FederationFlag(
                        federation: code,
                        width: width,
                        height: width * 0.75,
                        borderRadius: BorderRadius.zero,
                      ),
                    ),
                  ),
                ),
              ),
            Positioned(
              left: 12.w,
              right: 12.w,
              top: 118.w,
              bottom: 14.w,
              child: Column(
                children: [
                  Text(
                    shortcut.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: spaceText(
                      context,
                      size: 13,
                      line: 17,
                      weight: FontWeight.w700,
                    ),
                  ),
                  SizedBox(height: 2.w),
                  Text(
                    shortcut.subtitle ?? code.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: spaceText(
                      context,
                      size: 11,
                      line: 15,
                      color: context.colors.textPrimaryMuted,
                    ),
                  ),
                  const Spacer(),
                  _OpenRow(label: 'Players'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- events

class _EventTile extends ConsumerWidget {
  const _EventTile({required this.shortcut});

  final SpaceShortcut shortcut;

  bool get _isRound => shortcut.kind == SpaceShortcutKind.round;

  /// The group-broadcast id an image and a next round can be resolved from.
  String? get _eventId {
    if (!_isRound) return shortcut.targetId;
    return shortcut.str('groupBroadcastId') ??
        shortcut.str('eventId') ??
        shortcut.str('groupId');
  }

  /// Calendar and database-only events are not broadcasts: nothing live, no
  /// next round and no broadcast image to look up for them.
  bool get _isCommunity =>
      isSpaceCalendarEvent(shortcut) ||
      isVirtualGamebaseId(shortcut.targetId) ||
      isVirtualGamebaseId(_eventId);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eventId = _eventId;
    // Same live authorities the event cards use: the strict group-broadcast
    // stream for events, the settings row for rounds.
    final isLive = _isRound
        ? ref.watch(
            liveRoundsIdProvider.select(
              (ids) => ids.valueOrNull?.contains(shortcut.targetId) ?? false,
            ),
          )
        : _isCommunity
        ? false
        : ref.watch(
                liveGroupBroadcastIdsProvider.select(
                  (ids) =>
                      ids.valueOrNull?.contains(shortcut.targetId) ?? false,
                ),
              ) ||
              ref.watch(
                liveTourIdProvider.select(
                  (ids) =>
                      ids.valueOrNull?.contains(shortcut.targetId) ?? false,
                ),
              );

    final nextRound = !_isRound && !_isCommunity && !isLive && eventId != null
        ? ref.watch(eventNextRoundProvider(eventId)).valueOrNull
        : null;

    final muted = context.colors.textPrimaryMuted;
    final line = spaceText(context, size: 11, line: 15, color: muted);

    Widget statusLine;
    if (isLive) {
      statusLine = Text(
        'LIVE',
        style: spaceText(
          context,
          size: 11,
          line: 15,
          weight: FontWeight.w700,
          color: context.colors.accentText,
        ).copyWith(letterSpacing: 0.6),
      );
    } else if (nextRound != null) {
      statusLine = Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: nextRound.name.trim(),
              style: line.copyWith(
                fontWeight: FontWeight.w700,
                color: context.colors.textPrimary,
              ),
            ),
            TextSpan(text: '  ·  ${_when(nextRound.startsAt)}'),
          ],
        ),
        style: line,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    } else {
      // A round's event already sits on the foot row.
      statusLine = Text(
        (_isRound ? null : shortcut.str('location')) ?? '',
        style: line,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    }

    // The foot row: an event's dates, a round's event ("Round 7 · LIVE ·
    // Norway Chess 2026"), live or not.
    final footer = _isRound
        ? shortcut.str('eventName') ?? shortcut.subtitle
        : shortcut.str('dates') ?? shortcut.subtitle;
    final tcAsset = _timeControlAsset(shortcut.str('timeControl'));

    return DecoratedBox(
      decoration: _plate(context),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 92.w,
              child: _EventImage(
                eventId: _isCommunity ? null : eventId,
                location: shortcut.str('location'),
              ),
            ),
            Expanded(
              child: Padding(
                padding: EdgeInsets.fromLTRB(10.w, 10.w, 10.w, 12.w),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      shortcut.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: spaceText(
                        context,
                        size: 13,
                        line: 17,
                        weight: FontWeight.w600,
                      ),
                    ),
                    SizedBox(height: 6.w),
                    statusLine,
                    const Spacer(),
                    Row(
                      children: [
                        if (tcAsset != null) ...[
                          // The theme's own twin: the dark-stage coins
                          // vanish on paper.
                          TimeControlGlyph(tcAsset, size: 13.w),
                          SizedBox(width: 5.w),
                        ],
                        Expanded(
                          child: Text(
                            footer ?? '',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: line,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String? _timeControlAsset(String? tc) =>
      TimeControlGlyph.assetForLabel(tc);

  static String _when(DateTime startsAt) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(startsAt.year, startsAt.month, startsAt.day);
    final delta = day.difference(today).inDays;
    final time =
        '${startsAt.hour.toString().padLeft(2, '0')}:'
        '${startsAt.minute.toString().padLeft(2, '0')}';
    if (delta == 0) return 'today $time';
    if (delta == 1) return 'tomorrow $time';
    return '${days[(startsAt.weekday - 1).clamp(0, 6)]} $time';
  }
}

class _EventImage extends ConsumerWidget {
  const _EventImage({required this.eventId, required this.location});

  final String? eventId;
  final String? location;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = eventId;
    if (id == null) {
      return _flagOrPlain(context, _countryFromLocation(location));
    }

    final image = ref.watch(eventImageProvider(id)).valueOrNull;
    if (image == null) {
      return ColoredBox(color: context.colors.surfaceRecessed);
    }
    if (image.hasImage) {
      final cacheWidth =
          (SpaceMetrics.wide * MediaQuery.devicePixelRatioOf(context)).round();
      return CachedNetworkImage(
        imageUrl: image.imageUrl!,
        fit: BoxFit.cover,
        memCacheWidth: cacheWidth,
        fadeInDuration: const Duration(milliseconds: 180),
        placeholder: (_, __) =>
            ColoredBox(color: context.colors.surfaceRecessed),
        errorWidget: (_, __, ___) =>
            _flagOrPlain(context, image.fallbackCountryCode),
      );
    }
    return _flagOrPlain(context, image.fallbackCountryCode);
  }

  static String? _countryFromLocation(String? location) {
    final raw = location?.trim() ?? '';
    if (raw.isEmpty) return null;
    for (final part in [raw, ...raw.split(RegExp(r'[,|/]'))]) {
      final candidate = part.trim();
      if (candidate.isNotEmpty && FederationFlag.hasVisibleFlag(candidate)) {
        return candidate;
      }
    }
    return null;
  }

  Widget _flagOrPlain(BuildContext context, String? country) {
    if (country == null || !FederationFlag.hasVisibleFlag(country)) {
      return ColoredBox(color: context.colors.surfaceRecessed);
    }
    return ColoredBox(
      color: context.colors.surfaceRecessed,
      child: FittedBox(
        fit: BoxFit.cover,
        clipBehavior: Clip.hardEdge,
        child: FederationFlag(
          federation: country,
          width: SpaceMetrics.wide,
          height: SpaceMetrics.wide * 0.75,
          borderRadius: BorderRadius.zero,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- boards

/// A position and how it was reached. The line is normalised by the same
/// resolver the opener uses (UCI, SAN or a numbered SAN string all work), so
/// the tile shows exactly the board a tap will open.
class _Line {
  const _Line({this.fen, this.lastMove, this.after});

  final String? fen;
  final Move? lastMove;

  /// "After 3.e5" / "After 5...a6".
  final String? after;

  static _Line resolve({String? fen, Object? moves}) {
    final line = resolveSpaceLine(fen: fen, moves: moves);
    if (line == null) return _Line(fen: fen);
    if (line.ucis.isEmpty) return _Line(fen: line.fen);
    final sans = spaceSansForUcis(line.ucis);
    String? after;
    if (sans.isNotEmpty) {
      final index = sans.length - 1;
      final number = index ~/ 2 + 1;
      after = index.isEven
          ? 'After $number.${sans[index]}'
          : 'After $number...${sans[index]}';
    }
    return _Line(
      fen: line.fen,
      lastMove: NormalMove.fromUci(line.ucis.last),
      after: after,
    );
  }
}

class _OpeningTile extends StatelessWidget {
  const _OpeningTile({required this.shortcut});

  final SpaceShortcut shortcut;

  @override
  Widget build(BuildContext context) {
    final kind = shortcut.kind;
    final eco =
        (shortcut.str('eco') ??
                (kind == SpaceShortcutKind.opening ? shortcut.targetId : null))
            ?.toUpperCase();

    Object? moves = shortcut.params['moves'];
    if (kind == SpaceShortcutKind.opening &&
        (moves == null || (moves is List && moves.isEmpty)) &&
        eco != null) {
      // An opening family pins a code (or a range like B90-B99): play its
      // canonical line so the tile shows the position the name refers to.
      moves = spaceEcoMovePath(eco.split('-').first.trim());
    }
    final storedFen = kind == SpaceShortcutKind.position
        ? shortcut.targetId
        : shortcut.str('fen');
    final line = _Line.resolve(fen: storedFen, moves: moves);

    final name =
        shortcut.str('openingName') ?? shortcut.str('name') ?? shortcut.title;
    final caption = kind == SpaceShortcutKind.playerOpenings
        ? (shortcut.subtitle ?? line.after ?? '')
        : (line.after ?? shortcut.subtitle ?? '');

    final lane = SpaceMetrics.wide - SpaceMetrics.board;
    final rowHeight = 20.w;
    // The board is a fixed square in a fixed plate; the name and caption
    // around it grow to 1.15x text like every other plate's copy.
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.15,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: rowHeight,
            child: Padding(
              padding: EdgeInsets.only(left: lane),
              child: Row(
                children: [
                  Expanded(
                    child: _SnugLine(
                      text: name,
                      style: spaceText(
                        context,
                        size: 11,
                        line: 14,
                        weight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (eco != null && !name.startsWith(eco)) ...[
                    SizedBox(width: 6.w),
                    Text(
                      eco,
                      style: spaceText(
                        context,
                        size: 10,
                        line: 14,
                        weight: FontWeight.w600,
                        color: context.colors.titleAccent,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          SizedBox(height: 4.w),
          Padding(
            padding: EdgeInsets.only(left: lane),
            child: _Board(fen: line.fen, lastMove: line.lastMove),
          ),
          SizedBox(height: 4.w),
          SizedBox(
            height: rowHeight,
            child: Padding(
              padding: EdgeInsets.only(left: lane),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      caption,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: spaceText(
                        context,
                        size: 11,
                        line: 14,
                        color: context.colors.textPrimaryMuted,
                      ),
                    ),
                  ),
                  SpaceGlyph(
                    SpaceGlyphKind.arrowUpRight,
                    size: 14.w,
                    ink: context.colors.accentText,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One line of copy that eases a few percent smaller rather than lose its
/// last word ("QGD Three Knights" on a 360pt phone at large text). Past
/// [minScale] it keeps its size and ends in an ellipsis instead, so a long
/// catalogue name never turns into fine print.
class _SnugLine extends StatelessWidget {
  const _SnugLine({required this.text, required this.style});

  final String text;
  final TextStyle style;

  static const double minScale = 0.8;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final plain = Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: style,
        );
        if (!box.maxWidth.isFinite || box.maxWidth <= 0) return plain;
        final painter = _painter(context, text, style)..layout();
        final width = painter.width;
        painter.dispose();
        if (width <= box.maxWidth || box.maxWidth / width < minScale) {
          return plain;
        }
        return Align(
          alignment: Alignment.centerLeft,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(text, maxLines: 1, softWrap: false, style: style),
          ),
        );
      },
    );
  }
}

/// A game as the app's grid game card draws it: the card's own player rows
/// ([PlayerFirstRowDetailWidget] in grid view, through [SpaceGamePlayerRow])
/// around its mini board ([GameCardChessboard]), so the flag, title, name,
/// rating, result and clock read exactly as on the card for the same game.
///
/// The geometry is the grid card's at the tile's width: 20pt rows, 4pt gaps,
/// and the board past the 10pt lane where the card keeps its result and eval
/// bar. A row the card opens with that lane (a result, a live gauge) keeps
/// it; one without starts at the board's edge, as on the card. No engine
/// runs here, so the lane beside the board stays empty.
///
/// The players come from the shortcut's card snapshot, or from the game
/// itself, looked up once, for a pin that has none ([watchSpaceGameFace]).
/// Until then [SpaceGamePlayerRowStandIn] holds each row's geometry with
/// the pinned name, and the card's rows cross-fade in over it once the game
/// arrives. A game still being played streams its board the way the card
/// does ([watchLiveGamePosition]), over the same channel as its rows.
class _GameTile extends ConsumerWidget {
  const _GameTile({required this.shortcut, required this.preview});

  final SpaceShortcut shortcut;
  final bool preview;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final face = watchSpaceGameFace(ref, shortcut);
    final ready = face.players == SpaceGamePlayers.ready;
    final game = face.game;
    // A finished game's board is final; only a game that can still move
    // (once its players are known, so a bare pin never streams) watches it.
    final batchKey = ready ? spaceLiveBatchKey(game) : null;
    final live = ready && !game.gameStatus.isFinished
        ? watchLiveGamePosition(ref, game, batchKey: batchKey)
        : game;
    final lane = SpaceMetrics.wide - SpaceMetrics.board;
    final inset = spacePlayerRowLead(ref, live, PlayerView.gridView) > 0
        ? 0.0
        : lane;
    final hideEnding = spaceBoardHidesEnding(ref, live);
    final uci = live.lastMove?.trim() ?? '';

    Widget row({required bool white}) => SizedBox(
      height: 20.w,
      child: _RowCrossFade(
        ready: ready,
        standIn: SpaceGamePlayerRowStandIn(
          name: (white ? game.whitePlayer : game.blackPlayer).name,
          loading: face.players == SpaceGamePlayers.loading,
        ),
        row: Padding(
          padding: EdgeInsets.only(left: inset),
          child: SpaceGamePlayerRow(
            game: live,
            white: white,
            view: PlayerView.gridView,
            liveBatchKey: batchKey,
          ),
        ),
      ),
    );

    // The result and clock are plain text; past 1.15x they would outgrow
    // the card's 20pt rows. The names are set unscaled, as on the card.
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.15,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          row(white: false),
          SizedBox(height: 4.w),
          Padding(
            padding: EdgeInsets.only(left: lane),
            child: _Board(
              fen: live.fen ?? shortcut.str('fen'),
              lastMove: uci.length >= 4 ? Move.parse(uci) : null,
              gameStatus: hideEnding ? GameStatus.ongoing : live.gameStatus,
              animateEnding: !preview,
            ),
          ),
          SizedBox(height: 4.w),
          row(white: true),
        ],
      ),
    );
  }
}

/// One game row slot: the stand-in while the players are unknown, then the
/// card's row fading in over it on a smooth spring as the stand-in fades
/// out, both in the same slot, so nothing moves. A tile that knows its
/// players when it mounts shows the row at once. The row keeps its place in
/// the tree when the stand-in leaves, so it never rebuilds from scratch.
class _RowCrossFade extends StatelessWidget {
  const _RowCrossFade({
    required this.ready,
    required this.standIn,
    required this.row,
  });

  final bool ready;
  final Widget standIn;
  final Widget row;

  static const _motion = CupertinoMotion.smooth(
    duration: Duration(milliseconds: 320),
    snapToEnd: true,
  );

  @override
  Widget build(BuildContext context) {
    final still =
        MediaQuery.disableAnimationsOf(context) ||
        !TickerMode.valuesOf(context).enabled;
    return SingleMotionBuilder(
      motion: still ? const Motion.none() : _motion,
      value: ready ? 1.0 : 0.0,
      builder: (context, value, _) {
        final t = value.clamp(0.0, 1.0);
        return Stack(
          fit: StackFit.expand,
          children: [
            if (t < 1)
              KeyedSubtree(
                key: const ValueKey('stand-in'),
                child: Opacity(opacity: 1 - t, child: standIn),
              ),
            if (ready || t > 0)
              KeyedSubtree(
                key: const ValueKey('row'),
                child: Opacity(opacity: t, child: row),
              ),
          ],
        );
      },
    );
  }
}

/// The app's grid-card mini board, so a pinned position looks exactly like the
/// board it was pinned from (piece set, theme, last-move tint, and for a
/// finished game the fallen king or the draw marks).
class _Board extends StatelessWidget {
  const _Board({
    required this.fen,
    required this.lastMove,
    this.gameStatus,
    this.animateEnding = true,
  });

  final String? fen;
  final Move? lastMove;
  final GameStatus? gameStatus;
  final bool animateEnding;

  @override
  Widget build(BuildContext context) {
    final size = SpaceMetrics.board;
    return SizedBox(
      width: size,
      height: size,
      child: GameCardChessboard(
        fen: fen,
        lastMove: lastMove,
        boardSize: size,
        orientation: Side.white,
        showCoordinates: false,
        gameStatus: gameStatus,
        animateEnding: animateEnding,
      ),
    );
  }
}

// ---------------------------------------------------------------- glyphs

class _GlyphTile extends StatelessWidget {
  const _GlyphTile({required this.shortcut, this.subtitle});

  final SpaceShortcut shortcut;
  final Widget? subtitle;

  @override
  Widget build(BuildContext context) {
    final isFolderNode = shortcut.params['nodeType'] == 'folder';
    final (glyph, fallbackSubtitle) = switch (shortcut.kind) {
      SpaceShortcutKind.folder when isFolderNode => (
        SpaceGlyphKind.folder,
        'Folder',
      ),
      SpaceShortcutKind.folder => (SpaceGlyphKind.database, 'Database'),
      SpaceShortcutKind.miniatures => (SpaceGlyphKind.bolt, 'Today'),
      SpaceShortcutKind.likes => (SpaceGlyphKind.heart, 'Liked games'),
      SpaceShortcutKind.smartEvent => (SpaceGlyphKind.boards, 'Smart Event'),
      _ => (SpaceGlyphKind.link, _host(shortcut.targetId)),
    };
    final caption = shortcut.subtitle ?? fallbackSubtitle;
    final captionStyle = spaceText(
      context,
      size: 11,
      line: 15,
      color: context.colors.textPrimaryMuted,
    );
    // The name may take two lines ("Classical Games") and the second line
    // three ("Every game averaging 2500+" on a small phone) instead of an
    // ellipsis; capped at 1.15x text so both still sit inside the fixed
    // plate. The glyph keeps its 112pt band while the copy leaves room for
    // it, so glyphs line up along the rail, and only gives way (moving up,
    // never shrinking) when a tile's copy needs the extra line.
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.15,
      child: DecoratedBox(
        decoration: _plate(context),
        child: Padding(
          padding: EdgeInsets.fromLTRB(12.w, 0, 12.w, 14.w),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: LayoutBuilder(
                  builder: (context, box) => Align(
                    alignment: Alignment.topCenter,
                    child: SizedBox(
                      height: math.min(112.w, box.maxHeight),
                      child: Center(
                        child: SpaceGlyph(
                          glyph,
                          size: 48.w,
                          ink: context.colors.iconPrimary,
                          background: context.colors.surface,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Text(
                shortcut.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: spaceText(
                  context,
                  size: 13,
                  line: 17,
                  weight: FontWeight.w700,
                ),
              ),
              SizedBox(height: 2.w),
              DefaultTextStyle.merge(
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: captionStyle,
                // A single token (a link's host, "chessever.com") could only
                // wrap by cutting inside the word: it keeps one line and
                // eases smaller instead.
                child:
                    subtitle ??
                    (caption.contains(RegExp(r'\s'))
                        ? Text(caption)
                        : _SnugLine(text: caption, style: captionStyle)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _host(String url) {
    final uri = Uri.tryParse(url);
    final host = uri?.host ?? '';
    if (host.isNotEmpty) return host.replaceFirst('www.', '');
    return 'Link';
  }
}

/// Bottom row on tiles that open a list rather than a single object.
class _OpenRow extends StatelessWidget {
  const _OpenRow({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          label,
          style: spaceText(
            context,
            size: 11,
            line: 15,
            weight: FontWeight.w600,
            color: context.colors.textPrimaryMuted,
          ),
        ),
        SizedBox(width: 4.w),
        SpaceGlyph(
          SpaceGlyphKind.arrowUpRight,
          size: 12.w,
          ink: context.colors.accentText,
        ),
      ],
    );
  }
}
