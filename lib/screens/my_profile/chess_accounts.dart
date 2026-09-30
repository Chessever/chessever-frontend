import 'dart:convert';

import 'package:chessever2/providers/auth_state_provider.dart';
import 'package:chessever2/repository/authentication/model/app_user.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

/// A chess site whose username can be linked on My Profile.
enum ChessSite {
  lichess(
    label: 'Lichess',
    metadataKey: kLichessUsernameMetadataKey,
    profilePrefix: 'lichess.org/@/',
    minLength: 2,
    maxLength: 30,
  ),
  chesscom(
    label: 'Chess.com',
    metadataKey: kChesscomUsernameMetadataKey,
    profilePrefix: 'chess.com/member/',
    minLength: 3,
    maxLength: 25,
  );

  const ChessSite({
    required this.label,
    required this.metadataKey,
    required this.profilePrefix,
    required this.minLength,
    required this.maxLength,
  });

  final String label;

  /// The auth `user_metadata` key the username is stored under.
  final String metadataKey;

  /// The public profile address minus the username, as the field shows it.
  final String profilePrefix;

  final int minLength;
  final int maxLength;

  /// The public profile page, for the "View on …" link.
  Uri profileUrl(String username) => switch (this) {
    ChessSite.lichess => Uri.https('lichess.org', '/@/$username'),
    ChessSite.chesscom => Uri.https('www.chess.com', '/member/$username'),
  };

  /// The public API endpoint that answers whether [username] exists.
  Uri lookupUrl(String username) => switch (this) {
    ChessSite.lichess => Uri.https('lichess.org', '/api/user/$username'),
    // Chess.com's published data API is keyed on the lowercase name.
    ChessSite.chesscom => Uri.https(
      'api.chess.com',
      '/pub/player/${username.toLowerCase()}',
    ),
  };
}

/// Per-site access to a [LinkedChessAccounts] record.
extension LinkedChessAccountsSite on LinkedChessAccounts {
  String? of(ChessSite site) => switch (site) {
    ChessSite.lichess => lichess,
    ChessSite.chesscom => chesscom,
  };

  LinkedChessAccounts withSite(ChessSite site, String? username) =>
      switch (site) {
        ChessSite.lichess => (lichess: username, chesscom: chesscom),
        ChessSite.chesscom => (lichess: lichess, chesscom: username),
      };
}

final RegExp _usernameCharacters = RegExp(r'^[A-Za-z0-9_-]+$');

/// What the user typed, reduced to a bare username: trimmed, a leading `@`
/// dropped, and a pasted profile address (`https://lichess.org/@/Name/all`,
/// `chess.com/member/name?ref=x`) cut down to the name in it.
String normalizeChessUsername(String raw) {
  var value = raw.trim();
  if (value.contains('/')) {
    final path = value.split(RegExp(r'[?#]')).first;
    final segments = path
        .split('/')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    // Both sites put the name right after `@` or `member`; anything else
    // pasted is read as its last segment.
    final marker = segments.indexWhere((s) => s == '@' || s == 'member');
    if (marker >= 0 && marker + 1 < segments.length) {
      value = segments[marker + 1];
    } else {
      value = segments.isEmpty ? '' : segments.last;
    }
  }
  if (value.startsWith('@')) value = value.substring(1);
  return value;
}

/// The format error for [username] on [site], or null when it is valid.
/// An empty username is valid: it means "not linked".
String? validateChessUsername(ChessSite site, String username) {
  if (username.isEmpty) return null;
  if (!_usernameCharacters.hasMatch(username)) {
    return 'Use letters, numbers, - and _ only';
  }
  if (username.length < site.minLength || username.length > site.maxLength) {
    return '${site.label} usernames are ${site.minLength} to '
        '${site.maxLength} characters';
  }
  return null;
}

/// How a one-off existence check came back.
enum UsernameLookupStatus {
  /// The site knows this player.
  found,

  /// The site answered that nobody has this name.
  notFound,

  /// The account exists but was closed.
  closed,

  /// No answer we can trust: offline, timed out, rate limited, a server error.
  unreachable,
}

@immutable
class UsernameLookup {
  const UsernameLookup(this.status, {this.canonicalUsername});

  final UsernameLookupStatus status;

