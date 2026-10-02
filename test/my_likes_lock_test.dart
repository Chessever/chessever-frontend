import 'dart:math' as math;

import 'package:chessever2/providers/auth_state_provider.dart';
import 'package:chessever2/repository/authentication/model/app_user.dart';
import 'package:chessever2/repository/library/library_repository.dart';
import 'package:chessever2/repository/library/models/library_folder.dart';
import 'package:chessever2/repository/library/models/saved_analysis.dart';
import 'package:chessever2/revenue_cat_service/subscribe_state.dart';
import 'package:chessever2/screens/chessboard/analysis/chess_game.dart';
import 'package:chessever2/screens/library/utils/load_saved_analysis.dart';
import 'package:chessever2/screens/for_you/discovery/widgets/discovery_common.dart';
import 'package:chessever2/screens/my_likes/provider/my_likes_provider.dart';
import 'package:chessever2/screens/my_likes/widgets/my_likes_game_card.dart';
import 'package:chessever2/screens/my_space/models/space_shortcut.dart';
import 'package:chessever2/screens/my_space/providers/space_shortcuts_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/game_filter/game_filter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _pgn = '''
[Event "Test"]
[Site "?"]
[Date "2026.01.01"]
[Round "1"]
[White "White"]
[Black "Black"]
[Result "*"]

