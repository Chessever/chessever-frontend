import 'package:chessever2/repository/gamebase/gamebase_repository.dart'
    show GamebaseExternalPlayerSource;
import 'package:flutter/foundation.dart';
import 'package:chessever2/screens/gamebase/models/gamebase_player.dart';

/// Where a Prep account's games come from.
enum PrepSource {
  chessever('ChessEver'),
  lichess('Lichess'),
  chesscom('Chess.com'),
  manual('PGN');

  const PrepSource(this.label);
  final String label;
  bool get online => this == lichess || this == chesscom;
  static const playerSources = [lichess, chessever, chesscom];

  GamebaseExternalPlayerSource get gamebase => switch (this) {
    PrepSource.lichess => GamebaseExternalPlayerSource.lichess,
    PrepSource.chesscom => GamebaseExternalPlayerSource.chesscom,
    _ => throw StateError('$label is not an online account'),
  };

  String profileUrl(String username) => switch (this) {
    PrepSource.lichess => 'https://lichess.org/@/$username',
    PrepSource.chesscom => 'https://www.chess.com/member/$username',
    _ => '',
  };

  static PrepSource? tryParse(Object? raw) {
    for (final value in values) {
      if (value.name == raw) return value;
    }
    return null;
  }
}

/// Which My Prep tab a profile belongs to. A favorite is a curated famous
/// player the reader opened; it is kept so its games stay downloaded.
enum PrepKind {
  mine,
  opponent,
  favorite;

  static PrepKind tryParse(Object? raw) {
    for (final value in values) {
      if (value.name == raw) return value;
    }
    return PrepKind.opponent;
  }
}

/// The clock categories the server can select, as desktop Prep offers them.
/// Chess.com calls correspondence Daily.
enum PrepTimeControl {
  ultrabullet('UltraBullet'),
  bullet('Bullet'),
  blitz('Blitz'),
  rapid('Rapid'),
  classical('Classical'),
  correspondence('Correspondence');

  const PrepTimeControl(this.label);
  final String label;

  String labelFor(PrepSource? source) =>
      source == PrepSource.chesscom && this == correspondence ? 'Daily' : label;

  /// The category for a provider rating key (`blitz`, `daily`, ...).
  static PrepTimeControl? forRatingKey(String key) {
    if (key == 'daily') return correspondence;
    for (final value in values) {
      if (value.name == key) return value;
    }
    return null;
  }

  /// Which categories a provider actually has.
  static List<PrepTimeControl> offeredBy(PrepSource source) => switch (source) {
    PrepSource.lichess => values,
    PrepSource.chesscom => const [bullet, blitz, rapid, correspondence],
    // Over-the-board games: the three FIDE rating lists.
    PrepSource.chessever => const [blitz, rapid, classical],
    _ => const [],
  };
}

/// How far back a profile's download reaches. Relative ranges anchor to the
/// first day of a month, so the server sees the same selection (and serves
/// the same cached snapshot) all month instead of a new one every day.
enum PrepDateRange {
  months3('Last 3 months', 3),
  year('Last 12 months', 12),
  years3('Last 3 years', 36),
  all('All time', null),
  custom('Custom dates', null);

  const PrepDateRange(this.label, this.months);
  final String label;
  final int? months;

  DateTime? fromDate(DateTime now) {
    final back = months;
    if (back == null) return null;
    final utc = now.toUtc();
    return DateTime.utc(utc.year, utc.month - back + 1, 1);
  }

  static PrepDateRange tryParse(Object? raw) {
    for (final value in values) {
      if (value.name == raw) return value;
    }
    return PrepDateRange.year;
  }
}

/// What to download for an account. Empty [timeControls] means every clock.
@immutable
class PrepDownloadPreferences {
  const PrepDownloadPreferences({
    this.timeControls = const {},
    this.range = PrepDateRange.year,
    this.fromDate,
    this.toDate,
  });

  final Set<PrepTimeControl> timeControls;
  final PrepDateRange range;
  final DateTime? fromDate;
  final DateTime? toDate;

  /// What the add dialog proposes for a new account. Online accounts are
  /// mostly bullet by volume, so they start on the clocks worth preparing
  /// against; ChessEver's over-the-board games start on every clock.
  static PrepDownloadPreferences initialFor(PrepSource source) => source.online
      ? const PrepDownloadPreferences(
          timeControls: {PrepTimeControl.blitz, PrepTimeControl.rapid},
        )
      : const PrepDownloadPreferences();

