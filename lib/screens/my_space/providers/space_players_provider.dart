import 'dart:async';

import 'package:chessever2/config/feature_flags.dart';
import 'package:chessever2/providers/auth_state_provider.dart';
import 'package:chessever2/providers/favorite_players_provider.dart';
import 'package:chessever2/repository/favorites/models/favorite_player.dart';
import 'package:chessever2/repository/local_storage/local_storage_repository.dart';
import 'package:chessever2/screens/favorites/tabs/favorites_players_tab.dart'
    show playerPhotoProvider;
import 'package:chessever2/screens/my_space/models/space_shortcut.dart';
import 'package:chessever2/screens/my_space/providers/space_auto_provider.dart';
import 'package:chessever2/screens/my_space/providers/space_hub_providers.dart'
    show SpaceIds;
import 'package:chessever2/screens/my_space/providers/space_shortcuts_provider.dart';
import 'package:chessever2/screens/my_space/widgets/space_player_strip.dart'
    show spacePinFideId;
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

// My Space's Players: the players the user follows, shown by default, plus
// any player they pinned, most recently visited first. It is not Favorites:
// taking a player out of My Space hides them here only (on this device, per
// account) and never unfollows them.

/// Who a player is across Favorites and My Space pins, the same way a
/// player's pin is keyed ([spacePlayerTargetId]): the FIDE id when there is
/// one, else the game database's id for the player (a memorial or
/// TWIC-only player), else the name, lower-cased.
String spacePlayerIdentity({
  int? fideId,
  String? gamebaseId,
  required String name,
}) {
  if (fideId != null && fideId > 0) return 'fide:$fideId';
  final gamebase = gamebaseId?.trim() ?? '';
  if (gamebase.isNotEmpty) return 'gamebase:$gamebase';
  return 'name:${name.trim().toLowerCase()}';
}

String? _gamebaseOf(Map<String, dynamic> params) {
  final raw = params['gamebasePlayerId']?.toString().trim() ?? '';
  return raw.isEmpty ? null : raw;
}

int? _fideOf(SpaceShortcut s) => spacePinFideId(s);

String _nameOf(SpaceShortcut s) {
  final raw = s.params['playerName'];
  return raw is String && raw.trim().isNotEmpty ? raw : s.title;
}

/// [spacePlayerIdentity] of a player or player-games pin (or draft).
String spacePlayerIdentityOf(SpaceShortcut s) => spacePlayerIdentity(
  fideId: _fideOf(s),
  gamebaseId: _gamebaseOf(s.params),
  name: _nameOf(s),
);

/// [spacePlayerIdentity] of a followed player.
String spaceFavoriteIdentity(FavoritePlayer f) => spacePlayerIdentity(
  fideId: int.tryParse(f.fideId ?? ''),
  gamebaseId: _gamebaseOf(f.metadata),
  name: f.playerName,
);

/// Whether [s] is a person's pin (a face that can come from Favorites too),
/// rather than a Countrymen flag or a streak card.
bool spaceIsPersonPin(SpaceShortcut s) =>
    s.kind == SpaceShortcutKind.player || s.kind == SpaceShortcutKind.playerGames;

/// The key a followed player is hidden from My Space under. It names the
/// follow itself (its row), so following the player again after unfollowing
/// makes a new follow that shows again, with nothing to clear.
String spaceHiddenFavoriteKey(FavoritePlayer f) =>
    'space_player:${spaceFavoriteIdentity(f)}@${f.id}';

/// One face of My Space's Players.
@immutable
class SpacePlayerEntry {
  const SpacePlayerEntry({
    required this.identity,
    required this.shortcut,
    this.pins = const [],
    this.favorite,
    this.visitedAt,
  });

  /// [spacePlayerIdentity] for a person; the pin's key for a Countrymen
  /// flag or a streak card.
  final String identity;

  /// What the face draws and opens: the pin when there is one, else the
  /// follow as the shortcut its own Add to My Space would save.
  final SpaceShortcut shortcut;

  /// Every pin behind the face (a player pin and a player-games pin of the
  /// same player share one face). Removing the face removes them all.
  final List<SpaceShortcut> pins;

  /// The follow behind the face, when the user follows the player.
  final FavoritePlayer? favorite;

  /// When the user last opened the player from My Space.
  final DateTime? visitedAt;

  bool get isPerson => spaceIsPersonPin(shortcut);

  /// The FIDE id the face stands for, if any.
  int? get fideId =>
      isPerson ? _fideOf(shortcut) : null;
}

