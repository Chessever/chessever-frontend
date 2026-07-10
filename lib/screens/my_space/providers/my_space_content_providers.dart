import 'package:chessever2/providers/favorite_events_provider.dart';
import 'package:chessever2/providers/favorite_players_provider.dart';
import 'package:chessever2/repository/favorites/models/favorite_event.dart';
import 'package:chessever2/repository/favorites/models/favorite_player.dart';
import 'package:chessever2/repository/gamebase/gamebase_repository.dart';
import 'package:chessever2/repository/library/library_repository.dart';
import 'package:chessever2/repository/library/models/library_folder.dart';
import 'package:chessever2/repository/library/models/saved_analysis.dart';
import 'package:chessever2/repository/liked_games/liked_games_provider.dart';
import 'package:chessever2/revenue_cat_service/subscribe_state.dart';
import 'package:chessever2/screens/library/providers/library_folders_provider.dart';
import 'package:chessever2/screens/miniatures/providers/miniatures_provider.dart';
import 'package:chessever2/screens/my_likes/provider/my_likes_provider.dart';
import 'package:chessever2/screens/my_space/domain/my_space_shelf_state.dart';
import 'package:chessever2/screens/studies/providers/study_bookmarks_provider.dart';
import 'package:chessever2/screens/studies/providers/studies_provider.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

const int _maximumRailItems = 12;

enum MySpaceEntityKind {
  analysis,
  event,
  database,
  folder,
  player,
  study,
  miniature,
  unavailable,
}

/// Display-ready content that still retains its typed canonical source.
///
/// The UI never has to rebuild identities from display names. Concrete
/// subclasses carry the source model needed by the existing navigation path.
sealed class MySpaceContentItem {
  const MySpaceContentItem({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    this.status,
    this.imageUrl,
    this.isLocked = false,
  });

  final String id;
  final String title;
  final String subtitle;
  final String actionLabel;
  final String? status;
  final String? imageUrl;
  final bool isLocked;

  MySpaceEntityKind get kind;

  String get semanticEntityType => switch (kind) {
    MySpaceEntityKind.analysis => 'Saved analysis',
    MySpaceEntityKind.event => 'Event',
    MySpaceEntityKind.database => 'Database',
    MySpaceEntityKind.folder => 'Folder',
    MySpaceEntityKind.player => 'Player',
    MySpaceEntityKind.study => 'Lichess Study',
    MySpaceEntityKind.miniature => 'Miniature game',
    MySpaceEntityKind.unavailable => 'Unavailable item',
  };

  bool get isUnavailable => kind == MySpaceEntityKind.unavailable;

  String get semanticLabel => <String>[
    semanticEntityType,
    title,
    if (status case final value?) value,
    if (isLocked) 'Premium locked',
    actionLabel,
  ].join(', ');
}

final class MySpaceAnalysisItem extends MySpaceContentItem {
  const MySpaceAnalysisItem({
    required super.id,
    required super.title,
    required super.subtitle,
    required super.actionLabel,
    required this.analysis,
    required this.isLiked,
    super.status,
    super.imageUrl,
    super.isLocked,
  });

  final SavedAnalysis analysis;
  final bool isLiked;

  @override
  MySpaceEntityKind get kind => MySpaceEntityKind.analysis;
}

final class MySpaceEventItem extends MySpaceContentItem {
  const MySpaceEventItem({
    required super.id,
    required super.title,
    required super.subtitle,
    required super.actionLabel,
    required this.event,
    super.status,
    super.imageUrl,
  });

  final FavoriteEvent event;

  @override
  MySpaceEntityKind get kind => MySpaceEntityKind.event;
}

final class MySpaceLibraryItem extends MySpaceContentItem {
  const MySpaceLibraryItem({
    required super.id,
    required super.title,
    required super.subtitle,
    required super.actionLabel,
    required this.folder,
    super.status,
    super.imageUrl,
  });

  final LibraryFolder folder;

  @override
  MySpaceEntityKind get kind =>
      folder.isFolder ? MySpaceEntityKind.folder : MySpaceEntityKind.database;
}

final class MySpacePlayerItem extends MySpaceContentItem {
  const MySpacePlayerItem({
    required super.id,
    required super.title,
    required super.subtitle,
    required super.actionLabel,
    required this.player,
    required this.fideId,
    this.playerTitle,
    this.federation,
    this.rating,
    super.status,
    super.imageUrl,
  });

