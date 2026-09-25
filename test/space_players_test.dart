import 'package:chessever2/providers/auth_state_provider.dart';
import 'package:chessever2/providers/favorite_players_provider.dart';
import 'package:chessever2/repository/favorites/models/favorite_player.dart';
import 'package:chessever2/screens/library/widgets/library_context_menu.dart';
import 'package:chessever2/screens/my_space/actions/space_menu_action.dart';
import 'package:chessever2/screens/my_space/models/space_shortcut.dart';
import 'package:chessever2/screens/my_space/providers/space_auto_provider.dart';
import 'package:chessever2/screens/my_space/providers/space_players_provider.dart';
import 'package:chessever2/screens/my_space/providers/space_shortcuts_provider.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/space_shortcut_drafts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Pins in memory.
class _Store extends SpaceShortcutsNotifier {
  _Store([this.seed = const []]);

  final List<SpaceShortcut> seed;

  List<SpaceShortcut> get _list => state.valueOrNull ?? const [];

  @override
  Future<List<SpaceShortcut>> build() async => seed;

  @override
  Future<bool> add(SpaceShortcut draft) async {
    if (_list.any((s) => s.key == draft.key)) return false;
    state = AsyncData([draft, ..._list]);
    return true;
  }

  @override
  Future<SpaceShortcut?> removeTarget(
    SpaceShortcutKind kind,
    String targetId,
  ) async {
    final key = SpaceShortcut.keyFor(kind, targetId);
    final hit = _list.where((s) => s.key == key).firstOrNull;
    state = AsyncData([
      for (final s in _list)
        if (s.key != key) s,
    ]);
    return hit;
  }

  @override
  Future<void> restore(SpaceShortcut item) async {
    state = AsyncData([item, ..._list]);
  }

  @override
  Future<void> markOpened(String id) async {}
}

/// Hidden keys in memory.
class _Hidden extends SpaceHiddenAutoKeys {
  @override
  Set<String> build() => const <String>{};

  @override
  void hide(String key) => state = {...state, key};

  @override
  void unhide(String key) => state = {...state}..remove(key);
}

/// The follows, and a tally of every write that would unfollow one.
class _Favorites extends FavoritePlayersNotifierNew {
  _Favorites(this.seed);

  final List<FavoritePlayer> seed;
  int writes = 0;

  @override
  Future<List<FavoritePlayer>> build() async => seed;

  @override
  Future<void> removeFavorite(
    String playerName, {
    String? fideId,
    String? memorialSourceIdentity,
  }) async => writes++;

  @override
  Future<bool> toggleFavorite({
    String? fideId,
    required String playerName,
    String? countryCode,
    int? rating,
    String? title,
    String? gamebasePlayerId,
    String? memorialSourceIdentity,
    String? memorialRouteId,
  }) async {
    writes++;
    return false;
  }
}

class _Visits extends SpacePlayerVisits {
  @override
  Map<String, int> build() => const <String, int>{};
}

FavoritePlayer _follow(String name, int? fide, {String? id}) => FavoritePlayer(
  id: id ?? 'fav-${fide ?? name}',
  userId: 'u1',
  fideId: fide == null ? null : '$fide',
  playerName: name,
  metadata: const {'title': 'GM'},
  createdAt: DateTime(2026, 7, 1),
  updatedAt: DateTime(2026, 7, 1),
);

SpaceShortcut _pin(
  SpaceShortcut draft,
  String id, {
  DateTime? openedAt,
}) => SpaceShortcut(
  id: id,
  kind: draft.kind,
  targetId: draft.targetId,
  title: draft.title,
  subtitle: draft.subtitle,
  params: draft.params,
  sortIndex: 1,
  createdAt: DateTime(2026, 9, 1),
  lastOpenedAt: openedAt,
);

SpaceShortcut _playerPin(String name, int fide, String id, {DateTime? at}) =>
    _pin(spacePlayerDraft(playerName: name, fideId: fide), id, openedAt: at);

List<String> _names(List<SpacePlayerEntry> entries) => [
  for (final e in entries) e.shortcut.title,
];

