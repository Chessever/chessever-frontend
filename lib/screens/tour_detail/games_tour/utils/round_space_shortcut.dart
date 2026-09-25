import 'package:chessever2/repository/supabase/group_broadcast/group_broadcast.dart';
import 'package:chessever2/screens/gamebase/event_view/gamebase_virtual_event_id.dart';
import 'package:chessever2/screens/group_event/model/about_tour_model.dart';
import 'package:chessever2/screens/group_event/model/tour_event_card_model.dart';
import 'package:chessever2/screens/my_space/models/space_shortcut.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_app_bar_view_model.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_mode_provider.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_screen_provider.dart';
import 'package:chessever2/widgets/event_card/event_context_menu.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// The My Space shortcut for one round of an event. Every surface that pins a
/// round (the Games tab round header, the round dropdown, the event 3-dot)
/// builds it here, so the same round pinned from two places dedupes.
///
/// targetId is the round row's own id, the one the Games tab selects and
/// scrolls to. Knockout stages can be synthetic rows that no round lookup can
/// resolve, which is why [tourId] always rides along: the opener finds the
/// event through the tour and hands the id back to the Games tab as is.
///
/// Returns null when there is nothing the opener could reopen: no round id, no
/// event to open it in, or a gamebase-only virtual event (the opener resolves
/// real broadcasts only).
SpaceShortcut? roundSpaceDraft({
  required GamesAppBarModel round,
  required String? tourId,
  String? groupBroadcastId,
  String? eventName,
}) {
  final roundId = round.id.trim();
  final tour = _clean(tourId);
  final group = _clean(groupBroadcastId);
  if (roundId.isEmpty || (tour == null && group == null)) return null;
  if (isVirtualGamebaseId(tour) ||
      isVirtualGamebaseId(group) ||
      isVirtualGamebaseId(roundId)) {
    return null;
  }

  final name = _clean(round.name);
  final event = _clean(eventName);
  final sourceRoundIds = round.sourceRoundIds
      .map((id) => id.trim())
      .where((id) => id.isNotEmpty && id != roundId)
      .toList(growable: false);

  return SpaceShortcut.draft(
    kind: SpaceShortcutKind.round,
    targetId: roundId,
    title: name ?? 'Round',
    subtitle: event,
    params: {
      if (tour != null) 'tourId': tour,
      if (group != null) 'groupBroadcastId': group,
      if (event != null) 'eventName': event,
      if (sourceRoundIds.isNotEmpty) 'sourceRoundIds': sourceRoundIds,
    },
  );
}

/// [roundSpaceDraft] for a round of the event that is open right now, reading
/// the tour and event from the tournament detail state.
SpaceShortcut? currentEventRoundSpaceDraft(
  WidgetRef ref,
  GamesAppBarModel round,
) {
  final about = ref.read(tourDetailScreenProvider).valueOrNull?.aboutTourModel;
  final broadcast = ref.read(selectedBroadcastModelProvider);
  final tourName = _clean(about?.name);
  return roundSpaceDraft(
    round: round,
    tourId: about?.id,
    groupBroadcastId: _clean(about?.groupBroadcastId) ?? broadcast?.id,
    eventName: tourName ?? _clean(broadcast?.name),
  );
}

/// The event that is open in the tournament detail screen, as a My Space
/// shortcut. Same target as the event card's pin (the group broadcast id), so
/// pinning from either place dedupes; it also remembers the category on
/// screen (`tourId`) so the pin reopens there.
///
/// A gamebase-only virtual event pins by its virtual id, which the opener
/// reopens through the same tournament screen. Null only when there is no
/// event id at all.
SpaceShortcut? tournamentEventSpaceDraft({
  required GroupBroadcast? broadcast,
  required AboutTourModel about,
}) {
  final groupId = _clean(broadcast?.id) ?? _clean(about.groupBroadcastId);
  if (groupId == null) return null;

  final dates = _clean(about.date);
  final location = _clean(about.location);
  final timeControl = _clean(about.timeControl);
  if (isVirtualGamebaseId(groupId)) {
    final name =
        _clean(broadcast?.name) ??
        eventNameFromVirtualId(groupId) ??
        _clean(about.name) ??
        'Event';
    return SpaceShortcut.draft(
      kind: SpaceShortcutKind.event,
      targetId: groupId,
      title: name,
      subtitle: dates,
      params: {
        'source': 'gamebase',
        'eventName': name,
        if (timeControl != null) 'timeControl': timeControl,
        if (dates != null) 'dates': dates,
        if (location != null) 'location': location,
      },
    );
  }

  final SpaceShortcut base;
  if (broadcast != null && broadcast.id.trim() == groupId) {
    base = eventSpaceDraft(
      GroupEventCardModel.fromGroupBroadcast(broadcast, const <String>[]),
    );
  } else {
    base = SpaceShortcut.draft(
      kind: SpaceShortcutKind.event,
      targetId: groupId,
      title: _clean(about.name) ?? 'Event',
      subtitle: dates,
      params: {
        'eventSource': EventSource.lichessBroadcast.name,
        if (timeControl != null) 'timeControl': timeControl,
        if (dates != null) 'dates': dates,
        if (location != null) 'location': location,
      },
    );
  }

  final tourId = _clean(about.id);
  if (tourId == null || isVirtualGamebaseId(tourId)) return base;
  return base.copyWith(params: {...base.params, 'tourId': tourId});
}

/// How a round reads inside a menu label ("Add Round 5 to My Space"). Long
/// stage names fall back to "round" so the label never ellipsizes into
/// something ambiguous.
String spaceRoundLabelName(String roundName) {
  final name = roundName.trim();
  if (name.isEmpty || name.length > 18) return 'round';
  return name;
}

String? _clean(String? value) {
  final trimmed = value?.trim() ?? '';
  return trimmed.isEmpty ? null : trimmed;
}