  bool get isFiltered => timeControls.isNotEmpty || range != PrepDateRange.all;

  int? fromMs(DateTime now) =>
      (range == PrepDateRange.custom
              ? _calendarDate(fromDate)
              : range.fromDate(now))
          ?.millisecondsSinceEpoch;
  int? get untilMs => range == PrepDateRange.custom && toDate != null
      ? _calendarDate(
          toDate,
        )!.add(const Duration(days: 1)).millisecondsSinceEpoch
      : null;
  String? get validationError =>
      range == PrepDateRange.custom &&
          fromDate != null &&
          toDate != null &&
          _calendarDate(fromDate)!.isAfter(_calendarDate(toDate)!)
      ? 'The end date must be on or after the starting date.'
      : null;

  /// A stable key for the selection the server will see this month.
  String scopeKey(DateTime now) {
    final clocks = PrepTimeControl.values
        .where(timeControls.contains)
        .map((t) => t.name)
        .join(',');
    return '${clocks.isEmpty ? 'all' : clocks}|${fromMs(now) ?? 'all'}'
        '${untilMs == null ? '' : '|$untilMs'}';
  }

  /// The clocks to download, in display order. Empty means every clock.
  List<PrepTimeControl> get orderedTimeControls =>
      PrepTimeControl.values.where(timeControls.contains).toList();

  String get rangeLabel => range == PrepDateRange.custom
      ? '${fromDate == null ? 'Any start' : prepDateText(fromDate!)} to ${toDate == null ? 'today' : prepDateText(toDate!)}'
      : range.label;

  PrepDownloadPreferences copyWith({
    Set<PrepTimeControl>? timeControls,
    PrepDateRange? range,
    DateTime? fromDate,
    DateTime? toDate,
  }) => PrepDownloadPreferences(
    timeControls: timeControls ?? this.timeControls,
    range: range ?? this.range,
    fromDate: fromDate ?? this.fromDate,
    toDate: toDate ?? this.toDate,
  );

  Map<String, Object?> toJson() => {
    'timeControls': PrepTimeControl.values
        .where(timeControls.contains)
        .map((t) => t.name)
        .toList(),
    'range': range.name,
    'fromDate': fromDate == null ? null : prepDateText(fromDate!),
    'toDate': toDate == null ? null : prepDateText(toDate!),
  };