void main() {
  final carlsen = _follow('Carlsen, Magnus', 1503014);
  final gukesh = _follow('Gukesh D', 46616543);
  final pragg = _follow('Praggnanandhaa R', 25059530);

  test('with nothing pinned, the followed players are the group, in '
      'Favorites\' order', () {
    final players = spaceComposePlayers(
      pins: const [],
      favorites: [carlsen, gukesh, pragg],
      hidden: const {},
      visits: const {},
    );
    expect(_names(players), [
      'Carlsen, Magnus',
      'Gukesh D',
      'Praggnanandhaa R',
    ]);
    expect(players.every((e) => e.favorite != null && e.pins.isEmpty), isTrue);
  });

  test('a player both followed and pinned is one face, by FIDE id', () {
    final pin = _playerPin('Magnus Carlsen', 1503014, 'p1');
    final players = spaceComposePlayers(
      pins: [pin],
      favorites: [carlsen],
      hidden: const {},
      visits: const {},
    );
    expect(players, hasLength(1));
    expect(players.single.favorite, carlsen);
    expect(players.single.pins, [pin]);
    // The face draws the pin the player was saved with.
    expect(players.single.shortcut.id, 'p1');
  });

  test('hiding a followed player takes it off My Space only; following it '
      'again (a new follow) shows it again; a pin always shows', () {
    final hidden = {spaceHiddenFavoriteKey(gukesh)};
    expect(
      _names(
        spaceComposePlayers(
          pins: const [],
          favorites: [carlsen, gukesh],
          hidden: hidden,
          visits: const {},
        ),
      ),
      ['Carlsen, Magnus'],
    );
    // Unfollowed and followed again: a new follow row, not the hidden one.
    final again = _follow('Gukesh D', 46616543, id: 'fav-new');
    expect(
      _names(
        spaceComposePlayers(
          pins: const [],
          favorites: [carlsen, again],
          hidden: hidden,
          visits: const {},
        ),
      ),
      ['Carlsen, Magnus', 'Gukesh D'],
    );
    // Pinned from elsewhere: shown, whatever was hidden.
    expect(
      spaceComposePlayers(
        pins: [_playerPin('Gukesh D', 46616543, 'p2')],
        favorites: [carlsen, gukesh],
        hidden: hidden,
        visits: const {},
      ),
      hasLength(2),
    );
  });

  test('the most recently visited lead (a follow\'s visit or a pin\'s own '
      'last open, whichever is later); the rest keep Favorites\' order, '
      'pinned-only players after them, Countrymen last', () {
    final pinnedOnly = _playerPin('Firouzja, Alireza', 12573981, 'p3');
    final opened = _playerPin(
      'Praggnanandhaa R',
      25059530,
      'p4',
      at: DateTime(2026, 9, 25, 12),
    );
    final india = _pin(spaceCountrymenDraft('IN')!, 'c1');
    final players = spaceComposePlayers(
      pins: [india, pinnedOnly, opened],
      favorites: [carlsen, gukesh, pragg],
      hidden: const {},
      visits: {
        spacePlayerIdentity(fideId: 46616543, name: 'Gukesh D'): DateTime(
          2026,
          9,
          25,
          9,
        ).millisecondsSinceEpoch,
      },
    );
    expect(_names(players), [
      'Praggnanandhaa R',
      'Gukesh D',
      'Carlsen, Magnus',
      'Firouzja, Alireza',
      india.title,
    ]);
    expect(players.last.isPerson, isFalse);
  });

  test('a player without a FIDE id is known by name, any case', () {
    expect(
      spacePlayerIdentity(fideId: null, name: ' Hikaru  '),
      spacePlayerIdentity(fideId: 0, name: 'hikaru'),
    );
    final players = spaceComposePlayers(
      pins: [
        _pin(spacePlayerDraft(playerName: 'Local Hero'), 'p5'),
      ],
      favorites: [_follow('local hero', null)],
      hidden: const {},
      visits: const {},
    );
    expect(players, hasLength(1));
  });

  test('a player with a game database id and no FIDE id is known by that '
      'id, however their name is spelled, and one face', () {
    final tal = FavoritePlayer(
      id: 'fav-tal',
      userId: 'u1',
      playerName: 'Tal, Mikhail',
      metadata: const {'gamebasePlayerId': 'gb-tal-1'},
      createdAt: DateTime(2026, 7, 1),
      updatedAt: DateTime(2026, 7, 1),
    );
    final pin = _pin(
      spacePlayerDraft(playerName: 'Mikhail Tal', gamebasePlayerId: 'gb-tal-1'),
      'p-tal',
    );
    expect(spaceFavoriteIdentity(tal), spacePlayerIdentityOf(pin));
    expect(spaceFavoriteIdentity(tal), 'gamebase:gb-tal-1');
    final players = spaceComposePlayers(
      pins: [pin],
      favorites: [tal],
      hidden: const {},
      visits: const {},
    );
    expect(players, hasLength(1));
    expect(players.single.favorite, tal);
    expect(players.single.pins, [pin]);
    // The follow's own Add to My Space saves the key its face answers to.
    expect(spaceFollowOfPinKey([tal], spaceFavoriteDraft(tal).key), tal);
    // A numeric game database id is not a FIDE id.
    final numeric = spacePlayerDraft(
      playerName: 'Botvinnik, Mikhail',
      gamebasePlayerId: '12345',
    );
    expect(spacePlayerIdentityOf(numeric), 'gamebase:12345');
  });

  group('the app-wide My Space row for a player', () {
    late WidgetRef hostRef;
    late BuildContext hostContext;
    late ProviderContainer container;

    Future<(_Store, _Favorites)> pump(
      WidgetTester tester, {
      List<SpaceShortcut> pins = const [],
      required List<FavoritePlayer> follows,
    }) async {
      final store = _Store(pins);
      final favorites = _Favorites(follows);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            spaceShortcutsProvider.overrideWith(() => store),
            favoritePlayersProviderNew.overrideWith(() => favorites),
            spaceHiddenAutoKeysProvider.overrideWith(_Hidden.new),
            spacePlayerVisitsProvider.overrideWith(_Visits.new),
            currentUserProvider.overrideWithValue(null),
          ],
          child: MaterialApp(
            theme: AppTheme.darkTheme,
            home: Scaffold(
              body: Consumer(
                builder: (context, ref, _) {
                  ResponsiveHelper.init(context);
                  hostRef = ref;
                  hostContext = context;
                  // Keeps the reads warm, as a host watching them would.
                  ref.watch(favoritePlayersProviderNew);
                  ref.watch(spacePlayersProvider);
                  return const SizedBox();
                },
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      container = ProviderScope.containerOf(hostContext);
      return (store, favorites);
    }

    LibraryMenuAction row(SpaceShortcut draft) =>
        spaceMenuAction(context: hostContext, ref: hostRef, draft: draft);

    Future<void> run(WidgetTester tester, LibraryMenuAction action) async {
      await action.onSelected();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
    }

    SpaceShortcut draftOf(FavoritePlayer f) => spacePlayerDraft(
      playerName: f.playerName,
      fideId: int.parse(f.fideId!),
    );

    List<String> shown() => [
      for (final e in container.read(spacePlayersProvider) ?? const [])
        e.shortcut.title,
    ];

    testWidgets('a followed player already shows, so the row offers Remove, '
        'which hides the follow here and never unfollows; Add brings the '
        'follow back without a pin', (tester) async {
      final (store, favorites) = await pump(
        tester,
        follows: [carlsen, gukesh],
      );
      final draft = draftOf(gukesh);
      expect(container.read(spaceShortcutExistsProvider(draft.key)), isTrue);
      final remove = row(draft);
      expect(remove.label, 'Remove from My Space');

      await run(tester, remove);
      expect(shown(), ['Carlsen, Magnus']);
      expect(container.read(spaceShortcutExistsProvider(draft.key)), isFalse);
      expect(favorites.writes, 0);
      expect(find.text('Removed from My Space'), findsOneWidget);

      final add = row(draft);
      expect(add.label, 'Add to My Space');
      await run(tester, add);
      expect(shown(), ['Carlsen, Magnus', 'Gukesh D']);
      // Back as the follow it is: nothing was pinned.
      expect(store.state.valueOrNull, isEmpty);
      expect(favorites.writes, 0);
      await tester.pump(const Duration(seconds: 10));
    });

    testWidgets('a player both followed and pinned leaves My Space whole: '
        'the pin goes and the follow is hidden; Undo brings both back', (
      tester,
    ) async {
      final pin = _playerPin('Gukesh D', 46616543, 'p1');
      final (store, favorites) = await pump(
        tester,
        pins: [pin],
        follows: [carlsen, gukesh],
      );
      await run(tester, row(draftOf(gukesh)));
      expect(shown(), ['Carlsen, Magnus']);
      expect(store.state.valueOrNull, isEmpty);
      expect(favorites.writes, 0);

      // The snack slides in, then its Undo answers.
      await tester.pump(const Duration(milliseconds: 600));
      await tester.tap(find.text('Undo'));
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(shown(), ['Carlsen, Magnus', 'Gukesh D']);
      expect(store.state.valueOrNull, [pin]);
      await tester.pump(const Duration(seconds: 10));
    });

    testWidgets('a followed player known only by a game database id shows, '
        'and the row offers Remove, which hides the face', (tester) async {
      final tal = FavoritePlayer(
        id: 'fav-tal',
        userId: 'u1',
        playerName: 'Tal, Mikhail',
        metadata: const {'gamebasePlayerId': 'gb-tal-1'},
        createdAt: DateTime(2026, 7, 1),
        updatedAt: DateTime(2026, 7, 1),
      );
      final (store, favorites) = await pump(tester, follows: [carlsen, tal]);
      final draft = spaceFavoriteDraft(tal);
      expect(draft.key, 'player:gb-tal-1');
      expect(shown(), ['Carlsen, Magnus', 'Tal, Mikhail']);
      expect(container.read(spaceShortcutExistsProvider(draft.key)), isTrue);
      final remove = row(draft);
      expect(remove.label, 'Remove from My Space');
      await run(tester, remove);
      expect(shown(), ['Carlsen, Magnus']);
      expect(store.state.valueOrNull, isEmpty);
      expect(favorites.writes, 0);
      expect(row(draft).label, 'Add to My Space');
      await tester.pump(const Duration(seconds: 10));
    });

    testWidgets('a player nobody follows is a pin like any other', (
      tester,
    ) async {
      final (store, _) = await pump(tester, follows: [carlsen]);
      final draft = draftOf(pragg);
      expect(row(draft).label, 'Add to My Space');
      await run(tester, row(draft));
      expect(store.state.valueOrNull?.map((s) => s.key), [draft.key]);
      expect(shown(), ['Carlsen, Magnus', 'Praggnanandhaa R']);
      expect(row(draft).label, 'Remove from My Space');
      await run(tester, row(draft));
      expect(store.state.valueOrNull, isEmpty);
      expect(shown(), ['Carlsen, Magnus']);
      await tester.pump(const Duration(seconds: 10));
    });
  });
}
