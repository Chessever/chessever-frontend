import 'package:chessever2/repository/gamebase/gamebase_repository.dart';
import 'package:chessever2/screens/my_space/domain/my_space_shelf_state.dart';
import 'package:chessever2/screens/my_space/providers/my_space_content_providers.dart';
import 'package:chessever2/screens/studies/data/study_bookmark.dart';
import 'package:chessever2/screens/studies/providers/study_bookmarks_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

void main() {
  test('disabled Saved Studies is synchronously empty', () {
    final container = ProviderContainer(
      overrides: <Override>[
        studyBookmarksEnabledProvider.overrideWithValue(false),
        mySpaceSavedStudiesSourceProvider.overrideWithValue(
          const AsyncLoading<SavedStudiesState>(),
        ),
      ],
    );
    addTearDown(container.dispose);

    expect(
      container.read(mySpaceSavedStudiesShelfProvider),
      isA<MySpaceShelfEmpty<List<MySpaceContentItem>>>(),
    );
  });

  test('maps canonical Study and removable 404 tombstone without PGN', () {
    final availableBookmark = _bookmark('AbCd0001', progress: true);
    final missingBookmark = _bookmark('AbCd0002');
    final study = _study('AbCd0001');
    final container = ProviderContainer(
      overrides: <Override>[
        studyBookmarksEnabledProvider.overrideWithValue(true),
        mySpaceSavedStudiesSourceProvider.overrideWithValue(
          AsyncData<SavedStudiesState>(
            SavedStudiesState(
              isEnabled: true,
              items: <SavedStudyReference>[
                AvailableSavedStudy(bookmark: availableBookmark, study: study),
                UnavailableSavedStudy(bookmark: missingBookmark),
              ],
            ),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    final shelf =
        container.read(mySpaceSavedStudiesShelfProvider)
            as MySpaceShelfData<List<MySpaceContentItem>>;
    final available = shelf.data.first as MySpaceStudyItem;
    final missing = shelf.data.last as MySpaceUnavailableItem;

    expect(available.study.canonicalStudyId, 'AbCd0001');
    expect(
      available.study.canonicalSourceUrl.toString(),
      'https://lichess.org/study/AbCd0001',
    );
    expect(available.study.canOpenMirroredChapterInApp, isFalse);
    expect(available.status, 'Resume at ply 18');
    expect(missing.title, 'Saved AbCd0002');
    expect(missing.actionLabel, 'Remove bookmark');
    expect(missing.removableCanonicalStudyId, 'AbCd0002');
  });

  test('keeps resolved rows when another resolution fails', () {
    final container = ProviderContainer(
      overrides: <Override>[
        studyBookmarksEnabledProvider.overrideWithValue(true),
        mySpaceSavedStudiesSourceProvider.overrideWithValue(
          AsyncData<SavedStudiesState>(
            SavedStudiesState(
              isEnabled: true,
              items: <SavedStudyReference>[
                AvailableSavedStudy(
                  bookmark: _bookmark('AbCd0001'),
                  study: _study('AbCd0001'),
                ),
              ],
              resolutionFailures: <Object>[StateError('offline')],
            ),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    final shelf = container.read(mySpaceSavedStudiesShelfProvider);

    expect(shelf, isA<MySpaceShelfPartial<List<MySpaceContentItem>>>());
    expect(
      (shelf as MySpaceShelfPartial<List<MySpaceContentItem>>).data,
      hasLength(1),
    );
  });
}

StudyBookmarkReference _bookmark(String id, {bool progress = false}) {
  return StudyBookmarkReference(
    userId: 'user-1',
    lichessStudyId: id,
    lichessChapterId: progress ? 'Chapter1' : null,
    lastPly: progress ? 18 : null,
    displaySnapshot: StudyBookmarkDisplaySnapshot.validated(
      title: 'Saved $id',
      attribution: 'Study on Lichess',
    ),
    bookmarkedAt: DateTime.utc(2026, 7, 10, 10),
    progressUpdatedAt: progress ? DateTime.utc(2026, 7, 10, 12) : null,
    updatedAt: DateTime.utc(2026, 7, 10, 12),
  );
}

GamebaseStudySummary _study(String id) {
  final now = DateTime.utc(2026, 7, 10);
  return GamebaseStudySummary(
    lichessStudyId: id,
    authorUsername: 'author',
    name: 'Practical endings',
    views: 1200,
    lichessCreatedAt: now,
    lichessUpdatedAt: now,
    chapterCount: 3,
    plyTotal: 120,
    hasAnnotations: true,
    ecos: const <String>['C65'],
    ecoCategories: const <String>['C'],
    openings: const <String>['Ruy Lopez'],
    variants: const <String>['standard'],
    chapterModes: const <String>['normal'],
    players: const <String>[],
    isGamebook: false,
    hasCustomPositions: false,
    credibilityScore: 0.95,
    passedGate: true,
    status: GamebaseStudyStatus.active,
    syncedAt: now,
  );
}
