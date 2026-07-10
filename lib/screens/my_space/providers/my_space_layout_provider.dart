import 'dart:async';

import 'package:chessever2/screens/my_space/data/my_space_layout_repository.dart';
import 'package:chessever2/screens/my_space/domain/my_space_layout.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

const bool kMySpacePersistenceEnabled = bool.fromEnvironment(
  'MY_SPACE_PERSISTENCE_ENABLED',
  defaultValue: false,
);

final mySpacePersistenceEnabledProvider = Provider<bool>(
  (ref) => kMySpacePersistenceEnabled,
);

final class MySpaceLayoutSnapshot {
  const MySpaceLayoutSnapshot({
    required this.layout,
    required this.revision,
    required this.hasServerRow,
    required this.persistenceAvailable,
    this.isSaving = false,
    this.failure,
  });

  factory MySpaceLayoutSnapshot.defaultLayout({
    required bool persistenceAvailable,
    Object? failure,
  }) {
    return MySpaceLayoutSnapshot(
      layout: MySpaceLayout.curatedDefault,
      revision: 0,
      hasServerRow: false,
      persistenceAvailable: persistenceAvailable,
      failure: failure,
    );
  }

  factory MySpaceLayoutSnapshot.stored(MySpaceStoredLayout stored) {
    return MySpaceLayoutSnapshot(
      layout: stored.layout,
      revision: stored.revision,
      hasServerRow: true,
      persistenceAvailable: true,
    );
  }

  final MySpaceLayout layout;
  final int revision;
  final bool hasServerRow;
  final bool persistenceAvailable;
  final bool isSaving;
  final Object? failure;

  MySpaceLayoutSnapshot copyWith({
    MySpaceLayout? layout,
    int? revision,
    bool? hasServerRow,
    bool? persistenceAvailable,
    bool? isSaving,
    Object? failure,
    bool clearFailure = false,
  }) {
    return MySpaceLayoutSnapshot(
      layout: layout ?? this.layout,
      revision: revision ?? this.revision,
      hasServerRow: hasServerRow ?? this.hasServerRow,
      persistenceAvailable: persistenceAvailable ?? this.persistenceAvailable,
      isSaving: isSaving ?? this.isSaving,
      failure: clearFailure ? null : failure ?? this.failure,
    );
  }
}

final mySpaceLayoutProvider = AutoDisposeAsyncNotifierProvider<
  MySpaceLayoutNotifier,
  MySpaceLayoutSnapshot
>(MySpaceLayoutNotifier.new);