  /// The site's own spelling of the name (Lichess keeps case), when found.
  final String? canonicalUsername;
}

/// Checks linked usernames against the sites' public APIs and stores them in
/// auth `user_metadata`. Both happen on Save only, one request per changed
/// name, never in a loop.
class ChessAccountsService {
  ChessAccountsService({
    this.client,
    Future<User?> Function(Map<String, dynamic> data)? writeMetadata,
    this.timeout = const Duration(seconds: 6),
  }) : _writeMetadata = writeMetadata ?? _supabaseWriteMetadata;

  /// The HTTP client for existence checks; a fresh one per check when null.
  final http.Client? client;
  final Future<User?> Function(Map<String, dynamic> data) _writeMetadata;
  final Duration timeout;

  static Future<User?> _supabaseWriteMetadata(Map<String, dynamic> data) async {
    final response = await Supabase.instance.client.auth.updateUser(
      UserAttributes(data: data),
    );
    return response.user;
  }

  /// One request to [site]'s public profile endpoint. Never throws: anything
  /// short of a clear answer is [UsernameLookupStatus.unreachable], which the
  /// screen treats as "could not confirm", not as "wrong".
  Future<UsernameLookup> lookup(ChessSite site, String username) async {
    final requests = client ?? http.Client();
    try {
      final response = await requests
          .get(
            site.lookupUrl(username),
            headers: const {
              'Accept': 'application/json',
              'User-Agent': 'ChessEver (+https://chessever.com)',
            },
          )
          .timeout(timeout);
      return _parse(site, username, response);
    } catch (_) {
      return const UsernameLookup(UsernameLookupStatus.unreachable);
    } finally {
      if (client == null) requests.close();
    }
  }

  static UsernameLookup _parse(
    ChessSite site,
    String username,
    http.Response response,
  ) {
    final code = response.statusCode;
    if (code == 404 || code == 410) {
      return const UsernameLookup(UsernameLookupStatus.notFound);
    }
    if (code != 200) {
      return const UsernameLookup(UsernameLookupStatus.unreachable);
    }
    Object? body;
    try {
      body = jsonDecode(response.body);
    } catch (_) {
      body = null;
    }
    if (body is! Map) {
      // A 200 that is not a profile (a captive portal, a proxy page) proves
      // nothing either way.
      return const UsernameLookup(UsernameLookupStatus.unreachable);
    }
    switch (site) {
      case ChessSite.lichess:
        if (body['disabled'] == true) {
          return const UsernameLookup(UsernameLookupStatus.closed);
        }
        final name = body['username'];
        return UsernameLookup(
          UsernameLookupStatus.found,
          canonicalUsername:
              name is String && name.toLowerCase() == username.toLowerCase()
              ? name
              : null,
        );
      case ChessSite.chesscom:
        final status = body['status'];
        if (status is String && status.startsWith('closed')) {
          return const UsernameLookup(UsernameLookupStatus.closed);
        }
        return const UsernameLookup(UsernameLookupStatus.found);
    }
  }

  /// Writes the usernames of [sites] (the ones the user changed) to auth
  /// `user_metadata`. The server merges keys, so `full_name` and the rest stay
  /// as they are; a null value removes the key. Returns what the server now
  /// holds.
  ///
  /// Only [sites] are sent, never the whole record: the rest of [accounts]
  /// comes from the locally cached session, which can be up to a token
  /// refresh stale. Sending an untouched site would overwrite, or with a null
  /// delete, a link another device made in the meantime.
  Future<LinkedChessAccounts> save(
    LinkedChessAccounts accounts, {
    required Iterable<ChessSite> sites,
  }) async {
    final changed = sites.toSet();
    if (changed.isEmpty) return accounts;
    final user = await _writeMetadata({
      for (final site in changed) site.metadataKey: accounts.of(site),
    });
    if (user == null) return accounts;
    return (
      lichess: AppUser.metadataUsername(
        user.userMetadata,
        ChessSite.lichess.metadataKey,
      ),
      chesscom: AppUser.metadataUsername(
        user.userMetadata,
        ChessSite.chesscom.metadataKey,
      ),
    );
  }
}

final chessAccountsServiceProvider = Provider<ChessAccountsService>(
  (ref) => ChessAccountsService(),
);
