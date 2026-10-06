import 'package:chessever2/repository/gamebase/gamebase_repository.dart'
    show GamebaseExternalPlayerSource;
import 'package:flutter/foundation.dart';

/// Where a Prep account's games come from.
enum PrepSource {
  lichess('Lichess'),
  chesscom('Chess.com');

  const PrepSource(this.label);
  final String label;

  GamebaseExternalPlayerSource get gamebase => switch (this) {
    PrepSource.lichess => GamebaseExternalPlayerSource.lichess,
    PrepSource.chesscom => GamebaseExternalPlayerSource.chesscom,
  };

  String profileUrl(String username) => switch (this) {
    PrepSource.lichess => 'https://lichess.org/@/$username',
    PrepSource.chesscom => 'https://www.chess.com/member/$username',
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

  /// Which categories a provider actually has.
  static List<PrepTimeControl> offeredBy(PrepSource source) => switch (source) {
    PrepSource.lichess => values,
    PrepSource.chesscom => const [bullet, blitz, rapid, correspondence],
  };
}

/// How far back a profile's download reaches. Relative ranges anchor to the
/// first day of a month, so the server sees the same selection (and serves
/// the same cached snapshot) all month instead of a new one every day.
enum PrepDateRange {
  months3('Last 3 months', 3),
  year('Last 12 months', 12),
  years3('Last 3 years', 36),
  all('All time', null);

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
  });

  final Set<PrepTimeControl> timeControls;
  final PrepDateRange range;

  bool get isFiltered => timeControls.isNotEmpty || range != PrepDateRange.all;

  int? fromMs(DateTime now) => range.fromDate(now)?.millisecondsSinceEpoch;

  /// A stable key for the selection the server will see this month.
  String scopeKey(DateTime now) {
    final clocks = PrepTimeControl.values
        .where(timeControls.contains)
        .map((t) => t.name)
        .join(',');
    return '${clocks.isEmpty ? 'all' : clocks}|${fromMs(now) ?? 'all'}';
  }

  String describe(PrepSource? source) {
    final clocks = timeControls.isEmpty
        ? 'All time controls'
        : PrepTimeControl.values
              .where(timeControls.contains)
              .map((t) => t.labelFor(source))
              .join(', ');
    return '$clocks · ${range.label}';
  }

  PrepDownloadPreferences copyWith({
    Set<PrepTimeControl>? timeControls,
    PrepDateRange? range,
  }) => PrepDownloadPreferences(
    timeControls: timeControls ?? this.timeControls,
    range: range ?? this.range,
  );

  Map<String, Object?> toJson() => {
    'timeControls': PrepTimeControl.values
        .where(timeControls.contains)
        .map((t) => t.name)
        .toList(),
    'range': range.name,
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
    );
  }

  @override
  bool operator ==(Object other) =>
      other is PrepDownloadPreferences &&
      setEquals(other.timeControls, timeControls) &&
      other.range == range;

  @override
  int get hashCode => Object.hash(Object.hashAllUnordered(timeControls), range);
}

/// One Lichess or Chess.com account inside a profile.
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
  });

  final PrepSource source;
  final String username;
  final String? displayName;
  final String? avatarUrl;
  final String? title;
  final String? country;

  /// Rating per provider category name (`blitz`, `rapid`, `bullet`, ...).
  final Map<String, int> ratings;
  final PrepDownloadPreferences preferences;
  final int? lastSyncAtMs;

  /// [PrepDownloadPreferences.scopeKey] the stored games were downloaded
  /// with. A different current scope replaces them instead of merging.
  final String? syncedScope;
  final int gameCount;
  final String? error;

  /// Case-insensitive identity, since both providers treat names that way.
  String get key => '${source.name}:${username.toLowerCase()}';

  String get profileUrl => source.profileUrl(username);

  int? get bestRating {
    for (final key in const ['blitz', 'rapid', 'bullet', 'classical']) {
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
  }) => PrepAccount(
    source: source,
    username: username,
    displayName: displayName ?? this.displayName,
    avatarUrl: avatarUrl ?? this.avatarUrl,
    title: title ?? this.title,
    country: country ?? this.country,
    ratings: ratings ?? this.ratings,
    preferences: preferences ?? this.preferences,
    lastSyncAtMs: lastSyncAtMs ?? this.lastSyncAtMs,
    syncedScope: syncedScope ?? this.syncedScope,
    gameCount: gameCount ?? this.gameCount,
    error: clearError ? null : (error ?? this.error),
  );

  Map<String, Object?> toJson() => {
    'source': source.name,
    'username': username,
    'displayName': displayName,
    'avatarUrl': avatarUrl,
    'title': title,
    'country': country,
    'ratings': ratings,
    'preferences': preferences.toJson(),
    'lastSyncAtMs': lastSyncAtMs,
    'syncedScope': syncedScope,
    'gameCount': gameCount,
    'error': error,
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
      ratings: ratings,
      preferences: PrepDownloadPreferences.fromJson(raw['preferences']),
      lastSyncAtMs: raw['lastSyncAtMs'] is int
          ? raw['lastSyncAtMs'] as int
          : null,
      syncedScope: _text(raw['syncedScope']),
      gameCount: raw['gameCount'] is int ? raw['gameCount'] as int : 0,
      error: _text(raw['error']),
    );
  }
}

/// A person being prepared: the user themself (My games) or an opponent,
/// with one or more online accounts whose games are read together.
@immutable
class PrepProfile {
  const PrepProfile({
    required this.id,
    required this.kind,
    required this.name,
    required this.createdAtMs,
    this.accounts = const [],
    this.favoriteId,
  });

  final String id;
  final PrepKind kind;
  final String name;
  final int createdAtMs;
  final List<PrepAccount> accounts;

  /// Set when the profile was added from Favorites.
  final String? favoriteId;

  String? get title {
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

  /// Usernames that identify this person in a game's White/Black tags.
  Set<String> get aliases => {
    for (final a in accounts) a.username.toLowerCase(),
  };

  PrepProfile copyWith({
    String? name,
    List<PrepAccount>? accounts,
    PrepKind? kind,
  }) => PrepProfile(
    id: id,
    kind: kind ?? this.kind,
    name: name ?? this.name,
    createdAtMs: createdAtMs,
    accounts: accounts ?? this.accounts,
    favoriteId: favoriteId,
  );

  PrepProfile replaceAccount(PrepAccount account) => copyWith(
    accounts: [
      for (final a in accounts) a.key == account.key ? account : a,
    ],
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'kind': kind.name,
    'name': name,
    'createdAtMs': createdAtMs,
    'accounts': [for (final a in accounts) a.toJson()],
    'favoriteId': favoriteId,
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
      createdAtMs: raw['createdAtMs'] is int ? raw['createdAtMs'] as int : 0,
      accounts: [
        if (rawAccounts is List)
          for (final a in rawAccounts) ?PrepAccount.fromJson(a),
      ],
      favoriteId: _text(raw['favoriteId']),
    );
  }
}

String? _text(Object? raw) {
  final text = raw?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}