class MySpaceLayoutNotifier
    extends AutoDisposeAsyncNotifier<MySpaceLayoutSnapshot> {
  Future<void>? _saveOperation;

  @override
  Future<MySpaceLayoutSnapshot> build() async {
    if (!ref.watch(mySpacePersistenceEnabledProvider)) {
      return MySpaceLayoutSnapshot.defaultLayout(persistenceAvailable: false);
    }

    try {
      final stored = await ref.watch(mySpaceLayoutRepositoryProvider).fetch();
      return stored == null
          ? MySpaceLayoutSnapshot.defaultLayout(persistenceAvailable: true)
          : MySpaceLayoutSnapshot.stored(stored);
    } on MySpaceLayoutException catch (error) {
      if (error.kind == MySpaceLayoutFailureKind.unauthenticated) {
        return MySpaceLayoutSnapshot.defaultLayout(
          persistenceAvailable: false,
          failure: error,
        );
      }
      return MySpaceLayoutSnapshot.defaultLayout(
        persistenceAvailable: false,
        failure: error,
      );
    }
  }

  Future<void> reload() async {
    ref.invalidateSelf();
    await future;
  }

  Future<void> saveLayout(MySpaceLayout layout) {
    final inFlight = _saveOperation;
    if (inFlight != null) return inFlight;

    late final Future<void> operation;
    operation = _performSave(layout).whenComplete(() {
      if (identical(_saveOperation, operation)) _saveOperation = null;
    });
    _saveOperation = operation;
    return operation;
  }

  Future<void> addShelf(MySpaceShelfDescriptor descriptor) {
    return _mutate((layout) {
      return MySpaceLayout(shelves: [...layout.shelves, descriptor]);
    });
  }

  Future<void> removeShelf(String descriptorId) {
    return _mutate((layout) {
      return MySpaceLayout(
        shelves: layout.shelves
            .where((shelf) => shelf.id != descriptorId)
            .toList(growable: false),
      );
    });
  }

  Future<void> moveShelf(String descriptorId, int targetIndex) {
    return _mutate((layout) {
      final shelves = layout.shelves.toList();
      final currentIndex = shelves.indexWhere(
        (shelf) => shelf.id == descriptorId,
      );
      if (currentIndex < 0) {
        throw ArgumentError.value(
          descriptorId,
          'descriptorId',
          'Shelf does not exist.',
        );
      }
      final shelf = shelves.removeAt(currentIndex);
      shelves.insert(targetIndex.clamp(0, shelves.length), shelf);
      return MySpaceLayout(shelves: shelves);
    });
  }

  Future<void> resizeShelf(String descriptorId, MySpaceShelfSize size) {
    return _replaceShelf(
      descriptorId,
      (shelf) => MySpaceShelfDescriptor(
        id: shelf.id,
        type: shelf.type,
        targetId: shelf.targetId,
        size: size,
        visible: shelf.visible,
      ),
    );
  }

  Future<void> setShelfVisibility(String descriptorId, bool visible) {
    return _replaceShelf(
      descriptorId,
      (shelf) => MySpaceShelfDescriptor(
        id: shelf.id,
        type: shelf.type,
        targetId: shelf.targetId,
        size: shelf.size,
        visible: visible,
      ),
    );
  }

  Future<void> resetToDefault() => saveLayout(MySpaceLayout.curatedDefault);

  Future<void> _replaceShelf(
    String descriptorId,
    MySpaceShelfDescriptor Function(MySpaceShelfDescriptor shelf) replace,
  ) {
    return _mutate((layout) {
      var found = false;
      final shelves = layout.shelves
          .map((shelf) {
            if (shelf.id != descriptorId) return shelf;
            found = true;
            return replace(shelf);
          })
          .toList(growable: false);
      if (!found) {
        throw ArgumentError.value(
          descriptorId,
          'descriptorId',
          'Shelf does not exist.',
        );
      }
      return MySpaceLayout(shelves: shelves);
    });
  }

  Future<void> _mutate(MySpaceLayout Function(MySpaceLayout layout) mutate) {
    final current = state.valueOrNull;
    if (current == null) {
      throw StateError('My Space layout is still loading.');
    }
    return saveLayout(mutate(current.layout));
  }

  Future<void> _performSave(MySpaceLayout layout) async {
    final current = state.valueOrNull;
    if (current == null) {
      throw StateError('My Space layout is still loading.');
    }
    if (!current.persistenceAvailable) {
      throw const MySpaceLayoutException(
        kind: MySpaceLayoutFailureKind.unavailable,
        message: 'Saved My Space layouts are not enabled in this release.',
      );
    }

    layout.validateForSave();
    state = AsyncData(current.copyWith(isSaving: true, clearFailure: true));
    try {
      final stored = await ref
          .read(mySpaceLayoutRepositoryProvider)
          .save(layout: layout, expectedRevision: current.revision);
      state = AsyncData(MySpaceLayoutSnapshot.stored(stored));
    } on MySpaceLayoutException catch (error) {
      if (error.kind == MySpaceLayoutFailureKind.revisionConflict) {
        await _refreshAfterConflict(error, fallback: current);
      } else {
        state = AsyncData(current.copyWith(isSaving: false, failure: error));
      }
      rethrow;
    } catch (error) {
      state = AsyncData(current.copyWith(isSaving: false, failure: error));
      rethrow;
    }
  }

  Future<void> _refreshAfterConflict(
    MySpaceLayoutException conflict, {
    required MySpaceLayoutSnapshot fallback,
  }) async {
    try {
      final latest = await ref.read(mySpaceLayoutRepositoryProvider).fetch();
      state = AsyncData(
        (latest == null
                ? MySpaceLayoutSnapshot.defaultLayout(
                  persistenceAvailable: true,
                )
                : MySpaceLayoutSnapshot.stored(latest))
            .copyWith(failure: conflict),
      );
    } catch (_) {
      state = AsyncData(fallback.copyWith(isSaving: false, failure: conflict));
    }
  }
}
