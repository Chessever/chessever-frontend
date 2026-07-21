// Canonical event-id helpers shared by Calendar, For You, Current, and
// notification dispatch.
//
// Notification outbox / onesignal-dispatch match recipients with exact
// equality on `user_favorite_events.event_id == group_broadcasts.id`.
// Calendar community cards historically stored synthetic `cal_event_*` ids.
// These helpers keep star state and dispatch aligned across surfaces.

/// Sanitize an event display name the same way calendar cards build their id.
String sanitizeEventNameForFavoriteId(String name) {
  return name
      .replaceAll(' ', '_')
      .replaceAll(RegExp(r'[^\w\-]'), '')
      .toLowerCase();
}

/// Synthetic calendar / community favorite id: `cal_event_<sanitized_name>`.
String calendarEventFavoriteIdFromName(String name) {
  return 'cal_event_${sanitizeEventNameForFavoriteId(name)}';
}

/// True when [eventId] is a synthetic calendar (or legacy TWIC) id that will
/// never match `notification_outbox.group_broadcast_id` unless remapped.
bool isSyntheticFavoriteEventId(String eventId) {
  return eventId.startsWith('cal_event_') || eventId.startsWith('twic_event_');
}

/// All id strings that should be treated as "this event" for star UI and
/// recipient resolution, given a stored or card [eventId] and optional
/// display [eventName].
///
/// Always includes [eventId]. When [eventName] is non-empty also includes the
/// calendar alias so a Lichess broadcast star and a calendar card for the same
/// tournament share one favorite state.
Set<String> favoriteEventIdCandidates(
  String eventId, {
  String? eventName,
}) {
  final ids = <String>{eventId};
  final name = eventName?.trim();
  if (name != null && name.isNotEmpty) {
    ids.add(calendarEventFavoriteIdFromName(name));
  }
  return ids;
}

/// Whether a stored favorite row matches a card / outbox id.
///
/// Checks:
/// 1. exact `eventId`
/// 2. metadata aliases written on star (`cal_event_alias`, `source_event_id`)
/// 3. calendar alias of the favorite's display name vs the card id
bool favoriteEventMatchesId({
  required String storedEventId,
  required String candidateId,
  String? eventName,
  Map<String, dynamic>? metadata,
}) {
  if (storedEventId == candidateId) return true;

  final meta = metadata ?? const <String, dynamic>{};
  final calAlias = meta['cal_event_alias'] as String?;
  if (calAlias != null && calAlias == candidateId) return true;
  final sourceId = meta['source_event_id'] as String?;
  if (sourceId != null && sourceId == candidateId) return true;

  final name = eventName?.trim();
  if (name != null && name.isNotEmpty) {
    if (calendarEventFavoriteIdFromName(name) == candidateId) return true;
  }

  // Card is a real GBID, favorite is still a cal_event_* with same name alias.
  if (isSyntheticFavoriteEventId(storedEventId) &&
      !isSyntheticFavoriteEventId(candidateId) &&
      name != null &&
      name.isNotEmpty) {
    // Cannot prove GBID equality without a lookup; name alias is the bridge
    // only when the card is the calendar form. Leave GBID→cal to metadata.
  }

  return false;
}