/// My Space's Players, in the order the page shows them: every followed
/// player not hidden here, and every player pin (one face per player, by
/// FIDE id or name), the most recently visited first and the rest in
/// Favorites' order (pinned players nobody follows after them); then the
/// Countrymen flags (and streak cards, while streaks show) in store order.
List<SpacePlayerEntry> spaceComposePlayers({
  required List<SpaceShortcut> pins,
  required List<FavoritePlayer> favorites,
  required Set<String> hidden,
  required Map<String, int> visits,
}) {
  final pinsByPlayer = <String, List<SpaceShortcut>>{};
  final pinOrder = <String>[];
  final others = <SpaceShortcut>[];
  for (final s in pins) {
    if (s.section != SpaceSection.players) continue;
    if (s.kind == SpaceShortcutKind.streak && !FeatureFlags.streaks) continue;
    if (!spaceIsPersonPin(s)) {
      others.add(s);
      continue;
    }
    final id = spacePlayerIdentityOf(s);
    final list = pinsByPlayer.putIfAbsent(id, () {
      pinOrder.add(id);
      return <SpaceShortcut>[];
    });
    list.add(s);
  }

  DateTime? visitOf(String id, List<SpaceShortcut> pins) {
    DateTime? at;
    final ms = visits[id];
    if (ms != null) at = DateTime.fromMillisecondsSinceEpoch(ms);
    for (final p in pins) {
      final opened = p.lastOpenedAt;
      if (opened != null && (at == null || opened.isAfter(at))) at = opened;
    }
    return at;
  }

  // The face draws the pin a player was saved with (a player pin before a
  // player-games one); a follow alone draws as its own draft.
  SpaceShortcut faceOf(List<SpaceShortcut> pins) =>
      pins.firstWhere(
        (p) => p.kind == SpaceShortcutKind.player,
        orElse: () => pins.first,
      );

  final base = <SpacePlayerEntry>[];
  final seen = <String>{};
  for (final f in favorites) {
    final id = spaceFavoriteIdentity(f);
    if (!seen.add(id)) continue;
    final held = pinsByPlayer[id] ?? const <SpaceShortcut>[];
    // A hidden follow stays hidden unless the player was pinned again.
    if (held.isEmpty && hidden.contains(spaceHiddenFavoriteKey(f))) continue;
    base.add(
      SpacePlayerEntry(
        identity: id,
        shortcut: held.isEmpty ? spaceFavoriteDraft(f) : faceOf(held),
        pins: held,
        favorite: f,
        visitedAt: visitOf(id, held),
      ),
    );
  }
  for (final id in pinOrder) {
    if (!seen.add(id)) continue;
    final held = pinsByPlayer[id]!;
    base.add(
      SpacePlayerEntry(
        identity: id,
        shortcut: faceOf(held),
        pins: held,
        visitedAt: visitOf(id, held),
      ),
    );
  }

  final visited = [
    for (final e in base)
      if (e.visitedAt != null) e,
  ];
  // List.sort is not stable; the base index breaks ties.
  final place = {for (final (i, e) in base.indexed) e.identity: i};
  visited.sort((a, b) {
    final by = b.visitedAt!.compareTo(a.visitedAt!);
    return by != 0 ? by : place[a.identity]!.compareTo(place[b.identity]!);
  });
  return [
    ...visited,
    for (final e in base)
      if (e.visitedAt == null) e,
    for (final s in others)
      SpacePlayerEntry(identity: s.key, shortcut: s, pins: [s]),
  ];
}

/// My Space's Players ([spaceComposePlayers]). Null until the saved list is
/// known; the follows join as soon as they load (a failed read adds none).
final spacePlayersProvider = Provider.autoDispose<List<SpacePlayerEntry>?>((
  ref,
) {
  final saved = ref.watch(spaceShortcutsProvider);
  final pins = saved.valueOrNull;
  if (pins == null && !saved.hasError) return null;
  final favorites =
      ref.watch(favoritePlayersProviderNew).valueOrNull ??
      const <FavoritePlayer>[];
  return spaceComposePlayers(
    pins: pins ?? const [],
    favorites: favorites,
    hidden: ref.watch(spaceHiddenAutoKeysProvider),
    visits: ref.watch(spacePlayerVisitsProvider),
  );
});

/// Whether the player [identity] names shows in My Space's Players: pinned,
/// or followed and not hidden here. What the add sheet's player rows mark.
final spacePlayerShownProvider = Provider.autoDispose.family<bool, String>((
  ref,
  identity,
) {
  final players = ref.watch(spacePlayersProvider) ?? const [];
  return players.any((e) => e.identity == identity);
});

/// The follow of the player [identity] names among [favorites], if any.
FavoritePlayer? spaceFollowOf(List<FavoritePlayer> favorites, String identity) {
  for (final f in favorites) {
    if (spaceFavoriteIdentity(f) == identity) return f;
  }
  return null;
}

/// The target of a player pin's [key] (`player:<FIDE id or name>`), or null
/// for any other kind of pin.
String? spacePlayerPinTarget(String key) {
  final prefix = '${SpaceShortcutKind.player.name}:';
  return key.startsWith(prefix) ? key.substring(prefix.length) : null;
}