  static PrepDownloadPreferences fromJson(Object? raw) {
    if (raw is! Map) return const PrepDownloadPreferences();
    final clocks = raw['timeControls'];
    return PrepDownloadPreferences(
      timeControls: {
        for (final t in PrepTimeControl.values)
          if (clocks is List && clocks.contains(t.name)) t,
      },
      range: PrepDateRange.tryParse(raw['range']),
      fromDate: _prepDate(raw['fromDate']),
      toDate: _prepDate(raw['toDate']),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is PrepDownloadPreferences &&
      setEquals(other.timeControls, timeControls) &&
      other.range == range &&
      _calendarDate(other.fromDate) == _calendarDate(fromDate) &&
      _calendarDate(other.toDate) == _calendarDate(toDate);

  @override
  int get hashCode => Object.hash(
    Object.hashAllUnordered(timeControls),
    range,
    _calendarDate(fromDate),
    _calendarDate(toDate),
  );
}

/// A database player, online account or imported PGN inside a profile.
@immutable
class PrepAccount {
  const PrepAccount({
    required this.source,
    required this.username,
    this.displayName,
    this.avatarUrl,
    this.title,
    this.country,
    this.ratings = const {},
    this.preferences = const PrepDownloadPreferences(),
    this.lastSyncAtMs,
    this.syncedScope,
    this.gameCount = 0,
    this.error,
    this.cloudDatabaseId,
    this.cloudSyncedTs,
    this.cloudSyncedCount = 0,
    this.externalId,
    this.fideId,
    this.playerAliases = const [],
  });

  final PrepSource source;
  final String username;
  final String? displayName;
  final String? avatarUrl;
  final String? title;
  final String? country;
  final String? externalId;
  final String? fideId;
  final List<String> playerAliases;

  factory PrepAccount.fromPlayer(GamebasePlayer player) => PrepAccount(
    source: PrepSource.chessever,
    username: player.name,
    externalId: player.id,
    fideId: (int.tryParse(player.fideId) ?? 0) > 0 ? player.fideId : null,
    displayName: player.displayName,
    title: player.title,
    country: player.fed,
    playerAliases: [player.name, player.displayName],
    ratings: {
      if (player.ratingClassical case final r?) 'classical': r,
      if (player.ratingRapid case final r?) 'rapid': r,
      if (player.ratingBlitz case final r?) 'blitz': r,
    },
    preferences: const PrepDownloadPreferences(range: PrepDateRange.all),
  );

  /// Rating per provider category name (`blitz`, `rapid`, `bullet`, ...).
  final Map<String, int> ratings;
  final PrepDownloadPreferences preferences;
  final int? lastSyncAtMs;

  /// [PrepDownloadPreferences.scopeKey] the stored games were downloaded
  /// with. A different current scope replaces them instead of merging.
  final String? syncedScope;
  final int gameCount;
  final String? error;

  /// The cloud Library database this account's games are saved to, when
  /// the reader saved the player to the cloud (Premium).
  final String? cloudDatabaseId;

  /// The newest game already in [cloudDatabaseId], as yyyymmddHHMMSS: the
  /// next cloud sync uploads only games played after it.
  final int? cloudSyncedTs;
  final int cloudSyncedCount;

  /// The selection the stored games should hold this month. ChessEver's
  /// whole-player export keeps the scope it had before it could be narrowed.
  String downloadScope(DateTime now) => source != PrepSource.chessever
      ? preferences.scopeKey(now)
      : preferences.isFiltered
      ? 'chessever:${preferences.scopeKey(now)}'
      : 'chessever:all';

  /// Case-insensitive identity, since both providers treat names that way.
  String get key => '${source.name}:${(externalId ?? username).toLowerCase()}';

  String get profileUrl => source.profileUrl(username);

  int? get bestRating {
    for (final key
        in source == PrepSource.chessever
            ? const ['classical', 'rapid', 'blitz']
            : const ['blitz', 'rapid', 'bullet', 'classical']) {
      final value = ratings[key];
      if (value != null && value > 0) return value;
    }
    return null;
  }

  PrepAccount copyWith({
    String? displayName,
    String? avatarUrl,
    String? title,
    String? country,
    Map<String, int>? ratings,
    PrepDownloadPreferences? preferences,
    int? lastSyncAtMs,
    String? syncedScope,
    int? gameCount,
    String? error,
    bool clearError = false,
    String? cloudDatabaseId,
    int? cloudSyncedTs,
    int? cloudSyncedCount,
    bool clearCloud = false,
    List<String>? playerAliases,
  }) => PrepAccount(
    source: source,
    username: username,
    displayName: displayName ?? this.displayName,
    avatarUrl: avatarUrl ?? this.avatarUrl,
    title: title ?? this.title,
    country: country ?? this.country,
    externalId: externalId,
    fideId: fideId,
    playerAliases: playerAliases ?? this.playerAliases,
    ratings: ratings ?? this.ratings,
    preferences: preferences ?? this.preferences,
    lastSyncAtMs: lastSyncAtMs ?? this.lastSyncAtMs,
    syncedScope: syncedScope ?? this.syncedScope,
    gameCount: gameCount ?? this.gameCount,
    error: clearError ? null : (error ?? this.error),
    cloudDatabaseId: clearCloud
        ? null
        : (cloudDatabaseId ?? this.cloudDatabaseId),
    cloudSyncedTs: clearCloud ? null : (cloudSyncedTs ?? this.cloudSyncedTs),
    cloudSyncedCount: clearCloud
        ? 0
        : (cloudSyncedCount ?? this.cloudSyncedCount),
  );

  Map<String, Object?> toJson() => {
    'source': source.name,
    'username': username,
    'displayName': displayName,
    'avatarUrl': avatarUrl,
    'title': title,
    'country': country,
    'externalId': externalId,
    'fideId': fideId,
    'playerAliases': playerAliases,
    'ratings': ratings,
    'preferences': preferences.toJson(),
    'lastSyncAtMs': lastSyncAtMs,
    'syncedScope': syncedScope,
    'gameCount': gameCount,
    'error': error,
    'cloudDatabaseId': cloudDatabaseId,
    'cloudSyncedTs': cloudSyncedTs,
    'cloudSyncedCount': cloudSyncedCount,
  };

  static PrepAccount? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final source = PrepSource.tryParse(raw['source']);
    final username = raw['username']?.toString().trim() ?? '';
    if (source == null || username.isEmpty) return null;
    final ratings = <String, int>{};
    final rawRatings = raw['ratings'];
    if (rawRatings is Map) {
      for (final entry in rawRatings.entries) {
        final value = entry.value;
        if (value is int) ratings[entry.key.toString()] = value;
      }
    }
    return PrepAccount(
      source: source,
      username: username,
      displayName: _text(raw['displayName']),
      avatarUrl: _text(raw['avatarUrl']),
      title: _text(raw['title']),
      country: _text(raw['country']),
      externalId: _text(raw['externalId']),
      fideId: _text(raw['fideId']),
      playerAliases: raw['playerAliases'] is List
          ? (raw['playerAliases'] as List).whereType<String>().toList()
          : const [],
      ratings: ratings,
      // A ChessEver account saved without options holds every game.
      preferences: source == PrepSource.chessever && raw['preferences'] is! Map
          ? const PrepDownloadPreferences(range: PrepDateRange.all)
          : PrepDownloadPreferences.fromJson(raw['preferences']),
      lastSyncAtMs: raw['lastSyncAtMs'] is int
          ? raw['lastSyncAtMs'] as int
          : null,
      syncedScope: _text(raw['syncedScope']),
      gameCount: raw['gameCount'] is int ? raw['gameCount'] as int : 0,
      error: _text(raw['error']),
      cloudDatabaseId: _text(raw['cloudDatabaseId']),
      cloudSyncedTs: raw['cloudSyncedTs'] is int
          ? raw['cloudSyncedTs'] as int
          : null,
      cloudSyncedCount: raw['cloudSyncedCount'] is int
          ? raw['cloudSyncedCount'] as int
          : 0,
    );
  }
}

/// A person being prepared: the user themself (My games) or an opponent,
/// with optional sources whose games are read together.
@immutable
class PrepProfile {
  const PrepProfile({
    required this.id,
    required this.kind,
    required this.name,
    required this.createdAtMs,
    this.accounts = const [],
    this.favoriteId,
    this.cloudFolderId,
    this.fideIdentity,
  });

