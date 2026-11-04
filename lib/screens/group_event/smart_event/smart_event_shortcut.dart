import 'package:chessever2/repository/favorites/models/favorite_event.dart';
import 'package:chessever2/screens/group_event/smart_event/smart_aggregate_event_provider.dart';
import 'package:chessever2/screens/my_space/models/space_shortcut.dart';

/// The pin and subscription share criteria, not the resolved event snapshot.
SpaceShortcut smartEventSpaceDraft(SmartEventRequest request) {
  final metadata = Map<String, dynamic>.of(request.toFavoriteMetadata())
    ..remove('events')
    ..remove('notificationsEnabled');
  return SpaceShortcut.draft(
    kind: SpaceShortcutKind.smartEvent,
    targetId: request.criteriaKey,
    title: request.displayName,
    subtitle: request.caption,
    params: {'request': metadata},
  );
}

SmartEventRequest? smartEventRequestFromSpaceShortcut(SpaceShortcut shortcut) {
  final raw = shortcut.params['request'];
  if (raw is! Map) return null;
  final stamp = shortcut.createdAt ?? DateTime.now();
  return SmartEventRequest.fromFavoriteEvent(
    FavoriteEvent(
      id: shortcut.id,
      userId: '',
      eventId: 'smart_event:v2:${shortcut.targetId}',
      eventName: shortcut.title,
      metadata: Map<String, dynamic>.from(raw),
      createdAt: stamp,
      updatedAt: stamp,
    ),
  );
}