  final FavoritePlayer player;
  final int fideId;
  final String? playerTitle;
  final String? federation;
  final int? rating;

  @override
  MySpaceEntityKind get kind => MySpaceEntityKind.player;
}

/// A quality-ranked Study summary whose canonical identity remains Lichess.
///
/// This item deliberately carries no chapter PGN or in-app chapter capability.
final class MySpaceStudyItem extends MySpaceContentItem {
  const MySpaceStudyItem({
    required super.id,
    required super.title,
    required super.subtitle,
    required super.actionLabel,
    required this.study,
    super.status,
  });

  final GamebaseStudySummary study;

  @override
  MySpaceEntityKind get kind => MySpaceEntityKind.study;
}

/// A lightweight Miniatures row that must be hydrated before Board opens.
final class MySpaceMiniatureItem extends MySpaceContentItem {
  const MySpaceMiniatureItem({
    required super.id,
    required super.title,
    required super.subtitle,
    required super.actionLabel,
    required this.miniature,
    super.status,
  });

  final GamebaseMiniature miniature;

  @override
  MySpaceEntityKind get kind => MySpaceEntityKind.miniature;
}

/// A source row that cannot be opened without inventing canonical identity.
final class MySpaceUnavailableItem extends MySpaceContentItem {
  const MySpaceUnavailableItem({
    required super.id,
    required super.title,
    required super.subtitle,
    this.sourceType = 'Item',
    this.removableCanonicalStudyId,
    super.actionLabel = 'Unavailable',
    super.status = 'Unavailable',
  });

  final String sourceType;
  final String? removableCanonicalStudyId;

  @override
  MySpaceEntityKind get kind => MySpaceEntityKind.unavailable;

  @override
  String get semanticEntityType => '$sourceType unavailable';
}

typedef MySpaceContentShelfState = MySpaceShelfState<List<MySpaceContentItem>>;

/// Test seam over the canonical Library recency query.
final mySpaceContinueAnalysesSourceProvider =
    Provider.autoDispose<AsyncValue<List<SavedAnalysis>>>(
      (ref) => ref.watch(mySpaceRecentLibraryAnalysesProvider),
    );

/// Test seam over the canonical liked-games notifier. This deliberately does
/// not read the filtered/sorted My Likes screen provider.
final mySpaceLikedGamesSourceProvider =
    Provider.autoDispose<AsyncValue<List<SavedAnalysis>>>(
      (ref) => ref.watch(likedGamesProvider),
    );

final mySpaceFavoriteEventsSourceProvider =
    Provider.autoDispose<AsyncValue<List<FavoriteEvent>>>(
      (ref) => ref.watch(favoriteEventsProvider),
    );

final mySpaceLibraryFoldersSourceProvider =
    Provider.autoDispose<AsyncValue<List<LibraryFolder>>>(
      (ref) => ref.watch(combinedLibraryFoldersProvider),
    );

final mySpaceFavoritePlayersSourceProvider =
    Provider.autoDispose<AsyncValue<List<FavoritePlayer>>>(
      (ref) => ref.watch(favoritePlayersProviderNew),
    );

/// Test seams over the safe, metadata-only discovery feeds.
final mySpaceStudiesSourceProvider =
    Provider.autoDispose<AsyncValue<StudiesState>>(
      (ref) => ref.watch(studiesProvider),
    );

final mySpaceMiniaturesSourceProvider =
    Provider.autoDispose<AsyncValue<MiniaturesState>>(
      (ref) => ref.watch(miniaturesProvider),
    );

final mySpaceSavedStudiesSourceProvider =
    Provider.autoDispose<AsyncValue<SavedStudiesState>>(
      (ref) => ref.watch(savedStudiesProvider),
    );

/// Keeps tests independent from the RevenueCat-backed notifier while using the
/// same access policy as My Likes in production.
final mySpaceSubscriptionStateProvider =
    Provider.autoDispose<SubscriptionState>((ref) {
      return ref.watch(subscriptionProvider);
    });