  final String id;
  final PrepKind kind;
  final String name;
  final int createdAtMs;
  final List<PrepAccount> accounts;

  /// Retained after detaching a database source, as on desktop Prepare.
  final String? fideIdentity;

  /// Set when the profile was added from Favorites.
  final String? favoriteId;

  /// The cloud Library folder this player is saved to (Premium). Each
  /// account's games go to their own database inside it, as on desktop.
  final String? cloudFolderId;

  bool get savedToCloud => cloudFolderId != null;
  String? get fideId =>
      fideIdentity ??
      accounts.map((a) => a.fideId).whereType<String>().firstOrNull;
  PrepAccount? get databaseAccount =>
      accounts.where((a) => a.source == PrepSource.chessever).firstOrNull;

  String? get title {
    if (databaseAccount?.title != null) return databaseAccount!.title;
    for (final account in accounts) {
      final title = account.title;
      if (title != null && title.isNotEmpty) return title;
    }
    return null;
  }

  String? get avatarUrl {
    for (final account in accounts) {
      final url = account.avatarUrl;
      if (url != null && url.isNotEmpty) return url;
    }
    return null;
  }

  String? get country {
    if (databaseAccount?.country != null) return databaseAccount!.country;
    for (final account in accounts) {
      final country = account.country;
      if (country != null && country.isNotEmpty) return country;
    }
    return null;
  }

  int get gameCount => accounts.fold(0, (sum, a) => sum + a.gameCount);

  int? get lastSyncAtMs {
    int? latest;
    for (final account in accounts) {
      final at = account.lastSyncAtMs;
      if (at != null && (latest == null || at > latest)) latest = at;
    }
    return latest;
  }

