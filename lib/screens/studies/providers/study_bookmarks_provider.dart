import 'package:chessever2/repository/gamebase/gamebase_repository.dart';
import 'package:chessever2/screens/studies/data/study_bookmark.dart';
import 'package:chessever2/screens/studies/data/study_bookmark_repository.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

const bool kStudyBookmarksEnabled = bool.fromEnvironment(
  'STUDY_BOOKMARKS_ENABLED',
  defaultValue: false,
);

final studyBookmarksEnabledProvider = Provider<bool>(
  (ref) => kStudyBookmarksEnabled,
);

@immutable
class StudyBookmarksState {
  StudyBookmarksState({
    required this.isEnabled,
    required Iterable<StudyBookmarkReference> references,
  }) : references = List<StudyBookmarkReference>.unmodifiable(references);

  final bool isEnabled;
  final List<StudyBookmarkReference> references;
}

final studyBookmarksProvider = AutoDisposeAsyncNotifierProvider<
  StudyBookmarksNotifier,
  StudyBookmarksState
>(StudyBookmarksNotifier.new);

class StudyBookmarksNotifier
    extends AutoDisposeAsyncNotifier<StudyBookmarksState> {
  @override
  Future<StudyBookmarksState> build() async {
    final isEnabled = ref.watch(studyBookmarksEnabledProvider);
    if (!isEnabled) {
      return StudyBookmarksState(
        isEnabled: false,
        references: const <StudyBookmarkReference>[],
      );
    }
    final references = await ref.watch(studyBookmarkRepositoryProvider).fetch();
    return StudyBookmarksState(isEnabled: true, references: references);
  }

  Future<StudyBookmarkReference> bookmark({
    required String lichessStudyId,
    StudyBookmarkDisplaySnapshot snapshot =
        const StudyBookmarkDisplaySnapshot(),
  }) async {
    _requireEnabled();
    final saved = await ref
        .read(studyBookmarkRepositoryProvider)
        .bookmark(lichessStudyId: lichessStudyId, snapshot: snapshot);
    _publishUpsert(saved);
    return saved;
  }

  Future<StudyBookmarkReference> upsertProgress({
    required String lichessStudyId,
    required String lichessChapterId,
    required int lastPly,
    String? contentVersion,
    StudyBookmarkDisplaySnapshot snapshot =
        const StudyBookmarkDisplaySnapshot(),
  }) async {
    _requireEnabled();
    final saved = await ref
        .read(studyBookmarkRepositoryProvider)
        .upsertProgress(
          lichessStudyId: lichessStudyId,
          lichessChapterId: lichessChapterId,
          lastPly: lastPly,
          contentVersion: contentVersion,
          snapshot: snapshot,
        );
    _publishUpsert(saved);
    return saved;
  }

  Future<void> unbookmark(String lichessStudyId) async {
    _requireEnabled();
    final normalizedId = normalizeLichessStudyId(lichessStudyId);
    await ref.read(studyBookmarkRepositoryProvider).unbookmark(normalizedId);
    final current = state.valueOrNull;
    if (current == null) return;
    state = AsyncData(
      StudyBookmarksState(
        isEnabled: true,
        references: current.references.where(
          (reference) => reference.lichessStudyId != normalizedId,
        ),
      ),
    );
  }

  void _requireEnabled() {
    if (!ref.read(studyBookmarksEnabledProvider)) {
      throw const StudyBookmarkException(
        kind: StudyBookmarkFailureKind.unavailable,
        message: 'Saved Studies are not enabled in this app rollout.',
      );
    }
  }

  void _publishUpsert(StudyBookmarkReference saved) {
    final current = state.valueOrNull;
    final references = <StudyBookmarkReference>[
      saved,
      ...?current?.references.where(
        (reference) => reference.lichessStudyId != saved.lichessStudyId,
      ),
    ]..sort(compareStudyBookmarkRecency);
    state = AsyncData(
      StudyBookmarksState(isEnabled: true, references: references),
    );
  }
}

sealed class SavedStudyReference {
  const SavedStudyReference({required this.bookmark});

  final StudyBookmarkReference bookmark;
}

final class AvailableSavedStudy extends SavedStudyReference {
  const AvailableSavedStudy({required super.bookmark, required this.study});

  final GamebaseStudySummary study;
}

final class UnavailableSavedStudy extends SavedStudyReference {
  const UnavailableSavedStudy({required super.bookmark});
}

