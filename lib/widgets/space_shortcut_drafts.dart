import 'package:chessever2/screens/library/providers/library_folders_provider.dart'
    show kTwicBookId;
import 'package:chessever2/screens/library/widgets/library_context_menu.dart';
import 'package:chessever2/screens/my_space/actions/space_menu_action.dart';
import 'package:chessever2/screens/my_space/models/space_shortcut.dart';
import 'package:chessever2/screens/my_space/providers/space_shortcuts_provider.dart';
import 'package:chessever2/utils/eco_openings.dart';
import 'package:chessever2/utils/favorite_player_identity.dart'
    show countryCodeToIso2;
import 'package:country_picker/country_picker.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter/widgets.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Draft builders shared by every long-press surface that pins a player or an
/// opening into My Space. One targetId + params shape per kind is what makes
/// "Add" on the standings row read as "Remove" on the favorites row for the
/// same player, so callers never assemble these maps by hand.

/// A player's identity in My Space: FIDE id, else gamebase id, else name.
String spacePlayerTargetId({
  required String playerName,
  int? fideId,
  String? gamebasePlayerId,
}) {
  if (fideId != null && fideId > 0) return fideId.toString();
  final gamebase = gamebasePlayerId?.trim() ?? '';
  if (gamebase.isNotEmpty) return gamebase;
  return playerName.trim();
}

SpaceShortcut spacePlayerDraft({
  required String playerName,
  int? fideId,
  String? title,
  String? federation,
  int? rating,
  String? gamebasePlayerId,
  String? memorialSourceIdentity,
  String? memorialRouteId,
}) {
  return _playerDraft(
    kind: SpaceShortcutKind.player,
    playerName: playerName,
    fideId: fideId,
    title: title,
    federation: federation,
    rating: rating,
    gamebasePlayerId: gamebasePlayerId,
    memorialSourceIdentity: memorialSourceIdentity,
    memorialRouteId: memorialRouteId,
  );
}

SpaceShortcut spacePlayerGamesDraft({
  required String playerName,
  int? fideId,
  String? title,
  String? federation,
  int? rating,
  String? gamebasePlayerId,
  String? memorialSourceIdentity,
  String? memorialRouteId,
}) {
  return _playerDraft(
    kind: SpaceShortcutKind.playerGames,
    playerName: playerName,
    fideId: fideId,
    title: title,
    federation: federation,
    rating: rating,
    gamebasePlayerId: gamebasePlayerId,
    memorialSourceIdentity: memorialSourceIdentity,
    memorialRouteId: memorialRouteId,
    subtitleOverride: 'Games',
  );
}

SpaceShortcut _playerDraft({
  required SpaceShortcutKind kind,
  required String playerName,
  int? fideId,
  String? title,
  String? federation,
  int? rating,
  String? gamebasePlayerId,
  String? memorialSourceIdentity,
  String? memorialRouteId,
  String? subtitleOverride,
}) {
  final cleanTitle = _nonEmpty(title);
  final cleanFed = _nonEmpty(federation);
  final cleanRating = rating != null && rating > 0 ? rating : null;
  final subtitle =
      subtitleOverride ??
      _nonEmpty(
        [
          cleanTitle,
          cleanRating?.toString(),
          cleanFed,
        ].whereType<String>().join(' · '),
      );
  return SpaceShortcut.draft(
    kind: kind,
    targetId: spacePlayerTargetId(
      playerName: playerName,
      fideId: fideId,
      gamebasePlayerId: gamebasePlayerId,
    ),
    title: playerName.trim(),
    subtitle: subtitle,
    params: {
      if (fideId != null && fideId > 0) 'fideId': fideId,
      'playerName': playerName.trim(),
      if (cleanTitle != null) 'title': cleanTitle,
      if (cleanFed != null) 'federation': cleanFed,
      if (cleanRating != null) 'rating': cleanRating,
      if (_nonEmpty(gamebasePlayerId) != null)
        'gamebasePlayerId': gamebasePlayerId!.trim(),
      if (_nonEmpty(memorialSourceIdentity) != null)
        'memorialSourceIdentity': memorialSourceIdentity!.trim(),
      if (_nonEmpty(memorialRouteId) != null)
        'memorialRouteId': memorialRouteId!.trim(),
    },
  );
}

