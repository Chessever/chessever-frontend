import 'package:chessever2/screens/favorites/tabs/favorites_players_tab.dart'
    show playerPhotoProvider;
import 'package:chessever2/screens/library/widgets/library_context_menu.dart';
import 'package:chessever2/screens/my_space/actions/space_menu_action.dart';
import 'package:chessever2/screens/my_space/models/space_shortcut.dart';
import 'package:chessever2/screens/my_space/navigation/space_shortcut_navigator.dart';
import 'package:chessever2/screens/my_space/widgets/space_avatar.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/app_button.dart' show TappableScale;
import 'package:chessever2/widgets/card_context_menu.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// The surname a face is labelled with: "Carlsen, Magnus" and "Magnus
/// Carlsen" read "Carlsen"; a trailing initial never stands for the name
/// ("Gukesh D" reads "Gukesh").
String spaceSurname(String name) {
  final clean = name.trim();
  if (clean.isEmpty) return '';
  final comma = clean.indexOf(',');
  if (comma > 0) return clean.substring(0, comma).trim();
  final words = clean.split(RegExp(r'\s+'));
  bool initial(String w) => w.replaceAll('.', '').length <= 1;
  for (var i = words.length - 1; i >= 0; i--) {
    if (!initial(words[i])) return words[i];
  }
  return clean;
}

/// The FIDE id a player pin stands for, or null.
int? spacePinFideId(SpaceShortcut s) {
  final raw = s.params['fideId'];
  final fromParams = raw is num ? raw.toInt() : int.tryParse('${raw ?? ''}');
  if (fromParams != null && fromParams > 0) return fromParams;
  final fromTarget = int.tryParse(s.targetId);
  return fromTarget != null && fromTarget > 0 ? fromTarget : null;
}

String? _param(SpaceShortcut s, String key) {
  final v = s.params[key];
  if (v == null) return null;
  final t = v.toString().trim();
  return t.isEmpty ? null : t;
}

/// The saved players as a row of faces (an avatar group): photo, flag and
/// title on the circle, the surname under it and one line of standing (the
/// rating, "Games" for a games pin, LIVE while they are at the board). A
/// saved Countrymen reads as its flag. [padding] is the page gutter it
/// starts on.
///
/// On a phone a row longer than the screen scrolls sideways, running to the
/// screen's edge. Where the strip stands in a bounded column (a tablet's
/// half) or [wrap] asks for it (See all), the faces wrap onto rows of whole
/// faces instead, so no face is ever cut at a column's edge.
class SpacePlayerStrip extends StatelessWidget {
  const SpacePlayerStrip({
    super.key,
    required this.players,
    required this.liveFideIds,
    required this.padding,
    this.wrap = false,
  });

  final List<SpaceShortcut> players;
  final Set<int> liveFideIds;
  final double padding;
  final bool wrap;

  /// Width of one face and its two lines.
  static double get itemWidth => 80.w;

  /// Between two faces.
  static double get gap => 10.w;

  /// The circle.
  static double get face => 56.w;

  Widget _face(SpaceShortcut s, {double? width}) => SpacePlayerFace(
    key: ValueKey<String>('space_player_${s.key}'),
    shortcut: s,
    width: width,
    live: switch (spacePinFideId(s)) {
      final id? => liveFideIds.contains(id),
      null => false,
    },
  );

  /// The width each face takes on a phone rail [available] wide that holds
  /// more faces than fit: whole faces, then the next one cut through the
  /// middle of its circle, so the row reads as one that scrolls on (never a
  /// sliver of a face at the screen's edge). Null when every face fits.
  static double? peekWidth({
    required double available,
    required double padding,
    required int count,
  }) {
    final span = available - padding;
    if (count * itemWidth + (count - 1) * gap + padding <= span) return null;
    // Whole faces at the natural width, then half of one more.
    var whole = ((span + gap) / (itemWidth + gap)).floor();
    for (; whole > 0; whole--) {
      final width = (span - whole * gap) / (whole + 0.5);
      // Never so narrow the face's circle crowds its names.
      if (width >= face + 12.w) return width;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    Widget wrapped() => Padding(
      padding: EdgeInsets.symmetric(horizontal: padding),
      child: Wrap(
        spacing: gap,
        runSpacing: 12.w,
        children: [for (final s in players) _face(s)],
      ),
    );
    if (wrap) return wrapped();
    Widget rail({double? width}) => SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      padding: EdgeInsets.symmetric(horizontal: padding),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < players.length; i++) ...[
            if (i > 0) SizedBox(width: gap),
            _face(players[i], width: width),
          ],
        ],
      ),
    );
    return LayoutBuilder(
      builder: (context, box) {
        final available = box.maxWidth.isFinite
            ? box.maxWidth
            : MediaQuery.sizeOf(context).width;
        if (ResponsiveHelper.isTablet) {
          final need =
              players.length * itemWidth +
              (players.length - 1) * gap +
              2 * padding;
          return need <= available ? rail() : wrapped();
        }
        return rail(
          width: peekWidth(
            available: available,
            padding: padding,
            count: players.length,
          ),
        );
      },
    );
  }
}