/// The follow of the player a player pin's [key] names, if the user follows
/// them: the follow whose own Add to My Space saves that very key (keyed on
/// its FIDE id, else its game database id, else its name), else a follow
/// with no FIDE id or game database id whose name is the key's, in any
/// case.
FavoritePlayer? spaceFollowOfPinKey(List<FavoritePlayer> favorites, String key) {
  final target = spacePlayerPinTarget(key);
  if (target == null || favorites.isEmpty) return null;
  for (final f in favorites) {
    if (spaceFavoriteDraft(f).key == key) return f;
  }
  return spaceFollowOf(favorites, spacePlayerIdentity(name: target));
}

/// Whether the player a player pin's [key] names shows in My Space's
/// Players by default: the user follows them and has not taken them out of
/// My Space here. False for any other key. With the pin itself, this is
/// what "in My Space" means for a player everywhere in the app
/// ([spaceShortcutExistsProvider]), so every menu's label and action agree
/// with the faces My Space shows.
final spaceFollowShownProvider = Provider.autoDispose.family<bool, String>((
  ref,
  key,
) {
  if (spacePlayerPinTarget(key) == null) return false;
  final favorites =
      ref.watch(favoritePlayersProviderNew).valueOrNull ??
      const <FavoritePlayer>[];
  final follow = spaceFollowOfPinKey(favorites, key);
  if (follow == null) return false;
  return !ref
      .watch(spaceHiddenAutoKeysProvider)
      .contains(spaceHiddenFavoriteKey(follow));
});

/// Whether [draft] is in My Space, as the add sheet marks its row: a player
/// by whether My Space's Players show them (pinned, or followed and not
/// hidden), anything else by its pin.
bool watchSpaceDraftAdded(WidgetRef ref, SpaceShortcut draft) {
  if (draft.kind == SpaceShortcutKind.player) {
    return ref.watch(spacePlayerShownProvider(spacePlayerIdentityOf(draft)));
  }
  return ref.watch(spaceShortcutExistsProvider(draft.key));
}

/// Asks for the photos of one page of faces together, as the page is asked
/// for, and keeps them while the page shows. Each face still watches its
/// own [playerPhotoProvider], so a photo shows the moment it lands rather
/// than waiting on the slowest of the page, and a photo already known is
/// never asked for again.
///
/// There is no batch photo endpoint: each FIDE id not yet known is still
/// its own `fetch-fide-photo-webp` call. What the page gives is that they
/// all start at once, ahead of the faces scrolling in.
final spacePlayerPhotosProvider = Provider.autoDispose.family<void, SpaceIds>((
  ref,
  ids,
) {
  for (final id in ids.ids) {
    final fide = int.tryParse(id);
    if (fide == null) continue;
    // Listened, not watched: a photo landing never rebuilds the rail.
    ref.listen(playerPhotoProvider(fide), (_, __) {});
  }
});

// ------------------------------------------------------------------ visits

/// When the user last opened each player from My Space, by
/// [spacePlayerIdentity], in milliseconds since the epoch: on this device,
/// per account, like the hidden suggestions. Pins also keep their own
/// `lastOpenedAt`; the later of the two counts.
final spacePlayerVisitsProvider =
    NotifierProvider<SpacePlayerVisits, Map<String, int>>(
      SpacePlayerVisits.new,
    );

class SpacePlayerVisits extends Notifier<Map<String, int>> {
  static const _prefix = 'my_space_player_visits_v1:';

  /// The most visits kept; the oldest go first.
  static const int keep = 200;

  String? _userId;

  String get _storageKey => '$_prefix${_userId ?? 'guest'}';

  @override
  Map<String, int> build() {
    _userId = ref.watch(currentUserProvider.select((u) => u?.id));
    try {
      final stored = SharedPreferencesService.instance.prefsOrNull
          ?.getStringList(_storageKey);
      if (stored == null) return const <String, int>{};
      return {
        for (final line in stored)
          if (line.lastIndexOf('\t') case final at when at > 0)
            if (int.tryParse(line.substring(at + 1)) case final ms?)
              line.substring(0, at): ms,
      };
    } catch (_) {
      return const <String, int>{};
    }
  }

  /// Records a visit to [identity] now (or at [at]).
  void visit(String identity, {DateTime? at}) {
    final ms = (at ?? DateTime.now()).millisecondsSinceEpoch;
    final next = {...state, identity: ms};
    if (next.length > keep) {
      final oldest = next.entries.toList()
        ..sort((a, b) => a.value.compareTo(b.value));
      for (final e in oldest.take(next.length - keep)) {
        next.remove(e.key);
      }
    }
    state = next;
    unawaited(_persist());
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferencesService.instance.ensureInitialized();
      await prefs?.setStringList(_storageKey, [
        for (final e in state.entries) '${e.key}\t${e.value}',
      ]);
    } catch (e) {
      debugPrint('[MySpace] player visits not saved: $e');
    }
  }
}
