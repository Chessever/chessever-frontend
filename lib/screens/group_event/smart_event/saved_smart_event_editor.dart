import 'package:chessever2/providers/favorite_events_provider.dart';
import 'package:chessever2/repository/favorites/models/favorite_event.dart';
import 'package:chessever2/screens/group_event/smart_event/smart_aggregate_event_provider.dart';
import 'package:chessever2/screens/group_event/smart_event/smart_event_shortcut.dart';
import 'package:chessever2/screens/my_space/models/space_shortcut.dart';
import 'package:chessever2/screens/my_space/providers/space_shortcuts_provider.dart';
import 'package:chessever2/utils/smart_event_mutation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Retained by the edit screen so a failed compensation can be retried before
/// another edit. Remote rows are guarded individually, not atomically across
/// tables. No baseline is advanced until ALL writes and readbacks succeed.
class SavedSmartEventEditor {
  SavedSmartEventEditor(this.container);
  final ProviderContainer container;
  final List<Future<void> Function()> _undo = [];
  bool _ownerSet = false;
  String? _owner;
  bool get recoveryRequired => _undo.isNotEmpty;

  Future<void> apply(
    SmartEventRequest old,
    SmartEventRequest updated,
  ) => withSmartEventMutation(container, () async {
    await Future.wait([
      container.read(favoriteEventsProvider.future),
      container.read(spaceShortcutsProvider.future),
    ]);
    final favorites = container.read(favoriteEventsProvider.notifier);
    final pins = container.read(spaceShortcutsProvider.notifier);
    final owner = favorites.smartEventEditUserId;
    if (_ownerSet && owner != _owner) {
      throw StateError(
        'Account changed. Reopen this Smart Event before saving.',
      );
    }
    _ownerSet = true;
    _owner = owner;
    favorites.beginConfirmedSmartEventEdit();
    pins.beginConfirmedSmartEventEdit();
    try {
      await _recover();
      final rows = await favorites.readForSmartEventEdit();
      final shortcuts = await pins.readForSmartEventEdit();
      final oldRows = matchingSmartEventFavorites(rows, old.criteriaKey);
      final targetRows = matchingSmartEventFavorites(rows, updated.criteriaKey);
      final oldPins = shortcuts
          .where(
            (s) =>
                s.kind == SpaceShortcutKind.smartEvent &&
                (s.targetId == old.criteriaKey ||
                    smartEventRequestFromSpaceShortcut(s)?.criteriaKey ==
                        old.criteriaKey),
          )
          .toList();
      final oldPin = oldPins.firstOrNull;
      final targetPin = shortcuts
          .where(
            (s) =>
                s.kind == SpaceShortcutKind.smartEvent &&
                s.targetId == updated.criteriaKey,
          )
          .firstOrNull;

      // Existing target wins its own name, order and metadata. Never
      // unsubscribe it just because the edited source was unstarred.
      if (oldRows.isNotEmpty && old.criteriaKey != updated.criteriaKey) {
        final source = oldRows.first;
        if (targetRows.isEmpty) {
          final metadata = Map<String, dynamic>.of(source.metadata)
            ..remove('eco')
            ..remove('ecoCode')
            ..remove('openingContext')
            ..remove('maxAvgElo')
            ..remove('cal_event_alias')
            ..remove('source_event_id')
            ..addAll(updated.toFavoriteMetadata());
          final replacement = FavoriteEvent(
            id: source.id,
            userId: source.userId,
            eventId: updated.favoriteEventId,
            eventName: source.eventName == old.displayName
                ? updated.displayName
                : source.eventName,
            metadata: metadata,
            createdAt: source.createdAt,
            updatedAt: source.updatedAt,
          );
          await _write(
            () => favorites.writeSmartEventEdit(source, replacement),
            () => favorites.writeSmartEventEdit(replacement, source),
          );
        }
        // Duplicate legacy rows of ONLY the edited criteria collapse.
        for (final row in targetRows.isEmpty ? oldRows.skip(1) : oldRows) {
          await _write(
            () => favorites.writeSmartEventEdit(row, null),
            () => favorites.writeSmartEventEdit(null, row),
          );
        }
      }
      if (oldPin != null && oldPin.targetId != updated.criteriaKey) {
        final replacement = targetPin == null
            ? retargetSmartEventShortcut(oldPin, old, updated)
            : null;
        await _write(
          () => pins.writeSmartEventEdit(oldPin, replacement),
          () => pins.writeSmartEventEdit(replacement, oldPin),
        );
      }
      for (final duplicate in oldPins.skip(1)) {
        if (duplicate.targetId == updated.criteriaKey) continue;
        await _write(
          () => pins.writeSmartEventEdit(duplicate, null),
          () => pins.writeSmartEventEdit(null, duplicate),
        );
      }
      // Exact-store readback, not an optimistic local success claim.
      final finalRows = await favorites.readForSmartEventEdit();
      final finalPins = await pins.readForSmartEventEdit();
      if (old.criteriaKey != updated.criteriaKey &&
          (matchingSmartEventFavorites(finalRows, old.criteriaKey).isNotEmpty ||
              finalPins.any(
                (s) => oldPins.any((oldPin) => s.key == oldPin.key),
              ))) {
        throw StateError('The old saved criteria are still present.');
      }
      if (oldRows.isNotEmpty &&
          matchingSmartEventFavorites(finalRows, updated.criteriaKey).isEmpty) {
        throw StateError('The subscription could not be confirmed.');
      }
      if (oldPin != null &&
          !finalPins.any(
            (s) =>
                s.kind == SpaceShortcutKind.smartEvent &&
                s.targetId == updated.criteriaKey &&
                smartEventRequestFromSpaceShortcut(s)?.criteriaKey ==
                    updated.criteriaKey,
          )) {
        throw StateError('The My Space card could not be confirmed.');
      }
      _undo.clear();
    } catch (_) {
      var recoveryRequired = false;
      try {
        await _recover();
      } catch (_) {
        recoveryRequired = true;
      }
      throw SmartEventSaveFailure(recoveryRequired: recoveryRequired);
    } finally {
      pins.endConfirmedSmartEventEdit();
      favorites.endConfirmedSmartEventEdit();
    }
  });

