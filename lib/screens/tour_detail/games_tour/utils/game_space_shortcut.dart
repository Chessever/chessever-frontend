import 'package:chessever2/screens/my_space/models/space_game_card.dart';
import 'package:chessever2/screens/my_space/models/space_shortcut.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/utils/string_utils.dart';

/// The My Space shortcut for one game. Every card and board that offers
/// "Add to My Space" builds it here, so a game pinned from the Games tab, a
/// board grid or My Likes dedupes to the same shortcut.
///
/// The target is the game's canonical id ([GamesTourModel.likeId]), never the
/// synthetic board-isolation id a saved analysis carries. The defaults carry
/// the game card's snapshot ([spaceGameCardParams]), so the My Space tile
/// draws the same rows as the card it was pinned from with no lookup.
/// [params] extends or overrides the defaults; a null value drops that key.
///
/// Returns null when there is nothing the app could reopen later: board-editor
/// positions, local analyses, or a saved analysis with no source game.
SpaceShortcut? gameSpaceShortcutDraft(
  GamesTourModel game, {
  String? subtitle,
  Map<String, Object?> params = const {},
}) {
  final targetId = game.likeId.trim();
  if (!_isDeepLinkable(game, targetId)) return null;

  final gamebaseBacked =
      game.source == GameSource.gamebase || game.source == GameSource.twic;

  final merged = <String, dynamic>{
    'tourId': game.tourId,
    // Gamebase rows carry an explorer sentinel in roundId, not a round.
    if (!gamebaseBacked) 'roundId': game.roundId,
    'tourSlug': game.tourSlug,
    'fen': game.fen,
    'white': game.whitePlayer.name,
    'black': game.blackPlayer.name,
    'eco': game.eco,
    if (gamebaseBacked) 'source': 'gamebase',
    // Callers that already built the snapshot (liked faces, most liked) keep
    // theirs; the PGN parse behind it is cached, so the rest pay little.
    if (!params.containsKey(kSpaceGameCardParam)) ...spaceGameCardParams(game),
    ...params,
  }..removeWhere((_, v) => v == null || (v is String && v.trim().isEmpty));

  return SpaceShortcut.draft(
    kind: SpaceShortcutKind.game,
    targetId: targetId,
    title:
        '${_surname(game.whitePlayer.name)} – ${_surname(game.blackPlayer.name)}',
    subtitle: subtitle ?? _defaultSubtitle(game, gamebaseBacked),
    params: merged,
  );
}

bool _isDeepLinkable(GamesTourModel game, String id) {
  if (id.isEmpty || id == 'unknown' || id.startsWith('saved_analysis_')) {
    return false;
  }
  return switch (game.source) {
    GameSource.boardEditor || GameSource.localAnalysis => false,
    // A saved analysis only points back at a game through its source id; its
    // own id is a library row, not something a game route can open.
    GameSource.savedAnalysis => game.sourceGameId?.trim().isNotEmpty == true,
    _ => true,
  };
}

/// "Carlsen, Magnus" and "Magnus Carlsen" both read "Carlsen". A trailing
/// initial ("Praggnanandhaa R") keeps the name instead of the initial.
String _surname(String name) {
  final trimmed = name.trim();
  if (trimmed.isEmpty) return '?';
  final comma = trimmed.indexOf(',');
  if (comma > 0) return trimmed.substring(0, comma).trim();
  final tokens = trimmed.split(RegExp(r'\s+'));
  if (tokens.length == 1) return tokens.first;
  final last = tokens.last.replaceAll('.', '');
  return last.length <= 2 ? tokens.first : tokens.last;
}

/// Event, then round when the round slug is a real round. Gamebase rows reuse
/// roundSlug for the ECO / format code, so they get the event alone.
String? _defaultSubtitle(GamesTourModel game, bool gamebaseBacked) {
  final event = StringUtils.titleFromSlugOrName(game.tourSlug ?? '');
  final roundSlug = game.roundSlug?.trim() ?? '';
  final round = !gamebaseBacked && roundSlug.isNotEmpty
      ? StringUtils.formatRoundLabel(roundSlug)
      : '';
  final parts = [event, round].where((s) => s.isNotEmpty);
  return parts.isEmpty ? null : parts.join(' · ');
}