/// One player's opening tree for one ECO, from one side of the board.
/// [color] is `white`, `black` or `all`.
SpaceShortcut spacePlayerOpeningsDraft({
  required String playerName,
  required String eco,
  required String color,
  int? fideId,
  String? gamebasePlayerId,
  String? openingName,
}) {
  final code = eco.trim().toUpperCase();
  final playerKey = spacePlayerTargetId(
    playerName: playerName,
    fideId: fideId,
    gamebasePlayerId: gamebasePlayerId,
  );
  final name = _nonEmpty(openingName) ?? EcoOpenings.getOpeningName(code);
  final moves = spaceEcoMovePath(code);
  final fen = spaceFenAfter(moves);
  final side = switch (color) {
    'white' => 'as White',
    'black' => 'as Black',
    _ => null,
  };
  return SpaceShortcut.draft(
    kind: SpaceShortcutKind.playerOpenings,
    targetId: '$playerKey:$code:$color',
    title: name == null ? code : '$code $name',
    subtitle: [playerName.trim(), side].whereType<String>().join(' · '),
    params: {
      if (fideId != null && fideId > 0) 'fideId': fideId,
      'playerName': playerName.trim(),
      if (_nonEmpty(gamebasePlayerId) != null)
        'gamebasePlayerId': gamebasePlayerId!.trim(),
      'eco': code,
      'color': color,
      if (name != null) 'openingName': name,
      if (moves.isNotEmpty) 'moves': moves,
      if (fen != null) 'fen': fen,
    },
  );
}

/// An opening family or code. [targetId] is the ECO code (or the family's
/// range label, e.g. `B90-B99`), matching what the search results show.
SpaceShortcut spaceOpeningDraft({
  required String targetId,
  required String name,
  Map<String, dynamic> extraParams = const {},
}) {
  return SpaceShortcut.draft(
    kind: SpaceShortcutKind.opening,
    targetId: targetId,
    title: name,
    subtitle: targetId,
    params: {'name': name, ...extraParams},
  );
}

/// The canonical SAN line for a single ECO code, or empty when the code is a
/// sentinel / unknown.
List<String> spaceEcoMovePath(String eco) {
  final record = EcoOpenings.canonicalRecordForCode(eco);
  if (record == null) return const [];
  return EcoOpenings.moveTokens(record.moves);
}

/// FEN after playing [sanMoves] from the start position; null when any move
/// fails to parse, so a bad catalog row never pins a wrong position.
String? spaceFenAfter(List<String> sanMoves) {
  if (sanMoves.isEmpty) return null;
  try {
    Position position = Chess.initial;
    for (final san in sanMoves) {
      final move = position.parseSan(san);
      if (move == null) return null;
      position = position.play(move);
    }
    return position.fen;
  } catch (_) {
    return null;
  }
}

/// One event of the ChessEver Database: reopens the database filtered to it.
SpaceShortcut spaceTwicEventDraft({
  required String eventName,
  String? subtitle,
}) {
  final event = eventName.trim();
  return SpaceShortcut.draft(
    kind: SpaceShortcutKind.folder,
    targetId: '$kTwicBookId:$event',
    title: event,
    subtitle: _nonEmpty(subtitle) ?? 'ChessEver Database',
    params: {'event': event},
  );
}

/// Countrymen for a federation, keyed on the ISO code the Countrymen screen
/// pins, so a FIDE code (`NOR`) from a player row and the screen's own `NO`
/// are the same pin. Null when the code names no country.
SpaceShortcut? spaceCountrymenDraft(String code) {
  final iso2 = countryCodeToIso2(code);
  if (iso2.isEmpty) return null;
  final country = CountryService().findByCode(iso2);
  if (country == null) return null;
  return SpaceShortcut.draft(
    kind: SpaceShortcutKind.countrymen,
    targetId: country.countryCode,
    title: country.name,
    subtitle: 'Countrymen',
    params: {'name': country.name},
  );
}

/// [spaceMenuAction] with surface-specific wording, for menus that offer more
/// than one My Space row (a player and their Games tab, an opening and a
/// player's tree of it) where two identical "Add to My Space" rows would be
/// ambiguous. Persistence, haptics and the snack stay in the shared action.
LibraryMenuAction labeledSpaceMenuAction({
  required BuildContext context,
  required WidgetRef ref,
  required SpaceShortcut draft,
  required String addLabel,
  required String removeLabel,
}) {
  final base = spaceMenuAction(context: context, ref: ref, draft: draft);
  final inSpace = ref.read(spaceShortcutExistsProvider(draft.key));
  return LibraryMenuAction(
    icon: base.icon,
    label: inSpace ? removeLabel : addLabel,
    onSelected: base.onSelected,
  );
}

String? _nonEmpty(String? value) {
  final trimmed = value?.trim() ?? '';
  return trimmed.isEmpty ? null : trimmed;
}