/// Library activity has an explicit `lastOpenedAt`, making it safe to rank for
/// Continue. Liked-folder rows are excluded so Continue cannot bypass the
/// existing My Likes seven-day access rule.
final mySpaceRecentLibraryAnalysesProvider =
    FutureProvider.autoDispose<List<SavedAnalysis>>((ref) async {
      final repository = ref.watch(libraryRepositoryProvider);
      final results = await Future.wait<Object>([
        repository.getSavedAnalyses(),
        repository.getFolders(),
      ]);
      final analyses = results[0] as List<SavedAnalysis>;
      final folders = results[1] as List<LibraryFolder>;
      final likedFolderIds =
          folders
              .where((folder) => folder.isLikedGames)
              .map((folder) => folder.id)
              .toSet();

      final recent =
          analyses
              .where(
                (analysis) =>
                    analysis.lastOpenedAt != null &&
                    !likedFolderIds.contains(analysis.folderId),
              )
              .toList()
            ..sort(
              (left, right) =>
                  right.lastOpenedAt!.compareTo(left.lastOpenedAt!),
            );
      return List<SavedAnalysis>.unmodifiable(recent.take(6));
    });

final mySpaceContinueShelfProvider =
    Provider.autoDispose<MySpaceContentShelfState>((ref) {
      return _mapAsyncItems(
        ref.watch(mySpaceContinueAnalysesSourceProvider),
        (analyses) => analyses.map(_continueItem).toList(growable: false),
      );
    });

final mySpaceLikesShelfProvider =
    Provider.autoDispose<MySpaceContentShelfState>((ref) {
      final subscription = ref.watch(mySpaceSubscriptionStateProvider);
      return _mapAsyncItems(
        ref.watch(mySpaceLikedGamesSourceProvider),
        (analyses) => analyses
            .take(_maximumRailItems)
            .map(
              (analysis) => _likedAnalysisItem(
                analysis,
                isLocked: isLikedGameLocked(
                  analysis.createdAt.toLocal(),
                  isSubscribed: subscription.isSubscribed,
                  subscriptionLoading: subscription.isLoading,
                ),
              ),
            )
            .toList(growable: false),
      );
    });

final mySpaceSavedEventsShelfProvider =
    Provider.autoDispose<MySpaceContentShelfState>((ref) {
      return _mapAsyncItems(
        ref.watch(mySpaceFavoriteEventsSourceProvider),
        (events) => events
            .take(_maximumRailItems)
            .map(_favoriteEventItem)
            .toList(growable: false),
      );
    });

final mySpaceDatabasesShelfProvider = Provider.autoDispose<
  MySpaceContentShelfState
>((ref) {
  return _mapAsyncItems(ref.watch(mySpaceLibraryFoldersSourceProvider), (
    folders,
  ) {
    final visible =
        folders
            .where((folder) => folder.id != kTwicBookId && !folder.isLikedGames)
            .toList()
          ..sort((left, right) => right.updatedAt.compareTo(left.updatedAt));
    return visible
        .take(_maximumRailItems)
        .map(_libraryItem)
        .toList(growable: false);
  });
});

final mySpaceSavedStudiesShelfProvider =
    Provider.autoDispose<MySpaceContentShelfState>((ref) {
      if (!ref.watch(studyBookmarksEnabledProvider)) {
        return const MySpaceShelfState<List<MySpaceContentItem>>.empty();
      }
      final source = ref.watch(mySpaceSavedStudiesSourceProvider);
      final value = source.valueOrNull;
      if (value == null) return _mapColdAsync(source);
      if (!value.isEnabled) {
        return const MySpaceShelfState<List<MySpaceContentItem>>.empty();
      }

      final items = List<MySpaceContentItem>.unmodifiable(
        value.items.take(_maximumRailItems).map(_savedStudyItem),
      );
      if (value.hasPartialFailure && items.isNotEmpty) {
        return MySpaceShelfState<List<MySpaceContentItem>>.partial(
          data: items,
          error: value.resolutionFailures.first,
        );
      }
      if (value.hasPartialFailure) {
        return MySpaceShelfState<List<MySpaceContentItem>>.error(
          value.resolutionFailures.first,
        );
      }
      if (items.isEmpty) {
        return const MySpaceShelfState<List<MySpaceContentItem>>.empty();
      }
      return MySpaceShelfState<List<MySpaceContentItem>>.data(items);
    });

final mySpaceFavoritePlayersShelfProvider =
    Provider.autoDispose<MySpaceContentShelfState>((ref) {
      return _mapAsyncItems(
        ref.watch(mySpaceFavoritePlayersSourceProvider),
        (players) => players
            .take(_maximumRailItems)
            .map(_favoritePlayerItem)
            .toList(growable: false),
      );
    });