  Future<void> _write(
    Future<void> Function() forward,
    Future<void> Function() undo,
  ) async {
    // Include the attempted write: a network failure can lose its reply after
    // commit. The guarded undo is idempotent if it never reached the server.
    _undo.add(undo);
    await forward();
  }

  Future<void> _recover() async {
    while (_undo.isNotEmpty) {
      await _undo.last();
      _undo.removeLast();
    }
  }
}

List<FavoriteEvent> matchingSmartEventFavorites(
  List<FavoriteEvent> rows,
  String key,
) => [
  for (final row in rows)
    if (isSmartFavoriteEvent(row) &&
        SmartEventRequest.fromFavoriteEvent(row).criteriaKey == key)
      row,
];

SpaceShortcut retargetSmartEventShortcut(
  SpaceShortcut pin,
  SmartEventRequest old,
  SmartEventRequest updated,
) {
  final draft = smartEventSpaceDraft(updated);
  return SpaceShortcut(
    id: pin.id,
    kind: pin.kind,
    targetId: draft.targetId,
    title: pin.title == old.displayName ? draft.title : pin.title,
    subtitle: pin.subtitle == old.caption ? draft.subtitle : pin.subtitle,
    params: {...pin.params, ...draft.params},
    sortIndex: pin.sortIndex,
    openCount: pin.openCount,
    lastOpenedAt: pin.lastOpenedAt,
    createdAt: pin.createdAt,
  );
}

class SmartEventSaveFailure implements Exception {
  const SmartEventSaveFailure({required this.recoveryRequired});
  final bool recoveryRequired;
  @override
  String toString() => recoveryRequired
      ? 'Save incomplete. Some remote changes could not be restored. Retry to recover, or manage Starred Smart Events before leaving.'
      : 'Could not save the Smart Event. The previous configuration was kept. Please retry.';
}