1. e4 e5 *
''';

final _base = DateTime.utc(2026, 9, 1, 12);

/// Like number [n]: a bigger n was liked later (n minutes after [_base]).
SavedAnalysis _like(int n, {String? id, List<String> tags = const []}) {
  final at = _base.add(Duration(minutes: n));
  return SavedAnalysis(
    id: id ?? 'like-${n.toString().padLeft(3, '0')}',
    userId: 'user-1',
    folderId: 'liked-folder',
    title: 'Game $n',
    sourceGameId: 'game-$n',
    chessGame: ChessGame.fromPgn('game-$n', _pgn),
    analysisState: const {},
    variationComments: const {},
    lastViewedPosition: -1,
    tags: tags,
    isFavorite: false,
    createdAt: at,
    updatedAt: at,
  );
}

/// Likes 1..count, newest first (the server's default order).
List<SavedAnalysis> _likes(int count) => [
  for (var n = count; n >= 1; n--) _like(n),
];

List<String> _ids(Iterable<SavedAnalysis> likes) =>
    likes.map((a) => a.id).toList();

void main() {
  group('free window: latest $kFreeMyLikesVisibleLimit likes', () {
    test('keeps the 20 most recently liked, whatever the input order', () {
      final shuffled = _likes(25).reversed.toList()..shuffle();
      final window = freeVisibleLikeIds(shuffled);

      expect(window, hasLength(20));
      expect(window, containsAll(_ids(_likes(25).take(20))));
      // Likes 1..5 are the oldest and fall outside.
      for (var n = 1; n <= 5; n++) {
        expect(window.contains(_like(n).id), isFalse, reason: 'like $n');
      }
    });

    test('fewer likes than the limit are all inside', () {
      expect(freeVisibleLikeIds(_likes(7)), hasLength(7));
    });

    test('a tie on like time breaks on id, deterministically', () {
      final tied = [
        for (var i = 0; i < 21; i++)
          _like(1, id: 'tie-${i.toString().padLeft(2, '0')}'),
      ];
      final a = freeVisibleLikeIds(tied);
      final b = freeVisibleLikeIds(tied.reversed);
      expect(a, b);
      expect(a.contains('tie-00'), isFalse);
    });

    test('an unlimited user has no window', () {
      final likes = _likes(30);
      expect(freeLikesWindow(likes, unlimited: true), isNull);
      expect(freeLikesWindow(likes, unlimited: false), hasLength(20));
    });

    test('isLikedGameLocked only locks outside a window', () {
      final window = freeVisibleLikeIds(_likes(25));
      expect(isLikedGameLocked(_like(25).id, window: window), isFalse);
      expect(isLikedGameLocked(_like(3).id, window: window), isTrue);
      expect(isLikedGameLocked(_like(3).id, window: null), isFalse);
    });
  });

  group('buildMyLikesData', () {
    List<MyLikesEntry> listed(MyLikesData data) => [
      for (final s in data.sections) ...s.value,
    ];

    test('free: every like listed, the latest 20 open, the rest locked', () {
      final likes = _likes(25);
      final data = buildMyLikesData(
        matches: likes,
        totalLiked: 25,
        window: freeVisibleLikeIds(likes),
      );

      // The same list a Premium account sees.
      expect(data.visibleCount, 25);
      expect(_ids(listed(data).map((e) => e.analysis)), _ids(likes));
      // Only the lock differs, and the board swipes the open ones.
      expect(_ids(data.openableAnalyses), _ids(likes.take(20)));
      expect(
        _ids(listed(data).where((e) => e.isLocked).map((e) => e.analysis)),
        _ids(likes.skip(20)),
      );
      expect(data.hasNoMatches, isFalse);
    });

    test('premium sees everything, nothing locked', () {
      final likes = _likes(25);
      final data = buildMyLikesData(
        matches: likes,
        totalLiked: 25,
        window: null,
      );
      expect(data.visibleCount, 25);
      expect(data.openableAnalyses, hasLength(25));
      expect(listed(data).any((e) => e.isLocked), isFalse);
    });

    test('free with 20 or fewer likes has nothing locked', () {
      final likes = _likes(20);
      final data = buildMyLikesData(
        matches: likes,
        totalLiked: 20,
        window: freeVisibleLikeIds(likes),
      );
      expect(data.visibleCount, 20);
      expect(listed(data).any((e) => e.isLocked), isFalse);
    });

    test('a search lists its matches inside and past the window', () {
      final all = _likes(25);
      final window = freeVisibleLikeIds(all);
      // Two recent matches, three older ones.
      final matches = [_like(24), _like(22), _like(5), _like(3), _like(1)];
      final data = buildMyLikesData(
        matches: matches,
        totalLiked: 25,
        window: window,
        isNarrowed: true,
      );
      expect(data.visibleCount, 5);
      expect(_ids(listed(data).map((e) => e.analysis)), _ids(matches));
      expect(_ids(data.openableAnalyses), [_like(24).id, _like(22).id]);
      expect(data.hasNoMatches, isFalse);
    });

    test('a search that only hits older likes still lists them', () {
      final window = freeVisibleLikeIds(_likes(25));
      final data = buildMyLikesData(
        matches: [_like(4), _like(2)],
        totalLiked: 25,
        window: window,
        isNarrowed: true,
      );
      expect(data.visibleCount, 2);
      expect(listed(data).every((e) => e.isLocked), isTrue);
      expect(data.openableAnalyses, isEmpty);
      expect(data.hasNoMatches, isFalse);
    });

    test('a search with no hits anywhere is "no matches"', () {
      final data = buildMyLikesData(
        matches: const [],
        totalLiked: 25,
        window: freeVisibleLikeIds(_likes(25)),
        isNarrowed: true,
      );
      expect(data.hasNoMatches, isTrue);
    });

    test('a sorted list keeps one bucket in the server order', () {
      final all = _likes(22);
      final window = freeVisibleLikeIds(all);
      // Server sort order, unrelated to like time.
      final sorted = [_like(1), _like(12), _like(2), _like(20)];
      final data = buildMyLikesData(
        matches: sorted,
        totalLiked: 22,
        window: window,
        isSorted: true,
      );
      expect(data.sections.single.key, '__sorted__');
      expect(
        _ids(data.sections.single.value.map((e) => e.analysis)),
        _ids(sorted),
      );
      expect(_ids(data.openableAnalyses), [_like(12).id, _like(20).id]);
    });
  });

  group('locked like card', () {
    // A finished game, so the card draws a result rather than a live eval bar.
    final like = _like(3, tags: const ['Trap']);
    final game = savedAnalysisToCardGame(
      like,
    ).copyWith(gameStatus: GameStatus.whiteWins);

    Future<int Function()> pumpCard(
      WidgetTester tester, {
      required bool locked,
      double width = 390,
    }) async {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      var opens = 0;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [spaceShortcutsProvider.overrideWith(_NoShortcuts.new)],
          child: MaterialApp(
            theme: AppTheme.darkTheme,
            home: Builder(
              builder: (context) {
                ResponsiveHelper.init(context);
                return Scaffold(
                  backgroundColor: context.colors.background,
                  body: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: MyLikesGameCard(
                        analysis: like,
                        game: game,
                        isLocked: locked,
                        onOpen: () => opens++,
                        onRemove: () async {},
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.pump();
      return () => opens;
    }

    for (final width in [320.0, 390.0]) {
      testWidgets('cuts the shared padlock notch clear of every line at '
          '${width.toInt()}pt', (tester) async {
        await pumpCard(tester, locked: true, width: width);

        expect(find.text('PREMIUM'), findsNothing);
        // Tags stay behind the paywall; their slot holds the notch.
        expect(find.text('Trap'), findsNothing);

        final card = tester.getRect(find.byType(MyLikesGameCard));
        final size = math.min(22.w, 22.h);
        final notch = Rect.fromLTRB(
          card.right - size,
          card.bottom - size,
          card.right,
          card.bottom,
        );
        final lock = tester.getRect(find.byType(DiscoveryPadlock));
        expect(lock.center.dx, moreOrLessEquals(notch.center.dx));
        expect(lock.center.dy, moreOrLessEquals(notch.center.dy));

        final lines = find.descendant(
          of: find.byType(MyLikesGameCard),
          matching: find.byType(Text),
        );
        expect(lines, findsWidgets);
        for (final line in tester.widgetList(lines)) {
          final rect = tester.getRect(find.byWidget(line));
          expect(
            rect.overlaps(notch),
            isFalse,
            reason: '"${(line as Text).data}" runs into the notch',
          );
        }
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('an unlocked like keeps its tags and has no lock', (
      tester,
    ) async {
      await pumpCard(tester, locked: false);
      expect(find.text('Trap'), findsOneWidget);
      expect(find.byType(DiscoveryPadlock), findsNothing);
    });

    testWidgets('a tap on the padlock delegates to the parent access gate', (
      tester,
    ) async {
      final opens = await pumpCard(tester, locked: true);
      await tester.tap(find.byType(DiscoveryPadlock));
      await tester.pump(const Duration(milliseconds: 400));
      // The parent callback owns the strict gate for every liked game.
      expect(opens(), 1);
    });

    for (final locked in [false, true]) {
      testWidgets(
        locked
            ? 'a locked like cannot be added to My Space'
            : 'an open like keeps its actions without My Space or share',
        (tester) async {
          await pumpCard(tester, locked: locked);
          await tester.longPress(find.byType(MyLikesGameCard));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 400));

          expect(find.text('Open game'), findsOneWidget);
          expect(find.text('Remove from likes'), findsOneWidget);
          expect(find.text('Add to My Space'), findsNothing);
          expect(find.text('Share game'), findsNothing);
          expect(find.text('Copy PGN'), locked ? findsNothing : findsOneWidget);
        },
      );
    }
  });

  group('My Likes providers', () {
    setUpAll(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues({});
      await Supabase.initialize(
        url: 'https://placeholder.supabase.co',
        publishableKey: 'placeholder-publishable-key',
      );
    });

    test('a refresh in flight keeps the last settled entitlement', () async {
      final subscription = _ControlledSubscription(
        SubscriptionState(isSubscribed: false, isLoading: true),
      );
      final container = ProviderContainer(
        overrides: [subscriptionProvider.overrideWith((ref) => subscription)],
      );
      addTearDown(container.dispose);
      final unlimited = container.listen(myLikesUnlimitedProvider, (_, __) {});
      addTearDown(unlimited.close);

      // Cold start: unknown, so nothing is hidden from a possible subscriber.
      expect(unlimited.read(), isTrue);

      subscription.push(SubscriptionState(isSubscribed: false));
      expect(unlimited.read(), isFalse);

      // App resume refresh: the free list must not swell to full and back.
      subscription.push(
        SubscriptionState(isSubscribed: false, isLoading: true),
      );
      expect(unlimited.read(), isFalse);

      // Purchase: full history immediately.
      subscription.push(SubscriptionState(isSubscribed: true));
      expect(unlimited.read(), isTrue);
      subscription.push(SubscriptionState(isSubscribed: true, isLoading: true));
      expect(unlimited.read(), isTrue);

      // Downgrade: back to the latest 20, nothing deleted.
      subscription.push(SubscriptionState(isSubscribed: false));
      expect(unlimited.read(), isFalse);

      await Future<void>.delayed(const Duration(milliseconds: 50));
    });

    test('a narrowed list takes the window from the latest likes', () async {
      final all = _likes(25);
      final repository = _FakeLikesRepository(all);
      final container = ProviderContainer(
        overrides: [
          currentUserProvider.overrideWithValue(_user),
          libraryRepositoryProvider.overrideWithValue(repository),
          subscriptionProvider.overrideWith((ref) => _FreeSubscription()),
        ],
      );
      addTearDown(container.dispose);
      // Keep the auto-dispose view alive between reads.
      final sub = container.listen(myLikesViewProvider, (_, __) {});
      addTearDown(sub.close);

      final plain = await container.read(myLikesViewProvider.future);
      expect(repository.windowCalls, 0, reason: 'plain list is its own window');
      expect(plain.visibleCount, 25);
      expect(plain.openableAnalyses, hasLength(20));

      container.read(myLikesFilterProvider.notifier).toggleTag('Trap');
      final narrowed = await container.read(myLikesViewProvider.future);
      expect(repository.windowCalls, 1);
      expect(repository.lastWindowLimit, kFreeMyLikesVisibleLimit);
      // Trap is on likes 24 (recent) and 2 (archived).
      expect(_ids(narrowed.openableAnalyses), [_like(24).id]);
      expect(narrowed.visibleCount, 2);

      await Future<void>.delayed(const Duration(milliseconds: 50));
    });

    test('a My Space pin reopens an archived like only for Premium', () async {
      final repository = _FakeLikesRepository(_likes(25));
      ProviderContainer containerFor(SubscriptionNotifier Function() sub) {
        final container = ProviderContainer(
          overrides: [
            currentUserProvider.overrideWithValue(_user),
            libraryRepositoryProvider.overrideWithValue(repository),
            subscriptionProvider.overrideWith((ref) => sub()),
          ],
        );
        addTearDown(container.dispose);
        return container;
      }

      final free = containerFor(_FreeSubscription.new);
      expect(await isArchivedLike(free.read, _like(25)), isFalse);
      // Likes 25..6 are the latest 20.
      expect(await isArchivedLike(free.read, _like(6)), isFalse);
      expect(await isArchivedLike(free.read, _like(5)), isTrue);
      // A game saved to another database is not a like; nothing gates it here.
      expect(
        await isArchivedLike(
          free.read,
          _like(1).copyWith(folderId: 'my-database'),
        ),
        isFalse,
      );

      final premium = containerFor(
        () => _ControlledSubscription(SubscriptionState(isSubscribed: true)),
      );
      expect(await isArchivedLike(premium.read, _like(1)), isFalse);

      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
  });
}

final _user = AppUser(
  id: 'user-1',
  createdAt: DateTime(2026, 1, 1),
  isAnonymous: false,
);

final _folder = LibraryFolder(
  id: 'liked-folder',
  userId: 'user-1',
  name: 'Liked Games',
  color: '#F43F5E',
  icon: 'heart',
  orderIndex: 0,
  createdAt: DateTime(2026, 1, 1),
  updatedAt: DateTime(2026, 1, 1),
  isLikedGames: true,
);

class _FreeSubscription extends SubscriptionNotifier {
  _FreeSubscription() : super() {
    state = SubscriptionState(isSubscribed: false, isLoading: false);
  }

  // RevenueCat has no plugin under test; hold the resolved free state.
  @override
  set state(SubscriptionState value) =>
      super.state = value.copyWith(isSubscribed: false, isLoading: false);
}

/// Subscription whose state only [push] moves; RevenueCat's own init (no
/// plugin under test) cannot overwrite it.
class _ControlledSubscription extends SubscriptionNotifier {
  _ControlledSubscription(SubscriptionState initial) : super() {
    push(initial);
  }

  bool _pushing = false;

  void push(SubscriptionState next) {
    _pushing = true;
    state = next;
    _pushing = false;
  }

  @override
  set state(SubscriptionState value) {
    if (_pushing) super.state = value;
  }
}

class _FakeLikesRepository extends LibraryRepository {
  _FakeLikesRepository(List<SavedAnalysis> likes)
    : _likes = [
        for (final like in likes)
          like.id == _like(24).id || like.id == _like(2).id
              ? like.copyWith(tags: const ['Trap'])
              : like,
      ];

  final List<SavedAnalysis> _likes;
  int windowCalls = 0;
  int? lastWindowLimit;

  @override
  Future<LibraryFolder> ensureLikedGamesFolder() async => _folder;

  @override
  Future<List<SavedAnalysis>> getLikedAnalysesForView({
    required String folderId,
    required GameFilter filter,
    String search = '',
    List<String> tags = const <String>[],
  }) async {
    if (tags.isEmpty) return List<SavedAnalysis>.from(_likes);
    return _likes.where((a) => a.tags.any(tags.contains)).toList();
  }

  @override
  Future<int> getOwnedAnalysisCountInFolder(String folderId) async =>
      _likes.length;

  @override
  Future<List<SavedAnalysis>> getSavedAnalysesPaginated({
    required String folderId,
    required GameFilter filter,
    String search = '',
    List<String> tags = const <String>[],
    int limit = 30,
    int offset = 0,
  }) async {
    windowCalls++;
    lastWindowLimit = limit;
    final newest = List<SavedAnalysis>.from(_likes)
      ..sort(compareLikedNewestFirst);
    return newest.skip(offset).take(limit).toList();
  }
}

/// An empty My Space, so the long-press menu offers "Add to My Space".
class _NoShortcuts extends SpaceShortcutsNotifier {
  @override
  Future<List<SpaceShortcut>> build() async => const [];
}