final mySpaceStudyDiscoveryShelfProvider =
    Provider.autoDispose<MySpaceContentShelfState>((ref) {
      final source = ref.watch(mySpaceStudiesSourceProvider);
      final value = source.valueOrNull;
      if (value == null) return _mapColdAsync(source);

      final items = List<MySpaceContentItem>.unmodifiable(
        value.items.take(_maximumRailItems).map(_studyItem),
      );
      final failure = value.loadMoreFailure?.error ?? source.error;
      if (failure != null && items.isNotEmpty) {
        return MySpaceShelfState<List<MySpaceContentItem>>.partial(
          data: items,
          error: failure,
        );
      }
      if (failure != null) {
        return MySpaceShelfState<List<MySpaceContentItem>>.error(failure);
      }
      if (items.isEmpty) {
        return const MySpaceShelfState<List<MySpaceContentItem>>.empty();
      }
      return MySpaceShelfState<List<MySpaceContentItem>>.data(items);
    });

final mySpaceMiniaturesShelfProvider =
    Provider.autoDispose<MySpaceContentShelfState>((ref) {
      final source = ref.watch(mySpaceMiniaturesSourceProvider);
      final value = source.valueOrNull;
      if (value == null) return _mapColdAsync(source);

      final items = List<MySpaceContentItem>.unmodifiable(
        value.items.take(_maximumRailItems).map(_miniatureItem),
      );
      final failure = value.loadMoreFailure?.error ?? source.error;
      if (failure != null && items.isNotEmpty) {
        return MySpaceShelfState<List<MySpaceContentItem>>.partial(
          data: items,
          error: failure,
        );
      }
      if (failure != null) {
        return MySpaceShelfState<List<MySpaceContentItem>>.error(failure);
      }
      if (items.isEmpty) {
        return const MySpaceShelfState<List<MySpaceContentItem>>.empty();
      }
      return MySpaceShelfState<List<MySpaceContentItem>>.data(items);
    });

MySpaceContentShelfState _mapColdAsync<T>(AsyncValue<T> source) {
  if (source.hasError) {
    return MySpaceShelfState<List<MySpaceContentItem>>.error(source.error!);
  }
  return const MySpaceShelfState<List<MySpaceContentItem>>.loading();
}

MySpaceContentShelfState _mapAsyncItems<T>(
  AsyncValue<List<T>> source,
  List<MySpaceContentItem> Function(List<T> values) convert,
) {
  final values = source.valueOrNull;
  if (values != null) {
    final items = List<MySpaceContentItem>.unmodifiable(convert(values));
    if (source.hasError && items.isNotEmpty) {
      return MySpaceShelfState<List<MySpaceContentItem>>.partial(
        data: items,
        error: source.error!,
      );
    }
    if (source.hasError) {
      return MySpaceShelfState<List<MySpaceContentItem>>.error(source.error!);
    }
    if (items.isEmpty) {
      return const MySpaceShelfState<List<MySpaceContentItem>>.empty();
    }
    return MySpaceShelfState<List<MySpaceContentItem>>.data(items);
  }
  if (source.hasError) {
    return MySpaceShelfState<List<MySpaceContentItem>>.error(source.error!);
  }
  return const MySpaceShelfState<List<MySpaceContentItem>>.loading();
}

MySpaceContentItem _continueItem(SavedAnalysis analysis) {
  if (analysis.id.trim().isEmpty) {
    return const MySpaceUnavailableItem(
      id: 'continue-unavailable',
      title: 'Library activity unavailable',
      subtitle:
          'This activity no longer has a usable saved-analysis reference.',
      sourceType: 'Saved analysis',
    );
  }
  final move = analysis.lastViewedPosition;
  return MySpaceAnalysisItem(
    id: 'continue:${analysis.id}',
    title: _analysisTitle(analysis),
    subtitle: analysis.openingName ?? 'Saved analysis',
    status: move >= 0 ? 'Resume at move ${move + 1}' : 'Ready to continue',
    actionLabel: 'Continue analysis',
    analysis: analysis,
    isLiked: false,
  );
}