  /// Names that identify this person in a game's White/Black tags. Online
  /// handles stay exact. A database or PGN player is also known, as on
  /// desktop, by the profile's name, without a leading title and with the
  /// word order turned round (`Carlsen, Magnus` / `Magnus Carlsen`).
  /// The index compares them all without case, spacing or punctuation.
  Set<String> get aliases {
    final aliases = <String>{};
    void add(String raw) {
      final clean = raw.trim().toLowerCase();
      if (clean.isEmpty) return;
      final untitled = _withoutTitles(clean);
      for (final base in {clean, untitled}) {
        if (base.isEmpty) continue;
        aliases.add(base);
        final words = base
            .split(base.contains(',') ? ',' : RegExp(r'\s+'))
            .map((w) => w.trim())
            .where((w) => w.isNotEmpty)
            .toList();
        if (words.length < 2) continue;
        aliases.add(
          base.contains(',')
              ? '${words.skip(1).join(' ')} ${words.first}'
              : '${words.last} ${words.take(words.length - 1).join(' ')}',
        );
      }
    }

    if (accounts.any((a) => !a.source.online)) add(name);
    for (final account in accounts) {
      for (final raw in {account.username, ...account.playerAliases}) {
        if (account.source.online) {
          final handle = raw.trim().toLowerCase();
          if (handle.isNotEmpty) aliases.add(handle);
          continue;
        }
        add(raw);
        // Database exports also abbreviate the given name.
        if (account.source != PrepSource.chessever) continue;
        final parts = raw.trim().toLowerCase().split(',');
        if (parts.length != 2) continue;
        final family = parts.first.trim();
        final given = parts.last.trim();
        if (family.isEmpty || given.isEmpty) continue;
        aliases.add('$family,${String.fromCharCode(given.runes.first)}');
      }
    }
    return aliases;
  }

  static final _titles = RegExp(
    r'^(?:gm|wgm|im|wim|fm|wfm|cm|wcm|nm|wnm|agm|aim|afm|acm)\.?\s+',
  );

  static String _withoutTitles(String name) {
    var clean = name;
    while (true) {
      final next = clean.replaceFirst(_titles, '').trim();
      if (next == clean) return clean;
      clean = next;
    }
  }

  PrepProfile copyWith({
    String? name,
    List<PrepAccount>? accounts,
    PrepKind? kind,
    String? cloudFolderId,
    bool clearCloud = false,
  }) => PrepProfile(
    id: id,
    kind: kind ?? this.kind,
    name: name ?? this.name,
    createdAtMs: createdAtMs,
    accounts: accounts ?? this.accounts,
    fideIdentity:
        fideId ??
        accounts?.map((a) => a.fideId).whereType<String>().firstOrNull,
    favoriteId: favoriteId,
    cloudFolderId: clearCloud ? null : (cloudFolderId ?? this.cloudFolderId),
  );

  PrepProfile replaceAccount(PrepAccount account) => copyWith(
    accounts: [for (final a in accounts) a.key == account.key ? account : a],
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'kind': kind.name,
    'name': name,
    'createdAtMs': createdAtMs,
    'accounts': [for (final a in accounts) a.toJson()],
    'fideIdentity': fideId,
    'favoriteId': favoriteId,
    'cloudFolderId': cloudFolderId,
  };

  static PrepProfile? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = _text(raw['id']);
    final name = _text(raw['name']);
    if (id == null || name == null) return null;
    final rawAccounts = raw['accounts'];
    return PrepProfile(
      id: id,
      kind: PrepKind.tryParse(raw['kind']),
      name: name,
      fideIdentity: _text(raw['fideIdentity']),
      createdAtMs: raw['createdAtMs'] is int ? raw['createdAtMs'] as int : 0,
      accounts: [
        if (rawAccounts is List)
          for (final a in rawAccounts) ?PrepAccount.fromJson(a),
      ],
      favoriteId: _text(raw['favoriteId']),
      cloudFolderId: _text(raw['cloudFolderId']),
    );
  }
}

String? _text(Object? raw) {
  final text = raw?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}

String prepDateText(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

DateTime? _prepDate(Object? value) {
  final parsed = DateTime.tryParse('${value}T00:00:00Z');
  return parsed != null && prepDateText(parsed) == value ? parsed : null;
}

DateTime? _calendarDate(DateTime? value) =>
    value == null ? null : DateTime.utc(value.year, value.month, value.day);
