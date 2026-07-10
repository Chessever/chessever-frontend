import 'package:chessever2/repository/favorites/models/favorite_event.dart';
import 'package:chessever2/repository/favorites/models/favorite_player.dart';
import 'package:chessever2/repository/gamebase/gamebase_repository.dart';
import 'package:chessever2/repository/library/models/library_folder.dart';
import 'package:chessever2/repository/library/models/saved_analysis.dart';
import 'package:chessever2/revenue_cat_service/subscribe_state.dart';
import 'package:chessever2/screens/chessboard/analysis/chess_game.dart';
import 'package:chessever2/screens/library/providers/library_folders_provider.dart';
import 'package:chessever2/screens/miniatures/providers/miniatures_provider.dart';
import 'package:chessever2/screens/my_space/domain/my_space_shelf_state.dart';
import 'package:chessever2/screens/my_space/providers/my_space_content_providers.dart';
import 'package:chessever2/screens/studies/providers/studies_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

void main() {
  group('My Space content adapters', () {
    test('maps loading, empty, and error independently', () {
      final loading = ProviderContainer(
        overrides: [
          mySpaceContinueAnalysesSourceProvider.overrideWithValue(
            const AsyncValue<List<SavedAnalysis>>.loading(),
          ),
        ],
      );
      final empty = ProviderContainer(
        overrides: [
          mySpaceContinueAnalysesSourceProvider.overrideWithValue(
            const AsyncValue<List<SavedAnalysis>>.data(<SavedAnalysis>[]),
          ),
        ],
      );
      final error = ProviderContainer(
        overrides: [
          mySpaceContinueAnalysesSourceProvider.overrideWithValue(
            AsyncValue<List<SavedAnalysis>>.error(
              StateError('continue failed'),
              StackTrace.empty,
            ),
          ),
        ],
      );
      addTearDown(loading.dispose);
      addTearDown(empty.dispose);
      addTearDown(error.dispose);

      expect(
        loading.read(mySpaceContinueShelfProvider),
        isA<MySpaceShelfLoading<List<MySpaceContentItem>>>(),
      );
      expect(
        empty.read(mySpaceContinueShelfProvider),
        isA<MySpaceShelfEmpty<List<MySpaceContentItem>>>(),
      );
      expect(
        error.read(mySpaceContinueShelfProvider),
        isA<MySpaceShelfError<List<MySpaceContentItem>>>(),
      );
    });

    test('My Likes is derived from the canonical liked-games source seam', () {
      final analysis = _analysis(id: 'liked-analysis');
      final container = ProviderContainer(
        overrides: [
          mySpaceLikedGamesSourceProvider.overrideWithValue(
            AsyncValue<List<SavedAnalysis>>.data([analysis]),
          ),
          mySpaceSubscriptionStateProvider.overrideWithValue(
            SubscriptionState(isSubscribed: true),
          ),
        ],
      );
      addTearDown(container.dispose);

      final state = container.read(mySpaceLikesShelfProvider);

      expect(state, isA<MySpaceShelfData<List<MySpaceContentItem>>>());
      final item =
          (state as MySpaceShelfData<List<MySpaceContentItem>>).data.single;
      expect(item, isA<MySpaceAnalysisItem>());
      expect((item as MySpaceAnalysisItem).analysis, same(analysis));
      expect(item.isLiked, isTrue);
      expect(item.isLocked, isFalse);
      expect(item.actionLabel, 'Open analysis');
    });

    test('event identity failure becomes a scoped tombstone', () {
      final now = DateTime(2026, 7, 10);
      final valid = FavoriteEvent(
        id: 'favorite-event-1',
        userId: 'user-1',
        eventId: 'broadcast-42',
        eventName: 'Candidates',
        metadata: const {'timeControl': 'Classical'},
        createdAt: now,
        updatedAt: now,
      );
      final missingIdentity = FavoriteEvent(
        id: 'favorite-event-2',
        userId: 'user-1',
        eventId: '',
        eventName: 'A display name is not identity',
        metadata: const {},
        createdAt: now,
        updatedAt: now,
      );
      final nameDerivedIdentity = FavoriteEvent(
        id: 'favorite-event-3',
        userId: 'user-1',
        eventId: 'cal_event_name_derived',
        eventName: 'A generated calendar key',
        metadata: const {},
        createdAt: now,
        updatedAt: now,
      );
      final container = ProviderContainer(
        overrides: [
          mySpaceFavoriteEventsSourceProvider.overrideWithValue(
            AsyncValue<List<FavoriteEvent>>.data([
              valid,
              missingIdentity,
              nameDerivedIdentity,
            ]),
          ),
        ],
      );
      addTearDown(container.dispose);

      final state =
          container.read(mySpaceSavedEventsShelfProvider)
              as MySpaceShelfData<List<MySpaceContentItem>>;

      expect(state.data.first, isA<MySpaceEventItem>());
      expect(state.data.skip(1), everyElement(isA<MySpaceUnavailableItem>()));
      expect(state.data[1].title, 'Saved event unavailable');
      expect(state.data[2].isUnavailable, isTrue);
    });

    test('player identity failure is not guessed from a name', () {
      final now = DateTime(2026, 7, 10);
      final valid = FavoritePlayer(
        id: 'favorite-player-1',
        userId: 'user-1',
        fideId: '1503014',
        playerName: 'Magnus Carlsen',
        metadata: const {'title': 'GM', 'countryCode': 'NOR', 'rating': 2837},
        createdAt: now,
        updatedAt: now,
      );
      final missingIdentity = FavoritePlayer(
        id: 'favorite-player-2',
        userId: 'user-1',
        playerName: 'Name-only favorite',
        metadata: const {},
        createdAt: now,
        updatedAt: now,
      );
      final container = ProviderContainer(
        overrides: [
          mySpaceFavoritePlayersSourceProvider.overrideWithValue(
            AsyncValue<List<FavoritePlayer>>.data([valid, missingIdentity]),
          ),
        ],
      );
      addTearDown(container.dispose);

      final state =
          container.read(mySpaceFavoritePlayersShelfProvider)
              as MySpaceShelfData<List<MySpaceContentItem>>;

      final player = state.data.first as MySpacePlayerItem;
      expect(player.fideId, 1503014);
      expect(player.federation, 'NOR');
      expect(state.data.last, isA<MySpaceUnavailableItem>());
      expect(state.data.last.title, 'Favorite player unavailable');
    });

    test(
      'databases exclude synthetic and liked folders and sort by recency',
      () {
        final old = _folder(id: 'old', name: 'Old database', day: 1);
        final recent = _folder(id: 'recent', name: 'Recent folder', day: 3);
        final liked = _folder(
          id: 'liked',
          name: 'Liked Games',
          day: 4,
          isLikedGames: true,
        );
        final twic = _folder(id: kTwicBookId, name: 'ChessEver', day: 5);
        final container = ProviderContainer(
          overrides: [
            mySpaceLibraryFoldersSourceProvider.overrideWithValue(
              AsyncValue<List<LibraryFolder>>.data([old, liked, twic, recent]),
            ),
          ],
        );
        addTearDown(container.dispose);

        final state =
            container.read(mySpaceDatabasesShelfProvider)
                as MySpaceShelfData<List<MySpaceContentItem>>;

        expect(state.data.map((item) => item.title), const [
          'Recent folder',
          'Old database',
        ]);
      },
    );

    test('Saved Studies stays honestly empty without a canonical source', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(
        container.read(mySpaceSavedStudiesShelfProvider),
        isA<MySpaceShelfEmpty<List<MySpaceContentItem>>>(),
      );
    });

    test(
      'Study Discovery keeps canonical Lichess identity and no PGN path',
      () {
        final study = _study();
        final container = ProviderContainer(
          overrides: [
            mySpaceStudiesSourceProvider.overrideWithValue(
              AsyncValue<StudiesState>.data(
                StudiesState(
                  items: [study],
                  filter: kDefaultStudiesFilter,
                  total: 1,
                  nextOffset: 1,
                  hasMore: false,
                ),
              ),
            ),
          ],
        );
        addTearDown(container.dispose);

        final state =
            container.read(mySpaceStudyDiscoveryShelfProvider)
                as MySpaceShelfData<List<MySpaceContentItem>>;
        final item = state.data.single as MySpaceStudyItem;

        expect(item.study, same(study));
        expect(item.id, 'study:study-42');
        expect(
          item.study.canonicalSourceUrl.toString(),
          'https://lichess.org/study/study-42',
        );
        expect(item.study.canOpenMirroredChapterInApp, isFalse);
        expect(item.actionLabel, 'View Study');
      },
    );

    test('Miniatures keeps the canonical Gamebase hydration identity', () {
      final miniature = _miniature();
      final container = ProviderContainer(
        overrides: [
          mySpaceMiniaturesSourceProvider.overrideWithValue(
            AsyncValue<MiniaturesState>.data(
              MiniaturesState(
                items: [miniature],
                filter: kDefaultMiniaturesFilter,
                total: 1,
                nextOffset: 1,
                hasMore: false,
              ),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      final state =
          container.read(mySpaceMiniaturesShelfProvider)
              as MySpaceShelfData<List<MySpaceContentItem>>;
      final item = state.data.single as MySpaceMiniatureItem;

      expect(item.miniature, same(miniature));
      expect(item.id, 'miniature:game-42');
      expect(item.miniature.sourceMetadata.requiresFullGameHydration, isTrue);
      expect(item.actionLabel, 'Open game');
    });

    test('later-page discovery failures retain usable shelf data', () {
      final container = ProviderContainer(
        overrides: [
          mySpaceStudiesSourceProvider.overrideWithValue(
            AsyncValue<StudiesState>.data(
              StudiesState(
                items: [_study()],
                filter: kDefaultStudiesFilter,
                total: 30,
                nextOffset: 1,
                hasMore: true,
                loadMoreFailure: StudiesLoadMoreFailure(
                  error: StateError('next page failed'),
                  stackTrace: StackTrace.empty,
                  offset: 1,
                ),
              ),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      final state = container.read(mySpaceStudyDiscoveryShelfProvider);

      expect(state, isA<MySpaceShelfPartial<List<MySpaceContentItem>>>());
      expect(
        (state as MySpaceShelfPartial<List<MySpaceContentItem>>).data,
        hasLength(1),
      );
    });
  });
}

GamebaseStudySummary _study() {
  final now = DateTime.utc(2026, 7, 10);
  return GamebaseStudySummary(
    lichessStudyId: 'study-42',
    authorUsername: 'quality-author',
    name: 'Practical rook endings',
    views: 4200,
    lichessCreatedAt: now.subtract(const Duration(days: 30)),
    lichessUpdatedAt: now,
    chapterCount: 8,
    plyTotal: 640,
    hasAnnotations: true,
    ecos: const ['C65'],
    ecoCategories: const ['C'],
    openings: const ['Ruy Lopez'],
    variants: const ['standard'],
    chapterModes: const ['normal'],
    players: const ['Capablanca'],
    isGamebook: false,
    hasCustomPositions: false,
    credibilityScore: 0.96,
    passedGate: true,
    status: GamebaseStudyStatus.active,
    syncedAt: now,
  );
}

GamebaseMiniature _miniature() {
  return GamebaseMiniature(
    gameId: 'game-42',
    avgRating: 2450,
    plyCount: 34,
    finalMoveNumber: 17,
    result: MiniatureGameResult.whiteWins,
    timeControl: MiniatureGameTimeControl.rapid,
    onlineStatus: MiniatureGameOnlineStatus.offline,
    date: DateTime.utc(2026, 7, 9),
    event: 'Tactical Masters',
    eco: 'B12',
    opening: 'Caro-Kann Defense',
    whiteName: 'Alpha',
    blackName: 'Beta',
  );
}

SavedAnalysis _analysis({required String id}) {
  final now = DateTime(2026, 7, 10);
  return SavedAnalysis(
    id: id,
    userId: 'user-1',
    folderId: 'liked-folder',
    title: 'White vs Black',
    sourceGameId: 'game-1',
    sourceTournamentId: 'tour-1',
    chessGame: ChessGame(
      gameId: 'game-1',
      startingFen: '',
      metadata: const {
        'White': 'White',
        'Black': 'Black',
        'Opening': 'Sicilian Defense',
      },
      mainline: const [],
    ),
    analysisState: const {},
    variationComments: const {},
    lastViewedPosition: 4,
    tags: const [],
    isFavorite: false,
    createdAt: now,
    updatedAt: now,
    lastOpenedAt: now,
  );
}

LibraryFolder _folder({
  required String id,
  required String name,
  required int day,
  bool isLikedGames = false,
}) {
  return LibraryFolder(
    id: id,
    userId: 'user-1',
    name: name,
    color: '#0FB4E5',
    icon: 'folder',
    orderIndex: day,
    createdAt: DateTime(2026, 7, day),
    updatedAt: DateTime(2026, 7, day),
    isLikedGames: isLikedGames,
  );
}