MySpaceContentItem _likedAnalysisItem(
  SavedAnalysis analysis, {
  required bool isLocked,
}) {
  if (analysis.id.trim().isEmpty) {
    final fallbackId = _nonBlank(analysis.sourceGameId) ?? 'unknown';
    return MySpaceUnavailableItem(
      id: 'like-unavailable:$fallbackId',
      title: 'Liked game unavailable',
      subtitle: 'This like no longer has a usable saved-analysis reference.',
      sourceType: 'Saved analysis',
    );
  }
  return MySpaceAnalysisItem(
    id: 'like:${analysis.id}',
    title: _analysisTitle(analysis),
    subtitle: analysis.openingName ?? 'Liked game',
    status: isLocked ? 'Outside the free 7-day window' : 'Saved in My Likes',
    actionLabel: isLocked ? 'Unlock analysis' : 'Open analysis',
    analysis: analysis,
    isLiked: true,
    isLocked: isLocked,
  );
}

MySpaceContentItem _favoriteEventItem(FavoriteEvent event) {
  final canonicalId = _nonBlank(event.eventId);
  // Current `cal_event_*` values are synthesized from display names by the
  // Calendar surface. They are useful UI keys, but not canonical identity and
  // cannot safely drive the group-broadcast navigation helper.
  if (canonicalId == null || canonicalId.startsWith('cal_event_')) {
    return MySpaceUnavailableItem(
      id: 'event-unavailable:${_stableRowId(event.id)}',
      title: 'Saved event unavailable',
      subtitle: 'This favorite does not have a canonical event reference.',
      sourceType: 'Event',
    );
  }

  final timeControl = _metadataString(event.metadata, const [
    'timeControl',
    'time_control',
  ]);
  final dates = _metadataString(event.metadata, const ['dates', 'dateRange']);
  final subtitle = <String>[
    if (timeControl != null) timeControl,
    if (dates != null) dates,
  ].join(' · ');
  return MySpaceEventItem(
    id: 'event:$canonicalId',
    title: _nonBlank(event.eventName) ?? 'Saved event',
    subtitle: subtitle.isEmpty ? 'Saved event' : subtitle,
    actionLabel: 'Open event',
    event: event,
    imageUrl: _metadataString(event.metadata, const [
      'imageUrl',
      'image_url',
      'logoUrl',
    ]),
  );
}

MySpaceContentItem _libraryItem(LibraryFolder folder) {
  final canonicalId = _nonBlank(folder.id);
  if (canonicalId == null) {
    return const MySpaceUnavailableItem(
      id: 'library-unavailable',
      title: 'Library item unavailable',
      subtitle: 'This item no longer has a canonical Library reference.',
      sourceType: 'Library item',
    );
  }

  final type = folder.isFolder ? 'Folder' : 'Database';
  final ownership = folder.isSubscribed ? 'Subscribed' : 'Your Library';
  return MySpaceLibraryItem(
    id: 'library:$canonicalId',
    title: folder.displayName,
    subtitle: '$ownership · $type',
    actionLabel: folder.isFolder ? 'Open folder' : 'Open database',
    folder: folder,
  );
}

MySpaceContentItem _favoritePlayerItem(FavoritePlayer player) {
  final rawFideId = _nonBlank(player.fideId);
  final fideId = rawFideId == null ? null : int.tryParse(rawFideId);
  if (fideId == null) {
    return MySpaceUnavailableItem(
      id: 'player-unavailable:${_stableRowId(player.id)}',
      title: 'Favorite player unavailable',
      subtitle: 'This favorite does not have a canonical player ID.',
      sourceType: 'Player',
    );
  }

  final title = _metadataString(player.metadata, const ['title']);
  final federation = _metadataString(player.metadata, const [
    'countryCode',
    'country_code',
    'federation',
  ]);
  final rating = _metadataInt(player.metadata, const ['rating']);
  final subtitle = <String>[
    if (title != null) title,
    if (federation != null) federation,
    if (rating != null) '$rating',
  ].join(' · ');
  return MySpacePlayerItem(
    id: 'player:$fideId',
    title: _nonBlank(player.playerName) ?? 'Favorite player',
    subtitle: subtitle.isEmpty ? 'Favorite player' : subtitle,
    actionLabel: 'Open player',
    player: player,
    fideId: fideId,
    playerTitle: title,
    federation: federation,
    rating: rating,
    imageUrl: _metadataString(player.metadata, const [
      'imageUrl',
      'image_url',
      'photoUrl',
      'avatarUrl',
    ]),
  );
}