/// One face of [SpacePlayerStrip]. Tap opens the pin as it was saved; a
/// long press lifts it into the focus menu with Open and My Space.
class SpacePlayerFace extends ConsumerWidget {
  const SpacePlayerFace({
    super.key,
    required this.shortcut,
    this.live = false,
    this.width,
  });

  final SpaceShortcut shortcut;
  final bool live;

  /// The face's column width; [SpacePlayerStrip.itemWidth] unless the rail
  /// sizes its faces to end on a half face.
  final double? width;

  void _open(BuildContext context, WidgetRef ref) {
    HapticFeedbackService.cardTap();
    openSpaceShortcut(context, ref, shortcut);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final s = shortcut;
    final countrymen = s.kind == SpaceShortcutKind.countrymen;
    final fideId = countrymen ? null : spacePinFideId(s);
    final photo = fideId == null
        ? null
        : ref.watch(playerPhotoProvider(fideId)).valueOrNull;
    final name = _param(s, 'playerName') ?? s.title;
    final rating = int.tryParse(_param(s, 'rating') ?? '');
    final label = countrymen ? s.title : spaceSurname(name);
    final standing = switch (s.kind) {
      SpaceShortcutKind.countrymen => 'Countrymen',
      SpaceShortcutKind.playerGames => 'Games',
      _ when rating != null && rating > 0 => '$rating',
      _ => _param(s, 'title') ?? 'Player',
    };

    final nameStyle = AppTypography.textSmMedium.copyWith(
      fontSize: 12.5.f,
      height: 17 / 12.5,
      fontWeight: FontWeight.w600,
      color: colors.textPrimary,
    );
    final lineStyle = AppTypography.textXsMedium.copyWith(
      fontSize: 11.f,
      height: 15 / 11,
      color: colors.textSecondary,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final liveStyle = lineStyle.copyWith(
      color: colors.accentText,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.6,
      fontFeatures: const [],
    );

    final body = SizedBox(
      width: width ?? SpacePlayerStrip.itemWidth,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(height: 4.w),
          if (countrymen)
            SpaceFlagAvatar(size: SpacePlayerStrip.face, country: s.targetId)
          else
            SpacePlayerAvatar(
              size: SpacePlayerStrip.face,
              name: name,
              photoUrl: photo,
              title: _param(s, 'title'),
              federation: _param(s, 'federation') ?? _param(s, 'fed'),
            ),
          SizedBox(height: 8.w),
          // One size for every name, one line: a long surname ends in an
          // ellipsis rather than shrinking, so every name shares one size
          // and one baseline.
          Text(
            label,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: nameStyle,
          ),
          SizedBox(height: 1.w),
          Text(
            live ? 'LIVE' : standing,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: live ? liveStyle : lineStyle,
          ),
          SizedBox(height: 4.w),
        ],
      ),
    );

    return Semantics(
      button: true,
      label: [name, if (live) 'playing now' else standing].join(', '),
      excludeSemantics: true,
      onTap: () => _open(context, ref),
      child: TappableScale(
        onTap: () => _open(context, ref),
        child: CardContextMenu(
          onPreviewTap: () => _open(context, ref),
          actions: (menuContext) => [
            LibraryMenuAction(
              icon: Icons.open_in_new_rounded,
              label: 'Open',
              onSelected: () => _open(context, ref),
            ),
            spaceMenuAction(context: menuContext, ref: ref, draft: s),
          ],
          child: ColoredBox(color: Colors.transparent, child: body),
        ),
      ),
    );
  }
}