@immutable
class SavedStudiesState {
  SavedStudiesState({
    required this.isEnabled,
    required Iterable<SavedStudyReference> items,
    Iterable<Object> resolutionFailures = const <Object>[],
  }) : items = List<SavedStudyReference>.unmodifiable(items),
       resolutionFailures = List<Object>.unmodifiable(resolutionFailures);

  final bool isEnabled;
  final List<SavedStudyReference> items;
  final List<Object> resolutionFailures;

  bool get hasPartialFailure => resolutionFailures.isNotEmpty;
}

final savedStudiesProvider =
    AutoDisposeAsyncNotifierProvider<SavedStudiesNotifier, SavedStudiesState>(
      SavedStudiesNotifier.new,
    );

class SavedStudiesNotifier extends AutoDisposeAsyncNotifier<SavedStudiesState> {
  @override
  Future<SavedStudiesState> build() async {
    final bookmarks = await ref.watch(studyBookmarksProvider.future);
    if (!bookmarks.isEnabled || bookmarks.references.isEmpty) {
      return SavedStudiesState(
        isEnabled: bookmarks.isEnabled,
        items: const <SavedStudyReference>[],
      );
    }

    final references = bookmarks.references
        .take(kMaximumSavedStudiesRailItems)
        .toList(growable: false);
    final repository = ref.watch(gamebaseRepositoryProvider);
    final items = <SavedStudyReference>[];
    final failures = <Object>[];

    for (
      var offset = 0;
      offset < references.length;
      offset += kSavedStudyResolutionConcurrency
    ) {
      final end = (offset + kSavedStudyResolutionConcurrency).clamp(
        0,
        references.length,
      );
      final batch = references.sublist(offset, end);
      final outcomes = await Future.wait(
        batch.map((reference) => _resolve(repository, reference)),
      );
      for (final outcome in outcomes) {
        if (outcome.item != null) items.add(outcome.item!);
        if (outcome.failure != null) failures.add(outcome.failure!);
      }
    }

    return SavedStudiesState(
      isEnabled: true,
      items: items,
      resolutionFailures: failures,
    );
  }

  Future<_SavedStudyResolution> _resolve(
    GamebaseRepository repository,
    StudyBookmarkReference bookmark,
  ) async {
    try {
      final detail = await repository.getStudy(bookmark.lichessStudyId);
      if (detail.study.status == GamebaseStudyStatus.gone) {
        return _SavedStudyResolution.item(
          UnavailableSavedStudy(bookmark: bookmark),
        );
      }
      return _SavedStudyResolution.item(
        AvailableSavedStudy(bookmark: bookmark, study: detail.study),
      );
    } on GamebaseStudyRequestException catch (error) {
      if (error.isNotFound) {
        return _SavedStudyResolution.item(
          UnavailableSavedStudy(bookmark: bookmark),
        );
      }
      return _SavedStudyResolution.failure(error);
    } catch (error) {
      return _SavedStudyResolution.failure(error);
    }
  }

  Future<StudyBookmarkReference> bookmark({
    required String lichessStudyId,
    StudyBookmarkDisplaySnapshot snapshot =
        const StudyBookmarkDisplaySnapshot(),
  }) {
    return ref
        .read(studyBookmarksProvider.notifier)
        .bookmark(lichessStudyId: lichessStudyId, snapshot: snapshot);
  }

  Future<StudyBookmarkReference> upsertProgress({
    required String lichessStudyId,
    required String lichessChapterId,
    required int lastPly,
    String? contentVersion,
    StudyBookmarkDisplaySnapshot snapshot =
        const StudyBookmarkDisplaySnapshot(),
  }) {
    return ref
        .read(studyBookmarksProvider.notifier)
        .upsertProgress(
          lichessStudyId: lichessStudyId,
          lichessChapterId: lichessChapterId,
          lastPly: lastPly,
          contentVersion: contentVersion,
          snapshot: snapshot,
        );
  }

  Future<void> unbookmark(String lichessStudyId) {
    return ref.read(studyBookmarksProvider.notifier).unbookmark(lichessStudyId);
  }
}

final class _SavedStudyResolution {
  const _SavedStudyResolution({this.item, this.failure});

  const _SavedStudyResolution.item(SavedStudyReference value)
    : this(item: value);

  const _SavedStudyResolution.failure(Object value) : this(failure: value);

  final SavedStudyReference? item;
  final Object? failure;
}