MySpaceContentItem _studyItem(GamebaseStudySummary study) {
  if (study.status == GamebaseStudyStatus.gone) {
    return MySpaceUnavailableItem(
      id: 'study-removed:${study.canonicalStudyId}',
      title: study.name,
      subtitle: 'This Study is private or no longer available on Lichess.',
      sourceType: 'Lichess Study',
      status: 'Removed from source',
    );
  }

  final opening = study.openings.isEmpty ? null : study.openings.first;
  final author = _nonBlank(study.authorUsername);
  return MySpaceStudyItem(
    id: 'study:${study.canonicalStudyId}',
    title: study.name,
    subtitle: opening ?? (author == null ? 'Lichess Study' : 'By $author'),
    status:
        '${study.chapterCount} ${study.chapterCount == 1 ? 'chapter' : 'chapters'} · ${study.views} views',
    actionLabel: 'View Study',
    study: study,
  );
}

MySpaceContentItem _savedStudyItem(SavedStudyReference saved) {
  final bookmark = saved.bookmark;
  if (saved is UnavailableSavedStudy) {
    final snapshot = bookmark.displaySnapshot;
    return MySpaceUnavailableItem(
      id: 'study-removed:${bookmark.lichessStudyId}',
      title: snapshot.title ?? 'Saved Study unavailable',
      subtitle:
          snapshot.attribution ??
          'This Study is private or no longer available on Lichess.',
      sourceType: 'Lichess Study',
      status: 'Removed from source',
      actionLabel: 'Remove bookmark',
      removableCanonicalStudyId: bookmark.lichessStudyId,
    );
  }

  final available = saved as AvailableSavedStudy;
  final study = available.study;
  final opening = study.openings.isEmpty ? null : study.openings.first;
  final author = _nonBlank(study.authorUsername);
  return MySpaceStudyItem(
    id: 'study:${study.canonicalStudyId}',
    title: study.name,
    subtitle: opening ?? (author == null ? 'Lichess Study' : 'By $author'),
    status:
        bookmark.hasProgress
            ? 'Resume at ply ${bookmark.lastPly}'
            : 'Saved from Lichess',
    actionLabel: 'View on Lichess',
    study: study,
  );
}

MySpaceContentItem _miniatureItem(GamebaseMiniature miniature) {
  final white = _nonBlank(miniature.whiteName) ?? 'White';
  final black = _nonBlank(miniature.blackName) ?? 'Black';
  final opening = _nonBlank(miniature.opening);
  final event = _nonBlank(miniature.event);
  final subtitle = opening ?? event ?? _miniatureTimeControl(miniature);
  final rating = miniature.avgRating;
  return MySpaceMiniatureItem(
    id: 'miniature:${miniature.canonicalGameId}',
    title: '$white vs $black',
    subtitle: subtitle,
    status: <String>[
      '${miniature.finalMoveNumber} moves',
      if (rating != null) '$rating avg',
      _miniatureTimeControl(miniature),
    ].join(' · '),
    actionLabel: 'Open game',
    miniature: miniature,
  );
}

String _miniatureTimeControl(GamebaseMiniature miniature) {
  return switch (miniature.timeControl) {
    MiniatureGameTimeControl.classical => 'Classical',
    MiniatureGameTimeControl.rapid => 'Rapid',
    MiniatureGameTimeControl.blitz => 'Blitz',
  };
}

String _analysisTitle(SavedAnalysis analysis) {
  final title = _nonBlank(analysis.title);
  if (title != null) return title;
  final white = _nonBlank(analysis.whiteName);
  final black = _nonBlank(analysis.blackName);
  if (white != null && black != null) return '$white vs $black';
  return 'Saved analysis';
}

String _stableRowId(String value) => _nonBlank(value) ?? 'unknown';

String? _nonBlank(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

String? _metadataString(Map<String, dynamic> metadata, List<String> keys) {
  for (final key in keys) {
    final value = metadata[key];
    if (value is String) {
      final normalized = _nonBlank(value);
      if (normalized != null) return normalized;
    }
  }
  return null;
}

int? _metadataInt(Map<String, dynamic> metadata, List<String> keys) {
  for (final key in keys) {
    final value = metadata[key];
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) {
      final parsed = int.tryParse(value);
      if (parsed != null) return parsed;
    }
  }
  return null;
}
