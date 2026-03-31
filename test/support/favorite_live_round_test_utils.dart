class FavoriteLiveSnapshot {
  FavoriteLiveSnapshot({
    required Set<String> liveNames,
    Map<String, int>? ratings,
    Map<String, String>? opponents,
  }) : liveNames = liveNames,
       liveNameLookup =
           liveNames.map((name) => name.trim().toLowerCase()).toSet(),
       ratings = ratings ?? <String, int>{},
       opponents = opponents ?? <String, String>{};

  final Set<String> liveNames;
  final Set<String> liveNameLookup;
  final Map<String, int> ratings;
  final Map<String, String> opponents;
}

class RecipientCandidate {
  const RecipientCandidate({
    required this.userId,
    required this.isEventFav,
    required this.isPlayerFav,
    this.pushEnabled = true,
    this.favoriteEventAlerts = true,
    this.favoritePlayerAlerts = true,
    this.fpClassical = true,
    this.fpRapid = true,
    this.fpBlitz = true,
    this.seClassical = true,
    this.seRapid = true,
    this.seBlitz = true,
  });

  final String userId;
  final bool isEventFav;
  final bool isPlayerFav;
  final bool pushEnabled;
  final bool favoriteEventAlerts;
  final bool favoritePlayerAlerts;
  final bool fpClassical;
  final bool fpRapid;
  final bool fpBlitz;
  final bool seClassical;
  final bool seRapid;
  final bool seBlitz;
}

class RecipientSplit {
  const RecipientSplit({
    required this.playerRecipients,
    required this.eventRecipients,
  });

  final List<String> playerRecipients;
  final List<String> eventRecipients;
}

class FavoriteLiveBatch {
  const FavoriteLiveBatch({required this.body, required this.recipients});

  final String body;
  final List<String> recipients;
}

class FavoriteLiveAggregation {
  const FavoriteLiveAggregation({
    required this.batches,
    required this.recipientsToRecord,
  });

  final List<FavoriteLiveBatch> batches;
  final List<String> recipientsToRecord;
}

String formatPlayerName(String name) {
  final trimmed = name.trim();
  if (trimmed.contains(',')) return trimmed;
  final parts = trimmed.split(RegExp(r'\s+'));
  if (parts.length <= 1) return trimmed;
  if (parts.last.length <= 2 && parts.length >= 2) return trimmed;
  final last = parts.last;
  final first = parts.sublist(0, parts.length - 1).join(' ');
  return '$last, $first';
}

RecipientSplit splitRoundRecipients(
  List<RecipientCandidate> candidates, {
  String? timeControl,
}) {
  final playerRecipients = <String>{};
  final eventRecipients = <String>{};

  for (final candidate in candidates) {
    if (!candidate.pushEnabled) continue;

    final playerAllowed = candidate.favoritePlayerAlerts;
    final eventAllowed = candidate.favoriteEventAlerts;

    if (timeControl != null) {
      final fpBlocked =
          timeControl == 'classical'
              ? !candidate.fpClassical
              : timeControl == 'rapid'
              ? !candidate.fpRapid
              : !candidate.fpBlitz;
      final seBlocked =
          timeControl == 'classical'
              ? !candidate.seClassical
              : timeControl == 'rapid'
              ? !candidate.seRapid
              : !candidate.seBlitz;

      if (candidate.isPlayerFav && playerAllowed && fpBlocked) {
        if (candidate.isEventFav && eventAllowed && !seBlocked) {
          eventRecipients.add(candidate.userId);
        }
        continue;
      }

      if (candidate.isEventFav &&
          !candidate.isPlayerFav &&
          eventAllowed &&
          seBlocked) {
        continue;
      }
    }

    if (candidate.isPlayerFav && playerAllowed) {
      playerRecipients.add(candidate.userId);
      continue;
    }

    if (candidate.isEventFav &&
        eventAllowed &&
        !playerRecipients.contains(candidate.userId)) {
      eventRecipients.add(candidate.userId);
    }
  }

  return RecipientSplit(
    playerRecipients: playerRecipients.toList(),
    eventRecipients: eventRecipients.toList(),
  );
}

FavoriteLiveAggregation buildFavoriteLiveAggregation({
  required List<String> candidateUserIds,
  required Map<String, List<String>> playerFavoriteMap,
  required FavoriteLiveSnapshot liveSnapshot,
  required String roundName,
  Set<String>? alreadyCoveredUserIds,
}) {
  final alreadyCovered = alreadyCoveredUserIds ?? <String>{};
  final messageBatches = <String, List<String>>{};
  final recipientsToRecord = <String>[];

  for (final userId in candidateUserIds) {
    if (alreadyCovered.contains(userId)) continue;

    final favorites =
        (playerFavoriteMap[userId] ?? const <String>[])
            .where(
              (name) => liveSnapshot.liveNameLookup.contains(
                name.trim().toLowerCase(),
              ),
            )
            .toList();
    if (favorites.isEmpty) continue;

    favorites.sort((a, b) {
      final ra = liveSnapshot.ratings[a] ?? 0;
      final rb = liveSnapshot.ratings[b] ?? 0;
      return rb.compareTo(ra);
    });

    late final String body;
    if (favorites.length == 1) {
      final favorite = formatPlayerName(favorites.first);
      final opponent =
          formatPlayerName(liveSnapshot.opponents[favorites.first] ?? 'Opponent');
      body = '$favorite vs $opponent is live.';
    } else if (favorites.length == 2) {
      body =
          '${formatPlayerName(favorites[0])} and ${formatPlayerName(favorites[1])} are live in $roundName.';
    } else {
      body =
          '${formatPlayerName(favorites[0])}, ${formatPlayerName(favorites[1])}, and others are live in $roundName.';
    }

    messageBatches.putIfAbsent(body, () => <String>[]).add(userId);
    recipientsToRecord.add(userId);
  }

  return FavoriteLiveAggregation(
    batches:
        messageBatches.entries
            .map(
              (entry) =>
                  FavoriteLiveBatch(body: entry.key, recipients: entry.value),
            )
            .toList(),
    recipientsToRecord: recipientsToRecord,
  );
}
