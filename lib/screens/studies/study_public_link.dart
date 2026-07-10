import 'package:flutter/foundation.dart';

const String kStudyPublicHost = 'chessever.com';
const String kStudyCustomScheme = 'com.chessever.app';

final RegExp _studyIdPattern = RegExp(r'^[A-Za-z0-9]{8}$');
final RegExp _chapterIdPattern = RegExp(r'^[A-Za-z0-9]{1,64}$');
final RegExp _contentVersionPattern = RegExp(r'^sha256:[0-9a-f]{64}$');
final RegExp _plyPattern = RegExp(r'^[0-9]+$');

/// A public, non-sensitive pointer to a canonical ChessEver Study context.
///
/// This model intentionally carries only source identifiers and immutable
/// publication context. It never contains account, entitlement, bookmark, or
/// mirrored PGN data.
@immutable
class StudyPublicLink {
  StudyPublicLink({
    required String studyId,
    String? chapterId,
    int? ply,
    String? contentVersion,
  }) : studyId = _requireStudyId(studyId),
       chapterId = _optionalChapterId(chapterId),
       ply = _optionalPly(ply, chapterId),
       contentVersion = _optionalContentVersion(contentVersion);

  final String studyId;
  final String? chapterId;
  final int? ply;
  final String? contentVersion;

  Uri get uri => Uri(
    scheme: 'https',
    host: kStudyPublicHost,
    pathSegments: <String>[
      'studies',
      studyId,
      if (chapterId != null) ...<String>['chapters', chapterId!],
    ],
    queryParameters:
        ply == null && contentVersion == null
            ? null
            : <String, String>{
              if (ply != null) 'ply': '$ply',
              if (contentVersion != null) 'v': contentVersion!,
            },
  );

  /// Parses production universal links and the registered app-scheme shape.
  /// Returns null for every unsupported or ambiguous input.
  static StudyPublicLink? tryParse(Uri uri) {
    if (uri.hasFragment ||
        uri.userInfo.isNotEmpty ||
        uri.authority != uri.host ||
        !_hasOnlyAllowedQueryKeys(uri) ||
        uri.queryParametersAll.values.any((values) => values.length != 1)) {
      return null;
    }

    final List<String> routeSegments;
    if (uri.scheme == 'https' && uri.host == kStudyPublicHost) {
      routeSegments = uri.pathSegments;
    } else if (uri.scheme == kStudyCustomScheme && uri.host == 'studies') {
      routeSegments = <String>['studies', ...uri.pathSegments];
    } else {
      return null;
    }

    if (routeSegments.length != 2 && routeSegments.length != 4) return null;
    if (routeSegments.first != 'studies') return null;
    if (routeSegments.length == 4 && routeSegments[2] != 'chapters') {
      return null;
    }

    final studyId = routeSegments[1];
    final chapterId = routeSegments.length == 4 ? routeSegments[3] : null;
    if (!_studyIdPattern.hasMatch(studyId) ||
        (chapterId != null && !_chapterIdPattern.hasMatch(chapterId))) {
      return null;
    }

    final rawPly = uri.queryParameters['ply'];
    final rawVersion = uri.queryParameters['v'];
    if (rawPly != null &&
        (chapterId == null || !_plyPattern.hasMatch(rawPly))) {
      return null;
    }
    final ply = rawPly == null ? null : int.tryParse(rawPly);
    if (rawPly != null && ply == null) return null;
    if (rawVersion != null && !_contentVersionPattern.hasMatch(rawVersion)) {
      return null;
    }

    try {
      return StudyPublicLink(
        studyId: studyId,
        chapterId: chapterId,
        ply: ply,
        contentVersion: rawVersion,
      );
    } on ArgumentError {
      return null;
    }
  }

  StudyPublicLink copyWith({
    String? chapterId,
    int? ply,
    String? contentVersion,
    bool clearChapter = false,
    bool clearPly = false,
    bool clearContentVersion = false,
  }) {
    return StudyPublicLink(
      studyId: studyId,
      chapterId: clearChapter ? null : chapterId ?? this.chapterId,
      ply: clearPly ? null : ply ?? this.ply,
      contentVersion:
          clearContentVersion ? null : contentVersion ?? this.contentVersion,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is StudyPublicLink &&
        other.studyId == studyId &&
        other.chapterId == chapterId &&
        other.ply == ply &&
        other.contentVersion == contentVersion;
  }

  @override
  int get hashCode => Object.hash(studyId, chapterId, ply, contentVersion);

  @override
  String toString() => uri.toString();
}

String studyShareText({
  required StudyPublicLink link,
  required String title,
  String? chapterName,
}) {
  final normalizedTitle = title.trim();
  final normalizedChapter = chapterName?.trim();
  final label =
      normalizedChapter == null || normalizedChapter.isEmpty
          ? normalizedTitle
          : '$normalizedTitle — $normalizedChapter';
  return '$label\nSource: Lichess · Shared via ChessEver\n${link.uri}';
}

bool _hasOnlyAllowedQueryKeys(Uri uri) {
  return uri.queryParametersAll.keys.every(const <String>{'ply', 'v'}.contains);
}

String _requireStudyId(String value) {
  if (!_studyIdPattern.hasMatch(value)) {
    throw ArgumentError.value(value, 'studyId', 'Invalid Lichess Study ID.');
  }
  return value;
}

String? _optionalChapterId(String? value) {
  if (value == null) return null;
  if (!_chapterIdPattern.hasMatch(value)) {
    throw ArgumentError.value(
      value,
      'chapterId',
      'Invalid Lichess chapter ID.',
    );
  }
  return value;
}

int? _optionalPly(int? value, String? chapterId) {
  if (value == null) return null;
  if (value < 0 || chapterId == null) {
    throw ArgumentError.value(
      value,
      'ply',
      'Ply must be nonnegative and scoped to a chapter.',
    );
  }
  return value;
}

String? _optionalContentVersion(String? value) {
  if (value == null) return null;
  if (!_contentVersionPattern.hasMatch(value)) {
    throw ArgumentError.value(
      value,
      'contentVersion',
      'Expected a canonical lowercase SHA-256 version.',
    );
  }
  return value;
}
