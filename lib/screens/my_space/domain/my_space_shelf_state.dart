/// The independently resolved state of one My Space shelf.
///
/// This hierarchy deliberately depends only on Dart. UI and state-management
/// layers can exhaustively pattern-match it without importing those concerns
/// into the domain.
sealed class MySpaceShelfState<T> {
  const MySpaceShelfState();

  const factory MySpaceShelfState.loading() = MySpaceShelfLoading<T>;

  const factory MySpaceShelfState.data(T data) = MySpaceShelfData<T>;

  const factory MySpaceShelfState.empty() = MySpaceShelfEmpty<T>;

  const factory MySpaceShelfState.partial({
    required T data,
    required Object error,
  }) = MySpaceShelfPartial<T>;

  const factory MySpaceShelfState.error(Object error) = MySpaceShelfError<T>;

  const factory MySpaceShelfState.unauthorized() = MySpaceShelfUnauthorized<T>;

  const factory MySpaceShelfState.removed() = MySpaceShelfRemoved<T>;

  const factory MySpaceShelfState.tombstone() = MySpaceShelfRemoved<T>;

  const factory MySpaceShelfState.offlineWithCache(T data) =
      MySpaceShelfOfflineWithCache<T>;

  const factory MySpaceShelfState.offlineWithoutCache() =
      MySpaceShelfOfflineWithoutCache<T>;

  @override
  bool operator ==(Object other) {
    return identical(this, other) || other.runtimeType == runtimeType;
  }

  @override
  int get hashCode => runtimeType.hashCode;
}

final class MySpaceShelfLoading<T> extends MySpaceShelfState<T> {
  const MySpaceShelfLoading();
}

final class MySpaceShelfData<T> extends MySpaceShelfState<T> {
  const MySpaceShelfData(this.data);

  final T data;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is MySpaceShelfData<T> && other.data == data;
  }

  @override
  int get hashCode => Object.hash(runtimeType, data);
}

final class MySpaceShelfEmpty<T> extends MySpaceShelfState<T> {
  const MySpaceShelfEmpty();
}

final class MySpaceShelfPartial<T> extends MySpaceShelfState<T> {
  const MySpaceShelfPartial({required this.data, required this.error});

  final T data;
  final Object error;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is MySpaceShelfPartial<T> &&
            other.data == data &&
            other.error == error;
  }

  @override
  int get hashCode => Object.hash(runtimeType, data, error);
}

final class MySpaceShelfError<T> extends MySpaceShelfState<T> {
  const MySpaceShelfError(this.error);

  final Object error;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is MySpaceShelfError<T> && other.error == error;
  }

  @override
  int get hashCode => Object.hash(runtimeType, error);
}

final class MySpaceShelfUnauthorized<T> extends MySpaceShelfState<T> {
  const MySpaceShelfUnauthorized();
}

/// A source entity that was removed, made private, or otherwise tombstoned.
final class MySpaceShelfRemoved<T> extends MySpaceShelfState<T> {
  const MySpaceShelfRemoved();
}

final class MySpaceShelfOfflineWithCache<T> extends MySpaceShelfState<T> {
  const MySpaceShelfOfflineWithCache(this.data);

  final T data;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is MySpaceShelfOfflineWithCache<T> && other.data == data;
  }

  @override
  int get hashCode => Object.hash(runtimeType, data);
}

final class MySpaceShelfOfflineWithoutCache<T> extends MySpaceShelfState<T> {
  const MySpaceShelfOfflineWithoutCache();
}
