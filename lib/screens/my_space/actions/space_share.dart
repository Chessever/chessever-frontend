import 'package:chessever2/screens/chessboard/utils/game_share_utils.dart'
    show kGamebaseShareSourceParam, kGamebaseShareSourceValue;
import 'package:chessever2/screens/gamebase/event_view/gamebase_virtual_event_id.dart';
import 'package:chessever2/screens/my_space/models/space_shortcut.dart';
import 'package:chessever2/screens/player_profile/utils/player_profile_share_utils.dart';
import 'package:chessever2/screens/streaks/models/streak_models.dart';
import 'package:chessever2/widgets/event_card/event_context_menu.dart'
    show buildEventShareUrl;

final _uuid = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
  caseSensitive: false,
);

/// The public chessever.com link a shortcut can be shared as, built with the
/// same helpers the app's own Share buttons use. Null for anything without a
/// page anyone else can open: rounds, positions, openings, folders, smart
/// events, countrymen, likes, miniatures, calendar events and database-only
/// (virtual) events.
String? spaceShortcutShareUrl(SpaceShortcut s) {
  final p = s.params;
  switch (s.kind) {
    case SpaceShortcutKind.player:
    case SpaceShortcutKind.playerGames:
      return buildPlayerProfileShareUrl(
        _int(p['fideId']) ?? _int(s.targetId),
        playerName: _str(p['playerName']) ?? s.title,
        memorialRouteId: _str(p['memorialRouteId']),
      );
    case SpaceShortcutKind.streak:
      final fideId = _int(p['fideId']) ?? _int(s.targetId);
      if (fideId == null) return null;
      final tc = StreakTimeClassX.tryParse(_str(p['timeClass']));
      return tc == null
          ? 'https://streaks.chessever.com/p/$fideId'
          : 'https://streaks.chessever.com/p/$fideId?tc=${tc.wire}';
    case SpaceShortcutKind.game:
      return _gameUrl(s);
    case SpaceShortcutKind.event:
      if (isSpaceCalendarEvent(s)) return null;
      final id =
          _str(p['groupBroadcastId']) ?? _str(p['eventId']) ?? s.targetId;
      if (isVirtualGamebaseId(id) || isVirtualGamebaseId(s.targetId)) {
        return null;
      }
      return buildEventShareUrl(
        id: id,
        title: _str(p['eventName']) ?? s.title,
        tourId: _str(p['tourId']),
        tourSlug: _str(p['tourSlug']),
      );
    case SpaceShortcutKind.link:
      final uri = Uri.tryParse(s.targetId.trim());
      final web =
          uri != null &&
          (uri.scheme == 'https' || uri.scheme == 'http') &&
          uri.host.isNotEmpty;
      return web ? uri.toString() : null;
    case SpaceShortcutKind.round:
    case SpaceShortcutKind.position:
    case SpaceShortcutKind.opening:
    case SpaceShortcutKind.playerOpenings:
    case SpaceShortcutKind.folder:
    case SpaceShortcutKind.smartEvent:
    case SpaceShortcutKind.countrymen:
    case SpaceShortcutKind.miniatures:
    case SpaceShortcutKind.likes:
    case SpaceShortcutKind.collection:
      return null;
  }
}

/// A calendar (community or FIDE major) event pinned as an `event`: new pins
/// say so in `source`, older ones through the card's `eventSource` or the
/// `cal_event_` id the calendar cards use.
bool isSpaceCalendarEvent(SpaceShortcut s) {
  if (s.kind != SpaceShortcutKind.event) return false;
  final p = s.params;
  return _str(p['source']) == 'calendar' ||
      _str(p['eventSource']) == 'communityEvent' ||
      _str(p['calendarEventId']) != null ||
      s.targetId.startsWith('cal_event_');
}

/// Games are shared by their canonical id, exactly like the board's Share.
/// Gamebase-only games (a uuid with no Lichess id) carry `src=gamebase` so the
/// link resolves through the archive.
String? _gameUrl(SpaceShortcut s) {
  final id = s.targetId.trim();
  final linkable =
      _uuid.hasMatch(id) ||
      RegExp(r'^[A-Za-z0-9]{8}$').hasMatch(id) ||
      RegExp(r'^[A-Za-z0-9]{8}-[A-Za-z0-9]+$').hasMatch(id) ||
      RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]*:[^\s/?#]+$').hasMatch(id);
  if (!linkable) return null;
  final base = Uri.parse(
    'https://chessever.com/games/${Uri.encodeComponent(id)}',
  );
  final gamebase = _str(s.params['source']) == 'gamebase' && _uuid.hasMatch(id);
  return gamebase
      ? base
            .replace(
              queryParameters: {
                kGamebaseShareSourceParam: kGamebaseShareSourceValue,
              },
            )
            .toString()
      : base.toString();
}

String? _str(Object? value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}

int? _int(Object? value) {
  if (value is int) return value > 0 ? value : null;
  if (value is num) return value > 0 ? value.toInt() : null;
  final parsed = int.tryParse(value?.toString().trim() ?? '');
  return parsed != null && parsed > 0 ? parsed : null;
}
